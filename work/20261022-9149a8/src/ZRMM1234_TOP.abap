*&---------------------------------------------------------------------*
*& Include ZRMM1234_TOP - 전역 타입·상수·데이터 (설계 8.4)
*&---------------------------------------------------------------------*

*----------------------------------------------------------------------*
* 출력·내부 타입
*----------------------------------------------------------------------*
" 메인 ALV 1행 = 플랜트 + 저장위치(또는 운송중) (설계지시 1, 8.1)
TYPES: BEGIN OF ty_main,
         werks    TYPE werks_d,
         name1    TYPE t001w-name1,
         lgort    TYPE lgort_d,
         lgobe    TYPE t001l-lgobe,
         beg_qty  TYPE menge_d,
         gr_qty   TYPE menge_d,
         gi_qty   TYPE menge_d,
         end_qty  TYPE menge_d,
         meins    TYPE meins,
         unit_mix TYPE xfeld,
         stkcat   TYPE zestcat,
         t_color  TYPE lvc_t_scol,
       END OF ty_main.
TYPES ty_t_main TYPE STANDARD TABLE OF ty_main WITH EMPTY KEY.

" 자재 레벨 기간 결과(A 계산)
TYPES: BEGIN OF ty_matres,
         werks   TYPE ztmm1234-werks,
         lgort   TYPE ztmm1234-lgort,
         stkcat  TYPE ztmm1234-stkcat,
         matnr   TYPE ztmm1234-matnr,
         meins   TYPE ztmm1234-meins,
         beg_qty TYPE ztmm1234-beg_qty,
         gr_qty  TYPE ztmm1234-gr_qty,
         gi_qty  TYPE ztmm1234-gi_qty,
         end_qty TYPE ztmm1234-end_qty,
         k_end   TYPE ztmm1234-k_end,
         e_end   TYPE ztmm1234-e_end,
         trf_end TYPE ztmm1234-trf_end,
       END OF ty_matres.
TYPES ty_t_matres TYPE SORTED TABLE OF ty_matres
      WITH UNIQUE KEY werks stkcat lgort matnr.

" 상세 팝업 1행 = 자재 + 배치 (8.2)
TYPES: BEGIN OF ty_detail,
         werks   TYPE ztmm1236-werks,
         lgort   TYPE ztmm1236-lgort,
         lgobe   TYPE t001l-lgobe,
         matnr   TYPE ztmm1236-matnr,
         maktx   TYPE makt-maktx,
         charg   TYPE ztmm1236-charg,
         meins   TYPE ztmm1236-meins,
         beg_qty TYPE ztmm1236-beg_qty,
         gr_qty  TYPE ztmm1236-gr_qty,
         gi_qty  TYPE ztmm1236-gi_qty,
         end_qty TYPE ztmm1236-end_qty,
         k_end   TYPE ztmm1236-k_end,
         e_end   TYPE ztmm1236-e_end,
         trf_end TYPE ztmm1236-trf_end,
         stkcat  TYPE ztmm1236-stkcat,
       END OF ty_detail.
TYPES ty_t_detail TYPE SORTED TABLE OF ty_detail
      WITH UNIQUE KEY werks stkcat lgort matnr charg.
TYPES ty_t_popup TYPE STANDARD TABLE OF ty_detail WITH EMPTY KEY.

" 집계 테이블 조회 결과 (Q3)
TYPES: BEGIN OF ty_a,
         werks   TYPE ztmm1234-werks,
         lgort   TYPE ztmm1234-lgort,
         matnr   TYPE ztmm1234-matnr,
         stkcat  TYPE ztmm1234-stkcat,
         budat   TYPE ztmm1234-budat,
         meins   TYPE ztmm1234-meins,
         gr_qty  TYPE ztmm1234-gr_qty,
         gi_qty  TYPE ztmm1234-gi_qty,
         end_qty TYPE ztmm1234-end_qty,
         k_end   TYPE ztmm1234-k_end,
         e_end   TYPE ztmm1234-e_end,
         trf_end TYPE ztmm1234-trf_end,
       END OF ty_a.
TYPES ty_t_a TYPE STANDARD TABLE OF ty_a WITH EMPTY KEY.
TYPES: BEGIN OF ty_b,
         werks   TYPE ztmm1236-werks,
         lgort   TYPE ztmm1236-lgort,
         matnr   TYPE ztmm1236-matnr,
         charg   TYPE ztmm1236-charg,
         stkcat  TYPE ztmm1236-stkcat,
         budat   TYPE ztmm1236-budat,
         meins   TYPE ztmm1236-meins,
         gr_qty  TYPE ztmm1236-gr_qty,
         gi_qty  TYPE ztmm1236-gi_qty,
         end_qty TYPE ztmm1236-end_qty,
         k_end   TYPE ztmm1236-k_end,
         e_end   TYPE ztmm1236-e_end,
         trf_end TYPE ztmm1236-trf_end,
       END OF ty_b.
TYPES ty_t_b TYPE STANDARD TABLE OF ty_b WITH EMPTY KEY.

" 텍스트·제어
TYPES: BEGIN OF ty_t001w,
         werks TYPE t001w-werks,
         name1 TYPE t001w-name1,
       END OF ty_t001w.
TYPES ty_t_t001w TYPE HASHED TABLE OF ty_t001w WITH UNIQUE KEY werks.
TYPES: BEGIN OF ty_t001l,
         werks TYPE t001l-werks,
         lgort TYPE t001l-lgort,
         lgobe TYPE t001l-lgobe,
       END OF ty_t001l.
TYPES ty_t_t001l TYPE HASHED TABLE OF ty_t001l WITH UNIQUE KEY werks lgort.
TYPES ty_t_ctrl TYPE HASHED TABLE OF ztmm1237 WITH UNIQUE KEY werks.

*----------------------------------------------------------------------*
* 상수
*----------------------------------------------------------------------*
CONSTANTS:
  c_fc_detail   TYPE salv_de_function VALUE 'DETAIL',    " [상세조회] FCODE
  c_status      TYPE sypfkey VALUE 'STANDARD',           " GUI 상태(SE41)
  c_handle_main TYPE slis_handl VALUE 'MAIN',            " 메인 레이아웃 핸들
  c_handle_detl TYPE slis_handl VALUE 'DETL',            " 상세 레이아웃 핸들
  c_pop_scol    TYPE i VALUE 5,                          " 팝업 크기(화면 약 80%, D-14)
  c_pop_ecol    TYPE i VALUE 180,
  c_pop_slin    TYPE i VALUE 2,
  c_pop_elin    TYPE i VALUE 26,
  c_auth_wmb    TYPE c LENGTH 10 VALUE 'M_MSEG_WMB',     " 플랜트 권한 오브젝트
  c_auth_tcode  TYPE c LENGTH 10 VALUE 'S_TCODE',
  c_actvt_disp  TYPE c LENGTH 2 VALUE '03',              " 표시
  c_tcode_mb51  TYPE tcode VALUE 'MB51',
  c_sel_sign    TYPE c LENGTH 1 VALUE 'I',
  c_sel_eq      TYPE c LENGTH 2 VALUE 'EQ',
  c_sel_bt      TYPE c LENGTH 2 VALUE 'BT',
  c_kind_sel    TYPE c LENGTH 1 VALUE 'S'.

*----------------------------------------------------------------------*
* 로컬 클래스 참조
* (콜론 체인 형식: 웹앱 반영 도구가 이 INCLUDE를 전역 클래스로 오인하지 않게 함)
*----------------------------------------------------------------------*
CLASS: lcl_data DEFINITION DEFERRED,
       lcl_view DEFINITION DEFERRED.

DATA: g_data TYPE REF TO lcl_data,
      g_view TYPE REF TO lcl_view.

*----------------------------------------------------------------------*
* 선택화면 참조 변수·레인지
*----------------------------------------------------------------------*
DATA: g_werks TYPE t001w-werks,
      g_lgort TYPE t001l-lgort,
      g_matnr TYPE mara-matnr,
      g_mtart TYPE mara-mtart,
      g_matkl TYPE mara-matkl,
      g_charg TYPE mchb-charg.

DATA: r_werks  TYPE RANGE OF werks_d,     " 권한·집계 범위를 통과한 플랜트
      r_stkcat TYPE RANGE OF zestcat.     " SO_LGORT 입력 시 저장위치 행만
