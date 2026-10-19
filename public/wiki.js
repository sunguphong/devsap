// 지식 위키: 개발 요청 산출물(자동)과 직접 작성한 문서를 검색·열람·편집한다
const CATS = { doc: "📝 작성 문서", req: "📦 개발 요청", table: "🗄️ SAP 테이블", obj: "🧩 ABAP 오브젝트" };
let wikiPages = [];

const pageHref = (id) => `#/wiki/page/${encodeURIComponent(id)}`;
const targetId = (t) => (/^(doc|req|table|obj):/.test(t) ? t : `doc:${t}`);

// [[대상|표시명]] 링크, 알려진 SAP 테이블·필드 자동 링크를 붙여 렌더링한다
function wikiMd(markdown) {
  const tokened = markdown.replace(/\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/g, (_, t, label) => `⟦${encodeURIComponent(t.trim())}¦${label ?? t.trim()}⟧`);
  let html = md(tokened).replace(/⟦([^¦⟧]+)¦([^⟧]*)⟧/g, (_, t, label) => {
    const id = targetId(decodeURIComponent(t));
    const exists = wikiPages.some((p) => p.id === id);
    return exists
      ? `<a href="${pageHref(id)}">${label}</a>`
      : `<a class="missing" href="#/wiki/new/${encodeURIComponent(id.replace(/^doc:/, ""))}" title="아직 없는 문서 — 눌러서 작성">${label}</a>`;
  });
  const tables = new Set(wikiPages.filter((p) => p.category === "table").map((p) => p.title));
  return html
    .split(/(<pre[^>]*>[\s\S]*?<\/pre>|<a [^>]*>[\s\S]*?<\/a>)/)
    .map((part, i) => (i % 2 ? part : part.replace(/\b([A-Z][A-Z0-9_]{2,15})(-[A-Z][A-Z0-9_]{1,29})?\b/g, (m, t) =>
      tables.has(t) ? `<a href="${pageHref(`table:${t}`)}">${m}</a>` : m)))
    .join("");
}

const highlight = (text, terms) => {
  let s = esc(text);
  for (const t of terms) if (t) s = s.replace(new RegExp(esc(t).replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "gi"), (m) => `<mark>${m}</mark>`);
  return s;
};

async function loadWikiPages() {
  wikiPages = await api("/api/wiki/pages");
  $("#wikiNav").innerHTML = Object.entries(CATS).map(([c, label]) => {
    const list = wikiPages.filter((p) => p.category === c).sort((a, b) => a.title.localeCompare(b.title, "ko"));
    return `<details ${c !== "obj" ? "open" : ""}><summary>${label} <span class="sub">${list.length}</span></summary><ul>${
      list.map((p) => `<li><a href="${pageHref(p.id)}">${esc(p.title)}</a></li>`).join("") || `<li class="sub">없음</li>`}</ul></details>`;
  }).join("");
}

function wikiHome() {
  const recent = [...wikiPages].sort((a, b) => b.updatedAt.localeCompare(a.updatedAt)).slice(0, 12);
  $("#wikiBody").innerHTML = `<article class="card">
    <h2>📚 지식 위키</h2>
    <p class="sub" style="margin:4px 0 12px">개발 요청을 진행하며 쌓인 요구사항·설계·소스·SAP 테이블 정보와 직접 작성한 문서를 찾아볼 수 있습니다.
      개발 요청 문서는 산출물에서 자동으로 만들어지고, 작성 문서는 누구나 고칠 수 있습니다.</p>
    <div class="cats">${Object.entries(CATS).map(([c, l]) => `<div class="cat"><b>${wikiPages.filter((p) => p.category === c).length}</b><span>${l}</span></div>`).join("")}</div>
    <h3>최근 바뀐 문서</h3>
    <ul>${recent.map((p) => `<li><a href="${pageHref(p.id)}">${esc(p.title)}</a> <span class="sub">${CATS[p.category]} · ${new Date(p.updatedAt).toLocaleString()}</span></li>`).join("")}</ul>
    <h3>문서 작성 방법</h3>
    <p class="sub">마크다운으로 씁니다. <code>[[문서 제목]]</code> 으로 다른 문서에 링크하고, <code>[[table:MARC|플랜트 자재]]</code> 처럼 자동 문서에도 링크할 수 있습니다. MARC-XCHPF 같은 테이블·필드명은 자동으로 링크됩니다.</p>
  </article>`;
}

async function wikiSearch(q) {
  $("#wikiQ").value = q;
  const terms = q.toLowerCase().split(/\s+/).filter(Boolean);
  const results = await api(`/api/wiki/search?q=${encodeURIComponent(q)}`);
  const exact = wikiPages.find((p) => p.title.toLowerCase() === q.toLowerCase().trim());
  $("#wikiBody").innerHTML = `<article class="card">
    <h2>'${esc(q)}' 검색 결과 <span class="sub">${results.length}건</span></h2>
    ${exact ? `<p>정확히 일치하는 문서: <a href="${pageHref(exact.id)}"><b>${esc(exact.title)}</b></a></p>` : `<p class="sub">'${esc(q)}' 문서가 없습니다. <a href="#/wiki/new/${encodeURIComponent(q)}">새 문서로 작성하기</a></p>`}
    <ol class="results">${results.map((r) => `<li>
      <a href="${pageHref(r.id)}${r.section ? `?s=${encodeURIComponent(r.section)}` : ""}"><b>${highlight(r.title, terms)}</b>${r.section ? ` › ${highlight(r.section, terms)}` : ""}</a>
      <span class="sub">${CATS[r.category]}</span><div class="snip">${highlight(r.snippet, terms)}</div></li>`).join("")}</ol>
  </article>`;
}

async function wikiPage(id, section) {
  let p;
  try { p = await api(`/api/wiki/page?id=${encodeURIComponent(id)}`); } catch (e) {
    $("#wikiBody").innerHTML = `<article class="card"><h2>${esc(id)}</h2><p>${esc(e.message)}</p></article>`;
    return;
  }
  $("#wikiBody").innerHTML = `<article class="card wikipage">
    <div class="row" style="justify-content:space-between"><span class="sub">${CATS[p.category]} · 최종 수정 ${new Date(p.updatedAt).toLocaleString()}</span>
      <span class="row">${p.category === "req" ? `<a href="#/" data-ticket="${esc(p.id.slice(4))}">보드에서 열기</a>` : ""}${p.editable ? `<a href="#/wiki/edit/${encodeURIComponent(p.id)}"><button>✏️ 편집</button></a>` : `<span class="sub">산출물에서 자동 생성</span>`}</span></div>
    <div class="md">${wikiMd(p.markdown)}</div>
    ${p.backlinks.length ? `<hr><div class="sub">이 문서를 가리키는 문서: ${p.backlinks.map((b) => `<a href="${pageHref(b.id)}">${esc(b.title)}</a>`).join(", ")}</div>` : ""}
  </article>`;
  $("#wikiBody [data-ticket]")?.addEventListener("click", () => select($("#wikiBody [data-ticket]").dataset.ticket));
  if (section) [...$("#wikiBody").querySelectorAll("h3")].find((h) => h.textContent.trim() === section.replace(/[`*]/g, "").trim())?.scrollIntoView();
  else $("#wikiBody").scrollTop = 0;
}

async function wikiEdit(id, newTitle) {
  const p = id ? await api(`/api/wiki/page?id=${encodeURIComponent(id)}`) : { title: newTitle ?? "", markdown: newTitle ? `# ${newTitle}\n\n` : "" };
  $("#wikiBody").innerHTML = `<article class="card">
    <h2>${id ? "문서 편집" : "새 문서"}</h2>
    <label>제목<input id="wTitle" value="${esc(p.title)}" placeholder="예: 배치관리 자재 판정 기준" /></label>
    <div class="grid2 editor">
      <label>내용 (마크다운)<textarea id="wText" rows="24">${esc(p.markdown)}</textarea></label>
      <div><div class="k sub">미리보기</div><div class="md preview" id="wPrev"></div></div>
    </div>
    <div class="row end"><a href="${id ? pageHref(id) : "#/wiki"}"><button>취소</button></a><button class="primary" id="wSave">저장</button></div>
  </article>`;
  const prev = () => ($("#wPrev").innerHTML = wikiMd($("#wText").value));
  $("#wText").addEventListener("input", prev);
  prev();
  $("#wSave").addEventListener("click", async () => {
    try {
      const saved = await api("/api/wiki/page", { method: "PUT", body: { id, title: $("#wTitle").value, markdown: $("#wText").value } });
      await loadWikiPages();
      location.hash = pageHref(saved.id);
    } catch (e) { alert(e.message); }
  });
}

async function route() {
  const h = location.hash.slice(1) || "/";
  if (hbGuard && !hbGuard(h)) return;
  const onWiki = h.startsWith("/wiki");
  const onStd = h.startsWith("/standards");
  const onTrash = h.startsWith("/trash");
  $("#board").hidden = onWiki || onStd || onTrash;
  $("#wiki").hidden = !onWiki;
  $("#standards").hidden = !onStd;
  $("#trash").hidden = !onTrash;
  $("#navBoard").classList.toggle("on", !onWiki && !onStd && !onTrash);
  $("#navWiki").classList.toggle("on", onWiki);
  $("#navStd").classList.toggle("on", onStd);
  $("#navTrash").classList.toggle("on", onTrash);
  if (onTrash) return trashView();
  if (onStd) return h.startsWith("/standards/edit") ? standardsEdit() : standardsView();
  if (!onWiki) return;
  await loadWikiPages();
  const [, , kind, arg = ""] = h.split("/");
  const [raw, qs] = arg.split("?");
  const val = decodeURIComponent(raw);
  if (kind === "search") return wikiSearch(val);
  if (kind === "page") return wikiPage(val, qs ? decodeURIComponent(qs.replace(/^s=/, "")) : null);
  if (kind === "edit") return wikiEdit(val);
  if (kind === "new") return wikiEdit(null, val);
  wikiHome();
}

$("#wikiSearch").addEventListener("submit", (e) => {
  e.preventDefault();
  const q = $("#wikiQ").value.trim();
  if (q) location.hash = `#/wiki/search/${encodeURIComponent(q)}`;
});
$("#wikiNew").addEventListener("click", () => (location.hash = "#/wiki/new/"));
window.addEventListener("hashchange", route);
route();
