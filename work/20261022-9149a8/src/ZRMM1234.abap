*&---------------------------------------------------------------------*
*& Report ZRMM1234 - 전기일자 기준 자재수불부 조회(일별)
*&---------------------------------------------------------------------*
*& 전기일자 기준 자재수불부 조회(일별)_저장위치레벨포함
*& - 요청 ID : 20261022-9149a8 / 설계 02_design.md v1.1
*& - T-code  : ZRMM1234 / 패키지 ZMMD / 메시지 클래스 ZMMM3
*& - 원천    : 집계 테이블 ZTMM1234(A, 자재), ZTMM1236(B, 배치), ZTMM1237(제어)
*&             MKPF/MSEG는 읽지 않음 (매일 07:00 ZRMM1235 집계 결과 조회)
*& - 화면    : 메인 SALV(플랜트+저장위치 집계, [상세조회]/더블클릭)
*&             상세 SALV 팝업(선택 위치의 자재·배치, DB 재조회 없음)
*&---------------------------------------------------------------------*
REPORT zrmm1234 MESSAGE-ID zmmm3.

INCLUDE zrmm1234_top.      " 전역 타입·상수·데이터
INCLUDE zrmm1234_sel.      " 선택화면
INCLUDE zrmm1234_c01.      " 로컬 클래스 LCL_DATA / LCL_VIEW
INCLUDE zrmm1234_f01.      " 선택화면 보조 FORM

*----------------------------------------------------------------------*
INITIALIZATION.
*----------------------------------------------------------------------*
  " Q0 기본 전기일 = 최종 집계일 (변형 값이 있으면 변형 우선)
  PERFORM set_default_dates.

*----------------------------------------------------------------------*
AT SELECTION-SCREEN OUTPUT.
*----------------------------------------------------------------------*
  " 블록 B01 안내 줄(T01, T02)
  PERFORM set_info_text.

*----------------------------------------------------------------------*
AT SELECTION-SCREEN ON VALUE-REQUEST FOR pa_vari.
*----------------------------------------------------------------------*
  PERFORM f4_layout CHANGING pa_vari.

*----------------------------------------------------------------------*
AT SELECTION-SCREEN.
*----------------------------------------------------------------------*
  " Q1 일자 검증 (E 001, 002)
  PERFORM check_period.

*----------------------------------------------------------------------*
START-OF-SELECTION.
*----------------------------------------------------------------------*
  CREATE OBJECT g_data.

  " Q2 플랜트 확정(존재·권한·집계 범위)
  IF g_data->check_plants( ) = abap_false.
    LEAVE LIST-PROCESSING.
  ENDIF.

  " Q3~Q4 A·B 조회, 없으면 선택화면으로
  IF g_data->read_data( ) = abap_false.
    MESSAGE s010 DISPLAY LIKE 'W'.
    LEAVE LIST-PROCESSING.
  ENDIF.

  " Q5 키별 기간 계산·상세 캐시
  g_data->build_result( ).

  " Q6 플랜트+저장위치 집계 (0건이면 메서드가 S 010 표시)
  IF g_data->build_main( ) = abap_false.
    LEAVE LIST-PROCESSING.
  ENDIF.

  " Q7~Q10 메인 ALV와 상세 팝업
  CREATE OBJECT g_view
    EXPORTING
      io_data = g_data.
  g_view->display_main( ).
