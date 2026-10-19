# devsap 작업 규칙

웹 보드(http://localhost:3300, `npm start`)에서 팀장(사용자)이 승인·수정 지시를 내리면, 서버가 Claude Code를 헤드리스(`claude -p`, src/runner.ts)로 띄워 현재 단계를 작업시킨다. 헤드리스 세션이 PL 역할로 서브에이전트를 실행하고 1차 검토 결과를 구조화된 출력으로 돌려주면, 서버가 보드에 보고로 기록한다. 팀장이 승인해야 다음 단계로 넘어간다.

- 단계별 서브에이전트: 분석 `sap-analyst` → 01_analysis.md / 설계 `sap-designer` → 02_design.md / 개발 `sap-developer` → src/*.abap + 03_development.md / 테스트 `sap-tester` → 04_test.md + src/*.testclasses.abap
- 한 번에 한 단계만 작업하고 보고 후 멈춘다. revise 권고여도 스스로 재작업하지 않는다.
- `work/<ID>/ticket.json`을 직접 고쳐 팀장 승인을 건너뛰지 않는다.
- 진행 중 요구사항 변경(CR, src/changes.ts): 팀장이 보드에서 등록하면 PL 읽기 전용 세션이 영향받는 가장 앞 단계를 권고하고, 팀장이 반영하면 그 단계부터 수정 지시로 다시 작업한다. 반영된 CR은 모든 단계 프롬프트에 요구사항 기준선으로 들어가며, 산출물 변경 이력에 CR 번호를 남긴다.
- 요청 첨부 자료(src/attachments.ts): `work/<ID>/attachments/`, 요구사항 변경 첨부는 `work/<ID>/changes/<CR-xx>/` (CR 영향분석·반영 지시·단계 프롬프트에 경로가 함께 들어간다). 이미지·PDF·텍스트는 Read로 직접 읽고, docx/xlsx/pptx는 서버가 뽑아 둔 `attachments/.text/<파일명>.txt`를 읽는다. DRM(문서보안) 파일은 업로드 때 거부한다.
- AI 검증(src/verify.ts): 팀장이 보드에서 요청하면 작업 PL과 별개인 읽기 전용 세션이 단계 산출물을 검증해 `stages[*].verifications`에 남긴다. 참고용이며 승인·수정 지시는 팀장이 한다.
- SAP 시스템(src/systems.ts): 보드 상단 드롭다운에서 등록된 ABAP MCP 서버 중 하나를 고른다. 헤드리스 세션에는 그 서버만 `sap` 이름으로 붙으므로 에이전트는 `mcp__sap__*` 도구로 조회한다. 개발계 반영도 같은 서버의 접속 정보를 쓴다.
- 개발계 반영은 팀장이 보드에서 승인했을 때 웹앱이 ADT로 수행한다. 운영계 반영은 하지 않는다.

## 터미널에서 수동으로 진행할 때 (보조)
`node src/cli.ts list` → `start <ID>` → 서브에이전트 실행 → `report <ID> --summary "..." --decision approve|revise [--feedback ...] [--send-back <단계>]` (실패 시 `fail <ID> "<사유>"`)

## 지식 위키 (wiki/)
- 분석~테스트가 모두 승인되거나 개발계 반영이 끝나면 서버가 PL 헤드리스 세션(src/lessons.ts)으로 배운 점을 주제별 문서(wiki/<제목>.md)로 정리한다. 이 세션의 쓰기 권한은 wiki/ 로 제한된다.
- 요청 단위 회고가 아니라 주제 단위로 쓰고, 기존 문서가 있으면 보강한다. 바뀐 문서의 이전 버전은 서버가 wiki/.history/ 에 보관한다.
