-- =====================================================================================
-- 031 -- HSE PROGRAM (fondasi KPI)
-- Jalankan SETELAH 001-030, di Supabase project HSSE-Fusion4 (BUKAN Fusion4).
--
-- Konsep (hasil diskusi bareng CRV):
--   - HSE Plan = dokumen induk per project (kebijakan, organisasi, dst) -- TIDAK
--     dipecah jadi field di app ini, cukup jadi referensi di luar sistem.
--   - HSE Program = lampiran HSE Plan yang isinya matriks target terukur per bulan.
--     Ini yang dibangun di migration ini, karena inilah "mesin" KPI-nya:
--       1. hseProgramMasterItemTbl -- template GENERIK (sama utk semua project),
--          daftar item kegiatan HSSE standar (TBM, HSE Meeting, dst).
--       2. hseProgramTbl -- instance PER PROJECT PER TAHUN: tiap item di-toggle
--          "Use" / "N/A", dan kalau "Use" diisi target per bulan (Jan-Des).
--       3. Realisasi TIDAK disimpan manual -- dihitung live dari tabel laporan
--          masing2 modul yang udah jalan (cermatTbl, tbmTbl, dst), biar akurat.
--
-- Item PTW & Incident tetap dimasukkan (reaktif/sesuai kebutuhan lapangan, bukan
-- aktivitas terjadwal) -- untuk sementara pola targetnya disamakan (angka per bulan)
-- biar strukturnya seragam dulu; makna target per item (mis. "PTW: minimal X/bulan"
-- vs "Incident: target 0") bisa disesuaikan belakangan tanpa ubah skema.
-- MWT & Management Review disiapkan sebagai baris generik juga -- realisasinya masih
-- 0 karena modulnya belum dibangun, tapi target sudah bisa mulai diisi dari sekarang.
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- 1. MASTER TEMPLATE GENERIK -- daftar item kegiatan HSSE standar (sama utk semua project)
-- -------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "hseProgramMasterItemTbl" (
    "Id" BIGSERIAL PRIMARY KEY,
    "KodeItem" TEXT UNIQUE NOT NULL,
    "NamaItem" TEXT NOT NULL,
    "SatuanTarget" TEXT NOT NULL DEFAULT 'kali',
    "Urutan" INT NOT NULL DEFAULT 0,
    "Keterangan" TEXT DEFAULT '',
    "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO "hseProgramMasterItemTbl" ("KodeItem", "NamaItem", "SatuanTarget", "Urutan", "Keterangan") VALUES
    ('TBM', 'Toolbox Meeting (TBM)', 'kali', 10, 'Realisasi dari modul TBM'),
    ('HSE_MEETING_MINGGUAN', 'HSE Meeting Mingguan', 'kali', 20, 'Realisasi dari modul HSE Meeting, tipe Mingguan'),
    ('HSE_MEETING_BULANAN', 'HSE Meeting Bulanan', 'kali', 30, 'Realisasi dari modul HSE Meeting, tipe Bulanan'),
    ('INSPEKSI_OBSERVASI', 'Inspeksi & Observasi Lapangan', 'kali', 40, 'Realisasi dari modul Inspeksi & Observasi (gabungan kedua jenis)'),
    ('CERMAT', 'CERMAT', 'kali', 50, 'Realisasi dari modul CERMAT'),
    ('INTERNAL_AUDIT', 'Internal Audit HSSE', 'kali', 60, 'Realisasi dari modul Internal Audit'),
    ('PTW', 'Permit to Work (PTW) diterbitkan', 'kali', 70, 'Realisasi dari modul PTW -- sifatnya sesuai kebutuhan lapangan'),
    ('INCIDENT', 'Pelaporan Insiden/Kecelakaan', 'kali', 80, 'Realisasi dari modul Incident/Accident -- sifatnya reaktif'),
    ('MWT', 'Management Walk Through (MWT)', 'kali', 90, 'Modul belum dibangun -- realisasi masih 0'),
    ('MANAGEMENT_REVIEW', 'Management Review', 'kali', 100, 'Modul belum dibangun -- realisasi masih 0')
ON CONFLICT ("KodeItem") DO NOTHING;

-- -------------------------------------------------------------------------------------
-- 2. INSTANCE PER PROJECT PER TAHUN -- toggle Use/N/A + target per bulan (Jan..Des)
--    "TargetBulanan" JSONB berbentuk {"1": 0, "2": 0, ..., "12": 0}
-- -------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "hseProgramTbl" (
    "Id" BIGSERIAL PRIMARY KEY,
    "ProjectId" BIGINT NOT NULL REFERENCES "projectTbl"("Id"),
    "Tahun" INT NOT NULL,
    "ItemId" BIGINT NOT NULL REFERENCES "hseProgramMasterItemTbl"("Id"),
    "StatusPakai" TEXT NOT NULL DEFAULT 'N/A' CHECK ("StatusPakai" IN ('Use', 'N/A')),
    "TargetBulanan" JSONB NOT NULL DEFAULT '{"1":0,"2":0,"3":0,"4":0,"5":0,"6":0,"7":0,"8":0,"9":0,"10":0,"11":0,"12":0}'::jsonb,
    "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "UpdatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE ("ProjectId", "Tahun", "ItemId")
);

CREATE INDEX IF NOT EXISTS idx_hse_program_project_tahun ON "hseProgramTbl" ("ProjectId", "Tahun");

-- -------------------------------------------------------------------------------------
-- 3. RPC: AMBIL MASTER ITEM (dipakai kalau butuh daftar mentahnya aja)
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_hse_program_master_items()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_result JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'itemId', "Id", 'kodeItem', "KodeItem", 'namaItem', "NamaItem",
            'satuanTarget', "SatuanTarget", 'urutan', "Urutan", 'keterangan', "Keterangan"
        ) ORDER BY "Urutan"
    ), '[]'::jsonb)
    INTO v_result
    FROM "hseProgramMasterItemTbl";
    RETURN v_result;
END;
$function$;

-- -------------------------------------------------------------------------------------
-- 4. RPC: AMBIL HSE PROGRAM 1 PROJECT + 1 TAHUN, LENGKAP DENGAN REALISASI LIVE
--    Realisasi dihitung langsung dari tabel laporan tiap modul (bukan data statis).
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
-- 5. RPC: SIMPAN/UPDATE 1 BARIS ITEM (toggle Use/N/A + target 12 bulan) UNTUK 1 PROJECT+TAHUN
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.upsert_hse_program_item(
    p_project_id BIGINT,
    p_tahun INT,
    p_item_id BIGINT,
    p_status_pakai TEXT,
    p_target_bulanan JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_id BIGINT;
BEGIN
    IF p_status_pakai NOT IN ('Use', 'N/A') THEN
        RAISE EXCEPTION 'StatusPakai harus Use atau N/A';
    END IF;

    INSERT INTO "hseProgramTbl" ("ProjectId", "Tahun", "ItemId", "StatusPakai", "TargetBulanan", "UpdatedAt")
    VALUES (
        p_project_id, p_tahun, p_item_id, p_status_pakai,
        COALESCE(p_target_bulanan, '{"1":0,"2":0,"3":0,"4":0,"5":0,"6":0,"7":0,"8":0,"9":0,"10":0,"11":0,"12":0}'::jsonb),
        NOW()
    )
    ON CONFLICT ("ProjectId", "Tahun", "ItemId")
    DO UPDATE SET
        "StatusPakai" = EXCLUDED."StatusPakai",
        "TargetBulanan" = EXCLUDED."TargetBulanan",
        "UpdatedAt" = NOW()
    RETURNING "Id" INTO v_id;

    RETURN jsonb_build_object('success', true, 'id', v_id);
END;
$function$;
