*"* use this source file for your ABAP unit test classes
************************************************************************
* 테스트 클래스 : LTC_SCRAP_PRICE_MAIL
* 대상 클래스   : ZCL_MM_SCRAP_PRICE_MAIL (로컬 테스트 인클루드)
* 요청 ID       : 20261019-bce84c
* 작성          : 테스트 담당 (sap-tester) / 2026.10.20
*                 2차 2026.10.20 - 03_development.md 3차 기준 재검토.
*                 3차 2026.10.20 - 03_development.md 4차 기준 재검토.
*                 대상 클래스 소스 변경 없음을 확인하여 테스트 로직 유지
*                 (04_test.md 9장 변경 이력 참고, CR 없음)
*----------------------------------------------------------------------*
* 범위 : 순수 로직만 시험한다.
*   - CHECK_SELECTION / PARSE_ADDRESSES / FORMAT_PRICE / FORMAT_DATE /
*     BUILD_HTML_BODY (public)
*   - ADD_THOUSAND_SEP / IS_VALID_EMAIL / ESCAPE_HTML / ADD_TEXT_LINE
*     (private, LOCAL FRIENDS)
*   - SEND 는 수신자 0건 분기만 시험(BCS 객체 생성 전 RETURN).
*     실제 발송(CL_BCS)은 클래스에 주입 지점이 없어 테스트 더블로
*     바꿀 수 없으므로 통합 테스트(04_test.md IT-10~IT-14)에서 확인한다.
*   - 대상 클래스는 DB 를 읽지 않는다(GT_PR 값만 받음). DB 더블 불필요.
* 명명 : 테스트 클래스·메서드명, 참조 변수(GO_) 는 핸드북 규칙 없음 -
*        SAP 관례. 상수 C_, 지역 L_/LT_/LS_ 는 핸드북 2장 적용.
* 텍스트 심볼 : 대상 클래스 텍스트 풀(H01~H03, B02 등)과 같은 풀을 쓰며,
*        이미지 확인 대기 슬롯(A01~A05, B01, B03, Z01~Z03)은 값이
*        등록되어도 깨지지 않도록 조건부로 단언한다.
* 문법 : ABAP 7.40 SP08 이상(xsdbool, VALUE #, 테이블 식) - 대상 클래스와
*        같은 전제(03_development.md S-05).
************************************************************************
CLASS ltc_scrap_price_mail DEFINITION DEFERRED.
CLASS zcl_mm_scrap_price_mail DEFINITION LOCAL FRIENDS ltc_scrap_price_mail.

CLASS ltc_scrap_price_mail DEFINITION FINAL
  FOR TESTING
  RISK LEVEL HARMLESS
  DURATION SHORT.

  PRIVATE SECTION.

    CONSTANTS:
      c_datab_sample TYPE d VALUE '20260928',   " 시트 설계 C101 적용일자
      c_datab_other  TYPE d VALUE '20261005',
      c_datab_blank  TYPE d VALUE '00000000'.   " 신규 행(유효시작일 미입력)

    DATA go_cut TYPE REF TO zcl_mm_scrap_price_mail.

    METHODS setup.
    METHODS teardown.

*   ---- 시트 규칙 상수 -------------------------------------------------
    METHODS constants_sheet_rule       FOR TESTING.

*   ---- CHECK_SELECTION (FR-03, FR-04) ---------------------------------
    METHODS check_sel_no_row           FOR TESTING.
    METHODS check_sel_single_row       FOR TESTING.
    METHODS check_sel_same_datab       FOR TESTING.
    METHODS check_sel_multi_datab      FOR TESTING.
    METHODS check_sel_blank_datab      FOR TESTING.
    METHODS check_sel_mixed_blank      FOR TESTING.

*   ---- FORMAT_PRICE (FR-08) ------------------------------------------
    METHODS format_price_sheet_sample  FOR TESTING.
    METHODS format_price_thousand_sep  FOR TESTING.
    METHODS format_price_zero          FOR TESTING.
    METHODS format_price_negative      FOR TESTING.
    METHODS format_price_user_fmt_free FOR TESTING.

*   ---- FORMAT_DATE (FR-07 2항) ----------------------------------------
    METHODS format_date_normal         FOR TESTING.
    METHODS format_date_initial        FOR TESTING.

*   ---- BUILD_HTML_BODY (FR-07) ----------------------------------------
    METHODS build_html_sheet_sample    FOR TESTING.
    METHODS build_html_escape          FOR TESTING.
    METHODS build_html_slot_blank      FOR TESTING.
    METHODS build_html_no_item         FOR TESTING.

*   ---- PARSE_ADDRESSES (FR-05, FR-06) ---------------------------------
    METHODS parse_addr_single          FOR TESTING.
    METHODS parse_addr_multi_sep       FOR TESTING.
    METHODS parse_addr_blank           FOR TESTING.
    METHODS parse_addr_invalid         FOR TESTING.
    METHODS parse_addr_mixed_invalid   FOR TESTING.
    METHODS parse_addr_duplicate       FOR TESTING.

*   ---- SEND (FR-09, FR-10) - BCS 호출 전 분기만 ------------------------
    METHODS send_no_recipient          FOR TESTING.

*   ---- private (LOCAL FRIENDS) ----------------------------------------
    METHODS thousand_sep_boundary      FOR TESTING.
    METHODS is_valid_email_cases       FOR TESTING.
    METHODS is_valid_email_max_len     FOR TESTING.
    METHODS escape_html_special        FOR TESTING.
    METHODS add_text_line_blank        FOR TESTING.

*   ---- 보조 ------------------------------------------------------------
    METHODS add_item
      IMPORTING
        iv_grade TYPE string
        iv_price TYPE string
        iv_datab TYPE d
      CHANGING
        ct_item  TYPE zcl_mm_scrap_price_mail=>tt_item.

    METHODS get_sheet_sample
      RETURNING
        VALUE(rt_item) TYPE zcl_mm_scrap_price_mail=>tt_item.

    METHODS assert_contains
      IMPORTING
        iv_text TYPE string
        iv_sub  TYPE string
        iv_msg  TYPE string OPTIONAL.

ENDCLASS.



CLASS ltc_scrap_price_mail IMPLEMENTATION.

  METHOD setup.
    CREATE OBJECT go_cut.
  ENDMETHOD.


  METHOD teardown.
*   FORMAT_PRICE_USER_FMT_FREE 에서 바꾼 국가 형식 복원
    SET COUNTRY space.
    CLEAR go_cut.
  ENDMETHOD.


*======================================================================*
* 보조 메서드
*======================================================================*
  METHOD add_item.

    DATA ls_item TYPE zcl_mm_scrap_price_mail=>ty_item.

    ls_item-grade_txt = iv_grade.
    ls_item-price     = iv_price.          " 문자 -> DANGA(p) 변환
    ls_item-datab     = iv_datab.
    APPEND ls_item TO ct_item.

  ENDMETHOD.


  METHOD get_sheet_sample.
*   시트 설계 C96~D99 샘플 4건 (DANGA 내부값 = 메일 표시값 / 100)
    add_item( EXPORTING iv_grade = `생철AL`          iv_price = `4.70`
                        iv_datab = c_datab_sample CHANGING ct_item = rt_item ).
    add_item( EXPORTING iv_grade = `생철A`           iv_price = `4.70`
                        iv_datab = c_datab_sample CHANGING ct_item = rt_item ).
    add_item( EXPORTING iv_grade = `주물A(모터블럭)` iv_price = `4.70`
                        iv_datab = c_datab_sample CHANGING ct_item = rt_item ).
    add_item( EXPORTING iv_grade = `생철B`           iv_price = `4.65`
                        iv_datab = c_datab_sample CHANGING ct_item = rt_item ).
  ENDMETHOD.


  METHOD assert_contains.

    DATA l_msg TYPE string.

    l_msg = iv_msg.
    IF l_msg IS INITIAL.
      l_msg = |본문에 [{ iv_sub }] 이(가) 없음|.
    ENDIF.

    cl_abap_unit_assert=>assert_true(
      act = xsdbool( find( val = iv_text sub = iv_sub ) >= 0 )
      msg = l_msg ).

  ENDMETHOD.


*======================================================================*
* 상수 - 시트 설계 C110(x100), C96~D99(소수 1자리), 메시지 클래스
*======================================================================*
  METHOD constants_sheet_rule.

    cl_abap_unit_assert=>assert_equals(
      act = zcl_mm_scrap_price_mail=>c_price_factor exp = 100
      msg = '단가 계수는 시트 C110 기준 100' ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mm_scrap_price_mail=>c_price_dec exp = 1
      msg = '단가 소수 자리는 샘플 470.0 기준 1' ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_mm_scrap_price_mail=>c_msgid exp = 'ZMMM3'
      msg = '메시지 클래스 ZMMM3' ).

  ENDMETHOD.


*======================================================================*
* CHECK_SELECTION
*======================================================================*
  METHOD check_sel_no_row.
*   UT-02 / 설계 T01 - 시트 C59 최소 1행

    DATA: lt_item  TYPE zcl_mm_scrap_price_mail=>tt_item,
          l_datab  TYPE d,
          l_msgno  TYPE symsgno.

    l_datab = c_datab_other.     " 이전 값이 지워지는지 확인
    l_msgno = go_cut->check_selection( EXPORTING it_item  = lt_item
                                       IMPORTING ev_datab = l_datab ).

    cl_abap_unit_assert=>assert_equals(
      act = l_msgno exp = zcl_mm_scrap_price_mail=>c_msgno_no_row ).
    cl_abap_unit_assert=>assert_initial( act = l_datab ).

  ENDMETHOD.


  METHOD check_sel_single_row.
*   UT-03 경계 - 1건

    DATA: lt_item  TYPE zcl_mm_scrap_price_mail=>tt_item,
          l_datab  TYPE d,
          l_msgno  TYPE symsgno.

    add_item( EXPORTING iv_grade = `생철AL` iv_price = `4.70`
                        iv_datab = c_datab_sample CHANGING ct_item = lt_item ).

    l_msgno = go_cut->check_selection( EXPORTING it_item  = lt_item
                                       IMPORTING ev_datab = l_datab ).

    cl_abap_unit_assert=>assert_initial( act = l_msgno ).
    cl_abap_unit_assert=>assert_equals( act = l_datab exp = c_datab_sample ).

  ENDMETHOD.


  METHOD check_sel_same_datab.
*   UT-04 / 설계 T02 - 시트 샘플 4건, 같은 유효시작일

    DATA: lt_item  TYPE zcl_mm_scrap_price_mail=>tt_item,
          l_datab  TYPE d,
          l_msgno  TYPE symsgno.

    lt_item = get_sheet_sample( ).

    l_msgno = go_cut->check_selection( EXPORTING it_item  = lt_item
                                       IMPORTING ev_datab = l_datab ).

    cl_abap_unit_assert=>assert_initial( act = l_msgno ).
    cl_abap_unit_assert=>assert_equals( act = l_datab exp = c_datab_sample ).

  ENDMETHOD.


  METHOD check_sel_multi_datab.
*   UT-05 / 설계 T03 - 시트 C60~C61 유효시작일 2종

    DATA: lt_item  TYPE zcl_mm_scrap_price_mail=>tt_item,
          l_datab  TYPE d,
          l_msgno  TYPE symsgno.

    lt_item = get_sheet_sample( ).
    add_item( EXPORTING iv_grade = `경량B` iv_price = `3.00`
                        iv_datab = c_datab_other CHANGING ct_item = lt_item ).

    l_msgno = go_cut->check_selection( EXPORTING it_item  = lt_item
                                       IMPORTING ev_datab = l_datab ).

    cl_abap_unit_assert=>assert_equals(
      act = l_msgno exp = zcl_mm_scrap_price_mail=>c_msgno_multi_datab ).
    cl_abap_unit_assert=>assert_initial(
      act = l_datab msg = '오류 시 적용일자를 돌려주면 안 됨' ).

  ENDMETHOD.


  METHOD check_sel_blank_datab.
*   UT-06 경계 - 유효시작일 공란 행끼리(신규 행, U-06 기본값 '차단 없음')
*   현재 구현은 통과시킨다. U-06 결정이 '차단'으로 바뀌면 기대값 변경.

    DATA: lt_item  TYPE zcl_mm_scrap_price_mail=>tt_item,
          l_datab  TYPE d,
          l_msgno  TYPE symsgno.

    add_item( EXPORTING iv_grade = `생철AL` iv_price = `4.70`
                        iv_datab = c_datab_blank CHANGING ct_item = lt_item ).
    add_item( EXPORTING iv_grade = `생철A`  iv_price = `4.70`
                        iv_datab = c_datab_blank CHANGING ct_item = lt_item ).

    l_msgno = go_cut->check_selection( EXPORTING it_item  = lt_item
                                       IMPORTING ev_datab = l_datab ).

    cl_abap_unit_assert=>assert_initial( act = l_msgno ).
    cl_abap_unit_assert=>assert_initial( act = l_datab ).

  ENDMETHOD.


  METHOD check_sel_mixed_blank.
*   UT-07 경계 - 공란 + 날짜 혼합은 002

    DATA: lt_item  TYPE zcl_mm_scrap_price_mail=>tt_item,
          l_datab  TYPE d,
          l_msgno  TYPE symsgno.

    add_item( EXPORTING iv_grade = `생철AL` iv_price = `4.70`
                        iv_datab = c_datab_sample CHANGING ct_item = lt_item ).
    add_item( EXPORTING iv_grade = `생철A`  iv_price = `4.70`
                        iv_datab = c_datab_blank CHANGING ct_item = lt_item ).

    l_msgno = go_cut->check_selection( EXPORTING it_item  = lt_item
                                       IMPORTING ev_datab = l_datab ).

    cl_abap_unit_assert=>assert_equals(
      act = l_msgno exp = zcl_mm_scrap_price_mail=>c_msgno_multi_datab ).

  ENDMETHOD.


*======================================================================*
* FORMAT_PRICE - 시트 C110(x100), C111(천 단위 콤마), 샘플 470.0
*======================================================================*
  METHOD format_price_sheet_sample.
*   UT-08 / 설계 T04

    DATA l_price TYPE zcl_mm_scrap_price_mail=>ty_item-price.

    l_price = '4.70'.
    cl_abap_unit_assert=>assert_equals(
      act = go_cut->format_price( l_price ) exp = `470.0` ).

    l_price = '4.65'.
    cl_abap_unit_assert=>assert_equals(
      act = go_cut->format_price( l_price ) exp = `465.0` ).

  ENDMETHOD.


  METHOD format_price_thousand_sep.
*   UT-09 / 설계 T04, 7.3 - 천 단위 콤마 경계(3자리, 4자리, 6자리)

    DATA l_price TYPE zcl_mm_scrap_price_mail=>ty_item-price.

    l_price = '9.99'.
    cl_abap_unit_assert=>assert_equals(
      act = go_cut->format_price( l_price ) exp = `999.0`
      msg = '3자리는 콤마 없음' ).

    l_price = '12.35'.
    cl_abap_unit_assert=>assert_equals(
      act = go_cut->format_price( l_price ) exp = `1,235.0` ).

    l_price = '1234.56'.
    cl_abap_unit_assert=>assert_equals(
      act = go_cut->format_price( l_price ) exp = `123,456.0` ).

  ENDMETHOD.


  METHOD format_price_zero.
*   UT-10 경계 - 0 (신규 행 단가 미입력, U-06)

    DATA l_price TYPE zcl_mm_scrap_price_mail=>ty_item-price.

    CLEAR l_price.
    cl_abap_unit_assert=>assert_equals(
      act = go_cut->format_price( l_price ) exp = `0.0` ).

  ENDMETHOD.


  METHOD format_price_negative.
*   UT-11 경계 - 음수 (정상 업무값은 아니나 표시 깨짐 방지)

    DATA l_price TYPE zcl_mm_scrap_price_mail=>ty_item-price.

    l_price = '-12.35'.
    cl_abap_unit_assert=>assert_equals(
      act = go_cut->format_price( l_price ) exp = `-1,235.0` ).

  ENDMETHOD.


  METHOD format_price_user_fmt_free.
*   UT-12 / 설계 T05 - 국가(사용자) 숫자 형식과 무관

    DATA: l_price TYPE zcl_mm_scrap_price_mail=>ty_item-price,
          l_text  TYPE string.

    l_price = '1234.56'.
    SET COUNTRY 'DE'.                 " 1.234,56 형식 국가
    l_text = go_cut->format_price( l_price ).
    SET COUNTRY space.

    cl_abap_unit_assert=>assert_equals( act = l_text exp = `123,456.0` ).

  ENDMETHOD.


*======================================================================*
* FORMAT_DATE - 시트 C101 "2026.09.28"
*======================================================================*
  METHOD format_date_normal.
*   UT-13 / 설계 T06
    cl_abap_unit_assert=>assert_equals(
      act = go_cut->format_date( c_datab_sample ) exp = `2026.09.28` ).
  ENDMETHOD.


  METHOD format_date_initial.
*   UT-14 경계 - 초기 날짜는 공란
    cl_abap_unit_assert=>assert_initial(
      act = go_cut->format_date( c_datab_blank ) ).
  ENDMETHOD.


*======================================================================*
* BUILD_HTML_BODY - 시트 C79~C103
*======================================================================*
  METHOD build_html_sheet_sample.
*   UT-15 / 설계 T07 - 샘플 4건, 적용일자 2026.09.28

    DATA: lt_item TYPE zcl_mm_scrap_price_mail=>tt_item,
          l_html  TYPE string,
          l_b03   TYPE string.

    lt_item = get_sheet_sample( ).
    l_html  = go_cut->build_html_body( it_item  = lt_item
                                       iv_datab = c_datab_sample ).

*   머리/꼬리
    cl_abap_unit_assert=>assert_equals(
      act = substring( val = l_html len = 6 ) exp = `<html>` ).
    assert_contains( iv_text = l_html iv_sub = `<meta charset="utf-8">` ).
    assert_contains( iv_text = l_html iv_sub = `</table>` ).
    assert_contains( iv_text = l_html iv_sub = `</body></html>` ).

*   1항 + 표 헤더 (C95~E95)
    assert_contains( iv_text = l_html iv_sub = `>1. ` ).
    assert_contains( iv_text = l_html iv_sub = `>등급</th>` ).
    assert_contains( iv_text = l_html iv_sub = `>단가</th>` ).
    assert_contains( iv_text = l_html iv_sub = `>비고</th>` ).

*   표 행 4건 (C96~D99), 순서 유지, 비고 공란 = &nbsp;
    cl_abap_unit_assert=>assert_equals(
      act = count( val = l_html sub = `<tr><td>` ) exp = 4
      msg = '선택 행 수만큼 표 행 생성' ).
    assert_contains( iv_text = l_html
      iv_sub = `<tr><td>생철AL</td><td style="text-align:right">470.0</td><td>&nbsp;</td></tr>` ).
    assert_contains( iv_text = l_html
      iv_sub = `<tr><td>주물A(모터블럭)</td><td style="text-align:right">470.0</td>` ).
    assert_contains( iv_text = l_html
      iv_sub = `<tr><td>생철B</td><td style="text-align:right">465.0</td>` ).
    cl_abap_unit_assert=>assert_true(
      act = xsdbool( find( val = l_html sub = `생철AL` ) <
                     find( val = l_html sub = `생철B` ) )
      msg = '행 순서는 선택(ALV) 순서' ).

*   2항 (C101)
    assert_contains( iv_text = l_html iv_sub = `2. 적용일자: 2026.09.28` ).

*   3항 (C103) - 슬롯 B03 공란이면 줄 없음
    l_b03 = condense( TEXT-b03 ).
    IF l_b03 IS INITIAL.
      cl_abap_unit_assert=>assert_equals(
        act = find( val = l_html sub = `>3. ` ) exp = -1
        msg = 'B03 공란이면 3항 줄 생략' ).
    ELSE.
      assert_contains( iv_text = l_html iv_sub = `>3. ` ).
    ENDIF.

  ENDMETHOD.


  METHOD build_html_escape.
*   UT-16 / 설계 T08 - 등급명 특수문자 이스케이프

    DATA: lt_item TYPE zcl_mm_scrap_price_mail=>tt_item,
          l_html  TYPE string.

    add_item( EXPORTING iv_grade = `<A&B>` iv_price = `4.70`
                        iv_datab = c_datab_sample CHANGING ct_item = lt_item ).

    l_html = go_cut->build_html_body( it_item  = lt_item
                                      iv_datab = c_datab_sample ).

    assert_contains( iv_text = l_html iv_sub = `<td>&lt;A&amp;B&gt;</td>` ).
    cl_abap_unit_assert=>assert_equals(
      act = find( val = l_html sub = `<A&B>` ) exp = -1
      msg = '원문 특수문자가 그대로 남으면 안 됨' ).

  ENDMETHOD.


  METHOD build_html_slot_blank.
*   UT-17 / 설계 T18 - 문구 슬롯(A01~A05, Z01~Z03) 값 있는 줄만 출력

    DATA: lt_item TYPE zcl_mm_scrap_price_mail=>tt_item,
          lt_slot TYPE STANDARD TABLE OF string WITH EMPTY KEY,
          l_html  TYPE string,
          l_exp   TYPE i.

    lt_item = get_sheet_sample( ).
    l_html  = go_cut->build_html_body( it_item  = lt_item
                                       iv_datab = c_datab_sample ).

    lt_slot = VALUE #( ( condense( TEXT-a01 ) ) ( condense( TEXT-a02 ) )
                       ( condense( TEXT-a03 ) ) ( condense( TEXT-a04 ) )
                       ( condense( TEXT-a05 ) ) ( condense( TEXT-z01 ) )
                       ( condense( TEXT-z02 ) ) ( condense( TEXT-z03 ) ) ).
    DELETE lt_slot WHERE table_line IS INITIAL.

*   "1." 단락 1개 + 값 있는 슬롯 수
    l_exp = 1 + lines( lt_slot ).
    cl_abap_unit_assert=>assert_equals(
      act = count( val = l_html sub = `<p style="margin:0 0 6px 0">` )
      exp = l_exp
      msg = '공란 슬롯은 줄을 만들지 않음' ).

  ENDMETHOD.


  METHOD build_html_no_item.
*   UT-18 경계 - 0건(화면에서는 CHECK_SELECTION 001 로 막힘)

    DATA: lt_item TYPE zcl_mm_scrap_price_mail=>tt_item,
          l_html  TYPE string.

    l_html = go_cut->build_html_body( it_item  = lt_item
                                      iv_datab = c_datab_sample ).

    cl_abap_unit_assert=>assert_equals(
      act = count( val = l_html sub = `<tr><td>` ) exp = 0 ).
    assert_contains( iv_text = l_html iv_sub = `</table>` ).

  ENDMETHOD.


*======================================================================*
* PARSE_ADDRESSES - 시트 C63, 시트 외 X-2/X-3
*======================================================================*
  METHOD parse_addr_single.
*   UT-19 / 설계 T09

    DATA: lt_addr    TYPE zcl_mm_scrap_price_mail=>tt_addr,
          l_invalid  TYPE string,
          l_msgno    TYPE symsgno.

    l_msgno = go_cut->parse_addresses( EXPORTING iv_text    = '  User01@Example.com  '
                                       IMPORTING et_addr    = lt_addr
                                                 ev_invalid = l_invalid ).

    cl_abap_unit_assert=>assert_initial( act = l_msgno ).
    cl_abap_unit_assert=>assert_initial( act = l_invalid ).
    cl_abap_unit_assert=>assert_equals( act = lines( lt_addr ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals(
      act = lt_addr[ 1 ] exp = 'User01@Example.com'
      msg = '대소문자 보존(화면 Lower case 속성과 함께 IT-10 확인)' ).

  ENDMETHOD.


  METHOD parse_addr_multi_sep.
*   UT-20 / 설계 T09 - ';' ',' 공백 구분

    DATA: lt_addr    TYPE zcl_mm_scrap_price_mail=>tt_addr,
          l_invalid  TYPE string,
          l_msgno    TYPE symsgno.

    l_msgno = go_cut->parse_addresses(
                EXPORTING iv_text    = 'a@x.com; b@y.co.kr,c@dong-kuk.com d@z.net'
                IMPORTING et_addr    = lt_addr
                          ev_invalid = l_invalid ).

    cl_abap_unit_assert=>assert_initial( act = l_msgno ).
    cl_abap_unit_assert=>assert_equals( act = lines( lt_addr ) exp = 4 ).
    cl_abap_unit_assert=>assert_equals( act = lt_addr[ 2 ] exp = 'b@y.co.kr' ).
    cl_abap_unit_assert=>assert_equals(
      act = lt_addr[ 3 ] exp = 'c@dong-kuk.com'
      msg = '도메인 하이픈 허용(정규식 [\-] 해석 확인)' ).

  ENDMETHOD.


  METHOD parse_addr_blank.
*   UT-21 / 설계 T09 - 공란, 구분자만 -> 003

    DATA: lt_addr    TYPE zcl_mm_scrap_price_mail=>tt_addr,
          l_invalid  TYPE string,
          l_msgno    TYPE symsgno.

    l_msgno = go_cut->parse_addresses( EXPORTING iv_text    = ''
                                       IMPORTING et_addr    = lt_addr
                                                 ev_invalid = l_invalid ).
    cl_abap_unit_assert=>assert_equals(
      act = l_msgno exp = zcl_mm_scrap_price_mail=>c_msgno_no_addr ).
    cl_abap_unit_assert=>assert_initial( act = lt_addr ).

    l_msgno = go_cut->parse_addresses( EXPORTING iv_text    = ' ; , ;'
                                       IMPORTING et_addr    = lt_addr
                                                 ev_invalid = l_invalid ).
    cl_abap_unit_assert=>assert_equals(
      act = l_msgno exp = zcl_mm_scrap_price_mail=>c_msgno_no_addr ).

  ENDMETHOD.


  METHOD parse_addr_invalid.
*   UT-22 / 설계 T09 - 형식 오류 -> 004, 잘못된 주소 반환

    DATA: lt_addr    TYPE zcl_mm_scrap_price_mail=>tt_addr,
          l_invalid  TYPE string,
          l_msgno    TYPE symsgno.

    l_msgno = go_cut->parse_addresses( EXPORTING iv_text    = 'abc'
                                       IMPORTING et_addr    = lt_addr
                                                 ev_invalid = l_invalid ).
    cl_abap_unit_assert=>assert_equals(
      act = l_msgno exp = zcl_mm_scrap_price_mail=>c_msgno_invalid_addr ).
    cl_abap_unit_assert=>assert_equals( act = l_invalid exp = `abc` ).

    l_msgno = go_cut->parse_addresses( EXPORTING iv_text    = 'a@b'
                                       IMPORTING et_addr    = lt_addr
                                                 ev_invalid = l_invalid ).
    cl_abap_unit_assert=>assert_equals(
      act = l_msgno exp = zcl_mm_scrap_price_mail=>c_msgno_invalid_addr
      msg = '최상위 도메인 없는 주소는 오류' ).

  ENDMETHOD.


  METHOD parse_addr_mixed_invalid.
*   UT-23 - 정상+오류 혼합: 형식 오류 우선(004), 오류 주소만 ';' 로 연결

    DATA: lt_addr    TYPE zcl_mm_scrap_price_mail=>tt_addr,
          l_invalid  TYPE string,
          l_msgno    TYPE symsgno.

    l_msgno = go_cut->parse_addresses( EXPORTING iv_text    = 'a@x.com;abc;def@'
                                       IMPORTING et_addr    = lt_addr
                                                 ev_invalid = l_invalid ).

    cl_abap_unit_assert=>assert_equals(
      act = l_msgno exp = zcl_mm_scrap_price_mail=>c_msgno_invalid_addr ).
    cl_abap_unit_assert=>assert_equals( act = l_invalid exp = `abc;def@` ).
    cl_abap_unit_assert=>assert_equals( act = lines( lt_addr ) exp = 1 ).

  ENDMETHOD.


  METHOD parse_addr_duplicate.
*   UT-24 / 설계 T09 - 같은 주소 중복 입력은 1건

    DATA: lt_addr    TYPE zcl_mm_scrap_price_mail=>tt_addr,
          l_invalid  TYPE string,
          l_msgno    TYPE symsgno.

    l_msgno = go_cut->parse_addresses( EXPORTING iv_text    = 'a@x.com;a@x.com'
                                       IMPORTING et_addr    = lt_addr
                                                 ev_invalid = l_invalid ).

    cl_abap_unit_assert=>assert_initial( act = l_msgno ).
    cl_abap_unit_assert=>assert_equals( act = lines( lt_addr ) exp = 1 ).

  ENDMETHOD.


*======================================================================*
* SEND - 수신자 0건 분기 (BCS 객체 생성/COMMIT 없음)
*======================================================================*
  METHOD send_no_recipient.
*   UT-25

    DATA: lt_to    TYPE zcl_mm_scrap_price_mail=>tt_addr,
          l_error  TYPE string,
          l_ok     TYPE abap_bool.

    l_ok = go_cut->send( EXPORTING it_to    = lt_to
                                   iv_html  = `<html></html>`
                         IMPORTING ev_error = l_error ).

    cl_abap_unit_assert=>assert_false( act = l_ok ).
    cl_abap_unit_assert=>assert_not_initial(
      act = l_error msg = '실패 사유(006 &1)가 비면 안 됨' ).
    cl_abap_unit_assert=>assert_equals(
      act = sy-msgid exp = zcl_mm_scrap_price_mail=>c_msgid ).
    cl_abap_unit_assert=>assert_equals(
      act = sy-msgno exp = zcl_mm_scrap_price_mail=>c_msgno_no_addr ).

  ENDMETHOD.


*======================================================================*
* private (LOCAL FRIENDS)
*======================================================================*
  METHOD thousand_sep_boundary.
*   UT-26 - 0/1/3/4/6/7자리

    cl_abap_unit_assert=>assert_equals(
      act = go_cut->add_thousand_sep( `` )        exp = `` ).
    cl_abap_unit_assert=>assert_equals(
      act = go_cut->add_thousand_sep( `0` )       exp = `0` ).
    cl_abap_unit_assert=>assert_equals(
      act = go_cut->add_thousand_sep( `470` )     exp = `470` ).
    cl_abap_unit_assert=>assert_equals(
      act = go_cut->add_thousand_sep( `1235` )    exp = `1,235` ).
    cl_abap_unit_assert=>assert_equals(
      act = go_cut->add_thousand_sep( `123456` )  exp = `123,456` ).
    cl_abap_unit_assert=>assert_equals(
      act = go_cut->add_thousand_sep( `1234567` ) exp = `1,234,567` ).

  ENDMETHOD.


  METHOD is_valid_email_cases.
*   UT-27 - 정규식 형식 검사

    cl_abap_unit_assert=>assert_true(
      act = go_cut->is_valid_email( 'user.name+tag@dongkuk.co.kr' ) ).
    cl_abap_unit_assert=>assert_true(
      act = go_cut->is_valid_email( 'a_b-c@sub.dong-kuk.com' )
      msg = '로컬부/도메인 하이픈 허용' ).
    cl_abap_unit_assert=>assert_false(
      act = go_cut->is_valid_email( 'abc' ) ).
    cl_abap_unit_assert=>assert_false(
      act = go_cut->is_valid_email( 'a@@x.com' ) ).
    cl_abap_unit_assert=>assert_false(
      act = go_cut->is_valid_email( 'a@x.c' )
      msg = '최상위 도메인 2자 이상' ).
    cl_abap_unit_assert=>assert_false(
      act = go_cut->is_valid_email( `` ) ).

  ENDMETHOD.


  METHOD is_valid_email_max_len.
*   UT-28 경계 - AD_SMTPADR 241자

    DATA l_addr TYPE string.

    l_addr = repeat( val = `a` occ = 235 ) && `@x.com`.     " 241자
    cl_abap_unit_assert=>assert_true(
      act = go_cut->is_valid_email( l_addr ) msg = '241자는 허용' ).

    l_addr = repeat( val = `a` occ = 236 ) && `@x.com`.     " 242자
    cl_abap_unit_assert=>assert_false(
      act = go_cut->is_valid_email( l_addr ) msg = '242자는 거부' ).

  ENDMETHOD.


  METHOD escape_html_special.
*   UT-29

    cl_abap_unit_assert=>assert_equals(
      act = go_cut->escape_html( `<A&B>` ) exp = `&lt;A&amp;B&gt;` ).
    cl_abap_unit_assert=>assert_equals(
      act = go_cut->escape_html( `주물A(모터블럭)` ) exp = `주물A(모터블럭)`
      msg = '한글·괄호는 그대로' ).

  ENDMETHOD.


  METHOD add_text_line_blank.
*   UT-30 - 공란은 생략, 값은 <p> + 이스케이프

    DATA l_html TYPE string.

    go_cut->add_text_line( EXPORTING iv_text = '   ' CHANGING cv_html = l_html ).
    cl_abap_unit_assert=>assert_initial( act = l_html ).

    go_cut->add_text_line( EXPORTING iv_text = 'A&B' CHANGING cv_html = l_html ).
    cl_abap_unit_assert=>assert_equals(
      act = l_html exp = `<p style="margin:0 0 6px 0">A&amp;B</p>` ).

  ENDMETHOD.

ENDCLASS.
