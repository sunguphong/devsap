import { spawnClaude } from "./runner.ts";
import { getTicket, log } from "./store.ts";
import { TEAM } from "./types.ts";
import type { Lessons } from "./types.ts";
import { archiveChanged, snapshotWiki } from "./wiki.ts";

// 요청 진행 중 배운 점을 PL(헤드리스 Claude Code)이 지식 위키(wiki/*.md)에 주제별 문서로 정리한다.
// 쓰기 권한은 wiki/ 폴더로 제한한다.

const learning = new Set<string>();
// 위키 파일을 동시에 고치지 않도록 정리 작업은 한 번에 하나씩 돌린다
let queue: Promise<void> = Promise.resolve();

export function isLearning(id: string): boolean {
  return learning.has(id);
}

const SCHEMA = {
  type: "object",
  properties: {
    docs: {
      type: "array",
      items: {
        type: "object",
        properties: {
          title: { type: "string", description: "위키 문서 제목 (= 파일명)" },
          action: { type: "string", enum: ["created", "updated"] },
          summary: { type: "string", description: "이 문서에 정리/보강한 내용 한 줄" },
        },
        required: ["title", "action", "summary"],
      },
    },
  },
  required: ["docs"],
};

function buildPrompt(id: string, trigger: "approved" | "deployed" | "manual", existing: string[]): string {
  const t = getTicket(id)!;
  const focus = {
    approved: "분석~테스트가 모두 팀장 승인된 시점입니다.",
    deployed: "개발계 반영까지 끝난 시점입니다. 반영 결과(ticket.json의 deployResult)에서 배운 점도 포함하세요.",
    manual: "팀장이 직접 정리를 요청했습니다. 지금까지 진행된 단계까지 정리하세요.",
  }[trigger];
  return [
    `당신은 SAP 개발팀 PL입니다. 아래 개발 요청에서 팀이 배운 점을 팀 지식 위키에 정리합니다. ${focus}`,
    `(이 세션에서는 CLAUDE.md의 "진행해" 절차를 쓰지 않습니다.)`,
    ``,
    `요청: ${t.title} (ID ${t.id}) — 위키 링크 [[req:${t.id}|${t.title}]]`,
    `읽을 자료 (읽기 전용): work/${t.id}/request.md, attachments/ (첨부 자료, Office 문서는 attachments/.text/*.txt), 01_analysis.md, 02_design.md, 03_development.md, 04_test.md, src/*.abap, ticket.json (logs, stages[*].directives = 팀장 수정 지시, stages[*].review = PL 보고)`,
    `기존 위키 문서: ${existing.length ? existing.map((n) => `"${n}"`).join(", ") : "(없음)"}`,
    ``,
    `작성 규칙:`,
    `- 요청 단위 회고가 아니라 주제 단위 문서로 씁니다. 예: "배치관리 자재 판정 기준", "자재 단가 기준(이동평균가)", "자재마스터 조회 리포트 설계 패턴". 요청별 문서는 위키가 자동으로 만듭니다.`,
    `- 같은 주제의 기존 문서가 있으면 새로 만들지 말고 먼저 Read한 뒤 Edit로 보강합니다. 기존 내용을 지우지 말고, 서로 다르면 "요청별 차이"로 나란히 적습니다.`,
    `- 정리할 것: 현업이 확정한 사항과 근거, 팀장 수정 지시에서 드러난 요구 경향, 설계 판단과 그 이유, SAP 테이블·필드 사용법과 주의점, 테스트·리뷰에서 나온 결함 유형과 예방법, 개발계 반영 이슈.`,
    `- 이 요청에서 새로 배운 것이 없거나 일반 상식 수준이면 쓰지 않습니다. 보통 2~5개 문서면 충분합니다.`,
    `- SAP 시스템에서 확인하지 못한 정보는 "(시스템 미확인)"으로 표시합니다. 비밀번호·접속정보는 쓰지 않습니다.`,
    ``,
    `형식:`,
    `- 파일 경로 wiki/<제목>.md, 첫 줄 "# <제목>". 제목에 \\ / : * ? " < > | # [ ] 문자를 쓰지 않습니다.`,
    `- 마크다운. 각 항목에 출처 [[req:${t.id}|${t.title}]] 를 붙이고, 관련 문서는 [[문서 제목]], SAP 테이블은 [[table:MARC|MARC]] 로 링크합니다. 필드는 MARC-XCHPF 형태로 씁니다.`,
    `- wiki/ 폴더 밖의 파일과 wiki/.history 는 수정하지 않습니다.`,
    `- 판정 기준·데이터 경로·처리 흐름처럼 그림이 이해를 돕는 문서는 첫 "## " 절 앞에 "## 한눈에 보기" 절을 두고 Mermaid 다이어그램(\`\`\`mermaid, flowchart 권장) 1개를 넣습니다. 보강할 때는 다이어그램도 본문에 맞게 고칩니다.`,
    `- Mermaid 규칙: 노드 라벨은 A["라벨"]처럼 큰따옴표로 감싸고 라벨 안에 큰따옴표·HTML·[[링크]]를 쓰지 않습니다. 노드 ID는 영문/숫자만 쓰고 end·class·graph 같은 예약어는 피합니다. 노드는 15개 이하로 둡니다.`,
    ``,
    `끝나면 작성·보강한 문서 목록(docs)을 구조화된 출력으로 돌려줍니다. 아무것도 쓰지 않았다면 빈 배열을 돌려줍니다.`,
  ].join("\n");
}

export function runLessons(id: string, trigger: "approved" | "deployed" | "manual"): void {
  if (learning.has(id)) throw new Error("이미 배운 점을 정리하고 있습니다.");
  const t = getTicket(id);
  if (!t) throw new Error("요청을 찾을 수 없습니다.");
  learning.add(id);
  log(t, TEAM.lead.name, "📚 이번 요청에서 배운 점을 지식 위키에 정리합니다.");

  queue = queue.then(
    () =>
      new Promise<void>((resolve) => {
        const before = snapshotWiki();
        spawnClaude<{ docs: Lessons["docs"] }>({
          prompt: buildPrompt(id, trigger, [...before.keys()]),
          schema: SCHEMA,
          permissionMode: "default",
          tools: ["Read", "Glob", "Grep", "Edit(wiki/**)"],
          onTool: () => {},
          onDone: (out, error) => {
            learning.delete(id);
            const { created, updated } = archiveChanged(before);
            const cur = getTicket(id)!;
            if (error) log(cur, TEAM.lead.name, `⚠️ 배운 점 정리 실패 — ${error}`);
            else {
              // 실제로 바뀐 파일 기준으로 기록하고, PL이 준 요약을 붙인다
              const summaries = new Map((out?.docs ?? []).map((d) => [d.title, d.summary]));
              const docs = [
                ...created.map((title) => ({ title, action: "created" as const, summary: summaries.get(title) ?? "" })),
                ...updated.map((title) => ({ title, action: "updated" as const, summary: summaries.get(title) ?? "" })),
              ];
              const prev = cur.lessons?.docs ?? [];
              cur.lessons = { at: new Date().toISOString(), docs: [...docs, ...prev.filter((p) => !docs.some((d) => d.title === p.title))] };
              log(cur, TEAM.lead.name, docs.length
                ? `📚 지식 위키 정리 완료 — ${docs.map((d) => `${d.action === "created" ? "새 문서" : "보강"} '${d.title}'`).join(", ")}`
                : "📚 이번에는 위키에 새로 정리할 내용이 없었습니다.");
            }
            resolve();
          },
        });
      }),
  );
}
