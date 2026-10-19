************************************************************************
* 클래스명      : ZCL_MM_SCRAP_PRICE_MAIL
* 패키지        : $TMP (설계 U-12 기본값. 재지정 시 ZMMD)
* 설명          : 고철등급별 단가(ZEMM2222) 공문 메일 생성/발송
* 사용 프로그램 : SAPMZMM2222 (MZMM2222F01 MAIL_PROCESS 등)
* 요청 ID       : 20261019-bce84c
* 작성일자      : 2026.10.19 / 2차 2026.10.20 대상 ZEMM2222 전환
*                 (클래스 로직 변경 없음, 주석만 변경)
*----------------------------------------------------------------------*
* 메서드 파라미터 접두어(IV_/IT_/EV_/ET_/RV_/CV_)는 핸드북 규칙 없음 -
* SAP 관례 적용. 지역 변수는 핸드북 L_/LT_/LS_ 규칙 적용.
*----------------------------------------------------------------------*
* 텍스트 심볼 (SE24 > 텍스트 요소, 로그온 언어 KO)
*   S01 국내스크랩 기본단가 공문          (메일 제목, 가안 U-03)
*   H01 등급 / H02 단가 / H03 비고         (시트 설계 C95~E95)
*   B02 2. 적용일자:                       (시트 설계 C101, 뒤 공백은 코드에서)
*   E01 BCS 발송 요청이 처리되지 않았습니다 (SEND 결과 FALSE 시 사유)
*   A01~A05, B01, B03, Z01~Z03            (메일 양식 이미지 확인 대기 슬롯,
*                                          미생성 = 공란 = 줄 생략, U-02)
************************************************************************
CLASS zcl_mm_scrap_price_mail DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    TYPES:
      BEGIN OF ty_item,
        grade_txt TYPE ztmm0014-btext,   " 고철등급명 (GT_PR-BTEXT)
        price     TYPE ztmm0015-danga,   " ALV 단가 내부값 (GT_PR-DANGA)
        remark    TYPE c LENGTH 100,     " 비고 (GT_PR에 없음 - 항상 공란)
        datab     TYPE ztmm0015-datab,   " 유효시작일 (GT_PR-DATAB)
      END OF ty_item,
      tt_item TYPE STANDARD TABLE OF ty_item WITH DEFAULT KEY,
      tt_addr TYPE STANDARD TABLE OF ad_smtpadr WITH DEFAULT KEY.

    CONSTANTS:
      c_msgid              TYPE symsgid VALUE 'ZMMM3',
      c_msgno_no_row       TYPE symsgno VALUE '001',
      c_msgno_multi_datab  TYPE symsgno VALUE '002',
      c_msgno_no_addr      TYPE symsgno VALUE '003',
      c_msgno_invalid_addr TYPE symsgno VALUE '004',
      c_msgno_sent         TYPE symsgno VALUE '005',
      c_msgno_send_error   TYPE symsgno VALUE '006',
      c_price_factor       TYPE i VALUE 100,  " 시트 C110. 미결 U-01 답변 시 변경
      c_price_dec          TYPE i VALUE 1.    " 시트 C96~D99 샘플 470.0 기준

    "! 선택 행 검증: 0건(001), 유효시작일 2종 이상(002)
    METHODS check_selection
      IMPORTING
        it_item         TYPE tt_item
      EXPORTING
        ev_datab        TYPE d
      RETURNING
        VALUE(rv_msgno) TYPE symsgno.

    "! 입력창 메일주소 분리/검증: 공란(003), 형식 오류(004)
    METHODS parse_addresses
      IMPORTING
        iv_text         TYPE csequence
      EXPORTING
        et_addr         TYPE tt_addr
        ev_invalid      TYPE string
      RETURNING
        VALUE(rv_msgno) TYPE symsgno.

    "! 단가 표시: x C_PRICE_FACTOR, 소수 C_PRICE_DEC 자리, 천 단위 콤마
    METHODS format_price
      IMPORTING
        iv_price       TYPE ty_item-price
      RETURNING
        VALUE(rv_text) TYPE string.

    "! 날짜 표시: YYYY.MM.DD
    METHODS format_date
      IMPORTING
        iv_date        TYPE d
      RETURNING
        VALUE(rv_text) TYPE string.

    "! 공문 메일 HTML 본문 생성
    METHODS build_html_body
      IMPORTING
        it_item        TYPE tt_item
        iv_datab       TYPE d
      RETURNING
        VALUE(rv_html) TYPE string.

    "! BCS 메일 발송 (성공 시 COMMIT WORK, 실패 시 ROLLBACK WORK)
    METHODS send
      IMPORTING
        it_to        TYPE tt_addr
        iv_html      TYPE string
      EXPORTING
        ev_error     TYPE string
      RETURNING
        VALUE(rv_ok) TYPE abap_bool.

  PROTECTED SECTION.

  PRIVATE SECTION.

    CONSTANTS:
      c_doc_type     TYPE so_obj_tp VALUE 'HTM',
      c_max_addr_len TYPE i VALUE 241,
      c_addr_sep     TYPE c LENGTH 1 VALUE ';',
      c_addr_trans   TYPE c LENGTH 4 VALUE ',; ;',
      c_regex_mail   TYPE string
        VALUE '^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$'.

    METHODS add_text_line
      IMPORTING
        iv_text TYPE csequence
      CHANGING
        cv_html TYPE string.

    METHODS is_valid_email
      IMPORTING
        iv_addr         TYPE csequence
      RETURNING
        VALUE(rv_valid) TYPE abap_bool.

    METHODS add_thousand_sep
      IMPORTING
        iv_digits      TYPE string
      RETURNING
        VALUE(rv_text) TYPE string.

    METHODS escape_html
      IMPORTING
        iv_text        TYPE csequence
      RETURNING
        VALUE(rv_text) TYPE string.

ENDCLASS.



CLASS zcl_mm_scrap_price_mail IMPLEMENTATION.


  METHOD check_selection.

    DATA: ls_item  TYPE ty_item,
          l_datab  TYPE d.

    CLEAR: ev_datab, rv_msgno.

*   시트 설계 C59 - 최소 1행 선택
    IF it_item IS INITIAL.
      rv_msgno = c_msgno_no_row.
      RETURN.
    ENDIF.

*   시트 설계 C60~C61 - 유효시작일이 다른 행 다중 선택 불가
    READ TABLE it_item INTO ls_item INDEX 1.
    l_datab = ls_item-datab.

    LOOP AT it_item INTO ls_item.
      IF ls_item-datab <> l_datab.
        rv_msgno = c_msgno_multi_datab.
        RETURN.
      ENDIF.
    ENDLOOP.

    ev_datab = l_datab.

  ENDMETHOD.


  METHOD parse_addresses.

    DATA: l_text    TYPE string,
          lt_part   TYPE STANDARD TABLE OF string WITH DEFAULT KEY,
          l_part    TYPE string,
          l_addr    TYPE ad_smtpadr.

    CLEAR: et_addr, ev_invalid, rv_msgno.

*   ',' 와 공백을 ';' 로 통일 후 분리 (시트 외 X-3)
    l_text = iv_text.
    TRANSLATE l_text USING c_addr_trans.
    SPLIT l_text AT c_addr_sep INTO TABLE lt_part.

    LOOP AT lt_part INTO l_part.
      l_part = condense( l_part ).
      IF l_part IS INITIAL.
        CONTINUE.
      ENDIF.

      IF is_valid_email( l_part ) = abap_false.
        IF ev_invalid IS INITIAL.
          ev_invalid = l_part.
        ELSE.
          ev_invalid = |{ ev_invalid }{ c_addr_sep }{ l_part }|.
        ENDIF.
        CONTINUE.
      ENDIF.

      l_addr = l_part.
      IF line_exists( et_addr[ table_line = l_addr ] ).
        CONTINUE.
      ENDIF.
      APPEND l_addr TO et_addr.
    ENDLOOP.

*   시트 외 X-2 - 형식 오류 우선, 다음 공란
    IF ev_invalid IS NOT INITIAL.
      rv_msgno = c_msgno_invalid_addr.
    ELSEIF et_addr IS INITIAL.
      rv_msgno = c_msgno_no_addr.
    ENDIF.

  ENDMETHOD.


  METHOD format_price.

    DATA: l_val  TYPE p LENGTH 16 DECIMALS 4,
          l_text TYPE string,
          l_int  TYPE string,
          l_dec  TYPE string,
          l_neg  TYPE abap_bool.

*   시트 설계 C110 - ALV 단가 x 100
    l_val = iv_price * c_price_factor.
    IF l_val < 0.
      l_neg = abap_true.
      l_val = abs( l_val ).
    ENDIF.

*   RAW 형식(사용자 숫자 형식 USR01-DCPFM 무관), 소수 C_PRICE_DEC 자리 반올림
    l_text = |{ l_val DECIMALS = c_price_dec }|.
    SPLIT l_text AT '.' INTO l_int l_dec.

*   시트 설계 C111 - 천 단위 콤마
    rv_text = add_thousand_sep( l_int ).
    IF l_dec IS NOT INITIAL.
      rv_text = |{ rv_text }.{ l_dec }|.
    ENDIF.
    IF l_neg = abap_true.
      rv_text = |-{ rv_text }|.
    ENDIF.

  ENDMETHOD.


  METHOD format_date.

*   시트 설계 C101 - 2026.09.28 형식
    IF iv_date IS INITIAL.
      CLEAR rv_text.
      RETURN.
    ENDIF.
    rv_text = |{ iv_date(4) }.{ iv_date+4(2) }.{ iv_date+6(2) }|.

  ENDMETHOD.


  METHOD build_html_body.

    DATA: ls_item   TYPE ty_item,
          l_remark  TYPE string,
          l_b01     TYPE string,
          l_b03     TYPE string.

*   머리
    rv_html = `<html><head><meta charset="utf-8"></head>`
           && `<body style="font-family:'맑은 고딕',sans-serif;font-size:10pt">`.

*   영역 A - 상단 문구 슬롯 (공란이면 줄 생략, U-02)
    add_text_line( EXPORTING iv_text = TEXT-a01 CHANGING cv_html = rv_html ).
    add_text_line( EXPORTING iv_text = TEXT-a02 CHANGING cv_html = rv_html ).
    add_text_line( EXPORTING iv_text = TEXT-a03 CHANGING cv_html = rv_html ).
    add_text_line( EXPORTING iv_text = TEXT-a04 CHANGING cv_html = rv_html ).
    add_text_line( EXPORTING iv_text = TEXT-a05 CHANGING cv_html = rv_html ).

*   1항 - "1." + 제목 슬롯 B01
    l_b01 = condense( TEXT-b01 ).
    rv_html = rv_html && `<p style="margin:0 0 6px 0">1. `
           && escape_html( l_b01 ) && `</p>`.

*   1항 표 - 시트 설계 C95~E95 헤더, C96~D99 행
    rv_html = rv_html
           && `<table border="1" cellspacing="0" cellpadding="4" `
           && `style="border-collapse:collapse;font-size:10pt">`
           && `<tr style="background-color:#f2f2f2">`
           && `<th style="width:160px">` && escape_html( '등급'(h01) ) && `</th>`
           && `<th style="width:90px">`  && escape_html( '단가'(h02) ) && `</th>`
           && `<th style="width:120px">` && escape_html( '비고'(h03) ) && `</th>`
           && `</tr>`.

    LOOP AT it_item INTO ls_item.
      l_remark = condense( ls_item-remark ).
      IF l_remark IS INITIAL.
        l_remark = `&nbsp;`.
      ELSE.
        l_remark = escape_html( l_remark ).
      ENDIF.

      rv_html = rv_html
             && `<tr><td>` && escape_html( ls_item-grade_txt ) && `</td>`
             && `<td style="text-align:right">` && format_price( ls_item-price ) && `</td>`
             && `<td>` && l_remark && `</td></tr>`.
    ENDLOOP.

    rv_html = rv_html && `</table>`.

*   2항 - 시트 설계 C101 "2. 적용일자: 2026.09.28"
    rv_html = rv_html && `<p style="margin:12px 0 0 0">`
           && escape_html( '2. 적용일자:'(b02) ) && ` ` && format_date( iv_datab )
           && `</p>`.

*   3항 - 시트 설계 C103, 문구 슬롯 B03 공란이면 줄 생략
    l_b03 = condense( TEXT-b03 ).
    IF l_b03 IS NOT INITIAL.
      rv_html = rv_html && `<p style="margin:12px 0 0 0">3. `
             && escape_html( l_b03 ) && `</p>`.
    ENDIF.

*   영역 Z - 하단 문구 슬롯 (공란이면 줄 생략, U-02)
    add_text_line( EXPORTING iv_text = TEXT-z01 CHANGING cv_html = rv_html ).
    add_text_line( EXPORTING iv_text = TEXT-z02 CHANGING cv_html = rv_html ).
    add_text_line( EXPORTING iv_text = TEXT-z03 CHANGING cv_html = rv_html ).

    rv_html = rv_html && `</body></html>`.

  ENDMETHOD.


  METHOD send.

    DATA: lo_req      TYPE REF TO cl_bcs,
          lo_doc      TYPE REF TO cl_document_bcs,
          lo_rcpt     TYPE REF TO cl_cam_address_bcs,
          lx_bcs      TYPE REF TO cx_bcs,
          lt_text     TYPE soli_tab,
          l_subject   TYPE so_obj_des,
          l_subj_long TYPE string,
          l_to        TYPE ad_smtpadr.

    CLEAR: ev_error.
    rv_ok = abap_false.

    IF it_to IS INITIAL.
      MESSAGE ID c_msgid TYPE 'E' NUMBER c_msgno_no_addr INTO ev_error.
      RETURN.
    ENDIF.

    l_subj_long = '국내스크랩 기본단가 공문'(s01).
    l_subject   = l_subj_long.             " SO_OBJ_DES 50자 초과분 잘림

    TRY.
        lo_req = cl_bcs=>create_persistent( ).

*       HTML 문자열 -> SOLI_TAB (7.5 문자 변환 규칙)
        lt_text = cl_bcs_convert=>string_to_soli( iv_html ).

        lo_doc = cl_document_bcs=>create_document(
                   i_type    = c_doc_type
                   i_text    = lt_text
                   i_subject = l_subject ).
        lo_req->set_document( lo_doc ).

*       제목 50자 초과 대비
        lo_req->set_message_subject( l_subj_long ).

*       발신자 = 로그인 사용자 (SU01 메일, 시트 외 X-5)
        lo_req->set_sender( cl_sapuser_bcs=>create( sy-uname ) ).

*       수신자 = 팝업 0200 입력 주소 전원 (한 메일, 시트 외 X-3)
        LOOP AT it_to INTO l_to.
          lo_rcpt = cl_cam_address_bcs=>create_internet_address( l_to ).
          lo_req->add_recipient( i_recipient = lo_rcpt ).
        ENDLOOP.

        lo_req->set_send_immediately( abap_true ).

        rv_ok = lo_req->send( i_with_error_screen = space ).

        IF rv_ok = abap_true.
          COMMIT WORK.
        ELSE.
          ROLLBACK WORK.                                 "#EC CI_ROLLBACK
          ev_error = 'BCS 발송 요청이 처리되지 않았습니다'(e01).
        ENDIF.

      CATCH cx_bcs INTO lx_bcs.
        ROLLBACK WORK.                                   "#EC CI_ROLLBACK
        rv_ok    = abap_false.
        ev_error = lx_bcs->get_text( ).
    ENDTRY.

  ENDMETHOD.


  METHOD add_text_line.

    DATA l_text TYPE string.

    l_text = condense( iv_text ).
    IF l_text IS INITIAL.
      RETURN.
    ENDIF.

    cv_html = cv_html && `<p style="margin:0 0 6px 0">`
           && escape_html( l_text ) && `</p>`.

  ENDMETHOD.


  METHOD is_valid_email.

    rv_valid = abap_false.

    IF iv_addr IS INITIAL OR strlen( iv_addr ) > c_max_addr_len.
      RETURN.
    ENDIF.

    FIND REGEX c_regex_mail IN iv_addr.
    IF sy-subrc = 0.
      rv_valid = abap_true.
    ENDIF.

  ENDMETHOD.


  METHOD add_thousand_sep.

    DATA: l_pos TYPE i.

    CLEAR rv_text.
    l_pos = strlen( iv_digits ).

    WHILE l_pos > 3.
      l_pos = l_pos - 3.
      rv_text = |,{ substring( val = iv_digits off = l_pos len = 3 ) }{ rv_text }|.
    ENDWHILE.

    rv_text = |{ substring( val = iv_digits off = 0 len = l_pos ) }{ rv_text }|.

  ENDMETHOD.


  METHOD escape_html.

    rv_text = escape( val = iv_text format = cl_abap_format=>e_html_text ).

  ENDMETHOD.

ENDCLASS.
