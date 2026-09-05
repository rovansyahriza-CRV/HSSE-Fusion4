# HSSE-Fusion4

Sistem pelaporan HSSE (Health, Safety, Security & Environment) untuk pekerjaan
konstruksi PT BIMA sebagai kontraktor di proyek oil & gas (Pertamina Hulu /
Upstream). Dibangun dengan pola yang sama seperti [Fusion4 SmartGate](https://github.com/rovansyahriza-CRV/Fusion4)
dan SMMS-BIMA (website mobile-first + Supabase + GitHub Pages + Google Drive
buat file), tapi dengan **project Supabase & Drive Bridge sendiri, terpisah**
dari keduanya.

Tujuan utama: data HSSE (insiden, PEKA, inspeksi, permit to work, statistik)
selalu konsisten & ter-update dari lapangan, sehingga siap disajikan langsung
kalau ada audit CSMS berkala dari klien migas -- bukan direkap manual pas mepet
audit.

## Status

✅ **MVP pertama (CERMAT) sudah jadi.** Yang sudah selesai:

- [x] Struktur folder & branding dasar (navy + merah, konsisten sama Fusion4)
- [x] Riset standar HSSE Pertamina Hulu / Upstream (lihat bagian "Riset" di bawah)
- [x] Pola Drive Bridge (upload foto/PDF ke Google Drive) disiapkan ulang dari SMMS-BIMA, folder & token sendiri -- `AppsScript-Code.gs` sudah di-deploy & dites (`{"error":"Token tidak valid."}` muncul benar untuk token salah)
- [x] Project Supabase baru dibuat (`wvzajdnxmjegblqrvgfs.supabase.co`), key publishable sudah diisi di `config.js`
- [x] **Modul CERMAT (istilah lokal untuk PEKA)** -- form lapor (`cermat-report.html`) + halaman riwayat/audit dengan update status (`cermat-list.html`) + schema & RPC (`sql/001_cermat_schema.sql`)
- [ ] Belum dijalankan: migrasi `sql/001_cermat_schema.sql` di Supabase SQL Editor (lakukan ini dulu sebelum coba form-nya)
- [ ] Belum diisi: data Project/Kontrak asli (masih ada 1 baris placeholder "Contoh Project - GANTI INI")
- [ ] Modul lain (Incident, Inspeksi, Permit to Work, Dashboard KPI) belum dibangun

### Cara mulai pakai CERMAT

1. Buka Supabase project `wvzajdnxmjegblqrvgfs` -> **SQL Editor** -> New query -> paste seluruh isi `sql/001_cermat_schema.sql` -> Run.
2. Buka tab **Table Editor** -> tabel `projectTbl` -> hapus/ganti baris contoh, tambahkan project/kontrak asli kalian (kolom `TipeKonstruksi` cuma boleh `Onshore` atau `Offshore`).
3. Buka `cermat-report.html` di browser (atau lewat GitHub Pages setelah di-push) buat coba lapor. Buka `cermat-list.html` buat lihat riwayat & update status tindak lanjut sampai Closed.

## Riset: standar HSSE Pertamina Hulu (Upstream) untuk kontraktor

Dirangkum dari kebijakan resmi PHE, materi HSSE Subholding Upstream, dan
panduan CSMS -- dipakai sebagai acuan istilah & struktur data:

- **CSMS (Contractor Safety Management System)** -- syarat wajib kontraktor, 3 fase: Pre-Qualification (kuesioner HSSE + statistik TRIR/LTIFR, diklasifikasi Low/Medium/High Risk) -> Seleksi/Tender (HSE Plan dievaluasi pakai kerangka SUPREME) -> Implementation (inspeksi rutin, monitoring, evaluasi akhir).
- **PEKA (Pengamatan Keselamatan Kerja)** -- ini istilah resmi Pertamina buat "Anomaly Report". Kategori: *safe action*, *unsafe action*, *unsafe condition*, *near-miss*. Proses: Plan -> Observe -> Communicate -> Report. Ada wewenang **Stop Work Authority**.
- **Klasifikasi keparahan insiden** (6 tingkat): First Aid -> Near Miss -> Medical Treatment Case (MTC) -> Restricted Work Day Case (RWDC) -> Day Away From Work/LTI -> Fatality. **Wajib dilaporkan maksimal 12 jam setelah insiden.**
- **KPI standar**: TRIR (Total Recordable Incident Rate), LTIFR (Lost Time Injury Frequency Rate), total man-hours, tren temuan terbuka/tertutup.
- **Dokumen wajib CSMS**: HIRADC/JSA, sistem Permit-to-Work, Emergency Response Plan, matriks kompetensi, log inspeksi, laporan insiden & near-miss dengan root cause, catatan toolbox meeting, laporan audit.
- **HSSE Golden Rules**: "Patuh - Intervensi - Peduli" (PIP), plus Corporate Life Saving Rules (CLSR) -- daftar 12 aturan spesifiknya belum ketemu sumber terbuka lengkap, sebaiknya cek salinan dari HSE Plan kontrak PT BIMA kalau ada.

Sumber: [Kebijakan HSSE PHE](https://phe.pertamina.com/assets/files/hsse-policy-en.pdf), [Incident Reporting HSSE Subholding Upstream](https://hops-psu.com/bhl/pdf/9.pdf), [HSSE Observation & SWA / PEKA](https://hops-psu.com/bhl/pdf/8.pdf), [Panduan CSMS Pertamina](https://aksenijasa.com/panduan-lengkap-csms-pertamina/).

## Arahan desain (dari diskusi)

Karena tujuan utamanya audit-readiness, urutan bangun yang disepakati:

1. **Tulang punggung bersama dulu**: sistem tracking temuan & corrective action (status Open/In Progress/Closed, penanggung jawab, tenggat) -- dipakai bareng oleh PEKA, Inspeksi, dan Incident Report.
2. **Dashboard KPI** dihitung otomatis dari data yang masuk (bukan rekap manual).
3. Baru form-form input spesifik per modul nempel ke tulang punggung itu.
4. Setiap tabel butuh jejak audit (siapa isi, kapan, idealnya gak bisa diam-diam diedit/dihapus).

## Modul

- [x] **CERMAT** -- istilah lokal untuk PEKA (istilah resmi Pertamina). Sifat **Positif** (Safe Act/Safe Condition) atau **Negatif** (Unsafe Act/Unsafe Condition/Near Miss). Setiap laporan terikat ke satu **Project/Kontrak** (Nama Project + No. Kontrak), dan setiap Project punya tipe **Onshore/Offshore**. Sudah ada form lapor + halaman riwayat/audit dengan tracking status Open -> In Progress -> Closed.
- [ ] **Incident / Accident Report** -- klasifikasi 6 tingkat + reminder wajib lapor <12 jam, investigasi & root cause.
- [ ] **Inspeksi & Observasi Lapangan** -- safety patrol, checklist APD, kondisi alat/area kerja.
- [ ] **Permit to Work / JSA / Toolbox Meeting** -- izin kerja, Job Safety Analysis, briefing harian.
- [x] **Internal Audit** -- Rencana Audit (jadwal, tim auditor, scope, standar acuan) dulu, baru Temuan per kriteria checklist (`auditKriteriaTemplateTbl`, draft klausul ISO 45001, bisa diedit). Temuan "Tidak Sesuai" punya CAPA sendiri (akar masalah, rencana tindakan, PIC, tenggat) yang ditutup lewat tahap verifikasi closure terpisah -- gak digabung ke CERMAT. Khusus Author "Internal Auditor". Tim Auditor otomatis kecentang dari orang yang punya tag itu (baca dari `karyawanTbl` DAN `paswordTbl` di Fusion4 -- lihat `sql/029_fix_get_karyawan_by_author_paswordtbl.sql`), Auditee bisa lebih dari satu. Lihat `sql/026_internal_audit_schema.sql`, `sql/027_audit_multi_auditee.sql`, `audit-report.html`, `audit-list.html`, `audit-pdf.html`.
- [x] **HSE Program** -- lampiran HSE Plan tiap project: master template generik berisi item2 kegiatan HSSE standar (TBM, HSE Meeting Mingguan/Bulanan, Inspeksi & Observasi, CERMAT, Internal Audit, PTW, Incident, MWT, Management Review -- `hseProgramMasterItemTbl`), tinggal toggle **Use/N/A** per project + isi **target per bulan (Jan-Des)** per tahun (`hseProgramTbl`). Cara isi target ada 2: manual per bulan, atau cukup isi **Target (qty) + Frequency** (Harian/Mingguan/Bulanan/Triwulan/Semester/Tahunan) lalu klik ⚡ buat auto-spread ke 12 kolom bulan, dibatasi **Tanggal Mulai/Selesai Project** (disimpan di `projectTbl`) -- hasil spread tetap bisa diedit manual sebelum disimpan. Realisasi TIDAK diinput manual -- dihitung live langsung dari tabel laporan tiap modul yang sudah jalan, biar jadi fondasi KPI yang akurat buat modul Statistik & KPI di bawah. Triwulan/Semester/Tahunan jatuh temponya di-anchor ke tanggal mulai project (bukan kalender Jan-Des) -- project mulai Agustus + Tahunan otomatis jatuh tempo Juli tahun berikutnya. Khusus **Incident/Accident** diperlakukan beda (lagging indicator, bukan aktivitas terjadwal): target dikunci 0 (Zero Incident), kolom bulan nampilin realisasi kejadian langsung (bukan target editable), %Capaian-nya = persentase bulan aktif tanpa kejadian, dan item ini sengaja dikeluarkan dari ringkasan %Capaian Keseluruhan biar gak bikin angka leading-indicator lain keliatan lebih bagus gara-gara ada insiden. Lihat `sql/031_hse_program_schema.sql`, `sql/032_hse_program_frequency_spread.sql`, `hse-program.html`. Ada juga `hse-program-monitor.html` -- layar **Actual vs Target read-only** (chart batang per item per bulan, pakai Chart.js) buat HSE Officer/Management pantau capaian tanpa perlu masuk mode edit; ringkasan & data-nya sama persis (RPC `get_hse_program`), cuma disajikan sebagai grafik, bukan tabel yang bisa diedit.
- [x] **Management Walk Through (MWT)** -- kunjungan lapangan oleh manajemen/leadership buat liat langsung kondisi HSSE, ngobrol sama pekerja, dan kasih bukti visible leadership commitment. 2 TAHAP (mirip pola Internal Audit -- Rencana lalu Pelaksanaan), dipecah jadi 2 Author tag terpisah karena orangnya beda: (1) **JADWAL/RENCANA** -- Author **"Admin MWT"** (HSE Admin/koordinator) bikin sesi dulu di `mwt-schedule.html`: Project, Area/Lokasi Rencana, Tanggal Rencana, keluar No. Dokumen (NoMWT), status awal `Terjadwal`; (2) **KUNJUNGAN** -- Author **"Management Walkthrough"** pilih sesi yang udah dijadwalkan dari `mwt-list.html`, verifikasi diri sendiri (scan QR/wajah/PIN), lalu gabung & isi catatan observasi di `mwt-report.html?id=<id>`. Ini yang beda dari desain pertama: **kalau lebih dari 1 management ikut 1 sesi, tiap orang isi entry-nya sendiri-sendiri** (nama, pendamping, jumlah pekerja diskusi, catatan, foto) -- numpuk di kolom `KunjunganList` (array JSONB) tapi tetap 1 dokumen/No. MWT yang sama, bukan laporan terpisah-pisah. Status sesi otomatis `Berlangsung` begitu ada kunjungan pertama masuk; salah satu dari mereka bisa centang **"Tandai sesi ini Selesai"** pas submit kalau dirasa udah cukup (manual, gak otomatis ada yang nutup sesi). Realisasi ke HSE Program (`get_hse_program`, KodeItem `MWT`) dihitung **per SESI** (dokumen) yang udah ada minimal 1 kunjungan -- bukan per kepala management yang ikut -- bulan diambil dari kunjungan paling awal di sesi itu. Lihat `sql/033_mwt_schema.sql` (v2, replace total desain pertama), `sql/template-grant-author-admin-mwt.sql`, `sql/template-grant-author-management-walkthrough.sql`, `mwt-schedule.html` (buat jadwal), `mwt-report.html` (gabung & isi kunjungan), `mwt-list.html` (riwayat semua sesi + link gabung ke sesi yang masih terbuka + detail tiap kunjungan).
- [ ] **Statistik & KPI HSSE** -- TRIR, LTIFR, man-hours, temuan terbuka/tertutup, % capaian HSE Program per project -- dashboard audit-ready.

## Penyimpanan file (foto & PDF)

Pola sama seperti Fusion4/SMMS: foto & PDF laporan disimpan di Google Drive
lewat jembatan Google Apps Script (bukan disimpan langsung di Supabase),
Supabase cuma nyimpen metadata + link-nya. **Tapi pakai deployment & folder
Drive SENDIRI**, terpisah dari punya Fusion4/SMMS:

- Folder Drive: https://drive.google.com/drive/folders/1nvBha62Ldm3959CAsBe7PW2VtO01IKVp (100GB)
- `driveBridge.js` -- kode client, disalin persis dari SMMS-BIMA (generic, gak perlu diubah)
- `AppsScript-Code.gs` -- kode server (Google Apps Script) yang harus di-deploy manual lewat script.google.com, lihat instruksi lengkap di dalam file itu. Setelah deploy, isi URL & token hasil deploy ke `config.js`.

## Yang masih perlu dikonfirmasi

1. **Jalankan migrasi SQL** -- `sql/001_cermat_schema.sql` belum dijalankan di Supabase, form CERMAT belum bisa dipakai sebelum ini.
2. **Data Project/Kontrak asli** -- ganti baris placeholder di `projectTbl` dengan project & kontrak beneran (termasuk tipe Onshore/Offshore masing-masing).
3. **Format HSSE dari klien** -- apakah klien migas sudah punya format laporan wajib buat CERMAT/PEKA, atau bebas ditentukan sendiri.
4. **Modul prioritas berikutnya** -- Incident Report, Inspeksi, Permit to Work, atau Dashboard KPI dulu?

## Struktur proyek (rencana)

```
HSSE-Fusion4/
├── index.html            # Status/landing page, link ke semua modul
├── config.js              # Kredensial Supabase + Drive Bridge (sudah diisi)
├── style.css              # Styling bersama, branding PT BIMA
├── driveBridge.js         # Client helper upload/baca file ke Drive (sudah siap)
├── AppsScript-Code.gs     # Kode server Drive Bridge (sudah di-deploy)
├── sql/
│   └── 001_cermat_schema.sql  # Migrasi tabel projectTbl + cermatTbl + RPC (jalankan di Supabase)
├── cermat-report.html     # Form lapor CERMAT (Positif/Negatif)
├── cermat-list.html       # Riwayat & audit CERMAT + update status tindak lanjut
├── incident-report.html   # (rencana) Form lapor insiden/kecelakaan
├── inspeksi.html          # (rencana) Form inspeksi & observasi lapangan
├── permit-to-work.html    # (rencana) Form JSA / permit to work / toolbox meeting
└── dashboard-kpi.html     # (rencana) Statistik & KPI HSSE
```

Nama file modul yang belum dibangun masih tentatif, bisa berubah begitu detail tiap modul jelas.
