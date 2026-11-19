// 에이전트 오피스: PL·담당 에이전트별로 지금 하는 일, 대기열, 승인 대기, 누적 실적, 최근 활동을 한 화면에 모아 본다
// 보기: 에이전트(카드) / 상태 레인(업무 중·승인 대기·다음 차례·휴식 중 칸으로 나눔). 고른 보기는 브라우저에 기억한다

const OFFICE_ICON = { lead: "🧭", analysis: "🔍", design: "📐", development: "💻", test: "🧪", deploy: "🚀" };
const OFFICE_STATE = { busy: "업무 중", wait: "승인 대기", queued: "다음 차례", idle: "휴식 중" };
let officeTimer = null;
let officeMode = (() => { try { return localStorage.getItem("devsap-office-mode") || "cards"; } catch { return "cards"; } })();

function officeAgo(at) {
  if (!at) return "";
  const m = Math.floor((Date.now() - new Date(at).getTime()) / 60000);
  if (m < 1) return "방금";
  if (m < 60) return `${m}분째`;
  const h = Math.floor(m / 60);
  return h < 24 ? `${h}시간 ${m % 60}분째` : `${Math.floor(h / 24)}일째`;
}

const officeState = (d) => (d.working.length ? "busy" : d.review.length ? "wait" : d.queued.length ? "queued" : "idle");

function officeTicket(t, note) {
  return `<a href="#/" data-open="${esc(t.id)}"><b>${esc(t.title)}</b></a>
    <div class="sub" style="margin:0">${esc(t.id)}${t.system ? ` · ${esc(t.system)}` : ""}${note ? ` · ${note}` : ""}</div>`;
}

const notes = {
  working: (t) => [t.what && esc(t.what), t.attempt > 1 ? `${t.attempt}회차` : "", officeAgo(t.since)].filter(Boolean).join(" · "),
  queued: (t) => [t.failed ? `<span style="color:var(--bad)">⚠️ 실패 · 다시 시작 필요</span>` : "", t.directive ? "수정 지시 반영" : ""].filter(Boolean).join(" · "),
  review: (t) => esc(t.what ?? ""),
};

function officeDesk(d) {
  const state = officeState(d);
  const section = (title, list, note) => list.length
    ? `<div class="o-sec"><div class="o-h">${title} <span>${list.length}</span></div><ul>${list.map((t) => `<li>${officeTicket(t, note(t))}</li>`).join("")}</ul></div>` : "";
  return `<div data-key="${d.key}" class="desk o-${state}">
    <div class="o-top"><span class="o-ico">${OFFICE_ICON[d.key] ?? "👤"}</span>
      <div style="min-width:0"><div class="n">${esc(d.name)}</div><div class="sub" style="margin:0">${esc(d.agent ?? (d.key === "lead" ? "Claude Code" : "ADT"))}</div></div>
      <span class="o-st"><span class="dot"></span>${OFFICE_STATE[state]}</span></div>
    <div class="r">${esc(d.role)}</div>
    <div class="o-stat"><span>완료 <b>${d.approved}</b></span>${d.failed ? `<span class="bad">실패 <b>${d.failed}</b></span>` : ""}</div>
    ${section("지금 하는 일", d.working, notes.working)}
    ${section("다음 차례", d.queued, notes.queued)}
    ${section(d.key === "lead" ? "팀장 결정 대기" : "승인 대기", d.review, notes.review)}
    ${!d.working.length && !d.queued.length && !d.review.length ? `<div class="o-empty">맡은 일이 없습니다</div>` : ""}
    ${d.recent.length ? `<details class="o-log"><summary>최근 활동</summary>${d.recent.map((l) =>
      `<div><span class="time">${new Date(l.at).toLocaleString([], { month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit" })}</span> ${esc(l.text)} <a href="#/" data-open="${esc(l.id)}" class="sub">${esc(l.title)}</a></div>`).join("")}</details>` : ""}
  </div>`;
}

// 상태 레인: 칸마다 그 상태에 있는 일감(에이전트 + 요청)을 카드로 늘어놓는다
function officeLanes(desks) {
  const lanes = { busy: [], wait: [], queued: [], idle: [] };
  for (const d of desks) {
    const who = `<span class="o-who">${OFFICE_ICON[d.key] ?? "👤"} ${esc(d.name)}</span>`;
    d.working.forEach((t) => lanes.busy.push(`<li>${who}${officeTicket(t, notes.working(t))}</li>`));
    d.review.forEach((t) => lanes.wait.push(`<li>${who}${officeTicket(t, notes.review(t))}</li>`));
    d.queued.forEach((t) => lanes.queued.push(`<li>${who}${officeTicket(t, notes.queued(t))}</li>`));
    if (officeState(d) === "idle") lanes.idle.push(`<li>${who}<div class="sub" style="margin:0">완료 ${d.approved}${d.failed ? ` · 실패 ${d.failed}` : ""}</div></li>`);
  }
  return `<div class="o-lanes">${Object.entries(lanes).map(([k, items]) =>
    `<div class="o-lane o-${k}"><div class="o-lh"><span class="dot"></span>${OFFICE_STATE[k]} <span>${items.length}</span></div>
      <ul>${items.join("") || `<li class="o-none">없음</li>`}</ul></div>`).join("")}</div>`;
}

// 평면도: 층 = 개발팀, 구역 = 담당 에이전트(작업 흐름 순서), 좌석 = 그 에이전트가 맡은 요청 하나
const FLOOR_SEATS = 4; // 구역마다 최소 좌석 수 (모자라면 빈자리로 채움)
const FLOOR_LEGEND = [["busy", "업무 중"], ["wait", "승인 대기"], ["queued", "다음 차례"], ["failed", "실패 · 다시 시작"], ["empty", "빈자리"]];

function officeFloor(desks) {
  const seat = (t, kind, note) => `<a href="#/" data-open="${esc(t.id)}" class="seat s-${kind}" title="${esc(t.title)} (${esc(t.id)})">
      <span class="seat-t">${esc(t.title)}</span><span class="seat-m">${esc(t.id)}${note ? ` · ${note}` : ""}</span></a>`;
  const rooms = desks.map((d) => {
    const seats = [
      ...d.working.map((t) => seat(t, "busy", notes.working(t))),
      ...d.review.map((t) => seat(t, "wait", esc(t.what ?? "승인 대기"))),
      ...d.queued.map((t) => seat(t, t.failed ? "failed" : "queued", t.failed ? "실패" : t.directive ? "수정 지시" : "다음 차례")),
    ];
    while (seats.length < FLOOR_SEATS) seats.push(`<span class="seat s-empty">빈자리</span>`);
    const state = officeState(d);
    return `<div class="room r-${state}">
      <div class="room-h"><span class="o-ico">${OFFICE_ICON[d.key] ?? "👤"}</span>
        <div style="min-width:0"><b>${esc(d.name)}</b><div class="sub" style="margin:0">${esc(d.agent ?? (d.key === "lead" ? "Claude Code" : "ADT"))} · 완료 ${d.approved}</div></div>
        <span class="o-st"><span class="dot"></span>${OFFICE_STATE[state]}</span></div>
      <div class="seats">${seats.join("")}</div></div>`;
  });
  return `<div class="floor">${rooms.join("")}</div>
    <div class="legend">${FLOOR_LEGEND.map(([k, l]) => `<span><i class="s-${k}"></i>${l}</span>`).join("")}</div>
    <p class="sub" style="margin:6px 0 0">이 층이 SAP 개발팀이고, 구역은 PL과 담당 에이전트(분석 → 설계 → 개발 → 테스트 → 적용)입니다. 좌석 하나가 그 에이전트가 맡은 개발 요청 하나이며,
      좌석 색이 지금 상태입니다. 좌석을 누르면 그 요청의 보드로 이동합니다. 승인·수정 지시는 보드에서 팀장이 합니다.</p>`;
}

async function officeView() {
  const body = $("#officeBody");
  clearTimeout(officeTimer);
  const fromHash = location.hash.split("/")[2]; // #/office/floor 처럼 보기를 주소로 지정할 수 있다
  if (["cards", "floor", "lanes"].includes(fromHash)) officeMode = fromHash;
  let data;
  try { data = await api("/api/office"); } catch (e) { body.innerHTML = `<div class="card err">${esc(e.message)}</div>`; return; }
  const open = new Set([...body.querySelectorAll("details.o-log[open]")].map((el) => el.closest(".desk").dataset.key));
  const count = (f) => data.desks.reduce((n, d) => n + f(d), 0);
  const busy = data.desks.filter((d) => d.working.length).length;
  const tiles = [
    ["busy", count((d) => d.working.length), "업무 중"],
    ["wait", count((d) => d.review.length), "승인 대기"],
    ["queued", count((d) => d.queued.length), "다음 차례"],
    ["idle", data.desks.filter((d) => officeState(d) === "idle").length, "휴식 중"],
  ];
  body.innerHTML = `
    <div class="o-hero">
      <div class="o-hero-l">
        <div class="o-tags"><span class="o-tag on">에이전트 오피스</span><span class="o-tag">SAP 개발팀</span></div>
        <div class="o-kicker">SAP 개발 관리 보드</div>
        <h2>에이전트 오피스</h2>
        <div class="o-lead">${busy ? `에이전트 <b>${busy}명</b>이 지금 일하고 있습니다.` : "지금 일하고 있는 에이전트가 없습니다."} 진행 중 요청 ${data.active}건 / 전체 ${data.total}건</div>
      </div>
      <div class="o-tiles">${tiles.map(([k, n, label]) => `<div class="o-tile t-${k}"><b>${n}</b><span><span class="dot"></span>${label}</span></div>`).join("")}</div>
    </div>
    <div class="o-bar">
      <div class="o-seg">
        <button data-mode="cards" class="${officeMode === "cards" ? "on" : ""}">👥 에이전트</button>
        <button data-mode="floor" class="${officeMode === "floor" ? "on" : ""}">▦ 평면도</button>
        <button data-mode="lanes" class="${officeMode === "lanes" ? "on" : ""}">▤ 상태 레인</button>
      </div>
      <span class="sub" style="margin:0">갱신 ${new Date().toLocaleTimeString()} · 10초마다</span>
    </div>
    ${officeMode === "floor" ? officeFloor(data.desks) : officeMode === "lanes" ? officeLanes(data.desks) : `<div class="office">${data.desks.map(officeDesk).join("")}</div>`}`;
  open.forEach((k) => body.querySelector(`.desk[data-key="${k}"] details.o-log`)?.setAttribute("open", ""));
  body.querySelectorAll("[data-mode]").forEach((b) => b.addEventListener("click", () => {
    officeMode = b.dataset.mode;
    try { localStorage.setItem("devsap-office-mode", officeMode); } catch {}
    officeView();
  }));
  body.querySelectorAll("[data-open]").forEach((a) => a.addEventListener("click", async (e) => {
    e.preventDefault();
    location.hash = "#/";
    await select(a.dataset.open);
  }));
  officeTimer = setTimeout(() => { if (location.hash.startsWith("#/office")) officeView(); }, 10000);
}
