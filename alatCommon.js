// =====================================================================================
// HSSE-Fusion4 -- helper bersama modul Inspeksi Alat & Sertifikasi (SQL 070).
//   PIC "HSSE-ALT" (atau HSSE-ALL)    = register alat, sertifikat, inspeksi
//   Author "Approve Inspeksi Alat"    = setujui / kembalikan inspeksi alat
// Server tetap cek ulang lewat hsse_wajib_akses, jadi ini cuma buat tampilan.
// =====================================================================================
(function (global) {
  const PIC_TAG = 'HSSE-ALT';
  const APPROVER_TAG = 'Approve Inspeksi Alat';

  // kategori -> interval inspeksi default (hari), bisa diubah per alat
  const KATEGORI = {
    'Alat Angkat & Lifting Gear': 30,
    'Alat Berat & Kendaraan': 30,
    'Kelistrikan & Power Tools': 30,
    'Bejana Tekan & Kompresor': 30,
    'Peralatan Las & Tabung Gas': 30,
    'Scaffolding & Tangga': 7,
    'APAR & Peralatan Pemadam': 30,
    'Gas Detector & Alat Ukur': 30,
    'Hand Tools': 90,
    'Lainnya': 30
  };
  // kategori yang biasanya tidak wajib sertifikat pihak ketiga
  const TANPA_SERTIFIKAT = ['Hand Tools', 'Scaffolding & Tangga'];
  const PEMILIK = ['BIMA', 'Subkon', 'Sewa / Rental', 'Client'];
  const JENIS_SERTIFIKAT = ['SILO / Riksa Uji Disnaker', 'Sertifikat Inspeksi PJK3 / Third Party', 'Kalibrasi',
    'Load Test', 'Sertifikat Pabrikan / COC', 'Lainnya'];
  const JENIS_INSPEKSI = ['Pre-use / Harian', 'Mingguan', 'Bulanan / Color Code', 'Pasca Perbaikan', 'Insidental'];
  const HASIL_ITEM = ['Baik', 'Tidak Baik', 'N/A'];
  const HASIL = ['Layak', 'Layak dengan Catatan', 'Tidak Layak'];
  const WARNA_TAG = ['Merah', 'Kuning', 'Hijau', 'Biru', 'Putih', 'Lainnya'];

  function esc(v) {
    return String(v ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  }
  function tgl(v) {
    if (!v) return '-';
    const d = new Date(String(v).length === 10 ? v + 'T00:00:00' : v);
    return d.toLocaleDateString('id-ID', { day: '2-digit', month: 'short', year: 'numeric' });
  }
  function jam(v) {
    if (!v) return '-';
    return new Date(v).toLocaleTimeString('id-ID', { hour: '2-digit', minute: '2-digit' });
  }
  function tglJam(v) { return v ? `${tgl(v)} ${jam(v)}` : '-'; }
  function toLocalInput(v) {
    if (!v) return '';
    const d = new Date(v);
    const p = n => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
  }
  function fromLocalInput(v) { return v ? new Date(v).toISOString() : null; }
  function statusCls(s) { return String(s || '').toLowerCase().replaceAll(' ', '-').replaceAll('/', ''); }

  // Teks + kelas chip sisa masa berlaku sertifikat
  function sisaLabel(s) {
    if (s.statusBerlaku === 'Belum Ada') return 'belum ada sertifikat';
    if (s.sisaHari === null || s.sisaHari === undefined) return 'tanpa masa berlaku';
    if (s.sisaHari < 0) return `habis ${-s.sisaHari} hari lalu`;
    if (s.sisaHari === 0) return 'habis hari ini';
    return `${s.sisaHari} hari lagi`;
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

  global.AlatCommon = {
    PIC_TAG, APPROVER_TAG, KATEGORI, TANPA_SERTIFIKAT, PEMILIK, JENIS_SERTIFIKAT, JENIS_INSPEKSI,
    HASIL_ITEM, HASIL, WARNA_TAG,
    esc, tgl, jam, tglJam, toLocalInput, fromLocalInput, statusCls, sisaLabel,
    findPerson, extractQrId, verifyAktor
  };
})(window);
