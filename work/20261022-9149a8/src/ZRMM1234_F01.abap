*&---------------------------------------------------------------------*
*& Include ZRMM1234_F01 - 선택화면 보조 FORM (기본값, 안내 줄, F4, 일자 검증)
*&---------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*& Form SET_DEFAULT_DATES - 기본 전기일 = 최종 집계일 (없으면 전일)
*&---------------------------------------------------------------------*
FORM set_default_dates.
  DATA l_max TYPE budat.

  SELECT MAX( last_budat ) FROM ztmm1237 INTO @l_max.
  IF l_max IS INITIAL.
    l_max = sy-datum - 1.
  ENDIF.
  pa_budfr = l_max.
  pa_budto = l_max.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form SET_INFO_TEXT - 블록 B01 안내 줄 (T01 고정, T02 첫 플랜트 집계 정보)
*&---------------------------------------------------------------------*
FORM set_info_text.
  DATA: ls_werks LIKE LINE OF so_werks,
        l_cpudt  TYPE ztmm1237-last_cpudt,
        l_cputm  TYPE ztmm1237-last_cputm,
        l_budat  TYPE ztmm1237-last_budat,
        l_info   TYPE string,
        l_d1     TYPE string,
        l_t1     TYPE string,
        l_d2     TYPE string.

  g_info1 = TEXT-t01.
  CLEAR g_info2.

  READ TABLE so_werks INTO ls_werks INDEX 1.
  IF sy-subrc <> 0 OR ls_werks-low IS INITIAL.
    RETURN.
  ENDIF.
  SELECT SINGLE last_cpudt, last_cputm, last_budat
    FROM ztmm1237
    INTO (@l_cpudt, @l_cputm, @l_budat)
    WHERE werks = @ls_werks-low.
  IF sy-subrc <> 0 OR l_budat IS INITIAL.
    RETURN.
  ENDIF.

  l_d1 = |{ l_cpudt DATE = USER }|.
  l_t1 = |{ l_cputm TIME = USER }|.
  l_d2 = |{ l_budat DATE = USER }|.
  l_info = TEXT-t02.
  REPLACE '&1' WITH l_d1 INTO l_info.
  REPLACE '&2' WITH l_t1 INTO l_info.
  REPLACE '&3' WITH l_d2 INTO l_info.
  g_info2 = l_info.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form F4_LAYOUT - 메인 레이아웃 F4 (핸들 MAIN)
*&---------------------------------------------------------------------*
FORM f4_layout CHANGING cv_vari TYPE slis_vari.
  DATA: ls_key  TYPE salv_s_layout_key,
        ls_info TYPE salv_s_layout_info.

  ls_key-report = sy-repid.
  ls_key-handle = c_handle_main.
  ls_info = cl_salv_layout_service=>f4_layouts( s_key    = ls_key
                                                layout   = cv_vari
                                                restrict = if_salv_c_layout=>restrict_none ).
  IF ls_info-layout IS NOT INITIAL.
    cv_vari = ls_info-layout.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form CHECK_PERIOD - Q1 일자 검증 (From > To: E 001, To >= 오늘: E 002)
*&---------------------------------------------------------------------*
FORM check_period.
  DATA l_code TYPE zcl_mm_stkday_calc=>ty_chk_code.

  l_code = zcl_mm_stkday_calc=>check_period( iv_from  = pa_budfr
                                             iv_to    = pa_budto
                                             iv_today = sy-datum ).
  CASE l_code.
    WHEN zcl_mm_stkday_calc=>c_chk_from_gt_to.
      MESSAGE e001.
    WHEN zcl_mm_stkday_calc=>c_chk_to_today.
      MESSAGE e002.
    WHEN OTHERS.
  ENDCASE.
ENDFORM.
