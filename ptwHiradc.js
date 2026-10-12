// =====================================================================================
// HSSE-Fusion4 -- tombol "Ambil dari HIRADC" di JSA ptw-report.html.
// Nampilin baris HIRADC yang sudah Disetujui buat project yang dipilih (RPC
// get_hiradc_items_for_project, SQL 067), yang dicentang ditambahkan jadi baris JSA
// lengkap dengan skor L x S awal & sisa. Pakai variabel/fungsi milik ptw-report.html:
// supabaseClient, selectProject, jsaRows, addJsaRow, escapeHtml.
// =====================================================================================
(function (global) {
  let items = [];

  const css = `
    .hiradc-modal { position: fixed; inset: 0; background: rgba(15,23,42,.55); z-index: 1000; display: none; align-items: flex-start; justify-content: center; padding: 24px 12px; overflow-y: auto; }
    .hiradc-modal.open { display: flex; }
    .hiradc-box { background: #fff; border-radius: 14px; width: 100%; max-width: 760px; padding: 16px; }
    .hiradc-box h3 { margin: 0 0 4px; font-size: 16px; color: var(--navy-dark); }
    .hiradc-doc { font-size: 11px; font-weight: 800; color: var(--navy); text-transform: uppercase; margin: 14px 0 6px; }
    .hiradc-pick { display: flex; gap: 10px; align-items: flex-start; border: 1.5px solid var(--border); border-radius: 10px; padding: 9px 10px; margin-bottom: 6px; cursor: pointer; font-size: 12.5px; }
    .hiradc-pick input { width: auto; margin-top: 3px; }
    .hiradc-pick .sub { color: var(--muted); font-size: 11.5px; }
    .hiradc-actions { display: flex; gap: 8px; justify-content: flex-end; margin-top: 12px; position: sticky; bottom: 0; background: #fff; padding-top: 8px; }
    .hiradc-actions button { border: 0; border-radius: 9px; padding: 9px 14px; font-weight: 800; cursor: pointer; }`;

  function ensureModal() {
    if (document.getElementById('hiradcModal')) return;
    const style = document.createElement('style');
    style.textContent = css;
    document.head.appendChild(style);
    const m = document.createElement('div');
    m.id = 'hiradcModal';
    m.className = 'hiradc-modal';
    m.innerHTML = `
      <div class="hiradc-box">
        <h3>Ambil dari HIRADC</h3>
        <div style="font-size:12px;color:var(--muted);">Baris HIRADC yang sudah Disetujui untuk project ini. HIRADC = penilaian khusus project/area; contoh generik = template umum per Jenis Pekerjaan. Centang yang relevan, nanti jadi baris JSA (tetap bisa diedit).</div>
        <label style="display:flex;gap:6px;align-items:center;font-size:12px;margin-top:8px;"><input type="checkbox" id="hiradcAll" style="width:auto;"> Pilih semua</label>
        <label style="display:flex;gap:6px;align-items:center;font-size:12px;margin-top:4px;"><input type="checkbox" id="hiradcGanti" style="width:auto;" checked> Ganti baris contoh generik (Jenis Pekerjaan) yang belum diedit</label>
        <div id="hiradcList"></div>
        <div class="hiradc-actions">
          <button type="button" style="background:#E8ECF8;color:var(--navy-dark);" onclick="PtwHiradc.close()">Batal</button>
          <button type="button" style="background:var(--navy);color:#fff;" onclick="PtwHiradc.apply()">Tambahkan ke JSA</button>
        </div>
      </div>`;
    m.addEventListener('click', e => { if (e.target === m) close(); });
    document.body.appendChild(m);
    document.getElementById('hiradcAll').addEventListener('change', e => {
      document.querySelectorAll('#hiradcList input[type=checkbox]').forEach(c => c.checked = e.target.checked);
    });
  }

  async function open() {
    const projectId = Number(selectProject.value);
    if (!projectId) { alert('Pilih Project / Kontrak dulu.'); return; }
    ensureModal();
    const list = document.getElementById('hiradcList');
    list.innerHTML = '<div style="padding:20px;text-align:center;color:var(--muted);">Memuat HIRADC...</div>';
    document.getElementById('hiradcAll').checked = false;
    document.getElementById('hiradcModal').classList.add('open');
    const { data, error } = await supabaseClient.rpc('get_hiradc_items_for_project', { p_project_id: projectId });
    if (error) { list.innerHTML = `<div style="padding:20px;color:var(--accent);">Gagal memuat: ${escapeHtml(error.message)}</div>`; return; }
    items = data || [];
    if (!items.length) {
      list.innerHTML = '<div style="padding:20px;text-align:center;color:var(--muted);">Belum ada HIRADC yang Disetujui untuk project ini.</div>';
      return;
    }
    let lastDoc = null;
    list.innerHTML = items.map((it, i) => {
      const head = it.hiradcId !== lastDoc
        ? `<div class="hiradc-doc">${escapeHtml(it.noDokumen)} Rev.${it.revisi} -- ${escapeHtml(it.judul)}</div>` : '';
      lastDoc = it.hiradcId;
      return `${head}<label class="hiradc-pick"><input type="checkbox" data-i="${i}">
        <div><b>${escapeHtml(it.aktivitas)}</b> -- ${escapeHtml(it.bahaya)}
        <div class="sub">Risiko awal ${escapeHtml(it.tingkatAwal)} (${it.skorAwal}) → sisa ${escapeHtml(it.tingkatSisa)} (${it.skorSisa})</div></div></label>`;
    }).join('');
  }

  function close() {
    const m = document.getElementById('hiradcModal');
    if (m) m.classList.remove('open');
  }

  function rowIsEmpty(row) {
    return [...row.querySelectorAll('textarea')].every(t => !t.value.trim());
  }

  // Baris yang isinya masih persis contoh generik dari ptwJsaTemplateTbl (variabel jsaTemplate
  // di ptw-report.html) -- dianggap belum disesuaikan, jadi boleh diganti baris HIRADC.
  function rowIsUntouchedGeneric(row) {
    const tpl = (typeof jsaTemplate !== 'undefined' && Array.isArray(jsaTemplate)) ? jsaTemplate : [];
    const v = sel => ((row.querySelector(sel) || {}).value || '').trim();
    const langkah = v('[id^="jsa-langkah-"]'), bahaya = v('[id^="jsa-bahaya-"]'), pengendalian = v('[id^="jsa-pengendalian-"]');
    return tpl.some(t => (t.langkah || '').trim() === langkah && (t.bahaya || '').trim() === bahaya
      && (t.pengendalian || '').trim() === pengendalian);
  }

  function apply() {
    const picked = [...document.querySelectorAll('#hiradcList input[data-i]:checked')].map(c => items[Number(c.dataset.i)]);
    if (!picked.length) { alert('Belum ada baris yang dicentang.'); return; }
    // buang baris JSA kosong, plus contoh generik yang belum diedit kalau dicentang
    const ganti = document.getElementById('hiradcGanti').checked;
    [...jsaRows.children].forEach(r => { if (rowIsEmpty(r) || (ganti && rowIsUntouchedGeneric(r))) r.remove(); });
    picked.forEach(it => addJsaRow({
      langkah: it.aktivitas,
      bahaya: it.risiko ? `${it.bahaya}\nRisiko: ${it.risiko}` : it.bahaya,
      pengendalian: [it.pengendalianExisting, it.pengendalianTambahan].filter(Boolean).join('\n'),
      likelihoodAwal: it.likelihoodAwal, severityAwal: it.severityAwal,
      likelihoodSisa: it.likelihoodSisa, severitySisa: it.severitySisa
    }));
    [...jsaRows.children].forEach((r, i) => {
      const lbl = r.querySelector('.jsa-row-label');
      if (lbl) lbl.textContent = `Langkah ${i + 1}`;
    });
    close();
  }

  global.PtwHiradc = { open, close, apply };
})(window);
