* 스냅숏: srd-abap(클라이언트 250) GetInclude ZRMM0034TOP, 조회일 2026-10-24 (PL)
*&---------------------------------------------------------------------*
*&  Include           ZRMM0034TOP
*&---------------------------------------------------------------------*

*----------------------------------------------------------------------*
* TABLES                                                               *
*----------------------------------------------------------------------*
TABLES : ztmm0068,
         ztmm0069,
         mara,
         mkpf,
         mseg,
         ztmm0070.

*----------------------------------------------------------------------*
* DATA                                                                 *
*----------------------------------------------------------------------*
DATA: gt_68   LIKE ztmm0068 OCCURS 0 WITH HEADER LINE,
      gt_68_1 LIKE ztmm0068 OCCURS 0 WITH HEADER LINE,
      gt_10   LIKE ztmm0010 OCCURS 0 WITH HEADER LINE,
      gt_69   LIKE ztmm0069 OCCURS 0 WITH HEADER LINE,
      gt_69_1 LIKE ztmm0069 OCCURS 0 WITH HEADER LINE,
      gt_12   LIKE ztmm0012 OCCURS 0 WITH HEADER LINE.

DATA : BEGIN OF gt_68_zclstc OCCURS 0,
         lfgja  LIKE ztmm0068-lfgja,
         lfmon  LIKE ztmm0068-lfmon,
         werks  LIKE ztmm0068-werks,
         matnr  LIKE ztmm0068-matnr,
         zclstc LIKE ztmm0068-zclstc,
       END OF gt_68_zclstc.

DATA : BEGIN OF gt_69_zclstc OCCURS 0,
         lfgja  LIKE ztmm0069-lfgja,
         lfmon  LIKE ztmm0069-lfmon,
         werks  LIKE ztmm0069-werks,
         lgort  LIKE ztmm0069-lgort,
         matnr  LIKE ztmm0069-matnr,
         zclstc LIKE ztmm0069-zclstc,
       END OF gt_69_zclstc.

DATA : BEGIN OF g_mseg_t OCCURS 0,
         mblnr LIKE mseg-mblnr,
         mjahr LIKE mseg-mjahr,
         zeile LIKE mseg-zeile,
         matnr LIKE mseg-matnr,
         werks LIKE mseg-werks,
         budat LIKE mkpf-budat,
         lgort LIKE mseg-lgort,
         menge LIKE mseg-menge,
         meins LIKE mseg-meins,
         lmein LIKE mara-meins,
         shkzg LIKE mseg-shkzg,
         umwrk LIKE mseg-umwrk,
         umlgo LIKE mseg-umlgo,
         ummat LIKE mseg-ummat,
         bwart LIKE mseg-bwart,
         wertu LIKE mseg-wertu,
         mengu LIKE mseg-mengu,
         sobkz LIKE mseg-sobkz,
         kzbew LIKE mseg-kzbew,
         kzzug LIKE mseg-kzzug,
         kzvbr LIKE mseg-kzvbr,
         xauto LIKE mseg-xauto,
         ebeln LIKE mseg-ebeln,
         ebelp LIKE mseg-ebelp,
         bustm LIKE mseg-bustm,
         bustw LIKE mseg-bustw,
       END OF g_mseg_t.

DATA: g_answer  TYPE c,
      g_cls_ind LIKE ztmm0013-cls_ind,
      g_grind   LIKE ztmm0008-grind,
      g_giind   LIKE ztmm0008-giind,
      g_tpind   LIKE ztmm0008-tpind,
      g_shkzg   LIKE ztmm0008-shkzg,
      g_menge   LIKE mseg-menge,
      g_count0  TYPE i,
      g_count1  TYPE i,
      g_count2  TYPE i,
      g_count3  TYPE i,
      gv_tabix  LIKE sy-tabix,
      gv_meins  LIKE mara-meins,
      gs_tp2_wa LIKE ztmm0069,
      gs_tp2_68 LIKE ztmm0068,
      gs_tp2_69 LIKE ztmm0069.

DATA: BEGIN OF gs_qty,
        zpo_gr LIKE ztmm0069-zpo_gr,
        zpp_gr LIKE ztmm0069-zpp_gr,
        ztp_gr LIKE ztmm0069-ztp_gr,
        zre_gr LIKE ztmm0069-zre_gr,
        zot_gr LIKE ztmm0069-zot_gr,
        zsd_gi LIKE ztmm0069-zsd_gi,
        zpp_gi LIKE ztmm0069-zpp_gi,
        ztp_gi LIKE ztmm0069-ztp_gi,
        zsp_gi LIKE ztmm0069-zsp_gi,
        zot_gi LIKE ztmm0069-zot_gi,
      END OF gs_qty.

DATA : gs_uplog     LIKE ztmm0070.

DATA : dt_yesterday LIKE sy-datum.


DATA : BEGIN OF wa_stock OCCURS 0,
         matnr LIKE mchb-matnr,
         charg LIKE mchb-charg,
         werks LIKE mchb-werks,
         lgort LIKE mchb-lgort,
         clabs LIKE mchb-clabs,               "가용재고
         cinsm LIKE mchb-cinsm,           "품질재고
         shkzg LIKE ztppmseg-shkzg,
       END OF wa_stock.


DATA : BEGIN OF gt_stock OCCURS 0,
         matnr LIKE mchb-matnr,
         mtart  LIKE mara-mtart,
         budat LIKE mkpf-budat,
         charg LIKE mchb-charg,
         werks LIKE mchb-werks,
         lgort LIKE mchb-lgort,
         clabs LIKE mchb-clabs,
       END OF gt_stock.

*----------------------------------------------------------------------*
* SELECTION-SCREEN                                                     *
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE text-001.

SELECT-OPTIONS so_budat FOR mkpf-budat OBLIGATORY NO-EXTENSION.
SELECT-OPTIONS so_werks FOR mseg-werks OBLIGATORY
                                       NO-EXTENSION
                                       NO INTERVALS.
SELECT-OPTIONS so_matnr FOR mara-matnr.
*SELECT-OPTIONS so_mtart FOR mara-mtart.
SELECTION-SCREEN END OF BLOCK b1.
