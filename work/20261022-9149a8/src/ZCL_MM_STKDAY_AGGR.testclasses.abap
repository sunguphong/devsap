*"* use this source file for your ABAP unit test classes
*----------------------------------------------------------------------*
* ZCL_MM_STKDAY_AGGR 로컬 테스트 클래스 (Local Test Classes include)
* 요청 ID : 20261022-9149a8 / 04_test.md 5장
* 범위    : DB를 쓰지 않는 부분만 - 생성자 정규화, ADD_MATERIAL(자재별 최소 d0),
*           COMPUTE_BLOCK(초기 적재 모드: 분류 -> 다른 플랜트 키 제거 -> B/A 역산
*           -> 정합성 점검 (1)(2)). 초기 적재 모드는 CHECK_CONSISTENCY (3)의
*           ZTMM1236 SELECT 전에 RETURN 하므로 DB 접근이 없다.
* 격리    : 테스트 데이터 직접 주입(현재고·MSEG 집계행·자재 정보·취소 BWART).
*           private 멤버는 LOCAL FRIENDS로 접근(본 소스 변경 없음)
* 미포함  : READ_*/DETECT_MATERIALS/SAVE_BLOCK/UPDATE_CONTROL/잠금·로그
*           (CL_OSQL_TEST_ENVIRONMENT 없음 -> QAS 통합 테스트 TP-I09~I14)
* 명명    : 핸드북 2장(G_/L_/GT_/LT_/LS_/C_/R_). 테스트 클래스·메서드명은
*           핸드북 규칙 없음 - SAP 관례 적용
*----------------------------------------------------------------------*
CLASS ltcl_aggr DEFINITION DEFERRED.
CLASS zcl_mm_stkday_aggr DEFINITION LOCAL FRIENDS ltcl_aggr.

CLASS ltcl_aggr DEFINITION FINAL FOR TESTING
  RISK LEVEL HARMLESS
  DURATION SHORT.

  PRIVATE SECTION.
    CONSTANTS:
      c_werks  TYPE werks_d VALUE 'P001',
      c_werks2 TYPE werks_d VALUE 'P002',
      c_sl01   TYPE lgort_d VALUE 'SL01',
      c_sl09   TYPE lgort_d VALUE 'SL09',
      c_mat    TYPE matnr   VALUE 'MAT-A',
      c_mat2   TYPE matnr   VALUE 'MAT-B',
      c_matz   TYPE matnr   VALUE 'MAT-Z',
      c_b1     TYPE charg_d VALUE 'BATCH1',
      c_b2     TYPE charg_d VALUE 'BATCH2',
      c_loc    TYPE zestcat VALUE 'L',
      c_trn    TYPE zestcat VALUE 'T',
      c_kg     TYPE meins   VALUE 'KG',
      c_ea     TYPE meins   VALUE 'EA',
      c_d1020  TYPE budat   VALUE '20261020',
      c_d1021  TYPE budat   VALUE '20261021',
      c_d1022  TYPE budat   VALUE '20261022',
      c_d1023  TYPE budat   VALUE '20261023',
      c_d1025  TYPE budat   VALUE '20261025',
      c_today  TYPE sydatum VALUE '20261023',
      c_time   TYPE syuzeit VALUE '070000'.

    DATA g_cut TYPE REF TO zcl_mm_stkday_aggr.   " 테스트 대상

    METHODS:
      create_cut
        IMPORTING
          iv_mode       TYPE zcl_mm_stkday_aggr=>ty_code1
          iv_blksz      TYPE i DEFAULT 1000
          iv_ovlap      TYPE i DEFAULT 60
        RETURNING
          VALUE(ro_cut) TYPE REF TO zcl_mm_stkday_aggr,
      prepare_init_mode,
      ctor_clamps_block_size       FOR TESTING,
      ctor_negative_overlap        FOR TESTING,
      add_material_keeps_min_d0    FOR TESTING,
      compute_block_init_mode      FOR TESTING,
      compute_block_counts_negative FOR TESTING,
      compute_block_from_after_end FOR TESTING.
ENDCLASS.

CLASS ltcl_aggr IMPLEMENTATION.

  METHOD create_cut.
    DATA r_werks TYPE zcl_mm_stkday_calc=>ty_r_werks.

    r_werks = VALUE #( ( sign = 'I' option = 'EQ' low = c_werks ) ).
    CREATE OBJECT ro_cut
      EXPORTING
        iv_mode       = iv_mode
        it_werks      = r_werks
        iv_from       = c_d1020
        iv_overlap    = iv_ovlap
        iv_block_size = iv_blksz.
  ENDMETHOD.


  METHOD prepare_init_mode.
    " 초기 적재 모드, 플랜트 P001, 구간 10/20 ~ 10/22, 실행일 10/23 07:00, 취소 BWART 102
    g_cut = create_cut( zcl_mm_stkday_calc=>c_mode_init ).
    g_cut->g_werks     = c_werks.
    g_cut->g_d_end     = c_d1022.
    g_cut->g_load_from = c_d1020.
    g_cut->g_run_date  = c_today.
    g_cut->g_run_time  = c_time.
    g_cut->gt_cancel   = VALUE #( ( '102' ) ).
  ENDMETHOD.


  METHOD ctor_clamps_block_size.
    " 블록 크기 1~5000 제한(P3): 0 -> 기본 1000, 9999 -> 5000, 경계값은 그대로
    g_cut = create_cut( iv_mode = zcl_mm_stkday_calc=>c_mode_daily iv_blksz = 0 ).
    cl_abap_unit_assert=>assert_equals( act = g_cut->g_blksz
                                        exp = zcl_mm_stkday_aggr=>c_default_blksz
                                        msg = '0 -> 기본값' ).

    g_cut = create_cut( iv_mode = zcl_mm_stkday_calc=>c_mode_daily iv_blksz = 9999 ).
    cl_abap_unit_assert=>assert_equals( act = g_cut->g_blksz
                                        exp = zcl_mm_stkday_aggr=>c_max_blksz
                                        msg = '9999 -> 상한 5000' ).

    g_cut = create_cut( iv_mode = zcl_mm_stkday_calc=>c_mode_daily iv_blksz = 1 ).
    cl_abap_unit_assert=>assert_equals( act = g_cut->g_blksz exp = 1 msg = '1은 그대로' ).

    g_cut = create_cut( iv_mode = zcl_mm_stkday_calc=>c_mode_daily iv_blksz = 5000 ).
    cl_abap_unit_assert=>assert_equals( act = g_cut->g_blksz exp = 5000 msg = '5000은 그대로' ).
  ENDMETHOD.


  METHOD ctor_negative_overlap.
    " 여유시간 음수 -> 기본 60분, 0은 그대로(감지 여유 없음)
    g_cut = create_cut( iv_mode = zcl_mm_stkday_calc=>c_mode_daily iv_ovlap = -5 ).
    cl_abap_unit_assert=>assert_equals( act = g_cut->g_overlap
                                        exp = zcl_mm_stkday_aggr=>c_default_ovlap
                                        msg = '음수 -> 기본값' ).

    g_cut = create_cut( iv_mode = zcl_mm_stkday_calc=>c_mode_daily iv_ovlap = 0 ).
    cl_abap_unit_assert=>assert_equals( act = g_cut->g_overlap exp = 0 msg = '0은 그대로' ).
  ENDMETHOD.


  METHOD add_material_keeps_min_d0.
    " J3: 자재별 d0 = 감지 경로 (a)~(d) 중 가장 이른 전기일. 공란 자재·공란 일자는 무시
    DATA: lt_mat TYPE zcl_mm_stkday_aggr=>ty_t_mat_h,
          ls_mat TYPE zcl_mm_stkday_aggr=>ty_mat,
          l_init TYPE budat,
          l_none TYPE matnr.

    g_cut = create_cut( zcl_mm_stkday_calc=>c_mode_daily ).

    g_cut->add_material( EXPORTING iv_matnr = c_mat iv_d0 = c_d1022 CHANGING ct_mat = lt_mat ).
    g_cut->add_material( EXPORTING iv_matnr = c_mat iv_d0 = c_d1020 CHANGING ct_mat = lt_mat ).
    g_cut->add_material( EXPORTING iv_matnr = c_mat iv_d0 = c_d1025 CHANGING ct_mat = lt_mat ).
    g_cut->add_material( EXPORTING iv_matnr = l_none iv_d0 = c_d1020 CHANGING ct_mat = lt_mat ).
    g_cut->add_material( EXPORTING iv_matnr = c_mat2 iv_d0 = l_init CHANGING ct_mat = lt_mat ).

    cl_abap_unit_assert=>assert_equals( act = lines( lt_mat ) exp = 1
                                        msg = '공란 자재·공란 일자는 추가 안 함' ).
    READ TABLE lt_mat INTO ls_mat WITH TABLE KEY matnr = c_mat.
    cl_abap_unit_assert=>assert_equals( act = ls_mat-d0 exp = c_d1020
                                        msg = '가장 이른 d0 유지' ).
  ENDMETHOD.


  METHOD compute_block_init_mode.
    " J5 통합(메모리): 배치 자재 MAT-A(B1 60, B2 40) + 받는 운송중 7
    " 이동: B1 10/21 101 +10, B1 10/22 102 4(취소 -> 입고 -4), B2 10/22 261 20,
    "       P002의 351 H 7(받는 플랜트 P001), 정보 없는 자재 MAT-Z(무시)
    " 기대: B 6행(스냅샷 10/20 포함), A 4행, A = Σ B, P002 키 없음, 정합성 경고 0
    DATA: lt_info  TYPE zcl_mm_stkday_aggr=>ty_t_info,
          lt_stock TYPE zcl_mm_stkday_calc=>tt_stock,
          lt_move  TYPE zcl_mm_stkday_calc=>tt_move,
          r_matnr  TYPE zcl_mm_stkday_calc=>ty_r_matnr,
          lt_b     TYPE zcl_mm_stkday_aggr=>ty_t_b,
          lt_a     TYPE zcl_mm_stkday_aggr=>ty_t_a,
          ls_b     TYPE ztmm1236,
          ls_a     TYPE ztmm1234.

    prepare_init_mode( ).

    lt_info  = VALUE #( ( matnr = c_mat xchpf = abap_true meins = c_kg qtyupd = abap_true ) ).
    lt_stock = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat charg = c_b1
                          stkcat = c_loc gen_qty = 60 )
                        ( werks = c_werks lgort = c_sl01 matnr = c_mat charg = c_b2
                          stkcat = c_loc gen_qty = 40 )
                        ( werks = c_werks matnr = c_mat stkcat = c_trn trf_qty = 7 ) ).
    lt_move  = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat charg = c_b1
                          budat = c_d1021 bwart = '101' shkzg = 'S' menge = 10 )
                        ( werks = c_werks lgort = c_sl01 matnr = c_mat charg = c_b1
                          budat = c_d1022 bwart = '102' shkzg = 'H' menge = 4 )
                        ( werks = c_werks lgort = c_sl01 matnr = c_mat charg = c_b2
                          budat = c_d1022 bwart = '261' shkzg = 'H' menge = 20 )
                        ( werks = c_werks2 lgort = c_sl09 matnr = c_mat
                          budat = c_d1021 bwart = '351' shkzg = 'H' recv_werks = c_werks
                          menge = 7 )
                        ( werks = c_werks lgort = c_sl01 matnr = c_matz
                          budat = c_d1021 bwart = '101' shkzg = 'S' menge = 99 ) ).
    r_matnr  = VALUE #( ( sign = 'I' option = 'EQ' low = c_mat ) ).

    g_cut->compute_block( EXPORTING ir_matnr = r_matnr
                                    iv_from  = c_d1020
                                    it_info  = lt_info
                                    it_stock = lt_stock
                                    it_move  = lt_move
                          IMPORTING et_b     = lt_b
                                    et_a     = lt_a ).

    cl_abap_unit_assert=>assert_equals( act = lines( lt_b ) exp = 6
                                        msg = 'B: B1 3행(스냅샷 포함) + B2 2행 + 운송중 1행' ).
    cl_abap_unit_assert=>assert_equals( act = lines( lt_a ) exp = 4
                                        msg = 'A: 저장위치 3행(스냅샷 포함) + 운송중 1행' ).

    " B1 10/22: 취소 102는 입고 -4, 기말 60, 기초 64
    READ TABLE lt_b INTO ls_b WITH KEY werks = c_werks lgort = c_sl01 matnr = c_mat
                                       charg = c_b1 stkcat = c_loc budat = c_d1022.
    cl_abap_unit_assert=>assert_subrc( exp = 0 msg = 'B1 10/22 행 있음' ).
    cl_abap_unit_assert=>assert_equals( act = ls_b-gr_qty  exp = CONV menge_d( -4 )
                                        msg = 'B1 10/22 입고 -4(취소 순액)' ).
    cl_abap_unit_assert=>assert_equals( act = ls_b-gi_qty  exp = CONV menge_d( 0 )
                                        msg = 'B1 10/22 출고 0(취소를 출고로 잡지 않음)' ).
    cl_abap_unit_assert=>assert_equals( act = ls_b-end_qty exp = CONV menge_d( 60 )
                                        msg = 'B1 10/22 기말 60' ).
    cl_abap_unit_assert=>assert_equals( act = ls_b-beg_qty exp = CONV menge_d( 64 )
                                        msg = 'B1 10/22 기초 64' ).
    cl_abap_unit_assert=>assert_equals( act = ls_b-meins exp = c_kg msg = '단위 = MARA-MEINS' ).
    cl_abap_unit_assert=>assert_equals( act = ls_b-erdat exp = c_today msg = '집계일 = 실행일' ).

    " B1 적재 시작일 스냅샷 10/20: 기말 54
    READ TABLE lt_b INTO ls_b WITH KEY werks = c_werks lgort = c_sl01 matnr = c_mat
                                       charg = c_b1 stkcat = c_loc budat = c_d1020.
    cl_abap_unit_assert=>assert_subrc( exp = 0 msg = 'B1 적재 시작일 스냅샷 행' ).
    cl_abap_unit_assert=>assert_equals( act = ls_b-snapf exp = abap_true msg = 'SNAPF X' ).
    cl_abap_unit_assert=>assert_equals( act = ls_b-end_qty exp = CONV menge_d( 54 )
                                        msg = 'B1 10/20 기말 54' ).

    " A 10/21: 기말 124 = B1 64 + B2 60 (D4: A = Σ B)
    READ TABLE lt_a INTO ls_a WITH KEY werks = c_werks lgort = c_sl01 matnr = c_mat
                                       stkcat = c_loc budat = c_d1021.
    cl_abap_unit_assert=>assert_subrc( exp = 0 msg = 'A 10/21 행 있음' ).
    cl_abap_unit_assert=>assert_equals( act = ls_a-end_qty exp = CONV menge_d( 124 )
                                        msg = 'A 10/21 기말 124 = 64 + 60' ).
    cl_abap_unit_assert=>assert_equals( act = ls_a-beg_qty exp = CONV menge_d( 114 )
                                        msg = 'A 10/21 기초 114' ).

    " 운송중 행: 받는 플랜트 P001, 저장위치·배치 공란, 이전중 7
    READ TABLE lt_a INTO ls_a WITH KEY werks = c_werks stkcat = c_trn budat = c_d1021.
    cl_abap_unit_assert=>assert_subrc( exp = 0 msg = '운송중 A 행 있음' ).
    cl_abap_unit_assert=>assert_initial( act = ls_a-lgort msg = '운송중 행 저장위치 공란' ).
    cl_abap_unit_assert=>assert_equals( act = ls_a-trf_end exp = CONV menge_d( 7 )
                                        msg = '운송중 이전중 7' ).

    " 다른 플랜트(P002, STO 공급 쪽) 키와 정보 없는 자재는 저장하지 않음
    READ TABLE lt_b TRANSPORTING NO FIELDS WITH KEY werks = c_werks2.
    cl_abap_unit_assert=>assert_subrc( exp = 4 msg = 'P002 키 없음(B)' ).
    READ TABLE lt_a TRANSPORTING NO FIELDS WITH KEY werks = c_werks2.
    cl_abap_unit_assert=>assert_subrc( exp = 4 msg = 'P002 키 없음(A)' ).
    READ TABLE lt_b TRANSPORTING NO FIELDS WITH KEY matnr = c_matz.
    cl_abap_unit_assert=>assert_subrc( exp = 4 msg = 'MARC 정보 없는 자재 제외' ).

    " 정합성 점검 (1) A/B 불일치 0, (2) 음수 기말 0
    cl_abap_unit_assert=>assert_equals( act = g_cut->g_cnt_mis exp = 0 msg = 'A/B 불일치 0' ).
    cl_abap_unit_assert=>assert_equals( act = g_cut->g_cnt_neg exp = 0 msg = '음수 기말 0' ).
  ENDMETHOD.


  METHOD compute_block_counts_negative.
    " J8 (2): 현재고 0인데 10/22 입고 5 -> 10/20 스냅샷 기말 -5 -> 음수 기말 1건
    DATA: lt_info  TYPE zcl_mm_stkday_aggr=>ty_t_info,
          lt_stock TYPE zcl_mm_stkday_calc=>tt_stock,
          lt_move  TYPE zcl_mm_stkday_calc=>tt_move,
          r_matnr  TYPE zcl_mm_stkday_calc=>ty_r_matnr,
          lt_b     TYPE zcl_mm_stkday_aggr=>ty_t_b,
          lt_a     TYPE zcl_mm_stkday_aggr=>ty_t_a,
          ls_b     TYPE ztmm1236.

    prepare_init_mode( ).

    lt_info = VALUE #( ( matnr = c_mat2 meins = c_ea qtyupd = abap_true ) ).
    lt_move = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat2
                         budat = c_d1022 bwart = '101' shkzg = 'S' menge = 5 ) ).
    r_matnr = VALUE #( ( sign = 'I' option = 'EQ' low = c_mat2 ) ).

    g_cut->compute_block( EXPORTING ir_matnr = r_matnr
                                    iv_from  = c_d1020
                                    it_info  = lt_info
                                    it_stock = lt_stock
                                    it_move  = lt_move
                          IMPORTING et_b     = lt_b
                                    et_a     = lt_a ).

    READ TABLE lt_b INTO ls_b WITH KEY budat = c_d1020.
    cl_abap_unit_assert=>assert_subrc( exp = 0 msg = '10/20 스냅샷 행' ).
    cl_abap_unit_assert=>assert_equals( act = ls_b-end_qty exp = CONV menge_d( -5 )
                                        msg = '10/20 기말 -5' ).
    cl_abap_unit_assert=>assert_initial( act = ls_b-charg msg = '비배치 자재는 배치 공란' ).
    cl_abap_unit_assert=>assert_equals( act = g_cut->g_cnt_neg exp = 1
                                        msg = '음수 기말 1건을 경고 건수로 셈' ).
  ENDMETHOD.


  METHOD compute_block_from_after_end.
    " 가드: 블록 시작일 > 구간 끝(전일)이면 아무것도 만들지 않음
    DATA: lt_info  TYPE zcl_mm_stkday_aggr=>ty_t_info,
          lt_stock TYPE zcl_mm_stkday_calc=>tt_stock,
          lt_move  TYPE zcl_mm_stkday_calc=>tt_move,
          r_matnr  TYPE zcl_mm_stkday_calc=>ty_r_matnr,
          lt_b     TYPE zcl_mm_stkday_aggr=>ty_t_b,
          lt_a     TYPE zcl_mm_stkday_aggr=>ty_t_a.

    prepare_init_mode( ).

    lt_info  = VALUE #( ( matnr = c_mat meins = c_kg qtyupd = abap_true ) ).
    lt_stock = VALUE #( ( werks = c_werks lgort = c_sl01 matnr = c_mat stkcat = c_loc
                          gen_qty = 10 ) ).

    g_cut->compute_block( EXPORTING ir_matnr = r_matnr
                                    iv_from  = c_d1023
                                    it_info  = lt_info
                                    it_stock = lt_stock
                                    it_move  = lt_move
                          IMPORTING et_b     = lt_b
                                    et_a     = lt_a ).

    cl_abap_unit_assert=>assert_initial( act = lt_b msg = 'B 없음' ).
    cl_abap_unit_assert=>assert_initial( act = lt_a msg = 'A 없음' ).
  ENDMETHOD.

ENDCLASS.
