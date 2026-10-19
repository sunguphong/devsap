// 개발표준 핸드북: standards/handbook.md 를 문서 모양 그대로 보여주고, 그 화면에서 바로 고친다.
// 설계·개발·테스트 에이전트가 이 문서를 따른다. 저장할 때는 화면 내용을 다시 마크다운으로 바꿔 보관한다.
// 지원하는 마크다운: # 제목(1~4단계), > 인용, - 목록, | 표 |, 문단, **굵게**, `코드`

// ---------- 마크다운 → 블록 ----------
function hbParse(text) {
  const blocks = [];
  for (const line of text.replace(/\r\n/g, "\n").split("\n")) {
    const last = blocks[blocks.length - 1];
    const h = line.match(/^(#{1,4})\s+(.*)/);
    const q = line.match(/^>\s?(.*)/);
    const li = line.match(/^\s*[-*]\s+(.*)/);
    const row = /^\s*\|.*\|\s*$/.test(line);
    if (h) blocks.push({ type: "h", level: h[1].length, text: h[2] });
    else if (q) last?.type === "quote" ? last.lines.push(q[1]) : blocks.push({ type: "quote", lines: [q[1]] });
    else if (li) last?.type === "list" ? last.items.push(li[1]) : blocks.push({ type: "list", items: [li[1]] });
    else if (row) {
      if (/^\s*\|[\s:|-]+\|\s*$/.test(line)) continue; // 구분선
      const cells = line.trim().slice(1, -1).split("|").map((c) => c.trim());
      last?.type === "table" ? last.rows.push(cells) : blocks.push({ type: "table", head: cells, rows: [] });
    } else if (line.trim()) blocks.push({ type: "p", text: line.trim() });
  }
  return blocks;
}

// 인라인 마크다운 ↔ HTML
const hbInline = (s) => esc(s).replace(/\*\*(.+?)\*\*/g, "<b>$1</b>").replace(/`([^`]+)`/g, "<code>$1</code>");
function hbText(el) {
  let out = "";
  for (const n of el.childNodes) {
    if (n.nodeType === 3) out += n.textContent;
    else if (n.nodeName === "BR") out += " ";
    else if (["B", "STRONG"].includes(n.nodeName)) out += `**${hbText(n)}**`;
    else if (n.nodeName === "CODE") out += `\`${n.textContent}\``;
    else out += hbText(n);
  }
  return out.replace(/ /g, " ").replace(/\s+/g, " ").replace(/\*\*\s*\*\*/g, "").trim();
}

// ---------- 블록 → 화면 ----------
const ed = (edit) => (edit ? ' contenteditable="true"' : "");
function hbRender(blocks, edit) {
  return blocks.map((b) => {
    if (b.type === "h") return `<h${b.level + 1} class="hb-h" data-level="${b.level}"${ed(edit)}>${hbInline(b.text)}</h${b.level + 1}>`;
    if (b.type === "quote") return `<blockquote class="hb-quote">${b.lines.map((l) => `<p${ed(edit)}>${hbInline(l)}</p>`).join("")}</blockquote>`;
    if (b.type === "list") return `<ul class="hb-list"${ed(edit)}>${b.items.map((i) => `<li>${hbInline(i)}</li>`).join("")}</ul>`;
    if (b.type === "p") return `<p class="hb-p"${ed(edit)}>${hbInline(b.text)}</p>`;
    const cell = (c, tag) => `<${tag}${ed(edit)}>${hbInline(c)}</${tag}>`;
    const del = edit ? `<td class="hb-ctl"><button class="hb-del" title="이 행 삭제">×</button></td>` : "";
    return `<div class="hb-table"><table>
      <tr>${b.head.map((c) => cell(c, "th")).join("")}${edit ? "<th class=\"hb-ctl\"></th>" : ""}</tr>
      ${b.rows.map((r) => `<tr>${b.head.map((_, i) => cell(r[i] ?? "", "td")).join("")}${del}</tr>`).join("")}
    </table>${edit ? `<button class="hb-addrow">+ 행 추가</button>` : ""}</div>`;
  }).join("");
}

// ---------- 화면 → 마크다운 ----------
function hbSerialize(root) {
  const out = [];
  for (const el of root.children) {
    if (el.classList.contains("hb-h")) out.push(`${"#".repeat(Number(el.dataset.level))} ${hbText(el)}`, "");
    else if (el.classList.contains("hb-quote")) out.push(...[...el.querySelectorAll("p")].map((p) => `> ${hbText(p)}`), "");
    else if (el.classList.contains("hb-list")) out.push(...[...el.querySelectorAll("li")].map(hbText).filter(Boolean).map((t) => `- ${t}`), "");
    else if (el.classList.contains("hb-p")) { const t = hbText(el); if (t) out.push(t, ""); }
    else if (el.classList.contains("hb-table")) {
      const rows = [...el.querySelectorAll("tr")].map((tr) => [...tr.children].filter((c) => !c.classList.contains("hb-ctl")).map((c) => hbText(c).replace(/\|/g, "/")));
      const [head, ...body] = rows;
      out.push(`| ${head.join(" | ")} |`, `|${head.map(() => "---").join("|")}|`, ...body.filter((r) => r.some(Boolean)).map((r) => `| ${r.join(" | ")} |`), "");
    }
  }
  return out.join("\n").replace(/\n{3,}/g, "\n\n").trim() + "\n";
}

// ---------- 페이지 ----------
let hbGuard = null;
async function standardsView() {
  const h = await api("/api/standards");
  $("#stdBody").innerHTML = `<article class="card handbook">
    <div class="row" style="justify-content:space-between">
      <span class="sub">설계·개발·테스트 담당이 작업 전에 읽고 따릅니다 · 최종 수정 ${h.updatedAt ? new Date(h.updatedAt).toLocaleString() : "-"}${h.versions ? ` · 이전 버전 ${h.versions}개 보관` : ""}</span>
      <span class="row"><button id="sPptx">⬇️ PPTX 내려받기</button><a href="#/standards/edit"><button>✏️ 편집</button></a></span>
    </div>
    <div class="hb">${h.markdown ? hbRender(hbParse(h.markdown), false) : `<p class="sub">아직 핸드북이 없습니다. 편집을 눌러 작성하세요.</p>`}</div>
  </article>`;
  $("#sPptx").addEventListener("click", async (e) => {
    const b = e.currentTarget;
    b.disabled = true;
    b.textContent = "만드는 중…";
    try { await downloadPptx(); } catch (err) { alert(err.message ?? err); }
    finally { b.disabled = false; b.textContent = "⬇️ PPTX 내려받기"; }
  });
  $("#stdBody").scrollTop = 0;
}

async function standardsEdit() {
  const h = await api("/api/standards");
  $("#stdBody").innerHTML = `<article class="card handbook editing">
    <div class="hb-bar">
      <span class="sub">글자·표 칸을 눌러 바로 고치세요. 굵게: 글자 선택 후 Ctrl+B · 목록 줄 추가: 끝에서 Enter</span>
      <span class="row"><button id="sAddSec">+ 항목 추가</button><a href="#/standards"><button>취소</button></a><button class="primary" id="sSave">저장</button></span>
    </div>
    <div class="hb" id="hbEdit">${hbRender(hbParse(h.markdown || "# 개발표준 Handbook\n"), true)}</div>
  </article>`;
  const root = $("#hbEdit");
  let dirty = false;
  root.addEventListener("input", () => (dirty = true));
  // 붙여넣기는 서식 없이 글자만
  root.addEventListener("paste", (e) => {
    e.preventDefault();
    document.execCommand("insertText", false, e.clipboardData.getData("text/plain").replace(/\s*\n\s*/g, " "));
  });
  // 제목·문단·표 칸에서 Enter는 줄바꿈 대신 무시 (한 칸 = 한 줄)
  root.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && !e.target.closest(".hb-list")) e.preventDefault();
  });
  root.addEventListener("click", (e) => {
    const b = e.target.closest("button");
    if (!b) return;
    dirty = true;
    if (b.classList.contains("hb-del")) b.closest("tr").remove();
    if (b.classList.contains("hb-addrow")) {
      const table = b.previousElementSibling;
      const cols = table.rows[0].cells.length - 1;
      const tr = table.insertRow();
      tr.innerHTML = `${'<td contenteditable="true"></td>'.repeat(cols)}<td class="hb-ctl"><button class="hb-del" title="이 행 삭제">×</button></td>`;
      tr.cells[0].focus();
    }
  });
  // 새 명명규칙 항목: 제목 + position/usage 표 + 예시
  $("#sAddSec").addEventListener("click", () => {
    dirty = true;
    const wrap = document.createElement("div");
    wrap.innerHTML = hbRender(hbParse("### 새 항목\n| position | usage |\n|---|---|\n| 1 | 'Z' |\n\n예: `ZXXX0001`"), true);
    const nodes = [...wrap.children];
    root.append(...nodes);
    nodes[0].focus();
    document.getSelection().selectAllChildren(nodes[0]);
    nodes[0].scrollIntoView({ block: "center" });
  });
  $("#sSave").addEventListener("click", async () => {
    try {
      await api("/api/standards", { method: "PUT", body: { markdown: hbSerialize(root) } });
      dirty = false;
      window.onbeforeunload = null;
      location.hash = "#/standards";
    } catch (e) { alert(e.message); }
  });
  // 저장하지 않고 다른 화면으로 가려 하면 확인한다 (wiki.js route()가 호출)
  hbGuard = (hash) => {
    if (!dirty || hash.startsWith("/standards/edit")) return true;
    if (confirm("저장하지 않은 수정이 있습니다. 버리고 나갈까요?")) { hbGuard = null; return true; }
    history.replaceState(null, "", "#/standards/edit");
    return false;
  };
  window.onbeforeunload = () => (dirty ? "" : undefined);
}

// ---------- PPTX 내려받기 ----------
// pptxgenjs(CDN)로 브라우저에서 만든다. 표지 1장 + 장(##)마다 명명규칙 카드(###: 제목·표·예시)를 한 장에 6개씩 + 목록·문단만 있는 장은 글머리표 슬라이드
let pptxLib = null;
const loadPptx = () => (pptxLib ??= new Promise((ok, fail) => {
  const s = document.createElement("script");
  s.src = "https://cdn.jsdelivr.net/npm/pptxgenjs@3.12.0/dist/pptxgen.bundle.js";
  s.onload = () => ok(window.PptxGenJS);
  s.onerror = () => { pptxLib = null; fail(new Error("PPTX 라이브러리를 불러오지 못했습니다. 인터넷 연결을 확인해 주세요.")); };
  document.head.append(s);
}));
const plain = (s) => String(s ?? "").replace(/\*\*(.+?)\*\*/g, "$1").replace(/`([^`]+)`/g, "$1");

// 블록을 표지·장·카드 구조로 묶는다
function hbOutline(blocks) {
  const doc = { title: "개발표준 Handbook", notes: [], chapters: [] };
  let ch = null, card = null;
  for (const b of blocks) {
    if (b.type === "h" && b.level === 1) doc.title = plain(b.text);
    else if (b.type === "h" && b.level === 2) { ch = { title: plain(b.text), cards: [], bullets: [] }; doc.chapters.push(ch); card = null; }
    else if (b.type === "h" && b.level >= 3) {
      if (!ch) { ch = { title: "", cards: [], bullets: [] }; doc.chapters.push(ch); }
      card = { title: plain(b.text), head: null, rows: [], notes: [] };
      ch.cards.push(card);
    } else if (b.type === "quote" && !ch) doc.notes.push(...b.lines.map(plain));
    else if (b.type === "table" && card) { card.head = b.head.map(plain); card.rows = b.rows.map((r) => r.map(plain)); }
    else if (card && (b.type === "p" || b.type === "quote")) card.notes.push(...(b.lines ?? [b.text]).map(plain));
    else if (ch) ch.bullets.push(...(b.items ?? b.lines ?? [b.text]).map(plain));
  }
  return doc;
}

async function downloadPptx() {
  const PptxGenJS = await loadPptx();
  const doc = hbOutline(hbParse((await api("/api/standards")).markdown));
  const pptx = new PptxGenJS();
  pptx.layout = "LAYOUT_WIDE"; // 13.33 x 7.5 in
  pptx.title = doc.title;
  const FONT = "Malgun Gothic", NAVY = "1F3A5F", LINE = "9AA7B8", HEAD = "DCE6F2", MUTED = "5B6577";
  const header = (slide, text, page) => {
    slide.addShape(pptx.ShapeType.rect, { x: 0, y: 0, w: 13.33, h: 0.75, fill: { color: NAVY } });
    slide.addText(text, { x: 0.4, y: 0.1, w: 10.5, h: 0.55, fontFace: FONT, fontSize: 20, bold: true, color: "FFFFFF" });
    slide.addText(doc.title, { x: 9.0, y: 0.1, w: 4.0, h: 0.55, fontFace: FONT, fontSize: 10, color: "C9D6E8", align: "right" });
    if (page) slide.addText(page, { x: 12.0, y: 7.1, w: 1.0, h: 0.3, fontFace: FONT, fontSize: 9, color: MUTED, align: "right" });
  };

  // 표지
  const cover = pptx.addSlide();
  cover.background = { color: NAVY };
  cover.addText(doc.title, { x: 0.8, y: 2.4, w: 11.7, h: 1.2, fontFace: FONT, fontSize: 36, bold: true, color: "FFFFFF" });
  cover.addText(`기준일 ${new Date().toLocaleDateString("ko-KR")}`, { x: 0.8, y: 3.6, w: 11.7, h: 0.5, fontFace: FONT, fontSize: 14, color: "C9D6E8" });
  if (doc.notes.length) cover.addText(doc.notes.map((t) => ({ text: t, options: { bullet: true, breakLine: true } })), { x: 0.8, y: 4.6, w: 11.7, h: 1.8, fontFace: FONT, fontSize: 12, color: "E6EDF6", valign: "top" });

  let page = 1;
  for (const ch of doc.chapters) {
    // 카드: 한 장에 3열 x 2행
    const perSlide = 6, W = 4.05, H = 2.95, GX = 0.25, X0 = 0.35, Y0 = 0.95;
    const pages = Math.ceil(ch.cards.length / perSlide);
    for (let p = 0; p < pages; p++) {
      const slide = pptx.addSlide();
      header(slide, `${ch.title}${pages > 1 ? ` (${p + 1}/${pages})` : ""}`, String(++page));
      ch.cards.slice(p * perSlide, (p + 1) * perSlide).forEach((c, i) => {
        const x = X0 + (i % 3) * (W + GX), y = Y0 + Math.floor(i / 3) * (H + 0.15);
        slide.addShape(pptx.ShapeType.rect, { x, y, w: W, h: H, line: { color: LINE, width: 0.75 }, fill: { color: "FFFFFF" } });
        slide.addText(c.title, { x, y, w: W, h: 0.38, fontFace: FONT, fontSize: 12, bold: true, color: NAVY, fill: { color: HEAD }, align: "center" });
        if (c.head) {
          const rows = [c.head.map((t) => ({ text: t, options: { bold: true, fill: { color: "F2F5F9" } } })), ...c.rows];
          slide.addTable(rows, { x: x + 0.1, y: y + 0.48, w: W - 0.2, colW: [0.9, W - 1.1], fontFace: FONT, fontSize: 9.5, border: { type: "solid", color: "C8D1DC", pt: 0.5 }, rowH: 0.24, margin: 0.03, valign: "middle" });
        }
        if (c.notes.length) slide.addText(c.notes.join("\n"), { x: x + 0.1, y: y + H - 0.45, w: W - 0.2, h: 0.38, fontFace: FONT, fontSize: 10, bold: true, color: "B03A2E", valign: "bottom" });
      });
    }
    // 목록·문단 (예: 적용 메모)
    for (let k = 0; k < ch.bullets.length; k += 8) {
      const slide = pptx.addSlide();
      header(slide, ch.title || doc.title, String(++page));
      slide.addText(ch.bullets.slice(k, k + 8).map((t) => ({ text: t, options: { bullet: true, breakLine: true, paraSpaceAfter: 8 } })), { x: 0.6, y: 1.1, w: 12.1, h: 5.9, fontFace: FONT, fontSize: 15, color: "1D2330", valign: "top" });
    }
  }
  await pptx.writeFile({ fileName: `${doc.title.replace(/[\/:*?"<>|]/g, "_")}_${new Date().toISOString().slice(0, 10)}.pptx` });
}
