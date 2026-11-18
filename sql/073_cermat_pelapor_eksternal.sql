-- =====================================================================================
-- 073 -- CERMAT dari pelapor EKSTERNAL (tamu, subkon, vendor) + persetujuan PIC.
-- Jalankan di project Supabase HSSE-Fusion4 (BUKAN Fusion4 SmartGate). Run after 072.
-- Butuh 065 (hsse_wajib_akses) sudah terpasang.
--
-- Alur:
--   1. Orang luar buka cermat-report.html -> "Saya bukan karyawan BIMA" -> isi nama,
--      perusahaan, no HP (opsional), foto ID (opsional), lalu form CERMAT biasa.
--      Disimpan ke TABEL ANTREAN "cermatEksternalTbl" dengan status "Menunggu verifikasi".
--      BELUM masuk cermatTbl.
--   2. Di cermat-list.html tab "Eksternal", PIC "HSSE-CRM" (atau HSSE-ALL, atau Author
--      "Verifikasi Cermat") Setujui / Tolak + catatan. Cek akses dilakukan di SERVER
--      (SmartGate, sama dengan 065), bukan cuma di browser.
--   3. Setujui -> laporan disalin ke cermatTbl (Status "Open", label Eksternal, tanggal
--      lapor asli) lalu jalan alur CERMAT biasa (verifikasi HSE -> Dept -> Review -> Closed).
--      Tolak  -> tetap di cermatEksternalTbl sebagai arsip (status "Ditolak").
--
-- Kenapa tabel antrean terpisah: SEMUA RPC Statistik & KPI, piramida (near miss),
--   HSE Program, Management Review cuma menghitung dari cermatTbl. Jadi laporan eksternal
--   yang belum disetujui / ditolak otomatis TIDAK ikut terhitung, tanpa perlu mengubah
--   RPC-RPC itu satu per satu.
--
-- Anti-spam di submit_cermat_eksternal (anonim, tanpa QR):
--   - honeypot (field tersembunyi p_website harus kosong)
--   - form minimal 8 detik diisi
--   - batas panjang semua teks, maks 3 foto temuan + 1 foto ID, URL harus https
--   - rate limit: per IP (hash) 5/jam & 15/hari, per pelapor (HP / nama+perusahaan)
--     10/hari, total 60/jam, antrean "Menunggu verifikasi" maks 300
-- Aman dijalankan ulang.
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- 1. Tabel antrean laporan eksternal
-- -------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "cermatEksternalTbl" (
    "Id" BIGSERIAL PRIMARY KEY,
    "KodeRef" TEXT UNIQUE NOT NULL,
    "ProjectId" BIGINT NOT NULL REFERENCES "projectTbl"("Id"),
    "TanggalWaktu" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "NamaPelapor" TEXT NOT NULL,
    "Perusahaan" TEXT NOT NULL,
    "NoHp" TEXT DEFAULT '',
    "FotoIdentitas" JSONB NOT NULL DEFAULT '[]'::jsonb,
    "Sifat" TEXT NOT NULL CHECK ("Sifat" IN ('Positif', 'Negatif')),
    "JenisTemuan" TEXT NOT NULL,
    "LokasiArea" TEXT NOT NULL,
    "Deskripsi" TEXT NOT NULL,
    "FotoList" JSONB NOT NULL DEFAULT '[]'::jsonb,
    "TindakanLangsung" TEXT DEFAULT '',
    "Rekomendasi" TEXT DEFAULT '',
    "StatusVerifikasi" TEXT NOT NULL DEFAULT 'Menunggu verifikasi'
        CHECK ("StatusVerifikasi" IN ('Menunggu verifikasi', 'Disetujui', 'Ditolak')),
    "VerifikatorOleh" TEXT,
    "VerifikatorQrCodeId" TEXT,
    "TanggalVerifikasi" TIMESTAMPTZ,
    "CatatanVerifikasi" TEXT DEFAULT '',
    "CermatId" BIGINT REFERENCES "cermatTbl"("Id"),
    "IpHash" TEXT DEFAULT '',
    "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_cermat_eks_status ON "cermatEksternalTbl" ("StatusVerifikasi", "CreatedAt" DESC);
CREATE INDEX IF NOT EXISTS idx_cermat_eks_ip ON "cermatEksternalTbl" ("IpHash", "CreatedAt");

-- Sama dengan 063: tidak bisa dibaca/ditulis langsung dari browser, semua lewat RPC.
ALTER TABLE "cermatEksternalTbl" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "cermatEksternalTbl_no_direct" ON "cermatEksternalTbl";
CREATE POLICY "cermatEksternalTbl_no_direct" ON "cermatEksternalTbl"
    FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);

-- -------------------------------------------------------------------------------------
-- 2. Penanda Eksternal di cermatTbl (buat laporan yang sudah disetujui)
-- -------------------------------------------------------------------------------------
ALTER TABLE "cermatTbl"
    ADD COLUMN IF NOT EXISTS "PelaporEksternal" BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS "PelaporPerusahaan" TEXT DEFAULT '',
    ADD COLUMN IF NOT EXISTS "EksternalId" BIGINT;

-- -------------------------------------------------------------------------------------
-- 3. Helper: cek akses verifikator laporan eksternal (server-side, ke SmartGate)
--    Boleh: PIC "HSSE-CRM" / "HSSE-ALL", atau Author "Verifikasi Cermat".
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.hsse_wajib_akses_cermat_eksternal(p_nama TEXT, p_qr TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    BEGIN
        PERFORM public.hsse_wajib_akses(p_nama, p_qr, 'HSSE-CRM');
        RETURN;
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE 'Akses ditolak%' THEN
            RAISE;
        END IF;
    END;
    BEGIN
        PERFORM public.hsse_wajib_akses(p_nama, p_qr, 'Verifikasi Cermat');
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE 'Akses ditolak%' THEN
            RAISE EXCEPTION 'Akses ditolak: % tidak punya PIC "HSSE-CRM" / Author "Verifikasi Cermat".',
                COALESCE(NULLIF(trim(p_nama), ''), p_qr);
        END IF;
        RAISE;
    END;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.hsse_wajib_akses_cermat_eksternal(TEXT, TEXT) FROM PUBLIC, anon, authenticated;

-- -------------------------------------------------------------------------------------
-- 4. RPC: submit laporan eksternal (anonim)
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.hsse_bersihkan_foto(p_list JSONB, p_maks INT)
RETURNS JSONB LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    v_out JSONB := '[]'::jsonb;
    v_el JSONB;
    v_url TEXT;
    v_file TEXT;
BEGIN
    IF p_list IS NULL OR jsonb_typeof(p_list) <> 'array' THEN
        RETURN '[]'::jsonb;
    END IF;
    IF jsonb_array_length(p_list) > p_maks THEN
        RAISE EXCEPTION 'Maksimal % foto.', p_maks;
    END IF;
    FOR v_el IN SELECT * FROM jsonb_array_elements(p_list) LOOP
        v_url := COALESCE(v_el->>'url', '');
        v_file := COALESCE(v_el->>'fileId', '');
        IF v_url !~ '^https://' OR length(v_url) > 500 OR length(v_file) > 200 OR v_file !~ '^[A-Za-z0-9_-]*$' THEN
            RAISE EXCEPTION 'Data foto tidak valid.';
        END IF;
        v_out := v_out || jsonb_build_array(jsonb_build_object('url', v_url, 'fileId', v_file));
    END LOOP;
    RETURN v_out;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.hsse_bersihkan_foto(JSONB, INT) FROM PUBLIC, anon, authenticated;

DROP FUNCTION IF EXISTS public.submit_cermat_eksternal(BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, JSONB, TEXT, TEXT, TEXT, INT);
CREATE OR REPLACE FUNCTION public.submit_cermat_eksternal(
    p_project_id BIGINT,
    p_nama TEXT,
    p_perusahaan TEXT,
    p_no_hp TEXT,
    p_sifat TEXT,
    p_jenis_temuan TEXT,
    p_lokasi_area TEXT,
    p_deskripsi TEXT,
    p_foto_list JSONB DEFAULT '[]'::jsonb,
    p_foto_identitas JSONB DEFAULT '[]'::jsonb,
    p_tindakan_langsung TEXT DEFAULT '',
    p_rekomendasi TEXT DEFAULT '',
    p_website TEXT DEFAULT '',          -- honeypot: harus kosong
    p_lama_isi_detik INT DEFAULT 0
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_nama TEXT := regexp_replace(trim(COALESCE(p_nama, '')), '\s+', ' ', 'g');
    v_pt   TEXT := regexp_replace(trim(COALESCE(p_perusahaan, '')), '\s+', ' ', 'g');
    v_hp   TEXT := regexp_replace(COALESCE(p_no_hp, ''), '[^0-9+]', '', 'g');
    v_lok  TEXT := trim(COALESCE(p_lokasi_area, ''));
    v_desk TEXT := trim(COALESCE(p_deskripsi, ''));
    v_tind TEXT := trim(COALESCE(p_tindakan_langsung, ''));
    v_rek  TEXT := trim(COALESCE(p_rekomendasi, ''));
    v_foto JSONB;
    v_foto_id JSONB;
    v_ip   TEXT;
    v_ip_hash TEXT := '';
    v_kode TEXT;
    v_id   BIGINT;
    v_n    INT;
BEGIN
    -- Bot: honeypot keisi / terlalu cepat
    IF COALESCE(trim(p_website), '') <> '' THEN
        RAISE EXCEPTION 'Laporan ditolak.';
    END IF;
    IF COALESCE(p_lama_isi_detik, 0) < 8 THEN
        RAISE EXCEPTION 'Form terisi terlalu cepat. Periksa lagi isian lalu kirim ulang.';
    END IF;

    -- Validasi isi
    IF length(v_nama) < 3 OR length(v_nama) > 80 THEN
        RAISE EXCEPTION 'Nama wajib diisi (3-80 karakter).';
    END IF;
    IF length(v_pt) < 2 OR length(v_pt) > 100 THEN
        RAISE EXCEPTION 'Nama perusahaan wajib diisi (2-100 karakter).';
    END IF;
    IF v_hp <> '' AND v_hp !~ '^\+?[0-9]{8,15}$' THEN
        RAISE EXCEPTION 'No HP tidak valid (8-15 angka).';
    END IF;
    IF p_sifat NOT IN ('Positif', 'Negatif')
       OR (p_sifat = 'Positif' AND p_jenis_temuan NOT IN ('Safe Act', 'Safe Condition'))
       OR (p_sifat = 'Negatif' AND p_jenis_temuan NOT IN ('Unsafe Act', 'Unsafe Condition', 'Near Miss')) THEN
        RAISE EXCEPTION 'Sifat / jenis temuan tidak valid.';
    END IF;
    IF length(v_lok) < 3 OR length(v_lok) > 200 THEN
        RAISE EXCEPTION 'Lokasi wajib diisi (3-200 karakter).';
    END IF;
    IF length(v_desk) < 10 OR length(v_desk) > 2000 THEN
        RAISE EXCEPTION 'Deskripsi wajib diisi (10-2000 karakter).';
    END IF;
    IF length(v_tind) > 1000 OR length(v_rek) > 1000 THEN
        RAISE EXCEPTION 'Tindakan langsung / rekomendasi maksimal 1000 karakter.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM "projectTbl" WHERE "Id" = p_project_id AND "Status" = 'Aktif') THEN
        RAISE EXCEPTION 'Project tidak ditemukan / tidak aktif.';
    END IF;
    v_foto := public.hsse_bersihkan_foto(p_foto_list, 3);
    v_foto_id := public.hsse_bersihkan_foto(p_foto_identitas, 1);

    -- Rate limit
    BEGIN
        v_ip := trim(split_part(COALESCE(current_setting('request.headers', true)::json->>'x-forwarded-for', ''), ',', 1));
    EXCEPTION WHEN OTHERS THEN
        v_ip := '';
    END;
    IF COALESCE(v_ip, '') <> '' THEN
        v_ip_hash := md5('hsse-cermat-eks:' || v_ip);
        SELECT COUNT(*) INTO v_n FROM "cermatEksternalTbl" WHERE "IpHash" = v_ip_hash AND "CreatedAt" > NOW() - INTERVAL '1 hour';
        IF v_n >= 5 THEN
            RAISE EXCEPTION 'Terlalu banyak laporan dari perangkat ini. Coba lagi 1 jam lagi.';
        END IF;
        SELECT COUNT(*) INTO v_n FROM "cermatEksternalTbl" WHERE "IpHash" = v_ip_hash AND "CreatedAt" > NOW() - INTERVAL '1 day';
        IF v_n >= 15 THEN
            RAISE EXCEPTION 'Batas laporan harian dari perangkat ini sudah tercapai. Coba lagi besok.';
        END IF;
    END IF;
    SELECT COUNT(*) INTO v_n FROM "cermatEksternalTbl"
    WHERE "CreatedAt" > NOW() - INTERVAL '1 day'
      AND ((v_hp <> '' AND "NoHp" = v_hp)
           OR (lower("NamaPelapor") = lower(v_nama) AND lower("Perusahaan") = lower(v_pt)));
    IF v_n >= 10 THEN
        RAISE EXCEPTION 'Batas laporan harian untuk pelapor ini sudah tercapai. Coba lagi besok.';
    END IF;
    SELECT COUNT(*) INTO v_n FROM "cermatEksternalTbl" WHERE "CreatedAt" > NOW() - INTERVAL '1 hour';
    IF v_n >= 60 THEN
        RAISE EXCEPTION 'Sistem sedang menerima banyak laporan. Coba lagi sebentar lagi.';
    END IF;
    SELECT COUNT(*) INTO v_n FROM "cermatEksternalTbl" WHERE "StatusVerifikasi" = 'Menunggu verifikasi';
    IF v_n >= 300 THEN
        RAISE EXCEPTION 'Antrean verifikasi penuh. Hubungi HSE di lokasi.';
    END IF;

    -- Simpan
    LOOP
        v_kode := 'BIMA/CERMAT-EKS/' || TO_CHAR(NOW() AT TIME ZONE 'Asia/Makassar', 'YYYYMMDD') || '-'
                  || LPAD(FLOOR(RANDOM() * 9000 + 1000)::TEXT, 4, '0');
        EXIT WHEN NOT EXISTS (SELECT 1 FROM "cermatEksternalTbl" WHERE "KodeRef" = v_kode);
    END LOOP;

    INSERT INTO "cermatEksternalTbl" (
        "KodeRef", "ProjectId", "NamaPelapor", "Perusahaan", "NoHp", "FotoIdentitas",
        "Sifat", "JenisTemuan", "LokasiArea", "Deskripsi", "FotoList",
        "TindakanLangsung", "Rekomendasi", "IpHash"
    ) VALUES (
        v_kode, p_project_id, v_nama, v_pt, v_hp, v_foto_id,
        p_sifat, p_jenis_temuan, v_lok, v_desk, v_foto,
        v_tind, v_rek, v_ip_hash
    ) RETURNING "Id" INTO v_id;

    RETURN jsonb_build_object('success', true, 'id', v_id, 'kodeRef', v_kode,
                              'status', 'Menunggu verifikasi');
END;
$$;
GRANT EXECUTE ON FUNCTION public.submit_cermat_eksternal(BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, JSONB, TEXT, TEXT, TEXT, INT) TO anon, authenticated;

-- -------------------------------------------------------------------------------------
-- 5. RPC: daftar laporan eksternal (No HP disamarkan, foto ID tidak dikirim)
--    p_status: NULL = semua, 'Menunggu verifikasi' / 'Disetujui' / 'Ditolak'
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_cermat_eksternal(TEXT);
CREATE OR REPLACE FUNCTION public.get_cermat_eksternal(p_status TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', e."Id",
        'kodeRef', e."KodeRef",
        'tanggalWaktu', e."TanggalWaktu",
        'namaPelapor', e."NamaPelapor",
        'perusahaan', e."Perusahaan",
        'noHpSamar', CASE WHEN length(COALESCE(e."NoHp", '')) >= 7
                          THEN left(e."NoHp", 4) || repeat('*', length(e."NoHp") - 7) || right(e."NoHp", 3)
                          WHEN COALESCE(e."NoHp", '') = '' THEN '' ELSE '***' END,
        'adaFotoIdentitas', jsonb_array_length(e."FotoIdentitas") > 0,
        'sifat', e."Sifat",
        'jenisTemuan', e."JenisTemuan",
        'lokasiArea', e."LokasiArea",
        'deskripsi', e."Deskripsi",
        'fotoList', e."FotoList",
        'tindakanLangsung', e."TindakanLangsung",
        'rekomendasi', e."Rekomendasi",
        'statusVerifikasi', e."StatusVerifikasi",
        'verifikatorOleh', e."VerifikatorOleh",
        'verifikatorQrCodeId', e."VerifikatorQrCodeId",
        'tanggalVerifikasi', e."TanggalVerifikasi",
        'catatanVerifikasi', e."CatatanVerifikasi",
        'cermatId', e."CermatId",
        'cermatNoLaporan', c."NoLaporan",
        'namaProject', p."NamaProject",
        'noKontrak', p."NoKontrak"
    ) ORDER BY e."TanggalWaktu" DESC), '[]'::jsonb)
    INTO v_result
    FROM "cermatEksternalTbl" e
    JOIN "projectTbl" p ON p."Id" = e."ProjectId"
    LEFT JOIN "cermatTbl" c ON c."Id" = e."CermatId"
    WHERE p_status IS NULL OR e."StatusVerifikasi" = p_status;
    RETURN v_result;
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_cermat_eksternal(TEXT) TO anon, authenticated;

-- -------------------------------------------------------------------------------------
-- 6. RPC: kontak lengkap (No HP + foto ID) -- khusus verifikator, dicek di server
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_cermat_eksternal_kontak(BIGINT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION public.get_cermat_eksternal_kontak(p_id BIGINT, p_verifikator_nama TEXT, p_verifikator_qrcode TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_result JSONB;
BEGIN
    PERFORM public.hsse_wajib_akses_cermat_eksternal(p_verifikator_nama, p_verifikator_qrcode);
    SELECT jsonb_build_object('noHp', "NoHp", 'fotoIdentitas', "FotoIdentitas")
    INTO v_result FROM "cermatEksternalTbl" WHERE "Id" = p_id;
    IF v_result IS NULL THEN
        RAISE EXCEPTION 'Laporan eksternal tidak ditemukan.';
    END IF;
    RETURN v_result;
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_cermat_eksternal_kontak(BIGINT, TEXT, TEXT) TO anon, authenticated;

-- -------------------------------------------------------------------------------------
-- 7. RPC: Setujui / Tolak -- khusus PIC CERMAT, dicek di server
--    p_keputusan: 'setujui' | 'tolak' (tolak wajib catatan)
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.cermat_eksternal_verifikasi(BIGINT, TEXT, TEXT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION public.cermat_eksternal_verifikasi(
    p_id BIGINT,
    p_keputusan TEXT,
    p_catatan TEXT,
    p_verifikator_nama TEXT,
    p_verifikator_qrcode TEXT
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_e "cermatEksternalTbl"%ROWTYPE;
    v_catatan TEXT := trim(COALESCE(p_catatan, ''));
    v_no TEXT;
    v_cermat_id BIGINT;
BEGIN
    PERFORM public.hsse_wajib_akses_cermat_eksternal(p_verifikator_nama, p_verifikator_qrcode);

    IF p_keputusan NOT IN ('setujui', 'tolak') THEN
        RAISE EXCEPTION 'Keputusan tidak valid.';
    END IF;
    IF length(v_catatan) > 1000 THEN
        RAISE EXCEPTION 'Catatan maksimal 1000 karakter.';
    END IF;
    IF p_keputusan = 'tolak' AND v_catatan = '' THEN
        RAISE EXCEPTION 'Isi alasan penolakan dulu.';
    END IF;

    SELECT * INTO v_e FROM "cermatEksternalTbl" WHERE "Id" = p_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Laporan eksternal tidak ditemukan.';
    END IF;
    IF v_e."StatusVerifikasi" <> 'Menunggu verifikasi' THEN
        RAISE EXCEPTION 'Laporan ini sudah diputuskan (%).', v_e."StatusVerifikasi";
    END IF;

    IF p_keputusan = 'setujui' THEN
        LOOP
            v_no := generate_no_cermat();
            EXIT WHEN NOT EXISTS (SELECT 1 FROM "cermatTbl" WHERE "NoLaporan" = v_no);
        END LOOP;
        INSERT INTO "cermatTbl" (
            "NoLaporan", "ProjectId", "TanggalWaktu", "NamaPelapor", "PelaporQrCodeId",
            "Sifat", "JenisTemuan", "LokasiArea", "Deskripsi", "FotoList",
            "TindakanLangsung", "Rekomendasi",
            "PelaporEksternal", "PelaporPerusahaan", "EksternalId"
        ) VALUES (
            v_no, v_e."ProjectId", v_e."TanggalWaktu", v_e."NamaPelapor", '',
            v_e."Sifat", v_e."JenisTemuan", v_e."LokasiArea", v_e."Deskripsi", v_e."FotoList",
            v_e."TindakanLangsung", v_e."Rekomendasi",
            TRUE, v_e."Perusahaan", v_e."Id"
        ) RETURNING "Id" INTO v_cermat_id;
    END IF;

    UPDATE "cermatEksternalTbl"
    SET "StatusVerifikasi" = CASE WHEN p_keputusan = 'setujui' THEN 'Disetujui' ELSE 'Ditolak' END,
        "VerifikatorOleh" = p_verifikator_nama,
        "VerifikatorQrCodeId" = upper(trim(p_verifikator_qrcode)),
        "TanggalVerifikasi" = NOW(),
        "CatatanVerifikasi" = v_catatan,
        "CermatId" = v_cermat_id
    WHERE "Id" = p_id;

    RETURN jsonb_build_object('success', true, 'cermatId', v_cermat_id, 'noLaporan', v_no);
END;
$$;
GRANT EXECUTE ON FUNCTION public.cermat_eksternal_verifikasi(BIGINT, TEXT, TEXT, TEXT, TEXT) TO anon, authenticated;

-- -------------------------------------------------------------------------------------
-- 8. get_cermat_reports & get_cermat_report_by_id: tambah field Eksternal
--    (salinan versi 014 + pelaporEksternal / pelaporPerusahaan / eksternalId)
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_cermat_reports(p_status TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', c."Id",
        'noLaporan', c."NoLaporan",
        'tanggalWaktu', c."TanggalWaktu",
        'namaPelapor', c."NamaPelapor",
        'pelaporQrCodeId', c."PelaporQrCodeId",
        'pelaporEksternal', c."PelaporEksternal",
        'pelaporPerusahaan', c."PelaporPerusahaan",
        'eksternalId', c."EksternalId",
        'sifat', c."Sifat",
        'jenisTemuan', c."JenisTemuan",
        'lokasiArea', c."LokasiArea",
        'deskripsi', c."Deskripsi",
        'fotoList', c."FotoList",
        'fotoTindakLanjutList', c."FotoTindakLanjutList",
        'tindakanLangsung', c."TindakanLangsung",
        'rekomendasi', c."Rekomendasi",
        'penanggungJawab', c."PenanggungJawab",
        'tenggat', c."Tenggat",
        'status', c."Status",
        'tanggalClosed', c."TanggalClosed",
        'assignedDivisi', c."AssignedDivisi",
        'assignedDeptNama', c."AssignedDeptNama",
        'verifikatorOleh', c."VerifikatorOleh",
        'verifikatorQrCodeId', c."VerifikatorQrCodeId",
        'tanggalVerifikasi', c."TanggalVerifikasi",
        'followupOleh', c."FollowupOleh",
        'followupQrCodeId', c."FollowupQrCodeId",
        'tanggalFollowup', c."TanggalFollowup",
        'catatanFollowup', c."CatatanFollowup",
        'catatanPenolakan', c."CatatanPenolakan",
        'ditutupOleh', c."DitutupOleh",
        'ditutupQrCodeId', c."DitutupQrCodeId",
        'sourceInspeksiId', c."SourceInspeksiId",
        'sourceInspeksiNoLaporan', i."NoLaporan",
        'namaProject', p."NamaProject",
        'noKontrak', p."NoKontrak"
    ) ORDER BY c."TanggalWaktu" DESC), '[]'::JSONB)
    INTO v_result
    FROM "cermatTbl" c
    JOIN "projectTbl" p ON p."Id" = c."ProjectId"
    LEFT JOIN "inspeksiTbl" i ON i."Id" = c."SourceInspeksiId"
    WHERE p_status IS NULL OR c."Status" = p_status;

    RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION get_cermat_report_by_id(p_id BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'id', c."Id",
        'noLaporan', c."NoLaporan",
        'tanggalWaktu', c."TanggalWaktu",
        'namaPelapor', c."NamaPelapor",
        'pelaporQrCodeId', c."PelaporQrCodeId",
        'pelaporEksternal', c."PelaporEksternal",
        'pelaporPerusahaan', c."PelaporPerusahaan",
        'eksternalId', c."EksternalId",
        'sifat', c."Sifat",
        'jenisTemuan', c."JenisTemuan",
        'lokasiArea', c."LokasiArea",
        'deskripsi', c."Deskripsi",
        'fotoList', c."FotoList",
        'fotoTindakLanjutList', c."FotoTindakLanjutList",
        'tindakanLangsung', c."TindakanLangsung",
        'rekomendasi', c."Rekomendasi",
        'penanggungJawab', c."PenanggungJawab",
        'tenggat', c."Tenggat",
        'status', c."Status",
        'tanggalClosed', c."TanggalClosed",
        'assignedDivisi', c."AssignedDivisi",
        'assignedDeptNama', c."AssignedDeptNama",
        'verifikatorOleh', c."VerifikatorOleh",
        'verifikatorQrCodeId', c."VerifikatorQrCodeId",
        'tanggalVerifikasi', c."TanggalVerifikasi",
        'followupOleh', c."FollowupOleh",
        'followupQrCodeId', c."FollowupQrCodeId",
        'tanggalFollowup', c."TanggalFollowup",
        'catatanFollowup', c."CatatanFollowup",
        'catatanPenolakan', c."CatatanPenolakan",
        'ditutupOleh', c."DitutupOleh",
        'ditutupQrCodeId', c."DitutupQrCodeId",
        'sourceInspeksiId', c."SourceInspeksiId",
        'sourceInspeksiNoLaporan', i."NoLaporan",
        'namaProject', p."NamaProject",
        'noKontrak', p."NoKontrak",
        'tipeKonstruksi', p."TipeKonstruksi"
    )
    INTO v_result
    FROM "cermatTbl" c
    JOIN "projectTbl" p ON p."Id" = c."ProjectId"
    LEFT JOIN "inspeksiTbl" i ON i."Id" = c."SourceInspeksiId"
    WHERE c."Id" = p_id;

    RETURN v_result;
END;
$$;

-- =====================================================================================
-- CEK SETELAH JALAN:
-- 1) Tabel & RPC ada (harusnya 4 baris, anon = true):
-- SELECT p.proname, has_function_privilege('anon', p.oid, 'EXECUTE') AS anon
-- FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace
--   AND p.proname IN ('submit_cermat_eksternal', 'get_cermat_eksternal',
--                     'get_cermat_eksternal_kontak', 'cermat_eksternal_verifikasi') ORDER BY 1;
-- 2) Tabel antrean tidak bisa dibaca langsung (harusnya 0 baris / error RLS dari browser).
-- 3) Antrean: SELECT "KodeRef", "StatusVerifikasi" FROM "cermatEksternalTbl" ORDER BY "Id" DESC LIMIT 10;
--
-- ROLLBACK (kalau perlu batal total, laporan eksternal yang sudah DISETUJUI tetap di cermatTbl):
-- DROP FUNCTION IF EXISTS public.submit_cermat_eksternal(BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, JSONB, TEXT, TEXT, TEXT, INT);
-- DROP FUNCTION IF EXISTS public.get_cermat_eksternal(TEXT);
-- DROP FUNCTION IF EXISTS public.get_cermat_eksternal_kontak(BIGINT, TEXT, TEXT);
-- DROP FUNCTION IF EXISTS public.cermat_eksternal_verifikasi(BIGINT, TEXT, TEXT, TEXT, TEXT);
-- =====================================================================================
