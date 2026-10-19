import fs from "node:fs";
import path from "node:path";
import { attachmentsPrompt, changeAttachmentsNote } from "./attachments.ts";
import { sapSystemNote, spawnClaude } from "./runner.ts";
import { MCP_ALIAS } from "./systems.ts";
import { getTicket, log, saveTicket, STAGE_FILES, stageFiles, WORK_DIR } from "./store.ts";
import { TEAM, WORK_STAGES } from "./types.ts";
import type { Ticket, Verification, WorkStage } from "./types.ts";

// 팀장이 승인 전에 산출물 검증을 AI에게 맡긴다. 작업한 PL과 별개인 읽기 전용 헤드리스 세션이 검증하고,
// 결과는 단계 검증 이력에만 남는다. 승인·수정 지시는 여전히 팀장이 결정한다.

const AGENT = "AI 검증";
const VERDICT = { pass: "통과", warn: "주의", fail: "문제 있음" } as const;

const SCHEMA = {
  type: "object",
  properties: {
    verdict: { type: "string", enum: ["pass", "warn", "fail"], description: "pass=승인해도 됨, warn=승인 가능하나 확인 권장, fail=수정 필요" },
    summary: { type: "string", description: "팀장 보고 2~4문장. 비개발자도 이해할 수 있게" },
    checks: {
      type: "array",
      items: {
        type: "object",
        properties: {
          item: { type: "string", description: "검증 항목 (짧게)" },
          result: { type: "string", enum: ["ok", "warn", "issue"] },
          detail: { type: "string", description: "판단 근거. 파일명·절·요구사항 ID 등 위치를 포함" },
        },
        required: ["item", "result", "detail"],
      },
    },
    directive: { type: "string", description: "warn/fail이면 담당자에게 줄 구체적인 수정 지시 초안, pass면 빈 문자열" },
    send_back_to: { type: "string", enum: WORK_STAGES, description: "수정이 필요할 때 다시 작업할 단계. 원인이 앞 단계에 있으면 그 단계" },
  },
  required: ["verdict", "summary", "checks", "directive", "send_back_to"],
};

const FOCUS: Record<WorkStage, string[]> = {
  analysis: [
    "request.md와 첨부 자료의 요청 항목이 빠짐없이 기능 요구사항(FR)으로 옮겨졌는지 (첨부 화면 예시·양식의 항목 하나하나 대조)",
    "요청에 없는 기능을 임의로 추가하거나 요청을 다르게 해석하지 않았는지",
    "언급한 SAP 테이블·필드가 실제로 존재하는지 (SAP 조회로 확인)",
    "모호한 부분이 가정·현업 확인 필요 사항으로 드러나 있는지",
  ],
  design: [
    "01_analysis.md의 FR이 모두 설계 요소(오브젝트·로직·화면)에 매핑됐는지",
    "데이터 조회 경로·조인 키·필드가 실제 SAP 구조와 맞는지 (SAP 조회로 확인)",
    "개발표준(standards/handbook.md) 명명·구조 규칙 준수",
    "성능(대량 조회, 루프 안 SELECT)·권한 체크·예외 처리 설계",
  ],
  development: [
    "02_design.md 대비 구현 누락·불일치",
    "ABAP 문법·활성화 가능성 (선언 누락, 타입 불일치, 존재하지 않는 필드)",
    "개발표준 준수, 성능(루프 안 SELECT, FOR ALL ENTRIES 빈 테이블 체크), 권한 체크, 예외·메시지 처리",
    "사용한 테이블·필드·함수·클래스가 실제로 존재하는지 (SAP 조회로 확인)",
  ],
  test: [
    "테스트 시나리오가 모든 FR과 예외 경우를 다루는지",
    "pass/fail 판정이 실제 소스 근거와 맞는지 (테스트가 놓친 결함이 소스에 있는지 직접 확인)",
    "ABAP Unit이 의미 있는 검증을 하는지 (항상 통과하는 테스트, 외부 의존 미분리)",
  ],
};

function buildPrompt(t: Ticket, stage: WorkStage): string {
  const dir = path.join(WORK_DIR, t.id);
  const idx = WORK_STAGES.indexOf(stage);
  const prev = WORK_STAGES.slice(0, idx).flatMap((s) => STAGE_FILES[s].docs.filter((d) => fs.existsSync(path.join(dir, d))));
  const own = stageFiles(t.id, stage).map((f) => f.name);
  const st = t.stages[stage];
  const applied = (t.changes ?? []).filter((c) => c.status === "applied");
  const att = attachmentsPrompt(t.id);
  return [
    `당신은 SAP 개발팀의 독립 검증 담당입니다. 팀장이 ${TEAM[stage].name} 산출물을 승인하기 전에 검증을 맡겼습니다.`,
    `작업한 담당자·PL과 별개로, 산출물을 의심하는 관점에서 근거를 직접 확인해 판정하세요.`,
    `(이 세션은 읽기 전용입니다. 파일을 고치거나 서브에이전트를 실행하지 말고, CLAUDE.md의 "진행해" 절차와 src/cli.ts도 쓰지 않습니다. SAP 조회는 sap MCP 읽기 도구만 씁니다.)`,
    ``,
    `요청: ${t.title} (ID ${t.id}), 작업 폴더 work/${t.id}/`,
    sapSystemNote(t.system),
    `현업 요청 원문: work/${t.id}/request.md`,
    att,
    applied.length ? `반영된 요구사항 변경 (현재 요구사항 기준선): ${applied.map((c) => `${c.id} ${c.text}${changeAttachmentsNote(t.id, c.id)}`).join(" / ")}` : "",
    prev.length ? `이전 단계 산출물 (승인됨, 기준): ${prev.map((d) => `work/${t.id}/${d}`).join(", ")}` : "",
    `검증 대상 산출물: ${own.map((f) => `work/${t.id}/${f}`).join(", ")}`,
    `개발표준: standards/handbook.md (있으면)`,
    st.directives.length ? `팀장 수정 지시 이력 (반영됐는지도 확인): ${st.directives.map((d) => d.text).join(" / ")}` : "",
    ``,
    `중점 검증 항목:`,
    ...FOCUS[stage].map((f) => `- ${f}`),
    ``,
    `판정 규칙:`,
    `- checks에는 확인한 항목마다 결과를 적습니다 (5~12개). 통과한 항목도 무엇을 확인했는지 적습니다.`,
    `- 확인하지 못한 것은 통과로 적지 말고 warn으로 두고 이유를 적습니다. 추측으로 issue를 만들지 않습니다.`,
    `- issue가 하나라도 있으면 fail, warn만 있으면 warn, 모두 ok면 pass.`,
    `- summary와 detail은 한국어로, 비개발자도 이해할 수 있게 씁니다.`,
    `- 끝나면 결과를 구조화된 출력(verdict, summary, checks, directive, send_back_to)으로 돌려줍니다.`,
  ].filter((l) => l !== "").join("\n");
}

function mustGet(id: string): Ticket {
  const t = getTicket(id);
  if (!t) throw new Error("요청을 찾을 수 없습니다.");
  return t;
}

export function runVerify(id: string, stageArg: string): void {
  const t = mustGet(id);
  const stage = stageArg as WorkStage;
  if (!WORK_STAGES.includes(stage)) throw new Error("검증할 단계를 지정해 주세요.");
  const st = t.stages[stage];
  if (st.status === "running") throw new Error("작업 중인 단계는 검증할 수 없습니다. 보고가 올라온 뒤 다시 시도해 주세요.");
  if (st.verifications?.some((v) => v.status === "running")) throw new Error("이미 AI 검증 중입니다.");
  if (!stageFiles(id, stage).length) throw new Error("검증할 산출물이 없습니다.");

  const v: Verification = { at: new Date().toISOString(), attempt: st.attempts, status: "running" };
  (st.verifications ??= []).push(v);
  log(t, "팀장", `🤖 ${TEAM[stage].name} 산출물 AI 검증을 요청했습니다.`);

  spawnClaude<Required<Pick<Verification, "verdict" | "summary" | "checks" | "directive" | "send_back_to">>>({
    prompt: buildPrompt(t, stage),
    schema: SCHEMA,
    permissionMode: "default",
    tools: ["Read", "Glob", "Grep", `mcp__${MCP_ALIAS}`],
    system: t.system ?? null,
    onTool: () => {},
    onDone: (out, error) => {
      const cur = mustGet(id);
      const cv = cur.stages[stage].verifications?.find((x) => x.at === v.at);
      if (!cv) return;
      if (!out || !VERDICT[out.verdict]) {
        Object.assign(cv, { status: "failed", error: error ?? "검증 결과가 올바르지 않습니다." });
        log(cur, AGENT, `⚠️ ${TEAM[stage].name} 검증 실패 — ${cv.error}`);
        return;
      }
      const back = WORK_STAGES.indexOf(out.send_back_to) >= 0 && WORK_STAGES.indexOf(out.send_back_to) <= WORK_STAGES.indexOf(stage) ? out.send_back_to : stage;
      Object.assign(cv, { status: "done", verdict: out.verdict, summary: out.summary, checks: out.checks ?? [], directive: out.directive ?? "", send_back_to: back });
      const issues = cv.checks!.filter((c) => c.result !== "ok").length;
      log(cur, AGENT, `🤖 ${TEAM[stage].name} 검증 결과: ${VERDICT[out.verdict]}${issues ? ` (확인 필요 ${issues}건)` : ""} — ${out.summary}`);
    },
  });
}

// 서버 재시작으로 끊긴 검증은 실패로 표시해 다시 요청할 수 있게 한다
export function recoverVerifications(tickets: Ticket[]): void {
  for (const t of tickets) {
    let changed = false;
    for (const s of WORK_STAGES)
      for (const v of t.stages[s].verifications ?? [])
        if (v.status === "running") {
          Object.assign(v, { status: "failed", error: "서버 재시작으로 검증이 중단되었습니다." });
          changed = true;
        }
    if (changed) saveTicket(t);
  }
}
