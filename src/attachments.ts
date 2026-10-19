import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";
import { WORK_DIR } from "./store.ts";

// 요청 첨부 자료: work/<요청ID>/attachments/, 요구사항 변경(CR) 첨부: work/<요청ID>/changes/<CR-xx>/. 이미지·PDF·텍스트는 Claude Code Read 도구가 바로 읽고,
// Office 문서(docx/xlsx/pptx)는 Read가 못 읽으므로 텍스트 추출본을 attachments/.text/<파일명>.txt 로 같이 둔다.

export const MAX_SIZE = 20 * 1024 * 1024;

const KINDS: Record<string, "image" | "pdf" | "office" | "text"> = {
  png: "image", jpg: "image", jpeg: "image", gif: "image", webp: "image",
  pdf: "pdf",
  docx: "office", xlsx: "office", pptx: "office",
  txt: "text", md: "text", csv: "text", json: "text", xml: "text", abap: "text", sql: "text",
};

export interface Attachment {
  name: string;
  size: number;
  kind: "image" | "pdf" | "office" | "text";
  at: string;
  extracted: boolean; // Office 문서 텍스트 추출본 유무
  source?: string; // 구글시트에서 가져온 사본이면 원본 링크
}

const CR_ID = /^CR-\d+$/;
// cr을 주면 그 요구사항 변경의 첨부 폴더
const dirOf = (id: string, cr?: string) => {
  if (cr !== undefined && !CR_ID.test(cr)) throw new Error("잘못된 변경 요청 번호입니다.");
  return cr ? path.join(WORK_DIR, id, "changes", cr) : path.join(WORK_DIR, id, "attachments");
};
const textOf = (id: string, name: string, cr?: string) => path.join(dirOf(id, cr), ".text", `${name}.txt`);
const sourceOf = (id: string, name: string, cr?: string) => path.join(dirOf(id, cr), ".source", `${name}.url`);
const relDir = (id: string, cr?: string) => (cr ? `work/${id}/changes/${cr}` : `work/${id}/attachments`);
const kindOf = (name: string) => KINDS[path.extname(name).slice(1).toLowerCase()];

export function attachmentPath(id: string, name: string, cr?: string): string | null {
  if (!/^[\w-]+$/.test(id) || name !== path.basename(name) || name.startsWith(".") || (cr !== undefined && !CR_ID.test(cr))) return null;
  const file = path.join(dirOf(id, cr), name);
  return fs.existsSync(file) ? file : null;
}

export function listAttachments(id: string, cr?: string): Attachment[] {
  const dir = dirOf(id, cr);
  if (!fs.existsSync(dir)) return [];
  return fs
    .readdirSync(dir)
    .filter((f) => !f.startsWith(".") && kindOf(f))
    .map((f) => {
      const st = fs.statSync(path.join(dir, f));
      const src = sourceOf(id, f, cr);
      const source = fs.existsSync(src) ? fs.readFileSync(src, "utf8").trim() : undefined;
      return { name: f, size: st.size, kind: kindOf(f), at: st.mtime.toISOString(), extracted: fs.existsSync(textOf(id, f, cr)), source };
    })
    .sort((a, b) => a.at.localeCompare(b.at));
}

export function saveAttachment(id: string, rawName: string, data: Buffer, cr?: string): Attachment {
  const ext = path.extname(rawName).slice(1).toLowerCase();
  if (!kindOf(rawName))
    throw new Error(`올릴 수 없는 파일 형식입니다 (.${ext}). 이미지(png·jpg·gif·webp), PDF, Word·Excel·PowerPoint(docx·xlsx·pptx), 텍스트 파일만 됩니다. hwp·doc·xls는 PDF로 저장해서 올려 주세요.`);
  if (!data.length) throw new Error("빈 파일입니다.");
  if (data.length > MAX_SIZE) throw new Error(`파일이 너무 큽니다 (최대 ${MAX_SIZE / 1024 / 1024}MB).`);
  // 사내 문서보안(DRM)이 걸린 파일은 암호화돼 있어 AI가 읽을 수 없다
  const head = data.subarray(0, 64).toString("latin1");
  if (/^<DOCUMENT SAFER|^<##SASF|DRMONE|^SCDSA/i.test(head) || (kindOf(rawName) === "office" && !head.startsWith("PK")))
    throw new Error(`'${rawName}'은(는) 문서보안(DRM)이 걸려 있거나 손상된 파일이라 AI가 읽을 수 없습니다. 보안 해제(반출 승인) 후 올리거나, 내용을 PDF·캡처 이미지로 올려 주세요.`);
  // 파일명에 경로·윈도우 금지 문자가 들어오지 않게 하고, 같은 이름이 있으면 번호를 붙인다
  const base = path.basename(rawName, path.extname(rawName)).replace(/[\\/:*?"<>|\x00-\x1f]/g, "_").replace(/^\.+/, "").trim().slice(0, 80) || "첨부";
  const dir = dirOf(id, cr);
  fs.mkdirSync(dir, { recursive: true });
  let name = `${base}.${ext}`;
  for (let n = 2; fs.existsSync(path.join(dir, name)); n++) name = `${base} (${n}).${ext}`;
  fs.writeFileSync(path.join(dir, name), data);
  if (kindOf(name) === "office") {
    let text = "";
    try {
      text = extractOffice(ext, data);
    } catch {
      // 추출 실패해도 원본은 남긴다 (화면에 '추출 실패'로 표시)
    }
    if (text.trim()) {
      fs.mkdirSync(path.dirname(textOf(id, name, cr)), { recursive: true });
      fs.writeFileSync(textOf(id, name, cr), text);
    }
  }
  return listAttachments(id, cr).find((a) => a.name === name)!;
}

export function deleteAttachment(id: string, name: string): void {
  const file = attachmentPath(id, name);
  if (!file) throw new Error("첨부 파일을 찾을 수 없습니다.");
  fs.rmSync(file);
  fs.rmSync(textOf(id, name), { force: true });
  fs.rmSync(sourceOf(id, name), { force: true });
}

// ---------- 구글시트 참조 ----------
// '링크가 있는 모든 사용자 - 뷰어'로 공유했거나 웹에 게시한 시트를 xlsx로 내려받아 첨부로 둔다.
// 이후는 Excel 첨부와 같다 (텍스트 추출본을 단계 프롬프트가 읽는다). 시트가 바뀌면 다시 가져와야 한다.

export async function importGoogleSheet(id: string, url: string, cr?: string): Promise<Attachment> {
  const { link, title, data } = await downloadGoogleSheet(url);
  const a = saveAttachment(id, `${title}.xlsx`, data, cr);
  fs.mkdirSync(path.dirname(sourceOf(id, a.name, cr)), { recursive: true });
  fs.writeFileSync(sourceOf(id, a.name, cr), link);
  return { ...a, source: link };
}

/** 링크 연결 확인: 내려받아 읽히는지만 보고 저장하지 않는다 */
export async function checkGoogleSheet(url: string): Promise<{ title: string; size: number; sheets: { name: string; rows: number }[]; preview: string }> {
  const { title, data } = await downloadGoogleSheet(url);
  let text = "";
  try {
    text = extractOffice("xlsx", data);
  } catch {
    // 아래에서 내용 없음으로 알린다
  }
  if (!text.trim()) throw new Error(`'${title}' 시트는 내려받았지만 내용을 읽지 못했습니다. 시트가 비어 있지 않은지 확인해 주세요.`);
  const sheets = text.split(/^## 시트: /m).filter(Boolean).map((s) => {
    const [name, ...rows] = s.trimEnd().split("\n");
    return { name, rows: rows.filter(Boolean).length };
  });
  return { title, size: data.length, sheets, preview: text.split("\n").slice(0, 8).join("\n").slice(0, 600) };
}

async function downloadGoogleSheet(url: string): Promise<{ link: string; title: string; data: Buffer }> {
  const link = url.trim();
  const pub = link.match(/^https:\/\/docs\.google\.com\/spreadsheets\/d\/e\/([\w-]+)/);
  const doc = link.match(/^https:\/\/docs\.google\.com\/spreadsheets\/d\/([\w-]+)/);
  if (!doc) throw new Error("구글시트 링크가 아닙니다. https://docs.google.com/spreadsheets/d/... 링크를 넣어 주세요.");
  const key = pub?.[1] ?? doc[1];
  const exportUrl = pub
    ? `https://docs.google.com/spreadsheets/d/e/${key}/pub?output=xlsx`
    : `https://docs.google.com/spreadsheets/d/${key}/export?format=xlsx`;
  let res: Awaited<ReturnType<typeof fetch>>;
  try {
    res = await fetch(exportUrl, { redirect: "follow", signal: AbortSignal.timeout(60_000) });
  } catch (e) {
    throw new Error(`구글시트를 가져오지 못했습니다 (${(e as Error).message}). 이 PC에서 docs.google.com 접속이 되는지 확인해 주세요.`);
  }
  const data = Buffer.from(await res.arrayBuffer());
  // 비공개 시트는 구글 로그인 화면(HTML)이 돌아온다
  if (!res.ok || data.subarray(0, 2).toString("latin1") !== "PK")
    throw new Error("구글시트를 내려받을 수 없습니다. 공유를 '링크가 있는 모든 사용자 - 뷰어'로 바꾸거나, 파일 > 다운로드 > Microsoft Excel(.xlsx)로 받아 첨부해 주세요.");
  // 시트 제목은 다운로드 파일명(Content-Disposition)에 들어 있다
  const cd = res.headers.get("content-disposition") ?? "";
  const star = cd.match(/filename\*=UTF-8''([^;]+)/i)?.[1];
  const title = (star ? decodeURIComponent(star) : cd.match(/filename="([^"]+)"/i)?.[1] ?? "").replace(/\.xlsx$/i, "").trim() || `구글시트 ${key.slice(0, 8)}`;
  if (data.length > MAX_SIZE) throw new Error(`구글시트가 너무 큽니다 (xlsx ${Math.round(data.length / 1048576)}MB, 최대 ${MAX_SIZE / 1024 / 1024}MB).`);
  return { link, title, data };
}

/** 첨부 파일별 읽는 방법 안내 줄 */
function attachmentLines(id: string, cr?: string): string[] {
  const dir = relDir(id, cr);
  return listAttachments(id, cr).map((a) => {
    const p = `${dir}/${a.name}`;
    const from = a.source ? ` [구글시트 ${a.source} 에서 가져온 사본]` : "";
    if (a.kind === "office") return a.extracted ? `- ${p}${from} → 텍스트 추출본 ${dir}/.text/${a.name}.txt 를 읽으세요` : `- ${p}${from} (텍스트 추출 실패, 내용 확인 불가)`;
    return `- ${p} (${{ image: "이미지 — Read로 직접 보세요", pdf: "PDF — Read로 읽으세요, 10쪽 넘으면 pages 지정", text: "텍스트" }[a.kind]})`;
  });
}

/** 헤드리스 세션 프롬프트에 넣을 첨부 안내. 없으면 빈 문자열 */
export function attachmentsPrompt(id: string): string {
  const lines = attachmentLines(id);
  if (!lines.length) return "";
  return `현업 요청 첨부 자료 (request.md와 함께 요구사항 원문입니다. 화면 예시·양식·샘플 데이터 등이 들어 있으니 반드시 확인하세요):\n${lines.join("\n")}`;
}

/** 요구사항 변경(CR) 첨부 안내. CR 문구 뒤에 붙인다. 없으면 빈 문자열 */
export function changeAttachmentsNote(id: string, cr: string): string {
  const lines = attachmentLines(id, cr);
  return lines.length ? `\n  ${cr} 첨부 자료 (변경 내용의 일부이니 반드시 확인):\n  ${lines.join("\n  ")}` : "";
}

// ---------- Office 문서 텍스트 추출 (zip + XML, 외부 라이브러리 없이) ----------

function unzip(buf: Buffer): Map<string, () => Buffer> {
  let eocd = -1;
  for (let i = buf.length - 22; i >= Math.max(0, buf.length - 65_557); i--)
    if (buf.readUInt32LE(i) === 0x06054b50) {
      eocd = i;
      break;
    }
  if (eocd < 0) throw new Error("zip 형식이 아닙니다.");
  const count = buf.readUInt16LE(eocd + 10);
  let p = buf.readUInt32LE(eocd + 16);
  const out = new Map<string, () => Buffer>();
  for (let i = 0; i < count && buf.readUInt32LE(p) === 0x02014b50; i++) {
    const method = buf.readUInt16LE(p + 10);
    const size = buf.readUInt32LE(p + 20);
    const nameLen = buf.readUInt16LE(p + 28);
    const local = buf.readUInt32LE(p + 42);
    const name = buf.toString("utf8", p + 46, p + 46 + nameLen).replaceAll("\\", "/");
    p += 46 + nameLen + buf.readUInt16LE(p + 30) + buf.readUInt16LE(p + 32);
    out.set(name, () => {
      const start = local + 30 + buf.readUInt16LE(local + 26) + buf.readUInt16LE(local + 28);
      const data = buf.subarray(start, start + size);
      return method === 8 ? zlib.inflateRawSync(data) : data;
    });
  }
  return out;
}

const decode = (s: string) =>
  s.replace(/&(lt|gt|amp|quot|apos|#\d+|#x[\da-f]+);/gi, (_, e: string) =>
    ({ lt: "<", gt: ">", amp: "&", quot: '"', apos: "'" })[e.toLowerCase() as "lt"] ??
    String.fromCodePoint(e[1] === "x" || e[1] === "X" ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10)));
const strip = (xml: string) => decode(xml.replace(/<[^>]+>/g, ""));

function paragraphs(xml: string, para: string, tab: string): string {
  return strip(xml.replace(new RegExp(`<${tab}\\s*/>`, "g"), "\t").replace(new RegExp(`</${para}>`, "g"), "\n"))
    .split("\n").map((l) => l.trimEnd()).filter((l, i, a) => l || a[i - 1]).join("\n").trim();
}

function extractOffice(ext: string, data: Buffer): string {
  const zip = unzip(data);
  const read = (n: string) => zip.get(n)?.().toString("utf8") ?? "";
  if (ext === "docx") return paragraphs(read("word/document.xml"), "w:p", "w:tab");
  if (ext === "pptx") {
    const slides = [...zip.keys()].filter((n) => /^ppt\/slides\/slide\d+\.xml$/.test(n)).sort((a, b) => Number(a.match(/\d+/)![0]) - Number(b.match(/\d+/)![0]));
    return slides.map((n, i) => `## 슬라이드 ${i + 1}\n${paragraphs(read(n), "a:p", "a:tab")}`).join("\n\n");
  }
  // xlsx: 시트별로 셀 주소와 값을 행 단위로 적는다
  const shared = [...read("xl/sharedStrings.xml").matchAll(/<si>([\s\S]*?)<\/si>/g)].map((m) => strip(m[1]));
  const rels = new Map([...read("xl/_rels/workbook.xml.rels").matchAll(/<Relationship\b[^>]*>/g)].map((m) => [
    m[0].match(/Id="([^"]+)"/)?.[1], m[0].match(/Target="([^"]+)"/)?.[1]?.replace(/^\/?(xl\/)?/, "xl/"),
  ]));
  const sheets = [...read("xl/workbook.xml").matchAll(/<sheet\b[^>]*>/g)].map((m) => ({
    name: decode(m[0].match(/name="([^"]*)"/)?.[1] ?? ""),
    file: rels.get(m[0].match(/r:id="([^"]+)"/)?.[1]) ?? "",
  }));
  const out: string[] = [];
  for (const s of sheets) {
    const rows = [...read(s.file).matchAll(/<row\b[^>]*>([\s\S]*?)<\/row>/g)].map((r) =>
      [...r[1].matchAll(/<c\b([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/g)].map((c) => {
        const ref = c[1].match(/r="([A-Z]+\d+)"/)?.[1] ?? "";
        const type = c[1].match(/t="(\w+)"/)?.[1];
        const v = c[2]?.match(/<v>([\s\S]*?)<\/v>/)?.[1];
        const val = type === "s" ? shared[Number(v)] ?? "" : type === "inlineStr" ? strip(c[2] ?? "") : decode(v ?? "");
        return val.trim() ? `${ref}=${val.replace(/\s*\n\s*/g, " ")}` : "";
      }).filter(Boolean).join(" | "),
    ).filter(Boolean);
    out.push(`## 시트: ${s.name}\n${rows.join("\n")}`);
    if (out.join("\n").length > 300_000) break;
  }
  return out.join("\n\n").slice(0, 300_000);
}
