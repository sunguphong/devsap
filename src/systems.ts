import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { sapConfigFromEnv } from "./adt.ts";
import type { SapConfig } from "./adt.ts";

// 접속할 SAP 시스템 = Claude Code에 등록된 ABAP MCP 서버 (~/.claude.json 사용자·프로젝트 범위, .mcp.json) 중 팀장이 고른 하나.
// 헤드리스 세션에는 고른 서버만 'sap' 이라는 이름으로 넘겨서(--mcp-config --strict-mcp-config) 에이전트 도구 이름(mcp__sap__*)이 바뀌지 않게 한다.
// 개발계 반영(ADT)도 같은 서버의 접속 정보를 쓴다. 등록된 서버가 없으면 .env 접속 정보로 동작한다.

export const MCP_ALIAS = "sap";

interface McpServer {
  type?: string;
  command?: string;
  args?: string[];
  env?: Record<string, string>;
  [k: string]: unknown;
}

export interface SapSystem {
  name: string;
  url: string;
  client: string;
  user: string;
  language: string;
}

const SETTINGS = path.resolve("data", "settings.json");

function readJson(file: string): any {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    return null;
  }
}

/** SAP 접속 정보(SAP_URL)가 있는 MCP 서버. 같은 이름이면 프로젝트 범위가 이긴다 */
function mcpServers(): Map<string, McpServer> {
  const user = readJson(path.join(os.homedir(), ".claude.json"));
  const cwd = process.cwd().replaceAll("\\", "/");
  const project = Object.entries(user?.projects ?? {}).find(([p]) => p.replaceAll("\\", "/").toLowerCase() === cwd.toLowerCase())?.[1] as any;
  const all = { ...user?.mcpServers, ...project?.mcpServers, ...readJson(".mcp.json")?.mcpServers } as Record<string, McpServer>;
  return new Map(Object.entries(all).filter(([, s]) => s?.env?.SAP_URL));
}

export function listSystems(): SapSystem[] {
  return [...mcpServers()].map(([name, s]) => ({
    name,
    url: s.env!.SAP_URL,
    client: s.env!.SAP_CLIENT ?? "",
    user: s.env!.SAP_USERNAME ?? s.env!.SAP_USER ?? "",
    language: s.env!.SAP_LANGUAGE ?? "",
  }));
}

/** 보드 기본 시스템 이름 (새 요청의 기본값). 저장된 값이 없거나 등록이 빠졌으면 첫 번째 */
export function currentSystem(): string | null {
  const names = [...mcpServers().keys()];
  const saved = readJson(SETTINGS)?.sapSystem;
  return names.includes(saved) ? saved : names[0] ?? null;
}

/** 요청에 지정된 시스템. 없거나 등록이 빠졌으면 보드 기본 시스템 */
export function resolveSystem(name?: string | null): string | null {
  return name && mcpServers().has(name) ? name : currentSystem();
}

export function selectSystem(name: string): void {
  if (!mcpServers().has(name)) throw new Error(`등록되지 않은 MCP 서버입니다: ${name}`);
  fs.mkdirSync(path.dirname(SETTINGS), { recursive: true });
  fs.writeFileSync(SETTINGS, JSON.stringify({ ...readJson(SETTINGS), sapSystem: name }, null, 2));
}

/** 개발계 반영·접속 테스트용 ADT 접속 정보 */
export function sapConfig(system?: string | null): SapConfig | null {
  const name = resolveSystem(system);
  const env = name ? mcpServers().get(name)!.env! : null;
  if (!env) return sapConfigFromEnv();
  const user = env.SAP_USERNAME ?? env.SAP_USER;
  if (!user || !env.SAP_PASSWORD) return null;
  return { url: env.SAP_URL, client: env.SAP_CLIENT || "100", user, password: env.SAP_PASSWORD, language: env.SAP_LANGUAGE || "KO" };
}

/** 헤드리스 세션용 MCP 설정 파일. 비밀번호가 들어 있으니 세션이 끝나면 지운다. 시스템이 없으면 null */
export function writeMcpConfig(system?: string | null): { file: string; system: SapSystem; cleanup: () => void } | null {
  const name = resolveSystem(system);
  if (!name) return null;
  const file = path.join(os.tmpdir(), `devsap-mcp-${process.pid}-${Date.now()}-${Math.random().toString(36).slice(2)}.json`);
  fs.writeFileSync(file, JSON.stringify({ mcpServers: { [MCP_ALIAS]: mcpServers().get(name) } }), { mode: 0o600 });
  return { file, system: listSystems().find((s) => s.name === name)!, cleanup: () => fs.rmSync(file, { force: true }) };
}
