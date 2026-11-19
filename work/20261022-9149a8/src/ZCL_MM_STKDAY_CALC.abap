CLASS zcl_mm_stkday_calc DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

*----------------------------------------------------------------------*
* 자재수불부 일자별 집계 - 계산 클래스 (DB 접근 없음, ABAP Unit 대상)
* 요청 ID : 20261022-9149a8 / 설계 02_design.md v1.1 (D4, D10, D11)
* 사용처  : ZCL_MM_STKDAY_AGGR(집계 배치), ZRMM1234(조회)
* 명명    : 클래스/메서드 파라미터(IV_/IT_/ET_/RV_/RT_/CT_)는 핸드북 규칙
*           없음 - SAP 관례 적용. 속성·변수·상수·레인지는 핸드북 2장 적용
*----------------------------------------------------------------------*
  PUBLIC SECTION.

*-- 공용 타입 -----------------------------------------------------------
    TYPES ty_t_date TYPE SORTED TABLE OF budat WITH UNIQUE KEY table_line.
    TYPES ty_r_bwart TYPE RANGE OF bwart.
    TYPES ty_r_bustm TYPE RANGE OF mseg-bustm.
    TYPES ty_r_matnr TYPE RANGE OF matnr.
    TYPES ty_r_werks TYPE RANGE OF werks_d.
    TYPES ty_chk_code TYPE c LENGTH 1.

    " 집계 키 (B 레벨. A 레벨은 CHARG 공란)
    TYPES: BEGIN OF ty_key,
             werks  TYPE werks_d,
             lgort  TYPE lgort_d,
             matnr  TYPE matnr,
             charg  TYPE charg_d,
             stkcat TYPE zestcat,
           END OF ty_key.
    TYPES ty_t_key TYPE SORTED TABLE OF ty_key
          WITH UNIQUE KEY werks lgort matnr charg stkcat.

    " 현재고(실행 순간) - 비키 필드는 모두 수치(COLLECT 사용)
    TYPES: BEGIN OF ty_stock.
        INCLUDE TYPE ty_key.
    TYPES: gen_qty TYPE menge_d,
           k_qty   TYPE menge_d,
           e_qty   TYPE menge_d,
           trf_qty TYPE menge_d,
           END OF ty_stock.
    TYPES tt_stock TYPE SORTED TABLE OF ty_stock
          WITH UNIQUE KEY werks lgort matnr charg stkcat.

    " 키·전기일별 증감 - 비키 필드는 모두 수치(COLLECT 사용)
    TYPES: BEGIN OF ty_delta.
        INCLUDE TYPE ty_key.
    TYPES: budat   TYPE budat,
           gr_qty  TYPE menge_d,
           gi_qty  TYPE menge_d,
           k_gr    TYPE menge_d,
           k_gi    TYPE menge_d,
           e_gr    TYPE menge_d,
           e_gi    TYPE menge_d,
           trf_qty TYPE menge_d,
           END OF ty_delta.
    TYPES tt_delta TYPE SORTED TABLE OF ty_delta
          WITH UNIQUE KEY werks lgort matnr charg stkcat budat.

    " 역산 결과 1행 (필드명 = ZTMM1236/ZTMM1234 필드명)
    TYPES: BEGIN OF ty_row.
        INCLUDE TYPE ty_key.
    TYPES: budat   TYPE budat,
           snapf   TYPE xfeld,
           beg_qty TYPE menge_d,
           gr_qty  TYPE menge_d,
           gi_qty  TYPE menge_d,
           end_qty TYPE menge_d,
           k_gr    TYPE menge_d,
           k_gi    TYPE menge_d,
           k_end   TYPE menge_d,
           e_gr    TYPE menge_d,
           e_gi    TYPE menge_d,
           e_end   TYPE menge_d,
           trf_end TYPE menge_d,
           END OF ty_row.
    TYPES tt_row TYPE STANDARD TABLE OF ty_row WITH EMPTY KEY.

    " MSEG 집계 행(분류 입력)
    TYPES: BEGIN OF ty_move,
             werks      TYPE mseg-werks,
             lgort      TYPE mseg-lgort,
             matnr      TYPE mseg-matnr,
             charg      TYPE mseg-charg,
             budat      TYPE mkpf-budat,
             bwart      TYPE mseg-bwart,
             shkzg      TYPE mseg-shkzg,
             sobkz      TYPE mseg-sobkz,
             xauto      TYPE mseg-xauto,
             bustm      TYPE mseg-bustm,
             umwrk      TYPE mseg-umwrk,
             ebeln      TYPE mseg-ebeln,
             ebelp      TYPE mseg-ebelp,
             menge      TYPE mseg-menge,
             recv_werks TYPE werks_d,      " STO 받는 플랜트(UMWRK 또는 EKPO-WERKS)
             sto_rcpt   TYPE xfeld,        " STO 입고(EKKO-RESWK <> 공란) 표시
           END OF ty_move.
    TYPES tt_move TYPE STANDARD TABLE OF ty_move WITH EMPTY KEY.

    " 조회 기간 계산 입력(한 키의 일자 행)과 결과
    TYPES: BEGIN OF ty_period_in,
             budat   TYPE budat,
             gr_qty  TYPE menge_d,
             gi_qty  TYPE menge_d,
             end_qty TYPE menge_d,
             k_end   TYPE menge_d,
             e_end   TYPE menge_d,
             trf_end TYPE menge_d,
           END OF ty_period_in.
    TYPES tt_period_in TYPE STANDARD TABLE OF ty_period_in WITH EMPTY KEY.
    TYPES: BEGIN OF ty_period,
             beg_qty TYPE menge_d,
             gr_qty  TYPE menge_d,
             gi_qty  TYPE menge_d,
             end_qty TYPE menge_d,
             k_end   TYPE menge_d,
             e_end   TYPE menge_d,
             trf_end TYPE menge_d,
           END OF ty_period.

    " 메인 위치별 집계(설계 8.4, v1.1)
    TYPES: BEGIN OF ty_loc_key,
             werks  TYPE werks_d,
             lgort  TYPE lgort_d,
             stkcat TYPE zestcat,
           END OF ty_loc_key.
    TYPES tt_loc_key TYPE SORTED TABLE OF ty_loc_key
          WITH UNIQUE KEY werks stkcat lgort.
    TYPES: BEGIN OF ty_loc_qty.
        INCLUDE TYPE ty_loc_key.
    TYPES: matnr   TYPE matnr,
           meins   TYPE meins,
           beg_qty TYPE menge_d,
           gr_qty  TYPE menge_d,
           gi_qty  TYPE menge_d,
           end_qty TYPE menge_d,
           END OF ty_loc_qty.
    TYPES tt_loc_qty TYPE STANDARD TABLE OF ty_loc_qty WITH EMPTY KEY.
    TYPES: BEGIN OF ty_loc_sum.
        INCLUDE TYPE ty_loc_key.
    TYPES: meins    TYPE meins,
           unit_mix TYPE xfeld,
           beg_qty  TYPE menge_d,
           gr_qty   TYPE menge_d,
           gi_qty   TYPE menge_d,
           end_qty  TYPE menge_d,
           END OF ty_loc_sum.
    TYPES tt_loc_sum TYPE SORTED TABLE OF ty_loc_sum
          WITH UNIQUE KEY werks stkcat lgort.

*-- 상수 ----------------------------------------------------------------
    CONSTANTS:
      c_msgid          TYPE symsgid VALUE 'ZMMM3',
      " 재고구분 (도메인 ZDSTCAT 고정값)
      c_stk_loc        TYPE zestcat VALUE 'L',
      c_stk_transit    TYPE zestcat VALUE 'T',
      " 실행 모드 (ZTMM1237-RUN_MODE)
      c_mode_daily     TYPE c LENGTH 1 VALUE 'D',
      c_mode_recalc    TYPE c LENGTH 1 VALUE 'R',
      c_mode_init      TYPE c LENGTH 1 VALUE 'I',
      " 실행 상태 (ZTMM1237-RUN_STAT)
      c_stat_running   TYPE c LENGTH 1 VALUE 'R',
      c_stat_success   TYPE c LENGTH 1 VALUE 'S',
      c_stat_error     TYPE c LENGTH 1 VALUE 'E',
      c_stat_warning   TYPE c LENGTH 1 VALUE 'W',
      " 차변/대변, 특별재고
      c_shkzg_s        TYPE c LENGTH 1 VALUE 'S',
      c_shkzg_h        TYPE c LENGTH 1 VALUE 'H',
      c_sobkz_k        TYPE c LENGTH 1 VALUE 'K',
      c_sobkz_e        TYPE c LENGTH 1 VALUE 'E',
      " 이전중 BUSTM (RM07MLBD 규칙, D6 / D-04)
      c_bustm_l        TYPE c LENGTH 4 VALUE 'MA05',
      c_bustm_t        TYPE c LENGTH 4 VALUE 'MA02',
      " CHECK_PERIOD 반환 코드
      c_chk_ok         TYPE ty_chk_code VALUE ' ',
      c_chk_from_gt_to TYPE ty_chk_code VALUE '1',
      c_chk_to_today   TYPE ty_chk_code VALUE '2',
      c_chk_not_loaded TYPE ty_chk_code VALUE '3',
      c_chk_to_gt_last TYPE ty_chk_code VALUE '4',
      c_chk_from_lt_ld TYPE ty_chk_code VALUE '5'.

*-- 분류 규칙 상수 테이블 (CLASS_CONSTRUCTOR에서 채움, 4.3 C3~C6) ---------
    CLASS-DATA:
      r_trfbw TYPE ty_r_bwart READ-ONLY,   " C3 XAUTO+BUSTM 공란일 때 이전중 BWART
      r_trflb TYPE ty_r_bwart READ-ONLY,   " C3 저장위치 이전중(L) BWART
      r_trftb TYPE ty_r_bwart READ-ONLY,   " C3 플랜트 이전중(T) BWART
      r_trfbs TYPE ty_r_bustm READ-ONLY,   " C3 이전중 BUSTM
      r_rsolb TYPE ty_r_bwart READ-ONLY,   " C4 저장위치 이전중 해소 315/316
      r_rsotb TYPE ty_r_bwart READ-ONLY,   " C4 플랜트 이전중 해소 305/306
      r_stois TYPE ty_r_bwart READ-ONLY,   " C5 STO 출고 351/352/641~644
      r_storc TYPE ty_r_bwart READ-ONLY,   " C5 STO 입고 101/102
      r_typch TYPE ty_r_bwart READ-ONLY.   " C6 재고유형 간 이동

    CLASS-METHODS class_constructor.

    "! 4.3 이동 분류: MSEG 집계 1행을 키·일자별 증감으로 누적
    CLASS-METHODS classify_move
      IMPORTING
        !is_move       TYPE ty_move
        !iv_cancel     TYPE xfeld
        !iv_batch      TYPE xfeld
        !iv_qty_update TYPE xfeld
      CHANGING
        !ct_delta      TYPE tt_delta.

    "! 4.2 역산: 현재고 - 이후 증감으로 [IV_FROM, IV_TO] 일자 행 생성
    CLASS-METHODS roll_back
      IMPORTING
        !it_stock     TYPE tt_stock
        !it_delta     TYPE tt_delta
        !iv_from      TYPE budat
        !iv_to        TYPE budat
        !it_snap      TYPE ty_t_date
      RETURNING
        VALUE(rt_row) TYPE tt_row.

    "! D4: 배치 레벨 현재고·증감을 자재 레벨(CHARG 공란)로 합산
    CLASS-METHODS to_material_level
      IMPORTING
        !it_stock TYPE tt_stock
        !it_delta TYPE tt_delta
      EXPORTING
        !et_stock TYPE tt_stock
        !et_delta TYPE tt_delta.

    "! 키별 특정 일자 종료 시점 재고(현재고 - 그 일자 이후 증감). 정합성 점검용
    CLASS-METHODS end_at_date
      IMPORTING
        !it_stock       TYPE tt_stock
        !it_delta       TYPE tt_delta
        !iv_date        TYPE budat
      RETURNING
        VALUE(rt_stock) TYPE tt_stock.

    "! 스냅샷 일자: 구간 안 매월 1일 + 적재 시작일
    CLASS-METHODS get_snapshot_dates
      IMPORTING
        !iv_from       TYPE budat
        !iv_to         TYPE budat
        !iv_load_from  TYPE budat OPTIONAL
      RETURNING
        VALUE(rt_date) TYPE ty_t_date.

    CLASS-METHODS month_start
      IMPORTING
        !iv_date       TYPE d
      RETURNING
        VALUE(rv_date) TYPE budat.

    "! 4.4 조회 기간 계산 (한 키의 일자 행)
    CLASS-METHODS calc_period
      IMPORTING
        !it_row          TYPE tt_period_in
        !iv_from         TYPE budat
        !iv_to           TYPE budat
        !iv_low          TYPE budat
      RETURNING
        VALUE(rs_period) TYPE ty_period.

    CLASS-METHODS is_zero_result
      IMPORTING
        !is_period     TYPE ty_period
      RETURNING
        VALUE(rv_zero) TYPE abap_bool.

    "! 일자 검증 (Q1, Q2). IV_WITH_CTRL = 'X'면 집계 범위까지 확인
    CLASS-METHODS check_period
      IMPORTING
        !iv_from        TYPE budat
        !iv_to          TYPE budat
        !iv_today       TYPE d
        !iv_with_ctrl   TYPE abap_bool DEFAULT abap_false
        !iv_load_from   TYPE budat OPTIONAL
        !iv_last_budat  TYPE budat OPTIONAL
      RETURNING
        VALUE(rv_code)  TYPE ty_chk_code.

    "! 4.5 메인 위치별 수량 집계 + 단위 혼재 판정 (D11)
    CLASS-METHODS aggregate_location
      IMPORTING
        !it_qty       TYPE tt_loc_qty
      RETURNING
        VALUE(rt_sum) TYPE tt_loc_sum.

    "! 일시에서 분을 뺀 일시 (입력일시 감지 여유시간 R-02)
    CLASS-METHODS subtract_minutes
      IMPORTING
        !iv_date    TYPE d
        !iv_time    TYPE t
        !iv_minutes TYPE i
      EXPORTING
        !ev_date    TYPE d
        !ev_time    TYPE t.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS zcl_mm_stkday_calc IMPLEMENTATION.


  METHOD class_constructor.
    " 분류 규칙 상수 테이블. 실제 전표 확인(D-04, D-05) 결과가 다르면 여기만 고친다
    r_trfbw = VALUE #( sign = 'I' option = 'EQ'
                       ( low = '303' ) ( low = '304' ) ( low = '313' ) ( low = '314' ) ).
    r_trflb = VALUE #( sign = 'I' option = 'EQ' ( low = '313' ) ( low = '314' ) ).
    r_trftb = VALUE #( sign = 'I' option = 'EQ' ( low = '303' ) ( low = '304' ) ).
    r_trfbs = VALUE #( sign = 'I' option = 'EQ'
                       ( low = 'MA02' ) ( low = 'MA05' ) ( low = 'MAUO' )
                       ( low = 'MA0L' ) ( low = 'MAVA' ) ).
    r_rsolb = VALUE #( sign = 'I' option = 'EQ' ( low = '315' ) ( low = '316' ) ).
    r_rsotb = VALUE #( sign = 'I' option = 'EQ' ( low = '305' ) ( low = '306' ) ).
    r_stois = VALUE #( sign = 'I' option = 'EQ'
                       ( low = '351' ) ( low = '352' ) ( low = '641' )
                       ( low = '642' ) ( low = '643' ) ( low = '644' ) ).
    r_storc = VALUE #( sign = 'I' option = 'EQ' ( low = '101' ) ( low = '102' ) ).
    r_typch = VALUE #( sign = 'I' option = 'EQ'
                       ( low = '321' ) ( low = '322' ) ( low = '341' ) ( low = '342' )
                       ( low = '343' ) ( low = '344' ) ( low = '349' ) ( low = '350' ) ).
  ENDMETHOD.


  METHOD classify_move.
    DATA: ls_delta TYPE ty_delta,
          l_charg  TYPE charg_d,
          l_trf    TYPE menge_d.

    " C2 수량 갱신이 없는 자재유형은 버림
    IF iv_qty_update = abap_false.
      RETURN.
    ENDIF.

    " C1 특별재고: 공란, K, E만 사용 (Q, W, O, V, M 등 제외)
    IF is_move-sobkz IS NOT INITIAL
       AND is_move-sobkz <> c_sobkz_k
       AND is_move-sobkz <> c_sobkz_e.
      RETURN.
    ENDIF.

    " C8 배치관리 자재가 아니면 배치 공란
    IF iv_batch = abap_true.
      l_charg = is_move-charg.
    ENDIF.

    " C3 이전중 행(XAUTO + BUSTM, MB5B RM07MLBD 규칙): 일반재고에 넣지 않음
    IF is_move-xauto = abap_true
       AND ( ( is_move-bustm IS NOT INITIAL AND is_move-bustm IN r_trfbs )
          OR ( is_move-bustm IS INITIAL AND is_move-bwart IN r_trfbw ) ).
      IF is_move-sobkz IS INITIAL.
        " 부호: S +, H -
        IF is_move-shkzg = c_shkzg_h.
          l_trf = 0 - is_move-menge.
        ELSE.
          l_trf = is_move-menge.
        ENDIF.
        CLEAR ls_delta.
        ls_delta-matnr   = is_move-matnr.
        ls_delta-budat   = is_move-budat.
        ls_delta-trf_qty = l_trf.
        IF is_move-bustm = c_bustm_t
           OR ( is_move-bustm <> c_bustm_l AND is_move-bwart IN r_trftb ).
          " 플랜트 이전중(303/304, MA02) -> 그 행 플랜트의 운송중(T) 키
          ls_delta-werks  = is_move-werks.
          ls_delta-stkcat = c_stk_transit.
          COLLECT ls_delta INTO ct_delta.
        ELSEIF is_move-lgort IS NOT INITIAL.
          " 저장위치 이전중(313/314, MA05) -> 그 행 (플랜트, 저장위치, 배치) L 키
          ls_delta-werks  = is_move-werks.
          ls_delta-lgort  = is_move-lgort.
          ls_delta-charg  = l_charg.
          ls_delta-stkcat = c_stk_loc.
          COLLECT ls_delta INTO ct_delta.
        ENDIF.
      ENDIF.
      RETURN.
    ENDIF.

    " C6 재고유형 간 이동: 같은 키 안 순증감 0이므로 입출고에서 제외
    IF is_move-bwart IN r_typch.
      RETURN.
    ENDIF.

    " 이전중 증감 부호(C4, C5 공통): 출고행(H) +, 입고행(S) -
    IF is_move-shkzg = c_shkzg_h.
      l_trf = is_move-menge.
    ELSE.
      l_trf = 0 - is_move-menge.
    ENDIF.

    IF is_move-sobkz IS INITIAL.
      " C4 이전중 해소 315/316 -> 같은 L 키, 305/306 -> 그 플랜트 T 키
      IF is_move-bwart IN r_rsolb AND is_move-lgort IS NOT INITIAL.
        CLEAR ls_delta.
        ls_delta-werks   = is_move-werks.
        ls_delta-lgort   = is_move-lgort.
        ls_delta-matnr   = is_move-matnr.
        ls_delta-charg   = l_charg.
        ls_delta-stkcat  = c_stk_loc.
        ls_delta-budat   = is_move-budat.
        ls_delta-trf_qty = l_trf.
        COLLECT ls_delta INTO ct_delta.
      ELSEIF is_move-bwart IN r_rsotb.
        CLEAR ls_delta.
        ls_delta-werks   = is_move-werks.
        ls_delta-matnr   = is_move-matnr.
        ls_delta-stkcat  = c_stk_transit.
        ls_delta-budat   = is_move-budat.
        ls_delta-trf_qty = l_trf.
        COLLECT ls_delta INTO ct_delta.
      ENDIF.

      " C5 STO 운송중: 출고(351 등) -> 받는 플랜트 T 키 / STO 입고(101/102) -> 자기 T 키
      IF is_move-bwart IN r_stois.
        IF is_move-recv_werks IS NOT INITIAL.
          CLEAR ls_delta.
          ls_delta-werks   = is_move-recv_werks.
          ls_delta-matnr   = is_move-matnr.
          ls_delta-stkcat  = c_stk_transit.
          ls_delta-budat   = is_move-budat.
          ls_delta-trf_qty = l_trf.
          COLLECT ls_delta INTO ct_delta.
        ENDIF.
      ELSEIF is_move-bwart IN r_storc AND is_move-sto_rcpt = abap_true.
        CLEAR ls_delta.
        ls_delta-werks   = is_move-werks.
        ls_delta-matnr   = is_move-matnr.
        ls_delta-stkcat  = c_stk_transit.
        ls_delta-budat   = is_move-budat.
        ls_delta-trf_qty = l_trf.
        COLLECT ls_delta INTO ct_delta.
      ENDIF.
    ENDIF.

    " C7 일반/K/E 입출고. 저장위치 공란 행은 버림
    IF is_move-lgort IS INITIAL.
      RETURN.
    ENDIF.

    CLEAR ls_delta.
    ls_delta-werks  = is_move-werks.
    ls_delta-lgort  = is_move-lgort.
    ls_delta-matnr  = is_move-matnr.
    ls_delta-charg  = l_charg.
    ls_delta-stkcat = c_stk_loc.
    ls_delta-budat  = is_move-budat.

    " 정상: S 입고 +, H 출고 + / 취소(T156 XSTBW): H 입고 -, S 출고 -
    CASE is_move-sobkz.
      WHEN space.
        IF iv_cancel = abap_false.
          IF is_move-shkzg = c_shkzg_s.
            ls_delta-gr_qty = is_move-menge.
          ELSE.
            ls_delta-gi_qty = is_move-menge.
          ENDIF.
        ELSE.
          IF is_move-shkzg = c_shkzg_h.
            ls_delta-gr_qty = 0 - is_move-menge.
          ELSE.
            ls_delta-gi_qty = 0 - is_move-menge.
          ENDIF.
        ENDIF.
      WHEN c_sobkz_k.
        IF iv_cancel = abap_false.
          IF is_move-shkzg = c_shkzg_s.
            ls_delta-k_gr = is_move-menge.
          ELSE.
            ls_delta-k_gi = is_move-menge.
          ENDIF.
        ELSE.
          IF is_move-shkzg = c_shkzg_h.
            ls_delta-k_gr = 0 - is_move-menge.
          ELSE.
            ls_delta-k_gi = 0 - is_move-menge.
          ENDIF.
        ENDIF.
      WHEN c_sobkz_e.
        IF iv_cancel = abap_false.
          IF is_move-shkzg = c_shkzg_s.
            ls_delta-e_gr = is_move-menge.
          ELSE.
            ls_delta-e_gi = is_move-menge.
          ENDIF.
        ELSE.
          IF is_move-shkzg = c_shkzg_h.
            ls_delta-e_gr = 0 - is_move-menge.
          ELSE.
            ls_delta-e_gi = 0 - is_move-menge.
          ENDIF.
        ENDIF.
      WHEN OTHERS.
        RETURN.
    ENDCASE.

    COLLECT ls_delta INTO ct_delta.
  ENDMETHOD.


  METHOD roll_back.
    DATA: lt_key   TYPE ty_t_key,
          ls_key   TYPE ty_key,
          ls_stock TYPE ty_stock,
          ls_delta TYPE ty_delta,
          ls_day   TYPE ty_delta,
          lt_kd    TYPE STANDARD TABLE OF ty_delta WITH EMPTY KEY,
          lt_dates TYPE ty_t_date,
          l_date   TYPE budat,
          l_didx   TYPE i,
          l_kidx   TYPE i,
          l_gen    TYPE menge_d,
          l_k      TYPE menge_d,
          l_e      TYPE menge_d,
          l_trf    TYPE menge_d,
          l_moved  TYPE abap_bool,
          l_snap   TYPE abap_bool,
          ls_row   TYPE ty_row.

    IF iv_from IS INITIAL OR iv_to IS INITIAL OR iv_from > iv_to.
      RETURN.
    ENDIF.

    " 대상 키 = 현재고 키 + 증감 키
    LOOP AT it_stock INTO ls_stock.
      MOVE-CORRESPONDING ls_stock TO ls_key.
      INSERT ls_key INTO TABLE lt_key.
    ENDLOOP.
    LOOP AT it_delta INTO ls_delta.
      MOVE-CORRESPONDING ls_delta TO ls_key.
      INSERT ls_key INTO TABLE lt_key.
    ENDLOOP.

    LOOP AT lt_key INTO ls_key.
      CLEAR: ls_stock, lt_kd, lt_dates.
      READ TABLE it_stock INTO ls_stock
           WITH TABLE KEY werks  = ls_key-werks
                          lgort  = ls_key-lgort
                          matnr  = ls_key-matnr
                          charg  = ls_key-charg
                          stkcat = ls_key-stkcat.
      l_gen = ls_stock-gen_qty.
      l_k   = ls_stock-k_qty.
      l_e   = ls_stock-e_qty.
      l_trf = ls_stock-trf_qty.

      " 기말(IV_TO) = 현재고 - IV_TO 이후(당일·미래 일자 포함) 증감
      LOOP AT it_delta INTO ls_delta
           WHERE werks  = ls_key-werks
             AND lgort  = ls_key-lgort
             AND matnr  = ls_key-matnr
             AND charg  = ls_key-charg
             AND stkcat = ls_key-stkcat.
        IF ls_delta-budat > iv_to.
          l_gen = l_gen - ( ls_delta-gr_qty - ls_delta-gi_qty ).
          l_k   = l_k   - ( ls_delta-k_gr - ls_delta-k_gi ).
          l_e   = l_e   - ( ls_delta-e_gr - ls_delta-e_gi ).
          l_trf = l_trf - ls_delta-trf_qty.
        ELSEIF ls_delta-budat >= iv_from.
          APPEND ls_delta TO lt_kd.               " 전기일 오름차순(정렬 키)
          INSERT ls_delta-budat INTO TABLE lt_dates.
        ENDIF.
      ENDLOOP.

      " 구간 안 스냅샷 일자
      LOOP AT it_snap INTO l_date WHERE table_line >= iv_from AND table_line <= iv_to.
        INSERT l_date INTO TABLE lt_dates.
      ENDLOOP.

      " 최근 일자부터 거꾸로: 기말(d) = 기말(d+) - 증감(d < x <= d+)
      l_kidx = lines( lt_kd ).
      l_didx = lines( lt_dates ).
      WHILE l_didx > 0.
        READ TABLE lt_dates INTO l_date INDEX l_didx.
        CLEAR ls_day.
        WHILE l_kidx > 0.
          READ TABLE lt_kd INTO ls_delta INDEX l_kidx.
          IF ls_delta-budat > l_date.
            l_gen  = l_gen - ( ls_delta-gr_qty - ls_delta-gi_qty ).
            l_k    = l_k   - ( ls_delta-k_gr - ls_delta-k_gi ).
            l_e    = l_e   - ( ls_delta-e_gr - ls_delta-e_gi ).
            l_trf  = l_trf - ls_delta-trf_qty.
            l_kidx = l_kidx - 1.
          ELSEIF ls_delta-budat = l_date.
            ls_day = ls_delta.                    " 다음(이전 일자) 반복에서 차감됨
            EXIT.
          ELSE.
            EXIT.
          ENDIF.
        ENDWHILE.

        l_moved = abap_false.
        IF ls_day-gr_qty <> 0 OR ls_day-gi_qty <> 0
           OR ls_day-k_gr <> 0 OR ls_day-k_gi <> 0
           OR ls_day-e_gr <> 0 OR ls_day-e_gi <> 0
           OR ls_day-trf_qty <> 0.
          l_moved = abap_true.
        ENDIF.
        l_snap = abap_false.
        IF line_exists( it_snap[ table_line = l_date ] ).
          l_snap = abap_true.
        ENDIF.

        " 행 생성: 이동이 있는 날, 또는 스냅샷 일자이면서 기말 중 하나라도 0 아님
        IF l_moved = abap_true
           OR ( l_snap = abap_true
                AND ( l_gen <> 0 OR l_k <> 0 OR l_e <> 0 OR l_trf <> 0 ) ).
          CLEAR ls_row.
          MOVE-CORRESPONDING ls_key TO ls_row.
          ls_row-budat   = l_date.
          IF l_snap = abap_true.
            ls_row-snapf = abap_true.
          ENDIF.
          ls_row-gr_qty  = ls_day-gr_qty.
          ls_row-gi_qty  = ls_day-gi_qty.
          ls_row-end_qty = l_gen.
          ls_row-beg_qty = l_gen - ls_day-gr_qty + ls_day-gi_qty.
          ls_row-k_gr    = ls_day-k_gr.
          ls_row-k_gi    = ls_day-k_gi.
          ls_row-k_end   = l_k.
          ls_row-e_gr    = ls_day-e_gr.
          ls_row-e_gi    = ls_day-e_gi.
          ls_row-e_end   = l_e.
          ls_row-trf_end = l_trf.
          APPEND ls_row TO rt_row.
        ENDIF.

        l_didx = l_didx - 1.
      ENDWHILE.
    ENDLOOP.

    SORT rt_row BY werks lgort matnr charg stkcat budat.
  ENDMETHOD.


  METHOD to_material_level.
    DATA: ls_stock TYPE ty_stock,
          ls_delta TYPE ty_delta.

    CLEAR: et_stock, et_delta.

    LOOP AT it_stock INTO ls_stock.
      CLEAR ls_stock-charg.
      COLLECT ls_stock INTO et_stock.
    ENDLOOP.

    LOOP AT it_delta INTO ls_delta.
      CLEAR ls_delta-charg.
      COLLECT ls_delta INTO et_delta.
    ENDLOOP.
  ENDMETHOD.


  METHOD end_at_date.
    DATA: ls_delta TYPE ty_delta,
          ls_stock TYPE ty_stock.

    rt_stock = it_stock.

    LOOP AT it_delta INTO ls_delta WHERE budat > iv_date.
      CLEAR ls_stock.
      MOVE-CORRESPONDING ls_delta TO ls_stock.
      ls_stock-gen_qty = 0 - ( ls_delta-gr_qty - ls_delta-gi_qty ).
      ls_stock-k_qty   = 0 - ( ls_delta-k_gr - ls_delta-k_gi ).
      ls_stock-e_qty   = 0 - ( ls_delta-e_gr - ls_delta-e_gi ).
      ls_stock-trf_qty = 0 - ls_delta-trf_qty.
      COLLECT ls_stock INTO rt_stock.
    ENDLOOP.
  ENDMETHOD.


  METHOD get_snapshot_dates.
    DATA: l_date TYPE budat,
          l_next TYPE budat.

    IF iv_from IS INITIAL OR iv_to IS INITIAL OR iv_from > iv_to.
      RETURN.
    ENDIF.

    l_date = month_start( iv_from ).
    IF l_date < iv_from.
      l_next = l_date + 31.
      l_date = month_start( l_next ).
    ENDIF.

    WHILE l_date <= iv_to.
      INSERT l_date INTO TABLE rt_date.
      l_next = l_date + 31.
      l_date = month_start( l_next ).
    ENDWHILE.

    IF iv_load_from IS NOT INITIAL
       AND iv_load_from >= iv_from AND iv_load_from <= iv_to.
      INSERT iv_load_from INTO TABLE rt_date.
    ENDIF.
  ENDMETHOD.


  METHOD month_start.
    IF iv_date IS INITIAL.
      RETURN.
    ENDIF.
    rv_date = iv_date.
    rv_date+6(2) = '01'.
  ENDMETHOD.


  METHOD calc_period.
    DATA: ls_in   TYPE ty_period_in,
          l_last  TYPE budat.

    LOOP AT it_row INTO ls_in.
      " 입고·출고: From ~ To 합
      IF ls_in-budat >= iv_from AND ls_in-budat <= iv_to.
        rs_period-gr_qty = rs_period-gr_qty + ls_in-gr_qty.
        rs_period-gi_qty = rs_period-gi_qty + ls_in-gi_qty.
      ENDIF.
      " 기말(To): [L, To] 구간에서 전기일이 가장 큰 행
      IF ls_in-budat >= iv_low AND ls_in-budat <= iv_to AND ls_in-budat > l_last.
        l_last             = ls_in-budat.
        rs_period-end_qty  = ls_in-end_qty.
        rs_period-k_end    = ls_in-k_end.
        rs_period-e_end    = ls_in-e_end.
        rs_period-trf_end  = ls_in-trf_end.
      ENDIF.
    ENDLOOP.

    " 기초(From) = 기말(To) - 입고 + 출고
    rs_period-beg_qty = rs_period-end_qty - rs_period-gr_qty + rs_period-gi_qty.
  ENDMETHOD.


  METHOD is_zero_result.
    rv_zero = abap_false.
    IF is_period-beg_qty = 0 AND is_period-gr_qty = 0 AND is_period-gi_qty = 0
       AND is_period-end_qty = 0 AND is_period-k_end = 0 AND is_period-e_end = 0
       AND is_period-trf_end = 0.
      rv_zero = abap_true.
    ENDIF.
  ENDMETHOD.


  METHOD check_period.
    rv_code = c_chk_ok.

    IF iv_from > iv_to.
      rv_code = c_chk_from_gt_to.
      RETURN.
    ENDIF.
    IF iv_to >= iv_today.
      rv_code = c_chk_to_today.
      RETURN.
    ENDIF.
    IF iv_with_ctrl = abap_false.
      RETURN.
    ENDIF.
    IF iv_last_budat IS INITIAL.
      rv_code = c_chk_not_loaded.
      RETURN.
    ENDIF.
    IF iv_to > iv_last_budat.
      rv_code = c_chk_to_gt_last.
      RETURN.
    ENDIF.
    IF iv_from < iv_load_from.
      rv_code = c_chk_from_lt_ld.
      RETURN.
    ENDIF.
  ENDMETHOD.


  METHOD aggregate_location.
    DATA: ls_qty TYPE ty_loc_qty,
          ls_sum TYPE ty_loc_sum.
    FIELD-SYMBOLS <ls_sum> TYPE ty_loc_sum.

    LOOP AT it_qty INTO ls_qty.
      READ TABLE rt_sum ASSIGNING <ls_sum>
           WITH TABLE KEY werks  = ls_qty-werks
                          stkcat = ls_qty-stkcat
                          lgort  = ls_qty-lgort.
      IF sy-subrc <> 0.
        CLEAR ls_sum.
        MOVE-CORRESPONDING ls_qty TO ls_sum.
        INSERT ls_sum INTO TABLE rt_sum.
      ELSE.
        " 기본단위가 하나라도 다르면 단위 혼재. 값은 계속 더하고 마지막에 지움
        IF <ls_sum>-meins <> ls_qty-meins.
          <ls_sum>-unit_mix = abap_true.
        ENDIF.
        <ls_sum>-beg_qty = <ls_sum>-beg_qty + ls_qty-beg_qty.
        <ls_sum>-gr_qty  = <ls_sum>-gr_qty  + ls_qty-gr_qty.
        <ls_sum>-gi_qty  = <ls_sum>-gi_qty  + ls_qty-gi_qty.
        <ls_sum>-end_qty = <ls_sum>-end_qty + ls_qty-end_qty.
      ENDIF.
    ENDLOOP.

    " 서로 다른 단위는 합산하지 않음: 단위·수량 초기화
    LOOP AT rt_sum ASSIGNING <ls_sum> WHERE unit_mix = abap_true.
      CLEAR: <ls_sum>-meins, <ls_sum>-beg_qty, <ls_sum>-gr_qty,
             <ls_sum>-gi_qty, <ls_sum>-end_qty.
    ENDLOOP.
  ENDMETHOD.


  METHOD subtract_minutes.
    DATA: l_days  TYPE i,
          l_secs  TYPE p LENGTH 16 DECIMALS 0,
          l_rdays TYPE i,
          l_rsecs TYPE i.

    CLEAR: ev_date, ev_time.
    IF iv_date IS INITIAL.
      RETURN.
    ENDIF.

    l_days  = iv_date.                        " 0001.01.01 기준 일수
    l_secs  = l_days * 86400 + iv_time - iv_minutes * 60.
    IF l_secs < 0.
      RETURN.
    ENDIF.
    l_rdays = l_secs DIV 86400.
    l_rsecs = l_secs MOD 86400.
    ev_date = l_rdays.
    ev_time = l_rsecs.
  ENDMETHOD.
ENDCLASS.
