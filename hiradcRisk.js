// =====================================================================================
// HSSE-Fusion4 -- matriks risiko 5x5 HIRADC (sama dengan JSA PTW, getRiskLevel di ptw-report.html
// dan hiradc_tingkat() di SQL 067). Kalau ambang skor diubah, ubah di ketiga tempat itu.
// =====================================================================================
(function (global) {
  const LIKELIHOOD = {
    1: 'Hampir Tidak Mungkin', 2: 'Jarang Terjadi', 3: 'Kadang Terjadi',
    4: 'Sering Terjadi', 5: 'Hampir Pasti Terjadi'
  };
  const SEVERITY = {
    1: 'Tidak Signifikan', 2: 'Kecil (P3K)', 3: 'Sedang (Medis)',
    4: 'Berat (Cacat)', 5: 'Fatal'
  };
  const KONDISI = ['Rutin', 'Non Rutin', 'Darurat'];
  const KATEGORI = ['Keselamatan', 'Kesehatan', 'Lingkungan', 'Security'];
  const HIERARKI = ['Eliminasi', 'Substitusi', 'Rekayasa', 'Administrasi', 'APD'];
  const LEVELS = ['Rendah', 'Sedang', 'Tinggi', 'Ekstrem'];

  function level(likelihood, severity) {
    const score = Number(likelihood) * Number(severity);
    if (score <= 4) return { label: 'Rendah', cls: 'risk-rendah', score };
    if (score <= 9) return { label: 'Sedang', cls: 'risk-sedang', score };
    if (score <= 15) return { label: 'Tinggi', cls: 'risk-tinggi', score };
    return { label: 'Ekstrem', cls: 'risk-ekstrem', score };
  }

  // Tabel 5x5: baris = Kemungkinan (5 di atas), kolom = Keparahan. Butuh CSS .matrix + .m-<level>.
  function matrixHtml() {
    let h = '<table class="matrix"><tr><th>L \\ S</th>' + [1, 2, 3, 4, 5].map(s => `<th title="${SEVERITY[s]}">${s}</th>`).join('') + '</tr>';
    for (let l = 5; l >= 1; l--) {
      h += `<tr><th title="${LIKELIHOOD[l]}">${l}</th>` +
        [1, 2, 3, 4, 5].map(s => `<td class="m-${level(l, s).label.toLowerCase()}">${l * s}</td>`).join('') + '</tr>';
    }
    return h + '</table><div style="font-size:11px;color:var(--muted);margin-top:4px;">1-4 Rendah · 5-9 Sedang · 10-15 Tinggi · 16-25 Ekstrem</div>';
  }

  function tgl(v) {
    if (!v) return '';
    const d = new Date(String(v).length === 10 ? v + 'T00:00:00' : v);
    return isNaN(d) ? String(v) : d.toLocaleDateString('id-ID', { day: '2-digit', month: 'short', year: 'numeric' });
  }

  global.HiradcRisk = { LIKELIHOOD, SEVERITY, KONDISI, KATEGORI, HIERARKI, LEVELS, level, matrixHtml, tgl };
})(window);
