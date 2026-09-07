-- Management Review discussion frame -- richer per-item detail + correct
-- HSE Program realisasi total. Run after 049. Safe to rerun (CREATE OR REPLACE).
--
-- Perubahan dari 049:
-- 1. hseProgram sekarang menyertakan realisasiTotal yang benar-benar dihitung
--    dari tabel laporan masing-masing modul (pola sama seperti get_hse_program
--    di sql/031), bukan 0 hardcoded.
-- 2. incidentNearMiss, cermat.openList, inspeksi.openList masing-masing
--    ditambah field detail lengkap (kronologi, tindakan, tenggat, dst) supaya
--    UI bisa menampilkan popup "Lihat Detail" per item sesuai laporan modul asal.
-- 3. partisipasiPekerja menyertakan daftar sesi MWT + catatan observasi tiap
--    kunjungan supaya bisa ditampilkan sebagai list, bukan cuma angka agregat.

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
                    WHEN 'PTW' THEN (SELECT COUNT(*) FROM "ptwTbl" WHERE "ProjectId" = p_project_id AND EXTRACT(YEAR FROM "TanggalWaktu") = v_tahun)
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
