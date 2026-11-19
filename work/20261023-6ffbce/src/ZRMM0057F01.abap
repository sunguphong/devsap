*&---------------------------------------------------------------------*
*&  Include           ZRMM0057F01
*&---------------------------------------------------------------------*
*& FORM 루틴 (선택화면 처리, 조회, ALV 출력, 팝업)
*&---------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*&      Form  SET_DEFAULTS
*&---------------------------------------------------------------------*
*       S1: 기본값 (비어 있을 때만, Variant 값이 우선)
*----------------------------------------------------------------------*
FORM set_defaults.
  DATA: ls_budat LIKE LINE OF so_budat,
        ls_bust  LIKE LINE OF so_xbust,
        ls_bw    LIKE LINE OF so_bwit.

  IF so_budat[] IS INITIAL.
    CLEAR ls_budat.
    ls_budat-sign   = zcl_mm_sloc_ledger=>c_sign_i.
    ls_budat-option = c_opt_bt.
    ls_budat-low    = zcl_mm_sloc_ledger=>month_start( sy-datum ).
    ls_budat-high   = sy-datum.
    APPEND ls_budat TO so_budat.
  ENDIF.

  IF so_xbust[] IS INITIAL.
    CLEAR ls_bust.
    ls_bust-sign   = zcl_mm_sloc_ledger=>c_sign_i.
    ls_bust-option = zcl_mm_sloc_ledger=>c_opt_eq.
    ls_bust-low    = zcl_mm_sloc_ledger=>c_bustm_ma02.
    APPEND ls_bust TO so_xbust.
    ls_bust-low    = zcl_mm_sloc_ledger=>c_bustm_ma05.
    APPEND ls_bust TO so_xbust.
  ENDIF.

  CLEAR ls_bw.
  ls_bw-sign   = zcl_mm_sloc_ledger=>c_sign_i.
  ls_bw-option = zcl_mm_sloc_ledger=>c_opt_eq.

  IF so_bwit[] IS INITIAL.
    ls_bw-low = zcl_mm_sloc_ledger=>c_bwart_313.
    APPEND ls_bw TO so_bwit.
    ls_bw-low = zcl_mm_sloc_ledger=>c_bwart_314.
    APPEND ls_bw TO so_bwit.
  ENDIF.
  IF so_bwir[] IS INITIAL.
    ls_bw-low = zcl_mm_sloc_ledger=>c_bwart_315.
    APPEND ls_bw TO so_bwir.
    ls_bw-low = zcl_mm_sloc_ledger=>c_bwart_316.
    APPEND ls_bw TO so_bwir.
  ENDIF.
  IF so_bwpt[] IS INITIAL.
    ls_bw-low = zcl_mm_sloc_ledger=>c_bwart_303.
    APPEND ls_bw TO so_bwpt.
    ls_bw-low = zcl_mm_sloc_ledger=>c_bwart_304.
    APPEND ls_bw TO so_bwpt.
  ENDIF.
  IF so_bwpr[] IS INITIAL.
    ls_bw-low = zcl_mm_sloc_ledger=>c_bwart_305.
    APPEND ls_bw TO so_bwpr.
    ls_bw-low = zcl_mm_sloc_ledger=>c_bwart_306.
    APPEND ls_bw TO so_bwpr.
  ENDIF.

  pa_vsloc = abap_true.
  pa_nozer = abap_true.
ENDFORM.                    " SET_DEFAULTS

*&---------------------------------------------------------------------*
*&      Form  F4_LAYOUT
*&---------------------------------------------------------------------*
FORM f4_layout.
  DATA: ls_key  TYPE salv_s_layout_key,
        ls_info TYPE salv_s_layout_info.

  ls_key-report = sy-repid.
  ls_key-handle = c_handle_main.
  ls_info = cl_salv_layout_service=>f4_layouts(
              s_key    = ls_key
              restrict = if_salv_c_layout=>restrict_none ).
  IF ls_info-layout IS NOT INITIAL.
    pa_vari = ls_info-layout.
  ENDIF.
ENDFORM.                    " F4_LAYOUT

*&---------------------------------------------------------------------*
*&      Form  CHECK_INPUT
*&---------------------------------------------------------------------*
*       S2: 실행 버튼일 때만 검증
*----------------------------------------------------------------------*
FORM check_input.
  DATA ls_bw LIKE LINE OF so_bwit.

  CASE sscrfields-ucomm.
    WHEN c_ucomm_onli OR c_ucomm_prin OR c_ucomm_sjob.
    WHEN OTHERS.
      RETURN.
  ENDCASE.

  READ TABLE so_budat INTO DATA(ls_budat) INDEX 1.
  IF sy-subrc = 0.
    " 단일값(EQ) 또는 범위(BT), 포함(I)만 허용
    IF ls_budat-sign <> zcl_mm_sloc_ledger=>c_sign_i
       OR ( ls_budat-option <> zcl_mm_sloc_ledger=>c_opt_eq
            AND ls_budat-option <> c_opt_bt ).
      MESSAGE TEXT-e05 TYPE 'E'.
    ENDIF.
    IF ls_budat-low > sy-datum.
      MESSAGE TEXT-e01 TYPE 'E'.
    ENDIF.
  ENDIF.

  " 집계 규칙 range 충돌: 같은 이동유형이 출고·입고 양쪽에 있으면 오류
  IF so_bwir[] IS NOT INITIAL.
    LOOP AT so_bwit INTO ls_bw WHERE option = zcl_mm_sloc_ledger=>c_opt_eq.
      IF ls_bw-low IN so_bwir.
        MESSAGE TEXT-e02 TYPE 'E'.
      ENDIF.
    ENDLOOP.
  ENDIF.
  IF so_bwpr[] IS NOT INITIAL.
    LOOP AT so_bwpt INTO ls_bw WHERE option = zcl_mm_sloc_ledger=>c_opt_eq.
      IF ls_bw-low IN so_bwpr.
        MESSAGE TEXT-e02 TYPE 'E'.
      ENDIF.
    ENDLOOP.
  ENDIF.
ENDFORM.                    " CHECK_INPUT

*&---------------------------------------------------------------------*
*&      Form  MAIN_PROCESS
*&---------------------------------------------------------------------*
*       S3~S9: 권한, 기간 확인, 조회
*----------------------------------------------------------------------*
FORM main_process.
  DATA: l_exist   TYPE i,
        l_allowed TYPE i,
        l_denied  TYPE i,
        l_days    TYPE i,
        l_count   TYPE i,
        l_answer  TYPE c LENGTH 1,
        l_num     TYPE string,
        l_msg     TYPE string.

  CLEAR: gt_main, g_warn, gs_sel.

  READ TABLE so_budat INTO DATA(ls_budat) INDEX 1.
  gs_sel-werks      = so_werks[].
  gs_sel-matnr      = so_matnr[].
  gs_sel-lgort      = so_lgort[].
  gs_sel-mtart      = so_mtart[].
  gs_sel-xbustm     = so_xbust[].
  gs_sel-bw_it      = so_bwit[].
  gs_sel-bw_ir      = so_bwir[].
  gs_sel-bw_pt      = so_bwpt[].
  gs_sel-bw_pr      = so_bwpr[].
  gs_sel-budat_from = ls_budat-low.
  gs_sel-budat_to   = ls_budat-high.
  IF gs_sel-budat_to IS INITIAL.
    gs_sel-budat_to = gs_sel-budat_from.
  ENDIF.
  gs_sel-vsloc      = pa_vsloc.
  gs_sel-no_zero    = pa_nozer.

  CREATE OBJECT g_ledger
    EXPORTING
      is_sel = gs_sel.

  " S3 플랜트 존재·권한 (M_MSEG_WWA)
  g_ledger->check_plants( IMPORTING ev_exist   = l_exist
                                    ev_allowed = l_allowed
                                    ev_denied  = l_denied ).
  IF l_exist = 0.
    MESSAGE TEXT-e03 TYPE 'S' DISPLAY LIKE 'E'.
    LEAVE LIST-PROCESSING.
  ENDIF.
  IF l_allowed = 0.
    MESSAGE TEXT-e04 TYPE 'S' DISPLAY LIKE 'E'.
    LEAVE LIST-PROCESSING.
  ENDIF.
  IF l_denied > 0.
    l_msg = TEXT-w01.
    l_num = |{ l_denied }|.
    REPLACE '&1' IN l_msg WITH l_num.
    PERFORM add_warning USING l_msg.
  ENDIF.

  " S4 대화식 장기간 확인
  IF sy-batch IS INITIAL.
    l_days = gs_sel-budat_to - gs_sel-budat_from + 1.
    IF l_days > zcl_mm_sloc_ledger=>c_max_days_dialog.
      CALL FUNCTION 'POPUP_TO_CONFIRM'
        EXPORTING
          titlebar              = TEXT-q00
          text_question         = TEXT-q01
          text_button_1         = TEXT-q02
          text_button_2         = TEXT-q03
          default_button        = c_answer_no
          display_cancel_button = space
        IMPORTING
          answer                = l_answer
        EXCEPTIONS
          text_not_found        = 1
          OTHERS                = 2.
      IF sy-subrc <> 0 OR l_answer <> c_answer_yes.
        MESSAGE TEXT-m05 TYPE 'S'.
        LEAVE LIST-PROCESSING.
      ENDIF.
    ENDIF.
  ENDIF.

  " S5~S8 조회·집계
  gt_main = g_ledger->run( ).
  gs_sel  = g_ledger->get_sel( ).

  " 가상 저장위치 명칭
  LOOP AT gt_main ASSIGNING FIELD-SYMBOL(<ls_main>) WHERE vsloc = abap_true.
    CASE <ls_main>-lgort.
      WHEN zcl_mm_sloc_ledger=>c_vsloc_trns.
        <ls_main>-lgobe = TEXT-v01.
      WHEN zcl_mm_sloc_ledger=>c_vsloc_unkn.
        <ls_main>-lgobe = TEXT-v02.
      WHEN OTHERS.
    ENDCASE.
  ENDLOOP.

  " 매핑 누락·단위 변환 실패 경고
  l_count = g_ledger->get_unmapped_count( ).
  IF l_count > 0.
    l_msg = TEXT-w05.
    l_num = |{ l_count }|.
    REPLACE '&1' IN l_msg WITH l_num.
    PERFORM add_warning USING l_msg.
  ENDIF.
  l_count = g_ledger->get_conv_error_count( ).
  IF l_count > 0.
    l_msg = TEXT-w06.
    l_num = |{ l_count }|.
    REPLACE '&1' IN l_msg WITH l_num.
    PERFORM add_warning USING l_msg.
  ENDIF.

  " S9 결과 0건
  IF gt_main IS INITIAL.
    l_msg = TEXT-m01.
    IF g_warn IS NOT INITIAL.
      l_msg = |{ l_msg } ({ g_warn })|.
    ENDIF.
    MESSAGE l_msg TYPE 'S' DISPLAY LIKE 'W'.
    LEAVE LIST-PROCESSING.
  ENDIF.
ENDFORM.                    " MAIN_PROCESS

*&---------------------------------------------------------------------*
*&      Form  ADD_WARNING
*&---------------------------------------------------------------------*
*       경고를 한 줄로 합침
*----------------------------------------------------------------------*
FORM add_warning USING p_msg TYPE string.
  IF g_warn IS INITIAL.
    g_warn = p_msg.
  ELSE.
    g_warn = |{ g_warn } / { p_msg }|.
  ENDIF.
ENDFORM.                    " ADD_WARNING

*&---------------------------------------------------------------------*
*&      Form  DISPLAY_MAIN
*&---------------------------------------------------------------------*
*       S10: 대화식 = 컨테이너 SALV(툴바 버튼), 백그라운드 = 스풀 출력
*----------------------------------------------------------------------*
FORM display_main.
  DATA: lo_func   TYPE REF TO cl_salv_functions_list,
        lo_sel    TYPE REF TO cl_salv_selections,
        lo_events TYPE REF TO cl_salv_events_table,
        lo_layout TYPE REF TO cl_salv_layout,
        lo_disp   TYPE REF TO cl_salv_display_settings,
        ls_key    TYPE salv_s_layout_key,
        l_title   TYPE lvc_title,
        l_icon    TYPE string,
        l_text    TYPE string,
        l_tip     TYPE string,
        l_num     TYPE string,
        l_msg     TYPE string,
        lx_salv   TYPE REF TO cx_salv_error.

  IF gt_main IS INITIAL.
    RETURN.
  ENDIF.

  TRY.
      IF sy-batch IS INITIAL.
        cl_salv_table=>factory(
          EXPORTING
            r_container  = cl_gui_container=>default_screen
          IMPORTING
            r_salv_table = g_main
          CHANGING
            t_table      = gt_main ).
      ELSE.
        cl_salv_table=>factory(
          IMPORTING
            r_salv_table = g_main
          CHANGING
            t_table      = gt_main ).
      ENDIF.

      lo_func = g_main->get_functions( ).
      lo_func->set_all( abap_true ).

      IF sy-batch IS INITIAL.
        " GUI 상태 없이 툴바 버튼 추가 (컨테이너 모드만 가능)
        l_icon = icon_select_detail.
        l_text = TEXT-f01.
        l_tip  = TEXT-f02.
        lo_func->add_function( name     = c_fc_detail
                               icon     = l_icon
                               text     = l_text
                               tooltip  = l_tip
                               position = if_salv_c_function_position=>right_of_salv_functions ).
        l_icon = icon_compare.
        l_text = TEXT-f03.
        l_tip  = TEXT-f04.
        lo_func->add_function( name     = c_fc_recon
                               icon     = l_icon
                               text     = l_text
                               tooltip  = l_tip
                               position = if_salv_c_function_position=>right_of_salv_functions ).

        lo_sel = g_main->get_selections( ).
        lo_sel->set_selection_mode( if_salv_c_selection_mode=>row_column ).

        CREATE OBJECT g_handler.
        lo_events = g_main->get_event( ).
        SET HANDLER g_handler->on_added_function FOR lo_events.
      ENDIF.

      PERFORM set_columns USING g_main c_kind_main.
      PERFORM set_sort_total USING g_main c_kind_main.

      lo_layout = g_main->get_layout( ).
      ls_key-report = sy-repid.
      ls_key-handle = c_handle_main.
      lo_layout->set_key( ls_key ).
      lo_layout->set_save_restriction( if_salv_c_layout=>restrict_none ).
      lo_layout->set_default( abap_true ).
      IF pa_vari IS NOT INITIAL.
        lo_layout->set_initial_layout( pa_vari ).
      ENDIF.

      l_title = |{ TEXT-t01 } ({ gs_sel-budat_from DATE = USER } ~ { gs_sel-budat_to DATE = USER })|.
      lo_disp = g_main->get_display_settings( ).
      lo_disp->set_list_header( l_title ).
      lo_disp->set_striped_pattern( abap_true ).

    CATCH cx_salv_error INTO lx_salv.
      l_msg = lx_salv->get_text( ).
      MESSAGE l_msg TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
  ENDTRY.

  " 상태줄: 경고가 있으면 경고, 없으면 건수 + 취소전표 안내
  IF g_warn IS NOT INITIAL.
    MESSAGE g_warn TYPE 'S' DISPLAY LIKE 'W'.
  ELSE.
    l_msg = TEXT-m02.
    l_num = |{ lines( gt_main ) }|.
    REPLACE '&1' IN l_msg WITH l_num.
    l_msg = |{ l_msg } { TEXT-m10 }|.
    MESSAGE l_msg TYPE 'S'.
  ENDIF.

  g_main->display( ).

  IF sy-batch IS INITIAL.
    " 리스트 화면을 띄워 default_screen 컨테이너를 표시
    WRITE space.
  ENDIF.
ENDFORM.                    " DISPLAY_MAIN

*&---------------------------------------------------------------------*
*&      Form  SET_COLUMNS
*&---------------------------------------------------------------------*
*       컬럼 헤더(Text Symbol)·키·숨김·수량 단위·체크박스
*----------------------------------------------------------------------*
FORM set_columns USING io_salv TYPE REF TO cl_salv_table
                       p_kind  TYPE c
                 RAISING cx_salv_error.
  DATA: lo_cols TYPE REF TO cl_salv_columns_table,
        lo_col  TYPE REF TO cl_salv_column_table,
        lt_cols TYPE salv_t_column_ref,
        ls_col  TYPE salv_s_column_ref,
        l_text  TYPE string,
        l_qty   TYPE abap_bool,
        l_hide  TYPE abap_bool,
        l_key   TYPE abap_bool.

  lo_cols = io_salv->get_columns( ).
  lt_cols = lo_cols->get( ).

  LOOP AT lt_cols INTO ls_col.
    lo_col ?= ls_col-r_column.

    PERFORM get_col_text USING ls_col-columnname CHANGING l_text.
    IF l_text IS NOT INITIAL.
      PERFORM set_col_text USING lo_col l_text.
    ENDIF.
    lo_col->set_optimized( abap_true ).

    " 수량 컬럼 -> 단위 MEINS
    CASE ls_col-columnname.
      WHEN 'BEG_QTY' OR 'ZPO_GR' OR 'ZPP_GR' OR 'ZTP_GR' OR 'ZRE_GR' OR 'ZOT_GR'
        OR 'GR_SUM' OR 'ZSD_GI' OR 'ZPP_GI' OR 'ZTP_GI' OR 'ZSP_GI' OR 'ZOT_GI'
        OR 'GI_SUM' OR 'ZCLSTC' OR 'END_QTY' OR 'UML_BEG' OR 'UML_CHG' OR 'UML_END'
        OR 'VALUE' OR 'SLOC_END' OR 'TRNS_END' OR 'CALC_SUM' OR 'VAL_QTY' OR 'DIFF'.
        l_qty = abap_true.
      WHEN OTHERS.
        l_qty = abap_false.
    ENDCASE.
    IF l_qty = abap_true.
      lo_col->set_quantity_column( 'MEINS' ).
    ENDIF.

    " 키·숨김 (설계 8.1~8.4)
    l_key  = abap_false.
    l_hide = abap_false.
    CASE p_kind.
      WHEN c_kind_main.
        CASE ls_col-columnname.
          WHEN 'WERKS' OR 'MATNR' OR 'LGORT'.
            l_key = abap_true.
          WHEN 'NAME1' OR 'VSLOC' OR 'XCHPF' OR 'ZCLSTC' OR 'UML_BEG' OR 'UML_CHG'.
            l_hide = abap_true.
          WHEN OTHERS.
        ENDCASE.
      WHEN c_kind_btch.
        CASE ls_col-columnname.
          WHEN 'WERKS' OR 'MATNR' OR 'LGORT' OR 'CHARG'.
            l_key = abap_true.
          WHEN 'MAKTX' OR 'ZCLSTC' OR 'UML_BEG' OR 'UML_CHG'.
            l_hide = abap_true.
          WHEN OTHERS.
        ENDCASE.
      WHEN c_kind_docs.
        CASE ls_col-columnname.
          WHEN 'MBLNR'.
            l_key = abap_true.
          WHEN 'KIND' OR 'WERKS' OR 'MATNR' OR 'FNAME'.
            l_hide = abap_true.
          WHEN OTHERS.
        ENDCASE.
      WHEN c_kind_recn.
        CASE ls_col-columnname.
          WHEN 'WERKS' OR 'MATNR'.
            l_key = abap_true.
          WHEN OTHERS.
        ENDCASE.
      WHEN OTHERS.
    ENDCASE.

    IF l_key = abap_true.
      lo_col->set_key( abap_true ).
    ENDIF.
    IF l_hide = abap_true.
      lo_col->set_visible( abap_false ).
    ENDIF.

    " 'X'/공란 플래그는 체크박스 표시 (wiki 패턴)
    IF ls_col-columnname = 'XCHPF' OR ls_col-columnname = 'VSLOC'.
      lo_col->set_cell_type( if_salv_c_cell_type=>checkbox ).
    ENDIF.
  ENDLOOP.
ENDFORM.                    " SET_COLUMNS

*&---------------------------------------------------------------------*
*&      Form  SET_SORT_TOTAL
*&---------------------------------------------------------------------*
*       정렬·소계·합계
*----------------------------------------------------------------------*
FORM set_sort_total USING io_salv TYPE REF TO cl_salv_table
                          p_kind  TYPE c
                    RAISING cx_salv_error.
  DATA: lo_sorts TYPE REF TO cl_salv_sorts,
        lo_aggr  TYPE REF TO cl_salv_aggregations,
        lt_fname TYPE zcl_mm_sloc_ledger=>ty_t_fname,
        l_fname  TYPE lvc_fname.

  lo_sorts = io_salv->get_sorts( ).
  lo_aggr  = io_salv->get_aggregations( ).

  CASE p_kind.
    WHEN c_kind_main.
      lo_sorts->add_sort( columnname = 'WERKS' subtotal = abap_true ).
      lo_sorts->add_sort( columnname = 'MATNR' ).
      lt_fname = VALUE #( ( 'BEG_QTY' ) ( 'ZPO_GR' ) ( 'ZPP_GR' ) ( 'ZTP_GR' )
                          ( 'ZRE_GR' ) ( 'ZOT_GR' ) ( 'GR_SUM' ) ( 'ZSD_GI' )
                          ( 'ZPP_GI' ) ( 'ZTP_GI' ) ( 'ZSP_GI' ) ( 'ZOT_GI' )
                          ( 'GI_SUM' ) ( 'ZCLSTC' ) ( 'END_QTY' ) ( 'UML_BEG' )
                          ( 'UML_CHG' ) ( 'UML_END' ) ).
    WHEN c_kind_btch.
      lo_sorts->add_sort( columnname = 'WERKS' ).
      lo_sorts->add_sort( columnname = 'MATNR' ).
      lo_sorts->add_sort( columnname = 'LGORT' subtotal = abap_true ).
      lo_sorts->add_sort( columnname = 'CHARG' ).
      lt_fname = VALUE #( ( 'BEG_QTY' ) ( 'ZPO_GR' ) ( 'ZPP_GR' ) ( 'ZTP_GR' )
                          ( 'ZRE_GR' ) ( 'ZOT_GR' ) ( 'GR_SUM' ) ( 'ZSD_GI' )
                          ( 'ZPP_GI' ) ( 'ZTP_GI' ) ( 'ZSP_GI' ) ( 'ZOT_GI' )
                          ( 'GI_SUM' ) ( 'ZCLSTC' ) ( 'END_QTY' ) ( 'UML_BEG' )
                          ( 'UML_CHG' ) ( 'UML_END' ) ).
    WHEN c_kind_docs.
      lt_fname = VALUE #( ( 'VALUE' ) ).
    WHEN c_kind_recn.
      lo_sorts->add_sort( columnname = 'WERKS' ).
      lo_sorts->add_sort( columnname = 'MATNR' ).
    WHEN OTHERS.
  ENDCASE.

  LOOP AT lt_fname INTO DATA(l_name).
    l_fname = l_name.
    lo_aggr->add_aggregation( columnname = l_fname ).
  ENDLOOP.
ENDFORM.                    " SET_SORT_TOTAL

*&---------------------------------------------------------------------*
*&      Form  SET_COL_TEXT
*&---------------------------------------------------------------------*
FORM set_col_text USING io_col  TYPE REF TO cl_salv_column_table
                        p_text  TYPE csequence.
  DATA: l_short  TYPE scrtext_s,
        l_medium TYPE scrtext_m,
        l_long   TYPE scrtext_l.

  l_short  = p_text.
  l_medium = p_text.
  l_long   = p_text.
  io_col->set_short_text( l_short ).
  io_col->set_medium_text( l_medium ).
  io_col->set_long_text( l_long ).
ENDFORM.                    " SET_COL_TEXT

*&---------------------------------------------------------------------*
*&      Form  GET_COL_TEXT
*&---------------------------------------------------------------------*
*       컬럼명 -> 헤더 Text Symbol (문서 목록의 반영 컬럼에도 사용)
*----------------------------------------------------------------------*
FORM get_col_text USING    p_name TYPE csequence
                  CHANGING p_text TYPE string.
  CLEAR p_text.
  CASE p_name.
    WHEN 'WERKS'.    p_text = TEXT-c01.
    WHEN 'NAME1'.    p_text = TEXT-c02.
    WHEN 'MATNR'.    p_text = TEXT-c03.
    WHEN 'MAKTX'.    p_text = TEXT-c04.
    WHEN 'LGORT'.    p_text = TEXT-c05.
    WHEN 'LGOBE'.    p_text = TEXT-c06.
    WHEN 'VSLOC'.    p_text = TEXT-c07.
    WHEN 'XCHPF'.    p_text = TEXT-c08.
    WHEN 'MEINS'.    p_text = TEXT-c09.
    WHEN 'BEG_QTY'.  p_text = TEXT-c10.
    WHEN 'ZPO_GR'.   p_text = TEXT-c11.
    WHEN 'ZPP_GR'.   p_text = TEXT-c12.
    WHEN 'ZTP_GR'.   p_text = TEXT-c13.
    WHEN 'ZRE_GR'.   p_text = TEXT-c14.
    WHEN 'ZOT_GR'.   p_text = TEXT-c15.
    WHEN 'GR_SUM'.   p_text = TEXT-c16.
    WHEN 'ZSD_GI'.   p_text = TEXT-c17.
    WHEN 'ZPP_GI'.   p_text = TEXT-c18.
    WHEN 'ZTP_GI'.   p_text = TEXT-c19.
    WHEN 'ZSP_GI'.   p_text = TEXT-c20.
    WHEN 'ZOT_GI'.   p_text = TEXT-c21.
    WHEN 'GI_SUM'.   p_text = TEXT-c22.
    WHEN 'ZCLSTC'.   p_text = TEXT-c23.
    WHEN 'END_QTY'.  p_text = TEXT-c24.
    WHEN 'UML_BEG'.  p_text = TEXT-c25.
    WHEN 'UML_CHG' OR 'UML'.
                     p_text = TEXT-c26.
    WHEN 'UML_END'.  p_text = TEXT-c27.
    WHEN 'CHARG'.    p_text = TEXT-c28.
    WHEN 'KINDTX'.   p_text = TEXT-c29.
    WHEN 'BUDAT'.    p_text = TEXT-c30.
    WHEN 'MBLNR'.    p_text = TEXT-c31.
    WHEN 'MJAHR'.    p_text = TEXT-c32.
    WHEN 'ZEILE'.    p_text = TEXT-c33.
    WHEN 'BWART'.    p_text = TEXT-c34.
    WHEN 'SHKZG'.    p_text = TEXT-c35.
    WHEN 'UMLGO'.    p_text = TEXT-c36.
    WHEN 'COLTX'.    p_text = TEXT-c37.
    WHEN 'VALUE'.    p_text = TEXT-c38.
    WHEN 'SLOC_END'. p_text = TEXT-c39.
    WHEN 'TRNS_END'. p_text = TEXT-c41.
    WHEN 'CALC_SUM'. p_text = TEXT-c42.
    WHEN 'VAL_QTY'.  p_text = TEXT-c43.
    WHEN 'DIFF'.     p_text = TEXT-c44.
    WHEN 'XAUTO'.    p_text = TEXT-c45.
    WHEN OTHERS.
  ENDCASE.
ENDFORM.                    " GET_COL_TEXT

*&---------------------------------------------------------------------*
*&      Form  GET_SELECTED_KEYS
*&---------------------------------------------------------------------*
*       메인 ALV 선택 행 -> 키 (SALV 행 인덱스 = GT_MAIN 인덱스)
*----------------------------------------------------------------------*
FORM get_selected_keys CHANGING pt_key TYPE zcl_mm_sloc_ledger=>ty_t_key.
  DATA: lo_sel  TYPE REF TO cl_salv_selections,
        lt_rows TYPE salv_t_row,
        ls_key  TYPE zcl_mm_sloc_ledger=>ty_s_key.

  CLEAR pt_key.
  IF g_main IS NOT BOUND.
    RETURN.
  ENDIF.
  lo_sel  = g_main->get_selections( ).
  lt_rows = lo_sel->get_selected_rows( ).
  LOOP AT lt_rows INTO DATA(l_row).
    READ TABLE gt_main ASSIGNING FIELD-SYMBOL(<ls_main>) INDEX l_row.
    IF sy-subrc <> 0.
      CONTINUE.
    ENDIF.
    ls_key-werks = <ls_main>-werks.
    ls_key-matnr = <ls_main>-matnr.
    ls_key-lgort = <ls_main>-lgort.
    APPEND ls_key TO pt_key.
  ENDLOOP.
ENDFORM.                    " GET_SELECTED_KEYS

*&---------------------------------------------------------------------*
*&      Form  SHOW_BATCH_DETAIL
*&---------------------------------------------------------------------*
*       S11: 선택 행의 배치 단위 수불 팝업
*----------------------------------------------------------------------*
FORM show_batch_detail.
  DATA: lt_key    TYPE zcl_mm_sloc_ledger=>ty_t_key,
        lt_diff   TYPE zcl_mm_sloc_ledger=>ty_t_key,
        l_diff    TYPE mseg-menge,
        l_popup   TYPE REF TO cl_salv_table,
        lo_func   TYPE REF TO cl_salv_functions_list,
        lo_events TYPE REF TO cl_salv_events_table,
        lo_layout TYPE REF TO cl_salv_layout,
        lo_disp   TYPE REF TO cl_salv_display_settings,
        ls_lkey   TYPE salv_s_layout_key,
        l_title   TYPE lvc_title,
        l_period  TYPE string,
        l_num     TYPE string,
        l_msg     TYPE string,
        lx_salv   TYPE REF TO cx_salv_error.

  PERFORM get_selected_keys CHANGING lt_key.
  IF lt_key IS INITIAL.
    MESSAGE TEXT-m03 TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  g_ledger->get_batch( EXPORTING it_key      = lt_key
                       IMPORTING et_batch    = gt_batch
                                 et_diff_key = lt_diff
                                 ev_diff_qty = l_diff ).
  IF gt_batch IS INITIAL.
    MESSAGE TEXT-m04 TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  l_period = |({ gs_sel-budat_from DATE = USER } ~ { gs_sel-budat_to DATE = USER })|.
  IF lines( lt_key ) = 1.
    READ TABLE lt_key INTO DATA(ls_key) INDEX 1.
    l_title = |{ TEXT-t02 } - { ls_key-werks } / { ls_key-matnr ALPHA = OUT } / { ls_key-lgort } { l_period }|.
  ELSE.
    l_msg = TEXT-t03.
    l_num = |{ lines( lt_key ) }|.
    REPLACE '&1' IN l_msg WITH l_num.
    l_title = |{ TEXT-t02 } - { l_msg } { l_period }|.
  ENDIF.

  TRY.
      cl_salv_table=>factory( IMPORTING r_salv_table = l_popup
                              CHANGING  t_table      = gt_batch ).
      l_popup->set_screen_popup( start_column = c_pop_scol
                                 end_column   = c_pop_ecol
                                 start_line   = c_pop_slin
                                 end_line     = c_pop_elin ).
      lo_func = l_popup->get_functions( ).
      lo_func->set_all( abap_true ).

      PERFORM set_columns USING l_popup c_kind_btch.
      PERFORM set_sort_total USING l_popup c_kind_btch.

      lo_layout = l_popup->get_layout( ).
      ls_lkey-report = sy-repid.
      ls_lkey-handle = c_handle_btch.
      lo_layout->set_key( ls_lkey ).
      lo_layout->set_save_restriction( if_salv_c_layout=>restrict_none ).

      lo_disp = l_popup->get_display_settings( ).
      lo_disp->set_list_header( l_title ).

      lo_events = l_popup->get_event( ).
      SET HANDLER g_handler->on_double_click_batch FOR lo_events.
    CATCH cx_salv_error INTO lx_salv.
      l_msg = lx_salv->get_text( ).
      MESSAGE l_msg TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
  ENDTRY.

  " 배치 합계 <> 메인 행이면 경고 (이력 공백·MCHBH 누락 감지)
  IF lt_diff IS NOT INITIAL.
    l_msg = TEXT-w02.
    l_num = |{ l_diff }|.
    REPLACE '&1' IN l_msg WITH l_num.
    MESSAGE l_msg TYPE 'S' DISPLAY LIKE 'W'.
  ELSE.
    l_msg = TEXT-m06.
    l_num = |{ lines( gt_batch ) }|.
    REPLACE '&1' IN l_msg WITH l_num.
    MESSAGE l_msg TYPE 'S'.
  ENDIF.

  l_popup->display( ).

  SET HANDLER g_handler->on_double_click_batch FOR lo_events ACTIVATION abap_false.
ENDFORM.                    " SHOW_BATCH_DETAIL

*&---------------------------------------------------------------------*
*&      Form  SHOW_DOCS
*&---------------------------------------------------------------------*
*       S12: 배치 상세 행 더블클릭 -> 자재문서 목록 팝업
*----------------------------------------------------------------------*
FORM show_docs USING p_row TYPE salv_de_row.
  DATA: ls_dkey   TYPE zcl_mm_sloc_ledger=>ty_s_dkey,
        l_popup   TYPE REF TO cl_salv_table,
        lo_func   TYPE REF TO cl_salv_functions_list,
        lo_events TYPE REF TO cl_salv_events_table,
        lo_layout TYPE REF TO cl_salv_layout,
        lo_disp   TYPE REF TO cl_salv_display_settings,
        ls_lkey   TYPE salv_s_layout_key,
        l_title   TYPE lvc_title,
        l_text    TYPE string,
        l_msg     TYPE string,
        lx_salv   TYPE REF TO cx_salv_error.

  READ TABLE gt_batch ASSIGNING FIELD-SYMBOL(<ls_batch>) INDEX p_row.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.
  ls_dkey-werks = <ls_batch>-werks.
  ls_dkey-matnr = <ls_batch>-matnr.
  ls_dkey-lgort = <ls_batch>-lgort.
  ls_dkey-charg = <ls_batch>-charg.

  gt_doc = g_ledger->get_docs( ls_dkey ).
  IF gt_doc IS INITIAL.
    MESSAGE TEXT-m07 TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  LOOP AT gt_doc ASSIGNING FIELD-SYMBOL(<ls_doc>).
    IF <ls_doc>-kind = zcl_mm_sloc_ledger=>c_kind_beg.
      <ls_doc>-kindtx = TEXT-k01.
    ELSE.
      <ls_doc>-kindtx = TEXT-k02.
    ENDIF.
    PERFORM get_col_text USING <ls_doc>-fname CHANGING l_text.
    <ls_doc>-coltx = l_text.
  ENDLOOP.

  l_title = |{ TEXT-t05 } - { ls_dkey-werks } / { ls_dkey-matnr ALPHA = OUT } / { ls_dkey-lgort } / { ls_dkey-charg }|.

  TRY.
      cl_salv_table=>factory( IMPORTING r_salv_table = l_popup
                              CHANGING  t_table      = gt_doc ).
      l_popup->set_screen_popup( start_column = c_pop_scol
                                 end_column   = c_pop_ecol
                                 start_line   = c_pop_slin
                                 end_line     = c_pop_elin ).
      lo_func = l_popup->get_functions( ).
      lo_func->set_all( abap_true ).

      PERFORM set_columns USING l_popup c_kind_docs.
      PERFORM set_sort_total USING l_popup c_kind_docs.

      lo_layout = l_popup->get_layout( ).
      ls_lkey-report = sy-repid.
      ls_lkey-handle = c_handle_docs.
      lo_layout->set_key( ls_lkey ).
      lo_layout->set_save_restriction( if_salv_c_layout=>restrict_none ).

      lo_disp = l_popup->get_display_settings( ).
      lo_disp->set_list_header( l_title ).

      lo_events = l_popup->get_event( ).
      SET HANDLER g_handler->on_double_click_doc FOR lo_events.
    CATCH cx_salv_error INTO lx_salv.
      l_msg = lx_salv->get_text( ).
      MESSAGE l_msg TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
  ENDTRY.

  MESSAGE TEXT-m08 TYPE 'S'.
  l_popup->display( ).

  SET HANDLER g_handler->on_double_click_doc FOR lo_events ACTIVATION abap_false.
ENDFORM.                    " SHOW_DOCS

*&---------------------------------------------------------------------*
*&      Form  CALL_MB03
*&---------------------------------------------------------------------*
*       자재문서 더블클릭 -> MB03 (T-code 권한 사전 확인)
*----------------------------------------------------------------------*
FORM call_mb03 USING p_row TYPE salv_de_row.
  READ TABLE gt_doc ASSIGNING FIELD-SYMBOL(<ls_doc>) INDEX p_row.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  CALL FUNCTION 'AUTHORITY_CHECK_TCODE'
    EXPORTING
      tcode  = c_tcode_mb03
    EXCEPTIONS
      ok     = 0
      not_ok = 1
      OTHERS = 2.
  IF sy-subrc <> 0.
    MESSAGE TEXT-e06 TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  SET PARAMETER ID c_pid_mblnr FIELD <ls_doc>-mblnr.
  SET PARAMETER ID c_pid_mjahr FIELD <ls_doc>-mjahr.
  CALL TRANSACTION c_tcode_mb03 AND SKIP FIRST SCREEN.
ENDFORM.                    " CALL_MB03

*&---------------------------------------------------------------------*
*&      Form  SHOW_RECON
*&---------------------------------------------------------------------*
*       S13: 플랜트 대사 (저장위치 기말 + 이전중 + 운송중 vs MBEW/MBEWH)
*----------------------------------------------------------------------*
FORM show_recon.
  DATA: lt_key    TYPE zcl_mm_sloc_ledger=>ty_t_key,
        l_ok      TYPE abap_bool,
        l_cnt     TYPE i,
        l_num     TYPE string,
        l_popup   TYPE REF TO cl_salv_table,
        lo_func   TYPE REF TO cl_salv_functions_list,
        lo_layout TYPE REF TO cl_salv_layout,
        lo_disp   TYPE REF TO cl_salv_display_settings,
        ls_lkey   TYPE salv_s_layout_key,
        l_title   TYPE lvc_title,
        l_msg     TYPE string,
        lx_salv   TYPE REF TO cx_salv_error.

  " 선택 행이 있으면 그 플랜트·자재, 없으면 전체
  PERFORM get_selected_keys CHANGING lt_key.

  g_ledger->get_recon( EXPORTING it_key   = lt_key
                       IMPORTING et_recon = gt_recon
                                 ev_ok    = l_ok ).
  IF l_ok = abap_false.
    MESSAGE TEXT-w03 TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.
  IF gt_recon IS INITIAL.
    MESSAGE TEXT-m04 TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  l_title = |{ TEXT-t04 } { gs_sel-budat_to DATE = USER }|.

  TRY.
      cl_salv_table=>factory( IMPORTING r_salv_table = l_popup
                              CHANGING  t_table      = gt_recon ).
      l_popup->set_screen_popup( start_column = c_pop_scol
                                 end_column   = c_pop_ecol
                                 start_line   = c_pop_slin
                                 end_line     = c_pop_elin ).
      lo_func = l_popup->get_functions( ).
      lo_func->set_all( abap_true ).

      PERFORM set_columns USING l_popup c_kind_recn.
      PERFORM set_sort_total USING l_popup c_kind_recn.

      lo_layout = l_popup->get_layout( ).
      ls_lkey-report = sy-repid.
      ls_lkey-handle = c_handle_recn.
      lo_layout->set_key( ls_lkey ).
      lo_layout->set_save_restriction( if_salv_c_layout=>restrict_none ).

      lo_disp = l_popup->get_display_settings( ).
      lo_disp->set_list_header( l_title ).
    CATCH cx_salv_error INTO lx_salv.
      l_msg = lx_salv->get_text( ).
      MESSAGE l_msg TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
  ENDTRY.

  LOOP AT gt_recon TRANSPORTING NO FIELDS WHERE diff <> 0.
    l_cnt = l_cnt + 1.
  ENDLOOP.
  IF l_cnt > 0.
    l_msg = TEXT-w04.
    l_num = |{ l_cnt }|.
    REPLACE '&1' IN l_msg WITH l_num.
    MESSAGE l_msg TYPE 'S' DISPLAY LIKE 'W'.
  ELSE.
    MESSAGE TEXT-m09 TYPE 'S'.
  ENDIF.

  l_popup->display( ).
ENDFORM.                    " SHOW_RECON
