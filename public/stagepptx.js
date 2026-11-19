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

// ---------- 보고용 PPT ----------
// 서버(src/deck.ts)가 산출물을 요약한 슬라이드 개요로 만든다: 표지 → 한눈에 보기 → 본문(한 장 한 메시지) → 확인 필요·다음 단계.
// 화면에는 요점만 두고 상세 근거는 발표자 노트로 보낸다.

const RP = { X: 0.6, CW: 12.13, TOP: 2.1, H: 4.7, INK: "1D2330", BODY: "334155", SOFT: "E8EFFD", BG: "F4F6FA", LINE: "D9E0EA", WARN: "B45309", WARN_BG: "FFF6E8" };
const rpClip = (s, n) => { const c = [...String(s ?? "").trim()]; return c.length > n ? c.slice(0, n - 1).join("") + "…" : c.join(""); };

class ReportDeck {
  constructor(pptx, docTitle) { this.pptx = pptx; this.docTitle = docTitle; this.page = 1; }
  t(s, text, o) { s.addText(text, { fontFace: SP.FONT, color: RP.INK, margin: 0, valign: "top", ...o }); }
  rect(s, o) { s.addShape(this.pptx.ShapeType.rect, { line: { type: "none" }, ...o }); }

  // 공통 틀: 제목 + 핵심 메시지 + 구분선, 아래 본문 영역 (y 2.1 ~ 6.8)
  frame(title, message, notes) {
    const s = this.pptx.addSlide();
    this.rect(s, { x: RP.X, y: 0.5, w: 0.09, h: 0.58, fill: { color: SP.ACCENT } });
    this.t(s, rpClip(title, 30), { x: RP.X + 0.25, y: 0.42, w: RP.CW - 0.25, h: 0.72, fontSize: 26, bold: true, color: SP.NAVY, valign: "middle", fit: "shrink" });
    if (message) this.t(s, rpClip(message, 80), { x: RP.X + 0.25, y: 1.15, w: RP.CW - 0.25, h: 0.5, fontSize: 16, color: RP.BODY, valign: "middle", fit: "shrink" });
    s.addShape(this.pptx.ShapeType.line, { x: RP.X, y: 1.82, w: RP.CW, h: 0, line: { color: RP.LINE, width: 1 } });
    this.t(s, this.docTitle, { x: RP.X, y: 7.0, w: 9, h: 0.3, fontSize: 9, color: SP.MUTED });
    this.t(s, String(++this.page), { x: 11.73, y: 7.0, w: 1.0, h: 0.3, fontSize: 9, color: SP.MUTED, align: "right" });
    if (notes) s.addNotes(notes);
    return s;
  }

  // 요점 카드: 3개 이하는 세로형 카드를 가로로, 4개 이상(또는 좁은 영역)은 번호 붙은 가로형 카드
  points(s, pts, x = RP.X, w = RP.CW) {
    pts = pts.slice(0, 6);
    const n = pts.length;
    if (!n) return;
    if (n <= 3 && w > 8) {
      const gap = 0.3, cw = (w - gap * (n - 1)) / n, h = 3.6, y = RP.TOP + 0.3;
      pts.forEach((p, i) => {
        const cx = x + i * (cw + gap);
        this.rect(s, { x: cx, y, w: cw, h, fill: { color: RP.BG } });
        this.rect(s, { x: cx, y, w: cw, h: 0.08, fill: { color: SP.ACCENT } });
        this.t(s, String(i + 1).padStart(2, "0"), { x: cx + 0.35, y: y + 0.35, w: 1, h: 0.4, fontSize: 14, bold: true, color: SP.ACCENT });
        this.t(s, rpClip(p.head, 24), { x: cx + 0.35, y: y + 0.85, w: cw - 0.7, h: 0.9, fontSize: n === 1 ? 24 : 20, bold: true, color: SP.NAVY, fit: "shrink" });
        this.t(s, rpClip(p.text, 90), { x: cx + 0.35, y: y + 1.85, w: cw - 0.7, h: h - 2.1, fontSize: 15, color: RP.BODY, lineSpacingMultiple: 1.2, fit: "shrink" });
      });
      return;
    }
    const cols = w > 8 && n >= 4 ? 2 : 1, rows = Math.ceil(n / cols), gap = 0.22;
    const cw = (w - gap * (cols - 1)) / cols, ch = Math.min(1.6, (RP.H - gap * (rows - 1)) / rows);
    const small = ch < 1.3 || w < 5;
    pts.forEach((p, i) => {
      const cx = x + (i % cols) * (cw + gap), cy = RP.TOP + Math.floor(i / cols) * (ch + gap);
      this.rect(s, { x: cx, y: cy, w: cw, h: ch, fill: { color: RP.BG } });
      s.addShape(this.pptx.ShapeType.ellipse, { x: cx + 0.2, y: cy + (ch - 0.46) / 2, w: 0.46, h: 0.46, fill: { color: RP.SOFT }, line: { type: "none" } });
      this.t(s, String(i + 1), { x: cx + 0.2, y: cy + (ch - 0.46) / 2, w: 0.46, h: 0.46, fontSize: 13, bold: true, color: SP.ACCENT, align: "center", valign: "middle" });
      this.t(s, [
        { text: rpClip(p.head, 24), options: { fontSize: small ? 14 : 17, bold: true, color: SP.NAVY, breakLine: true } },
        { text: rpClip(p.text, 90), options: { fontSize: small ? 12 : 14, color: RP.BODY } },
      ], { x: cx + 0.85, y: cy + 0.1, w: cw - 1.0, h: ch - 0.2, valign: "middle", paraSpaceAfter: 4, fit: "shrink" });
    });
  }

  // 처리 단계: 가로로 이어지는 상자와 화살표
  steps(s, pts) {
    if (pts.length > 6 || pts.length < 2) return this.points(s, pts);
    const n = pts.length, gap = 0.4, cw = (RP.CW - gap * (n - 1)) / n, y = RP.TOP + 0.4;
    pts.forEach((p, i) => {
      const cx = RP.X + i * (cw + gap);
      this.rect(s, { x: cx, y, w: cw, h: 1.15, fill: { color: i === n - 1 ? SP.NAVY : SP.ACCENT } });
      this.t(s, [
        { text: `STEP ${i + 1}`, options: { fontSize: 10, color: "C9D6E8", breakLine: true } },
        { text: rpClip(p.head, 20), options: { fontSize: n > 4 ? 14 : 17, bold: true, color: "FFFFFF" } },
      ], { x: cx + 0.15, y, w: cw - 0.3, h: 1.15, valign: "middle", fit: "shrink" });
      this.rect(s, { x: cx, y: y + 1.15, w: cw, h: 2.1, fill: { color: RP.BG } });
      this.t(s, rpClip(p.text, 80), { x: cx + 0.18, y: y + 1.35, w: cw - 0.36, h: 1.75, fontSize: n > 4 ? 14 : 16, color: RP.BODY, lineSpacingMultiple: 1.2, fit: "shrink" });
      if (i < n - 1) s.addShape(this.pptx.ShapeType.rightArrow, { x: cx + cw + 0.08, y: y + 0.38, w: gap - 0.16, h: 0.4, fill: { color: "9FB4D9" }, line: { type: "none" } });
    });
  }

  // 핵심 수치: 큰 숫자 + 설명
  metrics(s, pts) {
    pts = pts.slice(0, 4);
    const n = pts.length, gap = 0.35, cw = (RP.CW - gap * (n - 1)) / n, y = RP.TOP + 0.6;
    pts.forEach((p, i) => {
      const cx = RP.X + i * (cw + gap);
      this.rect(s, { x: cx, y, w: cw, h: 2.8, fill: { color: RP.BG } });
      this.t(s, rpClip(p.head, 10), { x: cx, y: y + 0.35, w: cw, h: 1.3, fontSize: 44, bold: true, color: SP.ACCENT, align: "center", valign: "middle", fit: "shrink" });
      this.t(s, rpClip(p.text, 40), { x: cx + 0.25, y: y + 1.75, w: cw - 0.5, h: 0.85, fontSize: 15, color: RP.BODY, align: "center", fit: "shrink" });
    });
  }

  // 표: 남색 머리행 + 줄무늬, 넘치면 글자를 줄인다 (최대 10행)
  table(s, head, rows) {
    if (!head.length) return;
    const all = [head, ...rows.slice(0, 10)].map((r) => head.map((_, i) => String(r[i] ?? "")));
    let pt = head.length <= 3 ? 16 : head.length <= 5 ? 14 : 12;
    const need = head.map((_, i) => Math.min(30, Math.max(4, ...all.map((r) => spUnits(r[i])))));
    const total = need.reduce((a, b) => a + b, 0);
    const colW = need.map((u) => (RP.CW * u) / total);
    const height = (p) => all.reduce((h, r) => h + Math.max(...r.map((c, i) => spLines(c, colW[i] - 0.3, p))) * spLineH(p) + 0.24, 0);
    while (pt > 10 && height(pt) > RP.H) pt--;
    const body = all.map((r, ri) => r.map((c) => ({
      text: c,
      options: ri === 0 ? { bold: true, color: "FFFFFF", fill: { color: SP.NAVY } } : { fill: { color: ri % 2 ? "FFFFFF" : RP.BG } },
    })));
    s.addTable(body, { x: RP.X, y: RP.TOP, w: RP.CW, colW, fontFace: SP.FONT, fontSize: pt, color: RP.INK, border: { type: "solid", color: RP.LINE, pt: 0.75 }, margin: [0.12, 0.14, 0.12, 0.14], valign: "middle" });
  }

  // 흐름도(Mermaid → 그림). 설명 요점이 있으면 오른쪽에 둔다
  async diagram(s, code, pts) {
    const side = pts.length ? 3.9 : 0;
    const maxW = RP.CW - (side ? side + 0.3 : 0), maxH = RP.H;
    try {
      const img = await spMermaid(code);
      let w = Math.min(maxW, (img.w / 96) * 1.8), h = (w * img.h) / img.w;
      if (h > maxH) { h = maxH; w = (h * img.w) / img.h; }
      s.addImage({ data: img.data, x: RP.X + (maxW - w) / 2, y: RP.TOP + (maxH - h) / 2, w, h });
    } catch {
      this.t(s, "흐름도를 그림으로 만들지 못했습니다. 발표자 노트를 참고해 주세요.", { x: RP.X, y: RP.TOP, w: maxW, h: 0.5, fontSize: 13, color: SP.MUTED });
    }
    if (side) this.points(s, pts.slice(0, 3), RP.X + maxW + 0.3, side);
  }
}

async function downloadReportPptx(t, stage, o) {
  const PptxGenJS = await loadPptx();
  const pptx = new PptxGenJS();
  pptx.layout = "LAYOUT_WIDE";
  const stageName = status.team[stage].name;
  const st = t.stages[stage];
  pptx.title = `${t.title} - ${stageName} 보고`;
  const deck = new ReportDeck(pptx, `${t.title} · ${stageName}`);

  // 표지
  const cover = pptx.addSlide();
  cover.background = { color: SP.NAVY };
  deck.rect(cover, { x: 0.8, y: 1.55, w: 2.8, h: 0.42, fill: { color: SP.ACCENT } });
  deck.t(cover, `${stageName} 보고`, { x: 0.8, y: 1.55, w: 2.8, h: 0.42, fontSize: 13, bold: true, color: "FFFFFF", align: "center", valign: "middle" });
  deck.t(cover, t.title, { x: 0.8, y: 2.2, w: 11.7, h: 1.2, fontSize: 36, bold: true, color: "FFFFFF", valign: "middle", fit: "shrink" });
  if (o.headline) {
    deck.rect(cover, { x: 0.8, y: 3.75, w: 0.08, h: 0.9, fill: { color: "7FA7F5" } });
    deck.t(cover, rpClip(o.headline, 90), { x: 1.1, y: 3.75, w: 11.4, h: 0.9, fontSize: 19, color: "E6EDF6", valign: "middle", fit: "shrink" });
  }
  const pl = st.review ? ` · PL 검토 ${st.review.decision === "approve" ? "승인 권고" : "수정 권고"}` : "";
  deck.t(cover, `요청 ${t.id} · ${STAGE_STATUS[st.status] ?? st.status}${pl} · ${new Date().toLocaleDateString("ko-KR")}`, { x: 0.8, y: 6.4, w: 11.7, h: 0.4, fontSize: 12, color: "C9D6E8" });
  if (st.review) cover.addNotes(`PL 1차 검토 — ${st.review.summary}`);

  // 한눈에 보기
  const summary = (o.summary ?? []).filter(Boolean).slice(0, 5);
  if (summary.length) {
    const s = deck.frame("한눈에 보기", o.headline);
    const rh = Math.min(1.05, RP.H / summary.length);
    summary.forEach((line, i) => {
      const y = RP.TOP + i * rh;
      deck.t(s, String(i + 1).padStart(2, "0"), { x: RP.X, y, w: 0.9, h: rh, fontSize: 24, bold: true, color: SP.ACCENT, valign: "middle" });
      deck.t(s, rpClip(line, 70), { x: RP.X + 1.0, y, w: RP.CW - 1.0, h: rh, fontSize: 19, valign: "middle", fit: "shrink" });
      if (i < summary.length - 1) s.addShape(pptx.ShapeType.line, { x: RP.X + 1.0, y: y + rh, w: RP.CW - 1.0, h: 0, line: { color: RP.LINE, width: 0.75 } });
    });
  }

  // 본문: 한 장 한 메시지
  for (const sl of o.slides ?? []) {
    const s = deck.frame(sl.title, sl.message, sl.notes);
    const pts = (sl.points ?? []).filter((p) => p?.head || p?.text);
    if (sl.layout === "table" && sl.table?.head?.length) deck.table(s, sl.table.head, sl.table.rows ?? []);
    else if (sl.layout === "diagram" && sl.diagram?.trim()) await deck.diagram(s, sl.diagram, pts);
    else if (sl.layout === "steps") deck.steps(s, pts);
    else if (sl.layout === "metrics" && pts.length) deck.metrics(s, pts);
    else if (pts.length) deck.points(s, pts);
    else if (sl.table?.head?.length) deck.table(s, sl.table.head, sl.table.rows ?? []);
  }

  // 확인 필요 · 다음 단계
  const issues = (o.issues ?? []).filter((p) => p?.head || p?.text).slice(0, 4);
  if (issues.length || o.next) {
    const s = deck.frame(issues.length ? "확인 필요 · 다음 단계" : "다음 단계", issues.length ? `결정·확인이 필요한 사항 ${issues.length}건` : "");
    const lw = o.next && issues.length ? 7.6 : RP.CW;
    const ih = Math.min(1.1, (RP.H - 0.2 * (issues.length - 1)) / Math.max(1, issues.length));
    issues.forEach((p, i) => {
      const y = RP.TOP + i * (ih + 0.2);
      deck.rect(s, { x: RP.X, y, w: lw, h: ih, fill: { color: RP.WARN_BG } });
      deck.rect(s, { x: RP.X, y, w: 0.07, h: ih, fill: { color: RP.WARN } });
      deck.t(s, [
        { text: rpClip(p.head, 30), options: { fontSize: 16, bold: true, color: RP.WARN, breakLine: true } },
        { text: rpClip(p.text, 90), options: { fontSize: 13, color: RP.BODY } },
      ], { x: RP.X + 0.3, y: y + 0.08, w: lw - 0.5, h: ih - 0.16, valign: "middle", paraSpaceAfter: 3, fit: "shrink" });
    });
    if (o.next) {
      const x = issues.length ? RP.X + lw + 0.35 : RP.X, w = issues.length ? RP.CW - lw - 0.35 : RP.CW;
      deck.rect(s, { x, y: RP.TOP, w, h: 3.4, fill: { color: SP.NAVY } });
      deck.t(s, "다음 단계", { x: x + 0.35, y: RP.TOP + 0.3, w: w - 0.7, h: 0.4, fontSize: 13, bold: true, color: "9FB4D9" });
      deck.t(s, rpClip(o.next, 160), { x: x + 0.35, y: RP.TOP + 0.85, w: w - 0.7, h: 2.3, fontSize: 17, color: "FFFFFF", lineSpacingMultiple: 1.25, fit: "shrink" });
    }
  }

  await pptx.writeFile({ fileName: `${t.id}(${t.title})_${stageName}_보고_${new Date().toISOString().slice(0, 10)}.pptx`.replace(/[\\/:*?"<>|]/g, "_") });
}
