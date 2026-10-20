*&---------------------------------------------------------------------*
*&  Include           MZMM0020F01
*&---------------------------------------------------------------------*
*&---------------------------------------------------------------------*
*&      Form  INIT
*&---------------------------------------------------------------------*
*       프로그램 초기화 부분
*----------------------------------------------------------------------*
*  -->  p1        text
*  <--  p2        text
*----------------------------------------------------------------------*
FORM init .
  so_datab-high = sy-datum.
  CALL FUNCTION 'RP_CALC_DATE_IN_INTERVAL'
    EXPORTING
      date      = so_datab-high
      days      = '00'
      months    = '01'
      signum    = '-'
      years     = '00'
    IMPORTING
      calc_date = so_datab-low.
  so_datab-sign = 'I'.
  so_datab-option = 'BT'.
  APPEND so_datab.
ENDFORM.                    " INIT
*&---------------------------------------------------------------------*
*&      Form  GET_DATA
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*  -->  p1        text
*  <--  p2        text
*----------------------------------------------------------------------*
FORM get_data .

  FREE gt_pr.

  SELECT
      ztmm0015~werks
      ztmm0015~matnr
      ztmm0015~zlevel
      ztmm0014~btext
      ztmm0015~datab
      ztmm0015~datai
      ztmm0015~danga
      ztmm0015~waers
      ztmm0015~kpein
      ztmm0015~lvorm
      ztmm0015~laeda
      ztmm0015~ltime
      ztmm0015~aenam
      ztmm0015~zdrfst
      ztmm0015~zscrdno
    INTO CORRESPONDING FIELDS OF TABLE gt_pr
    FROM ztmm0015 INNER JOIN ztmm0014
            ON ztmm0015~werks = ztmm0014~werks
           AND ztmm0015~matnr = ztmm0014~matnr
           AND ztmm0015~zlevel = ztmm0014~zlevel

*    WHERE ZTMM0015~WERKS  IN RA_WERKS
*      AND ZTMM0015~MATNR  IN RA_MATNR
*      AND ZTMM0015~ZLEVEL IN RA_ZLEVEL
*      AND ZTMM0015~DATAB  IN RA_DATAB
    WHERE ztmm0015~werks  IN so_werks
      AND ztmm0015~matnr  IN so_matnr
      AND ztmm0015~zlevel IN so_level
      AND ztmm0015~datab  IN so_datab.

  LOOP AT gt_pr.
    IF grid IS INITIAL OR grid->is_ready_for_input( ) EQ 0.        "읽기
      PERFORM fill_coltab USING 'R'.
      PERFORM fill_stytab USING 'R'.
    ELSE.                                                          "수정
      PERFORM fill_coltab USING 'M'.
      PERFORM fill_stytab USING 'M'.
    ENDIF.
    gt_pr-dbdata = 'X'.
    MODIFY gt_pr TRANSPORTING coltab stytab dbdata.
  ENDLOOP.

ENDFORM.                    " GET_DATA
*&---------------------------------------------------------------------*
*&      Form  CREATE_DATA
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*  -->  p1        text
*  <--  p2        text
*----------------------------------------------------------------------*
FORM create_data .

  DATA: lt_row TYPE TABLE OF lvc_s_row WITH HEADER LINE.    "사용자가 선택한 행의 정보를 가지고 있는 테이블
  DATA: ls_pr LIKE gt_pr.                                   "추가될 행
  DATA: lv_index TYPE i.

  CALL METHOD grid->check_changed_data.

  CALL METHOD grid->get_selected_rows
    IMPORTING
      et_index_rows = lt_row[].                          "사용자가 선택한값을 얻는다.

  IF lt_row[] IS INITIAL.
    gt_pr = ls_pr.
    gt_pr-lvorm = space.
    PERFORM fill_coltab USING 'I'.
    PERFORM fill_stytab USING 'I'.
    APPEND gt_pr.
  ELSE.
    LOOP AT lt_row.
      lv_index = sy-tabix + lt_row-index.
      gt_pr-lvorm = space.
      gt_pr = ls_pr.
      PERFORM fill_coltab USING 'I'.
      PERFORM fill_stytab USING 'I'.
      INSERT gt_pr INDEX lv_index.
    ENDLOOP.
  ENDIF.

ENDFORM.                    " CREATE_DATA
*&---------------------------------------------------------------------*
*&      Form  TOGGLE_DISPLAY_CHANGE
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*  -->  p1        text
*  <--  p2        text
*----------------------------------------------------------------------*
FORM toggle_display_change .

  IF grid->is_ready_for_input( ) EQ 0.
    grid->set_ready_for_input( 1 ).
    PERFORM get_data.
    PERFORM make_alv_disp.
  ELSE.
    grid->set_ready_for_input( 0 ).
    PERFORM get_data.
    PERFORM make_alv_disp.
  ENDIF.

*  FREE GT_DELETED.

ENDFORM.                    " TOGGLE_DISPLAY_CHANGE

*&---------------------------------------------------------------------*
*&      Form  FILL_COLTAB
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*  -->  p1        text
*  <--  p2        text
*----------------------------------------------------------------------*
FORM fill_coltab USING p_mode.
  DATA ls_coltab TYPE lvc_s_scol .

  DEFINE fill_coltab.
    clear ls_coltab.
    ls_coltab-fname = &1.
    ls_coltab-color-col = '3'.
    append ls_coltab to gt_pr-coltab.
  END-OF-DEFINITION.

  FREE gt_pr-coltab.

  CASE p_mode.
    WHEN 'R'.          "읽기일때 색상

    WHEN 'M'.          "수정일때 색상
      fill_coltab:  'DANGA',
                    'WAERS',
                    'KPEIN'.
    WHEN 'I'.          "추가 일때의 색상
      fill_coltab:  'WERKS',
                    'MATNR',
                    'ZLEVEL',
                    'DATAB',
                    'DATAI',
                    'DANGA',
                    'WAERS',
                    'KPEIN'.
    WHEN 'C'.          "COPY 일때의 색상
      fill_coltab: 'DATAB',
                   'DANGA',
                   'WAERS',
                   'KPEIN'.
  ENDCASE.

ENDFORM.                    " FILL_COLTAB
*&---------------------------------------------------------------------*
*&      Form  FILL_STYTAB
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*  -->  p1        text
*  <--  p2        text
*----------------------------------------------------------------------*
FORM fill_stytab USING p_mode.

  DATA: ls_stytab TYPE lvc_s_styl.

  DEFINE fill_stytab.
    clear ls_stytab.
    ls_stytab-fieldname = &1.
    ls_stytab-style = &2.
    insert  ls_stytab into table gt_pr-stytab.
  END-OF-DEFINITION.

  FREE gt_pr-stytab.

  CASE p_mode.

    WHEN 'R'.          "읽기일때 편집여부
      fill_stytab:  'WERKS' cl_gui_alv_grid=>mc_style_disabled,
                    'MATNR' cl_gui_alv_grid=>mc_style_disabled,
                    'ZLEVEL' cl_gui_alv_grid=>mc_style_disabled,
                    'BTEXT' cl_gui_alv_grid=>mc_style_disabled,
                    'DATAB' cl_gui_alv_grid=>mc_style_disabled,
                    'DATAI' cl_gui_alv_grid=>mc_style_disabled,
                    'DANGA' cl_gui_alv_grid=>mc_style_disabled,
                    'WAERS' cl_gui_alv_grid=>mc_style_disabled,
                    'KPEIN' cl_gui_alv_grid=>mc_style_disabled,
                    'LVORM' cl_gui_alv_grid=>mc_style_disabled,
                    'LAEDA' cl_gui_alv_grid=>mc_style_disabled, "U1
                    'LTIME' cl_gui_alv_grid=>mc_style_disabled, "U1
                    'AENAM' cl_gui_alv_grid=>mc_style_disabled, "U1
                    'ZDRFST'  cl_gui_alv_grid=>mc_style_disabled, "U3
                    'ZSCRDNO' cl_gui_alv_grid=>mc_style_disabled. "U3

    WHEN 'M'.          "수정일때 편집
      fill_stytab:    'WERKS' cl_gui_alv_grid=>mc_style_disabled,
                      'MATNR' cl_gui_alv_grid=>mc_style_disabled,
                      'ZLEVEL' cl_gui_alv_grid=>mc_style_disabled,
                      'BTEXT' cl_gui_alv_grid=>mc_style_disabled,
                      'DATAB' cl_gui_alv_grid=>mc_style_disabled,
                      'DATAI' cl_gui_alv_grid=>mc_style_disabled,
                      'DANGA' cl_gui_alv_grid=>mc_style_enabled,
                      'WAERS' cl_gui_alv_grid=>mc_style_enabled,
                      'KPEIN' cl_gui_alv_grid=>mc_style_enabled,
                      'LVORM' cl_gui_alv_grid=>mc_style_disabled,
                      'LAEDA' cl_gui_alv_grid=>mc_style_disabled, "U1
                      'LTIME' cl_gui_alv_grid=>mc_style_disabled, "U1
                      'AENAM' cl_gui_alv_grid=>mc_style_disabled, "U1
                      'ZDRFST'  cl_gui_alv_grid=>mc_style_disabled, "U3
                      'ZSCRDNO' cl_gui_alv_grid=>mc_style_disabled. "U3

    WHEN 'I'.          "추가 일때의 색상
      fill_stytab:    'WERKS' cl_gui_alv_grid=>mc_style_enabled,
                      'MATNR' cl_gui_alv_grid=>mc_style_enabled,
                      'ZLEVEL' cl_gui_alv_grid=>mc_style_enabled,
                      'BTEXT' cl_gui_alv_grid=>mc_style_disabled,
                      'DATAB' cl_gui_alv_grid=>mc_style_enabled,
                      'DATAI' cl_gui_alv_grid=>mc_style_enabled,
                      'DANGA' cl_gui_alv_grid=>mc_style_enabled,
                      'WAERS' cl_gui_alv_grid=>mc_style_enabled,
                      'KPEIN' cl_gui_alv_grid=>mc_style_enabled,
                      'LVORM' cl_gui_alv_grid=>mc_style_disabled,
                      'LAEDA' cl_gui_alv_grid=>mc_style_disabled, "U1
                      'LTIME' cl_gui_alv_grid=>mc_style_disabled, "U1
                      'AENAM' cl_gui_alv_grid=>mc_style_disabled, "U1
                      'ZDRFST'  cl_gui_alv_grid=>mc_style_disabled, "U3
                      'ZSCRDNO' cl_gui_alv_grid=>mc_style_disabled. "U3

    WHEN 'C'.          "COPY 일때의 색상
      fill_stytab:   'WERKS' cl_gui_alv_grid=>mc_style_disabled,
                     'MATNR' cl_gui_alv_grid=>mc_style_disabled,
                     'ZLEVEL' cl_gui_alv_grid=>mc_style_disabled,
                     'BTEXT' cl_gui_alv_grid=>mc_style_disabled,
                     'DATAB' cl_gui_alv_grid=>mc_style_enabled,
                     'DATAI' cl_gui_alv_grid=>mc_style_disabled,
                     'DANGA' cl_gui_alv_grid=>mc_style_enabled,
                     'WAERS' cl_gui_alv_grid=>mc_style_enabled,
                     'KPEIN' cl_gui_alv_grid=>mc_style_enabled,
                     'LVORM' cl_gui_alv_grid=>mc_style_disabled,
                     'LAEDA' cl_gui_alv_grid=>mc_style_disabled, "U1
                     'LTIME' cl_gui_alv_grid=>mc_style_disabled, "U1
                     'AENAM' cl_gui_alv_grid=>mc_style_disabled, "U1
                     'ZDRFST'  cl_gui_alv_grid=>mc_style_disabled, "U3
                     'ZSCRDNO' cl_gui_alv_grid=>mc_style_disabled. "U3

  ENDCASE.



ENDFORM.                    " FILL_STYTAB
*&---------------------------------------------------------------------*
*&      Form  COPY_DATA
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*  -->  p1        text
*  <--  p2        text
*----------------------------------------------------------------------*
FORM copy_data .
  DATA: lt_row TYPE TABLE OF lvc_s_row WITH HEADER LINE.    "사용자가 선택한 행의 정보를 가지고 있는 테이블
  DATA: lv_index TYPE i.

  CALL METHOD grid->check_changed_data.

  CALL METHOD grid->get_selected_rows
    IMPORTING
      et_index_rows = lt_row[].                          "사용자가 선택한값을 얻는다.

  IF lt_row[] IS INITIAL.
    MESSAGE s000 WITH '하나이상의 행을 선택하세요'.
    EXIT.
  ELSE.
    LOOP AT lt_row.
      lv_index = lt_row-index + sy-tabix - 1.
      READ TABLE gt_pr INDEX lv_index.
      gt_pr-datab = space.
      gt_pr-danga = space.
      gt_pr-dbdata = space.
      gt_pr-datai = '99991231'.
      gt_pr-lvorm = space.
      gt_pr-zdrfst = space.
      gt_pr-zscrdno = space.
      lv_index = sy-tabix + 1.
      PERFORM fill_coltab USING 'C'.
      PERFORM fill_stytab USING 'C'.
      INSERT gt_pr INDEX lv_index.
    ENDLOOP.
  ENDIF.

ENDFORM.                    " COPY_DATA
*&---------------------------------------------------------------------*
*&      Form  SAVE_DATA
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*  -->  p1        text
*  <--  p2        text
*----------------------------------------------------------------------*
FORM save_data .

  CALL METHOD grid->check_changed_data.

*& 계산을 위한 INTERNAL TABLE
  DATA lt_check LIKE TABLE OF gt_pr.                                 "VALIDATION CHECK용 IT
  DATA ls_check LIKE LINE OF lt_check.                               "VALIDATION CHECK용 WA

  DATA lv_error TYPE string.                                         "ERROR TEXT용
  DATA lv_count TYPE i.                                              "생성, COPY된 ROW의 중복여부체크

  DATA lt_modified LIKE TABLE OF ztmm0015.                              "기존 변경될 ROWS IT
  DATA ls_modified LIKE LINE OF lt_modified.                         "기존 변경될 ROW WA

  DATA: lt_temp LIKE ztmm0015 OCCURS 0 WITH HEADER LINE.

  DATA: lv_usernm LIKE pa0001-sname. "U1 수정자

  DATA: lv_kb5_danga TYPE ztmm0015-danga,
        lv_kbt_danga TYPE ztmm0015-danga.

* 레코드 항목수 체크: 레코드수는 하나이상이어야 함
  IF gt_pr[] IS INITIAL.
    MESSAGE s000 WITH '하나 이상의 항목이 있어야 합니다.'.
    EXIT.
  ENDIF.

* 유효성 체크
  lt_check = gt_pr[].

  LOOP AT lt_check INTO ls_check.

* 고철등급 테이블을 통한 유효성 검사
    SELECT SINGLE mandt INTO sy-mandt
    FROM ztmm0014
    WHERE werks  EQ ls_check-werks AND
          matnr  EQ ls_check-matnr AND
          zlevel EQ ls_check-zlevel.
    IF sy-subrc <> 0.
      CONCATENATE '플랜트:'   ls_check-werks
                  '자재코드:' ls_check-matnr
                  '고철등급:' ls_check-zlevel
                  '은(는) 고철등급 코드관리 테이블에 없습니다.'
                  INTO lv_error SEPARATED BY space.
      MESSAGE s000 WITH lv_error.
      RETURN.
    ENDIF.

* 통화단위 검사
    SELECT SINGLE mandt INTO sy-mandt
    FROM tcurc
    WHERE waers = ls_check-waers.

    IF sy-subrc <> 0.
      MESSAGE s000 WITH '유효하지 않은 통화단위입니다.'.
      RETURN.
    ENDIF.

* 단가 검사
    IF ls_check-danga <= 0.
      MESSAGE s000 WITH '단가는 0보다 커야 합니다.'.
      RETURN.
    ENDIF.

* 단위 검사
    IF ls_check-kpein <= 0.
      MESSAGE s000 WITH '단위는 0보다 커야 합니다.'.
      RETURN.
    ENDIF.

* 유효시작일 검사
    IF ls_check-datab IS INITIAL.
      MESSAGE s000 WITH '유효시작일이 유효하지 않습니다.'.
      RETURN.
    ENDIF.

** 유효만료일검사및 설정
*    IF LS_CHECK-DATAI IS INITIAL.
*       LS_CHECK-DATAI = '99991231'.
**       MODIFY LS_CHECK.
*    ENDIF.

* 생성이나 COPY해서 생성된 ROW는 플랜트, 자재코드, 고철등급코드가 동일한 행이 존재해서는 안됨
    CLEAR lv_count.
    LOOP AT gt_pr WHERE werks = ls_check-werks AND
                        matnr = ls_check-matnr AND
                        zlevel = ls_check-zlevel AND
                        dbdata = space.
      lv_count = lv_count + 1.
    ENDLOOP.
    IF lv_count >= 2.
      CONCATENATE '추가된 플랜트:'   ls_check-werks
                  '자재코드:' ls_check-matnr
                  '고철등급:' ls_check-zlevel
                  '은(는) 2개이상입니다.'
                  INTO lv_error SEPARATED BY space.
      MESSAGE s000 WITH lv_error.
      RETURN.
    ENDIF.

* 유효만료일 조정할것을 처리
    FREE lt_temp.

    CHECK ls_check-dbdata IS INITIAL.

    SELECT * INTO CORRESPONDING FIELDS OF TABLE lt_temp
     FROM ztmm0015
     WHERE werks = ls_check-werks
       AND matnr = ls_check-matnr
       AND zlevel = ls_check-zlevel
       AND lvorm EQ ''.                                "U2.

*    LOOP AT LT_TEMP .      "삭제를안하는 것으로 정의되어 주석처리
*      READ TABLE GT_DELETED WITH KEY WERKS = LT_TEMP-WERKS
*                                     MATNR = LT_TEMP-MATNR
*                                     ZLEVEL = LT_TEMP-ZLEVEL
*                                     DATAB  = LT_TEMP-DATAB.
*      IF SY-SUBRC = 0.
*        DELETE LT_TEMP.
*        CONTINUE.
*      ENDIF.
*    ENDLOOP.

    SORT lt_temp BY datab DESCENDING.

    READ TABLE lt_temp INDEX 1.
    IF sy-subrc EQ 0.
      IF ls_check-datab <= lt_temp-datab.
        CONCATENATE '플랜트:'   ls_check-werks
                    '자재코드:' ls_check-matnr
                    '고철등급:' ls_check-zlevel
                    '유효시작일자:' ls_check-datab
                    '은'
                    lt_temp-datab '보다 커야 합니다.'
                    INTO lv_error SEPARATED BY space.
        MESSAGE s000 WITH lv_error.
        RETURN.
      ENDIF.

      MOVE-CORRESPONDING lt_temp TO ls_modified.
      ls_modified-datai = ls_check-datab - 1.
      APPEND ls_modified TO lt_modified.
    ENDIF.

  ENDLOOP.

  "----------------------------------------------
  "경량T 단가 등록 기준 적용 추가
  "----------------------------------------------
***  LOOP AT lt_check INTO ls_check.
***
***    IF ls_check-zlevel = 'KBT'.  "경량T 등록시
***
***      CLEAR:  lv_kb5_danga.
***      SELECT SINGLE danga
***        INTO  lv_kb5_danga         "경량B단가
***        FROM ztmm0015
***        WHERE zlevel IN ( 'KB5' )
***           AND zdrfst = 'X'
***           AND zscrdno  IS NOT NULL
***           AND lvorm = ''
***           AND matnr NOT LIKE '%A'
***           AND datai = '99991231'
***           AND werks = ls_check-werks.
***
***      "경량B 단가 300원/kg 이상일 경우, 경량T 단가 300원/kg보다 높게 입력 시
***      IF lv_kb5_danga >= 3.
***        IF ls_check-danga > 3.
***          MESSAGE s000 WITH
***                         '경량B 단가 300원/kg 이상일 경우, 경량T 단가 300원/kg보다 높게 입력 불가.'.
***          RETURN.
***        ENDIF.
***      ENDIF.
***
***      "경량B 단가 300원/kg 미만일 경우, 경량T 단가 300원/kg 이상 입력 시
***      IF lv_kb5_danga < 3.
***        IF ls_check-danga >= 3.
***          MESSAGE s000 WITH
***                         '경량B 단가 300원/kg 미만일 경우, 경량T 단가 300원/kg 이상 입력 불가.'.
***          RETURN.
***        ENDIF.
***      ENDIF.
***
***      "경량B 200원/kg 미만일 경우, 경량T 단가와 경량 A단가 차이 시
***      IF lv_kb5_danga < 2.
***        IF ls_check-danga  <> lv_kb5_danga.
***          MESSAGE s000 WITH
***                         '경량B 200원/kg 미만일 경우, 경량T 단가와 경량 A단가 차이 시 입력 불가.'.
***          RETURN.
***        ENDIF.
***      ENDIF.
***
***
***
***    ELSEIF ls_check-zlevel = 'KB5'.  "경량B 등록시
***
***      "경량B 200원/kg 미만일 경우, 기본단가 조정할때 경량T 단가 입력자체 누락 시
***      IF ls_check-danga < 2.
***        CLEAR: lv_kbt_danga.
***        SELECT SINGLE danga
***             INTO  lv_kbt_danga
***          FROM ztmm0015
***        WHERE zlevel IN ( 'KBT' )   "경량T
***             AND zdrfst = 'X'
***             AND zscrdno  IS NOT NULL
***             AND lvorm = ''
***             AND matnr NOT LIKE '%A'
***             AND datai = '99991231'
***             AND werks = ls_check-werks.
***        IF  lv_kbt_danga EQ 0.
***          MESSAGE s000 WITH
***           '경량B 200원/kg 미만일 경우, 기본단가 조정할때 경량T 단가 입력자체 누락 시 입력 불가.'.
***          RETURN.
***        ENDIF.
***      ENDIF.
***
***      "경량B 200원/kg 미만일 경우, 경량T 단가와 경량 A단가 차이 시
***      IF ls_check-danga < 2.
***        IF ls_check-danga  <> lv_kbt_danga.
***          MESSAGE s000 WITH
***                         '경량B 200원/kg 미만일 경우, 경량T 단가와 경량 A단가 차이 시 입력 불가.'.
***          RETURN.
***        ENDIF.
***      ENDIF.
***
***
***      "경량B 단가 300원/kg 미만일 경우, 기본단가 조정할때 경량T 단가 입력자체 누락 시
***      IF ls_check-danga < 3.
***        SELECT COUNT( * )
***          FROM ztmm0015
***        WHERE zlevel IN ( 'KBT' )   "경량T
***             AND zdrfst = 'X'
***             AND zscrdno  IS NOT NULL
***             AND lvorm = ''
***             AND matnr NOT LIKE '%A'
***             AND datai = '99991231'
***             AND werks = ls_check-werks.
***        IF  sy-dbcnt = 0 .
***          MESSAGE s000 WITH
***           '경량B 단가 300원/kg 미만일 경우, 기본단가 조정할때 경량T 단가 입력자체 누락 시 입력 불가.'.
***          RETURN.
***        ENDIF.
***      ENDIF.
***
***    ENDIF.
***
***  ENDLOOP.
***  "----------------------------------------------



  DATA : ls_ztmm0015 LIKE ztmm0015,
         lt_ztmm0015 LIKE ztmm0015 OCCURS 0.

** 삭제될것 삭제 "삭제 플래그로 대체
*  CLEAR: LS_ZTMM0015, LT_ZTMM0015.
*  LOOP AT GT_DELETED.
*    MOVE-CORRESPONDING GT_DELETED TO LS_ZTMM0015.
*    APPEND LS_ZTMM0015 TO LT_ZTMM0015.
*  ENDLOOP.
*
*  IF LT_ZTMM0015 IS NOT INITIAL.
*    DELETE ZTMM0015 FROM TABLE LT_ZTMM0015.
*    IF SY-DBCNT NE LINES( LT_ZTMM0015 ).
*      MESSAGE S000 WITH 'DB 에러'.
*      ROLLBACK WORK.
*      RETURN.
*    ENDIF.
*  ENDIF.

* 수정될것 수정
  CLEAR: ls_ztmm0015, lt_ztmm0015.
  LOOP AT lt_check INTO ls_check.
    IF ls_check-datai IS INITIAL.
      ls_check-datai = '99991231'.
    ENDIF.
    MOVE-CORRESPONDING ls_check TO ls_ztmm0015.

*U1 수정일자/시간/수정자 필드추가
    ls_ztmm0015-laeda = sy-datum.
    ls_ztmm0015-ltime = sy-uzeit.

    SELECT SINGLE sname FROM pa0001
      INTO ls_ztmm0015-aenam
                       WHERE pernr EQ sy-uname
                         AND begda LE sy-datum
                         AND endda GE sy-datum.

    IF sy-subrc NE 0.
      ls_ztmm0015-aenam = sy-uname.
    ENDIF.
*<-U1

    APPEND ls_ztmm0015 TO lt_ztmm0015.
  ENDLOOP.

  IF lt_ztmm0015 IS NOT INITIAL.
    MODIFY ztmm0015 FROM TABLE lt_ztmm0015.
    IF sy-dbcnt NE lines( lt_ztmm0015 ).
      MESSAGE s000 WITH 'DB 에러'.
      ROLLBACK WORK.
      RETURN.
    ENDIF.
  ENDIF.

* 유효만료일 수정될것 수정
  IF lt_modified IS NOT INITIAL.
    MODIFY ztmm0015 FROM TABLE lt_modified.
    IF sy-dbcnt NE lines( lt_modified ).
      MESSAGE s000 WITH 'DB 에러'.
      ROLLBACK WORK.
      RETURN.
    ENDIF.
  ENDIF.

  COMMIT WORK AND WAIT.

  PERFORM toggle_display_change .

ENDFORM.                    " SAVE_DATA
*&---------------------------------------------------------------------*
*&      Form  DEL_ROWS
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*  -->  p1        text
*  <--  p2        text
*----------------------------------------------------------------------*
FORM del_rows .
  DATA: lt_row TYPE TABLE OF lvc_s_row WITH HEADER LINE.    "사용자가 선택한 행의 정보를 가지고 있는 테이블

  CALL METHOD grid->check_changed_data.

  CALL METHOD grid->get_selected_rows
    IMPORTING
      et_index_rows = lt_row[].                          "사용자가 선택한값을 얻는다.

  SORT lt_row BY index DESCENDING.

  IF lt_row[] IS INITIAL.
    MESSAGE s000 WITH '하나이상의 행을 선택하세요'.
    EXIT.
  ELSE.
    LOOP AT lt_row.
      READ TABLE gt_pr INDEX lt_row-index.
      IF gt_pr-dbdata EQ 'X'.
*        GT_DELETED = GT_PR.
*        APPEND GT_DELETED.
        IF gt_pr-lvorm = 'X'.
          gt_pr-lvorm = space.
        ELSE.
          gt_pr-lvorm = 'X'.
        ENDIF.
        MODIFY gt_pr INDEX lt_row-index.
      ELSE.
        DELETE gt_pr INDEX lt_row-index.
      ENDIF.
    ENDLOOP.
  ENDIF.

ENDFORM.                    " DEL_ROWS

*-- U4 START : 공문발송 (요청 20261019-bce84c)
*&---------------------------------------------------------------------*
*& U4 2026.10.20 ZEMM2222 공문발송 FORM 4개 추가 (기존 인클루드 끝에 추가)
*&    - 위 기존 FORM(INIT ~ DEL_ROWS)은 원문 그대로, 변경 없음
*&---------------------------------------------------------------------*
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
*       미저장 수정값/신규 행/삭제표시 행도 그대로 포함 (U-06 기본값)
*----------------------------------------------------------------------*
FORM collect_selected_rows .

  DATA: lt_row  TYPE lvc_t_row,
        ls_row  TYPE lvc_s_row,
        ls_pr   LIKE LINE OF gt_pr,
        ls_item TYPE zcl_mm_scrap_price_mail=>ty_item.

  CLEAR gt_mail_item.

* 편집 중 값을 GT_PR 에 반영 (기존 COPY/DEL/SAVE 와 동일)
  CALL METHOD grid->check_changed_data.

  CALL METHOD grid->get_selected_rows
    IMPORTING
      et_index_rows = lt_row.

* 소계/합계 행 제외, ALV 표시 순서(INDEX 오름차순)
  DELETE lt_row WHERE rowtype IS NOT INITIAL.
  SORT lt_row BY index.

* GT_PR 헤더라인은 기존 FORM 공용이므로 INTO 워크에어리어로 읽음
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
