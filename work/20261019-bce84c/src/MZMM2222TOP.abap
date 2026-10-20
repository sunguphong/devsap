*&---------------------------------------------------------------------*
*& Include MZMM0020TOP                                       모듈풀              SAPMZMM0020
*&
*&---------------------------------------------------------------------*


************************************************************************
*** INTERNAL TABLE 및 구조 정의
************************************************************************
TABLES: ZTMM0015.

* PR용
DATA   BEGIN OF GT_PR OCCURS 0.
         INCLUDE STRUCTURE ZSMM0015.
DATA:    COLTAB  TYPE LVC_T_SCOL,
         STYTAB  TYPE LVC_T_STYL,
         DBDATA  TYPE C,
       END OF GT_PR.

DATA: rt_extab TYPE slis_t_extab.

* 삭제된 DB에서 가져온 DATA를 지울 ROW
*DATA: GT_DELETED LIKE GT_PR OCCURS 0 WITH HEADER LINE.

*********************************************************************
*** GLOBAL 변수 정의
*********************************************************************

* COMMAND관련
DATA: OK_CODE LIKE SY-UCOMM,
      SAVE_OK LIKE SY-UCOMM.


*********************************************************************
*** Constants 정의
*********************************************************************

*********************************************************************
*** RANGE 정의
*********************************************************************

*********************************************************************
*** FIELD SYMBOL 정의
*********************************************************************

*********************************************************************
*** SELECTION SCREEN 정의
*********************************************************************
SELECT-OPTIONS: SO_WERKS FOR ZTMM0015-WERKS,
                SO_MATNR FOR ZTMM0015-MATNR,
                SO_LEVEL FOR ZTMM0015-ZLEVEL,
                SO_DATAB FOR ZTMM0015-DATAB OBLIGATORY.

*-- U4 START : 공문발송 (요청 20261019-bce84c)
*&---------------------------------------------------------------------*
*& U4 2026.10.20 ZEMM2222 공문발송(ZMAIL) 전역 데이터·상수 추가
*&    - 기존 인클루드 끝에 추가. 위 기존 선언은 원문 그대로
*&---------------------------------------------------------------------*
*** INTERNAL TABLE : 공문발송 대상 / 수신 주소
DATA: gt_mail_item TYPE zcl_mm_scrap_price_mail=>tt_item,   " 선택 행 공문 대상
      gt_mail_to   TYPE zcl_mm_scrap_price_mail=>tt_addr.   " 수신 메일주소

*** GLOBAL 변수 : 공문발송 팝업(화면 0200)
DATA: g_mail_to TYPE c LENGTH 255,     " 화면 0200 메일주소 입력창 (시트 C63)
      g_datab   TYPE d,                " 선택 행 공통 유효시작일
      g_ok_0200 TYPE sy-ucomm,         " 화면 0200 OK_CODE
      g_answer  TYPE c LENGTH 1.       " 화면 0200 결과 (S 발송 / C 취소)

* 참조 변수 접두어 GO_ : 핸드북 규칙 없음 - SAP 관례
DATA: go_mail   TYPE REF TO zcl_mm_scrap_price_mail.

*** Constants : 공문발송 FCODE / 팝업 결과
CONSTANTS: c_fc_mail     TYPE sy-ucomm   VALUE 'ZMAIL',  " GUI 상태 0100 공문발송
           c_fc_send     TYPE sy-ucomm   VALUE 'SEND',   " GUI 상태 0200 발송
           c_fc_canc     TYPE sy-ucomm   VALUE 'CANC',   " GUI 상태 0200 취소
           c_answer_send TYPE c LENGTH 1 VALUE 'S',      " 팝업 결과 발송
           c_answer_canc TYPE c LENGTH 1 VALUE 'C'.      " 팝업 결과 취소
*-- U4 END
