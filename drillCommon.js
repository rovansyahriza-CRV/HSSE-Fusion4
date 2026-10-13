// =====================================================================================
// HSSE-Fusion4 -- helper bersama modul Drill / Tanggap Darurat & Review ERP (SQL 069).
//   PIC "HSSE-DRL" (atau HSSE-ALL) = rencana, mulai, absen, laporan, temuan, review ERP
//   Author "Approve Drill"         = setujui / kembalikan laporan drill & review ERP
// Server tetap cek ulang lewat hsse_wajib_akses, jadi ini cuma buat tampilan.
// =====================================================================================
(function (global) {
  const PIC_TAG = 'HSSE-DRL';
  const APPROVER_TAG = 'Approve Drill';

  const JENIS = ['Fire', 'Muster / Evakuasi', 'Medical', 'Spill', 'Gas Release / H2S', 'Lainnya'];
  const PERAN = ['Peserta', 'ERT / Fire Warden', 'First Aider', 'Observer', 'Koordinator'];
  const HASIL = ['Baik', 'Cukup', 'Kurang', 'N/A'];
  const JENIS_REVIEW = ['Tahunan', 'Pasca Drill', 'Pasca Insiden', 'Perubahan Operasi', 'Lainnya'];

  const ASPEK_UMUM = [
    'Alarm / sistem komunikasi darurat terdengar & dipahami',
    'Respon awal dan pelaporan ke koordinator',
    'Jalur evakuasi bebas hambatan & rambu terlihat',
    'Kecepatan menuju muster point / titik kumpul',
    'Headcount / absensi di muster point akurat',
    'Peran ERT / fire warden / first aider dijalankan',
    'Kesiapan peralatan darurat',
    'Penggunaan APD selama drill',
    'Koordinasi dengan pihak luar (klinik, damkar, client)'
  ];
  const ASPEK_JENIS = {
    'Fire': ['APAR / hydrant dapat dijangkau dan berfungsi', 'Teknik pemadaman sesuai jenis api'],
    'Medical': ['Kecepatan pertolongan pertama (P3K)', 'Kesiapan tandu, kotak P3K, AED', 'Evakuasi medis / MEDEVAC ke klinik/RS rujukan'],
    'Spill': ['Kesiapan & penggunaan spill kit', 'Penahanan tumpahan sebelum masuk drainase/tanah', 'Penanganan limbah hasil pembersihan'],
    'Gas Release / H2S': ['Deteksi gas & pembacaan gas detector', 'Evakuasi melawan arah angin (windsock)', 'Penggunaan SCBA / escape set'],
    'Muster / Evakuasi': ['Waktu evakuasi sesuai target', 'Pemeriksaan area (sweeping) oleh warden']
  };

  function aspekDefault(jenis) {
    return [...ASPEK_UMUM, ...(ASPEK_JENIS[jenis] || [])].map(a => ({ aspek: a, hasil: '', catatan: '' }));
  }

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
  // ISO -> nilai <input type="datetime-local"> (jam lokal browser)
  function toLocalInput(v) {
    if (!v) return '';
    const d = new Date(v);
    const p = n => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
  }
  // nilai datetime-local -> ISO dengan zona waktu browser (null kalau kosong)
  function fromLocalInput(v) { return v ? new Date(v).toISOString() : null; }
  function statusCls(s) { return String(s || '').toLowerCase().replaceAll(' ', '-').replaceAll('/', ''); }

  function hadirPersen(d) {
    if (!d.jumlahOrangDiArea) return null;
    return Math.round((d.jumlahHadir / d.jumlahOrangDiArea) * 1000) / 10;
  }

  function personNama(p, fallback) {
    return (p && (p.nama || p.NamaPersonnel || p.Nama || p.name)) || fallback || 'Tanpa nama';
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

  function extractQrId(raw) {
    let id = String(raw || '').trim();
    try {
      const url = new URL(id);
      const q = url.searchParams.get('QrCodeId') || url.searchParams.get('qrCodeId') || url.searchParams.get('qrcodeid');
      if (q) id = q;
    } catch (e) { /* bukan URL */ }
    return id.trim().toUpperCase();
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

  global.DrillCommon = {
    PIC_TAG, APPROVER_TAG, JENIS, PERAN, HASIL, JENIS_REVIEW, aspekDefault,
    esc, tgl, jam, tglJam, toLocalInput, fromLocalInput, statusCls, hadirPersen,
    findPerson, extractQrId, verifyAktor
  };
})(window);
