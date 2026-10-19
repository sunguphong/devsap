// 단계 산출물 PPTX: 선택한 단계의 산출물(문서·소스)을 슬라이드로 만들어 내려받는다.
// 표지(요청·단계·PL 의견) → 문서의 ## 절마다 새 슬라이드, 넘치면 "(계속)" 슬라이드.
// 문단·목록·표·코드는 그대로, ```mermaid 는 그림(PNG), ```sapscreen 은 표로 옮긴다. pptxgenjs는 standards.js의 loadPptx()로 불러온다.

const SP = { W: 13.33, X: 0.5, CW: 12.33, TOP: 1.0, BOTTOM: 7.0, FONT: "Malgun Gothic", MONO: "Consolas", NAVY: "1F3A5F", ACCENT: "2463EB", MUTED: "5B6577" };

// 글자 폭 단위(한글 2, 영문 1)로 줄 수를 어림한다
const spUnits = (s) => [...String(s)].reduce((n, c) => n + (c.charCodeAt(0) > 0x2e80 ? 2 : 1), 0);
const spLines = (s, wIn, pt) => String(s).split("\n").reduce((n, l) => n + Math.max(1, Math.ceil((spUnits(l) * pt * 0.5) / (wIn * 72 - 8))), 0);
const spLineH = (pt) => (pt * 1.32) / 72;

// 마크다운 → 블록 (코드 블록은 언어와 함께)
function spParse(text) {
  const blocks = [];
  let code = null;
  for (const line of text.replace(/\r\n/g, "\n").split("\n")) {
    if (code) {
      if (line.startsWith("```")) { blocks.push(code); code = null; } else code.lines.push(line);
      continue;
    }
    if (line.startsWith("```")) { code = { type: "code", lang: line.slice(3).trim(), lines: [] }; continue; }
    const last = blocks[blocks.length - 1];
    const h = line.match(/^(#{1,6})\s+(.*)/);
    const q = line.match(/^>\s?(.*)/);
    const li = line.match(/^(\s*)(?:[-*]|\d+\.)\s+(.*)/);
    if (h) blocks.push({ type: "h", level: h[1].length, text: plain(h[2]) });
    else if (/^\s*\|.*\|\s*$/.test(line)) {
      if (/^\s*\|[\s:|-]+\|\s*$/.test(line)) continue;
      const cells = line.trim().slice(1, -1).split("|").map((c) => plain(c.trim()));
      last?.type === "table" ? last.rows.push(cells) : blocks.push({ type: "table", head: cells, rows: [] });
    } else if (q) last?.type === "quote" ? last.lines.push(plain(q[1])) : blocks.push({ type: "quote", lines: [plain(q[1])] });
    else if (li) {
      const item = { text: plain(li[2]), indent: li[1].length >= 2 ? 1 : 0 };
      last?.type === "list" ? last.items.push(item) : blocks.push({ type: "list", items: [item] });
    } else if (line.trim()) blocks.push({ type: "p", text: plain(line.trim()) });
  }
  if (code) blocks.push(code);
  return blocks;
}

// 예상 화면(sapscreen JSON) → 표 블록
function spScreen(lines) {
  const d = JSON.parse(lines.join("\n"));
  const title = `[예상 화면] ${d.title ?? ""}${d.tcode ? ` (${d.tcode})` : ""}`;
  const out = [{ type: "sub", text: title }];
  if (d.type === "alv") {
    const cols = (d.columns ?? []).map((c) => c.label);
    if (cols.length) out.push({ type: "table", head: cols, rows: [...(d.rows ?? []), ...(d.total ? [d.total] : [])].map((r) => r.map(String)) });
    if (d.toolbar?.length) out.push({ type: "p", text: `툴바: ${d.toolbar.join(" · ")}` });
  } else if (d.type === "popup") out.push({ type: "p", text: `팝업 — ${d.message ?? ""} [${(d.buttons ?? ["확인"]).join("] [")}]` });
  else {
    const KIND = { select: "범위(From~To)", param: "단일 입력", check: "체크박스", radio: "라디오버튼" };
    const rows = (d.blocks ?? []).flatMap((b) => (b.fields ?? []).map((f) => [b.title ?? "", f.label ?? "", KIND[f.kind] ?? f.kind ?? "", f.required ? "필수" : "", f.checked ? "기본 선택" : f.value ?? ""]));
    if (rows.length) out.push({ type: "table", head: ["블록", "항목", "형태", "필수", "기본값"], rows });
  }
  if (d.status) out.push({ type: "p", text: `상태바(${d.status.type ?? "S"}): ${d.status.text ?? ""}` });
  return out;
}

// Mermaid → PNG (PowerPoint가 못 그리는 HTML 라벨을 끄고 다시 그린다)
async function spMermaid(code) {
  mermaidLib ??= import("https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs").then(({ default: m }) => m);
  const m = await mermaidLib;
  const base = { startOnLoad: false, securityLevel: "strict", theme: "default", fontFamily: "Malgun Gothic, sans-serif" };
  m.initialize({ ...base, htmlLabels: false, flowchart: { htmlLabels: false }, class: { htmlLabels: false } });
  let svg;
  try { ({ svg } = await m.render(`sp${Date.now()}${Math.random().toString(36).slice(2, 7)}`, code)); }
  finally { m.initialize(base); }
  // HTML 파서로 읽어 크기를 고정한 뒤 XML로 다시 직렬화한다 (mermaid SVG의 width="100%"·<br> 때문에 그대로는 이미지로 안 읽힌다)
  const holder = document.createElement("div");
  holder.innerHTML = svg;
  const el = holder.querySelector("svg");
  const vb = el.viewBox?.baseVal;
  const w = vb?.width || 800, h = vb?.height || 600;
  el.setAttribute("width", w);
  el.setAttribute("height", h);
  el.removeAttribute("style");
  const img = new Image();
  img.src = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(new XMLSerializer().serializeToString(el));
  await img.decode();
  const scale = Math.max(2, Math.min(8, 2400 / Math.max(w, h)));
  const canvas = Object.assign(document.createElement("canvas"), { width: Math.round(w * scale), height: Math.round(h * scale) });
  const ctx = canvas.getContext("2d");
  ctx.fillStyle = "#fff";
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
  return { data: canvas.toDataURL("image/png"), w, h };
}

// 위에서 아래로 쌓다가 넘치면 다음 슬라이드로 넘기는 배치기
class SpFlow {
  constructor(pptx, docTitle) { this.pptx = pptx; this.docTitle = docTitle; this.slide = null; this.page = 1; this.section = docTitle; }
  newSlide(title, cont = false) {
    this.section = title;
    const s = (this.slide = this.pptx.addSlide());
    s.addShape(this.pptx.ShapeType.rect, { x: 0, y: 0, w: SP.W, h: 0.75, fill: { color: SP.NAVY } });
    s.addText(`${title}${cont ? " (계속)" : ""}`, { x: 0.4, y: 0.1, w: 9.6, h: 0.55, fontFace: SP.FONT, fontSize: 20, bold: true, color: "FFFFFF", fit: "shrink" });
    s.addText(this.docTitle, { x: 9.9, y: 0.1, w: 3.1, h: 0.55, fontFace: SP.FONT, fontSize: 9, color: "C9D6E8", align: "right", fit: "shrink" });
    s.addText(String(++this.page), { x: 12.0, y: 7.1, w: 1.0, h: 0.3, fontFace: SP.FONT, fontSize: 9, color: SP.MUTED, align: "right" });
    this.y = SP.TOP;
  }
  room() { return SP.BOTTOM - this.y; }
  ensure(h) { if (!this.slide || h > this.room()) this.newSlide(this.section, !!this.slide); }

  text(runs, pt, opts = {}) {
    const str = runs.map((r) => (typeof r === "string" ? r : r.text)).join("\n");
    const h = spLines(str, SP.CW - (opts.indentIn ?? 0), pt) * spLineH(pt) + 0.08;
    this.ensure(Math.min(h, SP.BOTTOM - SP.TOP));
    const body = runs.every((r) => typeof r === "string") ? str : runs;
    this.slide.addText(body, { x: SP.X + (opts.indentIn ?? 0), y: this.y, w: SP.CW - (opts.indentIn ?? 0), h, fontFace: SP.FONT, fontSize: pt, color: "1D2330", valign: "top", margin: 2, ...opts.style });
    this.y += h + (opts.gap ?? 0.06);
  }
  list(items) {
    for (const it of items)
      this.text([{ text: it.text, options: { bullet: it.indent ? { indent: 14 } : true } }], 12, { indentIn: it.indent * 0.35, gap: 0.02 });
    this.y += 0.06;
  }
  table(head, rows) {
    const n = head.length;
    const all = [head, ...rows].map((r) => head.map((_, i) => String(r[i] ?? "")));
    const pt = n > 6 ? 8 : n > 4 ? 9 : 10;
    // 열 너비: 내용 길이 비례, 최소 0.7in
    const need = head.map((_, i) => Math.min(60, Math.max(4, ...all.map((r) => spUnits(r[i])))));
    const total = need.reduce((a, b) => a + b, 0);
    let colW = need.map((u) => Math.max(0.7, (SP.CW * u) / total));
    const scale = SP.CW / colW.reduce((a, b) => a + b, 0);
    colW = colW.map((w) => w * scale);
    const rowH = (r) => Math.max(...r.map((c, i) => spLines(c, colW[i] - 0.1, pt))) * spLineH(pt) + 0.08;
    const headRow = all[0].map((t) => ({ text: t, options: { bold: true, fill: { color: "DCE6F2" } } }));
    let i = 1;
    while (i <= rows.length || i === 1) {
      this.ensure(rowH(all[0]) + Math.min(rowH(all[i] ?? all[0]), 1.5));
      const chunk = [];
      let h = rowH(all[0]);
      while (i <= rows.length && h + rowH(all[i]) <= this.room()) { h += rowH(all[i]); chunk.push(all[i++]); }
      if (!chunk.length && i <= rows.length) { chunk.push(all[i++]); h += 0.4; } // 한 행이 한 장보다 길면 그대로 싣는다
      this.slide.addTable([headRow, ...chunk], { x: SP.X, y: this.y, w: SP.CW, colW, fontFace: SP.FONT, fontSize: pt, border: { type: "solid", color: "C8D1DC", pt: 0.5 }, margin: 0.04, valign: "top" });
      this.y += h + 0.15;
      if (i > rows.length) break;
      this.newSlide(this.section, true);
    }
  }
  code(lines, label) {
    const pt = 9, lh = spLineH(pt);
    let k = 0;
    do {
      this.ensure(Math.min(lines.length - k, 6) * lh + 0.2);
      const fit = Math.max(1, Math.floor((this.room() - 0.15) / lh));
      const part = lines.slice(k, k + fit);
      const h = part.length * lh + 0.12;
      this.slide.addText(part.join("\n") || " ", { x: SP.X, y: this.y, w: SP.CW, h, fontFace: SP.MONO, fontSize: pt, color: "1D2330", fill: { color: "F4F6F9" }, valign: "top", margin: 4, line: { color: "D5DCE5", width: 0.5 } });
      this.y += h + 0.12;
      k += part.length;
      if (k < lines.length) this.newSlide(this.section, true);
    } while (k < lines.length);
    if (label) this.text([label], 9, { style: { color: SP.MUTED } });
  }
  image(img) {
    const maxH = SP.BOTTOM - SP.TOP;
    let w = Math.min(SP.CW, (img.w / 96) * 1.6), h = (w * img.h) / img.w; // 작은 그림은 과하게 키우지 않는다
    if (h > maxH) { h = maxH; w = (h * img.w) / img.h; }
    if (h > this.room() && this.room() < maxH * 0.6) this.newSlide(this.section, true);
    if (h > this.room()) { h = this.room(); w = (h * img.w) / img.h; }
    this.slide.addImage({ data: img.data, x: SP.X + (SP.CW - w) / 2, y: this.y, w, h });
    this.y += h + 0.15;
  }
}

async function spRenderDoc(flow, file) {
  const blocks = file.name.endsWith(".md") ? spParse(file.content) : [{ type: "code", lang: "abap", lines: file.content.replace(/\r\n/g, "\n").split("\n") }];
  if (!file.name.endsWith(".md")) flow.newSlide(`📄 ${file.name}`);
  for (const b of blocks) {
    if (b.type === "h" && b.level <= 2) { flow.newSlide(b.level === 1 ? b.text : b.text); continue; }
    if (!flow.slide) flow.newSlide(flow.section);
    if (b.type === "h") flow.text([b.text], b.level === 3 ? 15 : 13, { style: { bold: true, color: b.level === 3 ? SP.NAVY : SP.ACCENT }, gap: 0.04 });
    else if (b.type === "sub") flow.text([b.text], 13, { style: { bold: true, color: SP.ACCENT } });
    else if (b.type === "p") flow.text([b.text], 12);
    else if (b.type === "quote") flow.text([b.lines.join("\n")], 11, { style: { color: SP.MUTED, fill: { color: "EEF3FB" } } });
    else if (b.type === "list") flow.list(b.items);
    else if (b.type === "table") flow.table(b.head, b.rows);
    else if (b.type === "code" && b.lang === "mermaid") {
      try { flow.image(await spMermaid(b.lines.join("\n"))); } catch { flow.code(b.lines, "다이어그램을 그림으로 바꾸지 못해 원문을 넣었습니다."); }
    } else if (b.type === "code" && b.lang === "sapscreen") {
      try { for (const x of spScreen(b.lines)) x.type === "table" ? flow.table(x.head, x.rows) : flow.text([x.text], x.type === "sub" ? 13 : 11, x.type === "sub" ? { style: { bold: true, color: SP.ACCENT } } : {}); }
      catch { flow.code(b.lines); }
    } else if (b.type === "code") flow.code(b.lines);
  }
}

async function downloadStagePptx(t, stage) {
  const PptxGenJS = await loadPptx();
  const pptx = new PptxGenJS();
  pptx.layout = "LAYOUT_WIDE";
  const stageName = status.team[stage].name;
  const st = t.stages[stage];
  pptx.title = `${t.title} - ${stageName}`;

  // 표지
  const cover = pptx.addSlide();
  cover.background = { color: SP.NAVY };
  cover.addText(t.title, { x: 0.8, y: 1.9, w: 11.7, h: 1.1, fontFace: SP.FONT, fontSize: 34, bold: true, color: "FFFFFF", fit: "shrink" });
  cover.addText(`${stageName} 산출물`, { x: 0.8, y: 3.0, w: 11.7, h: 0.6, fontFace: SP.FONT, fontSize: 20, color: "C9D6E8" });
  cover.addText(`요청 ${t.id} · 상태 ${STAGE_STATUS[st.status] ?? st.status} · 작성 ${new Date().toLocaleDateString("ko-KR")}`, { x: 0.8, y: 3.6, w: 11.7, h: 0.4, fontFace: SP.FONT, fontSize: 12, color: "C9D6E8" });
  if (st.review) cover.addText(`PL 의견 (권고: ${st.review.decision === "approve" ? "승인" : "수정"}) — ${st.review.summary}`, { x: 0.8, y: 4.4, w: 11.7, h: 2.6, fontFace: SP.FONT, fontSize: 12, color: "E6EDF6", valign: "top", fit: "shrink" });

  const flow = new SpFlow(pptx, `${t.title} · ${stageName}`);
  if (stage === "deploy") {
    flow.newSlide("개발계 반영 결과");
    flow.code((t.deployResult?.text ?? "아직 반영하지 않았습니다.").split("\n"));
  } else {
    const files = [...(t.files[stage] ?? [])].sort((a, b) => Number(b.name.endsWith(".md")) - Number(a.name.endsWith(".md")));
    if (!files.length) throw new Error("이 단계에는 아직 산출물이 없습니다.");
    for (const f of files) { flow.slide = null; flow.section = f.name; await spRenderDoc(flow, f); }
  }
  if (st.directives?.length) {
    flow.newSlide("팀장 수정 지시 이력");
    flow.list(st.directives.map((d) => ({ text: `${new Date(d.at).toLocaleString()} — ${d.text}`, indent: 0 })));
  }
  await pptx.writeFile({ fileName: `${t.id}(${t.title})_${stageName}_${new Date().toISOString().slice(0, 10)}.pptx`.replace(/[\\/:*?"<>|]/g, "_") });
}
