// =====================================================================================
// Piramida Keselamatan (Statistik & KPI)
// Dipakai statistik-kpi.html dan statistik-kpi-pdf.html.
// Data dari RPC get_statistik_piramida (migrasi 058).
// Lebar tiap lapisan itu bentuk piramida, BUKAN skala data. Angka & rasio ada di labelnya.
// =====================================================================================
(function () {
  // Satu warna (merah), makin atas makin gelap = makin parah.
  const WARNA = ['#5C0B10', '#7F1419', '#A11D22', '#C0392B', '#D9604F', '#E8897A', '#F2B3A8'];
  const INFO = {
    FAT: 'Meninggal dunia',
    LTI: 'Hilang hari kerja',
    RWC: 'Kerja terbatas / pindah tugas',
    MTC: 'Perlu perawatan medis',
    FAC: 'Cukup P3K',
    NM: 'Hampir celaka',
    UA: 'Tindakan / kondisi tidak aman'
  };
  const BULAN = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];

  function esc(s) {
    return String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  }
  function num(v) { return Number(v || 0).toLocaleString('id-ID'); }
  function rasio(v, basis) {
    const r = Number(v || 0) / basis;
    if (r === 0) return '0';
    return r < 10 ? r.toLocaleString('id-ID', { maximumFractionDigits: 1 }) : Math.round(r).toLocaleString('id-ID');
  }

  // Basis rasio: cedera berat (Fatality + LTI). Kalau 0, pakai recordable. Kalau 0 juga, lapisan teratas yang ada isinya.
  function hitungBasis(lap) {
    const by = k => Number((lap.find(l => l.kode === k) || {}).jumlah || 0);
    const berat = by('FAT') + by('LTI');
    if (berat > 0) return { nilai: berat, kode: ['FAT', 'LTI'], label: 'Fatality + LTI' };
    const rec = berat + by('RWC') + by('MTC');
    if (rec > 0) return { nilai: rec, kode: ['FAT', 'LTI', 'RWC', 'MTC'], label: 'Recordable (Fatality + LTI + RWC + MTC)' };
    const atas = lap.find(l => Number(l.jumlah) > 0);
    if (atas) {
      const idx = lap.indexOf(atas);
      return { nilai: Number(atas.jumlah), kode: lap.slice(0, idx + 1).map(l => l.kode), label: atas.nama };
    }
    return null;
  }

  function rincianText(l) {
    if (!l.rincian) return '';
    if (l.kode === 'NM') return `Incident ${num(l.rincian.incident)} · CERMAT ${num(l.rincian.cermat)}`;
    if (l.kode === 'UA') return `CERMAT ${num(l.rincian.cermat)} · item inspeksi ${num(l.rincian.inspeksi)}`;
    return '';
  }

  function periodeText(d) {
    const a = d.bulanDari || 1, b = d.bulanSampai || 12;
    return a === 1 && b === 12 ? `Jan – Des ${d.tahun}` : (a === b ? `${BULAN[a - 1]} ${d.tahun}` : `${BULAN[a - 1]} – ${BULAN[b - 1]} ${d.tahun}`);
  }

  // Ringkasan gaya Bird: berat : recordable lain : first aid : near miss : unsafe
  function ringkasanBird(lap) {
    const by = k => Number((lap.find(l => l.kode === k) || {}).jumlah || 0);
    const berat = by('FAT') + by('LTI');
    if (!berat) return '';
    const parts = [berat, by('RWC') + by('MTC'), by('FAC'), by('NM'), by('UA')].map(v => rasio(v, berat));
    return `Rasio Fatality+LTI : RWC+MTC : First Aid : Near Miss : Unsafe = <b>${parts.join(' : ')}</b>`;
  }

  function svgPiramida(lap, basis, opts) {
    const W = 760, bandH = 46, gap = 3, top = 8, pyrW = 360, pyrX = 8;
    const n = lap.length;
    const H = top + n * bandH + (n - 1) * gap + 8;
    const cx = pyrX + pyrW / 2;
    const slope = (pyrW / 2) / (n * bandH + (n - 1) * gap); // setengah lebar per px tinggi
    const labelX = pyrX + pyrW + 28;
    let g = '';
    lap.forEach((l, i) => {
      const y0 = top + i * (bandH + gap);
      const y1 = y0 + bandH;
      const hw0 = (y0 - top) * slope, hw1 = (y1 - top) * slope;
      const pts = i === 0
        ? `${cx},${y0} ${cx + hw1},${y1} ${cx - hw1},${y1}`
        : `${cx - hw0},${y0} ${cx + hw0},${y0} ${cx + hw1},${y1} ${cx - hw1},${y1}`;
      const jml = Number(l.jumlah || 0);
      const dalamBasis = basis && basis.kode.includes(l.kode);
      const r = !basis ? '–' : (dalamBasis ? 'basis' : '1 : ' + rasio(jml, basis.nilai));
      const rinc = rincianText(l);
      const tip = `${l.nama}: ${num(jml)}${rinc ? ' (' + rinc + ')' : ''}${basis && !dalamBasis ? ' · rasio 1 : ' + rasio(jml, basis.nilai) : ''}`;
      const midY = y0 + bandH / 2;
      const edgeX = cx + (hw0 + hw1) / 2;
      const kodeFill = i <= 3 ? '#FFFFFF' : '#3A0A0C';
      g += `<g class="pyr-band" tabindex="0" role="listitem" aria-label="${esc(tip)}">
        <title>${esc(tip)}</title>
        <polygon points="${pts}" fill="${WARNA[i]}" stroke="rgba(0,0,0,0.12)" stroke-width="1"></polygon>
        ${i === 0 ? '' : `<text x="${cx}" y="${midY + 5}" text-anchor="middle" font-size="14" font-weight="800" fill="${kodeFill}">${esc(l.kode)}</text>`}
        <line x1="${edgeX + 4}" y1="${midY}" x2="${labelX - 8}" y2="${midY}" stroke="#C5CAD8" stroke-width="1" stroke-dasharray="2 3"></line>
        <text x="${labelX}" y="${midY - 4}" font-size="13.5" font-weight="700" fill="#1B2650">${esc(l.nama)}${i === 0 ? ' (FAT)' : ''}</text>
        <text x="${labelX}" y="${midY + 13}" font-size="11.5" fill="#6B7280">${esc(rinc || INFO[l.kode] || '')}</text>
        <text x="${W - 120}" y="${midY + 6}" text-anchor="end" font-size="20" font-weight="800" fill="${(l.kode === 'FAT' || l.kode === 'LTI') && jml ? '#C0392B' : '#1B2650'}">${num(jml)}</text>
        <text x="${W - 8}" y="${midY + 5}" text-anchor="end" font-size="13" font-weight="700" fill="${r === 'basis' ? '#6B7280' : '#2D3C73'}">${esc(r)}</text>
      </g>`;
    });
    const head = `<text x="${W - 120}" y="0" text-anchor="end" font-size="10.5" font-weight="700" fill="#6B7280" dy="-2">JUMLAH</text>
      <text x="${W - 8}" y="0" text-anchor="end" font-size="10.5" font-weight="700" fill="#6B7280" dy="-2">RASIO</text>`;
    // Di HP lebar minimal 600px, geser ke samping di dalam kotak biar tulisan tetap kebaca.
    return `<div style="overflow-x:auto;-webkit-overflow-scrolling:touch;"><svg class="pyr-svg" viewBox="0 -12 ${W} ${H + 12}" role="list" aria-label="Piramida keselamatan" style="width:100%;min-width:${opts.maxWidth ? 0 : 600}px;height:auto;display:block;${opts.maxWidth ? 'max-width:' + opts.maxWidth + ';' : ''}">${head}${g}</svg></div>`;
  }

  function tabel(lap, basis) {
    return `<table class="pyr-table"><thead><tr><th style="text-align:left;">Lapisan</th><th>Jumlah</th><th>Rincian</th><th>Rasio</th></tr></thead><tbody>` +
      lap.map(l => {
        const dalamBasis = basis && basis.kode.includes(l.kode);
        return `<tr><td style="text-align:left;">${esc(l.nama)}</td><td>${num(l.jumlah)}</td><td>${esc(rincianText(l)) || '–'}</td>
          <td>${!basis ? '–' : (dalamBasis ? 'basis' : '1 : ' + rasio(l.jumlah, basis.nilai))}</td></tr>`;
      }).join('') + '</tbody></table>';
  }

  window.renderPiramida = function (el, d, opts) {
    opts = opts || {};
    const lap = (d && d.lapisan) || [];
    const basis = hitungBasis(lap);
    const luar = (d && d.diLuarPiramida) || {};
    const info = (d && d.info) || {};
    const bird = ringkasanBird(lap);
    el.innerHTML =
      svgPiramida(lap, basis, opts) +
      `<div class="pyr-note">` +
        `Periode ${esc(periodeText(d))}. ` +
        (basis ? `Basis rasio (1) = <b>${esc(basis.label)}</b> = ${num(basis.nilai)} kejadian. ` : 'Belum ada data di periode ini. ') +
        (bird ? bird + '. ' : '') +
        `Di luar piramida: kerusakan properti ${num(luar.kerusakanProperti)}, lingkungan ${num(luar.lingkungan)}, keamanan ${num(luar.keamanan)}. ` +
        `Unsafe = CERMAT negatif selain near miss (CERMAT hasil inspeksi gak dihitung lagi, biar gak dobel) + item checklist "Tidak Sesuai" dari ${num(info.jumlahInspeksi)} inspeksi. ` +
        `Lebar lapisan cuma bentuk piramida, bukan skala angka. Pembanding umum: Heinrich 1 : 29 : 300, Bird 1 : 10 : 30 : 600.` +
      `</div>` +
      (opts.tabel === false ? '' : `<details class="pyr-details"><summary>Lihat sebagai tabel</summary>${tabel(lap, basis)}</details>`);
  };
})();
