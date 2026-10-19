*"* use this source file for your ABAP unit test classes
*"----------------------------------------------------------------------
*" ZCL_MM_MATERIAL_LIST 로컬 테스트 클래스 (요청 20261006-33d4fc)
*" - 대상 시스템: ECC, SAP_BASIS 7.40 (CL_ABAP_TESTDOUBLE 있음, SP09 이상 추정)
*" - CL_OSQL_TEST_ENVIRONMENT / CL_AUNIT_AUTHORITY_CHECK 없음(2026-10-12 SearchObject)
*"   → Open SQL·AUTHORITY-CHECK 테스트 더블을 쓸 수 없으므로 DB가 필요 없는
*"     정적 메서드, constructor 정규화, 플랜트 미입력 가드만 단위 테스트합니다.
*"     read_* (DB 조회)와 권한 체크 결과는 QAS 통합 테스트(04_test.md IT-xx)로 확인합니다.
*" - MAKT 조회 결과는 메모리 버퍼(tt_makt, setup에서 생성)로 대신합니다.
*" - private 멤버(ms_sel, mt_werks_ok, mv_auth_checked) 확인을 위해
*"   이 include에서 LOCAL FRIENDS를 선언합니다(본 소스 변경 불필요).
*" - 문법: 7.40 SP05 범위(VALUE, CONV, NEW, 인라인 선언)만 사용. xsdbool·FOR 미사용
*"----------------------------------------------------------------------
CLASS ltcl_material_list DEFINITION DEFERRED.
CLASS zcl_mm_material_list DEFINITION LOCAL FRIENDS ltcl_material_list.

CLASS ltcl_material_list DEFINITION FINAL
  FOR TESTING
  RISK LEVEL HARMLESS
  DURATION SHORT.

  PRIVATE SECTION.

    CONSTANTS:
      gc_mat1 TYPE matnr VALUE 'ZUT-MAT-0001',
      gc_mat2 TYPE matnr VALUE 'ZUT-MAT-0002',
      gc_mat9 TYPE matnr VALUE 'ZUT-MAT-0009',
      gc_ko   TYPE spras VALUE '3',
      gc_en   TYPE spras VALUE 'E',
      gc_de   TYPE spras VALUE 'D'.

    DATA mt_makt TYPE zcl_mm_material_list=>tt_makt.

    METHODS setup.

    " build_deletion_range (MARC-LVORM, 확정 Q2 / FR-03)
    METHODS del_exclude_eq_space    FOR TESTING.
    METHODS del_only_ne_space       FOR TESTING.
    METHODS del_all_empty           FOR TESTING.
    METHODS del_invalid_empty       FOR TESTING.
    METHODS del_range_semantics     FOR TESTING.

    " build_batch_range (MARC-XCHPF, FR-12/FR-13)
    METHODS bat_all_empty           FOR TESTING.
    METHODS bat_only_ne_space       FOR TESTING.
    METHODS bat_none_eq_space       FOR TESTING.
    METHODS bat_invalid_empty       FOR TESTING.
    METHODS bat_range_semantics     FOR TESTING.

    " pick_text (FR-05, Q4)
    METHODS text_primary_found      FOR TESTING.
    METHODS text_fallback_used      FOR TESTING.
    METHODS text_none_found         FOR TESTING.
    METHODS text_fallback_blank     FOR TESTING.
    METHODS text_fallback_same      FOR TESTING.
    METHODS text_other_material     FOR TESTING.

    " constructor 정규화 (Q4, Q5)
    METHODS ctor_blank_spras_langu  FOR TESTING.
    METHODS ctor_clear_same_spras2  FOR TESTING.
    METHODS ctor_negative_maxhit    FOR TESTING.
    METHODS ctor_keeps_valid_input  FOR TESTING.

    " 플랜트 미입력 가드 (FR-02, FR-11: 빈 range IN = 전체 조회 방지)
    METHODS no_plant_auth_empty     FOR TESTING.
    METHODS no_plant_get_data_empty FOR TESTING.

    " 도우미: range 의미 판정 (DB 없이 Open SQL IN과 같은 규칙으로 평가)
    METHODS lvorm_hit
      IMPORTING
        iv_value      TYPE marc-lvorm
        it_range      TYPE zcl_mm_material_list=>tt_r_lvorm
      RETURNING
        VALUE(rv_hit) TYPE abap_bool.

    METHODS xchpf_hit
      IMPORTING
        iv_value      TYPE marc-xchpf
        it_range      TYPE zcl_mm_material_list=>tt_r_xchpf
      RETURNING
        VALUE(rv_hit) TYPE abap_bool.

ENDCLASS.


CLASS ltcl_material_list IMPLEMENTATION.

  METHOD setup.
    " MAKT 대신 쓰는 메모리 버퍼 (테스트 더블 역할)
    " MAT1: KO + EN / MAT2: EN만 / MAT9: 없음
    mt_makt = VALUE #(
      ( matnr = gc_mat1 spras = gc_ko maktx = 'MAT1 KO TEXT' )
      ( matnr = gc_mat1 spras = gc_en maktx = 'MAT1 EN TEXT' )
      ( matnr = gc_mat2 spras = gc_en maktx = 'MAT2 EN TEXT' ) ).
  ENDMETHOD.


  METHOD lvorm_hit.
    IF iv_value IN it_range.
      rv_hit = abap_true.
    ELSE.
      rv_hit = abap_false.
    ENDIF.
  ENDMETHOD.


  METHOD xchpf_hit.
    IF iv_value IN it_range.
      rv_hit = abap_true.
    ELSE.
      rv_hit = abap_false.
    ENDIF.
  ENDMETHOD.


*----------------------------------------------------------------------*
* build_deletion_range
*----------------------------------------------------------------------*
  METHOD del_exclude_eq_space.
    DATA(lt_act) = zcl_mm_material_list=>build_deletion_range(
                     zcl_mm_material_list=>gc_del_mode-del_exclude ).

    cl_abap_unit_assert=>assert_equals(
      act = lt_act
      exp = VALUE zcl_mm_material_list=>tt_r_lvorm(
              ( sign = 'I' option = 'EQ' low = space ) )
      msg = '삭제 제외(E)는 I EQ 공란 1행이어야 함' ).
  ENDMETHOD.


  METHOD del_only_ne_space.
    DATA(lt_act) = zcl_mm_material_list=>build_deletion_range(
                     zcl_mm_material_list=>gc_del_mode-del_only ).

    cl_abap_unit_assert=>assert_equals(
      act = lt_act
      exp = VALUE zcl_mm_material_list=>tt_r_lvorm(
              ( sign = 'I' option = 'NE' low = space ) )
      msg = '삭제만(O)은 I NE 공란 1행이어야 함' ).
  ENDMETHOD.


  METHOD del_all_empty.
    DATA(lt_act) = zcl_mm_material_list=>build_deletion_range(
                     zcl_mm_material_list=>gc_del_mode-del_all ).

    cl_abap_unit_assert=>assert_initial(
      act = lt_act
      msg = '전체(A)는 빈 range(조건 없음)여야 함' ).
  ENDMETHOD.


  METHOD del_invalid_empty.
    DATA(lt_act) = zcl_mm_material_list=>build_deletion_range( 'Z' ).

    cl_abap_unit_assert=>assert_initial(
      act = lt_act
      msg = '잘못된 모드는 빈 range(설계 7.3, 10장)여야 함' ).
  ENDMETHOD.


  METHOD del_range_semantics.
    DATA(lt_e) = zcl_mm_material_list=>build_deletion_range(
                   zcl_mm_material_list=>gc_del_mode-del_exclude ).
    DATA(lt_o) = zcl_mm_material_list=>build_deletion_range(
                   zcl_mm_material_list=>gc_del_mode-del_only ).
    DATA(lt_a) = zcl_mm_material_list=>build_deletion_range(
                   zcl_mm_material_list=>gc_del_mode-del_all ).

    " E: 정상(공란)만 참
    cl_abap_unit_assert=>assert_true(
      act = lvorm_hit( iv_value = space it_range = lt_e )
      msg = 'E: 공란은 포함되어야 함' ).
    cl_abap_unit_assert=>assert_false(
      act = lvorm_hit( iv_value = 'X' it_range = lt_e )
      msg = 'E: X(삭제표시)는 제외되어야 함' ).

    " O: 삭제표시만 참
    cl_abap_unit_assert=>assert_true(
      act = lvorm_hit( iv_value = 'X' it_range = lt_o )
      msg = 'O: X는 포함되어야 함' ).
    cl_abap_unit_assert=>assert_false(
      act = lvorm_hit( iv_value = space it_range = lt_o )
      msg = 'O: 공란은 제외되어야 함' ).

    " A: 모두 참
    cl_abap_unit_assert=>assert_true(
      act = lvorm_hit( iv_value = 'X' it_range = lt_a )
      msg = 'A: X도 포함되어야 함' ).
    cl_abap_unit_assert=>assert_true(
      act = lvorm_hit( iv_value = space it_range = lt_a )
      msg = 'A: 공란도 포함되어야 함' ).
  ENDMETHOD.


*----------------------------------------------------------------------*
* build_batch_range
*----------------------------------------------------------------------*
  METHOD bat_all_empty.
    DATA(lt_act) = zcl_mm_material_list=>build_batch_range(
                     zcl_mm_material_list=>gc_batch_mode-all ).

    cl_abap_unit_assert=>assert_initial(
      act = lt_act
      msg = '배치 전체(A)는 빈 range여야 함' ).
  ENDMETHOD.


  METHOD bat_only_ne_space.
    DATA(lt_act) = zcl_mm_material_list=>build_batch_range(
                     zcl_mm_material_list=>gc_batch_mode-only ).

    cl_abap_unit_assert=>assert_equals(
      act = lt_act
      exp = VALUE zcl_mm_material_list=>tt_r_xchpf(
              ( sign = 'I' option = 'NE' low = space ) )
      msg = '배치관리만(B)은 I NE 공란 1행이어야 함' ).
  ENDMETHOD.


  METHOD bat_none_eq_space.
    DATA(lt_act) = zcl_mm_material_list=>build_batch_range(
                     zcl_mm_material_list=>gc_batch_mode-none ).

    cl_abap_unit_assert=>assert_equals(
      act = lt_act
      exp = VALUE zcl_mm_material_list=>tt_r_xchpf(
              ( sign = 'I' option = 'EQ' low = space ) )
      msg = '비배치관리만(N)은 I EQ 공란 1행이어야 함' ).
  ENDMETHOD.


  METHOD bat_invalid_empty.
    DATA(lt_act) = zcl_mm_material_list=>build_batch_range( 'Z' ).

    cl_abap_unit_assert=>assert_initial(
      act = lt_act
      msg = '잘못된 배치 모드는 빈 range여야 함' ).
  ENDMETHOD.


  METHOD bat_range_semantics.
    DATA(lt_a) = zcl_mm_material_list=>build_batch_range(
                   zcl_mm_material_list=>gc_batch_mode-all ).
    DATA(lt_b) = zcl_mm_material_list=>build_batch_range(
                   zcl_mm_material_list=>gc_batch_mode-only ).
    DATA(lt_n) = zcl_mm_material_list=>build_batch_range(
                   zcl_mm_material_list=>gc_batch_mode-none ).

    " B: X만 참
    cl_abap_unit_assert=>assert_true(
      act = xchpf_hit( iv_value = 'X' it_range = lt_b )
      msg = 'B: X는 포함되어야 함' ).
    cl_abap_unit_assert=>assert_false(
      act = xchpf_hit( iv_value = space it_range = lt_b )
      msg = 'B: 공란은 제외되어야 함' ).

    " N: 공란만 참
    cl_abap_unit_assert=>assert_true(
      act = xchpf_hit( iv_value = space it_range = lt_n )
      msg = 'N: 공란은 포함되어야 함' ).
    cl_abap_unit_assert=>assert_false(
      act = xchpf_hit( iv_value = 'X' it_range = lt_n )
      msg = 'N: X는 제외되어야 함' ).

    " A: 모두 참 (전체 = 배치관리만 + 비배치관리만, IT-13 전제)
    cl_abap_unit_assert=>assert_true(
      act = xchpf_hit( iv_value = 'X' it_range = lt_a )
      msg = 'A: X도 포함되어야 함' ).
    cl_abap_unit_assert=>assert_true(
      act = xchpf_hit( iv_value = space it_range = lt_a )
      msg = 'A: 공란도 포함되어야 함' ).
  ENDMETHOD.


*----------------------------------------------------------------------*
* pick_text
*----------------------------------------------------------------------*
  METHOD text_primary_found.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mm_material_list=>pick_text( it_makt   = mt_makt
                                             iv_matnr  = gc_mat1
                                             iv_spras  = gc_ko
                                             iv_spras2 = gc_en )
      exp = CONV maktx( 'MAT1 KO TEXT' )
      msg = '1순위 언어 텍스트가 있으면 그것을 써야 함' ).
  ENDMETHOD.


  METHOD text_fallback_used.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mm_material_list=>pick_text( it_makt   = mt_makt
                                             iv_matnr  = gc_mat2
                                             iv_spras  = gc_ko
                                             iv_spras2 = gc_en )
      exp = CONV maktx( 'MAT2 EN TEXT' )
      msg = '1순위가 없으면 대체 언어 텍스트를 써야 함' ).
  ENDMETHOD.


  METHOD text_none_found.
    cl_abap_unit_assert=>assert_initial(
      act = zcl_mm_material_list=>pick_text( it_makt   = mt_makt
                                             iv_matnr  = gc_mat9
                                             iv_spras  = gc_ko
                                             iv_spras2 = gc_en )
      msg = '두 언어 모두 없으면 공란이어야 함' ).
  ENDMETHOD.


  METHOD text_fallback_blank.
    cl_abap_unit_assert=>assert_initial(
      act = zcl_mm_material_list=>pick_text( it_makt   = mt_makt
                                             iv_matnr  = gc_mat2
                                             iv_spras  = gc_ko
                                             iv_spras2 = space )
      msg = '대체 언어가 공란이면 대체하지 않아야 함' ).
  ENDMETHOD.


  METHOD text_fallback_same.
    cl_abap_unit_assert=>assert_initial(
      act = zcl_mm_material_list=>pick_text( it_makt   = mt_makt
                                             iv_matnr  = gc_mat2
                                             iv_spras  = gc_de
                                             iv_spras2 = gc_de )
      msg = '대체 언어 = 1순위이고 텍스트가 없으면 공란이어야 함' ).
  ENDMETHOD.


  METHOD text_other_material.
    " 다른 자재(MAT1)의 KO 텍스트를 잘못 집지 않는지 확인
    DATA(lv_act) = zcl_mm_material_list=>pick_text( it_makt   = mt_makt
                                                    iv_matnr  = gc_mat2
                                                    iv_spras  = gc_ko
                                                    iv_spras2 = gc_de ).
    cl_abap_unit_assert=>assert_initial(
      act = lv_act
      msg = '자재번호가 다르면 텍스트를 가져오면 안 됨' ).
  ENDMETHOD.


*----------------------------------------------------------------------*
* constructor 정규화 (private ms_sel 확인: LOCAL FRIENDS)
*----------------------------------------------------------------------*
  METHOD ctor_blank_spras_langu.
    DATA(lo_cut) = NEW zcl_mm_material_list( VALUE #( spras = space ) ).

    cl_abap_unit_assert=>assert_equals(
      act = lo_cut->ms_sel-spras
      exp = sy-langu
      msg = '자재명 언어가 공란이면 로그온 언어여야 함' ).
  ENDMETHOD.


  METHOD ctor_clear_same_spras2.
    DATA(lo_cut) = NEW zcl_mm_material_list(
                     VALUE #( spras = gc_en spras2 = gc_en ) ).
    cl_abap_unit_assert=>assert_initial(
      act = lo_cut->ms_sel-spras2
      msg = '대체 언어 = 1순위이면 대체 언어를 지워야 함' ).

    " 1순위 공란 → 로그온 언어로 바뀐 뒤 대체 언어와 같아지는 경우
    DATA(lo_cut2) = NEW zcl_mm_material_list(
                      VALUE #( spras = space spras2 = sy-langu ) ).
    cl_abap_unit_assert=>assert_initial(
      act = lo_cut2->ms_sel-spras2
      msg = '로그온 언어로 보정된 1순위와 같으면 대체 언어를 지워야 함' ).
  ENDMETHOD.


  METHOD ctor_negative_maxhit.
    DATA(lo_cut) = NEW zcl_mm_material_list( VALUE #( maxhit = -1 ) ).

    cl_abap_unit_assert=>assert_equals(
      act = lo_cut->ms_sel-maxhit
      exp = zcl_mm_material_list=>gc_default_maxhit
      msg = '최대건수 음수는 기본값(50,000)으로 바뀌어야 함' ).
  ENDMETHOD.


  METHOD ctor_keeps_valid_input.
    DATA(lo_cut) = NEW zcl_mm_material_list(
                     VALUE #( spras      = gc_ko
                              spras2     = gc_en
                              maxhit     = 0
                              del_mode   = zcl_mm_material_list=>gc_del_mode-del_only
                              batch_mode = zcl_mm_material_list=>gc_batch_mode-none ) ).

    cl_abap_unit_assert=>assert_equals( act = lo_cut->ms_sel-spras  exp = gc_ko
                                        msg = '1순위 언어 유지' ).
    cl_abap_unit_assert=>assert_equals( act = lo_cut->ms_sel-spras2 exp = gc_en
                                        msg = '대체 언어 유지' ).
    cl_abap_unit_assert=>assert_equals( act = lo_cut->ms_sel-maxhit exp = 0
                                        msg = '최대건수 0(무제한) 유지' ).
    cl_abap_unit_assert=>assert_equals( act = lo_cut->ms_sel-del_mode
                                        exp = zcl_mm_material_list=>gc_del_mode-del_only
                                        msg = '삭제 모드 유지' ).
    cl_abap_unit_assert=>assert_equals( act = lo_cut->ms_sel-batch_mode
                                        exp = zcl_mm_material_list=>gc_batch_mode-none
                                        msg = '배치 모드 유지' ).

    DATA(lo_cut2) = NEW zcl_mm_material_list( VALUE #( maxhit = 10 ) ).
    cl_abap_unit_assert=>assert_equals( act = lo_cut2->ms_sel-maxhit exp = 10
                                        msg = '양수 최대건수 유지' ).
  ENDMETHOD.


*----------------------------------------------------------------------*
* 플랜트 미입력 가드 (DB 접근 없음: ms_sel-werks 공란이면 T001W SELECT 전 RETURN)
*----------------------------------------------------------------------*
  METHOD no_plant_auth_empty.
    DATA(lo_cut) = NEW zcl_mm_material_list( VALUE #( maxhit = 10 ) ).

    lo_cut->check_plant_authority(
      IMPORTING
        et_allowed = DATA(lt_allowed)
        et_denied  = DATA(lt_denied) ).

    cl_abap_unit_assert=>assert_initial( act = lt_allowed
                                         msg = '플랜트 미입력: 허용 플랜트 없음' ).
    cl_abap_unit_assert=>assert_initial( act = lt_denied
                                         msg = '플랜트 미입력: 거부 플랜트 없음' ).
    cl_abap_unit_assert=>assert_initial( act = lo_cut->mt_werks_ok
                                         msg = '플랜트 미입력: 조회용 range 비어 있음' ).
    cl_abap_unit_assert=>assert_true( act = lo_cut->mv_auth_checked
                                      msg = '권한 체크 수행 플래그가 서야 함' ).
  ENDMETHOD.


  METHOD no_plant_get_data_empty.
    " check_plant_authority를 먼저 부르지 않아도 get_data 내부에서 수행 후 조회 차단
    DATA(lo_cut) = NEW zcl_mm_material_list( VALUE #( maxhit = 10 ) ).

    DATA(lt_out) = lo_cut->get_data( ).

    cl_abap_unit_assert=>assert_initial(
      act = lt_out
      msg = '허용 플랜트가 없으면 조회하지 않고 빈 결과여야 함(전체 조회 방지)' ).
    cl_abap_unit_assert=>assert_false(
      act = lo_cut->is_truncated( )
      msg = '조회하지 않았으면 최대건수 도달이 아니어야 함' ).
    cl_abap_unit_assert=>assert_true(
      act = lo_cut->mv_auth_checked
      msg = 'get_data가 권한 체크를 먼저 수행해야 함' ).
  ENDMETHOD.

ENDCLASS.
