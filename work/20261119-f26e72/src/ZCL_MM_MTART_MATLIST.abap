CLASS zcl_mm_mtart_matlist DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

*----------------------------------------------------------------------*
* 클래스  : ZCL_MM_MTART_MATLIST
* 내역    : [MM] 자재유형별 자재 리스트 조회 로직
* 호출    : FM Z_MM_GET_MATERIAL_LIST (함수 그룹 ZFGMM71, 일반 함수 모듈)
* 요청 ID : 20261119-f26e72
* 처리    : 입력 정규화 -> 입력 누락 검사 -> T134 존재 검사
*           -> (T134-BEGRU 있으면) M_MATE_MAR 권한 점검
*           -> MARA 조회 -> MAKT FOR ALL ENTRIES -> 정렬/최대건수
*           -> ET_LIST / EV_COUNT / ES_RETURN(BAPIRET2 단건)
* 출력타입: TY_LIST / TT_LIST 는 FM Z_MM_GET_MATERIAL_LIST 의 ET_LIST
*           파라미터 타입이다(신규 DDIC 구조·테이블 타입 없음).
*           FM·호출 프로그램이 참조하므로 이름·필드 변경 금지.
*           필드 추가는 맨 뒤에만 한다.
* 문법    : ABAP 7.40 SP05 이상 (New Open SQL). SP08 이상 구문 미사용
* 읽기 전용: DB 갱신/COMMIT 없음
*----------------------------------------------------------------------*
  PUBLIC SECTION.

    "FM 출력 행: 자재코드, 자재내역, 기본단위 (내부 형식)
    TYPES:
      BEGIN OF ty_list,
        matnr TYPE matnr,
        maktx TYPE maktx,
        meins TYPE meins,
      END OF ty_list.
    "FM 출력 테이블 (Z_MM_GET_MATERIAL_LIST-ET_LIST)
    TYPES:
      tt_list TYPE STANDARD TABLE OF ty_list WITH DEFAULT KEY.

    TYPES:
      BEGIN OF ty_mara,
        matnr TYPE mara-matnr,
        meins TYPE mara-meins,
      END OF ty_mara.
    TYPES:
      tt_mara TYPE STANDARD TABLE OF ty_mara WITH DEFAULT KEY.
    TYPES:
      BEGIN OF ty_makt,
        matnr TYPE makt-matnr,
        maktx TYPE makt-maktx,
      END OF ty_makt.
    TYPES:
      tt_makt TYPE HASHED TABLE OF ty_makt WITH UNIQUE KEY matnr.
    TYPES:
      tt_lvorm_range TYPE RANGE OF mara-lvorm.

    "메시지 클래스와 번호 (기존 공용 메시지 클래스 ZMM, 338~343 신규 배정)
    CONSTANTS c_msgid          TYPE symsgid VALUE 'ZMM'.
    CONSTANTS c_msg_no_input   TYPE symsgno VALUE '338'.
    CONSTANTS c_msg_invalid    TYPE symsgno VALUE '339'.
    CONSTANTS c_msg_no_auth    TYPE symsgno VALUE '340'.
    CONSTANTS c_msg_no_data    TYPE symsgno VALUE '341'.
    CONSTANTS c_msg_success    TYPE symsgno VALUE '342'.
    CONSTANTS c_msg_trunc      TYPE symsgno VALUE '343'.
    "메시지 유형
    CONSTANTS c_msgty_error    TYPE bapi_mtype VALUE 'E'.
    CONSTANTS c_msgty_warning  TYPE bapi_mtype VALUE 'W'.
    CONSTANTS c_msgty_success  TYPE bapi_mtype VALUE 'S'.
    "권한 점검 액티비티: 03 조회
    CONSTANTS c_actvt_display  TYPE activ_auth VALUE '03'.

    METHODS constructor
      IMPORTING
        !iv_mtart        TYPE mtart
        !iv_spras        TYPE spras OPTIONAL
        !iv_with_deleted TYPE xfeld OPTIONAL
        !iv_max_rows     TYPE i OPTIONAL.

    METHODS execute
      EXPORTING
        !et_list   TYPE tt_list
        !ev_count  TYPE i
        !es_return TYPE bapiret2.

    CLASS-METHODS normalize_mtart
      IMPORTING
        !iv_mtart       TYPE mtart
      RETURNING
        VALUE(rv_mtart) TYPE mtart.

    CLASS-METHODS normalize_spras
      IMPORTING
        !iv_spras       TYPE spras
      RETURNING
        VALUE(rv_spras) TYPE spras.

    CLASS-METHODS normalize_max_rows
      IMPORTING
        !iv_max_rows       TYPE i
      RETURNING
        VALUE(rv_max_rows) TYPE i.

    CLASS-METHODS build_lvorm_range
      IMPORTING
        !iv_with_deleted TYPE xfeld
      RETURNING
        VALUE(rt_lvorm)  TYPE tt_lvorm_range.

    CLASS-METHODS get_up_to_rows
      IMPORTING
        !iv_max_rows   TYPE i
      RETURNING
        VALUE(rv_rows) TYPE i.

    CLASS-METHODS build_list
      IMPORTING
        !it_mara      TYPE tt_mara
        !it_makt      TYPE tt_makt
        !iv_max_rows  TYPE i
      EXPORTING
        !et_list      TYPE tt_list
        !ev_truncated TYPE abap_bool.

    CLASS-METHODS decide_return
      IMPORTING
        !iv_mtart        TYPE mtart
        !iv_count        TYPE i
        !iv_truncated    TYPE abap_bool
        !iv_max_rows     TYPE i
      RETURNING
        VALUE(rs_return) TYPE bapiret2.

    CLASS-METHODS make_return
      IMPORTING
        !iv_type         TYPE bapi_mtype
        !iv_number       TYPE symsgno
        !iv_v1           TYPE clike OPTIONAL
        !iv_v2           TYPE clike OPTIONAL
      RETURNING
        VALUE(rs_return) TYPE bapiret2.

  PROTECTED SECTION.

  PRIVATE SECTION.

    "Range 행 구성값 (SIGN / OPTION)
    CONSTANTS c_sign_exclude TYPE c LENGTH 1 VALUE 'E'.
    CONSTANTS c_option_eq    TYPE c LENGTH 2 VALUE 'EQ'.

    DATA g_mtart        TYPE mtart.
    DATA g_spras        TYPE spras.
    DATA g_with_deleted TYPE xfeld.
    DATA g_max_rows     TYPE i.

    METHODS check_mtart
      EXPORTING
        !ev_found TYPE abap_bool
        !ev_begru TYPE t134-begru.

    METHODS check_authority
      IMPORTING
        !iv_begru    TYPE t134-begru
      RETURNING
        VALUE(rv_ok) TYPE abap_bool.

    METHODS read_mara
      RETURNING
        VALUE(rt_mara) TYPE tt_mara.

    METHODS read_makt
      IMPORTING
        !it_mara       TYPE tt_mara
      RETURNING
        VALUE(rt_makt) TYPE tt_makt.

ENDCLASS.



CLASS zcl_mm_mtart_matlist IMPLEMENTATION.


  METHOD constructor.
*----------------------------------------------------------------------*
* 2단계 - 입력 정규화. FM 밖에서 직접 생성해도 결과가 같도록 여기서 처리
*----------------------------------------------------------------------*
    g_mtart    = normalize_mtart( iv_mtart ).
    g_spras    = normalize_spras( iv_spras ).
    g_max_rows = normalize_max_rows( iv_max_rows ).

    IF iv_with_deleted = abap_true.
      g_with_deleted = abap_true.
    ELSE.
      CLEAR g_with_deleted.
    ENDIF.
  ENDMETHOD.


  METHOD execute.
*----------------------------------------------------------------------*
* 3~9단계 - 검증, 조회, 조립, 반환
*----------------------------------------------------------------------*
    DATA l_found     TYPE abap_bool.
    DATA l_begru     TYPE t134-begru.
    DATA l_truncated TYPE abap_bool.
    DATA lt_mara     TYPE tt_mara.
    DATA lt_makt     TYPE tt_makt.

    CLEAR: et_list, ev_count, es_return.

    "3단계 - 입력 누락: DB 접근 전에 종료
    IF g_mtart IS INITIAL.
      es_return = make_return( iv_type   = c_msgty_error
                               iv_number = c_msg_no_input ).
      RETURN.
    ENDIF.

    "4단계 - T134 존재 검사
    check_mtart( IMPORTING ev_found = l_found
                           ev_begru = l_begru ).
    IF l_found = abap_false.
      es_return = make_return( iv_type   = c_msgty_error
                               iv_number = c_msg_invalid
                               iv_v1     = g_mtart ).
      RETURN.
    ENDIF.

    "5단계 - 자재유형 권한그룹이 있을 때만 권한 점검
    IF l_begru IS NOT INITIAL.
      IF check_authority( l_begru ) = abap_false.
        es_return = make_return( iv_type   = c_msgty_error
                                 iv_number = c_msg_no_auth
                                 iv_v1     = g_mtart ).
        RETURN.
      ENDIF.
    ENDIF.

    "6단계 - MARA 조회
    lt_mara = read_mara( ).
    IF lt_mara IS INITIAL.
      es_return = make_return( iv_type   = c_msgty_warning
                               iv_number = c_msg_no_data
                               iv_v1     = g_mtart ).
      RETURN.
    ENDIF.

    "7단계 - MAKT 조회
    lt_makt = read_makt( lt_mara ).

    "8단계 - 결과 조립
    build_list( EXPORTING it_mara      = lt_mara
                          it_makt      = lt_makt
                          iv_max_rows  = g_max_rows
                IMPORTING et_list      = et_list
                          ev_truncated = l_truncated ).

    "9단계 - 반환
    ev_count  = lines( et_list ).
    es_return = decide_return( iv_mtart     = g_mtart
                               iv_count     = ev_count
                               iv_truncated = l_truncated
                               iv_max_rows  = g_max_rows ).
  ENDMETHOD.


  METHOD normalize_mtart.
*----------------------------------------------------------------------*
* 앞 공백 제거 후 대문자 (예: ' roh' -> 'ROH')
*----------------------------------------------------------------------*
    rv_mtart = iv_mtart.
    SHIFT rv_mtart LEFT DELETING LEADING space.
    TRANSLATE rv_mtart TO UPPER CASE.
  ENDMETHOD.


  METHOD normalize_spras.
*----------------------------------------------------------------------*
* 공란이면 로그온 언어
*----------------------------------------------------------------------*
    IF iv_spras IS INITIAL.
      rv_spras = sy-langu.
    ELSE.
      rv_spras = iv_spras.
    ENDIF.
  ENDMETHOD.


  METHOD normalize_max_rows.
*----------------------------------------------------------------------*
* 음수는 0(제한 없음)
*----------------------------------------------------------------------*
    IF iv_max_rows < 0.
      rv_max_rows = 0.
    ELSE.
      rv_max_rows = iv_max_rows.
    ENDIF.
  ENDMETHOD.


  METHOD build_lvorm_range.
*----------------------------------------------------------------------*
* 공란 -> 삭제 표시('X') 제외 1행 / 'X' -> 빈 range(조건 없음)
*----------------------------------------------------------------------*
    DATA ls_lvorm LIKE LINE OF rt_lvorm.

    CLEAR rt_lvorm.
    IF iv_with_deleted = abap_true.
      RETURN.
    ENDIF.

    ls_lvorm-sign   = c_sign_exclude.
    ls_lvorm-option = c_option_eq.
    ls_lvorm-low    = abap_true.
    APPEND ls_lvorm TO rt_lvorm.
  ENDMETHOD.


  METHOD get_up_to_rows.
*----------------------------------------------------------------------*
* 0 이하 -> MAX_INT4(제한 없음)
* 1 이상 -> 잘림 판정용으로 1건 더 (단 MAX_INT4를 넘지 않음)
*----------------------------------------------------------------------*
    IF iv_max_rows <= 0 OR iv_max_rows >= cl_abap_math=>max_int4.
      rv_rows = cl_abap_math=>max_int4.
    ELSE.
      rv_rows = iv_max_rows + 1.
    ENDIF.
  ENDMETHOD.


  METHOD build_list.
*----------------------------------------------------------------------*
* MARA 행 기준으로 MAKT 내역 결합(없으면 공란, 행 유지)
* -> 자재코드 오름차순 -> 최대 건수 초과분 삭제
*----------------------------------------------------------------------*
    DATA ls_mara LIKE LINE OF it_mara.
    DATA ls_makt LIKE LINE OF it_makt.
    DATA ls_list TYPE ty_list.
    DATA l_from  TYPE i.

    CLEAR: et_list, ev_truncated.

    LOOP AT it_mara INTO ls_mara.
      CLEAR ls_list.
      ls_list-matnr = ls_mara-matnr.
      ls_list-meins = ls_mara-meins.

      READ TABLE it_makt INTO ls_makt
           WITH TABLE KEY matnr = ls_mara-matnr.
      IF sy-subrc = 0.
        ls_list-maktx = ls_makt-maktx.
      ENDIF.

      APPEND ls_list TO et_list.
    ENDLOOP.

    SORT et_list BY matnr.

    IF iv_max_rows > 0 AND lines( et_list ) > iv_max_rows.
      l_from = iv_max_rows + 1.
      DELETE et_list FROM l_from.
      ev_truncated = abap_true.
    ENDIF.
  ENDMETHOD.


  METHOD decide_return.
*----------------------------------------------------------------------*
* 잘림 -> W ZMM-343(&1 최대건수)
* 그 외 -> S ZMM-342(&1 자재유형, &2 건수)
*----------------------------------------------------------------------*
    DATA l_count TYPE symsgv.
    DATA l_max   TYPE symsgv.

    IF iv_truncated = abap_true.
      l_max = |{ iv_max_rows }|.
      rs_return = make_return( iv_type   = c_msgty_warning
                               iv_number = c_msg_trunc
                               iv_v1     = l_max ).
    ELSE.
      l_count = |{ iv_count }|.
      rs_return = make_return( iv_type   = c_msgty_success
                               iv_number = c_msg_success
                               iv_v1     = iv_mtart
                               iv_v2     = l_count ).
    ENDIF.
  ENDMETHOD.


  METHOD make_return.
*----------------------------------------------------------------------*
* MESSAGE ... INTO 로 텍스트 생성 후 BAPIRET2 단건 조립
* (화면 출력·처리 중단 없음)
*----------------------------------------------------------------------*
    DATA l_msg TYPE bapiret2-message.

    CLEAR rs_return.

    MESSAGE ID c_msgid TYPE iv_type NUMBER iv_number
            WITH iv_v1 iv_v2
            INTO l_msg.

    rs_return-type       = sy-msgty.
    rs_return-id         = sy-msgid.
    rs_return-number     = sy-msgno.
    rs_return-message    = l_msg.
    rs_return-message_v1 = sy-msgv1.
    rs_return-message_v2 = sy-msgv2.
    rs_return-message_v3 = sy-msgv3.
    rs_return-message_v4 = sy-msgv4.
  ENDMETHOD.


  METHOD check_mtart.
*----------------------------------------------------------------------*
* 4단계 - T134 기본키 단건 읽기 (존재 여부 + 권한그룹)
*----------------------------------------------------------------------*
    CLEAR: ev_found, ev_begru.

    SELECT SINGLE begru
      FROM t134
      INTO @ev_begru
      WHERE mtart = @g_mtart.

    IF sy-subrc = 0.
      ev_found = abap_true.
    ELSE.
      ev_found = abap_false.
    ENDIF.
  ENDMETHOD.


  METHOD check_authority.
*----------------------------------------------------------------------*
* 5단계 - 자재유형 권한 (표준 MM03 기준: M_MATE_MAR, ACTVT 03)
*----------------------------------------------------------------------*
    AUTHORITY-CHECK OBJECT 'M_MATE_MAR'
      ID 'ACTVT' FIELD c_actvt_display
      ID 'BEGRU' FIELD iv_begru.

    IF sy-subrc = 0.
      rv_ok = abap_true.
    ELSE.
      rv_ok = abap_false.
    ENDIF.
  ENDMETHOD.


  METHOD read_mara.
*----------------------------------------------------------------------*
* 6단계 - MARA 조회. 절 순서 INTO -> UP TO -> WHERE -> ORDER BY (7.40 SP05)
*----------------------------------------------------------------------*
    DATA r_lvorm TYPE tt_lvorm_range.
    DATA l_rows  TYPE i.

    CLEAR rt_mara.

    r_lvorm = build_lvorm_range( g_with_deleted ).
    l_rows  = get_up_to_rows( g_max_rows ).

    SELECT matnr, meins
      FROM mara
      INTO TABLE @rt_mara
      UP TO @l_rows ROWS
      WHERE mtart = @g_mtart
        AND lvorm IN @r_lvorm
      ORDER BY matnr.
  ENDMETHOD.


  METHOD read_makt.
*----------------------------------------------------------------------*
* 7단계 - MAKT 조회 (FOR ALL ENTRIES, 기본키 MATNR + SPRAS)
* SPRAS를 한 값으로 고정하므로 HASHED UNIQUE KEY MATNR 중복 없음
*----------------------------------------------------------------------*
    CLEAR rt_makt.

    "FAE 드라이버가 비면 전체 조회가 되므로 반드시 확인
    IF it_mara IS INITIAL.
      RETURN.
    ENDIF.

    SELECT matnr, maktx
      FROM makt
      INTO TABLE @rt_makt
      FOR ALL ENTRIES IN @it_mara
      WHERE matnr = @it_mara-matnr
        AND spras = @g_spras.
  ENDMETHOD.

ENDCLASS.
