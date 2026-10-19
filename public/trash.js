// 휴지통: 삭제한 개발 요청 (work/.trash/). 복원하면 개발 요청 목록으로 돌아간다

async function trashView() {
  const body = $("#trashBody");
  let list;
  try { list = await api("/api/trash"); } catch (e) { body.innerHTML = `<div class="card err">${esc(e.message)}</div>`; return; }
  body.innerHTML = `<div class="card"><h3>🗑 휴지통 (${list.length})</h3>
    <p class="sub" style="margin:0 0 10px">삭제한 개발 요청입니다. 복원하면 산출물·첨부 자료·진행 기록이 그대로 돌아옵니다. 영구 삭제는 되돌릴 수 없습니다.</p>
    ${list.length ? `<div class="hb-table"><table><thead><tr><th>요청</th><th>상태</th><th>등록</th><th>삭제</th><th></th></tr></thead><tbody>
      ${list.map((t) => `<tr>
        <td><b>${esc(t.title)}</b><div class="sub" style="margin:0">${esc(t.id)}</div></td>
        <td><span class="badge ${esc(t.status)}">${esc(STATUS[t.status] ?? t.status)}</span></td>
        <td>${new Date(t.createdAt).toLocaleDateString()}</td>
        <td>${new Date(t.deletedAt).toLocaleString()}</td>
        <td style="white-space:nowrap"><button class="small primary" data-restore="${esc(t.entry)}">♻️ 복원</button>
          <button class="small" data-purge="${esc(t.entry)}" data-title="${esc(t.title)}">영구 삭제</button></td></tr>`).join("")}
      </tbody></table></div>` : `<div class="empty" style="margin:20px 0">휴지통이 비어 있습니다</div>`}</div>`;
  body.querySelectorAll("[data-restore]").forEach((b) => b.addEventListener("click", async () => {
    b.disabled = true;
    try {
      const { id } = await api(`/api/trash/${encodeURIComponent(b.dataset.restore)}/restore`, { method: "POST" });
      await loadList();
      location.hash = "#/";
      await select(id);
    } catch (e) { alert(e.message); b.disabled = false; }
  }));
  body.querySelectorAll("[data-purge]").forEach((b) => b.addEventListener("click", async () => {
    if (!confirm(`'${b.dataset.title}' 요청을 영구 삭제할까요?\n되돌릴 수 없습니다.`)) return;
    b.disabled = true;
    try { await api(`/api/trash/${encodeURIComponent(b.dataset.purge)}`, { method: "DELETE" }); await trashView(); }
    catch (e) { alert(e.message); b.disabled = false; }
  }));
}
