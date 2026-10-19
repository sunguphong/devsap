*&---------------------------------------------------------------------*
*&  Include           MZMM0020F01   - U4 변경 블록
*&---------------------------------------------------------------------*
*& [반영 방법] 기존 MZMM0020F01 소스는 변경하지 않고, 마지막 FORM
*&   DEL_ROWS 의 ENDFORM.  " DEL_ROWS 다음 줄에 아래 U4 블록 전체를
*&   그대로 추가한다. (참고본 ref/MZMM0020F01.abap 은 SAVE_DATA 등이
*&   요약본이라 전체 소스 대신 추가 블록으로 제공)
*& U4 2026.10.19 공문발송 FORM 추가 - 요청 20261019-bce84c
*&---------------------------------------------------------------------*

*-- U4 START
*&---------------------------------------------------------------------*
*&      Form  MAIL_PROCESS
*&---------------------------------------------------------------------*
*       공문발송 버튼(ZMAIL) 처리 - 시트 설계 C56~C77
*       선택 행 수집 -> 선택 검증 -> 메일주소 팝업 -> 발송
*----------------------------------------------------------------------*
FORM mail_process .

  DATA: l_msgno TYPE symsgno.

  IF grid IS INITIAL.
    RETURN.
  ENDIF.

  IF go_mail IS INITIAL.
    CREATE OBJECT go_mail.
  ENDIF.

* 1. 선택 행 수집 (시트 C56)
  PERFORM collect_selected_rows.

* 2. 선택 검증 - 0건 001 / 유효시작일 상이 002 (시트 C59~C61)
  CLEAR g_datab.
  l_msgno = go_mail->check_selection(
              EXPORTING it_item  = gt_mail_item
              IMPORTING ev_datab = g_datab ).
  IF l_msgno IS NOT INITIAL.
    MESSAGE ID zcl_mm_scrap_price_mail=>c_msgid TYPE 'S' NUMBER l_msgno
            DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

* 3. 메일주소 입력 팝업 (시트 C63)
  CLEAR: g_mail_to, gt_mail_to, g_answer, g_ok_0200.
  CALL SCREEN 0200 STARTING AT 10 5 ENDING AT 80 8.

* 4. [발송] 이면 메일 발송 (시트 C77), [취소] 면 메시지 없이 종료
  IF g_answer = c_answer_send.
    PERFORM send_mail.
  ENDIF.

ENDFORM.                    " MAIL_PROCESS

*&---------------------------------------------------------------------*
*&      Form  COLLECT_SELECTED_ROWS
*&---------------------------------------------------------------------*
*       ALV 선택 행 -> GT_MAIL_ITEM (기존 COPY/DEL 과 같은 방식)
*       BTEXT -> GRADE_TXT, DANGA -> PRICE, DATAB -> DATAB,
*       REMARK 는 GT_PR 에 대응 필드가 없어 공란
*----------------------------------------------------------------------*
FORM collect_selected_rows .

  DATA: lt_row  TYPE lvc_t_row,
        ls_row  TYPE lvc_s_row,
        ls_pr   LIKE gt_pr,
        ls_item TYPE zcl_mm_scrap_price_mail=>ty_item.

  CLEAR gt_mail_item.

* 편집 중 값을 GT_PR 에 반영 (미결 U-06 : 미저장 값 차단 없음)
  CALL METHOD grid->check_changed_data.

  CALL METHOD grid->get_selected_rows
    IMPORTING
      et_index_rows = lt_row.

* 소계/합계 행 제외, ALV 순서(INDEX 오름차순)
  DELETE lt_row WHERE rowtype IS NOT INITIAL.
  SORT lt_row BY index.

  LOOP AT lt_row INTO ls_row.
    READ TABLE gt_pr INTO ls_pr INDEX ls_row-index.
    IF sy-subrc <> 0.
      CONTINUE.
    ENDIF.

    CLEAR ls_item.
    ls_item-grade_txt = ls_pr-btext.
    ls_item-price     = ls_pr-danga.
    ls_item-datab     = ls_pr-datab.
    APPEND ls_item TO gt_mail_item.
  ENDLOOP.

ENDFORM.                    " COLLECT_SELECTED_ROWS

*&---------------------------------------------------------------------*
*&      Form  CHECK_MAIL_ADDRESS
*&---------------------------------------------------------------------*
*       팝업 0200 [발송] - 입력 메일주소 확인 (공란 003 / 형식 004)
*       오류면 팝업 유지(입력값 보존), 정상이면 팝업 닫고 발송 표시
*----------------------------------------------------------------------*
FORM check_mail_address .

  DATA: l_msgno   TYPE symsgno,
        l_invalid TYPE string,
        l_msgv    TYPE symsgv.

  l_msgno = go_mail->parse_addresses(
              EXPORTING iv_text    = g_mail_to
              IMPORTING et_addr    = gt_mail_to
                        ev_invalid = l_invalid ).
  IF l_msgno IS NOT INITIAL.
    l_msgv = l_invalid.
    MESSAGE ID zcl_mm_scrap_price_mail=>c_msgid TYPE 'S' NUMBER l_msgno
            WITH l_msgv DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  g_answer = c_answer_send.
  LEAVE TO SCREEN 0.

ENDFORM.                    " CHECK_MAIL_ADDRESS

*&---------------------------------------------------------------------*
*&      Form  SEND_MAIL
*&---------------------------------------------------------------------*
*       HTML 본문 생성 -> BCS 발송 -> 결과 메시지 005 / 006
*----------------------------------------------------------------------*
FORM send_mail .

  DATA: l_html  TYPE string,
        l_error TYPE string,
        l_ok    TYPE abap_bool,
        l_msgv  TYPE symsgv.

  l_html = go_mail->build_html_body( it_item  = gt_mail_item
                                     iv_datab = g_datab ).

  l_ok = go_mail->send( EXPORTING it_to    = gt_mail_to
                                  iv_html  = l_html
                        IMPORTING ev_error = l_error ).

  IF l_ok = abap_true.
    MESSAGE ID zcl_mm_scrap_price_mail=>c_msgid TYPE 'S'
            NUMBER zcl_mm_scrap_price_mail=>c_msgno_sent.
  ELSE.
    l_msgv = l_error.
    MESSAGE ID zcl_mm_scrap_price_mail=>c_msgid TYPE 'S'
            NUMBER zcl_mm_scrap_price_mail=>c_msgno_send_error
            WITH l_msgv DISPLAY LIKE 'E'.
  ENDIF.

ENDFORM.                    " SEND_MAIL
*-- U4 END
