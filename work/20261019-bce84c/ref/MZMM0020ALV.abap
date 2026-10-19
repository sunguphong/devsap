*&---------------------------------------------------------------------*
*&  Include           MZMM0020ALV
*&---------------------------------------------------------------------*
************************************************************************
*** TYPE-POOLS 선언
************************************************************************
TABLES : SSCRFIELDS.
INCLUDE <ICON>.

CLASS LCL_EVENT_RECEIVER DEFINITION DEFERRED.
CLASS CL_GUI_CFW DEFINITION LOAD.

************************************************************************
*** ALV INTERNAL TABLE
************************************************************************
DATA: GT_FIELDCAT         TYPE LVC_T_FCAT,       "ALV Field catalog
      GT_SORT             TYPE LVC_T_SORT,       "ALV Sort field
      GT_TOOLBAR          TYPE STB_BUTTON,       "ALV TOOLBAR
      GT_EXCLUDE          TYPE UI_FUNCTIONS.
************************************************************************
*** ALV STRUCTURE
************************************************************************
DATA : GS_FIELDCAT         TYPE LVC_S_FCAT,
       GS_SORT             TYPE LVC_S_SORT,
       GS_LAYOUT           TYPE LVC_S_LAYO,       "ALV Layout
       GS_VARIANT          TYPE DISVARIANT,       "Variant
       GS_EXCLUDE          TYPE UI_FUNC.
************************************************************************
*** ALV VARIANCE
************************************************************************
DATA: G_REPID             LIKE SY-REPID,
      EVENT_RECEIVER      TYPE REF TO LCL_EVENT_RECEIVER.

* PR DATA
DATA: GRID                    TYPE REF TO CL_GUI_ALV_GRID,
      G_CONT_NAME             TYPE SCRFNAME  VALUE 'CTRL_CONTAINER',
      CUSTOM_CONTAINER        TYPE REF TO CL_GUI_CUSTOM_CONTAINER.

************************************************************************
*** CLASS lcl_event_receiver DEFINITION
************************************************************************
CLASS LCL_EVENT_RECEIVER DEFINITION.

  PUBLIC SECTION.

*    DATA: INSERTED_ROWS TYPE ZTMM9999,
*          DELETED_ROWS  TYPE STANDARD TABLE OF ZTMM9999.

*    TYPES:ZTSCS_WSPLAN  TYPE STANDARD TABLE OF ZTMM9999.

    METHODS:

      HANDLE_TOOLBAR
        FOR EVENT TOOLBAR OF CL_GUI_ALV_GRID
        IMPORTING E_OBJECT E_INTERACTIVE,

      HANDLE_USER_COMMAND
          FOR EVENT USER_COMMAND OF CL_GUI_ALV_GRID
          IMPORTING E_UCOMM,

      HANDLE_DATA_CHANGED
         FOR EVENT DATA_CHANGED OF CL_GUI_ALV_GRID
             IMPORTING ER_DATA_CHANGED,

      HANDLE_DATA_CHANGED_FINISHED
                 FOR EVENT DATA_CHANGED_FINISHED OF CL_GUI_ALV_GRID
                 IMPORTING E_MODIFIED
                           ET_GOOD_CELLS,

      HANDLE_HOTSPOT_CLICK
          FOR EVENT HOTSPOT_CLICK OF CL_GUI_ALV_GRID
              IMPORTING E_ROW_ID E_COLUMN_ID ES_ROW_NO,

      HANDLE_DOUBLE_CLICK
          FOR EVENT DOUBLE_CLICK OF CL_GUI_ALV_GRID
              IMPORTING E_ROW E_COLUMN.


  PRIVATE SECTION.
    METHODS:
      MODIFY_ZCUSTM
        IMPORTING PS_ZPOS         TYPE LVC_S_MODI
                  PR_DATA_CHANGED TYPE REF TO
                                  CL_ALV_CHANGED_DATA_PROTOCOL,
      CHECK_ZCUSTM
        IMPORTING PS_ZPOS         TYPE LVC_S_MODI
                  PR_DATA_CHANGED TYPE REF TO
                                  CL_ALV_CHANGED_DATA_PROTOCOL.

ENDCLASS.                    "lcl_event_receiver DEFINITION

*---------------------------------------------------------------------*
*       CLASS lcl_alv_grid DEFINITION
*---------------------------------------------------------------------*
CLASS LCL_ALV_GRID DEFINITION INHERITING FROM CL_GUI_ALV_GRID.

  PUBLIC SECTION.
    METHODS: SET_CURSOR IMPORTING ROW  TYPE I
                                  COL  TYPE I.

ENDCLASS.                    "lcl_alv_grid DEFINITION
*---------------------------------------------------------------------*
*       CLASS LCL_ALV_GRID IMPLEMENTATION
*---------------------------------------------------------------------*
CLASS LCL_ALV_GRID IMPLEMENTATION.

  METHOD SET_CURSOR.

    CALL METHOD ME->SET_CURRENT_CELL_BASE
      EXPORTING
        ROW = ROW
        COL = COL.

  ENDMETHOD.                    "SET_CURSOR

ENDCLASS.                    "lcl_alv_grid IMPLEMENTATION
**********************************************************************
* LOCAL CLASSES: Implementation
**********************************************************************
CLASS LCL_EVENT_RECEIVER IMPLEMENTATION.
*----------------------------------------------------------------------*
* ALV HOTSPOT
*----------------------------------------------------------------------*
  METHOD HANDLE_HOTSPOT_CLICK.
*   read selected row from internal table gt_with
    CALL FUNCTION 'POPUP_TO_INFORM'
      EXPORTING
        TITEL = G_REPID
        TXT2  = SY-SUBRC
        TXT1  = E_ROW_ID-INDEX.
  ENDMETHOD.                           "handle_hotspot_click

  METHOD HANDLE_DOUBLE_CLICK.
*    PERFORM REMAKE_GT_SAVE.
*    READ TABLE GT_PR INDEX E_ROW-INDEX INTO GT_YEAR6_TEMP.
*    READ TABLE GT_YEAR1 INDEX E_ROW-INDEX INTO GT_YEAR1_TEMP.
**    PERFORM REMAKE_GT_SAVE.
*    PERFORM GET_DETAIL_PROC.
*    PERFORM MAKE_TITLE.
*    CALL METHOD GRID->REFRESH_TABLE_DISPLAY.

  ENDMETHOD.                    "handle_double_click
*---------------------------------------------------------------------*
* DEFINE handle_toolbar
*---------------------------------------------------------------------*
  METHOD HANDLE_TOOLBAR.
*   저장 BUTTON
    CLEAR GT_TOOLBAR.
    GT_TOOLBAR-BUTN_TYPE = 3 .              "Separator
    APPEND GT_TOOLBAR TO E_OBJECT->MT_TOOLBAR.

*    CLEAR GT_TOOLBAR.
*    GT_TOOLBAR-BUTN_TYPE = 0.               "Button Type
*    GT_TOOLBAR-FUNCTION  = 'MINUS'(UC3).
*    GT_TOOLBAR-ICON      = ICON_SYSTEM_CHANGE.
*    GT_TOOLBAR-QUICKINFO = '원화환산'(UT3).
*    GT_TOOLBAR-TEXT      = '원화환산'(112).
*    GT_TOOLBAR-DISABLED  = ' ' .
*    APPEND GT_TOOLBAR TO E_OBJECT->MT_TOOLBAR.
  ENDMETHOD.                    "HANDLE_TOOLBAR

  METHOD HANDLE_USER_COMMAND.
    DATA: LT_ROWS TYPE LVC_T_ROW,
          LS_SELECTED_LINE TYPE LVC_S_ROW,
          L_LINE LIKE SY-INDEX.

    OK_CODE = E_UCOMM.
    CASE OK_CODE.
      WHEN 'KRW'.
*        PERFORM CHANGE_TO_KRW.
    ENDCASE.
  ENDMETHOD.                    "HANDLE_TOOLBAR

*----------------------------------------------------------------------*
* ALV의 DATA CHANGE
*----------------------------------------------------------------------*
  METHOD HANDLE_DATA_CHANGED.
    DATA: LS_GOOD TYPE LVC_S_MODI.

    LOOP AT ER_DATA_CHANGED->MT_GOOD_CELLS INTO LS_GOOD.

      CASE LS_GOOD-FIELDNAME.
        WHEN 'MATNR' OR 'ZFTYP' OR 'ZOTYP'.
          CALL METHOD MODIFY_ZCUSTM
            EXPORTING
              PS_ZPOS         = LS_GOOD
              PR_DATA_CHANGED = ER_DATA_CHANGED.

        WHEN 'ZCUSTM' OR 'ZFRATM' OR 'ZOPAYM' OR 'WAERS'.
          CALL METHOD CHECK_ZCUSTM
            EXPORTING
              PS_ZPOS         = LS_GOOD
              PR_DATA_CHANGED = ER_DATA_CHANGED.
      ENDCASE.

    ENDLOOP.
  ENDMETHOD.                    "handle_data_changed
*
  METHOD MODIFY_ZCUSTM.
    DATA: L_TYPE. " TYPE ZTMMTEST02-ZCTYP.
    DATA IS_STABLE TYPE LVC_S_STBL .
    CALL METHOD PR_DATA_CHANGED->GET_CELL_VALUE
      EXPORTING
        I_ROW_ID    = PS_ZPOS-ROW_ID
        I_FIELDNAME = PS_ZPOS-FIELDNAME
      IMPORTING
        E_VALUE     = L_TYPE.
  ENDMETHOD.      "modify_zcart

  METHOD CHECK_ZCUSTM.
*    (원문 전체 주석 처리 - 통화/ZCUSTM 검사 코드, 생략)
  ENDMETHOD.                    "modify_zcart

*----------------------------------------------------------------------*
* ALV의 DATA CHANGE FINISHED
*----------------------------------------------------------------------*
  METHOD HANDLE_DATA_CHANGED_FINISHED.

    DATA : LS_MOD_CELLS     TYPE LVC_S_MODI.
*
    DATA LS_PR LIKE GT_PR.

    CHECK E_MODIFIED = 'X'.

    LOOP AT ET_GOOD_CELLS INTO LS_MOD_CELLS.
      READ TABLE GT_PR INDEX LS_MOD_CELLS-ROW_ID INTO LS_PR.
      CASE LS_MOD_CELLS-FIELDNAME.     "셀의 필드명
        WHEN 'WAERS'.

          SELECT SINGLE MANDT INTO SY-MANDT
          FROM TCURC
          WHERE WAERS = LS_PR-WAERS.

          IF SY-SUBRC <> 0.
            MESSAGE S000 WITH '유효하지 않은 통화단위입니다.'.
          ENDIF.
        WHEN 'DANGA' .
          IF LS_PR-DANGA <= 0.
            MESSAGE S000 WITH '단가는 0보다 커야 합니다.'.
          ENDIF.
        WHEN 'KPEIN'.
          IF LS_PR-KPEIN <= 0.
            MESSAGE S000 WITH '단위는 0보다 커야 합니다.'.
          ENDIF.
        WHEN 'WERKS' OR 'MATNR' OR 'ZLEVEL'.              "고철등급명 반영
           IF LS_PR-WERKS IS NOT INITIAL AND LS_PR-MATNR IS NOT INITIAL AND LS_PR-ZLEVEL IS NOT INITIAL.
            SELECT SINGLE BTEXT INTO LS_PR-BTEXT
            FROM ZTMM0014
            WHERE WERKS = LS_PR-WERKS
              AND MATNR = LS_PR-MATNR
              AND ZLEVEL = LS_PR-ZLEVEL.
            IF SY-SUBRC = 0.
              MODIFY GT_PR FROM LS_PR INDEX LS_MOD_CELLS-ROW_ID.

              DATA IS_STABLE TYPE LVC_S_STBL .
              IS_STABLE-ROW = 1.
              IS_STABLE-COL = 1.

              CALL METHOD GRID->REFRESH_TABLE_DISPLAY
                EXPORTING
                  IS_STABLE = IS_STABLE
                EXCEPTIONS
                  FINISHED  = 1
                  OTHERS    = 2.

            ENDIF.
          ENDIF.
        WHEN OTHERS.
*           do nothing
      ENDCASE.

    ENDLOOP.

  ENDMETHOD.                    "HANDLE_DATA_CHANGED_FINISHED
ENDCLASS.                    "lcl_event_receiver IMPLEMENTATION
