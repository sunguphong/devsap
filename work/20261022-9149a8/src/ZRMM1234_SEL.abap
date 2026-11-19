*&---------------------------------------------------------------------*
*& Include ZRMM1234_SEL - 선택화면 (설계 5.1)
*&---------------------------------------------------------------------*

" B01 전기일 기간 + 안내 줄(T01, T02)
SELECTION-SCREEN BEGIN OF BLOCK b01 WITH FRAME TITLE TEXT-b01.
PARAMETERS: pa_budfr TYPE budat OBLIGATORY,
            pa_budto TYPE budat OBLIGATORY.
SELECTION-SCREEN COMMENT /1(75) g_info1.
SELECTION-SCREEN COMMENT /1(75) g_info2.
SELECTION-SCREEN END OF BLOCK b01.

" B02 조직
SELECTION-SCREEN BEGIN OF BLOCK b02 WITH FRAME TITLE TEXT-b02.
SELECT-OPTIONS: so_werks FOR g_werks OBLIGATORY MEMORY ID wrk,
                so_lgort FOR g_lgort.
SELECTION-SCREEN END OF BLOCK b02.

" B03 자재
SELECTION-SCREEN BEGIN OF BLOCK b03 WITH FRAME TITLE TEXT-b03.
SELECT-OPTIONS: so_matnr FOR g_matnr MATCHCODE OBJECT mat1,
                so_mtart FOR g_mtart,
                so_matkl FOR g_matkl,
                so_charg FOR g_charg.
SELECTION-SCREEN END OF BLOCK b03.

" B04 옵션
SELECTION-SCREEN BEGIN OF BLOCK b04 WITH FRAME TITLE TEXT-b04.
PARAMETERS: pa_nozer AS CHECKBOX DEFAULT 'X',
            pa_vari  TYPE slis_vari.
SELECTION-SCREEN END OF BLOCK b04.
