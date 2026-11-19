# 02. 설계서 - 자재 리스트 조회 펀션 신규 개발

- 요청 ID: 20261119-f26e72
- 작성: sap-designer (설계 1차 작업, 팀장 수정 지시 없음)
- 작성일: 2026-11-19
- 입력: `request.md`, `01_analysis.md`(팀장 승인본), 분석 승인 시 AI 검증 주의 사항 3건(참고)
- 첨부 자료: 없음
- 개발표준: `standards/handbook.md` (Dongkuk Steel ABAP 개발표준 Handbook)
- 참고 wiki: "ECC 7.40 시스템 ABAP 개발 제약", "SAP 시스템 미확인 상태에서 작업하는 방법", "자재마스터 조회 리포트 설계 패턴", "테스트계 반영 전 점검 항목"
- 조회 시스템: mrd-abap-rw (클라이언트 350), `mcp__sap__*` 읽기 전용 조회만 함

### 근거 표기 규칙

| 표기 | 의미 |
|---|---|
| **[확인]** | 이 설계 세션이 mrd-abap-rw에서 SearchObject로 직접 확인함 |
| **[분석확인]** | 분석 단계가 시스템에서 확인했고 설계에서 다시 조회하지 않음 |
| **[미확인(표준 기준)]** | 시스템 도구로 읽을 수 없어 SAP ECC 표준 지식으로 씀. 활성화·SE11·SU21 등으로 확인 필요 |
| **[가정]** | 분석 가정 또는 설계 가정. 현업 답(Q)에 따라 바뀔 수 있음 |
| **[추가]** | 요청 원문에 없는 **현업 확인 전 추가 기능**(AI 검증 주의 2 반영) |

---

## 0. 설계 전 확인 결과

### 0.1 시스템 조회 결과 (2026-11-19)

| 대상 | 도구 | 결과 |
|---|---|---|
| 함수 그룹 `ZFGMM*` | SearchObject (FUGR) | [확인] ZFGMM00~33, 35~38, 41~70, 80, 91, 92, ZFGMM_ADDR 존재(모두 ZMMD). **ZFGMM34·39·40·71~79 없음**. `ZFGMM7*` 검색 결과는 ZFGMM70 1건뿐 |
| ZFGMM41 | SearchObject | [확인] "MM Common Function", ZMMD. 소속 FM과 전역 데이터는 읽을 수 없음(아래 0.2) |
| FM 이름 `Z_MM_GET_MAT*` | SearchObject | [확인] `Z_MM_GET_MATNR`(강종·두께그룹·폭그룹으로 자재번호 발췌), `Z_MM_GET_MATNR_SUB`(부자재 자재코드 채번)만 있음. **`Z_MM_GET_MATERIAL_LIST` 없음** |
| 메시지 클래스 `ZMMM*` | SearchObject (MSAG) | [확인] ZMMM("ZMM Message Class"), ZMMM1("User Exit용"), ZMMM2("[MM] Message Class") 존재(ZMMD). **ZMMM3 없음** |
| 구조 `ZSMM*` | SearchObject | [확인] ZSMM0000~ZSMM3538, ZSMM4000~4870, ZSMM5001~5510, ZSMM9001~9999 사이에 다수 사용. **`ZSMM36*` 결과 없음** |
| 테이블 타입 | SearchObject (TTYP) | [확인] 팀 사례: `ZTMM2200`(=구조 ZSMM2200의 테이블 타입), `ZSTMM0266`, `ZTMM_ATTACH`. **`ZTTMM*` 결과 없음** |
| 클래스 `ZCL_MM_MAT*`, `ZCL_MM_MTART*` | SearchObject | [확인] `ZCL_MM_MATERIAL_LIST`($TMP, 자재마스터 조회 리포트 로직)만 있음. **`ZCL_MM_MTART*` 없음** |
| 재사용 후보 FM 위치 | SearchObject (detail full) | [확인] `Z_MM_MP_SELECT_MATNR_DATA` → 함수 그룹 **ZFGMM25**("[MM] 통합구매 Function Group"), `Z_MD_MIGMAT_LIST_GET` → 함수 그룹 **ZFGMD98**(패키지 ZMDD) |
| 사용 타입 | SearchObject | [확인] `XFELD`(DTEL "체크박스"), `INT4`(DTEL "정수"), `CL_ABAP_MATH`(SABP_CORE) 존재. [분석확인] MTART·MATNR·MAKTX·MEINS·SPRAS·LVOMA DTEL, BAPIRET2, M_MATE_MAR, MARA·MAKT·T134 존재 |

### 0.2 읽지 못한 것 (시도한 도구와 오류)

| 대상 | 시도 | 결과 | 넘긴 곳 |
|---|---|---|---|
| `Z_MM_MP_SELECT_MATNR_DATA`, `Z_MD_MIGMAT_LIST_GET` 인터페이스·소스 | GetProgram `SAPLZFGMM25`, `LZFGMM25UXX`, `LZFGMD98UXX` | 404 `Resource PROGRAM ... does not exist` (함수 그룹·인클루드는 `/programs/programs/` 경로가 아님. FM 소스 조회 도구 없음) | C-04 |
| MARA·MAKT·T134 필드 길이, MARA 인덱스 | (분석 단계) GetTable·GetTypeInfo | 404 `ExceptionResourceNotFound` — 7.50 미만 ADT 제약 | C-01, C-02 |
| M_MATE_MAR 권한 필드 | 도구 없음 | 확인 불가 | C-03 |
| ZMMM2·ZMMM 메시지 번호 사용 현황 | 도구 없음 | 확인 불가 | 6.2 결정 근거 |

### 0.3 개발계 반영 도구 제약 (설계에 영향)

- 웹앱 개발계 반영(src/board.ts, src/adt.ts)은 `src/*.abap`을 **CLAS / PROG / INCL 세 유형으로만** 판별해 올립니다. `CLASS ... DEFINITION`이 없는 파일은 PROG 또는 INCL로 생성을 시도합니다. [확인: 프로젝트 소스]
- 따라서 **함수 그룹·FM·DDIC 구조·테이블 타입·메시지는 웹앱으로 반영할 수 없습니다.** FM 소스를 `src/`에 두면 FM 이름의 인클루드 생성이 시도되어 반영이 실패합니다(wiki "테스트계 반영 전 점검 항목": src/에는 웹앱이 반영할 ABAP 소스 오브젝트만 둠).
- 설계 결정: **핵심 로직은 전역 클래스(웹앱 반영 가능, ABAP Unit 대상)에 두고, FM은 클래스를 호출만 하는 얇은 래퍼**로 둡니다. FM 소스는 `work/20261119-f26e72/manual/`에 두고 SE37에서 수작업으로 반영합니다(10장 반영 순서).

---

## 1. 개요

- **목적**: 자재유형(MTART)을 입력받아 그 유형의 **자재코드(MARA-MATNR), 자재내역(MAKT-MAKTX), 기본단위(MARA-MEINS)** 목록을 돌려주는 함수 모듈 `Z_MM_GET_MATERIAL_LIST`를 만듭니다(request.md). 화면(리포트·ALV)은 없습니다.
- **구성(최소 오브젝트)**: 함수 그룹 `ZFGMM71` 1개, FM `Z_MM_GET_MATERIAL_LIST` 1개, 로직 클래스 `ZCL_MM_MTART_MATLIST` 1개, 출력용 DDIC 구조 `ZSMM3600`·테이블 타입 `ZTTMM3600`, 메시지 클래스 `ZMMM3`(메시지 6개). 신규 DB 테이블, 스키마 변경, T-code는 없습니다.
- **처리 요약**: 입력 정규화 → 입력 누락 검사 → T134 존재 검사 → (자재유형에 권한그룹이 있으면) 권한 점검 → MARA 조회 → MAKT 내역 결합(FOR ALL ENTRIES) → 자재코드 순 정렬·최대 건수 적용 → `ET_LIST`, `EV_COUNT`, `ES_RETURN`(BAPIRET2) 반환.
- **범위 결정 요약** (요청 범위 밖 기능 = [추가], 3장 상세)

| 분석 FR | 설계 결정 | 구분 |
|---|---|---|
| FR-01, 03~07 | 포함 | 요청 범위(FR-03·06·07의 세부 규칙은 [가정]) |
| FR-02 자재유형 범위 입력 | **1차 개발 제외** (Q2 답이 "여러 개"면 선택 파라미터 추가) | [추가] |
| FR-05 `IV_SPRAS` 언어 파라미터 | 포함(선택, 기본 SY-LANGU) | [추가] |
| FR-08 삭제 자재 기본 제외 | 포함(`IV_WITH_DELETED`, 기본 공란 = 제외) — **결과 건수에 영향**, 3.2 | [추가] |
| FR-09 최대 건수 | 포함(`IV_MAX_ROWS`, 기본 0 = 제한 없음) | [추가] |
| FR-10 자재유형 권한 | 포함(T134-BEGRU가 있을 때만 점검) | [추가] |
| FR-11 RFC 가능 | 포함(Remote-Enabled, 값 전달) | [추가] |

- **대상 릴리스**: ECC, SAP_BASIS 7.40 SP09 이상·7.50 미만 추정(분석서 A-11, wiki). MATNR 18자리. 사용 구문의 최소 SP는 9장에 적습니다.

---

## 설계 다이어그램

### 1) 프로그램 구조도

```mermaid
classDiagram
  class CALLER {
    <<caller>>
    ABAP 프로그램 또는 외부 시스템 RFC
  }
  class ZFGMM71 {
    <<function group>>
  }
  class Z_MM_GET_MATERIAL_LIST {
    <<function module RFC>>
    +IV_MTART
    +IV_SPRAS
    +IV_WITH_DELETED
    +IV_MAX_ROWS
    +ET_LIST
    +EV_COUNT
    +ES_RETURN
  }
  class ZCL_MM_MTART_MATLIST {
    +constructor(iv_mtart iv_spras iv_with_deleted iv_max_rows)
    +execute() et_list ev_count es_return
    +normalize_mtart(iv_mtart)$ mtart
    +normalize_spras(iv_spras)$ spras
    +normalize_max_rows(iv_max_rows)$ i
    +build_lvorm_range(iv_with_deleted)$ range
    +get_up_to_rows(iv_max_rows)$ i
    +build_list(it_mara it_makt iv_max_rows)$
    +decide_return(iv_mtart iv_count iv_truncated iv_max_rows)$ bapiret2
    +make_return(iv_type iv_number iv_v1 iv_v2)$ bapiret2
    -check_mtart() found begru
    -check_authority(iv_begru) subrc
    -read_mara() tt_mara
    -read_makt(it_mara) tt_makt
  }
  class LTCL_MTART_MATLIST {
    <<test class CCAU>>
  }
  CALLER --> Z_MM_GET_MATERIAL_LIST : CALL FUNCTION
  ZFGMM71 *-- Z_MM_GET_MATERIAL_LIST
  Z_MM_GET_MATERIAL_LIST --> ZCL_MM_MTART_MATLIST : NEW 후 execute
  LTCL_MTART_MATLIST ..> ZCL_MM_MTART_MATLIST : 정적 메서드와 가드 테스트
```

### 2) 처리 흐름도

```mermaid
flowchart TD
  S1["1 FM 호출 - 파라미터 수신"] --> S2["2 입력 정규화 constructor"]
  S2 --> D1{"3 자재유형 입력됨?"}
  D1 -->|아니오| E1["RETURN E 001 입력 누락"]
  D1 -->|예| S4["4 T134 존재 검사"]
  S4 --> D2{"T134에 있음?"}
  D2 -->|아니오| E2["RETURN E 002 잘못된 자재유형"]
  D2 -->|예| D3{"5 T134-BEGRU 있음?"}
  D3 -->|예| S5["M_MATE_MAR 권한 점검 ACTVT 03"]
  S5 --> D4{"권한 있음?"}
  D4 -->|아니오| E3["RETURN E 003 권한 없음"]
  D4 -->|예| S6
  D3 -->|아니오| S6["6 MARA 조회 MTART LVORM UP TO"]
  S6 --> D5{"결과 있음?"}
  D5 -->|아니오| E4["RETURN W 004 데이터 없음"]
  D5 -->|예| S7["7 MAKT 조회 FOR ALL ENTRIES"]
  S7 --> S8["8 결과 조립 정렬 최대건수 자르기"]
  S8 --> D6{"잘림?"}
  D6 -->|예| R2["9 RETURN W 006 잘림 경고"]
  D6 -->|아니오| R1["9 RETURN S 005 n건 조회"]
  E1 --> OUT["ET_LIST EV_COUNT ES_RETURN 반환"]
  E2 --> OUT
  E3 --> OUT
  E4 --> OUT
  R1 --> OUT
  R2 --> OUT
```

### 3) 데이터 관계도

```mermaid
erDiagram
  T134 ||--o{ MARA : "T134.MTART = MARA.MTART"
  MARA ||--o| MAKT : "MARA.MATNR = MAKT.MATNR, MAKT.SPRAS = 입력 언어"
  T134 {
    CHAR4 MTART PK
    CHAR4 BEGRU
  }
  MARA {
    CHAR18 MATNR PK
    CHAR4 MTART
    UNIT3 MEINS
    CHAR1 LVORM
  }
  MAKT {
    CHAR18 MATNR PK
    LANG1 SPRAS PK
    CHAR40 MAKTX
  }
```

(필드 형식은 [미확인(표준 기준)]. 테이블 존재만 [분석확인].)

---

## 예상 화면

**화면 없음.** 이 오브젝트는 화면이 없는 함수 모듈입니다(분석서 A-01).

- 실행 방법(개발·테스트): SE37 → `Z_MM_GET_MATERIAL_LIST` → 테스트/실행(F8) → `IV_MTART` 등 입력 → 실행 → `ET_LIST`·`EV_COUNT`·`ES_RETURN` 확인. RFC 확인은 SE37 테스트 화면의 "RFC 목적지"에 `NONE`을 넣어 실행합니다(AC-12).
- 운영 호출: 다른 ABAP 프로그램의 `CALL FUNCTION 'Z_MM_GET_MATERIAL_LIST'` 또는 외부 시스템의 RFC 호출(Q1). 백그라운드 잡(SM36) 대상이 아닙니다.
- 사용자에게 보이는 결과는 `ES_RETURN`의 메시지뿐이며, 메시지 목록은 7장 표에 있습니다.

---

## 2. 개발 오브젝트 목록

| No | 유형 | 이름 | 신규/재사용 | 목적 | 명명 근거 | 반영 방법 |
|---|---|---|---|---|---|---|
| O-01 | 패키지 (DEVC) | `ZMMD` | 재사용 | MM 개발 패키지 | 핸드북 Z+MM+D, wiki에서 실재 확인 | — |
| O-02 | 함수 그룹 (FUGR) | `ZFGMM71` | **신규** | RFC 노출 자재 조회 FM 전용 그룹. 내역: "[MM] 자재마스터 조회 공통(RFC)" | 핸드북 Z+FG+MM+2자리. ZFGMM70 다음 빈 번호 [확인] | SE80/SE37 수작업 |
| O-03 | 함수 모듈 (FUNC) | `Z_MM_GET_MATERIAL_LIST` | **신규** | 자재유형별 자재 리스트 조회. Remote-Enabled. 내역: "[MM] 자재유형별 자재코드·내역·기본단위 조회" | 핸드북 Z_+서술어 [확인: 동명 없음] | SE37 수작업. 소스는 `manual/Z_MM_GET_MATERIAL_LIST.fm.abap` |
| O-04 | 클래스 (CLAS) | `ZCL_MM_MTART_MATLIST` | **신규** | 검증·조회·조립 로직, ABAP Unit 대상. 내역: "[MM] 자재유형별 자재 리스트 조회 로직" | 핸드북 규칙 없음 — SAP 관례 적용(`ZCL_<모듈>_<서술>`) [확인: 동명 없음] | 웹앱 개발계 반영 (`src/ZCL_MM_MTART_MATLIST.abap` + `.testclasses.abap`) |
| O-05 | 구조 (TABL/DS) | `ZSMM3600` | **신규** | `ET_LIST` 행 구조: MATNR, MAKTX, MEINS. 내역: "[MM] 자재유형별 자재 리스트(Z_MM_GET_MATERIAL_LIST)" | 핸드북 Z+S+MM+4자리. `ZSMM36*` 비어 있음 [확인] | SE11 수작업 |
| O-06 | 테이블 타입 (TTYP) | `ZTTMM3600` | **신규** | `ET_LIST` 타입, 행 타입 ZSMM3600 | 핸드북 규칙 없음 — SAP 관례(`ZTT_` 계열) 적용. 팀 사례 `ZTMM2200`처럼 `ZT`+`MM`+번호를 쓰면 핸드북의 DB 테이블 규칙(ZTMM####)과 이름 공간이 겹쳐 피함. 구조 번호와 맞춤 [확인: ZTTMM* 없음] | SE11 수작업 |
| O-07 | 메시지 클래스 (MSAG) | `ZMMM3` | **신규** | 메시지 001~006 (7장). 내역: "[MM] 자재마스터 조회 공통 메시지" | 핸드북 Z+M+MM+1자리, ZMMM1·ZMMM2 다음 [확인] | SE91 수작업 |
| — | 표준 재사용 | MARA, MAKT, T134, BAPIRET2, MTART/SPRAS/XFELD/INT4/MATNR/MAKTX/MEINS DTEL, M_MATE_MAR, CL_ABAP_MATH | 재사용 | 데이터 원천·타입·권한 | — | — |

- 이송요청: SE09에서 별도 생성(팀장·Basis). 위 O-02~O-07을 같은 이송요청에 담습니다. `$TMP` 금지(wiki).
- 개발 산출물 위치(개발 담당 지시): `src/`에는 **O-04 클래스 파일 2개만** 둡니다. FM 소스·DDIC 정의·메시지 텍스트는 `manual/`과 03_development.md 표로 둡니다.

### 2.1 설계 단계에서 결정한 항목 (AI 검증 주의 3 반영)

| 항목 | 결정 | 근거 |
|---|---|---|
| **Q9 함수 그룹** | 기존 `ZFGMM41`에 넣지 않고 **신규 `ZFGMM71`** | ① RFC 권한(S_RFC)은 함수 그룹 단위로 부여되므로, RFC 계정에 이 FM만 열려면 전용 그룹이 필요합니다(ZFGMM41에 넣으면 그룹 안 다른 FM까지 함께 열리거나, 이 FM 때문에 ZFGMM41 전체를 열어야 함). ② ZFGMM41의 전역 데이터·소속 FM을 읽을 수 없어(0.2) 기존 그룹 메인 프로그램 재활성화 영향을 판단할 수 없습니다. ③ 팀에서도 I/F 용도별로 그룹을 나눠 왔습니다(ZFGMM01 Maximo, 03 MES, 17 업체소싱 RFC 등 [확인]). 단점은 오브젝트 1개 증가뿐입니다. 팀 표준상 ZFGMM41을 써야 하면 FM만 옮기면 되고 클래스는 바뀌지 않습니다 |
| **Q10 기존 FM 재사용** | **신규 개발** (재사용 안 함) | `Z_MM_MP_SELECT_MATNR_DATA`는 통합구매 그룹(ZFGMM25) 소속이고 내역이 "자재-플랜트, 기본단위 조회"라 플랜트 단위·통합구매 용도로 보입니다. `Z_MD_MIGMAT_LIST_GET`은 ZMDD 패키지·ZFGMD98 그룹이고 이름(MIGMAT)상 마이그레이션 용도로 보입니다. 둘 다 인터페이스를 읽지 못해(0.2) 그대로 쓸 수 있다는 근거가 없고, 다른 용도 FM에 의존하면 그쪽 변경이 이 기능에 번집니다. `BAPI_MATERIAL_GETLIST`는 반환 구조에 기본단위가 없는 것으로 알려져 있어(표준 지식, [미확인(표준 기준)]) 단위를 따로 읽어야 합니다. 개발 착수 전 SE37로 두 Z FM을 확인(C-04)해 **입력이 자재유형이고 출력에 자재코드·내역·기본단위가 모두 있으면** 팀장에게 재사용 여부를 다시 묻습니다 |
| 메시지 클래스 | 신규 `ZMMM3` | ZMMM·ZMMM2의 빈 번호를 도구로 확인할 수 없어 번호 충돌 위험이 있습니다. 메시지 ID·번호는 클래스 상수(`C_MSGID`, `C_MSG_*`)로만 쓰므로, 팀장이 기존 클래스(예: ZMMM2) 재사용을 원하면 상수만 바꾸면 됩니다. 메시지 생성은 시스템 쓰기라 SE91 수작업(팀장 승인 후) |
| FM 래퍼 + 클래스 분리 | 채택 | 웹앱이 FM을 반영할 수 없고(0.3), FM 안의 로직은 ABAP Unit 대상으로 만들기 어렵습니다. FM은 클래스 호출 3줄만 둡니다 |
| DAO 인터페이스 주입 | 채택하지 않음 | 웹앱은 클래스를 FINAL로 만들고 main·testclasses 인클루드만 올립니다(전역 인터페이스·로컬 타입 인클루드 반영 불가). 대신 **조립 로직을 DB 없는 정적 메서드 `build_list`로 빼서** MARA·MAKT 행을 입력으로 넣어 테스트합니다(wiki 리뷰 I4의 목적을 다른 방법으로 달성) |

---

## 3. FM 인터페이스 상세

### 3.1 `Z_MM_GET_MATERIAL_LIST` 파라미터

속성: 처리 유형 **Remote-Enabled Module** [추가, Q1], 업데이트 모듈 아님. 전달 방식은 **전부 값 전달(Pass Value)** — RFC 필수 조건. TABLES·CHANGING·EXCEPTIONS 없음.

| 구분 | 파라미터 | 타입 (TYPE) | 선택 | 기본값 | 설명 | FR | 구분 |
|---|---|---|---|---|---|---|---|
| IMPORTING | `IV_MTART` | `MTART` | 필수(Optional 해제) | — | 자재유형. 공란 값으로 호출하면 E 001 반환 | FR-01 | 요청 |
| IMPORTING | `IV_SPRAS` | `SPRAS` | 선택 | `SY-LANGU` | 자재내역 언어. 공란이면 SY-LANGU (RFC 호출이면 RFC 로그온 언어) | FR-05 | [추가] |
| IMPORTING | `IV_WITH_DELETED` | `XFELD` | 선택 | `SPACE` | 'X' = 삭제 표시 자재(MARA-LVORM='X') 포함. 공란 = 제외 | FR-08 | [추가] |
| IMPORTING | `IV_MAX_ROWS` | `INT4` | 선택 | `0` | 최대 반환 건수. 0 또는 음수 = 제한 없음 | FR-09 | [추가] |
| EXPORTING | `ET_LIST` | `ZTTMM3600` | — | — | 결과 목록(MATNR 오름차순). 오류 시 빈 테이블 | FR-04~06 | 요청 |
| EXPORTING | `EV_COUNT` | `INT4` | — | — | `ET_LIST` 건수 | FR-06 | [가정] |
| EXPORTING | `ES_RETURN` | `BAPIRET2` | — | — | 처리 결과 단건(7장) | FR-07 | [가정] |

- FR-02(`IT_MTART_RANGE`)는 1차 개발에서 **제외**합니다. 요청 원문은 "자재유형을 입력값을 받고"(단수)이고 최소 오브젝트 원칙에 따릅니다. Q2 답이 "여러 개"면 선택 IMPORTING 파라미터를 뒤에 추가합니다(선택 파라미터 추가는 기존 호출측과 호환). 그때 범위 타입은 분석서 후보(`MD_RANGE_T_MTART` 등)의 행 구조를 SE11로 확인한 뒤 고릅니다.
- EXPORTING 테이블 타입은 RFC에서 쓸 수 있습니다. 호출측이 구형 RFC 라이브러리라 TABLES가 필요하면(Q1) `TABLES` 파라미터를 따로 추가해야 하므로 Q1 답을 받은 뒤 결정합니다.
- 기본값을 FM 인터페이스에 둔 이유: SE37 테스트와 호출측이 기본 동작을 바로 볼 수 있게 하기 위해서입니다. 클래스 constructor도 같은 정규화를 해서(4.2) FM 밖에서 호출해도 결과가 같습니다.

### 3.2 FR-08 삭제 자재 기본 제외 — 결정 근거와 Q3에 따라 바뀌는 지점 (AI 검증 주의 2)

- **기본값 결정 근거**: 분석 가정 A-04를 따릅니다. 삭제 표시(MARA-LVORM='X') 자재는 보관(아카이빙) 대상이며 구매·재고 업무에 쓰지 않는 자재이므로, "조회해서 쓰는 목록"에서는 빼는 쪽을 기본으로 둡니다. 호출측이 `IV_WITH_DELETED = 'X'`로 언제든 포함할 수 있어 정보 손실은 없습니다. **이 기본값은 요청 원문 근거가 없는 설계 가정**이며, 요청 문구만 보면 "자재유형의 모든 자재"로도 읽힙니다.
- **기준은 클라이언트 레벨 MARA-LVORM 하나**입니다. 플랜트 레벨 삭제(MARC-LVORM)는 보지 않습니다(플랜트 조건이 없는 FM이므로, 분석 A-03).
- **Q3 답에 따라 바뀌는 지점**

| Q3 답 | 바꿀 곳 | 영향 받는 테스트 |
|---|---|---|
| "제외" (현재 가정과 같음) | 없음 | — |
| "항상 포함" | FM 기본값 `IV_WITH_DELETED` = `'X'`로 변경(또는 파라미터 삭제). 클래스 `build_lvorm_range`는 그대로 | **AC-01 기대 건수 = SE16 MARA(MTART=값) 전체 건수**(LVORM 조건 제거), AC-08은 기본값 반대로, UT-05·06 변경 없음 |
| "선택 가능, 기본 포함" | FM 기본값만 `'X'` | AC-01 기대 건수 = 전체, AC-08 기본값 반대로 |

- AC-01 현재 기대 건수: **SE16 MARA에서 MTART = 값 AND LVORM ≠ 'X'** 건수. 테스트 문서에는 삭제 자재가 있는 자재유형을 골라 AC-01·AC-08을 같은 유형으로 확인해 차이(= 삭제 자재 수)를 기록합니다.

### 3.3 출력 DDIC

**구조 `ZSMM3600`** (Enhancement Category: "Can be enhanced (character-type or numeric)")

| 필드 | 구성 타입(Data Element) | 형식(표준 기준) | 설명 |
|---|---|---|---|
| MATNR | `MATNR` | CHAR 18, 변환루틴 MATN1 | 자재코드 (내부 형식, NFR-04·Q5) |
| MAKTX | `MAKTX` | CHAR 40 | 자재내역 |
| MEINS | `MEINS` | UNIT 3, 변환루틴 CUNIT | 기본단위 (내부 단위값, Q5) |

- 형식은 [미확인(표준 기준)]. Data Element를 참조하므로 길이는 시스템 정의를 따르며 SE11 활성화가 곧 확인 수단입니다.
- MEINS는 단위 필드 자체라 참조 필드가 필요 없습니다(수량 필드가 없음).

**테이블 타입 `ZTTMM3600`**: 행 타입 `ZSMM3600`, 접근 "표준 테이블", 키 "표준 키·비고유".

---

## 4. 클래스 `ZCL_MM_MTART_MATLIST` 설계

`PUBLIC FINAL CREATE PUBLIC`. 내부 명명은 핸드북 2장을 따릅니다(클래스 속성 = Global → `G_`, 로컬 `L_`/`LT_`/`LS_`, 상수 `C_`, 범위 `R_`). 메서드 파라미터(`IV_`/`EV_`/`IT_`/`ET_`/`RV_`/`RT_`/`RS_`), 타입(`TY_`/`TT_`), 객체 참조(`LO_`)는 **핸드북 규칙 없음 — SAP 관례 적용**.

### 4.1 공개 타입·상수·속성

| 구분 | 이름 | 정의 |
|---|---|---|
| TYPES | `TY_MARA` | `matnr TYPE mara-matnr, meins TYPE mara-meins` |
| TYPES | `TT_MARA` | `STANDARD TABLE OF ty_mara WITH DEFAULT KEY` |
| TYPES | `TY_MAKT` | `matnr TYPE makt-matnr, maktx TYPE makt-maktx` |
| TYPES | `TT_MAKT` | `HASHED TABLE OF ty_makt WITH UNIQUE KEY matnr` — SPRAS를 한 값으로 고정해 읽으므로 MAKT 기본키(MATNR+SPRAS) 기준 1건 보장(wiki 해시 테이블 덤프 주의) |
| TYPES | `TT_LVORM_RANGE` | `RANGE OF mara-lvorm` |
| CONSTANTS | `C_MSGID` | `TYPE symsgid VALUE 'ZMMM3'` |
| CONSTANTS | `C_MSG_NO_INPUT` / `C_MSG_INVALID` / `C_MSG_NO_AUTH` / `C_MSG_NO_DATA` / `C_MSG_SUCCESS` / `C_MSG_TRUNC` | `TYPE symsgno VALUE '001'`~`'006'` (7장) |
| CONSTANTS | `C_ACTVT_DISPLAY` | `TYPE activ_auth VALUE '03'` (타입 [미확인(표준 기준)], 없으면 `TYPE c LENGTH 2`) |
| 속성(PRIVATE) | `G_MTART` `TYPE mtart`, `G_SPRAS` `TYPE spras`, `G_WITH_DELETED` `TYPE xfeld`, `G_MAX_ROWS` `TYPE i` | constructor에서 정규화해 보관 |

### 4.2 메서드

| 메서드 | 가시성 | 정적 | 시그니처 | 내용 | DB | Unit |
|---|---|---|---|---|---|---|
| `constructor` | PUBLIC | | IMPORTING `iv_mtart TYPE mtart`, `iv_spras TYPE spras OPTIONAL`, `iv_with_deleted TYPE xfeld OPTIONAL`, `iv_max_rows TYPE i OPTIONAL` | 아래 normalize_* 결과를 G_ 속성에 저장. `g_with_deleted`는 'X'가 아니면 공란 | 없음 | O |
| `execute` | PUBLIC | | EXPORTING `et_list TYPE zttmm3600`, `ev_count TYPE i`, `es_return TYPE bapiret2` | 5장 처리 로직 2~9단계 | 있음 | 가드(3단계)만 |
| `normalize_mtart` | PUBLIC | O | IMPORTING `iv_mtart TYPE mtart` RETURNING `rv_mtart TYPE mtart` | 앞 공백 제거 후 대문자 | 없음 | O |
| `normalize_spras` | PUBLIC | O | IMPORTING `iv_spras TYPE spras` RETURNING `rv_spras TYPE spras` | 공란 → SY-LANGU | 없음 | O |
| `normalize_max_rows` | PUBLIC | O | IMPORTING `iv_max_rows TYPE i` RETURNING `rv_max_rows TYPE i` | 음수 → 0 | 없음 | O |
| `build_lvorm_range` | PUBLIC | O | IMPORTING `iv_with_deleted TYPE xfeld` RETURNING `rt_lvorm TYPE tt_lvorm_range` | 공란 → 1행 `sign 'E' option 'EQ' low 'X'`(삭제 표시 제외), 'X' → 빈 range(조건 없음) | 없음 | O |
| `get_up_to_rows` | PUBLIC | O | IMPORTING `iv_max_rows TYPE i` RETURNING `rv_rows TYPE i` | 0 → `cl_abap_math=>max_int4`. 1 이상 → `iv_max_rows + 1`(잘림 판정용 1건 더). 단 `iv_max_rows >= max_int4`면 `max_int4` | 없음 | O |
| `build_list` | PUBLIC | O | IMPORTING `it_mara TYPE tt_mara`, `it_makt TYPE tt_makt`, `iv_max_rows TYPE i` EXPORTING `et_list TYPE zttmm3600`, `ev_truncated TYPE abap_bool` | MARA 행마다 MAKT를 키로 읽어 MAKTX(없으면 공란) → `SORT et_list BY matnr` → `iv_max_rows > 0` AND 건수 > `iv_max_rows`면 초과분 삭제, `ev_truncated = abap_true` | 없음 | O |
| `decide_return` | PUBLIC | O | IMPORTING `iv_mtart TYPE mtart`, `iv_count TYPE i`, `iv_truncated TYPE abap_bool`, `iv_max_rows TYPE i` RETURNING `rs_return TYPE bapiret2` | 잘림 → W 006(&1=iv_max_rows), 그 외 S 005(&1=mtart, &2=count) | 없음 | O |
| `make_return` | PUBLIC | O | IMPORTING `iv_type TYPE bapi_mtype`, `iv_number TYPE symsgno`, `iv_v1 TYPE clike OPTIONAL`, `iv_v2 TYPE clike OPTIONAL` RETURNING `rs_return TYPE bapiret2` | `MESSAGE ID c_msgid TYPE iv_type NUMBER iv_number WITH iv_v1 iv_v2 INTO l_msg.` 후 TYPE·ID·NUMBER·MESSAGE·MESSAGE_V1~V4를 SY-MSG*로 채움 | 없음 | O |
| `check_mtart` | PRIVATE | | EXPORTING `ev_found TYPE abap_bool`, `ev_begru TYPE t134-begru` | T134 SELECT SINGLE | T134 | X (통합) |
| `check_authority` | PRIVATE | | IMPORTING `iv_begru TYPE t134-begru` RETURNING `rv_ok TYPE abap_bool` | 8장 | 권한 | X (통합) |
| `read_mara` | PRIVATE | | RETURNING `rt_mara TYPE tt_mara` | 5장 6단계 | MARA | X (통합) |
| `read_makt` | PRIVATE | | IMPORTING `it_mara TYPE tt_mara` RETURNING `rt_makt TYPE tt_makt` | 5장 7단계 | MAKT | X (통합) |

- `make_return`의 `iv_v1`·`iv_v2`를 `clike`로 둔 이유: 자재유형(CHAR 4)과 건수(숫자를 문자로 변환한 값)를 모두 받기 위해서입니다. 건수는 호출 전에 `CONV string( iv_count )` 등으로 문자로 바꾸고 앞 공백을 없앱니다.
- `bapi_mtype`·`symsgno`·`symsgid` 타입은 BAPIRET2 필드 타입(표준) 기준이며 [미확인(표준 기준)]입니다. 활성화 오류가 나면 `bapiret2-type`·`bapiret2-number`·`bapiret2-id` 필드 참조로 바꿉니다(wiki: 필드 참조로 수정 범위 축소).

---

## 5. 처리 로직 단계 (흐름도 번호와 같음)

### 1단계 - FM (manual/Z_MM_GET_MATERIAL_LIST.fm.abap)

```abap
FUNCTION z_mm_get_material_list.
*"  IMPORTING
*"     VALUE(IV_MTART) TYPE  MTART
*"     VALUE(IV_SPRAS) TYPE  SPRAS DEFAULT SY-LANGU
*"     VALUE(IV_WITH_DELETED) TYPE  XFELD DEFAULT SPACE
*"     VALUE(IV_MAX_ROWS) TYPE  INT4 DEFAULT 0
*"  EXPORTING
*"     VALUE(ET_LIST) TYPE  ZTTMM3600
*"     VALUE(EV_COUNT) TYPE  INT4
*"     VALUE(ES_RETURN) TYPE  BAPIRET2
  DATA lo_list TYPE REF TO zcl_mm_mtart_matlist.
  CREATE OBJECT lo_list ... (또는 lo_list = NEW #( ... ))
  lo_list->execute( IMPORTING et_list = et_list ev_count = ev_count es_return = es_return ).
ENDFUNCTION.
```

- 이 코드는 형태 지시이며 실제 소스는 개발 단계가 씁니다. FM에는 로직을 두지 않습니다. `EV_COUNT`(INT4)와 클래스의 `TYPE i`는 같은 4바이트 정수라 그대로 넘깁니다.
- `NEW zcl( )->execute( ... )`처럼 생성식에 바로 메서드를 잇지 않고 참조 변수에 받은 뒤 호출합니다(wiki 7.40 주의와 같은 이유).

### 2단계 - 입력 정규화 (constructor)

- `g_mtart = normalize_mtart( iv_mtart )`, `g_spras = normalize_spras( iv_spras )`, `g_with_deleted = COND #( WHEN iv_with_deleted = abap_true THEN abap_true ELSE space )`, `g_max_rows = normalize_max_rows( iv_max_rows )`.

### 3단계 - 입력 누락 검사 (execute 시작)

- `CLEAR: et_list, ev_count, es_return.`
- `g_mtart IS INITIAL` → `es_return = make_return( iv_type = 'E' iv_number = c_msg_no_input )`, RETURN. **DB를 읽기 전에 끝남**(AC-05, UT-14).

### 4단계 - T134 존재 검사

```abap
SELECT SINGLE mtart, begru FROM t134
  INTO (@l_mtart, @ev_begru)        " 또는 구조 변수 1개로 받기
  WHERE mtart = @g_mtart.
```
- `sy-subrc <> 0` → E 002(&1 = g_mtart), RETURN.
- T134 기본키(MANDT, MTART) 단건 읽기라 성능 영향 없음. T134-BEGRU 존재는 [미확인(표준 기준)] — 활성화로 확인(C-01).

### 5단계 - 권한 점검 [추가, FR-10]

- `ev_begru IS NOT INITIAL`일 때만 `check_authority( )` 호출(8장). 거부 → E 003(&1 = g_mtart), RETURN.
- BEGRU가 비어 있으면 점검하지 않습니다. 표준 MM03의 자재유형 권한 동작과 같게 하려는 것이며, Q8 답이 "운영하지 않음"이면 T134-BEGRU가 비어 있어 이 단계는 결과에 영향이 없습니다.

### 6단계 - MARA 조회

```abap
DATA(r_lvorm) = build_lvorm_range( g_with_deleted ).
DATA(l_rows)  = get_up_to_rows( g_max_rows ).

SELECT matnr, meins
  FROM mara
  INTO TABLE @rt_mara               " rt_mara는 tt_mara (인라인 INTO @DATA( )는 쓰지 않음)
  UP TO @l_rows ROWS
  WHERE mtart = @g_mtart
    AND lvorm IN @r_lvorm
  ORDER BY matnr.
```
- 절 순서는 `INTO → UP TO → WHERE → ORDER BY`(wiki 7.40 SP05 호환).
- 0건 → `es_return = make_return( 'W', c_msg_no_data, g_mtart )`, RETURN (AC-07).
- `ORDER BY matnr`는 MARA 기본키 순이라 정렬 부담이 작고, `UP TO`와 함께 쓰면 "자재코드가 작은 앞 n건"이 됩니다. DB가 정렬 후 자르므로 최대 건수로 응답시간이 줄지는 않습니다(wiki 리뷰 W2). MTART 보조 인덱스 여부는 C-02.

### 7단계 - MAKT 조회 (FOR ALL ENTRIES)

```abap
IF it_mara IS INITIAL.   " FAE 드라이버가 비면 전체 조회되므로 반드시 확인
  RETURN.
ENDIF.
SELECT matnr, maktx
  FROM makt
  INTO TABLE @rt_makt                 " tt_makt (HASHED, KEY matnr)
  FOR ALL ENTRIES IN @it_mara
  WHERE matnr = @it_mara-matnr
    AND spras = @g_spras.
```

**FOR ALL ENTRIES / JOIN 선택 근거**

| 대안 | 판단 |
|---|---|
| MARA LEFT OUTER JOIN MAKT (ON 조건에 `spras = @g_spras`) | **채택 안 함.** 릴리스를 확정하지 못한 상태에서 LEFT OUTER JOIN ON 조건의 호스트 변수·리터럴 비교 제약을 피합니다(wiki "SAP 시스템 미확인 상태에서 작업하는 방법"). 내역이 없는 자재를 빠뜨리지 않으려면 INNER JOIN도 못 씁니다(FR-05) |
| MARA 조회 + MAKT FOR ALL ENTRIES | **채택.** ① `UP TO`가 MARA 자재 건수에 정확히 적용됩니다. ② MAKT를 기본키(MATNR+SPRAS)로 읽어 인덱스를 탑니다. ③ 팀의 기존 클래스들(ZCL_MM_MATERIAL_LIST, ZCL_MM_SLOC_LEDGER, ZRMM1234)과 같은 패턴입니다. 단점: 자재가 많으면 FAE가 여러 번 나눠 실행되지만 키 접근이라 수만 건까지는 문제 없을 것으로 봅니다(AC-14로 확인) |
| 행마다 SELECT SINGLE MAKT | 채택 안 함(N회 DB 왕복) |

- FAE는 중복 행을 없애므로 MATNR 중복 제거가 따로 필요 없습니다. `tt_makt`가 HASHED UNIQUE KEY matnr인데 SPRAS를 단일 값으로 고정했으므로 키 중복 덤프가 생기지 않습니다.

### 8단계 - 결과 조립 (`build_list`)

```text
LOOP AT it_mara INTO ls_mara.
  ls_list-matnr = ls_mara-matnr. ls_list-meins = ls_mara-meins.
  READ TABLE it_makt INTO ls_makt WITH TABLE KEY matnr = ls_mara-matnr.
  ls_list-maktx = COND #( WHEN sy-subrc = 0 THEN ls_makt-maktx ELSE space ).
  APPEND ls_list TO et_list.
ENDLOOP.
SORT et_list BY matnr.
IF iv_max_rows > 0 AND lines( et_list ) > iv_max_rows.
  DELETE et_list FROM iv_max_rows + 1.
  ev_truncated = abap_true.
ENDIF.
```
- `UP TO n+1`로 읽고 초과 1건을 지워 잘림을 판정하므로, 조건에 맞는 자재가 정확히 n건이면 잘림 경고가 뜨지 않습니다(wiki 리뷰 I1 반영).
- 내역 언어 대체(KO 없으면 EN)는 하지 않습니다(분석 A-05, Q4). Q4 답이 "대체"면 MAKT를 `spras IN (1순위, 대체)`로 읽고 고르는 정적 메서드를 추가합니다.

### 9단계 - 반환

- `ev_count = lines( et_list )`.
- `es_return = decide_return( iv_mtart = g_mtart iv_count = ev_count iv_truncated = l_truncated iv_max_rows = g_max_rows )` → 잘림이면 W 006, 아니면 S 005.
- COMMIT 없음, DB 갱신 없음(NFR-02).

---

## 6. 데이터 소스

### 6.1 테이블·용도·조인키

| 테이블 | 용도 | 읽는 필드 | 조건·조인키 | 접근 | 확인 상태 |
|---|---|---|---|---|---|
| T134 | 자재유형 존재 검사(FR-03), 권한그룹(FR-10) | MTART, BEGRU | `MTART = G_MTART` | SELECT SINGLE, 기본키 | 테이블 존재 [분석확인], 필드 [미확인(표준 기준)] |
| MARA | 자재코드·기본단위(FR-04), 삭제 표시(FR-08) | MATNR, MEINS (조건: MTART, LVORM) | `MTART = G_MTART AND LVORM IN R_LVORM` / T134.MTART = MARA.MTART | SELECT, MTART 인덱스 여부 미확인(C-02) | 존재 [분석확인], 필드 [미확인(표준 기준)] |
| MAKT | 자재내역(FR-05) | MATNR, MAKTX (조건: SPRAS) | MARA.MATNR = MAKT.MATNR AND MAKT.SPRAS = G_SPRAS | FOR ALL ENTRIES, 기본키 | 존재 [분석확인], 필드 [미확인(표준 기준)] |

### 6.2 출력 매핑

| ET_LIST 필드 | 원천 | 없을 때 |
|---|---|---|
| MATNR | MARA-MATNR | — (MARA 행이 기준) |
| MAKTX | MAKT-MAKTX (SPRAS = G_SPRAS) | 공란, 행은 유지 (AC-04) |
| MEINS | MARA-MEINS | — |

---

## 7. 메시지·오류 처리

메시지 클래스 `ZMMM3` (SE91 신규, 팀장 승인 후 수작업). 텍스트는 73자 이내, 원어 KO. EN 번역 필요 여부는 Q7.

| 번호 | 유형 | 텍스트(KO) | 발생 조건 | ET_LIST | EV_COUNT | 단계 | AC |
|---|---|---|---|---|---|---|---|
| 001 | E | 자재유형을 입력하십시오. | 정규화 후 IV_MTART 공란 | 빈 테이블 | 0 | 3 | AC-05 |
| 002 | E | 자재유형 &1 이(가) 존재하지 않습니다. | T134에 없음 | 빈 테이블 | 0 | 4 | AC-06 |
| 003 | E | 자재유형 &1 에 대한 조회 권한이 없습니다. | T134-BEGRU가 있고 M_MATE_MAR 거부 | 빈 테이블 | 0 | 5 | AC-13 |
| 004 | W | 자재유형 &1 에 해당하는 자재가 없습니다. | MARA 0건 | 빈 테이블 | 0 | 6 | AC-07 |
| 005 | S | 자재유형 &1 자재 &2 건이 조회되었습니다. | 정상 | 결과 | n | 9 | AC-01 |
| 006 | W | 최대 &1 건까지만 반환했습니다. 조회 조건에 맞는 자재가 더 있습니다. | IV_MAX_ROWS > 0이고 초과 | 앞 n건 | n | 9 | AC-11 |

- RETURN은 **단건**(BAPIRET2)입니다(분석 A-08). 잘림 경고(006)와 성공(005)이 겹치면 006만 줍니다(건수는 EV_COUNT로 알 수 있음).
- 클래식 EXCEPTIONS는 두지 않습니다. 이 규칙(성공·데이터 없음·잘못된 자재유형 구분)의 근거는 **분석 가정**입니다(분석서 FR-07 근거의 "팀장 지시" 표기는 기록이 없어 설계서에서는 분석 가정으로 다룸 — AI 검증 주의 1).
- RFC 호출 시 통신·시스템 오류는 호출측의 `SYSTEM_FAILURE`·`COMMUNICATION_FAILURE`로 처리됩니다(표준 RFC 동작). FM 안에서 따로 다루지 않습니다.
- `MESSAGE ... INTO`를 쓰므로 메시지가 화면에 뜨거나 처리를 중단하지 않습니다. ZMMM3가 아직 없으면 MESSAGE 텍스트가 비지만 TYPE·ID·NUMBER는 채워집니다(SE91 등록 확인 = 반영 체크리스트).

---

## 8. 권한 체크

| 대상 | 방법 | 결정 | 근거 |
|---|---|---|---|
| 자재유형 권한 [추가, FR-10] | `AUTHORITY-CHECK OBJECT 'M_MATE_MAR' ID 'ACTVT' FIELD c_actvt_display ID 'BEGRU' FIELD iv_begru.` sy-subrc ≠ 0 → E 003 | T134-BEGRU가 있을 때만 점검 | 표준 MM03과 같은 기준. 권한 객체 존재 [분석확인], 필드명(ACTVT, BEGRU)은 [미확인(표준 기준)] → SU21 확인(C-03). Q8 답이 "점검 불필요"면 5단계 호출만 빼면 됨 |
| 자재별 권한그룹 (MARA-BEGRU, M_MATE_MAT) | 점검 안 함 | 범위 밖 | 요청·분석에 없음. 운영 중이면 Q8과 함께 확인 |
| RFC 실행 권한 (S_RFC) | 코드 없음 — Basis가 호출 RFC 계정 역할에 함수 그룹 `ZFGMM71` 등록 | 운영 설정 | NFR-07. 전용 함수 그룹으로 만든 이유(2.1) |
| 프로그램 권한그룹 | 해당 없음(실행 프로그램·T-code 없음) | — | — |

---

## 9. ABAP 7.40 문법 제약 (개발 담당 준수)

| 구문 | 사용 | 최소 릴리스 | 비고 |
|---|---|---|---|
| New Open SQL(쉼표 필드 목록, `@` 호스트 변수) | 사용 | 7.40 SP05 | 절 순서 `INTO → UP TO → WHERE → ORDER BY` |
| `SELECT ... INTO TABLE @DATA(...)` 인라인 | **금지** | (끝 INTO는 SP08) | 타입(`tt_mara`, `tt_makt`)을 미리 선언 |
| 인라인 `DATA( )`, `NEW #( )`, `COND #( )`, `VALUE #( )`, `CONV #( )` | 사용 가능 | 7.40 SP02 | |
| `lines( )`, `to_upper( )`, `condense( )` | 사용 | 7.02 | |
| `xsdbool( )` | **금지** | 7.40 SP08 | `boolc( )` 또는 IF로 |
| `VALUE #( FOR ... )`, `REDUCE`, `FILTER` | 쓰지 않음 | SP08 이상 | 필요 없음 |
| `CL_ABAP_CORRESPONDING`, CDS, `CL_OSQL_TEST_ENVIRONMENT` | 금지 | 7.50 이상 | 시스템에 없음 [분석확인] |
| `cl_abap_math=>max_int4` | 사용 | — | 시스템 존재 [확인], 무제한 UP TO 값 |
| `NEW zcl( )->method( )` 체인 | 피함 | — | 참조 변수에 받은 뒤 호출 |
| ABAP Unit `RISK LEVEL HARMLESS DURATION SHORT`, `CL_ABAP_UNIT_ASSERT` | 사용 | — | |

- 이 설계가 요구하는 최소 기준은 **7.40 SP05**입니다(New Open SQL). 개발 문서에 "SP05 기준"이라고 적을 때 실제로 쓴 구문 중 SP08 이상이 없는지 확인합니다(wiki I6).

---

## 10. 반영 순서 (개발계, 의존 순서)

| 순서 | 대상 | 방법 | 비고 |
|---|---|---|---|
| R-1 | 이송요청 | SE09 | 팀장·Basis |
| R-2 | `ZSMM3600` → `ZTTMM3600` | SE11 수작업 생성·활성화 | **클래스보다 먼저.** 클래스가 `zttmm3600`을 참조 |
| R-3 | `ZMMM3` 메시지 001~006 | SE91 수작업 | 7장 텍스트 |
| R-4 | `ZCL_MM_MTART_MATLIST` + 테스트 클래스(CCAU) | 웹앱 개발계 반영 | src/에는 이 2파일만 |
| R-5 | `ZFGMM71` | SE80/SE37 수작업 생성(패키지 ZMMD) | |
| R-6 | `Z_MM_GET_MATERIAL_LIST` | SE37: 속성 Remote-Enabled, 파라미터(3.1, 값 전달 체크), 소스는 `manual/` 붙여넣기 → 활성화 | |
| R-7 | ABAP Unit 실행 → SE37 통합 테스트(11장) | SE80/SE37 | |

- 웹앱은 FM·DDIC·메시지를 올리지 못하므로(0.3) R-2·R-3·R-5·R-6은 반드시 수작업 체크리스트로 03_development.md에 남깁니다. R-2 전에 R-4를 하면 클래스 활성화가 실패합니다.

---

## 11. 테스트 포인트

### 11.1 ABAP Unit (`LTCL_MTART_MATLIST`, 클래스 Local Test Classes include = CCAU)

DB·권한이 필요 없는 공개 정적 메서드와 DB 전에 끝나는 가드만 대상으로 합니다(이 시스템에 OSQL·권한 테스트 더블 없음 [분석확인]).

| UT | 대상 | 입력 | 기대 |
|---|---|---|---|
| UT-01 | normalize_mtart | `' roh'` 형태(소문자·앞 공백) | `'ROH'` (AC-09) |
| UT-02 | normalize_mtart | 공란 | 공란 |
| UT-03 | normalize_spras | 공란 / `'E'` | SY-LANGU / `'E'` |
| UT-04 | normalize_max_rows | -5 / 0 / 10 | 0 / 0 / 10 |
| UT-05 | build_lvorm_range | 공란 | 1행(E EQ 'X'), `'X' IN r` 거짓, `' ' IN r` 참 |
| UT-06 | build_lvorm_range | 'X' | 빈 range, `'X' IN r`·`' ' IN r` 모두 참 |
| UT-07 | get_up_to_rows | 0 / 10 / max_int4 | max_int4 / 11 / max_int4 |
| UT-08 | build_list | MARA 2건, MAKT 1건만 | 2행, 내역 없는 행 MAKTX 공란 (AC-04) |
| UT-09 | build_list | MARA를 역순으로 | MATNR 오름차순 (AC-10) |
| UT-10 | build_list | MARA 3건, max 2 | 2행, truncated = 참 (AC-11) |
| UT-11 | build_list | MARA 2건, max 2 | 2행, truncated = 거짓 (정확히 n건이면 경고 없음) |
| UT-12 | build_list | MARA 3건, max 0 | 3행, truncated = 거짓 |
| UT-13 | make_return | 'E', '002', 'ZZZ9' | TYPE 'E', ID 'ZMMM3', NUMBER '002', MESSAGE_V1 'ZZZ9' (텍스트는 SE91 등록 전이면 비교하지 않음) |
| UT-14 | execute 가드 | `iv_mtart` 공란으로 생성 | ET_LIST 빈 테이블, EV_COUNT 0, TYPE 'E', NUMBER '001' — DB 접근 없이 끝남 (AC-05) |
| UT-15 | decide_return | count 5, 잘림 아님 / 잘림 | S 005 / W 006 |

테스트 데이터 자재번호는 18자리 내부 형식(앞 0 채움) 가상 값으로 만듭니다.

### 11.2 통합 테스트 (SE37, 개발계·QAS)

| 테스트 | 내용 | AC |
|---|---|---|
| IT-01 | 자재가 있는 자재유형(SE16 MARA로 선정) 호출: 건수 = MARA(MTART=값, LVORM≠'X'), EV_COUNT 같음, S 005 | AC-01 |
| IT-02 | 임의 3건 MATNR·MEINS를 MM03과 대조 | AC-02 |
| IT-03 | 로그온 KO, MAKTX = MAKT(SPRAS='3') | AC-03 |
| IT-04 | KO 내역 없는 자재 포함 유형: 행 유지, MAKTX 공란 | AC-04 |
| IT-05 | IV_MTART 공란: E 001 | AC-05 |
| IT-06 | T134에 없는 값(SE16 T134로 미존재 확인): E 002 | AC-06 |
| IT-07 | T134에 있으나 자재 0건: W 004 | AC-07 |
| IT-08 | 삭제 자재 있는 유형, IV_WITH_DELETED 공란/'X': 건수 차이 = 삭제 자재 수 | AC-08 |
| IT-09 | 소문자 입력 = 대문자 결과 | AC-09 |
| IT-10 | MAX_ROWS 10, 대상 > 10: 10건, W 006 / 대상 = 10: 10건, S 005 | AC-11 |
| IT-11 | SE37 RFC 목적지 NONE으로 IT-01 반복, 덤프 없음 | AC-12 |
| IT-12 | BEGRU 있는 자재유형 + 권한 없는 사용자: E 003 (BEGRU 있는 유형이 없으면 "해당 없음" 기록) | AC-13 |
| IT-13 | 자재가 가장 많은 유형: ST05로 MARA 접근 경로·응답시간 기록 | AC-14 |
| IT-14 | IV_SPRAS = 'E' 지정 시 EN 내역 | FR-05 |

---

## 12. 분석서 FR·AC·NFR 추적표

| 분석 항목 | 설계 반영 위치 | 구현 메서드 | 테스트 | 구분 |
|---|---|---|---|---|
| FR-01 자재유형 필수·대문자 | 3.1, 5장 2·3단계 | constructor, normalize_mtart, execute 가드 | UT-01·02·14, IT-05·09 | 요청 |
| FR-02 범위 입력 | 3.1 (1차 제외) | — | — | [추가], Q2 |
| FR-03 T134 검사 | 5장 4단계, 7장 002 | check_mtart | IT-06 | [가정] |
| FR-04 MATNR·MEINS | 5장 6단계, 3.3 | read_mara | IT-01·02 | 요청 |
| FR-05 MAKTX·언어 | 5장 7단계, 3.1 | read_makt, normalize_spras, build_list | UT-03·08, IT-03·04·14 | 요청 + IV_SPRAS [추가] |
| FR-06 정렬·건수 | 5장 8·9단계 | build_list | UT-09, IT-01 | [가정] |
| FR-07 RETURN | 7장 | make_return, decide_return | UT-13·15, IT-05~07 | 분석 가정 |
| FR-08 삭제 자재 제외 | 3.2, 5장 6단계 | build_lvorm_range | UT-05·06, IT-08 | [추가], Q3 |
| FR-09 최대 건수 | 5장 6·8단계, 7장 006 | get_up_to_rows, build_list | UT-07·10~12, IT-10 | [추가], Q6 |
| FR-10 권한 | 8장 | check_authority | IT-12 | [추가], Q8 |
| FR-11 RFC | 3.1, 10장 R-6 | (FM 속성) | IT-11 | [추가], Q1 |
| AC-01~AC-14 | 11.2 IT-01~13 | — | — | — |
| NFR-01 성능 | 5장 6·7단계 | read_mara, read_makt | IT-13 | — |
| NFR-02 정합성·읽기 전용 | 5장 9단계 | execute | IT-01 | — |
| NFR-03 7.40 호환 | 9장 | 전체 | 활성화 | — |
| NFR-04 내부 형식 | 3.3 | — | IT-02 | Q5 |
| NFR-05 메시지 | 7장, 2.1 | make_return | UT-13 | Q7 |
| NFR-06 테스트 용이성 | 4.2, 11.1 | 정적 메서드 | UT-01~15 | — |
| NFR-07 보안 | 8장 | check_authority | IT-12 | — |

---

## 13. 남은 확인 사항

### 13.1 현업 확인 (분석서 Q, 답이 오면 바뀌는 곳)

| Q | 내용 | 현재 설계 | 답에 따라 바뀌는 곳 |
|---|---|---|---|
| Q1 | 호출 주체·RFC·TABLES 필요 여부 | RFC 가능, EXPORTING 테이블 타입 | FM 속성, TABLES 파라미터 추가 여부 |
| Q2 | 자재유형 여러 개 | 단일 | 3.1 선택 파라미터 추가, read_mara 조건 |
| Q3 | 삭제 자재 포함 | 기본 제외 | 3.2 표 (FM 기본값, AC-01·08) |
| Q4 | 내역 언어 대체 | SY-LANGU, 없으면 공란 | 5장 7·8단계, AC-04 |
| Q5 | MATNR·MEINS 표시 형식 | 내부 형식 | build_list에 변환(CONVERSION_EXIT_*_OUTPUT) 추가 |
| Q6 | 예상 건수·최대 건수·응답시간 | 제한 없음(옵션) | FM 기본값 IV_MAX_ROWS |
| Q7 | RETURN 형식·다국어 | BAPIRET2 단건, KO | 7장, SE63 번역 |
| Q8 | 자재유형 권한 운영 | BEGRU 있을 때만 점검 | 5장 5단계 유지·삭제 |
| Q9 | 함수 그룹 | **신규 ZFGMM71로 결정**(2.1) | 팀 표준이 ZFGMM41이면 FM 위치만 변경 |
| Q10 | 기존 FM 재사용 | **신규 개발로 결정**(2.1) | C-04 결과에 따라 팀장 재판단 |
| Q11 | 출력 항목 3개 확정 | 3개 | ZSMM3600 필드 추가(구조 확장 → RFC 호출측 영향 검토) |

### 13.2 개발 착수 전 시스템 확인 (개발팀, 도구로 못 읽은 것)

| C | 확인 | 도구 | 못 읽은 이유 |
|---|---|---|---|
| C-01 | MARA-MTART/MEINS/LVORM, MAKT-MAKTX, T134-BEGRU 필드·Data Element·길이 | SE11 (또는 클래스 활성화로 간접 확인) | GetTable 404 (분석) |
| C-02 | MARA의 MTART 보조 인덱스 | SE11 인덱스, ST05 | 인덱스 조회 도구 없음 |
| C-03 | M_MATE_MAR 필드(ACTVT, BEGRU) | SU21 | SUSO 정의 조회 도구 없음 |
| C-04 | `Z_MM_MP_SELECT_MATNR_DATA`(ZFGMM25)·`Z_MD_MIGMAT_LIST_GET`(ZFGMD98)·`BAPI_MATERIAL_GETLIST` 인터페이스 | SE37 | FM 소스 조회 도구 없음(GetProgram 404) |
| C-05 | `ZFGMM71`·`ZSMM3600`·`ZTTMM3600`·`ZMMM3` 다른 시스템(QAS·PRD)에서도 비어 있는지 | SE80/SE11/SE91 (각 시스템) | 개발계만 조회함 |
| C-06 | SAP_BASIS 정확한 SP | 시스템 > 상태 | 직접 조회 불가 |
| C-07 | 기존 메시지 클래스 재사용 희망 여부(ZMMM2 등) | 팀장 | 번호 사용 현황 조회 불가 |
| C-08 | 웹앱 반영 도구가 FM·DDIC를 지원하지 않는 점 — 수작업 반영 담당·순서 합의 | 팀장 | 0.3 |

### 13.3 설계 가정

| No | 가정 |
|---|---|
| D-01 | 함수 그룹은 ZFGMM71 신규(Q9 설계 결정) |
| D-02 | 메시지 클래스는 ZMMM3 신규(C-07에 따라 변경 가능, 클래스 상수만 수정) |
| D-03 | 표 3.3의 필드 형식, T134-BEGRU, M_MATE_MAR 필드, BAPIRET2 필드 타입은 SAP 표준 기준 |
| D-04 | 웹앱 반영은 클래스만, 나머지는 수작업(0.3) |
