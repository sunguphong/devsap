*&---------------------------------------------------------------------*
*&  Include           ZRMM0057C01
*&---------------------------------------------------------------------*
*& 로컬 이벤트 핸들러 (SALV 툴바 버튼, 팝업 더블클릭)
*&---------------------------------------------------------------------*

CLASS lcl_event_handler DEFINITION FINAL.
  PUBLIC SECTION.
    METHODS:
      on_added_function
        FOR EVENT added_function OF cl_salv_events
        IMPORTING e_salv_function,
      on_double_click_batch
        FOR EVENT double_click OF cl_salv_events_table
        IMPORTING row column,
      on_double_click_doc
        FOR EVENT double_click OF cl_salv_events_table
        IMPORTING row column.
ENDCLASS.


CLASS lcl_event_handler IMPLEMENTATION.

  METHOD on_added_function.
    CASE e_salv_function.
      WHEN c_fc_detail.
        PERFORM show_batch_detail.
      WHEN c_fc_recon.
        PERFORM show_recon.
      WHEN OTHERS.
        " SALV 표준 기능은 SALV 가 처리
    ENDCASE.
  ENDMETHOD.


  METHOD on_double_click_batch.
    " 배치 상세 행 -> 자재문서 목록
    IF row <= 0.
      RETURN.
    ENDIF.
    PERFORM show_docs USING row.
  ENDMETHOD.


  METHOD on_double_click_doc.
    " 자재문서 행 -> MB03
    IF row <= 0.
      RETURN.
    ENDIF.
    PERFORM call_mb03 USING row.
  ENDMETHOD.

ENDCLASS.
