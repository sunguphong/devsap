*&---------------------------------------------------------------------*
*&  Include           ZRMM0057TOP
*&---------------------------------------------------------------------*
*& 전역 데이터 선언
*&---------------------------------------------------------------------*

TABLES: sscrfields,
        mkpf,
        mseg,
        mara.

CLASS lcl_event_handler DEFINITION DEFERRED.

*----------------------------------------------------------------------*
* 상수
*----------------------------------------------------------------------*
CONSTANTS:
  c_fc_detail    TYPE salv_de_function VALUE 'DETAIL',   " 배치 상세
  c_fc_recon     TYPE salv_de_function VALUE 'RECON',    " 대사
  c_handle_main  TYPE slis_handl VALUE 'MAIN',
  c_handle_btch  TYPE slis_handl VALUE 'BTCH',
  c_handle_docs  TYPE slis_handl VALUE 'DOCS',
  c_handle_recn  TYPE slis_handl VALUE 'RECN',
  c_tcode_mb03   TYPE tstc-tcode VALUE 'MB03',
  c_pid_mblnr    TYPE memoryid VALUE 'MBN',
  c_pid_mjahr    TYPE memoryid VALUE 'MJA',
  c_ucomm_onli   TYPE sy-ucomm VALUE 'ONLI',
  c_ucomm_prin   TYPE sy-ucomm VALUE 'PRIN',
  c_ucomm_sjob   TYPE sy-ucomm VALUE 'SJOB',
  c_answer_yes   TYPE c LENGTH 1 VALUE '1',
  c_answer_no    TYPE c LENGTH 1 VALUE '2',
  c_opt_bt       TYPE c LENGTH 2 VALUE 'BT',
  c_pop_scol     TYPE i VALUE 5,
  c_pop_ecol     TYPE i VALUE 200,
  c_pop_slin     TYPE i VALUE 3,
  c_pop_elin     TYPE i VALUE 25,
  c_kind_main    TYPE c LENGTH 4 VALUE 'MAIN',
  c_kind_btch    TYPE c LENGTH 4 VALUE 'BTCH',
  c_kind_docs    TYPE c LENGTH 4 VALUE 'DOCS',
  c_kind_recn    TYPE c LENGTH 4 VALUE 'RECN'.

*----------------------------------------------------------------------*
* 데이터
*----------------------------------------------------------------------*
DATA: g_ledger  TYPE REF TO zcl_mm_sloc_ledger,
      g_main    TYPE REF TO cl_salv_table,
      g_handler TYPE REF TO lcl_event_handler,
      g_warn    TYPE string,                        " 결합 경고 메시지
      gs_sel    TYPE zcl_mm_sloc_ledger=>ty_s_sel,
      gt_main   TYPE zcl_mm_sloc_ledger=>ty_t_main,
      gt_batch  TYPE zcl_mm_sloc_ledger=>ty_t_batch,
      gt_doc    TYPE zcl_mm_sloc_ledger=>ty_t_doc,
      gt_recon  TYPE zcl_mm_sloc_ledger=>ty_t_recon.
