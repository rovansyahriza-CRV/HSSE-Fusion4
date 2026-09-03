-- =====================================================================================
-- HSSE-Fusion4 — MIGRASI #16: MODUL PERMIT TO WORK (PTW) + JSA
-- Jalankan SETELAH 001-015, di Supabase project HSSE-Fusion4.
--
-- Konsep (disepakati di chat):
-- 1. JSA (Langkah Kerja - Bahaya - Pengendalian) jadi BAGIAN dari form Permit to Work,
--    bukan modul terpisah -- sesuai praktik lapangan pada umumnya.
-- 2. Hazard checklist beda per Jenis Pekerjaan (Hot Work, Confined Space, dst), disimpan
--    di tabel master sendiri (biar bisa diedit/ditambah lewat SQL tanpa ubah kode),
--    bentuknya checkbox "sudah terpenuhi" (konfirmasi kesiapan), BUKAN audit Sesuai/
--    Tidak Sesuai kayak modul Inspeksi.
-- 3. Alur 5 status, 3 titik verifikasi Author-gated:
--      Diajukan --(HSE Officer, Author "Review Permit to Work")--> Menunggu Approval Area Authority
--                                                                \-> Diajukan (reject)
--      Menunggu Approval Area Authority --(Area Authority, Author "Approve Permit to Work")--> Aktif
--                                                                                            \-> Diajukan (reject, BUKAN balik ke HSE)
--      Aktif --(siapa aja, ajukan closing, gak perlu Author khusus)--> Menunggu Approval Penutupan
--      Menunggu Approval Penutupan --(HSE Officer, Author "Review Permit to Work" lagi)--> Ditutup
--                                                                                        \-> Aktif (reject, kerjaan lanjut lagi)
--      Ditutup --(HSE Officer, reopen)--> Aktif langsung (gak approval ulang dari nol)
-- =====================================================================================


-- -------------------------------------------------------------------------------------
-- 1. TABEL MASTER HAZARD CHECKLIST PER JENIS PEKERJAAN (draft standar -- edit/tambah
--    lewat Table Editor Supabase kapan aja, gak perlu ubah kode).
-- -------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "ptwHazardChecklistTemplateTbl" (
    "Id" BIGSERIAL PRIMARY KEY,
    "JenisPekerjaan" TEXT NOT NULL,
    "Item" TEXT NOT NULL,
    "Urutan" INT NOT NULL DEFAULT 0,
    "Status" TEXT NOT NULL DEFAULT 'Aktif' CHECK ("Status" IN ('Aktif', 'Non-Aktif')),
    "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ptw_template_jenis ON "ptwHazardChecklistTemplateTbl" ("JenisPekerjaan", "Status");

INSERT INTO "ptwHazardChecklistTemplateTbl" ("JenisPekerjaan", "Item", "Urutan")
SELECT * FROM (VALUES
    ('Hot Work', 'APAR / fire watch siaga di lokasi', 10),
    ('Hot Work', 'Area bebas dari material/bahan mudah terbakar dalam radius aman', 11),
    ('Hot Work', 'Gas test dilakukan (kalau di area proses/confined)', 12),
    ('Hot Work', 'Terpal/fire blanket dipasang buat tahan percikan api', 13),
    ('Cold Work', 'Area kerja sudah dibarikade/ditandai', 10),
    ('Cold Work', 'Alat kerja diperiksa kondisinya', 11),
    ('Cold Work', 'APD standar dipakai', 12),
    ('Confined Space', 'Uji gas (gas test) dilakukan sebelum masuk', 10),
    ('Confined Space', 'Ventilasi/blower udara terpasang', 11),
    ('Confined Space', 'Standby man siaga di luar ruang', 12),
    ('Confined Space', 'Rencana komunikasi & rescue plan disiapkan', 13),
    ('Bekerja di Ketinggian', 'Full body harness diperiksa & terpasang', 10),
    ('Bekerja di Ketinggian', 'Scaffolding/perancah bertag inspeksi', 11),
    ('Bekerja di Ketinggian', 'Barikade/tanda peringatan area ketinggian terpasang', 12),
    ('Penggalian (Excavation)', 'Cek utilitas bawah tanah (kabel/pipa) sebelum gali', 10),
    ('Penggalian (Excavation)', 'Dinding galian aman (sloping/shoring kalau perlu)', 11),
    ('Penggalian (Excavation)', 'Barikade di sekitar area galian', 12),
    ('Kelistrikan (Electrical/LOTO)', 'Lock-Out Tag-Out (LOTO) terpasang di sumber listrik', 10),
    ('Kelistrikan (Electrical/LOTO)', 'Alat ukur tegangan (multimeter) dites sebelum & sesudah cek', 11),
    ('Kelistrikan (Electrical/LOTO)', 'APD kelistrikan (sarung tangan isolasi, dll) dipakai', 12),
    ('Pengangkatan (Lifting)', 'Rigger/operator crane bersertifikat', 10),
    ('Pengangkatan (Lifting)', 'Load chart sesuai kapasitas alat angkat', 11),
    ('Pengangkatan (Lifting)', 'Area di bawah beban steril dari orang', 12)
) AS v("JenisPekerjaan", "Item", "Urutan")
WHERE NOT EXISTS (SELECT 1 FROM "ptwHazardChecklistTemplateTbl");


-- -------------------------------------------------------------------------------------
-- 2. TABEL PERMIT TO WORK (+ JSA menyatu di kolom JsaItems)
-- -------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "ptwTbl" (
    "Id" BIGSERIAL PRIMARY KEY,
    "NoPermit" TEXT UNIQUE NOT NULL,
    "JenisPekerjaan" TEXT NOT NULL,
    "ProjectId" BIGINT NOT NULL REFERENCES "projectTbl"("Id"),
    "TanggalWaktu" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "NamaRequester" TEXT NOT NULL,
    "RequesterQrCodeId" TEXT DEFAULT '',
    "LokasiArea" TEXT NOT NULL,
    "DeskripsiPekerjaan" TEXT NOT NULL,
    "AlatYangDipakai" TEXT DEFAULT '',
    "JumlahPekerja" INT,
    "TanggalMulaiKerja" TIMESTAMPTZ,
    "TanggalSelesaiKerja" TIMESTAMPTZ,
    "JsaItems" JSONB NOT NULL DEFAULT '[]'::jsonb, -- [{langkah, bahaya, pengendalian}]
    "HazardChecklist" JSONB NOT NULL DEFAULT '[]'::jsonb, -- [{id, item, terpenuhi, keterangan}]
    "FotoList" JSONB NOT NULL DEFAULT '[]'::jsonb,
    "Status" TEXT NOT NULL DEFAULT 'Diajukan' CHECK ("Status" IN
        ('Diajukan', 'Menunggu Approval Area Authority', 'Aktif', 'Menunggu Approval Penutupan', 'Ditutup')),
    "HseReviewOleh" TEXT, "HseReviewQrCodeId" TEXT, "TanggalHseReview" TIMESTAMPTZ,
    "AreaAuthorityOleh" TEXT, "AreaAuthorityQrCodeId" TEXT, "TanggalAreaAuthority" TIMESTAMPTZ,
    "CatatanPenolakan" TEXT DEFAULT '',
    "PenutupanDiajukanOleh" TEXT, "PenutupanQrCodeId" TEXT, "TanggalPenutupanDiajukan" TIMESTAMPTZ,
    "CatatanPenutupanDiajukan" TEXT DEFAULT '',
    "DitutupOleh" TEXT, "DitutupQrCodeId" TEXT, "TanggalDitutup" TIMESTAMPTZ,
    "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ptw_project ON "ptwTbl" ("ProjectId");
CREATE INDEX IF NOT EXISTS idx_ptw_status ON "ptwTbl" ("Status");


-- -------------------------------------------------------------------------------------
-- 3. RPC: GENERATE NOMOR PERMIT
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS generate_no_ptw();
CREATE OR REPLACE FUNCTION generate_no_ptw()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_date_str TEXT := TO_CHAR(NOW() AT TIME ZONE 'Asia/Makassar', 'YYYYMMDD');
    v_rand TEXT := LPAD(FLOOR(RANDOM() * 9000 + 1000)::TEXT, 4, '0');
BEGIN
    RETURN 'BIMA/PTW/' || v_date_str || '-' || v_rand;
END;
$$;


-- -------------------------------------------------------------------------------------
-- 4. RPC: DAFTAR JENIS PEKERJAAN (buat dropdown) & TEMPLATE HAZARD CHECKLIST-NYA
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS get_jenis_pekerjaan_list();
CREATE OR REPLACE FUNCTION get_jenis_pekerjaan_list()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(DISTINCT "JenisPekerjaan" ORDER BY "JenisPekerjaan"), '[]'::jsonb)
    INTO v_result
    FROM "ptwHazardChecklistTemplateTbl"
    WHERE "Status" = 'Aktif';

    RETURN v_result;
END;
$$;

DROP FUNCTION IF EXISTS get_ptw_hazard_checklist_template(TEXT);
CREATE OR REPLACE FUNCTION get_ptw_hazard_checklist_template(p_jenis_pekerjaan TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', "Id",
        'item', "Item"
    ) ORDER BY "Urutan"), '[]'::jsonb)
    INTO v_result
    FROM "ptwHazardChecklistTemplateTbl"
    WHERE "JenisPekerjaan" = p_jenis_pekerjaan AND "Status" = 'Aktif';

    RETURN v_result;
END;
$$;


-- -------------------------------------------------------------------------------------
-- 5. RPC: SUBMIT PERMIT TO WORK BARU (Status awal: Diajukan)
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS submit_ptw(TEXT, BIGINT, TEXT, TEXT, TEXT, JSONB, JSONB, TEXT, TEXT, INT, TIMESTAMPTZ, TIMESTAMPTZ, JSONB);
CREATE OR REPLACE FUNCTION submit_ptw(
    p_jenis_pekerjaan TEXT,
    p_project_id BIGINT,
    p_nama_requester TEXT,
    p_lokasi_area TEXT,
    p_deskripsi_pekerjaan TEXT,
    p_jsa_items JSONB,
    p_hazard_checklist JSONB,
    p_requester_qrcode TEXT DEFAULT '',
    p_alat_yang_dipakai TEXT DEFAULT '',
    p_jumlah_pekerja INT DEFAULT NULL,
    p_tanggal_mulai TIMESTAMPTZ DEFAULT NULL,
    p_tanggal_selesai TIMESTAMPTZ DEFAULT NULL,
    p_foto_list JSONB DEFAULT '[]'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_no_permit TEXT := generate_no_ptw();
    v_id BIGINT;
BEGIN
    INSERT INTO "ptwTbl" (
        "NoPermit", "JenisPekerjaan", "ProjectId", "NamaRequester", "RequesterQrCodeId",
        "LokasiArea", "DeskripsiPekerjaan", "AlatYangDipakai", "JumlahPekerja",
        "TanggalMulaiKerja", "TanggalSelesaiKerja", "JsaItems", "HazardChecklist", "FotoList"
    ) VALUES (
        v_no_permit, p_jenis_pekerjaan, p_project_id, p_nama_requester, p_requester_qrcode,
        p_lokasi_area, p_deskripsi_pekerjaan, p_alat_yang_dipakai, p_jumlah_pekerja,
        p_tanggal_mulai, p_tanggal_selesai, p_jsa_items, p_hazard_checklist, p_foto_list
    )
    RETURNING "Id" INTO v_id;

    RETURN jsonb_build_object('success', true, 'id', v_id, 'noPermit', v_no_permit);
END;
$$;


-- -------------------------------------------------------------------------------------
-- 6. RPC: HSE OFFICER REVIEW (Diajukan -> Menunggu Approval Area Authority, atau reject)
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS ptw_hse_review(BIGINT, TEXT, TEXT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION ptw_hse_review(
    p_id BIGINT,
    p_decision TEXT, -- 'approve' | 'reject'
    p_catatan_penolakan TEXT DEFAULT '',
    p_nama TEXT DEFAULT NULL,
    p_qrcode TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF p_decision = 'approve' THEN
        UPDATE "ptwTbl"
        SET "Status" = 'Menunggu Approval Area Authority',
            "HseReviewOleh" = p_nama,
            "HseReviewQrCodeId" = p_qrcode,
            "TanggalHseReview" = NOW(),
            "CatatanPenolakan" = ''
        WHERE "Id" = p_id;
    ELSE
        UPDATE "ptwTbl"
        SET "Status" = 'Diajukan',
            "CatatanPenolakan" = p_catatan_penolakan
        WHERE "Id" = p_id;
    END IF;

    RETURN jsonb_build_object('success', true);
END;
$$;


-- -------------------------------------------------------------------------------------
-- 7. RPC: AREA AUTHORITY APPROVE (Menunggu Approval Area Authority -> Aktif, atau reject
--    BALIK KE DIAJUKAN -- bukan ke HSE, sesuai kesepakatan)
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS ptw_area_authority_decision(BIGINT, TEXT, TEXT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION ptw_area_authority_decision(
    p_id BIGINT,
    p_decision TEXT, -- 'approve' | 'reject'
    p_catatan_penolakan TEXT DEFAULT '',
    p_nama TEXT DEFAULT NULL,
    p_qrcode TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF p_decision = 'approve' THEN
        UPDATE "ptwTbl"
        SET "Status" = 'Aktif',
            "AreaAuthorityOleh" = p_nama,
            "AreaAuthorityQrCodeId" = p_qrcode,
            "TanggalAreaAuthority" = NOW(),
            "CatatanPenolakan" = ''
        WHERE "Id" = p_id;
    ELSE
        UPDATE "ptwTbl"
        SET "Status" = 'Diajukan',
            "CatatanPenolakan" = p_catatan_penolakan
        WHERE "Id" = p_id;
    END IF;

    RETURN jsonb_build_object('success', true);
END;
$$;


-- -------------------------------------------------------------------------------------
-- 8. RPC: AJUKAN PENUTUPAN (Aktif -> Menunggu Approval Penutupan) -- gak perlu Author
--    khusus, siapa aja yang identifikasi bisa ajukan (kayak submit awal).
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS ptw_request_closing(BIGINT, TEXT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION ptw_request_closing(
    p_id BIGINT,
    p_catatan TEXT DEFAULT '',
    p_nama TEXT DEFAULT NULL,
    p_qrcode TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE "ptwTbl"
    SET "Status" = 'Menunggu Approval Penutupan',
        "PenutupanDiajukanOleh" = p_nama,
        "PenutupanQrCodeId" = p_qrcode,
        "TanggalPenutupanDiajukan" = NOW(),
        "CatatanPenutupanDiajukan" = p_catatan
    WHERE "Id" = p_id;

    RETURN jsonb_build_object('success', true);
END;
$$;


-- -------------------------------------------------------------------------------------
-- 9. RPC: HSE OFFICER APPROVE PENUTUPAN (pakai Author "Review Permit to Work" yang sama)
--    -- Menunggu Approval Penutupan -> Ditutup, atau reject balik ke Aktif.
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS ptw_closing_decision(BIGINT, TEXT, TEXT, JSONB, TEXT, TEXT);
CREATE OR REPLACE FUNCTION ptw_closing_decision(
    p_id BIGINT,
    p_decision TEXT, -- 'approve' | 'reject'
    p_catatan_penolakan TEXT DEFAULT '',
    p_foto_list JSONB DEFAULT '[]'::jsonb,
    p_nama TEXT DEFAULT NULL,
    p_qrcode TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF p_decision = 'approve' THEN
        UPDATE "ptwTbl"
        SET "Status" = 'Ditutup',
            "DitutupOleh" = p_nama,
            "DitutupQrCodeId" = p_qrcode,
            "TanggalDitutup" = NOW(),
            "FotoList" = "FotoList" || COALESCE(p_foto_list, '[]'::jsonb),
            "CatatanPenolakan" = ''
        WHERE "Id" = p_id;
    ELSE
        UPDATE "ptwTbl"
        SET "Status" = 'Aktif',
            "CatatanPenolakan" = p_catatan_penolakan
        WHERE "Id" = p_id;
    END IF;

    RETURN jsonb_build_object('success', true);
END;
$$;


-- -------------------------------------------------------------------------------------
-- 10. RPC: REOPEN (Ditutup -> Aktif langsung, gak approval ulang dari nol)
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS ptw_reopen(BIGINT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION ptw_reopen(
    p_id BIGINT,
    p_nama TEXT,
    p_qrcode TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE "ptwTbl"
    SET "Status" = 'Aktif',
        "DitutupOleh" = NULL,
        "DitutupQrCodeId" = NULL,
        "TanggalDitutup" = NULL,
        "PenutupanDiajukanOleh" = NULL,
        "PenutupanQrCodeId" = NULL,
        "TanggalPenutupanDiajukan" = NULL,
        "CatatanPenutupanDiajukan" = '',
        "CatatanPenolakan" = ''
    WHERE "Id" = p_id;

    RETURN jsonb_build_object('success', true);
END;
$$;


-- -------------------------------------------------------------------------------------
-- 11. RPC: AMBIL DAFTAR PERMIT (riwayat) & DETAIL BY ID
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS get_ptw_list(TEXT);
CREATE OR REPLACE FUNCTION get_ptw_list(p_status TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', c."Id",
        'noPermit', c."NoPermit",
        'jenisPekerjaan', c."JenisPekerjaan",
        'tanggalWaktu', c."TanggalWaktu",
        'namaRequester', c."NamaRequester",
        'requesterQrCodeId', c."RequesterQrCodeId",
        'lokasiArea', c."LokasiArea",
        'deskripsiPekerjaan', c."DeskripsiPekerjaan",
        'alatYangDipakai', c."AlatYangDipakai",
        'jumlahPekerja', c."JumlahPekerja",
        'tanggalMulaiKerja', c."TanggalMulaiKerja",
        'tanggalSelesaiKerja', c."TanggalSelesaiKerja",
        'jsaItems', c."JsaItems",
        'hazardChecklist', c."HazardChecklist",
        'fotoList', c."FotoList",
        'status', c."Status",
        'hseReviewOleh', c."HseReviewOleh",
        'hseReviewQrCodeId', c."HseReviewQrCodeId",
        'tanggalHseReview', c."TanggalHseReview",
        'areaAuthorityOleh', c."AreaAuthorityOleh",
        'areaAuthorityQrCodeId', c."AreaAuthorityQrCodeId",
        'tanggalAreaAuthority', c."TanggalAreaAuthority",
        'catatanPenolakan', c."CatatanPenolakan",
        'penutupanDiajukanOleh', c."PenutupanDiajukanOleh",
        'penutupanQrCodeId', c."PenutupanQrCodeId",
        'tanggalPenutupanDiajukan', c."TanggalPenutupanDiajukan",
        'catatanPenutupanDiajukan', c."CatatanPenutupanDiajukan",
        'ditutupOleh', c."DitutupOleh",
        'ditutupQrCodeId', c."DitutupQrCodeId",
        'tanggalDitutup', c."TanggalDitutup",
        'namaProject', p."NamaProject",
        'noKontrak', p."NoKontrak"
    ) ORDER BY c."TanggalWaktu" DESC), '[]'::JSONB)
    INTO v_result
    FROM "ptwTbl" c
    JOIN "projectTbl" p ON p."Id" = c."ProjectId"
    WHERE p_status IS NULL OR c."Status" = p_status;

    RETURN v_result;
END;
$$;


DROP FUNCTION IF EXISTS get_ptw_by_id(BIGINT);
CREATE OR REPLACE FUNCTION get_ptw_by_id(p_id BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'id', c."Id",
        'noPermit', c."NoPermit",
        'jenisPekerjaan', c."JenisPekerjaan",
        'tanggalWaktu', c."TanggalWaktu",
        'namaRequester', c."NamaRequester",
        'requesterQrCodeId', c."RequesterQrCodeId",
        'lokasiArea', c."LokasiArea",
        'deskripsiPekerjaan', c."DeskripsiPekerjaan",
        'alatYangDipakai', c."AlatYangDipakai",
        'jumlahPekerja', c."JumlahPekerja",
        'tanggalMulaiKerja', c."TanggalMulaiKerja",
        'tanggalSelesaiKerja', c."TanggalSelesaiKerja",
        'jsaItems', c."JsaItems",
        'hazardChecklist', c."HazardChecklist",
        'fotoList', c."FotoList",
        'status', c."Status",
        'hseReviewOleh', c."HseReviewOleh",
        'hseReviewQrCodeId', c."HseReviewQrCodeId",
        'tanggalHseReview', c."TanggalHseReview",
        'areaAuthorityOleh', c."AreaAuthorityOleh",
        'areaAuthorityQrCodeId', c."AreaAuthorityQrCodeId",
        'tanggalAreaAuthority', c."TanggalAreaAuthority",
        'catatanPenolakan', c."CatatanPenolakan",
        'penutupanDiajukanOleh', c."PenutupanDiajukanOleh",
        'penutupanQrCodeId', c."PenutupanQrCodeId",
        'tanggalPenutupanDiajukan', c."TanggalPenutupanDiajukan",
        'catatanPenutupanDiajukan', c."CatatanPenutupanDiajukan",
        'ditutupOleh', c."DitutupOleh",
        'ditutupQrCodeId', c."DitutupQrCodeId",
        'tanggalDitutup', c."TanggalDitutup",
        'namaProject', p."NamaProject",
        'noKontrak', p."NoKontrak",
        'tipeKonstruksi', p."TipeKonstruksi"
    )
    INTO v_result
    FROM "ptwTbl" c
    JOIN "projectTbl" p ON p."Id" = c."ProjectId"
    WHERE c."Id" = p_id;

    RETURN v_result;
END;
$$;
