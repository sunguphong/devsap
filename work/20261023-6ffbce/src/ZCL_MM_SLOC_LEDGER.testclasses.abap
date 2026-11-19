*"* use this source file for your ABAP unit test classes
*----------------------------------------------------------------------*
* ZCL_MM_SLOC_LEDGER 로컬 테스트 클래스 (Local Test Classes include, CCAU)
* 요청 ID : 20261023-6ffbce / 04_test.md 8~9장
* 방식    : DB 접근 없음 (RISK LEVEL HARMLESS, DURATION SHORT)
*  - LTCL_RULES  : PUBLIC STATIC 규칙 메서드 (build_deltas, gr/gi_column,
*                  resolve_vsloc, pick_period_end, prev_period, month_start,
*                  to_period, apply_delta, finalize, is_zero,
*                  to_exclude_range, mov_fields)
*  - LTCL_LEDGER : 인스턴스 가드, HANDLE_ITEM, POST_DELTA/POST_BEGIN,
*                  GET_BATCH(비배치·가상 행), GET_RECON 가드.
*                  private 멤버는 LOCAL FRIENDS 로 접근 (본 소스 수정 없음)
*  - LTD_FIXTURE : 테스트 더블. READ_MAPPING(ZTMM0008)·READ_BSX(T156W) DB
*                  조회 대신 GT_MAP·GT_BSX 에 값을 넣고, 첨부 샘플
*                  (3000/4000/R1D1, 2026-05-03, 261 17건 / 262 15건)을 만든다
* 전제    : ZTMM0008 매핑값(261/262 GIIND '2', 311 TPIND '1'+SHKZG 'H',
*           301 TPIND '2' 등)은 테스트용 가정값(C-02 SE16 확인 전).
*           기대값은 ZRMM0034F01 원문(581~878, 1185~1265행) 손계산.
* 주의    : SIMUL_GR_GI_NO_STOCK, GI_UNKNOWN_VALUE 는 원문 동작(R-01)을
*           고정한다. 팀장이 C-14 에서 FR-11 보정 방식을 정하면 함께 바꾼다.
* 문법    : ABAP 7.40 SP05 (VALUE/CONV, FOR·xsdbool·REDUCE 미사용)
* 명명    : 변수·상수는 핸드북 2장(G_/L_/GT_/LT_/GS_/LS_/C_).
*           테스트 클래스(LTCL_/LTD_)·메서드·파라미터(IV_/IS_/IO_/RV_/RS_/RT_)
*           는 핸드북 규칙 없음 -> SAP 관례 적용
*----------------------------------------------------------------------*

CLASS ltd_fixture DEFINITION DEFERRED.
CLASS ltcl_ledger DEFINITION DEFERRED.
CLASS zcl_mm_sloc_ledger DEFINITION LOCAL FRIENDS ltd_fixture ltcl_ledger.

*----------------------------------------------------------------------*
* 테스트 더블 / 데이터 빌더
*----------------------------------------------------------------------*
CLASS ltd_fixture DEFINITION FINAL FOR TESTING
  RISK LEVEL HARMLESS
  DURATION SHORT.

  PUBLIC SECTION.
    TYPES ty_t_qty TYPE STANDARD TABLE OF mseg-menge WITH DEFAULT KEY.

    CONSTANTS:
      c_werks     TYPE mseg-werks VALUE '3000',
      c_werks2    TYPE mseg-werks VALUE '3100',
      c_lgort     TYPE mseg-lgort VALUE '4000',
      c_lgort2    TYPE mseg-lgort VALUE '4100',
      c_lgort3    TYPE mseg-lgort VALUE '5000',
      c_lgort4    TYPE mseg-lgort VALUE '6000',
      c_matnr     TYPE mseg-matnr VALUE 'R1D1',
      c_charg1    TYPE mseg-charg VALUE 'B0001',
      c_charg2    TYPE mseg-charg VALUE 'B0002',
      c_meins     TYPE mara-meins VALUE 'KG',
      c_bustw     TYPE mseg-bustw VALUE 'WA01',
      c_bustw_no  TYPE mseg-bustw VALUE 'WA99',
      c_bustm     TYPE mseg-bustm VALUE 'MA01',
      c_bwart_101 TYPE mseg-bwart VALUE '101',
      c_bwart_102 TYPE mseg-bwart VALUE '102',
      c_bwart_261 TYPE mseg-bwart VALUE '261',
      c_bwart_262 TYPE mseg-bwart VALUE '262',
      c_bwart_301 TYPE mseg-bwart VALUE '301',
      c_bwart_303 TYPE mseg-bwart VALUE '303',
      c_bwart_305 TYPE mseg-bwart VALUE '305',
      c_bwart_311 TYPE mseg-bwart VALUE '311',
      c_bwart_313 TYPE mseg-bwart VALUE '313',
      c_bwart_315 TYPE mseg-bwart VALUE '315',
      c_bwart_999 TYPE mseg-bwart VALUE '999',
      c_sobkz_k   TYPE mseg-sobkz VALUE 'K',
      c_xauto_x   TYPE mseg-xauto VALUE 'X',
      c_xauto_u   TYPE mseg-xauto VALUE 'U',
      c_ind_9     TYPE ztmm0008-giind VALUE '9',
      c_d0115     TYPE mkpf-budat VALUE '20200115',
      c_d0501     TYPE mkpf-budat VALUE '20260501',
      c_d0502     TYPE mkpf-budat VALUE '20260502',
      c_d0503     TYPE mkpf-budat VALUE '20260503',
      c_d0115y    TYPE mkpf-budat VALUE '20260115'.

    CLASS-METHODS item
      IMPORTING
        iv_bwart       TYPE mseg-bwart
        iv_shkzg       TYPE mseg-shkzg
        iv_menge       TYPE numeric
      RETURNING
        VALUE(rs_item) TYPE zcl_mm_sloc_ledger=>ty_s_item.

    CLASS-METHODS sample_items
      RETURNING
        VALUE(rt_item) TYPE zcl_mm_sloc_ledger=>ty_t_item.

    CLASS-METHODS sel
      RETURNING
        VALUE(rs_sel) TYPE zcl_mm_sloc_ledger=>ty_s_sel.

    CLASS-METHODS inject
      IMPORTING
        io_cut TYPE REF TO zcl_mm_sloc_ledger.
ENDCLASS.


CLASS ltd_fixture IMPLEMENTATION.

  METHOD item.
    " 첨부 샘플 행 72~103 형식: 3000/4000/R1D1, WERTU·MENGU X, MA01/WA01
    CLEAR rs_item.
    rs_item-budat = c_d0503.
    rs_item-werks = c_werks.
    rs_item-lgort = c_lgort.
    rs_item-matnr = c_matnr.
    rs_item-bwart = iv_bwart.
    rs_item-shkzg = iv_shkzg.
    rs_item-menge = iv_menge.
    rs_item-lmein = c_meins.
    rs_item-meins = c_meins.
    rs_item-wertu = abap_true.
    rs_item-mengu = abap_true.
    rs_item-bustm = c_bustm.
    rs_item-bustw = c_bustw.
  ENDMETHOD.


  METHOD sample_items.
    DATA: lt_261  TYPE ty_t_qty,
          lt_262  TYPE ty_t_qty,
          l_qty   TYPE mseg-menge,
          ls_item TYPE zcl_mm_sloc_ledger=>ty_s_item.

    " 261 생산출고 17건 = 254,420 KG (첨부 J72~J88)
    lt_261 = VALUE #( ( 16690 ) ( 17360 ) ( 18620 ) ( 16250 ) ( 16880 )
                      ( 16840 ) ( 14480 ) ( 19140 ) ( 21530 ) ( 18550 )
                      ( 18220 ) ( 19980 ) ( 16380 ) ( 18190 ) ( 2310 )
                      ( 1500 ) ( 1500 ) ).
    " 262 생산출고 취소 15건 = 229,395 KG (첨부 J89~J103)
    lt_262 = VALUE #( ( 1208 ) ( 17532 ) ( 19722 ) ( 18302 ) ( 15288 )
                      ( 17056 ) ( 14885 ) ( 15426 ) ( 16690 ) ( 15902 )
                      ( 15462 ) ( 13264 ) ( 16992 ) ( 15004 ) ( 16662 ) ).

    LOOP AT lt_261 INTO l_qty.
      ls_item = item( iv_bwart = c_bwart_261
                      iv_shkzg = zcl_mm_sloc_ledger=>c_shkzg_h
                      iv_menge = l_qty ).
      APPEND ls_item TO rt_item.
    ENDLOOP.
    LOOP AT lt_262 INTO l_qty.
      ls_item = item( iv_bwart = c_bwart_262
                      iv_shkzg = zcl_mm_sloc_ledger=>c_shkzg_s
                      iv_menge = l_qty ).
      APPEND ls_item TO rt_item.
    ENDLOOP.
  ENDMETHOD.


  METHOD sel.
    CLEAR rs_sel.
    rs_sel-werks = VALUE #( ( sign = 'I' option = 'EQ' low = c_werks ) ).
    rs_sel-budat_from = c_d0503.
    rs_sel-budat_to   = c_d0503.
    rs_sel-xbustm = VALUE #( ( sign = 'I' option = 'EQ' low = zcl_mm_sloc_ledger=>c_bustm_ma02 )
                             ( sign = 'I' option = 'EQ' low = zcl_mm_sloc_ledger=>c_bustm_ma05 ) ).
    rs_sel-vsloc   = abap_true.
    rs_sel-no_zero = abap_true.
  ENDMETHOD.


  METHOD inject.
    " READ_MAPPING / READ_BSX (DB) 대체: 테스트용 ZTMM0008·T156W 내용
    io_cut->gt_map = VALUE #(
      ( bwart = c_bwart_261 wertu = abap_true mengu = abap_true
        giind = zcl_mm_sloc_ledger=>c_giind_pp )
      ( bwart = c_bwart_262 wertu = abap_true mengu = abap_true
        giind = zcl_mm_sloc_ledger=>c_giind_pp )
      ( bwart = c_bwart_311 wertu = abap_true mengu = abap_true
        tpind = zcl_mm_sloc_ledger=>c_tpind_1 shkzg = zcl_mm_sloc_ledger=>c_shkzg_h )
      ( bwart = c_bwart_301 wertu = abap_true mengu = abap_true
        tpind = zcl_mm_sloc_ledger=>c_tpind_2 ) ).
    io_cut->gt_bsx = VALUE #( ( bustw = c_bustw xbgbb = space ) ).
  ENDMETHOD.

ENDCLASS.


*----------------------------------------------------------------------*
* 정적 규칙 메서드 (DB 없음)
*----------------------------------------------------------------------*
CLASS ltcl_rules DEFINITION FINAL FOR TESTING
  RISK LEVEL HARMLESS
  DURATION SHORT.

  PRIVATE SECTION.
    DATA: gs_map  TYPE zcl_mm_sloc_ledger=>ty_s_map,
          gs_rule TYPE zcl_mm_sloc_ledger=>ty_s_rule.

    METHODS setup.

    METHODS deltas
      IMPORTING
        is_item         TYPE zcl_mm_sloc_ledger=>ty_s_item
      RETURNING
        VALUE(rt_delta) TYPE zcl_mm_sloc_ledger=>ty_t_delta.

    METHODS pick
      IMPORTING
        it_delta        TYPE zcl_mm_sloc_ledger=>ty_t_delta
        iv_side         TYPE c
      RETURNING
        VALUE(rs_delta) TYPE zcl_mm_sloc_ledger=>ty_s_delta.

    METHODS check_qty
      IMPORTING
        iv_act TYPE any
        iv_exp TYPE any
        iv_msg TYPE csequence.

    METHODS:
      issue_261_production    FOR TESTING,
      cancel_262_net_issue    FOR TESTING,
      sample_total_25025      FOR TESTING,
      cancel_102_net_receipt  FOR TESTING,
      simul_gr_gi_no_stock    FOR TESTING,
      tp1_311_sender          FOR TESTING,
      tp1_311_receiver        FOR TESTING,
      tp1_shkzg_blank_none    FOR TESTING,
      tp_grind_123_not_posted FOR TESTING,
      tp_grind_4_transfer     FOR TESTING,
      tp2_cross_plant_cpt     FOR TESTING,
      tp2_cpt_no_umlgo_trns   FOR TESTING,
      tp2_same_plant_sign     FOR TESTING,
      tp2_no_umwrk            FOR TESTING,
      same_key_skipped        FOR TESTING,
      same_sloc_batch_intra   FOR TESTING,
      special_stock_excluded  FOR TESTING,
      blank_lgort_virtual     FOR TESTING,
      overlay_313_in_transfer FOR TESTING,
      overlay_313_auto_item   FOR TESTING,
      overlay_315_receipt     FOR TESTING,
      overlay_303_trns_up     FOR TESTING,
      overlay_305_trns_down   FOR TESTING,
      column_mapping          FOR TESTING,
      gi_unknown_value        FOR TESTING,
      period_end_gap_month    FOR TESTING,
      period_end_exact        FOR TESTING,
      period_end_current      FOR TESTING,
      period_end_after_x      FOR TESTING,
      prev_period_year_turn   FOR TESTING,
      month_start_and_period  FOR TESTING,
      apply_delta_before      FOR TESTING,
      apply_delta_period      FOR TESTING,
      finalize_formula        FOR TESTING,
      is_zero_flag            FOR TESTING,
      exclude_range_bustm     FOR TESTING,
      exclude_range_empty     FOR TESTING,
      mov_fields_complete     FOR TESTING.
ENDCLASS.


CLASS ltcl_rules IMPLEMENTATION.

  METHOD setup.
    CLEAR: gs_map, gs_rule.
    gs_rule-vsloc = abap_true.
  ENDMETHOD.


  METHOD deltas.
    rt_delta = zcl_mm_sloc_ledger=>build_deltas( is_item = is_item
                                                 is_map  = gs_map
                                                 is_rule = gs_rule ).
  ENDMETHOD.


  METHOD pick.
    READ TABLE it_delta INTO rs_delta WITH KEY side = iv_side.
    cl_abap_unit_assert=>assert_subrc( exp = 0 act = sy-subrc
                                       msg = '기대한 side 의 델타가 없음' ).
  ENDMETHOD.


  METHOD check_qty.
    DATA: l_act TYPE mseg-menge,
          l_exp TYPE mseg-menge.

    l_act = iv_act.
    l_exp = iv_exp.
    cl_abap_unit_assert=>assert_equals( act = l_act exp = l_exp msg = iv_msg ).
  ENDMETHOD.


  METHOD issue_261_production.
    " TS-01 / 원문 SLO_GRO(868~878): 261 H -> 생산출고 +q, 증감 -q
    DATA: lt_delta TYPE zcl_mm_sloc_ledger=>ty_t_delta,
          ls_delta TYPE zcl_mm_sloc_ledger=>ty_s_delta.

    gs_map-giind = zcl_mm_sloc_ledger=>c_giind_pp.
    lt_delta = deltas( ltd_fixture=>item( iv_bwart = ltd_fixture=>c_bwart_261
                                          iv_shkzg = zcl_mm_sloc_ledger=>c_shkzg_h
                                          iv_menge = 16690 ) ).

    cl_abap_unit_assert=>assert_equals( act = lines( lt_delta ) exp = 1
                                        msg = '261: 자기 위치 델타 1건' ).
    ls_delta = pick( it_delta = lt_delta iv_side = zcl_mm_sloc_ledger=>c_side_own ).
    check_qty( iv_act = ls_delta-zpp_gi iv_exp = 16690  iv_msg = '261 H 생산출고 +16,690' ).
    check_qty( iv_act = ls_delta-zclstc iv_exp = -16690 iv_msg = '261 H 증감 -16,690' ).
    cl_abap_unit_assert=>assert_equals( act = ls_delta-werks exp = ltd_fixture=>c_werks
                                        msg = '대상 플랜트 = 품목 WERKS' ).
    cl_abap_unit_assert=>assert_equals( act = ls_delta-lgort exp = ltd_fixture=>c_lgort
                                        msg = '대상 저장위치 = 품목 LGORT' ).
  ENDMETHOD.


  METHOD cancel_262_net_issue.
    " TS-02 / 원문 GI_SQTY_S_RTN(690~706): 262 S -> 생산출고 -q (원래 컬럼 차감)
    DATA: lt_delta TYPE zcl_mm_sloc_ledger=>ty_t_delta,
          ls_delta TYPE zcl_mm_sloc_ledger=>ty_s_delta.

    gs_map-giind = zcl_mm_sloc_ledger=>c_giind_pp.
    lt_delta = deltas( ltd_fixture=>item( iv_bwart = ltd_fixture=>c_bwart_262
                                          iv_shkzg = zcl_mm_sloc_ledger=>c_shkzg_s
                                          iv_menge = 1208 ) ).
    ls_delta = pick( it_delta = lt_delta iv_side = zcl_mm_sloc_ledger=>c_side_own ).
    check_qty( iv_act = ls_delta-zpp_gi iv_exp = -1208 iv_msg = '262 S 생산출고 -1,208 (순액)' ).
    check_qty( iv_act = ls_delta-zclstc iv_exp = 1208  iv_msg = '262 S 증감 +1,208' ).
    check_qty( iv_act = ls_delta-ztp_gr iv_exp = 0     iv_msg = '262 는 입고 컬럼에 안 감' ).
  ENDMETHOD.


  METHOD sample_total_25025.
    " TS-01 첨부 샘플: 261 254,420 - 262 229,395 = 생산출고 25,025 / 증감 -25,025
    DATA: lt_item  TYPE zcl_mm_sloc_ledger=>ty_t_item,
          ls_item  TYPE zcl_mm_sloc_ledger=>ty_s_item,
          lt_delta TYPE zcl_mm_sloc_ledger=>ty_t_delta,
          ls_delta TYPE zcl_mm_sloc_ledger=>ty_s_delta,
          ls_qty   TYPE zcl_mm_sloc_ledger=>ty_s_qty,
          l_calc   TYPE mseg-menge.

    gs_map-giind = zcl_mm_sloc_ledger=>c_giind_pp.
    lt_item = ltd_fixture=>sample_items( ).
    cl_abap_unit_assert=>assert_equals( act = lines( lt_item ) exp = 32
                                        msg = '첨부 샘플 261 17건 + 262 15건' ).

    ls_qty-beg_qty = 100000.
    LOOP AT lt_item INTO ls_item.
      lt_delta = deltas( ls_item ).
      LOOP AT lt_delta INTO ls_delta.
        zcl_mm_sloc_ledger=>apply_delta( EXPORTING is_delta  = ls_delta
                                                   iv_before = abap_false
                                         CHANGING  cs_qty    = ls_qty ).
      ENDLOOP.
    ENDLOOP.
    zcl_mm_sloc_ledger=>finalize( CHANGING cs_qty = ls_qty ).

    check_qty( iv_act = ls_qty-zpp_gi  iv_exp = 25025  iv_msg = '생산출고 ZPP_GI = 25,025 (첨부 R280)' ).
    check_qty( iv_act = ls_qty-zclstc  iv_exp = -25025 iv_msg = '증감 ZCLSTC = -25,025 (첨부 V280)' ).
    check_qty( iv_act = ls_qty-gi_sum  iv_exp = 25025  iv_msg = '출고계 = 25,025' ).
    check_qty( iv_act = ls_qty-gr_sum  iv_exp = 0      iv_msg = '입고계 = 0' ).
    check_qty( iv_act = ls_qty-end_qty iv_exp = 74975  iv_msg = '기말 = 100,000 - 25,025' ).
    " FR-11: 일반 출고·취소만 있으면 기말 = 기초 + 입고계 - 출고계
    l_calc = ls_qty-beg_qty + ls_qty-gr_sum - ls_qty-gi_sum.
    check_qty( iv_act = ls_qty-end_qty iv_exp = l_calc iv_msg = 'FR-11 정합성(일반 이동)' ).
  ENDMETHOD.


  METHOD cancel_102_net_receipt.
    " TS-02 / 원문 SLO_GR1(775~791): 101 +100, 102 -20 -> 구매입고 80
    DATA: lt_delta TYPE zcl_mm_sloc_ledger=>ty_t_delta,
          ls_delta TYPE zcl_mm_sloc_ledger=>ty_s_delta,
          ls_qty   TYPE zcl_mm_sloc_ledger=>ty_s_qty.

    gs_map-grind = zcl_mm_sloc_ledger=>c_grind_po.
    lt_delta = deltas( ltd_fixture=>item( iv_bwart = ltd_fixture=>c_bwart_101
                                          iv_shkzg = zcl_mm_sloc_ledger=>c_shkzg_s
                                          iv_menge = 100 ) ).
    LOOP AT lt_delta INTO ls_delta.
      zcl_mm_sloc_ledger=>apply_delta( EXPORTING is_delta = ls_delta iv_before = abap_false
                                       CHANGING  cs_qty   = ls_qty ).
    ENDLOOP.
    lt_delta = deltas( ltd_fixture=>item( iv_bwart = ltd_fixture=>c_bwart_102
                                          iv_shkzg = zcl_mm_sloc_ledger=>c_shkzg_h
                                          iv_menge = 20 ) ).
    LOOP AT lt_delta INTO ls_delta.
      zcl_mm_sloc_ledger=>apply_delta( EXPORTING is_delta = ls_delta iv_before = abap_false
                                       CHANGING  cs_qty   = ls_qty ).
    ENDLOOP.
    zcl_mm_sloc_ledger=>finalize( CHANGING cs_qty = ls_qty ).

    check_qty( iv_act = ls_qty-zpo_gr  iv_exp = 80 iv_msg = '구매입고 순액 80' ).
    check_qty( iv_act = ls_qty-gi_sum  iv_exp = 0  iv_msg = '102 는 출고 컬럼에 안 감' ).
    check_qty( iv_act = ls_qty-end_qty iv_exp = 80 iv_msg = '기말 +80' ).
  ENDMETHOD.


  METHOD simul_gr_gi_no_stock.
    " TS-07 / 원문 SLO_GR1 + GI_SQTY_S_RTN: 동시출고(GRIND+GIIND) S 품목
    " 입고 +q, 출고 -q, 증감 0  -> 입고계-출고계(2q) <> 증감(0) : R-01 재현
    DATA: lt_delta TYPE zcl_mm_sloc_ledger=>ty_t_delta,
          ls_delta TYPE zcl_mm_sloc_ledger=>ty_s_delta,
          ls_qty   TYPE zcl_mm_sloc_ledger=>ty_s_qty,
          l_net    TYPE mseg-menge.

    gs_map-grind = zcl_mm_sloc_ledger=>c_grind_po.
    gs_map-giind = zcl_mm_sloc_ledger=>c_giind_pp.
    lt_delta = deltas( ltd_fixture=>item( iv_bwart = ltd_fixture=>c_bwart_101
                                          iv_shkzg = zcl_mm_sloc_ledger=>c_shkzg_s
                                          iv_menge = 50 ) ).
    ls_delta = pick( it_delta = lt_delta iv_side = zcl_mm_sloc_ledger=>c_side_own ).
    check_qty( iv_act = ls_delta-zpo_gr iv_exp = 50  iv_msg = '동시출고 입고 +50' ).
    check_qty( iv_act = ls_delta-zpp_gi iv_exp = -50 iv_msg = '동시출고 S 출고 -50 (원문 부호)' ).
    check_qty( iv_act = ls_delta-zclstc iv_exp = 0   iv_msg = '동시출고 증감 0' ).

    zcl_mm_sloc_ledger=>apply_delta( EXPORTING is_delta = ls_delta iv_before = abap_false
                                     CHANGING  cs_qty   = ls_qty ).
    zcl_mm_sloc_ledger=>finalize( CHANGING cs_qty = ls_qty ).
    l_net = ls_qty-gr_sum - ls_qty-gi_sum.
    cl_abap_unit_assert=>assert_differs( act = l_net exp = ls_qty-zclstc
                                         msg = 'R-01: 입고계-출고계 <> 증감 (FR-11 미충족 재현)' ).
  ENDMETHOD.


  METHOD tp1_311_sender.
    " TS-11 / 원문 SL_GRO(740~767): 311 보내는 품목 H, ZTMM0008-SHKZG H
    DATA: ls_item  TYPE zcl_mm_sloc_ledger=>ty_s_item,
          lt_delta TYPE zcl_mm_sloc_ledger=>ty_t_delta,
          ls_delta TYPE zcl_mm_sloc_ledger=>ty_s_delta.

    gs_map-tpind = zcl_mm_sloc_ledger=>c_tpind_1.
    gs_map-shkzg = zcl_mm_sloc_ledger=>c_shkzg_h.
    ls_item = ltd_fixture=>item( iv_bwart = ltd_fixture=>c_bwart_311
                                 iv_shkzg = zcl_mm_sloc_ledger=>c_shkzg_h
                                 iv_menge = 40 ).
    ls_item-umwrk = ltd_fixture=>c_werks.
    ls_item-umlgo = ltd_fixture=>c_lgort2.
    ls_item-ummat = ltd_fixture=>c_matnr.
    lt_delta = deltas( ls_item ).

    cl_abap_unit_assert=>assert_equals( act = lines( lt_delta ) exp = 1
                                        msg = 'TPIND 1 은 자기 위치만 (상대 반영 없음)' ).
    ls_delta = pick( it_delta = lt_delta iv_side = zcl_mm_sloc_ledger=>c_side_own ).
    check_qty( iv_act = ls_delta-ztp_gi iv_exp = 40  iv_msg = '보내는 쪽 이전출고 +40' ).
    check_qty( iv_act = ls_delta-zclstc iv_exp = -40 iv_msg = '보내는 쪽 증감 -40' ).
    cl_abap_unit_assert=>assert_equals( act = ls_delta-lgort exp = ltd_fixture=>c_lgort
                                        msg = '보내는 저장위치' ).
  ENDMETHOD.


  METHOD tp1_311_receiver.
    " TS-11: 311 받는 품목 S -> 받는 저장위치 이전입고 +q (각 품목 자기 위치)
    DATA: ls_item  TYPE zcl_mm_sloc_ledger=>ty_s_item,
          lt_delta TYPE zcl_mm_sloc_ledger=>ty_t_delta,
          ls_delta TYPE zcl_mm_sloc_ledger=>ty_s_delta.

    gs_map-tpind = zcl_mm_sloc_ledger=>c_tpind_1.
    gs_map-shkzg = zcl_mm_sloc_ledger=>c_shkzg_h.
    ls_item = ltd_fixture=>item( iv_bwart = ltd_fixture=>c_bwart_311
                                 iv_shkzg = zcl_mm_sloc_ledger=>c_shkzg_s
                                 iv_menge = 40 ).
    ls_item-lgort = ltd_fixture=>c_lgort2.
    ls_item-umwrk = ltd_fixture=>c_werks.
    ls_item-umlgo = ltd_fixture=>c_lgort.
    ls_item-ummat = ltd_fixture=>c_matnr.
    ls_item-xauto = ltd_fixture=>c_xauto_x.
    lt_delta = deltas( ls_item ).

    cl_abap_unit_assert=>assert_equals( act = lines( lt_delta ) exp = 1
                                        msg = '받는 품목도 자기 위치 1건' ).
    ls_delta = pick( it_delta = lt_delta iv_side = zcl_mm_sloc_ledger=>c_side_own ).
    check_qty( iv_act = ls_delta-ztp_gr iv_exp = 40 iv_msg = '받는 쪽 이전입고 +40' ).
    check_qty( iv_act = ls_delta-zclstc iv_exp = 40 iv_msg = '받는 쪽 증감 +40' ).
    cl_abap_unit_assert=>assert_equals( act = ls_delta-lgort exp = ltd_fixture=>c_lgort2
                                        msg = '받는 저장위치' ).
  ENDMETHOD.


  METHOD tp1_shkzg_blank_none.
    " 원문 SL_GRO 743/754: ZTMM0008-SHKZG 공란이면 반영 없음
    gs_map-tpind = zcl_mm_sloc_ledger=>c_tpind_1.
    cl_abap_unit_assert=>assert_initial(
      act = deltas( ltd_fixture=>item( iv_bwart = ltd_fixture=>c_bwart_311
                                       iv_shkzg = zcl_mm_sloc_ledger=>c_shkzg_h
                                       iv_menge = 10 ) )
      msg = 'TPIND 1 + SHKZG 공란 -> 델타 없음' ).
  ENDMETHOD.


  METHOD tp_grind_123_not_posted.
    " 원문 603/612 '세팅불가': TPIND 1·2 + GRIND 1·2·3 은 반영 없음
    gs_map-tpind = zcl_mm_sloc_ledger=>c_tpind_1.
    gs_map-grind = zcl_mm_sloc_ledger=>c_grind_po.
    cl_abap_unit_assert=>assert_initial(
      act = deltas( ltd_fixture=>item( iv_bwart = ltd_fixture=>c_bwart_311
                                       iv_shkzg = zcl_mm_sloc_ledger=>c_shkzg_s
                                       iv_menge = 10 ) )
      msg = 'TPIND 1 + GRIND 1 -> 없음' ).
    gs_map-tpind = zcl_mm_sloc_ledger=>c_tpind_2.
    gs_map-grind = zcl_mm_sloc_ledger=>c_grind_re.
    cl_abap_unit_assert=>assert_initial(
      act = deltas( ltd_fixture=>item( iv_bwart = ltd_fixture=>c_bwart_301
                                       iv_shkzg = zcl_mm_sloc_ledger=>c_shkzg_s
                                       iv_menge = 10 ) )
      msg = 'TPIND 2 + GRIND 3 -> 없음' ).
  ENDMETHOD.


  METHOD tp_grind_4_transfer.
    " 원문 SL_GR4(663~682): 이전입고 = 부호수량, 증감 = 부호수량(GIIND 공란)
    DATA: lt_delta TYPE zcl_mm_sloc_ledger=>ty_t_delta,
          ls_delta TYPE zcl_mm_sloc_ledger=>ty_s_delta.

    gs_map-tpind = zcl_mm_sloc_ledger=>c_tpind_1.
    gs_map-grind = zcl_mm_sloc_ledger=>c_grind_ot.
    lt_delta = deltas( ltd_fixture=>item( iv_bwart = ltd_fixture=>c_bwart_311
                                          iv_shkzg = zcl_mm_sloc_ledger=>c_shkzg_s
                                          iv_menge = 10 ) ).
    ls_delta = pick( it_delta = lt_delta iv_side = zcl_mm_sloc_ledger=>c_side_own ).
    check_qty( iv_act = ls_delta-ztp_gr iv_exp = 10 iv_msg = 'GR4 S 이전입고 +10' ).
    check_qty( iv_act = ls_delta-zclstc iv_exp = 10 iv_msg = 'GR4 S 증감 +10' ).

    lt_delta = deltas( ltd_fixture=>item( iv_bwart = ltd_fixture=>c_bwart_311
                                          iv_shkzg = zcl_mm_sloc_ledger=>c_shkzg_h
                                          iv_menge = 10 ) ).
    ls_delta = pick( it_delta = lt_delta iv_side = zcl_mm_sloc_ledger=>c_side_own ).
    check_qty( iv_act = ls_delta-ztp_gr iv_exp = -10 iv_msg = 'GR4 H 이전입고 -10' ).
    check_qty( iv_act = ls_delta-zclstc iv_exp = -10 iv_msg = 'GR4 H 증감 -10' ).
  ENDMETHOD.


  METHOD tp2_cross_plant_cpt.
    " 원문 SL2_GRO(1187~1207) + GI_SQTY_S_RTN_TP2: 상대 위치 ZTP_GR, 증감 0
    DATA: ls_item  TYPE zcl_mm_sloc_ledger=>ty_s_item,
          lt_delta TYPE zcl_mm_sloc_ledger=>ty_t_delta,
          ls_own   TYPE zcl_mm_sloc_ledger=>ty_s_delta,
          ls_cpt   TYPE zcl_mm_sloc_ledger=>ty_s_delta.

    gs_map-tpind = zcl_mm_sloc_ledger=>c_tpind_2.
    ls_item = ltd_fixture=>item( iv_bwart = ltd_fixture=>c_bwart_301
                                 iv_shkzg = zcl_mm_sloc_ledger=>c_shkzg_h
                                 iv_menge = 30 ).
    ls_item-umwrk = ltd_fixture=>c_werks2.
    ls_item-umlgo = ltd_fixture=>c_lgort3.
    ls_item-ummat = ltd_fixture=>c_matnr.
    lt_delta = deltas( ls_item ).

    cl_abap_unit_assert=>assert_equals( act = lines( lt_delta ) exp = 2
                                        msg = '자기 1건 + 상대 1건' ).
    ls_own = pick( it_delta = lt_delta iv_side = zcl_mm_sloc_ledger=>c_side_own ).
    check_qty( iv_act = ls_own-ztp_gi iv_exp = 30  iv_msg = '보내는 플랜트 이전출고 +30' ).
    check_qty( iv_act = ls_own-zclstc iv_exp = -30 iv_msg = '보내는 플랜트 증감 -30' ).
    ls_cpt = pick( it_delta = lt_delta iv_side = zcl_mm_sloc_ledger=>c_side_cpt ).
    cl_abap_unit_assert=>assert_equals( act = ls_cpt-werks exp = ltd_fixture=>c_werks2
                                        msg = '상대 = UMWRK' ).
    cl_abap_unit_assert=>assert_equals( act = ls_cpt-lgort exp = ltd_fixture=>c_lgort3
                                        msg = '상대 = UMLGO' ).
    check_qty( iv_act = ls_cpt-ztp_gr iv_exp = 30 iv_msg = '받는 플랜트 이전입고 +30' ).
    check_qty( iv_act = ls_cpt-zclstc iv_exp = 0  iv_msg = '상대 증감 0 (원문 gs_tp2_69)' ).
  ENDMETHOD.


  METHOD tp2_cpt_no_umlgo_trns.
    " UMLGO 공란 상대 -> 가상 TRNS, PA_VSLOC 공란이면 상대 델타 없음
    DATA: ls_item  TYPE zcl_mm_sloc_ledger=>ty_s_item,
          lt_delta TYPE zcl_mm_sloc_ledger=>ty_t_delta,
          ls_cpt   TYPE zcl_mm_sloc_ledger=>ty_s_delta.

    gs_map-tpind = zcl_mm_sloc_ledger=>c_tpind_2.
    ls_item = ltd_fixture=>item( iv_bwart = ltd_fixture=>c_bwart_301
                                 iv_shkzg = zcl_mm_sloc_ledger=>c_shkzg_h
                                 iv_menge = 30 ).
    ls_item-umwrk = ltd_fixture=>c_werks2.
    lt_delta = deltas( ls_item ).
    ls_cpt = pick( it_delta = lt_delta iv_side = zcl_mm_sloc_ledger=>c_side_cpt ).
    cl_abap_unit_assert=>assert_equals( act = ls_cpt-lgort exp = zcl_mm_sloc_ledger=>c_vsloc_trns
                                        msg = '상대 UMLGO 공란 -> TRNS' ).
    cl_abap_unit_assert=>assert_equals( act = ls_cpt-vsloc exp = abap_true msg = '가상 표시' ).

    gs_rule-vsloc = abap_false.
    lt_delta = deltas( ls_item ).
    cl_abap_unit_assert=>assert_equals( act = lines( lt_delta ) exp = 1
                                        msg = '가상 미표시면 자기 델타만' ).
  ENDMETHOD.


  METHOD tp2_same_plant_sign.
    " 원문 1208~1215: UMWRK = WERKS 이면 출고 컬럼 부호 반대(H -> -q)
    DATA: ls_item  TYPE zcl_mm_sloc_ledger=>ty_s_item,
          ls_delta TYPE zcl_mm_sloc_ledger=>ty_s_delta.

    gs_map-tpind = zcl_mm_sloc_ledger=>c_tpind_2.
    gs_map-giind = zcl_mm_sloc_ledger=>c_giind_ot.
    ls_item = ltd_fixture=>item( iv_bwart = ltd_fixture=>c_bwart_301
                                 iv_shkzg = zcl_mm_sloc_ledger=>c_shkzg_h
                                 iv_menge = 10 ).
    ls_item-umwrk = ltd_fixture=>c_werks.
    ls_item-umlgo = ltd_fixture=>c_lgort2.
    ls_delta = pick( it_delta = deltas( ls_item ) iv_side = zcl_mm_sloc_ledger=>c_side_own ).
    check_qty( iv_act = ls_delta-zot_gi iv_exp = -10 iv_msg = '동일 플랜트 기타출고 -10 (원문 부호)' ).
    check_qty( iv_act = ls_delta-zclstc iv_exp = -10 iv_msg = '증감 -10' ).
  ENDMETHOD.


  METHOD tp2_no_umwrk.
    " 원문 1217~1224: UMWRK 공란이면 일반 출고 부호
    DATA ls_delta TYPE zcl_mm_sloc_ledger=>ty_s_delta.

    gs_map-tpind = zcl_mm_sloc_ledger=>c_tpind_2.
    gs_map-giind = zcl_mm_sloc_ledger=>c_giind_ot.
    ls_delta = pick( it_delta = deltas( ltd_fixture=>item( iv_bwart = ltd_fixture=>c_bwart_301
                                                           iv_shkzg = zcl_mm_sloc_ledger=>c_shkzg_h
                                                           iv_menge = 10 ) )
                     iv_side = zcl_mm_sloc_ledger=>c_side_own ).
    check_qty( iv_act = ls_delta-zot_gi iv_exp = 10  iv_msg = 'UMWRK 공란 기타출고 +10' ).
    check_qty( iv_act = ls_delta-zclstc iv_exp = -10 iv_msg = '증감 -10' ).
  ENDMETHOD.


  METHOD same_key_skipped.
    " 원문 583~587: 같은 플랜트·저장위치·자재 사이 이동은 건너뜀
    DATA ls_item TYPE zcl_mm_sloc_ledger=>ty_s_item.

    gs_map-tpind = zcl_mm_sloc_ledger=>c_tpind_1.
    gs_map-shkzg = zcl_mm_sloc_ledger=>c_shkzg_h.
    ls_item = ltd_fixture=>item( iv_bwart = ltd_fixture=>c_bwart_311
                                 iv_shkzg = zcl_mm_sloc_ledger=>c_shkzg_h
                                 iv_menge = 5 ).
    ls_item-umwrk = ltd_fixture=>c_werks.
    ls_item-umlgo = ltd_fixture=>c_lgort.
    ls_item-ummat = ltd_fixture=>c_matnr.
    cl_abap_unit_assert=>assert_initial( act = deltas( ls_item ) msg = '같은 키, 배치 공란 -> 없음' ).

    ls_item-charg = ltd_fixture=>c_charg1.
    ls_item-umcha = ltd_fixture=>c_charg1.
    cl_abap_unit_assert=>assert_initial( act = deltas( ls_item ) msg = '같은 키, 같은 배치 -> 없음' ).
  ENDMETHOD.


  METHOD same_sloc_batch_intra.
    " TS-12: 같은 저장위치 배치 변경 -> intra 델타 (배치 상세만, 메인 제외)
    DATA: ls_item  TYPE zcl_mm_sloc_ledger=>ty_s_item,
          lt_delta TYPE zcl_mm_sloc_ledger=>ty_t_delta,
          ls_delta TYPE zcl_mm_sloc_ledger=>ty_s_delta.

    gs_map-tpind = zcl_mm_sloc_ledger=>c_tpind_1.
    gs_map-shkzg = zcl_mm_sloc_ledger=>c_shkzg_h.
    gs_rule-bw_it = VALUE #( ( sign = 'I' option = 'EQ' low = ltd_fixture=>c_bwart_313 ) ).
    ls_item = ltd_fixture=>item( iv_bwart = ltd_fixture=>c_bwart_311
                                 iv_shkzg = zcl_mm_sloc_ledger=>c_shkzg_h
                                 iv_menge = 5 ).
    ls_item-umwrk = ltd_fixture=>c_werks.
    ls_item-umlgo = ltd_fixture=>c_lgort.
    ls_item-ummat = ltd_fixture=>c_matnr.
    ls_item-charg = ltd_fixture=>c_charg1.
    ls_item-umcha = ltd_fixture=>c_charg2.
    lt_delta = deltas( ls_item ).

    cl_abap_unit_assert=>assert_equals( act = lines( lt_delta ) exp = 1
                                        msg = 'intra 자기 델타 1건, 보조 델타 없음' ).
    ls_delta = pick( it_delta = lt_delta iv_side = zcl_mm_sloc_ledger=>c_side_own ).
    cl_abap_unit_assert=>assert_equals( act = ls_delta-intra exp = abap_true msg = 'intra 표시' ).
    cl_abap_unit_assert=>assert_equals( act = ls_delta-charg exp = ltd_fixture=>c_charg1
                                        msg = '자기 배치' ).
    check_qty( iv_act = ls_delta-zclstc iv_exp = -5 iv_msg = '배치 B0001 증감 -5' ).
  ENDMETHOD.


  METHOD special_stock_excluded.
    " TS-16 / 설계 5.1: 자기 위치는 SOBKZ 공란만
    DATA ls_item TYPE zcl_mm_sloc_ledger=>ty_s_item.

    gs_map-giind = zcl_mm_sloc_ledger=>c_giind_pp.
    ls_item = ltd_fixture=>item( iv_bwart = ltd_fixture=>c_bwart_261
                                 iv_shkzg = zcl_mm_sloc_ledger=>c_shkzg_h
                                 iv_menge = 10 ).
    ls_item-sobkz = ltd_fixture=>c_sobkz_k.
    cl_abap_unit_assert=>assert_initial( act = deltas( ls_item ) msg = '특별재고 K 제외' ).
  ENDMETHOD.


  METHOD blank_lgort_virtual.
    " TS-15 / 설계 5.3: LGORT 공란 -> XAUTO X = TRNS, 그 밖 ZZZZ, 미표시면 없음
    DATA: ls_item  TYPE zcl_mm_sloc_ledger=>ty_s_item,
          ls_delta TYPE zcl_mm_sloc_ledger=>ty_s_delta.

    gs_map-giind = zcl_mm_sloc_ledger=>c_giind_pp.
    ls_item = ltd_fixture=>item( iv_bwart = ltd_fixture=>c_bwart_261
                                 iv_shkzg = zcl_mm_sloc_ledger=>c_shkzg_h
                                 iv_menge = 10 ).
    CLEAR ls_item-lgort.
    ls_item-charg = ltd_fixture=>c_charg1.
    ls_item-xauto = ltd_fixture=>c_xauto_x.
    ls_delta = pick( it_delta = deltas( ls_item ) iv_side = zcl_mm_sloc_ledger=>c_side_own ).
    cl_abap_unit_assert=>assert_equals( act = ls_delta-lgort exp = zcl_mm_sloc_ledger=>c_vsloc_trns
                                        msg = 'XAUTO X -> TRNS' ).
    cl_abap_unit_assert=>assert_equals( act = ls_delta-vsloc exp = abap_true msg = '가상 표시' ).
    cl_abap_unit_assert=>assert_initial( act = ls_delta-charg msg = '가상 행 배치 공란' ).

    CLEAR ls_item-xauto.
    ls_delta = pick( it_delta = deltas( ls_item ) iv_side = zcl_mm_sloc_ledger=>c_side_own ).
    cl_abap_unit_assert=>assert_equals( act = ls_delta-lgort exp = zcl_mm_sloc_ledger=>c_vsloc_unkn
                                        msg = 'XAUTO 공란 -> ZZZZ' ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mm_sloc_ledger=>resolve_vsloc( ls_item )
      exp = zcl_mm_sloc_ledger=>c_vsloc_unkn
      msg = 'resolve_vsloc 직접 호출' ).

    gs_rule-vsloc = abap_false.
    cl_abap_unit_assert=>assert_initial( act = deltas( ls_item ) msg = '가상 미표시면 버림' ).
  ENDMETHOD.


  METHOD overlay_313_in_transfer.
    " TS-13 / 설계 5.2 보조: 313 보내는 품목 -> 받는 저장위치 이전중 +q
    DATA: ls_item  TYPE zcl_mm_sloc_ledger=>ty_s_item,
          lt_delta TYPE zcl_mm_sloc_ledger=>ty_t_delta,
          ls_ovl   TYPE zcl_mm_sloc_ledger=>ty_s_delta.

    gs_map-tpind = zcl_mm_sloc_ledger=>c_tpind_1.
    gs_map-shkzg = zcl_mm_sloc_ledger=>c_shkzg_h.
    gs_rule-bw_it = VALUE #( ( sign = 'I' option = 'EQ' low = ltd_fixture=>c_bwart_313 ) ).
    ls_item = ltd_fixture=>item( iv_bwart = ltd_fixture=>c_bwart_313
                                 iv_shkzg = zcl_mm_sloc_ledger=>c_shkzg_h
                                 iv_menge = 25 ).
    ls_item-umwrk = ltd_fixture=>c_werks.
    ls_item-umlgo = ltd_fixture=>c_lgort2.
    ls_item-ummat = ltd_fixture=>c_matnr.
    lt_delta = deltas( ls_item ).

    cl_abap_unit_assert=>assert_equals( act = lines( lt_delta ) exp = 2
                                        msg = '자기(이전출고) + 이전중 보조' ).
    ls_ovl = pick( it_delta = lt_delta iv_side = zcl_mm_sloc_ledger=>c_side_ovl ).
    cl_abap_unit_assert=>assert_equals( act = ls_ovl-lgort exp = ltd_fixture=>c_lgort2
                                        msg = '받는 저장위치' ).
    check_qty( iv_act = ls_ovl-uml    iv_exp = 25 iv_msg = '이전중 +25' ).
    check_qty( iv_act = ls_ovl-zclstc iv_exp = 0  iv_msg = '이전중 보조는 재고 증감 0' ).
  ENDMETHOD.


  METHOD overlay_313_auto_item.
    " R-02 확인용: 313 자동생성(XAUTO X) 받는 품목은 이전중 보조를 만들지 않지만
    " ZTMM0008 매핑이 있으면 자기 위치 재고 증감(+q)은 생긴다.
    " -> 받는 저장위치에서 기말 +25 와 이전중 +25 가 함께 잡힐 수 있음 (C-05)
    DATA: ls_item  TYPE zcl_mm_sloc_ledger=>ty_s_item,
          lt_delta TYPE zcl_mm_sloc_ledger=>ty_t_delta,
          ls_delta TYPE zcl_mm_sloc_ledger=>ty_s_delta.

    gs_map-tpind = zcl_mm_sloc_ledger=>c_tpind_1.
    gs_map-shkzg = zcl_mm_sloc_ledger=>c_shkzg_h.
    gs_rule-bw_it = VALUE #( ( sign = 'I' option = 'EQ' low = ltd_fixture=>c_bwart_313 ) ).
    ls_item = ltd_fixture=>item( iv_bwart = ltd_fixture=>c_bwart_313
                                 iv_shkzg = zcl_mm_sloc_ledger=>c_shkzg_s
                                 iv_menge = 25 ).
    ls_item-lgort = ltd_fixture=>c_lgort2.
    ls_item-umwrk = ltd_fixture=>c_werks.
    ls_item-umlgo = ltd_fixture=>c_lgort.
    ls_item-ummat = ltd_fixture=>c_matnr.
    ls_item-xauto = ltd_fixture=>c_xauto_x.
    lt_delta = deltas( ls_item ).

    cl_abap_unit_assert=>assert_equals( act = lines( lt_delta ) exp = 1
                                        msg = '자동생성 품목은 보조 델타 없음' ).
    ls_delta = pick( it_delta = lt_delta iv_side = zcl_mm_sloc_ledger=>c_side_own ).
    check_qty( iv_act = ls_delta-zclstc iv_exp = 25 iv_msg = '자동생성 품목 자기 증감 +25 (R-02)' ).
  ENDMETHOD.


  METHOD overlay_315_receipt.
    " TS-13: 315 받는 품목 -> 자기 이전입고 +q, 이전중 -q
    DATA: ls_item  TYPE zcl_mm_sloc_ledger=>ty_s_item,
          lt_delta TYPE zcl_mm_sloc_ledger=>ty_t_delta,
          ls_delta TYPE zcl_mm_sloc_ledger=>ty_s_delta.

    gs_map-tpind = zcl_mm_sloc_ledger=>c_tpind_1.
    gs_map-shkzg = zcl_mm_sloc_ledger=>c_shkzg_h.
    gs_rule-bw_ir = VALUE #( ( sign = 'I' option = 'EQ' low = ltd_fixture=>c_bwart_315 ) ).
    ls_item = ltd_fixture=>item( iv_bwart = ltd_fixture=>c_bwart_315
                                 iv_shkzg = zcl_mm_sloc_ledger=>c_shkzg_s
                                 iv_menge = 25 ).
    ls_item-lgort = ltd_fixture=>c_lgort2.
    lt_delta = deltas( ls_item ).

    cl_abap_unit_assert=>assert_equals( act = lines( lt_delta ) exp = 1 msg = '자기 델타 1건' ).
    ls_delta = pick( it_delta = lt_delta iv_side = zcl_mm_sloc_ledger=>c_side_own ).
    check_qty( iv_act = ls_delta-ztp_gr iv_exp = 25  iv_msg = '이전입고 +25' ).
    check_qty( iv_act = ls_delta-uml    iv_exp = -25 iv_msg = '이전중 -25' ).
  ENDMETHOD.


  METHOD overlay_303_trns_up.
    " TS-14: 303 보내는 품목 -> 받는 플랜트 TRNS 증감 +q
    DATA: ls_item  TYPE zcl_mm_sloc_ledger=>ty_s_item,
          lt_delta TYPE zcl_mm_sloc_ledger=>ty_t_delta,
          ls_ovl   TYPE zcl_mm_sloc_ledger=>ty_s_delta.

    gs_map-tpind = zcl_mm_sloc_ledger=>c_tpind_1.
    gs_map-shkzg = zcl_mm_sloc_ledger=>c_shkzg_h.
    gs_rule-bw_pt = VALUE #( ( sign = 'I' option = 'EQ' low = ltd_fixture=>c_bwart_303 ) ).
    ls_item = ltd_fixture=>item( iv_bwart = ltd_fixture=>c_bwart_303
                                 iv_shkzg = zcl_mm_sloc_ledger=>c_shkzg_h
                                 iv_menge = 60 ).
    ls_item-umwrk = ltd_fixture=>c_werks2.
    lt_delta = deltas( ls_item ).

    ls_ovl = pick( it_delta = lt_delta iv_side = zcl_mm_sloc_ledger=>c_side_ovl ).
    cl_abap_unit_assert=>assert_equals( act = ls_ovl-werks exp = ltd_fixture=>c_werks2
                                        msg = '받는 플랜트' ).
    cl_abap_unit_assert=>assert_equals( act = ls_ovl-lgort exp = zcl_mm_sloc_ledger=>c_vsloc_trns
                                        msg = 'TRNS 행' ).
    check_qty( iv_act = ls_ovl-zclstc iv_exp = 60 iv_msg = '운송중 +60' ).
  ENDMETHOD.


  METHOD overlay_305_trns_down.
    " TS-14: 305 받는 품목 -> 자기 플랜트 TRNS 증감 -q
    DATA: ls_item TYPE zcl_mm_sloc_ledger=>ty_s_item,
          ls_ovl  TYPE zcl_mm_sloc_ledger=>ty_s_delta.

    gs_map-tpind = zcl_mm_sloc_ledger=>c_tpind_1.
    gs_map-shkzg = zcl_mm_sloc_ledger=>c_shkzg_h.
    gs_rule-bw_pr = VALUE #( ( sign = 'I' option = 'EQ' low = ltd_fixture=>c_bwart_305 ) ).
    ls_item = ltd_fixture=>item( iv_bwart = ltd_fixture=>c_bwart_305
                                 iv_shkzg = zcl_mm_sloc_ledger=>c_shkzg_s
                                 iv_menge = 60 ).
    ls_item-werks = ltd_fixture=>c_werks2.
    ls_item-lgort = ltd_fixture=>c_lgort3.
    ls_ovl = pick( it_delta = deltas( ls_item ) iv_side = zcl_mm_sloc_ledger=>c_side_ovl ).
    cl_abap_unit_assert=>assert_equals( act = ls_ovl-werks exp = ltd_fixture=>c_werks2
                                        msg = '자기 플랜트' ).
    check_qty( iv_act = ls_ovl-zclstc iv_exp = -60 iv_msg = '운송중 -60' ).
  ENDMETHOD.


  METHOD column_mapping.
    " 원문 618~629, 692~705: GRIND/GIIND 1~4 -> 컬럼, 그 밖은 공란
    DATA: l_grind TYPE ztmm0008-grind,
          l_giind TYPE ztmm0008-giind.

    cl_abap_unit_assert=>assert_equals( act = zcl_mm_sloc_ledger=>gr_column( zcl_mm_sloc_ledger=>c_grind_po )
                                        exp = zcl_mm_sloc_ledger=>c_fn_zpo_gr msg = 'GR 1' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_mm_sloc_ledger=>gr_column( zcl_mm_sloc_ledger=>c_grind_pp )
                                        exp = zcl_mm_sloc_ledger=>c_fn_zpp_gr msg = 'GR 2' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_mm_sloc_ledger=>gr_column( zcl_mm_sloc_ledger=>c_grind_re )
                                        exp = zcl_mm_sloc_ledger=>c_fn_zre_gr msg = 'GR 3' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_mm_sloc_ledger=>gr_column( zcl_mm_sloc_ledger=>c_grind_ot )
                                        exp = zcl_mm_sloc_ledger=>c_fn_zot_gr msg = 'GR 4' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_mm_sloc_ledger=>gi_column( zcl_mm_sloc_ledger=>c_giind_sd )
                                        exp = zcl_mm_sloc_ledger=>c_fn_zsd_gi msg = 'GI 1' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_mm_sloc_ledger=>gi_column( zcl_mm_sloc_ledger=>c_giind_pp )
                                        exp = zcl_mm_sloc_ledger=>c_fn_zpp_gi msg = 'GI 2' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_mm_sloc_ledger=>gi_column( zcl_mm_sloc_ledger=>c_giind_sp )
                                        exp = zcl_mm_sloc_ledger=>c_fn_zsp_gi msg = 'GI 3' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_mm_sloc_ledger=>gi_column( zcl_mm_sloc_ledger=>c_giind_ot )
                                        exp = zcl_mm_sloc_ledger=>c_fn_zot_gi msg = 'GI 4' ).
    CLEAR l_grind.
    cl_abap_unit_assert=>assert_initial( act = zcl_mm_sloc_ledger=>gr_column( l_grind ) msg = 'GR 공란' ).
    l_giind = ltd_fixture=>c_ind_9.
    cl_abap_unit_assert=>assert_initial( act = zcl_mm_sloc_ledger=>gi_column( l_giind ) msg = 'GI 미등록' ).
  ENDMETHOD.


  METHOD gi_unknown_value.
    " R-01 확인용: GIIND 미등록 값이면 컬럼 없이 증감만 생김 (원문 CASE OTHERS 없음)
    DATA ls_delta TYPE zcl_mm_sloc_ledger=>ty_s_delta.

    gs_map-giind = ltd_fixture=>c_ind_9.
    ls_delta = pick( it_delta = deltas( ltd_fixture=>item( iv_bwart = ltd_fixture=>c_bwart_261
                                                           iv_shkzg = zcl_mm_sloc_ledger=>c_shkzg_h
                                                           iv_menge = 10 ) )
                     iv_side = zcl_mm_sloc_ledger=>c_side_own ).
    check_qty( iv_act = ls_delta-zot_gi iv_exp = 0   iv_msg = '미등록 GIIND -> 출고 컬럼 없음' ).
    check_qty( iv_act = ls_delta-zclstc iv_exp = -10 iv_msg = '재고 증감은 -10 (R-01)' ).
  ENDMETHOD.


  METHOD period_end_gap_month.
    " TS-04 / 설계 5.4 UT-13: 이력 202601=100, 202604=150, X=202603 -> 150
    DATA: lt_hist TYPE zcl_mm_sloc_ledger=>ty_t_hist,
          ls_cur  TYPE zcl_mm_sloc_ledger=>ty_s_hist,
          ls_end  TYPE zcl_mm_sloc_ledger=>ty_s_hist,
          l_x     TYPE zcl_mm_sloc_ledger=>ty_period VALUE '202603'.

    lt_hist = VALUE #( ( period = '202604' qty = 150 )
                       ( period = '202601' qty = 100 ) ).
    ls_cur-period = '202605'.
    ls_cur-qty    = 160.
    ls_end = zcl_mm_sloc_ledger=>pick_period_end( it_hist = lt_hist iv_period = l_x is_cur = ls_cur ).
    check_qty( iv_act = ls_end-qty iv_exp = 150 iv_msg = '기간 >= X 중 가장 이른 이력' ).
  ENDMETHOD.


  METHOD period_end_exact.
    DATA: lt_hist TYPE zcl_mm_sloc_ledger=>ty_t_hist,
          ls_cur  TYPE zcl_mm_sloc_ledger=>ty_s_hist,
          ls_end  TYPE zcl_mm_sloc_ledger=>ty_s_hist,
          l_x     TYPE zcl_mm_sloc_ledger=>ty_period VALUE '202603'.

    lt_hist = VALUE #( ( period = '202604' qty = 150 uml = 7 )
                       ( period = '202603' qty = 90  uml = 5 ) ).
    ls_cur-period = '202605'.
    ls_end = zcl_mm_sloc_ledger=>pick_period_end( it_hist = lt_hist iv_period = l_x is_cur = ls_cur ).
    check_qty( iv_act = ls_end-qty iv_exp = 90 iv_msg = '같은 기간 이력' ).
    check_qty( iv_act = ls_end-uml iv_exp = 5  iv_msg = '이전중도 같은 레코드' ).
  ENDMETHOD.


  METHOD period_end_current.
    " UT-14: 이력 없음, 현재 기간 202602 <= X -> 현재값
    DATA: lt_hist TYPE zcl_mm_sloc_ledger=>ty_t_hist,
          ls_cur  TYPE zcl_mm_sloc_ledger=>ty_s_hist,
          ls_end  TYPE zcl_mm_sloc_ledger=>ty_s_hist,
          l_x     TYPE zcl_mm_sloc_ledger=>ty_period VALUE '202603'.

    ls_cur-period = '202602'.
    ls_cur-qty    = 70.
    ls_end = zcl_mm_sloc_ledger=>pick_period_end( it_hist = lt_hist iv_period = l_x is_cur = ls_cur ).
    check_qty( iv_act = ls_end-qty iv_exp = 70 iv_msg = '현재 레코드 값' ).
  ENDMETHOD.


  METHOD period_end_after_x.
    " UT-15: 이력 없음, 현재 기간 202605 > X -> 0
    DATA: lt_hist TYPE zcl_mm_sloc_ledger=>ty_t_hist,
          ls_cur  TYPE zcl_mm_sloc_ledger=>ty_s_hist,
          ls_end  TYPE zcl_mm_sloc_ledger=>ty_s_hist,
          l_x     TYPE zcl_mm_sloc_ledger=>ty_period VALUE '202603'.

    ls_cur-period = '202605'.
    ls_cur-qty    = 160.
    ls_end = zcl_mm_sloc_ledger=>pick_period_end( it_hist = lt_hist iv_period = l_x is_cur = ls_cur ).
    check_qty( iv_act = ls_end-qty iv_exp = 0 iv_msg = 'X 이후 생성 -> 0' ).
    cl_abap_unit_assert=>assert_equals( act = ls_end-period exp = l_x msg = '기간 = X' ).
  ENDMETHOD.


  METHOD prev_period_year_turn.
    " TS-05: 1월 -> 전년 12월, 5월 -> 4월
    DATA: l_exp1 TYPE zcl_mm_sloc_ledger=>ty_period VALUE '202512',
          l_exp2 TYPE zcl_mm_sloc_ledger=>ty_period VALUE '202604'.

    cl_abap_unit_assert=>assert_equals( act = zcl_mm_sloc_ledger=>prev_period( ltd_fixture=>c_d0115y )
                                        exp = l_exp1 msg = '2026-01-15 -> 202512' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_mm_sloc_ledger=>prev_period( ltd_fixture=>c_d0503 )
                                        exp = l_exp2 msg = '2026-05-03 -> 202604' ).
  ENDMETHOD.


  METHOD month_start_and_period.
    DATA: l_gja TYPE mard-lfgja VALUE '2026',
          l_mon TYPE mard-lfmon VALUE '05',
          l_exp TYPE zcl_mm_sloc_ledger=>ty_period VALUE '202605'.

    cl_abap_unit_assert=>assert_equals( act = zcl_mm_sloc_ledger=>month_start( ltd_fixture=>c_d0503 )
                                        exp = ltd_fixture=>c_d0501 msg = '월초' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_mm_sloc_ledger=>to_period( iv_gja = l_gja iv_mon = l_mon )
                                        exp = l_exp msg = 'YYYYMM' ).
  ENDMETHOD.


  METHOD apply_delta_before.
    " TS-03: 월초~시작일 전날 델타는 기초(증감·이전중)에만
    DATA: ls_delta TYPE zcl_mm_sloc_ledger=>ty_s_delta,
          ls_qty   TYPE zcl_mm_sloc_ledger=>ty_s_qty.

    ls_delta-zpp_gi = 10.
    ls_delta-zclstc = -10.
    ls_delta-uml    = 3.
    zcl_mm_sloc_ledger=>apply_delta( EXPORTING is_delta = ls_delta iv_before = abap_true
                                     CHANGING  cs_qty   = ls_qty ).
    check_qty( iv_act = ls_qty-beg_qty iv_exp = -10 iv_msg = '기초 -10' ).
    check_qty( iv_act = ls_qty-uml_beg iv_exp = 3   iv_msg = '이전중 기초 +3' ).
    check_qty( iv_act = ls_qty-zpp_gi  iv_exp = 0   iv_msg = '기간 컬럼 영향 없음' ).
    check_qty( iv_act = ls_qty-zclstc  iv_exp = 0   iv_msg = '기간 증감 영향 없음' ).
  ENDMETHOD.


  METHOD apply_delta_period.
    DATA: ls_delta TYPE zcl_mm_sloc_ledger=>ty_s_delta,
          ls_qty   TYPE zcl_mm_sloc_ledger=>ty_s_qty.

    ls_delta-zpp_gi = 10.
    ls_delta-zclstc = -10.
    ls_delta-uml    = 3.
    zcl_mm_sloc_ledger=>apply_delta( EXPORTING is_delta = ls_delta iv_before = abap_false
                                     CHANGING  cs_qty   = ls_qty ).
    check_qty( iv_act = ls_qty-zpp_gi  iv_exp = 10  iv_msg = '생산출고 +10' ).
    check_qty( iv_act = ls_qty-zclstc  iv_exp = -10 iv_msg = '증감 -10' ).
    check_qty( iv_act = ls_qty-uml_chg iv_exp = 3   iv_msg = '이전중 증감 +3' ).
    check_qty( iv_act = ls_qty-beg_qty iv_exp = 0   iv_msg = '기초 영향 없음' ).
  ENDMETHOD.


  METHOD finalize_formula.
    " TS-06 / 설계 5.5: 합계·기말·이전중 기말, 여러 번 불러도 같은 값
    DATA: ls_qty  TYPE zcl_mm_sloc_ledger=>ty_s_qty,
          l_calc  TYPE mseg-menge.

    ls_qty-beg_qty = 100.
    ls_qty-zpo_gr  = 10.
    ls_qty-zpp_gr  = 5.
    ls_qty-ztp_gr  = 1.
    ls_qty-zre_gr  = 2.
    ls_qty-zot_gr  = 3.
    ls_qty-zsd_gi  = 4.
    ls_qty-zpp_gi  = 6.
    ls_qty-zsp_gi  = 1.
    ls_qty-zot_gi  = 2.
    ls_qty-zclstc  = 8.
    ls_qty-uml_beg = 5.
    ls_qty-uml_chg = -2.
    zcl_mm_sloc_ledger=>finalize( CHANGING cs_qty = ls_qty ).
    zcl_mm_sloc_ledger=>finalize( CHANGING cs_qty = ls_qty ).

    check_qty( iv_act = ls_qty-gr_sum  iv_exp = 21  iv_msg = '입고계' ).
    check_qty( iv_act = ls_qty-gi_sum  iv_exp = 13  iv_msg = '출고계' ).
    check_qty( iv_act = ls_qty-end_qty iv_exp = 108 iv_msg = '기말 = 기초 + 증감' ).
    check_qty( iv_act = ls_qty-uml_end iv_exp = 3   iv_msg = '이전중 기말' ).
    l_calc = ls_qty-beg_qty + ls_qty-gr_sum - ls_qty-gi_sum.
    check_qty( iv_act = ls_qty-end_qty iv_exp = l_calc iv_msg = 'FR-11 (증감 = 입고계-출고계일 때)' ).
  ENDMETHOD.


  METHOD is_zero_flag.
    DATA ls_qty TYPE zcl_mm_sloc_ledger=>ty_s_qty.

    cl_abap_unit_assert=>assert_equals( act = zcl_mm_sloc_ledger=>is_zero( ls_qty )
                                        exp = abap_true msg = '모두 0 -> X' ).
    ls_qty-uml_end = 1.
    cl_abap_unit_assert=>assert_equals( act = zcl_mm_sloc_ledger=>is_zero( ls_qty )
                                        exp = abap_false msg = '이전중만 있어도 표시' ).
  ENDMETHOD.


  METHOD exclude_range_bustm.
    " TS-19: 선택화면 I 값 -> SIGN E, 의미까지 확인 (wiki: range 는 IN 으로 검증)
    DATA: lt_in   TYPE zcl_mm_sloc_ledger=>ty_r_bustm,
          lt_r    TYPE zcl_mm_sloc_ledger=>ty_r_bustm,
          ls_r    LIKE LINE OF lt_r,
          l_bustm TYPE mseg-bustm,
          l_flag  TYPE abap_bool.

    lt_in = VALUE #( ( sign = 'I' option = 'EQ' low = zcl_mm_sloc_ledger=>c_bustm_ma02 )
                     ( sign = 'I' low = zcl_mm_sloc_ledger=>c_bustm_ma05 ) ).
    lt_r = zcl_mm_sloc_ledger=>to_exclude_range( lt_in ).

    cl_abap_unit_assert=>assert_equals( act = lines( lt_r ) exp = 2 msg = '2행' ).
    READ TABLE lt_r INTO ls_r INDEX 2.
    cl_abap_unit_assert=>assert_equals( act = ls_r-sign exp = zcl_mm_sloc_ledger=>c_sign_e msg = 'SIGN E' ).
    cl_abap_unit_assert=>assert_equals( act = ls_r-option exp = zcl_mm_sloc_ledger=>c_opt_eq
                                        msg = 'OPTION 공란 -> EQ' ).

    l_bustm = ltd_fixture=>c_bustm.
    l_flag = abap_false.
    IF l_bustm IN lt_r.
      l_flag = abap_true.
    ENDIF.
    cl_abap_unit_assert=>assert_equals( act = l_flag exp = abap_true msg = 'MA01 은 남음' ).

    l_bustm = zcl_mm_sloc_ledger=>c_bustm_ma05.
    l_flag = abap_false.
    IF l_bustm IN lt_r.
      l_flag = abap_true.
    ENDIF.
    cl_abap_unit_assert=>assert_equals( act = l_flag exp = abap_false msg = 'MA05 는 제외' ).
  ENDMETHOD.


  METHOD exclude_range_empty.
    DATA: lt_in   TYPE zcl_mm_sloc_ledger=>ty_r_bustm,
          lt_r    TYPE zcl_mm_sloc_ledger=>ty_r_bustm,
          l_bustm TYPE mseg-bustm,
          l_flag  TYPE abap_bool.

    lt_r = zcl_mm_sloc_ledger=>to_exclude_range( lt_in ).
    cl_abap_unit_assert=>assert_initial( act = lt_r msg = '빈 값 -> 빈 range' ).
    l_bustm = zcl_mm_sloc_ledger=>c_bustm_ma02.
    IF l_bustm IN lt_r.
      l_flag = abap_true.
    ENDIF.
    cl_abap_unit_assert=>assert_equals( act = l_flag exp = abap_true msg = '빈 range = 조건 없음' ).
  ENDMETHOD.


  METHOD mov_fields_complete.
    " 문서 목록(get_docs) 컬럼 목록: 유형 10 + 증감 + 이전중
    DATA lt_fname TYPE zcl_mm_sloc_ledger=>ty_t_fname.

    lt_fname = zcl_mm_sloc_ledger=>mov_fields( ).
    cl_abap_unit_assert=>assert_equals( act = lines( lt_fname ) exp = 12 msg = '12개 컬럼' ).
    READ TABLE lt_fname TRANSPORTING NO FIELDS WITH KEY table_line = zcl_mm_sloc_ledger=>c_fn_zclstc.
    cl_abap_unit_assert=>assert_subrc( exp = 0 act = sy-subrc msg = 'ZCLSTC 포함' ).
  ENDMETHOD.

ENDCLASS.


*----------------------------------------------------------------------*
* 인스턴스 가드·품목 처리·집계 (LOCAL FRIENDS, DB 없음)
*----------------------------------------------------------------------*
CLASS ltcl_ledger DEFINITION FINAL FOR TESTING
  RISK LEVEL HARMLESS
  DURATION SHORT.

  PRIVATE SECTION.
    DATA g_cut TYPE REF TO zcl_mm_sloc_ledger.

    METHODS setup.

    METHODS check_qty
      IMPORTING
        iv_act TYPE any
        iv_exp TYPE any
        iv_msg TYPE csequence.

    METHODS post_all
      IMPORTING
        it_item TYPE zcl_mm_sloc_ledger=>ty_t_item.

    METHODS:
      ctor_normalizes_sel      FOR TESTING,
      run_needs_check_plants   FOR TESTING,
      check_plants_empty_guard FOR TESTING,
      getters_before_run       FOR TESTING,
      item_t156w_filter        FOR TESTING,
      item_xauto_u_as_blank    FOR TESTING,
      item_unmapped_counted    FOR TESTING,
      item_plant_filter_cpt    FOR TESTING,
      item_lgort_filter        FOR TESTING,
      sample_sloc_with_begin   FOR TESTING,
      batch_sum_equals_sloc    FOR TESTING,
      batch_detail_nonbatch    FOR TESTING,
      batch_detail_virtual     FOR TESTING,
      recon_guard_month_end    FOR TESTING.
ENDCLASS.


CLASS ltcl_ledger IMPLEMENTATION.

  METHOD setup.
    CREATE OBJECT g_cut
      EXPORTING
        is_sel = ltd_fixture=>sel( ).
    ltd_fixture=>inject( g_cut ).
  ENDMETHOD.


  METHOD check_qty.
    DATA: l_act TYPE mseg-menge,
          l_exp TYPE mseg-menge.

    l_act = iv_act.
    l_exp = iv_exp.
    cl_abap_unit_assert=>assert_equals( act = l_act exp = l_exp msg = iv_msg ).
  ENDMETHOD.


  METHOD post_all.
    " read_movements 의 패키지 루프와 같은 순서 (handle_item -> post_delta)
    DATA: ls_item   TYPE zcl_mm_sloc_ledger=>ty_s_item,
          lt_delta  TYPE zcl_mm_sloc_ledger=>ty_t_delta,
          ls_delta  TYPE zcl_mm_sloc_ledger=>ty_s_delta,
          l_before  TYPE abap_bool.

    LOOP AT it_item INTO ls_item.
      lt_delta = g_cut->handle_item( is_item = ls_item iv_count = abap_true ).
      l_before = abap_false.
      IF ls_item-budat < g_cut->gs_sel-budat_from.
        l_before = abap_true.
      ENDIF.
      LOOP AT lt_delta INTO ls_delta.
        zcl_mm_sloc_ledger=>post_delta( EXPORTING is_delta  = ls_delta
                                                  iv_before = l_before
                                                  iv_charg  = ls_delta-charg
                                        CHANGING  ct_bal    = g_cut->gt_bal ).
        IF ls_delta-intra = abap_false.
          zcl_mm_sloc_ledger=>post_delta( EXPORTING is_delta  = ls_delta
                                                    iv_before = l_before
                                                    iv_charg  = space
                                          CHANGING  ct_bal    = g_cut->gt_sloc ).
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.


  METHOD ctor_normalizes_sel.
    " 설계 UT-19: 종료일 공란 -> 시작일, 월초·직전 기간·제외 range 준비
    DATA: ls_sel TYPE zcl_mm_sloc_ledger=>ty_s_sel,
          l_cut  TYPE REF TO zcl_mm_sloc_ledger,
          ls_r   LIKE LINE OF ls_sel-xbustm,
          l_x    TYPE zcl_mm_sloc_ledger=>ty_period VALUE '202604'.

    ls_sel = ltd_fixture=>sel( ).
    CLEAR ls_sel-budat_to.
    CREATE OBJECT l_cut
      EXPORTING
        is_sel = ls_sel.
    ls_sel = l_cut->get_sel( ).

    cl_abap_unit_assert=>assert_equals( act = ls_sel-budat_to exp = ltd_fixture=>c_d0503
                                        msg = '종료일 = 시작일' ).
    cl_abap_unit_assert=>assert_equals( act = l_cut->g_month_start exp = ltd_fixture=>c_d0501
                                        msg = '월초' ).
    cl_abap_unit_assert=>assert_equals( act = l_cut->g_period_x exp = l_x msg = '직전 기간 X' ).
    READ TABLE l_cut->r_bustm INTO ls_r INDEX 1.
    cl_abap_unit_assert=>assert_equals( act = ls_r-sign exp = zcl_mm_sloc_ledger=>c_sign_e
                                        msg = 'BUSTM 제외 range' ).
  ENDMETHOD.


  METHOD run_needs_check_plants.
    " TS-21: check_plants 전에는 DB 를 읽지 않고 빈 결과
    DATA lt_main TYPE zcl_mm_sloc_ledger=>ty_t_main.

    lt_main = g_cut->run( ).
    cl_abap_unit_assert=>assert_initial( act = lt_main msg = 'check_plants 전 run -> 빈 결과' ).
    cl_abap_unit_assert=>assert_equals( act = g_cut->g_loaded exp = abap_false msg = '미적재' ).
  ENDMETHOD.


  METHOD check_plants_empty_guard.
    " TS-21: 빈 플랜트 range 는 T001W SELECT 전에 RETURN (전체 플랜트 조회 방지)
    DATA: ls_sel     TYPE zcl_mm_sloc_ledger=>ty_s_sel,
          l_cut      TYPE REF TO zcl_mm_sloc_ledger,
          l_exist    TYPE i,
          l_allowed  TYPE i,
          l_denied   TYPE i,
          lt_main    TYPE zcl_mm_sloc_ledger=>ty_t_main.

    ls_sel = ltd_fixture=>sel( ).
    CLEAR ls_sel-werks.
    CREATE OBJECT l_cut
      EXPORTING
        is_sel = ls_sel.
    l_cut->check_plants( IMPORTING ev_exist   = l_exist
                                   ev_allowed = l_allowed
                                   ev_denied  = l_denied ).
    cl_abap_unit_assert=>assert_equals( act = l_exist exp = 0 msg = '존재 0' ).
    cl_abap_unit_assert=>assert_equals( act = l_allowed exp = 0 msg = '허용 0' ).
    cl_abap_unit_assert=>assert_equals( act = l_cut->g_checked exp = abap_false msg = '미체크' ).
    lt_main = l_cut->run( ).
    cl_abap_unit_assert=>assert_initial( act = lt_main msg = 'run -> 빈 결과' ).
  ENDMETHOD.


  METHOD getters_before_run.
    " run 전 get_batch / get_docs / get_recon 은 DB 없이 빈 결과
    DATA: lt_key   TYPE zcl_mm_sloc_ledger=>ty_t_key,
          ls_key   TYPE zcl_mm_sloc_ledger=>ty_s_key,
          ls_dkey  TYPE zcl_mm_sloc_ledger=>ty_s_dkey,
          lt_batch TYPE zcl_mm_sloc_ledger=>ty_t_batch,
          lt_diff  TYPE zcl_mm_sloc_ledger=>ty_t_key,
          l_diff   TYPE mseg-menge,
          lt_recon TYPE zcl_mm_sloc_ledger=>ty_t_recon,
          l_ok     TYPE abap_bool.

    ls_key-werks = ltd_fixture=>c_werks.
    ls_key-matnr = ltd_fixture=>c_matnr.
    ls_key-lgort = ltd_fixture=>c_lgort.
    APPEND ls_key TO lt_key.
    MOVE-CORRESPONDING ls_key TO ls_dkey.

    g_cut->get_batch( EXPORTING it_key      = lt_key
                      IMPORTING et_batch    = lt_batch
                                et_diff_key = lt_diff
                                ev_diff_qty = l_diff ).
    cl_abap_unit_assert=>assert_initial( act = lt_batch msg = 'get_batch 빈 결과' ).
    cl_abap_unit_assert=>assert_initial( act = g_cut->get_docs( ls_dkey ) msg = 'get_docs 빈 결과' ).
    g_cut->get_recon( EXPORTING it_key   = lt_key
                      IMPORTING et_recon = lt_recon
                                ev_ok    = l_ok ).
    cl_abap_unit_assert=>assert_equals( act = l_ok exp = abap_false msg = 'get_recon 미실행' ).
  ENDMETHOD.


  METHOD item_t156w_filter.
    " TS-17 / 원문 172~183: T156W(BSX)에 BUSTW 가 없으면 제외, 매핑 누락으로 세지 않음
    DATA ls_item TYPE zcl_mm_sloc_ledger=>ty_s_item.

    ls_item = ltd_fixture=>item( iv_bwart = ltd_fixture=>c_bwart_261
                                 iv_shkzg = zcl_mm_sloc_ledger=>c_shkzg_h
                                 iv_menge = 10 ).
    cl_abap_unit_assert=>assert_equals(
      act = lines( g_cut->handle_item( is_item = ls_item iv_count = abap_true ) )
      exp = 1 msg = '재고계정 전기 품목은 통과' ).

    ls_item-bustw = ltd_fixture=>c_bustw_no.
    cl_abap_unit_assert=>assert_initial(
      act = g_cut->handle_item( is_item = ls_item iv_count = abap_true )
      msg = '비재고 전기(BSX 없음) 제외' ).
    cl_abap_unit_assert=>assert_equals( act = g_cut->g_unmapped exp = 0
                                        msg = 'T156W 제외는 매핑 누락이 아님' ).
  ENDMETHOD.


  METHOD item_xauto_u_as_blank.
    " TS-17 / 원문 172~174: XAUTO 'U' 는 공란으로 T156W 판정, 'X' 는 별도 키
    DATA ls_item TYPE zcl_mm_sloc_ledger=>ty_s_item.

    ls_item = ltd_fixture=>item( iv_bwart = ltd_fixture=>c_bwart_261
                                 iv_shkzg = zcl_mm_sloc_ledger=>c_shkzg_h
                                 iv_menge = 10 ).
    ls_item-xauto = ltd_fixture=>c_xauto_u.
    cl_abap_unit_assert=>assert_equals(
      act = lines( g_cut->handle_item( is_item = ls_item iv_count = abap_true ) )
      exp = 1 msg = 'U -> 공란 키로 통과' ).
    ls_item-xauto = ltd_fixture=>c_xauto_x.
    cl_abap_unit_assert=>assert_initial(
      act = g_cut->handle_item( is_item = ls_item iv_count = abap_true )
      msg = 'XBGBB X 행이 없으면 제외' ).
  ENDMETHOD.


  METHOD item_unmapped_counted.
    " TS-18: 재고계정 전기인데 ZTMM0008 매핑 없음 -> 자기 플랜트 기준으로만 셈
    DATA ls_item TYPE zcl_mm_sloc_ledger=>ty_s_item.

    ls_item = ltd_fixture=>item( iv_bwart = ltd_fixture=>c_bwart_999
                                 iv_shkzg = zcl_mm_sloc_ledger=>c_shkzg_h
                                 iv_menge = 10 ).
    cl_abap_unit_assert=>assert_initial(
      act = g_cut->handle_item( is_item = ls_item iv_count = abap_true ) msg = '매핑 없음 제외' ).
    cl_abap_unit_assert=>assert_equals( act = g_cut->g_unmapped exp = 1 msg = '1건 셈' ).

    g_cut->handle_item( is_item = ls_item iv_count = abap_false ).
    cl_abap_unit_assert=>assert_equals( act = g_cut->g_unmapped exp = 1 msg = '문서 조회(iv_count 공란)는 안 셈' ).

    ls_item-werks = ltd_fixture=>c_werks2.
    g_cut->handle_item( is_item = ls_item iv_count = abap_true ).
    cl_abap_unit_assert=>assert_equals( act = g_cut->g_unmapped exp = 1 msg = '다른 플랜트 품목은 안 셈' ).
  ENDMETHOD.


  METHOD item_plant_filter_cpt.
    " 이중 계산 방지 3번: UMWRK 조건으로 읽힌 다른 플랜트 품목은 상대 델타만 남음
    DATA: ls_item  TYPE zcl_mm_sloc_ledger=>ty_s_item,
          lt_delta TYPE zcl_mm_sloc_ledger=>ty_t_delta,
          ls_delta TYPE zcl_mm_sloc_ledger=>ty_s_delta.

    ls_item = ltd_fixture=>item( iv_bwart = ltd_fixture=>c_bwart_301
                                 iv_shkzg = zcl_mm_sloc_ledger=>c_shkzg_h
                                 iv_menge = 30 ).
    ls_item-werks = ltd_fixture=>c_werks2.
    ls_item-lgort = ltd_fixture=>c_lgort4.
    ls_item-umwrk = ltd_fixture=>c_werks.
    ls_item-umlgo = ltd_fixture=>c_lgort.
    ls_item-ummat = ltd_fixture=>c_matnr.
    lt_delta = g_cut->handle_item( is_item = ls_item iv_count = abap_true ).

    cl_abap_unit_assert=>assert_equals( act = lines( lt_delta ) exp = 1 msg = '상대 델타만' ).
    READ TABLE lt_delta INTO ls_delta INDEX 1.
    cl_abap_unit_assert=>assert_equals( act = ls_delta-side exp = zcl_mm_sloc_ledger=>c_side_cpt
                                        msg = 'side C' ).
    cl_abap_unit_assert=>assert_equals( act = ls_delta-werks exp = ltd_fixture=>c_werks
                                        msg = '허용 플랜트 3000' ).
    check_qty( iv_act = ls_delta-ztp_gr iv_exp = 30 iv_msg = '이전입고 +30' ).
    check_qty( iv_act = ls_delta-zclstc iv_exp = 0  iv_msg = '증감 0' ).
  ENDMETHOD.


  METHOD item_lgort_filter.
    " SO_LGORT 는 대상 저장위치(가상 포함)에 적용
    DATA: ls_sel  TYPE zcl_mm_sloc_ledger=>ty_s_sel,
          l_cut   TYPE REF TO zcl_mm_sloc_ledger,
          ls_item TYPE zcl_mm_sloc_ledger=>ty_s_item.

    ls_sel = ltd_fixture=>sel( ).
    ls_sel-lgort = VALUE #( ( sign = 'I' option = 'EQ' low = ltd_fixture=>c_lgort ) ).
    CREATE OBJECT l_cut
      EXPORTING
        is_sel = ls_sel.
    ltd_fixture=>inject( l_cut ).

    ls_item = ltd_fixture=>item( iv_bwart = ltd_fixture=>c_bwart_311
                                 iv_shkzg = zcl_mm_sloc_ledger=>c_shkzg_s
                                 iv_menge = 40 ).
    ls_item-lgort = ltd_fixture=>c_lgort2.
    ls_item-umwrk = ltd_fixture=>c_werks.
    ls_item-umlgo = ltd_fixture=>c_lgort.
    ls_item-ummat = ltd_fixture=>c_matnr.
    cl_abap_unit_assert=>assert_initial(
      act = l_cut->handle_item( is_item = ls_item iv_count = abap_true )
      msg = '4100 델타는 SO_LGORT=4000 에서 제외' ).

    ls_item-lgort = ltd_fixture=>c_lgort.
    ls_item-umlgo = ltd_fixture=>c_lgort2.
    ls_item-shkzg = zcl_mm_sloc_ledger=>c_shkzg_h.
    cl_abap_unit_assert=>assert_equals(
      act = lines( l_cut->handle_item( is_item = ls_item iv_count = abap_true ) )
      exp = 1 msg = '4000 델타는 남음' ).
  ENDMETHOD.


  METHOD sample_sloc_with_begin.
    " TS-01 + TS-03: 첨부 샘플(5/3) + 5/2 261 1,000 (기초분) + 4월말 100,000
    DATA: lt_item TYPE zcl_mm_sloc_ledger=>ty_t_item,
          ls_item TYPE zcl_mm_sloc_ledger=>ty_s_item,
          ls_hist TYPE zcl_mm_sloc_ledger=>ty_s_hist,
          ls_bal  TYPE zcl_mm_sloc_ledger=>ty_s_bal,
          l_calc  TYPE mseg-menge.

    lt_item = ltd_fixture=>sample_items( ).
    ls_item = ltd_fixture=>item( iv_bwart = ltd_fixture=>c_bwart_261
                                 iv_shkzg = zcl_mm_sloc_ledger=>c_shkzg_h
                                 iv_menge = 1000 ).
    ls_item-budat = ltd_fixture=>c_d0502.
    APPEND ls_item TO lt_item.
    post_all( lt_item ).

    ls_hist-period = '202604'.
    ls_hist-qty    = 100000.
    zcl_mm_sloc_ledger=>post_begin( EXPORTING iv_werks = ltd_fixture=>c_werks
                                              iv_matnr = ltd_fixture=>c_matnr
                                              iv_lgort = ltd_fixture=>c_lgort
                                              iv_charg = space
                                              iv_vsloc = abap_false
                                              is_hist  = ls_hist
                                    CHANGING  ct_bal   = g_cut->gt_sloc ).

    READ TABLE g_cut->gt_sloc INTO ls_bal
      WITH TABLE KEY werks = ltd_fixture=>c_werks
                     matnr = ltd_fixture=>c_matnr
                     lgort = ltd_fixture=>c_lgort
                     charg = space.
    cl_abap_unit_assert=>assert_subrc( exp = 0 act = sy-subrc msg = '3000/R1D1/4000 행' ).
    zcl_mm_sloc_ledger=>finalize( CHANGING cs_qty = ls_bal-qty ).

    check_qty( iv_act = ls_bal-beg_qty iv_exp = 99000  iv_msg = '기초 = 100,000 - 1,000(5/2)' ).
    check_qty( iv_act = ls_bal-zpp_gi  iv_exp = 25025  iv_msg = '생산출고 25,025' ).
    check_qty( iv_act = ls_bal-zclstc  iv_exp = -25025 iv_msg = '증감 -25,025' ).
    check_qty( iv_act = ls_bal-end_qty iv_exp = 73975  iv_msg = '기말 73,975' ).
    l_calc = ls_bal-beg_qty + ls_bal-gr_sum - ls_bal-gi_sum.
    check_qty( iv_act = ls_bal-end_qty iv_exp = l_calc iv_msg = 'FR-11 정합성' ).
    cl_abap_unit_assert=>assert_equals( act = lines( g_cut->gt_sloc ) exp = 1
                                        msg = '저장위치 행 1개' ).
  ENDMETHOD.


  METHOD batch_sum_equals_sloc.
    " TS-08 / FR-14: 배치 레벨 합계 = 저장위치 레벨 (intra 는 배치에서 상쇄)
    DATA: lt_item TYPE zcl_mm_sloc_ledger=>ty_t_item,
          ls_item TYPE zcl_mm_sloc_ledger=>ty_s_item,
          ls_bal  TYPE zcl_mm_sloc_ledger=>ty_s_bal,
          l_sum   TYPE mseg-menge,
          l_b1    TYPE mseg-menge,
          l_b2    TYPE mseg-menge.

    ls_item = ltd_fixture=>item( iv_bwart = ltd_fixture=>c_bwart_261
                                 iv_shkzg = zcl_mm_sloc_ledger=>c_shkzg_h
                                 iv_menge = 100 ).
    ls_item-charg = ltd_fixture=>c_charg1.
    APPEND ls_item TO lt_item.
    ls_item-menge = 50.
    ls_item-charg = ltd_fixture=>c_charg2.
    APPEND ls_item TO lt_item.
    " 같은 저장위치 배치 변경 311: B0001 -> B0002 (2품목)
    ls_item = ltd_fixture=>item( iv_bwart = ltd_fixture=>c_bwart_311
                                 iv_shkzg = zcl_mm_sloc_ledger=>c_shkzg_h
                                 iv_menge = 30 ).
    ls_item-umwrk = ltd_fixture=>c_werks.
    ls_item-umlgo = ltd_fixture=>c_lgort.
    ls_item-ummat = ltd_fixture=>c_matnr.
    ls_item-charg = ltd_fixture=>c_charg1.
    ls_item-umcha = ltd_fixture=>c_charg2.
    APPEND ls_item TO lt_item.
    ls_item-shkzg = zcl_mm_sloc_ledger=>c_shkzg_s.
    ls_item-charg = ltd_fixture=>c_charg2.
    ls_item-umcha = ltd_fixture=>c_charg1.
    APPEND ls_item TO lt_item.
    post_all( lt_item ).

    LOOP AT g_cut->gt_bal INTO ls_bal
         WHERE werks = ltd_fixture=>c_werks
           AND matnr = ltd_fixture=>c_matnr
           AND lgort = ltd_fixture=>c_lgort.
      l_sum = l_sum + ls_bal-zclstc.
      IF ls_bal-charg = ltd_fixture=>c_charg1.
        l_b1 = ls_bal-zclstc.
      ELSEIF ls_bal-charg = ltd_fixture=>c_charg2.
        l_b2 = ls_bal-zclstc.
      ENDIF.
    ENDLOOP.
    check_qty( iv_act = l_b1 iv_exp = -130 iv_msg = 'B0001 = -100 -30' ).
    check_qty( iv_act = l_b2 iv_exp = -20  iv_msg = 'B0002 = -50 +30' ).

    READ TABLE g_cut->gt_sloc INTO ls_bal
      WITH TABLE KEY werks = ltd_fixture=>c_werks
                     matnr = ltd_fixture=>c_matnr
                     lgort = ltd_fixture=>c_lgort
                     charg = space.
    check_qty( iv_act = ls_bal-zclstc iv_exp = l_sum iv_msg = '배치 합계 = 저장위치' ).
    check_qty( iv_act = ls_bal-ztp_gi iv_exp = 0     iv_msg = '메인은 intra 이전 제외' ).
  ENDMETHOD.


  METHOD batch_detail_nonbatch.
    " TS-09 / FR-14: 비배치 자재 -> 배치 공란 1행 = 메인 값 (MCHB 조회 없음)
    DATA: ls_bal   TYPE zcl_mm_sloc_ledger=>ty_s_bal,
          ls_marc  TYPE zcl_mm_sloc_ledger=>ty_s_marc,
          ls_mara  TYPE zcl_mm_sloc_ledger=>ty_s_mara,
          lt_key   TYPE zcl_mm_sloc_ledger=>ty_t_key,
          ls_key   TYPE zcl_mm_sloc_ledger=>ty_s_key,
          lt_batch TYPE zcl_mm_sloc_ledger=>ty_t_batch,
          ls_batch TYPE zcl_mm_sloc_ledger=>ty_s_batch,
          lt_diff  TYPE zcl_mm_sloc_ledger=>ty_t_key,
          l_diff   TYPE mseg-menge.

    ls_bal-werks   = ltd_fixture=>c_werks.
    ls_bal-matnr   = ltd_fixture=>c_matnr.
    ls_bal-lgort   = ltd_fixture=>c_lgort.
    ls_bal-beg_qty = 100.
    ls_bal-zpp_gi  = 30.
    ls_bal-gi_sum  = 30.
    ls_bal-zclstc  = -30.
    ls_bal-end_qty = 70.
    INSERT ls_bal INTO TABLE g_cut->gt_sloc.
    ls_marc-matnr = ltd_fixture=>c_matnr.
    ls_marc-werks = ltd_fixture=>c_werks.
    INSERT ls_marc INTO TABLE g_cut->gt_marc.
    ls_mara-matnr = ltd_fixture=>c_matnr.
    ls_mara-meins = ltd_fixture=>c_meins.
    INSERT ls_mara INTO TABLE g_cut->gt_mara.
    g_cut->g_loaded = abap_true.

    MOVE-CORRESPONDING ls_bal TO ls_key.
    APPEND ls_key TO lt_key.
    g_cut->get_batch( EXPORTING it_key      = lt_key
                      IMPORTING et_batch    = lt_batch
                                et_diff_key = lt_diff
                                ev_diff_qty = l_diff ).

    cl_abap_unit_assert=>assert_equals( act = lines( lt_batch ) exp = 1 msg = '1행' ).
    READ TABLE lt_batch INTO ls_batch INDEX 1.
    cl_abap_unit_assert=>assert_initial( act = ls_batch-charg msg = '배치 공란' ).
    check_qty( iv_act = ls_batch-end_qty iv_exp = 70 iv_msg = '기말 = 메인' ).
    check_qty( iv_act = ls_batch-zpp_gi  iv_exp = 30 iv_msg = '생산출고 = 메인' ).
    cl_abap_unit_assert=>assert_equals( act = ls_batch-meins exp = ltd_fixture=>c_meins msg = '단위' ).
    cl_abap_unit_assert=>assert_initial( act = lt_diff msg = '차이 없음' ).
  ENDMETHOD.


  METHOD batch_detail_virtual.
    " 가상 행(TRNS)은 배치관리 자재라도 배치 공란 1행 (MCHB 조회 없음)
    DATA: ls_bal   TYPE zcl_mm_sloc_ledger=>ty_s_bal,
          ls_marc  TYPE zcl_mm_sloc_ledger=>ty_s_marc,
          lt_key   TYPE zcl_mm_sloc_ledger=>ty_t_key,
          ls_key   TYPE zcl_mm_sloc_ledger=>ty_s_key,
          lt_batch TYPE zcl_mm_sloc_ledger=>ty_t_batch,
          ls_batch TYPE zcl_mm_sloc_ledger=>ty_s_batch,
          lt_diff  TYPE zcl_mm_sloc_ledger=>ty_t_key,
          l_diff   TYPE mseg-menge.

    ls_bal-werks   = ltd_fixture=>c_werks.
    ls_bal-matnr   = ltd_fixture=>c_matnr.
    ls_bal-lgort   = zcl_mm_sloc_ledger=>c_vsloc_trns.
    ls_bal-vsloc   = abap_true.
    ls_bal-zclstc  = 60.
    ls_bal-end_qty = 60.
    INSERT ls_bal INTO TABLE g_cut->gt_sloc.
    ls_marc-matnr = ltd_fixture=>c_matnr.
    ls_marc-werks = ltd_fixture=>c_werks.
    ls_marc-xchpf = abap_true.
    INSERT ls_marc INTO TABLE g_cut->gt_marc.
    g_cut->g_loaded = abap_true.

    MOVE-CORRESPONDING ls_bal TO ls_key.
    APPEND ls_key TO lt_key.
    g_cut->get_batch( EXPORTING it_key      = lt_key
                      IMPORTING et_batch    = lt_batch
                                et_diff_key = lt_diff
                                ev_diff_qty = l_diff ).

    cl_abap_unit_assert=>assert_equals( act = lines( lt_batch ) exp = 1 msg = '가상 행 1행' ).
    READ TABLE lt_batch INTO ls_batch INDEX 1.
    cl_abap_unit_assert=>assert_initial( act = ls_batch-charg msg = '배치 공란' ).
    check_qty( iv_act = ls_batch-end_qty iv_exp = 60 iv_msg = 'TRNS 기말' ).
  ENDMETHOD.


  METHOD recon_guard_month_end.
    " TS-26 / 설계 S13: 종료일이 월말도 오늘 이후도 아니면 DB 조회 없이 ev_ok 공란
    DATA: ls_sel   TYPE zcl_mm_sloc_ledger=>ty_s_sel,
          l_cut    TYPE REF TO zcl_mm_sloc_ledger,
          lt_key   TYPE zcl_mm_sloc_ledger=>ty_t_key,
          lt_recon TYPE zcl_mm_sloc_ledger=>ty_t_recon,
          l_ok     TYPE abap_bool.

    ls_sel = ltd_fixture=>sel( ).
    ls_sel-budat_from = ltd_fixture=>c_d0115.
    ls_sel-budat_to   = ltd_fixture=>c_d0115.
    CREATE OBJECT l_cut
      EXPORTING
        is_sel = ls_sel.
    l_cut->g_loaded = abap_true.

    l_cut->get_recon( EXPORTING it_key   = lt_key
                      IMPORTING et_recon = lt_recon
                                ev_ok    = l_ok ).
    cl_abap_unit_assert=>assert_equals( act = l_ok exp = abap_false msg = '2020-01-15 -> 대사 불가' ).
    cl_abap_unit_assert=>assert_initial( act = lt_recon msg = '결과 없음' ).
  ENDMETHOD.

ENDCLASS.
