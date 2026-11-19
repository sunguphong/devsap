*&---------------------------------------------------------------------*
*&  Include           ZRMM0057SEL
*&---------------------------------------------------------------------*
*& 선택화면 (설계 4장). 기본값은 INITIALIZATION 에서 클래스 상수로 채움
*&---------------------------------------------------------------------*

* B1 조회 조건
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-b01.
SELECT-OPTIONS: so_werks FOR mseg-werks OBLIGATORY,
                so_budat FOR mkpf-budat OBLIGATORY NO-EXTENSION,
                so_matnr FOR mseg-matnr,
                so_lgort FOR mseg-lgort,
                so_mtart FOR mara-mtart.
SELECTION-SCREEN END OF BLOCK b1.

* B2 출력 옵션
SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-b02.
PARAMETERS: pa_vsloc AS CHECKBOX,
            pa_nozer AS CHECKBOX,
            pa_vari  TYPE slis_vari.
SELECTION-SCREEN END OF BLOCK b2.

* B3 집계 규칙 (변경 시 팀장 확인)
SELECTION-SCREEN BEGIN OF BLOCK b3 WITH FRAME TITLE TEXT-b03.
SELECT-OPTIONS: so_xbust FOR mseg-bustm NO INTERVALS,
                so_bwit  FOR mseg-bwart,
                so_bwir  FOR mseg-bwart,
                so_bwpt  FOR mseg-bwart,
                so_bwpr  FOR mseg-bwart.
SELECTION-SCREEN END OF BLOCK b3.
