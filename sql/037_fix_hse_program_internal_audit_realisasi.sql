-- =====================================================================================
-- MIGRASI #37: FIX get_hse_program() -- realisasi Internal Audit baru dihitung kalau
-- Status minimal "Selesai Audit" (bukan langsung pas baru dibikin Rencana Audit)
-- Jalankan di Supabase project HSSE-FUSION4 (BUKAN Fusion4!) -- sama kayak migrasi
-- #031/#032/#033, ini nyentuh tabel HSSE-Fusion4 sendiri (auditTbl, hseProgramTbl).
-- READ-ONLY buat data: cuma redefine 1 RPC, gak ada perubahan/hapus data.
--
-- Kenapa perlu: kartu "Internal Audit HSSE" di HSE Program & Monitoring kemarin nunjukin
-- Realisasi: 1 (100%) padahal di Riwayat Internal Audit, filter "Ditutup" masih kosong
-- ("Belum ada Internal Audit"). Ternyata get_hse_program() (migrasi #033, branch
-- INTERNAL_AUDIT) selama ini ngitung SEMUA baris "auditTbl" apapun Status-nya -- begitu
-- HSE Admin bikin Rencana Audit baru (Status masih 'Direncanakan', belum ada pelaksanaan
-- sama sekali), langsung kehitung sebagai 1 realisasi. Padahal yang bener, realisasi
-- baru boleh kehitung kalau audit-nya MINIMAL udah selesai dilaksanakan (Status
-- 'Selesai Audit' atau 'Ditutup'), bukan pas baru direncanakan/masih berlangsung.
--
-- Perubahan: branch INTERNAL_AUDIT sekarang FILTER "Status" IN ('Selesai Audit',
-- 'Ditutup'), dan bulan realisasi diambil dari "TanggalSelesaiAudit" (fallback ke
-- "TanggalDitutup" kalau yang itu somehow kosong) -- bukan lagi dari TanggalPelaksanaan/
-- TanggalRencana. Semua branch UNION ALL lain (TBM, HSE Meeting, Inspeksi, CERMAT, PTW,
-- Incident, MWT) TIDAK diubah sama sekali, disalin persis dari sql/033.
-- =====================================================================================

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
        -- FIX #37: dulu ngitung SEMUA status (termasuk 'Direncanakan'/'Berlangsung') pakai
        -- COALESCE(TanggalPelaksanaan, TanggalRencana). Sekarang cuma audit yang MINIMAL
        -- 'Selesai Audit' yang kehitung, bulan diambil dari TanggalSelesaiAudit.
        SELECT 'INTERNAL_AUDIT', EXTRACT(MONTH FROM COALESCE("TanggalSelesaiAudit", "TanggalDitutup"))::INT, COUNT(*)
        FROM "auditTbl"
        WHERE "ProjectId" = p_project_id
          AND "Status" IN ('Selesai Audit', 'Ditutup')
          AND EXTRACT(YEAR FROM COALESCE("TanggalSelesaiAudit", "TanggalDitutup")) = p_tahun
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
