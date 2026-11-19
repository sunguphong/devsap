*"* use this source file for your ABAP unit test classes
*----------------------------------------------------------------------*
* ZCL_MM_STKDAY_CALC 로컬 테스트 클래스 (Local Test Classes include)
* 요청 ID : 20261022-9149a8 / 04_test.md 5장 (TP-U01~U15 + END_AT_DATE,
*           SUBTRACT_MINUTES, 분류 규칙 레인지)
* 방식    : DB 접근 없음. 정적 메서드에 테스트 데이터를 직접 주입한다
* 문법    : ABAP 7.40 (VALUE/CONV, 인라인 선언·FOR·REDUCE·xsdbool 미사용)
* 명명    : 변수·상수·레인지는 핸드북 2장(G_/L_/GT_/LT_/LS_/C_/R_).
*           테스트 클래스(LTCL_)·메서드명은 핸드북 규칙 없음 - SAP 관례 적용
*----------------------------------------------------------------------*

*----------------------------------------------------------------------*
* 공통 상수 (추상 기반 클래스)
*----------------------------------------------------------------------*
CLASS ltcl_base DEFINITION ABSTRACT FOR TESTING
  RISK LEVEL HARMLESS
  DURATION SHORT.

  PROTECTED SECTION.
    CONSTANTS:
      c_werks  TYPE werks_d VALUE 'P001',
      c_werks2 TYPE werks_d VALUE 'P002',
      c_sl01   TYPE lgort_d VALUE 'SL01',
      c_sl02   TYPE lgort_d VALUE 'SL02',
      c_mat    TYPE matnr   VALUE 'MAT-A',
      c_mat2   TYPE matnr   VALUE 'MAT-B',
      c_mat3   TYPE matnr   VALUE 'MAT-C',
      c_b1     TYPE charg_d VALUE 'BATCH1',
      c_b2     TYPE charg_d VALUE 'BATCH2',
      c_b3     TYPE charg_d VALUE 'BATCH3',
      c_loc    TYPE zestcat VALUE 'L',
      c_trn    TYPE zestcat VALUE 'T',
      c_s      TYPE c LENGTH 1 VALUE 'S',
      c_h      TYPE c LENGTH 1 VALUE 'H',
      c_kg     TYPE meins   VALUE 'KG',
      c_ea     TYPE meins   VALUE 'EA',
      c_d0925  TYPE budat   VALUE '20260925',
      c_d0926  TYPE budat   VALUE '20260926',
      c_d1001  TYPE budat   VALUE '20261001',
      c_d1003  TYPE budat   VALUE '20261003',
      c_d1005  TYPE budat   VALUE '20261005',
      c_d1010  TYPE budat   VALUE '20261010',
      c_d1015  TYPE budat   VALUE '20261015',
      c_d1018  TYPE budat   VALUE '20261018',
      c_d1020  TYPE budat   VALUE '20261020',
      c_d1021  TYPE budat   VALUE '20261021',
      c_d1022  TYPE budat   VALUE '20261022',
      c_d1023  TYPE budat   VALUE '20261023',
      c_d1024  TYPE budat   VALUE '20261024',
      c_today  TYPE d       VALUE '20261023'.
ENDCLASS.

CLASS ltcl_base IMPLEMENTATION.
ENDCLASS.

*----------------------------------------------------------------------*
* CLASSIFY_MOVE (TP-U01~U05, 팀장 확인: 취소 순액, K/E 별도·Q/W 제외,
* 이전중/운송중) + CLASS_CONSTRUCTOR 분류 레인지
*----------------------------------------------------------------------*
CLASS ltcl_classify DEFINITION INHERITING FROM ltcl_base FINAL FOR TESTING
  RISK LEVEL HARMLESS
  DURATION SHORT.

  PRIVATE SECTION.
    METHODS:
      classify
        IMPORTING
          is_move   TYPE zcl_mm_stkday_calc=>ty_move
          iv_cancel TYPE xfeld DEFAULT abap_false
          iv_batch  TYPE xfeld DEFAULT abap_false
          iv_qtyupd TYPE xfeld DEFAULT abap_true
        CHANGING
          ct_delta  TYPE zcl_mm_stkday_calc=>tt_delta,
      gr_101_normal_receipt      FOR TESTING,
      cancel_102_net_receipt     FOR TESTING,
      cancel_262_net_issue       FOR TESTING,
      special_k_e_separate       FOR TESTING,
      special_q_w_o_excluded     FOR TESTING,
      typechange_321_excluded    FOR TESTING,
      no_qty_update_excluded     FOR TESTING,
      blank_lgort_excluded       FOR TESTING,
      batch_flag_sets_charg      FOR TESTING,
      sloc_313_xauto_in_transfer FOR TESTING,
      sloc_315_resolves_transfer FOR TESTING,
      sloc_314_316_cancel        FOR TESTING,
      plant_303_305_transit      FOR TESTING,
      sto_351_352_recv_plant     FOR TESTING,
      sto_101_receipt_transit    FOR TESTING,
      collect_sums_same_key      FOR TESTING,
      rule_ranges_semantics      FOR TESTING.
ENDCLASS.

CLASS ltcl_classify IMPLEMENTATION.

  METHOD classify.
    zcl_mm_stkday_calc=>classify_move(
      EXPORTING
        is_move       = is_move
        iv_cancel     = iv_cancel
        iv_batch      = iv_batch
        iv_qty_update = iv_qtyupd
      CHANGING
        ct_delta      = ct_delta ).
  ENDMETHOD.


  METHOD gr_101_normal_receipt.
    " TP-U01: 101 S 100 -> 일반 입고 100
    DATA: lt_delta TYPE zcl_mm_stkday_calc=>tt_delta,
          lt_exp   TYPE zcl_mm_stkday_calc=>tt_delta.

    classify( EXPORTING is_move = VALUE #( werks = c_werks lgort = c_sl01 matnr = c_mat
                                           budat = c_d1022 bwart = '101' shkzg = c_s
                                           menge = 100 )
              CHANGING  ct_delta = lt_delta ).

    lt_exp = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc
                        budat = c_d1022 gr_qty = 100 ) ).
    cl_abap_unit_assert=>assert_equals( act = lt_delta exp = lt_exp
                                        msg = '101 정상 입고는 입고 +수량' ).
  ENDMETHOD.


  METHOD cancel_102_net_receipt.
    " 팀장 확인: 102(취소)는 출고가 아니라 입고에서 마이너스. 101 100 + 102 20 = 입고 80, 출고 0
    DATA: lt_delta TYPE zcl_mm_stkday_calc=>tt_delta,
          lt_one   TYPE zcl_mm_stkday_calc=>tt_delta,
          lt_exp   TYPE zcl_mm_stkday_calc=>tt_delta.

    classify( EXPORTING is_move = VALUE #( werks = c_werks lgort = c_sl01 matnr = c_mat
                                           budat = c_d1022 bwart = '101' shkzg = c_s
                                           menge = 100 )
              CHANGING  ct_delta = lt_delta ).
    classify( EXPORTING is_move   = VALUE #( werks = c_werks lgort = c_sl01 matnr = c_mat
                                             budat = c_d1022 bwart = '102' shkzg = c_h
                                             menge = 20 )
                        iv_cancel = abap_true
              CHANGING  ct_delta  = lt_delta ).

    lt_exp = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc
                        budat = c_d1022 gr_qty = 80 gi_qty = 0 ) ).
    cl_abap_unit_assert=>assert_equals( act = lt_delta exp = lt_exp
                                        msg = '101 100 + 102 20 -> 입고 80, 출고 0' ).

    " 102 단독(다른 날 취소): 입고 -20
    classify( EXPORTING is_move   = VALUE #( werks = c_werks lgort = c_sl01 matnr = c_mat
                                             budat = c_d1023 bwart = '102' shkzg = c_h
                                             menge = 20 )
                        iv_cancel = abap_true
              CHANGING  ct_delta  = lt_one ).
    lt_exp = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc
                        budat = c_d1023 gr_qty = -20 ) ).
    cl_abap_unit_assert=>assert_equals( act = lt_one exp = lt_exp
                                        msg = '102 단독은 입고 -20(출고 아님)' ).
  ENDMETHOD.


  METHOD cancel_262_net_issue.
    " 팀장 확인: 262(취소)는 입고가 아니라 출고에서 마이너스. 261 50 + 262 10 = 출고 40
    DATA: lt_delta TYPE zcl_mm_stkday_calc=>tt_delta,
          lt_exp   TYPE zcl_mm_stkday_calc=>tt_delta.

    classify( EXPORTING is_move = VALUE #( werks = c_werks lgort = c_sl01 matnr = c_mat
                                           budat = c_d1022 bwart = '261' shkzg = c_h
                                           menge = 50 )
              CHANGING  ct_delta = lt_delta ).
    classify( EXPORTING is_move   = VALUE #( werks = c_werks lgort = c_sl01 matnr = c_mat
                                             budat = c_d1022 bwart = '262' shkzg = c_s
                                             menge = 10 )
                        iv_cancel = abap_true
              CHANGING  ct_delta  = lt_delta ).

    lt_exp = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc
                        budat = c_d1022 gr_qty = 0 gi_qty = 40 ) ).
    cl_abap_unit_assert=>assert_equals( act = lt_delta exp = lt_exp
                                        msg = '261 50 + 262 10 -> 출고 40, 입고 0' ).
  ENDMETHOD.


  METHOD special_k_e_separate.
    " TP-U05: K -> 위탁 측정값, E -> 오더 측정값. 일반 입출고에는 들어가지 않음
    DATA: lt_delta TYPE zcl_mm_stkday_calc=>tt_delta,
          lt_exp   TYPE zcl_mm_stkday_calc=>tt_delta.

    classify( EXPORTING is_move = VALUE #( werks = c_werks lgort = c_sl01 matnr = c_mat
                                           budat = c_d1022 bwart = '101' shkzg = c_s
                                           sobkz = 'K' menge = 30 )
              CHANGING  ct_delta = lt_delta ).
    classify( EXPORTING is_move   = VALUE #( werks = c_werks lgort = c_sl01 matnr = c_mat
                                             budat = c_d1022 bwart = '102' shkzg = c_h
                                             sobkz = 'K' menge = 10 )
                        iv_cancel = abap_true
              CHANGING  ct_delta  = lt_delta ).
    classify( EXPORTING is_move = VALUE #( werks = c_werks lgort = c_sl01 matnr = c_mat
                                           budat = c_d1022 bwart = '231' shkzg = c_h
                                           sobkz = 'E' menge = 5 )
              CHANGING  ct_delta = lt_delta ).

    lt_exp = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc
                        budat = c_d1022 k_gr = 20 e_gi = 5 ) ).
    cl_abap_unit_assert=>assert_equals( act = lt_delta exp = lt_exp
                                        msg = 'K 입고 30 - 취소 10 = 20, E 출고 5, 일반 0' ).
  ENDMETHOD.


  METHOD special_q_w_o_excluded.
    " 팀장 확인: Q·W 제외(그 밖의 O·V도 제외)
    DATA lt_delta TYPE zcl_mm_stkday_calc=>tt_delta.

    classify( EXPORTING is_move = VALUE #( werks = c_werks lgort = c_sl01 matnr = c_mat
                                           budat = c_d1022 bwart = '101' shkzg = c_s
                                           sobkz = 'Q' menge = 10 )
              CHANGING  ct_delta = lt_delta ).
    classify( EXPORTING is_move = VALUE #( werks = c_werks lgort = c_sl01 matnr = c_mat
                                           budat = c_d1022 bwart = '631' shkzg = c_h
                                           sobkz = 'W' menge = 10 )
              CHANGING  ct_delta = lt_delta ).
    classify( EXPORTING is_move = VALUE #( werks = c_werks lgort = c_sl01 matnr = c_mat
                                           budat = c_d1022 bwart = '541' shkzg = c_s
                                           sobkz = 'O' menge = 10 )
              CHANGING  ct_delta = lt_delta ).
    classify( EXPORTING is_move = VALUE #( werks = c_werks lgort = c_sl01 matnr = c_mat
                                           budat = c_d1022 bwart = '101' shkzg = c_s
                                           sobkz = 'V' menge = 10 )
              CHANGING  ct_delta = lt_delta ).

    cl_abap_unit_assert=>assert_initial( act = lt_delta
                                         msg = 'SOBKZ Q/W/O/V 이동은 결과 없음' ).
  ENDMETHOD.


  METHOD typechange_321_excluded.
    " TP-U05 / Q6: 재고유형 간 이동(321/343)은 입출고에서 제외
    DATA lt_delta TYPE zcl_mm_stkday_calc=>tt_delta.

    classify( EXPORTING is_move = VALUE #( werks = c_werks lgort = c_sl01 matnr = c_mat
                                           budat = c_d1022 bwart = '321' shkzg = c_s
                                           menge = 10 )
              CHANGING  ct_delta = lt_delta ).
    classify( EXPORTING is_move = VALUE #( werks = c_werks lgort = c_sl01 matnr = c_mat
                                           budat = c_d1022 bwart = '321' shkzg = c_h
                                           menge = 10 )
              CHANGING  ct_delta = lt_delta ).
    classify( EXPORTING is_move = VALUE #( werks = c_werks lgort = c_sl01 matnr = c_mat
                                           budat = c_d1022 bwart = '343' shkzg = c_s
                                           menge = 3 )
              CHANGING  ct_delta = lt_delta ).

    cl_abap_unit_assert=>assert_initial( act = lt_delta
                                         msg = '재고유형 간 이동은 결과 없음' ).
  ENDMETHOD.


  METHOD no_qty_update_excluded.
    " C2: 수량 갱신이 없는 자재유형은 버림
    DATA lt_delta TYPE zcl_mm_stkday_calc=>tt_delta.

    classify( EXPORTING is_move   = VALUE #( werks = c_werks lgort = c_sl01 matnr = c_mat
                                             budat = c_d1022 bwart = '101' shkzg = c_s
                                             menge = 10 )
                        iv_qtyupd = abap_false
              CHANGING  ct_delta  = lt_delta ).

    cl_abap_unit_assert=>assert_initial( act = lt_delta
                                         msg = '수량 갱신 없음(MENGU 공란)은 결과 없음' ).
  ENDMETHOD.


  METHOD blank_lgort_excluded.
    " TP-U05: 저장위치 공란 일반 행(계정지정 직접소비 등)은 버림
    DATA lt_delta TYPE zcl_mm_stkday_calc=>tt_delta.

    classify( EXPORTING is_move = VALUE #( werks = c_werks matnr = c_mat
                                           budat = c_d1022 bwart = '101' shkzg = c_s
                                           menge = 10 )
              CHANGING  ct_delta = lt_delta ).

    cl_abap_unit_assert=>assert_initial( act = lt_delta
                                         msg = '저장위치 공란 행은 결과 없음' ).
  ENDMETHOD.


  METHOD batch_flag_sets_charg.
    " C8 / FR-14: 배치관리 자재가 아니면 배치 공란, 배치관리면 배치 유지
    DATA: lt_nobat TYPE zcl_mm_stkday_calc=>tt_delta,
          lt_bat   TYPE zcl_mm_stkday_calc=>tt_delta,
          lt_exp   TYPE zcl_mm_stkday_calc=>tt_delta,
          ls_move  TYPE zcl_mm_stkday_calc=>ty_move.

    ls_move = VALUE #( werks = c_werks lgort = c_sl01 matnr = c_mat charg = c_b1
                       budat = c_d1022 bwart = '101' shkzg = c_s menge = 7 ).

    classify( EXPORTING is_move = ls_move iv_batch = abap_false
              CHANGING  ct_delta = lt_nobat ).
    lt_exp = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc
                        budat = c_d1022 gr_qty = 7 ) ).
    cl_abap_unit_assert=>assert_equals( act = lt_nobat exp = lt_exp
                                        msg = '비배치 자재는 배치 공란' ).

    classify( EXPORTING is_move = ls_move iv_batch = abap_true
              CHANGING  ct_delta = lt_bat ).
    lt_exp = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat charg = c_b1
                        stkcat = c_loc budat = c_d1022 gr_qty = 7 ) ).
    cl_abap_unit_assert=>assert_equals( act = lt_bat exp = lt_exp
                                        msg = '배치 자재는 배치 유지' ).
  ENDMETHOD.


  METHOD sloc_313_xauto_in_transfer.
    " TP-U02 / 팀장 확인(이전중): 313 비XAUTO H -> 보내는 저장위치 출고,
    " 313 XAUTO S(BUSTM MA05) -> 일반 0, 받는 저장위치 L 키 이전중 +
    DATA: lt_delta TYPE zcl_mm_stkday_calc=>tt_delta,
          lt_exp   TYPE zcl_mm_stkday_calc=>tt_delta.

    classify( EXPORTING is_move = VALUE #( werks = c_werks lgort = c_sl01 matnr = c_mat
                                           budat = c_d1022 bwart = '313' shkzg = c_h
                                           menge = 100 )
              CHANGING  ct_delta = lt_delta ).
    classify( EXPORTING is_move = VALUE #( werks = c_werks lgort = c_sl02 matnr = c_mat
                                           budat = c_d1022 bwart = '313' shkzg = c_s
                                           xauto = abap_true bustm = 'MA05' menge = 100 )
              CHANGING  ct_delta = lt_delta ).

    lt_exp = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc
                        budat = c_d1022 gi_qty = 100 )
                      ( werks = c_werks lgort = c_sl02 matnr = c_mat stkcat = c_loc
                        budat = c_d1022 trf_qty = 100 ) ).
    cl_abap_unit_assert=>assert_equals( act = lt_delta exp = lt_exp
                                        msg = '313: 보내는 쪽 출고, 받는 쪽 이전중 +' ).
  ENDMETHOD.


  METHOD sloc_315_resolves_transfer.
    " TP-U02: 313 후 315 S -> 받는 저장위치 일반 입고 +, 이전중 -(해소)
    DATA: lt_delta TYPE zcl_mm_stkday_calc=>tt_delta,
          lt_exp   TYPE zcl_mm_stkday_calc=>tt_delta.

    classify( EXPORTING is_move = VALUE #( werks = c_werks lgort = c_sl01 matnr = c_mat
                                           budat = c_d1022 bwart = '313' shkzg = c_h
                                           menge = 100 )
              CHANGING  ct_delta = lt_delta ).
    classify( EXPORTING is_move = VALUE #( werks = c_werks lgort = c_sl02 matnr = c_mat
                                           budat = c_d1022 bwart = '313' shkzg = c_s
                                           xauto = abap_true bustm = 'MA05' menge = 100 )
              CHANGING  ct_delta = lt_delta ).
    classify( EXPORTING is_move = VALUE #( werks = c_werks lgort = c_sl02 matnr = c_mat
                                           budat = c_d1022 bwart = '315' shkzg = c_s
                                           menge = 100 )
              CHANGING  ct_delta = lt_delta ).

    lt_exp = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc
                        budat = c_d1022 gi_qty = 100 )
                      ( werks = c_werks lgort = c_sl02 matnr = c_mat stkcat = c_loc
                        budat = c_d1022 gr_qty = 100 trf_qty = 0 ) ).
    cl_abap_unit_assert=>assert_equals( act = lt_delta exp = lt_exp
                                        msg = '315 입고로 이전중 해소(같은 날 순증감 0)' ).
  ENDMETHOD.


  METHOD sloc_314_316_cancel.
    " TP-U02: 314(313 취소) / 316(315 취소)은 반대 부호
    DATA: lt_314 TYPE zcl_mm_stkday_calc=>tt_delta,
          lt_316 TYPE zcl_mm_stkday_calc=>tt_delta,
          lt_exp TYPE zcl_mm_stkday_calc=>tt_delta.

    classify( EXPORTING is_move   = VALUE #( werks = c_werks lgort = c_sl01 matnr = c_mat
                                             budat = c_d1022 bwart = '314' shkzg = c_s
                                             menge = 100 )
                        iv_cancel = abap_true
              CHANGING  ct_delta  = lt_314 ).
    classify( EXPORTING is_move   = VALUE #( werks = c_werks lgort = c_sl02 matnr = c_mat
                                             budat = c_d1022 bwart = '314' shkzg = c_h
                                             xauto = abap_true bustm = 'MA05' menge = 100 )
                        iv_cancel = abap_true
              CHANGING  ct_delta  = lt_314 ).
    lt_exp = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc
                        budat = c_d1022 gi_qty = -100 )
                      ( werks = c_werks lgort = c_sl02 matnr = c_mat stkcat = c_loc
                        budat = c_d1022 trf_qty = -100 ) ).
    cl_abap_unit_assert=>assert_equals( act = lt_314 exp = lt_exp
                                        msg = '314: 보내는 쪽 출고 -, 받는 쪽 이전중 -' ).

    classify( EXPORTING is_move   = VALUE #( werks = c_werks lgort = c_sl02 matnr = c_mat
                                             budat = c_d1022 bwart = '316' shkzg = c_h
                                             menge = 100 )
                        iv_cancel = abap_true
              CHANGING  ct_delta  = lt_316 ).
    lt_exp = VALUE #( ( werks = c_werks lgort = c_sl02 matnr = c_mat stkcat = c_loc
                        budat = c_d1022 gr_qty = -100 trf_qty = 100 ) ).
    cl_abap_unit_assert=>assert_equals( act = lt_316 exp = lt_exp
                                        msg = '316: 받는 쪽 입고 -, 이전중 +' ).
  ENDMETHOD.


  METHOD plant_303_305_transit.
    " TP-U03 / 팀장 확인(운송중 행): 303 XAUTO(MA02) -> T 키 이전중 +,
    " 305 -> 일반 입고 + T 키 이전중 -. BUSTM 공란 + 303 XAUTO도 T 키
    DATA: lt_delta TYPE zcl_mm_stkday_calc=>tt_delta,
          lt_blank TYPE zcl_mm_stkday_calc=>tt_delta,
          lt_exp   TYPE zcl_mm_stkday_calc=>tt_delta.

    " 보내는 플랜트 P002 출고
    classify( EXPORTING is_move = VALUE #( werks = c_werks2 lgort = c_sl01 matnr = c_mat
                                           budat = c_d1021 bwart = '303' shkzg = c_h
                                           menge = 50 )
              CHANGING  ct_delta = lt_delta ).
    " 받는 플랜트 P001 XAUTO 행
    classify( EXPORTING is_move = VALUE #( werks = c_werks lgort = c_sl01 matnr = c_mat
                                           budat = c_d1021 bwart = '303' shkzg = c_s
                                           xauto = abap_true bustm = 'MA02' menge = 50 )
              CHANGING  ct_delta = lt_delta ).
    " 받는 플랜트 305 입고
    classify( EXPORTING is_move = VALUE #( werks = c_werks lgort = c_sl01 matnr = c_mat
                                           budat = c_d1022 bwart = '305' shkzg = c_s
                                           menge = 50 )
              CHANGING  ct_delta = lt_delta ).

    lt_exp = VALUE #( ( werks = c_werks matnr = c_mat stkcat = c_trn
                        budat = c_d1021 trf_qty = 50 )
                      ( werks = c_werks matnr = c_mat stkcat = c_trn
                        budat = c_d1022 trf_qty = -50 )
                      ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc
                        budat = c_d1022 gr_qty = 50 )
                      ( werks = c_werks2 lgort = c_sl01 matnr = c_mat stkcat = c_loc
                        budat = c_d1021 gi_qty = 50 ) ).
    cl_abap_unit_assert=>assert_equals( act = lt_delta exp = lt_exp
                                        msg = '303/305: 보내는 쪽 출고, 받는 플랜트 운송중 +/-' ).

    classify( EXPORTING is_move = VALUE #( werks = c_werks lgort = c_sl01 matnr = c_mat
                                           budat = c_d1021 bwart = '303' shkzg = c_s
                                           xauto = abap_true menge = 50 )
              CHANGING  ct_delta = lt_blank ).
    lt_exp = VALUE #( ( werks = c_werks matnr = c_mat stkcat = c_trn
                        budat = c_d1021 trf_qty = 50 ) ).
    cl_abap_unit_assert=>assert_equals( act = lt_blank exp = lt_exp
                                        msg = 'BUSTM 공란 + 303 XAUTO도 운송중(T) 키' ).
  ENDMETHOD.


  METHOD sto_351_352_recv_plant.
    " TP-U04: 351 H(받는 플랜트 P001) -> 자기 L 출고 + P001 T 키 이전중 +. 352는 반대 부호
    DATA: lt_delta TYPE zcl_mm_stkday_calc=>tt_delta,
          lt_exp   TYPE zcl_mm_stkday_calc=>tt_delta.

    classify( EXPORTING is_move = VALUE #( werks = c_werks2 lgort = c_sl01 matnr = c_mat
                                           budat = c_d1021 bwart = '351' shkzg = c_h
                                           recv_werks = c_werks menge = 40 )
              CHANGING  ct_delta = lt_delta ).
    classify( EXPORTING is_move   = VALUE #( werks = c_werks2 lgort = c_sl01 matnr = c_mat
                                             budat = c_d1022 bwart = '352' shkzg = c_s
                                             recv_werks = c_werks menge = 15 )
                        iv_cancel = abap_true
              CHANGING  ct_delta  = lt_delta ).

    lt_exp = VALUE #( ( werks = c_werks matnr = c_mat stkcat = c_trn
                        budat = c_d1021 trf_qty = 40 )
                      ( werks = c_werks matnr = c_mat stkcat = c_trn
                        budat = c_d1022 trf_qty = -15 )
                      ( werks = c_werks2 lgort = c_sl01 matnr = c_mat stkcat = c_loc
                        budat = c_d1021 gi_qty = 40 )
                      ( werks = c_werks2 lgort = c_sl01 matnr = c_mat stkcat = c_loc
                        budat = c_d1022 gi_qty = -15 ) ).
    cl_abap_unit_assert=>assert_equals( act = lt_delta exp = lt_exp
                                        msg = 'STO 351/352: 받는 플랜트 운송중, 공급 플랜트 출고' ).
  ENDMETHOD.


  METHOD sto_101_receipt_transit.
    " TP-U04: STO 입고 101(EKKO-RESWK 있음) -> 일반 입고 + 자기 T 키 이전중 -.
    " 일반 구매 101(STO 아님) -> 입고만
    DATA: lt_delta TYPE zcl_mm_stkday_calc=>tt_delta,
          lt_exp   TYPE zcl_mm_stkday_calc=>tt_delta.

    classify( EXPORTING is_move = VALUE #( werks = c_werks lgort = c_sl01 matnr = c_mat
                                           budat = c_d1023 bwart = '101' shkzg = c_s
                                           sto_rcpt = abap_true menge = 40 )
              CHANGING  ct_delta = lt_delta ).
    classify( EXPORTING is_move = VALUE #( werks = c_werks lgort = c_sl02 matnr = c_mat
                                           budat = c_d1023 bwart = '101' shkzg = c_s
                                           menge = 10 )
              CHANGING  ct_delta = lt_delta ).

    lt_exp = VALUE #( ( werks = c_werks matnr = c_mat stkcat = c_trn
                        budat = c_d1023 trf_qty = -40 )
                      ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc
                        budat = c_d1023 gr_qty = 40 )
                      ( werks = c_werks lgort = c_sl02 matnr = c_mat stkcat = c_loc
                        budat = c_d1023 gr_qty = 10 ) ).
    cl_abap_unit_assert=>assert_equals( act = lt_delta exp = lt_exp
                                        msg = 'STO 입고만 운송중 차감' ).
  ENDMETHOD.


  METHOD collect_sums_same_key.
    " 03 T-2: 같은 키·일자 입력은 COLLECT로 합산
    DATA: lt_delta TYPE zcl_mm_stkday_calc=>tt_delta,
          lt_exp   TYPE zcl_mm_stkday_calc=>tt_delta.

    classify( EXPORTING is_move = VALUE #( werks = c_werks lgort = c_sl01 matnr = c_mat
                                           budat = c_d1022 bwart = '101' shkzg = c_s
                                           menge = 10 )
              CHANGING  ct_delta = lt_delta ).
    classify( EXPORTING is_move = VALUE #( werks = c_werks lgort = c_sl01 matnr = c_mat
                                           budat = c_d1022 bwart = '101' shkzg = c_s
                                           menge = 15 )
              CHANGING  ct_delta = lt_delta ).
    classify( EXPORTING is_move = VALUE #( werks = c_werks lgort = c_sl01 matnr = c_mat
                                           budat = c_d1022 bwart = '201' shkzg = c_h
                                           menge = 3 )
              CHANGING  ct_delta = lt_delta ).

    lt_exp = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc
                        budat = c_d1022 gr_qty = 25 gi_qty = 3 ) ).
    cl_abap_unit_assert=>assert_equals( act = lt_delta exp = lt_exp
                                        msg = '같은 키·일자는 1행으로 합산' ).
  ENDMETHOD.


  METHOD rule_ranges_semantics.
    " 03 T-1: CLASS_CONSTRUCTOR 분류 레인지를 의미('값 IN 레인지')로 확인
    IF NOT '313' IN zcl_mm_stkday_calc=>r_trflb.
      cl_abap_unit_assert=>fail( msg = '313은 저장위치 이전중(L) BWART' ).
    ENDIF.
    IF '303' IN zcl_mm_stkday_calc=>r_trflb.
      cl_abap_unit_assert=>fail( msg = '303은 L 레인지에 없어야 함' ).
    ENDIF.
    IF NOT '304' IN zcl_mm_stkday_calc=>r_trftb.
      cl_abap_unit_assert=>fail( msg = '304는 플랜트 이전중(T) BWART' ).
    ENDIF.
    IF NOT 'MA05' IN zcl_mm_stkday_calc=>r_trfbs.
      cl_abap_unit_assert=>fail( msg = 'MA05는 이전중 BUSTM' ).
    ENDIF.
    IF NOT '316' IN zcl_mm_stkday_calc=>r_rsolb.
      cl_abap_unit_assert=>fail( msg = '316은 저장위치 이전중 해소 BWART' ).
    ENDIF.
    IF NOT '306' IN zcl_mm_stkday_calc=>r_rsotb.
      cl_abap_unit_assert=>fail( msg = '306은 플랜트 이전중 해소 BWART' ).
    ENDIF.
    IF NOT '643' IN zcl_mm_stkday_calc=>r_stois.
      cl_abap_unit_assert=>fail( msg = '643은 STO 출고 BWART' ).
    ENDIF.
    IF NOT '102' IN zcl_mm_stkday_calc=>r_storc.
      cl_abap_unit_assert=>fail( msg = '102는 STO 입고(취소) BWART' ).
    ENDIF.
    IF NOT '350' IN zcl_mm_stkday_calc=>r_typch.
      cl_abap_unit_assert=>fail( msg = '350은 재고유형 간 이동' ).
    ENDIF.
    IF '311' IN zcl_mm_stkday_calc=>r_typch.
      cl_abap_unit_assert=>fail( msg = '311(저장위치 간 이전)은 재고유형 간 이동이 아님' ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* ROLL_BACK / TO_MATERIAL_LEVEL / END_AT_DATE (TP-U06~U08, 03 T-1·T-3)
*----------------------------------------------------------------------*
CLASS ltcl_roll_back DEFINITION INHERITING FROM ltcl_base FINAL FOR TESTING
  RISK LEVEL HARMLESS
  DURATION SHORT.

  PRIVATE SECTION.
    METHODS:
      design_example_one_day     FOR TESTING,
      multi_day_back_calc        FOR TESTING,
      month_snapshot_row         FOR TESTING,
      snapshot_zero_no_row       FOR TESTING,
      snapshot_with_move_one_row FOR TESTING,
      stock_only_no_rows         FOR TESTING,
      invalid_range_empty        FOR TESTING,
      special_measures_rollback  FOR TESTING,
      material_level_equals_sum  FOR TESTING,
      end_at_date_subtracts      FOR TESTING.
ENDCLASS.

CLASS ltcl_roll_back IMPLEMENTATION.

  METHOD design_example_one_day.
    " TP-U06(설계 4.2 예시): 현재고 150, 10/23 입고 30(미래), 10/22 101 50·261 20
    " -> 10/22 행 기초 90 / 입고 50 / 출고 20 / 기말 120. 10/21은 이동이 없어 행 없음
    DATA: lt_stock TYPE zcl_mm_stkday_calc=>tt_stock,
          lt_delta TYPE zcl_mm_stkday_calc=>tt_delta,
          lt_snap  TYPE zcl_mm_stkday_calc=>ty_t_date,
          lt_row   TYPE zcl_mm_stkday_calc=>tt_row,
          lt_exp   TYPE zcl_mm_stkday_calc=>tt_row.

    lt_stock = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc
                          gen_qty = 150 ) ).
    lt_delta = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc
                          budat = c_d1022 gr_qty = 50 gi_qty = 20 )
                        ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc
                          budat = c_d1023 gr_qty = 30 ) ).

    lt_row = zcl_mm_stkday_calc=>roll_back( it_stock = lt_stock
                                            it_delta = lt_delta
                                            iv_from  = c_d1021
                                            iv_to    = c_d1022
                                            it_snap  = lt_snap ).

    lt_exp = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc
                        budat = c_d1022 beg_qty = 90 gr_qty = 50 gi_qty = 20 end_qty = 120 ) ).
    cl_abap_unit_assert=>assert_equals( act = lt_row exp = lt_exp
                                        msg = '설계 4.2 예시: 90/50/20/120, 이동 없는 날 행 없음' ).
  ENDMETHOD.


  METHOD multi_day_back_calc.
    " 기말(d-1) = 기말(d) - 증감(d): 10/21 입고 10 추가 -> 10/21 기말 90, 기초 80
    DATA: lt_stock TYPE zcl_mm_stkday_calc=>tt_stock,
          lt_delta TYPE zcl_mm_stkday_calc=>tt_delta,
          lt_snap  TYPE zcl_mm_stkday_calc=>ty_t_date,
          lt_row   TYPE zcl_mm_stkday_calc=>tt_row,
          lt_exp   TYPE zcl_mm_stkday_calc=>tt_row.

    lt_stock = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc
                          gen_qty = 150 ) ).
    lt_delta = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc
                          budat = c_d1021 gr_qty = 10 )
                        ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc
                          budat = c_d1022 gr_qty = 50 gi_qty = 20 )
                        ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc
                          budat = c_d1023 gr_qty = 30 ) ).

    lt_row = zcl_mm_stkday_calc=>roll_back( it_stock = lt_stock
                                            it_delta = lt_delta
                                            iv_from  = c_d1021
                                            iv_to    = c_d1022
                                            it_snap  = lt_snap ).

    lt_exp = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc
                        budat = c_d1021 beg_qty = 80 gr_qty = 10 end_qty = 90 )
                      ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc
                        budat = c_d1022 beg_qty = 90 gr_qty = 50 gi_qty = 20 end_qty = 120 ) ).
    cl_abap_unit_assert=>assert_equals( act = lt_row exp = lt_exp
                                        msg = '전일 기말 = 당일 기초(연속성)' ).
  ENDMETHOD.


  METHOD month_snapshot_row.
    " TP-U07 / TS-15: 10/01 이동 없음·기말 <> 0 -> SNAPF 'X' 행
    DATA: lt_stock TYPE zcl_mm_stkday_calc=>tt_stock,
          lt_delta TYPE zcl_mm_stkday_calc=>tt_delta,
          lt_snap  TYPE zcl_mm_stkday_calc=>ty_t_date,
          lt_row   TYPE zcl_mm_stkday_calc=>tt_row,
          lt_exp   TYPE zcl_mm_stkday_calc=>tt_row.

    lt_stock = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc
                          gen_qty = 100 ) ).
    lt_snap  = VALUE #( ( c_d1001 ) ).

    lt_row = zcl_mm_stkday_calc=>roll_back( it_stock = lt_stock
                                            it_delta = lt_delta
                                            iv_from  = c_d1001
                                            iv_to    = c_d1022
                                            it_snap  = lt_snap ).

    lt_exp = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc
                        budat = c_d1001 snapf = abap_true beg_qty = 100 end_qty = 100 ) ).
    cl_abap_unit_assert=>assert_equals( act = lt_row exp = lt_exp
                                        msg = '월초 스냅샷 행(SNAPF X, 기초=기말)' ).
  ENDMETHOD.


  METHOD snapshot_zero_no_row.
    " TP-U07: 스냅샷 일자라도 기말(일반·K·E·이전중)이 모두 0이면 행 없음
    DATA: lt_stock TYPE zcl_mm_stkday_calc=>tt_stock,
          lt_delta TYPE zcl_mm_stkday_calc=>tt_delta,
          lt_snap  TYPE zcl_mm_stkday_calc=>ty_t_date,
          lt_row   TYPE zcl_mm_stkday_calc=>tt_row.

    lt_stock = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc ) ).
    lt_snap  = VALUE #( ( c_d1001 ) ( c_d1015 ) ).

    lt_row = zcl_mm_stkday_calc=>roll_back( it_stock = lt_stock
                                            it_delta = lt_delta
                                            iv_from  = c_d1001
                                            iv_to    = c_d1022
                                            it_snap  = lt_snap ).

    cl_abap_unit_assert=>assert_initial( act = lt_row
                                         msg = '재고 0이면 스냅샷 행을 만들지 않음' ).
  ENDMETHOD.


  METHOD snapshot_with_move_one_row.
    " 03 T-3: 스냅샷일과 이동일이 겹치면 SNAPF 'X'이면서 입출고 값이 있는 행 1건
    DATA: lt_stock TYPE zcl_mm_stkday_calc=>tt_stock,
          lt_delta TYPE zcl_mm_stkday_calc=>tt_delta,
          lt_snap  TYPE zcl_mm_stkday_calc=>ty_t_date,
          lt_row   TYPE zcl_mm_stkday_calc=>tt_row,
          lt_exp   TYPE zcl_mm_stkday_calc=>tt_row.

    lt_stock = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc
                          gen_qty = 100 ) ).
    lt_delta = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc
                          budat = c_d1001 gr_qty = 10 ) ).
    lt_snap  = VALUE #( ( c_d1001 ) ).

    lt_row = zcl_mm_stkday_calc=>roll_back( it_stock = lt_stock
                                            it_delta = lt_delta
                                            iv_from  = c_d1001
                                            iv_to    = c_d1005
                                            it_snap  = lt_snap ).

    lt_exp = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc
                        budat = c_d1001 snapf = abap_true beg_qty = 90 gr_qty = 10
                        end_qty = 100 ) ).
    cl_abap_unit_assert=>assert_equals( act = lt_row exp = lt_exp
                                        msg = '스냅샷+이동 같은 날은 1행' ).
  ENDMETHOD.


  METHOD stock_only_no_rows.
    " 03 T-3: 현재고만 있고 이동·스냅샷이 없는 키는 행 0건
    DATA: lt_stock TYPE zcl_mm_stkday_calc=>tt_stock,
          lt_delta TYPE zcl_mm_stkday_calc=>tt_delta,
          lt_snap  TYPE zcl_mm_stkday_calc=>ty_t_date,
          lt_row   TYPE zcl_mm_stkday_calc=>tt_row.

    lt_stock = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc
                          gen_qty = 100 ) ).

    lt_row = zcl_mm_stkday_calc=>roll_back( it_stock = lt_stock
                                            it_delta = lt_delta
                                            iv_from  = c_d1001
                                            iv_to    = c_d1022
                                            it_snap  = lt_snap ).

    cl_abap_unit_assert=>assert_initial( act = lt_row
                                         msg = '이동·스냅샷 없으면 행 없음' ).
  ENDMETHOD.


  METHOD invalid_range_empty.
    " 가드: From > To 또는 일자 공란이면 빈 결과
    DATA: lt_stock TYPE zcl_mm_stkday_calc=>tt_stock,
          lt_delta TYPE zcl_mm_stkday_calc=>tt_delta,
          lt_snap  TYPE zcl_mm_stkday_calc=>ty_t_date,
          lt_row   TYPE zcl_mm_stkday_calc=>tt_row,
          l_init   TYPE budat.

    lt_stock = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc
                          gen_qty = 100 ) ).
    lt_delta = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc
                          budat = c_d1021 gr_qty = 10 ) ).

    lt_row = zcl_mm_stkday_calc=>roll_back( it_stock = lt_stock
                                            it_delta = lt_delta
                                            iv_from  = c_d1022
                                            iv_to    = c_d1021
                                            it_snap  = lt_snap ).
    cl_abap_unit_assert=>assert_initial( act = lt_row msg = 'From > To는 빈 결과' ).

    lt_row = zcl_mm_stkday_calc=>roll_back( it_stock = lt_stock
                                            it_delta = lt_delta
                                            iv_from  = l_init
                                            iv_to    = c_d1022
                                            it_snap  = lt_snap ).
    cl_abap_unit_assert=>assert_initial( act = lt_row msg = 'From 공란은 빈 결과' ).
  ENDMETHOD.


  METHOD special_measures_rollback.
    " K·E·이전중도 같은 원리로 역산 (팀장 확인: K/E 별도 컬럼, 이전중)
    " 현재고 K 30 / E 5 / 이전중 20, 10/22 K 입고 10·이전중 +20, 10/23 E 출고 5
    DATA: lt_stock TYPE zcl_mm_stkday_calc=>tt_stock,
          lt_delta TYPE zcl_mm_stkday_calc=>tt_delta,
          lt_snap  TYPE zcl_mm_stkday_calc=>ty_t_date,
          lt_row   TYPE zcl_mm_stkday_calc=>tt_row,
          lt_exp   TYPE zcl_mm_stkday_calc=>tt_row.

    lt_stock = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc
                          k_qty = 30 e_qty = 5 trf_qty = 20 ) ).
    lt_delta = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc
                          budat = c_d1022 k_gr = 10 trf_qty = 20 )
                        ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc
                          budat = c_d1023 e_gi = 5 ) ).

    lt_row = zcl_mm_stkday_calc=>roll_back( it_stock = lt_stock
                                            it_delta = lt_delta
                                            iv_from  = c_d1022
                                            iv_to    = c_d1022
                                            it_snap  = lt_snap ).

    lt_exp = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc
                        budat = c_d1022 k_gr = 10 k_end = 30 e_end = 10 trf_end = 20 ) ).
    cl_abap_unit_assert=>assert_equals( act = lt_row exp = lt_exp
                                        msg = 'K/E/이전중 기말 역산(E는 미래 출고 5 되돌림)' ).
  ENDMETHOD.


  METHOD material_level_equals_sum.
    " TP-U08 / D4: 배치 2개가 서로 다른 날 행을 가질 때 A 기말 = 각 배치 그날 기준 기말 합
    DATA: lt_stock   TYPE zcl_mm_stkday_calc=>tt_stock,
          lt_delta   TYPE zcl_mm_stkday_calc=>tt_delta,
          lt_stock_a TYPE zcl_mm_stkday_calc=>tt_stock,
          lt_delta_a TYPE zcl_mm_stkday_calc=>tt_delta,
          lt_end     TYPE zcl_mm_stkday_calc=>tt_stock,
          lt_end_m   TYPE zcl_mm_stkday_calc=>tt_stock,
          lt_dummy   TYPE zcl_mm_stkday_calc=>tt_delta,
          lt_snap    TYPE zcl_mm_stkday_calc=>ty_t_date,
          lt_row     TYPE zcl_mm_stkday_calc=>tt_row,
          ls_row     TYPE zcl_mm_stkday_calc=>ty_row,
          ls_end     TYPE zcl_mm_stkday_calc=>ty_stock,
          lt_exp_s   TYPE zcl_mm_stkday_calc=>tt_stock,
          lt_exp_d   TYPE zcl_mm_stkday_calc=>tt_delta,
          lt_exp     TYPE zcl_mm_stkday_calc=>tt_row.

    lt_stock = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat charg = c_b1
                          stkcat = c_loc gen_qty = 60 )
                        ( werks = c_werks lgort = c_sl01 matnr = c_mat charg = c_b2
                          stkcat = c_loc gen_qty = 40 ) ).
    lt_delta = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat charg = c_b1
                          stkcat = c_loc budat = c_d1021 gr_qty = 10 )
                        ( werks = c_werks lgort = c_sl01 matnr = c_mat charg = c_b2
                          stkcat = c_loc budat = c_d1022 gi_qty = 20 ) ).

    zcl_mm_stkday_calc=>to_material_level( EXPORTING it_stock = lt_stock
                                                     it_delta = lt_delta
                                           IMPORTING et_stock = lt_stock_a
                                                     et_delta = lt_delta_a ).

    lt_exp_s = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc
                          gen_qty = 100 ) ).
    cl_abap_unit_assert=>assert_equals( act = lt_stock_a exp = lt_exp_s
                                        msg = '현재고 배치 합산(CHARG 공란)' ).
    lt_exp_d = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc
                          budat = c_d1021 gr_qty = 10 )
                        ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc
                          budat = c_d1022 gi_qty = 20 ) ).
    cl_abap_unit_assert=>assert_equals( act = lt_delta_a exp = lt_exp_d
                                        msg = '증감 배치 합산(CHARG 공란)' ).

    lt_row = zcl_mm_stkday_calc=>roll_back( it_stock = lt_stock_a
                                            it_delta = lt_delta_a
                                            iv_from  = c_d1021
                                            iv_to    = c_d1022
                                            it_snap  = lt_snap ).
    lt_exp = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc
                        budat = c_d1021 beg_qty = 110 gr_qty = 10 end_qty = 120 )
                      ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc
                        budat = c_d1022 beg_qty = 120 gi_qty = 20 end_qty = 100 ) ).
    cl_abap_unit_assert=>assert_equals( act = lt_row exp = lt_exp
                                        msg = 'A 레벨 역산 결과' ).

    " 10/21 A 기말(120) = B1 10/21 기말(60) + B2 10/21 기말(40+20=60)
    lt_end = zcl_mm_stkday_calc=>end_at_date( it_stock = lt_stock
                                              it_delta = lt_delta
                                              iv_date  = c_d1021 ).
    zcl_mm_stkday_calc=>to_material_level( EXPORTING it_stock = lt_end
                                                     it_delta = lt_dummy
                                           IMPORTING et_stock = lt_end_m ).
    READ TABLE lt_end_m INTO ls_end INDEX 1.
    READ TABLE lt_row INTO ls_row WITH KEY budat = c_d1021.
    cl_abap_unit_assert=>assert_equals( act = ls_row-end_qty exp = ls_end-gen_qty
                                        msg = 'A 기말 = 배치별 그날 기준 기말 합(D4)' ).
  ENDMETHOD.


  METHOD end_at_date_subtracts.
    " 03 T-1: END_AT_DATE = 현재고 - 그 일자 이후 증감. 증감만 있는 키도 결과에 포함
    DATA: lt_stock TYPE zcl_mm_stkday_calc=>tt_stock,
          lt_delta TYPE zcl_mm_stkday_calc=>tt_delta,
          lt_end   TYPE zcl_mm_stkday_calc=>tt_stock,
          lt_exp   TYPE zcl_mm_stkday_calc=>tt_stock.

    lt_stock = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat charg = c_b1
                          stkcat = c_loc gen_qty = 60 ) ).
    lt_delta = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat charg = c_b1
                          stkcat = c_loc budat = c_d1021 gr_qty = 3 )
                        ( werks = c_werks lgort = c_sl01 matnr = c_mat charg = c_b1
                          stkcat = c_loc budat = c_d1023 gr_qty = 5 )
                        ( werks = c_werks lgort = c_sl01 matnr = c_mat charg = c_b1
                          stkcat = c_loc budat = c_d1024 gi_qty = 2 )
                        ( werks = c_werks lgort = c_sl01 matnr = c_mat charg = c_b3
                          stkcat = c_loc budat = c_d1023 gr_qty = 7 ) ).

    lt_end = zcl_mm_stkday_calc=>end_at_date( it_stock = lt_stock
                                              it_delta = lt_delta
                                              iv_date  = c_d1022 ).

    lt_exp = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat charg = c_b1
                        stkcat = c_loc gen_qty = 57 )
                      ( werks = c_werks lgort = c_sl01 matnr = c_mat charg = c_b3
                        stkcat = c_loc gen_qty = -7 ) ).
    cl_abap_unit_assert=>assert_equals( act = lt_end exp = lt_exp
                                        msg = '60 - (5 - 2) = 57, 증감만 있는 키 -7' ).
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* CALC_PERIOD / IS_ZERO_RESULT / CHECK_PERIOD / 일자 유틸
* (TP-U09~U12, 팀장 확인: From~To 기초/기말, 03 T-1 SUBTRACT_MINUTES)
*----------------------------------------------------------------------*
CLASS ltcl_period DEFINITION INHERITING FROM ltcl_base FINAL FOR TESTING
  RISK LEVEL HARMLESS
  DURATION SHORT.

  PRIVATE SECTION.
    METHODS:
      design_example            FOR TESTING,
      no_rows_all_zero          FOR TESTING,
      from_in_prev_month        FOR TESTING,
      one_day_cancel_negative   FOR TESTING,
      special_from_last_row     FOR TESTING,
      low_is_load_from          FOR TESTING,
      is_zero_only_all_zero     FOR TESTING,
      check_period_codes        FOR TESTING,
      snapshot_dates_months     FOR TESTING,
      snapshot_dates_leap_year  FOR TESTING,
      month_start_values        FOR TESTING,
      subtract_minutes_boundary FOR TESTING.
ENDCLASS.

CLASS ltcl_period IMPLEMENTATION.

  METHOD design_example.
    " TP-U09(설계 4.4 예시): F 10/21, T 10/22, 10/01 스냅샷 END 90,
    " 10/22 행(입고 50, 출고 20, END 120) -> 기초 90 / 입고 50 / 출고 20 / 기말 120
    DATA: lt_in  TYPE zcl_mm_stkday_calc=>tt_period_in,
          ls_act TYPE zcl_mm_stkday_calc=>ty_period,
          ls_exp TYPE zcl_mm_stkday_calc=>ty_period.

    lt_in = VALUE #( ( budat = c_d1001 end_qty = 90 )
                     ( budat = c_d1022 gr_qty = 50 gi_qty = 20 end_qty = 120 ) ).

    ls_act = zcl_mm_stkday_calc=>calc_period( it_row  = lt_in
                                              iv_from = c_d1021
                                              iv_to   = c_d1022
                                              iv_low  = c_d1001 ).

    ls_exp = VALUE #( beg_qty = 90 gr_qty = 50 gi_qty = 20 end_qty = 120 ).
    cl_abap_unit_assert=>assert_equals( act = ls_act exp = ls_exp
                                        msg = '설계 4.4 예시 90/50/20/120' ).
  ENDMETHOD.


  METHOD no_rows_all_zero.
    " TP-U09: 행 없음 -> 모두 0
    DATA: lt_in  TYPE zcl_mm_stkday_calc=>tt_period_in,
          ls_act TYPE zcl_mm_stkday_calc=>ty_period.

    ls_act = zcl_mm_stkday_calc=>calc_period( it_row  = lt_in
                                              iv_from = c_d1021
                                              iv_to   = c_d1022
                                              iv_low  = c_d1001 ).

    cl_abap_unit_assert=>assert_initial( act = ls_act msg = '행이 없으면 0' ).
  ENDMETHOD.


  METHOD from_in_prev_month.
    " TP-U09: From이 전월(F < L)이면 입출고에 전월분 포함, 기말은 당월 구간 [L, T]
    " 09/26 입고 10(END 100), 10/01 스냅샷 END 100, 10/03 출고 5(END 95)
    DATA: lt_in  TYPE zcl_mm_stkday_calc=>tt_period_in,
          ls_act TYPE zcl_mm_stkday_calc=>ty_period,
          ls_exp TYPE zcl_mm_stkday_calc=>ty_period.

    lt_in = VALUE #( ( budat = c_d0926 gr_qty = 10 end_qty = 100 )
                     ( budat = c_d1001 end_qty = 100 )
                     ( budat = c_d1003 gi_qty = 5 end_qty = 95 ) ).

    ls_act = zcl_mm_stkday_calc=>calc_period( it_row  = lt_in
                                              iv_from = c_d0925
                                              iv_to   = c_d1005
                                              iv_low  = c_d1001 ).

    ls_exp = VALUE #( beg_qty = 90 gr_qty = 10 gi_qty = 5 end_qty = 95 ).
    cl_abap_unit_assert=>assert_equals( act = ls_act exp = ls_exp
                                        msg = '기초(09/25 시작) 90 = 95 - 10 + 5' ).
  ENDMETHOD.


  METHOD one_day_cancel_negative.
    " 팀장 확인(From=To 일별 + 취소 순액): 10/20 입고 100, 10/22에 그 입고를 20 취소(102)
    " -> 10/22 하루 조회: 기초 100 / 입고 -20 / 출고 0 / 기말 80
    DATA: lt_in  TYPE zcl_mm_stkday_calc=>tt_period_in,
          ls_act TYPE zcl_mm_stkday_calc=>ty_period,
          ls_exp TYPE zcl_mm_stkday_calc=>ty_period.

    lt_in = VALUE #( ( budat = c_d1020 gr_qty = 100 end_qty = 100 )
                     ( budat = c_d1022 gr_qty = -20 end_qty = 80 ) ).

    ls_act = zcl_mm_stkday_calc=>calc_period( it_row  = lt_in
                                              iv_from = c_d1022
                                              iv_to   = c_d1022
                                              iv_low  = c_d1001 ).

    ls_exp = VALUE #( beg_qty = 100 gr_qty = -20 gi_qty = 0 end_qty = 80 ).
    cl_abap_unit_assert=>assert_equals( act = ls_act exp = ls_exp
                                        msg = '다른 날 취소는 그 날 입고 마이너스' ).
  ENDMETHOD.


  METHOD special_from_last_row.
    " TP-U09: K / E / 이전중은 기말(T)과 같은 행(구간 안 마지막 행)의 값
    DATA: lt_in  TYPE zcl_mm_stkday_calc=>tt_period_in,
          ls_act TYPE zcl_mm_stkday_calc=>ty_period,
          ls_exp TYPE zcl_mm_stkday_calc=>ty_period.

    lt_in = VALUE #( ( budat = c_d1001 end_qty = 10 k_end = 5 e_end = 3 )
                     ( budat = c_d1015 end_qty = 10 k_end = 6 e_end = 3 trf_end = 7 )
                     ( budat = c_d1023 end_qty = 99 k_end = 99 ) ).   " To 이후 행은 무시

    ls_act = zcl_mm_stkday_calc=>calc_period( it_row  = lt_in
                                              iv_from = c_d1020
                                              iv_to   = c_d1020
                                              iv_low  = c_d1001 ).

    ls_exp = VALUE #( beg_qty = 10 end_qty = 10 k_end = 6 e_end = 3 trf_end = 7 ).
    cl_abap_unit_assert=>assert_equals( act = ls_act exp = ls_exp
                                        msg = 'K/E/이전중은 마지막 행 값, To 이후 행 무시' ).
  ENDMETHOD.


  METHOD low_is_load_from.
    " L = 적재 시작일(10/15)일 때 그 이전 행은 기말 후보가 아님
    DATA: lt_in  TYPE zcl_mm_stkday_calc=>tt_period_in,
          ls_act TYPE zcl_mm_stkday_calc=>ty_period,
          ls_exp TYPE zcl_mm_stkday_calc=>ty_period.

    lt_in = VALUE #( ( budat = c_d1010 end_qty = 999 )
                     ( budat = c_d1015 end_qty = 40 )
                     ( budat = c_d1018 gr_qty = 5 end_qty = 45 ) ).

    ls_act = zcl_mm_stkday_calc=>calc_period( it_row  = lt_in
                                              iv_from = c_d1015
                                              iv_to   = c_d1020
                                              iv_low  = c_d1015 ).

    ls_exp = VALUE #( beg_qty = 40 gr_qty = 5 end_qty = 45 ).
    cl_abap_unit_assert=>assert_equals( act = ls_act exp = ls_exp
                                        msg = '적재 시작일 이전 행 제외' ).
  ENDMETHOD.


  METHOD is_zero_only_all_zero.
    " TP-U10: 7개 값이 모두 0일 때만 참. 이전중만 있으면 거짓
    DATA ls_period TYPE zcl_mm_stkday_calc=>ty_period.

    cl_abap_unit_assert=>assert_equals(
      act = zcl_mm_stkday_calc=>is_zero_result( ls_period )
      exp = abap_true
      msg = '모두 0이면 참' ).

    ls_period-trf_end = 1.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mm_stkday_calc=>is_zero_result( ls_period )
      exp = abap_false
      msg = '이전중만 있으면 거짓' ).

    CLEAR ls_period.
    ls_period-k_end = -1.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mm_stkday_calc=>is_zero_result( ls_period )
      exp = abap_false
      msg = '위탁(K)만 있으면 거짓' ).

    CLEAR ls_period.
    ls_period-gr_qty = 5.
    ls_period-gi_qty = 5.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mm_stkday_calc=>is_zero_result( ls_period )
      exp = abap_false
      msg = '기초=기말=0이어도 입출고가 있으면 거짓' ).
  ENDMETHOD.


  METHOD check_period_codes.
    " TP-U11: 반환 코드 (오늘 = 2026.10.23)
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mm_stkday_calc=>check_period( iv_from = c_d1022 iv_to = c_d1021
                                              iv_today = c_today )
      exp = zcl_mm_stkday_calc=>c_chk_from_gt_to
      msg = 'From > To -> 1' ).

    cl_abap_unit_assert=>assert_equals(
      act = zcl_mm_stkday_calc=>check_period( iv_from = c_d1021 iv_to = c_d1023
                                              iv_today = c_today )
      exp = zcl_mm_stkday_calc=>c_chk_to_today
      msg = 'To = 오늘 -> 2' ).

    cl_abap_unit_assert=>assert_equals(
      act = zcl_mm_stkday_calc=>check_period( iv_from = c_d1021 iv_to = c_d1022
                                              iv_today = c_today )
      exp = zcl_mm_stkday_calc=>c_chk_ok
      msg = '제어 미확인이면 정상' ).

    cl_abap_unit_assert=>assert_equals(
      act = zcl_mm_stkday_calc=>check_period( iv_from = c_d1021 iv_to = c_d1022
                                              iv_today = c_today iv_with_ctrl = abap_true
                                              iv_load_from = c_d1015 )
      exp = zcl_mm_stkday_calc=>c_chk_not_loaded
      msg = 'LAST_BUDAT 공란 -> 3(미집계)' ).

    cl_abap_unit_assert=>assert_equals(
      act = zcl_mm_stkday_calc=>check_period( iv_from = c_d1021 iv_to = c_d1022
                                              iv_today = c_today iv_with_ctrl = abap_true
                                              iv_load_from = c_d1015
                                              iv_last_budat = c_d1021 )
      exp = zcl_mm_stkday_calc=>c_chk_to_gt_last
      msg = 'To > LAST_BUDAT -> 4' ).

    cl_abap_unit_assert=>assert_equals(
      act = zcl_mm_stkday_calc=>check_period( iv_from = c_d1010 iv_to = c_d1022
                                              iv_today = c_today iv_with_ctrl = abap_true
                                              iv_load_from = c_d1015
                                              iv_last_budat = c_d1022 )
      exp = zcl_mm_stkday_calc=>c_chk_from_lt_ld
      msg = 'From < LOAD_FROM -> 5' ).

    cl_abap_unit_assert=>assert_equals(
      act = zcl_mm_stkday_calc=>check_period( iv_from = c_d1015 iv_to = c_d1022
                                              iv_today = c_today iv_with_ctrl = abap_true
                                              iv_load_from = c_d1015
                                              iv_last_budat = c_d1022 )
      exp = zcl_mm_stkday_calc=>c_chk_ok
      msg = '집계 범위 안 -> 정상' ).
  ENDMETHOD.


  METHOD snapshot_dates_months.
    " TP-U12: 10/15~12/03 -> 11/01, 12/01 (+ 구간 안 적재 시작일). 연도 경계
    DATA: lt_act TYPE zcl_mm_stkday_calc=>ty_t_date,
          lt_exp TYPE zcl_mm_stkday_calc=>ty_t_date.

    lt_act = zcl_mm_stkday_calc=>get_snapshot_dates( iv_from = '20261015' iv_to = '20261203' ).
    lt_exp = VALUE #( ( '20261101' ) ( '20261201' ) ).
    cl_abap_unit_assert=>assert_equals( act = lt_act exp = lt_exp msg = '구간 안 매월 1일' ).

    lt_act = zcl_mm_stkday_calc=>get_snapshot_dates( iv_from      = '20261015'
                                                     iv_to        = '20261203'
                                                     iv_load_from = '20261020' ).
    lt_exp = VALUE #( ( '20261020' ) ( '20261101' ) ( '20261201' ) ).
    cl_abap_unit_assert=>assert_equals( act = lt_act exp = lt_exp msg = '적재 시작일 포함' ).

    lt_act = zcl_mm_stkday_calc=>get_snapshot_dates( iv_from      = '20261015'
                                                     iv_to        = '20261203'
                                                     iv_load_from = '20260901' ).
    lt_exp = VALUE #( ( '20261101' ) ( '20261201' ) ).
    cl_abap_unit_assert=>assert_equals( act = lt_act exp = lt_exp msg = '구간 밖 적재 시작일 제외' ).

    lt_act = zcl_mm_stkday_calc=>get_snapshot_dates( iv_from = '20261101' iv_to = '20261101' ).
    lt_exp = VALUE #( ( '20261101' ) ).
    cl_abap_unit_assert=>assert_equals( act = lt_act exp = lt_exp msg = 'From이 월초면 포함' ).

    lt_act = zcl_mm_stkday_calc=>get_snapshot_dates( iv_from = '20261215' iv_to = '20270205' ).
    lt_exp = VALUE #( ( '20270101' ) ( '20270201' ) ).
    cl_abap_unit_assert=>assert_equals( act = lt_act exp = lt_exp msg = '연도 경계' ).

    lt_act = zcl_mm_stkday_calc=>get_snapshot_dates( iv_from = '20261203' iv_to = '20261015' ).
    cl_abap_unit_assert=>assert_initial( act = lt_act msg = 'From > To는 빈 결과' ).
  ENDMETHOD.


  METHOD snapshot_dates_leap_year.
    " TP-U12: 윤년(2028) 2월 포함 구간
    DATA: lt_act TYPE zcl_mm_stkday_calc=>ty_t_date,
          lt_exp TYPE zcl_mm_stkday_calc=>ty_t_date.

    lt_act = zcl_mm_stkday_calc=>get_snapshot_dates( iv_from = '20280115' iv_to = '20280310' ).
    lt_exp = VALUE #( ( '20280201' ) ( '20280301' ) ).
    cl_abap_unit_assert=>assert_equals( act = lt_act exp = lt_exp msg = '윤년 2월·3월 1일' ).
  ENDMETHOD.


  METHOD month_start_values.
    " TP-U12: MONTH_START 윤년 2/29, 공란
    DATA: l_exp  TYPE budat VALUE '20280201',
          l_exp2 TYPE budat VALUE '20261001',
          l_init TYPE d.

    cl_abap_unit_assert=>assert_equals( act = zcl_mm_stkday_calc=>month_start( '20280229' )
                                        exp = l_exp msg = '2028.02.29 -> 2028.02.01' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_mm_stkday_calc=>month_start( c_d1022 )
                                        exp = l_exp2 msg = '2026.10.22 -> 2026.10.01' ).
    cl_abap_unit_assert=>assert_initial( act = zcl_mm_stkday_calc=>month_start( l_init )
                                         msg = '공란 -> 공란' ).
  ENDMETHOD.


  METHOD subtract_minutes_boundary.
    " 03 T-1: 자정·연도 경계, 날짜 공란 -> 공란, 0분 -> 그대로
    DATA: l_date TYPE d,
          l_time TYPE t,
          l_init TYPE d.

    zcl_mm_stkday_calc=>subtract_minutes( EXPORTING iv_date = '20261023' iv_time = '003000'
                                                    iv_minutes = 60
                                          IMPORTING ev_date = l_date ev_time = l_time ).
    cl_abap_unit_assert=>assert_equals( act = l_date exp = CONV d( '20261022' )
                                        msg = '자정 경계 날짜' ).
    cl_abap_unit_assert=>assert_equals( act = l_time exp = CONV t( '233000' )
                                        msg = '자정 경계 시각' ).

    zcl_mm_stkday_calc=>subtract_minutes( EXPORTING iv_date = '20260101' iv_time = '001000'
                                                    iv_minutes = 20
                                          IMPORTING ev_date = l_date ev_time = l_time ).
    cl_abap_unit_assert=>assert_equals( act = l_date exp = CONV d( '20251231' )
                                        msg = '연도 경계 날짜' ).
    cl_abap_unit_assert=>assert_equals( act = l_time exp = CONV t( '235000' )
                                        msg = '연도 경계 시각' ).

    zcl_mm_stkday_calc=>subtract_minutes( EXPORTING iv_date = '20261023' iv_time = '070000'
                                                    iv_minutes = 0
                                          IMPORTING ev_date = l_date ev_time = l_time ).
    cl_abap_unit_assert=>assert_equals( act = l_time exp = CONV t( '070000' )
                                        msg = '0분이면 그대로' ).

    zcl_mm_stkday_calc=>subtract_minutes( EXPORTING iv_date = l_init iv_time = '070000'
                                                    iv_minutes = 60
                                          IMPORTING ev_date = l_date ev_time = l_time ).
    cl_abap_unit_assert=>assert_initial( act = l_date msg = '날짜 공란 -> 공란' ).
    cl_abap_unit_assert=>assert_initial( act = l_time msg = '날짜 공란 -> 시각 공란' ).
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* AGGREGATE_LOCATION (TP-U13~U15, 팀장 확인: 단위 혼재 시 합산 안 함)
*----------------------------------------------------------------------*
CLASS ltcl_location DEFINITION INHERITING FROM ltcl_base FINAL FOR TESTING
  RISK LEVEL HARMLESS
  DURATION SHORT.

  PRIVATE SECTION.
    METHODS:
      single_unit_sums           FOR TESTING,
      unit_mix_not_summed        FOR TESTING,
      unit_mix_order_independent FOR TESTING,
      key_sort_transit_last      FOR TESTING,
      empty_input_empty_result   FOR TESTING.
ENDCLASS.

CLASS ltcl_location IMPLEMENTATION.

  METHOD single_unit_sums.
    " TP-U13: SL01(KG 배치 2행 + 마이너스 입고 자재) -> KG 합, UNIT_MIX 공란, 항등식 성립
    DATA: lt_qty TYPE zcl_mm_stkday_calc=>tt_loc_qty,
          lt_sum TYPE zcl_mm_stkday_calc=>tt_loc_sum,
          lt_exp TYPE zcl_mm_stkday_calc=>tt_loc_sum,
          ls_sum TYPE zcl_mm_stkday_calc=>ty_loc_sum,
          l_beg  TYPE menge_d.

    lt_qty = VALUE #( ( werks = c_werks lgort = c_sl01 stkcat = c_loc matnr = c_mat meins = c_kg
                        beg_qty = 60 gr_qty = 30 gi_qty = 10 end_qty = 80 )
                      ( werks = c_werks lgort = c_sl01 stkcat = c_loc matnr = c_mat meins = c_kg
                        beg_qty = 40 gr_qty = 20 gi_qty = 20 end_qty = 40 )
                      ( werks = c_werks lgort = c_sl01 stkcat = c_loc matnr = c_mat3 meins = c_kg
                        beg_qty = 10 gr_qty = -5 gi_qty = 0 end_qty = 5 ) ).

    lt_sum = zcl_mm_stkday_calc=>aggregate_location( lt_qty ).

    lt_exp = VALUE #( ( werks = c_werks lgort = c_sl01 stkcat = c_loc meins = c_kg
                        beg_qty = 110 gr_qty = 45 gi_qty = 30 end_qty = 125 ) ).
    cl_abap_unit_assert=>assert_equals( act = lt_sum exp = lt_exp
                                        msg = '단일 단위 위치는 합산(마이너스 입고 순액 포함)' ).

    READ TABLE lt_sum INTO ls_sum INDEX 1.
    l_beg = ls_sum-end_qty - ls_sum-gr_qty + ls_sum-gi_qty.
    cl_abap_unit_assert=>assert_equals( act = ls_sum-beg_qty exp = l_beg
                                        msg = '기초 = 기말 - 입고 + 출고' ).
  ENDMETHOD.


  METHOD unit_mix_not_summed.
    " TP-U14 / 팀장 확인: SL02(KG + EA) -> UNIT_MIX 'X', MEINS 공란, 수량 4개 0
    DATA: lt_qty TYPE zcl_mm_stkday_calc=>tt_loc_qty,
          lt_sum TYPE zcl_mm_stkday_calc=>tt_loc_sum,
          lt_exp TYPE zcl_mm_stkday_calc=>tt_loc_sum.

    lt_qty = VALUE #( ( werks = c_werks lgort = c_sl02 stkcat = c_loc matnr = c_mat2 meins = c_kg
                        beg_qty = 10 gr_qty = 5 gi_qty = 0 end_qty = 15 )
                      ( werks = c_werks lgort = c_sl02 stkcat = c_loc matnr = c_mat3 meins = c_ea
                        beg_qty = 3 gr_qty = 0 gi_qty = 1 end_qty = 2 ) ).

    lt_sum = zcl_mm_stkday_calc=>aggregate_location( lt_qty ).

    lt_exp = VALUE #( ( werks = c_werks lgort = c_sl02 stkcat = c_loc unit_mix = abap_true ) ).
    cl_abap_unit_assert=>assert_equals( act = lt_sum exp = lt_exp
                                        msg = '서로 다른 단위는 합산하지 않음' ).
  ENDMETHOD.


  METHOD unit_mix_order_independent.
    " TP-U14: 입력 순서를 바꿔도(EA 먼저) 혼재. KG 3행 + EA 1행(마지막)도 혼재
    DATA: lt_qty TYPE zcl_mm_stkday_calc=>tt_loc_qty,
          lt_sum TYPE zcl_mm_stkday_calc=>tt_loc_sum,
          lt_exp TYPE zcl_mm_stkday_calc=>tt_loc_sum.

    lt_exp = VALUE #( ( werks = c_werks lgort = c_sl02 stkcat = c_loc unit_mix = abap_true ) ).

    lt_qty = VALUE #( ( werks = c_werks lgort = c_sl02 stkcat = c_loc matnr = c_mat3 meins = c_ea
                        beg_qty = 3 gi_qty = 1 end_qty = 2 )
                      ( werks = c_werks lgort = c_sl02 stkcat = c_loc matnr = c_mat2 meins = c_kg
                        beg_qty = 10 gr_qty = 5 end_qty = 15 ) ).
    lt_sum = zcl_mm_stkday_calc=>aggregate_location( lt_qty ).
    cl_abap_unit_assert=>assert_equals( act = lt_sum exp = lt_exp msg = 'EA 먼저 입력해도 혼재' ).

    lt_qty = VALUE #( ( werks = c_werks lgort = c_sl02 stkcat = c_loc matnr = c_mat meins = c_kg
                        beg_qty = 1 end_qty = 1 )
                      ( werks = c_werks lgort = c_sl02 stkcat = c_loc matnr = c_mat2 meins = c_kg
                        beg_qty = 2 end_qty = 2 )
                      ( werks = c_werks lgort = c_sl02 stkcat = c_loc matnr = c_mat2 meins = c_kg
                        beg_qty = 3 end_qty = 3 )
                      ( werks = c_werks lgort = c_sl02 stkcat = c_loc matnr = c_mat3 meins = c_ea
                        beg_qty = 4 end_qty = 4 ) ).
    lt_sum = zcl_mm_stkday_calc=>aggregate_location( lt_qty ).
    cl_abap_unit_assert=>assert_equals( act = lt_sum exp = lt_exp msg = 'KG 3행 + EA 마지막도 혼재' ).
  ENDMETHOD.


  METHOD key_sort_transit_last.
    " TP-U15 / 03 T-4: 위치별 1행, 정렬 WERKS -> L -> T(운송중, LGORT 공란)
    DATA: lt_qty TYPE zcl_mm_stkday_calc=>tt_loc_qty,
          lt_sum TYPE zcl_mm_stkday_calc=>tt_loc_sum,
          ls_sum TYPE zcl_mm_stkday_calc=>ty_loc_sum,
          l_exp  TYPE menge_d VALUE 7.

    lt_qty = VALUE #( ( werks = c_werks2 lgort = c_sl01 stkcat = c_loc matnr = c_mat meins = c_kg
                        beg_qty = 1 end_qty = 1 )
                      ( werks = c_werks stkcat = c_trn matnr = c_mat meins = c_kg )
                      ( werks = c_werks lgort = c_sl02 stkcat = c_loc matnr = c_mat meins = c_kg
                        beg_qty = 2 end_qty = 2 )
                      ( werks = c_werks lgort = c_sl01 stkcat = c_loc matnr = c_mat meins = c_kg
                        beg_qty = 3 end_qty = 3 )
                      ( werks = c_werks lgort = c_sl01 stkcat = c_loc matnr = c_mat2 meins = c_kg
                        beg_qty = 4 end_qty = 4 ) ).

    lt_sum = zcl_mm_stkday_calc=>aggregate_location( lt_qty ).

    cl_abap_unit_assert=>assert_equals( act = lines( lt_sum ) exp = 4 msg = '위치별 1행' ).
    READ TABLE lt_sum INTO ls_sum INDEX 1.
    cl_abap_unit_assert=>assert_equals( act = ls_sum-lgort exp = c_sl01 msg = '1행 P001 SL01' ).
    cl_abap_unit_assert=>assert_equals( act = ls_sum-end_qty exp = l_exp msg = 'SL01 = 3 + 4' ).
    READ TABLE lt_sum INTO ls_sum INDEX 2.
    cl_abap_unit_assert=>assert_equals( act = ls_sum-lgort exp = c_sl02 msg = '2행 P001 SL02' ).
    READ TABLE lt_sum INTO ls_sum INDEX 3.
    cl_abap_unit_assert=>assert_equals( act = ls_sum-stkcat exp = c_trn
                                        msg = '3행 P001 운송중(저장위치 행 뒤)' ).
    cl_abap_unit_assert=>assert_initial( act = ls_sum-lgort msg = '운송중 행 저장위치 공란' ).
    READ TABLE lt_sum INTO ls_sum INDEX 4.
    cl_abap_unit_assert=>assert_equals( act = ls_sum-werks exp = c_werks2 msg = '4행 P002' ).
  ENDMETHOD.


  METHOD empty_input_empty_result.
    " TP-U15: 빈 입력 -> 빈 결과
    DATA: lt_qty TYPE zcl_mm_stkday_calc=>tt_loc_qty,
          lt_sum TYPE zcl_mm_stkday_calc=>tt_loc_sum.

    lt_sum = zcl_mm_stkday_calc=>aggregate_location( lt_qty ).
    cl_abap_unit_assert=>assert_initial( act = lt_sum msg = '빈 입력은 빈 결과' ).
  ENDMETHOD.

ENDCLASS.
