// Claude Code(PL)가 작업 상태를 보드에 기록할 때 쓰는 CLI
//   node src/cli.ts list                         작업할 차례인 요청 목록 (팀장 수정 지시 포함)
//   node src/cli.ts start <요청ID>               현재 단계 작업 시작 표시
//   node src/cli.ts report <요청ID> --summary "..." [--decision approve|revise] [--feedback "..."] [--send-back <단계>]
//                                                현재 단계 결과를 팀장에게 보고 (승인 대기로 전환)
//   node src/cli.ts fail <요청ID> "<사유>"       현재 단계 작업 실패 기록
import path from "node:path";
import { failStage, reportStage, startStage } from "./board.ts";
import { listTickets, STAGE_FILES, WORK_DIR } from "./store.ts";
import { TEAM } from "./types.ts";
import type { StageKey, WorkStage } from "./types.ts";

const [cmd, id, ...rest] = process.argv.slice(2);

function opt(name: string): string | undefined {
  const i = rest.indexOf(`--${name}`);
  return i >= 0 ? rest[i + 1] : undefined;
}

function main(): void {
  switch (cmd) {
    case "list": {
      const todo = listTickets().filter((t) => t.status === "in_progress");
      if (!todo.length) return console.log("작업할 차례인 요청이 없습니다.");
      for (const t of todo) {
        const stage = t.currentStage as WorkStage;
        const st = t.stages[stage];
        console.log(`■ ${t.id} ${t.title}`);
        console.log(`  단계: ${TEAM[stage].name} (${TEAM[stage].agent}) / 상태 ${st.status} / ${st.attempts + 1}회차`);
        console.log(`  폴더: ${path.join(WORK_DIR, t.id)}  산출물: ${STAGE_FILES[stage].docs.join(", ")}`);
        if (st.directive) console.log(`  팀장 수정 지시(반드시 반영): ${st.directive}`);
        const prev = st.directives.slice(0, -1);
        if (prev.length) console.log(`  이전 지시: ${prev.map((d) => d.text).join(" / ")}`);
      }
      return;
    }
    case "start":
      startStage(id);
      return console.log(`${id}: 작업 시작으로 표시했습니다.`);
    case "report": {
      const summary = opt("summary");
      if (!summary) throw new Error("--summary 가 필요합니다.");
      const decision = opt("decision") === "revise" ? "revise" : "approve";
      reportStage(id, { decision, summary, feedback: opt("feedback") ?? "", send_back_to: opt("send-back") as StageKey | undefined });
      return console.log(`${id}: 팀장에게 보고했습니다 (승인 대기).`);
    }
    case "fail":
      failStage(id, rest.join(" ") || "사유 미기재");
      return console.log(`${id}: 실패로 기록했습니다.`);
    default:
      console.log("사용법: node src/cli.ts list | start <id> | report <id> --summary ... | fail <id> <사유>");
  }
}

try {
  main();
} catch (e) {
  console.error((e as Error).message);
  process.exit(1);
}
