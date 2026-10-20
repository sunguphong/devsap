const $ = (s, el = document) => el.querySelector(s);
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

const STAGES = ["analysis", "design", "development", "test", "deploy"];
const WORK_STAGES = STAGES.slice(0, 4);
const STATUS = { in_progress: "Claude Code 작업", awaiting_review: "팀장 승인 대기", awaiting_deploy: "반영 승인 대기", deploying: "개발계 반영 중", done: "완료", failed: "반영 실패" };
const CR_STATUS = { analyzing: "영향분석 중", proposed: "결정 대기", applied: "반영", deferred: "다음 차수", rejected: "반려", failed: "분석 실패" };
const EFFORT = { small: "작음", medium: "보통", large: "큼" };
const STAGE_STATUS = { pending: "대기", running: "작업 중", review: "팀장 승인 대기", approved: "승인", failed: "실패" };

let status = null;
let selectedId = null;
let selectedStage = null;
let lastUpdated = null;
let pollTimer = null;

async function api(path, opts = {}) {
  const res = await fetch(path, { headers: { "Content-Type": "application/json" }, ...opts, body: opts.body && JSON.stringify(opts.body) });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || res.statusText);
  return data;
}

const ACCEPT = ".png,.jpg,.jpeg,.gif,.webp,.pdf,.docx,.xlsx,.pptx,.txt,.md,.csv,.json,.xml,.abap,.sql";
let crFiles = []; // 요구사항 변경 등록 전에 고른 첨부 (화면을 다시 그려도 유지)

// 클립보드의 캡처 이미지를 이름 붙인 파일로 바꾼다
function pastedImages(e) {
  const imgs = [...(e.clipboardData?.files ?? [])].filter((f) => f.type.startsWith("image/"));
  const stamp = new Date().toLocaleTimeString().replace(/:/g, "");
  return imgs.map((f, i) => new File([f], `붙여넣은 화면 ${stamp}${imgs.length > 1 ? `-${i + 1}` : ""}.${f.type.split("/")[1] || "png"}`, { type: f.type }));
}

// cr을 주면 그 요구사항 변경의 첨부로 올린다
async function upload(id, file, cr) {
  const res = await fetch(`/api/tickets/${id}${cr ? `/changes/${cr}` : ""}/attachments?name=${encodeURIComponent(file.name)}`, { method: "POST", headers: { "Content-Type": "application/octet-stream" }, body: file });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || (res.status === 413 ? "파일이 너무 큽니다." : res.statusText));
  return data;
}
// 구글시트 링크를 서버가 xlsx 사본으로 받아 첨부로 둔다
const sheetLinks = (text) => [...new Set(String(text ?? "").match(/https:\/\/docs\.google\.com\/spreadsheets\/d\/[^\s<>"')]+/g) ?? [])];
const importSheet = (id, url) => api(`/api/tickets/${id}/gsheet`, { method: "POST", body: { url } });
const fmtSize = (n) => n < 1024 ? `${n}B` : n < 1048576 ? `${(n / 1024).toFixed(0)}KB` : `${(n / 1048576).toFixed(1)}MB`;

async function loadStatus() {
  status = await api("/api/status");
  $("#env").innerHTML = `
    <span class="pill on">작업: Claude Code 서브에이전트</span>
    ${status.systems.length ? `<label class="pill ${status.sap ? "on" : "off"}" title="새 요청의 기본 대상 시스템, 접속 테스트 대상 (요청별 시스템은 등록할 때 고릅니다)">기본 SAP
      <select id="sapSys" class="sys">${status.systems.map((s) => `<option value="${esc(s.name)}" ${s.name === status.system ? "selected" : ""}>${esc(s.name)} · ${esc(s.url.replace(/^https?:\/\//, ""))} / ${esc(s.client)}</option>`).join("")}</select></label>`
      : `<span class="pill ${status.sap ? "on" : "off"}">${status.sap ? `SAP ${esc(status.sap.url)} / ${esc(status.sap.client)}` : "SAP 미연결 (반영 시뮬레이션)"}</span>`}
    ${status.sap ? `<button id="sapTest">접속 테스트</button>` : ""}`;
  $("#sapTest")?.addEventListener("click", async () => {
    try { alert((await api("/api/sap/test", { method: "POST" })).message); } catch (e) { alert(e.message); }
  });
  $("#sapSys")?.addEventListener("change", async (e) => {
    try {
      await api("/api/sap/system", { method: "PUT", body: { name: e.target.value } });
      await loadStatus();
    } catch (err) { alert(err.message); await loadStatus(); }
  });
}

async function loadList() {
  const list = await api("/api/tickets");
  $("#tickets").innerHTML = list.length
    ? list.map((t) => `<li data-id="${t.id}" class="${t.id === selectedId ? "sel" : ""}">
        <div class="t">${esc(t.title)}<button class="small del" data-del="${t.id}" data-title="${esc(t.title)}" title="요청 삭제">🗑</button></div>
        <div class="m"><span>${t.id}${t.system ? ` · ${esc(t.system)}` : ""}</span><span class="badge ${t.status}">${STATUS[t.status] ?? t.status}</span></div></li>`).join("")
    : `<li class="empty" style="margin:20px 0">등록된 요청이 없습니다</li>`;
}

$("#tickets").addEventListener("click", async (e) => {
  const del = e.target.closest("[data-del]");
  if (del) {
    const id = del.dataset.del;
    const title = del.dataset.title;
    if (!confirm(`'${title}' (${id}) 요청을 삭제할까요?\n산출물·첨부 자료와 함께 휴지통으로 옮겨지며, 휴지통 메뉴에서 복원할 수 있습니다.`)) return;
    try {
      await api(`/api/tickets/${id}`, { method: "DELETE" });
      if (selectedId === id) {
        selectedId = null;
        clearTimeout(pollTimer);
        $("#detail").innerHTML = `<div class="empty">왼쪽에서 요청을 선택하거나 새 개발 요청을 등록하세요.</div>`;
      }
      await loadList();
    } catch (err) { alert(err.message); }
    return;
  }
  const li = e.target.closest("li[data-id]");
  if (li) select(li.dataset.id);
});

async function select(id) {
  if (selectedId !== id) { selectedStage = null; crFiles = []; }
  selectedId = id;
  lastUpdated = null;
  await refresh();
}

// Claude Code가 파일을 바꾸므로 계속 확인하고, 바뀌었을 때만 다시 그린다 (입력 중인 수정 지시가 지워지지 않게)
async function refresh() {
  clearTimeout(pollTimer);
  if (!selectedId) return;
  try {
    const t = await api(`/api/tickets/${selectedId}`);
    const typing = ["fb", "target", "crText"].includes(document.activeElement?.id) || document.activeElement?.closest?.("#crList")
      || $("#fb")?.value.trim() || $("#crText")?.value.trim() || crFiles.length || document.querySelector("#crList input:checked");
    if (t.updatedAt !== lastUpdated && !(typing && lastUpdated)) {
      lastUpdated = t.updatedAt;
      renderTicket(t);
      await loadList();
    }
  } finally {
    pollTimer = setTimeout(refresh, 3000);
  }
}

// ---------- 산출물 렌더링 ----------

function md(s) {
  const lines = esc(s).split("\n");
  let html = "", list = false, code = false, table = false;
  const inline = (x) => x.replace(/\*\*(.+?)\*\*/g, "<b>$1</b>").replace(/`([^`]+)`/g, "<code>$1</code>");
  for (const line of lines) {
    if (line.startsWith("```")) { html += code ? "</pre>" : line.trim() === "```mermaid" ? '<pre class="mermaid">' : line.trim() === "```sapscreen" ? '<pre class="sapscreen">' : "<pre>"; code = !code; continue; }
    if (code) { html += line + "\n"; continue; }
    const row = /^\s*\|.*\|\s*$/.test(line);
    if (!row && table) { html += "</table>"; table = false; }
    if (row) {
      if (/^\s*\|[\s:|-]+\|\s*$/.test(line)) continue; // 구분선
      const cells = line.trim().slice(1, -1).split("|").map((c) => inline(c.trim()));
      html += table ? `<tr>${cells.map((c) => `<td>${c}</td>`).join("")}</tr>` : `<table><tr>${cells.map((c) => `<th>${c}</th>`).join("")}</tr>`;
      table = true;
      continue;
    }
    const li = line.match(/^\s*(?:[-*]|\d+\.)\s+(.*)/);
    if (li && !list) { html += "<ul>"; list = true; }
    if (!li && list) { html += "</ul>"; list = false; }
    const h = line.match(/^(#{1,4})\s+(.*)/);
    if (h) html += `<h3>${inline(h[2])}</h3>`;
    else if (li) html += `<li>${inline(li[1])}</li>`;
    else if (line.trim()) html += `<p>${inline(line)}</p>`;
  }
  return html + (list ? "</ul>" : "") + (table ? "</table>" : "") + (code ? "</pre>" : "");
}

// ```mermaid 블록(설계 다이어그램)은 화면에 붙으면 Mermaid(CDN)로 그린다. 못 그리면 원문 코드를 그대로 둔다.
let mermaidLib = null;
async function renderDiagrams() {
  const nodes = [...document.querySelectorAll("pre.mermaid:not([data-processed])")];
  if (!nodes.length) return;
  try {
    mermaidLib ??= import("https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs").then(({ default: m }) => {
      m.initialize({ startOnLoad: false, securityLevel: "strict", theme: "default", fontFamily: "Pretendard, Malgun Gothic, sans-serif" });
      return m;
    });
    const m = await mermaidLib;
    for (const el of nodes) {
      if (!el.isConnected) continue;
      try { await m.run({ nodes: [el] }); el.classList.add("diagram"); fitDiagram(el); }
      catch (err) { el.dataset.processed = "error"; el.title = `다이어그램을 그리지 못했습니다: ${err.message ?? err}`; }
    }
  } catch { mermaidLib = null; nodes.forEach((el) => (el.dataset.processed = "offline")); }
}
// 카드에서는 칸에 맞춰 전체 모양을 보여주고, 클릭하면 전체 화면에서 원래 크기로 연다.
function fitDiagram(el) {
  const svg = el.querySelector("svg");
  const natural = svg?.viewBox?.baseVal?.width;
  if (!natural) return;
  el.title = "클릭하면 원래 크기로 크게 봅니다";
  el.addEventListener("click", () => {
    let dlg = $("#diagramDlg");
    if (!dlg) {
      dlg = document.createElement("dialog");
      dlg.id = "diagramDlg";
      dlg.addEventListener("click", () => dlg.close());
      document.body.append(dlg);
    }
    const big = svg.cloneNode(true);
    big.style.maxWidth = "none";
    big.style.width = `${natural}px`;
    dlg.replaceChildren(big);
    dlg.showModal();
  });
}
// ```sapscreen 블록(설계 예상 화면)은 JSON 정의를 SAP GUI 모양 HTML로 바꾼다. JSON이 틀리면 원문 그대로 둔다.
// { type: "selection"|"alv"|"popup", title, tcode, blocks:[{title, fields:[{label, kind:"select"|"param"|"check"|"radio", required, value, to, checked}]}],
//   toolbar:[...], columns:[{label, align:"right", key}], rows:[[...]], total:[...], message, icon:"?"|"!"|"x"|"i", buttons:[...], status:{type:"S"|"W"|"E", text} }
function renderScreens() {
  for (const el of document.querySelectorAll("pre.sapscreen:not([data-processed])")) {
    el.dataset.processed = "1";
    try {
      const div = document.createElement("div");
      div.className = "sapgui";
      div.innerHTML = sapScreen(JSON.parse(el.textContent));
      el.replaceWith(div);
    } catch (err) { el.title = `예상 화면을 그리지 못했습니다: ${err.message ?? err}`; }
  }
}
function sapScreen(d) {
  const statusBar = d.status ? `<div class="sg-status ${esc(d.status.type ?? "S")}"><span class="sg-ico">${{ E: "⛔", W: "⚠", S: "✔" }[d.status.type] ?? "✔"}</span>${esc(d.status.text)}</div>` : "";
  if (d.type === "popup")
    return `<div class="sg-popup"><div class="sg-title">${esc(d.title ?? "")}</div>
      <div class="sg-pbody"><span class="sg-picon">${{ "?": "❓", "!": "⚠", x: "⛔", i: "ℹ" }[d.icon] ?? "ℹ"}</span><div>${esc(d.message ?? "")}</div></div>
      <div class="sg-pbtns">${(d.buttons ?? ["확인"]).map((b) => `<span class="sg-btn">${esc(b)}</span>`).join("")}</div></div>`;
  const head = `<div class="sg-title">${esc(d.title ?? "")}${d.tcode ? `<span class="sg-tcode">${esc(d.tcode)}</span>` : ""}</div>`;
  let body = "";
  if (d.type === "alv") {
    const cols = d.columns ?? [];
    const cell = (v, i, tag = "td") => `<${tag} class="${cols[i]?.align === "right" ? "r" : ""} ${cols[i]?.key ? "key" : ""}">${esc(v)}</${tag}>`;
    body = `<div class="sg-toolbar">${(d.toolbar ?? []).map((b) => `<span class="sg-tbtn">${esc(b)}</span>`).join("")}</div><div class="sg-grid"><table>
      <tr>${cols.map((c, i) => cell(c.label, i, "th")).join("")}</tr>
      ${(d.rows ?? []).map((r) => `<tr>${r.map((v, i) => cell(v, i)).join("")}</tr>`).join("")}
      ${d.total ? `<tr class="sum">${d.total.map((v, i) => cell(v, i)).join("")}</tr>` : ""}</table></div>`;
  } else {
    const input = (v, req) => `<span class="sg-in">${esc(v ?? "")}${req ? `<span class="sg-req">✔</span>` : ""}</span>`;
    const field = (f) => {
      if (f.kind === "check") return `<div class="sg-row"><span class="sg-chk">${f.checked ? "✔" : ""}</span>${esc(f.label)}</div>`;
      if (f.kind === "radio") return `<div class="sg-row"><span class="sg-rad ${f.checked ? "on" : ""}"></span>${esc(f.label)}</div>`;
      const range = f.kind === "select" ? `<span class="sg-to">~</span>${input(f.to)}<span class="sg-multi">➔</span>` : "";
      return `<div class="sg-row"><label>${esc(f.label)}</label>${input(f.value, f.required)}${range}</div>`;
    };
    body = `<div class="sg-toolbar"><span class="sg-tbtn">⏵ 실행</span></div>` + (d.blocks ?? []).map((b) =>
      `<fieldset class="sg-block">${b.title ? `<legend>${esc(b.title)}</legend>` : ""}${(b.fields ?? []).map(field).join("")}</fieldset>`).join("");
  }
  return `<div class="sg-win">${head}<div class="sg-body">${body}</div>${statusBar}</div>`;
}
let diagramTimer = null;
new MutationObserver(() => { clearTimeout(diagramTimer); diagramTimer = setTimeout(() => { renderScreens(); renderDiagrams(); }, 300); })
  .observe(document.body, { childList: true, subtree: true });

function renderFiles(files) {
  if (!files?.length) return "";
  return files.map((f) => f.name.endsWith(".abap")
    ? `<details><summary class="k">📄 ${esc(f.name)} (${f.content.split("\n").length}줄)</summary><pre>${esc(f.content)}</pre></details>`
    : `<div class="k">📄 ${esc(f.name)}</div><div class="md">${md(f.content)}</div>`).join("");
}

// 소요일수는 달력 날짜 기준으로 시작일·종료일을 모두 센다 (같은 날 = 1일). 진행 중이면 오늘까지 n일째.
const mmdd = (iso) => { const d = new Date(iso); return `${String(d.getMonth() + 1).padStart(2, "0")}/${String(d.getDate()).padStart(2, "0")}`; };
const dayOf = (iso) => { const d = new Date(iso); return new Date(d.getFullYear(), d.getMonth(), d.getDate()); };
const hhmm = (iso) => { const d = new Date(iso); return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`; };
function span(start, end, prefix = "") {
  if (!start) return "";
  const days = Math.round((dayOf(end ?? new Date().toISOString()) - dayOf(start)) / 86400000) + 1;
  const title = `${new Date(start).toLocaleString()} ~ ${end ? new Date(end).toLocaleString() : "진행 중"}`;
  return `<div class="d" title="${esc(title)}">${prefix}${end ? `${days}일` : `${days}일째`}</div>
    <div class="d tm" title="${esc(title)}">${mmdd(start)} ${hhmm(start)} ~</div>
    <div class="d tm" title="${esc(title)}">${end ? `${mmdd(end)} ${hhmm(end)}` : "진행 중"}</div>`;
}

function renderTicket(t) {
  const team = status.team;
  if (!selectedStage) selectedStage = t.currentStage;
  const st = t.stages[selectedStage];

  const allEnd = t.stages.deploy.endedAt ?? (t.status === "done" ? t.updatedAt : null);
  const members = [
    `<div class="member lead"><div class="n">📋 ${team.lead.name}</div><div class="r">${team.lead.role}</div>
      <div class="s">${STATUS[t.status] ?? t.status}</div>${span(t.stages.analysis.startedAt ?? t.createdAt, allEnd, "전체 ")}</div>`,
    ...STAGES.map((k) => {
      const s = t.stages[k];
      return `<div class="member st-${s.status} ${k === selectedStage ? "sel" : ""}" data-stage="${k}">
        <div class="n">${team[k].name}</div><div class="r">${team[k].role}</div>
        <div class="s"><span class="dot"></span>${STAGE_STATUS[s.status]}${s.attempts > 1 ? ` (${s.attempts}회차)` : ""}</div>${span(s.startedAt, s.endedAt)}</div>`;
    }),
  ].join("");

  // 팀장 수정 지시 폼: 현재 단계 또는 앞 단계를 지정해 다시 작업시킨다
  const reviseForm = (maxIdx, def, prefill = "") => `
      <div class="row" style="margin-top:12px;align-items:flex-end">
        <label style="flex:0 0 180px">수정 지시 대상<select id="target">${WORK_STAGES.slice(0, maxIdx + 1)
          .map((k) => `<option value="${k}" ${k === def ? "selected" : ""}>${team[k].name}</option>`).join("")}</select></label>
        <label>수정 지시 내용 (지정한 단계부터 다시 작업 후 재보고)<textarea id="fb" rows="2" placeholder="예: 납품일 기준 필터를 추가해 주세요">${esc(prefill)}</textarea></label>
      </div>
      <div class="row end"><button id="revise">수정 지시</button></div>`;

  // AI 검증: 팀장이 승인 전에 산출물 검증을 맡긴다. 결과는 참고용이고 승인·수정 지시는 팀장이 한다.
  const VERDICT = { pass: ["통과", "done"], warn: ["주의", "awaiting_review"], fail: ["문제 있음", "failed"] };
  const verifyPanel = (k) => {
    const list = t.stages[k].verifications ?? [];
    const v = list.at(-1);
    if (!v) return "";
    const old = v.attempt !== t.stages[k].attempts ? ` · <b>이전 산출물(${v.attempt}회차) 기준</b>` : "";
    const head = `<span class="sub">${new Date(v.at).toLocaleString()}${old}${list.length > 1 ? ` · 검증 ${list.length}회` : ""}</span>`;
    if (v.status === "running") return `<div class="verify run"><b><span class="dot" style="color:var(--run)"></span> 🤖 AI가 ${team[k].name} 산출물을 검증 중입니다</b> ${head}<div class="sub" style="margin:0">몇 분 걸릴 수 있습니다. 끝나면 결과가 여기에 표시됩니다.</div></div>`;
    if (v.status === "failed") return `<div class="verify fail"><b>🤖 AI 검증 실패</b> ${head}<div class="sub" style="margin:0;color:var(--bad)">${esc(v.error)}</div></div>`;
    const [label, cls] = VERDICT[v.verdict] ?? [v.verdict, ""];
    const icon = { ok: "✅", warn: "⚠️", issue: "❌" };
    const checks = [...(v.checks ?? [])].sort((a, b) => ["issue", "warn", "ok"].indexOf(a.result) - ["issue", "warn", "ok"].indexOf(b.result));
    return `<div class="verify ${v.verdict}"><b>🤖 AI 검증 결과</b> <span class="badge ${cls}">${label}</span> ${head}
      <div style="margin:4px 0">${esc(v.summary)}</div>
      <details ${v.verdict !== "pass" ? "open" : ""}><summary class="sub" style="margin:0;cursor:pointer">검증 항목 ${checks.length}개 (확인 필요 ${checks.filter((c) => c.result !== "ok").length})</summary>
        <ul class="checks">${checks.map((c) => `<li class="${c.result}">${icon[c.result] ?? ""} <b>${esc(c.item)}</b> — ${esc(c.detail)}</li>`).join("")}</ul></details>
      ${v.directive ? `<div style="margin-top:4px"><b>제안 수정 지시${v.send_back_to && v.send_back_to !== k ? ` (${team[v.send_back_to].name})` : ""}:</b> ${esc(v.directive)}</div>` : ""}
      ${v.directive && k === t.currentStage && t.status === "awaiting_review" ? `<div class="row end" style="margin-top:6px"><button class="small" id="useVerify" data-stage="${esc(v.send_back_to ?? k)}">검증 결과로 수정 지시 채우기</button></div>` : ""}</div>`;
  };
  const verifying = (k) => (t.stages[k].verifications ?? []).some((v) => v.status === "running");
  const verifyBtn = (k, id) => `<button id="${id}" data-stage="${k}" ${verifying(k) ? "disabled" : ""} title="작업한 PL과 별개의 AI가 요청·첨부·이전 단계 대비 산출물을 검증합니다. 승인은 팀장이 직접 합니다.">${verifying(k) ? "🤖 검증 중..." : "🤖 AI 검증"}</button>`;

  let gate = "";
  if (t.status === "in_progress") {
    const k = t.currentStage, s = t.stages[k];
    const working = t.busy && s.status === "running";
    gate = `<div class="card wait"><h3>${working ? `<span class="dot" style="color:var(--run)"></span> ${team[k].name} 작업 중 (${team[k].agent})` : s.status === "failed" ? `⚠️ ${team[k].name} 작업 실패` : `⏳ ${team[k].name} 작업 대기`}</h3>
      ${s.directive ? `<div class="review revise"><b>팀장 수정 지시</b> — ${esc(s.directive)}</div>` : ""}
      ${working
        ? `<p class="sub" style="margin:0 0 8px">Claude Code가 작업 중입니다. 몇 분 걸릴 수 있으며, 끝나면 이 화면에 보고가 올라옵니다. 진행 상황은 진행 기록에 표시됩니다.</p>
           <div class="row end"><button id="stop">⏹ 작업 중단</button></div>`
        : `<div class="row end"><button class="primary" id="run">${s.status === "failed" ? "다시 시작" : "작업 시작"}</button></div>`}
      ${reviseForm(WORK_STAGES.indexOf(k), k)}
      ${working ? `<p class="sub" style="margin:4px 0 0;text-align:right">작업 중에 수정 지시를 내리면 현재 작업을 중단하고 지정한 단계부터 다시 시작합니다.</p>` : ""}</div>`;
  }
  if (t.status === "awaiting_review") {
    const k = t.currentStage;
    const r = t.stages[k].review;
    const idx = WORK_STAGES.indexOf(k);
    const rec = r?.decision === "revise";
    gate = `<div class="card gate"><h3>📨 ${team[k].name} 결과 보고 — 팀장 승인 필요</h3>
      ${r ? `<div class="review ${rec ? "revise" : ""}"><b>PL 의견 (권고: ${rec ? "수정" : "승인"})</b> — ${esc(r.summary)}${rec && r.feedback ? `<div style="margin-top:4px"><b>제안 수정 지시:</b> ${esc(r.feedback)}</div>` : ""}</div>` : ""}
      <p class="sub" style="margin:0 0 10px">아래 산출물을 확인하고 승인하면 ${idx < WORK_STAGES.length - 1 ? `<b>${team[WORK_STAGES[idx + 1]].name}</b> 단계로 넘어갑니다.` : "<b>개발계 반영 승인</b> 단계로 넘어갑니다."}</p>
      ${verifyPanel(k)}
      <div class="row end">${verifyBtn(k, "verifyGate")}<button class="primary" id="approveStage">✅ 승인하고 다음 단계로</button></div>
      <p class="sub" style="margin:4px 0 0;text-align:right">🤖 AI 검증은 참고용입니다. 검증 결과와 관계없이 승인·수정 지시는 팀장이 결정합니다.</p>
      ${reviseForm(idx, rec ? r.send_back_to : k, rec ? r.feedback : "")}</div>`;
  }
  if (t.status === "awaiting_deploy" || t.status === "failed") {
    gate = `<div class="card gate"><h3>🚦 개발계 반영 승인${t.status === "failed" ? " (재시도)" : ""}</h3>
      <p class="sub" style="margin:0 0 10px">${status.sap ? `<b>${esc(status.sap.url)}</b> (클라이언트 ${esc(status.sap.client)})에 src/*.abap 오브젝트를 생성·활성화하고 ABAP Unit을 실행합니다.` : "SAP 접속 정보가 없어 <b>시뮬레이션</b>으로 진행됩니다. 실제 시스템에는 반영되지 않습니다."}</p>
      <div class="row">
        <label>패키지<input id="pkg" value="${esc(t.deployConfig?.package || "$TMP")}" /></label>
        <label>이송요청 (비우면 자동 생성, $TMP는 불필요)<input id="trkorr" value="${esc(t.deployConfig?.transport || "")}" placeholder="예: DEVK900123" /></label>
        <button class="primary" id="deploy">승인하고 반영</button>
      </div>
      ${reviseForm(WORK_STAGES.length - 1, "development", t.status === "failed" && t.deployResult ? `개발계 반영 오류를 수정해 주세요:\n${t.deployResult.text.split("\n").filter((l) => /\[E\]|실패|오류/.test(l)).join("\n")}` : "")}</div>`;
  }
  if (t.status === "done") gate = `<div class="card"><h3>수정 지시</h3>${reviseForm(WORK_STAGES.length - 1, "development")}</div>`;

  // 요구사항 변경(CR): 언제든 등록 → PL 영향분석 → 팀장이 반영/다음 차수/반려 결정
  const changes = t.changes ?? [];
  const crItem = (c) => {
    const i = c.impact;
    const pick = c.status === "proposed"
      ? `<div class="row" style="margin-top:6px;align-items:center;gap:8px">
          <label style="flex:0 0 auto;display:flex;align-items:center;gap:4px"><input type="checkbox" class="crPick" value="${c.id}" style="width:auto" />반영 대상</label>
          <select class="crStage" data-id="${c.id}" style="flex:0 0 180px">${WORK_STAGES.map((k) => `<option value="${k}" ${k === i.from ? "selected" : ""}>${team[k].name}부터${k === i.from ? " (PL 권고)" : ""}</option>`).join("")}</select>
          <button class="small" data-cr="${c.id}" data-act="defer">다음 차수로</button><button class="small" data-cr="${c.id}" data-act="reject">반려</button></div>`
      : c.status === "failed" ? `<div class="row end"><button class="small" data-cr="${c.id}" data-act="reanalyze">다시 분석</button><button class="small" data-cr="${c.id}" data-act="reject">반려</button></div>`
      : c.status === "deferred" || c.status === "rejected" ? `<div class="row end"><button class="small" data-cr="${c.id}" data-act="reopen">다시 검토</button></div>`
      : "";
    return `<li class="cr cr-${c.status}"><div><b>${c.id}</b> <span class="badge cr-${c.status}">${CR_STATUS[c.status] ?? c.status}</span>
        <span class="sub">${new Date(c.at).toLocaleString()}</span> ${esc(c.text)}</div>
      ${c.attachments?.length ? `<ul class="atts">${c.attachments.map((a) => {
        const url = `/api/tickets/${t.id}/changes/${c.id}/attachments/${encodeURIComponent(a.name)}`;
        return `<li>${a.kind === "image" ? `<a href="${url}" target="_blank"><img src="${url}" alt="${esc(a.name)}" loading="lazy" /></a>` : ""}
          <a href="${url}" target="_blank">${{ image: "🖼", pdf: "📕", office: "📄", text: "📝" }[a.kind]} ${esc(a.name)}</a> <span class="sub">${fmtSize(a.size)}</span></li>`;
      }).join("")}</ul>` : ""}
      ${i ? `<div class="sub" style="margin:2px 0 0">PL 영향분석: <b>${team[c.appliedTo ?? i.from].name}부터</b>${c.appliedTo && c.appliedTo !== i.from ? ` (권고 ${team[i.from].name})` : ""} · 규모 ${EFFORT[i.effort] ?? i.effort} — ${esc(i.summary)}</div>` : ""}
      ${c.status === "failed" && c.error ? `<div class="sub" style="margin:2px 0 0;color:var(--bad)">${esc(c.error)}</div>` : ""}${pick}</li>`;
  };
  const crCard = `<div class="card"><h3>🔄 요구사항 변경 <span class="sub">진행 중 추가·수정 요청</span></h3>
      ${changes.length ? `<ul id="crList" class="crs">${[...changes].reverse().map(crItem).join("")}</ul>` : ""}
      ${changes.some((c) => c.status === "proposed") ? `<div class="row end"><button class="primary" id="crApply">선택한 변경 반영</button></div>
        <p class="sub" style="margin:4px 0 8px;text-align:right">여러 건을 고르면 가장 앞 단계부터 함께 다시 작업합니다. 아직 오지 않은 단계면 그 단계 차례에 반영합니다.</p>` : ""}
      <div id="crDrop"><label>새 변경 요청 (작업 중이어도 등록 가능, PL이 영향받는 단계를 분석해 권고)<textarea id="crText" rows="2" placeholder="예: 조회 결과에 저장위치별 재고도 보여 주세요&#10;화면 캡처는 여기에 바로 붙여넣기(Ctrl+V), 파일은 끌어다 놓을 수 있습니다."></textarea></label>
        <input type="file" id="crFiles" multiple hidden accept="${ACCEPT}" />
        <ul id="crFileList" class="atts"></ul></div>
      <div class="row end"><button id="crPick" class="small">📎 파일·이미지 첨부</button><button id="crAdd">변경 요청 등록</button></div></div>`;
  const applied = changes.filter((c) => c.status === "applied");

  // 요청 첨부 자료: 이미지는 미리보기, 문서는 링크. 진행 중에 추가하면 다음 작업부터 참고한다
  const attUrl = (a) => `/api/tickets/${t.id}/attachments/${encodeURIComponent(a.name)}`;
  const attCard = `<h3 class="row" style="justify-content:space-between;margin-top:12px">📎 첨부 자료 (${t.attachments.length})<span><button id="sheetAdd" class="small">+ 구글시트</button> <button id="attAdd" class="small">+ 자료 추가</button></span></h3>
      <input type="file" id="attFiles" multiple hidden accept="${ACCEPT}" />
      ${t.attachments.length ? `<ul class="atts">${t.attachments.map((a) => `<li>
          ${a.kind === "image" ? `<a href="${attUrl(a)}" target="_blank"><img src="${attUrl(a)}" alt="${esc(a.name)}" loading="lazy" /></a>` : ""}
          <a href="${attUrl(a)}" target="_blank">${a.source ? "📊" : { image: "🖼", pdf: "📕", office: "📄", text: "📝" }[a.kind]} ${esc(a.name)}</a>
          ${a.source ? `<a href="${esc(a.source)}" target="_blank" rel="noopener" class="sub">원본 시트 ↗</a>` : ""}
          <span class="sub">${fmtSize(a.size)}${a.kind === "office" ? (a.extracted ? " · 텍스트 추출됨" : " · <span style='color:var(--bad)'>텍스트 추출 실패</span>") : ""}</span>
          <button class="small" data-attdel="${esc(a.name)}" title="삭제">✕</button></li>`).join("")}</ul>`
        : `<p class="sub" style="margin:0">화면 캡처·양식·샘플 데이터 등을 올리면 분석부터 모든 단계가 참고합니다.</p>`}
      ${t.attachments.length && t.stages.analysis.status !== "pending" ? `<p class="sub" style="margin:4px 0 0">작업 중에 추가한 자료는 다음 작업부터 참고합니다. 요구사항이 바뀌면 요구사항 변경으로 등록해 주세요.</p>` : ""}`;


  const deploy = t.deployResult
    ? `<div class="card ${t.deployResult.ok ? "" : "err"}"><h3>🧪 개발계 반영 결과 <span class="badge ${t.deployResult.ok ? "done" : "failed"}">${t.deployResult.ok ? "성공" : "문제 있음"}</span></h3><pre>${esc(t.deployResult.text)}</pre></div>`
    : "";

  const review = st.review && selectedStage !== "deploy"
    ? `<div class="review ${st.review.decision === "revise" ? "revise" : ""}"><b>PL 의견 (권고: ${st.review.decision === "approve" ? "승인" : "수정"})</b> — ${esc(st.review.summary)}</div>`
    : "";
  const directives = st.directives?.length
    ? `<div class="review revise"><b>팀장 수정 지시 이력</b><ul style="margin:4px 0 0;padding-left:18px">${st.directives
        .map((d) => `<li><span class="sub">${new Date(d.at).toLocaleString()}</span> ${esc(d.text)}</li>`).join("")}</ul></div>`
    : "";
  const gateShowsVerify = t.status === "awaiting_review" && selectedStage === t.currentStage;
  const stageVerify = selectedStage !== "deploy" && !gateShowsVerify ? verifyPanel(selectedStage) : "";
  const canVerify = selectedStage !== "deploy" && !gateShowsVerify && t.files[selectedStage]?.length && st.status !== "running";
  const output = selectedStage === "deploy"
    ? (t.deployResult ? `<pre>${esc(t.deployResult.text)}</pre>` : `<span class="sub">아직 반영하지 않았습니다.</span>`)
    : renderFiles(t.files[selectedStage]) || `<span class="sub">${st.status === "running" ? "작업 중입니다..." : "아직 산출물이 없습니다."}</span>`;

  $("#detail").innerHTML = `
    <h2>${esc(t.title)} <span class="badge ${t.status}">${STATUS[t.status] ?? t.status}</span></h2>
    <div class="sub">${t.id}${t.system ? ` · 🖥 ${esc(t.system)}` : ""} · 등록 ${new Date(t.createdAt).toLocaleString()} · 팀장 수정 지시 ${t.revisionCount}회 · 폴더 work/${t.id}/</div>
    <div class="team">${members}</div>
    ${gate}${crCard}${deploy}
    <div class="grid2">
      <div class="card"><h3 class="row" style="justify-content:space-between">${team[selectedStage].name} 산출물<span class="row" style="gap:6px">${canVerify ? verifyBtn(selectedStage, "verifyStage").replace("<button ", '<button class="small" ') : ""}${selectedStage === "test" ? '<button id="testResult" class="small">⬇️ 테스트결과서</button>' : ""}<button id="stagePptx" class="small">⬇️ PPTX</button></span></h3>${review}${stageVerify}${directives}<div class="out">${output}</div></div>
      <div>
        <div class="card"><h3>📚 배운 점 <span class="sub">지식 위키</span></h3>
          ${t.lessons?.docs.length
            ? `<ul class="lessons">${t.lessons.docs.map((d) => `<li><a href="#/wiki/page/${encodeURIComponent(`doc:${d.title}`)}">${esc(d.title)}</a>
                <span class="badge">${d.action === "created" ? "새 문서" : "보강"}</span>${d.summary ? `<div class="sub" style="margin:0">${esc(d.summary)}</div>` : ""}</li>`).join("")}</ul>
               <div class="sub" style="margin:4px 0 8px">마지막 정리 ${new Date(t.lessons.at).toLocaleString()}</div>`
            : `<p class="sub" style="margin:0 0 8px">분석~테스트가 모두 승인되거나 개발계 반영이 끝나면 PL이 자동으로 정리합니다.</p>`}
          <div class="row end"><button id="lessons" ${t.learning ? "disabled" : ""}>${t.learning ? "정리 중..." : "지금 정리하기"}</button></div></div>
        <div class="card"><h3>진행 기록</h3><div class="logs">${[...t.logs].reverse().map((l) =>
          `<div><span class="time">${new Date(l.at).toLocaleTimeString()}</span><span class="a">${esc(l.agent)}</span><span class="text">${esc(l.text)}</span></div>`).join("")}</div></div>
        <div class="card"><h3>개발 요청 원문</h3><div class="md">${md(t.request)}</div>${attCard}${applied.length ? `<h3 style="margin-top:12px">반영된 요구사항 변경</h3><ul class="lessons">${applied.map((c) => `<li><b>${c.id}</b> ${esc(c.text)} <span class="sub">${c.decidedAt ? new Date(c.decidedAt).toLocaleDateString() : ""}</span></li>`).join("")}</ul>` : ""}</div>
      </div>
    </div>`;

  $("#stagePptx").addEventListener("click", async (e) => {
    const btn = e.currentTarget;
    btn.disabled = true;
    btn.textContent = "만드는 중…";
    try { await downloadStagePptx(t, selectedStage); } catch (err) { alert(err.message ?? err); }
    finally { btn.disabled = false; btn.textContent = "⬇️ PPTX"; }
  });
  $("#testResult")?.addEventListener("click", async (e) => {
    const btn = e.currentTarget;
    btn.disabled = true;
    btn.textContent = "만드는 중…";
    try { await downloadTestResult(t); } catch (err) { alert(err.message ?? err); }
    finally { btn.disabled = false; btn.textContent = "⬇️ 테스트결과서"; }
  });
  $("#detail .team").addEventListener("click", (e) => {
    const m = e.target.closest("[data-stage]");
    if (m) { selectedStage = m.dataset.stage; renderTicket(t); }
  });
  const act = (sel, fn) => $(sel)?.addEventListener("click", async (e) => {
    e.target.disabled = true;
    try { await fn(); selectedStage = null; lastUpdated = null; $("#fb") && ($("#fb").value = ""); $("#crText") && ($("#crText").value = ""); document.querySelectorAll(".crPick").forEach((x) => (x.checked = false)); await refresh(); } catch (err) { alert(err.message); e.target.disabled = false; }
  });
  act("#lessons", () => api(`/api/tickets/${t.id}/lessons`, { method: "POST" }));
  act("#run", () => api(`/api/tickets/${t.id}/run`, { method: "POST" }));
  act("#stop", () => {
    if (!confirm("진행 중인 작업을 중단할까요?")) throw new Error("취소했습니다.");
    return api(`/api/tickets/${t.id}/stop`, { method: "POST" });
  });
  act("#approveStage", () => api(`/api/tickets/${t.id}/approve-stage`, { method: "POST" }));
  act("#revise", () => {
    if (t.busy && !confirm("진행 중인 작업을 중단하고 수정 지시를 내릴까요?")) throw new Error("취소했습니다.");
    return api(`/api/tickets/${t.id}/revise`, { method: "POST", body: { stage: $("#target").value, feedback: $("#fb").value } });
  });
  // 보고 있는 단계와 입력 중인 수정 지시는 그대로 둔다
  for (const sel of ["#verifyGate", "#verifyStage"])
    $(sel)?.addEventListener("click", async (e) => {
      e.target.disabled = true;
      try { await api(`/api/tickets/${t.id}/verify`, { method: "POST", body: { stage: e.target.dataset.stage } }); lastUpdated = null; await refresh(); }
      catch (err) { alert(err.message); e.target.disabled = false; }
    });
  $("#useVerify")?.addEventListener("click", (e) => {
    const v = t.stages[t.currentStage].verifications.at(-1);
    $("#target").value = e.target.dataset.stage;
    $("#fb").value = v.directive;
    $("#fb").focus();
  });
  $("#attAdd")?.addEventListener("click", () => $("#attFiles").click());
  $("#sheetAdd")?.addEventListener("click", async (e) => {
    const text = prompt("구글시트 링크 ('링크가 있는 모든 사용자 - 뷰어'로 공유된 시트)");
    if (!text?.trim()) return;
    const urls = sheetLinks(text);
    if (!urls.length) return alert("구글시트 링크는 https://docs.google.com/spreadsheets/d/... 형식으로 넣어 주세요.");
    e.target.disabled = true;
    const failed = [];
    for (const url of urls) try { await importSheet(t.id, url); } catch (err) { failed.push(`${url}: ${err.message}`); }
    if (failed.length) alert(failed.join("\n"));
    lastUpdated = null;
    await refresh();
  });
  $("#attFiles")?.addEventListener("change", async (e) => {
    const failed = [];
    for (const file of e.target.files) try { await upload(t.id, file); } catch (err) { failed.push(`${file.name}: ${err.message}`); }
    if (failed.length) alert(failed.join("\n"));
    lastUpdated = null;
    await refresh();
  });
  document.querySelectorAll("[data-attdel]").forEach((b) => b.addEventListener("click", async () => {
    if (!confirm(`첨부 '${b.dataset.attdel}'을(를) 삭제할까요?`)) return;
    b.disabled = true;
    try { await api(`/api/tickets/${t.id}/attachments/${encodeURIComponent(b.dataset.attdel)}`, { method: "DELETE" }); lastUpdated = null; await refresh(); }
    catch (err) { alert(err.message); b.disabled = false; }
  }));
  // CR 첨부: 파일 선택·끌어다 놓기·캡처 붙여넣기. 다시 그려도 고른 파일이 남도록 crFiles에 둔다
  const renderCrFiles = () => {
    $("#crFileList").innerHTML = crFiles.map((f, i) => `<li>${f.type.startsWith("image/") ? "🖼" : "📄"} ${esc(f.name)} <span class="sub">${fmtSize(f.size)}</span>
      <button type="button" class="small" data-crrm="${i}" title="빼기">✕</button></li>`).join("");
  };
  const addCrFiles = (list) => { crFiles.push(...[...list].filter((f) => f.size)); renderCrFiles(); };
  renderCrFiles();
  $("#crPick").addEventListener("click", () => $("#crFiles").click());
  $("#crFiles").addEventListener("change", (e) => { addCrFiles(e.target.files); e.target.value = ""; });
  $("#crFileList").addEventListener("click", (e) => { const b = e.target.closest("[data-crrm]"); if (b) { crFiles.splice(Number(b.dataset.crrm), 1); renderCrFiles(); } });
  $("#crText").addEventListener("paste", (e) => {
    const imgs = pastedImages(e);
    if (imgs.length) { e.preventDefault(); addCrFiles(imgs); }
  });
  for (const ev of ["dragover", "dragleave", "drop"])
    $("#crDrop").addEventListener(ev, (e) => {
      e.preventDefault();
      $("#crDrop").classList.toggle("over", ev === "dragover");
      if (ev === "drop") addCrFiles(e.dataTransfer.files);
    });
  act("#crAdd", async () => {
    const text = $("#crText").value, files = crFiles;
    if (!text.trim() && !files.length) throw new Error("변경 내용을 입력하거나 자료를 첨부해 주세요.");
    // 첨부가 있으면 등록만 하고, 자료를 모두 올린 뒤 영향분석을 시작한다
    const c = await api(`/api/tickets/${t.id}/changes`, { method: "POST", body: { text, hold: files.length > 0 } });
    if (!files.length) return;
    const failed = [];
    for (const file of files) try { await upload(t.id, file, c.id); } catch (err) { failed.push(`${file.name}: ${err.message}`); }
    crFiles = [];
    if (failed.length) alert(`일부 자료를 올리지 못했습니다. 올라간 자료로 분석하려면 ${c.id}의 '다시 분석'을 눌러 주세요.\n\n${failed.join("\n")}`);
    else await api(`/api/tickets/${t.id}/changes/${c.id}/reanalyze`, { method: "POST" });
  });
  act("#crApply", () => {
    const picks = [...document.querySelectorAll(".crPick:checked")].map((x) => ({ id: x.value, stage: $(`.crStage[data-id="${x.value}"]`).value }));
    if (!picks.length) throw new Error("반영할 변경 요청을 선택해 주세요.");
    const first = WORK_STAGES[Math.min(...picks.map((p) => WORK_STAGES.indexOf(p.stage)))];
    const restart = t.status !== "in_progress" && t.status !== "awaiting_review" || WORK_STAGES.indexOf(first) <= WORK_STAGES.indexOf(t.currentStage);
    const msg = `${picks.map((p) => p.id).join(", ")}을(를) 반영할까요?
${restart ? `${team[first].name}부터 다시 작업합니다.${t.busy ? " 진행 중인 작업은 중단됩니다." : ""}` : `${team[first].name} 차례에 함께 반영합니다.`}`;
    if (!confirm(msg)) throw new Error("취소했습니다.");
    return api(`/api/tickets/${t.id}/changes/apply`, { method: "POST", body: { picks } });
  });
  $("#crList")?.addEventListener("click", async (e) => {
    const b = e.target.closest("button[data-cr]");
    if (!b) return;
    if (b.dataset.act === "reject" && !confirm(`${b.dataset.cr}을(를) 반려할까요?`)) return;
    b.disabled = true;
    try { await api(`/api/tickets/${t.id}/changes/${b.dataset.cr}/${b.dataset.act}`, { method: "POST" }); lastUpdated = null; await refresh(); }
    catch (err) { alert(err.message); b.disabled = false; }
  });
  act("#deploy", () => {
    if (!confirm("개발계에 반영할까요?")) throw new Error("취소했습니다.");
    return api(`/api/tickets/${t.id}/deploy`, { method: "POST", body: { package: $("#pkg").value, transport: $("#trkorr").value } });
  });
}

// ---------- 새 요청 ----------

let newFiles = [];
const renderNewFiles = () => {
  $("#newList").innerHTML = newFiles.map((f, i) => `<li>${f.type.startsWith("image/") ? "🖼" : "📄"} ${esc(f.name)} <span class="sub">${fmtSize(f.size)}</span>
    <button type="button" class="small" data-rm="${i}" title="빼기">✕</button></li>`).join("");
};
const addNewFiles = (list) => { newFiles.push(...[...list].filter((f) => f.size)); renderNewFiles(); };
$("#newBtn").addEventListener("click", async () => {
  $("#newForm").reset(); newFiles = []; renderNewFiles(); $("#sheetResult").innerHTML = "";
  // 대상 시스템: 등록된 MCP 서버 목록, 기본값은 상단에서 고른 기본 시스템
  await loadStatus().catch(() => {});
  const sel = $("#newSystem");
  sel.innerHTML = status?.systems?.length
    ? status.systems.map((s) => `<option value="${esc(s.name)}" ${s.name === status.system ? "selected" : ""}>${esc(s.name)} · ${esc(s.url.replace(/^https?:\/\//, ""))} / 클라이언트 ${esc(s.client)}</option>`).join("")
    : `<option value="">(등록된 SAP 시스템 없음)</option>`;
  sel.disabled = !status?.systems?.length;
  $("#newDlg").showModal();
});
// 구글시트 링크가 열리고 내용이 읽히는지 미리 확인한다 (저장하지 않음)
$("#sheetCheck").addEventListener("click", async (e) => {
  const f = new FormData($("#newForm"));
  const urls = sheetLinks(`${f.get("sheets")}\n${f.get("request")}`);
  const out = $("#sheetResult");
  if (!urls.length) { out.innerHTML = `<li class="sub" style="color:var(--bad)">확인할 구글시트 링크가 없습니다. https://docs.google.com/spreadsheets/d/... 링크를 넣어 주세요.</li>`; return; }
  e.target.disabled = true;
  out.innerHTML = urls.map((u, i) => `<li id="sc${i}"><span class="sub">⏳ 확인 중… ${esc(u.slice(0, 70))}</span></li>`).join("");
  await Promise.all(urls.map(async (url, i) => {
    try {
      const r = await api("/api/gsheet/check", { method: "POST", body: { url } });
      $(`#sc${i}`).innerHTML = `<span style="color:var(--ok)">✅</span> <b>${esc(r.title)}</b>
        <span class="sub">${fmtSize(r.size)} · ${r.sheets.map((s) => `${esc(s.name)} ${s.rows}행`).join(", ")}</span>
        <details style="width:100%"><summary class="sub">읽은 내용 미리보기</summary><pre style="white-space:pre-wrap;font-size:12px;margin:4px 0">${esc(r.preview)}</pre></details>`;
    } catch (err) {
      $(`#sc${i}`).innerHTML = `<span style="color:var(--bad)">❌ ${esc(url.slice(0, 70))}</span><span class="sub" style="width:100%">${esc(err.message)}</span>`;
    }
  }));
  e.target.disabled = false;
});
$("#newPick").addEventListener("click", () => $("#newFiles").click());
$("#newFiles").addEventListener("change", (e) => { addNewFiles(e.target.files); e.target.value = ""; });
$("#newList").addEventListener("click", (e) => { const b = e.target.closest("[data-rm]"); if (b) { newFiles.splice(Number(b.dataset.rm), 1); renderNewFiles(); } });
// 화면 캡처 붙여넣기, 파일 끌어다 놓기
$("#newForm").addEventListener("paste", (e) => {
  const imgs = pastedImages(e);
  if (!imgs.length) return;
  e.preventDefault();
  addNewFiles(imgs);
});
for (const ev of ["dragover", "dragleave", "drop"])
  $("#newDrop").addEventListener(ev, (e) => {
    e.preventDefault();
    $("#newDrop").classList.toggle("over", ev === "dragover");
    if (ev === "drop") addNewFiles(e.dataTransfer.files);
  });
$("#newForm").addEventListener("submit", (e) => {
  const f = new FormData($("#newForm"));
  if (e.submitter?.value !== "ok") return;
  if (String(f.get("sheets")).trim() && !sheetLinks(f.get("sheets")).length) { e.preventDefault(); alert("구글시트 링크는 https://docs.google.com/spreadsheets/d/... 형식으로 넣어 주세요."); return; }
  if (!String(f.get("request")).trim() && !newFiles.length && !sheetLinks(f.get("sheets")).length) { e.preventDefault(); alert("요청 내용을 입력하거나 자료를 첨부해 주세요."); }
});
$("#newDlg").addEventListener("close", async () => {
  if ($("#newDlg").returnValue !== "ok") return;
  const f = new FormData($("#newForm"));
  const files = newFiles;
  // 링크 칸과 요청 내용에 붙여 넣은 구글시트 링크를 모두 가져온다
  const sheets = sheetLinks(`${f.get("sheets")}\n${f.get("request")}`);
  try {
    // 첨부가 있으면 접수만 하고, 자료를 모두 올린 뒤 분석을 시작한다
    const t = await api("/api/tickets", { method: "POST", body: { title: f.get("title"), request: f.get("request"), system: f.get("system") || null, hold: files.length + sheets.length > 0 } });
    if (files.length || sheets.length) {
      const failed = [];
      for (const url of sheets) try { await importSheet(t.id, url); } catch (err) { failed.push(`${url}: ${err.message}`); }
      for (const file of files) try { await upload(t.id, file); } catch (err) { failed.push(`${file.name}: ${err.message}`); }
      if (failed.length) alert(`일부 자료를 올리지 못했습니다. 요청 화면에서 다시 첨부한 뒤 '작업 시작'을 눌러 주세요.\n\n${failed.join("\n")}`);
      else await api(`/api/tickets/${t.id}/run`, { method: "POST" });
    }
    await select(t.id);
  } catch (e) { alert(e.message); }
});

(async () => {
  await loadStatus();
  await loadList();
  const first = $("#tickets li[data-id]");
  if (first) select(first.dataset.id);
})();
