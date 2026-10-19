import fs from "node:fs";
import path from "node:path";
import { listTickets, readRequest, stageFiles } from "./store.ts";
import { TEAM, WORK_STAGES } from "./types.ts";
import type { Ticket } from "./types.ts";

// 지식 위키: 프로젝트 산출물에서 자동으로 만든 문서 + 사람이 직접 쓴 문서(wiki/*.md)
//   doc:<이름>   직접 작성한 문서 (편집 가능, 이전 버전은 wiki/.history/에 보관)
//   req:<요청ID> 개발 요청별 산출물·의사결정 기록
//   table:<테이블> 산출물에 등장한 SAP 테이블과 필드
//   obj:<오브젝트> 개발한 ABAP 오브젝트
// 문서 안의 [[대상]] / [[대상|표시명]] 은 위키 링크다.

const WIKI_DIR = path.resolve("wiki");
const HISTORY_DIR = path.join(WIKI_DIR, ".history");
fs.mkdirSync(HISTORY_DIR, { recursive: true });

export type Category = "doc" | "req" | "table" | "obj";

export interface WikiPage {
  id: string;
  title: string;
  category: Category;
  markdown: string;
  updatedAt: string;
  editable: boolean;
}

// TABLE-FIELD 처럼 보이지만 ABAP 문법인 것
const NOT_TABLES = new Set(["SELECT", "SELECTION", "AUTHORITY", "TEXT", "START", "END", "TOP", "CALL", "READ", "CLASS", "LINE", "TYPE", "VERDICT", "UTF", "ISO", "HTTP", "ABAP", "SAP", "ALV", "NON"]);
const FIELD_RE = /\b([A-Z][A-Z0-9_]{2,15})[-~]([A-Z][A-Z0-9_]{1,29})\b/g;
const SRC_TABLE_RE = /\b(?:from|join|update|modify|insert\s+into|delete\s+from)\s+([a-z][a-z0-9_]{2,15})\b/gi;
const isVariable = (n: string) => /^(?:[lgsm][tsvor]?_|lo_|lr_|lv_|ls_|lt_|gt_|gs_|gv_|p_|s_|so_|pa_)/i.test(n);

// 표 행·강조 표시를 걷어내 한 줄 문맥으로 만든다
const cleanContext = (line: string) =>
  line.trim().replace(/^\||\|$/g, "").split("|").map((c) => c.trim()).filter(Boolean).join(" · ").replace(/\*\*|`/g, "").replace(/^[-*>]\s*/, "").slice(0, 200);

const safeName = (title: string) => title.trim().replace(/[\\/:*?"<>|#\[\]]/g, "_").slice(0, 80);

// ---------- 직접 작성한 문서 ----------

function manualPages(): WikiPage[] {
  return fs
    .readdirSync(WIKI_DIR)
    .filter((f) => f.endsWith(".md"))
    .map((f) => {
      const file = path.join(WIKI_DIR, f);
      const name = f.slice(0, -3);
      const markdown = fs.readFileSync(file, "utf8");
      return { id: `doc:${name}`, title: name, category: "doc", markdown, updatedAt: fs.statSync(file).mtime.toISOString(), editable: true } as WikiPage;
    });
}

export function savePage(oldId: string | null, title: string, markdown: string): WikiPage {
  const name = safeName(title);
  if (!name) throw new Error("문서 제목을 입력해 주세요.");
  const file = path.join(WIKI_DIR, `${name}.md`);
  const oldName = oldId?.startsWith("doc:") ? oldId.slice(4) : null;
  if (oldName !== name && fs.existsSync(file)) throw new Error(`'${name}' 문서가 이미 있습니다.`);
  // 덮어쓰기·이름 변경 전 이전 버전을 보관한다
  if (oldName) {
    const prev = path.join(WIKI_DIR, `${oldName}.md`);
    if (fs.existsSync(prev)) {
      const dir = path.join(HISTORY_DIR, safeName(oldName));
      fs.mkdirSync(dir, { recursive: true });
      fs.copyFileSync(prev, path.join(dir, `${new Date().toISOString().replace(/[:.]/g, "-")}.md`));
      if (oldName !== name) fs.renameSync(prev, file);
    }
  }
  fs.writeFileSync(file, markdown.replace(/\r\n/g, "\n"));
  return manualPages().find((p) => p.id === `doc:${name}`)!;
}

/** 위키 문서 내용 스냅샷 (PL 자동 정리 전후 비교용) */
export function snapshotWiki(): Map<string, string> {
  return new Map(fs.readdirSync(WIKI_DIR).filter((f) => f.endsWith(".md")).map((f) => [f.slice(0, -3), fs.readFileSync(path.join(WIKI_DIR, f), "utf8")]));
}

/** 스냅샷 이후 바뀐 문서의 이전 버전을 .history에 보관하고, 새로 생긴/바뀐 문서 이름을 돌려준다 */
export function archiveChanged(before: Map<string, string>): { created: string[]; updated: string[] } {
  const after = snapshotWiki();
  const created: string[] = [];
  const updated: string[] = [];
  for (const [name, text] of after) {
    const old = before.get(name);
    if (old === undefined) created.push(name);
    else if (old !== text) {
      updated.push(name);
      const dir = path.join(HISTORY_DIR, safeName(name));
      fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(path.join(dir, `${new Date().toISOString().replace(/[:.]/g, "-")}.md`), old);
    }
  }
  return { created, updated };
}

// ---------- 산출물에서 자동으로 만드는 문서 ----------

interface Mention {
  table: string;
  field: string | null;
  ticket: Ticket;
  where: string; // 파일명
  context: string;
}

function collect() {
  const tickets = listTickets();
  const mentions: Mention[] = [];
  const objects = new Map<string, { name: string; type: string; ticket: Ticket; file: string; source: string; testSource: string | null }[]>();

  for (const t of tickets) {
    for (const s of WORK_STAGES)
      for (const f of stageFiles(t.id, s)) {
        if (f.name.endsWith(".abap")) {
          if (!f.name.endsWith(".testclasses.abap")) {
            const name = path.basename(f.name, ".abap").toUpperCase();
            const testFile = path.join("work", t.id, "src", `${path.basename(f.name, ".abap")}.testclasses.abap`);
            const list = objects.get(name) ?? [];
            list.push({
              name,
              type: /^\s*CLASS\s+\S+\s+DEFINITION/im.test(f.content) ? "CLAS" : "PROG",
              ticket: t,
              file: f.name,
              source: f.content,
              testSource: fs.existsSync(testFile) ? fs.readFileSync(testFile, "utf8") : null,
            });
            objects.set(name, list);
          }
          for (const m of f.content.matchAll(SRC_TABLE_RE))
            if (!isVariable(m[1])) mentions.push({ table: m[1].toUpperCase(), field: null, ticket: t, where: f.name, context: "" });
          for (const m of f.content.matchAll(/\b([a-z][a-z0-9_]{2,15})~([a-z][a-z0-9_]{1,29})\b/gi))
            if (!isVariable(m[1])) mentions.push({ table: m[1].toUpperCase(), field: m[2].toUpperCase(), ticket: t, where: f.name, context: "" });
          continue;
        }
        for (const line of f.content.split("\n"))
          for (const m of line.matchAll(FIELD_RE))
            if (!NOT_TABLES.has(m[1])) mentions.push({ table: m[1], field: m[2], ticket: t, where: f.name, context: cleanContext(line) });
      }
  }
  return { tickets, mentions, objects };
}

const reqLink = (t: Ticket) => `[[req:${t.id}|${t.title}]]`;

function ticketPage(t: Ticket, objects: string[]): WikiPage {
  const out: string[] = [`# ${t.title}`, "", `요청 ID ${t.id} · 등록 ${t.createdAt.slice(0, 10)} · 단계 ${TEAM[t.currentStage].name} · 팀장 수정 지시 ${t.revisionCount}회`, ""];
  if (objects.length) out.push(`개발 오브젝트: ${objects.map((o) => `[[obj:${o}|${o}]]`).join(", ")}`, "");
  out.push("## 현업 요청", readRequest(t.id).replace(/^# .*\n/, "").trim(), "");
  out.push("## 의사결정 기록");
  for (const s of WORK_STAGES) {
    const st = t.stages[s];
    for (const d of st.directives ?? []) out.push(`- ${d.at.slice(0, 10)} 팀장 → ${TEAM[s].name} 수정 지시: ${d.text}`);
    if (st.review) out.push(`- ${TEAM[s].name} PL 보고 (${st.status === "approved" ? "팀장 승인" : "검토 중"}): ${st.review.summary}`);
  }
  out.push("");
  for (const s of WORK_STAGES)
    for (const f of stageFiles(t.id, s))
      if (!f.name.endsWith(".abap")) out.push(`## ${TEAM[s].name} · ${f.name}`, f.content.replace(/^# .*\n/, ""), "");
  return { id: `req:${t.id}`, title: t.title, category: "req", markdown: out.join("\n"), updatedAt: t.updatedAt, editable: false };
}

function tablePages(mentions: Mention[]): WikiPage[] {
  const byTable = new Map<string, Mention[]>();
  for (const m of mentions) byTable.set(m.table, [...(byTable.get(m.table) ?? []), m]);
  return [...byTable].map(([table, ms]) => {
    const out = [`# ${table}`, "", "SAP 테이블. 개발 요청 산출물에서 언급된 필드와 쓰임새입니다.", ""];
    const fields = new Map<string, Mention[]>();
    for (const m of ms) if (m.field) fields.set(m.field, [...(fields.get(m.field) ?? []), m]);
    if (fields.size) {
      out.push("## 필드", "| 필드 | 사용한 요청 | 문맥 |", "|---|---|---|");
      for (const [f, fm] of [...fields].sort())
        out.push(
          `| ${table}-${f} | ${[...new Set(fm.map((m) => reqLink(m.ticket)))].join(", ")} | ${fm.find((m) => m.context)?.context ?? ""} |`,
        );
      out.push("");
    }
    out.push("## 사용한 요청");
    for (const t of new Map(ms.map((m) => [m.ticket.id, m.ticket])).values())
      out.push(`- ${reqLink(t)} (${[...new Set(ms.filter((m) => m.ticket.id === t.id).map((m) => m.where))].join(", ")})`);
    const updatedAt = ms.map((m) => m.ticket.updatedAt).sort().at(-1)!;
    return { id: `table:${table}`, title: table, category: "table", markdown: out.join("\n"), updatedAt, editable: false } as WikiPage;
  });
}

function objectPages(objects: ReturnType<typeof collect>["objects"], mentions: Mention[]): WikiPage[] {
  return [...objects].map(([name, list]) => {
    const o = list.at(-1)!;
    const tables = [...new Set(mentions.filter((m) => m.where === o.file && m.ticket.id === o.ticket.id).map((m) => m.table))].sort();
    const desc = o.source.match(/shorttext[^>]*>([^<]+)</)?.[1] ?? "";
    const out = [`# ${name}`, "", `${o.type === "CLAS" ? "ABAP 클래스" : "ABAP 프로그램"}${desc ? ` — ${desc}` : ""}`, ""];
    out.push(`개발 요청: ${list.map((x) => reqLink(x.ticket)).join(", ")}`);
    if (tables.length) out.push(`사용 테이블: ${tables.map((t) => `[[table:${t}|${t}]]`).join(", ")}`);
    out.push("", "## 소스", "```", o.source, "```");
    if (o.testSource) out.push("", "## ABAP Unit", "```", o.testSource, "```");
    return { id: `obj:${name}`, title: name, category: "obj", markdown: out.join("\n"), updatedAt: o.ticket.updatedAt, editable: false } as WikiPage;
  });
}

export function allPages(): WikiPage[] {
  const { tickets, mentions, objects } = collect();
  const objsOf = (t: Ticket) => [...objects].filter(([, l]) => l.some((x) => x.ticket.id === t.id)).map(([n]) => n);
  return [...manualPages(), ...tickets.map((t) => ticketPage(t, objsOf(t))), ...tablePages(mentions), ...objectPages(objects, mentions)];
}

// ---------- 조회·검색 ----------

export function getPage(id: string): (WikiPage & { backlinks: { id: string; title: string }[] }) | null {
  const pages = allPages();
  const page = pages.find((p) => p.id === id) ?? pages.find((p) => p.category === "doc" && p.title === id.replace(/^doc:/, ""));
  if (!page) return null;
  const targets = [page.id, page.title];
  const backlinks = pages
    .filter((p) => p.id !== page.id && [...p.markdown.matchAll(/\[\[([^\]|]+)/g)].some((m) => targets.includes(m[1].trim())))
    .map((p) => ({ id: p.id, title: p.title }));
  return { ...page, backlinks };
}

export function search(q: string) {
  const terms = q.toLowerCase().split(/\s+/).filter(Boolean);
  if (!terms.length) return [];
  const results: { id: string; title: string; category: Category; section: string; snippet: string; score: number }[] = [];
  for (const p of allPages()) {
    // 문서를 제목(##) 단위로 나눠 어느 부분이 맞았는지 보여준다
    const parts = p.markdown.split(/\n(?=##\s)/);
    for (const part of parts) {
      const section = part.match(/^##\s+(.*)/)?.[1] ?? "";
      const text = part.toLowerCase();
      const title = `${p.title} ${section}`.toLowerCase();
      if (!terms.every((t) => text.includes(t) || title.includes(t))) continue;
      const score = terms.reduce((s, t) => s + (title.includes(t) ? 10 : 0) + Math.min(text.split(t).length - 1, 10), 0);
      const i = Math.max(0, text.indexOf(terms[0]));
      const snippet = part.slice(Math.max(0, i - 60), i + 140).replace(/\s+/g, " ").trim();
      results.push({ id: p.id, title: p.title, category: p.category, section, snippet, score });
    }
  }
  return results.sort((a, b) => b.score - a.score).slice(0, 50);
}
