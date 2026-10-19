*&---------------------------------------------------------------------*
*& Report ZRMM0024
*&---------------------------------------------------------------------*
*& 자재마스터 조회 리포트 (T-code ZRMM0024, 패키지 ZMMD)
*& - 자재 x 플랜트 1행, 조회 전용 (DB 변경 없음)
*& - 현업 확정: Q1 플랜트 필수 / Q2 삭제여부 = MARC-LVORM
*&             Q3 단가 = 항상 MBEW-VERPR
*& - 미결(분석 가정·권장안): Q4 자재명 언어/대체 언어, Q5 최대건수
*&             Q9 배치관리 = MARC-XCHPF, Q10 배치관리 선택조건(블록 B4)
*& - 조회 로직: ZCL_MM_MATERIAL_LIST
*& - 명명: UNION Steel ABAP 개발표준 Handbook (SO_/PA_/R_/C_/GT_/LT_/
*&         G_/L_/GS_/LS_). 로컬 클래스·메서드 파라미터는 SAP 관례(LCL_,
*&         IO_/IV_) 적용 — 핸드북 규칙 없음
*& - 대상: ECC(MATNR C18), SAP_BASIS 7.40 (SP09 이상 추정, 7.50 미만)
*&   반영 대상: 개발계(MRD, 클라이언트 350)
*&---------------------------------------------------------------------*
REPORT zrmm0024.

*----------------------------------------------------------------------*
* 선택화면 참조용 변수 (DDIC 참조로 F4/검색도움말 사용)
*----------------------------------------------------------------------*
DATA: g_werks TYPE marc-werks,
      g_matnr TYPE mara-matnr,
      g_mtart TYPE mara-mtart,
      g_matkl TYPE mara-matkl,
      g_ernam TYPE mara-ernam,
      g_ersda TYPE mara-ersda.

" 레이아웃 정보 (INITIALIZATION 기본 레이아웃, F4 결과)
DATA gs_layout TYPE salv_s_layout_info.

*----------------------------------------------------------------------*
* 선택화면 (블록 순서 B1 → B2 → B4 → B3, 설계 5장)
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-b01.
  SELECT-OPTIONS: so_werks FOR g_werks OBLIGATORY,   " 현업 확정 Q1
                  so_matnr FOR g_matnr,
                  so_mtart FOR g_mtart,
                  so_matkl FOR g_matkl,
                  so_ernam FOR g_ernam,
                  so_ersda FOR g_ersda.
SELECTION-SCREEN END OF BLOCK b1.

" 삭제여부(플랜트) - MARC-LVORM 기준 (현업 확정 Q2)
SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-b02.
  PARAMETERS: pa_delex RADIOBUTTON GROUP del DEFAULT 'X',
              pa_delon RADIOBUTTON GROUP del,
              pa_delal RADIOBUTTON GROUP del.
SELECTION-SCREEN END OF BLOCK b2.

" 배치관리(플랜트) - MARC-XCHPF 기준 (권장안, 현업 확인 대기 Q10)
SELECTION-SCREEN BEGIN OF BLOCK b4 WITH FRAME TITLE TEXT-b04.
  PARAMETERS: pa_batal RADIOBUTTON GROUP bat DEFAULT 'X',
              pa_baton RADIOBUTTON GROUP bat,
              pa_batof RADIOBUTTON GROUP bat.
SELECTION-SCREEN END OF BLOCK b4.

" 출력 옵션
SELECTION-SCREEN BEGIN OF BLOCK b3 WITH FRAME TITLE TEXT-b03.
  PARAMETERS: pa_spras TYPE spras,                 " 자재명 언어 (Q4)
              pa_spra2 TYPE spras,                 " 대체 언어 (공란 = 대체 안 함)
              pa_maxht TYPE i,                     " 최대건수 (0 = 무제한, Q5)
              pa_vari  TYPE slis_vari.             " ALV 레이아웃
SELECTION-SCREEN END OF BLOCK b3.

*----------------------------------------------------------------------*
* 리포트 처리 클래스 (로컬 클래스: 핸드북 규칙 없음 — SAP 관례 LCL_)
* 클래스 속성은 핸드북 3장대로 Global(G_/GT_/GS_)로 봄
*----------------------------------------------------------------------*
CLASS lcl_report DEFINITION FINAL.
  PUBLIC SECTION.
    CONSTANTS c_tcode_mm03 TYPE sy-tcode VALUE 'MM03'.

    METHODS run.

    METHODS on_double_click
      FOR EVENT double_click OF cl_salv_events_table
      IMPORTING row column.

  PRIVATE SECTION.
    "! 배치관리 체크박스 컬럼 고정 출력 길이 (설계 9장)
    CONSTANTS c_xchpf_out_len TYPE lvc_outlen VALUE '6'.

    DATA gs_sel     TYPE zcl_mm_material_list=>ty_sel.      " 선택값 → 클래스 전달
    DATA g_list     TYPE REF TO zcl_mm_material_list.       " 조회 클래스
    DATA gt_denied  TYPE zcl_mm_material_list=>tt_werks.    " 권한 없는 플랜트
    DATA gt_out     TYPE zcl_mm_material_list=>tt_out.      " 조회 결과(ALV 출력)
    DATA g_alv      TYPE REF TO cl_salv_table.              " ALV

    METHODS build_sel
      RETURNING
        VALUE(rs_sel) TYPE zcl_mm_material_list=>ty_sel.

    METHODS display.

    METHODS set_columns
      RAISING
        cx_salv_not_found
        cx_salv_data_error.

    METHODS set_column_text
      IMPORTING
        io_columns TYPE REF TO cl_salv_columns_table
        iv_name    TYPE lvc_fname
        iv_text    TYPE csequence
      RAISING
        cx_salv_not_found.

    METHODS set_checkbox
      IMPORTING
        io_columns TYPE REF TO cl_salv_columns_table
        iv_name    TYPE lvc_fname
      RAISING
        cx_salv_not_found.
ENDCLASS.


CLASS lcl_report IMPLEMENTATION.

  METHOD run.
    DATA lt_allowed    TYPE zcl_mm_material_list=>tt_werks.
    DATA l_denied_msg  TYPE string.
    DATA l_trunc_msg   TYPE string.
    DATA l_msg         TYPE string.

    gs_sel = build_sel( ).
    g_list = NEW zcl_mm_material_list( gs_sel ).

    " 플랜트 권한 체크 (M_MATE_WRK, ACTVT 03)
    g_list->check_plant_authority(
      IMPORTING
        et_allowed = lt_allowed
        et_denied  = gt_denied ).

    IF lt_allowed IS INITIAL.
      MESSAGE '조회 권한이 있는 플랜트가 없습니다'(m01) TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    IF gt_denied IS NOT INITIAL.
      l_denied_msg = '권한 없는 플랜트 &1개를 제외했습니다'(m02).
      REPLACE '&1' IN l_denied_msg WITH |{ lines( gt_denied ) }|.
    ENDIF.

    gt_out = g_list->get_data( ).

    IF gt_out IS INITIAL.
      " 배치관리 조건으로 0건이 된 경우도 같은 메시지 (설계 10장)
      l_msg = '조회된 데이터가 없습니다'(m03).
      IF l_denied_msg IS NOT INITIAL.
        l_msg = |{ l_msg } ({ l_denied_msg })|.
      ENDIF.
      MESSAGE l_msg TYPE 'S' DISPLAY LIKE 'W'.
      RETURN.
    ENDIF.

    " 최대건수 도달 경고 (Q5)
    IF g_list->is_truncated( ) = abap_true.
      l_trunc_msg = '최대건수 &1건까지만 조회했습니다. 조건을 좁히거나 최대건수를 늘리세요'(m04).
      REPLACE '&1' IN l_trunc_msg WITH |{ gs_sel-maxhit NUMBER = USER }|.
    ENDIF.

    " 경고는 상태표시줄 1건으로 합쳐서 표시 (ALV 화면 진입 전 S 메시지)
    IF l_trunc_msg IS NOT INITIAL AND l_denied_msg IS NOT INITIAL.
      l_msg = |{ l_trunc_msg } / { l_denied_msg }|.
    ELSEIF l_trunc_msg IS NOT INITIAL.
      l_msg = l_trunc_msg.
    ELSE.
      l_msg = l_denied_msg.
    ENDIF.
    IF l_msg IS NOT INITIAL.
      MESSAGE l_msg TYPE 'S' DISPLAY LIKE 'W'.
    ENDIF.

    display( ).
  ENDMETHOD.


  METHOD build_sel.
    rs_sel = VALUE #(
      werks      = so_werks[]
      matnr      = so_matnr[]
      mtart      = so_mtart[]
      matkl      = so_matkl[]
      ernam      = so_ernam[]
      ersda      = so_ersda[]
      del_mode   = COND #( WHEN pa_delon = abap_true
                             THEN zcl_mm_material_list=>c_del_mode-del_only
                           WHEN pa_delal = abap_true
                             THEN zcl_mm_material_list=>c_del_mode-del_all
                           ELSE zcl_mm_material_list=>c_del_mode-del_exclude )
      " Q10에서 블록 B4가 빠지면 c_batch_mode-all 고정으로 바꿈
      batch_mode = COND #( WHEN pa_baton = abap_true
                             THEN zcl_mm_material_list=>c_batch_mode-only
                           WHEN pa_batof = abap_true
                             THEN zcl_mm_material_list=>c_batch_mode-none
                           ELSE zcl_mm_material_list=>c_batch_mode-all )
      spras      = pa_spras
      spras2     = pa_spra2
      maxhit     = pa_maxht ).
  ENDMETHOD.


  METHOD display.
    " CX_SALV_MSG / NOT_FOUND / DATA_ERROR / EXISTING 공통 슈퍼클래스 = CX_SALV_ERROR
    DATA l_error TYPE REF TO cx_salv_error.
    DATA l_text  TYPE string.

    TRY.
        cl_salv_table=>factory(
          IMPORTING
            r_salv_table = g_alv
          CHANGING
            t_table      = gt_out ).

        " 표준 기능(정렬, 필터, 합계, 엑셀 다운로드 등)
        g_alv->get_functions( )->set_all( abap_true ).
        g_alv->get_display_settings( )->set_striped_pattern( abap_true ).

        " 레이아웃 저장/기본 레이아웃 (KEY = SY-REPID = ZRMM0024)
        DATA(l_layout) = g_alv->get_layout( ).
        l_layout->set_key( VALUE salv_s_layout_key( report = sy-repid ) ).
        l_layout->set_save_restriction( if_salv_c_layout=>restrict_none ).
        l_layout->set_default( abap_true ).
        IF pa_vari IS NOT INITIAL.
          l_layout->set_initial_layout( pa_vari ).
        ENDIF.

        set_columns( ).

        " 더블클릭 -> MM03 (SET HANDLER ... FOR 에는 참조 변수를 넘김)
        DATA(l_events) = g_alv->get_event( ).
        SET HANDLER on_double_click FOR l_events.

        g_alv->display( ).

      CATCH cx_salv_msg cx_salv_not_found cx_salv_data_error cx_salv_existing INTO l_error.
        l_text = l_error->get_text( ).
        MESSAGE l_text TYPE 'S' DISPLAY LIKE 'E'.
    ENDTRY.
  ENDMETHOD.


  METHOD set_columns.
    DATA(l_columns) = g_alv->get_columns( ).

    " 컬럼 폭 최적화: 배치관리(고정 폭)만 제외하고 컬럼별로 적용
    " (전체 set_optimize는 개별 출력 길이를 덮어쓰므로 사용하지 않음)
    LOOP AT l_columns->get( ) INTO DATA(ls_column_ref).
      IF ls_column_ref-columnname <> 'XCHPF'.
        ls_column_ref-r_column->set_optimized( abap_true ).
      ENDIF.
    ENDLOOP.

    " 키 컬럼
    CAST cl_salv_column_table( l_columns->get_column( 'MATNR' ) )->set_key( abap_true ).
    CAST cl_salv_column_table( l_columns->get_column( 'WERKS' ) )->set_key( abap_true ).

    " 이동평균가: 통화 참조 (현업 확정 Q3, MBEW-VERPR)
    l_columns->get_column( 'VERPR' )->set_currency_column( 'WAERS' ).
    set_column_text( io_columns = l_columns iv_name = 'VERPR'
                     iv_text    = '이동평균가'(c01) ).

    " 삭제여부: MARC-LVORM 기준 (현업 확정 Q2), 체크박스(읽기 전용)
    set_column_text( io_columns = l_columns iv_name = 'LVORM'
                     iv_text    = '삭제여부'(c02) ).
    set_checkbox( io_columns = l_columns iv_name = 'LVORM' ).

    " 배치관리: MARC-XCHPF 기준 (Q9), 체크박스(읽기 전용), 출력 길이 고정
    set_column_text( io_columns = l_columns iv_name = 'XCHPF'
                     iv_text    = '배치관리'(c07) ).
    set_checkbox( io_columns = l_columns iv_name = 'XCHPF' ).
    l_columns->get_column( 'XCHPF' )->set_output_length( c_xchpf_out_len ).

    " 텍스트 컬럼명
    set_column_text( io_columns = l_columns iv_name = 'MAKTX'
                     iv_text    = '자재명'(c03) ).
    set_column_text( io_columns = l_columns iv_name = 'WGBEZ'
                     iv_text    = '자재그룹명'(c04) ).
    set_column_text( io_columns = l_columns iv_name = 'SPART_T'
                     iv_text    = '제품군명'(c05) ).
    set_column_text( io_columns = l_columns iv_name = 'MTBEZ'
                     iv_text    = '자재유형명'(c06) ).

    " 기본 숨김 컬럼 (레이아웃에서 표시 가능, 설계 9장)
    l_columns->get_column( 'SPART_T' )->set_visible( abap_false ).
    l_columns->get_column( 'MTART' )->set_visible( abap_false ).
    l_columns->get_column( 'MTBEZ' )->set_visible( abap_false ).
    l_columns->get_column( 'ERNAM' )->set_visible( abap_false ).
  ENDMETHOD.


  METHOD set_column_text.
    DATA(l_column) = io_columns->get_column( iv_name ).
    l_column->set_short_text( CONV scrtext_s( iv_text ) ).
    l_column->set_medium_text( CONV scrtext_m( iv_text ) ).
    l_column->set_long_text( CONV scrtext_l( iv_text ) ).
  ENDMETHOD.


  METHOD set_checkbox.
    " checkbox = 편집 불가 체크박스. checkbox_hotspot은 쓰지 않음 (설계 9장)
    CAST cl_salv_column_table( io_columns->get_column( iv_name ) )->set_cell_type(
      if_salv_c_cell_type=>checkbox ).
  ENDMETHOD.


  METHOD on_double_click.
    DATA l_auth_error TYPE REF TO cx_sy_authorization_error.
    DATA l_text       TYPE string.

    READ TABLE gt_out ASSIGNING FIELD-SYMBOL(<ls_out>) INDEX row.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    SET PARAMETER ID 'MAT' FIELD <ls_out>-matnr.
    SET PARAMETER ID 'WRK' FIELD <ls_out>-werks.

    TRY.
        CALL TRANSACTION c_tcode_mm03 WITH AUTHORITY-CHECK AND SKIP FIRST SCREEN.
      CATCH cx_sy_authorization_error INTO l_auth_error.
        l_text = l_auth_error->get_text( ).
        MESSAGE l_text TYPE 'S' DISPLAY LIKE 'E'.
    ENDTRY.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* INITIALIZATION
*----------------------------------------------------------------------*
INITIALIZATION.
  " 기본값은 클래스 상수에서 가져옴 (변형이 있으면 변형 값이 우선)
  pa_spras = sy-langu.
  pa_spra2 = zcl_mm_material_list=>c_default_spras2.
  pa_maxht = zcl_mm_material_list=>c_default_maxhit.

  gs_layout = cl_salv_layout_service=>get_default_layout(
                s_key    = VALUE #( report = sy-repid )
                restrict = if_salv_c_layout=>restrict_none ).
  pa_vari = gs_layout-layout.

*----------------------------------------------------------------------*
* 선택화면 검증
*----------------------------------------------------------------------*
AT SELECTION-SCREEN ON pa_maxht.
  IF pa_maxht < 0.
    MESSAGE '최대건수는 0 이상으로 입력하세요 (0 = 무제한)'(m05) TYPE 'E'.
  ENDIF.

AT SELECTION-SCREEN.
  " 자재명 언어 공란이면 로그온 언어
  IF pa_spras IS INITIAL.
    pa_spras = sy-langu.
  ENDIF.
  " 대체 언어가 1순위 언어와 같으면 공란 처리 (경고 없음, 설계 5장)
  IF pa_spra2 = pa_spras.
    CLEAR pa_spra2.
  ENDIF.

*----------------------------------------------------------------------*
* 레이아웃 F4
*----------------------------------------------------------------------*
AT SELECTION-SCREEN ON VALUE-REQUEST FOR pa_vari.
  gs_layout = cl_salv_layout_service=>f4_layouts(
                s_key    = VALUE #( report = sy-repid )
                restrict = if_salv_c_layout=>restrict_none ).
  IF gs_layout-layout IS NOT INITIAL.
    pa_vari = gs_layout-layout.
  ENDIF.

*----------------------------------------------------------------------*
* START-OF-SELECTION
*----------------------------------------------------------------------*
START-OF-SELECTION.
  NEW lcl_report( )->run( ).
