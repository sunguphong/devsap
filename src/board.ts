import fs from "node:fs";
import path from "node:path";
import { AdtClient, objectUri } from "./adt.ts";
import { resolveSystem, sapConfig } from "./systems.ts";
import type { ObjectType } from "./adt.ts";
import { getTicket, log, saveTicket, WORK_DIR } from "./store.ts";
import { TEAM, WORK_STAGES } from "./types.ts";
import type { DeployConfig, LeadReview, StageKey, Ticket, WorkStage } from "./types.ts";

// 팀장(사용자)의 승인·수정 지시와 개발계 반영. 각 단계의 실제 작업은 Claude Code가 한다 (cli.ts 참고).

const deploying = new Set<string>();

// 서버가 연결하는 후속 작업 (개발계 반영 성공 후 배운 점 정리 등)
export const hooks: { afterDeploy?: (id: string) => void } = {};

export function isBusy(id: string): boolean {
  return deploying.has(id);
}

function mustGet(id: string): Ticket {
  const t = getTicket(id);
  if (!t) throw new Error("요청을 찾을 수 없습니다.");
  return t;
}

export function approveStage(id: string): void {
  const t = mustGet(id);
  if (t.status !== "awaiting_review") throw new Error("팀장 승인 대기 상태가 아닙니다.");
  const stage = t.currentStage as WorkStage;
  t.stages[stage].status = "approved";
  t.stages[stage].endedAt = new Date().toISOString();
  log(t, "팀장", `✅ ${TEAM[stage].name} 결과를 승인했습니다.`);
  const next = WORK_STAGES[WORK_STAGES.indexOf(stage) + 1];
  if (!next) {
    t.status = "awaiting_deploy";
    t.currentStage = "deploy";
    log(t, TEAM.lead.name, "분석~테스트가 모두 승인되었습니다. 개발계 반영을 승인해 주세요.");
    return;
  }
  t.currentStage = next;
  // 이전 방식에서 넘어와 이미 보고가 올라와 있는 단계면 바로 승인 대기
  t.status = t.stages[next].status === "review" ? "awaiting_review" : "in_progress";
  if (t.status === "in_progress") log(t, TEAM.lead.name, `${TEAM[next].name} 작업 차례입니다. Claude Code에서 진행합니다.`);
  else saveTicket(t);
}

// 팀장 수정 지시: 지정한 단계(현재 단계 또는 앞 단계)부터 다시 작업하고, 끝나면 다시 보고한다
export function revise(id: string, target: string, feedback: string): void {
  const t = mustGet(id);
  if (!["in_progress", "awaiting_review", "awaiting_deploy", "done", "failed"].includes(t.status)) throw new Error("수정 지시를 내릴 수 있는 상태가 아닙니다.");
  if (!feedback.trim()) throw new Error("수정 지시 내용을 입력해 주세요.");
  const cur = t.status === "in_progress" || t.status === "awaiting_review" ? WORK_STAGES.indexOf(t.currentStage as WorkStage) : WORK_STAGES.length - 1;
  const j = WORK_STAGES.indexOf(target as WorkStage);
  if (j < 0 || j > cur) throw new Error("현재 단계 또는 이전 단계에만 수정 지시를 내릴 수 있습니다.");

  const text = feedback.trim();
  const stage = WORK_STAGES[j];
  const st = t.stages[stage];
  // 아직 반영되지 않은 지시(예: 앞으로 할 단계에 걸어 둔 CR)가 있으면 이어 붙인다
  st.directive = st.directive ? `${st.directive}\n${text}` : text;
  st.directives.push({ at: new Date().toISOString(), text });
  // 다시 여는 단계는 시작일을 유지하고 종료일만 지운다. 그 뒤 단계는 새로 시작한다.
  for (const k of [...WORK_STAGES.slice(j), "deploy" as const]) {
    t.stages[k].status = "pending";
    t.stages[k].endedAt = null;
    if (k !== stage) t.stages[k].startedAt = null;
  }
  t.deployResult = null;
  t.revisionCount++;
  t.currentStage = stage;
  t.status = "in_progress";
  log(t, "팀장", `↩️ ${TEAM[stage].name}에게 수정 지시 — ${text}`);
}

// ---------- 개발계 반영 (ADT 직접 호출, LLM 없음) ----------

interface DevObject {
  type: ObjectType;
  name: string;
  description: string;
  source: string;
  testSource: string | null;
  /** include의 메인 프로그램 (반영 때 SAP에 연결된 값으로 바뀔 수 있다) */
  mainProgram?: string;
}

// 화면 플로우 로직(PROCESS BEFORE OUTPUT ...)은 ADT REST로 반영할 수 없어 SE51 수동 반영으로 돌린다
const isFlowLogic = (source: string) => /^\s*PROCESS\s+(BEFORE\s+OUTPUT|AFTER\s+INPUT)\b/im.test(source);

function srcFiles(id: string): { file: string; source: string }[] {
  const srcDir = path.join(WORK_DIR, id, "src");
  if (!fs.existsSync(srcDir)) return [];
  return fs
    .readdirSync(srcDir)
    .filter((f) => f.endsWith(".abap") && !f.endsWith(".testclasses.abap"))
    .map((f) => ({ file: f, source: fs.readFileSync(path.join(srcDir, f), "utf8") }));
}

function objectType(source: string): ObjectType {
  if (/^\s*CLASS\s+\S+\s+DEFINITION/im.test(source)) return "CLAS";
  if (/^\s*(REPORT|PROGRAM)\b/im.test(source)) return "PROG";
  return "INCL";
}

function devObjects(id: string): DevObject[] {
  const srcDir = path.join(WORK_DIR, id, "src");
  const files = srcFiles(id).filter((f) => !isFlowLogic(f.source));
  const objs = files.map(({ file: f, source }): DevObject => {
    const name = f.slice(0, -".abap".length).toUpperCase();
    const testFile = path.join(srcDir, `${f.slice(0, -".abap".length)}.testclasses.abap`);
    const shorttext = source.match(/shorttext[^>]*>([^<]+)</)?.[1] ?? source.match(/^\*&\s*Report\s+\S+\s*[-:]?\s*(.+)$/im)?.[1];
    return {
      type: objectType(source),
      name,
      description: (shorttext?.trim() || name).slice(0, 60),
      source,
      testSource: fs.existsSync(testFile) ? fs.readFileSync(testFile, "utf8") : null,
    };
  });
  // include의 메인 프로그램: 같이 올리는 프로그램 중 INCLUDE 하는 것 → 모듈풀 명명 규칙(MZXX0001F01 → SAPMZXX0001)
  for (const o of objs.filter((x) => x.type === "INCL")) {
    const includeStmt = new RegExp(`^\\s*INCLUDE\\s+${o.name}\\s*\\.`, "im");
    const byName = o.name.match(/^(M\w+?)(TOP|[A-Z]\d\d)$/);
    o.mainProgram = objs.find((p) => p.type === "PROG" && includeStmt.test(p.source))?.name ?? (byName ? `SAP${byName[1]}` : undefined);
  }
  // 메인 프로그램 → include → 클래스 순서로 만든다
  const order: Record<ObjectType, number> = { PROG: 0, INCL: 1, CLAS: 2 };
  return objs.sort((a, b) => order[a.type] - order[b.type]);
}

/** 웹앱이 반영하지 못해 SE51 등에서 직접 반영해야 하는 파일 */
function manualFiles(id: string): string[] {
  return srcFiles(id)
    .filter((f) => isFlowLogic(f.source))
    .map((f) => f.file);
}

export function approveDeploy(id: string, cfg: DeployConfig): void {
  const t = mustGet(id);
  if (deploying.has(id) || (t.status !== "awaiting_deploy" && t.status !== "failed")) throw new Error("개발계 반영 승인 대기 상태가 아닙니다.");
  t.deployConfig = { package: cfg.package.trim().toUpperCase() || "$TMP", transport: cfg.transport.trim().toUpperCase() };
  if (!devObjects(id).length) throw new Error("반영할 소스(work/<요청ID>/src/*.abap)가 없습니다.");
  t.status = "deploying";
  t.stages.deploy.status = "running";
  t.stages.deploy.attempts++;
  t.stages.deploy.startedAt ??= new Date().toISOString();
  t.stages.deploy.endedAt = null;
  log(t, "팀장", "개발계 반영을 승인했습니다.");
  deploying.add(id);
  runDeploy(id)
    .catch((e: Error) => {
      const f = mustGet(id);
      f.status = "failed";
      f.stages.deploy.status = "failed";
      f.deployResult = { mode: f.deployResult?.mode ?? "", ok: false, text: e.message ?? String(e) };
      log(f, TEAM.deploy.name, `반영 중 오류: ${e.message}`);
    })
    .finally(() => deploying.delete(id));
}

async function runDeploy(id: string): Promise<void> {
  const t = mustGet(id);
  const { package: pkg } = t.deployConfig!;
  let { transport } = t.deployConfig!;
  const sap = sapConfig(t.system);
  const adt = sap ? new AdtClient(sap) : null;
  const mode = adt ? `실제 반영 (${resolveSystem(t.system)} · ${sap!.url}, 클라이언트 ${sap!.client})` : "시뮬레이션 (SAP 접속 정보 없음 - 실제로 반영되지 않음)";
  const objs = devObjects(id);
  const lines: string[] = [`반영 모드: ${mode}`, `패키지 ${pkg}, 이송요청 ${transport || (pkg.startsWith("$") ? "없음 (로컬 오브젝트)" : "자동 생성")}`, ""];
  const note = (text: string) => {
    lines.push(text);
    log(t, TEAM.deploy.name, text);
  };

  // 로컬이 아닌 패키지에 이송요청 번호가 없으면 새로 만든다. 번호는 deployConfig에 남겨 재반영 때 다시 쓴다
  // $로 시작하는 패키지($TMP, $ZTEST 등)는 로컬 패키지라 이송요청이 없다
  if (!pkg.startsWith("$") && !transport) {
    const text = `[devsap ${id}] ${t.title}`;
    if (!adt) note(`[시뮬레이션] 이송요청 자동 생성 ("${text.slice(0, 60)}")`);
    else {
      transport = await adt.createTransport(pkg, text, objectUri(objs[0].type, objs[0].name));
      t.deployConfig = { package: pkg, transport };
      note(`이송요청 ${transport} 자동 생성 ("${text.slice(0, 60)}")`);
    }
  }

  for (const o of objs) {
    const mainNote = () => (o.type === "INCL" ? ` (메인 프로그램 ${o.mainProgram ?? "미확인"})` : "");
    if (!adt) {
      note(`[시뮬레이션] ${o.type} ${o.name}${mainNote()} 생성/저장 (소스 ${o.source.split("\n").length}줄${o.testSource ? ", 테스트 클래스 포함" : ""})`);
      continue;
    }
    const existed = await adt.exists(o.type, o.name);
    if (o.type === "INCL") {
      // 이미 있는 include는 SAP에 연결된 메인 프로그램을 그대로 쓴다
      if (existed) o.mainProgram = (await adt.includeMainProgram(o.name)) ?? o.mainProgram;
      else {
        if (!o.mainProgram) throw new Error(`${o.name}: 메인 프로그램을 알 수 없어 include를 만들 수 없습니다. 메인 프로그램 소스(INCLUDE ${o.name}.)를 함께 올려 주세요.`);
        if (!objs.some((p) => p.type === "PROG" && p.name === o.mainProgram) && !(await adt.exists("PROG", o.mainProgram)))
          throw new Error(`${o.name}: 메인 프로그램 ${o.mainProgram}이(가) SAP에 없습니다. 메인 프로그램을 먼저 만들거나 소스를 함께 올려 주세요.`);
      }
    }
    if (!existed) await adt.create(o.type, o.name, o.description, pkg, transport, o.mainProgram);
    await adt.writeSource(o.type, o.name, "main", o.source, transport);
    if (o.type === "CLAS" && o.testSource) await adt.writeSource(o.type, o.name, "testclasses", o.testSource, transport);
    note(`${o.type} ${o.name}${mainNote()} ${existed ? "소스 갱신" : "신규 생성"} 완료${o.type === "CLAS" && o.testSource ? " (테스트 클래스 포함)" : ""}`);
  }

  const manual = manualFiles(id);
  if (manual.length) note(`⚠️ 수동 반영 필요 (ADT로 반영 불가): ${manual.join(", ")} — SE51 화면 플로우 로직은 화면 레이아웃·GUI Status와 함께 직접 반영해 주세요.`);

  let ok = true;
  if (adt) {
    const r = await adt.activate(objs);
    ok = r.ok;
    note(`활성화 ${r.ok ? "성공" : "실패"}${r.messages.length ? `\n${r.messages.join("\n")}` : ""}`);
    if (ok)
      for (const o of objs.filter((x) => x.type === "CLAS" && x.testSource)) {
        const u = await adt.runUnitTests(o.type, o.name);
        if (!u.includes("모든 테스트 통과")) ok = false;
        note(`${o.name} ABAP Unit: ${u}`);
      }
  } else note("[시뮬레이션] 활성화·ABAP Unit은 실행되지 않았습니다.");

  t.deployResult = { mode, ok, text: lines.join("\n") };
  t.stages.deploy.status = ok ? "approved" : "failed";
  if (ok) t.stages.deploy.endedAt = new Date().toISOString();
  t.status = ok ? "done" : "failed";
  log(t, TEAM.deploy.name, ok ? "📋 개발계 반영을 마쳤습니다." : "⚠️ 반영 중 문제가 있습니다. 결과를 확인하고 수정 지시를 내려 주세요.");
  if (ok) hooks.afterDeploy?.(id);
}

// 서버가 반영 도중 꺼졌던 요청은 실패로 표시해 다시 승인할 수 있게 한다
export function recoverInterrupted(tickets: Ticket[]): void {
  for (const t of tickets)
    if (t.status === "deploying") {
      t.status = "failed";
      t.stages.deploy.status = "failed";
      log(t, TEAM.deploy.name, "서버 재시작으로 반영이 중단되었습니다. 다시 승인해 주세요.");
    }
}

// cli.ts에서 쓰는 단계 갱신
export function startStage(id: string): Ticket {
  const t = mustGet(id);
  if (t.status !== "in_progress") throw new Error(`작업할 차례가 아닙니다 (상태: ${t.status}).`);
  const stage = t.currentStage as WorkStage;
  const st = t.stages[stage];
  st.status = "running";
  st.attempts++;
  st.startedAt ??= new Date().toISOString();
  st.endedAt = null;
  log(t, TEAM[stage].name, st.directive ? "팀장 수정 지시를 반영해 다시 작업합니다." : "작업을 시작합니다.");
  return t;
}

export function reportStage(id: string, review: Omit<LeadReview, "send_back_to"> & { send_back_to?: StageKey }): Ticket {
  const t = mustGet(id);
  if (t.status !== "in_progress") throw new Error(`보고할 단계가 없습니다 (상태: ${t.status}).`);
  const stage = t.currentStage as WorkStage;
  const st = t.stages[stage];
  const back = WORK_STAGES.includes(review.send_back_to as WorkStage) && WORK_STAGES.indexOf(review.send_back_to as WorkStage) <= WORK_STAGES.indexOf(stage)
    ? (review.send_back_to as WorkStage)
    : stage;
  st.review = { decision: review.decision, send_back_to: back, feedback: review.feedback, summary: review.summary };
  st.directive = null;
  st.status = "review";
  t.status = "awaiting_review";
  log(t, TEAM.lead.name, `📨 팀장님께 ${TEAM[stage].name} 결과를 보고드립니다 (권고: ${review.decision === "approve" ? "승인" : "수정"}) — ${review.summary}`);
  return t;
}

export function failStage(id: string, reason: string): Ticket {
  const t = mustGet(id);
  const stage = t.currentStage as WorkStage;
  t.stages[stage].status = "failed";
  log(t, TEAM.lead.name, `⚠️ ${TEAM[stage].name} 작업 실패 — ${reason}`);
  return t;
}
