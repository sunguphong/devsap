*&---------------------------------------------------------------------*
*&  Include           MZMM0020F02
*&---------------------------------------------------------------------*
FORM make_alv_disp.

  IF custom_container IS INITIAL.
    PERFORM create_container.
    PERFORM create_instance.
    PERFORM set_grid_layout.
    PERFORM set_grid_exclude.
    PERFORM set_grid_fieldcat.
    PERFORM create_event_receiver.
    PERFORM display_grid.

  ELSE.
    PERFORM refresh_grid_scr.
  ENDIF.

ENDFORM.                 " MAKE_ALV_DISP

FORM create_container .
  CREATE OBJECT custom_container
    EXPORTING
      container_name              = g_cont_name
    EXCEPTIONS
      cntl_error                  = 1
      cntl_system_error           = 2
      create_error                = 3
      lifetime_error              = 4
      lifetime_dynpro_dynpro_link = 5.
  IF sy-subrc NE 0.
    CALL FUNCTION 'POPUP_TO_INFORM'
      EXPORTING
        titel = g_repid
        txt2  = sy-subrc
        txt1  = 'The control could not be created'(510).
  ENDIF.
ENDFORM.                    " CREATE_CONTAINER

FORM create_instance .
  CREATE OBJECT grid
    EXPORTING
      i_parent = custom_container.
ENDFORM.                    " CREATE_INSTANCE

FORM set_grid_layout .

  CLEAR gs_layout.
  gs_layout-sel_mode = 'A'.  "선택모드
*  GS_LAYOUT-BOX_FNAME = 'MARK'.
  gs_layout-cwidth_opt = space.
  gs_layout-ctab_fname = 'COLTAB'.
  gs_layout-stylefname = 'STYTAB'.
  gs_layout-edit = 'X'.
ENDFORM.                    " SET_GRID_LAYOUT

FORM set_grid_exclude .
  FREE gt_exclude.
  gs_exclude = cl_gui_alv_grid=>mc_fc_loc_paste.          APPEND gs_exclude TO gt_exclude.
  gs_exclude = cl_gui_alv_grid=>mc_fc_loc_paste_new_row.  APPEND gs_exclude TO gt_exclude.
  gs_exclude = cl_gui_alv_grid=>mc_fc_loc_undo.           APPEND gs_exclude TO gt_exclude.
  gs_exclude = cl_gui_alv_grid=>mc_fc_loc_cut.            APPEND gs_exclude TO gt_exclude.
  gs_exclude = cl_gui_alv_grid=>mc_fc_loc_copy_row.       APPEND gs_exclude TO gt_exclude.
  gs_exclude = cl_gui_alv_grid=>mc_fc_loc_copy.           APPEND gs_exclude TO gt_exclude.
  gs_exclude = cl_gui_alv_grid=>mc_fc_refresh.            APPEND gs_exclude TO gt_exclude.
  gs_exclude = cl_gui_alv_grid=>mc_fc_loc_insert_row.     APPEND gs_exclude TO gt_exclude.
  gs_exclude = cl_gui_alv_grid=>mc_fc_loc_append_row.     APPEND gs_exclude TO gt_exclude.
  gs_exclude = cl_gui_alv_grid=>mc_fc_loc_delete_row.     APPEND gs_exclude TO gt_exclude.
ENDFORM.                    " SET_GRID_EXCLUDE

FORM set_grid_fieldcat .
  DATA: l_text(100) TYPE c.
  CLEAR: gt_fieldcat, gt_fieldcat[].
  CALL FUNCTION 'LVC_FIELDCATALOG_MERGE'
    EXPORTING
      i_structure_name       = 'ZSMM0015'
      i_client_never_display = 'X'
    CHANGING
      ct_fieldcat            = gt_fieldcat.
  LOOP AT gt_fieldcat INTO gs_fieldcat.
    CASE gs_fieldcat-fieldname.
      WHEN 'WERKS'.   gs_fieldcat-fix_column = 'X'. gs_fieldcat-col_pos = 1.
      WHEN 'MATNR'.   gs_fieldcat-fix_column = 'X'. gs_fieldcat-col_pos = 2. gs_fieldcat-outputlen = 18.
      WHEN 'ZLEVEL'.  l_text = '고철등급'.   gs_fieldcat-fix_column = 'X'. gs_fieldcat-col_pos = 3.
      WHEN 'BTEXT'.   l_text = '고철등급명'. gs_fieldcat-fix_column = 'X'. gs_fieldcat-col_pos = 4. gs_fieldcat-edit = space.
      WHEN 'DATAB'.   l_text = '유효시작일'. gs_fieldcat-fix_column = 'X'. gs_fieldcat-col_pos = 5.
      WHEN 'DATAI'.   gs_fieldcat-fix_column = 'X'. gs_fieldcat-col_pos = 6. l_text = '유효만료일'.
      WHEN 'DANGA'.   l_text = '단가'.     gs_fieldcat-col_pos = 7.
      WHEN 'WAERS'.   l_text = '통화'.     gs_fieldcat-col_pos = 8.
      WHEN 'KPEIN'.   l_text = '가격단위'. gs_fieldcat-col_pos = 9.
      WHEN 'ZDRFST'.  l_text = '품의상태'.   gs_fieldcat-col_pos = 10. gs_fieldcat-edit = space.
      WHEN 'ZSCRDNO'. l_text = '품의서번호'. gs_fieldcat-col_pos = 11. gs_fieldcat-edit = space.
      WHEN 'LAEDA'.   l_text = '수정일자'.   gs_fieldcat-col_pos = 12. gs_fieldcat-edit = space.
      WHEN 'LTIME'.   l_text = '수정시간'.   gs_fieldcat-col_pos = 13. gs_fieldcat-edit = space.
      WHEN 'AENAM'.   l_text = '수정인'.     gs_fieldcat-col_pos = 14. gs_fieldcat-edit = space.
      WHEN OTHERS.
    ENDCASE.
    IF l_text <> space.
      gs_fieldcat-scrtext_s    = l_text.
      gs_fieldcat-scrtext_m    = l_text.
      gs_fieldcat-scrtext_l    = l_text.
      gs_fieldcat-coltext = l_text.
    ENDIF.
    CLEAR l_text.
    MODIFY gt_fieldcat FROM gs_fieldcat.
  ENDLOOP.
ENDFORM.                    " SET_GRID_FIELDCAT
* (참고본은 위 FORM들의 줄바꿈만 압축했고 내용은 원문과 같음)

*&---------------------------------------------------------------------*
*&      Form  CREATE_EVENT_RECEIVER   (원문 그대로)
*&---------------------------------------------------------------------*
FORM create_event_receiver .

*   화면의 DATA가 변경된 경우를 인식
  CALL METHOD grid->register_edit_event
    EXPORTING
      i_event_id = cl_gui_alv_grid=>mc_evt_enter.
*   EVENT RECEIVER
  CREATE OBJECT event_receiver.

*   EVENT
  SET HANDLER event_receiver->handle_user_command   FOR grid.
  SET HANDLER event_receiver->handle_data_changed_finished FOR grid.

*  SET HANDLER EVENT_RECEIVER->HANDLE_DATA_CHANGED   FOR GRID.
*  SET HANDLER EVENT_RECEIVER->HANDLE_TOOLBAR        FOR GRID.
  SET HANDLER event_receiver->handle_double_click   FOR grid.
*    SET HANDLER EVENT_RECEIVER->HANDLE_MENU_BUTTON FOR GRID.
*  CALL METHOD GRID->SET_TOOLBAR_INTERACTIVE.

ENDFORM.                    " CREATE_EVENT_RECEIVER

FORM display_grid .

  gs_variant-report = sy-repid.

  grid->set_ready_for_input( 0 ).

  CALL METHOD grid->set_table_for_first_display
    EXPORTING
      i_structure_name     = 'ZSMM0015'
      is_layout            = gs_layout
      is_variant           = gs_variant
      i_save               = 'A'
      it_toolbar_excluding = gt_exclude
    CHANGING
      it_fieldcatalog      = gt_fieldcat
      it_outtab            = gt_pr[].

ENDFORM.                    " DISPLAY_GRID

FORM refresh_grid_scr .
  DATA is_stable TYPE lvc_s_stbl .
  is_stable-row = 1.
  is_stable-col = 1.
  CALL METHOD grid->refresh_table_display
    EXPORTING
      is_stable = is_stable
    EXCEPTIONS
      finished  = 1
      OTHERS    = 2.
ENDFORM.                    " REFRESH_GRID_SCR

*&---------------------------------------------------------------------*
*&      Form  SET_PF_STATUS   (원문 그대로)
*&---------------------------------------------------------------------*
FORM set_pf_status .
  DATA: lt_status TYPE slis_t_extab.
  DATA: ls_status TYPE slis_extab.

  DATA: lv_orgeh LIKE pa0001-orgeh.

  SELECT orgeh INTO lv_orgeh
    FROM pa0001
   WHERE pernr = sy-uname
        AND begda = ( SELECT MAX( begda )
                                FROM pa0001
                                WHERE pernr = sy-uname ).
  ENDSELECT.

  IF lv_orgeh = '10005020' OR sy-uname(2) = 'DU'. " 스크럽구매팀이라면
    IF grid IS INITIAL OR grid->is_ready_for_input(  ) EQ 0.
      ls_status = 'SAVE'.
      APPEND ls_status TO lt_status.
      ls_status = 'COPY'.
      APPEND ls_status TO lt_status.
      ls_status = 'CREA'.
      APPEND ls_status TO lt_status.
      ls_status = 'DEL'.
      APPEND ls_status TO lt_status.
    ENDIF.
  ELSE. " 스크럽구매팀이 아니라면
    IF grid IS INITIAL OR grid->is_ready_for_input(  ) EQ 0.
      ls_status = 'SAVE'.
      APPEND ls_status TO lt_status.
      ls_status = 'COPY'.
      APPEND ls_status TO lt_status.
      ls_status = 'CREA'.
      APPEND ls_status TO lt_status.
      ls_status = 'DEL'.
      APPEND ls_status TO lt_status.
      ls_status = 'TOGG'.
      APPEND ls_status TO lt_status.
    ENDIF.
  ENDIF.

  SET PF-STATUS '0100' EXCLUDING lt_status.
ENDFORM.                    " SET_PF_STATUS
