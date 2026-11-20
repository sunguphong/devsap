import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import type { Express, NextFunction, Request, Response } from "express";

// 개발구성 화면 잠금: 보드 로그인과 별도로 비밀번호를 한 번 더 묻는다 (서버 경로·계정·인프라 정보가 보이는 화면이라서).
// 비밀번호는 data/devgate.json 에 scrypt 해시로만 저장한다 (git 제외 폴더). 처음 들어오면 비밀번호를 정한다.
// 잠금 해제는 서명 쿠키(12시간)로 들고 다니며, 비밀번호를 바꾸면 기존 해제 쿠키는 모두 무효가 된다.

const FILE = path.resolve("data", "devgate.json");
const COOKIE = "devsap_gate";
const HOURS = 12;

interface Gate { salt: string; hash: string; changedAt: string }

function readGate(): Gate | null {
  try {
    return JSON.parse(fs.readFileSync(FILE, "utf8"));
  } catch {
    return null;
  }
}

const hashOf = (password: string, salt: string) => crypto.scryptSync(password, salt, 32).toString("hex");

function check(password: string): boolean {
  const g = readGate();
  if (!g) return false;
  const a = Buffer.from(hashOf(password, g.salt), "hex");
  const b = Buffer.from(g.hash, "hex");
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

function save(password: string): void {
  if (password.length < 6) throw new Error("비밀번호는 6자 이상으로 정해 주세요.");
  const salt = crypto.randomBytes(16).toString("hex");
  fs.mkdirSync(path.dirname(FILE), { recursive: true });
  fs.writeFileSync(FILE, JSON.stringify({ salt, hash: hashOf(password, salt), changedAt: new Date().toISOString() }, null, 2), { mode: 0o600 });
}

const sign = (exp: number) => {
  const g = readGate();
  return crypto.createHmac("sha256", `devgate:${g?.hash ?? ""}`).update(String(exp)).digest("base64url");
};

function unlocked(req: Request): boolean {
  const token = req.headers.cookie?.split(/;\s*/).find((c) => c.startsWith(`${COOKIE}=`))?.slice(COOKIE.length + 1);
  if (!token || !readGate()) return false;
  const [exp, mac] = token.split(".");
  if (!exp || !mac || Number(exp) < Date.now()) return false;
  const want = sign(Number(exp));
  return mac.length === want.length && crypto.timingSafeEqual(Buffer.from(mac), Buffer.from(want));
}

function setCookie(req: Request, res: Response): void {
  const exp = Date.now() + HOURS * 3600_000;
  const secure = req.secure || req.headers["x-forwarded-proto"] === "https" ? "; Secure" : "";
  res.setHeader("Set-Cookie", `${COOKIE}=${exp}.${sign(exp)}; Path=/; HttpOnly; SameSite=Strict; Max-Age=${HOURS * 3600}${secure}`);
}

// 무작위 대입 방지: 5번 틀리면 5분 잠금 (IP별)
const fails = new Map<string, { n: number; until: number }>();
const ipOf = (req: Request) => String(req.headers["cf-connecting-ip"] ?? req.socket.remoteAddress ?? "");
function guard(req: Request): void {
  const f = fails.get(ipOf(req));
  if (f && f.n >= 5 && f.until > Date.now()) throw new Error(`비밀번호를 여러 번 틀려 ${Math.ceil((f.until - Date.now()) / 60000)}분 동안 잠겼습니다.`);
}
function failed(req: Request): void {
  const ip = ipOf(req);
  const f = fails.get(ip);
  fails.set(ip, { n: (f && f.until > Date.now() ? f.n : 0) + 1, until: Date.now() + 5 * 60_000 });
}

export function devgateRoutes(app: Express): void {
  app.get("/api/devgate", (req, res) => {
    const g = readGate();
    res.json({ configured: !!g, unlocked: !!g && unlocked(req), changedAt: g?.changedAt ?? null });
  });
  app.post("/api/devgate/setup", (req, res) => {
    if (readGate()) return res.status(409).json({ error: "이미 비밀번호가 정해져 있습니다." });
    try {
      save(String(req.body?.password ?? ""));
    } catch (e) {
      return res.status(400).json({ error: (e as Error).message });
    }
    setCookie(req, res);
    res.json({ ok: true });
  });
  app.post("/api/devgate/unlock", (req, res) => {
    try {
      guard(req);
    } catch (e) {
      return res.status(429).json({ error: (e as Error).message });
    }
    if (!check(String(req.body?.password ?? ""))) {
      failed(req);
      return res.status(401).json({ error: "비밀번호가 맞지 않습니다." });
    }
    fails.delete(ipOf(req));
    setCookie(req, res);
    res.json({ ok: true });
  });
  app.post("/api/devgate/lock", (_req, res) => {
    res.setHeader("Set-Cookie", `${COOKIE}=; Path=/; HttpOnly; SameSite=Strict; Max-Age=0`);
    res.json({ ok: true });
  });
  app.post("/api/devgate/change", (req, res) => {
    try {
      guard(req);
    } catch (e) {
      return res.status(429).json({ error: (e as Error).message });
    }
    if (!check(String(req.body?.current ?? ""))) {
      failed(req);
      return res.status(401).json({ error: "현재 비밀번호가 맞지 않습니다." });
    }
    try {
      save(String(req.body?.next ?? ""));
    } catch (e) {
      return res.status(400).json({ error: (e as Error).message });
    }
    setCookie(req, res);
    res.json({ ok: true });
  });
}

/** 개발구성 API 보호: 잠금 해제 안 됐으면 423 */
export function requireDevgate(req: Request, res: Response, next: NextFunction): void {
  if (readGate() && unlocked(req)) return next();
  res.status(423).json({ error: "개발구성 화면이 잠겨 있습니다.", locked: true });
}
