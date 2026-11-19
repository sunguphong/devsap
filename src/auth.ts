import crypto from "node:crypto";
import type { NextFunction, Request, Response } from "express";

// 보드 로그인. .env 의 BOARD_PASSWORD 가 있으면 모든 화면·API에 로그인을 요구한다 (Cloudflare Tunnel 등으로 외부에 열 때).
// 없으면 로그인 없이 동작한다 (localhost 전용 사용).
// 세션은 서명한 쿠키(HMAC)로 들고 다니며 서버 메모리에 따로 저장하지 않는다. 비밀번호를 바꾸면 기존 세션은 모두 무효가 된다.

const COOKIE = "devsap_session";
const MAX_AGE_DAYS = 14;
const password = () => process.env.BOARD_PASSWORD || "";
const key = () => crypto.createHash("sha256").update(`devsap:${password()}`).digest();

export const authEnabled = () => !!password();

function sign(expires: number): string {
  const mac = crypto.createHmac("sha256", key()).update(String(expires)).digest("base64url");
  return `${expires}.${mac}`;
}

function valid(token: string | undefined): boolean {
  if (!token) return false;
  const [exp, mac] = token.split(".");
  if (!exp || !mac || Number(exp) < Date.now()) return false;
  const expected = sign(Number(exp)).split(".")[1];
  return mac.length === expected.length && crypto.timingSafeEqual(Buffer.from(mac), Buffer.from(expected));
}

function cookieOf(req: Request): string | undefined {
  return req.headers.cookie?.split(/;\s*/).find((c) => c.startsWith(`${COOKIE}=`))?.slice(COOKIE.length + 1);
}

function secure(req: Request): boolean {
  return req.secure || req.headers["x-forwarded-proto"] === "https";
}

// 비밀번호 무작위 대입을 늦춘다: IP별로 15분에 10번까지
const fails = new Map<string, { n: number; until: number }>();
function clientIp(req: Request): string {
  return String(req.headers["cf-connecting-ip"] ?? req.socket.remoteAddress ?? "");
}

const page = (msg = "") => `<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>SAP 개발팀 로그인</title><style>
body{margin:0;min-height:100vh;display:grid;place-items:center;font:14px/1.5 "Pretendard","Malgun Gothic",system-ui,sans-serif;background:linear-gradient(120deg,#111a24,#0f2e2c);color:#1d2330}
form{background:#fff;padding:28px 26px;border-radius:14px;width:min(340px,calc(100vw - 32px));box-shadow:0 20px 60px rgba(0,0,0,.35)}
h1{font-size:19px;margin:0 0 4px}p{color:#6b7385;font-size:12px;margin:0 0 16px}
input{display:block;width:100%;box-sizing:border-box;font:inherit;padding:9px 11px;border:1px solid #e2e5ea;border-radius:8px;margin-bottom:12px}
button{width:100%;font:inherit;padding:9px;border:0;border-radius:8px;background:#2463eb;color:#fff;font-weight:600;cursor:pointer}
.err{color:#dc2626;font-size:12px;margin:-4px 0 10px}</style></head><body>
<form method="post" action="/login"><h1>SAP 개발팀</h1><p>개발 관리 보드에 들어가려면 비밀번호를 입력하세요.</p>
${msg ? `<div class="err">${msg}</div>` : ""}<input type="password" name="password" placeholder="비밀번호" autofocus required autocomplete="current-password"><button>로그인</button></form></body></html>`;

export function loginRoutes(app: import("express").Express): void {
  app.get("/login", (_req, res) => res.type("html").send(page()));
  app.post("/login", (req, res) => {
    const ip = clientIp(req);
    const f = fails.get(ip);
    if (f && f.n >= 10 && f.until > Date.now()) return res.status(429).type("html").send(page("시도가 너무 많습니다. 15분 뒤에 다시 시도하세요."));
    const given = Buffer.from(String(req.body?.password ?? ""));
    const want = Buffer.from(password());
    if (given.length !== want.length || !crypto.timingSafeEqual(given, want)) {
      fails.set(ip, { n: (f && f.until > Date.now() ? f.n : 0) + 1, until: Date.now() + 15 * 60_000 });
      return res.status(401).type("html").send(page("비밀번호가 맞지 않습니다."));
    }
    fails.delete(ip);
    const expires = Date.now() + MAX_AGE_DAYS * 86_400_000;
    res.setHeader("Set-Cookie", `${COOKIE}=${sign(expires)}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${MAX_AGE_DAYS * 86400}${secure(req) ? "; Secure" : ""}`);
    res.redirect("/");
  });
  app.post("/logout", (_req, res) => {
    res.setHeader("Set-Cookie", `${COOKIE}=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0`);
    res.json({ ok: true });
  });
}

/** 로그인 확인. API는 401 JSON, 화면은 /login 으로 보낸다 */
export function requireLogin(req: Request, res: Response, next: NextFunction): void {
  if (!authEnabled() || req.path === "/login" || valid(cookieOf(req))) return next();
  if (req.path.startsWith("/api/")) {
    res.status(401).json({ error: "로그인이 필요합니다." });
    return;
  }
  res.redirect("/login");
}
