*&---------------------------------------------------------------------*
*&  Include           MZMM0020I01
*&---------------------------------------------------------------------*
*&---------------------------------------------------------------------*
*&      Module  EXIT  INPUT
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
MODULE EXIT INPUT.
  CASE OK_CODE.
    WHEN 'EXIT'.
      LEAVE PROGRAM.
    WHEN 'CANC'.
      LEAVE TO SCREEN 0.
  ENDCASE.
ENDMODULE.                 " EXIT  INPUT

*&---------------------------------------------------------------------*
*&      Module  USER_COMMAND_XXXX  INPUT
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
MODULE USER_COMMAND_XXXX INPUT.
  SAVE_OK = OK_CODE.
  CLEAR OK_CODE.
ENDMODULE.                 " USER_COMMAND_XXXX  INPUT

*&---------------------------------------------------------------------*
*&      Module  USER_COMMAND_0100  INPUT
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
MODULE USER_COMMAND_0100 INPUT.
  CASE SAVE_OK.
    WHEN 'BACK'.
      LEAVE TO SCREEN 0.
    WHEN 'TOGG'.
      PERFORM TOGGLE_DISPLAY_CHANGE.
    WHEN 'CREA'.
      PERFORM CREATE_DATA.
    WHEN 'COPY'.
      PERFORM COPY_DATA.
    WHEN 'DEL'.
      PERFORM DEL_ROWS.
    WHEN 'SAVE'.
      PERFORM SAVE_DATA.
    WHEN 'GRAD'.
      CALL TRANSACTION 'ZTMM0014'.
   ENDCASE.
ENDMODULE.                 " USER_COMMAND_0100  INPUT
