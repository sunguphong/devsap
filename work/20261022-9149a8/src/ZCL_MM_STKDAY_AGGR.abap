CLASS zcl_mm_stkday_aggr DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

*----------------------------------------------------------------------*
* 자재수불부 일자별 집계 실행 클래스 (ZRMM1235에서 호출)
* 요청 ID : 20261022-9149a8 / 설계 02_design.md v1.1 7.1 (J0~J8)
* 쓰기    : ZTMM1234(A), ZTMM1236(B), ZTMM1237(제어) - 이 클래스만 씀
* 잠금    : EZTMM1237 (플랜트별, _SCOPE = '1')
* 로그    : SLG1 오브젝트 ZMM / 서브오브젝트 ZRMM1235
* 명명    : 클래스/메서드 파라미터는 핸드북 규칙 없음 - SAP 관례 적용
*----------------------------------------------------------------------*
  PUBLIC SECTION.

    TYPES ty_code1 TYPE c LENGTH 1.
    TYPES: BEGIN OF ty_result,
             werks    TYPE werks_d,
             run_mode TYPE c LENGTH 1,
             run_mats TYPE i,
             rows_b   TYPE i,
             rows_a   TYPE i,
             run_stat TYPE c LENGTH 1,
             secs     TYPE i,
             run_msg  TYPE bapi_msg,
           END OF ty_result.
    TYPES tt_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    CONSTANTS:
      c_default_ovlap TYPE i VALUE 60,        " 입력일시 감지 여유시간(분)
      c_default_blksz TYPE i VALUE 1000,      " 블록당 자재 수
      c_min_blksz     TYPE i VALUE 1,
      c_max_blksz     TYPE i VALUE 5000,
      c_log_object    TYPE balobj_d VALUE 'ZMM',
      c_log_subobj    TYPE balsubobj VALUE 'ZRMM1235',
      c_lock_mode     TYPE c LENGTH 1 VALUE 'E'.

    METHODS constructor
      IMPORTING
        !iv_mode       TYPE ty_code1
        !it_werks      TYPE zcl_mm_stkday_calc=>ty_r_werks
        !iv_from       TYPE budat OPTIONAL
        !iv_prev_month TYPE xfeld OPTIONAL
        !it_matnr      TYPE zcl_mm_stkday_calc=>ty_r_matnr OPTIONAL
        !iv_overlap    TYPE i DEFAULT c_default_ovlap
        !iv_block_size TYPE i DEFAULT c_default_blksz
        !iv_test       TYPE xfeld OPTIONAL.

    "! J0~J8 실행. 플랜트별 결과, 실패 여부, 대상 플랜트 없음 여부
    METHODS run
      EXPORTING
        !et_result   TYPE tt_result
        !ev_error    TYPE abap_bool
        !ev_no_plant TYPE abap_bool.

  PROTECTED SECTION.
  PRIVATE SECTION.

    TYPES ty_t_werks TYPE STANDARD TABLE OF werks_d WITH EMPTY KEY.
    TYPES: BEGIN OF ty_mat,
             matnr TYPE matnr,
             d0    TYPE budat,
           END OF ty_mat.
    TYPES ty_t_mat TYPE STANDARD TABLE OF ty_mat WITH EMPTY KEY.
    TYPES ty_t_mat_h TYPE HASHED TABLE OF ty_mat WITH UNIQUE KEY matnr.
    TYPES: BEGIN OF ty_info,
             matnr  TYPE matnr,
             xchpf  TYPE marc-xchpf,
             umlmc  TYPE marc-umlmc,
             trame  TYPE marc-trame,
             mtart  TYPE mara-mtart,
             meins  TYPE mara-meins,
             qtyupd TYPE xfeld,
           END OF ty_info.
    TYPES ty_t_info TYPE HASHED TABLE OF ty_info WITH UNIQUE KEY matnr.
    TYPES: BEGIN OF ty_mtqty,
             mtart TYPE t134m-mtart,
             mengu TYPE t134m-mengu,
           END OF ty_mtqty.
    TYPES ty_t_mtqty TYPE HASHED TABLE OF ty_mtqty WITH UNIQUE KEY mtart.
    TYPES ty_t_bwart TYPE SORTED TABLE OF bwart WITH UNIQUE KEY table_line.
    TYPES ty_t_b TYPE STANDARD TABLE OF ztmm1236 WITH EMPTY KEY.
    TYPES ty_t_a TYPE STANDARD TABLE OF ztmm1234 WITH EMPTY KEY.

    " 실행 조건
    DATA: g_mode    TYPE c LENGTH 1,
          r_werks   TYPE zcl_mm_stkday_calc=>ty_r_werks,
          r_matnr   TYPE zcl_mm_stkday_calc=>ty_r_matnr,
          g_from    TYPE budat,
          g_prvmo   TYPE xfeld,
          g_overlap TYPE i,
          g_blksz   TYPE i,
          g_test    TYPE xfeld.
    " 실행 공통
    DATA: g_run_date TYPE sydatum,
          g_run_time TYPE syuzeit,
          gt_cancel  TYPE ty_t_bwart,
          g_log      TYPE balloghndl.
    " 플랜트 처리 상태
    DATA: g_werks     TYPE werks_d,
          g_bwkey     TYPE t001w-bwkey,
          gs_ctrl     TYPE ztmm1237,
          g_d_end     TYPE budat,
          g_load_from TYPE budat,
          gt_mtqty    TYPE ty_t_mtqty,
          g_cnt_b     TYPE i,
          g_cnt_a     TYPE i,
          g_cnt_mis   TYPE i,
          g_cnt_neg   TYPE i,
          g_cnt_con   TYPE i,
          g_errmsg    TYPE bapi_msg.

    METHODS get_target_plants
      RETURNING VALUE(rt_werks) TYPE ty_t_werks.
    METHODS process_plant
      IMPORTING !iv_werks  TYPE werks_d
      CHANGING  !cs_result TYPE ty_result.
    METHODS detect_materials
      EXPORTING !et_mat     TYPE ty_t_mat
      RETURNING VALUE(rv_ok) TYPE abap_bool.
    METHODS add_material
      IMPORTING !iv_matnr TYPE matnr
                !iv_d0    TYPE budat
      CHANGING  !ct_mat   TYPE ty_t_mat_h.
    METHODS check_open_period
      IMPORTING !iv_d0 TYPE budat.
    METHODS read_stock
      IMPORTING !ir_matnr TYPE zcl_mm_stkday_calc=>ty_r_matnr
      EXPORTING !et_info  TYPE ty_t_info
                !et_stock TYPE zcl_mm_stkday_calc=>tt_stock.
    METHODS read_moves
      IMPORTING !ir_matnr TYPE zcl_mm_stkday_calc=>ty_r_matnr
                !iv_from  TYPE budat
      EXPORTING !et_move  TYPE zcl_mm_stkday_calc=>tt_move.
    METHODS read_sto_moves
      IMPORTING !ir_matnr TYPE zcl_mm_stkday_calc=>ty_r_matnr
                !iv_from  TYPE budat
      CHANGING  !ct_move  TYPE zcl_mm_stkday_calc=>tt_move.
    METHODS compute_block
      IMPORTING !ir_matnr TYPE zcl_mm_stkday_calc=>ty_r_matnr
                !iv_from  TYPE budat
                !it_info  TYPE ty_t_info
                !it_stock TYPE zcl_mm_stkday_calc=>tt_stock
                !it_move  TYPE zcl_mm_stkday_calc=>tt_move
      EXPORTING !et_b     TYPE ty_t_b
                !et_a     TYPE ty_t_a.
    METHODS save_block
      IMPORTING !ir_matnr    TYPE zcl_mm_stkday_calc=>ty_r_matnr
                !iv_from     TYPE budat
                !it_b        TYPE ty_t_b
                !it_a        TYPE ty_t_a
      RETURNING VALUE(rv_ok) TYPE abap_bool.
    METHODS check_consistency
      IMPORTING !ir_matnr TYPE zcl_mm_stkday_calc=>ty_r_matnr
                !iv_from  TYPE budat
                !it_stock TYPE zcl_mm_stkday_calc=>tt_stock
                !it_delta TYPE zcl_mm_stkday_calc=>tt_delta
                !it_snap  TYPE zcl_mm_stkday_calc=>ty_t_date
                !it_b     TYPE ty_t_b
                !it_a     TYPE ty_t_a.
    METHODS update_control
      IMPORTING !iv_success TYPE abap_bool
                !iv_stat    TYPE ty_code1
                !iv_mats    TYPE i.
    METHODS open_log.
    METHODS save_log.
    METHODS add_log
      IMPORTING !iv_type   TYPE symsgty
                !iv_number TYPE symsgno
                !iv_v1     TYPE simple OPTIONAL
                !iv_v2     TYPE simple OPTIONAL
                !iv_v3     TYPE simple OPTIONAL
                !iv_v4     TYPE simple OPTIONAL
      RETURNING VALUE(rv_text) TYPE bapi_msg.
    METHODS date_text
      IMPORTING !iv_date       TYPE d
      RETURNING VALUE(rv_text) TYPE string.
ENDCLASS.



CLASS zcl_mm_stkday_aggr IMPLEMENTATION.


  METHOD constructor.
    g_mode    = iv_mode.
    r_werks   = it_werks.
    r_matnr   = it_matnr.
    g_from    = iv_from.
    g_prvmo   = iv_prev_month.
    g_overlap = iv_overlap.
    g_test    = iv_test.

    " 블록 크기 1~5000 제한 (P3 SQL 문장 길이 보호)
    g_blksz = iv_block_size.
    IF g_blksz < c_min_blksz.
      g_blksz = c_default_blksz.
    ELSEIF g_blksz > c_max_blksz.
      g_blksz = c_max_blksz.
    ENDIF.
    IF g_overlap < 0.
      g_overlap = c_default_ovlap.
    ENDIF.
  ENDMETHOD.


  METHOD run.
    DATA: lt_werks  TYPE ty_t_werks,
          l_werks   TYPE werks_d,
          ls_result TYPE ty_result.

    CLEAR: et_result, ev_error, ev_no_plant.

    " J0 실행 시작 일시(서버 시간)
    g_run_date = sy-datum.
    g_run_time = sy-uzeit.

    " ⑨ 취소 이동유형(T156 XSTBW = 'X') - 실행당 한 번
    SELECT bwart FROM t156 INTO TABLE @gt_cancel WHERE xstbw = @abap_true.

    lt_werks = get_target_plants( ).
    IF lt_werks IS INITIAL.
      ev_no_plant = abap_true.
      RETURN.
    ENDIF.

    LOOP AT lt_werks INTO l_werks.
      CLEAR ls_result.
      process_plant( EXPORTING iv_werks  = l_werks
                     CHANGING  cs_result = ls_result ).
      APPEND ls_result TO et_result.
      IF ls_result-run_stat = zcl_mm_stkday_calc=>c_stat_error.
        ev_error = abap_true.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD get_target_plants.
    DATA l_init TYPE budat.

    CLEAR rt_werks.
    CASE g_mode.
      WHEN zcl_mm_stkday_calc=>c_mode_daily.
        " 일 집계: 초기 적재를 한 플랜트(적재 시작일 있음)
        SELECT werks FROM ztmm1237 INTO TABLE @rt_werks
          WHERE werks IN @r_werks
            AND load_from <> @l_init.
      WHEN OTHERS.
        " 재집계·초기 적재: 플랜트 입력 필수(빈 range 전체 처리 방지)
        IF r_werks IS INITIAL.
          RETURN.
        ENDIF.
        SELECT werks FROM t001w INTO TABLE @rt_werks
          WHERE werks IN @r_werks.
    ENDCASE.
    SORT rt_werks.
  ENDMETHOD.


  METHOD process_plant.
    DATA: lt_mat    TYPE ty_t_mat,
          ls_mat    TYPE ty_mat,
          lr_block  TYPE zcl_mm_stkday_calc=>ty_r_matnr,
          lt_info   TYPE ty_t_info,
          lt_stock  TYPE zcl_mm_stkday_calc=>tt_stock,
          lt_move   TYPE zcl_mm_stkday_calc=>tt_move,
          lt_b      TYPE ty_t_b,
          lt_a      TYPE ty_t_a,
          l_count   TYPE i,
          l_mats    TYPE i,
          l_idx     TYPE i,
          l_end     TYPE i,
          l_from    TYPE budat,
          l_ok      TYPE abap_bool,
          l_stat    TYPE c LENGTH 1,
          l_user    TYPE symsgv,
          l_text    TYPE bapi_msg,
          l_dummy   TYPE bapi_msg,
          l_beg_d   TYPE d,
          l_beg_t   TYPE t,
          l_end_d   TYPE d,
          l_end_t   TYPE t,
          l_secs    TYPE p LENGTH 16 DECIMALS 0,
          lx_sql    TYPE REF TO cx_sy_open_sql_db,
          lx_arith  TYPE REF TO cx_sy_arithmetic_error,
          lx_conv   TYPE REF TO cx_sy_conversion_error.

    GET TIME.
    l_beg_d = sy-datum.
    l_beg_t = sy-uzeit.
    g_werks = iv_werks.
    CLEAR: gs_ctrl, g_bwkey, g_d_end, g_load_from, gt_mtqty,
           g_cnt_b, g_cnt_a, g_cnt_mis, g_cnt_neg, g_cnt_con, g_errmsg.
    cs_result-werks    = iv_werks.
    cs_result-run_mode = g_mode.

    open_log( ).

    "-- J1 플랜트 잠금 (COMMIT WORK 후에도 유지)
    CALL FUNCTION 'ENQUEUE_EZTMM1237'
      EXPORTING
        mode_ztmm1237  = c_lock_mode
        mandt          = sy-mandt
        werks          = iv_werks
        _scope         = '1'
      EXCEPTIONS
        foreign_lock   = 1
        system_failure = 2
        OTHERS         = 3.
    IF sy-subrc <> 0.
      "-- J2 잠금 실패: 경고 후 다음 플랜트 (제어 행 변경 없음)
      l_user = sy-msgv1.
      cs_result-run_msg  = add_log( iv_type = 'W' iv_number = '021'
                                    iv_v1 = iv_werks iv_v2 = l_user ).
      cs_result-run_stat = zcl_mm_stkday_calc=>c_stat_warning.
      save_log( ).
      RETURN.
    ENDIF.

    "-- 제어 행 읽기
    SELECT SINGLE * FROM ztmm1237 INTO @gs_ctrl WHERE werks = @iv_werks.
    IF sy-subrc <> 0.
      CLEAR gs_ctrl.
      gs_ctrl-werks = iv_werks.
    ENDIF.

    " 일 집계·재집계는 적재 완료(LAST_BUDAT 있음)가 전제
    IF g_mode <> zcl_mm_stkday_calc=>c_mode_init AND gs_ctrl-last_budat IS INITIAL.
      MESSAGE ID zcl_mm_stkday_calc=>c_msgid TYPE 'E' NUMBER '007'
              WITH iv_werks INTO l_dummy.
      l_text = l_dummy.
      cs_result-run_msg  = add_log( iv_type = 'E' iv_number = '023'
                                    iv_v1 = iv_werks iv_v2 = l_text ).
      cs_result-run_stat = zcl_mm_stkday_calc=>c_stat_error.
      CALL FUNCTION 'DEQUEUE_EZTMM1237'
        EXPORTING
          mode_ztmm1237 = c_lock_mode
          mandt         = sy-mandt
          werks         = iv_werks
          _scope        = '1'.
      save_log( ).
      RETURN.
    ENDIF.

    " 구간 끝: 일 집계·초기 적재 = 전일, 재집계 = 최종 집계일
    IF g_mode = zcl_mm_stkday_calc=>c_mode_recalc.
      g_d_end = gs_ctrl-last_budat.
    ELSE.
      g_d_end = g_run_date - 1.
    ENDIF.
    IF g_mode = zcl_mm_stkday_calc=>c_mode_init.
      g_load_from = g_from.
    ELSE.
      g_load_from = gs_ctrl-load_from.
    ENDIF.

    " 평가영역과 수량 갱신 자재유형(C2)
    SELECT SINGLE bwkey FROM t001w INTO @g_bwkey WHERE werks = @iv_werks.
    SELECT mtart, mengu FROM t134m INTO TABLE @gt_mtqty WHERE bwkey = @g_bwkey.

    "-- 실행 중 표시. 초기 적재는 LAST_BUDAT을 지워 조회 차단
    IF g_test = abap_false.
      gs_ctrl-run_stat = zcl_mm_stkday_calc=>c_stat_running.
      gs_ctrl-run_date = g_run_date.
      gs_ctrl-run_time = g_run_time.
      gs_ctrl-run_mode = g_mode.
      IF g_mode = zcl_mm_stkday_calc=>c_mode_init.
        CLEAR gs_ctrl-last_budat.
      ENDIF.
      gs_ctrl-aedat = sy-datum.
      gs_ctrl-aezet = sy-uzeit.
      gs_ctrl-aenam = sy-uname.
      MODIFY ztmm1237 FROM @gs_ctrl.
      COMMIT WORK.
    ENDIF.

    l_ok = abap_true.
    TRY.
        "-- J3 대상 감지·자재별 시작일
        detect_materials( IMPORTING et_mat = lt_mat
                          RECEIVING rv_ok  = l_ok ).

        IF l_ok = abap_true.
          " 초기 적재: 플랜트 전체 삭제 후 COMMIT
          IF g_mode = zcl_mm_stkday_calc=>c_mode_init AND g_test = abap_false.
            DELETE FROM ztmm1236 WHERE werks = @iv_werks.
            DELETE FROM ztmm1234 WHERE werks = @iv_werks.
            COMMIT WORK.
          ENDIF.

          READ TABLE lt_mat INTO ls_mat INDEX 1.
          IF sy-subrc = 0.
            check_open_period( ls_mat-d0 ).
          ENDIF.

          "-- J4~J6 자재 블록 처리 (블록 단위 집합 조회, LOOP 안 행 단위 SELECT 없음)
          l_count = lines( lt_mat ).
          l_idx   = 1.
          WHILE l_idx <= l_count AND l_ok = abap_true.
            l_end = l_idx + g_blksz - 1.
            IF l_end > l_count.
              l_end = l_count.
            ENDIF.
            CLEAR: lr_block, l_from.
            LOOP AT lt_mat INTO ls_mat FROM l_idx TO l_end.
              APPEND VALUE #( sign = 'I' option = 'EQ' low = ls_mat-matnr ) TO lr_block.
              IF l_from IS INITIAL OR ls_mat-d0 < l_from.
                l_from = ls_mat-d0.
              ENDIF.
            ENDLOOP.

            read_stock( EXPORTING ir_matnr = lr_block
                        IMPORTING et_info  = lt_info
                                  et_stock = lt_stock ).
            read_moves( EXPORTING ir_matnr = lr_block
                                  iv_from  = l_from
                        IMPORTING et_move  = lt_move ).
            read_sto_moves( EXPORTING ir_matnr = lr_block
                                      iv_from  = l_from
                            CHANGING  ct_move  = lt_move ).
            compute_block( EXPORTING ir_matnr = lr_block
                                     iv_from  = l_from
                                     it_info  = lt_info
                                     it_stock = lt_stock
                                     it_move  = lt_move
                           IMPORTING et_b     = lt_b
                                     et_a     = lt_a ).
            IF save_block( ir_matnr = lr_block
                           iv_from  = l_from
                           it_b     = lt_b
                           it_a     = lt_a ) = abap_false.
              l_ok = abap_false.
            ENDIF.
            l_idx = l_end + 1.
          ENDWHILE.
        ENDIF.

      CATCH cx_sy_open_sql_db INTO lx_sql.
        l_ok     = abap_false.
        g_errmsg = lx_sql->get_text( ).
      CATCH cx_sy_arithmetic_error INTO lx_arith.
        l_ok     = abap_false.
        g_errmsg = lx_arith->get_text( ).
      CATCH cx_sy_conversion_error INTO lx_conv.
        l_ok     = abap_false.
        g_errmsg = lx_conv->get_text( ).
    ENDTRY.

    l_mats = lines( lt_mat ).
    IF l_ok = abap_true.
      "-- J8 정합성 결과·성공 처리
      l_stat = zcl_mm_stkday_calc=>c_stat_success.
      IF g_cnt_mis > 0 OR g_cnt_neg > 0 OR g_cnt_con > 0.
        l_stat = zcl_mm_stkday_calc=>c_stat_warning.
        add_log( iv_type = 'W' iv_number = '026' iv_v1 = iv_werks
                 iv_v2 = g_cnt_mis iv_v3 = g_cnt_neg iv_v4 = g_cnt_con ).
      ENDIF.
      cs_result-run_msg = add_log( iv_type = 'S' iv_number = '022' iv_v1 = iv_werks
                                   iv_v2 = l_mats iv_v3 = g_cnt_b iv_v4 = g_cnt_a ).
      IF g_test = abap_true.
        cs_result-run_msg = add_log( iv_type = 'S' iv_number = '027' ).
      ENDIF.
      g_errmsg = cs_result-run_msg.
      update_control( iv_success = abap_true iv_stat = l_stat iv_mats = l_mats ).
    ELSE.
      "-- J7 오류: 해당 블록 ROLLBACK, 최종 집계일 유지
      ROLLBACK WORK.
      l_stat = zcl_mm_stkday_calc=>c_stat_error.
      cs_result-run_msg = add_log( iv_type = 'E' iv_number = '023'
                                   iv_v1 = iv_werks iv_v2 = g_errmsg ).
      update_control( iv_success = abap_false iv_stat = l_stat iv_mats = l_mats ).
    ENDIF.

    CALL FUNCTION 'DEQUEUE_EZTMM1237'
      EXPORTING
        mode_ztmm1237 = c_lock_mode
        mandt         = sy-mandt
        werks         = iv_werks
        _scope        = '1'.

    save_log( ).

    " 플랜트별 소요 시간(초)
    GET TIME.
    l_end_d = sy-datum.
    l_end_t = sy-uzeit.
    l_secs = ( l_end_d - l_beg_d ) * 86400 + ( l_end_t - l_beg_t ).
    cs_result-secs     = l_secs.
    cs_result-run_stat = l_stat.
    cs_result-run_mats = l_mats.
    cs_result-rows_b   = g_cnt_b.
    cs_result-rows_a   = g_cnt_a.
  ENDMETHOD.


  METHOD detect_materials.
    TYPES: BEGIN OF lty_det,
             matnr TYPE matnr,
             d0    TYPE budat,
           END OF lty_det.
    TYPES: BEGIN OF lty_sto,
             matnr TYPE mseg-matnr,
             umwrk TYPE mseg-umwrk,
             ebeln TYPE mseg-ebeln,
             ebelp TYPE mseg-ebelp,
             d0    TYPE budat,
           END OF lty_sto.
    TYPES: BEGIN OF lty_po,
             ebeln TYPE ekpo-ebeln,
             ebelp TYPE ekpo-ebelp,
           END OF lty_po.
    TYPES: BEGIN OF lty_ekpo,
             ebeln TYPE ekpo-ebeln,
             ebelp TYPE ekpo-ebelp,
             werks TYPE ekpo-werks,
           END OF lty_ekpo.
    DATA: lt_min    TYPE ty_t_mat_h,
          lt_det    TYPE STANDARD TABLE OF lty_det WITH EMPTY KEY,
          ls_det    TYPE lty_det,
          lt_sto    TYPE STANDARD TABLE OF lty_sto WITH EMPTY KEY,
          ls_sto    TYPE lty_sto,
          lt_po     TYPE STANDARD TABLE OF lty_po WITH EMPTY KEY,
          lt_ekpo   TYPE HASHED TABLE OF lty_ekpo WITH UNIQUE KEY ebeln ebelp,
          ls_ekpo   TYPE lty_ekpo,
          lt_matnr  TYPE STANDARD TABLE OF matnr WITH EMPTY KEY,
          l_matnr   TYPE matnr,
          lt_snap   TYPE zcl_mm_stkday_calc=>ty_t_date,
          l_snap1   TYPE budat,
          l_tdate   TYPE d,
          l_ttime   TYPE t,
          l_bfrom   TYPE budat,
          l_start   TYPE budat,
          l_prev    TYPE budat,
          lr_stois  TYPE zcl_mm_stkday_calc=>ty_r_bwart,
          l_v1      TYPE string,
          l_v2      TYPE string,
          ls_mat    TYPE ty_mat.

    CLEAR et_mat.
    rv_ok = abap_true.

    CASE g_mode.
      WHEN zcl_mm_stkday_calc=>c_mode_daily.
        " (b) 새 일자 구간: D_last+1 ~ D-1 (없으면 조건이 성립하지 않게 D-1+1)
        l_bfrom = gs_ctrl-last_budat + 1.
        IF l_bfrom > g_d_end.
          l_bfrom = g_d_end + 1.
        ENDIF.
        " (a) 입력일시 감지 기준 T_last = 마지막 성공 실행 시작 - 여유시간
        zcl_mm_stkday_calc=>subtract_minutes(
          EXPORTING iv_date    = gs_ctrl-last_cpudt
                    iv_time    = gs_ctrl-last_cputm
                    iv_minutes = g_overlap
          IMPORTING ev_date    = l_tdate
                    ev_time    = l_ttime ).
        IF l_tdate IS INITIAL.
          l_tdate = '99991231'.                 " 기준 없음: (a) 감지 안 함
        ENDIF.

        " (a)+(b) 자재별 최소 전기일 (DB 집계)
        SELECT s~matnr, MIN( k~budat ) AS d0
          FROM mkpf AS k
          INNER JOIN mseg AS s ON s~mblnr = k~mblnr
                              AND s~mjahr = k~mjahr
          INTO TABLE @lt_det
          WHERE s~werks = @g_werks
            AND k~budat <= @g_d_end
            AND ( k~cpudt > @l_tdate
               OR ( k~cpudt = @l_tdate AND k~cputm >= @l_ttime )
               OR k~budat >= @l_bfrom )
          GROUP BY s~matnr.
        LOOP AT lt_det INTO ls_det.
          add_material( EXPORTING iv_matnr = ls_det-matnr iv_d0 = ls_det-d0
                        CHANGING  ct_mat   = lt_min ).
        ENDLOOP.

        " (c) 다른 플랜트에서 이 플랜트로 오는 STO 출고 (받는 플랜트 = 이 플랜트)
        lr_stois = zcl_mm_stkday_calc=>r_stois.
        SELECT s~matnr, s~umwrk, s~ebeln, s~ebelp, MIN( k~budat ) AS d0
          FROM mkpf AS k
          INNER JOIN mseg AS s ON s~mblnr = k~mblnr
                              AND s~mjahr = k~mjahr
          INTO TABLE @lt_sto
          WHERE s~bwart IN @lr_stois
            AND s~werks <> @g_werks
            AND ( s~umwrk = @g_werks OR s~umwrk = @space )
            AND k~budat <= @g_d_end
            AND ( k~cpudt > @l_tdate
               OR ( k~cpudt = @l_tdate AND k~cputm >= @l_ttime )
               OR k~budat >= @l_bfrom )
          GROUP BY s~matnr, s~umwrk, s~ebeln, s~ebelp.
        LOOP AT lt_sto INTO ls_sto WHERE umwrk IS INITIAL AND ebeln IS NOT INITIAL.
          APPEND VALUE #( ebeln = ls_sto-ebeln ebelp = ls_sto-ebelp ) TO lt_po.
        ENDLOOP.
        IF lt_po IS NOT INITIAL.
          SORT lt_po BY ebeln ebelp.
          DELETE ADJACENT DUPLICATES FROM lt_po COMPARING ebeln ebelp.
          SELECT ebeln, ebelp, werks FROM ekpo INTO TABLE @lt_ekpo
            FOR ALL ENTRIES IN @lt_po
            WHERE ebeln = @lt_po-ebeln
              AND ebelp = @lt_po-ebelp.
        ENDIF.
        LOOP AT lt_sto INTO ls_sto.
          IF ls_sto-umwrk IS INITIAL.
            READ TABLE lt_ekpo INTO ls_ekpo
                 WITH TABLE KEY ebeln = ls_sto-ebeln ebelp = ls_sto-ebelp.
            IF sy-subrc <> 0 OR ls_ekpo-werks <> g_werks.
              CONTINUE.
            ENDIF.
          ENDIF.
          add_material( EXPORTING iv_matnr = ls_sto-matnr iv_d0 = ls_sto-d0
                        CHANGING  ct_mat   = lt_min ).
        ENDLOOP.

        " (d) 새 구간에 월초가 있으면 재고 보유 자재 전체를 첫 스냅샷일부터
        l_prev = gs_ctrl-last_budat + 1.
        lt_snap = zcl_mm_stkday_calc=>get_snapshot_dates( iv_from = l_prev
                                                          iv_to   = g_d_end ).
        READ TABLE lt_snap INTO l_snap1 INDEX 1.
        IF sy-subrc = 0.
          CLEAR lt_matnr.
          SELECT DISTINCT matnr FROM mard APPENDING TABLE @lt_matnr
            WHERE werks = @g_werks
              AND ( labst <> 0 OR insme <> 0 OR speme <> 0 OR einme <> 0
                 OR retme <> 0 OR umlme <> 0 ).
          SELECT DISTINCT matnr FROM mchb APPENDING TABLE @lt_matnr
            WHERE werks = @g_werks
              AND ( clabs <> 0 OR cinsm <> 0 OR cspem <> 0 OR ceinm <> 0
                 OR cretm <> 0 OR cumlm <> 0 ).
          SELECT DISTINCT matnr FROM mkol APPENDING TABLE @lt_matnr
            WHERE werks = @g_werks
              AND ( slabs <> 0 OR sinsm <> 0 OR sspem <> 0 OR seinm <> 0 ).
          SELECT DISTINCT matnr FROM mska APPENDING TABLE @lt_matnr
            WHERE werks = @g_werks
              AND ( kalab <> 0 OR kains <> 0 OR kaspe <> 0 OR kaein <> 0 ).
          SELECT DISTINCT matnr FROM marc APPENDING TABLE @lt_matnr
            WHERE werks = @g_werks
              AND ( umlmc <> 0 OR trame <> 0 ).
          " 첫 스냅샷일 이후 이동이 있는 자재(당일·미래 일자 포함: 현재 0이어도 그날 재고가 있었을 수 있음)
          SELECT DISTINCT s~matnr
            FROM mkpf AS k
            INNER JOIN mseg AS s ON s~mblnr = k~mblnr
                                AND s~mjahr = k~mjahr
            APPENDING TABLE @lt_matnr
            WHERE s~werks = @g_werks
              AND k~budat >= @l_snap1.
          LOOP AT lt_matnr INTO l_matnr.
            add_material( EXPORTING iv_matnr = l_matnr iv_d0 = l_snap1
                          CHANGING  ct_mat   = lt_min ).
          ENDLOOP.
        ENDIF.

      WHEN zcl_mm_stkday_calc=>c_mode_recalc.
        " 재집계 시작일: 전월 1일(PA_PRVMO) 또는 입력 시작일
        IF g_prvmo = abap_true.
          l_prev  = zcl_mm_stkday_calc=>month_start( g_run_date ) - 1.
          l_start = zcl_mm_stkday_calc=>month_start( l_prev ).
        ELSE.
          l_start = g_from.
        ENDIF.
        IF l_start < gs_ctrl-load_from.
          l_v1 = date_text( l_start ).
          l_v2 = date_text( gs_ctrl-load_from ).
          g_errmsg = add_log( iv_type = 'E' iv_number = '024' iv_v1 = l_v1 iv_v2 = l_v2 ).
          rv_ok = abap_false.
          RETURN.
        ENDIF.
        IF l_start > g_d_end.
          RETURN.                                  " 재계산할 일자 없음
        ENDIF.
        SELECT matnr FROM marc INTO TABLE @lt_matnr
          WHERE werks = @g_werks
            AND matnr IN @r_matnr.
        LOOP AT lt_matnr INTO l_matnr.
          add_material( EXPORTING iv_matnr = l_matnr iv_d0 = l_start
                        CHANGING  ct_mat   = lt_min ).
        ENDLOOP.

      WHEN zcl_mm_stkday_calc=>c_mode_init.
        " 초기 적재: 플랜트 전체 자재를 시작 전기일부터
        IF g_from IS INITIAL OR g_from > g_d_end.
          RETURN.
        ENDIF.
        SELECT matnr FROM marc INTO TABLE @lt_matnr
          WHERE werks = @g_werks.
        LOOP AT lt_matnr INTO l_matnr.
          add_material( EXPORTING iv_matnr = l_matnr iv_d0 = g_from
                        CHANGING  ct_mat   = lt_min ).
        ENDLOOP.
    ENDCASE.

    " d0 오름차순으로 블록을 나누기 위해 정렬
    LOOP AT lt_min INTO ls_mat.
      APPEND ls_mat TO et_mat.
    ENDLOOP.
    SORT et_mat BY d0 matnr.
  ENDMETHOD.


  METHOD add_material.
    FIELD-SYMBOLS <ls_mat> TYPE ty_mat.

    IF iv_matnr IS INITIAL OR iv_d0 IS INITIAL.
      RETURN.
    ENDIF.
    READ TABLE ct_mat ASSIGNING <ls_mat> WITH TABLE KEY matnr = iv_matnr.
    IF sy-subrc = 0.
      IF iv_d0 < <ls_mat>-d0.
        <ls_mat>-d0 = iv_d0.
      ENDIF.
    ELSE.
      INSERT VALUE #( matnr = iv_matnr d0 = iv_d0 ) INTO TABLE ct_mat.
    ENDIF.
  ENDMETHOD.


  METHOD check_open_period.
    " 재계산 시작일이 열린 MM 기간(전기간 VMGJA/VMMON 1일)보다 이르면 경고(처리는 계속)
    DATA: l_bukrs TYPE t001k-bukrs,
          l_vmgja TYPE marv-vmgja,
          l_vmmon TYPE marv-vmmon,
          l_open  TYPE c LENGTH 8,
          l_date  TYPE d,
          l_v2    TYPE string.

    SELECT SINGLE bukrs FROM t001k INTO @l_bukrs WHERE bwkey = @g_bwkey.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    SELECT SINGLE vmgja, vmmon FROM marv INTO (@l_vmgja, @l_vmmon) WHERE bukrs = @l_bukrs.
    IF sy-subrc <> 0 OR l_vmgja IS INITIAL OR l_vmmon IS INITIAL.
      RETURN.
    ENDIF.
    " 회계연도 = 역년, 기간 = 월 가정 (03 문서 가정 항목)
    CONCATENATE l_vmgja l_vmmon '01' INTO l_open.
    l_date = l_open.
    IF iv_d0 < l_date.
      l_v2 = date_text( iv_d0 ).
      add_log( iv_type = 'W' iv_number = '025' iv_v1 = g_werks iv_v2 = l_v2 ).
    ENDIF.
  ENDMETHOD.


  METHOD read_stock.
    TYPES: BEGIN OF lty_marc,
             matnr TYPE marc-matnr,
             xchpf TYPE marc-xchpf,
             umlmc TYPE marc-umlmc,
             trame TYPE marc-trame,
             mtart TYPE mara-mtart,
             meins TYPE mara-meins,
           END OF lty_marc.
    TYPES: BEGIN OF lty_mard,
             matnr TYPE mard-matnr,
             lgort TYPE mard-lgort,
             labst TYPE mard-labst,
             insme TYPE mard-insme,
             speme TYPE mard-speme,
             einme TYPE mard-einme,
             retme TYPE mard-retme,
             umlme TYPE mard-umlme,
           END OF lty_mard.
    TYPES: BEGIN OF lty_mchb,
             matnr TYPE mchb-matnr,
             lgort TYPE mchb-lgort,
             charg TYPE mchb-charg,
             clabs TYPE mchb-clabs,
             cinsm TYPE mchb-cinsm,
             cspem TYPE mchb-cspem,
             ceinm TYPE mchb-ceinm,
             cretm TYPE mchb-cretm,
             cumlm TYPE mchb-cumlm,
           END OF lty_mchb.
    TYPES: BEGIN OF lty_mkol,
             matnr TYPE mkol-matnr,
             lgort TYPE mkol-lgort,
             charg TYPE mkol-charg,
             slabs TYPE mkol-slabs,
             sinsm TYPE mkol-sinsm,
             sspem TYPE mkol-sspem,
             seinm TYPE mkol-seinm,
           END OF lty_mkol.
    TYPES: BEGIN OF lty_mska,
             matnr TYPE mska-matnr,
             lgort TYPE mska-lgort,
             charg TYPE mska-charg,
             kalab TYPE mska-kalab,
             kains TYPE mska-kains,
             kaspe TYPE mska-kaspe,
             kaein TYPE mska-kaein,
           END OF lty_mska.
    DATA: lt_marc  TYPE STANDARD TABLE OF lty_marc WITH EMPTY KEY,
          ls_marc  TYPE lty_marc,
          lt_mard  TYPE STANDARD TABLE OF lty_mard WITH EMPTY KEY,
          ls_mard  TYPE lty_mard,
          lt_mchb  TYPE STANDARD TABLE OF lty_mchb WITH EMPTY KEY,
          ls_mchb  TYPE lty_mchb,
          lt_mkol  TYPE STANDARD TABLE OF lty_mkol WITH EMPTY KEY,
          ls_mkol  TYPE lty_mkol,
          lt_mska  TYPE STANDARD TABLE OF lty_mska WITH EMPTY KEY,
          ls_mska  TYPE lty_mska,
          ls_info  TYPE ty_info,
          ls_mtq   TYPE ty_mtqty,
          ls_stock TYPE zcl_mm_stkday_calc=>ty_stock.

    CLEAR: et_info, et_stock.
    IF ir_matnr IS INITIAL.
      RETURN.
    ENDIF.

    " ① MARC + MARA: 배치관리, 플랜트 운송중, 자재유형, 기본단위
    SELECT c~matnr, c~xchpf, c~umlmc, c~trame, m~mtart, m~meins
      FROM marc AS c
      INNER JOIN mara AS m ON m~matnr = c~matnr
      INTO TABLE @lt_marc
      WHERE c~werks = @g_werks
        AND c~matnr IN @ir_matnr.
    LOOP AT lt_marc INTO ls_marc.
      CLEAR ls_info.
      MOVE-CORRESPONDING ls_marc TO ls_info.
      " ② C2 수량 갱신: T134M 행이 있고 MENGU 공란이면 제외 (행 없으면 포함 - 가정)
      ls_info-qtyupd = abap_true.
      READ TABLE gt_mtqty INTO ls_mtq WITH TABLE KEY mtart = ls_marc-mtart.
      IF sy-subrc = 0 AND ls_mtq-mengu IS INITIAL.
        ls_info-qtyupd = abap_false.
      ENDIF.
      INSERT ls_info INTO TABLE et_info.

      " 플랜트 운송중(T 키) 현재고 = UMLMC + TRAME
      IF ls_info-qtyupd = abap_true AND ( ls_marc-umlmc <> 0 OR ls_marc-trame <> 0 ).
        CLEAR ls_stock.
        ls_stock-werks   = g_werks.
        ls_stock-matnr   = ls_marc-matnr.
        ls_stock-stkcat  = zcl_mm_stkday_calc=>c_stk_transit.
        ls_stock-trf_qty = ls_marc-umlmc + ls_marc-trame.
        COLLECT ls_stock INTO et_stock.
      ENDIF.
    ENDLOOP.

    " ③ MARD: 비배치 자재 일반재고(+반품 보류, D-01)·저장위치 이전중
    SELECT matnr, lgort, labst, insme, speme, einme, retme, umlme
      FROM mard
      INTO TABLE @lt_mard
      WHERE werks = @g_werks
        AND matnr IN @ir_matnr
        AND ( labst <> 0 OR insme <> 0 OR speme <> 0 OR einme <> 0
           OR retme <> 0 OR umlme <> 0 ).
    LOOP AT lt_mard INTO ls_mard.
      READ TABLE et_info INTO ls_info WITH TABLE KEY matnr = ls_mard-matnr.
      IF sy-subrc <> 0 OR ls_info-qtyupd = abap_false OR ls_info-xchpf IS NOT INITIAL.
        CONTINUE.
      ENDIF.
      CLEAR ls_stock.
      ls_stock-werks   = g_werks.
      ls_stock-lgort   = ls_mard-lgort.
      ls_stock-matnr   = ls_mard-matnr.
      ls_stock-stkcat  = zcl_mm_stkday_calc=>c_stk_loc.
      ls_stock-gen_qty = ls_mard-labst + ls_mard-insme + ls_mard-speme
                       + ls_mard-einme + ls_mard-retme.
      ls_stock-trf_qty = ls_mard-umlme.
      COLLECT ls_stock INTO et_stock.
    ENDLOOP.

    " ④ MCHB: 배치 자재 일반재고·배치 이전중
    SELECT matnr, lgort, charg, clabs, cinsm, cspem, ceinm, cretm, cumlm
      FROM mchb
      INTO TABLE @lt_mchb
      WHERE werks = @g_werks
        AND matnr IN @ir_matnr
        AND ( clabs <> 0 OR cinsm <> 0 OR cspem <> 0 OR ceinm <> 0
           OR cretm <> 0 OR cumlm <> 0 ).
    LOOP AT lt_mchb INTO ls_mchb.
      READ TABLE et_info INTO ls_info WITH TABLE KEY matnr = ls_mchb-matnr.
      IF sy-subrc <> 0 OR ls_info-qtyupd = abap_false OR ls_info-xchpf IS INITIAL.
        CONTINUE.
      ENDIF.
      CLEAR ls_stock.
      ls_stock-werks   = g_werks.
      ls_stock-lgort   = ls_mchb-lgort.
      ls_stock-matnr   = ls_mchb-matnr.
      ls_stock-charg   = ls_mchb-charg.
      ls_stock-stkcat  = zcl_mm_stkday_calc=>c_stk_loc.
      ls_stock-gen_qty = ls_mchb-clabs + ls_mchb-cinsm + ls_mchb-cspem
                       + ls_mchb-ceinm + ls_mchb-cretm.
      ls_stock-trf_qty = ls_mchb-cumlm.
      COLLECT ls_stock INTO et_stock.
    ENDLOOP.

    " ⑤ MKOL: 위탁(K) 현재고 (공급업체 합산)
    SELECT matnr, lgort, charg, slabs, sinsm, sspem, seinm
      FROM mkol
      INTO TABLE @lt_mkol
      WHERE werks = @g_werks
        AND matnr IN @ir_matnr
        AND ( slabs <> 0 OR sinsm <> 0 OR sspem <> 0 OR seinm <> 0 ).
    LOOP AT lt_mkol INTO ls_mkol.
      READ TABLE et_info INTO ls_info WITH TABLE KEY matnr = ls_mkol-matnr.
      IF sy-subrc <> 0 OR ls_info-qtyupd = abap_false.
        CONTINUE.
      ENDIF.
      CLEAR ls_stock.
      ls_stock-werks  = g_werks.
      ls_stock-lgort  = ls_mkol-lgort.
      ls_stock-matnr  = ls_mkol-matnr.
      IF ls_info-xchpf IS NOT INITIAL.
        ls_stock-charg = ls_mkol-charg.
      ENDIF.
      ls_stock-stkcat = zcl_mm_stkday_calc=>c_stk_loc.
      ls_stock-k_qty  = ls_mkol-slabs + ls_mkol-sinsm + ls_mkol-sspem + ls_mkol-seinm.
      COLLECT ls_stock INTO et_stock.
    ENDLOOP.

    " ⑥ MSKA: 판매오더(E) 현재고 (오더/품목 합산)
    SELECT matnr, lgort, charg, kalab, kains, kaspe, kaein
      FROM mska
      INTO TABLE @lt_mska
      WHERE werks = @g_werks
        AND matnr IN @ir_matnr
        AND ( kalab <> 0 OR kains <> 0 OR kaspe <> 0 OR kaein <> 0 ).
    LOOP AT lt_mska INTO ls_mska.
      READ TABLE et_info INTO ls_info WITH TABLE KEY matnr = ls_mska-matnr.
      IF sy-subrc <> 0 OR ls_info-qtyupd = abap_false.
        CONTINUE.
      ENDIF.
      CLEAR ls_stock.
      ls_stock-werks  = g_werks.
      ls_stock-lgort  = ls_mska-lgort.
      ls_stock-matnr  = ls_mska-matnr.
      IF ls_info-xchpf IS NOT INITIAL.
        ls_stock-charg = ls_mska-charg.
      ENDIF.
      ls_stock-stkcat = zcl_mm_stkday_calc=>c_stk_loc.
      ls_stock-e_qty  = ls_mska-kalab + ls_mska-kains + ls_mska-kaspe + ls_mska-kaein.
      COLLECT ls_stock INTO et_stock.
    ENDLOOP.
  ENDMETHOD.


  METHOD read_moves.
    TYPES: BEGIN OF lty_po,
             ebeln TYPE ekko-ebeln,
           END OF lty_po.
    DATA: lt_po     TYPE STANDARD TABLE OF lty_po WITH EMPTY KEY,
          lt_sto    TYPE SORTED TABLE OF ekko-ebeln WITH UNIQUE KEY table_line,
          lr_storc  TYPE zcl_mm_stkday_calc=>ty_r_bwart,
          lr_stois  TYPE zcl_mm_stkday_calc=>ty_r_bwart.
    FIELD-SYMBOLS <ls_move> TYPE zcl_mm_stkday_calc=>ty_move.

    CLEAR et_move.
    IF ir_matnr IS INITIAL.
      RETURN.
    ENDIF.

    " ⑦ MSEG⋈MKPF DB 집계. 상한 없음(당일·미래 일자 포함 - 역산에 필요)
    "   EBELN은 STO 입고(101/102) 판정(C5)에 필요해 GROUP BY에 포함
    SELECT s~werks, s~lgort, s~matnr, s~charg, k~budat, s~bwart, s~shkzg,
           s~sobkz, s~xauto, s~bustm, s~umwrk, s~ebeln,
           SUM( s~menge ) AS menge
      FROM mkpf AS k
      INNER JOIN mseg AS s ON s~mblnr = k~mblnr
                          AND s~mjahr = k~mjahr
      INTO CORRESPONDING FIELDS OF TABLE @et_move
      WHERE s~werks = @g_werks
        AND s~matnr IN @ir_matnr
        AND k~budat >= @iv_from
      GROUP BY s~werks, s~lgort, s~matnr, s~charg, k~budat, s~bwart, s~shkzg,
               s~sobkz, s~xauto, s~bustm, s~umwrk, s~ebeln.

    " STO 입고 판정: EKKO-RESWK(공급 플랜트) <> 공란
    lr_storc = zcl_mm_stkday_calc=>r_storc.
    lr_stois = zcl_mm_stkday_calc=>r_stois.
    LOOP AT et_move ASSIGNING <ls_move> WHERE ebeln IS NOT INITIAL.
      IF <ls_move>-bwart IN lr_storc.
        APPEND VALUE #( ebeln = <ls_move>-ebeln ) TO lt_po.
      ENDIF.
    ENDLOOP.
    IF lt_po IS NOT INITIAL.
      SORT lt_po BY ebeln.
      DELETE ADJACENT DUPLICATES FROM lt_po COMPARING ebeln.
      SELECT ebeln FROM ekko INTO TABLE @lt_sto
        FOR ALL ENTRIES IN @lt_po
        WHERE ebeln = @lt_po-ebeln
          AND reswk <> @space.
    ENDIF.

    LOOP AT et_move ASSIGNING <ls_move>.
      " 자기 플랜트 STO 출고: 받는 플랜트 = UMWRK (이 플랜트가 아니면 계산 후 제외됨)
      IF <ls_move>-bwart IN lr_stois.
        <ls_move>-recv_werks = <ls_move>-umwrk.
      ENDIF.
      IF <ls_move>-ebeln IS NOT INITIAL AND <ls_move>-bwart IN lr_storc
         AND line_exists( lt_sto[ table_line = <ls_move>-ebeln ] ).
        <ls_move>-sto_rcpt = abap_true.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD read_sto_moves.
    TYPES: BEGIN OF lty_po,
             ebeln TYPE ekpo-ebeln,
             ebelp TYPE ekpo-ebelp,
           END OF lty_po.
    TYPES: BEGIN OF lty_ekpo,
             ebeln TYPE ekpo-ebeln,
             ebelp TYPE ekpo-ebelp,
             werks TYPE ekpo-werks,
           END OF lty_ekpo.
    DATA: lt_sto    TYPE zcl_mm_stkday_calc=>tt_move,
          ls_sto    TYPE zcl_mm_stkday_calc=>ty_move,
          lt_po     TYPE STANDARD TABLE OF lty_po WITH EMPTY KEY,
          lt_ekpo   TYPE HASHED TABLE OF lty_ekpo WITH UNIQUE KEY ebeln ebelp,
          ls_ekpo   TYPE lty_ekpo,
          lr_stois  TYPE zcl_mm_stkday_calc=>ty_r_bwart.

    IF ir_matnr IS INITIAL.
      RETURN.
    ENDIF.

    " ⑧ 다른 플랜트의 STO 출고 중 받는 플랜트가 이 플랜트인 것 (운송중 T 키)
    lr_stois = zcl_mm_stkday_calc=>r_stois.
    SELECT s~werks, s~lgort, s~matnr, s~charg, k~budat, s~bwart, s~shkzg,
           s~sobkz, s~xauto, s~bustm, s~umwrk, s~ebeln, s~ebelp,
           SUM( s~menge ) AS menge
      FROM mkpf AS k
      INNER JOIN mseg AS s ON s~mblnr = k~mblnr
                          AND s~mjahr = k~mjahr
      INTO CORRESPONDING FIELDS OF TABLE @lt_sto
      WHERE s~bwart IN @lr_stois
        AND s~werks <> @g_werks
        AND s~matnr IN @ir_matnr
        AND ( s~umwrk = @g_werks OR s~umwrk = @space )
        AND k~budat >= @iv_from
      GROUP BY s~werks, s~lgort, s~matnr, s~charg, k~budat, s~bwart, s~shkzg,
               s~sobkz, s~xauto, s~bustm, s~umwrk, s~ebeln, s~ebelp.
    IF lt_sto IS INITIAL.
      RETURN.
    ENDIF.

    " UMWRK 공란이면 EKPO-WERKS로 받는 플랜트 판정 (D-05)
    LOOP AT lt_sto INTO ls_sto WHERE umwrk IS INITIAL AND ebeln IS NOT INITIAL.
      APPEND VALUE #( ebeln = ls_sto-ebeln ebelp = ls_sto-ebelp ) TO lt_po.
    ENDLOOP.
    IF lt_po IS NOT INITIAL.
      SORT lt_po BY ebeln ebelp.
      DELETE ADJACENT DUPLICATES FROM lt_po COMPARING ebeln ebelp.
      SELECT ebeln, ebelp, werks FROM ekpo INTO TABLE @lt_ekpo
        FOR ALL ENTRIES IN @lt_po
        WHERE ebeln = @lt_po-ebeln
          AND ebelp = @lt_po-ebelp.
    ENDIF.

    LOOP AT lt_sto INTO ls_sto.
      IF ls_sto-umwrk IS INITIAL.
        READ TABLE lt_ekpo INTO ls_ekpo
             WITH TABLE KEY ebeln = ls_sto-ebeln ebelp = ls_sto-ebelp.
        IF sy-subrc <> 0 OR ls_ekpo-werks <> g_werks.
          CONTINUE.
        ENDIF.
      ENDIF.
      ls_sto-recv_werks = g_werks.
      APPEND ls_sto TO ct_move.
    ENDLOOP.
  ENDMETHOD.


  METHOD compute_block.
    DATA: lt_delta   TYPE zcl_mm_stkday_calc=>tt_delta,
          lt_stock_a TYPE zcl_mm_stkday_calc=>tt_stock,
          lt_delta_a TYPE zcl_mm_stkday_calc=>tt_delta,
          lt_snap    TYPE zcl_mm_stkday_calc=>ty_t_date,
          lt_row     TYPE zcl_mm_stkday_calc=>tt_row,
          ls_row     TYPE zcl_mm_stkday_calc=>ty_row,
          ls_move    TYPE zcl_mm_stkday_calc=>ty_move,
          ls_info    TYPE ty_info,
          ls_b       TYPE ztmm1236,
          ls_a       TYPE ztmm1234,
          l_cancel   TYPE xfeld,
          l_batch    TYPE xfeld.

    CLEAR: et_b, et_a.
    IF iv_from IS INITIAL OR iv_from > g_d_end.
      RETURN.
    ENDIF.

    "-- J5 분류: 행마다 CLASSIFY_MOVE -> 키·일자별 증감표
    LOOP AT it_move INTO ls_move.
      READ TABLE it_info INTO ls_info WITH TABLE KEY matnr = ls_move-matnr.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      l_cancel = abap_false.
      IF line_exists( gt_cancel[ table_line = ls_move-bwart ] ).
        l_cancel = abap_true.
      ENDIF.
      l_batch = abap_false.
      IF ls_info-xchpf IS NOT INITIAL.
        l_batch = abap_true.
      ENDIF.
      zcl_mm_stkday_calc=>classify_move(
        EXPORTING is_move       = ls_move
                  iv_cancel     = l_cancel
                  iv_batch      = l_batch
                  iv_qty_update = ls_info-qtyupd
        CHANGING  ct_delta      = lt_delta ).
    ENDLOOP.
    " 다른 플랜트 키(STO 공급 플랜트 쪽 등)는 이 플랜트 처리에서 버림
    DELETE lt_delta WHERE werks <> g_werks.

    "-- 역산: B(배치 레벨) / A(자재 레벨, 같은 식 - D4)
    lt_snap = zcl_mm_stkday_calc=>get_snapshot_dates( iv_from      = iv_from
                                                      iv_to        = g_d_end
                                                      iv_load_from = g_load_from ).
    lt_row = zcl_mm_stkday_calc=>roll_back( it_stock = it_stock
                                            it_delta = lt_delta
                                            iv_from  = iv_from
                                            iv_to    = g_d_end
                                            it_snap  = lt_snap ).
    LOOP AT lt_row INTO ls_row.
      CLEAR ls_b.
      MOVE-CORRESPONDING ls_row TO ls_b.
      READ TABLE it_info INTO ls_info WITH TABLE KEY matnr = ls_row-matnr.
      IF sy-subrc = 0.
        ls_b-meins = ls_info-meins.
      ENDIF.
      ls_b-erdat = g_run_date.
      ls_b-erzet = g_run_time.
      ls_b-ernam = sy-uname.
      APPEND ls_b TO et_b.
    ENDLOOP.

    zcl_mm_stkday_calc=>to_material_level( EXPORTING it_stock = it_stock
                                                     it_delta = lt_delta
                                           IMPORTING et_stock = lt_stock_a
                                                     et_delta = lt_delta_a ).
    lt_row = zcl_mm_stkday_calc=>roll_back( it_stock = lt_stock_a
                                            it_delta = lt_delta_a
                                            iv_from  = iv_from
                                            iv_to    = g_d_end
                                            it_snap  = lt_snap ).
    LOOP AT lt_row INTO ls_row.
      CLEAR ls_a.
      MOVE-CORRESPONDING ls_row TO ls_a.
      READ TABLE it_info INTO ls_info WITH TABLE KEY matnr = ls_row-matnr.
      IF sy-subrc = 0.
        ls_a-meins = ls_info-meins.
      ENDIF.
      ls_a-erdat = g_run_date.
      ls_a-erzet = g_run_time.
      ls_a-ernam = sy-uname.
      APPEND ls_a TO et_a.
    ENDLOOP.

    "-- J8 정합성 점검(메모리)
    check_consistency( ir_matnr = ir_matnr
                       iv_from  = iv_from
                       it_stock = it_stock
                       it_delta = lt_delta
                       it_snap  = lt_snap
                       it_b     = et_b
                       it_a     = et_a ).
  ENDMETHOD.


  METHOD save_block.
    rv_ok = abap_true.

    " 테스트 실행은 저장하지 않음 (건수만 집계)
    IF g_test = abap_true.
      g_cnt_b = g_cnt_b + lines( it_b ).
      g_cnt_a = g_cnt_a + lines( it_a ).
      RETURN.
    ENDIF.

    "-- J6 블록 삭제 후 INSERT (지운 범위 = 다시 계산한 범위)
    DELETE FROM ztmm1236 WHERE werks = @g_werks
                           AND matnr IN @ir_matnr
                           AND budat >= @iv_from.
    DELETE FROM ztmm1234 WHERE werks = @g_werks
                           AND matnr IN @ir_matnr
                           AND budat >= @iv_from.
    IF it_b IS NOT INITIAL.
      INSERT ztmm1236 FROM TABLE @it_b.
      IF sy-subrc <> 0.
        MESSAGE ID zcl_mm_stkday_calc=>c_msgid TYPE 'E' NUMBER '023'
                WITH g_werks 'ZTMM1236 INSERT' INTO g_errmsg.
        rv_ok = abap_false.
        RETURN.
      ENDIF.
    ENDIF.
    IF it_a IS NOT INITIAL.
      INSERT ztmm1234 FROM TABLE @it_a.
      IF sy-subrc <> 0.
        MESSAGE ID zcl_mm_stkday_calc=>c_msgid TYPE 'E' NUMBER '023'
                WITH g_werks 'ZTMM1234 INSERT' INTO g_errmsg.
        rv_ok = abap_false.
        RETURN.
      ENDIF.
    ENDIF.
    COMMIT WORK.

    g_cnt_b = g_cnt_b + lines( it_b ).
    g_cnt_a = g_cnt_a + lines( it_a ).
  ENDMETHOD.


  METHOD check_consistency.
    TYPES: BEGIN OF lty_prev,
             werks   TYPE ztmm1236-werks,
             lgort   TYPE ztmm1236-lgort,
             matnr   TYPE ztmm1236-matnr,
             charg   TYPE ztmm1236-charg,
             stkcat  TYPE ztmm1236-stkcat,
             budat   TYPE ztmm1236-budat,
             end_qty TYPE ztmm1236-end_qty,
             k_end   TYPE ztmm1236-k_end,
             e_end   TYPE ztmm1236-e_end,
             trf_end TYPE ztmm1236-trf_end,
           END OF lty_prev.
    DATA: lt_dates  TYPE zcl_mm_stkday_calc=>ty_t_date,
          l_date    TYPE budat,
          lt_end    TYPE zcl_mm_stkday_calc=>tt_stock,
          lt_endm   TYPE zcl_mm_stkday_calc=>tt_stock,
          lt_dummy  TYPE zcl_mm_stkday_calc=>tt_delta,
          ls_end    TYPE zcl_mm_stkday_calc=>ty_stock,
          ls_a      TYPE ztmm1234,
          ls_b      TYPE ztmm1236,
          lt_prev   TYPE STANDARD TABLE OF lty_prev WITH EMPTY KEY,
          ls_prev   TYPE lty_prev,
          l_prevday TYPE budat,
          l_win     TYPE budat.

    " (2) 기말 음수 행 수 (B)
    LOOP AT it_b INTO ls_b
         WHERE end_qty < 0 OR k_end < 0 OR e_end < 0 OR trf_end < 0.
      g_cnt_neg = g_cnt_neg + 1.
    ENDLOOP.

    " (1) A 행 기말 = 같은 자재 키 B 키별 그날 기준 기말 합 (구간 끝·스냅샷 일자에서 비교)
    lt_dates = it_snap.
    INSERT g_d_end INTO TABLE lt_dates.
    LOOP AT lt_dates INTO l_date WHERE table_line >= iv_from AND table_line <= g_d_end.
      lt_end = zcl_mm_stkday_calc=>end_at_date( it_stock = it_stock
                                                it_delta = it_delta
                                                iv_date  = l_date ).
      zcl_mm_stkday_calc=>to_material_level( EXPORTING it_stock = lt_end
                                                       it_delta = lt_dummy
                                             IMPORTING et_stock = lt_endm ).
      LOOP AT it_a INTO ls_a WHERE budat = l_date.
        CLEAR ls_end.
        READ TABLE lt_endm INTO ls_end
             WITH TABLE KEY werks  = ls_a-werks
                            lgort  = ls_a-lgort
                            matnr  = ls_a-matnr
                            charg  = space
                            stkcat = ls_a-stkcat.
        IF ls_end-gen_qty <> ls_a-end_qty OR ls_end-k_qty <> ls_a-k_end
           OR ls_end-e_qty <> ls_a-e_end OR ls_end-trf_qty <> ls_a-trf_end.
          g_cnt_mis = g_cnt_mis + 1.
        ENDIF.
      ENDLOOP.
    ENDLOOP.

    " (3) 연속성: 시작일 전날 저장 기말 = 새로 계산한 전날 기말 (초기 적재 제외)
    IF g_mode = zcl_mm_stkday_calc=>c_mode_init OR iv_from <= g_load_from.
      RETURN.
    ENDIF.
    l_prevday = iv_from - 1.
    l_win = zcl_mm_stkday_calc=>month_start( l_prevday ).
    IF l_win < g_load_from.
      l_win = g_load_from.
    ENDIF.
    SELECT werks, lgort, matnr, charg, stkcat, budat, end_qty, k_end, e_end, trf_end
      FROM ztmm1236
      INTO TABLE @lt_prev
      WHERE werks = @g_werks
        AND matnr IN @ir_matnr
        AND budat BETWEEN @l_win AND @l_prevday.
    SORT lt_prev BY werks lgort matnr charg stkcat budat DESCENDING.
    DELETE ADJACENT DUPLICATES FROM lt_prev COMPARING werks lgort matnr charg stkcat.

    lt_end = zcl_mm_stkday_calc=>end_at_date( it_stock = it_stock
                                              it_delta = it_delta
                                              iv_date  = l_prevday ).
    LOOP AT lt_prev INTO ls_prev.
      CLEAR ls_end.
      READ TABLE lt_end INTO ls_end
           WITH TABLE KEY werks  = ls_prev-werks
                          lgort  = ls_prev-lgort
                          matnr  = ls_prev-matnr
                          charg  = ls_prev-charg
                          stkcat = ls_prev-stkcat.
      IF ls_end-gen_qty <> ls_prev-end_qty OR ls_end-k_qty <> ls_prev-k_end
         OR ls_end-e_qty <> ls_prev-e_end OR ls_end-trf_qty <> ls_prev-trf_end.
        g_cnt_con = g_cnt_con + 1.
      ENDIF.
    ENDLOOP.
    " 새 계산에는 재고가 있는데 저장 행이 없는 키
    LOOP AT lt_end INTO ls_end
         WHERE gen_qty <> 0 OR k_qty <> 0 OR e_qty <> 0 OR trf_qty <> 0.
      " LT_PREV는 키 오름차순 정렬 상태(전기일만 내림차순)라 BINARY SEARCH 사용
      READ TABLE lt_prev TRANSPORTING NO FIELDS
           WITH KEY werks  = ls_end-werks
                    lgort  = ls_end-lgort
                    matnr  = ls_end-matnr
                    charg  = ls_end-charg
                    stkcat = ls_end-stkcat
           BINARY SEARCH.
      IF sy-subrc <> 0.
        g_cnt_con = g_cnt_con + 1.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD update_control.
    DATA: l_jobname  TYPE btcjob,
          l_jobcount TYPE btcjobcnt.

    " 테스트 실행은 제어 정보를 바꾸지 않음
    IF g_test = abap_true.
      RETURN.
    ENDIF.

    IF iv_success = abap_true.
      CASE g_mode.
        WHEN zcl_mm_stkday_calc=>c_mode_daily.
          gs_ctrl-last_budat = g_d_end.
          gs_ctrl-last_cpudt = g_run_date.
          gs_ctrl-last_cputm = g_run_time.
        WHEN zcl_mm_stkday_calc=>c_mode_init.
          gs_ctrl-load_from  = g_from.
          gs_ctrl-last_budat = g_d_end.
          gs_ctrl-last_cpudt = g_run_date.
          gs_ctrl-last_cputm = g_run_time.
        WHEN OTHERS.
          " 재집계: LAST_* 유지
      ENDCASE.
    ENDIF.

    gs_ctrl-run_stat = iv_stat.
    gs_ctrl-run_mats = iv_mats.
    gs_ctrl-run_msg  = g_errmsg.
    IF sy-batch = abap_true.
      CALL FUNCTION 'GET_JOB_RUNTIME_INFO'
        IMPORTING
          jobcount        = l_jobcount
          jobname         = l_jobname
        EXCEPTIONS
          no_runtime_info = 1
          OTHERS          = 2.
      IF sy-subrc = 0.
        gs_ctrl-jobname  = l_jobname.
        gs_ctrl-jobcount = l_jobcount.
      ENDIF.
    ELSE.
      CLEAR: gs_ctrl-jobname, gs_ctrl-jobcount.
    ENDIF.
    gs_ctrl-aedat = sy-datum.
    gs_ctrl-aezet = sy-uzeit.
    gs_ctrl-aenam = sy-uname.

    MODIFY ztmm1237 FROM @gs_ctrl.
    COMMIT WORK.
  ENDMETHOD.


  METHOD open_log.
    DATA ls_log TYPE bal_s_log.

    CLEAR g_log.
    ls_log-object    = c_log_object.
    ls_log-subobject = c_log_subobj.
    ls_log-extnumber = |{ g_werks } { g_run_date } { g_run_time }|.
    ls_log-aldate    = sy-datum.
    ls_log-altime    = sy-uzeit.
    ls_log-aluser    = sy-uname.
    ls_log-alprog    = sy-cprog.

    CALL FUNCTION 'BAL_LOG_CREATE'
      EXPORTING
        i_s_log                 = ls_log
      IMPORTING
        e_log_handle            = g_log
      EXCEPTIONS
        log_header_inconsistent = 1
        OTHERS                  = 2.
    IF sy-subrc <> 0.
      " 로그 오브젝트 미생성(SLG0) 등: 로그 없이 계속 (결과 목록·잡 로그로 확인)
      CLEAR g_log.
    ENDIF.
  ENDMETHOD.


  METHOD save_log.
    DATA lt_handle TYPE bal_t_logh.

    IF g_log IS INITIAL.
      RETURN.
    ENDIF.
    APPEND g_log TO lt_handle.
    CALL FUNCTION 'BAL_DB_SAVE'
      EXPORTING
        i_t_log_handle   = lt_handle
      EXCEPTIONS
        log_not_found    = 1
        save_not_allowed = 2
        numbering_error  = 3
        OTHERS           = 4.
    IF sy-subrc = 0.
      COMMIT WORK.
    ENDIF.
    CLEAR g_log.
  ENDMETHOD.


  METHOD add_log.
    DATA: ls_msg TYPE bal_s_msg,
          l_v1   TYPE symsgv,
          l_v2   TYPE symsgv,
          l_v3   TYPE symsgv,
          l_v4   TYPE symsgv.

    " 전달된 값만 문자로 변환(숫자 앞 공백 제거)
    IF iv_v1 IS SUPPLIED.
      l_v1 = iv_v1.
      CONDENSE l_v1.
    ENDIF.
    IF iv_v2 IS SUPPLIED.
      l_v2 = iv_v2.
      CONDENSE l_v2.
    ENDIF.
    IF iv_v3 IS SUPPLIED.
      l_v3 = iv_v3.
      CONDENSE l_v3.
    ENDIF.
    IF iv_v4 IS SUPPLIED.
      l_v4 = iv_v4.
      CONDENSE l_v4.
    ENDIF.

    MESSAGE ID zcl_mm_stkday_calc=>c_msgid TYPE iv_type NUMBER iv_number
            WITH l_v1 l_v2 l_v3 l_v4 INTO rv_text.

    ls_msg-msgty = sy-msgty.
    ls_msg-msgid = sy-msgid.
    ls_msg-msgno = sy-msgno.
    ls_msg-msgv1 = sy-msgv1.
    ls_msg-msgv2 = sy-msgv2.
    ls_msg-msgv3 = sy-msgv3.
    ls_msg-msgv4 = sy-msgv4.

    IF g_log IS NOT INITIAL.
      CALL FUNCTION 'BAL_LOG_MSG_ADD'
        EXPORTING
          i_log_handle     = g_log
          i_s_msg          = ls_msg
        EXCEPTIONS
          log_not_found    = 1
          msg_inconsistent = 2
          log_is_full      = 3
          OTHERS           = 4.
      IF sy-subrc <> 0.
        CLEAR g_log.
      ENDIF.
    ENDIF.

    " 백그라운드: 잡 로그에도 남김 (S 유형으로 남겨 실행을 끊지 않음)
    IF sy-batch = abap_true.
      MESSAGE ID ls_msg-msgid TYPE 'S' NUMBER ls_msg-msgno
              WITH ls_msg-msgv1 ls_msg-msgv2 ls_msg-msgv3 ls_msg-msgv4.
    ENDIF.
  ENDMETHOD.


  METHOD date_text.
    rv_text = |{ iv_date DATE = USER }|.
  ENDMETHOD.
ENDCLASS.
