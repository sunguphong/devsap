import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { spawnClaude } from "./runner.ts";
import { getTicket, log, stageFiles, WORK_DIR } from "./store.ts";
import { TEAM, WORK_STAGES } from "./types.ts";
import type { WorkStage } from "./types.ts";

// 보고용 PPT: 단계 산출물을 그대로 옮기면 글이 너무 많아 보고 자료로 쓰기 어렵다.
// 읽기 전용 헤드리스 세션이 산출물을 슬라이드 개요(한 장 한 메시지, 짧은 요점·표·흐름도)로 요약하고,
// 브라우저(public/stagepptx.js)가 그 개요로 디자인된 슬라이드를 만든다. 상세 내용은 발표자 노트로 보낸다.
// 개요는 work/<ID>/.deck/<단계>.json 에 두고, 산출물이 바뀌면(hash) 다시 만든다.

const AGENT = "보고 자료";

const POINT = {
  type: "object",
  properties: {
    head: { type: "string", description: "요점 제목 15자 이내 (metrics면 수치·값, 예: '12건', '100%')" },
    text: { type: "string", description: "설명 한 줄 45자 이내. 문장 대신 명사형으로 끝낸다" },
  },
  required: ["head", "text"],
};

const SCHEMA = {
  type: "object",
  properties: {
    headline: { type: "string", description: "이 단계 결과를 한 문장으로 (50자 이내). 결론부터" },
    summary: { type: "array", items: { type: "string" }, description: "'한눈에 보기' 핵심 3~4개, 각 40자 이내" },
    slides: {
      type: "array",
      description: "본문 슬라이드 5~9장. 한 장에 메시지 하나",
      items: {
        type: "object",
        properties: {
          layout: {
            type: "string",
            enum: ["points", "steps", "metrics", "table", "diagram"],
            description: "points=요점 카드 2~4개, steps=순서가 있는 처리 단계 3~6개, metrics=핵심 수치 2~4개, table=비교·목록 표, diagram=Mermaid 흐름도",
          },
          title: { type: "string", description: "슬라이드 제목 20자 이내" },
          message: { type: "string", description: "이 장에서 말하려는 핵심 메시지 한 문장 (50자 이내)" },
          points: { type: "array", items: POINT, description: "points/steps/metrics용. diagram이면 그림 옆 설명 0~3개. table이면 빈 배열" },
          table: {
            type: "object",
            properties: {
              head: { type: "array", items: { type: "string" } },
              rows: { type: "array", items: { type: "array", items: { type: "string" } } },
            },
            required: ["head", "rows"],
            description: "table용: 열 2~5개, 행 2~7개, 셀 20자 이내. 다른 layout이면 head·rows 빈 배열",
          },
          diagram: { type: "string", description: "diagram용 Mermaid 코드 (flowchart LR 또는 TD, 노드 10개 이내, 라벨 12자 이내, A[\"라벨\"] 형태, HTML 태그 금지). 다른 layout이면 빈 문자열" },
          notes: { type: "string", description: "발표자 노트: 이 장의 상세 근거·수치·예외 (산출물의 절 이름 포함). 화면에 못 넣은 내용은 여기에" },
        },
        required: ["layout", "title", "message", "points", "table", "diagram", "notes"],
      },
    },
    issues: { type: "array", items: POINT, description: "확인 필요·리스크 0~4개 (head=항목, text=누가 무엇을 확인)" },
    next: { type: "string", description: "다음 단계 또는 팀장이 결정할 사항 한두 문장" },
  },
  required: ["headline", "summary", "slides", "issues", "next"],
};

export type DeckOutline = Record<string, unknown>;
interface DeckFile { at: string; hash: string; attempt: number; outline: DeckOutline }

const FOCUS: Record<WorkStage, string> = {
  analysis: "요청 배경·목적 → 개발 범위(포함/제외) → 기능 요구사항 묶음 → 데이터 원천(테이블) → 화면·출력 → 확인 필요 사항",
  design: "전체 구조(오브젝트 구성) → 처리 흐름(diagram) → 화면 설계 → 핵심 로직·데이터 조회 → 성능·권한·예외 처리 → 확인 필요 사항",
  development: "개발 오브젝트 목록(table) → 처리 흐름(steps 또는 diagram) → 핵심 구현 포인트 → 개발표준·성능 준수 → 남은 과제",
  test: "테스트 결과 수치(metrics: 시나리오 수·통과·실패) → 요구사항별 커버리지(table) → 발견 결함과 조치 → ABAP Unit 요약 → 개발계 반영 전 확인 사항",
};

const building = new Map<string, string | null>(); // `${id}:${stage}` → 실패 사유 (null = 진행 중)
const key = (id: string, stage: string) => `${id}:${stage}`;
const deckPath = (id: string, stage: WorkStage) => path.join(WORK_DIR, id, ".deck", `${stage}.json`);
const hashFiles = (id: string, stage: WorkStage) =>
  crypto.createHash("sha1").update(stageFiles(id, stage).map((f) => `${f.name}\n${f.content}`).join("\0")).digest("hex");

export function isDeckBuilding(id: string): boolean {
  return WORK_STAGES.some((s) => building.get(key(id, s)) === null);
}

function readDeck(id: string, stage: WorkStage): DeckFile | null {
  try { return JSON.parse(fs.readFileSync(deckPath(id, stage), "utf8")); } catch { return null; }
}

/** 보드에 보여 줄 단계별 보고용 PPT 상태 */
export function deckStatus(id: string): Record<string, { status: "building" | "ready" | "stale" | "failed" | "none"; at?: string; error?: string }> {
  return Object.fromEntries(WORK_STAGES.map((s) => {
    const b = building.get(key(id, s));
    if (b === null) return [s, { status: "building" }];
    const d = readDeck(id, s);
    if (b) return [s, { status: "failed", error: b, at: d?.at }];
    if (!d) return [s, { status: "none" }];
    return [s, { status: d.hash === hashFiles(id, s) ? "ready" : "stale", at: d.at }];
  }));
}

export function getDeck(id: string, stage: string): DeckOutline {
  if (!WORK_STAGES.includes(stage as WorkStage)) throw new Error("보고용 PPT를 만들 단계를 지정해 주세요.");
  const d = readDeck(id, stage as WorkStage);
  if (!d) throw new Error("아직 보고용 요약이 없습니다.");
  return d.outline;
}

function buildPrompt(id: string, stage: WorkStage): string {
  const t = getTicket(id)!;
  const st = t.stages[stage];
  const files = stageFiles(id, stage).map((f) => `work/${id}/${f.name}`);
  const applied = (t.changes ?? []).filter((c) => c.status === "applied");
  return [
    `당신은 SAP 개발팀 PL입니다. ${TEAM[stage].name} 산출물을 팀장·현업 보고용 슬라이드 개요로 요약합니다.`,
    `(이 세션은 읽기 전용입니다. 파일을 고치거나 서브에이전트를 실행하지 말고, CLAUDE.md의 "진행해" 절차와 src/cli.ts도 쓰지 않습니다.)`,
    ``,
    `요청: ${t.title} (ID ${id})`,
    `읽을 자료: ${files.join(", ")} (요청 배경이 필요하면 work/${id}/request.md)`,
    applied.length ? `반영된 요구사항 변경: ${applied.map((c) => `${c.id} ${c.text}`).join(" / ")}` : "",
    st.review ? `PL 1차 검토: ${st.review.decision === "approve" ? "승인 권고" : "수정 권고"} — ${st.review.summary}` : "",
    ``,
    `권장 흐름 (내용이 없으면 건너뛰고, 산출물에 없는 내용은 지어내지 않습니다): ${FOCUS[stage]}`,
    ``,
    `작성 원칙 — 이 자료는 화면에 띄워 보고하고, 나중에 다시 보는 자료로도 씁니다:`,
    `- 한 장에 메시지 하나. message는 제목을 반복하지 말고 "그래서 무엇인지"를 말합니다.`,
    `- 화면 글은 최소로: 요점은 2~4개, 각 줄은 명사형으로 짧게. 문단·긴 문장 금지.`,
    `- 글보다 구조로 보여 줍니다: 순서는 steps, 흐름·관계는 diagram, 비교·목록은 table, 숫자는 metrics.`,
    `- 같은 layout을 3장 넘게 연달아 쓰지 않습니다.`,
    `- 테이블·필드·프로그램명 같은 기술 이름은 꼭 필요한 곳에만, 처음 나올 때 우리말 뜻과 함께 씁니다.`,
    `- 화면에서 뺀 상세 근거·필드 목록·예외 조건은 notes(발표자 노트)에 정리합니다. 자료를 나중에 다시 볼 때 노트가 상세 설명 역할을 합니다.`,
    `- 끝나면 구조화된 출력(headline, summary, slides, issues, next)으로 돌려줍니다. 모두 한국어.`,
  ].filter((l) => l !== "").join("\n");
}

export function runDeck(id: string, stageArg: string): void {
  const t = getTicket(id);
  if (!t) throw new Error("요청을 찾을 수 없습니다.");
  const stage = stageArg as WorkStage;
  if (!WORK_STAGES.includes(stage)) throw new Error("보고용 PPT를 만들 단계를 지정해 주세요.");
  if (t.stages[stage].status === "running") throw new Error("작업 중인 단계입니다. 보고가 올라온 뒤 다시 시도해 주세요.");
  if (building.get(key(id, stage)) === null) throw new Error("이미 보고용 요약을 만드는 중입니다.");
  if (!stageFiles(id, stage).length) throw new Error("이 단계에는 아직 산출물이 없습니다.");

  const hash = hashFiles(id, stage);
  const attempt = t.stages[stage].attempts;
  building.set(key(id, stage), null);
  log(t, "팀장", `📊 ${TEAM[stage].name} 보고용 PPT 요약을 요청했습니다.`);

  spawnClaude<DeckOutline>({
    prompt: buildPrompt(id, stage),
    schema: SCHEMA,
    permissionMode: "default",
    tools: ["Read", "Glob", "Grep"],
    onTool: () => {},
    onDone: (out, error) => {
      const cur = getTicket(id);
      const slides = (out as { slides?: unknown[] } | null)?.slides;
      if (!out || !Array.isArray(slides) || !slides.length) {
        const why = error ?? "요약 결과가 올바르지 않습니다.";
        building.set(key(id, stage), why);
        if (cur) log(cur, AGENT, `⚠️ ${TEAM[stage].name} 보고용 PPT 요약 실패 — ${why}`);
        return;
      }
      fs.mkdirSync(path.dirname(deckPath(id, stage)), { recursive: true });
      fs.writeFileSync(deckPath(id, stage), JSON.stringify({ at: new Date().toISOString(), hash, attempt, outline: out } satisfies DeckFile, null, 2));
      building.delete(key(id, stage));
      if (cur) log(cur, AGENT, `📊 ${TEAM[stage].name} 보고용 PPT 요약을 만들었습니다 (본문 ${slides.length}장).`);
    },
  });
}
