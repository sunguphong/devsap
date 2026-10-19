import fs from "node:fs";
import path from "node:path";

// 개발표준 핸드북: standards/handbook.md 한 문서. 설계·개발·테스트 에이전트가 읽고, 보드에서 고친다.
// 고치기 전 버전은 standards/.history/에 보관한다.

const DIR = path.resolve("standards");
const FILE = path.join(DIR, "handbook.md");
const HISTORY_DIR = path.join(DIR, ".history");

export interface Handbook {
  markdown: string;
  updatedAt: string | null;
  versions: number;
}

export function getHandbook(): Handbook {
  const exists = fs.existsSync(FILE);
  return {
    markdown: exists ? fs.readFileSync(FILE, "utf8") : "",
    updatedAt: exists ? fs.statSync(FILE).mtime.toISOString() : null,
    versions: fs.existsSync(HISTORY_DIR) ? fs.readdirSync(HISTORY_DIR).filter((f) => f.endsWith(".md")).length : 0,
  };
}

export function saveHandbook(markdown: string): Handbook {
  const text = markdown.replace(/\r\n/g, "\n");
  if (!text.trim()) throw new Error("내용이 비어 있습니다.");
  fs.mkdirSync(HISTORY_DIR, { recursive: true });
  if (fs.existsSync(FILE)) {
    if (fs.readFileSync(FILE, "utf8") === text) return getHandbook();
    fs.copyFileSync(FILE, path.join(HISTORY_DIR, `${new Date().toISOString().replace(/[:.]/g, "-")}.md`));
  }
  fs.writeFileSync(FILE, text);
  return getHandbook();
}
