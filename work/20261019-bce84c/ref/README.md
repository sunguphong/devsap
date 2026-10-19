# 현행 소스 참고본 (srd-abap, 클라이언트 250, 2026-10-19 PL 조회)

개발 담당에게는 인클루드 조회 도구(GetInclude/GetProgram)가 없으므로 PL이 mcp__sap__GetInclude / GetProgram 으로 조회한 현행 소스를 저장했다.
- SAPMZMM0020.abap (메인), MZMM0020TOP / ALV / F02 / I01 / O01 : 원문 그대로
- MZMM0020F01.abap : 원문 전체 (1차 개발 후 요약본 → 전체 원문으로 교체)
- MZMM0020ALV.abap : CHECK_ZCUSTM 메서드 본문(전부 주석)만 생략. MZMM0020F02.abap : 일부 FORM 줄바꿈 압축(내용 동일). 두 인클루드는 이번 개발 변경 대상 아님

## ZEMM2222 (SAPMZMM2222, $TMP) 현행 소스 — 2026-10-19 PL 재조회 (팀장 지시로 대상 변경)
- SAPMZMM2222.abap, MZMM2222TOP / I01 / O01 .abap : 원문 그대로 저장
- MZMM2222ALV / F01 / F02 : PL이 GetInclude로 전문을 읽어 대조한 결과, 위 MZMM0020ALV / F01 / F02와 로직·FORM·변수명이 같다(헤더 주석도 'MZMM0020'으로 남아 있음). 별도 파일은 만들지 않았으므로 MZMM0020ALV/F01/F02.abap 을 MZMM2222 내용으로 보면 된다.
- 차이: 메인 프로그램이 REPORT SAPMZMM2222 MESSAGE-ID ZMMM, INCLUDE MZMM2222TOP/ALV/F02/O01/I01/F01 (MZMM0020* INCLUDE 줄은 주석). 화면 100, GUI 상태 '0100', 타이틀 '0100'은 SAPMZMM2222 소속(화면·GUI 상태 내용은 MCP로 조회 불가, SAPMZMM0020 복사본으로 추정).
- 아래 표의 사실은 ZEMM2222에도 그대로 적용된다.

## 설계서(02_design.md)와 다른 실제 사실 (AI 검증 결과, 팀장 승인 시점에 반영 지시 미완)
| 설계서 표기 | 실제 |
|---|---|
| LCL_EVENT_HANDLER | LCL_EVENT_RECEIVER (인스턴스 EVENT_RECEIVER) |
| go_grid | GRID (TYPE REF TO CL_GUI_ALV_GRID) |
| ALV 출력 테이블 (미확인) | GT_PR (OCCURS 0, 헤더라인, INCLUDE STRUCTURE ZSMM0015 + COLTAB/STYTAB/DBDATA) |
| 등급명 | BTEXT (ZTMM0014 조인) |
| 단가 | DANGA (ZTMM0015-DANGA), 통화 WAERS, 가격단위 KPEIN |
| 효력시작일 | DATAB (화면 라벨 '유효시작일') |
| 비고 | GT_PR에 비고 필드 없음 → 항상 공란 |
| 툴바 버튼 | CREATE_EVENT_RECEIVER에서 HANDLE_TOOLBAR SET HANDLER와 SET_TOOLBAR_INTERACTIVE가 주석 처리 → 기존 버튼(SAVE/COPY/DEL/CREA/TOGG/GRAD)은 GUI 상태 '0100' + USER_COMMAND_0100(SAVE_OK)에서 처리 |
| SEL_MODE | 이미 'A' (변경 불필요) |
| 편집형 | gs_layout-edit = 'X', TOGG로 입력 가능 전환. 기존 COPY/DEL은 grid->check_changed_data 후 get_selected_rows |
| 권한/버튼 노출 | SET_PF_STATUS: PA0001-ORGEH = '10005020'(스크럽구매팀) 또는 SY-UNAME(2)='DU' 기준으로 버튼 제외 |
| 메시지 | REPORT ... MESSAGE-ID ZMMM, 기존은 MESSAGE s000 WITH '...' 사용 |
| ×100 근거 | SAVE_DATA 주석: '경량B 단가 300원/kg 이상' → lv_kb5_danga >= 3 (DANGA 내부값 = 원/kg의 1/100) |
