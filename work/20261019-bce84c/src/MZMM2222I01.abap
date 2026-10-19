*&---------------------------------------------------------------------*
*&  Include           MZMM0020I01
*&---------------------------------------------------------------------*
*& U4 2026.10.19 ZEMM2222 공문발송(ZMAIL) 분기, 화면 0200 PAI 추가
*&               - 요청 20261019-bce84c
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
*-- U4 START : 공문발송 (시트 설계 B21, C58)
    WHEN c_fc_mail.
      PERFORM mail_process.
*-- U4 END
   ENDCASE.
ENDMODULE.                 " USER_COMMAND_0100  INPUT

*-- U4 START
*&---------------------------------------------------------------------*
*&      Module  EXIT_0200  INPUT
*&---------------------------------------------------------------------*
*       팝업 0200 [취소] (FCODE CANC, 기능 유형 E) - 시트 외 X-1
*----------------------------------------------------------------------*
MODULE exit_0200 INPUT.
  IF g_ok_0200 = c_fc_canc.
    CLEAR g_ok_0200.
    g_answer = c_answer_canc.
    LEAVE TO SCREEN 0.
  ENDIF.
ENDMODULE.                 " EXIT_0200  INPUT

*&---------------------------------------------------------------------*
*&      Module  USER_COMMAND_0200  INPUT
*&---------------------------------------------------------------------*
*       팝업 0200 [발송] (FCODE SEND) - 시트 설계 C77
*       주소 확인·메시지·LEAVE 는 FORM CHECK_MAIL_ADDRESS (모듈 안 DATA
*       선언은 전역이 되므로 지역 변수는 FORM 에 둠)
*----------------------------------------------------------------------*
MODULE user_command_0200 INPUT.
  CASE g_ok_0200.
    WHEN c_fc_send.
      CLEAR g_ok_0200.
      PERFORM check_mail_address.
    WHEN OTHERS.
      CLEAR g_ok_0200.
  ENDCASE.
ENDMODULE.                 " USER_COMMAND_0200  INPUT
*-- U4 END
