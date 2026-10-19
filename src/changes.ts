import fs from "node:fs";
import path from "node:path";
import { attachmentsPrompt, changeAttachmentsNote } from "./attachments.ts";
import { revise } from "./board.ts";
import { isWorking, runStage, spawnClaude, stopRun } from "./runner.ts";
import { getTicket, log, saveTicket, STAGE_FILES, WORK_DIR } from "./store.ts";
import { TEAM, WORK_STAGES } from "./types.ts";
import type { ChangeImpact, ChangeRequest, Ticket, WorkStage } from "./types.ts";

// 진행 중 요구사항 변경(CR). 팀장이 언제든 등록하면 PL(읽기 전용 헤드리스 세션)이 영향받는 가장 앞 단계를 분석해 권고하고,
// 팀장이 반영·다음 차수로 미루기·반려를 정한다. 반영은 기존 수정 지시(revise) 흐름을 그대로 쓴다.

const EFFORT = { small: "작음", medium: "보통", large: "큼" } as const;

const SCHEMA = {
  type: "object",
  properties: {
    from: { type: "string", enum: WORK_STAGES, description: "이 변경으로 고쳐야 하는 가장 앞 단계" },
    effort: { type: "string", enum: ["small", "medium", "large"], description: "재작업 규모" },
    summary: { type: "string", description: "팀장 보고 2~3문장. 무엇이 바뀌고 어떤 산출물·오브젝트에 영향이 있는지, 기존 요구사항과 충돌하는지" },
    directive: { type: "string", description: "from 단계 담당자에게 줄 구체적인 수정 지시 초안" },
  },
  required: ["from", "effort", "summary", "directive"],
};

function mustGet(id: string): Ticket {
  const t = getTicket(id);
  if (!t) throw new Error("요청을 찾을 수 없습니다.");
  t.changes ??= [];
  return t;
}

function mustGetChange(t: Ticket, cid: string): ChangeRequest {
  const c = t.changes!.find((x) => x.id === cid);
  if (!c) throw new Error(`${cid}를 찾을 수 없습니다.`);
  return c;
}

function appliedChanges(t: Ticket): ChangeRequest[] {
  return (t.changes ?? []).filter((c) => c.status === "applied");
}

function buildPrompt(t: Ticket, c: ChangeRequest): string {
  const dir = path.join(WORK_DIR, t.id);
  const docs = WORK_STAGES.flatMap((s) => STAGE_FILES[s].docs.filter((d) => fs.existsSync(path.join(dir, d))).map((d) => `${d} (${TEAM[s].name})`));
  const stageInfo = WORK_STAGES.map((s) => `${s}(${TEAM[s].name}): ${t.stages[s].status}`).join(", ");
  const applied = appliedChanges(t);
  return [
    `당신은 SAP 개발팀 PL입니다. 진행 중인 개발 요청에 팀장이 요구사항 변경(${c.id})을 등록했습니다. 영향을 분석해 팀장에게 권고합니다.`,
    `(이 세션은 읽기 전용입니다. 파일을 고치거나 서브에이전트를 실행하지 말고, CLAUDE.md의 "진행해" 절차와 src/cli.ts도 쓰지 않습니다.)`,
    ``,
    `요청: ${t.title} (ID ${t.id}), 작업 폴더 work/${t.id}/`,
    `현업 요청 원문: request.md`,
    attachmentsPrompt(t.id),
    `작성된 산출물: ${docs.length ? docs.join(", ") : "(아직 없음)"}${fs.existsSync(path.join(dir, "src")) ? ", src/*.abap" : ""}`,
    `단계 상태: ${stageInfo} / 현재 단계 ${t.currentStage}, 요청 상태 ${t.status}`,
    applied.length ? `이미 반영된 변경: ${applied.map((a) => `${a.id} "${a.text}"${changeAttachmentsNote(t.id, a.id)}`).join(" / ")}` : "",
    ``,
    `새 변경 요청 ${c.id}: ${c.text}${changeAttachmentsNote(t.id, c.id)}`,
    ``,
    `할 일:`,
    `1. 원문과 산출물을 읽고 이 변경이 어느 산출물의 어느 부분을 바꾸게 하는지 확인합니다.`,
    `2. from = 고쳐야 하는 가장 앞 단계. 요구사항(기능·조회조건·출력항목·판정기준) 자체가 바뀌면 analysis, 요구사항은 그대로이고 오브젝트·로직 구조가 바뀌면 design, 화면 문구·코드 수준이면 development, 테스트만이면 test. 아직 작성되지 않은 단계여도 그 단계를 고르면 됩니다.`,
    `3. 기존 요구사항이나 이미 반영된 변경과 충돌하면 summary에 분명히 적습니다.`,
    `4. directive는 from 단계 담당자가 바로 작업할 수 있게 구체적으로 씁니다. 산출물 변경 이력에 "${c.id}"를 남기라는 지시를 포함합니다.`,
    `5. summary는 비개발자도 이해할 수 있게 한국어로 씁니다.`,
  ].filter((l) => l !== "").join("\n");
}

/**
 * hold: 첨부 자료를 올린 뒤 화면에서 reanalyze로 분석을 시작한다.
 * 업로드가 중간에 실패해도 '다시 분석' 버튼으로 이어갈 수 있게 분석 실패 상태로 둔다.
 */
export function addChange(id: string, text: string, hold = false): ChangeRequest {
  if (!text.trim() && !hold) throw new Error("변경 요청 내용을 입력하거나 자료를 첨부해 주세요.");
  const t = mustGet(id);
  const n = Math.max(0, ...t.changes!.map((c) => Number(c.id.slice(3)) || 0)) + 1;
  const c: ChangeRequest = { id: `CR-${String(n).padStart(2, "0")}`, at: new Date().toISOString(), text: text.trim() || "(첨부 자료 참고)", status: "analyzing", impact: null };
  t.changes!.push(c);
  if (hold) Object.assign(c, { status: "failed", error: "첨부 자료를 올리는 중입니다. 다 올라가면 영향분석을 시작합니다." });
  log(t, "팀장", `🔄 요구사항 변경 ${c.id} 등록 — ${c.text}`);
  if (!hold) analyze(id, c.id);
  return c;
}

function analyze(id: string, cid: string): void {
  const t = mustGet(id);
  const c = mustGetChange(t, cid);
  c.status = "analyzing";
  c.error = null;
  log(t, TEAM.lead.name, `${c.id} 영향을 분석합니다.`);
  spawnClaude<ChangeImpact>({
    prompt: buildPrompt(t, c),
    schema: SCHEMA,
    permissionMode: "default",
    tools: ["Read", "Glob", "Grep"],
    onTool: () => {},
    onDone: (impact, error) => {
      const cur = mustGet(id);
      const cc = mustGetChange(cur, cid);
      if (cc.status !== "analyzing") return; // 분석 중에 팀장이 이미 결정함
      if (!impact || !WORK_STAGES.includes(impact.from)) {
        cc.status = "failed";
        cc.error = error ?? "영향분석 결과가 올바르지 않습니다.";
        log(cur, TEAM.lead.name, `⚠️ ${cc.id} 영향분석 실패 — ${cc.error}`);
        return;
      }
      cc.impact = impact;
      cc.status = "proposed";
      log(cur, TEAM.lead.name, `📨 ${cc.id} 영향분석 — ${TEAM[impact.from].name}부터 수정 권고 (규모 ${EFFORT[impact.effort] ?? impact.effort}). ${impact.summary}`);
    },
  });
}

/** 팀장 결정: 다음 차수로 미루기 / 반려 / 다시 분석 / 다시 검토(미룬 것을 결정 대기로) */
export function decideChange(id: string, cid: string, action: string): void {
  const t = mustGet(id);
  const c = mustGetChange(t, cid);
  const now = new Date().toISOString();
  if (action === "defer" || action === "reject") {
    if (!["proposed", "failed", "analyzing"].includes(c.status)) throw new Error("결정 대기 중인 변경만 처리할 수 있습니다.");
    c.status = action === "defer" ? "deferred" : "rejected";
    c.decidedAt = now;
    log(t, "팀장", `${action === "defer" ? "⏭ 다음 차수로 미룸" : "✖ 반려"} — ${c.id} ${c.text}`);
  } else if (action === "reanalyze") {
    if (c.status === "applied") throw new Error("이미 반영한 변경입니다.");
    analyze(id, cid);
  } else if (action === "reopen") {
    if (c.status !== "deferred" && c.status !== "rejected") throw new Error("미루거나 반려한 변경만 다시 검토할 수 있습니다.");
    if (!c.impact) return analyze(id, cid);
    c.status = "proposed";
    c.decidedAt = null;
    log(t, "팀장", `↺ ${c.id} 다시 검토합니다.`);
  } else throw new Error("알 수 없는 처리입니다.");
}

/**
 * 선택한 CR을 한 번에 반영한다. 반영 단계는 팀장이 고른 단계(없으면 PL 권고) 중 가장 앞 단계.
 * - 이미 진행했거나 진행 중인 단계면 수정 지시로 그 단계부터 다시 작업한다 (작업 중이면 중단).
 * - 아직 오지 않은 단계면 그 단계에 지시를 걸어 두고, 차례가 되면 함께 반영한다.
 */
export function applyChanges(id: string, picks: { id: string; stage?: string }[]): void {
  if (!picks.length) throw new Error("반영할 변경 요청을 선택해 주세요.");
  const t = mustGet(id);
  const items = picks.map((p) => {
    const c = mustGetChange(t, p.id);
    if (c.status !== "proposed") throw new Error(`${c.id}는 반영할 수 있는 상태가 아닙니다.`);
    const stage = (WORK_STAGES.includes(p.stage as WorkStage) ? p.stage : c.impact!.from) as WorkStage;
    return { c, stage };
  });
  const target = WORK_STAGES[Math.min(...items.map((x) => WORK_STAGES.indexOf(x.stage)))];
  if (t.status === "deploying") throw new Error("개발계 반영 중에는 변경을 반영할 수 없습니다. 반영이 끝난 뒤 다시 시도해 주세요.");
  const text = items.map(({ c }) => `[${c.id}] 요구사항 변경: ${c.text}${changeAttachmentsNote(id, c.id)}\n→ ${c.impact!.directive}\n(산출물 변경 이력에 ${c.id}를 남겨 주세요)`).join("\n\n");

  const cur = t.status === "in_progress" || t.status === "awaiting_review" ? WORK_STAGES.indexOf(t.currentStage as WorkStage) : WORK_STAGES.length - 1;
  const future = WORK_STAGES.indexOf(target) > cur;

  const now = new Date().toISOString();
  for (const { c, stage } of items) Object.assign(c, { status: "applied", appliedTo: stage, decidedAt: now });
  const ids = items.map((x) => x.c.id).join(", ");

  if (future) {
    const st = t.stages[target];
    st.directive = st.directive ? `${st.directive}\n\n${text}` : text;
    st.directives.push({ at: now, text });
    log(t, "팀장", `✅ ${ids} 반영 — ${TEAM[target].name} 차례에 함께 반영합니다.`);
    return;
  }
  saveTicket(t);
  if (stopRun(id)) log(getTicket(id)!, "팀장", "⏹ 진행 중인 작업을 중단했습니다.");
  log(getTicket(id)!, "팀장", `✅ ${ids} 반영 — ${TEAM[target].name}부터 다시 작업합니다.`);
  revise(id, target, text);
  if (!isWorking(id)) runStage(id);
}

// 서버 재시작으로 끊긴 영향분석은 실패로 표시해 다시 분석할 수 있게 한다
export function recoverChanges(tickets: Ticket[]): void {
  for (const t of tickets) {
    const stale = (t.changes ?? []).filter((c) => c.status === "analyzing");
    if (!stale.length) continue;
    for (const c of stale) Object.assign(c, { status: "failed", error: "서버 재시작으로 영향분석이 중단되었습니다." });
    saveTicket(t);
  }
}
