"! <p class="shorttext synchronized" lang="ko">자재마스터 조회 리포트 로직(ZRMM0024)</p>
"! 조회 전용. DB 변경 없음. 호출 프로그램: ZRMM0024 (T-code ZRMM0024, 패키지 ZMMD)
"! 현업 확정: Q1 플랜트 필수 / Q2 삭제여부 = MARC-LVORM / Q3 단가 = 항상 MBEW-VERPR
"! 현업 미결(분석 가정·권장안 적용): Q4 자재명 언어 + 대체 언어 / Q5 최대건수(0 = 무제한)
"!                                   Q9 배치관리 = MARC-XCHPF / Q10 배치관리 선택조건(전체 기본)
"! 대상: ECC(MATNR C18), SAP_BASIS 7.40 (SP09 이상·7.50 미만 추정). FOR 반복식 사용 → SP08 이상 필요
"! 명명: UNION Steel ABAP 개발표준 Handbook 2장 (상수 C_, 속성 G_/GS_/R_, 로컬 L_/LT_/LS_/R_)
"!       타입·메서드 파라미터는 핸드북 규칙 없음 — SAP 관례 적용 (설계 4.2)
"! 타입은 테이블 필드 참조(marc-lvorm 등)로 DB 필드 타입과 항상 일치시킴
CLASS zcl_mm_material_list DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    TYPES ty_del_mode TYPE c LENGTH 1.
    TYPES ty_batch_mode TYPE c LENGTH 1.

    "! 삭제여부 모드 (MARC-LVORM 기준, 현업 확정 Q2)
    CONSTANTS:
      BEGIN OF c_del_mode,
        del_exclude TYPE ty_del_mode VALUE 'E', " 삭제 제외(기본)
        del_only    TYPE ty_del_mode VALUE 'O', " 삭제만
        del_all     TYPE ty_del_mode VALUE 'A', " 전체
      END OF c_del_mode.

    "! 배치관리 모드 (MARC-XCHPF 기준, Q9-a / Q10)
    CONSTANTS:
      BEGIN OF c_batch_mode,
        all  TYPE ty_batch_mode VALUE 'A', " 전체(기본)
        only TYPE ty_batch_mode VALUE 'B', " 배치관리 자재만
        none TYPE ty_batch_mode VALUE 'N', " 비배치관리 자재만
      END OF c_batch_mode.

    "! 최대건수 기본값 (Q5 분석 가정). 0 = 무제한
    CONSTANTS c_default_maxhit TYPE i VALUE 50000.
    "! 자재명 대체 언어 기본값 (Q4 분석 가정, 내부 언어키 'E' = EN)
    CONSTANTS c_default_spras2 TYPE spras VALUE 'E'.

    TYPES:
      tt_r_werks TYPE RANGE OF werks_d,
      tt_r_matnr TYPE RANGE OF matnr,
      tt_r_mtart TYPE RANGE OF mtart,
      tt_r_matkl TYPE RANGE OF matkl,
      tt_r_ernam TYPE RANGE OF ernam,
      tt_r_ersda TYPE RANGE OF ersda,
      "! 삭제여부 조건 range (MARC-LVORM)
      tt_r_lvorm TYPE RANGE OF marc-lvorm,
      "! 배치관리 조건 range (MARC-XCHPF)
      tt_r_xchpf TYPE RANGE OF marc-xchpf.

    TYPES:
      BEGIN OF ty_sel,
        werks      TYPE tt_r_werks,
        matnr      TYPE tt_r_matnr,
        mtart      TYPE tt_r_mtart,
        matkl      TYPE tt_r_matkl,
        ernam      TYPE tt_r_ernam,
        ersda      TYPE tt_r_ersda,
        del_mode   TYPE ty_del_mode,      " E=삭제 제외 O=삭제만 A=전체
        batch_mode TYPE ty_batch_mode,    " A=전체 B=배치관리만 N=비배치관리만
        spras      TYPE spras,            " 자재명·텍스트 언어
        spras2     TYPE spras,            " 자재명 대체 언어(공란 = 대체 안 함)
        maxhit     TYPE i,                " 최대건수(0 = 무제한)
      END OF ty_sel.

    "! ALV 출력 구조 (컴포넌트 순서 = ALV 컬럼 순서, 설계 9장)
    TYPES:
      BEGIN OF ty_out,
        matnr   TYPE matnr,
        ersda   TYPE ersda,
        werks   TYPE werks_d,
        meins   TYPE meins,
        maktx   TYPE maktx,
        matkl   TYPE matkl,
        wgbez   TYPE t023t-wgbez,         " 자재그룹명
        spart   TYPE spart,
        spart_t TYPE tspat-vtext,         " 제품군명
        verpr   TYPE mbew-verpr,          " 이동평균가 (확정 Q3)
        peinh   TYPE mbew-peinh,
        waers   TYPE waers,
        lvorm   TYPE marc-lvorm,          " 삭제여부 = MARC-LVORM (확정 Q2)
        xchpf   TYPE marc-xchpf,          " 배치관리 여부 = MARC-XCHPF ('X'/공란)
        mtart   TYPE mtart,
        mtbez   TYPE t134t-mtbez,         " 자재유형명
        ernam   TYPE ernam,
      END OF ty_out,
      tt_out TYPE STANDARD TABLE OF ty_out WITH EMPTY KEY.

    TYPES tt_werks TYPE STANDARD TABLE OF werks_d WITH EMPTY KEY.

    "! 자재명 버퍼 (pick_text 입력)
    TYPES:
      BEGIN OF ty_makt,
        matnr TYPE matnr,
        spras TYPE spras,
        maktx TYPE maktx,
      END OF ty_makt,
      tt_makt TYPE SORTED TABLE OF ty_makt WITH UNIQUE KEY matnr spras.

    "! @parameter is_sel | 조회조건
    METHODS constructor
      IMPORTING
        is_sel TYPE ty_sel.

    "! 조회조건 플랜트별 M_MATE_WRK(ACTVT 03) 권한 체크. 통과 플랜트만 조회에 사용
    "! @parameter et_allowed | 권한 있는 플랜트
    "! @parameter et_denied  | 권한 없는 플랜트
    METHODS check_plant_authority
      EXPORTING
        et_allowed TYPE tt_werks
        et_denied  TYPE tt_werks.

    "! 조회 실행 (권한 체크 미실행 시 내부에서 먼저 수행)
    METHODS get_data
      RETURNING
        VALUE(rt_out) TYPE tt_out.

    "! 최대건수 도달 여부 (get_data 이후 유효)
    METHODS is_truncated
      RETURNING
        VALUE(rv_truncated) TYPE abap_bool.

    "! 삭제여부 조건 range (MARC-LVORM 기준 고정, 확정 Q2)
    "! E: I EQ ' ' / O: I NE ' ' / A 및 그 외 값: 빈 range(조건 없음)
    CLASS-METHODS build_deletion_range
      IMPORTING
        iv_mode         TYPE ty_del_mode
      RETURNING
        VALUE(rt_range) TYPE tt_r_lvorm.

    "! 배치관리 조건 range (MARC-XCHPF 기준)
    "! A 및 그 외 값: 빈 range / B: I NE ' ' / N: I EQ ' '
    CLASS-METHODS build_batch_range
      IMPORTING
        iv_mode         TYPE ty_batch_mode
      RETURNING
        VALUE(rt_range) TYPE tt_r_xchpf.

    "! 자재명 판정: 1순위 언어, 없으면 대체 언어, 둘 다 없으면 공란
    "! @parameter it_makt   | 자재명 버퍼
    "! @parameter iv_matnr  | 자재
    "! @parameter iv_spras  | 1순위 언어
    "! @parameter iv_spras2 | 대체 언어(공란이면 대체하지 않음)
    CLASS-METHODS pick_text
      IMPORTING
        it_makt         TYPE tt_makt
        iv_matnr        TYPE matnr
        iv_spras        TYPE spras
        iv_spras2       TYPE spras
      RETURNING
        VALUE(rv_maktx) TYPE maktx.

  PROTECTED SECTION.

  PRIVATE SECTION.

    CONSTANTS:
      c_auth_obj_plant TYPE xuobject VALUE 'M_MATE_WRK',
      c_actvt_display  TYPE activ_auth VALUE '03'.

    TYPES:
      BEGIN OF ty_main,
        matnr TYPE matnr,
        ersda TYPE ersda,
        ernam TYPE ernam,
        mtart TYPE mtart,
        matkl TYPE matkl,
        spart TYPE spart,
        meins TYPE meins,
        werks TYPE werks_d,
        lvorm TYPE marc-lvorm,
        xchpf TYPE marc-xchpf,
        bwkey TYPE bwkey,
      END OF ty_main,
      tt_main TYPE STANDARD TABLE OF ty_main WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_mbew_key,
        matnr TYPE matnr,
        bwkey TYPE bwkey,
      END OF ty_mbew_key,
      tt_mbew_key TYPE STANDARD TABLE OF ty_mbew_key WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_mbew,
        matnr TYPE matnr,
        bwkey TYPE bwkey,
        verpr TYPE mbew-verpr,
        peinh TYPE mbew-peinh,
      END OF ty_mbew,
      tt_mbew TYPE HASHED TABLE OF ty_mbew WITH UNIQUE KEY matnr bwkey.

    TYPES:
      BEGIN OF ty_curr,
        bwkey TYPE bwkey,
        waers TYPE waers,
      END OF ty_curr,
      tt_curr TYPE HASHED TABLE OF ty_curr WITH UNIQUE KEY bwkey.

    TYPES:
      BEGIN OF ty_t134t,
        mtart TYPE mtart,
        mtbez TYPE t134t-mtbez,
      END OF ty_t134t,
      tt_t134t TYPE HASHED TABLE OF ty_t134t WITH UNIQUE KEY mtart,
      BEGIN OF ty_t023t,
        matkl TYPE matkl,
        wgbez TYPE t023t-wgbez,
      END OF ty_t023t,
      tt_t023t TYPE HASHED TABLE OF ty_t023t WITH UNIQUE KEY matkl,
      BEGIN OF ty_tspat,
        spart TYPE spart,
        vtext TYPE tspat-vtext,
      END OF ty_tspat,
      tt_tspat TYPE HASHED TABLE OF ty_tspat WITH UNIQUE KEY spart.

    TYPES:
      tt_matnr   TYPE STANDARD TABLE OF matnr WITH EMPTY KEY,
      tt_bwkey   TYPE STANDARD TABLE OF bwkey WITH EMPTY KEY,
      tt_mtart   TYPE STANDARD TABLE OF mtart WITH EMPTY KEY,
      tt_matkl   TYPE STANDARD TABLE OF matkl WITH EMPTY KEY,
      tt_spart   TYPE STANDARD TABLE OF spart WITH EMPTY KEY,
      tt_r_spras TYPE RANGE OF spras.

    " 클래스 속성 = Global (핸드북 3장 적용 메모)
    DATA gs_sel TYPE ty_sel.              " 조회 조건 (Structure)
    DATA r_werks TYPE tt_r_werks.         " 권한 통과 플랜트 (Ranges)
    DATA g_auth_checked TYPE abap_bool.   " 권한 체크 수행 여부 (Variables)
    DATA g_truncated TYPE abap_bool.      " 최대건수 도달 여부 (Variables)

    METHODS read_main
      RETURNING
        VALUE(rt_main) TYPE tt_main.

    METHODS read_makt
      IMPORTING
        it_main        TYPE tt_main
      RETURNING
        VALUE(rt_makt) TYPE tt_makt.

    METHODS read_mbew
      IMPORTING
        it_main        TYPE tt_main
      RETURNING
        VALUE(rt_mbew) TYPE tt_mbew.

    METHODS read_currency
      IMPORTING
        it_main        TYPE tt_main
      RETURNING
        VALUE(rt_curr) TYPE tt_curr.

    METHODS read_texts
      IMPORTING
        it_main  TYPE tt_main
      EXPORTING
        et_t134t TYPE tt_t134t
        et_t023t TYPE tt_t023t
        et_tspat TYPE tt_tspat.

ENDCLASS.



CLASS zcl_mm_material_list IMPLEMENTATION.


  METHOD constructor.
    gs_sel = is_sel.

    " 언어 기본값: 공란이면 로그온 언어 (Q4 분석 가정)
    IF gs_sel-spras IS INITIAL.
      gs_sel-spras = sy-langu.
    ENDIF.

    " 대체 언어가 1순위 언어와 같으면 대체하지 않음
    IF gs_sel-spras2 = gs_sel-spras.
      CLEAR gs_sel-spras2.
    ENDIF.

    " 최대건수 음수는 선택화면에서 막지만 방어적으로 기본값 적용
    IF gs_sel-maxhit < 0.
      gs_sel-maxhit = c_default_maxhit.
    ENDIF.
  ENDMETHOD.


  METHOD build_deletion_range.
    " 판정 기준은 MARC-LVORM(플랜트 레벨) 고정 (현업 확정 Q2)
    CASE iv_mode.
      WHEN c_del_mode-del_exclude.
        rt_range = VALUE #( ( sign = 'I' option = 'EQ' low = space ) ).
      WHEN c_del_mode-del_only.
        rt_range = VALUE #( ( sign = 'I' option = 'NE' low = space ) ).
      WHEN OTHERS.
        " c_del_mode-del_all 및 잘못된 값: 빈 range = 조건 없음 (설계 7.3, 10장)
        CLEAR rt_range.
    ENDCASE.
  ENDMETHOD.


  METHOD build_batch_range.
    " 판정 기준은 MARC-XCHPF(플랜트 레벨) (Q9-a, 가정 8)
    CASE iv_mode.
      WHEN c_batch_mode-only.
        rt_range = VALUE #( ( sign = 'I' option = 'NE' low = space ) ).
      WHEN c_batch_mode-none.
        rt_range = VALUE #( ( sign = 'I' option = 'EQ' low = space ) ).
      WHEN OTHERS.
        " c_batch_mode-all 및 잘못된 값: 빈 range = 조건 없음
        CLEAR rt_range.
    ENDCASE.
  ENDMETHOD.


  METHOD pick_text.
    CLEAR rv_maktx.

    READ TABLE it_makt ASSIGNING FIELD-SYMBOL(<ls_makt>)
         WITH TABLE KEY matnr = iv_matnr
                        spras = iv_spras.
    IF sy-subrc = 0.
      rv_maktx = <ls_makt>-maktx.
      RETURN.
    ENDIF.

    " 대체 언어가 공란이거나 1순위와 같으면 대체하지 않음
    IF iv_spras2 IS INITIAL OR iv_spras2 = iv_spras.
      RETURN.
    ENDIF.

    READ TABLE it_makt ASSIGNING <ls_makt>
         WITH TABLE KEY matnr = iv_matnr
                        spras = iv_spras2.
    IF sy-subrc = 0.
      rv_maktx = <ls_makt>-maktx.
    ENDIF.
  ENDMETHOD.


  METHOD check_plant_authority.
    DATA lt_werks TYPE tt_werks.
    DATA l_werks TYPE werks_d.

    CLEAR: et_allowed, et_denied, r_werks.
    g_auth_checked = abap_true.

    " 플랜트는 필수 조건 (현업 확정 Q1). 비어 있으면 아무것도 허용하지 않음
    IF gs_sel-werks IS INITIAL.
      RETURN.
    ENDIF.

    SELECT werks
      FROM t001w
      INTO TABLE @lt_werks
      WHERE werks IN @gs_sel-werks
      ORDER BY werks.

    LOOP AT lt_werks INTO l_werks.
      AUTHORITY-CHECK OBJECT c_auth_obj_plant
        ID 'ACTVT' FIELD c_actvt_display
        ID 'WERKS' FIELD l_werks.
      IF sy-subrc = 0.
        APPEND l_werks TO et_allowed.
        APPEND VALUE #( sign = 'I' option = 'EQ' low = l_werks ) TO r_werks.
      ELSE.
        APPEND l_werks TO et_denied.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD get_data.
    DATA lt_t134t TYPE tt_t134t.
    DATA lt_t023t TYPE tt_t023t.
    DATA lt_tspat TYPE tt_tspat.

    CLEAR: rt_out, g_truncated.

    IF g_auth_checked = abap_false.
      check_plant_authority( ).
    ENDIF.

    " 허용 플랜트가 없으면 조회하지 않음 (빈 range IN = 전체 조회 방지)
    IF r_werks IS INITIAL.
      RETURN.
    ENDIF.

    DATA(lt_main) = read_main( ).
    IF lt_main IS INITIAL.
      RETURN.
    ENDIF.

    DATA(lt_makt) = read_makt( lt_main ).
    DATA(lt_mbew) = read_mbew( lt_main ).
    DATA(lt_curr) = read_currency( lt_main ).
    read_texts(
      EXPORTING
        it_main  = lt_main
      IMPORTING
        et_t134t = lt_t134t
        et_t023t = lt_t023t
        et_tspat = lt_tspat ).

    LOOP AT lt_main ASSIGNING FIELD-SYMBOL(<ls_main>).
      APPEND INITIAL LINE TO rt_out ASSIGNING FIELD-SYMBOL(<ls_out>).
      " lvorm, xchpf는 MARC 값을 변환 없이 그대로 옮김 (설계 7.4)
      <ls_out> = CORRESPONDING #( <ls_main> ).

      " 자재명: 1순위 언어 → 대체 언어 → 공란 (Q4)
      <ls_out>-maktx = pick_text( it_makt   = lt_makt
                                  iv_matnr  = <ls_main>-matnr
                                  iv_spras  = gs_sel-spras
                                  iv_spras2 = gs_sel-spras2 ).

      " 단가: 항상 MBEW-VERPR (현업 확정 Q3). 평가 뷰 없으면 0
      READ TABLE lt_mbew ASSIGNING FIELD-SYMBOL(<ls_mbew>)
           WITH TABLE KEY matnr = <ls_main>-matnr
                          bwkey = <ls_main>-bwkey.
      IF sy-subrc = 0.
        <ls_out>-verpr = <ls_mbew>-verpr.
        <ls_out>-peinh = <ls_mbew>-peinh.
      ENDIF.

      READ TABLE lt_curr ASSIGNING FIELD-SYMBOL(<ls_curr>)
           WITH TABLE KEY bwkey = <ls_main>-bwkey.
      IF sy-subrc = 0.
        <ls_out>-waers = <ls_curr>-waers.
      ENDIF.

      READ TABLE lt_t134t ASSIGNING FIELD-SYMBOL(<ls_t134t>)
           WITH TABLE KEY mtart = <ls_main>-mtart.
      IF sy-subrc = 0.
        <ls_out>-mtbez = <ls_t134t>-mtbez.
      ENDIF.

      READ TABLE lt_t023t ASSIGNING FIELD-SYMBOL(<ls_t023t>)
           WITH TABLE KEY matkl = <ls_main>-matkl.
      IF sy-subrc = 0.
        <ls_out>-wgbez = <ls_t023t>-wgbez.
      ENDIF.

      READ TABLE lt_tspat ASSIGNING FIELD-SYMBOL(<ls_tspat>)
           WITH TABLE KEY spart = <ls_main>-spart.
      IF sy-subrc = 0.
        <ls_out>-spart_t = <ls_tspat>-vtext.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD is_truncated.
    rv_truncated = g_truncated.
  ENDMETHOD.


  METHOD read_main.
    DATA l_maxhit TYPE i.

    " 삭제여부(Q2)·배치관리(FR-13) 조건은 range. 빈 range는 조건 없음
    DATA(r_lvorm) = build_deletion_range( gs_sel-del_mode ).
    DATA(r_xchpf) = build_batch_range( gs_sel-batch_mode ).

    " 최대건수 0 = 무제한: UP TO 0 ROWS 동작에 의존하지 않고 INT4 최대값 사용 (SELECT 분기 없음)
    " CL_ABAP_MATH=>MAX_INT4 (TYPE i, 2147483647) 시스템 존재 확인
    IF gs_sel-maxhit > 0.
      l_maxhit = gs_sel-maxhit.
    ELSE.
      l_maxhit = cl_abap_math=>max_int4.
    ENDIF.

    " 7.40 SP05 호환 절 순서: INTO → UP TO → WHERE → ORDER BY
    SELECT a~matnr, a~ersda, a~ernam, a~mtart, a~matkl, a~spart, a~meins,
           c~werks, c~lvorm, c~xchpf, w~bwkey
      FROM mara AS a
      INNER JOIN marc  AS c ON c~matnr = a~matnr
      INNER JOIN t001w AS w ON w~werks = c~werks
      INTO CORRESPONDING FIELDS OF TABLE @rt_main
      UP TO @l_maxhit ROWS
      WHERE c~werks IN @r_werks
        AND a~matnr IN @gs_sel-matnr
        AND a~mtart IN @gs_sel-mtart
        AND a~matkl IN @gs_sel-matkl
        AND a~ernam IN @gs_sel-ernam
        AND a~ersda IN @gs_sel-ersda
        AND c~lvorm IN @r_lvorm         " 삭제여부 (Q2)
        AND c~xchpf IN @r_xchpf         " 배치관리 (FR-13)
      ORDER BY a~matnr, c~werks.

    " 최대건수에 도달하면 잘림 플래그 (maxhit > 0일 때만)
    IF gs_sel-maxhit > 0 AND lines( rt_main ) >= gs_sel-maxhit.
      g_truncated = abap_true.
    ENDIF.
  ENDMETHOD.


  METHOD read_makt.
    DATA lt_matnr TYPE tt_matnr.
    DATA r_spras TYPE tt_r_spras.

    lt_matnr = VALUE #( FOR ls_main IN it_main ( ls_main-matnr ) ).
    SORT lt_matnr BY table_line.
    DELETE ADJACENT DUPLICATES FROM lt_matnr COMPARING table_line.
    IF lt_matnr IS INITIAL.
      RETURN.
    ENDIF.

    " 1순위 언어 + 대체 언어(공란이면 1순위만) (Q4)
    APPEND VALUE #( sign = 'I' option = 'EQ' low = gs_sel-spras ) TO r_spras.
    IF gs_sel-spras2 IS NOT INITIAL.
      APPEND VALUE #( sign = 'I' option = 'EQ' low = gs_sel-spras2 ) TO r_spras.
    ENDIF.

    SELECT matnr, spras, maktx
      FROM makt
      INTO CORRESPONDING FIELDS OF TABLE @rt_makt
      FOR ALL ENTRIES IN @lt_matnr
      WHERE matnr = @lt_matnr-table_line
        AND spras IN @r_spras.
  ENDMETHOD.


  METHOD read_mbew.
    DATA lt_mbew_key TYPE tt_mbew_key.

    lt_mbew_key = VALUE #( FOR ls_main IN it_main
                           ( matnr = ls_main-matnr bwkey = ls_main-bwkey ) ).
    SORT lt_mbew_key BY matnr bwkey.
    DELETE ADJACENT DUPLICATES FROM lt_mbew_key COMPARING matnr bwkey.
    IF lt_mbew_key IS INITIAL.
      RETURN.
    ENDIF.

    " 분할평가 자재는 헤더 레코드(평가유형 공란)만 사용 (Q7)
    SELECT matnr, bwkey, verpr, peinh
      FROM mbew
      INTO CORRESPONDING FIELDS OF TABLE @rt_mbew
      FOR ALL ENTRIES IN @lt_mbew_key
      WHERE matnr = @lt_mbew_key-matnr
        AND bwkey = @lt_mbew_key-bwkey
        AND bwtar = @space.
  ENDMETHOD.


  METHOD read_currency.
    DATA lt_bwkey TYPE tt_bwkey.

    lt_bwkey = VALUE #( FOR ls_main IN it_main ( ls_main-bwkey ) ).
    SORT lt_bwkey BY table_line.
    DELETE ADJACENT DUPLICATES FROM lt_bwkey COMPARING table_line.
    IF lt_bwkey IS INITIAL.
      RETURN.
    ENDIF.

    " 평가영역 → 회사코드 → 통화
    SELECT k~bwkey, t~waers
      FROM t001k AS k
      INNER JOIN t001 AS t ON t~bukrs = k~bukrs
      INTO CORRESPONDING FIELDS OF TABLE @rt_curr
      FOR ALL ENTRIES IN @lt_bwkey
      WHERE k~bwkey = @lt_bwkey-table_line.
  ENDMETHOD.


  METHOD read_texts.
    DATA lt_mtart TYPE tt_mtart.
    DATA lt_matkl TYPE tt_matkl.
    DATA lt_spart TYPE tt_spart.

    CLEAR: et_t134t, et_t023t, et_tspat.

    lt_mtart = VALUE #( FOR ls_main IN it_main ( ls_main-mtart ) ).
    SORT lt_mtart BY table_line.
    DELETE ADJACENT DUPLICATES FROM lt_mtart COMPARING table_line.

    lt_matkl = VALUE #( FOR ls_main IN it_main ( ls_main-matkl ) ).
    SORT lt_matkl BY table_line.
    DELETE ADJACENT DUPLICATES FROM lt_matkl COMPARING table_line.

    lt_spart = VALUE #( FOR ls_main IN it_main ( ls_main-spart ) ).
    SORT lt_spart BY table_line.
    DELETE ADJACENT DUPLICATES FROM lt_spart COMPARING table_line.

    " 텍스트 언어 = PA_SPRAS (설계 6장)
    IF lt_mtart IS NOT INITIAL.
      SELECT mtart, mtbez
        FROM t134t
        INTO CORRESPONDING FIELDS OF TABLE @et_t134t
        FOR ALL ENTRIES IN @lt_mtart
        WHERE spras = @gs_sel-spras
          AND mtart = @lt_mtart-table_line.
    ENDIF.

    IF lt_matkl IS NOT INITIAL.
      SELECT matkl, wgbez
        FROM t023t
        INTO CORRESPONDING FIELDS OF TABLE @et_t023t
        FOR ALL ENTRIES IN @lt_matkl
        WHERE spras = @gs_sel-spras
          AND matkl = @lt_matkl-table_line.
    ENDIF.

    IF lt_spart IS NOT INITIAL.
      SELECT spart, vtext
        FROM tspat
        INTO CORRESPONDING FIELDS OF TABLE @et_tspat
        FOR ALL ENTRIES IN @lt_spart
        WHERE spras = @gs_sel-spras
          AND spart = @lt_spart-table_line.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
