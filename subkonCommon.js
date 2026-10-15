// =====================================================================================
// HSSE-Fusion4 -- helper bersama modul Subkontraktor / CSMS (SQL 071, data perusahaan dari SMMS BIMA: SQL 072).
//   PIC "HSSE-SUB" (atau HSSE-ALL)    = register subkon, pekerjaan, dokumen, evaluasi
//   Author "Approve Subkon"           = setujui / kembalikan evaluasi CSMS
// Server tetap cek ulang lewat hsse_wajib_akses, jadi ini cuma buat tampilan.
// =====================================================================================
(function (global) {
  const PIC_TAG = 'HSSE-SUB';
  const APPROVER_TAG = 'Approve Subkon';

  const STATUS_SUBKON = ['Aktif', 'Tidak Aktif', 'Daftar Hitam'];
  const STATUS_PEKERJAAN = ['Rencana', 'Berjalan', 'Selesai', 'Dibatalkan'];
  const RISIKO = ['Rendah', 'Menengah', 'Tinggi'];
  // sama dengan subkon_nilai_minimum() di SQL 071
  const NILAI_MINIMUM = { 'Rendah': 55, 'Menengah': 65, 'Tinggi': 75 };
  const TAHAP = ['Prakualifikasi', 'Pre-Job Activity', 'Work in Progress', 'Final Evaluation'];
  const TAHAP_SINGKAT = { 'Prakualifikasi': 'PQ', 'Pre-Job Activity': 'PJA', 'Work in Progress': 'WIP', 'Final Evaluation': 'FE' };
  const JENIS_DOKUMEN = ['NIB / Izin Usaha', 'Sertifikat CSMS / PQ Client', 'ISO 45001 / SMK3', 'HSE Plan',
    'BPJS Ketenagakerjaan / Asuransi', 'Sertifikat Kompetensi Personil', 'MCU / Fit to Work', 'Lainnya'];
  const DOKUMEN_PERSONIL = ['Sertifikat Kompetensi Personil', 'MCU / Fit to Work'];
  const NILAI = [
    { v: '3', t: '3 Baik' }, { v: '2', t: '2 Cukup' }, { v: '1', t: '1 Kurang' }, { v: '0', t: '0 Tidak ada' }, { v: 'N/A', t: 'N/A' }
  ];
  const HASIL = ['Memenuhi', 'Memenuhi dengan Catatan', 'Tidak Memenuhi'];

  function esc(v) {
    return String(v ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  }
  function tgl(v) {
    if (!v) return '-';
    const d = new Date(String(v).length === 10 ? v + 'T00:00:00' : v);
    return d.toLocaleDateString('id-ID', { day: '2-digit', month: 'short', year: 'numeric' });
  }
  function toLocalInput(v) {
    if (!v) return '';
    const d = new Date(v);
    const p = n => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
  }
  function fromLocalInput(v) { return v ? new Date(v).toISOString() : null; }
  function statusCls(s) { return String(s || '').toLowerCase().replaceAll(' ', '-').replaceAll('/', ''); }
  function nilai(v) { return v === null || v === undefined ? '-' : Number(v).toLocaleString('id-ID', { maximumFractionDigits: 1 }); }

  // Hitung nilai % dari checklist (sama dengan server): jumlah / (3 x item dinilai) x 100
  function hitungNilai(list) {
    const dinilai = list.filter(x => ['0', '1', '2', '3'].includes(String(x.nilai)));
    const total = dinilai.reduce((s, x) => s + Number(x.nilai), 0);
    return {
      dinilai: dinilai.length,
      nol: dinilai.filter(x => String(x.nilai) === '0').length,
      kosong: list.filter(x => !['0', '1', '2', '3', 'N/A'].includes(String(x.nilai))).length,
      persen: dinilai.length ? Math.round(total * 1000 / (3 * dinilai.length)) / 10 : null
    };
  }

  // Teks + kelas chip sisa masa berlaku dokumen
  function sisaLabel(s) {
    if (s.sisaHari === null || s.sisaHari === undefined) return 'tanpa masa berlaku';
    if (s.sisaHari < 0) return `habis ${-s.sisaHari} hari lalu`;
    if (s.sisaHari === 0) return 'habis hari ini';
    return `${s.sisaHari} hari lagi`;
  }

  // Chip ringkas status CSMS per tahap (PQ / PJA / WIP / FE) dari pekerjaan.csms
  function csmsChips(p) {
    const c = p.csms || {};
    return TAHAP.map(t => {
      const e = c[t];
      const cls = !e ? 'belum' : statusCls(e.hasil);
      const judul = e ? `${t}: ${e.hasil} (${nilai(e.nilai)}) ${tgl(e.tanggal)}` : `${t}: belum ada evaluasi disetujui`;
      return `<span class="csms-chip ${cls}" title="${esc(judul)}">${TAHAP_SINGKAT[t]}${e ? ' ' + nilai(e.nilai) : ''}</span>`;
    }).join('');
  }

  // Chip asal data SMMS BIMA (SQL 072): terhubung, tidak ada lagi di SMMS, atau masih input manual lama
  function smmsChip(r) {
    if (!r.vendorIdSmms) return '<span class="status-chip tidak-aktif" title="Dibuat manual sebelum terhubung ke SMMS">Belum terhubung SMMS</span>';
    if (r.statusSmms && r.statusSmms !== 'Approved') return `<span class="status-chip daftar-hitam" title="Vendor tidak Approved lagi di SMMS BIMA">${esc(r.statusSmms)}</span>`;
    return '';
  }

  function personNama(p, fallback) {
    return (p && (p.nama || p.NamaPersonnel || p.Nama || p.name)) || fallback || 'Tanpa nama';
  }

  function extractQrId(raw) {
    let id = String(raw || '').trim();
    try {
      const url = new URL(id);
      const q = url.searchParams.get('QrCodeId') || url.searchParams.get('qrCodeId') || url.searchParams.get('qrcodeid');
      if (q) id = q;
    } catch (e) { /* bukan URL */ }
    return id.trim().toUpperCase();
  }

  // Cari orang di SmartGate dari QR Code ID atau PIN. Hasil: { nama, qrCodeId, person } atau null.
  async function findPerson(fusion4, qr, pin) {
    if (qr) {
      const id = extractQrId(qr);
      const { data, error } = await fusion4.rpc('get_person_face_data', { p_qrcode: id });
      if (error) throw error;
      if (!data || data.status === 'NOT_FOUND' || data.status === 'REJECTED' || !data.person) return null;
      return { nama: personNama(data.person, id), qrCodeId: data.person.qrCodeId || id, person: data.person };
    }
    if (pin) {
      const { data, error } = await fusion4.rpc('get_all_face_data');
      if (error) throw error;
      const p = (data || []).find(x => String(x.digitalPin || '').trim() === String(pin).trim());
      return p ? { nama: personNama(p), qrCodeId: p.qrCodeId, person: p } : null;
    }
    return null;
  }

  // Verifikasi PIC/approver. Hasil: { nama, qrCodeId, bisaPic, bisaApprove } atau lempar Error.
  async function verifyAktor(fusion4, qr, pin) {
    const found = await findPerson(fusion4, qr, pin);
    if (!found) throw new Error('Identitas tidak ditemukan di SmartGate.');
    const bisaPic = HSSEAccess.allows(found.person, PIC_TAG);
    const bisaApprove = HSSEAccess.allows(found.person, APPROVER_TAG);
    if (!bisaPic && !bisaApprove) {
      throw new Error(`${found.nama} belum punya ${HSSEAccess.label(PIC_TAG)} atau ${HSSEAccess.label(APPROVER_TAG)}.`);
    }
    return { nama: found.nama, qrCodeId: found.qrCodeId, bisaPic, bisaApprove };
  }

  global.SubkonCommon = {
    PIC_TAG, APPROVER_TAG, STATUS_SUBKON, STATUS_PEKERJAAN, RISIKO, NILAI_MINIMUM, TAHAP, TAHAP_SINGKAT,
    JENIS_DOKUMEN, DOKUMEN_PERSONIL, NILAI, HASIL,
    esc, tgl, toLocalInput, fromLocalInput, statusCls, nilai, hitungNilai, sisaLabel, csmsChips, smmsChip,
    findPerson, extractQrId, verifyAktor
  };
})(window);
