FUNCTION z_mm_get_material_list.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(IV_MTART) TYPE  MTART
*"     VALUE(IV_SPRAS) TYPE  SPRAS DEFAULT SY-LANGU
*"     VALUE(IV_WITH_DELETED) TYPE  XFELD DEFAULT SPACE
*"     VALUE(IV_MAX_ROWS) TYPE  INT4 DEFAULT 0
*"  EXPORTING
*"     VALUE(ET_LIST) TYPE  ZCL_MM_MTART_MATLIST=>TT_LIST
*"     VALUE(EV_COUNT) TYPE  INT4
*"     VALUE(ES_RETURN) TYPE  BAPIRET2
*"----------------------------------------------------------------------
*----------------------------------------------------------------------*
* 함수 모듈 : Z_MM_GET_MATERIAL_LIST  (함수 그룹 ZFGMM71, 패키지 ZMMD)
* 내역      : [MM] 자재유형별 자재코드·내역·기본단위 조회
* 처리 유형 : 일반 함수 모듈 (Normal). ET_LIST 가 클래스 타입이라
*             Remote-Enabled 불가 (설계 2.2)
* 요청 ID   : 20261119-f26e72
* 비고      : 로직은 ZCL_MM_MTART_MATLIST 에 있음. 이 FM은 호출만 함.
*             호출측 수신 변수 선언:
*               DATA lt_list TYPE zcl_mm_mtart_matlist=>tt_list.
*             IV_MTART 는 필수. 공란 값이면 E ZMMM3-001.
*             IV_WITH_DELETED 공란 = 삭제 표시 자재 제외, 'X' = 포함.
*             IV_MAX_ROWS 0 이하 = 제한 없음.
*             ES_RETURN: S 005 정상 / W 004 데이터 없음 / W 006 잘림
*                        E 001 입력 누락 / E 002 자재유형 없음 / E 003 권한 없음
*----------------------------------------------------------------------*
  DATA lo_list TYPE REF TO zcl_mm_mtart_matlist.

  CREATE OBJECT lo_list
    EXPORTING
      iv_mtart        = iv_mtart
      iv_spras        = iv_spras
      iv_with_deleted = iv_with_deleted
      iv_max_rows     = iv_max_rows.

  lo_list->execute( IMPORTING et_list   = et_list
                              ev_count  = ev_count
                              es_return = es_return ).

ENDFUNCTION.
