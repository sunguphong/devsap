import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { authEnabled } from "./auth.ts";
import { claudeBin } from "./runner.ts";
import { listTickets } from "./store.ts";
import { currentSystem, listSystems } from "./systems.ts";

// 개발구성 화면에 보여 줄 실제 값 (서버·디스크·메모리·저장 폴더·터널·git·Claude Code)

const STARTED = new Date();

interface DirStat { size: number; files: number; mtime: number }

/** 폴더(또는 파일) 전체 크기·파일 수·마지막 변경 시각 */
function statPath(p: string, skip: (name: string) => boolean = () => false): DirStat {
  const out: DirStat = { size: 0, files: 0, mtime: 0 };
  const walk = (cur: string) => {
    let st: fs.Stats;
    try {
      st = fs.statSync(cur);
    } catch {
      return;
    }
    if (st.isDirectory()) {
      out.mtime = Math.max(out.mtime, st.mtimeMs);
      for (const n of fs.readdirSync(cur)) if (!skip(n)) walk(path.join(cur, n));
    } else {
      out.size += st.size;
      out.files++;
      out.mtime = Math.max(out.mtime, st.mtimeMs);
    }
  };
  walk(p);
  return out;
}

const run = (cmd: string, args: string[], timeout = 5000) => {
  try {
    return execFileSync(cmd, args, { encoding: "utf8", windowsHide: true, timeout }).trim();
  } catch {
    return null;
  }
};

let claudeVersion: string | null | undefined;

/** cloudflared 빠른 터널은 127.0.0.1:20241~20245 의 /quicktunnel 에 자기 주소를, /config 에 연결 대상을 알려 준다.
 *  이 PC에 다른 앱용 터널도 떠 있을 수 있으므로 보드 포트로 가는 것만 고른다 */
async function tunnels(boardPort: number): Promise<string[]> {
  const get = async (port: number, p: string) => (await fetch(`http://127.0.0.1:${port}${p}`, { signal: AbortSignal.timeout(800) })).json() as Promise<any>;
  const found = await Promise.all(
    [20241, 20242, 20243, 20244, 20245].map(async (port) => {
      try {
        const [q, c] = await Promise.all([get(port, "/quicktunnel"), get(port, "/config")]);
        const targets: string[] = (c?.config?.ingress ?? []).map((r: any) => String(r.service ?? ""));
        const toBoard = targets.some((s) => new RegExp(`^https?://(localhost|127\\.0\\.0\\.1|\\[::1\\]):${boardPort}/?$`).test(s));
        return q?.hostname && toBoard ? `https://${q.hostname}` : null;
      } catch {
        return null;
      }
    }),
  );
  return found.filter((x): x is string => !!x);
}

export async function devInfo() {
  const tickets = listTickets();
  const data = [
    { key: "work/", what: "개발 요청 전체 (요청서·산출물·소스·첨부·진행 기록 ticket.json)", st: statPath("work", (n) => n === ".trash"), git: true },
    { key: "work/.trash/", what: "휴지통 — 삭제한 요청 (복원 가능)", st: statPath(path.join("work", ".trash")), git: true },
    { key: "wiki/", what: "지식 위키 문서 (PL이 자동 정리 + 직접 작성)", st: statPath("wiki", (n) => n === ".history"), git: true },
    { key: "wiki/.history/", what: "위키 문서 이전 버전", st: statPath(path.join("wiki", ".history")), git: true },
    { key: "standards/", what: "개발표준 핸드북 (이전 버전은 .history)", st: statPath("standards"), git: true },
    { key: ".claude/agents/", what: "단계별 서브에이전트 지침 (분석·설계·개발·테스트)", st: statPath(path.join(".claude", "agents")), git: true },
    { key: "data/settings.json", what: "보드 기본 SAP 시스템 선택값", st: statPath(path.join("data", "settings.json")), git: false },
    { key: "data/devgate.json", what: "개발구성 화면 비밀번호 (scrypt 해시)", st: statPath(path.join("data", "devgate.json")), git: false },
    { key: ".env", what: "보드 로그인 비밀번호 등 환경 변수 (내용은 표시하지 않음)", st: statPath(".env"), git: false },
  ];
  const totals = data.filter((d) => d.key !== "work/.trash/").reduce((a, d) => ({ size: a.size + d.st.size, files: a.files + d.st.files }), { size: 0, files: 0 });
  totals.size += data[1].st.size;
  totals.files += data[1].st.files;

  let disk: { free: number; total: number } | null = null;
  try {
    const s = fs.statfsSync(process.cwd());
    disk = { free: s.bavail * s.bsize, total: s.blocks * s.bsize };
  } catch {}

  claudeVersion ??= run(claudeBin(), ["--version"]);
  const git = (() => {
    const remote = run("git", ["remote", "get-url", "origin"]);
    if (!remote) return null;
    return {
      remote,
      branch: run("git", ["rev-parse", "--abbrev-ref", "HEAD"]),
      head: run("git", ["log", "-1", "--format=%h"]),
      subject: run("git", ["log", "-1", "--format=%s"]),
      at: run("git", ["log", "-1", "--format=%cI"]),
      dirty: (run("git", ["status", "--porcelain"]) ?? "").split("\n").filter(Boolean).length,
    };
  })();

  const mem = process.memoryUsage();
  const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
  return {
    now: new Date().toISOString(),
    app: {
      startedAt: STARTED.toISOString(),
      uptimeSec: Math.round(process.uptime()),
      node: process.version,
      express: pkg.dependencies?.express ?? "",
      port: Number(process.env.PORT || 3300),
      pid: process.pid,
      rss: mem.rss,
      cwd: process.cwd(),
      tz: Intl.DateTimeFormat().resolvedOptions().timeZone,
    },
    host: {
      name: os.hostname(),
      os: `${os.version()} (${os.release()}, ${os.arch()})`,
      cpu: `${os.cpus()[0]?.model ?? ""} · ${os.cpus().length}코어`,
      memTotal: os.totalmem(),
      memFree: os.freemem(),
      uptimeSec: Math.round(os.uptime()),
    },
    disk,
    data,
    totals,
    tickets: {
      total: tickets.length,
      active: tickets.filter((t) => t.status !== "done").length,
      done: tickets.filter((t) => t.status === "done").length,
    },
    auth: authEnabled(),
    systems: listSystems().map((s) => ({ name: s.name, url: s.url, client: s.client, user: s.user })),
    current: currentSystem(),
    tunnels: await tunnels(Number(process.env.PORT || 3300)),
    claude: claudeVersion,
    git,
  };
}
