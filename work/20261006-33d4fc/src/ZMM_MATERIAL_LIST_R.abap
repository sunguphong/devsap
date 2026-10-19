*&---------------------------------------------------------------------*
*& Report ZMM_MATERIAL_LIST_R
*&---------------------------------------------------------------------*
*& 자재마스터 조회 리포트 (T-code ZMM_MATLIST 제안)
*& - 자재 x 플랜트 1행, 조회 전용 (DB 변경 없음)
*& - 현업 확정: Q1 플랜트 필수 / Q2 삭제여부 = MARC-LVORM
*&             Q3 단가 = 항상 MBEW-VERPR
*& - 미결(분석 가정·권장안): Q4 자재명 언어/대체 언어, Q5 최대건수
*&             Q9 배치관리 = MARC-XCHPF, Q10 배치관리 선택조건(블록 B4)
*& - 조회 로직: ZCL_MM_MATERIAL_LIST
*& - 대상: ECC(MATNR C18), SAP_BASIS 7.40 (SP09 이상 추정, 7.51 미만)
*&   2026-10-11 abap-mrd 조회 결과 기준
*&---------------------------------------------------------------------*
REPORT zmm_material_list_r.

*----------------------------------------------------------------------*
* 선택화면 참조용 변수 (DDIC 참조로 F4/검색도움말 사용)
*----------------------------------------------------------------------*
DATA: gv_werks TYPE marc-werks,
      gv_matnr TYPE mara-matnr,
      gv_mtart TYPE mara-mtart,
      gv_matkl TYPE mara-matkl,
      gv_ernam TYPE mara-ernam,
      gv_ersda TYPE mara-ersda.

*----------------------------------------------------------------------*
* 선택화면 (블록 순서 B1 → B2 → B4 → B3, 설계 5장)
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-b01.
  SELECT-OPTIONS: s_werks FOR gv_werks OBLIGATORY,   " 현업 확정 Q1
                  s_matnr FOR gv_matnr,
                  s_mtart FOR gv_mtart,
                  s_matkl FOR gv_matkl,
                  s_ernam FOR gv_ernam,
                  s_ersda FOR gv_ersda.
SELECTION-SCREEN END OF BLOCK b1.

" 삭제여부(플랜트) - MARC-LVORM 기준 (현업 확정 Q2)
SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-b02.
  PARAMETERS: p_del_ex RADIOBUTTON GROUP del DEFAULT 'X',
              p_del_on RADIOBUTTON GROUP del,
              p_del_al RADIOBUTTON GROUP del.
SELECTION-SCREEN END OF BLOCK b2.

" 배치관리(플랜트) - MARC-XCHPF 기준 (권장안, 현업 확인 대기 Q10)
SELECTION-SCREEN BEGIN OF BLOCK b4 WITH FRAME TITLE TEXT-b04.
  PARAMETERS: p_bat_al RADIOBUTTON GROUP bat DEFAULT 'X',
              p_bat_on RADIOBUTTON GROUP bat,
              p_bat_of RADIOBUTTON GROUP bat.
SELECTION-SCREEN END OF BLOCK b4.

" 출력 옵션
SELECTION-SCREEN BEGIN OF BLOCK b3 WITH FRAME TITLE TEXT-b03.
  PARAMETERS: p_spras  TYPE spras,                 " 자재명 언어 (Q4)
              p_spras2 TYPE spras,                 " 대체 언어 (공란 = 대체 안 함)
              p_maxhit TYPE i,                     " 최대건수 (0 = 무제한, Q5)
              p_vari   TYPE slis_vari.             " ALV 레이아웃 (CL_SALV_LAYOUT=>SET_INITIAL_LAYOUT 타입)
SELECTION-SCREEN END OF BLOCK b3.

*----------------------------------------------------------------------*
* 리포트 처리 클래스
*----------------------------------------------------------------------*
CLASS lcl_report DEFINITION FINAL.
  PUBLIC SECTION.
    CONSTANTS gc_tcode_mm03 TYPE sy-tcode VALUE 'MM03'.

    METHODS run.

    METHODS on_double_click
      FOR EVENT double_click OF cl_salv_events_table
      IMPORTING row column.

  PRIVATE SECTION.
    "! 배치관리 체크박스 컬럼 고정 출력 길이 (설계 9장)
    CONSTANTS gc_xchpf_out_len TYPE lvc_outlen VALUE '6'.

    DATA mt_out  TYPE zcl_mm_material_list=>tt_out.
    DATA mo_salv TYPE REF TO cl_salv_table.

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
    DATA lv_denied_msg TYPE string.
    DATA lv_trunc_msg  TYPE string.
    DATA lv_msg        TYPE string.

    DATA(ls_sel) = build_sel( ).
    DATA(lo_list) = NEW zcl_mm_material_list( ls_sel ).

    " 플랜트 권한 체크 (M_MATE_WRK, ACTVT 03)
    lo_list->check_plant_authority(
      IMPORTING
        et_allowed = DATA(lt_allowed)
        et_denied  = DATA(lt_denied) ).

    IF lt_allowed IS INITIAL.
      MESSAGE '조회 권한이 있는 플랜트가 없습니다'(m01) TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    IF lt_denied IS NOT INITIAL.
      lv_denied_msg = '권한 없는 플랜트 &1개를 제외했습니다'(m02).
      REPLACE '&1' IN lv_denied_msg WITH |{ lines( lt_denied ) }|.
    ENDIF.

    mt_out = lo_list->get_data( ).

    IF mt_out IS INITIAL.
      " 배치관리 조건으로 0건이 된 경우도 같은 메시지 (설계 10장)
      lv_msg = '조회된 데이터가 없습니다'(m03).
      IF lv_denied_msg IS NOT INITIAL.
        lv_msg = |{ lv_msg } ({ lv_denied_msg })|.
      ENDIF.
      MESSAGE lv_msg TYPE 'S' DISPLAY LIKE 'W'.
      RETURN.
    ENDIF.

    " 최대건수 도달 경고 (Q5)
    IF lo_list->is_truncated( ) = abap_true.
      lv_trunc_msg = '최대건수 &1건까지만 조회했습니다. 조건을 좁히거나 최대건수를 늘리세요'(m04).
      REPLACE '&1' IN lv_trunc_msg WITH |{ ls_sel-maxhit NUMBER = USER }|.
    ENDIF.

    " 경고는 상태표시줄 1건으로 합쳐서 표시 (ALV 화면 진입 전 S 메시지)
    IF lv_trunc_msg IS NOT INITIAL AND lv_denied_msg IS NOT INITIAL.
      lv_msg = |{ lv_trunc_msg } / { lv_denied_msg }|.
    ELSEIF lv_trunc_msg IS NOT INITIAL.
      lv_msg = lv_trunc_msg.
    ELSE.
      lv_msg = lv_denied_msg.
    ENDIF.
    IF lv_msg IS NOT INITIAL.
      MESSAGE lv_msg TYPE 'S' DISPLAY LIKE 'W'.
    ENDIF.

    display( ).
  ENDMETHOD.


  METHOD build_sel.
    rs_sel = VALUE #(
      werks      = s_werks[]
      matnr      = s_matnr[]
      mtart      = s_mtart[]
      matkl      = s_matkl[]
      ernam      = s_ernam[]
      ersda      = s_ersda[]
      del_mode   = COND #( WHEN p_del_on = abap_true
                             THEN zcl_mm_material_list=>gc_del_mode-del_only
                           WHEN p_del_al = abap_true
                             THEN zcl_mm_material_list=>gc_del_mode-del_all
                           ELSE zcl_mm_material_list=>gc_del_mode-del_exclude )
      " Q10에서 블록 B4가 빠지면 gc_batch_mode-all 고정으로 바꿈
      batch_mode = COND #( WHEN p_bat_on = abap_true
                             THEN zcl_mm_material_list=>gc_batch_mode-only
                           WHEN p_bat_of = abap_true
                             THEN zcl_mm_material_list=>gc_batch_mode-none
                           ELSE zcl_mm_material_list=>gc_batch_mode-all )
      spras      = p_spras
      spras2     = p_spras2
      maxhit     = p_maxhit ).
  ENDMETHOD.


  METHOD display.
    " CX_SALV_MSG / NOT_FOUND / DATA_ERROR / EXISTING 공통 슈퍼클래스 = CX_SALV_ERROR
    DATA lx_salv TYPE REF TO cx_salv_error.

    TRY.
        cl_salv_table=>factory(
          IMPORTING
            r_salv_table = mo_salv
          CHANGING
            t_table      = mt_out ).

        " 표준 기능(정렬, 필터, 합계, 엑셀 다운로드 등)
        mo_salv->get_functions( )->set_all( abap_true ).
        mo_salv->get_display_settings( )->set_striped_pattern( abap_true ).

        " 레이아웃 저장/기본 레이아웃
        DATA(lo_layout) = mo_salv->get_layout( ).
        lo_layout->set_key( VALUE salv_s_layout_key( report = sy-repid ) ).
        lo_layout->set_save_restriction( if_salv_c_layout=>restrict_none ).
        lo_layout->set_default( abap_true ).
        IF p_vari IS NOT INITIAL.
          lo_layout->set_initial_layout( p_vari ).
        ENDIF.

        set_columns( ).

        " 더블클릭 -> MM03 (SET HANDLER ... FOR 에는 참조 변수를 넘김)
        DATA(lo_events) = mo_salv->get_event( ).
        SET HANDLER on_double_click FOR lo_events.

        mo_salv->display( ).

      CATCH cx_salv_msg cx_salv_not_found cx_salv_data_error cx_salv_existing INTO lx_salv.
        DATA(lv_text) = lx_salv->get_text( ).
        MESSAGE lv_text TYPE 'S' DISPLAY LIKE 'E'.
    ENDTRY.
  ENDMETHOD.


  METHOD set_columns.
    DATA(lo_columns) = mo_salv->get_columns( ).

    " 컬럼 폭 최적화: 배치관리(고정 폭)만 제외하고 컬럼별로 적용
    " (전체 set_optimize는 개별 출력 길이를 덮어쓰므로 사용하지 않음)
    LOOP AT lo_columns->get( ) INTO DATA(ls_column_ref).
      IF ls_column_ref-columnname <> 'XCHPF'.
        ls_column_ref-r_column->set_optimized( abap_true ).
      ENDIF.
    ENDLOOP.

    " 키 컬럼
    CAST cl_salv_column_table( lo_columns->get_column( 'MATNR' ) )->set_key( abap_true ).
    CAST cl_salv_column_table( lo_columns->get_column( 'WERKS' ) )->set_key( abap_true ).

    " 이동평균가: 통화 참조 (현업 확정 Q3, MBEW-VERPR)
    lo_columns->get_column( 'VERPR' )->set_currency_column( 'WAERS' ).
    set_column_text( io_columns = lo_columns iv_name = 'VERPR'
                     iv_text    = '이동평균가'(c01) ).

    " 삭제여부: MARC-LVORM 기준 (현업 확정 Q2), 체크박스(읽기 전용)
    set_column_text( io_columns = lo_columns iv_name = 'LVORM'
                     iv_text    = '삭제여부'(c02) ).
    set_checkbox( io_columns = lo_columns iv_name = 'LVORM' ).

    " 배치관리: MARC-XCHPF 기준 (Q9), 체크박스(읽기 전용), 출력 길이 고정
    set_column_text( io_columns = lo_columns iv_name = 'XCHPF'
                     iv_text    = '배치관리'(c07) ).
    set_checkbox( io_columns = lo_columns iv_name = 'XCHPF' ).
    lo_columns->get_column( 'XCHPF' )->set_output_length( gc_xchpf_out_len ).

    " 텍스트 컬럼명
    set_column_text( io_columns = lo_columns iv_name = 'MAKTX'
                     iv_text    = '자재명'(c03) ).
    set_column_text( io_columns = lo_columns iv_name = 'WGBEZ'
                     iv_text    = '자재그룹명'(c04) ).
    set_column_text( io_columns = lo_columns iv_name = 'SPART_T'
                     iv_text    = '제품군명'(c05) ).
    set_column_text( io_columns = lo_columns iv_name = 'MTBEZ'
                     iv_text    = '자재유형명'(c06) ).

    " 기본 숨김 컬럼 (레이아웃에서 표시 가능, 설계 9장)
    lo_columns->get_column( 'SPART_T' )->set_visible( abap_false ).
    lo_columns->get_column( 'MTART' )->set_visible( abap_false ).
    lo_columns->get_column( 'MTBEZ' )->set_visible( abap_false ).
    lo_columns->get_column( 'ERNAM' )->set_visible( abap_false ).
  ENDMETHOD.


  METHOD set_column_text.
    DATA(lo_column) = io_columns->get_column( iv_name ).
    lo_column->set_short_text( CONV scrtext_s( iv_text ) ).
    lo_column->set_medium_text( CONV scrtext_m( iv_text ) ).
    lo_column->set_long_text( CONV scrtext_l( iv_text ) ).
  ENDMETHOD.


  METHOD set_checkbox.
    " checkbox = 편집 불가 체크박스. checkbox_hotspot은 쓰지 않음 (설계 9장)
    CAST cl_salv_column_table( io_columns->get_column( iv_name ) )->set_cell_type(
      if_salv_c_cell_type=>checkbox ).
  ENDMETHOD.


  METHOD on_double_click.
    READ TABLE mt_out ASSIGNING FIELD-SYMBOL(<ls_out>) INDEX row.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    SET PARAMETER ID 'MAT' FIELD <ls_out>-matnr.
    SET PARAMETER ID 'WRK' FIELD <ls_out>-werks.

    TRY.
        CALL TRANSACTION gc_tcode_mm03 WITH AUTHORITY-CHECK AND SKIP FIRST SCREEN.
      CATCH cx_sy_authorization_error INTO DATA(lx_auth).
        DATA(lv_text) = lx_auth->get_text( ).
        MESSAGE lv_text TYPE 'S' DISPLAY LIKE 'E'.
    ENDTRY.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* INITIALIZATION
*----------------------------------------------------------------------*
INITIALIZATION.
  " 기본값은 클래스 상수에서 가져옴 (변형이 있으면 변형 값이 우선)
  p_spras  = sy-langu.
  p_spras2 = zcl_mm_material_list=>gc_default_spras2.
  p_maxhit = zcl_mm_material_list=>gc_default_maxhit.

  DATA(gs_default_layout) = cl_salv_layout_service=>get_default_layout(
                              s_key    = VALUE #( report = sy-repid )
                              restrict = if_salv_c_layout=>restrict_none ).
  p_vari = gs_default_layout-layout.

*----------------------------------------------------------------------*
* 선택화면 검증
*----------------------------------------------------------------------*
AT SELECTION-SCREEN ON p_maxhit.
  IF p_maxhit < 0.
    MESSAGE '최대건수는 0 이상으로 입력하세요 (0 = 무제한)'(m05) TYPE 'E'.
  ENDIF.

AT SELECTION-SCREEN.
  " 자재명 언어 공란이면 로그온 언어
  IF p_spras IS INITIAL.
    p_spras = sy-langu.
  ENDIF.
  " 대체 언어가 1순위 언어와 같으면 공란 처리 (경고 없음, 설계 5장)
  IF p_spras2 = p_spras.
    CLEAR p_spras2.
  ENDIF.

*----------------------------------------------------------------------*
* 레이아웃 F4
*----------------------------------------------------------------------*
AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_vari.
  DATA(gs_f4_layout) = cl_salv_layout_service=>f4_layouts(
                         s_key    = VALUE #( report = sy-repid )
                         restrict = if_salv_c_layout=>restrict_none ).
  IF gs_f4_layout-layout IS NOT INITIAL.
    p_vari = gs_f4_layout-layout.
  ENDIF.

*----------------------------------------------------------------------*
* START-OF-SELECTION
*----------------------------------------------------------------------*
START-OF-SELECTION.
  NEW lcl_report( )->run( ).
