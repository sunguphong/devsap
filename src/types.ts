export const STAGES = ["analysis", "design", "development", "test", "deploy"] as const;
export type StageKey = (typeof STAGES)[number];
export type WorkStage = Exclude<StageKey, "deploy">;
export const WORK_STAGES = STAGES.slice(0, 4) as WorkStage[];

export const TEAM: Record<StageKey | "lead", { name: string; role: string; agent?: string }> = {
  lead: { name: "PL", role: "Claude Code. 담당자 작업 지시, 산출물 1차 검토, 팀장 보고" },
  analysis: { name: "요구사항 분석 담당", role: "현업 요청을 기능/비기능 요구사항으로 정리", agent: "sap-analyst" },
  design: { name: "설계 담당", role: "개발 오브젝트·데이터 흐름·처리 로직 설계", agent: "sap-designer" },
  development: { name: "개발 담당", role: "ABAP 소스 작성", agent: "sap-developer" },
  test: { name: "테스트 담당", role: "테스트 시나리오·ABAP Unit 작성, 코드 리뷰", agent: "sap-tester" },
  deploy: { name: "적용", role: "개발계 생성·활성화·단위테스트 실행 (ADT)" },
};

export type StageStatus = "pending" | "running" | "review" | "approved" | "failed";

export type TicketStatus =
  | "in_progress" // Claude Code가 현재 단계를 작업할 차례
  | "awaiting_review" // 단계 보고 후 팀장 승인 대기
  | "awaiting_deploy" // 개발계 반영 승인 대기
  | "deploying" // 개발계 반영 중
  | "done"
  | "failed"; // 개발계 반영 실패

// PL(Claude Code)의 1차 검토 보고. 다음 단계 진행은 팀장(사용자)이 결정한다.
export interface LeadReview {
  decision: "approve" | "revise";
  send_back_to: WorkStage;
  feedback: string;
  summary: string;
}

export interface StageState {
  status: StageStatus;
  review: LeadReview | null;
  attempts: number;
  directive: string | null; // 재작업 대기 중인 팀장 수정 지시
  directives: { at: string; text: string }[]; // 팀장 수정 지시 이력
  startedAt?: string | null; // 처음 작업을 시작한 시각 (재작업해도 유지)
  endedAt?: string | null; // 팀장 승인(반영은 반영 완료) 시각. 다시 열리면 null
  verifications?: Verification[]; // 팀장이 요청한 AI 검증 이력 (승인 여부는 팀장이 정한다)
}

// 팀장이 승인 전에 맡기는 독립 AI 검증 (읽기 전용 헤드리스 세션). 단계 상태는 바꾸지 않는다.
export interface VerifyCheck {
  item: string; // 검증 항목
  result: "ok" | "warn" | "issue";
  detail: string; // 근거 (파일·위치 포함)
}

export interface Verification {
  at: string;
  attempt: number; // 검증한 산출물 회차 (stages[*].attempts)
  status: "running" | "done" | "failed";
  verdict?: "pass" | "warn" | "fail";
  summary?: string;
  checks?: VerifyCheck[];
  directive?: string; // 문제가 있을 때 수정 지시 초안
  send_back_to?: WorkStage; // 수정 지시를 내릴 단계 (원인이 앞 단계일 수 있음)
  error?: string | null;
}

export interface LogEntry {
  at: string;
  agent: string;
  text: string;
}

export interface DeployConfig {
  package: string;
  transport: string;
}

export interface DeployResult {
  mode: string;
  ok: boolean;
  text: string;
}

export interface Lessons {
  at: string;
  docs: { title: string; action: "created" | "updated"; summary: string }[];
}

// 진행 중에 팀장이 등록하는 요구사항 변경(CR). PL이 영향 단계를 분석해 권고하고 팀장이 반영 여부를 정한다.
export type ChangeStatus =
  | "analyzing" // PL 영향분석 중
  | "proposed" // 영향분석 완료, 팀장 결정 대기
  | "applied" // 반영 (해당 단계부터 재작업 또는 다음 단계 작업 때 반영)
  | "deferred" // 다음 차수로 미룸
  | "rejected"
  | "failed"; // 영향분석 실패

export interface ChangeImpact {
  from: WorkStage; // 영향받는 가장 앞 단계
  effort: "small" | "medium" | "large";
  summary: string; // 팀장 보고용 영향 설명
  directive: string; // from 단계 담당자에게 줄 수정 지시 초안
}

export interface ChangeRequest {
  id: string; // CR-01
  at: string;
  text: string;
  status: ChangeStatus;
  impact: ChangeImpact | null;
  error?: string | null;
  appliedTo?: WorkStage | null; // 실제 반영한 단계 (팀장이 바꿀 수 있음)
  decidedAt?: string | null;
}

export interface Ticket {
  id: string;
  title: string;
  status: TicketStatus;
  currentStage: StageKey;
  stages: Record<StageKey, StageState>;
  revisionCount: number;
  deployConfig: DeployConfig | null;
  deployResult: DeployResult | null;
  lessons?: Lessons | null; // PL이 지식 위키에 정리한 배운 점
  changes?: ChangeRequest[]; // 진행 중 요구사항 변경 요청
  system?: string | null; // 작업 대상 SAP 시스템 (등록된 ABAP MCP 서버 이름). 없으면 보드 기본 시스템
  logs: LogEntry[];
  createdAt: string;
  updatedAt: string;
}
