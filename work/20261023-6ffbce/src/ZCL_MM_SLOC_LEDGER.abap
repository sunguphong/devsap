CLASS zcl_mm_sloc_ledger DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

*----------------------------------------------------------------------*
* 저장위치별 수불부 계산 엔진 (ZRMM0057)
*  - 수불 대상 선별·이동 분류는 ZRMM0034F01 원문 기준
*    (스냅숏: srd-abap GetInclude 2026-10-24)
*  - 기초재고(기간말 이력), 가상 저장위치, 이전중, 배치 상세, 대사는
*    설계서 02_design.md 5.3~5.5, S11~S13 기준
*  - 파라미터 접두어(IV_/IS_/IT_/EV_/ET_/RV_/RT_/CS_)는 핸드북 규칙 없음
*    -> SAP 관례 적용
*----------------------------------------------------------------------*
  PUBLIC SECTION.

    TYPES:
      ty_r_werks TYPE RANGE OF mseg-werks,
      ty_r_matnr TYPE RANGE OF mseg-matnr,
      ty_r_lgort TYPE RANGE OF mseg-lgort,
      ty_r_mtart TYPE RANGE OF mara-mtart,
      ty_r_bustm TYPE RANGE OF mseg-bustm,
      ty_r_bwart TYPE RANGE OF mseg-bwart,
      ty_period  TYPE n LENGTH 6.

    " 선택 조건
    TYPES: BEGIN OF ty_s_sel,
             werks      TYPE ty_r_werks,
             budat_from TYPE mkpf-budat,
             budat_to   TYPE mkpf-budat,
             matnr      TYPE ty_r_matnr,
             lgort      TYPE ty_r_lgort,
             mtart      TYPE ty_r_mtart,
             xbustm     TYPE ty_r_bustm,   " 제외할 BUSTM (I 값으로 받음)
             bw_it      TYPE ty_r_bwart,   " 저장위치 이전중 출고 (313/314)
             bw_ir      TYPE ty_r_bwart,   " 저장위치 이전중 입고 (315/316)
             bw_pt      TYPE ty_r_bwart,   " 플랜트간 운송중 출고 (303/304)
             bw_pr      TYPE ty_r_bwart,   " 플랜트간 운송중 입고 (305/306)
             vsloc      TYPE abap_bool,    " 가상 저장위치 표시
             no_zero    TYPE abap_bool,    " 0 행 제외
           END OF ty_s_sel.

    " 자재문서 품목 (SELECT 목록과 같은 순서)
    TYPES: BEGIN OF ty_s_item,
             mblnr TYPE mseg-mblnr,
             mjahr TYPE mseg-mjahr,
             zeile TYPE mseg-zeile,
             budat TYPE mkpf-budat,
             werks TYPE mseg-werks,
             lgort TYPE mseg-lgort,
             charg TYPE mseg-charg,
             matnr TYPE mseg-matnr,
             bwart TYPE mseg-bwart,
             shkzg TYPE mseg-shkzg,
             menge TYPE mseg-menge,
             lmein TYPE mseg-meins,     " 입출고 단위 (원문 LMEIN)
             meins TYPE mara-meins,     " 기본단위 (원문 MEINS)
             sobkz TYPE mseg-sobkz,
             kzbew TYPE mseg-kzbew,
             kzzug TYPE mseg-kzzug,
             kzvbr TYPE mseg-kzvbr,
             wertu TYPE mseg-wertu,
             mengu TYPE mseg-mengu,
             umwrk TYPE mseg-umwrk,
             umlgo TYPE mseg-umlgo,
             ummat TYPE mseg-ummat,
             umcha TYPE mseg-umcha,
             umsok TYPE mseg-umsok,
             xauto TYPE mseg-xauto,
             bustm TYPE mseg-bustm,
             bustw TYPE mseg-bustw,
           END OF ty_s_item,
           ty_t_item TYPE STANDARD TABLE OF ty_s_item WITH DEFAULT KEY.

    " ZTMM0008 매핑 결과 (원문 156~165행 SELECT 결과 4필드)
    TYPES: BEGIN OF ty_s_map,
             grind TYPE ztmm0008-grind,
             giind TYPE ztmm0008-giind,
             tpind TYPE ztmm0008-tpind,
             shkzg TYPE ztmm0008-shkzg,
           END OF ty_s_map.

    " 집계 규칙 (이전중·운송중 이동유형, 가상 저장위치)
    TYPES: BEGIN OF ty_s_rule,
             bw_it TYPE ty_r_bwart,
             bw_ir TYPE ty_r_bwart,
             bw_pt TYPE ty_r_bwart,
             bw_pr TYPE ty_r_bwart,
             vsloc TYPE abap_bool,
           END OF ty_s_rule.

    " 이동 영향 (원문 ZTMM0069 수량 컬럼 + ZCLSTC + 이전중)
    TYPES: BEGIN OF ty_s_mov,
             zpo_gr TYPE mseg-menge,
             zpp_gr TYPE mseg-menge,
             ztp_gr TYPE mseg-menge,
             zre_gr TYPE mseg-menge,
             zot_gr TYPE mseg-menge,
             zsd_gi TYPE mseg-menge,
             zpp_gi TYPE mseg-menge,
             ztp_gi TYPE mseg-menge,
             zsp_gi TYPE mseg-menge,
             zot_gi TYPE mseg-menge,
             zclstc TYPE mseg-menge,    " 재고 증감 (원문 계산식)
             uml    TYPE mseg-menge,    " 이전중 증감 (설계 5.2 추가)
           END OF ty_s_mov.

    TYPES: BEGIN OF ty_s_delta,
             werks TYPE mseg-werks,
             matnr TYPE mseg-matnr,
             lgort TYPE mseg-lgort,
             charg TYPE mseg-charg,
             vsloc TYPE abap_bool,      " 가상 저장위치
             intra TYPE abap_bool,      " 같은 저장위치 배치 간 이동 (메인 제외)
             side  TYPE c LENGTH 1.     " O 자기 / C 상대(TPIND 2) / V 이전중·운송중
            INCLUDE TYPE ty_s_mov AS mov.
    TYPES: END OF ty_s_delta,
           ty_t_delta TYPE STANDARD TABLE OF ty_s_delta WITH DEFAULT KEY.

    " 수불 수량 (메인·배치 공통)
    TYPES: BEGIN OF ty_s_qty,
             beg_qty TYPE mseg-menge,
             zpo_gr  TYPE mseg-menge,
             zpp_gr  TYPE mseg-menge,
             ztp_gr  TYPE mseg-menge,
             zre_gr  TYPE mseg-menge,
             zot_gr  TYPE mseg-menge,
             gr_sum  TYPE mseg-menge,
             zsd_gi  TYPE mseg-menge,
             zpp_gi  TYPE mseg-menge,
             ztp_gi  TYPE mseg-menge,
             zsp_gi  TYPE mseg-menge,
             zot_gi  TYPE mseg-menge,
             gi_sum  TYPE mseg-menge,
             zclstc  TYPE mseg-menge,
             end_qty TYPE mseg-menge,
             uml_beg TYPE mseg-menge,
             uml_chg TYPE mseg-menge,
             uml_end TYPE mseg-menge,
           END OF ty_s_qty.

    TYPES: BEGIN OF ty_s_main,
             werks TYPE mseg-werks,
             name1 TYPE t001w-name1,
             matnr TYPE mseg-matnr,
             maktx TYPE makt-maktx,
             lgort TYPE mseg-lgort,
             lgobe TYPE t001l-lgobe,
             vsloc TYPE abap_bool,
             xchpf TYPE marc-xchpf,
             meins TYPE mara-meins.
            INCLUDE TYPE ty_s_qty AS qty.
    TYPES: END OF ty_s_main,
           ty_t_main TYPE STANDARD TABLE OF ty_s_main WITH DEFAULT KEY.

    TYPES: BEGIN OF ty_s_batch,
             werks TYPE mseg-werks,
             matnr TYPE mseg-matnr,
             maktx TYPE makt-maktx,
             lgort TYPE mseg-lgort,
             charg TYPE mseg-charg,
             meins TYPE mara-meins.
            INCLUDE TYPE ty_s_qty AS qty.
    TYPES: END OF ty_s_batch,
           ty_t_batch TYPE STANDARD TABLE OF ty_s_batch WITH DEFAULT KEY.

    TYPES: BEGIN OF ty_s_doc,
             kind   TYPE c LENGTH 1,    " B 기초분(월초~시작일 전날) / P 기간
             kindtx TYPE c LENGTH 10,   " 리포트가 채움
             budat  TYPE mkpf-budat,
             mblnr  TYPE mseg-mblnr,
             mjahr  TYPE mseg-mjahr,
             zeile  TYPE mseg-zeile,
             werks  TYPE mseg-werks,
             matnr  TYPE mseg-matnr,
             bwart  TYPE mseg-bwart,
             shkzg  TYPE mseg-shkzg,
             charg  TYPE mseg-charg,
             lgort  TYPE mseg-lgort,
             umlgo  TYPE mseg-umlgo,
             xauto  TYPE mseg-xauto,
             fname  TYPE fieldname,
             coltx  TYPE c LENGTH 20,   " 리포트가 채움
             value  TYPE mseg-menge,
             meins  TYPE mara-meins,
           END OF ty_s_doc,
           ty_t_doc TYPE STANDARD TABLE OF ty_s_doc WITH DEFAULT KEY.

    TYPES: BEGIN OF ty_s_recon,
             werks    TYPE mseg-werks,
             matnr    TYPE mseg-matnr,
             maktx    TYPE makt-maktx,
             meins    TYPE mara-meins,
             sloc_end TYPE mseg-menge,
             uml_end  TYPE mseg-menge,
             trns_end TYPE mseg-menge,
             calc_sum TYPE mseg-menge,
             val_qty  TYPE mbew-lbkum,
             diff     TYPE mbew-lbkum,
           END OF ty_s_recon,
           ty_t_recon TYPE STANDARD TABLE OF ty_s_recon WITH DEFAULT KEY.

    TYPES: BEGIN OF ty_s_key,
             werks TYPE mseg-werks,
             matnr TYPE mseg-matnr,
             lgort TYPE mseg-lgort,
           END OF ty_s_key,
           ty_t_key TYPE STANDARD TABLE OF ty_s_key WITH DEFAULT KEY.

    TYPES: BEGIN OF ty_s_dkey,
             werks TYPE mseg-werks,
             matnr TYPE mseg-matnr,
             lgort TYPE mseg-lgort,
             charg TYPE mseg-charg,
           END OF ty_s_dkey.

    TYPES: BEGIN OF ty_s_hist,
             period TYPE ty_period,
             qty    TYPE mseg-menge,
             uml    TYPE mseg-menge,
           END OF ty_s_hist,
           ty_t_hist TYPE STANDARD TABLE OF ty_s_hist WITH DEFAULT KEY.

    TYPES ty_t_fname TYPE STANDARD TABLE OF fieldname WITH DEFAULT KEY.

    CONSTANTS:
      c_vsloc_trns      TYPE mseg-lgort VALUE 'TRNS',
      c_vsloc_unkn      TYPE mseg-lgort VALUE 'ZZZZ',
      c_vorsl_bsx       TYPE t156w-vorsl VALUE 'BSX',
      c_bustm_ma02      TYPE mseg-bustm VALUE 'MA02',
      c_bustm_ma05      TYPE mseg-bustm VALUE 'MA05',
      c_bwart_303       TYPE mseg-bwart VALUE '303',
      c_bwart_304       TYPE mseg-bwart VALUE '304',
      c_bwart_305       TYPE mseg-bwart VALUE '305',
      c_bwart_306       TYPE mseg-bwart VALUE '306',
      c_bwart_313       TYPE mseg-bwart VALUE '313',
      c_bwart_314       TYPE mseg-bwart VALUE '314',
      c_bwart_315       TYPE mseg-bwart VALUE '315',
      c_bwart_316       TYPE mseg-bwart VALUE '316',
      c_max_days_dialog TYPE i VALUE 92,
      " ZTMM0008 구분값 (원문 245~275, 598~631, 690~729행)
      c_tpind_1         TYPE ztmm0008-tpind VALUE '1',
      c_tpind_2         TYPE ztmm0008-tpind VALUE '2',
      c_grind_po        TYPE ztmm0008-grind VALUE '1',   " 구매입고
      c_grind_pp        TYPE ztmm0008-grind VALUE '2',   " 생산입고
      c_grind_re        TYPE ztmm0008-grind VALUE '3',   " 고객반품입고
      c_grind_ot        TYPE ztmm0008-grind VALUE '4',   " 기타입고
      c_giind_sd        TYPE ztmm0008-giind VALUE '1',   " 판매출고
      c_giind_pp        TYPE ztmm0008-giind VALUE '2',   " 생산출고
      c_giind_sp        TYPE ztmm0008-giind VALUE '3',   " ZSP출고
      c_giind_ot        TYPE ztmm0008-giind VALUE '4',   " 기타출고
      c_shkzg_s         TYPE mseg-shkzg VALUE 'S',
      c_shkzg_h         TYPE mseg-shkzg VALUE 'H',
      c_xauto_x         TYPE mseg-xauto VALUE 'X',
      c_xauto_u         TYPE mseg-xauto VALUE 'U',
      c_side_own        TYPE c LENGTH 1 VALUE 'O',
      c_side_cpt        TYPE c LENGTH 1 VALUE 'C',
      c_side_ovl        TYPE c LENGTH 1 VALUE 'V',
      c_kind_beg        TYPE c LENGTH 1 VALUE 'B',
      c_kind_per        TYPE c LENGTH 1 VALUE 'P',
      c_fn_zpo_gr       TYPE fieldname VALUE 'ZPO_GR',
      c_fn_zpp_gr       TYPE fieldname VALUE 'ZPP_GR',
      c_fn_ztp_gr       TYPE fieldname VALUE 'ZTP_GR',
      c_fn_zre_gr       TYPE fieldname VALUE 'ZRE_GR',
      c_fn_zot_gr       TYPE fieldname VALUE 'ZOT_GR',
      c_fn_zsd_gi       TYPE fieldname VALUE 'ZSD_GI',
      c_fn_zpp_gi       TYPE fieldname VALUE 'ZPP_GI',
      c_fn_ztp_gi       TYPE fieldname VALUE 'ZTP_GI',
      c_fn_zsp_gi       TYPE fieldname VALUE 'ZSP_GI',
      c_fn_zot_gi       TYPE fieldname VALUE 'ZOT_GI',
      c_fn_zclstc       TYPE fieldname VALUE 'ZCLSTC',
      c_fn_uml          TYPE fieldname VALUE 'UML',
      c_sign_i          TYPE c LENGTH 1 VALUE 'I',
      c_sign_e          TYPE c LENGTH 1 VALUE 'E',
      c_opt_eq          TYPE c LENGTH 2 VALUE 'EQ',
      c_auth_wwa        TYPE c LENGTH 10 VALUE 'M_MSEG_WWA',
      c_actvt_disp      TYPE c LENGTH 2 VALUE '03',
      c_pkg_size        TYPE i VALUE 20000.

    METHODS constructor
      IMPORTING
        is_sel TYPE ty_s_sel.

    METHODS check_plants
      EXPORTING
        ev_exist   TYPE i
        ev_allowed TYPE i
        ev_denied  TYPE i.

    METHODS run
      RETURNING
        VALUE(rt_main) TYPE ty_t_main.

    METHODS get_sel
      RETURNING
        VALUE(rs_sel) TYPE ty_s_sel.

    METHODS get_unmapped_count
      RETURNING
        VALUE(rv_count) TYPE i.

    METHODS get_conv_error_count
      RETURNING
        VALUE(rv_count) TYPE i.

    METHODS get_batch
      IMPORTING
        it_key      TYPE ty_t_key
      EXPORTING
        et_batch    TYPE ty_t_batch
        et_diff_key TYPE ty_t_key
        ev_diff_qty TYPE mseg-menge.

    METHODS get_docs
      IMPORTING
        is_key        TYPE ty_s_dkey
      RETURNING
        VALUE(rt_doc) TYPE ty_t_doc.

    METHODS get_recon
      IMPORTING
        it_key   TYPE ty_t_key
      EXPORTING
        et_recon TYPE ty_t_recon
        ev_ok    TYPE abap_bool.

    " ---- 정적 규칙 메서드 (DB 없음, ABAP Unit 대상) ----
    CLASS-METHODS build_deltas
      IMPORTING
        is_item         TYPE ty_s_item
        is_map          TYPE ty_s_map
        is_rule         TYPE ty_s_rule
      RETURNING
        VALUE(rt_delta) TYPE ty_t_delta.

    CLASS-METHODS resolve_vsloc
      IMPORTING
        is_item         TYPE ty_s_item
      RETURNING
        VALUE(rv_lgort) TYPE mseg-lgort.

    CLASS-METHODS gr_column
      IMPORTING
        iv_grind        TYPE ztmm0008-grind
      RETURNING
        VALUE(rv_fname) TYPE fieldname.

    CLASS-METHODS gi_column
      IMPORTING
        iv_giind        TYPE ztmm0008-giind
      RETURNING
        VALUE(rv_fname) TYPE fieldname.

    CLASS-METHODS pick_period_end
      IMPORTING
        it_hist        TYPE ty_t_hist
        iv_period      TYPE ty_period
        is_cur         TYPE ty_s_hist
      RETURNING
        VALUE(rs_hist) TYPE ty_s_hist.

    CLASS-METHODS prev_period
      IMPORTING
        iv_date          TYPE sy-datum
      RETURNING
        VALUE(rv_period) TYPE ty_period.

    CLASS-METHODS month_start
      IMPORTING
        iv_date        TYPE sy-datum
      RETURNING
        VALUE(rv_date) TYPE sy-datum.

    CLASS-METHODS to_period
      IMPORTING
        iv_gja           TYPE mard-lfgja
        iv_mon           TYPE mard-lfmon
      RETURNING
        VALUE(rv_period) TYPE ty_period.

    CLASS-METHODS apply_delta
      IMPORTING
        is_delta  TYPE ty_s_delta
        iv_before TYPE abap_bool
      CHANGING
        cs_qty    TYPE ty_s_qty.

    CLASS-METHODS finalize
      CHANGING
        cs_qty TYPE ty_s_qty.

    CLASS-METHODS is_zero
      IMPORTING
        is_qty         TYPE ty_s_qty
      RETURNING
        VALUE(rv_zero) TYPE abap_bool.

    CLASS-METHODS to_exclude_range
      IMPORTING
        it_bustm        TYPE ty_r_bustm
      RETURNING
        VALUE(rt_bustm) TYPE ty_r_bustm.

    CLASS-METHODS mov_fields
      RETURNING
        VALUE(rt_fname) TYPE ty_t_fname.

  PRIVATE SECTION.

    TYPES: BEGIN OF ty_s_map_db,
             bwart TYPE ztmm0008-bwart,
             wertu TYPE ztmm0008-wertu,
             mengu TYPE ztmm0008-mengu,
             sobkz TYPE ztmm0008-sobkz,
             kzbew TYPE ztmm0008-kzbew,
             kzzug TYPE ztmm0008-kzzug,
             kzvbr TYPE ztmm0008-kzvbr,
             grind TYPE ztmm0008-grind,
             giind TYPE ztmm0008-giind,
             tpind TYPE ztmm0008-tpind,
             shkzg TYPE ztmm0008-shkzg,
           END OF ty_s_map_db,
           ty_t_map_db TYPE STANDARD TABLE OF ty_s_map_db WITH DEFAULT KEY,
           ty_h_map    TYPE HASHED TABLE OF ty_s_map_db
                         WITH UNIQUE KEY bwart wertu mengu sobkz kzbew kzzug kzvbr.

    TYPES: BEGIN OF ty_s_bsx,
             bustw TYPE t156w-bustw,
             xbgbb TYPE t156w-xbgbb,
           END OF ty_s_bsx,
           ty_t_bsx TYPE STANDARD TABLE OF ty_s_bsx WITH DEFAULT KEY,
           ty_h_bsx TYPE HASHED TABLE OF ty_s_bsx WITH UNIQUE KEY bustw xbgbb.

    TYPES: BEGIN OF ty_s_bal,
             werks TYPE mseg-werks,
             matnr TYPE mseg-matnr,
             lgort TYPE mseg-lgort,
             charg TYPE mseg-charg,
             vsloc TYPE abap_bool.
            INCLUDE TYPE ty_s_qty AS qty.
    TYPES: END OF ty_s_bal,
           ty_h_bal TYPE HASHED TABLE OF ty_s_bal WITH UNIQUE KEY werks matnr lgort charg.

    TYPES: BEGIN OF ty_s_makt,
             matnr TYPE makt-matnr,
             maktx TYPE makt-maktx,
           END OF ty_s_makt,
           ty_h_makt TYPE HASHED TABLE OF ty_s_makt WITH UNIQUE KEY matnr.

    TYPES: BEGIN OF ty_s_mara,
             matnr TYPE mara-matnr,
             meins TYPE mara-meins,
           END OF ty_s_mara,
           ty_h_mara TYPE HASHED TABLE OF ty_s_mara WITH UNIQUE KEY matnr.

    TYPES: BEGIN OF ty_s_marc,
             matnr TYPE marc-matnr,
             werks TYPE marc-werks,
             xchpf TYPE marc-xchpf,
           END OF ty_s_marc,
           ty_h_marc TYPE HASHED TABLE OF ty_s_marc WITH UNIQUE KEY matnr werks.

    TYPES: BEGIN OF ty_s_t001w,
             werks TYPE t001w-werks,
             name1 TYPE t001w-name1,
           END OF ty_s_t001w,
           ty_h_t001w TYPE HASHED TABLE OF ty_s_t001w WITH UNIQUE KEY werks.

    TYPES: BEGIN OF ty_s_t001l,
             werks TYPE t001l-werks,
             lgort TYPE t001l-lgort,
             lgobe TYPE t001l-lgobe,
           END OF ty_s_t001l,
           ty_h_t001l TYPE HASHED TABLE OF ty_s_t001l WITH UNIQUE KEY werks lgort.

    TYPES: BEGIN OF ty_s_wm,
             werks TYPE mseg-werks,
             matnr TYPE mseg-matnr,
           END OF ty_s_wm,
           ty_t_wm TYPE STANDARD TABLE OF ty_s_wm WITH DEFAULT KEY.

    DATA gs_sel TYPE ty_s_sel.
    DATA gs_rule TYPE ty_s_rule.
    DATA r_bustm TYPE ty_r_bustm.
    DATA g_month_start TYPE sy-datum.
    DATA g_period_x TYPE ty_period.
    DATA g_checked TYPE abap_bool.
    DATA g_loaded TYPE abap_bool.
    DATA g_unmapped TYPE i.
    DATA g_conv_err TYPE i.
    DATA gt_map TYPE ty_h_map.
    DATA gt_bsx TYPE ty_h_bsx.
    DATA gt_sloc TYPE ty_h_bal.
    DATA gt_bal TYPE ty_h_bal.
    DATA gt_main TYPE ty_t_main.
    DATA gt_makt TYPE ty_h_makt.
    DATA gt_mara TYPE ty_h_mara.
    DATA gt_marc TYPE ty_h_marc.

    METHODS read_mapping.
    METHODS read_bsx.
    METHODS read_movements.
    METHODS read_open_sloc.
    METHODS read_open_trns.
    METHODS read_texts.
    METHODS build_main.

    METHODS handle_item
      IMPORTING
        is_item         TYPE ty_s_item
        iv_count        TYPE abap_bool
      RETURNING
        VALUE(rt_delta) TYPE ty_t_delta.

    METHODS convert_unit
      EXPORTING
        ev_ok   TYPE abap_bool
      CHANGING
        cs_item TYPE ty_s_item.

    CLASS-METHODS post_delta
      IMPORTING
        is_delta  TYPE ty_s_delta
        iv_before TYPE abap_bool
        iv_charg  TYPE mseg-charg
      CHANGING
        ct_bal    TYPE ty_h_bal.

    CLASS-METHODS post_begin
      IMPORTING
        iv_werks TYPE mseg-werks
        iv_matnr TYPE mseg-matnr
        iv_lgort TYPE mseg-lgort
        iv_charg TYPE mseg-charg
        iv_vsloc TYPE abap_bool
        is_hist  TYPE ty_s_hist
      CHANGING
        ct_bal   TYPE ty_h_bal.

    CLASS-METHODS add_to_column
      IMPORTING
        iv_fname TYPE fieldname
        iv_value TYPE mseg-menge
      CHANGING
        cs_mov   TYPE ty_s_mov.

ENDCLASS.



CLASS zcl_mm_sloc_ledger IMPLEMENTATION.


  METHOD constructor.
    gs_sel = is_sel.
    " 종료일 공란 -> 시작일 (설계 7.3)
    IF gs_sel-budat_to IS INITIAL.
      gs_sel-budat_to = gs_sel-budat_from.
    ENDIF.
    r_bustm = to_exclude_range( gs_sel-xbustm ).

    gs_rule-bw_it = gs_sel-bw_it.
    gs_rule-bw_ir = gs_sel-bw_ir.
    gs_rule-bw_pt = gs_sel-bw_pt.
    gs_rule-bw_pr = gs_sel-bw_pr.
    gs_rule-vsloc = gs_sel-vsloc.

    IF gs_sel-budat_from IS NOT INITIAL.
      g_month_start = month_start( gs_sel-budat_from ).
      g_period_x    = prev_period( gs_sel-budat_from ).
    ENDIF.
    g_checked = abap_false.
  ENDMETHOD.


  METHOD check_plants.
    DATA: lt_werks TYPE STANDARD TABLE OF t001w-werks WITH DEFAULT KEY,
          ls_werks LIKE LINE OF gs_sel-werks,
          lt_allow TYPE ty_r_werks.

    CLEAR: ev_exist, ev_allowed, ev_denied.
    g_checked = abap_false.

    " 빈 range 로 전체 플랜트를 읽지 않게 막음 (wiki 가드)
    IF gs_sel-werks IS INITIAL.
      RETURN.
    ENDIF.

    SELECT werks FROM t001w
      INTO TABLE @lt_werks
      WHERE werks IN @gs_sel-werks.
    ev_exist = lines( lt_werks ).

    LOOP AT lt_werks INTO DATA(l_werks).
      AUTHORITY-CHECK OBJECT c_auth_wwa
        ID 'ACTVT' FIELD c_actvt_disp
        ID 'WERKS' FIELD l_werks.
      IF sy-subrc = 0.
        CLEAR ls_werks.
        ls_werks-sign   = c_sign_i.
        ls_werks-option = c_opt_eq.
        ls_werks-low    = l_werks.
        APPEND ls_werks TO lt_allow.
      ELSE.
        ev_denied = ev_denied + 1.
      ENDIF.
    ENDLOOP.

    ev_allowed = lines( lt_allow ).
    " 내부 플랜트 range = 허용 플랜트 EQ 목록 (설계 S3)
    gs_sel-werks = lt_allow.
    IF ev_allowed > 0.
      g_checked = abap_true.
    ENDIF.
  ENDMETHOD.


  METHOD run.
    CLEAR: gt_sloc, gt_bal, gt_main, gt_makt, gt_mara, gt_marc,
           g_unmapped, g_conv_err.
    g_loaded = abap_false.

    " check_plants 전이거나 허용 플랜트가 없으면 조회하지 않음
    IF g_checked = abap_false OR gs_sel-werks IS INITIAL
       OR gs_sel-budat_from IS INITIAL.
      RETURN.
    ENDIF.

    read_mapping( ).
    read_bsx( ).
    read_movements( ).
    read_open_sloc( ).
    IF gs_rule-vsloc = abap_true AND c_vsloc_trns IN gs_sel-lgort.
      read_open_trns( ).
    ENDIF.

    LOOP AT gt_sloc ASSIGNING FIELD-SYMBOL(<ls_sloc>).
      finalize( CHANGING cs_qty = <ls_sloc>-qty ).
    ENDLOOP.

    build_main( ).
    g_loaded = abap_true.
    rt_main = gt_main.
  ENDMETHOD.


  METHOD get_sel.
    rs_sel = gs_sel.
  ENDMETHOD.


  METHOD get_unmapped_count.
    rv_count = g_unmapped.
  ENDMETHOD.


  METHOD get_conv_error_count.
    rv_count = g_conv_err.
  ENDMETHOD.


  METHOD read_mapping.
    DATA lt_map TYPE ty_t_map_db.

    " 원문 156~165행: ZTMM0008 키 7필드 -> GRIND GIIND TPIND SHKZG
    SELECT bwart, wertu, mengu, sobkz, kzbew, kzzug, kzvbr,
           grind, giind, tpind, shkzg
      FROM ztmm0008
      INTO TABLE @lt_map.

    SORT lt_map BY bwart wertu mengu sobkz kzbew kzzug kzvbr.
    DELETE ADJACENT DUPLICATES FROM lt_map
      COMPARING bwart wertu mengu sobkz kzbew kzzug kzvbr.
    gt_map = lt_map.
  ENDMETHOD.


  METHOD read_bsx.
    DATA lt_bsx TYPE ty_t_bsx.

    " 원문 143~150행: T156W VORSL = 'BSX' 의 BUSTW + XBGBB
    SELECT bustw, xbgbb
      FROM t156w
      INTO TABLE @lt_bsx
      WHERE vorsl = @c_vorsl_bsx.

    SORT lt_bsx BY bustw xbgbb.
    DELETE ADJACENT DUPLICATES FROM lt_bsx COMPARING bustw xbgbb.
    DELETE lt_bsx WHERE bustw IS INITIAL.
    gt_bsx = lt_bsx.
  ENDMETHOD.


  METHOD read_movements.
    DATA: l_cursor TYPE cursor,
          l_before TYPE abap_bool,
          lt_item  TYPE ty_t_item,
          lt_delta TYPE ty_t_delta.

    " 커서는 7.40 전 SP 호환을 위해 기존 Open SQL 형식으로 씀
    " 기간: 시작월 1일 ~ 종료일 (월초~시작일 전날 이동은 기초에 반영)
    " WERKS OR UMWRK: TPIND 2 상대 위치 반영(원문 1185~1226행)용
    OPEN CURSOR l_cursor FOR
      SELECT b~mblnr b~mjahr b~zeile a~budat b~werks b~lgort b~charg
             b~matnr b~bwart b~shkzg b~menge b~meins AS lmein
             c~meins AS meins b~sobkz b~kzbew b~kzzug b~kzvbr
             b~wertu b~mengu b~umwrk b~umlgo b~ummat b~umcha
             b~umsok b~xauto b~bustm b~bustw
        FROM mkpf AS a
        INNER JOIN mseg AS b ON b~mblnr = a~mblnr
                            AND b~mjahr = a~mjahr
        INNER JOIN mara AS c ON c~matnr = b~matnr
        WHERE a~budat BETWEEN g_month_start AND gs_sel-budat_to
          AND ( b~werks IN gs_sel-werks OR b~umwrk IN gs_sel-werks )
          AND b~matnr IN gs_sel-matnr
          AND b~matnr <> space
          AND b~bustm IN r_bustm
          AND c~mtart IN gs_sel-mtart.

    DO.
      FETCH NEXT CURSOR l_cursor INTO TABLE lt_item PACKAGE SIZE c_pkg_size.
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.

      LOOP AT lt_item ASSIGNING FIELD-SYMBOL(<ls_item>).
        lt_delta = handle_item( is_item = <ls_item> iv_count = abap_true ).
        IF lt_delta IS INITIAL.
          CONTINUE.
        ENDIF.
        l_before = boolc( <ls_item>-budat < gs_sel-budat_from ).
        LOOP AT lt_delta ASSIGNING FIELD-SYMBOL(<ls_delta>).
          " 배치 레벨: 모든 델타 (intra 포함)
          post_delta( EXPORTING is_delta  = <ls_delta>
                                iv_before = l_before
                                iv_charg  = <ls_delta>-charg
                      CHANGING  ct_bal    = gt_bal ).
          " 저장위치 레벨: intra 제외 (원문 583행 건너뜀과 같은 결과)
          IF <ls_delta>-intra = abap_false.
            post_delta( EXPORTING is_delta  = <ls_delta>
                                  iv_before = l_before
                                  iv_charg  = space
                        CHANGING  ct_bal    = gt_sloc ).
          ENDIF.
        ENDLOOP.
      ENDLOOP.
    ENDDO.

    CLOSE CURSOR l_cursor.
  ENDMETHOD.


  METHOD handle_item.
    DATA: ls_item    TYPE ty_s_item,
          ls_map     TYPE ty_s_map,
          l_xbgbb    TYPE t156w-xbgbb,
          l_conv_ok  TYPE abap_bool.

    ls_item = is_item.

    " 1) T156W 재고계정 전기 여부 (원문 172~183행)
    "    XBGBB = MSEG-XAUTO, XAUTO 'U' 는 공란으로 비교
    l_xbgbb = ls_item-xauto.
    IF ls_item-xauto = c_xauto_u.
      CLEAR l_xbgbb.
    ENDIF.
    READ TABLE gt_bsx
      WITH TABLE KEY bustw = ls_item-bustw
                     xbgbb = l_xbgbb
      TRANSPORTING NO FIELDS.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    " 2) ZTMM0008 매핑 (원문 156~170행). 없음 또는 3구분 공란이면 제외
    READ TABLE gt_map ASSIGNING FIELD-SYMBOL(<ls_map>)
      WITH TABLE KEY bwart = ls_item-bwart
                     wertu = ls_item-wertu
                     mengu = ls_item-mengu
                     sobkz = ls_item-sobkz
                     kzbew = ls_item-kzbew
                     kzzug = ls_item-kzzug
                     kzvbr = ls_item-kzvbr.
    IF sy-subrc = 0.
      ls_map-grind = <ls_map>-grind.
      ls_map-giind = <ls_map>-giind.
      ls_map-tpind = <ls_map>-tpind.
      ls_map-shkzg = <ls_map>-shkzg.
    ENDIF.
    IF ls_map-grind IS INITIAL AND ls_map-giind IS INITIAL
       AND ls_map-tpind IS INITIAL.
      " 재고계정 전기인데 매핑이 없는 품목 수 (자기 플랜트 기준)
      IF iv_count = abap_true AND ls_item-werks IN gs_sel-werks.
        g_unmapped = g_unmapped + 1.
      ENDIF.
      RETURN.
    ENDIF.

    " 3) 입출고 단위 <> 기본단위면 기본단위로 변환 (원문 185~198행)
    IF ls_item-lmein <> ls_item-meins.
      convert_unit( IMPORTING ev_ok   = l_conv_ok
                    CHANGING  cs_item = ls_item ).
      IF l_conv_ok = abap_false AND iv_count = abap_true.
        g_conv_err = g_conv_err + 1.
      ENDIF.
    ENDIF.

    " 4) 분류 -> 델타
    rt_delta = build_deltas( is_item = ls_item
                             is_map  = ls_map
                             is_rule = gs_rule ).

    " 5) 대상 키 필터: 허용 플랜트, 저장위치 조건(가상 코드 포함)
    DELETE rt_delta WHERE werks NOT IN gs_sel-werks
                       OR lgort NOT IN gs_sel-lgort.
  ENDMETHOD.


  METHOD convert_unit.
    DATA: l_old TYPE plfh-mgvgw,
          l_new TYPE plfh-mgvgw.

    ev_ok = abap_false.
    l_old = cs_item-menge.

    " 원문 187~197행과 같은 호출
    CALL FUNCTION 'CF_UT_UNIT_CONVERSION'
      EXPORTING
        matnr_imp     = cs_item-matnr
        unit_new_imp  = cs_item-meins
        unit_old_imp  = cs_item-lmein
        value_old_imp = l_old
      IMPORTING
        value_new_exp = l_new
      EXCEPTIONS
        overflow      = 1
        OTHERS        = 2.
    IF sy-subrc = 0.
      cs_item-menge = l_new.
      ev_ok = abap_true.
    ENDIF.
    " 실패하면 원문처럼 원래 수량을 그대로 씀
  ENDMETHOD.


  METHOD read_open_sloc.
    TYPES: BEGIN OF lty_s_mard,
             werks TYPE mard-werks,
             matnr TYPE mard-matnr,
             lgort TYPE mard-lgort,
             lfgja TYPE mard-lfgja,
             lfmon TYPE mard-lfmon,
             labst TYPE mard-labst,
             insme TYPE mard-insme,
             einme TYPE mard-einme,
             speme TYPE mard-speme,
             retme TYPE mard-retme,
             umlme TYPE mard-umlme,
           END OF lty_s_mard.
    DATA: lt_mard  TYPE STANDARD TABLE OF lty_s_mard WITH DEFAULT KEY,
          lt_mardh TYPE SORTED TABLE OF lty_s_mard
                     WITH NON-UNIQUE KEY werks matnr lgort,
          lt_hist  TYPE ty_t_hist,
          ls_hist  TYPE ty_s_hist,
          ls_cur   TYPE ty_s_hist,
          ls_end   TYPE ty_s_hist,
          l_gja    TYPE mard-lfgja,
          l_mon    TYPE mard-lfmon.

    l_gja = g_period_x(4).
    l_mon = g_period_x+4(2).

    " 기초 드라이버: 이동이 없어도 재고가 있는 행이 나와야 함 (설계 S7)
    SELECT a~werks, a~matnr, a~lgort, a~lfgja, a~lfmon,
           a~labst, a~insme, a~einme, a~speme, a~retme, a~umlme
      FROM mard AS a
      INNER JOIN mara AS c ON c~matnr = a~matnr
      INTO TABLE @lt_mard
      WHERE a~werks IN @gs_sel-werks
        AND a~matnr IN @gs_sel-matnr
        AND a~lgort IN @gs_sel-lgort
        AND c~mtart IN @gs_sel-mtart.
    IF lt_mard IS INITIAL.
      RETURN.
    ENDIF.

    " 기간 >= X 인 이력만 (pick_period_end 규칙: 이상 가장 이른 레코드)
    SELECT a~werks, a~matnr, a~lgort, a~lfgja, a~lfmon,
           a~labst, a~insme, a~einme, a~speme, a~retme, a~umlme
      FROM mardh AS a
      INNER JOIN mara AS c ON c~matnr = a~matnr
      INTO TABLE @lt_mardh
      WHERE a~werks IN @gs_sel-werks
        AND a~matnr IN @gs_sel-matnr
        AND a~lgort IN @gs_sel-lgort
        AND c~mtart IN @gs_sel-mtart
        AND ( a~lfgja > @l_gja OR ( a~lfgja = @l_gja AND a~lfmon >= @l_mon ) ).

    LOOP AT lt_mard ASSIGNING FIELD-SYMBOL(<ls_mard>).
      CLEAR lt_hist.
      LOOP AT lt_mardh ASSIGNING FIELD-SYMBOL(<ls_mardh>)
           WHERE werks = <ls_mard>-werks
             AND matnr = <ls_mard>-matnr
             AND lgort = <ls_mard>-lgort.
        CLEAR ls_hist.
        ls_hist-period = to_period( iv_gja = <ls_mardh>-lfgja iv_mon = <ls_mardh>-lfmon ).
        " 재고 범위: 재고유형 합계 (설계 5.4, Q11 팀장 확인 사항)
        ls_hist-qty = <ls_mardh>-labst + <ls_mardh>-insme + <ls_mardh>-einme
                    + <ls_mardh>-speme + <ls_mardh>-retme.
        ls_hist-uml = <ls_mardh>-umlme.
        APPEND ls_hist TO lt_hist.
      ENDLOOP.

      CLEAR ls_cur.
      ls_cur-period = to_period( iv_gja = <ls_mard>-lfgja iv_mon = <ls_mard>-lfmon ).
      ls_cur-qty = <ls_mard>-labst + <ls_mard>-insme + <ls_mard>-einme
                 + <ls_mard>-speme + <ls_mard>-retme.
      ls_cur-uml = <ls_mard>-umlme.

      ls_end = pick_period_end( it_hist   = lt_hist
                                iv_period = g_period_x
                                is_cur    = ls_cur ).

      post_begin( EXPORTING iv_werks = <ls_mard>-werks
                            iv_matnr = <ls_mard>-matnr
                            iv_lgort = <ls_mard>-lgort
                            iv_charg = space
                            iv_vsloc = abap_false
                            is_hist  = ls_end
                  CHANGING  ct_bal   = gt_sloc ).
    ENDLOOP.
  ENDMETHOD.


  METHOD read_open_trns.
    TYPES: BEGIN OF lty_s_marc,
             werks TYPE marc-werks,
             matnr TYPE marc-matnr,
             lfgja TYPE marc-lfgja,
             lfmon TYPE marc-lfmon,
             umlmc TYPE marc-umlmc,
             trame TYPE marc-trame,
           END OF lty_s_marc.
    DATA: lt_marc  TYPE STANDARD TABLE OF lty_s_marc WITH DEFAULT KEY,
          lt_march TYPE SORTED TABLE OF lty_s_marc
                     WITH NON-UNIQUE KEY werks matnr,
          lt_hist  TYPE ty_t_hist,
          ls_hist  TYPE ty_s_hist,
          ls_cur   TYPE ty_s_hist,
          ls_end   TYPE ty_s_hist,
          l_gja    TYPE marc-lfgja,
          l_mon    TYPE marc-lfmon.

    l_gja = g_period_x(4).
    l_mon = g_period_x+4(2).

    " 운송중(가상 TRNS) 기초 = MARC/MARCH UMLMC + TRAME (설계 5.4)
    SELECT a~werks, a~matnr, a~lfgja, a~lfmon, a~umlmc, a~trame
      FROM marc AS a
      INNER JOIN mara AS c ON c~matnr = a~matnr
      INTO TABLE @lt_marc
      WHERE a~werks IN @gs_sel-werks
        AND a~matnr IN @gs_sel-matnr
        AND c~mtart IN @gs_sel-mtart.
    IF lt_marc IS INITIAL.
      RETURN.
    ENDIF.

    SELECT a~werks, a~matnr, a~lfgja, a~lfmon, a~umlmc, a~trame
      FROM march AS a
      INNER JOIN mara AS c ON c~matnr = a~matnr
      INTO TABLE @lt_march
      WHERE a~werks IN @gs_sel-werks
        AND a~matnr IN @gs_sel-matnr
        AND c~mtart IN @gs_sel-mtart
        AND ( a~lfgja > @l_gja OR ( a~lfgja = @l_gja AND a~lfmon >= @l_mon ) ).

    LOOP AT lt_marc ASSIGNING FIELD-SYMBOL(<ls_marc>).
      CLEAR lt_hist.
      LOOP AT lt_march ASSIGNING FIELD-SYMBOL(<ls_march>)
           WHERE werks = <ls_marc>-werks
             AND matnr = <ls_marc>-matnr.
        CLEAR ls_hist.
        ls_hist-period = to_period( iv_gja = <ls_march>-lfgja iv_mon = <ls_march>-lfmon ).
        ls_hist-qty    = <ls_march>-umlmc + <ls_march>-trame.
        APPEND ls_hist TO lt_hist.
      ENDLOOP.

      CLEAR ls_cur.
      ls_cur-period = to_period( iv_gja = <ls_marc>-lfgja iv_mon = <ls_marc>-lfmon ).
      ls_cur-qty    = <ls_marc>-umlmc + <ls_marc>-trame.

      ls_end = pick_period_end( it_hist   = lt_hist
                                iv_period = g_period_x
                                is_cur    = ls_cur ).

      " 운송중 기초가 0이고 이동도 없으면 TRNS 행을 만들지 않음
      READ TABLE gt_sloc
        WITH TABLE KEY werks = <ls_marc>-werks
                       matnr = <ls_marc>-matnr
                       lgort = c_vsloc_trns
                       charg = space
        TRANSPORTING NO FIELDS.
      IF ls_end-qty = 0 AND sy-subrc <> 0.
        CONTINUE.
      ENDIF.

      post_begin( EXPORTING iv_werks = <ls_marc>-werks
                            iv_matnr = <ls_marc>-matnr
                            iv_lgort = c_vsloc_trns
                            iv_charg = space
                            iv_vsloc = abap_true
                            is_hist  = ls_end
                  CHANGING  ct_bal   = gt_sloc ).
    ENDLOOP.
  ENDMETHOD.


  METHOD build_main.
    DATA ls_main TYPE ty_s_main.

    CLEAR gt_main.
    read_texts( ).

    LOOP AT gt_sloc ASSIGNING FIELD-SYMBOL(<ls_sloc>).
      IF gs_sel-no_zero = abap_true AND is_zero( <ls_sloc>-qty ) = abap_true.
        CONTINUE.
      ENDIF.
      CLEAR ls_main.
      ls_main-werks = <ls_sloc>-werks.
      ls_main-matnr = <ls_sloc>-matnr.
      ls_main-lgort = <ls_sloc>-lgort.
      ls_main-vsloc = <ls_sloc>-vsloc.
      ls_main-qty   = <ls_sloc>-qty.

      READ TABLE gt_makt ASSIGNING FIELD-SYMBOL(<ls_makt>)
        WITH TABLE KEY matnr = <ls_sloc>-matnr.
      IF sy-subrc = 0.
        ls_main-maktx = <ls_makt>-maktx.
      ENDIF.
      READ TABLE gt_mara ASSIGNING FIELD-SYMBOL(<ls_mara>)
        WITH TABLE KEY matnr = <ls_sloc>-matnr.
      IF sy-subrc = 0.
        ls_main-meins = <ls_mara>-meins.
      ENDIF.
      READ TABLE gt_marc ASSIGNING FIELD-SYMBOL(<ls_marc>)
        WITH TABLE KEY matnr = <ls_sloc>-matnr
                       werks = <ls_sloc>-werks.
      IF sy-subrc = 0.
        ls_main-xchpf = <ls_marc>-xchpf.
      ENDIF.
      APPEND ls_main TO gt_main.
    ENDLOOP.

    " 플랜트명·저장위치명 (가상 행 명칭은 리포트 Text Symbol)
    IF gt_main IS NOT INITIAL.
      DATA: lt_t001w TYPE ty_h_t001w,
            lt_t001l TYPE ty_h_t001l.
      SELECT werks, name1 FROM t001w
        INTO TABLE @lt_t001w
        WHERE werks IN @gs_sel-werks.
      SELECT werks, lgort, lgobe FROM t001l
        INTO TABLE @lt_t001l
        WHERE werks IN @gs_sel-werks
          AND lgort IN @gs_sel-lgort.
      LOOP AT gt_main ASSIGNING FIELD-SYMBOL(<ls_main>).
        READ TABLE lt_t001w ASSIGNING FIELD-SYMBOL(<ls_t001w>)
          WITH TABLE KEY werks = <ls_main>-werks.
        IF sy-subrc = 0.
          <ls_main>-name1 = <ls_t001w>-name1.
        ENDIF.
        IF <ls_main>-vsloc = abap_false.
          READ TABLE lt_t001l ASSIGNING FIELD-SYMBOL(<ls_t001l>)
            WITH TABLE KEY werks = <ls_main>-werks
                           lgort = <ls_main>-lgort.
          IF sy-subrc = 0.
            <ls_main>-lgobe = <ls_t001l>-lgobe.
          ENDIF.
        ENDIF.
      ENDLOOP.
    ENDIF.

    SORT gt_main BY werks matnr vsloc lgort.
  ENDMETHOD.


  METHOD read_texts.
    DATA: lt_mat TYPE STANDARD TABLE OF ty_s_mara WITH DEFAULT KEY,
          ls_mat TYPE ty_s_mara,
          lt_wm  TYPE ty_t_wm,
          ls_wm  TYPE ty_s_wm.

    LOOP AT gt_sloc ASSIGNING FIELD-SYMBOL(<ls_sloc>).
      ls_mat-matnr = <ls_sloc>-matnr.
      APPEND ls_mat TO lt_mat.
      ls_wm-werks = <ls_sloc>-werks.
      ls_wm-matnr = <ls_sloc>-matnr.
      APPEND ls_wm TO lt_wm.
    ENDLOOP.
    SORT lt_mat BY matnr.
    DELETE ADJACENT DUPLICATES FROM lt_mat COMPARING matnr.
    SORT lt_wm BY werks matnr.
    DELETE ADJACENT DUPLICATES FROM lt_wm COMPARING werks matnr.

    " FOR ALL ENTRIES 드라이버가 비면 건너뜀 (전체 조회 방지)
    IF lt_mat IS INITIAL.
      RETURN.
    ENDIF.

    SELECT matnr, maktx FROM makt
      INTO TABLE @gt_makt
      FOR ALL ENTRIES IN @lt_mat
      WHERE matnr = @lt_mat-matnr
        AND spras = @sy-langu.

    SELECT matnr, meins FROM mara
      INTO TABLE @gt_mara
      FOR ALL ENTRIES IN @lt_mat
      WHERE matnr = @lt_mat-matnr.

    SELECT matnr, werks, xchpf FROM marc
      INTO TABLE @gt_marc
      FOR ALL ENTRIES IN @lt_wm
      WHERE matnr = @lt_wm-matnr
        AND werks = @lt_wm-werks.
  ENDMETHOD.


  METHOD get_batch.
    TYPES: BEGIN OF lty_s_mchb,
             matnr TYPE mchb-matnr,
             werks TYPE mchb-werks,
             lgort TYPE mchb-lgort,
             charg TYPE mchb-charg,
             lfgja TYPE mchb-lfgja,
             lfmon TYPE mchb-lfmon,
             clabs TYPE mchb-clabs,
             cinsm TYPE mchb-cinsm,
             ceinm TYPE mchb-ceinm,
             cspem TYPE mchb-cspem,
             cretm TYPE mchb-cretm,
             cumlm TYPE mchb-cumlm,
           END OF lty_s_mchb.
    DATA: lt_key   TYPE ty_t_key,
          lt_bkey  TYPE ty_t_key,
          lt_bkeyh TYPE HASHED TABLE OF ty_s_key WITH UNIQUE KEY werks matnr lgort,
          lt_mchb  TYPE STANDARD TABLE OF lty_s_mchb WITH DEFAULT KEY,
          lt_mchbh TYPE SORTED TABLE OF lty_s_mchb
                     WITH NON-UNIQUE KEY werks matnr lgort charg,
          lt_tmp   TYPE ty_h_bal,
          lt_hist  TYPE ty_t_hist,
          ls_hist  TYPE ty_s_hist,
          ls_cur   TYPE ty_s_hist,
          ls_end   TYPE ty_s_hist,
          ls_batch TYPE ty_s_batch,
          l_sum    TYPE mseg-menge,
          l_diff   TYPE mseg-menge,
          l_batch  TYPE abap_bool,
          l_gja    TYPE mchb-lfgja,
          l_mon    TYPE mchb-lfmon.

    CLEAR: et_batch, et_diff_key, ev_diff_qty.
    IF it_key IS INITIAL OR g_loaded = abap_false.
      RETURN.
    ENDIF.

    lt_key = it_key.
    SORT lt_key BY werks matnr lgort.
    DELETE ADJACENT DUPLICATES FROM lt_key COMPARING werks matnr lgort.

    " 1) 비배치 자재·가상 행: 배치 공란 1행 = 메인 값 (FR-14)
    LOOP AT lt_key ASSIGNING FIELD-SYMBOL(<ls_key>).
      READ TABLE gt_sloc ASSIGNING FIELD-SYMBOL(<ls_sloc>)
        WITH TABLE KEY werks = <ls_key>-werks
                       matnr = <ls_key>-matnr
                       lgort = <ls_key>-lgort
                       charg = space.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      l_batch = abap_false.
      IF <ls_sloc>-vsloc = abap_false.
        READ TABLE gt_marc ASSIGNING FIELD-SYMBOL(<ls_marc>)
          WITH TABLE KEY matnr = <ls_key>-matnr
                         werks = <ls_key>-werks.
        IF sy-subrc = 0 AND <ls_marc>-xchpf IS NOT INITIAL.
          l_batch = abap_true.
        ENDIF.
      ENDIF.
      IF l_batch = abap_false.
        CLEAR ls_batch.
        ls_batch-werks = <ls_sloc>-werks.
        ls_batch-matnr = <ls_sloc>-matnr.
        ls_batch-lgort = <ls_sloc>-lgort.
        ls_batch-qty   = <ls_sloc>-qty.
        APPEND ls_batch TO et_batch.
      ELSE.
        APPEND <ls_key> TO lt_bkey.
        INSERT <ls_key> INTO TABLE lt_bkeyh.
      ENDIF.
    ENDLOOP.

    " 2) 배치관리 자재: 배치 레벨 이동 + MCHB/MCHBH 기간말 재고
    IF lt_bkey IS NOT INITIAL.
      LOOP AT gt_bal ASSIGNING FIELD-SYMBOL(<ls_bal>).
        READ TABLE lt_bkeyh
          WITH TABLE KEY werks = <ls_bal>-werks
                         matnr = <ls_bal>-matnr
                         lgort = <ls_bal>-lgort
          TRANSPORTING NO FIELDS.
        IF sy-subrc = 0.
          INSERT <ls_bal> INTO TABLE lt_tmp.
        ENDIF.
      ENDLOOP.

      l_gja = g_period_x(4).
      l_mon = g_period_x+4(2).

      SELECT matnr, werks, lgort, charg, lfgja, lfmon,
             clabs, cinsm, ceinm, cspem, cretm, cumlm
        FROM mchb
        INTO TABLE @lt_mchb
        FOR ALL ENTRIES IN @lt_bkey
        WHERE matnr = @lt_bkey-matnr
          AND werks = @lt_bkey-werks
          AND lgort = @lt_bkey-lgort.

      SELECT matnr, werks, lgort, charg, lfgja, lfmon,
             clabs, cinsm, ceinm, cspem, cretm, cumlm
        FROM mchbh
        INTO TABLE @lt_mchbh
        FOR ALL ENTRIES IN @lt_bkey
        WHERE matnr = @lt_bkey-matnr
          AND werks = @lt_bkey-werks
          AND lgort = @lt_bkey-lgort
          AND ( lfgja > @l_gja OR ( lfgja = @l_gja AND lfmon >= @l_mon ) ).

      LOOP AT lt_mchb ASSIGNING FIELD-SYMBOL(<ls_mchb>).
        CLEAR lt_hist.
        LOOP AT lt_mchbh ASSIGNING FIELD-SYMBOL(<ls_mchbh>)
             WHERE werks = <ls_mchb>-werks
               AND matnr = <ls_mchb>-matnr
               AND lgort = <ls_mchb>-lgort
               AND charg = <ls_mchb>-charg.
          CLEAR ls_hist.
          ls_hist-period = to_period( iv_gja = <ls_mchbh>-lfgja iv_mon = <ls_mchbh>-lfmon ).
          ls_hist-qty = <ls_mchbh>-clabs + <ls_mchbh>-cinsm + <ls_mchbh>-ceinm
                      + <ls_mchbh>-cspem + <ls_mchbh>-cretm.
          ls_hist-uml = <ls_mchbh>-cumlm.
          APPEND ls_hist TO lt_hist.
        ENDLOOP.

        CLEAR ls_cur.
        ls_cur-period = to_period( iv_gja = <ls_mchb>-lfgja iv_mon = <ls_mchb>-lfmon ).
        ls_cur-qty = <ls_mchb>-clabs + <ls_mchb>-cinsm + <ls_mchb>-ceinm
                   + <ls_mchb>-cspem + <ls_mchb>-cretm.
        ls_cur-uml = <ls_mchb>-cumlm.

        ls_end = pick_period_end( it_hist   = lt_hist
                                  iv_period = g_period_x
                                  is_cur    = ls_cur ).

        post_begin( EXPORTING iv_werks = <ls_mchb>-werks
                              iv_matnr = <ls_mchb>-matnr
                              iv_lgort = <ls_mchb>-lgort
                              iv_charg = <ls_mchb>-charg
                              iv_vsloc = abap_false
                              is_hist  = ls_end
                    CHANGING  ct_bal   = lt_tmp ).
      ENDLOOP.

      LOOP AT lt_tmp ASSIGNING FIELD-SYMBOL(<ls_tmp>).
        finalize( CHANGING cs_qty = <ls_tmp>-qty ).
        IF gs_sel-no_zero = abap_true AND is_zero( <ls_tmp>-qty ) = abap_true.
          CONTINUE.
        ENDIF.
        CLEAR ls_batch.
        ls_batch-werks = <ls_tmp>-werks.
        ls_batch-matnr = <ls_tmp>-matnr.
        ls_batch-lgort = <ls_tmp>-lgort.
        ls_batch-charg = <ls_tmp>-charg.
        ls_batch-qty   = <ls_tmp>-qty.
        APPEND ls_batch TO et_batch.
      ENDLOOP.

      " 3) 배치 합계 END_QTY 와 메인 END_QTY 비교 (FR-14 검증)
      LOOP AT lt_bkey ASSIGNING <ls_key>.
        CLEAR l_sum.
        LOOP AT lt_tmp ASSIGNING <ls_tmp>
             WHERE werks = <ls_key>-werks
               AND matnr = <ls_key>-matnr
               AND lgort = <ls_key>-lgort.
          l_sum = l_sum + <ls_tmp>-end_qty.
        ENDLOOP.
        READ TABLE gt_sloc ASSIGNING <ls_sloc>
          WITH TABLE KEY werks = <ls_key>-werks
                         matnr = <ls_key>-matnr
                         lgort = <ls_key>-lgort
                         charg = space.
        IF sy-subrc = 0.
          l_diff = l_sum - <ls_sloc>-end_qty.
          IF l_diff <> 0.
            APPEND <ls_key> TO et_diff_key.
            ev_diff_qty = ev_diff_qty + abs( l_diff ).
          ENDIF.
        ENDIF.
      ENDLOOP.
    ENDIF.

    " 자재내역·단위
    LOOP AT et_batch ASSIGNING FIELD-SYMBOL(<ls_batch>).
      READ TABLE gt_makt ASSIGNING FIELD-SYMBOL(<ls_makt>)
        WITH TABLE KEY matnr = <ls_batch>-matnr.
      IF sy-subrc = 0.
        <ls_batch>-maktx = <ls_makt>-maktx.
      ENDIF.
      READ TABLE gt_mara ASSIGNING FIELD-SYMBOL(<ls_mara>)
        WITH TABLE KEY matnr = <ls_batch>-matnr.
      IF sy-subrc = 0.
        <ls_batch>-meins = <ls_mara>-meins.
      ENDIF.
    ENDLOOP.

    SORT et_batch BY werks matnr lgort charg.
  ENDMETHOD.


  METHOD get_docs.
    DATA: lt_item  TYPE ty_t_item,
          lt_delta TYPE ty_t_delta,
          lt_fname TYPE ty_t_fname,
          ls_doc   TYPE ty_s_doc.
    FIELD-SYMBOLS <l_value> TYPE mseg-menge.

    IF g_loaded = abap_false OR is_key-werks IS INITIAL OR is_key-matnr IS INITIAL.
      RETURN.
    ENDIF.

    " 같은 기간·같은 필터로 다시 조회해 화면 수치와 1:1 대응 (설계 S12)
    SELECT b~mblnr, b~mjahr, b~zeile, a~budat, b~werks, b~lgort, b~charg,
           b~matnr, b~bwart, b~shkzg, b~menge, b~meins AS lmein,
           c~meins AS meins, b~sobkz, b~kzbew, b~kzzug, b~kzvbr,
           b~wertu, b~mengu, b~umwrk, b~umlgo, b~ummat, b~umcha,
           b~umsok, b~xauto, b~bustm, b~bustw
      FROM mkpf AS a
      INNER JOIN mseg AS b ON b~mblnr = a~mblnr
                          AND b~mjahr = a~mjahr
      INNER JOIN mara AS c ON c~matnr = b~matnr
      INTO TABLE @lt_item
      WHERE a~budat BETWEEN @g_month_start AND @gs_sel-budat_to
        AND ( b~werks = @is_key-werks OR b~umwrk = @is_key-werks )
        AND b~matnr = @is_key-matnr
        AND b~bustm IN @r_bustm.

    lt_fname = mov_fields( ).

    LOOP AT lt_item ASSIGNING FIELD-SYMBOL(<ls_item>).
      lt_delta = handle_item( is_item = <ls_item> iv_count = abap_false ).
      LOOP AT lt_delta ASSIGNING FIELD-SYMBOL(<ls_delta>)
           WHERE werks = is_key-werks
             AND matnr = is_key-matnr
             AND lgort = is_key-lgort
             AND charg = is_key-charg.
        CLEAR ls_doc.
        IF <ls_item>-budat < gs_sel-budat_from.
          ls_doc-kind = c_kind_beg.
        ELSE.
          ls_doc-kind = c_kind_per.
        ENDIF.
        ls_doc-budat = <ls_item>-budat.
        ls_doc-mblnr = <ls_item>-mblnr.
        ls_doc-mjahr = <ls_item>-mjahr.
        ls_doc-zeile = <ls_item>-zeile.
        ls_doc-werks = <ls_item>-werks.
        ls_doc-matnr = <ls_item>-matnr.
        ls_doc-bwart = <ls_item>-bwart.
        ls_doc-shkzg = <ls_item>-shkzg.
        ls_doc-charg = <ls_item>-charg.
        ls_doc-lgort = <ls_item>-lgort.
        ls_doc-umlgo = <ls_item>-umlgo.
        ls_doc-xauto = <ls_item>-xauto.
        ls_doc-meins = <ls_item>-meins.
        " 0이 아닌 컬럼마다 1행 (기초분은 ZCLSTC·UML 만 화면 기초에 반영됨)
        LOOP AT lt_fname INTO DATA(l_fname).
          ASSIGN COMPONENT l_fname OF STRUCTURE <ls_delta>-mov TO <l_value>.
          IF sy-subrc = 0 AND <l_value> <> 0.
            ls_doc-fname = l_fname.
            ls_doc-value = <l_value>.
            APPEND ls_doc TO rt_doc.
          ENDIF.
        ENDLOOP.
      ENDLOOP.
    ENDLOOP.

    SORT rt_doc BY budat mblnr mjahr zeile fname.
  ENDMETHOD.


  METHOD get_recon.
    TYPES: BEGIN OF lty_s_mbew,
             matnr TYPE mbew-matnr,
             bwkey TYPE mbew-bwkey,
             lfgja TYPE mbew-lfgja,
             lfmon TYPE mbew-lfmon,
             lbkum TYPE mbew-lbkum,
           END OF lty_s_mbew.
    TYPES: BEGIN OF lty_s_bwm,
             matnr TYPE mbew-matnr,
             bwkey TYPE mbew-bwkey,
           END OF lty_s_bwm.
    DATA: ls_wm     TYPE ty_s_wm,
          lt_bwm    TYPE STANDARD TABLE OF lty_s_bwm WITH DEFAULT KEY,
          ls_bwm    TYPE lty_s_bwm,
          lt_wmh    TYPE HASHED TABLE OF ty_s_wm WITH UNIQUE KEY werks matnr,
          lt_recon  TYPE HASHED TABLE OF ty_s_recon WITH UNIQUE KEY werks matnr,
          ls_recon  TYPE ty_s_recon,
          lt_mbew   TYPE STANDARD TABLE OF lty_s_mbew WITH DEFAULT KEY,
          lt_mbewh  TYPE SORTED TABLE OF lty_s_mbew WITH NON-UNIQUE KEY matnr bwkey,
          lt_hist   TYPE ty_t_hist,
          ls_hist   TYPE ty_s_hist,
          ls_cur    TYPE ty_s_hist,
          ls_end    TYPE ty_s_hist,
          l_next    TYPE sy-datum,
          l_current TYPE abap_bool,
          l_period  TYPE ty_period,
          l_gja     TYPE mbew-lfgja,
          l_mon     TYPE mbew-lfmon.

    CLEAR: et_recon, ev_ok.
    IF g_loaded = abap_false.
      RETURN.
    ENDIF.

    " 기준일 = 종료일. 월말이거나 오늘 이후일 때만 대사 (설계 S13)
    l_next = gs_sel-budat_to + 1.
    IF gs_sel-budat_to >= sy-datum.
      l_current = abap_true.
    ELSEIF l_next+6(2) <> '01'.
      RETURN.
    ENDIF.
    ev_ok = abap_true.

    " 대상 플랜트·자재: 선택 행, 없으면 전체
    IF it_key IS NOT INITIAL.
      LOOP AT it_key ASSIGNING FIELD-SYMBOL(<ls_key>).
        ls_wm-werks = <ls_key>-werks.
        ls_wm-matnr = <ls_key>-matnr.
        INSERT ls_wm INTO TABLE lt_wmh.
      ENDLOOP.
    ELSE.
      LOOP AT gt_sloc ASSIGNING FIELD-SYMBOL(<ls_sloc>).
        ls_wm-werks = <ls_sloc>-werks.
        ls_wm-matnr = <ls_sloc>-matnr.
        INSERT ls_wm INTO TABLE lt_wmh.
      ENDLOOP.
    ENDIF.

    " 계산 합계 = 실제 저장위치 기말 + 이전중 + 운송중(가상). ZZZZ 는 차이로 남김
    LOOP AT gt_sloc ASSIGNING <ls_sloc>.
      READ TABLE lt_wmh
        WITH TABLE KEY werks = <ls_sloc>-werks matnr = <ls_sloc>-matnr
        TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      READ TABLE lt_recon ASSIGNING FIELD-SYMBOL(<ls_recon>)
        WITH TABLE KEY werks = <ls_sloc>-werks matnr = <ls_sloc>-matnr.
      IF sy-subrc <> 0.
        CLEAR ls_recon.
        ls_recon-werks = <ls_sloc>-werks.
        ls_recon-matnr = <ls_sloc>-matnr.
        INSERT ls_recon INTO TABLE lt_recon ASSIGNING <ls_recon>.
      ENDIF.
      IF <ls_sloc>-vsloc = abap_false.
        <ls_recon>-sloc_end = <ls_recon>-sloc_end + <ls_sloc>-end_qty.
        <ls_recon>-uml_end  = <ls_recon>-uml_end + <ls_sloc>-uml_end.
      ELSEIF <ls_sloc>-lgort = c_vsloc_trns.
        <ls_recon>-trns_end = <ls_recon>-trns_end + <ls_sloc>-end_qty.
      ENDIF.
    ENDLOOP.
    IF lt_recon IS INITIAL.
      RETURN.
    ENDIF.

    " 평가수량: 평가레벨 = 플랜트 가정(BWKEY = WERKS), BWTAR 공란
    LOOP AT lt_recon ASSIGNING <ls_recon>.
      ls_bwm-matnr = <ls_recon>-matnr.
      ls_bwm-bwkey = <ls_recon>-werks.
      APPEND ls_bwm TO lt_bwm.
    ENDLOOP.

    SELECT matnr, bwkey, lfgja, lfmon, lbkum
      FROM mbew
      INTO TABLE @lt_mbew
      FOR ALL ENTRIES IN @lt_bwm
      WHERE matnr = @lt_bwm-matnr
        AND bwkey = @lt_bwm-bwkey
        AND bwtar = @space.

    IF l_current = abap_false.
      l_period = gs_sel-budat_to(6).
      l_gja    = l_period(4).
      l_mon    = l_period+4(2).
      SELECT matnr, bwkey, lfgja, lfmon, lbkum
        FROM mbewh
        INTO TABLE @lt_mbewh
        FOR ALL ENTRIES IN @lt_bwm
        WHERE matnr = @lt_bwm-matnr
          AND bwkey = @lt_bwm-bwkey
          AND bwtar = @space
          AND ( lfgja > @l_gja OR ( lfgja = @l_gja AND lfmon >= @l_mon ) ).
    ENDIF.

    LOOP AT lt_recon ASSIGNING <ls_recon>.
      CLEAR ls_cur.
      READ TABLE lt_mbew ASSIGNING FIELD-SYMBOL(<ls_mbew>)
        WITH KEY matnr = <ls_recon>-matnr bwkey = <ls_recon>-werks.
      IF sy-subrc = 0.
        ls_cur-period = to_period( iv_gja = <ls_mbew>-lfgja iv_mon = <ls_mbew>-lfmon ).
        ls_cur-qty    = <ls_mbew>-lbkum.
      ENDIF.
      IF l_current = abap_true.
        <ls_recon>-val_qty = ls_cur-qty.
      ELSE.
        CLEAR lt_hist.
        LOOP AT lt_mbewh ASSIGNING FIELD-SYMBOL(<ls_mbewh>)
             WHERE matnr = <ls_recon>-matnr
               AND bwkey = <ls_recon>-werks.
          CLEAR ls_hist.
          ls_hist-period = to_period( iv_gja = <ls_mbewh>-lfgja iv_mon = <ls_mbewh>-lfmon ).
          ls_hist-qty    = <ls_mbewh>-lbkum.
          APPEND ls_hist TO lt_hist.
        ENDLOOP.
        ls_end = pick_period_end( it_hist   = lt_hist
                                  iv_period = l_period
                                  is_cur    = ls_cur ).
        <ls_recon>-val_qty = ls_end-qty.
      ENDIF.
      <ls_recon>-calc_sum = <ls_recon>-sloc_end + <ls_recon>-uml_end
                          + <ls_recon>-trns_end.
      <ls_recon>-diff = <ls_recon>-calc_sum - <ls_recon>-val_qty.

      READ TABLE gt_makt ASSIGNING FIELD-SYMBOL(<ls_makt>)
        WITH TABLE KEY matnr = <ls_recon>-matnr.
      IF sy-subrc = 0.
        <ls_recon>-maktx = <ls_makt>-maktx.
      ENDIF.
      READ TABLE gt_mara ASSIGNING FIELD-SYMBOL(<ls_mara>)
        WITH TABLE KEY matnr = <ls_recon>-matnr.
      IF sy-subrc = 0.
        <ls_recon>-meins = <ls_mara>-meins.
      ENDIF.
      APPEND <ls_recon> TO et_recon.
    ENDLOOP.

    SORT et_recon BY werks matnr.
  ENDMETHOD.


  METHOD build_deltas.
*----------------------------------------------------------------------*
* ZRMM0034F01 STORAGE_LEDGER_COLLECT(581~655행)와 하위 루틴 기준.
* l_sq = 부호 수량(S = +MENGE, H = -MENGE).
*  - 출고 컬럼 값 = -l_sq (GI_SQTY_S_RTN / GI_SQTY_H_RTN, 690~729행)
*  - 입고 컬럼 값 = +l_sq
*  - ZCLSTC(재고 증감) = l_sq. 단 입고·출고가 같이 매핑된 '동시출고'는 0
* 각 품목은 자기 저장위치에만 반영하고, 상대 위치 반영은 TPIND '2'이면서
* WERKS <> UMWRK 일 때만 한다(SL2_GRO_DATA_PLANT, 1185~1226행).
* 이전중(UML)·운송중(TRNS) 보조 델타는 설계 5.2 추가분(원문에 없음).
*----------------------------------------------------------------------*
    DATA: ls_own   TYPE ty_s_delta,
          ls_cpt   TYPE ty_s_delta,
          ls_ovl   TYPE ty_s_delta,
          l_sq     TYPE mseg-menge,
          l_neg    TYPE mseg-menge,
          l_intra  TYPE abap_bool,
          l_cpt    TYPE abap_bool,
          l_fname  TYPE fieldname,
          l_gi     TYPE fieldname.

    IF is_item-shkzg = c_shkzg_h.
      l_sq = 0 - is_item-menge.
    ELSE.
      l_sq = is_item-menge.
    ENDIF.
    l_neg = 0 - l_sq.
    l_gi  = gi_column( is_map-giind ).

    " 같은 플랜트·저장위치·자재 사이 이동은 건너뜀 (원문 583~587행)
    " 단 배치가 바뀌는 경우는 배치 상세용 intra 델타로 남김 (메인 제외)
    IF is_item-werks = is_item-umwrk
       AND is_item-lgort = is_item-umlgo
       AND is_item-matnr = is_item-ummat.
      IF is_item-charg IS INITIAL OR is_item-umcha IS INITIAL
         OR is_item-charg = is_item-umcha.
        RETURN.
      ENDIF.
      l_intra = abap_true.
    ENDIF.

    " ---- 자기 위치 컬럼 (원문 598~631행) ----
    CASE is_map-tpind.
      WHEN c_tpind_1 OR c_tpind_2.
        CASE is_map-grind.
          WHEN c_grind_ot.
            " SL_GR4_DATA_PLANT (663~682행)
            ls_own-ztp_gr = l_sq.
            add_to_column( EXPORTING iv_fname = l_gi iv_value = l_neg
                           CHANGING  cs_mov   = ls_own-mov ).
            IF is_map-giind IS INITIAL.
              ls_own-zclstc = l_sq.
            ENDIF.
          WHEN c_grind_po OR c_grind_pp OR c_grind_re.
            " 원문 '세팅불가': 반영 없음
          WHEN OTHERS.
            IF is_map-tpind = c_tpind_1.
              " SL_GRO_DATA_PLANT (740~767행): ZTMM0008-SHKZG 와 MSEG-SHKZG 비교
              IF is_map-shkzg = c_shkzg_s OR is_map-shkzg = c_shkzg_h.
                IF is_item-shkzg = is_map-shkzg.
                  ls_own-ztp_gi = l_neg.
                  ls_own-zclstc = l_sq.
                ELSE.
                  ls_own-ztp_gr = l_sq.
                  add_to_column( EXPORTING iv_fname = l_gi iv_value = l_neg
                                 CHANGING  cs_mov   = ls_own-mov ).
                  IF is_map-giind IS INITIAL.
                    ls_own-zclstc = l_sq.
                  ENDIF.
                ENDIF.
              ENDIF.
            ELSE.
              " SL2_GRO_DATA_PLANT (1185~1226행)
              IF is_item-umwrk IS NOT INITIAL AND is_item-werks <> is_item-umwrk.
                ls_own-ztp_gi = l_neg.
                ls_own-zclstc = l_sq.
                l_cpt = abap_true.
              ELSEIF is_item-umwrk IS NOT INITIAL.
                " 같은 플랜트: 원문은 출고 컬럼 부호를 반대로 씀 (1208~1215행)
                add_to_column( EXPORTING iv_fname = l_gi iv_value = l_sq
                               CHANGING  cs_mov   = ls_own-mov ).
                ls_own-zclstc = l_sq.
              ELSE.
                add_to_column( EXPORTING iv_fname = l_gi iv_value = l_neg
                               CHANGING  cs_mov   = ls_own-mov ).
                ls_own-zclstc = l_sq.
              ENDIF.
            ENDIF.
        ENDCASE.

      WHEN OTHERS.
        " SLO_GR1~4 / SLO_GRO (775~878행)
        l_fname = gr_column( is_map-grind ).
        IF l_fname IS NOT INITIAL.
          add_to_column( EXPORTING iv_fname = l_fname iv_value = l_sq
                         CHANGING  cs_mov   = ls_own-mov ).
          add_to_column( EXPORTING iv_fname = l_gi iv_value = l_neg
                         CHANGING  cs_mov   = ls_own-mov ).
          IF is_map-giind IS INITIAL.
            ls_own-zclstc = l_sq.
          ENDIF.
        ELSE.
          add_to_column( EXPORTING iv_fname = l_gi iv_value = l_neg
                         CHANGING  cs_mov   = ls_own-mov ).
          ls_own-zclstc = l_sq.
        ENDIF.
    ENDCASE.

    " ---- 이전중 보조: 저장위치 이전중 입고(315/316) 자기 위치 (설계 5.2) ----
    IF l_intra = abap_false AND is_item-xauto IS INITIAL
       AND is_rule-bw_ir IS NOT INITIAL AND is_item-bwart IN is_rule-bw_ir
       AND is_item-lgort IS NOT INITIAL.
      ls_own-uml = ls_own-uml + l_neg.
    ENDIF.

    " ---- 자기 위치 델타 (특별재고 제외: SOBKZ 공란만, 설계 5.1) ----
    IF is_item-sobkz IS INITIAL AND ls_own-mov IS NOT INITIAL.
      ls_own-werks = is_item-werks.
      ls_own-matnr = is_item-matnr.
      ls_own-lgort = resolve_vsloc( is_item ).
      IF is_item-lgort IS INITIAL.
        ls_own-vsloc = abap_true.
      ELSE.
        ls_own-charg = is_item-charg.
      ENDIF.
      ls_own-intra = l_intra.
      ls_own-side  = c_side_own.
      IF ls_own-vsloc = abap_false OR is_rule-vsloc = abap_true.
        APPEND ls_own TO rt_delta.
      ENDIF.
    ENDIF.

    " ---- 상대 위치 델타 (TPIND 2, WERKS <> UMWRK. 원문 gs_tp2_69) ----
    " 원문 TP2_ADD_LINE: 대상 = UMWRK + UMLGO + MATNR, ZTP_GR·출고 컬럼만 채우고
    " ZCLSTC 는 넣지 않음 -> 상대 위치 재고 증감 0
    IF l_cpt = abap_true AND is_item-umsok IS INITIAL.
      ls_cpt-ztp_gr = l_neg.
      add_to_column( EXPORTING iv_fname = l_gi iv_value = l_neg
                     CHANGING  cs_mov   = ls_cpt-mov ).
      ls_cpt-werks = is_item-umwrk.
      ls_cpt-matnr = is_item-matnr.
      IF is_item-umlgo IS INITIAL.
        ls_cpt-lgort = c_vsloc_trns.
        ls_cpt-vsloc = abap_true.
      ELSE.
        ls_cpt-lgort = is_item-umlgo.
        IF is_item-umcha IS NOT INITIAL.
          ls_cpt-charg = is_item-umcha.
        ELSE.
          ls_cpt-charg = is_item-charg.
        ENDIF.
      ENDIF.
      ls_cpt-side = c_side_cpt.
      IF ls_cpt-vsloc = abap_false OR is_rule-vsloc = abap_true.
        APPEND ls_cpt TO rt_delta.
      ENDIF.
    ENDIF.

    " ---- 이전중·운송중 보조 델타 (설계 5.2, 자동생성 품목 제외) ----
    IF l_intra = abap_true OR is_item-xauto IS NOT INITIAL.
      RETURN.
    ENDIF.

    " 저장위치 이전중 출고(313/314): 받는 저장위치 이전중 증가
    IF is_rule-bw_it IS NOT INITIAL AND is_item-bwart IN is_rule-bw_it
       AND is_item-umlgo IS NOT INITIAL AND is_item-umsok IS INITIAL.
      CLEAR ls_ovl.
      IF is_item-umwrk IS NOT INITIAL.
        ls_ovl-werks = is_item-umwrk.
      ELSE.
        ls_ovl-werks = is_item-werks.
      ENDIF.
      ls_ovl-matnr = is_item-matnr.
      ls_ovl-lgort = is_item-umlgo.
      IF is_item-umcha IS NOT INITIAL.
        ls_ovl-charg = is_item-umcha.
      ELSE.
        ls_ovl-charg = is_item-charg.
      ENDIF.
      ls_ovl-uml  = l_neg.
      ls_ovl-side = c_side_ovl.
      APPEND ls_ovl TO rt_delta.
    ENDIF.

    " 플랜트간 운송중 출고(303/304): 받는 플랜트 TRNS 재고 증가
    IF is_rule-vsloc = abap_true
       AND is_rule-bw_pt IS NOT INITIAL AND is_item-bwart IN is_rule-bw_pt
       AND is_item-umwrk IS NOT INITIAL AND is_item-umsok IS INITIAL.
      CLEAR ls_ovl.
      ls_ovl-werks  = is_item-umwrk.
      ls_ovl-matnr  = is_item-matnr.
      ls_ovl-lgort  = c_vsloc_trns.
      ls_ovl-vsloc  = abap_true.
      ls_ovl-zclstc = l_neg.
      ls_ovl-side   = c_side_ovl.
      APPEND ls_ovl TO rt_delta.
    ENDIF.

    " 플랜트간 운송중 입고(305/306): 자기 플랜트 TRNS 재고 감소
    IF is_rule-vsloc = abap_true
       AND is_rule-bw_pr IS NOT INITIAL AND is_item-bwart IN is_rule-bw_pr
       AND is_item-sobkz IS INITIAL.
      CLEAR ls_ovl.
      ls_ovl-werks  = is_item-werks.
      ls_ovl-matnr  = is_item-matnr.
      ls_ovl-lgort  = c_vsloc_trns.
      ls_ovl-vsloc  = abap_true.
      ls_ovl-zclstc = l_neg.
      ls_ovl-side   = c_side_ovl.
      APPEND ls_ovl TO rt_delta.
    ENDIF.
  ENDMETHOD.


  METHOD resolve_vsloc.
    " 설계 5.3: 저장위치 공란 -> XAUTO 'X' 운송중(TRNS), 그 밖 미분류(ZZZZ)
    IF is_item-lgort IS NOT INITIAL.
      rv_lgort = is_item-lgort.
    ELSEIF is_item-xauto = c_xauto_x.
      rv_lgort = c_vsloc_trns.
    ELSE.
      rv_lgort = c_vsloc_unkn.
    ENDIF.
  ENDMETHOD.


  METHOD gr_column.
    " C_MAP_GR: 원문 618~629행 (1 구매, 2 생산, 3 고객반품, 4 기타)
    CASE iv_grind.
      WHEN c_grind_po.
        rv_fname = c_fn_zpo_gr.
      WHEN c_grind_pp.
        rv_fname = c_fn_zpp_gr.
      WHEN c_grind_re.
        rv_fname = c_fn_zre_gr.
      WHEN c_grind_ot.
        rv_fname = c_fn_zot_gr.
      WHEN OTHERS.
        CLEAR rv_fname.
    ENDCASE.
  ENDMETHOD.


  METHOD gi_column.
    " C_MAP_GI: 원문 692~705행 (1 판매, 2 생산, 3 ZSP, 4 기타). 그 밖은 반영 없음
    CASE iv_giind.
      WHEN c_giind_sd.
        rv_fname = c_fn_zsd_gi.
      WHEN c_giind_pp.
        rv_fname = c_fn_zpp_gi.
      WHEN c_giind_sp.
        rv_fname = c_fn_zsp_gi.
      WHEN c_giind_ot.
        rv_fname = c_fn_zot_gi.
      WHEN OTHERS.
        CLEAR rv_fname.
    ENDCASE.
  ENDMETHOD.


  METHOD pick_period_end.
    " 설계 5.4: 기간 >= X 인 이력 중 가장 이른 기간 값,
    " 없고 현재 레코드 기간 <= X 면 현재 값, 둘 다 아니면 0
    DATA l_found TYPE abap_bool.

    CLEAR rs_hist.
    LOOP AT it_hist ASSIGNING FIELD-SYMBOL(<ls_hist>) WHERE period >= iv_period.
      IF l_found = abap_false OR <ls_hist>-period < rs_hist-period.
        rs_hist = <ls_hist>.
        l_found = abap_true.
      ENDIF.
    ENDLOOP.
    IF l_found = abap_true.
      RETURN.
    ENDIF.

    IF is_cur-period IS NOT INITIAL AND is_cur-period <= iv_period.
      rs_hist = is_cur.
    ELSE.
      CLEAR rs_hist.
      rs_hist-period = iv_period.
    ENDIF.
  ENDMETHOD.


  METHOD prev_period.
    DATA: l_year  TYPE n LENGTH 4,
          l_month TYPE n LENGTH 2.

    l_year  = iv_date(4).
    l_month = iv_date+4(2).
    IF l_month = 1.
      l_year  = l_year - 1.
      l_month = 12.
    ELSE.
      l_month = l_month - 1.
    ENDIF.
    CONCATENATE l_year l_month INTO rv_period.
  ENDMETHOD.


  METHOD month_start.
    rv_date = iv_date.
    rv_date+6(2) = '01'.
  ENDMETHOD.


  METHOD to_period.
    CONCATENATE iv_gja iv_mon INTO rv_period.
  ENDMETHOD.


  METHOD apply_delta.
    IF iv_before = abap_true.
      " 월초 ~ 시작일 전날: 기초에만 반영
      cs_qty-beg_qty = cs_qty-beg_qty + is_delta-zclstc.
      cs_qty-uml_beg = cs_qty-uml_beg + is_delta-uml.
    ELSE.
      cs_qty-zpo_gr  = cs_qty-zpo_gr + is_delta-zpo_gr.
      cs_qty-zpp_gr  = cs_qty-zpp_gr + is_delta-zpp_gr.
      cs_qty-ztp_gr  = cs_qty-ztp_gr + is_delta-ztp_gr.
      cs_qty-zre_gr  = cs_qty-zre_gr + is_delta-zre_gr.
      cs_qty-zot_gr  = cs_qty-zot_gr + is_delta-zot_gr.
      cs_qty-zsd_gi  = cs_qty-zsd_gi + is_delta-zsd_gi.
      cs_qty-zpp_gi  = cs_qty-zpp_gi + is_delta-zpp_gi.
      cs_qty-ztp_gi  = cs_qty-ztp_gi + is_delta-ztp_gi.
      cs_qty-zsp_gi  = cs_qty-zsp_gi + is_delta-zsp_gi.
      cs_qty-zot_gi  = cs_qty-zot_gi + is_delta-zot_gi.
      cs_qty-zclstc  = cs_qty-zclstc + is_delta-zclstc.
      cs_qty-uml_chg = cs_qty-uml_chg + is_delta-uml.
    ENDIF.
  ENDMETHOD.


  METHOD finalize.
    cs_qty-gr_sum = cs_qty-zpo_gr + cs_qty-zpp_gr + cs_qty-ztp_gr
                  + cs_qty-zre_gr + cs_qty-zot_gr.
    cs_qty-gi_sum = cs_qty-zsd_gi + cs_qty-zpp_gi + cs_qty-ztp_gi
                  + cs_qty-zsp_gi + cs_qty-zot_gi.
    " 기말 = 기초 + ZCLSTC(원문 재고 증감). 동시출고·상대 반영은 컬럼과 다를 수 있음
    cs_qty-end_qty = cs_qty-beg_qty + cs_qty-zclstc.
    cs_qty-uml_end = cs_qty-uml_beg + cs_qty-uml_chg.
  ENDMETHOD.


  METHOD is_zero.
    rv_zero = boolc( is_qty-beg_qty = 0 AND is_qty-gr_sum = 0 AND is_qty-gi_sum = 0
                 AND is_qty-zpo_gr = 0 AND is_qty-zpp_gr = 0 AND is_qty-ztp_gr = 0
                 AND is_qty-zre_gr = 0 AND is_qty-zot_gr = 0
                 AND is_qty-zsd_gi = 0 AND is_qty-zpp_gi = 0 AND is_qty-ztp_gi = 0
                 AND is_qty-zsp_gi = 0 AND is_qty-zot_gi = 0
                 AND is_qty-zclstc = 0 AND is_qty-end_qty = 0
                 AND is_qty-uml_beg = 0 AND is_qty-uml_chg = 0 AND is_qty-uml_end = 0 ).
  ENDMETHOD.


  METHOD to_exclude_range.
    " 선택화면의 I 값을 SIGN E 로 바꿈. 빈 값이면 빈 range(조건 없음)
    DATA ls_bustm LIKE LINE OF rt_bustm.

    LOOP AT it_bustm INTO ls_bustm.
      IF ls_bustm-sign = c_sign_e.
        ls_bustm-sign = c_sign_i.
      ELSE.
        ls_bustm-sign = c_sign_e.
      ENDIF.
      IF ls_bustm-option IS INITIAL.
        ls_bustm-option = c_opt_eq.
      ENDIF.
      APPEND ls_bustm TO rt_bustm.
    ENDLOOP.
  ENDMETHOD.


  METHOD mov_fields.
    rt_fname = VALUE #( ( c_fn_zpo_gr ) ( c_fn_zpp_gr ) ( c_fn_ztp_gr )
                        ( c_fn_zre_gr ) ( c_fn_zot_gr )
                        ( c_fn_zsd_gi ) ( c_fn_zpp_gi ) ( c_fn_ztp_gi )
                        ( c_fn_zsp_gi ) ( c_fn_zot_gi )
                        ( c_fn_zclstc ) ( c_fn_uml ) ).
  ENDMETHOD.


  METHOD post_delta.
    DATA ls_bal TYPE ty_s_bal.

    READ TABLE ct_bal ASSIGNING FIELD-SYMBOL(<ls_bal>)
      WITH TABLE KEY werks = is_delta-werks
                     matnr = is_delta-matnr
                     lgort = is_delta-lgort
                     charg = iv_charg.
    IF sy-subrc <> 0.
      CLEAR ls_bal.
      ls_bal-werks = is_delta-werks.
      ls_bal-matnr = is_delta-matnr.
      ls_bal-lgort = is_delta-lgort.
      ls_bal-charg = iv_charg.
      ls_bal-vsloc = is_delta-vsloc.
      INSERT ls_bal INTO TABLE ct_bal ASSIGNING <ls_bal>.
    ENDIF.
    apply_delta( EXPORTING is_delta  = is_delta
                           iv_before = iv_before
                 CHANGING  cs_qty    = <ls_bal>-qty ).
  ENDMETHOD.


  METHOD post_begin.
    DATA ls_bal TYPE ty_s_bal.

    READ TABLE ct_bal ASSIGNING FIELD-SYMBOL(<ls_bal>)
      WITH TABLE KEY werks = iv_werks
                     matnr = iv_matnr
                     lgort = iv_lgort
                     charg = iv_charg.
    IF sy-subrc <> 0.
      CLEAR ls_bal.
      ls_bal-werks = iv_werks.
      ls_bal-matnr = iv_matnr.
      ls_bal-lgort = iv_lgort.
      ls_bal-charg = iv_charg.
      ls_bal-vsloc = iv_vsloc.
      INSERT ls_bal INTO TABLE ct_bal ASSIGNING <ls_bal>.
    ENDIF.
    <ls_bal>-beg_qty = <ls_bal>-beg_qty + is_hist-qty.
    <ls_bal>-uml_beg = <ls_bal>-uml_beg + is_hist-uml.
  ENDMETHOD.


  METHOD add_to_column.
    FIELD-SYMBOLS <l_value> TYPE mseg-menge.

    IF iv_fname IS INITIAL OR iv_value = 0.
      RETURN.
    ENDIF.
    ASSIGN COMPONENT iv_fname OF STRUCTURE cs_mov TO <l_value>.
    IF sy-subrc = 0.
      <l_value> = <l_value> + iv_value.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
