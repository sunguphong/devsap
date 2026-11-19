*"* use this source file for your ABAP unit test classes
*----------------------------------------------------------------------*
* ZCL_MM_MTART_MATLIST 로컬 테스트 클래스 (Local Test Classes include, CCAU)
* 요청 ID : 20261119-f26e72 / 04_test.md 7.1장(UT), 8장(구성)
* 버전    : 3.0 (개발 재작업 2차 반영 - 메시지 클래스 ZMMM3 -> 기존 ZMM,
*           번호 001~006 -> 338~343. 출력 타입은 클래스 public TYPES
*           TY_LIST / TT_LIST, 신규 DDIC 없음)
* 방식    : DB·권한 접근 없음 (RISK LEVEL HARMLESS, DURATION SHORT)
*  - LTCL_MTART_MATLIST : UT-01~19. 공개 정적 메서드 8개, constructor
*                         정규화(G_ 속성은 LOCAL FRIENDS 로 확인),
*                         execute 입력 누락 가드(DB 접근 전 RETURN),
*                         FM 출력 타입 TY_LIST/TT_LIST 계약(RTTI),
*                         메시지 ID ZMM / 번호 338~343 계약(UT-19)
*  - LTD_MATDATA        : 테스트 더블(데이터 빌더). read_mara/read_makt 의
*                         DB 조회 결과 대신 MARA/MAKT 행을 메모리로 만들어
*                         build_list 에 넣는다
* 제외    : check_mtart / read_mara / read_makt / check_authority 는
*           private + DB/권한 의존이고, 이 시스템(7.40)에 OSQL·권한
*           테스트 더블이 없어 SE37 통합 테스트(04_test.md IT-xx)로 확인
* 전제    : 신규 DDIC 없음. 클래스 main 과 함께 활성화된다.
*           ZMM 338~343 반영이 실패해도 실행되도록 메시지 텍스트(MESSAGE)
*           는 비교하지 않고 TYPE/ID/NUMBER/V1~V2만 비교한다.
*           ID·NUMBER 기대값은 클래스 상수가 아니라 이 클래스의 고정
*           기대값(C_EXP_*: 'ZMM', '338'~'343')으로 비교해 상수 회귀를 잡는다.
* 데이터  : 자재번호는 ECC 18자리 내부 형식(앞 0 채움) 가상값.
*           MAKT 는 HASHED UNIQUE KEY matnr 이므로 같은 MATNR 을 두 번
*           넣지 않는다(LTD_MATDATA=>ADD_MAKT 가 중복이면 실패 처리).
* 문법    : ABAP 7.40 SP05 이하 구문만 사용(인라인 선언·VALUE·xsdbool·
*           FOR·REDUCE·끝 INTO 미사용). 기대값은 비교 대상과 같은 타입의
*           변수·상수로 넘긴다(리터럴 타입 차이 회피)
* 명명    : 핸드북 2장(L_/LT_/LS_/C_/R_). 테스트 클래스(LTCL_/LTD_)·메서드·
*           파라미터(IV_/IT_/CT_/RV_/RT_)·객체 참조(LO_)는 핸드북 규칙
*           없음 -> SAP 관례 적용
*----------------------------------------------------------------------*

CLASS ltcl_mtart_matlist DEFINITION DEFERRED.
CLASS zcl_mm_mtart_matlist DEFINITION LOCAL FRIENDS ltcl_mtart_matlist.

*----------------------------------------------------------------------*
* 테스트 더블 / 데이터 빌더 (MARA·MAKT 조회 결과 대체)
*----------------------------------------------------------------------*
CLASS ltd_matdata DEFINITION FINAL FOR TESTING
  RISK LEVEL HARMLESS
  DURATION SHORT.

  PUBLIC SECTION.
    CONSTANTS:
      c_matnr1   TYPE matnr VALUE '000000000000100001',
      c_matnr2   TYPE matnr VALUE '000000000000100002',
      c_matnr3   TYPE matnr VALUE '000000000000100003',
      c_meins_st TYPE meins VALUE 'ST',
      c_meins_kg TYPE meins VALUE 'KG',
      c_meins_m  TYPE meins VALUE 'M',
      c_maktx1   TYPE maktx VALUE 'UT MATERIAL 100001',
      c_maktx3   TYPE maktx VALUE 'UT MATERIAL 100003'.

    CLASS-METHODS add_mara
      IMPORTING
        !iv_matnr TYPE matnr
        !iv_meins TYPE meins
      CHANGING
        !ct_mara  TYPE zcl_mm_mtart_matlist=>tt_mara.

    CLASS-METHODS add_makt
      IMPORTING
        !iv_matnr TYPE matnr
        !iv_maktx TYPE maktx
      CHANGING
        !ct_makt  TYPE zcl_mm_mtart_matlist=>tt_makt.

    "기대값 목록 행 추가 (FM 출력 타입 TT_LIST)
    CLASS-METHODS add_list
      IMPORTING
        !iv_matnr TYPE matnr
        !iv_maktx TYPE maktx OPTIONAL
        !iv_meins TYPE meins
      CHANGING
        !ct_list  TYPE zcl_mm_mtart_matlist=>tt_list.

    "MARA 3건, 자재코드 역순(3 -> 2 -> 1)
    CLASS-METHODS mara_3_desc
      RETURNING
        VALUE(rt_mara) TYPE zcl_mm_mtart_matlist=>tt_mara.

    "MARA 2건, 자재코드 순(1 -> 2)
    CLASS-METHODS mara_2_asc
      RETURNING
        VALUE(rt_mara) TYPE zcl_mm_mtart_matlist=>tt_mara.

    "MAKT 2건(자재 1, 3) - 자재 2는 해당 언어 내역 없음
    CLASS-METHODS makt_1_3
      RETURNING
        VALUE(rt_makt) TYPE zcl_mm_mtart_matlist=>tt_makt.

ENDCLASS.


CLASS ltd_matdata IMPLEMENTATION.

  METHOD add_mara.
    DATA ls_mara TYPE zcl_mm_mtart_matlist=>ty_mara.

    ls_mara-matnr = iv_matnr.
    ls_mara-meins = iv_meins.
    APPEND ls_mara TO ct_mara.
  ENDMETHOD.


  METHOD add_makt.
    DATA ls_makt  TYPE zcl_mm_mtart_matlist=>ty_makt.
    DATA l_subrc  TYPE sysubrc.

    ls_makt-matnr = iv_matnr.
    ls_makt-maktx = iv_maktx.
    "HASHED UNIQUE KEY matnr: 중복이면 sy-subrc = 4 -> 테스트 데이터 오류
    INSERT ls_makt INTO TABLE ct_makt.
    l_subrc = sy-subrc.

    cl_abap_unit_assert=>assert_equals(
      act = l_subrc
      exp = 0
      msg = 'Test data error: duplicate MATNR in MAKT (HASHED key)' ).
  ENDMETHOD.


  METHOD add_list.
    DATA ls_list TYPE zcl_mm_mtart_matlist=>ty_list.

    ls_list-matnr = iv_matnr.
    ls_list-maktx = iv_maktx.
    ls_list-meins = iv_meins.
    APPEND ls_list TO ct_list.
  ENDMETHOD.


  METHOD mara_3_desc.
    add_mara( EXPORTING iv_matnr = c_matnr3 iv_meins = c_meins_m
              CHANGING  ct_mara  = rt_mara ).
    add_mara( EXPORTING iv_matnr = c_matnr2 iv_meins = c_meins_kg
              CHANGING  ct_mara  = rt_mara ).
    add_mara( EXPORTING iv_matnr = c_matnr1 iv_meins = c_meins_st
              CHANGING  ct_mara  = rt_mara ).
  ENDMETHOD.


  METHOD mara_2_asc.
    add_mara( EXPORTING iv_matnr = c_matnr1 iv_meins = c_meins_st
              CHANGING  ct_mara  = rt_mara ).
    add_mara( EXPORTING iv_matnr = c_matnr2 iv_meins = c_meins_kg
              CHANGING  ct_mara  = rt_mara ).
  ENDMETHOD.


  METHOD makt_1_3.
    add_makt( EXPORTING iv_matnr = c_matnr1 iv_maktx = c_maktx1
              CHANGING  ct_makt  = rt_makt ).
    add_makt( EXPORTING iv_matnr = c_matnr3 iv_maktx = c_maktx3
              CHANGING  ct_makt  = rt_makt ).
  ENDMETHOD.

ENDCLASS.


*----------------------------------------------------------------------*
* 단위 테스트
*----------------------------------------------------------------------*
CLASS ltcl_mtart_matlist DEFINITION FINAL FOR TESTING
  RISK LEVEL HARMLESS
  DURATION SHORT.

  PRIVATE SECTION.
    CONSTANTS:
      c_mtart_roh  TYPE mtart      VALUE 'ROH',
      c_mtart_low  TYPE mtart      VALUE ' roh',
      c_spras_en   TYPE spras      VALUE 'E',
      c_lvorm_del  TYPE mara-lvorm VALUE 'X',
      c_lvorm_none TYPE mara-lvorm VALUE space,
      c_v1_zzz9    TYPE symsgv     VALUE 'ZZZ9',
      c_v_roh      TYPE symsgv     VALUE 'ROH',
      c_v_5        TYPE symsgv     VALUE '5',
      c_v_10       TYPE symsgv     VALUE '10'.

    "메시지 계약 고정 기대값 (팀장 지시: 기존 메시지 클래스 ZMM 338~343)
    CONSTANTS:
      c_exp_msgid  TYPE symsgid    VALUE 'ZMM',
      c_exp_no_338 TYPE symsgno    VALUE '338',   "E 입력 누락
      c_exp_no_339 TYPE symsgno    VALUE '339',   "E 자재유형 없음
      c_exp_no_340 TYPE symsgno    VALUE '340',   "E 권한 없음
      c_exp_no_341 TYPE symsgno    VALUE '341',   "W 데이터 없음
      c_exp_no_342 TYPE symsgno    VALUE '342',   "S 정상
      c_exp_no_343 TYPE symsgno    VALUE '343'.   "W 잘림

    "UT-01~02 normalize_mtart
    METHODS ut01_mtart_lower_lead_space FOR TESTING.
    METHODS ut02_mtart_initial          FOR TESTING.
    "UT-03 normalize_spras
    METHODS ut03_spras_default_and_given FOR TESTING.
    "UT-04 normalize_max_rows
    METHODS ut04_max_rows_normalize     FOR TESTING.
    "UT-05~06 build_lvorm_range (행 내용 + IN 의미)
    METHODS ut05_lvorm_range_exclude    FOR TESTING.
    METHODS ut06_lvorm_range_with_del   FOR TESTING.
    "UT-07 get_up_to_rows (음수 -1, 경계 포함)
    METHODS ut07_up_to_rows             FOR TESTING.
    "UT-08~12, 17 build_list
    METHODS ut08_list_makt_missing      FOR TESTING.
    METHODS ut09_list_sorted            FOR TESTING.
    METHODS ut10_list_truncated         FOR TESTING.
    METHODS ut11_list_exact_n_not_trunc FOR TESTING.
    METHODS ut12_list_max_zero_all      FOR TESTING.
    METHODS ut17_list_empty_input       FOR TESTING.
    "UT-13 make_return (텍스트 비교 안 함)
    METHODS ut13_make_return_fields     FOR TESTING.
    "UT-14 execute 입력 누락 가드
    METHODS ut14_execute_guard_no_input FOR TESTING.
    "UT-15 decide_return
    METHODS ut15_decide_return_s_and_w  FOR TESTING.
    "UT-16 constructor 정규화 (LOCAL FRIENDS)
    METHODS ut16_constructor_normalize  FOR TESTING.
    "UT-18 FM 출력 타입 계약 TY_LIST / TT_LIST (RTTI)
    METHODS ut18_list_type_contract     FOR TESTING.
    "UT-19 메시지 계약 ZMM 338~343 (상수 + make_return 결과)
    METHODS ut19_msg_contract_zmm       FOR TESTING.

    "보조: lvorm 값이 range 조건에 드는지
    METHODS is_in_range
      IMPORTING
        !iv_lvorm    TYPE mara-lvorm
        !it_range    TYPE zcl_mm_mtart_matlist=>tt_lvorm_range
      RETURNING
        VALUE(rv_in) TYPE abap_bool.

    "보조: make_return 결과의 TYPE / ID / NUMBER 확인
    METHODS assert_return_id_no
      IMPORTING
        !iv_type   TYPE bapi_mtype
        !iv_number TYPE symsgno
        !iv_exp_no TYPE symsgno
        !iv_label  TYPE csequence.

ENDCLASS.


CLASS ltcl_mtart_matlist IMPLEMENTATION.

  METHOD is_in_range.
    rv_in = abap_false.
    IF iv_lvorm IN it_range.
      rv_in = abap_true.
    ENDIF.
  ENDMETHOD.


  METHOD assert_return_id_no.
    DATA ls_return TYPE bapiret2.
    DATA l_msg     TYPE string.

    ls_return = zcl_mm_mtart_matlist=>make_return(
                  iv_type   = iv_type
                  iv_number = iv_number ).

    CONCATENATE 'UT-19' iv_label 'TYPE' INTO l_msg SEPARATED BY space.
    cl_abap_unit_assert=>assert_equals(
      act = ls_return-type   exp = iv_type     msg = l_msg ).
    CONCATENATE 'UT-19' iv_label 'ID ZMM' INTO l_msg SEPARATED BY space.
    cl_abap_unit_assert=>assert_equals(
      act = ls_return-id     exp = c_exp_msgid msg = l_msg ).
    CONCATENATE 'UT-19' iv_label 'NUMBER' INTO l_msg SEPARATED BY space.
    cl_abap_unit_assert=>assert_equals(
      act = ls_return-number exp = iv_exp_no   msg = l_msg ).
  ENDMETHOD.


  METHOD ut01_mtart_lower_lead_space.
    DATA l_act TYPE mtart.

    l_act = zcl_mm_mtart_matlist=>normalize_mtart( c_mtart_low ).

    cl_abap_unit_assert=>assert_equals(
      act = l_act
      exp = c_mtart_roh
      msg = 'UT-01 leading space removed and upper case' ).
  ENDMETHOD.


  METHOD ut02_mtart_initial.
    DATA l_in  TYPE mtart.
    DATA l_act TYPE mtart.

    l_act = zcl_mm_mtart_matlist=>normalize_mtart( l_in ).

    cl_abap_unit_assert=>assert_initial(
      act = l_act
      msg = 'UT-02 initial MTART stays initial' ).
  ENDMETHOD.


  METHOD ut03_spras_default_and_given.
    DATA l_in  TYPE spras.
    DATA l_act TYPE spras.

    "공란 -> 로그온 언어
    l_act = zcl_mm_mtart_matlist=>normalize_spras( l_in ).
    cl_abap_unit_assert=>assert_equals(
      act = l_act
      exp = sy-langu
      msg = 'UT-03 initial SPRAS -> SY-LANGU' ).

    "지정 -> 그대로
    l_act = zcl_mm_mtart_matlist=>normalize_spras( c_spras_en ).
    cl_abap_unit_assert=>assert_equals(
      act = l_act
      exp = c_spras_en
      msg = 'UT-03 given SPRAS kept' ).
  ENDMETHOD.


  METHOD ut04_max_rows_normalize.
    DATA l_in  TYPE i.
    DATA l_act TYPE i.

    l_in  = -5.
    l_act = zcl_mm_mtart_matlist=>normalize_max_rows( l_in ).
    cl_abap_unit_assert=>assert_equals(
      act = l_act exp = 0 msg = 'UT-04 negative -> 0' ).

    l_in  = 0.
    l_act = zcl_mm_mtart_matlist=>normalize_max_rows( l_in ).
    cl_abap_unit_assert=>assert_equals(
      act = l_act exp = 0 msg = 'UT-04 zero -> 0' ).

    l_in  = 10.
    l_act = zcl_mm_mtart_matlist=>normalize_max_rows( l_in ).
    cl_abap_unit_assert=>assert_equals(
      act = l_act exp = 10 msg = 'UT-04 positive kept' ).
  ENDMETHOD.


  METHOD ut05_lvorm_range_exclude.
    DATA r_lvorm  TYPE zcl_mm_mtart_matlist=>tt_lvorm_range.
    DATA ls_lvorm LIKE LINE OF r_lvorm.
    DATA ls_exp   LIKE LINE OF r_lvorm.
    DATA l_with   TYPE xfeld.            "공란 = 삭제 자재 제외
    DATA l_lines  TYPE i.

    r_lvorm = zcl_mm_mtart_matlist=>build_lvorm_range( l_with ).

    l_lines = lines( r_lvorm ).
    cl_abap_unit_assert=>assert_equals(
      act = l_lines exp = 1 msg = 'UT-05 one exclude row' ).

    "기대 행: SIGN E / OPTION EQ / LOW X
    ls_exp-sign   = 'E'.
    ls_exp-option = 'EQ'.
    ls_exp-low    = c_lvorm_del.

    READ TABLE r_lvorm INTO ls_lvorm INDEX 1.
    cl_abap_unit_assert=>assert_equals(
      act = ls_lvorm exp = ls_exp msg = 'UT-05 row E / EQ / X' ).

    "의미: 삭제 표시 'X' 는 제외, 공란은 포함
    cl_abap_unit_assert=>assert_false(
      act = is_in_range( iv_lvorm = c_lvorm_del  it_range = r_lvorm )
      msg = 'UT-05 X IN range must be false' ).
    cl_abap_unit_assert=>assert_true(
      act = is_in_range( iv_lvorm = c_lvorm_none it_range = r_lvorm )
      msg = 'UT-05 space IN range must be true' ).
  ENDMETHOD.


  METHOD ut06_lvorm_range_with_del.
    DATA r_lvorm TYPE zcl_mm_mtart_matlist=>tt_lvorm_range.
    DATA l_with  TYPE xfeld.

    l_with  = abap_true.              "'X' = 삭제 자재 포함
    r_lvorm = zcl_mm_mtart_matlist=>build_lvorm_range( l_with ).

    cl_abap_unit_assert=>assert_initial(
      act = r_lvorm
      msg = 'UT-06 empty range (no condition)' ).

    cl_abap_unit_assert=>assert_true(
      act = is_in_range( iv_lvorm = c_lvorm_del  it_range = r_lvorm )
      msg = 'UT-06 X IN empty range must be true' ).
    cl_abap_unit_assert=>assert_true(
      act = is_in_range( iv_lvorm = c_lvorm_none it_range = r_lvorm )
      msg = 'UT-06 space IN empty range must be true' ).
  ENDMETHOD.


  METHOD ut07_up_to_rows.
    DATA l_in  TYPE i.
    DATA l_act TYPE i.

    "0 -> 제한 없음
    l_in  = 0.
    l_act = zcl_mm_mtart_matlist=>get_up_to_rows( l_in ).
    cl_abap_unit_assert=>assert_equals(
      act = l_act exp = cl_abap_math=>max_int4 msg = 'UT-07 0 -> MAX_INT4' ).

    "10 -> 잘림 판정용 1건 더
    l_in  = 10.
    l_act = zcl_mm_mtart_matlist=>get_up_to_rows( l_in ).
    cl_abap_unit_assert=>assert_equals(
      act = l_act exp = 11 msg = 'UT-07 10 -> 11' ).

    "MAX_INT4 -> 넘침 없이 MAX_INT4
    l_in  = cl_abap_math=>max_int4.
    l_act = zcl_mm_mtart_matlist=>get_up_to_rows( l_in ).
    cl_abap_unit_assert=>assert_equals(
      act = l_act exp = cl_abap_math=>max_int4 msg = 'UT-07 MAX_INT4 -> MAX_INT4' ).

    "MAX_INT4 - 1 -> +1 해도 MAX_INT4 (경계, 넘침 없음)
    l_in  = cl_abap_math=>max_int4 - 1.
    l_act = zcl_mm_mtart_matlist=>get_up_to_rows( l_in ).
    cl_abap_unit_assert=>assert_equals(
      act = l_act exp = cl_abap_math=>max_int4 msg = 'UT-07 MAX_INT4-1 -> MAX_INT4' ).

    "음수 -1 -> 제한 없음 (03_development X-03, UP TO -n ROWS 방지)
    l_in  = -1.
    l_act = zcl_mm_mtart_matlist=>get_up_to_rows( l_in ).
    cl_abap_unit_assert=>assert_equals(
      act = l_act exp = cl_abap_math=>max_int4 msg = 'UT-07 -1 -> MAX_INT4' ).
  ENDMETHOD.


  METHOD ut08_list_makt_missing.
    DATA lt_mara  TYPE zcl_mm_mtart_matlist=>tt_mara.
    DATA lt_makt  TYPE zcl_mm_mtart_matlist=>tt_makt.
    DATA lt_list  TYPE zcl_mm_mtart_matlist=>tt_list.
    DATA lt_exp   TYPE zcl_mm_mtart_matlist=>tt_list.
    DATA l_trunc  TYPE abap_bool.

    "MARA 2건(1, 2), MAKT 는 자재 1·3 (자재 3 내역은 MARA 에 없어 무시)
    lt_mara = ltd_matdata=>mara_2_asc( ).
    lt_makt = ltd_matdata=>makt_1_3( ).

    zcl_mm_mtart_matlist=>build_list(
      EXPORTING it_mara      = lt_mara
                it_makt      = lt_makt
                iv_max_rows  = 0
      IMPORTING et_list      = lt_list
                ev_truncated = l_trunc ).

    ltd_matdata=>add_list( EXPORTING iv_matnr = ltd_matdata=>c_matnr1
                                     iv_maktx = ltd_matdata=>c_maktx1
                                     iv_meins = ltd_matdata=>c_meins_st
                           CHANGING  ct_list  = lt_exp ).
    "자재 2: 내역 없음 -> MAKTX 공란, 행 유지 (AC-04)
    ltd_matdata=>add_list( EXPORTING iv_matnr = ltd_matdata=>c_matnr2
                                     iv_meins = ltd_matdata=>c_meins_kg
                           CHANGING  ct_list  = lt_exp ).

    cl_abap_unit_assert=>assert_equals(
      act = lt_list exp = lt_exp
      msg = 'UT-08 row kept with empty MAKTX when MAKT missing' ).
    cl_abap_unit_assert=>assert_false(
      act = l_trunc msg = 'UT-08 not truncated' ).
  ENDMETHOD.


  METHOD ut09_list_sorted.
    DATA lt_mara  TYPE zcl_mm_mtart_matlist=>tt_mara.
    DATA lt_makt  TYPE zcl_mm_mtart_matlist=>tt_makt.
    DATA lt_list  TYPE zcl_mm_mtart_matlist=>tt_list.
    DATA lt_exp   TYPE zcl_mm_mtart_matlist=>tt_list.
    DATA l_trunc  TYPE abap_bool.

    lt_mara = ltd_matdata=>mara_3_desc( ).      "3 -> 2 -> 1
    lt_makt = ltd_matdata=>makt_1_3( ).

    zcl_mm_mtart_matlist=>build_list(
      EXPORTING it_mara      = lt_mara
                it_makt      = lt_makt
                iv_max_rows  = 0
      IMPORTING et_list      = lt_list
                ev_truncated = l_trunc ).

    "MATNR 오름차순, 자재별 MEINS·MAKTX 매핑 유지 (AC-10)
    ltd_matdata=>add_list( EXPORTING iv_matnr = ltd_matdata=>c_matnr1
                                     iv_maktx = ltd_matdata=>c_maktx1
                                     iv_meins = ltd_matdata=>c_meins_st
                           CHANGING  ct_list  = lt_exp ).
    ltd_matdata=>add_list( EXPORTING iv_matnr = ltd_matdata=>c_matnr2
                                     iv_meins = ltd_matdata=>c_meins_kg
                           CHANGING  ct_list  = lt_exp ).
    ltd_matdata=>add_list( EXPORTING iv_matnr = ltd_matdata=>c_matnr3
                                     iv_maktx = ltd_matdata=>c_maktx3
                                     iv_meins = ltd_matdata=>c_meins_m
                           CHANGING  ct_list  = lt_exp ).

    cl_abap_unit_assert=>assert_equals(
      act = lt_list exp = lt_exp
      msg = 'UT-09 sorted by MATNR ascending' ).
    cl_abap_unit_assert=>assert_false(
      act = l_trunc msg = 'UT-09 not truncated' ).
  ENDMETHOD.


  METHOD ut10_list_truncated.
    DATA lt_mara  TYPE zcl_mm_mtart_matlist=>tt_mara.
    DATA lt_makt  TYPE zcl_mm_mtart_matlist=>tt_makt.
    DATA lt_list  TYPE zcl_mm_mtart_matlist=>tt_list.
    DATA lt_exp   TYPE zcl_mm_mtart_matlist=>tt_list.
    DATA l_trunc  TYPE abap_bool.

    "역순 3건, 최대 2건 -> 정렬 후 앞 2건(자재 1, 2)만 남아야 함 (AC-11)
    lt_mara = ltd_matdata=>mara_3_desc( ).
    lt_makt = ltd_matdata=>makt_1_3( ).

    zcl_mm_mtart_matlist=>build_list(
      EXPORTING it_mara      = lt_mara
                it_makt      = lt_makt
                iv_max_rows  = 2
      IMPORTING et_list      = lt_list
                ev_truncated = l_trunc ).

    ltd_matdata=>add_list( EXPORTING iv_matnr = ltd_matdata=>c_matnr1
                                     iv_maktx = ltd_matdata=>c_maktx1
                                     iv_meins = ltd_matdata=>c_meins_st
                           CHANGING  ct_list  = lt_exp ).
    ltd_matdata=>add_list( EXPORTING iv_matnr = ltd_matdata=>c_matnr2
                                     iv_meins = ltd_matdata=>c_meins_kg
                           CHANGING  ct_list  = lt_exp ).

    cl_abap_unit_assert=>assert_equals(
      act = lt_list exp = lt_exp
      msg = 'UT-10 first 2 rows after sort' ).
    cl_abap_unit_assert=>assert_true(
      act = l_trunc msg = 'UT-10 truncated flag set' ).
  ENDMETHOD.


  METHOD ut11_list_exact_n_not_trunc.
    DATA lt_mara  TYPE zcl_mm_mtart_matlist=>tt_mara.
    DATA lt_makt  TYPE zcl_mm_mtart_matlist=>tt_makt.
    DATA lt_list  TYPE zcl_mm_mtart_matlist=>tt_list.
    DATA l_trunc  TYPE abap_bool.
    DATA l_lines  TYPE i.

    "정확히 n건이면 잘림 아님
    lt_mara = ltd_matdata=>mara_2_asc( ).
    lt_makt = ltd_matdata=>makt_1_3( ).

    zcl_mm_mtart_matlist=>build_list(
      EXPORTING it_mara      = lt_mara
                it_makt      = lt_makt
                iv_max_rows  = 2
      IMPORTING et_list      = lt_list
                ev_truncated = l_trunc ).

    l_lines = lines( lt_list ).
    cl_abap_unit_assert=>assert_equals(
      act = l_lines exp = 2 msg = 'UT-11 2 rows' ).
    cl_abap_unit_assert=>assert_false(
      act = l_trunc msg = 'UT-11 exactly n rows -> not truncated' ).
  ENDMETHOD.


  METHOD ut12_list_max_zero_all.
    DATA lt_mara  TYPE zcl_mm_mtart_matlist=>tt_mara.
    DATA lt_makt  TYPE zcl_mm_mtart_matlist=>tt_makt.
    DATA lt_list  TYPE zcl_mm_mtart_matlist=>tt_list.
    DATA l_trunc  TYPE abap_bool.
    DATA l_lines  TYPE i.

    lt_mara = ltd_matdata=>mara_3_desc( ).
    lt_makt = ltd_matdata=>makt_1_3( ).

    zcl_mm_mtart_matlist=>build_list(
      EXPORTING it_mara      = lt_mara
                it_makt      = lt_makt
                iv_max_rows  = 0
      IMPORTING et_list      = lt_list
                ev_truncated = l_trunc ).

    l_lines = lines( lt_list ).
    cl_abap_unit_assert=>assert_equals(
      act = l_lines exp = 3 msg = 'UT-12 max 0 -> all rows' ).
    cl_abap_unit_assert=>assert_false(
      act = l_trunc msg = 'UT-12 max 0 -> not truncated' ).
  ENDMETHOD.


  METHOD ut17_list_empty_input.
    DATA lt_mara  TYPE zcl_mm_mtart_matlist=>tt_mara.
    DATA lt_makt  TYPE zcl_mm_mtart_matlist=>tt_makt.
    DATA lt_list  TYPE zcl_mm_mtart_matlist=>tt_list.
    DATA l_trunc  TYPE abap_bool.

    "이전 값이 남지 않는지 확인하려고 미리 채움
    ltd_matdata=>add_list( EXPORTING iv_matnr = ltd_matdata=>c_matnr1
                                     iv_meins = ltd_matdata=>c_meins_st
                           CHANGING  ct_list  = lt_list ).
    l_trunc = abap_true.

    zcl_mm_mtart_matlist=>build_list(
      EXPORTING it_mara      = lt_mara
                it_makt      = lt_makt
                iv_max_rows  = 2
      IMPORTING et_list      = lt_list
                ev_truncated = l_trunc ).

    cl_abap_unit_assert=>assert_initial(
      act = lt_list msg = 'UT-17 empty MARA -> empty list' ).
    cl_abap_unit_assert=>assert_false(
      act = l_trunc msg = 'UT-17 empty MARA -> not truncated' ).
  ENDMETHOD.


  METHOD ut13_make_return_fields.
    DATA ls_return TYPE bapiret2.

    ls_return = zcl_mm_mtart_matlist=>make_return(
                  iv_type   = zcl_mm_mtart_matlist=>c_msgty_error
                  iv_number = zcl_mm_mtart_matlist=>c_msg_invalid
                  iv_v1     = c_v1_zzz9 ).

    "ZMM 338~343 반영 실패 가능성이 있으므로 MESSAGE 텍스트는 비교하지 않음
    cl_abap_unit_assert=>assert_equals(
      act = ls_return-type   exp = zcl_mm_mtart_matlist=>c_msgty_error
      msg = 'UT-13 TYPE E' ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_return-id     exp = c_exp_msgid
      msg = 'UT-13 ID ZMM' ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_return-number exp = c_exp_no_339
      msg = 'UT-13 NUMBER 339' ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_return-message_v1 exp = c_v1_zzz9 msg = 'UT-13 MESSAGE_V1' ).
    cl_abap_unit_assert=>assert_initial(
      act = ls_return-message_v2 msg = 'UT-13 MESSAGE_V2 not supplied' ).
  ENDMETHOD.


  METHOD ut14_execute_guard_no_input.
    DATA lo_cut    TYPE REF TO zcl_mm_mtart_matlist.
    DATA l_mtart   TYPE mtart.                 "공란
    DATA lt_list   TYPE zcl_mm_mtart_matlist=>tt_list.
    DATA l_count   TYPE i.
    DATA ls_return TYPE bapiret2.

    "출력 파라미터를 미리 채워 execute 첫 줄 CLEAR 확인
    ltd_matdata=>add_list( EXPORTING iv_matnr = ltd_matdata=>c_matnr1
                                     iv_meins = ltd_matdata=>c_meins_st
                           CHANGING  ct_list  = lt_list ).
    l_count = 99.

    CREATE OBJECT lo_cut
      EXPORTING
        iv_mtart = l_mtart.

    "입력 누락이면 T134/MARA/MAKT 를 읽기 전에 RETURN (AC-05)
    lo_cut->execute( IMPORTING et_list   = lt_list
                               ev_count  = l_count
                               es_return = ls_return ).

    cl_abap_unit_assert=>assert_initial(
      act = lt_list  msg = 'UT-14 ET_LIST empty' ).
    cl_abap_unit_assert=>assert_equals(
      act = l_count  exp = 0 msg = 'UT-14 EV_COUNT 0' ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_return-type   exp = zcl_mm_mtart_matlist=>c_msgty_error
      msg = 'UT-14 TYPE E' ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_return-id     exp = c_exp_msgid
      msg = 'UT-14 ID ZMM' ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_return-number exp = c_exp_no_338
      msg = 'UT-14 NUMBER 338' ).
  ENDMETHOD.


  METHOD ut15_decide_return_s_and_w.
    DATA ls_return TYPE bapiret2.

    "잘림 아님 -> S ZMM 342 (&1 자재유형, &2 건수)
    ls_return = zcl_mm_mtart_matlist=>decide_return(
                  iv_mtart     = c_mtart_roh
                  iv_count     = 5
                  iv_truncated = abap_false
                  iv_max_rows  = 0 ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_return-type   exp = zcl_mm_mtart_matlist=>c_msgty_success
      msg = 'UT-15 success TYPE S' ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_return-id     exp = c_exp_msgid
      msg = 'UT-15 success ID ZMM' ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_return-number exp = c_exp_no_342
      msg = 'UT-15 success NUMBER 342' ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_return-message_v1 exp = c_v_roh msg = 'UT-15 success V1 MTART' ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_return-message_v2 exp = c_v_5   msg = 'UT-15 success V2 count' ).

    "잘림 -> W ZMM 343 (&1 최대 건수)
    ls_return = zcl_mm_mtart_matlist=>decide_return(
                  iv_mtart     = c_mtart_roh
                  iv_count     = 10
                  iv_truncated = abap_true
                  iv_max_rows  = 10 ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_return-type   exp = zcl_mm_mtart_matlist=>c_msgty_warning
      msg = 'UT-15 truncated TYPE W' ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_return-id     exp = c_exp_msgid
      msg = 'UT-15 truncated ID ZMM' ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_return-number exp = c_exp_no_343
      msg = 'UT-15 truncated NUMBER 343' ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_return-message_v1 exp = c_v_10 msg = 'UT-15 truncated V1 max rows' ).
  ENDMETHOD.


  METHOD ut16_constructor_normalize.
    DATA lo_cut  TYPE REF TO zcl_mm_mtart_matlist.
    DATA l_spras TYPE spras.          "공란
    DATA l_with  TYPE xfeld.
    DATA l_max   TYPE i.

    "소문자·앞 공백, 언어 공란, 'X' 아닌 플래그, 음수 건수
    l_with = 'Y'.
    l_max  = -5.
    CREATE OBJECT lo_cut
      EXPORTING
        iv_mtart        = c_mtart_low
        iv_spras        = l_spras
        iv_with_deleted = l_with
        iv_max_rows     = l_max.

    cl_abap_unit_assert=>assert_equals(
      act = lo_cut->g_mtart exp = c_mtart_roh msg = 'UT-16 G_MTART normalized' ).
    cl_abap_unit_assert=>assert_equals(
      act = lo_cut->g_spras exp = sy-langu    msg = 'UT-16 G_SPRAS = SY-LANGU' ).
    cl_abap_unit_assert=>assert_initial(
      act = lo_cut->g_with_deleted            msg = 'UT-16 non-X flag -> space' ).
    cl_abap_unit_assert=>assert_equals(
      act = lo_cut->g_max_rows exp = 0        msg = 'UT-16 negative -> 0' ).

    "삭제 자재 포함, 언어 지정, 양수 건수
    l_with = abap_true.
    l_max  = 10.
    CREATE OBJECT lo_cut
      EXPORTING
        iv_mtart        = c_mtart_roh
        iv_spras        = c_spras_en
        iv_with_deleted = l_with
        iv_max_rows     = l_max.

    cl_abap_unit_assert=>assert_equals(
      act = lo_cut->g_spras exp = c_spras_en  msg = 'UT-16 G_SPRAS kept' ).
    cl_abap_unit_assert=>assert_equals(
      act = lo_cut->g_with_deleted exp = abap_true msg = 'UT-16 X kept' ).
    cl_abap_unit_assert=>assert_equals(
      act = lo_cut->g_max_rows exp = 10       msg = 'UT-16 positive kept' ).
  ENDMETHOD.


  METHOD ut18_list_type_contract.
*----------------------------------------------------------------------*
* FM Z_MM_GET_MATERIAL_LIST-ET_LIST 가 참조하는 클래스 타입의 계약 확인
* - TY_LIST: 필드 3개, 순서 MATNR -> MAKTX -> MEINS (변경 금지 항목)
* - TT_LIST: STANDARD TABLE, DEFAULT KEY
*----------------------------------------------------------------------*
    DATA ls_list     TYPE zcl_mm_mtart_matlist=>ty_list.
    DATA lt_list     TYPE zcl_mm_mtart_matlist=>tt_list.
    DATA lo_sdescr   TYPE REF TO cl_abap_structdescr.
    DATA lo_tdescr   TYPE REF TO cl_abap_tabledescr.
    DATA ls_comp     TYPE abap_compdescr.
    DATA l_exp_name  LIKE ls_comp-name.
    DATA l_lines     TYPE i.

    lo_sdescr ?= cl_abap_typedescr=>describe_by_data( ls_list ).

    l_lines = lines( lo_sdescr->components ).
    cl_abap_unit_assert=>assert_equals(
      act = l_lines exp = 3 msg = 'UT-18 TY_LIST has 3 fields' ).

    READ TABLE lo_sdescr->components INTO ls_comp INDEX 1.
    l_exp_name = 'MATNR'.
    cl_abap_unit_assert=>assert_equals(
      act = ls_comp-name exp = l_exp_name msg = 'UT-18 field 1 MATNR' ).

    READ TABLE lo_sdescr->components INTO ls_comp INDEX 2.
    l_exp_name = 'MAKTX'.
    cl_abap_unit_assert=>assert_equals(
      act = ls_comp-name exp = l_exp_name msg = 'UT-18 field 2 MAKTX' ).

    READ TABLE lo_sdescr->components INTO ls_comp INDEX 3.
    l_exp_name = 'MEINS'.
    cl_abap_unit_assert=>assert_equals(
      act = ls_comp-name exp = l_exp_name msg = 'UT-18 field 3 MEINS' ).

    lo_tdescr ?= cl_abap_typedescr=>describe_by_data( lt_list ).
    cl_abap_unit_assert=>assert_equals(
      act = lo_tdescr->table_kind exp = cl_abap_tabledescr=>tablekind_std
      msg = 'UT-18 TT_LIST is STANDARD TABLE' ).
    cl_abap_unit_assert=>assert_equals(
      act = lo_tdescr->key_defkind exp = cl_abap_tabledescr=>keydefkind_default
      msg = 'UT-18 TT_LIST has DEFAULT KEY' ).
  ENDMETHOD.


  METHOD ut19_msg_contract_zmm.
*----------------------------------------------------------------------*
* 팀장 지시(개발 재작업 2차): 메시지 클래스 ZMMM3 -> 기존 ZMM 338~343
* 1) 클래스 상수 값이 ZMM / 338~343 인지 (상수 회귀 방지)
* 2) make_return 이 6개 번호 모두 SY-MSGID = ZMM, 해당 번호로 조립하는지
*    (MESSAGE ... INTO 는 텍스트가 없어도 SY-MSGID/MSGNO 를 채운다)
*----------------------------------------------------------------------*
    "1) 상수
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mm_mtart_matlist=>c_msgid exp = c_exp_msgid
      msg = 'UT-19 C_MSGID = ZMM' ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mm_mtart_matlist=>c_msg_no_input exp = c_exp_no_338
      msg = 'UT-19 C_MSG_NO_INPUT = 338' ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mm_mtart_matlist=>c_msg_invalid  exp = c_exp_no_339
      msg = 'UT-19 C_MSG_INVALID = 339' ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mm_mtart_matlist=>c_msg_no_auth  exp = c_exp_no_340
      msg = 'UT-19 C_MSG_NO_AUTH = 340' ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mm_mtart_matlist=>c_msg_no_data  exp = c_exp_no_341
      msg = 'UT-19 C_MSG_NO_DATA = 341' ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mm_mtart_matlist=>c_msg_success  exp = c_exp_no_342
      msg = 'UT-19 C_MSG_SUCCESS = 342' ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mm_mtart_matlist=>c_msg_trunc    exp = c_exp_no_343
      msg = 'UT-19 C_MSG_TRUNC = 343' ).

    "2) make_return 결과 (유형은 execute/decide_return 에서 쓰는 조합)
    assert_return_id_no( iv_type   = zcl_mm_mtart_matlist=>c_msgty_error
                         iv_number = zcl_mm_mtart_matlist=>c_msg_no_input
                         iv_exp_no = c_exp_no_338
                         iv_label  = '338' ).
    assert_return_id_no( iv_type   = zcl_mm_mtart_matlist=>c_msgty_error
                         iv_number = zcl_mm_mtart_matlist=>c_msg_invalid
                         iv_exp_no = c_exp_no_339
                         iv_label  = '339' ).
    assert_return_id_no( iv_type   = zcl_mm_mtart_matlist=>c_msgty_error
                         iv_number = zcl_mm_mtart_matlist=>c_msg_no_auth
                         iv_exp_no = c_exp_no_340
                         iv_label  = '340' ).
    assert_return_id_no( iv_type   = zcl_mm_mtart_matlist=>c_msgty_warning
                         iv_number = zcl_mm_mtart_matlist=>c_msg_no_data
                         iv_exp_no = c_exp_no_341
                         iv_label  = '341' ).
    assert_return_id_no( iv_type   = zcl_mm_mtart_matlist=>c_msgty_success
                         iv_number = zcl_mm_mtart_matlist=>c_msg_success
                         iv_exp_no = c_exp_no_342
                         iv_label  = '342' ).
    assert_return_id_no( iv_type   = zcl_mm_mtart_matlist=>c_msgty_warning
                         iv_number = zcl_mm_mtart_matlist=>c_msg_trunc
                         iv_exp_no = c_exp_no_343
                         iv_label  = '343' ).
  ENDMETHOD.

ENDCLASS.
