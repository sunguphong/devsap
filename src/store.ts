import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { STAGES, TEAM } from "./types.ts";
import type { StageKey, StageState, Ticket, WorkStage } from "./types.ts";

// 요청 1건 = work/<요청ID>/ 폴더. 상태는 ticket.json, 산출물은 Claude Code 서브에이전트가 같은 폴더에 쓴다.
// 웹앱과 Claude Code(cli.ts)가 같은 파일을 고치므로 메모리에 캐시하지 않고 매번 디스크에서 읽는다.
export const WORK_DIR = path.resolve("work");
fs.mkdirSync(WORK_DIR, { recursive: true });

const ticketFile = (id: string) => path.join(WORK_DIR, id, "ticket.json");

export const STAGE_FILES: Record<WorkStage, { docs: string[]; src: (f: string) => boolean }> = {
  analysis: { docs: ["01_analysis.md"], src: () => false },
  design: { docs: ["02_design.md"], src: () => false },
  development: { docs: ["03_development.md"], src: (f) => !f.endsWith(".testclasses.abap") },
  test: { docs: ["04_test.md"], src: (f) => f.endsWith(".testclasses.abap") },
};

function emptyStages(): Record<StageKey, StageState> {
  const stages = {} as Record<StageKey, StageState>;
  for (const s of STAGES) stages[s] = { status: "pending", review: null, attempts: 0, directive: null, directives: [] };
  return stages;
}

export function listTickets(): Ticket[] {
  return fs
    .readdirSync(WORK_DIR)
    .map((id) => getTicket(id))
    .filter((t): t is Ticket => Boolean(t))
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
}

export function getTicket(id: string): Ticket | undefined {
  if (!/^[\w-]+$/.test(id)) return undefined;
  try {
    const t = JSON.parse(fs.readFileSync(ticketFile(id), "utf8")) as Ticket;
    fillStageTimes(t);
    return t;
  } catch {
    return undefined;
  }
}

// 단계 시작·종료 시각이 없던 요청은 진행 기록에서 채운다 (undefined = 아직 안 채움, null = 비어 있음)
function fillStageTimes(t: Ticket): void {
  let prevEnd: string | null = null;
  for (const k of STAGES) {
    const st = t.stages[k];
    const name = TEAM[k].name;
    if (st.startedAt === undefined) {
      const first = t.logs.find((l) => k === "deploy"
        ? l.agent === "팀장" && /^(테스트계|개발계) 반영을 승인/.test(l.text)
        : l.agent === name && /작업을 시작합니다|다시 작업합니다/.test(l.text));
      st.startedAt = st.status === "pending" ? null : k === "analysis" ? t.createdAt : first?.at ?? prevEnd ?? t.createdAt;
    }
    if (st.endedAt === undefined) {
      const done = [...t.logs].reverse().find((l) => k === "deploy"
        ? /^📋 (테스트계|개발계) 반영을 마쳤습니다/.test(l.text)
        : l.agent === "팀장" && l.text.startsWith(`✅ ${name} 결과를 승인`));
      st.endedAt = st.status === "approved" ? done?.at ?? null : null;
    }
    prevEnd = st.endedAt ?? prevEnd;
  }
}

export function readRequest(id: string): string {
  try {
    return fs.readFileSync(path.join(WORK_DIR, id, "request.md"), "utf8");
  } catch {
    return "";
  }
}

export function createTicket(title: string, request: string, system: string | null = null): Ticket {
  const now = new Date().toISOString();
  const t: Ticket = {
    id: now.slice(0, 10).replaceAll("-", "") + "-" + crypto.randomBytes(3).toString("hex"),
    title,
    status: "in_progress",
    currentStage: "analysis",
    stages: emptyStages(),
    revisionCount: 0,
    deployConfig: null,
    deployResult: null,
    system,
    logs: [],
    createdAt: now,
    updatedAt: now,
  };
  fs.mkdirSync(path.join(WORK_DIR, t.id, "src"), { recursive: true });
  fs.writeFileSync(path.join(WORK_DIR, t.id, "request.md"), `# ${title}\n\n${request}\n`);
  saveTicket(t);
  return t;
}

export function saveTicket(t: Ticket): void {
  t.updatedAt = new Date().toISOString();
  const file = ticketFile(t.id);
  fs.writeFileSync(file + ".tmp", JSON.stringify(t, null, 2));
  fs.renameSync(file + ".tmp", file);
}

// 요청 삭제: 폴더를 바로 지우지 않고 work/.trash/<요청ID>-<시각>/ 으로 옮긴다 (실수로 지웠으면 다시 옮겨 오면 된다)
export function deleteTicket(id: string): void {
  if (!getTicket(id)) throw new Error("요청을 찾을 수 없습니다.");
  fs.mkdirSync(TRASH_DIR, { recursive: true });
  const dest = path.join(TRASH_DIR, `${id}-${new Date().toISOString().replace(/[:.]/g, "")}`);
  fs.renameSync(path.join(WORK_DIR, id), dest);
  const now = new Date();
  fs.utimesSync(dest, now, now); // 삭제 시각 = 휴지통 폴더 수정 시각
}

const TRASH_DIR = path.join(WORK_DIR, ".trash");
const trashPath = (entry: string) => {
  if (!/^[\w-]+$/.test(entry) || !fs.existsSync(path.join(TRASH_DIR, entry, "ticket.json"))) throw new Error("휴지통에서 요청을 찾을 수 없습니다.");
  return path.join(TRASH_DIR, entry);
};

/** 휴지통 목록 (최근 삭제 순). entry = 휴지통 폴더 이름 */
export function listTrash(): { entry: string; id: string; title: string; status: string; createdAt: string; deletedAt: string }[] {
  if (!fs.existsSync(TRASH_DIR)) return [];
  return fs.readdirSync(TRASH_DIR).flatMap((entry) => {
    try {
      const t = JSON.parse(fs.readFileSync(path.join(TRASH_DIR, entry, "ticket.json"), "utf8")) as Ticket;
      const deletedAt = fs.statSync(path.join(TRASH_DIR, entry)).mtime.toISOString();
      return [{ entry, id: t.id, title: t.title, status: t.status, createdAt: t.createdAt, deletedAt }];
    } catch {
      return [];
    }
  }).sort((a, b) => b.deletedAt.localeCompare(a.deletedAt));
}

export function restoreTicket(entry: string): string {
  const src = trashPath(entry);
  const id = (JSON.parse(fs.readFileSync(path.join(src, "ticket.json"), "utf8")) as Ticket).id;
  if (fs.existsSync(path.join(WORK_DIR, id))) throw new Error(`같은 번호의 요청(${id})이 이미 목록에 있어 복원할 수 없습니다.`);
  fs.renameSync(src, path.join(WORK_DIR, id));
  return id;
}

/** 휴지통에서 영구 삭제 (되돌릴 수 없음) */
export function purgeTicket(entry: string): void {
  fs.rmSync(trashPath(entry), { recursive: true, force: true });
}

export function log(t: Ticket, agent: string, text: string): void {
  t.logs.push({ at: new Date().toISOString(), agent, text });
  saveTicket(t);
}

/** 단계별 산출물 파일 (문서 + ABAP 소스) */
export function stageFiles(id: string, stage: WorkStage): { name: string; content: string }[] {
  const dir = path.join(WORK_DIR, id);
  const { docs, src } = STAGE_FILES[stage];
  const out: { name: string; content: string }[] = [];
  for (const d of docs) if (fs.existsSync(path.join(dir, d))) out.push({ name: d, content: fs.readFileSync(path.join(dir, d), "utf8") });
  const srcDir = path.join(dir, "src");
  if (fs.existsSync(srcDir))
    for (const f of fs.readdirSync(srcDir).sort())
      if (f.endsWith(".abap") && src(f)) out.push({ name: `src/${f}`, content: fs.readFileSync(path.join(srcDir, f), "utf8") });
  return out;
}

// 예전 API 방식(data/tickets/*.json)으로 만든 요청을 work/ 폴더 방식으로 옮긴다.
// 산출물 파일이 이미 있는 단계는 '팀장 승인 대기'로 두어 팀장이 하나씩 확인·승인하게 한다.
function migrateLegacy(): void {
  const legacyDir = path.resolve("data", "tickets");
  if (!fs.existsSync(legacyDir)) return;
  for (const file of fs.readdirSync(legacyDir)) {
    if (!file.endsWith(".json")) continue;
    const old = JSON.parse(fs.readFileSync(path.join(legacyDir, file), "utf8"));
    if (getTicket(old.id)) continue;
    const dir = path.join(WORK_DIR, old.id);
    fs.mkdirSync(path.join(dir, "src"), { recursive: true });
    if (!fs.existsSync(path.join(dir, "request.md"))) fs.writeFileSync(path.join(dir, "request.md"), `# ${old.title}\n\n${old.request}\n`);
    const t: Ticket = {
      id: old.id,
      title: old.title,
      status: "in_progress",
      currentStage: "analysis",
      stages: emptyStages(),
      revisionCount: 0,
      deployConfig: null,
      deployResult: null,
      logs: [],
      createdAt: old.createdAt,
      updatedAt: old.createdAt,
    };
    let first: WorkStage | null = null;
    for (const s of ["analysis", "design", "development", "test"] as WorkStage[]) {
      const done = STAGE_FILES[s].docs.every((d) => fs.existsSync(path.join(dir, d)));
      if (!done) break;
      t.stages[s].status = "review";
      first ??= s;
    }
    if (first) {
      t.currentStage = first;
      t.status = "awaiting_review";
    }
    log(t, "PL", "Claude Code 작업 방식으로 옮겼습니다. 이미 작성된 산출물은 팀장 승인을 기다립니다.");
  }
}
migrateLegacy();
