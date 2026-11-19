// SAP ADT(ABAP Development Tools) REST API 클라이언트 - 개발계 반영 전용
export type ObjectType = "PROG" | "INCL" | "CLAS";
export type SourcePart = "main" | "testclasses";

export interface SapConfig {
  url: string;
  client: string;
  user: string;
  password: string;
  language: string;
}

export function sapConfigFromEnv(): SapConfig | null {
  const { SAP_URL, SAP_CLIENT, SAP_USER, SAP_PASSWORD } = process.env;
  if (!SAP_URL || !SAP_USER || !SAP_PASSWORD) return null;
  return { url: SAP_URL, client: SAP_CLIENT || "100", user: SAP_USER, password: SAP_PASSWORD, language: process.env.SAP_LANGUAGE || "KO" };
}

const xmlEscape = (s: string) =>
  s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

/** encoding="ASCII" 로 선언한 본문에 한글 등을 넣을 때: ASCII 밖 문자는 &#코드; 문자 참조로 바꾼다
 *  (그대로 넣으면 SAP가 "Error during deserialization" 으로 거부한다) */
const asciiXml = (s: string) => xmlEscape(s).replace(/[^\x00-\x7f]/gu, (c) => `&#${c.codePointAt(0)};`);

const decodeXml = (s: string) =>
  s.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&amp;/g, "&");

export function objectUri(type: ObjectType, name: string): string {
  const n = encodeURIComponent(name.toLowerCase());
  return type === "PROG" ? `/sap/bc/adt/programs/programs/${n}` : type === "INCL" ? `/sap/bc/adt/programs/includes/${n}` : `/sap/bc/adt/oo/classes/${n}`;
}

export const fugrUri = (group: string) => `/sap/bc/adt/functions/groups/${encodeURIComponent(group.toLowerCase())}`;
export const fmUri = (group: string, name: string) => `${fugrUri(group)}/fmodules/${encodeURIComponent(name.toLowerCase())}`;
export const msagUri = (name: string) => `/sap/bc/adt/messageclass/${encodeURIComponent(name.toLowerCase())}`;

/** include는 메인 프로그램 문맥에서 활성화해야 하므로 ?context= 를 붙인다 */
function activationUri(o: { type: ObjectType; name: string; mainProgram?: string }): string {
  const uri = objectUri(o.type, o.name);
  return o.type === "INCL" && o.mainProgram ? `${uri}?context=${encodeURIComponent(objectUri("PROG", o.mainProgram))}` : uri;
}

interface Res {
  status: number;
  text: string;
  headers: Headers;
}

export class AdtClient {
  private cfg: SapConfig;
  private cookies = new Map<string, string>();
  private csrf = "";

  constructor(cfg: SapConfig) {
    this.cfg = cfg;
  }

  private async raw(method: string, path: string, opts: { body?: string; contentType?: string; accept?: string; query?: Record<string, string>; stateful?: boolean; fetchCsrf?: boolean } = {}): Promise<Res> {
    const url = new URL(path, this.cfg.url);
    url.searchParams.set("sap-client", this.cfg.client);
    url.searchParams.set("sap-language", this.cfg.language);
    for (const [k, v] of Object.entries(opts.query ?? {})) url.searchParams.set(k, v);

    const headers: Record<string, string> = {
      Authorization: "Basic " + Buffer.from(`${this.cfg.user}:${this.cfg.password}`).toString("base64"),
      Accept: opts.accept ?? "*/*",
      "x-csrf-token": opts.fetchCsrf ? "fetch" : this.csrf,
    };
    if (this.cookies.size) headers.Cookie = [...this.cookies].map(([k, v]) => `${k}=${v}`).join("; ");
    if (opts.contentType) headers["Content-Type"] = opts.contentType;
    if (opts.stateful) headers["X-sap-adt-sessiontype"] = "stateful";

    const res = await fetch(url, { method, headers, body: opts.body });
    for (const c of res.headers.getSetCookie()) {
      const [pair] = c.split(";");
      const i = pair.indexOf("=");
      this.cookies.set(pair.slice(0, i).trim(), pair.slice(i + 1).trim());
    }
    const token = res.headers.get("x-csrf-token");
    if (token && token !== "Required") this.csrf = token;
    return { status: res.status, text: await res.text(), headers: res.headers };
  }

  private async req(method: string, path: string, opts: Parameters<AdtClient["raw"]>[2] = {}): Promise<Res> {
    if (method !== "GET" && !this.csrf) await this.raw("GET", "/sap/bc/adt/discovery", { fetchCsrf: true });
    let res = await this.raw(method, path, opts);
    if (res.status === 403 && res.headers.get("x-csrf-token") === "Required") {
      await this.raw("GET", "/sap/bc/adt/discovery", { fetchCsrf: true });
      res = await this.raw(method, path, opts);
    }
    return res;
  }

  private static fail(what: string, res: Res): never {
    // ADT 오류는 <message>, 로그온 오류는 HTML 페이지로 온다 → 태그·스타일을 걷어내고 본문만 보여준다
    const msg =
      res.text.match(/<message[^>]*>([\s\S]*?)<\/message>/)?.[1] ??
      res.text.replace(/<(style|script|head)[\s\S]*?<\/\1>/gi, " ").replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").slice(0, 500);
    throw new Error(`${what} 실패 (HTTP ${res.status}): ${decodeXml(msg).trim()}`);
  }

  async ping(): Promise<string> {
    const res = await this.raw("GET", "/sap/bc/adt/discovery", { fetchCsrf: true });
    if (res.status !== 200) AdtClient.fail("SAP 접속", res);
    return `SAP 접속 성공 (${this.cfg.url}, 클라이언트 ${this.cfg.client})`;
  }

  /** 설치 컴포넌트 버전(CVERS)에서 SAP_BASIS 릴리스·SP를 읽는다 (데이터 미리보기, 읽기 전용). 예: { release: "7.40", sp: 30 } */
  async basisRelease(): Promise<{ release: string; sp: number } | null> {
    const res = await this.req("POST", "/sap/bc/adt/datapreview/ddic", {
      body: "SELECT * FROM CVERS",
      contentType: "text/plain",
      accept: "application/xml, application/vnd.sap.adt.datapreview.table.v1+xml",
      query: { rowNumber: "500", ddicEntityName: "CVERS" },
    });
    if (res.status !== 200) AdtClient.fail("SAP_BASIS 버전 조회", res);
    const col = (name: string) =>
      [...(res.text.match(new RegExp(`dataPreview:name="${name}"[\\s\\S]*?<dataPreview:dataSet>([\\s\\S]*?)</dataPreview:dataSet>`))?.[1] ?? "").matchAll(/<dataPreview:data>([^<]*)<\/dataPreview:data>/g)].map((m) => m[1].trim());
    const comps = col("COMPONENT");
    const i = comps.indexOf("SAP_BASIS");
    if (i < 0) return null;
    const rel = col("RELEASE")[i] ?? "";
    return { release: /^\d{3}$/.test(rel) ? `${rel[0]}.${rel.slice(1)}` : rel, sp: Number(col("EXTRELEASE")[i] ?? 0) };
  }

  async exists(type: ObjectType, name: string): Promise<boolean> {
    const res = await this.req("GET", objectUri(type, name));
    if (res.status === 200) return true;
    if (res.status === 404) return false;
    AdtClient.fail(`${name} 존재 확인`, res);
  }

  /** 이미 있는 include가 SAP에 연결된 메인 프로그램 이름 (없으면 null) */
  async includeMainProgram(name: string): Promise<string | null> {
    const res = await this.req("GET", objectUri("INCL", name));
    if (res.status !== 200) return null;
    return res.text.match(/<include:contextRef\b[^>]*adtcore:name="([^"]+)"/)?.[1] ?? null;
  }

  async create(type: ObjectType, name: string, description: string, pkg: string, transport: string, mainProgram?: string): Promise<void> {
    const N = xmlEscape(name.toUpperCase());
    const D = xmlEscape(description.slice(0, 60));
    const common = `xmlns:adtcore="http://www.sap.com/adt/core" adtcore:description="${D}" adtcore:name="${N}" adtcore:masterLanguage="${this.cfg.language}" adtcore:responsible="${xmlEscape(this.cfg.user.toUpperCase())}"`;
    const pkgRef = `<adtcore:packageRef adtcore:name="${xmlEscape(pkg.toUpperCase())}"/>`;
    const main = xmlEscape((mainProgram ?? "").toUpperCase());
    const body =
      type === "PROG"
        ? `<?xml version="1.0" encoding="UTF-8"?><program:abapProgram xmlns:program="http://www.sap.com/adt/programs/programs" ${common} adtcore:type="PROG/P">${pkgRef}</program:abapProgram>`
        : type === "INCL"
        ? `<?xml version="1.0" encoding="UTF-8"?><include:abapInclude xmlns:include="http://www.sap.com/adt/programs/includes" ${common} adtcore:type="PROG/I">${pkgRef}${main ? `<include:containerRef adtcore:name="${main}" adtcore:type="PROG/P" adtcore:uri="${objectUri("PROG", main)}"/>` : ""}</include:abapInclude>`
        : `<?xml version="1.0" encoding="UTF-8"?><class:abapClass xmlns:class="http://www.sap.com/adt/oo/classes" ${common} adtcore:type="CLAS/OC" class:final="true" class:visibility="public">${pkgRef}<class:include adtcore:name="CLAS/OC" adtcore:type="CLAS/OC" class:includeType="testclasses"/><class:superClassRef/></class:abapClass>`;
    const collection = type === "PROG" ? "/sap/bc/adt/programs/programs" : type === "INCL" ? "/sap/bc/adt/programs/includes" : "/sap/bc/adt/oo/classes";
    const res = await this.req("POST", collection, { body, contentType: "application/*", query: transport ? { corrNr: transport } : {} });
    if (res.status >= 300) AdtClient.fail(`${name} 생성`, res);
  }

  /** 패키지에 맞는 워크벤치 이송요청을 새로 만들고 번호를 돌려준다 (ADT "New Transport Request"와 같은 호출) */
  async createTransport(pkg: string, text: string, refUri: string): Promise<string> {
    const body = `<?xml version="1.0" encoding="ASCII"?><asx:abap xmlns:asx="http://www.sap.com/abapxml" version="1.0"><asx:values><DATA>
<OPERATION>I</OPERATION><DEVCLASS>${xmlEscape(pkg.toUpperCase())}</DEVCLASS><REQUEST_TEXT>${asciiXml(text.slice(0, 60))}</REQUEST_TEXT><REF>${asciiXml(refUri)}</REF>
</DATA></asx:values></asx:abap>`;
    const res = await this.req("POST", "/sap/bc/adt/cts/transports", {
      body,
      accept: "text/plain",
      contentType: "application/vnd.sap.as+xml; charset=UTF-8; dataname=com.sap.adt.CreateCorrectionRequest",
    });
    if (res.status >= 300) AdtClient.fail("이송요청 생성", res);
    const trkorr = res.text.trim().split("/").pop()?.match(/^[A-Z0-9]{3}K\d{6}$/)?.[0];
    if (!trkorr) throw new Error(`이송요청 생성 응답에서 번호를 찾지 못했습니다: ${res.text.slice(0, 200)}`);
    return trkorr;
  }

  private async lock(uri: string): Promise<string> {
    const res = await this.req("POST", uri, {
      query: { _action: "LOCK", accessMode: "MODIFY" },
      accept: "application/*,application/vnd.sap.as+xml;charset=UTF-8;dataname=com.sap.adt.lock.result;q=0.8, application/vnd.sap.as+xml;charset=UTF-8;dataname=com.sap.adt.lock.result2;q=0.9",
      stateful: true,
    });
    const handle = res.text.match(/<LOCK_HANDLE>(.*?)<\/LOCK_HANDLE>/)?.[1];
    if (res.status >= 300 || !handle) AdtClient.fail("잠금", res);
    return decodeXml(handle);
  }

  private async unlock(uri: string, handle: string): Promise<void> {
    await this.req("POST", uri, { query: { _action: "UNLOCK", lockHandle: handle }, stateful: true });
  }

  async writeSource(type: ObjectType, name: string, part: SourcePart, source: string, transport: string): Promise<void> {
    return this.writeSourceAt(objectUri(type, name), name, part, source, transport);
  }

  /** 오브젝트 URI 기준 소스 저장 (함수 모듈처럼 objectUri로 표현되지 않는 오브젝트도 쓴다) */
  async writeSourceAt(uri: string, name: string, part: SourcePart, source: string, transport: string): Promise<void> {
    const handle = await this.lock(uri);
    try {
      const target = part === "main" ? `${uri}/source/main` : `${uri}/includes/testclasses`;
      const query: Record<string, string> = { lockHandle: handle };
      if (transport) query.corrNr = transport;
      let res = await this.req("PUT", target, { body: source, contentType: "text/plain; charset=utf-8", query, stateful: true });
      if (res.status === 404 && part === "testclasses") {
        // 테스트 클래스 include가 아직 없으면 만든 뒤 다시 쓴다
        const inc = `<?xml version="1.0" encoding="UTF-8"?><class:abapClassInclude xmlns:class="http://www.sap.com/adt/oo/classes" xmlns:adtcore="http://www.sap.com/adt/core" adtcore:name="dummy" class:includeType="testclasses"/>`;
        const created = await this.req("POST", `${uri}/includes`, { body: inc, contentType: "application/*", query, stateful: true });
        if (created.status >= 300) AdtClient.fail(`${name} 테스트 include 생성`, created);
        res = await this.req("PUT", target, { body: source, contentType: "text/plain; charset=utf-8", query, stateful: true });
      }
      if (res.status >= 300) AdtClient.fail(`${name} 소스 저장`, res);
    } finally {
      await this.unlock(uri, handle);
    }
  }

  async readSource(type: ObjectType, name: string, part: SourcePart): Promise<string> {
    const uri = objectUri(type, name);
    const res = await this.req("GET", part === "main" ? `${uri}/source/main` : `${uri}/includes/testclasses`, { accept: "text/plain" });
    if (res.status !== 200) AdtClient.fail(`${name} 소스 조회`, res);
    return res.text;
  }

  /** 활성화 후 오류/경고 메시지를 사람이 읽을 수 있는 형태로 돌려준다 */
  async activate(
    objects: { type: ObjectType; name: string; mainProgram?: string }[],
    extra: { uri: string; name: string }[] = [],
  ): Promise<{ ok: boolean; messages: string[] }> {
    const refs = [...objects.map((o) => ({ uri: activationUri(o), name: o.name })), ...extra]
      .map((o) => `<adtcore:objectReference adtcore:uri="${xmlEscape(o.uri)}" adtcore:name="${xmlEscape(o.name.toUpperCase())}"/>`)
      .join("");
    const body = `<?xml version="1.0" encoding="UTF-8"?><adtcore:objectReferences xmlns:adtcore="http://www.sap.com/adt/core">${refs}</adtcore:objectReferences>`;
    const res = await this.req("POST", "/sap/bc/adt/activation", { body, contentType: "application/xml", query: { method: "activate", preauditRequested: "true" } });
    if (res.status >= 300) AdtClient.fail("활성화", res);
    const messages: string[] = [];
    for (const m of res.text.matchAll(/<msg\b([^>]*)>([\s\S]*?)<\/msg>/g)) {
      const attrs = m[1];
      const type = attrs.match(/type="(\w)"/)?.[1] ?? "?";
      const href = attrs.match(/href="([^"]*)"/)?.[1] ?? "";
      const line = href.match(/start=(\d+)/)?.[1];
      const txt = [...m[2].matchAll(/<txt>([\s\S]*?)<\/txt>/g)].map((x) => decodeXml(x[1])).join(" ");
      messages.push(`[${type}] ${decodeXml(href.split("#")[0].split("/").slice(-3).join("/"))}${line ? ` (line ${line})` : ""}: ${txt}`);
    }
    const failed = /activationExecuted="false"/.test(res.text) || messages.some((m) => m.startsWith("[E]"));
    return { ok: !failed, messages };
  }

  // ---------- 함수 그룹 · 함수 모듈 ----------

  async existsAt(uri: string, what: string): Promise<boolean> {
    const res = await this.req("GET", uri);
    if (res.status === 200) return true;
    if (res.status === 404) return false;
    AdtClient.fail(`${what} 존재 확인`, res);
  }

  private common(name: string, description: string): string {
    return `xmlns:adtcore="http://www.sap.com/adt/core" adtcore:description="${xmlEscape(description.slice(0, 60))}" adtcore:name="${xmlEscape(name.toUpperCase())}" adtcore:masterLanguage="${this.cfg.language}" adtcore:responsible="${xmlEscape(this.cfg.user.toUpperCase())}"`;
  }

  async createFunctionGroup(name: string, description: string, pkg: string, transport: string): Promise<void> {
    const body = `<?xml version="1.0" encoding="UTF-8"?><group:abapFunctionGroup xmlns:group="http://www.sap.com/adt/functions/groups" ${this.common(name, description)} adtcore:type="FUGR/F"><adtcore:packageRef adtcore:name="${xmlEscape(pkg.toUpperCase())}"/></group:abapFunctionGroup>`;
    const res = await this.req("POST", "/sap/bc/adt/functions/groups", { body, contentType: "application/*", query: transport ? { corrNr: transport } : {} });
    if (res.status >= 300) AdtClient.fail(`함수 그룹 ${name} 생성`, res);
  }

  /** processingType: normal | rfc (Remote-Enabled) */
  async createFunctionModule(group: string, name: string, description: string, transport: string, processingType: string): Promise<void> {
    const body = `<?xml version="1.0" encoding="UTF-8"?><fmodule:abapFunctionModule xmlns:fmodule="http://www.sap.com/adt/functions/fmodules" ${this.common(name, description)} adtcore:type="FUGR/FF" fmodule:processingType="${xmlEscape(processingType)}"><adtcore:containerRef adtcore:name="${xmlEscape(group.toUpperCase())}" adtcore:type="FUGR/F" adtcore:uri="${fugrUri(group)}"/></fmodule:abapFunctionModule>`;
    const res = await this.req("POST", `${fugrUri(group)}/fmodules`, { body, contentType: "application/*", query: transport ? { corrNr: transport } : {} });
    if (res.status >= 300) AdtClient.fail(`함수 모듈 ${name} 생성`, res);
  }

  /** SAP에 저장된 함수 모듈 처리 유형 (normal / rfc / update ...). 알 수 없으면 null */
  async functionModuleProcessingType(group: string, name: string): Promise<string | null> {
    const res = await this.req("GET", fmUri(group, name));
    if (res.status !== 200) return null;
    return res.text.match(/fmodule:processingType="([^"]*)"/)?.[1] ?? null;
  }

  // ---------- 메시지 클래스 ----------

  async readMessageClass(name: string): Promise<{ xml: string; numbers: Map<string, string> } | null> {
    const res = await this.req("GET", msagUri(name), { accept: "application/*" });
    if (res.status === 404) return null;
    if (res.status !== 200) AdtClient.fail(`메시지 클래스 ${name} 조회`, res);
    const numbers = new Map<string, string>();
    for (const m of res.text.matchAll(/<mc:messages\b([^>]*?)\/?>/g)) {
      const no = m[1].match(/mc:msgno="(\d+)"/)?.[1];
      if (no) numbers.set(no.padStart(3, "0"), decodeXml(m[1].match(/mc:msgtext="([^"]*)"/)?.[1] ?? ""));
    }
    return { xml: res.text, numbers };
  }

  private static msgXml(m: { no: string; text: string; selfExplanatory?: boolean }): string {
    return `<mc:messages mc:msgno="${xmlEscape(m.no.padStart(3, "0"))}" mc:msgtext="${xmlEscape(m.text.slice(0, 73))}" mc:selfexplainatory="${m.selfExplanatory === false ? "false" : "true"}" mc:documented="false"/>`;
  }

  async createMessageClass(name: string, description: string, pkg: string, transport: string, messages: { no: string; text: string; selfExplanatory?: boolean }[]): Promise<void> {
    const body = `<?xml version="1.0" encoding="UTF-8"?><mc:messageClass xmlns:mc="http://www.sap.com/adt/MessageClass" ${this.common(name, description)} adtcore:type="MSAG/N"><adtcore:packageRef adtcore:name="${xmlEscape(pkg.toUpperCase())}"/>${messages.map(AdtClient.msgXml).join("")}</mc:messageClass>`;
    const res = await this.req("POST", "/sap/bc/adt/messageclass", { body, contentType: "application/*", query: transport ? { corrNr: transport } : {} });
    if (res.status >= 300) AdtClient.fail(`메시지 클래스 ${name} 생성`, res);
  }

  /** 없는 번호만 덧붙인다. 이미 있는 번호의 텍스트는 바꾸지 않는다 (다른 프로그램이 쓰고 있을 수 있음) */
  async addMessages(name: string, xml: string, messages: { no: string; text: string; selfExplanatory?: boolean }[], transport: string): Promise<void> {
    const uri = msagUri(name);
    const handle = await this.lock(uri);
    try {
      const body = xml.replace(/<\/mc:messageClass>\s*$/,`${messages.map(AdtClient.msgXml).join("")}</mc:messageClass>`);
      const query: Record<string, string> = { lockHandle: handle };
      if (transport) query.corrNr = transport;
      const res = await this.req("PUT", uri, { body, contentType: "application/*", query, stateful: true });
      if (res.status >= 300) AdtClient.fail(`메시지 클래스 ${name} 저장`, res);
    } finally {
      await this.unlock(uri, handle);
    }
  }

  async runUnitTests(type: ObjectType, name: string): Promise<string> {
    const body = `<?xml version="1.0" encoding="UTF-8"?>
<aunit:runConfiguration xmlns:aunit="http://www.sap.com/adt/aunit">
  <external><coverage active="false"/></external>
  <options>
    <uriType value="semantic"/>
    <testDeterminationStrategy sameProgram="true" assignedTests="false"/>
    <testRiskLevels harmless="true" dangerous="true" critical="true"/>
    <testDurations short="true" medium="true" long="true"/>
    <withNavigationUri enabled="false"/>
  </options>
  <adtcore:objectSets xmlns:adtcore="http://www.sap.com/adt/core">
    <objectSet kind="inclusive"><adtcore:objectReferences><adtcore:objectReference adtcore:uri="${objectUri(type, name)}"/></adtcore:objectReferences></objectSet>
  </adtcore:objectSets>
</aunit:runConfiguration>`;
    const res = await this.req("POST", "/sap/bc/adt/abapunit/testruns", { body, contentType: "application/vnd.sap.adt.abapunit.testruns.config.v4+xml" });
    if (res.status >= 300) AdtClient.fail(`${name} ABAP Unit 실행`, res);
    const methods = [...res.text.matchAll(/<testMethod\b[^>]*adtcore:name="([^"]*)"/g)].map((m) => m[1]);
    const alerts = [...res.text.matchAll(/<alert\b[^>]*kind="([^"]*)"[^>]*severity="([^"]*)"[^>]*>[\s\S]*?<title>([\s\S]*?)<\/title>([\s\S]*?)<\/alert>/g)].map((m) => {
      const details = [...m[4].matchAll(/<detail\b[^>]*text="([^"]*)"/g)].map((d) => decodeXml(d[1])).join(" / ");
      return `- [${m[1]}/${m[2]}] ${decodeXml(m[3])}${details ? `: ${details}` : ""}`;
    });
    if (!methods.length && !alerts.length) return "실행된 테스트 메서드가 없습니다 (테스트 클래스 없음 또는 인식 실패).";
    return `테스트 메서드 ${methods.length}개 실행 (${methods.join(", ")})\n` + (alerts.length ? `실패/경고 ${alerts.length}건:\n${alerts.join("\n")}` : "모든 테스트 통과");
  }
}
