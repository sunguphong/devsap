import express from "express";
import type { NextFunction, Request, Response } from "express";
import { AdtClient } from "./adt.ts";
import { authEnabled, loginRoutes, requireLogin } from "./auth.ts";
import { attachmentPath, checkGoogleSheet, deleteAttachment, importGoogleSheet, listAttachments, MAX_SIZE, saveAttachment } from "./attachments.ts";
import { currentSystem, listSystems, resolveSystem, sapConfig, selectSystem } from "./systems.ts";
import { approveDeploy, approveStage, failStage, hooks, isBusy, recoverInterrupted, revise } from "./board.ts";
import { addChange, applyChanges, decideChange, recoverChanges } from "./changes.ts";
import { deckStatus, getDeck, isDeckBuilding, runDeck } from "./deck.ts";
import { isLearning, runLessons } from "./lessons.ts";
import { isWorking, recoverStale, runStage, stopRun } from "./runner.ts";
import { createTicket, deleteTicket, getTicket, listTickets, listTrash, log, purgeTicket, readRequest, restoreTicket, stageFiles } from "./store.ts";
import { TEAM, WORK_STAGES } from "./types.ts";
import { getHandbook, saveHandbook } from "./standards.ts";
import { recoverVerifications, runVerify } from "./verify.ts";
import { allPages, getPage, savePage, search } from "./wiki.ts";

if (process.env.SAP_INSECURE_TLS === "1") process.env.NODE_TLS_REJECT_UNAUTHORIZED = "0";

const app = express();
app.set("trust proxy", "loopback"); // Cloudflare Tunnel(cloudflared)이 같은 PC에서 넘겨 주는 https 정보를 믿는다
app.use(express.json({ limit: "2mb" }));
app.use(express.urlencoded({ extended: false, limit: "8kb" }));
loginRoutes(app);
app.use(requireLogin);
app.use(express.static("public"));

const wrap = (fn: (req: Request, res: Response) => unknown) => async (req: Request, res: Response, next: NextFunction) => {
  try {
    await fn(req, res);
  } catch (e) {
    next(e);
  }
};

// 시스템별 SAP_BASIS 버전 (CVERS 조회 결과를 12시간 캐시). 실패는 5분만 캐시해 곧 다시 시도한다
const releaseCache = new Map<string, { at: number; ttl: number; value: { release: string; sp: number; label: string } | null; error?: string }>();
app.get("/api/systems/:name/release", wrap(async (req, res) => {
  const name = resolveSystem(String(req.params.name));
  if (!name) return res.json({ name: null, value: null, error: "등록된 SAP 시스템이 없습니다." });
  const hit = releaseCache.get(name);
  if (hit && Date.now() - hit.at < hit.ttl) return res.json({ name, value: hit.value, error: hit.error ?? null });
  const cfg = sapConfig(name);
  if (!cfg) return res.json({ name, value: null, error: "접속 정보가 없습니다." });
  try {
    const r = await new AdtClient(cfg).basisRelease();
    const value = r ? { ...r, label: `${r.release} SP${String(r.sp).padStart(2, "0")}` } : null;
    releaseCache.set(name, { at: Date.now(), ttl: 12 * 3600_000, value, error: value ? undefined : "CVERS에 SAP_BASIS가 없습니다." });
    res.json({ name, value, error: value ? null : "CVERS에 SAP_BASIS가 없습니다." });
  } catch (e) {
    releaseCache.set(name, { at: Date.now(), ttl: 5 * 60_000, value: null, error: (e as Error).message });
    res.json({ name, value: null, error: (e as Error).message });
  }
}));

app.get("/api/status", (_req, res) => {
  const sap = sapConfig();
  res.json({ team: TEAM, sap: sap ? { url: sap.url, client: sap.client, user: sap.user } : null, systems: listSystems(), system: currentSystem(), auth: authEnabled() });
});

// 접속할 SAP 시스템(등록된 ABAP MCP 서버) 선택. 이후 시작하는 작업·검증·개발계 반영부터 적용된다
app.put("/api/sap/system", wrap((req, res) => {
  selectSystem(String(req.body?.name ?? ""));
  res.json({ ok: true, system: currentSystem() });
}));

app.post(
  "/api/sap/test",
  wrap(async (_req, res) => {
    const cfg = sapConfig();
    if (!cfg) return res.status(400).json({ error: "SAP 접속 정보가 없습니다. MCP 서버의 SAP_URL·SAP_USERNAME·SAP_PASSWORD(또는 .env)를 확인해 주세요." });
    res.json({ message: await new AdtClient(cfg).ping() });
  }),
);

// 구글시트 링크 연결 확인 (저장하지 않음)
app.post("/api/gsheet/check", wrap(async (req, res) => {
  res.json(await checkGoogleSheet(String(req.body?.url ?? "")));
}));

app.get("/api/tickets", (_req, res) => {
  res.json(
    listTickets().map(({ id, title, status, currentStage, createdAt, updatedAt, system }) => ({ id, title, status, currentStage, createdAt, updatedAt, system: resolveSystem(system) })),
  );
});

app.post(
  "/api/tickets",
  wrap((req, res) => {
    const { title, request, hold, system } = req.body ?? {};
    // hold: 첨부 자료를 올린 뒤 화면에서 /run 으로 분석을 시작한다
    if (!title?.trim() || (!request?.trim() && !hold)) return res.status(400).json({ error: "제목과 요청 내용(또는 첨부 자료)을 입력해 주세요." });
    if (system && !listSystems().some((s) => s.name === system)) return res.status(400).json({ error: `등록되지 않은 SAP 시스템입니다: ${system}` });
    const t = createTicket(title.trim(), request?.trim() || "(첨부 자료 참고)", system || currentSystem());
    log(t, TEAM.lead.name, `새 개발 요청을 접수했습니다${t.system ? ` (대상 시스템 ${t.system})` : ""}. 요구사항 분석부터 진행합니다.`);
    if (!hold) runStage(t.id);
    res.status(201).json(t);
  }),
);

app.get("/api/tickets/:id", (req, res) => {
  const t = getTicket(req.params.id);
  if (!t) return res.status(404).json({ error: "요청을 찾을 수 없습니다." });
  const files = Object.fromEntries(WORK_STAGES.map((s) => [s, stageFiles(t.id, s)]));
  const changes = (t.changes ?? []).map((c) => ({ ...c, attachments: listAttachments(t.id, c.id) }));
  res.json({ ...t, system: resolveSystem(t.system), changes, request: readRequest(t.id), files, attachments: listAttachments(t.id), busy: isBusy(t.id) || isWorking(t.id), learning: isLearning(t.id), decks: deckStatus(t.id) });
});

app.post("/api/tickets/:id/approve-stage", wrap((req, res) => {
  const id = req.params.id as string;
  approveStage(id);
  const status = getTicket(id)?.status;
  if (status === "in_progress") runStage(id);
  // 분석~테스트가 모두 승인되면 배운 점을 위키에 정리한다
  if (status === "awaiting_deploy" && !isLearning(id)) runLessons(id, "approved");
  res.json({ ok: true });
}));

app.post("/api/tickets/:id/revise", wrap((req, res) => {
  const id = req.params.id as string;
  // 작업 중이면 중단하고 지정한 단계로 돌아간다
  if (stopRun(id)) log(getTicket(id)!, "팀장", "⏹ 진행 중인 작업을 중단했습니다.");
  revise(id, req.body?.stage ?? "", req.body?.feedback ?? "");
  runStage(id);
  res.json({ ok: true });
}));

// 요청 삭제 (work/.trash/ 로 옮김). 헤드리스 세션이 그 폴더에 쓰는 중이면 막는다
app.delete("/api/tickets/:id", wrap((req, res) => {
  const id = req.params.id as string;
  const t = getTicket(id);
  if (!t) return res.status(404).json({ error: "요청을 찾을 수 없습니다." });
  const verifying = Object.values(t.stages).some((s) => s.verifications?.some((v) => v.status === "running"));
  const analyzing = t.changes?.some((c) => c.status === "analyzing");
  if (isBusy(id) || isWorking(id) || isLearning(id) || isDeckBuilding(id) || verifying || analyzing)
    throw new Error("작업·검증·영향분석·위키 정리·보고 자료 요약 중인 요청은 삭제할 수 없습니다. 작업을 중단하거나 끝난 뒤 삭제해 주세요.");
  deleteTicket(id);
  res.json({ ok: true });
}));

// ---------- 에이전트 오피스 (에이전트별 현재 업무·대기열·최근 활동) ----------

app.get("/api/office", (_req, res) => {
  const tickets = listTickets();
  const brief = (t: (typeof tickets)[number], extra: Record<string, unknown> = {}) => ({ id: t.id, title: t.title, system: resolveSystem(t.system), ...extra });
  const desks = (["lead", ...WORK_STAGES, "deploy"] as const).map((key) => {
    const m = TEAM[key];
    const working: unknown[] = [];
    const queued: unknown[] = [];
    const review: unknown[] = [];
    let approved = 0;
    let failed = 0;
    for (const t of tickets) {
      if (key === "lead") {
        for (const c of t.changes ?? []) if (c.status === "analyzing") working.push(brief(t, { what: `${c.id} 영향분석`, since: c.at }));
        for (const k of WORK_STAGES) for (const v of t.stages[k].verifications ?? [])
          if (v.status === "running") working.push(brief(t, { what: `${TEAM[k].name} AI 검증`, since: v.at }));
        if (isLearning(t.id)) working.push(brief(t, { what: "지식 위키 정리" }));
        if (isDeckBuilding(t.id)) working.push(brief(t, { what: "보고용 PPT 요약" }));
        if (t.status === "awaiting_review") review.push(brief(t, { what: `${TEAM[t.currentStage].name} 결과 보고` }));
        if (t.status === "awaiting_deploy") review.push(brief(t, { what: "개발계 반영 승인" }));
        if (t.status === "done") approved++;
        continue;
      }
      const s = t.stages[key];
      if (key === "deploy") {
        if (t.status === "deploying") working.push(brief(t, { since: s.startedAt }));
        else if (t.status === "awaiting_deploy") review.push(brief(t));
      } else if (s.status === "running" || (t.status === "in_progress" && t.currentStage === key && isWorking(t.id))) working.push(brief(t, { since: s.startedAt, attempt: s.attempts }));
      else if (t.status === "in_progress" && t.currentStage === key) queued.push(brief(t, { directive: !!s.directive, failed: s.status === "failed" }));
      else if (s.status === "review") review.push(brief(t, { attempt: s.attempts }));
      if (s.status === "approved") approved++;
      if (s.status === "failed") failed++;
    }
    const recent = tickets
      .flatMap((t) => t.logs.filter((l) => l.agent === m.name).map((l) => ({ ...l, id: t.id, title: t.title })))
      .sort((a, b) => b.at.localeCompare(a.at))
      .slice(0, 6);
    return { key, name: m.name, role: m.role, agent: m.agent ?? null, working, queued, review, approved, failed, recent };
  });
  res.json({ desks, total: tickets.length, active: tickets.filter((t) => t.status !== "done").length });
});

// ---------- 휴지통 (삭제한 요청) ----------

app.get("/api/trash", (_req, res) => {
  res.json(listTrash());
});

app.post("/api/trash/:entry/restore", wrap((req, res) => {
  const id = restoreTicket(req.params.entry as string);
  log(getTicket(id)!, "팀장", "♻️ 휴지통에서 복원했습니다.");
  res.json({ ok: true, id });
}));

app.delete("/api/trash/:entry", wrap((req, res) => {
  purgeTicket(req.params.entry as string);
  res.json({ ok: true });
}));

app.post("/api/tickets/:id/stop", wrap((req, res) => {
  const id = req.params.id as string;
  if (!stopRun(id)) throw new Error("작업 중이 아닙니다.");
  failStage(id, "팀장이 작업을 중단했습니다.");
  res.json({ ok: true });
}));

// ---------- 요청 첨부 자료 (문서·이미지) ----------

app.post("/api/tickets/:id/attachments", express.raw({ type: () => true, limit: MAX_SIZE + 1024 }), wrap((req, res) => {
  const id = req.params.id as string;
  const t = getTicket(id);
  if (!t) return res.status(404).json({ error: "요청을 찾을 수 없습니다." });
  const a = saveAttachment(id, String(req.query.name ?? ""), Buffer.isBuffer(req.body) ? req.body : Buffer.alloc(0));
  log(t, "팀장", `📎 자료 첨부 — ${a.name}${a.kind === "office" && !a.extracted ? " (텍스트 추출 실패)" : ""}`);
  res.status(201).json(a);
}));

// 구글시트 링크 → xlsx 사본을 첨부로 저장
app.post("/api/tickets/:id/gsheet", wrap(async (req, res) => {
  const id = req.params.id as string;
  if (!getTicket(id)) return res.status(404).json({ error: "요청을 찾을 수 없습니다." });
  const a = await importGoogleSheet(id, String(req.body?.url ?? ""));
  log(getTicket(id)!, "팀장", `📊 구글시트 참조 — ${a.name}${a.extracted ? "" : " (텍스트 추출 실패)"}`);
  res.status(201).json(a);
}));

app.get("/api/tickets/:id/attachments/:name", (req, res) => {
  const file = attachmentPath(req.params.id, req.params.name);
  if (!file) return res.status(404).json({ error: "첨부 파일을 찾을 수 없습니다." });
  res.sendFile(file, { headers: { "Content-Disposition": `inline; filename*=UTF-8''${encodeURIComponent(req.params.name)}` } });
});

app.delete("/api/tickets/:id/attachments/:name", wrap((req, res) => {
  const id = req.params.id as string;
  deleteAttachment(id, req.params.name as string);
  log(getTicket(id)!, "팀장", `📎 첨부 삭제 — ${req.params.name}`);
  res.json({ ok: true });
}));

// 팀장이 승인 전에 산출물 검증을 AI에게 맡긴다 (단계 상태는 그대로)
app.post("/api/tickets/:id/verify", wrap((req, res) => {
  runVerify(req.params.id as string, String(req.body?.stage ?? ""));
  res.json({ ok: true });
}));

// 보고용 PPT: 단계 산출물을 슬라이드 개요로 요약한다 (읽기 전용 세션). 개요로 슬라이드를 만드는 건 브라우저가 한다
app.post("/api/tickets/:id/deck", wrap((req, res) => {
  runDeck(req.params.id as string, String(req.body?.stage ?? ""));
  res.json({ ok: true });
}));

app.get("/api/tickets/:id/deck/:stage", wrap((req, res) => {
  res.json(getDeck(req.params.id as string, req.params.stage as string));
}));

app.post("/api/tickets/:id/lessons", wrap((req, res) => {
  runLessons(req.params.id as string, "manual");
  res.json({ ok: true });
}));

// 실패했거나 서버 재시작으로 끊긴 단계를 다시 시작
app.post("/api/tickets/:id/run", wrap((req, res) => {
  runStage(req.params.id as string);
  res.json({ ok: true });
}));

app.post("/api/tickets/:id/deploy", wrap((req, res) => {
  approveDeploy(req.params.id as string, { package: req.body?.package ?? "$TMP", transport: req.body?.transport ?? "" });
  res.json({ ok: true });
}));

// ---------- 요구사항 변경 (CR) ----------

app.post("/api/tickets/:id/changes", wrap((req, res) => {
  res.status(201).json(addChange(req.params.id as string, String(req.body?.text ?? ""), Boolean(req.body?.hold)));
}));

// CR 첨부 자료 (문서·이미지). 반영한 CR에는 더 올릴 수 없다 (이미 재작업 지시가 나감)
app.post("/api/tickets/:id/changes/:cid/attachments", express.raw({ type: () => true, limit: MAX_SIZE + 1024 }), wrap((req, res) => {
  const id = req.params.id as string;
  const cid = req.params.cid as string;
  const t = getTicket(id);
  const c = t?.changes?.find((x) => x.id === cid);
  if (!t || !c) return res.status(404).json({ error: "변경 요청을 찾을 수 없습니다." });
  if (c.status === "applied") throw new Error("이미 반영한 변경 요청에는 자료를 추가할 수 없습니다. 새 변경 요청으로 등록해 주세요.");
  const a = saveAttachment(id, String(req.query.name ?? ""), Buffer.isBuffer(req.body) ? req.body : Buffer.alloc(0), cid);
  log(t, "팀장", `📎 ${cid} 자료 첨부 — ${a.name}${a.kind === "office" && !a.extracted ? " (텍스트 추출 실패)" : ""}`);
  res.status(201).json(a);
}));

app.get("/api/tickets/:id/changes/:cid/attachments/:name", (req, res) => {
  const file = attachmentPath(req.params.id, req.params.name, req.params.cid);
  if (!file) return res.status(404).json({ error: "첨부 파일을 찾을 수 없습니다." });
  res.sendFile(file, { headers: { "Content-Disposition": `inline; filename*=UTF-8''${encodeURIComponent(req.params.name)}` } });
});

// picks: [{ id: "CR-01", stage?: "design" }] — 선택한 CR을 가장 앞 단계부터 한 번에 반영
app.post("/api/tickets/:id/changes/apply", wrap((req, res) => {
  applyChanges(req.params.id as string, Array.isArray(req.body?.picks) ? req.body.picks : []);
  res.json({ ok: true });
}));

// action: defer | reject | reanalyze | reopen
app.post("/api/tickets/:id/changes/:cid/:action", wrap((req, res) => {
  decideChange(req.params.id as string, req.params.cid as string, req.params.action as string);
  res.json({ ok: true });
}));

// ---------- 지식 위키 ----------

app.get("/api/wiki/pages", (_req, res) => {
  res.json(allPages().map(({ id, title, category, updatedAt }) => ({ id, title, category, updatedAt })));
});

app.get("/api/wiki/page", (req, res) => {
  const page = getPage(String(req.query.id ?? ""));
  if (!page) return res.status(404).json({ error: "문서를 찾을 수 없습니다." });
  res.json(page);
});

app.get("/api/wiki/search", (req, res) => {
  res.json(search(String(req.query.q ?? "")));
});

app.put("/api/wiki/page", wrap((req, res) => {
  const { id, title, markdown } = req.body ?? {};
  res.json(savePage(id || null, String(title ?? ""), String(markdown ?? "")));
}));

// ---------- 개발표준 핸드북 ----------

app.get("/api/standards", (_req, res) => {
  res.json(getHandbook());
});

app.put("/api/standards", wrap((req, res) => {
  res.json(saveHandbook(String(req.body?.markdown ?? "")));
}));

app.use((err: Error, _req: Request, res: Response, _next: NextFunction) => {
  res.status(400).json({ error: err.message });
});

recoverInterrupted(listTickets());
recoverStale();
recoverChanges(listTickets());
recoverVerifications(listTickets());
hooks.afterDeploy = (id) => {
  if (!isLearning(id)) runLessons(id, "deployed");
};

const port = Number(process.env.PORT || 3300);
app.listen(port, () => {
  console.log(`SAP 개발 관리 보드: http://localhost:${port}`);
  console.log(authEnabled() ? "로그인: 사용 (BOARD_PASSWORD)" : "로그인: 사용 안 함 — 외부에 열려면 .env 에 BOARD_PASSWORD 를 설정하세요");
  console.log(`SAP 시스템: ${currentSystem() ?? "(등록된 ABAP MCP 서버 없음 — .env 사용)"}`);
  if (!sapConfig()) console.log("SAP 접속 정보가 없어 개발계 반영은 시뮬레이션 모드로 동작합니다.");
});
