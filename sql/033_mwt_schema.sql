-- =====================================================================================
-- HSSE-Fusion4 — MIGRASI #33: MODUL MANAGEMENT WALK THROUGH (MWT) -- v2
-- Jalankan SETELAH 001-032, di Supabase project HSSE-Fusion4 (BUKAN Fusion4).
--
-- CATATAN: kalau kamu sempat menjalankan versi PERTAMA sql/033 (yang cuma 1 form submit
-- tunggal, tanpa jadwal), file ini SUDAH REPLACE total desainnya -- jalankan file ini,
-- CREATE TABLE IF NOT EXISTS-nya aman (gak ngedrop data), tapi kolom2 lama versi pertama
-- (AreaKunjungan, NamaManagement, dst di level tabel) TIDAK dipakai lagi oleh RPC baru di
-- bawah -- kalau tabelnya sudah pernah ke-create dengan skema lama & sudah ada isinya,
-- kasih tau dulu sebelum lanjut migrasi data manual.
--
-- Konsep (disepakati di chat, setelah diskusi soal >1 manajemen ikut 1 sesi):
-- 1. MWT sekarang 2 TAHAP, mirip pola Internal Audit (Rencana -> Pelaksanaan):
--    a. JADWAL/RENCANA -- dibikin oleh Author "Admin MWT" (HSE Admin/koordinator):
--       Project, Area/Lokasi Rencana, Tanggal Rencana. Keluar No. Dokumen (NoMWT).
--       Status awal 'Terjadwal'.
--    b. KUNJUNGAN -- Management (Author "Management Walkthrough") pilih sesi yang
--       udah dijadwalkan, verifikasi diri (scan QR/wajah/PIN), lalu isi catatan
--       observasi SENDIRI-SENDIRI (tiap Management yang gabung punya entry sendiri --
--       bukan 1 catatan gabungan). Entry numpuk di "KunjunganList" (array), tetap
--       1 dokumen/No. MWT yang sama. Status jadi 'Berlangsung' begitu entry pertama
--       masuk. Salah satu dari mereka bisa tandai sesi 'Selesai' saat submit kalau
--       dirasa udah cukup (manual, gak otomatis).
-- 2. Realisasi ke HSE Program dihitung per SESI (dokumen) yang udah ada minimal 1
--    kunjungan -- BUKAN per kepala Management yang ikut -- bulan diambil dari
--    kunjungan PALING AWAL di sesi itu.
-- =====================================================================================


-- -------------------------------------------------------------------------------------
-- 1. TABEL MWT (satu row per SESI/dokumen -- dari Terjadwal sampai Selesai)
--    KunjunganList JSONB shape per item:
--    { "managementNama":.., "managementQrCodeId":.., "tanggalKunjungan":.. (timestamptz),
--      "jumlahPekerjaDiskusi":.. (int), "catatanObservasi":.. (text),
--      "pendampingList": [{nama, jabatan}], "fotoList": [{url, fileId}] }
-- -------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "mwtTbl" (
    "Id" BIGSERIAL PRIMARY KEY,
    "NoMWT" TEXT UNIQUE NOT NULL,
    "ProjectId" BIGINT NOT NULL REFERENCES "projectTbl"("Id"),
    "AreaRencana" TEXT NOT NULL,
    "TanggalRencana" DATE NOT NULL,
    "CatatanRencana" TEXT DEFAULT '',
    "AdminNama" TEXT NOT NULL,
    "AdminQrCodeId" TEXT DEFAULT '',
    "Status" TEXT NOT NULL DEFAULT 'Terjadwal' CHECK ("Status" IN ('Terjadwal', 'Berlangsung', 'Selesai')),
    "KunjunganList" JSONB NOT NULL DEFAULT '[]'::jsonb,
    "TanggalDitutup" TIMESTAMPTZ,
    "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_mwt_project ON "mwtTbl" ("ProjectId");
CREATE INDEX IF NOT EXISTS idx_mwt_status ON "mwtTbl" ("Status");

-- Kalau tabel ini sebelumnya ke-create dari versi PERTAMA migrasi ini (kolom lama:
-- AreaKunjungan, NamaManagement, dst di level tabel, bukan di dalam KunjunganList),
-- baris di bawah nambahin kolom2 baru yang belum ada -- aman dijalankan berkali-kali.
ALTER TABLE "mwtTbl" ADD COLUMN IF NOT EXISTS "AreaRencana" TEXT;
ALTER TABLE "mwtTbl" ADD COLUMN IF NOT EXISTS "TanggalRencana" DATE;
ALTER TABLE "mwtTbl" ADD COLUMN IF NOT EXISTS "CatatanRencana" TEXT DEFAULT '';
ALTER TABLE "mwtTbl" ADD COLUMN IF NOT EXISTS "AdminNama" TEXT;
ALTER TABLE "mwtTbl" ADD COLUMN IF NOT EXISTS "AdminQrCodeId" TEXT DEFAULT '';
ALTER TABLE "mwtTbl" ADD COLUMN IF NOT EXISTS "Status" TEXT DEFAULT 'Terjadwal';
ALTER TABLE "mwtTbl" ADD COLUMN IF NOT EXISTS "KunjunganList" JSONB DEFAULT '[]'::jsonb;
ALTER TABLE "mwtTbl" ADD COLUMN IF NOT EXISTS "TanggalDitutup" TIMESTAMPTZ;


-- -------------------------------------------------------------------------------------
-- 2. RPC: GENERATE NOMOR MWT
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS generate_no_mwt();
CREATE OR REPLACE FUNCTION generate_no_mwt()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_date_str TEXT := TO_CHAR(NOW() AT TIME ZONE 'Asia/Makassar', 'YYYYMMDD');
    v_rand TEXT := LPAD(FLOOR(RANDOM() * 9000 + 1000)::TEXT, 4, '0');
BEGIN
    RETURN 'BIMA/MWT/' || v_date_str || '-' || v_rand;
END;
$$;


-- -------------------------------------------------------------------------------------
-- 3. RPC: BIKIN JADWAL/RENCANA MWT (Author "Admin MWT" -- dicek di client sebelum
--    manggil ini, sama pola kayak tahap Author-gated lainnya). Status awal 'Terjadwal'.
-- -------------------------------------------------------------------------------------
-- Bersihin dulu kemungkinan versi lama fungsi ini dari migrasi pertama (signature beda).
DROP FUNCTION IF EXISTS submit_mwt(BIGINT, TEXT, TEXT, JSONB, INT, TEXT, TEXT, TIMESTAMPTZ, JSONB);
DROP FUNCTION IF EXISTS create_mwt_schedule(BIGINT, TEXT, DATE, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION create_mwt_schedule(
    p_project_id BIGINT,
    p_area_rencana TEXT,
    p_tanggal_rencana DATE,
    p_admin_nama TEXT,
    p_admin_qrcode TEXT DEFAULT '',
    p_catatan_rencana TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_no_mwt TEXT := generate_no_mwt();
    v_id BIGINT;
BEGIN
    INSERT INTO "mwtTbl" (
        "NoMWT", "ProjectId", "AreaRencana", "TanggalRencana",
        "AdminNama", "AdminQrCodeId", "CatatanRencana"
    ) VALUES (
        v_no_mwt, p_project_id, p_area_rencana, p_tanggal_rencana,
        p_admin_nama, p_admin_qrcode, p_catatan_rencana
    )
    RETURNING "Id" INTO v_id;

    RETURN jsonb_build_object('success', true, 'id', v_id, 'noMWT', v_no_mwt);
END;
$$;


-- -------------------------------------------------------------------------------------
-- 4. RPC: GABUNG SESI & ISI KUNJUNGAN SENDIRI (Author "Management Walkthrough" --
--    dicek di client). Nambah 1 entry ke KunjunganList, sesi jadi 'Berlangsung' kalau
--    masih 'Terjadwal'. p_tandai_selesai=true -> sesi ditutup jadi 'Selesai' (manual,
--    dari salah satu Management yang ngerasa udah cukup -- bukan otomatis).
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS submit_mwt_kunjungan(BIGINT, TEXT, TEXT, INT, TEXT, JSONB, JSONB, BOOLEAN);
CREATE OR REPLACE FUNCTION submit_mwt_kunjungan(
    p_id BIGINT,
    p_management_nama TEXT,
    p_management_qrcode TEXT,
    p_jumlah_pekerja_diskusi INT,
    p_catatan_observasi TEXT,
    p_pendamping_list JSONB DEFAULT '[]'::jsonb,
    p_foto_list JSONB DEFAULT '[]'::jsonb,
    p_tandai_selesai BOOLEAN DEFAULT false
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_status TEXT;
    v_new_entry JSONB;
    v_jumlah_entry INT;
BEGIN
    SELECT "Status" INTO v_status FROM "mwtTbl" WHERE "Id" = p_id;
    IF v_status IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'Jadwal MWT tidak ditemukan.');
    END IF;
    IF v_status = 'Selesai' THEN
        RETURN jsonb_build_object('success', false, 'message', 'Sesi MWT ini sudah Selesai, tidak bisa ditambah kunjungan lagi.');
    END IF;

    v_new_entry := jsonb_build_object(
        'managementNama', p_management_nama,
        'managementQrCodeId', p_management_qrcode,
        'tanggalKunjungan', to_jsonb(NOW()),
        'jumlahPekerjaDiskusi', COALESCE(p_jumlah_pekerja_diskusi, 0),
        'catatanObservasi', COALESCE(p_catatan_observasi, ''),
        'pendampingList', COALESCE(p_pendamping_list, '[]'::jsonb),
        'fotoList', COALESCE(p_foto_list, '[]'::jsonb)
    );

    UPDATE "mwtTbl"
    SET "KunjunganList" = "KunjunganList" || jsonb_build_array(v_new_entry),
        "Status" = CASE WHEN p_tandai_selesai THEN 'Selesai' ELSE 'Berlangsung' END,
        "TanggalDitutup" = CASE WHEN p_tandai_selesai THEN NOW() ELSE "TanggalDitutup" END
    WHERE "Id" = p_id
    RETURNING jsonb_array_length("KunjunganList") INTO v_jumlah_entry;

    RETURN jsonb_build_object('success', true, 'jumlahKunjungan', v_jumlah_entry, 'status', CASE WHEN p_tandai_selesai THEN 'Selesai' ELSE 'Berlangsung' END);
END;
$$;


-- -------------------------------------------------------------------------------------
-- 5. RPC: AMBIL DAFTAR (RIWAYAT) & DETAIL BY ID
-- -------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS get_mwt_list(BIGINT);
DROP FUNCTION IF EXISTS get_mwt_list(TEXT, BIGINT);
CREATE OR REPLACE FUNCTION get_mwt_list(p_status TEXT DEFAULT NULL, p_project_id BIGINT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', c."Id",
        'noMWT', c."NoMWT",
        'areaRencana', c."AreaRencana",
        'tanggalRencana', c."TanggalRencana",
        'catatanRencana', c."CatatanRencana",
        'adminNama', c."AdminNama",
        'adminQrCodeId', c."AdminQrCodeId",
        'status', c."Status",
        'kunjunganList', c."KunjunganList",
        'tanggalDitutup', c."TanggalDitutup",
        'createdAt', c."CreatedAt",
        'namaProject', p."NamaProject",
        'noKontrak', p."NoKontrak"
    ) ORDER BY c."CreatedAt" DESC), '[]'::JSONB)
    INTO v_result
    FROM "mwtTbl" c
    JOIN "projectTbl" p ON p."Id" = c."ProjectId"
    WHERE (p_status IS NULL OR c."Status" = p_status)
      AND (p_project_id IS NULL OR c."ProjectId" = p_project_id);

    RETURN v_result;
END;
$$;


DROP FUNCTION IF EXISTS get_mwt_by_id(BIGINT);
CREATE OR REPLACE FUNCTION get_mwt_by_id(p_id BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'id', c."Id",
        'noMWT', c."NoMWT",
        'projectId', c."ProjectId",
        'areaRencana', c."AreaRencana",
        'tanggalRencana', c."TanggalRencana",
        'catatanRencana', c."CatatanRencana",
        'adminNama', c."AdminNama",
        'adminQrCodeId', c."AdminQrCodeId",
        'status', c."Status",
        'kunjunganList', c."KunjunganList",
        'tanggalDitutup', c."TanggalDitutup",
        'createdAt', c."CreatedAt",
        'namaProject', p."NamaProject",
        'noKontrak', p."NoKontrak",
        'tipeKonstruksi', p."TipeKonstruksi"
    )
    INTO v_result
    FROM "mwtTbl" c
    JOIN "projectTbl" p ON p."Id" = c."ProjectId"
    WHERE c."Id" = p_id;

    RETURN v_result;
END;
$$;


-- -------------------------------------------------------------------------------------
-- 6. get_hse_program() -- realisasi MWT dihitung PER SESI (bukan per kepala Management)
--    -- 1 sesi yang udah ada >=1 kunjungan = 1 "kali", bulan diambil dari kunjungan
--    PALING AWAL di sesi itu. Body fungsi disalin dari sql/032, cuma nambah 1 UNION ALL.
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_hse_program(p_project_id BIGINT, p_tahun INT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_result JSONB;
BEGIN
    WITH realisasi AS (
        SELECT 'TBM' AS kode, EXTRACT(MONTH FROM "TanggalMulai")::INT AS bulan, COUNT(*) AS jumlah
        FROM "tbmTbl"
        WHERE "ProjectId" = p_project_id AND EXTRACT(YEAR FROM "TanggalMulai") = p_tahun
        GROUP BY 2

        UNION ALL
        SELECT 'HSE_MEETING_MINGGUAN', EXTRACT(MONTH FROM "TanggalRapat")::INT, COUNT(*)
        FROM "hseMeetingTbl"
        WHERE "ProjectId" = p_project_id AND "TipeMeeting" = 'Mingguan'
          AND EXTRACT(YEAR FROM "TanggalRapat") = p_tahun
        GROUP BY 2

        UNION ALL
        SELECT 'HSE_MEETING_BULANAN', EXTRACT(MONTH FROM "TanggalRapat")::INT, COUNT(*)
        FROM "hseMeetingTbl"
        WHERE "ProjectId" = p_project_id AND "TipeMeeting" = 'Bulanan'
          AND EXTRACT(YEAR FROM "TanggalRapat") = p_tahun
        GROUP BY 2

        UNION ALL
        SELECT 'INSPEKSI_OBSERVASI', EXTRACT(MONTH FROM "TanggalWaktu")::INT, COUNT(*)
        FROM "inspeksiTbl"
        WHERE "ProjectId" = p_project_id AND EXTRACT(YEAR FROM "TanggalWaktu") = p_tahun
        GROUP BY 2

        UNION ALL
        SELECT 'CERMAT', EXTRACT(MONTH FROM "TanggalWaktu")::INT, COUNT(*)
        FROM "cermatTbl"
        WHERE "ProjectId" = p_project_id AND EXTRACT(YEAR FROM "TanggalWaktu") = p_tahun
        GROUP BY 2

        UNION ALL
        SELECT 'INTERNAL_AUDIT', EXTRACT(MONTH FROM COALESCE("TanggalPelaksanaan", "TanggalRencana"::timestamptz))::INT, COUNT(*)
        FROM "auditTbl"
        WHERE "ProjectId" = p_project_id
          AND EXTRACT(YEAR FROM COALESCE("TanggalPelaksanaan", "TanggalRencana"::timestamptz)) = p_tahun
        GROUP BY 2

        UNION ALL
        SELECT 'PTW', EXTRACT(MONTH FROM "TanggalWaktu")::INT, COUNT(*)
        FROM "ptwTbl"
        WHERE "ProjectId" = p_project_id AND EXTRACT(YEAR FROM "TanggalWaktu") = p_tahun
        GROUP BY 2

        UNION ALL
        SELECT 'INCIDENT', EXTRACT(MONTH FROM "TanggalWaktu")::INT, COUNT(*)
        FROM "incidentTbl"
        WHERE "ProjectId" = p_project_id AND EXTRACT(YEAR FROM "TanggalWaktu") = p_tahun
        GROUP BY 2

        UNION ALL
        SELECT 'MWT', EXTRACT(MONTH FROM mv.tgl_kunjungan_pertama)::INT, COUNT(*)
        FROM "mwtTbl" m
        CROSS JOIN LATERAL (
            SELECT MIN((elem->>'tanggalKunjungan')::timestamptz) AS tgl_kunjungan_pertama
            FROM jsonb_array_elements(m."KunjunganList") elem
        ) mv
        WHERE m."ProjectId" = p_project_id
          AND mv.tgl_kunjungan_pertama IS NOT NULL
          AND EXTRACT(YEAR FROM mv.tgl_kunjungan_pertama) = p_tahun
        GROUP BY 2
    ),
    realisasi_agg AS (
        SELECT kode, jsonb_object_agg(bulan::text, jumlah) AS realisasi_bulanan, SUM(jumlah) AS realisasi_total
        FROM realisasi
        GROUP BY kode
    )
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'itemId', mi."Id",
            'kodeItem', mi."KodeItem",
            'namaItem', mi."NamaItem",
            'satuanTarget', mi."SatuanTarget",
            'urutan', mi."Urutan",
            'statusPakai', COALESCE(hp."StatusPakai", 'N/A'),
            'targetQty', hp."TargetQty",
            'frequency', hp."Frequency",
            'targetBulanan', COALESCE(hp."TargetBulanan", '{"1":0,"2":0,"3":0,"4":0,"5":0,"6":0,"7":0,"8":0,"9":0,"10":0,"11":0,"12":0}'::jsonb),
            'targetTotal', COALESCE((
                SELECT SUM(v.value::text::int)
                FROM jsonb_each(COALESCE(hp."TargetBulanan", '{}'::jsonb)) v
            ), 0),
            'realisasiBulanan', COALESCE(ra.realisasi_bulanan, '{}'::jsonb),
            'realisasiTotal', COALESCE(ra.realisasi_total, 0)
        ) ORDER BY mi."Urutan"
    ), '[]'::jsonb)
    INTO v_result
    FROM "hseProgramMasterItemTbl" mi
    LEFT JOIN "hseProgramTbl" hp
        ON hp."ItemId" = mi."Id" AND hp."ProjectId" = p_project_id AND hp."Tahun" = p_tahun
    LEFT JOIN realisasi_agg ra ON ra.kode = mi."KodeItem";

    RETURN v_result;
END;
$function$;


-- -------------------------------------------------------------------------------------
-- 7. Update deskripsi item master MWT (baris sudah ada dari sql/031, KodeItem='MWT').
-- -------------------------------------------------------------------------------------
UPDATE "hseProgramMasterItemTbl" SET "Keterangan" = 'Realisasi dari modul MWT -- 1 sesi/dokumen = 1 kali, dihitung dari kunjungan pertama di sesi itu' WHERE "KodeItem" = 'MWT';
