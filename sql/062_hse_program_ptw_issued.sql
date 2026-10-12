-- =====================================================================================
-- 062 -- Realisasi PTW di HSE Program cuma hitung permit yang sudah DITERBITKAN.
-- Jalankan di project Supabase HSSE-Fusion4 (BUKAN Fusion4 SmartGate). Run after 061.
--
-- Sebelumnya: semua permit dihitung begitu diajukan (termasuk yang masih Diajukan /
-- Menunggu Approval Area Authority / ditolak balik ke Diajukan).
-- Sekarang : hanya Status 'Aktif', 'Menunggu Approval Penutupan', 'Ditutup'
--            (= sudah di-approve Area Authority; sama dengan "PTW disetujui" di Statistik).
--            Bulan realisasi pakai tanggal approve Area Authority (tanggal terbit),
--            fallback ke TanggalWaktu kalau kosong.
-- Yang diubah: get_hse_program (salinan 046) dan get_management_review_frame (salinan 054),
-- hanya baris PTW. Aman dijalankan ulang (CREATE OR REPLACE, tidak ubah struktur tabel).
-- =====================================================================================

UPDATE "hseProgramMasterItemTbl"
SET "Keterangan" = 'Realisasi dari modul PTW -- hanya permit yang sudah diterbitkan (Aktif / Menunggu Approval Penutupan / Ditutup), bulan = tanggal approve Area Authority'
WHERE "KodeItem" = 'PTW';

CREATE OR REPLACE FUNCTION public.get_hse_program(p_project_id BIGINT, p_tahun INT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_result JSONB;
BEGIN
    WITH realisasi AS (
        SELECT 'TBM' AS kode, EXTRACT(MONTH FROM "TanggalMulai")::INT AS bulan, COUNT(*) AS jumlah
        FROM "tbmTbl" WHERE "ProjectId" = p_project_id
          AND EXTRACT(YEAR FROM "TanggalMulai") = p_tahun GROUP BY 2
        UNION ALL
        SELECT CASE WHEN "TipeMeeting" = 'Mingguan' THEN 'HSE_MEETING_MINGGUAN' ELSE 'HSE_MEETING_BULANAN' END,
               EXTRACT(MONTH FROM "TanggalRapat")::INT, COUNT(*)
        FROM "hseMeetingTbl" WHERE "ProjectId" = p_project_id
          AND EXTRACT(YEAR FROM "TanggalRapat") = p_tahun GROUP BY 1, 2
        UNION ALL
        SELECT 'INSPEKSI_OBSERVASI', EXTRACT(MONTH FROM "TanggalWaktu")::INT, COUNT(*)
        FROM "inspeksiTbl" WHERE "ProjectId" = p_project_id
          AND EXTRACT(YEAR FROM "TanggalWaktu") = p_tahun GROUP BY 2
        UNION ALL
        SELECT 'CERMAT', EXTRACT(MONTH FROM "TanggalWaktu")::INT, COUNT(*)
        FROM "cermatTbl" WHERE "ProjectId" = p_project_id
          AND EXTRACT(YEAR FROM "TanggalWaktu") = p_tahun GROUP BY 2
        UNION ALL
        SELECT 'INTERNAL_AUDIT', EXTRACT(MONTH FROM COALESCE("TanggalSelesaiAudit", "TanggalDitutup"))::INT, COUNT(*)
        FROM "auditTbl" WHERE "ProjectId" = p_project_id
          AND "Status" IN ('Selesai Audit', 'Ditutup')
          AND EXTRACT(YEAR FROM COALESCE("TanggalSelesaiAudit", "TanggalDitutup")) = p_tahun GROUP BY 2
        UNION ALL
        SELECT 'PTW', EXTRACT(MONTH FROM COALESCE("TanggalAreaAuthority", "TanggalWaktu"))::INT, COUNT(*)
        FROM "ptwTbl" WHERE "ProjectId" = p_project_id
          AND "Status" IN ('Aktif', 'Menunggu Approval Penutupan', 'Ditutup')
          AND EXTRACT(YEAR FROM COALESCE("TanggalAreaAuthority", "TanggalWaktu")) = p_tahun GROUP BY 2
        UNION ALL
        SELECT 'INCIDENT', EXTRACT(MONTH FROM "TanggalWaktu")::INT, COUNT(*)
        FROM "incidentTbl" WHERE "ProjectId" = p_project_id
          AND EXTRACT(YEAR FROM "TanggalWaktu") = p_tahun GROUP BY 2
        UNION ALL
        SELECT 'MWT', EXTRACT(MONTH FROM mv.tgl_kunjungan_pertama)::INT, COUNT(*)
        FROM "mwtTbl" m
        CROSS JOIN LATERAL (
            SELECT MIN((elem->>'tanggalKunjungan')::timestamptz) AS tgl_kunjungan_pertama
            FROM jsonb_array_elements(m."KunjunganList") elem
        ) mv
        WHERE m."ProjectId" = p_project_id AND mv.tgl_kunjungan_pertama IS NOT NULL
          AND EXTRACT(YEAR FROM mv.tgl_kunjungan_pertama) = p_tahun GROUP BY 2
        UNION ALL
        SELECT 'MANAGEMENT_REVIEW' AS kode,
               EXTRACT(MONTH FROM "TanggalReview")::INT AS bulan, COUNT(*) AS jumlah
        FROM "managementReviewTbl"
        WHERE "ProjectId" = p_project_id AND "Status" = 'Completed'
          AND EXTRACT(YEAR FROM "TanggalReview") = p_tahun
        GROUP BY 2
    ), realisasi_agg AS (
        SELECT kode, jsonb_object_agg(bulan::text, jumlah) AS bulanan, SUM(jumlah) AS total
        FROM realisasi GROUP BY kode
    )
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'itemId', mi."Id", 'kodeItem', mi."KodeItem", 'namaItem', mi."NamaItem",
        'kategori', mi."Kategori", 'sumberRealisasi', mi."SumberRealisasi",
        'satuanTarget', mi."SatuanTarget", 'urutan', mi."Urutan",
        'statusPakai', COALESCE(hp."StatusPakai", 'N/A'),
        'targetQty', hp."TargetQty", 'frequency', hp."Frequency",
        'targetBulanan', COALESCE(hp."TargetBulanan",
          '{"1":0,"2":0,"3":0,"4":0,"5":0,"6":0,"7":0,"8":0,"9":0,"10":0,"11":0,"12":0}'::jsonb),
        'targetTotal', COALESCE((SELECT SUM(v.value::text::int)
          FROM jsonb_each(COALESCE(hp."TargetBulanan", '{}'::jsonb)) v), 0),
        'realisasiBulanan', CASE WHEN mi."SumberRealisasi" = 'MANUAL'
          THEN COALESCE(hp."RealisasiManualBulanan", '{}'::jsonb)
          ELSE COALESCE(ra.bulanan, '{}'::jsonb) END,
        'realisasiTotal', CASE WHEN mi."SumberRealisasi" = 'MANUAL'
          THEN COALESCE((SELECT SUM(v.value::text::int)
            FROM jsonb_each(COALESCE(hp."RealisasiManualBulanan", '{}'::jsonb)) v), 0)
          ELSE COALESCE(ra.total, 0) END
    ) ORDER BY mi."Urutan"), '[]'::jsonb)
    INTO v_result
    FROM "hseProgramMasterItemTbl" mi
    LEFT JOIN "hseProgramTbl" hp
      ON hp."ItemId" = mi."Id" AND hp."ProjectId" = p_project_id AND hp."Tahun" = p_tahun
    LEFT JOIN realisasi_agg ra ON ra.kode = mi."KodeItem";
    RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_management_review_frame(p_project_id BIGINT, p_tahun INT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_tahun INT := COALESCE(p_tahun, EXTRACT(YEAR FROM NOW())::INT);
    v_result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'tahun', v_tahun,

        'hseProgram', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'itemId', mi."Id",
                'kodeItem', mi."KodeItem",
                'namaItem', mi."NamaItem",
                'targetTotal', COALESCE((
                    SELECT SUM(v.value::text::int) FROM jsonb_each(COALESCE(hp."TargetBulanan", '{}'::jsonb)) v
                ), 0),
                'realisasiTotal', CASE mi."KodeItem"
                    WHEN 'TBM' THEN (SELECT COUNT(*) FROM "tbmTbl" WHERE "ProjectId" = p_project_id AND EXTRACT(YEAR FROM "TanggalMulai") = v_tahun)
                    WHEN 'HSE_MEETING_MINGGUAN' THEN (SELECT COUNT(*) FROM "hseMeetingTbl" WHERE "ProjectId" = p_project_id AND "TipeMeeting" = 'Mingguan' AND EXTRACT(YEAR FROM "TanggalRapat") = v_tahun)
                    WHEN 'HSE_MEETING_BULANAN' THEN (SELECT COUNT(*) FROM "hseMeetingTbl" WHERE "ProjectId" = p_project_id AND "TipeMeeting" = 'Bulanan' AND EXTRACT(YEAR FROM "TanggalRapat") = v_tahun)
                    WHEN 'INSPEKSI_OBSERVASI' THEN (SELECT COUNT(*) FROM "inspeksiTbl" WHERE "ProjectId" = p_project_id AND EXTRACT(YEAR FROM "TanggalWaktu") = v_tahun)
                    WHEN 'CERMAT' THEN (SELECT COUNT(*) FROM "cermatTbl" WHERE "ProjectId" = p_project_id AND EXTRACT(YEAR FROM "TanggalWaktu") = v_tahun)
                    WHEN 'INTERNAL_AUDIT' THEN (SELECT COUNT(*) FROM "auditTbl" WHERE "ProjectId" = p_project_id AND EXTRACT(YEAR FROM COALESCE("TanggalPelaksanaan", "TanggalRencana"::timestamptz)) = v_tahun)
                    WHEN 'PTW' THEN (SELECT COUNT(*) FROM "ptwTbl" WHERE "ProjectId" = p_project_id AND "Status" IN ('Aktif', 'Menunggu Approval Penutupan', 'Ditutup') AND EXTRACT(YEAR FROM COALESCE("TanggalAreaAuthority", "TanggalWaktu")) = v_tahun)
                    WHEN 'INCIDENT' THEN (SELECT COUNT(*) FROM "incidentTbl" WHERE "ProjectId" = p_project_id AND EXTRACT(YEAR FROM "TanggalWaktu") = v_tahun)
                    WHEN 'MWT' THEN (SELECT COUNT(*) FROM "mwtTbl" WHERE "ProjectId" = p_project_id AND EXTRACT(YEAR FROM "TanggalRencana") = v_tahun)
                    WHEN 'MANAGEMENT_REVIEW' THEN (SELECT COUNT(*) FROM "managementReviewTbl" WHERE "ProjectId" = p_project_id AND "Status" = 'Completed' AND EXTRACT(YEAR FROM "TanggalReview") = v_tahun)
                    ELSE 0
                END
            ) ORDER BY mi."Urutan")
            FROM "hseProgramMasterItemTbl" mi
            JOIN "hseProgramTbl" hp ON hp."ItemId" = mi."Id"
                AND hp."ProjectId" = p_project_id AND hp."Tahun" = v_tahun
            WHERE hp."StatusPakai" = 'Use'
        ), '[]'::jsonb),

        'incidentNearMiss', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'id', i."Id",
                'noLaporan', i."NoLaporan", 'tanggalWaktu', i."TanggalWaktu",
                'namaPelapor', i."NamaPelapor", 'klasifikasi', i."Klasifikasi",
                'lokasiArea', i."LokasiArea", 'kronologi', i."Kronologi",
                'akarMasalah', i."AkarMasalah", 'tindakanKorektif', i."TindakanKorektif",
                'tindakanLangsung', i."TindakanLangsung",
                'penanggungJawab', i."PenanggungJawab", 'tenggat', i."Tenggat",
                'status', i."Status"
            ) ORDER BY i."TanggalWaktu" DESC)
            FROM "incidentTbl" i
            WHERE i."ProjectId" = p_project_id AND i."Status" <> 'Closed'
        ), '[]'::jsonb),

        'cermat', jsonb_build_object(
            'totalOpen', (SELECT COUNT(*) FROM "cermatTbl" WHERE "ProjectId" = p_project_id AND "Status" <> 'Closed'),
            'totalClosed', (SELECT COUNT(*) FROM "cermatTbl" WHERE "ProjectId" = p_project_id AND "Status" = 'Closed'),
            'openList', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                    'id', c."Id",
                    'noLaporan', c."NoLaporan", 'tanggalWaktu', c."TanggalWaktu",
                    'namaPelapor', c."NamaPelapor", 'sifat', c."Sifat", 'jenisTemuan', c."JenisTemuan",
                    'lokasiArea', c."LokasiArea", 'deskripsi', c."Deskripsi",
                    'tindakanLangsung', c."TindakanLangsung", 'rekomendasi', c."Rekomendasi",
                    'status', c."Status", 'penanggungJawab', c."PenanggungJawab", 'tenggat', c."Tenggat"
                ) ORDER BY c."TanggalWaktu" DESC)
                FROM "cermatTbl" c WHERE c."ProjectId" = p_project_id AND c."Status" <> 'Closed'
            ), '[]'::jsonb)
        ),

        'inspeksi', jsonb_build_object(
            'totalOpen', (
                SELECT COUNT(*) FROM "inspeksiTbl"
                WHERE "ProjectId" = p_project_id AND "JumlahTidakSesuai" > 0 AND "CermatId" IS NULL
            ),
            'totalClosed', (
                SELECT COUNT(*) FROM "inspeksiTbl"
                WHERE "ProjectId" = p_project_id AND ("JumlahTidakSesuai" = 0 OR "CermatId" IS NOT NULL)
            ),
            'openList', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                    'id', ii."Id",
                    'noLaporan', ii."NoLaporan", 'jenis', ii."Jenis", 'tanggalWaktu', ii."TanggalWaktu",
                    'namaInspektor', ii."NamaInspektor", 'lokasiArea', ii."LokasiArea",
                    'catatanUmum', ii."CatatanUmum", 'jumlahSesuai', ii."JumlahSesuai",
                    'jumlahTidakSesuai', ii."JumlahTidakSesuai", 'jumlahNA', ii."JumlahNA",
                    'skorPersen', ii."SkorPersen"
                ) ORDER BY ii."TanggalWaktu" DESC)
                FROM "inspeksiTbl" ii
                WHERE ii."ProjectId" = p_project_id AND ii."JumlahTidakSesuai" > 0 AND ii."CermatId" IS NULL
            ), '[]'::jsonb)
        ),

        'partisipasiPekerja', jsonb_build_object(
            'totalSesi', (SELECT COUNT(*) FROM "mwtTbl" WHERE "ProjectId" = p_project_id),
            'totalKunjungan', COALESCE((
                SELECT SUM(jsonb_array_length(COALESCE("KunjunganList", '[]'::jsonb)))
                FROM "mwtTbl" WHERE "ProjectId" = p_project_id
            ), 0),
            'totalPekerjaDiskusi', COALESCE((
                SELECT SUM((k->>'jumlahPekerjaDiskusi')::int)
                FROM "mwtTbl" m, jsonb_array_elements(COALESCE(m."KunjunganList", '[]'::jsonb)) k
                WHERE m."ProjectId" = p_project_id
            ), 0),
            'sesiList', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                    'id', m."Id",
                    'noMWT', m."NoMWT", 'areaRencana', m."AreaRencana", 'tanggalRencana', m."TanggalRencana",
                    'status', m."Status", 'kunjunganList', COALESCE(m."KunjunganList", '[]'::jsonb)
                ) ORDER BY m."TanggalRencana" DESC)
                FROM "mwtTbl" m WHERE m."ProjectId" = p_project_id
            ), '[]'::jsonb)
        )
    ) INTO v_result;

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_management_review_frame(BIGINT, INT) TO anon, authenticated;
