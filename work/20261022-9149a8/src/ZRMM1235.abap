*&---------------------------------------------------------------------*
*& Report ZRMM1235 - 자재수불부 일자별 집계 배치
*&---------------------------------------------------------------------*
*& 자재수불부 일자별 집계 배치 (전기일 기준, 저장위치·배치 레벨)
*& - 요청 ID : 20261022-9149a8 / 설계 02_design.md v1.1 5.2, 7.1
*& - 실행    : SM36 잡 ZRMM1235_DAILY(변형 DAILY, 매일 07:00)
*&             ZRMM1235_MONTHLY(변형 MONTHLY, 전월 1일부터 재집계)
*&             수동 실행은 SA38(운영 담당). T-code 없음
*& - 처리    : ZCL_MM_STKDAY_AGGR->RUN( ) -> 결과 목록(SALV)
*& - 패키지  : ZMMD / 메시지 클래스 ZMMM3
*&---------------------------------------------------------------------*
REPORT zrmm1235 MESSAGE-ID zmmm3.

*----------------------------------------------------------------------*
* 선택화면 참조 변수
*----------------------------------------------------------------------*
DATA: g_werks TYPE t001w-werks,
      g_matnr TYPE mara-matnr.

DATA: gt_result TYPE zcl_mm_stkday_aggr=>tt_result,
      g_aggr    TYPE REF TO zcl_mm_stkday_aggr.

*----------------------------------------------------------------------*
* 선택화면
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b01 WITH FRAME TITLE TEXT-b01.
PARAMETERS: pa_daily RADIOBUTTON GROUP rmd DEFAULT 'X',
            pa_recal RADIOBUTTON GROUP rmd,
            pa_init  RADIOBUTTON GROUP rmd.
SELECTION-SCREEN END OF BLOCK b01.

SELECTION-SCREEN BEGIN OF BLOCK b02 WITH FRAME TITLE TEXT-b02.
SELECT-OPTIONS: so_werks FOR g_werks.
PARAMETERS:     pa_from  TYPE budat,
                pa_prvmo AS CHECKBOX.
SELECT-OPTIONS: so_matnr FOR g_matnr MATCHCODE OBJECT mat1.
SELECTION-SCREEN END OF BLOCK b02.

SELECTION-SCREEN BEGIN OF BLOCK b03 WITH FRAME TITLE TEXT-b03.
PARAMETERS: pa_ovlap TYPE i,
            pa_blksz TYPE i,
            pa_test  AS CHECKBOX.
SELECTION-SCREEN END OF BLOCK b03.

*----------------------------------------------------------------------*
INITIALIZATION.
*----------------------------------------------------------------------*
  " 기본값은 클래스 상수(변형 값이 있으면 변형 우선)
  pa_ovlap = zcl_mm_stkday_aggr=>c_default_ovlap.
  pa_blksz = zcl_mm_stkday_aggr=>c_default_blksz.

*----------------------------------------------------------------------*
AT SELECTION-SCREEN.
*----------------------------------------------------------------------*
  PERFORM check_selection.

*----------------------------------------------------------------------*
START-OF-SELECTION.
*----------------------------------------------------------------------*
  PERFORM run_aggregation.

*&---------------------------------------------------------------------*
*& Form CHECK_SELECTION - 선택화면 검증 (E 018/019/020)
*&---------------------------------------------------------------------*
FORM check_selection.
  IF pa_recal = abap_true OR pa_init = abap_true.
    " 재집계·초기 적재는 플랜트 필수
    IF so_werks[] IS INITIAL.
      MESSAGE e018.
    ENDIF.
    " 시작 전기일: 재집계는 PA_FROM 또는 PA_PRVMO, 초기 적재는 PA_FROM 필수
    IF pa_from IS INITIAL
       AND ( pa_init = abap_true OR pa_prvmo = abap_false ).
      MESSAGE e019.
    ENDIF.
    IF pa_from IS NOT INITIAL AND pa_from >= sy-datum.
      MESSAGE e019.
    ENDIF.
  ENDIF.
  " 초기 적재는 자재 조건 사용 불가(부분 적재는 키 정합성을 깸)
  IF pa_init = abap_true AND so_matnr[] IS NOT INITIAL.
    MESSAGE e020.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form RUN_AGGREGATION - 집계 실행과 결과 출력
*&---------------------------------------------------------------------*
FORM run_aggregation.
  DATA: l_mode     TYPE zcl_mm_stkday_aggr=>ty_code1,
        l_answer   TYPE c LENGTH 1,
        l_error    TYPE abap_bool,
        l_no_plant TYPE abap_bool,
        lr_werks   TYPE zcl_mm_stkday_calc=>ty_r_werks,
        lr_matnr   TYPE zcl_mm_stkday_calc=>ty_r_matnr,
        ls_result  TYPE zcl_mm_stkday_aggr=>ty_result,
        l_failed   TYPE string,
        l_v1       TYPE symsgv,
        l_v2       TYPE symsgv.

  " 실행 모드
  IF pa_init = abap_true.
    l_mode = zcl_mm_stkday_calc=>c_mode_init.
  ELSEIF pa_recal = abap_true.
    l_mode = zcl_mm_stkday_calc=>c_mode_recalc.
  ELSE.
    l_mode = zcl_mm_stkday_calc=>c_mode_daily.
  ENDIF.

  " J0 초기 적재 온라인 실행: 확인 팝업 (백그라운드는 팝업 없이 진행)
  IF l_mode = zcl_mm_stkday_calc=>c_mode_init AND sy-batch = abap_false.
    CALL FUNCTION 'POPUP_TO_CONFIRM'
      EXPORTING
        titlebar              = TEXT-p01
        text_question         = TEXT-p02
        default_button        = '2'
        display_cancel_button = abap_false
      IMPORTING
        answer                = l_answer
      EXCEPTIONS
        text_not_found        = 1
        OTHERS                = 2.
    IF sy-subrc <> 0 OR l_answer <> '1'.
      MESSAGE i029.
      RETURN.
    ENDIF.
  ENDIF.

  lr_werks = so_werks[].
  lr_matnr = so_matnr[].

  CREATE OBJECT g_aggr
    EXPORTING
      iv_mode       = l_mode
      it_werks      = lr_werks
      iv_from       = pa_from
      iv_prev_month = pa_prvmo
      it_matnr      = lr_matnr
      iv_overlap    = pa_ovlap
      iv_block_size = pa_blksz
      iv_test       = pa_test.

  g_aggr->run( IMPORTING et_result   = gt_result
                         ev_error    = l_error
                         ev_no_plant = l_no_plant ).

  IF l_no_plant = abap_true.
    IF sy-batch = abap_true.
      MESSAGE e028.
    ELSE.
      MESSAGE s028 DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
  ENDIF.

  " 결과 목록 (백그라운드는 스풀)
  PERFORM display_result.

  " 한 플랜트라도 실패하면 잡을 '취소됨'으로 끝냄 (로그·제어는 이미 COMMIT됨)
  IF l_error = abap_true.
    LOOP AT gt_result INTO ls_result
         WHERE run_stat = zcl_mm_stkday_calc=>c_stat_error.
      IF l_failed IS INITIAL.
        l_failed = ls_result-werks.
        l_v2     = ls_result-run_msg.
      ELSE.
        l_failed = |{ l_failed }, { ls_result-werks }|.
      ENDIF.
    ENDLOOP.
    l_v1 = l_failed.
    IF sy-batch = abap_true.
      MESSAGE e023 WITH l_v1 l_v2.
    ELSE.
      MESSAGE s023 DISPLAY LIKE 'E' WITH l_v1 l_v2.
    ENDIF.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form DISPLAY_RESULT - 플랜트별 실행 결과 SALV
*&---------------------------------------------------------------------*
FORM display_result.
  DATA: l_salv    TYPE REF TO cl_salv_table,
        lo_cols   TYPE REF TO cl_salv_columns_table,
        lx_salv   TYPE REF TO cx_salv_error,
        l_msg     TYPE string,
        l_v1      TYPE symsgv.

  TRY.
      cl_salv_table=>factory( IMPORTING r_salv_table = l_salv
                              CHANGING  t_table      = gt_result ).
      lo_cols = l_salv->get_columns( ).
      lo_cols->set_optimize( abap_true ).
      PERFORM set_result_column USING lo_cols 'WERKS'    TEXT-r01.
      PERFORM set_result_column USING lo_cols 'RUN_MODE' TEXT-r02.
      PERFORM set_result_column USING lo_cols 'RUN_MATS' TEXT-r03.
      PERFORM set_result_column USING lo_cols 'ROWS_B'   TEXT-r04.
      PERFORM set_result_column USING lo_cols 'ROWS_A'   TEXT-r05.
      PERFORM set_result_column USING lo_cols 'RUN_STAT' TEXT-r06.
      PERFORM set_result_column USING lo_cols 'SECS'     TEXT-r07.
      PERFORM set_result_column USING lo_cols 'RUN_MSG'  TEXT-r08.
      l_salv->display( ).
    CATCH cx_salv_error INTO lx_salv.
      l_msg = lx_salv->get_text( ).
      l_v1  = l_msg.
      MESSAGE s015 DISPLAY LIKE 'E' WITH l_v1.
  ENDTRY.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form SET_RESULT_COLUMN - 결과 컬럼 헤더(Text Symbol)
*&---------------------------------------------------------------------*
FORM set_result_column USING io_cols TYPE REF TO cl_salv_columns_table
                             iv_name TYPE csequence
                             iv_text TYPE csequence
                       RAISING cx_salv_error.
  DATA lo_col TYPE REF TO cl_salv_column.

  lo_col = io_cols->get_column( CONV lvc_fname( iv_name ) ).
  lo_col->set_short_text( CONV scrtext_s( iv_text ) ).
  lo_col->set_medium_text( CONV scrtext_m( iv_text ) ).
  lo_col->set_long_text( CONV scrtext_l( iv_text ) ).
ENDFORM.
