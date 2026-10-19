import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import readline from "node:readline";
import { attachmentsPrompt, changeAttachmentsNote } from "./attachments.ts";
import { failStage, reportStage, startStage } from "./board.ts";
import { getTicket, log, STAGE_FILES, WORK_DIR } from "./store.ts";
import { listSystems, MCP_ALIAS, resolveSystem, writeMcpConfig } from "./systems.ts";
import { TEAM, WORK_STAGES } from "./types.ts";
import type { LeadReview, WorkStage } from "./types.ts";

// 팀장이 웹에서 승인·수정 지시를 내리면 Claude Code를 헤드리스(claude -p)로 띄워 현재 단계를 작업시킨다.
// Claude Code 구독으로 동작하므로 API 키는 자식 프로세스에 넘기지 않는다.

const TIMEOUT_MS = Number(process.env.CLAUDE_TIMEOUT_MIN || 40) * 60_000;
const running = new Map<string, { cancel: () => void }>();

export function isWorking(id: string): boolean {
  return running.has(id);
}

// claude.exe가 띄운 MCP 서버 등 자식 프로세스까지 함께 종료한다
function killTree(child: ReturnType<typeof spawn>): void {
  if (process.platform === "win32" && child.pid) spawn("taskkill", ["/pid", String(child.pid), "/T", "/F"], { windowsHide: true });
  else child.kill();
}

/** 작업 중인 Claude Code를 중단한다. 결과는 보드에 반영하지 않는다. */
export function stopRun(id: string): boolean {
  const r = running.get(id);
  if (!r) return false;
  r.cancel();
  return true;
}

function claudeBin(): string {
  if (process.env.CLAUDE_BIN) return process.env.CLAUDE_BIN;
  const exe = path.join(process.env.APPDATA ?? "", "npm", "node_modules", "@anthropic-ai", "claude-code", "bin", "claude.exe");
  return fs.existsSync(exe) ? exe : "claude";
}

const REVIEW_SCHEMA = {
  type: "object",
  properties: {
    decision: { type: "string", enum: ["approve", "revise"], description: "팀장에게 드리는 권고" },
    summary: { type: "string", description: "팀장 보고 2~4문장. 수정 지시 재작업이면 반영 내용 포함" },
    feedback: { type: "string", description: "revise 권고일 때 수정 지시 초안, 아니면 빈 문자열" },
    send_back_to: { type: "string", enum: WORK_STAGES, description: "revise 권고일 때 다시 작업할 단계" },
  },
  required: ["decision", "summary", "feedback", "send_back_to"],
};

/** 프롬프트에 넣을 조회 대상 SAP 시스템 안내 */
export function sapSystemNote(system?: string | null): string {
  const name = resolveSystem(system);
  const s = listSystems().find((x) => x.name === name);
  return s
    ? `조회 대상 SAP 시스템: ${s.name} (${s.url}, 클라이언트 ${s.client}) — ${MCP_ALIAS} MCP 도구(mcp__${MCP_ALIAS}__*)로 조회합니다. 서브에이전트에게도 이 시스템 기준임을 알려 주세요.`
    : `SAP 시스템이 연결되어 있지 않아 SAP 조회 도구를 쓸 수 없습니다. 확인이 필요한 시스템 정보는 '확인 필요'로 남기게 하세요.`;
}

function buildPrompt(id: string, stage: WorkStage): string {
  const t = getTicket(id)!;
  const st = t.stages[stage];
  const applied = (t.changes ?? []).filter((c) => c.status === "applied");
  const outputs: Record<WorkStage, string> = {
    analysis: "01_analysis.md",
    design: "02_design.md",
    development: "src/<오브젝트명>.abap 과 03_development.md",
    test: "04_test.md 와 src/<클래스명>.testclasses.abap",
  };
  return [
    `당신은 SAP 개발팀 PL입니다. 웹 보드에서 팀장이 지시한 작업을 처리합니다. (이 세션에서는 CLAUDE.md의 "진행해" 절차와 src/cli.ts를 쓰지 않습니다. 보드 기록은 서버가 합니다.)`,
    ``,
    `요청: ${t.title} (ID ${t.id})`,
    `작업 폴더: work/${t.id}/  (request.md = 현업 요청, ticket.json은 절대 수정 금지)`,
    sapSystemNote(t.system),
    attachmentsPrompt(t.id) && `${attachmentsPrompt(t.id)}\n(서브에이전트에게 이 첨부 경로들을 그대로 전달하세요)`,
    `이번 단계: ${TEAM[stage].name} → 서브에이전트 ${TEAM[stage].agent} 를 Agent 도구로 실행하세요. 산출물: ${outputs[stage]}`,
    st.directive
      ? `\n팀장 수정 지시 (반드시 반영): ${st.directive}\n기존 산출물을 지시에 맞게 고치게 하세요.${
          st.directives.length > 1 ? `\n이전 지시 이력: ${st.directives.slice(0, -1).map((d) => d.text).join(" / ")}` : ""
        }`
      : STAGE_FILES[stage].docs.some((d) => fs.existsSync(path.join(WORK_DIR, t.id, d)))
        ? `\n이전 단계가 바뀌었을 수 있으니 기존 산출물을 최신 이전 단계 산출물에 맞게 갱신하게 하세요.`
        : "",
    applied.length
      ? `\n반영된 요구사항 변경 (원문 request.md에 더해 현재 요구사항 기준선입니다. 산출물이 이와 어긋나지 않게 하세요): ${applied.map((c) => `${c.id} ${c.text}${changeAttachmentsNote(t.id, c.id)}`).join(" / ")}`
      : "",
    ``,
    `순서:`,
    `1. 서브에이전트에게 작업 폴더, 산출물 파일, 첨부 자료(있으면), 팀장 수정 지시(있으면)를 정확히 전달해 작업시킵니다.`,
    `2. 산출물을 직접 읽어 1차 검토합니다: 요청·이전 단계와 부합하는지, 팀장 지시가 반영됐는지, 다음 단계가 작업 가능한지.`,
    `3. 이 단계만 하고 멈춥니다. 다음 단계 작업, SAP 시스템 쓰기는 하지 않습니다. revise 권고여도 직접 재작업하지 말고 보고만 합니다.`,
    `4. 검토 결과를 구조화된 출력(decision, summary, feedback, send_back_to)으로 팀장에게 보고합니다. summary는 비개발자도 이해할 수 있게 한국어로.`,
  ].join("\n");
}

export interface ClaudeJob<T> {
  prompt: string;
  permissionMode?: string; // 기본 acceptEdits. 경로 제한 규칙(Edit(wiki/**))을 쓰려면 default
  schema: object;
  tools: string[];
  system?: string | null; // 붙일 SAP 시스템 (MCP 서버). 생략하면 SAP 조회 도구 없이 실행
  onTool: (tool: { name: string; input: any }) => void;
  onDone: (output: T | null, error: string | null) => void;
}

/** Claude Code를 헤드리스로 실행하고 구조화된 출력을 돌려준다. 반환값은 중단 함수. */
export function spawnClaude<T>(job: ClaudeJob<T>): () => void {
  const env = { ...process.env };
  delete env.ANTHROPIC_API_KEY;
  delete env.ANTHROPIC_AUTH_TOKEN;
  // 보드에서 고른 SAP 시스템의 MCP 서버만 'sap' 이름으로 붙인다 (다른 MCP 서버는 띄우지 않음)
  const mcp = job.system !== undefined ? writeMcpConfig(job.system) : null;
  const args = [
    "-p",
    "--output-format", "stream-json",
    "--verbose",
    "--json-schema", JSON.stringify(job.schema),
    "--permission-mode", job.permissionMode ?? "acceptEdits",
    "--strict-mcp-config",
    ...(mcp ? ["--mcp-config", mcp.file] : []),
    "--allowedTools", ...job.tools,
  ];
  const child = spawn(claudeBin(), args, { cwd: process.cwd(), env, stdio: ["pipe", "pipe", "pipe"], windowsHide: true });
  child.stdin!.end(job.prompt);

  let output: T | null = null;
  let error = "";
  let stderr = "";
  let finished = false;
  const timer = setTimeout(() => {
    error = `시간 초과 (${TIMEOUT_MS / 60_000}분)`;
    killTree(child);
  }, TIMEOUT_MS);

  readline.createInterface({ input: child.stdout! }).on("line", (line) => {
    if (finished) return;
    let m: any;
    try {
      m = JSON.parse(line);
    } catch {
      return;
    }
    if (m.type === "assistant") {
      for (const c of m.message?.content ?? []) {
        if (c.type !== "tool_use") continue;
        if (c.name === "StructuredOutput") output = c.input;
        else job.onTool(c);
      }
    } else if (m.type === "result") {
      if (m.structured_output) output = m.structured_output;
      if (m.is_error || m.subtype !== "success") error ||= String(m.result || m.subtype || "실패");
    }
  });
  child.stderr!.on("data", (d) => (stderr += d).length > 4000 && (stderr = stderr.slice(-4000)));

  child.on("close", () => mcp?.cleanup());
  const finish = (code: number | null, spawnErr?: Error) => {
    if (finished) return;
    finished = true;
    clearTimeout(timer);
    try {
      if (output && !error) job.onDone(output, null);
      else job.onDone(null, spawnErr?.message || error || stderr.trim().split("\n").slice(-3).join(" ") || `Claude Code 종료 코드 ${code}`);
    } catch (e) {
      console.error(e);
    }
  };
  child.on("error", (e) => finish(null, e));
  child.on("close", (code) => finish(code));
  return () => {
    finished = true;
    clearTimeout(timer);
    killTree(child);
  };
}

export function runStage(id: string): void {
  if (running.has(id)) throw new Error("이미 작업 중입니다.");
  const t = startStage(id);
  const stage = t.currentStage as WorkStage;
  log(t, TEAM.lead.name, `${TEAM[stage].agent} 에이전트에게 작업을 지시했습니다.`);
  const note = (text: string) => {
    const cur = getTicket(id);
    if (cur) log(cur, TEAM[stage].name, text);
  };
  const cancel = spawnClaude<LeadReview>({
    prompt: buildPrompt(id, stage),
    schema: REVIEW_SCHEMA,
    tools: ["Agent", "Task", "Read", "Write", "Edit", "Glob", "Grep", `mcp__${MCP_ALIAS}`],
    system: t.system ?? null,
    onTool: (c) => {
      if (c.name === "Write" || c.name === "Edit") note(`✏️ ${path.relative(path.join(WORK_DIR, id), c.input?.file_path ?? "").replaceAll("\\", "/")} ${c.name === "Write" ? "작성" : "수정"}`);
      else if (c.name?.startsWith(`mcp__${MCP_ALIAS}__`)) note(`🔎 SAP 조회: ${c.name.replace(`mcp__${MCP_ALIAS}__`, "")} ${Object.values(c.input ?? {}).join(" ").slice(0, 60)}`);
    },
    onDone: (review, error) => {
      running.delete(id);
      if (review) reportStage(id, review);
      else failStage(id, error!);
    },
  });
  running.set(id, {
    cancel: () => {
      running.delete(id);
      cancel();
    },
  });
}

// 서버 재시작으로 끊긴 작업은 실패로 표시해 웹에서 다시 시작할 수 있게 한다
export function recoverStale(): void {
  for (const id of fs.readdirSync(WORK_DIR)) {
    const t = getTicket(id);
    if (t?.status === "in_progress" && t.stages[t.currentStage].status === "running")
      failStage(id, "서버 재시작으로 작업이 중단되었습니다. 다시 시작해 주세요.");
  }
}
