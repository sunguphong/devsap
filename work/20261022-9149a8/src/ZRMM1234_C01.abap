*&---------------------------------------------------------------------*
*& Include ZRMM1234_C01 - 로컬 클래스
*&   LCL_DATA : 조회·기간 계산·위치 집계·상세 캐시 (Q2~Q6)
*&   LCL_VIEW : 메인 SALV·[상세조회]·더블클릭·상세 팝업·MB51 (Q7~Q10)
*& 클래스 정의 문장은 콜론 체인 형식(CLASS: ...)으로 쓴다. 웹앱 반영 도구가
*& 이 INCLUDE를 전역 클래스로 오인하지 않게 하기 위함(03 문서 참고)
*&---------------------------------------------------------------------*

*----------------------------------------------------------------------*
* lcl_data 정의
*----------------------------------------------------------------------*
CLASS: lcl_data DEFINITION FINAL.
  PUBLIC SECTION.
    DATA: gt_t001w  TYPE ty_t_t001w READ-ONLY,   " 플랜트명
          gt_ctrl   TYPE ty_t_ctrl READ-ONLY,    " 집계 제어 정보
          g_mix_cnt TYPE i READ-ONLY.            " 단위 혼재 위치 수

    METHODS:
      "Q2 플랜트 존재·권한·집계 범위 확인, R_WERKS 구성
      check_plants
        RETURNING VALUE(rv_ok) TYPE abap_bool,
      "Q3 집계 테이블 A·B 조회
      read_data
        RETURNING VALUE(rv_found) TYPE abap_bool,
      "Q5 키별 기간 계산, 재고 0 제외, 상세 캐시(자재내역 포함)
      build_result,
      "Q6 플랜트+저장위치 집계
      build_main
        RETURNING VALUE(rv_found) TYPE abap_bool,
      get_main
        RETURNING VALUE(rt_main) TYPE ty_t_main,
      "Q9 선택 위치의 상세 (DB 조회 없음, D7)
      get_detail
        IMPORTING it_keys          TYPE zcl_mm_stkday_calc=>tt_loc_key
        RETURNING VALUE(rt_detail) TYPE ty_t_popup,
      "메인 제목용 제어 정보 (허용 플랜트 중 첫 플랜트)
      get_first_ctrl
        RETURNING VALUE(rs_ctrl) TYPE ztmm1237.

  PRIVATE SECTION.
    DATA: gt_t001l  TYPE ty_t_t001l,
          gt_a      TYPE ty_t_a,
          gt_b      TYPE ty_t_b,
          gt_matres TYPE ty_t_matres,
          gt_detail TYPE ty_t_detail,
          gt_main   TYPE ty_t_main.

    METHODS:
      read_texts
        IMPORTING it_sum TYPE zcl_mm_stkday_calc=>tt_loc_sum,
      read_makt,
      get_low_end
        IMPORTING iv_werks      TYPE werks_d
        RETURNING VALUE(rv_low) TYPE budat,
      show_partial_warning
        IMPORTING it_werks  TYPE STANDARD TABLE
                  iv_msgno  TYPE symsgno
                  iv_date   TYPE d OPTIONAL,
      plant_list
        IMPORTING it_werks       TYPE STANDARD TABLE
        RETURNING VALUE(rv_list) TYPE symsgv,
      date_text
        IMPORTING iv_date       TYPE d
        RETURNING VALUE(rv_text) TYPE symsgv.
ENDCLASS.

*----------------------------------------------------------------------*
* lcl_view 정의
*----------------------------------------------------------------------*
CLASS: lcl_view DEFINITION FINAL.
  PUBLIC SECTION.
    METHODS:
      constructor
        IMPORTING io_data TYPE REF TO lcl_data,
      "Q7 메인 ALV 표시
      display_main.

  PRIVATE SECTION.
    DATA: g_data    TYPE REF TO lcl_data,
          g_main    TYPE REF TO cl_salv_table,
          gt_main   TYPE ty_t_main,       " SALV CHANGING 대상(GET_MAIN 복사본)
          gt_popup  TYPE ty_t_popup.      " 현재 팝업 데이터(더블클릭 인덱스용)

    METHODS:
      "Q8 [상세조회] (ADDED_FUNCTION)
      on_user_command FOR EVENT added_function OF cl_salv_events_table
        IMPORTING e_salv_function,
      "Q8 메인 더블클릭: 그 행 하나
      on_double_click FOR EVENT double_click OF cl_salv_events_table
        IMPORTING row column,
      get_selected_keys
        RETURNING VALUE(rt_keys) TYPE zcl_mm_stkday_calc=>tt_loc_key,
      "Q9 상세 팝업
      show_detail
        IMPORTING it_keys TYPE zcl_mm_stkday_calc=>tt_loc_key,
      "Q10 팝업 더블클릭 -> MB51
      on_popup_double_click FOR EVENT double_click OF cl_salv_events_table
        IMPORTING row column,
      call_mb51
        IMPORTING is_detail TYPE ty_detail,
      set_main_columns
        IMPORTING io_salv TYPE REF TO cl_salv_table
        RAISING   cx_salv_error,
      set_popup_columns
        IMPORTING io_salv TYPE REF TO cl_salv_table
        RAISING   cx_salv_error,
      set_column
        IMPORTING io_columns   TYPE REF TO cl_salv_columns_table
                  iv_name      TYPE csequence
                  iv_text      TYPE csequence
                  iv_quantity  TYPE abap_bool DEFAULT abap_false
                  iv_hide_zero TYPE abap_bool DEFAULT abap_false
        RAISING   cx_salv_error,
      get_period_text
        RETURNING VALUE(rv_text) TYPE string.
ENDCLASS.

*----------------------------------------------------------------------*
* CLASS lcl_data IMPLEMENTATION
*----------------------------------------------------------------------*
CLASS lcl_data IMPLEMENTATION.

  METHOD check_plants.
    DATA: ls_t001w   TYPE ty_t001w,
          ls_ctrl    TYPE ztmm1237,
          l_code     TYPE zcl_mm_stkday_calc=>ty_chk_code,
          lt_noauth  TYPE STANDARD TABLE OF werks_d WITH EMPTY KEY,
          lt_notld   TYPE STANDARD TABLE OF werks_d WITH EMPTY KEY,
          lt_tolast  TYPE STANDARD TABLE OF werks_d WITH EMPTY KEY,
          lt_ldfrom  TYPE STANDARD TABLE OF werks_d WITH EMPTY KEY,
          l_last006  TYPE budat,
          l_load008  TYPE budat,
          l_dly_wrk  TYPE werks_d,
          ls_dly     TYPE ztmm1237,
          l_yday     TYPE d,
          l_v1       TYPE symsgv,
          l_v2       TYPE symsgv,
          l_v3       TYPE symsgv.

    rv_ok = abap_false.
    CLEAR: r_werks, gt_t001w, gt_ctrl.

    " 방어: 플랜트 미입력(OBLIGATORY라 정상 경로에서는 없음)
    IF so_werks[] IS INITIAL.
      MESSAGE s003 DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    " ① 플랜트 존재·플랜트명
    SELECT werks, name1 FROM t001w
      INTO TABLE @gt_t001w
      WHERE werks IN @so_werks.
    IF sy-subrc <> 0.
      MESSAGE s004 DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    " 제어 정보 (한 번에 읽음)
    SELECT * FROM ztmm1237
      INTO TABLE @gt_ctrl
      WHERE werks IN @so_werks.

    l_yday = sy-datum - 1.

    LOOP AT gt_t001w INTO ls_t001w.
      " ② 플랜트 권한 M_MSEG_WMB 표시
      AUTHORITY-CHECK OBJECT c_auth_wmb
        ID 'ACTVT' FIELD c_actvt_disp
        ID 'WERKS' FIELD ls_t001w-werks.
      IF sy-subrc <> 0.
        APPEND ls_t001w-werks TO lt_noauth.
        CONTINUE.
      ENDIF.

      " ③ 집계 범위 (미집계 / To > 최종 집계일 / From < 적재 시작일)
      CLEAR ls_ctrl.
      READ TABLE gt_ctrl INTO ls_ctrl WITH TABLE KEY werks = ls_t001w-werks.
      l_code = zcl_mm_stkday_calc=>check_period( iv_from       = pa_budfr
                                                 iv_to         = pa_budto
                                                 iv_today      = sy-datum
                                                 iv_with_ctrl  = abap_true
                                                 iv_load_from  = ls_ctrl-load_from
                                                 iv_last_budat = ls_ctrl-last_budat ).
      CASE l_code.
        WHEN zcl_mm_stkday_calc=>c_chk_ok.
          APPEND VALUE #( sign = c_sel_sign option = c_sel_eq low = ls_t001w-werks )
            TO r_werks.
          " ⑤ 집계 지연·실패 (첫 플랜트 기준으로 한 번 표시)
          IF l_dly_wrk IS INITIAL
             AND ( ls_ctrl-run_stat = zcl_mm_stkday_calc=>c_stat_error
                OR ls_ctrl-run_stat = zcl_mm_stkday_calc=>c_stat_running
                OR ls_ctrl-last_budat < l_yday ).
            l_dly_wrk = ls_t001w-werks.
            ls_dly    = ls_ctrl.
          ENDIF.
        WHEN zcl_mm_stkday_calc=>c_chk_not_loaded.
          APPEND ls_t001w-werks TO lt_notld.
        WHEN zcl_mm_stkday_calc=>c_chk_to_gt_last.
          IF lt_tolast IS INITIAL.
            l_last006 = ls_ctrl-last_budat.
          ENDIF.
          APPEND ls_t001w-werks TO lt_tolast.
        WHEN zcl_mm_stkday_calc=>c_chk_from_lt_ld.
          IF lt_ldfrom IS INITIAL.
            l_load008 = ls_ctrl-load_from.
          ENDIF.
          APPEND ls_t001w-werks TO lt_ldfrom.
        WHEN zcl_mm_stkday_calc=>c_chk_from_gt_to.
          MESSAGE s001 DISPLAY LIKE 'E'.
          RETURN.
        WHEN OTHERS.
          MESSAGE s002 DISPLAY LIKE 'E'.
          RETURN.
      ENDCASE.
    ENDLOOP.

    " ④ 남은 플랜트가 없으면 사유에 맞는 오류 후 선택화면으로 (우선순위 005 > 007 > 006 > 008)
    IF r_werks IS INITIAL.
      IF lt_noauth IS NOT INITIAL.
        l_v1 = plant_list( lt_noauth ).
        MESSAGE s005 DISPLAY LIKE 'E' WITH l_v1.
      ELSEIF lt_notld IS NOT INITIAL.
        l_v1 = plant_list( lt_notld ).
        MESSAGE s007 DISPLAY LIKE 'E' WITH l_v1.
      ELSEIF lt_tolast IS NOT INITIAL.
        l_v1 = plant_list( lt_tolast ).
        l_v2 = date_text( l_last006 ).
        MESSAGE s006 DISPLAY LIKE 'E' WITH l_v1 l_v2.
      ELSE.
        l_v1 = plant_list( lt_ldfrom ).
        l_v2 = date_text( l_load008 ).
        MESSAGE s008 DISPLAY LIKE 'E' WITH l_v1 l_v2.
      ENDIF.
      RETURN.
    ENDIF.

    " 일부 제외: 사유별 경고 (메인 상태줄 메시지에 덮이지 않도록 팝업으로 표시)
    show_partial_warning( it_werks = lt_noauth iv_msgno = '005' ).
    show_partial_warning( it_werks = lt_notld  iv_msgno = '007' ).
    show_partial_warning( it_werks = lt_tolast iv_msgno = '006' iv_date = l_last006 ).
    show_partial_warning( it_werks = lt_ldfrom iv_msgno = '008' iv_date = l_load008 ).

    " ⑤ 집계 지연·실패 경고 W 009
    IF l_dly_wrk IS NOT INITIAL.
      l_v1 = date_text( ls_dly-last_cpudt ).
      l_v2 = |{ ls_dly-last_cputm TIME = USER }|.
      l_v3 = l_dly_wrk.
      MESSAGE i009 DISPLAY LIKE 'W' WITH l_v1 l_v2 l_v3.
    ENDIF.

    rv_ok = abap_true.
  ENDMETHOD.


  METHOD read_data.
    DATA l_low TYPE budat.

    rv_found = abap_false.
    CLEAR: gt_a, gt_b, r_stkcat.

    " 빈 range로 전체 조회되지 않게 방어
    IF r_werks IS INITIAL.
      RETURN.
    ENDIF.

    " 읽는 하한 = min(From, 월초(To))
    l_low = zcl_mm_stkday_calc=>month_start( pa_budto ).
    IF pa_budfr < l_low.
      l_low = pa_budfr.
    ENDIF.

    " 저장위치를 입력하면 '(운송중)' 행 미표시 (Q7)
    IF so_lgort[] IS NOT INITIAL.
      APPEND VALUE #( sign = c_sel_sign option = c_sel_eq
                      low = zcl_mm_stkday_calc=>c_stk_loc ) TO r_stkcat.
    ENDIF.

    " A: 자재 레벨 (메인 수량 원천)
    SELECT a~werks, a~lgort, a~matnr, a~stkcat, a~budat, a~meins,
           a~gr_qty, a~gi_qty, a~end_qty, a~k_end, a~e_end, a~trf_end
      FROM ztmm1234 AS a
      INNER JOIN mara AS m ON m~matnr = a~matnr
      INTO CORRESPONDING FIELDS OF TABLE @gt_a
      WHERE a~werks  IN @r_werks
        AND a~budat  BETWEEN @l_low AND @pa_budto
        AND a~lgort  IN @so_lgort
        AND a~matnr  IN @so_matnr
        AND m~mtart  IN @so_mtart
        AND m~matkl  IN @so_matkl
        AND a~stkcat IN @r_stkcat.

    " B: 배치 레벨 (상세, SO_CHARG 입력 시 메인 수량 원천)
    SELECT b~werks, b~lgort, b~matnr, b~charg, b~stkcat, b~budat, b~meins,
           b~gr_qty, b~gi_qty, b~end_qty, b~k_end, b~e_end, b~trf_end
      FROM ztmm1236 AS b
      INNER JOIN mara AS m ON m~matnr = b~matnr
      INTO CORRESPONDING FIELDS OF TABLE @gt_b
      WHERE b~werks  IN @r_werks
        AND b~budat  BETWEEN @l_low AND @pa_budto
        AND b~lgort  IN @so_lgort
        AND b~matnr  IN @so_matnr
        AND b~charg  IN @so_charg
        AND m~mtart  IN @so_mtart
        AND m~matkl  IN @so_matkl
        AND b~stkcat IN @r_stkcat.

    IF gt_a IS NOT INITIAL OR gt_b IS NOT INITIAL.
      rv_found = abap_true.
    ENDIF.
  ENDMETHOD.


  METHOD build_result.
    DATA: lt_in     TYPE zcl_mm_stkday_calc=>tt_period_in,
          ls_in     TYPE zcl_mm_stkday_calc=>ty_period_in,
          ls_period TYPE zcl_mm_stkday_calc=>ty_period,
          ls_matres TYPE ty_matres,
          ls_detail TYPE ty_detail,
          l_lines   TYPE i,
          l_idx     TYPE i,
          l_next    TYPE i,
          l_flush   TYPE abap_bool.
    FIELD-SYMBOLS: <ls_a>  TYPE ty_a,
                   <ls_an> TYPE ty_a,
                   <ls_b>  TYPE ty_b,
                   <ls_bn> TYPE ty_b.

    CLEAR: gt_matres, gt_detail.

    "-- ① A: 키(플랜트·재고구분·저장위치·자재)별 기간 계산 -> GT_MATRES
    SORT gt_a BY werks stkcat lgort matnr budat.
    l_lines = lines( gt_a ).
    LOOP AT gt_a ASSIGNING <ls_a>.
      l_idx = sy-tabix.
      CLEAR ls_in.
      MOVE-CORRESPONDING <ls_a> TO ls_in.
      APPEND ls_in TO lt_in.

      " 다음 행의 키가 다르면(또는 마지막 행) 계산
      l_flush = abap_true.
      IF l_idx < l_lines.
        l_next = l_idx + 1.
        READ TABLE gt_a ASSIGNING <ls_an> INDEX l_next.
        IF <ls_an>-werks = <ls_a>-werks AND <ls_an>-stkcat = <ls_a>-stkcat
           AND <ls_an>-lgort = <ls_a>-lgort AND <ls_an>-matnr = <ls_a>-matnr.
          l_flush = abap_false.
        ENDIF.
      ENDIF.
      CHECK l_flush = abap_true.

      ls_period = zcl_mm_stkday_calc=>calc_period( it_row  = lt_in
                                                   iv_from = pa_budfr
                                                   iv_to   = pa_budto
                                                   iv_low  = get_low_end( <ls_a>-werks ) ).
      CLEAR lt_in.
      " ③ 재고 0 행 제외
      IF pa_nozer = abap_true AND zcl_mm_stkday_calc=>is_zero_result( ls_period ) = abap_true.
        CONTINUE.
      ENDIF.
      CLEAR ls_matres.
      ls_matres-werks  = <ls_a>-werks.
      ls_matres-lgort  = <ls_a>-lgort.
      ls_matres-stkcat = <ls_a>-stkcat.
      ls_matres-matnr  = <ls_a>-matnr.
      ls_matres-meins  = <ls_a>-meins.
      MOVE-CORRESPONDING ls_period TO ls_matres.
      INSERT ls_matres INTO TABLE gt_matres.
    ENDLOOP.

    "-- ② B: 키(+배치)별 같은 방식 -> GT_DETAIL (상세 캐시)
    CLEAR lt_in.
    SORT gt_b BY werks stkcat lgort matnr charg budat.
    l_lines = lines( gt_b ).
    LOOP AT gt_b ASSIGNING <ls_b>.
      l_idx = sy-tabix.
      CLEAR ls_in.
      MOVE-CORRESPONDING <ls_b> TO ls_in.
      APPEND ls_in TO lt_in.

      l_flush = abap_true.
      IF l_idx < l_lines.
        l_next = l_idx + 1.
        READ TABLE gt_b ASSIGNING <ls_bn> INDEX l_next.
        IF <ls_bn>-werks = <ls_b>-werks AND <ls_bn>-stkcat = <ls_b>-stkcat
           AND <ls_bn>-lgort = <ls_b>-lgort AND <ls_bn>-matnr = <ls_b>-matnr
           AND <ls_bn>-charg = <ls_b>-charg.
          l_flush = abap_false.
        ENDIF.
      ENDIF.
      CHECK l_flush = abap_true.

      ls_period = zcl_mm_stkday_calc=>calc_period( it_row  = lt_in
                                                   iv_from = pa_budfr
                                                   iv_to   = pa_budto
                                                   iv_low  = get_low_end( <ls_b>-werks ) ).
      CLEAR lt_in.
      IF pa_nozer = abap_true AND zcl_mm_stkday_calc=>is_zero_result( ls_period ) = abap_true.
        CONTINUE.
      ENDIF.
      CLEAR ls_detail.
      ls_detail-werks  = <ls_b>-werks.
      ls_detail-lgort  = <ls_b>-lgort.
      ls_detail-stkcat = <ls_b>-stkcat.
      ls_detail-matnr  = <ls_b>-matnr.
      ls_detail-charg  = <ls_b>-charg.
      ls_detail-meins  = <ls_b>-meins.
      MOVE-CORRESPONDING ls_period TO ls_detail.
      INSERT ls_detail INTO TABLE gt_detail.
    ENDLOOP.

    " 원천 행은 더 쓰지 않음 (메모리 해제)
    FREE: gt_a, gt_b.

    "-- ④ 자재내역 (한 번만, 팝업에서는 DB를 읽지 않음)
    read_makt( ).
  ENDMETHOD.


  METHOD build_main.
    DATA: lt_qty    TYPE zcl_mm_stkday_calc=>tt_loc_qty,
          ls_qty    TYPE zcl_mm_stkday_calc=>ty_loc_qty,
          lt_sum    TYPE zcl_mm_stkday_calc=>tt_loc_sum,
          ls_sum    TYPE zcl_mm_stkday_calc=>ty_loc_sum,
          ls_matres TYPE ty_matres,
          ls_detail TYPE ty_detail,
          ls_main   TYPE ty_main,
          ls_t001w  TYPE ty_t001w,
          ls_t001l  TYPE ty_t001l,
          ls_color  TYPE lvc_s_scol.
    FIELD-SYMBOLS <ls_det> TYPE ty_detail.

    rv_found = abap_false.
    CLEAR: gt_main, g_mix_cnt.

    " ① 원천: SO_CHARG 미입력 = 자재 레벨(A), 입력 = 배치 레벨(B, 선택 배치분)
    IF so_charg[] IS INITIAL.
      LOOP AT gt_matres INTO ls_matres.
        CLEAR ls_qty.
        MOVE-CORRESPONDING ls_matres TO ls_qty.
        APPEND ls_qty TO lt_qty.
      ENDLOOP.
    ELSE.
      LOOP AT gt_detail INTO ls_detail.
        CLEAR ls_qty.
        MOVE-CORRESPONDING ls_detail TO ls_qty.
        APPEND ls_qty TO lt_qty.
      ENDLOOP.
    ENDIF.

    IF lt_qty IS INITIAL.
      MESSAGE s010 DISPLAY LIKE 'W'.
      RETURN.
    ENDIF.

    " ② 위치별 합계·단위 혼재 (4.5, D11)
    lt_sum = zcl_mm_stkday_calc=>aggregate_location( lt_qty ).

    " 저장위치명 (T001L, 한 번)
    read_texts( lt_sum ).

    " ③④ 메인 행 조립 (정렬 = WERKS, STKCAT(L→T), LGORT: TT_LOC_SUM 정렬 키)
    LOOP AT lt_sum INTO ls_sum.
      CLEAR ls_main.
      MOVE-CORRESPONDING ls_sum TO ls_main.
      READ TABLE gt_t001w INTO ls_t001w WITH TABLE KEY werks = ls_sum-werks.
      IF sy-subrc = 0.
        ls_main-name1 = ls_t001w-name1.
      ENDIF.
      IF ls_sum-stkcat = zcl_mm_stkday_calc=>c_stk_transit.
        ls_main-lgobe = TEXT-t10.
      ELSE.
        READ TABLE gt_t001l INTO ls_t001l
             WITH TABLE KEY werks = ls_sum-werks lgort = ls_sum-lgort.
        IF sy-subrc = 0.
          ls_main-lgobe = ls_t001l-lgobe.
        ENDIF.
      ENDIF.
      IF ls_sum-unit_mix = abap_true.
        " 단위 혼재: 행 전체 노란색
        CLEAR ls_color.
        ls_color-color-col = col_total.
        ls_color-color-int = 0.
        ls_color-color-inv = 0.
        APPEND ls_color TO ls_main-t_color.
        g_mix_cnt = g_mix_cnt + 1.
      ENDIF.
      APPEND ls_main TO gt_main.
    ENDLOOP.

    " 상세 저장위치명 (같은 텍스트 재사용)
    LOOP AT gt_detail ASSIGNING <ls_det>.
      IF <ls_det>-stkcat = zcl_mm_stkday_calc=>c_stk_transit.
        <ls_det>-lgobe = TEXT-t10.
      ELSE.
        READ TABLE gt_t001l INTO ls_t001l
             WITH TABLE KEY werks = <ls_det>-werks lgort = <ls_det>-lgort.
        IF sy-subrc = 0.
          <ls_det>-lgobe = ls_t001l-lgobe.
        ENDIF.
      ENDIF.
    ENDLOOP.

    rv_found = abap_true.
  ENDMETHOD.


  METHOD get_main.
    rt_main = gt_main.
  ENDMETHOD.


  METHOD get_detail.
    DATA: ls_key    TYPE zcl_mm_stkday_calc=>ty_loc_key,
          ls_detail TYPE ty_detail.

    " 선택 위치마다 정렬 키 앞부분(WERKS, STKCAT, LGORT)으로 거름 - DB 조회 없음
    LOOP AT it_keys INTO ls_key.
      LOOP AT gt_detail INTO ls_detail
           WHERE werks  = ls_key-werks
             AND stkcat = ls_key-stkcat
             AND lgort  = ls_key-lgort.
        APPEND ls_detail TO rt_detail.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.


  METHOD get_first_ctrl.
    DATA ls_werks LIKE LINE OF r_werks.

    READ TABLE r_werks INTO ls_werks INDEX 1.
    IF sy-subrc = 0.
      READ TABLE gt_ctrl INTO rs_ctrl WITH TABLE KEY werks = ls_werks-low.
    ENDIF.
  ENDMETHOD.


  METHOD read_texts.
    TYPES: BEGIN OF lty_key,
             werks TYPE t001l-werks,
             lgort TYPE t001l-lgort,
           END OF lty_key.
    DATA: lt_key    TYPE SORTED TABLE OF lty_key WITH UNIQUE KEY werks lgort,
          ls_key    TYPE lty_key,
          ls_sum    TYPE zcl_mm_stkday_calc=>ty_loc_sum,
          ls_detail TYPE ty_detail.

    CLEAR gt_t001l.

    " 저장위치 키(메인 + 상세, 운송중 제외)
    LOOP AT it_sum INTO ls_sum WHERE stkcat = zcl_mm_stkday_calc=>c_stk_loc.
      ls_key-werks = ls_sum-werks.
      ls_key-lgort = ls_sum-lgort.
      INSERT ls_key INTO TABLE lt_key.
    ENDLOOP.
    LOOP AT gt_detail INTO ls_detail WHERE stkcat = zcl_mm_stkday_calc=>c_stk_loc.
      ls_key-werks = ls_detail-werks.
      ls_key-lgort = ls_detail-lgort.
      INSERT ls_key INTO TABLE lt_key.
    ENDLOOP.

    " FOR ALL ENTRIES는 드라이버가 비었는지 먼저 확인
    IF lt_key IS INITIAL.
      RETURN.
    ENDIF.
    SELECT werks, lgort, lgobe FROM t001l
      INTO TABLE @gt_t001l
      FOR ALL ENTRIES IN @lt_key
      WHERE werks = @lt_key-werks
        AND lgort = @lt_key-lgort.
  ENDMETHOD.


  METHOD read_makt.
    TYPES: BEGIN OF lty_mat,
             matnr TYPE makt-matnr,
           END OF lty_mat.
    TYPES: BEGIN OF lty_makt,
             matnr TYPE makt-matnr,
             spras TYPE makt-spras,
             maktx TYPE makt-maktx,
           END OF lty_makt.
    DATA: lt_mat  TYPE SORTED TABLE OF lty_mat WITH UNIQUE KEY matnr,
          ls_mat  TYPE lty_mat,
          lt_makt TYPE HASHED TABLE OF lty_makt WITH UNIQUE KEY matnr spras,
          ls_makt TYPE lty_makt.
    FIELD-SYMBOLS <ls_det> TYPE ty_detail.

    LOOP AT gt_detail ASSIGNING <ls_det>.
      ls_mat-matnr = <ls_det>-matnr.
      INSERT ls_mat INTO TABLE lt_mat.
    ENDLOOP.
    IF lt_mat IS INITIAL.
      RETURN.
    ENDIF.

    " 키 = DB 기본키(MATNR, SPRAS)로 중복 없음
    SELECT matnr, spras, maktx FROM makt
      INTO TABLE @lt_makt
      FOR ALL ENTRIES IN @lt_mat
      WHERE matnr = @lt_mat-matnr
        AND spras = @sy-langu.

    LOOP AT gt_detail ASSIGNING <ls_det>.
      READ TABLE lt_makt INTO ls_makt
           WITH TABLE KEY matnr = <ls_det>-matnr spras = sy-langu.
      IF sy-subrc = 0.
        <ls_det>-maktx = ls_makt-maktx.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD get_low_end.
    DATA ls_ctrl TYPE ztmm1237.

    " 기말 탐색 하한 L = max(월초(To), 플랜트 적재 시작일)
    rv_low = zcl_mm_stkday_calc=>month_start( pa_budto ).
    READ TABLE gt_ctrl INTO ls_ctrl WITH TABLE KEY werks = iv_werks.
    IF sy-subrc = 0 AND ls_ctrl-load_from > rv_low.
      rv_low = ls_ctrl-load_from.
    ENDIF.
  ENDMETHOD.


  METHOD show_partial_warning.
    DATA: l_v1 TYPE symsgv,
          l_v2 TYPE symsgv.

    IF it_werks IS INITIAL.
      RETURN.
    ENDIF.
    l_v1 = plant_list( it_werks ).
    IF iv_date IS NOT INITIAL.
      l_v2 = date_text( iv_date ).
    ENDIF.
    MESSAGE ID zcl_mm_stkday_calc=>c_msgid TYPE 'I' NUMBER iv_msgno
            DISPLAY LIKE 'W' WITH l_v1 l_v2.
  ENDMETHOD.


  METHOD plant_list.
    DATA: l_werks TYPE werks_d,
          l_list  TYPE string.
    FIELD-SYMBOLS <l_any> TYPE any.

    LOOP AT it_werks ASSIGNING <l_any>.
      l_werks = <l_any>.
      IF l_list IS INITIAL.
        l_list = l_werks.
      ELSE.
        l_list = |{ l_list }, { l_werks }|.
      ENDIF.
    ENDLOOP.
    rv_list = l_list.
  ENDMETHOD.


  METHOD date_text.
    rv_text = |{ iv_date DATE = USER }|.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* CLASS lcl_view IMPLEMENTATION
*----------------------------------------------------------------------*
CLASS lcl_view IMPLEMENTATION.

  METHOD constructor.
    g_data = io_data.
  ENDMETHOD.


  METHOD display_main.
    DATA: lo_sel    TYPE REF TO cl_salv_selections,
          lo_events TYPE REF TO cl_salv_events_table,
          lo_layout TYPE REF TO cl_salv_layout,
          lo_disp   TYPE REF TO cl_salv_display_settings,
          ls_key    TYPE salv_s_layout_key,
          ls_ctrl   TYPE ztmm1237,
          l_info    TYPE string,
          l_d1      TYPE string,
          l_t1      TYPE string,
          l_d2      TYPE string,
          l_title   TYPE lvc_title,
          l_cnt     TYPE i,
          l_v1      TYPE symsgv,
          lx_salv   TYPE REF TO cx_salv_error.

    gt_main = g_data->get_main( ).

    TRY.
        cl_salv_table=>factory( IMPORTING r_salv_table = g_main
                                CHANGING  t_table      = gt_main ).

        " GUI 상태 STANDARD (SALV_STANDARD 복사 + DETAIL, SE41)
        " (REPORT 파라미터를 줄 머리에 두지 않음: 반영 도구가 PROG로 오인)
        g_main->set_screen_status( pfstatus = c_status  report = sy-repid
                                   set_functions = cl_salv_table=>c_functions_all ).

        " 다중 행 선택 (설계지시 3)
        lo_sel = g_main->get_selections( ).
        lo_sel->set_selection_mode( if_salv_c_selection_mode=>row_column ).

        set_main_columns( g_main ).

        " 이벤트: [상세조회], 더블클릭
        lo_events = g_main->get_event( ).
        SET HANDLER on_user_command FOR lo_events.
        SET HANDLER on_double_click FOR lo_events.

        " 레이아웃 (핸들 MAIN, 초기 레이아웃 = PA_VARI)
        lo_layout = g_main->get_layout( ).
        ls_key-report = sy-repid.
        ls_key-handle = c_handle_main.
        lo_layout->set_key( ls_key ).
        lo_layout->set_save_restriction( if_salv_c_layout=>restrict_none ).
        lo_layout->set_default( abap_true ).
        IF pa_vari IS NOT INITIAL.
          lo_layout->set_initial_layout( pa_vari ).
        ENDIF.

        " 제목 = T11 + 기간 + 마지막 집계(T02)
        ls_ctrl = g_data->get_first_ctrl( ).
        l_d1 = |{ ls_ctrl-last_cpudt DATE = USER }|.
        l_t1 = |{ ls_ctrl-last_cputm TIME = USER }|.
        l_d2 = |{ ls_ctrl-last_budat DATE = USER }|.
        l_info = TEXT-t02.
        REPLACE '&1' WITH l_d1 INTO l_info.
        REPLACE '&2' WITH l_t1 INTO l_info.
        REPLACE '&3' WITH l_d2 INTO l_info.
        l_title = |{ TEXT-t11 } { get_period_text( ) } ({ l_info })|.
        lo_disp = g_main->get_display_settings( ).
        lo_disp->set_list_header( l_title ).

      CATCH cx_salv_error INTO lx_salv.
        l_v1 = lx_salv->get_text( ).
        MESSAGE s015 DISPLAY LIKE 'E' WITH l_v1.
        RETURN.
    ENDTRY.

    " 표시 직전 메시지: 단위 혼재 W 016, 아니면 S 011
    IF g_data->g_mix_cnt > 0.
      l_cnt = g_data->g_mix_cnt.
      MESSAGE s016 DISPLAY LIKE 'W' WITH l_cnt.
    ELSE.
      l_cnt = lines( gt_main ).
      MESSAGE s011 WITH l_cnt.
    ENDIF.

    g_main->display( ).
  ENDMETHOD.


  METHOD on_user_command.
    DATA lt_keys TYPE zcl_mm_stkday_calc=>tt_loc_key.

    CASE e_salv_function.
      WHEN c_fc_detail.
        " 선택한 모든 행의 위치 (셀만 선택한 경우는 선택 없음)
        lt_keys = get_selected_keys( ).
        IF lt_keys IS INITIAL.
          MESSAGE s012.
          RETURN.
        ENDIF.
        show_detail( lt_keys ).
      WHEN OTHERS.
        " SALV 표준 기능은 SALV가 처리
    ENDCASE.
  ENDMETHOD.


  METHOD on_double_click.
    DATA: ls_main TYPE ty_main,
          ls_key  TYPE zcl_mm_stkday_calc=>ty_loc_key,
          lt_keys TYPE zcl_mm_stkday_calc=>tt_loc_key.

    " 데이터 행이 아니면 무시. 더블클릭한 행 하나만(다른 선택 행 무시)
    IF row <= 0.
      RETURN.
    ENDIF.
    READ TABLE gt_main INTO ls_main INDEX row.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    ls_key-werks  = ls_main-werks.
    ls_key-lgort  = ls_main-lgort.
    ls_key-stkcat = ls_main-stkcat.
    INSERT ls_key INTO TABLE lt_keys.
    show_detail( lt_keys ).
  ENDMETHOD.


  METHOD get_selected_keys.
    DATA: lo_sel  TYPE REF TO cl_salv_selections,
          lt_rows TYPE salv_t_row,
          l_idx   TYPE i,
          ls_main TYPE ty_main,
          ls_key  TYPE zcl_mm_stkday_calc=>ty_loc_key.

    " SALV 행 인덱스 = GT_MAIN 인덱스 (정렬·필터와 무관)
    lo_sel  = g_main->get_selections( ).
    lt_rows = lo_sel->get_selected_rows( ).
    LOOP AT lt_rows INTO l_idx.
      READ TABLE gt_main INTO ls_main INDEX l_idx.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      ls_key-werks  = ls_main-werks.
      ls_key-lgort  = ls_main-lgort.
      ls_key-stkcat = ls_main-stkcat.
      INSERT ls_key INTO TABLE rt_keys.        " 중복 위치는 무시됨
    ENDLOOP.
  ENDMETHOD.


  METHOD show_detail.
    DATA: l_popup   TYPE REF TO cl_salv_table,
          lo_func   TYPE REF TO cl_salv_functions_list,
          lo_events TYPE REF TO cl_salv_events_table,
          lo_layout TYPE REF TO cl_salv_layout,
          lo_disp   TYPE REF TO cl_salv_display_settings,
          ls_key    TYPE salv_s_layout_key,
          l_sel     TYPE string,
          l_cntx    TYPE string,
          l_title   TYPE lvc_title,
          l_keycnt  TYPE i,
          l_cnt     TYPE i,
          l_v1      TYPE symsgv,
          lx_salv   TYPE REF TO cx_salv_error.

    " ① 메모리 캐시에서 선택 위치만 (DB 조회 없음, D7)
    gt_popup = g_data->get_detail( it_keys ).
    IF gt_popup IS INITIAL.
      MESSAGE s010 DISPLAY LIKE 'W'.
      RETURN.
    ENDIF.

    " ③ 정렬: 플랜트 -> 재고구분(L, T) -> 저장위치 -> 자재 -> 배치
    SORT gt_popup BY werks stkcat lgort matnr charg.
    l_keycnt = lines( it_keys ).
    l_cnt    = lines( gt_popup ).

    TRY.
        " ④ 팝업은 매번 새 인스턴스
        cl_salv_table=>factory( IMPORTING r_salv_table = l_popup
                                CHANGING  t_table      = gt_popup ).
        l_popup->set_screen_popup( start_column = c_pop_scol
                                   end_column   = c_pop_ecol
                                   start_line   = c_pop_slin
                                   end_line     = c_pop_elin ).
        lo_func = l_popup->get_functions( ).
        lo_func->set_all( abap_true ).

        set_popup_columns( l_popup ).

        lo_layout = l_popup->get_layout( ).
        ls_key-report = sy-repid.
        ls_key-handle = c_handle_detl.
        lo_layout->set_key( ls_key ).
        lo_layout->set_save_restriction( if_salv_c_layout=>restrict_none ).

        l_cntx = |{ l_keycnt }|.
        l_sel = TEXT-t13.
        REPLACE '&1' WITH l_cntx INTO l_sel.
        l_title = |{ TEXT-t12 } { get_period_text( ) } { l_sel }|.
        lo_disp = l_popup->get_display_settings( ).
        lo_disp->set_list_header( l_title ).

        lo_events = l_popup->get_event( ).
        SET HANDLER on_popup_double_click FOR lo_events.

      CATCH cx_salv_error INTO lx_salv.
        " 팝업 오류여도 메인은 그대로 유지
        l_v1 = lx_salv->get_text( ).
        MESSAGE s015 DISPLAY LIKE 'E' WITH l_v1.
        RETURN.
    ENDTRY.

    MESSAGE s017 WITH l_keycnt l_cnt.

    " ⑤ 계속/취소로 닫으면 반환되어 메인 화면 유지(선택·정렬·필터 그대로)
    l_popup->display( ).

    SET HANDLER on_popup_double_click FOR lo_events ACTIVATION abap_false.
  ENDMETHOD.


  METHOD on_popup_double_click.
    DATA ls_detail TYPE ty_detail.

    IF row <= 0.
      RETURN.
    ENDIF.
    READ TABLE gt_popup INTO ls_detail INDEX row.
    IF sy-subrc = 0.
      call_mb51( ls_detail ).
    ENDIF.
  ENDMETHOD.


  METHOD call_mb51.
    DATA: lt_rspar TYPE STANDARD TABLE OF rsparams WITH EMPTY KEY,
          ls_rspar TYPE rsparams.

    " SUBMIT은 S_TCODE를 거치지 않으므로 사전 체크
    AUTHORITY-CHECK OBJECT c_auth_tcode
      ID 'TCD' FIELD c_tcode_mb51.
    IF sy-subrc <> 0.
      MESSAGE s013 DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    " 선택 필드: 자재·플랜트·저장위치(운송중 생략)·배치(공란 생략)·전기일 (D-07)
    CLEAR ls_rspar.
    ls_rspar-selname = 'MATNR'.
    ls_rspar-kind    = c_kind_sel.
    ls_rspar-sign    = c_sel_sign.
    ls_rspar-option  = c_sel_eq.
    ls_rspar-low     = is_detail-matnr.
    APPEND ls_rspar TO lt_rspar.

    ls_rspar-selname = 'WERKS'.
    ls_rspar-low     = is_detail-werks.
    APPEND ls_rspar TO lt_rspar.

    IF is_detail-stkcat = zcl_mm_stkday_calc=>c_stk_loc AND is_detail-lgort IS NOT INITIAL.
      ls_rspar-selname = 'LGORT'.
      ls_rspar-low     = is_detail-lgort.
      APPEND ls_rspar TO lt_rspar.
    ENDIF.

    IF is_detail-charg IS NOT INITIAL.
      ls_rspar-selname = 'CHARG'.
      ls_rspar-low     = is_detail-charg.
      APPEND ls_rspar TO lt_rspar.
    ENDIF.

    CLEAR ls_rspar.
    ls_rspar-selname = 'BUDAT'.
    ls_rspar-kind    = c_kind_sel.
    ls_rspar-sign    = c_sel_sign.
    ls_rspar-option  = c_sel_bt.
    ls_rspar-low     = pa_budfr.
    ls_rspar-high    = pa_budto.
    APPEND ls_rspar TO lt_rspar.

    SUBMIT rm07docs WITH SELECTION-TABLE lt_rspar
           VIA SELECTION-SCREEN
           AND RETURN.

    " 복귀 후 안내 (집계 이후 전표도 보일 수 있음)
    MESSAGE s014.
  ENDMETHOD.


  METHOD set_main_columns.
    DATA: lo_cols TYPE REF TO cl_salv_columns_table,
          lo_col  TYPE REF TO cl_salv_column.

    lo_cols = io_salv->get_columns( ).
    lo_cols->set_optimize( abap_true ).

    " 표시 컬럼 8개 (설계지시 1)
    set_column( io_columns = lo_cols iv_name = 'WERKS' iv_text = TEXT-c01 ).
    set_column( io_columns = lo_cols iv_name = 'NAME1' iv_text = TEXT-c02 ).
    set_column( io_columns = lo_cols iv_name = 'LGORT' iv_text = TEXT-c03 ).
    set_column( io_columns = lo_cols iv_name = 'LGOBE' iv_text = TEXT-c04 ).
    " 수량: 단위 = MEINS, 0은 공란 표시(단위 혼재 행 공란)
    set_column( io_columns = lo_cols iv_name = 'BEG_QTY' iv_text = TEXT-c05
                iv_quantity = abap_true iv_hide_zero = abap_true ).
    set_column( io_columns = lo_cols iv_name = 'GR_QTY'  iv_text = TEXT-c06
                iv_quantity = abap_true iv_hide_zero = abap_true ).
    set_column( io_columns = lo_cols iv_name = 'GI_QTY'  iv_text = TEXT-c07
                iv_quantity = abap_true iv_hide_zero = abap_true ).
    set_column( io_columns = lo_cols iv_name = 'END_QTY' iv_text = TEXT-c08
                iv_quantity = abap_true iv_hide_zero = abap_true ).

    " 숨김: 단위(레이아웃에서 표시 가능), 기술 필드
    set_column( io_columns = lo_cols iv_name = 'MEINS' iv_text = TEXT-c14 ).
    lo_col = lo_cols->get_column( 'MEINS' ).
    lo_col->set_visible( abap_false ).
    lo_col = lo_cols->get_column( 'UNIT_MIX' ).
    lo_col->set_technical( abap_true ).
    lo_col = lo_cols->get_column( 'STKCAT' ).
    lo_col->set_technical( abap_true ).

    " 단위 혼재 행 색상
    lo_cols->set_color_column( 'T_COLOR' ).
  ENDMETHOD.


  METHOD set_popup_columns.
    DATA: lo_cols TYPE REF TO cl_salv_columns_table,
          lo_col  TYPE REF TO cl_salv_column.

    lo_cols = io_salv->get_columns( ).
    lo_cols->set_optimize( abap_true ).

    set_column( io_columns = lo_cols iv_name = 'WERKS' iv_text = TEXT-c01 ).
    set_column( io_columns = lo_cols iv_name = 'LGORT' iv_text = TEXT-c03 ).
    set_column( io_columns = lo_cols iv_name = 'LGOBE' iv_text = TEXT-c04 ).
    set_column( io_columns = lo_cols iv_name = 'MATNR' iv_text = TEXT-c11 ).
    set_column( io_columns = lo_cols iv_name = 'MAKTX' iv_text = TEXT-c12 ).
    set_column( io_columns = lo_cols iv_name = 'CHARG' iv_text = TEXT-c13 ).
    set_column( io_columns = lo_cols iv_name = 'MEINS' iv_text = TEXT-c14 ).
    " 수량 7개: 단위 = MEINS, 0은 그대로 표시
    set_column( io_columns = lo_cols iv_name = 'BEG_QTY' iv_text = TEXT-c15 iv_quantity = abap_true ).
    set_column( io_columns = lo_cols iv_name = 'GR_QTY'  iv_text = TEXT-c16 iv_quantity = abap_true ).
    set_column( io_columns = lo_cols iv_name = 'GI_QTY'  iv_text = TEXT-c17 iv_quantity = abap_true ).
    set_column( io_columns = lo_cols iv_name = 'END_QTY' iv_text = TEXT-c18 iv_quantity = abap_true ).
    set_column( io_columns = lo_cols iv_name = 'K_END'   iv_text = TEXT-c19 iv_quantity = abap_true ).
    set_column( io_columns = lo_cols iv_name = 'E_END'   iv_text = TEXT-c20 iv_quantity = abap_true ).
    set_column( io_columns = lo_cols iv_name = 'TRF_END' iv_text = TEXT-c21 iv_quantity = abap_true ).

    lo_col = lo_cols->get_column( 'STKCAT' ).
    lo_col->set_technical( abap_true ).
  ENDMETHOD.


  METHOD set_column.
    DATA lo_col TYPE REF TO cl_salv_column.

    lo_col = io_columns->get_column( CONV lvc_fname( iv_name ) ).
    " 헤더는 Text Symbol (MENGE_D 기본 라벨 대신)
    lo_col->set_short_text( CONV scrtext_s( iv_text ) ).
    lo_col->set_medium_text( CONV scrtext_m( iv_text ) ).
    lo_col->set_long_text( CONV scrtext_l( iv_text ) ).
    IF iv_quantity = abap_true.
      lo_col->set_quantity_column( 'MEINS' ).
    ENDIF.
    IF iv_hide_zero = abap_true.
      lo_col->set_zero( abap_false ).
    ENDIF.
  ENDMETHOD.


  METHOD get_period_text.
    rv_text = |{ pa_budfr DATE = USER } ~ { pa_budto DATE = USER }|.
  ENDMETHOD.

ENDCLASS.
