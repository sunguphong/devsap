// 개발구성: 이 보드를 구성하는 인프라를 한눈에 본다 (요약 타일 · 구성도 · 구성 요소 · 데이터 저장 위치 · 백업 · 보안 · 서버 설정)
// 서버 경로·계정 정보가 보이므로 보드 로그인과 별도의 비밀번호(data/devgate.json)로 잠근다.

const fmtBytes = (n) => n == null ? "-" : n < 1024 ? `${n} B` : n < 1048576 ? `${(n / 1024).toFixed(1)} KB` : n < 1073741824 ? `${(n / 1048576).toFixed(1)} MB` : `${(n / 1073741824).toFixed(2)} GB`;
const fmtDur = (sec) => { const d = Math.floor(sec / 86400), h = Math.floor((sec % 86400) / 3600), m = Math.floor((sec % 3600) / 60); return d ? `${d}일 ${h}시간` : h ? `${h}시간 ${m}분` : `${m}분`; };
const fmtTime = (t) => t ? new Date(t).toLocaleString() : "-";
const code = (s) => `<code>${esc(s)}</code>`;

// ---------- 잠금 화면 ----------
async function adminView() {
  const body = $("#adminBody");
  let gate;
  try { gate = await api("/api/devgate"); } catch (e) { body.innerHTML = `<div class="card err">${esc(e.message)}</div>`; return; }
  if (!gate.unlocked) return adminGate(body, gate.configured);
  let info;
  try { info = await api("/api/admin/info"); }
  catch (e) { body.innerHTML = `<div class="card err">${esc(e.message)}</div>`; return; }
  adminRender(body, info);
}

function adminGate(body, configured, msg = "") {
  body.innerHTML = `<article class="admin"><div class="dg-bar"><h2>개발구성</h2></div>
    <form class="card dg-lock" id="dgForm">
      <h3>🔒 ${configured ? "개발구성 화면 잠금 해제" : "개발구성 화면 비밀번호 정하기"}</h3>
      <p class="sub" style="margin:0 0 10px">서버 경로·계정·인프라 정보가 보이는 화면이라 보드 로그인과 별도의 비밀번호로 잠급니다.${configured ? "" : " 처음이라 비밀번호를 정해 주세요 (6자 이상)."}</p>
      ${msg ? `<div class="card err" style="margin:0 0 10px;padding:8px 10px">${esc(msg)}</div>` : ""}
      <input type="password" id="dgPw" placeholder="비밀번호" autocomplete="${configured ? "current-password" : "new-password"}" required minlength="${configured ? 1 : 6}" />
      ${configured ? "" : `<input type="password" id="dgPw2" placeholder="비밀번호 확인" autocomplete="new-password" required minlength="6" />`}
      <button class="primary" style="margin-top:10px">${configured ? "잠금 해제" : "비밀번호 정하고 열기"}</button>
    </form></article>`;
  $("#dgPw").focus();
  $("#dgForm").addEventListener("submit", async (e) => {
    e.preventDefault();
    const pw = $("#dgPw").value;
    if (!configured && pw !== $("#dgPw2").value) return adminGate(body, configured, "비밀번호 확인이 다릅니다.");
    try {
      await api(configured ? "/api/devgate/unlock" : "/api/devgate/setup", { method: "POST", body: { password: pw } });
      adminView();
    } catch (err) { adminGate(body, configured, err.message); }
  });
}

// ---------- 본문 ----------
function adminRender(body, i) {
  const memUsed = i.host.memTotal - i.host.memFree;
  const tiles = [
    [fmtDur(i.app.uptimeSec), `앱 가동 시간 (마지막 재시작 ${fmtTime(i.app.startedAt)})`],
    [fmtBytes(i.totals.size), `데이터 크기 (파일 ${i.totals.files.toLocaleString()}개)`],
    [i.disk ? fmtBytes(i.disk.free) : "-", i.disk ? `디스크 남은 공간 (전체 ${fmtBytes(i.disk.total)})` : "디스크 정보 없음"],
    [fmtBytes(memUsed), `메모리 사용 (전체 ${fmtBytes(i.host.memTotal)}, 앱 ${fmtBytes(i.app.rss)})`],
    [`${i.tickets.total}건`, `개발 요청 (진행 ${i.tickets.active} · 완료 ${i.tickets.done})`],
    [`${i.systems.length}개`, `SAP 시스템 (기본 ${esc(i.current ?? "-")})`],
  ];
  const tunnel = i.tunnels[0] ?? null;
  const git = i.git;

  body.innerHTML = `<article class="admin">
    <div class="dg-bar"><h2>개발구성</h2></div>
    <div class="dg-tools">
      <span class="sub" style="margin:0"><b>조회 시각</b> ${fmtTime(i.now)}</span>
      <span class="row" style="gap:6px"><button class="small" id="dgRefresh">새로 고침</button><button class="small" id="dgChange">비밀번호 바꾸기</button><button class="small" id="dgLock">🔒 잠그기</button></span>
    </div>
    <div class="dg-tiles">${tiles.map(([v, l]) => `<div class="dg-tile"><b>${v}</b><span>${l}</span></div>`).join("")}</div>

    <div class="card"><h3>한눈에 보는 구성도</h3>${adminDiagram(i, tunnel)}</div>

    <div class="card"><h3>구성 요소</h3>
      ${dgTable(["구분", "사용 기술 · 서비스", "위치 · 설정", "역할", "비용"], [
        ["접속 주소", "Cloudflare Quick Tunnel (무료)", tunnel ? `${code(tunnel)}${i.tunnels.length > 1 ? ` <span class="warn-t">외 ${i.tunnels.length - 1}개 실행 중</span>` : ""}` : `<span class="warn-t">터널 꺼짐</span> · 로컬 ${code(`http://localhost:${i.app.port}`)}`, "외부 → 이 PC 연결 (주소는 터널 재시작마다 바뀜)", "무료"],
        ["서버", "개인 PC (상시 켜 둠)", `호스트 ${esc(i.host.name)} · ${esc(i.host.cpu)} · 메모리 ${fmtBytes(i.host.memTotal)}`, "보드·AI 작업 실행", "-"],
        ["운영체제", esc(i.host.os), `켜진 시간 ${fmtDur(i.host.uptimeSec)}`, "서버 OS", "-"],
        ["앱", `Node.js ${esc(i.app.node)} · Express ${esc(i.app.express)}`, `${code(i.app.cwd)} · ${code("npm start")} · 포트 ${i.app.port}`, "화면 · API · 개발계 반영 · 로그인", "무료"],
        ["데이터 저장", "파일 (JSON · Markdown · ABAP, 별도 DB 없음)", code("work/ · wiki/ · standards/ · data/"), "모든 데이터 (아래 표)", "-"],
        ["AI 작업", `Claude Code CLI 헤드리스 ${i.claude ? code(i.claude) : ""}`, `${code("claude -p")} · PL + 서브에이전트 4종`, "분석 · 설계 · 개발 · 테스트 · AI 검증 · 위키 정리", "사용량만큼"],
        ["SAP 조회", "ABAP MCP 서버 (mcp-abap-adt)", `~/.claude.json 등록 ${i.systems.length}개 · 세션에 ${code("sap")} 이름으로 연결`, "에이전트의 테이블·소스 조회 (읽기 전용)", "-"],
        ["개발계 반영", "SAP ADT REST API", `기본 ${esc(i.current ?? "-")} · ${code("src/adt.ts")}`, "이송요청 · 오브젝트 생성 · 활성화 · ABAP Unit", "-"],
        ["보고서 출력", "pptxgenjs · exceljs · mermaid (CDN)", "브라우저에서 생성 후 내려받기", "단계 산출물 PPT · 테스트결과서 엑셀 · 다이어그램", "무료"],
        ["로그인", "서명 쿠키 (HMAC)", i.auth ? `<span class="ok-t">BOARD_PASSWORD 설정됨</span>` : `<span class="warn-t">미설정 — 외부 접속 위험</span>`, "모든 화면 · API 보호", "-"],
        ["소스 관리", "GitHub 공개 저장소", git ? `${esc(git.branch)} 브랜치 · ${code(git.head)} (${fmtTime(git.at)})${git.dirty ? ` · <span class="warn-t">커밋 안 한 변경 ${git.dirty}개</span>` : ""}` : "확인 불가", "코드 · 산출물 · 위키 보관", "무료"],
        ["배포", "git pull + 서버 재시작", code("git pull && npm start"), "코드 반영 (데이터 폴더는 그대로)", "-"],
      ])}</div>

    <div class="card"><h3>데이터 저장 위치 <span class="sub">(${esc(i.app.cwd)})</span></h3>
      ${dgTable(["파일 · 폴더", "내용", "크기", "파일 수", "GitHub", "마지막 변경"], i.data.map((d) => [
        code(d.key), esc(d.what), `<span class="num">${fmtBytes(d.st.size)}</span>`, `<span class="num">${d.st.files.toLocaleString()}</span>`,
        d.git ? "올라감" : `<span class="ok-t">제외</span>`, `<span class="num">${d.st.mtime ? fmtTime(d.st.mtime) : "-"}</span>`]))}
      <p class="sub" style="margin:8px 0 0">work/ · wiki/ · standards/ 는 GitHub 공개 저장소에 올라갑니다 (현업 요청·ABAP 소스 포함). data/ · .env 는 .gitignore 로 제외됩니다.</p></div>

    <div class="card"><h3>백업</h3>
      ${dgTable(["백업", "방식", "위치", "보관", "현재 상태"], [
        ["① GitHub 커밋", "작업 후 수동 커밋 · 푸시", code(git?.remote ?? "-"), "전체 이력", git ? `마지막 ${code(git.head)} ${fmtTime(git.at)}${git.dirty ? ` · <span class="warn-t">미커밋 ${git.dirty}개</span>` : ""}` : "확인 불가"],
        ["② 위키 이전 버전", "문서가 바뀔 때 서버가 자동 보관", code("wiki/.history"), "계속 보관", `${i.data.find((d) => d.key === "wiki/.history/")?.st.files ?? 0}개`],
        ["③ 개발표준 이전 버전", "핸드북 저장 때 자동 보관", code("standards/.history"), "계속 보관", "standards/ 크기에 포함"],
        ["④ 휴지통", "요청 삭제 시 폴더째 이동", code("work/.trash"), "영구 삭제 전까지", `${i.data.find((d) => d.key === "work/.trash/")?.st.files ?? 0}개 파일`],
        ["⑤ 설정 · 비밀번호", "백업 없음", code("data/ · .env"), "-", `<span class="warn-t">PC 장애 시 다시 설정 필요</span>`],
      ])}
      <p class="sub" style="margin:8px 0 0">자동 정기 백업(예약 작업)은 아직 없습니다. GitHub 푸시가 사실상 유일한 외부 백업입니다.</p></div>

    <div class="grid2">
      <div class="card"><h3>보안 구성</h3><ul class="dg-list">
        <li>외부 접속은 Cloudflare Tunnel HTTPS · 보드 로그인 ${i.auth ? "켜짐" : "<b class=\"warn-t\">꺼짐</b>"} (BOARD_PASSWORD, 서명 쿠키 HttpOnly · SameSite=Lax · HTTPS면 Secure, 14일)</li>
        <li>로그인 10번 틀리면 15분 잠금 (IP별) · 개발구성 화면은 별도 비밀번호 (scrypt 해시, 5번 틀리면 5분 잠금, 해제 12시간)</li>
        <li>SAP 계정은 MCP 서버 설정(~/.claude.json · env 파일)에만 있고 화면 · GitHub에 나가지 않음. 헤드리스 세션용 임시 MCP 설정 파일은 작업이 끝나면 지움</li>
        <li>에이전트는 SAP 조회만 (읽기 전용 MCP 도구). SAP 쓰기는 팀장이 보드에서 개발계 반영을 승인할 때만, 운영계 반영 없음</li>
        <li>위키 정리 세션은 wiki/ 에만 쓸 수 있음 · AI 검증 · 영향분석 세션은 읽기 전용</li>
        <li class="warn-t">GitHub 저장소가 공개 — work/ 의 현업 요청 · ABAP 소스 · 사내 SAP 호스트명이 공개됨</li>
        <li class="warn-t">서버가 모든 네트워크 주소(0.0.0.0:${i.app.port})에서 받음 — 같은 사내망에서도 접속 가능 (로그인으로 보호)</li>
      </ul></div>
      <div class="card"><h3>서버 설정</h3><ul class="dg-list">
        <li>포트 ${i.app.port} · 받는 주소 0.0.0.0 · PID ${i.app.pid}</li>
        <li>시간대 ${esc(i.app.tz)} · HTTPS 판단은 Cloudflare 전달 헤더(trust proxy loopback)</li>
        <li>SAP 시스템 ${i.systems.length}개 · 기본 ${esc(i.current ?? "-")}</li>
        <li>PC 켜진 시간 ${fmtDur(i.host.uptimeSec)} · 앱 재시작 ${fmtTime(i.app.startedAt)}</li>
        <li>재시작하면 진행 중이던 AI 작업은 실패로 표시됨 (에이전트 오피스에서 '업무 중' 0 확인 후 재시작)</li>
      </ul>
      <div class="sub" style="margin:10px 0 4px">업데이트 명령</div>
      <pre class="dg-cmd">git pull
npm start</pre>
      <div class="sub" style="margin:10px 0 4px">외부 접속 터널</div>
      <pre class="dg-cmd">"C:\\Program Files (x86)\\cloudflared\\cloudflared.exe" tunnel --url http://localhost:${i.app.port}</pre></div>
    </div>

    <div class="card"><h3>SAP 시스템 (ABAP MCP 서버)</h3>
      ${dgTable(["이름", "접속 주소", "클라이언트", "계정", "SAP_BASIS"], i.systems.map((x) => [
        `${esc(x.name)}${x.name === i.current ? ' <span class="badge done">기본</span>' : ""}`, code(x.url), esc(x.client), esc(x.user), `<span class="sysrel" data-sysrel="${esc(x.name)}"></span>`]))}</div>
  </article>`;

  fillReleases(body);
  $("#dgRefresh").addEventListener("click", adminView);
  $("#dgLock").addEventListener("click", async () => { await api("/api/devgate/lock", { method: "POST" }); adminView(); });
  $("#dgChange").addEventListener("click", async () => {
    const current = prompt("현재 개발구성 비밀번호");
    if (current == null) return;
    const next = prompt("새 비밀번호 (6자 이상)");
    if (next == null) return;
    if (prompt("새 비밀번호 확인") !== next) return alert("새 비밀번호 확인이 다릅니다.");
    try { await api("/api/devgate/change", { method: "POST", body: { current, next } }); alert("비밀번호를 바꿨습니다."); }
    catch (e) { alert(e.message); }
  });
}

const dgTable = (head, rows) => `<div class="dg-table"><table><thead><tr>${head.map((h) => `<th>${h}</th>`).join("")}</tr></thead>
  <tbody>${rows.map((r) => `<tr>${r.map((c, k) => `<td${k === 0 ? ' class="a-key"' : ""}>${c}</td>`).join("")}</tr>`).join("")}</tbody></table></div>`;

// ---------- 구성도 (박스 + 화살표, 레이아웃은 CSS grid) ----------
function adminDiagram(i, tunnel) {
  const box = (cls, icon, title, lines) => `<div class="dg-box ${cls}"><div class="dg-bt">${icon} ${title}</div>${lines.map((l) => `<div>${l}</div>`).join("")}</div>`;
  const arrow = (label, dir = "r") => `<div class="dg-arrow dg-${dir}"><span>${label}</span></div>`;
  return `<div class="dg-diagram">
    <div class="dg-col">
      ${box("c-user", "👤", "사용자", ["팀장 · PC/모바일 브라우저", "로그인 후 승인 · 수정 지시"])}
      ${box("c-dev", "🐙", "GitHub", [esc(i.git?.remote?.replace(/^https:\/\/github.com\//, "") ?? "저장소"), "코드 · 산출물 · 위키 (공개)"])}
    </div>
    <div class="dg-col dg-mid">
      ${arrow("HTTPS")}
      ${box("c-edge", "🌐", "Cloudflare Tunnel", [tunnel ? esc(tunnel.replace(/^https:\/\//, "")) : "터널 꺼짐", "trycloudflare 임시 주소 (무료)"])}
      ${arrow("git push (수동)", "l")}
    </div>
    <div class="dg-group">
      <div class="dg-gt">🖥 보드 서버 PC · ${esc(i.host.name)}</div>
      <div class="sub" style="margin:0 0 10px">${esc(i.host.os)} · 메모리 ${fmtBytes(i.host.memTotal)} · 디스크 남음 ${i.disk ? fmtBytes(i.disk.free) : "-"}</div>
      ${box("c-proxy", "🔒", "cloudflared", ["터널 → http://localhost:" + i.app.port, `보드 로그인 ${i.auth ? "켜짐" : "꺼짐"}`])}
      <div class="dg-down"></div>
      ${box("c-app", "⚙️", "Node.js 앱 (src/server.ts)", [`npm start · Express · ${esc(i.app.node)}`, "화면 · API · 개발계 반영 · 로그인"])}
      <div class="dg-split"><div class="dg-down"><span>단계 작업</span></div><div class="dg-down"><span>읽기 · 쓰기</span></div></div>
      <div class="dg-row2">
        ${box("c-ai", "🤖", "Claude Code 헤드리스", ["claude -p · PL + 서브에이전트", "MCP sap (조회 전용)"])}
        ${box("c-data", "🗄", "파일 저장 (DB 없음)", [`work/ · wiki/ · standards/ · data/`, `${fmtBytes(i.totals.size)} · 파일 ${i.totals.files.toLocaleString()}개`])}
      </div>
    </div>
    <div class="dg-col dg-mid">
      ${arrow("모델 호출")}
      ${arrow("ADT HTTPS")}
      ${arrow("CDN (브라우저)")}
    </div>
    <div class="dg-col">
      ${box("c-api", "🧠", "Claude API", ["Anthropic", "단계 작업 · AI 검증 · 위키 정리"])}
      ${box("c-sap", "🏭", "SAP 개발계", [`ADT REST · ${i.systems.length}개 시스템`, "조회(MCP) · 개발계 반영 · SAP_BASIS"])}
      ${box("c-cdn", "📦", "jsDelivr CDN", ["mermaid · pptxgenjs · exceljs", "보고서 · 다이어그램 생성"])}
    </div>
  </div>`;
}
