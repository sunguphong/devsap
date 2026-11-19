// 관리자: 이 보드를 구성하는 인프라를 한눈에 본다 (구성도 + 저장소·기능·외부 연결 표 + 실시간 운영 상태)
// 구성도·표는 코드 구조(src/*.ts)를 기준으로 적은 것이고, 숫자·주소·버전은 /api/admin/info 와 SAP_BASIS 조회로 채운다.

const ADMIN_DIAGRAM = `flowchart LR
  subgraph USER["사용자"]
    B1["팀장 브라우저<br/>(외부)"]
    B2["로컬 브라우저<br/>localhost:3300"]
  end
  subgraph EDGE["Cloudflare"]
    CF["Cloudflare Tunnel<br/>trycloudflare.com 임시 주소"]
  end
  subgraph PC["보드 서버 PC (Windows)"]
    CFD["cloudflared"]
    S["보드 서버<br/>Node.js + Express :3300<br/>로그인 BOARD_PASSWORD"]
    CC["Claude Code 헤드리스<br/>claude -p · PL + 서브에이전트"]
    MCP["ABAP MCP 서버<br/>mcp-abap-adt (sap 이름으로 연결)"]
    subgraph FS["저장소 (로컬 파일)"]
      W[("work/ 요청·산출물<br/>ticket.json · *.md · src/*.abap")]
      WK[("wiki/ 지식 위키<br/>.history 이전 버전")]
      ST[("standards/ 개발표준")]
      D[("data/settings.json<br/>.env 비밀번호·접속정보")]
      CJ[("~/.claude.json<br/>MCP 서버 등록")]
    end
  end
  subgraph EXT["외부 서비스"]
    AN["Anthropic API<br/>Claude 모델"]
    SAP["SAP 개발계<br/>ADT REST (HTTPS)"]
    GH["GitHub<br/>sunguphong/devsap"]
    CDN["jsDelivr CDN<br/>mermaid · pptxgenjs · exceljs"]
    GS["Google Sheets<br/>첨부 가져오기"]
  end
  B1 -->|HTTPS| CF --> CFD -->|http| S
  B2 -->|http| S
  B1 -.->|라이브러리| CDN
  S -->|읽기·쓰기| W
  S --> WK
  S --> ST
  S --> D
  S -->|시스템 목록| CJ
  S -->|단계 작업 실행| CC
  CC -->|모델 호출| AN
  CC -->|산출물 작성| W
  CC -->|조회 전용| MCP -->|ADT 읽기| SAP
  S -->|개발계 반영·SAP_BASIS 조회| SAP
  S -->|CSV 내려받기| GS
  W -.->|"git push 수동"| GH`;

const ADMIN_STORAGE = [
  ["work/&lt;요청ID&gt;/", "개발 요청 1건의 모든 것: ticket.json(상태·로그), request.md, 01~04 산출물, src/*.abap 소스, attachments/ 첨부, changes/ 변경요청 첨부, .deck/ 보고용 요약", "파일 (JSON·Markdown·ABAP)", "src/store.ts"],
  ["work/.trash/", "삭제한 요청 (복원 가능, 영구 삭제 시 제거)", "폴더 이동", "src/store.ts"],
  ["wiki/", "지식 위키 문서. 바뀐 문서의 이전 버전은 wiki/.history/", "Markdown", "src/wiki.ts · lessons.ts"],
  ["standards/", "개발표준 핸드북. 이전 버전은 standards/.history/", "Markdown", "src/standards.ts"],
  ["data/settings.json", "보드 기본 SAP 시스템 선택값", "JSON (git 제외)", "src/systems.ts"],
  [".env", "BOARD_PASSWORD(로그인), 포트, 보조 SAP 접속정보", "환경 변수 (git 제외)", "src/auth.ts"],
  ["~/.claude.json · .mcp.json", "SAP 시스템 = 등록된 ABAP MCP 서버 (접속 URL·계정). --env-path 파일도 읽음", "Claude Code 설정", "src/systems.ts"],
  ["GitHub 저장소", "코드 + work/ + wiki/ 백업·이력 (수동 커밋·푸시)", "git", "—"],
];

const ADMIN_FEATURES = [
  ["웹 보드", "요청 등록·단계 승인·수정 지시·변경요청·첨부·휴지통", "Express 5 정적 파일 + REST API, 바닐라 JS", "src/server.ts · public/*.js"],
  ["로그인", "외부 접속 시 모든 화면·API 보호 (서명 쿠키 14일, IP별 시도 제한)", "HMAC 쿠키 (node:crypto)", "src/auth.ts"],
  ["단계 작업 (AI)", "분석→설계→개발→테스트를 서브에이전트가 수행, PL이 1차 검토", "Claude Code 헤드리스 claude -p, JSON 스키마 출력", "src/runner.ts · .claude/agents/"],
  ["SAP 조회", "에이전트가 테이블·구조·클래스 등을 읽기 전용으로 확인", "ABAP MCP 서버 (mcp__sap__*)", "src/systems.ts"],
  ["개발계 반영", "이송요청 생성 → 메시지 클래스·함수 그룹·프로그램·클래스·함수 모듈 생성 → 활성화 → ABAP Unit", "SAP ADT REST API", "src/adt.ts · board.ts"],
  ["AI 검증 · 변경 영향분석", "작업 PL과 별개인 읽기 전용 세션이 산출물 검증 / CR 영향 단계 권고", "Claude Code 헤드리스 (읽기 전용)", "src/verify.ts · changes.ts"],
  ["지식 위키 정리", "단계 완료·반영 후 배운 점을 주제별 문서로", "Claude Code 헤드리스 (wiki/ 쓰기만)", "src/lessons.ts"],
  ["보고 자료", "단계 산출물 PPTX·테스트결과서 XLSX·다이어그램", "브라우저에서 pptxgenjs · exceljs · mermaid (CDN)", "public/stagepptx.js · testresult.js"],
  ["에이전트 오피스", "에이전트별 업무·평면도·상태 레인", "/api/office 집계", "public/office.js"],
  ["외부 접속", "어디서든 보드 접속", "Cloudflare Quick Tunnel (cloudflared)", "—"],
];

const ADMIN_LINKS = [
  ["Anthropic API", "Claude Code가 모델 호출", "HTTPS", "Claude Code 로그인 계정"],
  ["SAP 개발계 (ADT)", "조회(MCP)·개발계 반영·SAP_BASIS 조회", "HTTPS /sap/bc/adt/*", "MCP 서버 env의 SAP 계정 (Basic)"],
  ["Cloudflare", "외부 → 이 PC 터널", "HTTPS → cloudflared → http://localhost:3300", "보드 로그인 (BOARD_PASSWORD)"],
  ["GitHub", "코드·산출물 저장소", "git push", "gh 로그인 계정"],
  ["jsDelivr CDN", "브라우저가 다이어그램·PPTX·XLSX 라이브러리 로드", "HTTPS", "없음 (공개)"],
  ["Google Sheets", "링크 공유 시트를 첨부로 가져오기", "HTTPS CSV 내보내기", "없음 ('링크가 있는 모든 사용자' 공유 필요)"],
];

const adminTable = (head, rows) => `<div class="hb-table"><table><thead><tr>${head.map((h) => `<th>${h}</th>`).join("")}</tr></thead>
  <tbody>${rows.map((r) => `<tr>${r.map((c, i) => `<td${i === 0 ? ' class="a-key"' : ""}>${c}</td>`).join("")}</tr>`).join("")}</tbody></table></div>`;

function adminUptime(sec) {
  const d = Math.floor(sec / 86400), h = Math.floor((sec % 86400) / 3600), m = Math.floor((sec % 3600) / 60);
  return d ? `${d}일 ${h}시간` : h ? `${h}시간 ${m}분` : `${m}분`;
}

async function adminView() {
  const body = $("#adminBody");
  let info;
  try { info = await api("/api/admin/info"); } catch (e) { body.innerHTML = `<div class="card err">${esc(e.message)}</div>`; return; }
  const s = info.server;
  const tiles = [
    ["보드 서버", `Node ${esc(s.node)}`, `:${s.port} · 가동 ${adminUptime(s.uptimeSec)}`],
    ["로그인", info.auth ? "사용" : "미사용", info.auth ? "BOARD_PASSWORD" : "외부 공개 시 위험"],
    ["SAP 시스템", `${info.systems.length}개`, `기본 ${esc(info.current ?? "-")}`],
    ["개발 요청", `${info.storage.tickets}건`, `진행 ${info.storage.active} · 휴지통 ${info.storage.trash}`],
    ["지식 위키", `${info.storage.wiki}개`, `이전 버전 ${info.storage.wikiHistory}개`],
  ];
  body.innerHTML = `<article class="admin">
    <div class="o-hero">
      <div class="o-hero-l">
        <div class="o-tags"><span class="o-tag on">관리자</span><span class="o-tag">인프라 구성</span></div>
        <div class="o-kicker">SAP 개발 관리 보드</div>
        <h2>인프라 구성도</h2>
        <div class="o-lead">어디에 저장하고, 어떤 기능·서비스로 동작하는지 한눈에 봅니다. ${esc(s.host)} · ${esc(s.platform)}</div>
      </div>
      <div class="o-tiles a-tiles">${tiles.map(([l, v, sub]) => `<div class="o-tile"><span>${l}</span><b class="a-v">${v}</b><span>${sub}</span></div>`).join("")}</div>
    </div>

    <div class="card"><h3>🗺 전체 구성도</h3>
      <p class="sub" style="margin:0 0 8px">실선은 상시 동작, 점선은 수동·보조 경로입니다. 그림을 누르면 크게 볼 수 있습니다.</p>
      <pre class="mermaid">${esc(ADMIN_DIAGRAM)}</pre></div>

    <div class="grid2">
      <div class="card"><h3>💾 저장소 — 무엇을 어디에 저장하나</h3>
        ${adminTable(["위치", "내용", "형식", "담당 코드"], ADMIN_STORAGE)}</div>
      <div class="card"><h3>🔗 외부 연결</h3>
        ${adminTable(["대상", "용도", "방식", "인증"], ADMIN_LINKS)}</div>
    </div>

    <div class="card"><h3>⚙️ 기능별 구성 — 어떤 기술로 동작하나</h3>
      ${adminTable(["기능", "하는 일", "사용 기술", "코드"], ADMIN_FEATURES)}</div>

    <div class="grid2">
      <div class="card"><h3>🖥 SAP 시스템 (ABAP MCP 서버)</h3>
        ${adminTable(["이름", "접속 주소", "클라이언트", "계정", "SAP_BASIS"], info.systems.map((x) => [
          `${esc(x.name)}${x.name === info.current ? ' <span class="badge done">기본</span>' : ""}`, esc(x.url), esc(x.client), esc(x.user),
          `<span class="sysrel" data-sysrel="${esc(x.name)}"></span>`]))}</div>
      <div class="card"><h3>📦 서버 · 저장소 현황</h3>
        ${adminTable(["항목", "값"], [
          ["작업 폴더", esc(s.cwd)],
          ["서버 프로세스", `PID ${s.pid} · ${esc(s.platform)}`],
          ["GitHub", info.git ? `${esc(info.git.remote)} (${esc(info.git.branch)})` : "확인 불가"],
          ["최근 커밋", info.git ? esc(info.git.head) : "-"],
          ["개발표준 이전 버전", `${info.storage.standardsHistory}개`],
          ["외부 접속", "Cloudflare Quick Tunnel — 주소는 터널을 다시 켤 때마다 바뀝니다"],
        ])}</div>
    </div>
  </article>`;
  fillReleases(body);
  renderDiagrams();
}
