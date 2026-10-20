// 테스트결과서 XLSX: 테스트 단계 04_test.md의 시나리오 표를 통합테스트 양식(테스트시나리오 시트)에 옮겨 내려받는다.
// 머리글(Business Scenario·개요·주관모듈·관련모듈·중점 Check point) → 시나리오 표(### 절마다 구분 행) → 테스트 데이터 칸.
// 테스트 담당자·결과·Input/Output은 실제 테스트 때 채우도록 비워 둔다. 마크다운 표는 stagepptx.js의 spParse()로 읽는다.

let excelLib = null;
const loadExcel = () => (excelLib ??= new Promise((ok, fail) => {
  const s = document.createElement("script");
  s.src = "https://cdn.jsdelivr.net/npm/exceljs@4.4.0/dist/exceljs.min.js";
  s.onload = () => ok(window.ExcelJS);
  s.onerror = () => { excelLib = null; fail(new Error("엑셀 라이브러리를 불러오지 못했습니다. 인터넷 연결을 확인해 주세요.")); };
  document.head.append(s);
}));

const TR = {
  FONT: "Arial",
  HEAD: "FFDDEBF7", // 머리글·표 제목 (하늘색)
  GROUP: "FFE2EFDA", // 구분 행 (연두색)
  SUB: "FFFFFF00", // 소구분·테스트 데이터 제목 (노란색)
  WIDTHS: [4.38, 13.38, 22, 13.88, 16.75, 53.25, 53.75, 23, 14.5, 14, 16.25, 47.75],
  RESULTS: ["성공", "실패", "보류", "해당없음"],
};

// 표 머리글 이름으로 열을 찾는다 (테스트 담당이 단계마다 표 머리글을 조금씩 다르게 쓴다)
const trCol = (head, re) => head.findIndex((h) => re.test(h.trim()));

// 04_test.md → [{ group, rows: [{ id, title, tcode, proc, expect, input, trace }] }]
function trScenarios(text) {
  const groups = [];
  let heading = "";
  for (const b of spParse(text)) {
    if (b.type === "h" && b.level >= 2) { heading = b.text.replace(/^[\d.]+\s*/, "").trim(); continue; }
    if (b.type !== "table") continue;
    const c = {
      id: trCol(b.head, /^(ID|No\.?|번호)$/i),
      title: trCol(b.head, /제목|테스트 메서드|시나리오|항목|테스트명/),
      proc: trCol(b.head, /절차|방법|단계|입력 조건/),
      expect: trCol(b.head, /기대/),
      trace: trCol(b.head, /추적|관련|요구사항/),
      tcode: trCol(b.head, /T-?CODE|트랜잭션/i),
      input: trCol(b.head, /테스트 ?데이터|Input|입력값/i),
    };
    if (c.expect < 0 || (c.proc < 0 && c.title < 0)) continue; // 시나리오 표가 아니다 (리뷰·판정 표 등)
    const cell = (r, i) => (i >= 0 ? r[i] ?? "" : "");
    const groupTcode = heading.match(/T-?code\s*:?\s*([A-Z][A-Z0-9_]{2,19})/i)?.[1] ?? ""; // "통합 테스트 (T-code ZEMM2222)"
    groups.push({
      group: heading || "테스트 시나리오",
      rows: b.rows.map((r) => ({
        id: cell(r, c.id), title: cell(r, c.title), tcode: cell(r, c.tcode) || groupTcode, proc: cell(r, c.proc),
        expect: cell(r, c.expect), input: cell(r, c.input), trace: cell(r, c.trace),
      })),
    });
  }
  return groups;
}

// 분석서의 "## n. <제목>" 절 본문 줄
function trSection(text, re) {
  const lines = String(text ?? "").replace(/\r\n/g, "\n").split("\n");
  const i = lines.findIndex((l) => /^##\s/.test(l) && re.test(l));
  if (i < 0) return [];
  const end = lines.findIndex((l, k) => k > i && /^##\s/.test(l));
  return lines.slice(i + 1, end < 0 ? undefined : end).filter((l) => l.trim());
}

// 분석서 요약에서 "요청" 항목(없으면 첫 항목)을 개요로 쓴다. 근거 표기([REQ] 등)는 뺀다
function trOverview(t, analysis) {
  const lines = trSection(analysis, /요약/).filter((l) => !/^\s*(\||```|#)/.test(l));
  const items = lines.filter((l) => /^[-*]\s/.test(l)).map((l) => plain(l.replace(/^[-*]\s+/, "")).replace(/\s*\[[^\]]*\]/g, ""));
  const pick = items.find((l) => /^요청\s*:/.test(l)) ?? (lines[0] && !/^[-*]\s/.test(lines[0]) ? plain(lines[0]) : items[0]);
  return (pick ? pick.replace(/^요청\s*:\s*/, "") : plain(t.title)).slice(0, 300);
}

// 분석서 "관련 모듈" 절의 모듈 코드(MM, BC ...). 없으면 오브젝트 이름(ZCL_MM_..., SAPMZMM2222)에서 짐작한다
function trModules(t, analysis) {
  const codes = trSection(analysis, /관련 모듈/).map((l) => l.replace(/^[-*]\s+/, "").match(/^([A-Z]{2,4})\b/)?.[1]).filter(Boolean);
  if (codes.length) return [...new Set(codes)];
  const names = [...(t.files.development ?? []), ...(t.files.test ?? [])].map((f) => f.name.replace(/^src\//, "").toUpperCase());
  for (const n of [...names, t.title.toUpperCase()]) {
    const m = n.match(/(?:^|[_Z])(MM|SD|FI|CO|PP|PM|QM|HR|PS|WM|LE|BC)(?=[_\d])/);
    if (m) return [m[1]];
  }
  return [];
}

async function downloadTestResult(t) {
  const doc = (t.files.test ?? []).find((f) => f.name.endsWith("04_test.md"));
  if (!doc) throw new Error("테스트 단계 산출물(04_test.md)이 아직 없습니다.");
  const groups = trScenarios(doc.content);
  if (!groups.length) throw new Error("04_test.md에서 테스트 시나리오 표(절차·기대 결과 열이 있는 표)를 찾지 못했습니다.");

  const ExcelJS = await loadExcel();
  const wb = new ExcelJS.Workbook();
  const ws = wb.addWorksheet("테스트시나리오", { views: [{ state: "frozen", ySplit: 8 }] });
  TR.WIDTHS.forEach((w, i) => (ws.getColumn(i + 1).width = w));

  const thin = { style: "thin", color: { argb: "FF808080" } };
  const border = { top: thin, left: thin, bottom: thin, right: thin };
  const fill = (argb) => ({ type: "pattern", pattern: "solid", fgColor: { argb } });
  const style = (cell, o = {}) => {
    cell.font = { name: TR.FONT, size: o.size ?? 10, bold: !!o.bold, color: o.color ? { argb: o.color } : undefined };
    cell.alignment = { vertical: o.v ?? "middle", horizontal: o.h, wrapText: o.wrap ?? true };
    if (o.fill) cell.fill = fill(o.fill);
    if (o.border !== false) cell.border = border;
  };
  // 범위를 병합하고 모든 칸에 테두리를 그린다 (병합 칸 테두리는 칸마다 줘야 보인다)
  const put = (range, value, o = {}) => {
    const [a, b = a] = range.split(":");
    if (a !== b) ws.mergeCells(range);
    ws.getCell(a).value = value;
    const s = ws.getCell(a), e = ws.getCell(b);
    for (let r = s.row; r <= e.row; r++) for (let c = s.col; c <= e.col; c++) style(ws.getCell(r, c), o);
  };

  // 머리글
  const analysis = (t.files.analysis ?? []).find((f) => f.name.endsWith("01_analysis.md"))?.content ?? "";
  const mods = trModules(t, analysis);
  const mod = mods[0] ?? "";
  const review = t.stages.test?.review;
  const head = [
    ["Business Scenario", t.title, "D1:H1"],
    ["Scenario 개요", trOverview(t, analysis), "D2:H2"],
    ["주관모듈", mod, "D3:H3"],
    ["관련모듈", mods.join(", "), "D4:H4"],
    ["중점 Check point", review?.summary ?? "", "D5:H5"],
  ];
  head.forEach(([label, value, range], i) => {
    put(`B${i + 1}:C${i + 1}`, label, { bold: true, fill: TR.HEAD, h: "center" });
    put(range, value, { v: "top" });
    ws.getRow(i + 1).height = i === 4 ? 60 : i === 1 ? 36 : 18;
  });
  put("B6", `요청 ${t.id} · 테스트 일시/장소: `, { bold: true, border: false, wrap: false });

  // 표 제목 (7~8행)
  const cols7 = [["B7:B8", "No"], ["C7:C8", "Process Step"], ["D7:D8", "T-CODE"], ["E7:E8", "모듈"], ["F7:F8", "Step 세부내용 및 Check Point"],
    ["G7:H7", "테스트"], ["I7:I8", "테스트\n담당자"], ["J7:J8", "테스트\n결과"], ["K7:K8", "통테\n1차"], ["L7:L8", "비고"]];
  for (const [range, label] of cols7) put(range, label, { bold: true, fill: TR.HEAD, h: "center", size: 11 });
  put("G8", "Input", { bold: true, fill: TR.HEAD, h: "center", size: 11 });
  put("H8", "Output", { bold: true, fill: TR.HEAD, h: "center", size: 11 });
  ws.getRow(7).height = 18;
  ws.getRow(8).height = 18;

  // 시나리오
  let r = 9;
  for (const g of groups) {
    put(`B${r}`, g.group, { bold: true, fill: TR.GROUP, h: "center" });
    put(`C${r}:L${r}`, "", { fill: TR.GROUP });
    r++;
    g.rows.forEach((s, i) => {
      const detail = [s.proc, s.expect && `[기대 결과]\n${s.expect}`].filter(Boolean).join("\n\n");
      const vals = [i + 1, [s.id, s.title].filter(Boolean).join(" "), s.tcode, mod, detail, s.input, "", "", "", "", s.trace];
      vals.forEach((v, k) => style(Object.assign(ws.getCell(r, k + 2), { value: v }), { h: [0, 2, 3, 6, 7, 8, 9].includes(k) ? "center" : undefined, bold: k === 1 }));
      ws.getCell(r, 10).dataValidation = { type: "list", allowBlank: true, formulae: [`"${TR.RESULTS.join(",")}"`] };
      ws.getCell(r, 10).font = { name: TR.FONT, size: 10, bold: true, color: { argb: "FF0000FF" } };
      const lines = Math.max(...[detail, s.trace, vals[1]].map((x, k) => String(x).split("\n").reduce((n, l) => n + Math.max(1, Math.ceil(spUnits(l) / ([53, 47, 22][k] * 1.1))), 0)));
      ws.getRow(r).height = Math.min(400, Math.max(30, lines * 13 + 6));
      r++;
    });
  }

  // 테스트 데이터 (실제 테스트 때 채운다)
  r += 2;
  put(`B${r}`, "[테스트 데이터]", { bold: true, border: false, wrap: false });
  r++;
  put(`B${r}`, "No.", { bold: true, fill: TR.SUB, h: "center" });
  put(`C${r}:E${r}`, "구분", { bold: true, fill: TR.SUB, h: "center" });
  put(`F${r}`, "TEST DATA", { bold: true, fill: TR.SUB, h: "center" });
  put(`G${r}:H${r}`, "비   고", { bold: true, fill: TR.SUB, h: "center" });
  put(`I${r}`, "생성담당자", { bold: true, fill: TR.SUB, h: "center" });
  for (let i = 1; i <= 5; i++) {
    r++;
    put(`B${r}`, i, { h: "center" });
    put(`C${r}:E${r}`, "");
    put(`F${r}`, "");
    put(`G${r}:H${r}`, "");
    put(`I${r}`, "", { h: "center" });
    ws.getRow(r).height = 20;
  }

  ws.pageSetup = { orientation: "landscape", fitToPage: true, fitToWidth: 1, fitToHeight: 0, paperSize: 9 };
  const blob = new Blob([await wb.xlsx.writeBuffer()], { type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" });
  const a = Object.assign(document.createElement("a"), {
    href: URL.createObjectURL(blob),
    download: `${t.id}(${t.title})_테스트결과서_${new Date().toISOString().slice(0, 10)}.xlsx`.replace(/[\\/:*?"<>|]/g, "_"),
  });
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
}
