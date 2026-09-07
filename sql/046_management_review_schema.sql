-- HSSE-Fusion4 -- MIGRASI #46: MANAGEMENT REVIEW
-- Jalankan setelah 039_hse_program_kategori_manual_item.sql.
-- Semua tabel sengaja memakai RPC SECURITY DEFINER agar tetap aman untuk publishable
-- client. RLS menutup akses tabel langsung; aplikasi hanya memanggil RPC teruji.

CREATE TABLE IF NOT EXISTS "managementReviewTbl" (
    "Id" BIGSERIAL PRIMARY KEY,
    "ProjectId" BIGINT NOT NULL REFERENCES "projectTbl"("Id"),
    "TanggalReview" DATE NOT NULL,
    "DocumentNo" TEXT NOT NULL DEFAULT '',
    "Agenda" TEXT NOT NULL,
    "ReviewInputs" TEXT NOT NULL DEFAULT '',
    "Decisions" TEXT NOT NULL DEFAULT '',
    "Status" TEXT NOT NULL DEFAULT 'Draft'
        CHECK ("Status" IN ('Draft', 'Scheduled', 'In Progress', 'Completed', 'Cancelled')),
    "CreatedByNama" TEXT NOT NULL,
    "CreatedByQrCodeId" TEXT NOT NULL DEFAULT '',
    "Participants" JSONB NOT NULL DEFAULT '[]'::jsonb,
    "Attachments" JSONB NOT NULL DEFAULT '[]'::jsonb,
    "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "UpdatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS "managementReviewActionTbl" (
    "Id" BIGSERIAL PRIMARY KEY,
    "ReviewId" BIGINT NOT NULL REFERENCES "managementReviewTbl"("Id") ON DELETE CASCADE,
    "ActionItem" TEXT NOT NULL,
    "PicNama" TEXT NOT NULL,
    "PicQrCodeId" TEXT NOT NULL DEFAULT '',
    "DueDate" DATE,
    "Status" TEXT NOT NULL DEFAULT 'Open'
        CHECK ("Status" IN ('Open', 'In Progress', 'Blocked', 'Completed', 'Cancelled')),
    "Notes" TEXT NOT NULL DEFAULT '',
    "Attachments" JSONB NOT NULL DEFAULT '[]'::jsonb,
    "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "UpdatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE "managementReviewTbl"
    ADD COLUMN IF NOT EXISTS "Participants" JSONB NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE "managementReviewTbl"
    ADD COLUMN IF NOT EXISTS "DocumentNo" TEXT NOT NULL DEFAULT '';

CREATE INDEX IF NOT EXISTS idx_management_review_project_date
    ON "managementReviewTbl" ("ProjectId", "TanggalReview" DESC);
CREATE INDEX IF NOT EXISTS idx_management_review_status
    ON "managementReviewTbl" ("Status");
CREATE INDEX IF NOT EXISTS idx_management_review_action_review
    ON "managementReviewActionTbl" ("ReviewId");

ALTER TABLE "managementReviewTbl" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "managementReviewActionTbl" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS management_review_no_direct_table_access ON "managementReviewTbl";
DROP POLICY IF EXISTS management_review_action_no_direct_table_access ON "managementReviewActionTbl";
CREATE POLICY management_review_no_direct_table_access ON "managementReviewTbl"
    FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
CREATE POLICY management_review_action_no_direct_table_access ON "managementReviewActionTbl"
    FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);

CREATE OR REPLACE FUNCTION public.get_management_review_list(
    p_project_id BIGINT DEFAULT NULL,
    p_status TEXT DEFAULT NULL,
    p_search TEXT DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_result JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(row_data ORDER BY review_date DESC, id DESC), '[]'::jsonb)
    INTO v_result
    FROM (
        SELECT jsonb_build_object(
            'id', r."Id", 'projectId', r."ProjectId", 'tanggalReview', r."TanggalReview",
            'documentNo', r."DocumentNo",
            'agenda', r."Agenda", 'reviewInputs', r."ReviewInputs", 'decisions', r."Decisions",
            'status', r."Status", 'createdByNama', r."CreatedByNama",
            'createdByQrCodeId', r."CreatedByQrCodeId", 'participants', r."Participants",
            'attachments', r."Attachments",
            'createdAt', r."CreatedAt", 'updatedAt', r."UpdatedAt",
            'namaProject', p."NamaProject", 'noKontrak', p."NoKontrak",
            'actions', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                    'id', a."Id", 'reviewId', a."ReviewId", 'actionItem', a."ActionItem",
                    'picNama', a."PicNama", 'picQrCodeId', a."PicQrCodeId",
                    'dueDate', a."DueDate", 'status', a."Status", 'notes', a."Notes",
                    'attachments', a."Attachments", 'createdAt', a."CreatedAt",
                    'updatedAt', a."UpdatedAt"
                ) ORDER BY a."DueDate" NULLS LAST, a."Id")
                FROM "managementReviewActionTbl" a
                WHERE a."ReviewId" = r."Id"
            ), '[]'::jsonb)
        ) AS row_data, r."TanggalReview" AS review_date, r."Id" AS id
        FROM "managementReviewTbl" r
        JOIN "projectTbl" p ON p."Id" = r."ProjectId"
        WHERE (p_project_id IS NULL OR r."ProjectId" = p_project_id)
          AND (p_status IS NULL OR p_status = '' OR r."Status" = p_status)
          AND (
            p_search IS NULL OR p_search = '' OR
            r."Agenda" ILIKE '%' || p_search || '%' OR
            r."ReviewInputs" ILIKE '%' || p_search || '%' OR
            r."Decisions" ILIKE '%' || p_search || '%' OR
            EXISTS (
                SELECT 1 FROM "managementReviewActionTbl" ax
                WHERE ax."ReviewId" = r."Id"
                  AND (ax."ActionItem" ILIKE '%' || p_search || '%'
                       OR ax."PicNama" ILIKE '%' || p_search || '%')
            )
          )
    ) q;
    RETURN v_result;
END;
$$;

-- Ringkasan follow up lintas module untuk frame Management Review.
-- Hanya item yang belum close yang ditampilkan; sumber status tetap berasal
-- dari module asal (HSE Meeting, CERMAT, Incident, dan Internal Audit).
CREATE OR REPLACE FUNCTION public.get_management_review_open_followups(p_project_id BIGINT)
RETURNS JSONB LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
    SELECT COALESCE(jsonb_agg(item ORDER BY module, title), '[]'::jsonb)
    FROM (
        SELECT jsonb_build_object(
            'module', 'HSE Meeting',
            'title', COALESCE(t->>'item', 'Tindak lanjut HSE Meeting'),
            'detail', t->>'topikTerkait',
            'status', COALESCE(t->>'status', 'Open'),
            'pic', t->>'pic'
        ) AS item,
        COALESCE(t->>'item', 'Tindak lanjut HSE Meeting') AS title,
        'HSE Meeting' AS module
        FROM "hseMeetingTbl" h
        CROSS JOIN LATERAL jsonb_array_elements(COALESCE(h."TindakLanjutList", '[]'::jsonb)) t
        WHERE h."ProjectId" = p_project_id
          AND COALESCE(t->>'status', 'Open') <> 'Selesai'

        UNION ALL

        SELECT jsonb_build_object(
            'module', 'CERMAT',
            'title', COALESCE(c."NoLaporan", 'Laporan CERMAT'),
            'detail', COALESCE(c."Rekomendasi", c."TindakanLangsung", ''),
            'status', c."Status",
            'pic', c."PenanggungJawab"
        ), COALESCE(c."NoLaporan", 'Laporan CERMAT'), 'CERMAT'
        FROM "cermatTbl" c
        WHERE c."ProjectId" = p_project_id AND c."Status" <> 'Closed'

        UNION ALL

        SELECT jsonb_build_object(
            'module', 'Incident',
            'title', COALESCE(i."NoLaporan", 'Incident'),
            'detail', COALESCE(i."TindakanKorektif", i."TindakanLangsung", ''),
            'status', i."Status",
            'pic', i."PenanggungJawab"
        ), COALESCE(i."NoLaporan", 'Incident'), 'Incident'
        FROM "incidentTbl" i
        WHERE i."ProjectId" = p_project_id AND i."Status" <> 'Closed'

        UNION ALL

        SELECT jsonb_build_object(
            'module', 'Internal Audit',
            'title', COALESCE(a."NoAudit", 'Internal Audit'),
            'detail', a."JudulAudit",
            'status', a."Status",
            'pic', a."LeadAuditor"
        ), COALESCE(a."NoAudit", 'Internal Audit'), 'Internal Audit'
        FROM "auditTbl" a
        WHERE a."ProjectId" = p_project_id
          AND a."Status" <> 'Ditutup'
          AND a."JumlahTidakSesuai" > 0
    ) followups;
$$;

DROP FUNCTION IF EXISTS public.save_management_review(BIGINT, BIGINT, DATE, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB);
DROP FUNCTION IF EXISTS public.save_management_review(BIGINT, BIGINT, DATE, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, JSONB);
DROP FUNCTION IF EXISTS public.save_management_review(BIGINT, BIGINT, DATE, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, JSONB, TEXT);
CREATE OR REPLACE FUNCTION public.save_management_review(
    p_id BIGINT DEFAULT NULL,
    p_project_id BIGINT DEFAULT NULL,
    p_tanggal_review DATE DEFAULT NULL,
    p_agenda TEXT DEFAULT '',
    p_review_inputs TEXT DEFAULT '',
    p_decisions TEXT DEFAULT '',
    p_status TEXT DEFAULT 'Draft',
    p_created_by_nama TEXT DEFAULT '',
    p_created_by_qrcode TEXT DEFAULT '',
    p_participants JSONB DEFAULT '[]'::jsonb,
    p_attachments JSONB DEFAULT '[]'::jsonb,
    p_document_no TEXT DEFAULT ''
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id BIGINT;
BEGIN
    IF p_project_id IS NULL OR p_tanggal_review IS NULL OR NULLIF(TRIM(p_agenda), '') IS NULL
       OR NULLIF(TRIM(p_created_by_nama), '') IS NULL THEN
        RAISE EXCEPTION 'Project, tanggal, agenda, dan identitas Author wajib diisi.';
    END IF;
    IF p_status NOT IN ('Draft', 'Scheduled', 'In Progress', 'Completed', 'Cancelled') THEN
        RAISE EXCEPTION 'Status Management Review tidak valid.';
    END IF;
    IF p_id IS NULL THEN
        INSERT INTO "managementReviewTbl" (
            "ProjectId", "TanggalReview", "DocumentNo", "Agenda", "ReviewInputs", "Decisions", "Status",
            "CreatedByNama", "CreatedByQrCodeId", "Participants", "Attachments"
        ) VALUES (
            p_project_id, p_tanggal_review, COALESCE(NULLIF(TRIM(p_document_no), ''), 'MR-' || TO_CHAR(p_tanggal_review, 'YYYYMMDD') || '-P' || p_project_id), TRIM(p_agenda), COALESCE(p_review_inputs, ''),
            COALESCE(p_decisions, ''), p_status, TRIM(p_created_by_nama),
            COALESCE(p_created_by_qrcode, ''), COALESCE(p_participants, '[]'::jsonb),
            COALESCE(p_attachments, '[]'::jsonb)
        ) RETURNING "Id" INTO v_id;
    ELSE
        UPDATE "managementReviewTbl"
        SET "ProjectId" = p_project_id, "TanggalReview" = p_tanggal_review,
            "DocumentNo" = COALESCE(NULLIF(TRIM(p_document_no), ''), NULLIF("DocumentNo", ''), 'MR-' || TO_CHAR(p_tanggal_review, 'YYYYMMDD') || '-P' || p_project_id),
            "Agenda" = TRIM(p_agenda), "ReviewInputs" = COALESCE(p_review_inputs, ''),
            "Decisions" = COALESCE(p_decisions, ''), "Status" = p_status,
            "Participants" = COALESCE(p_participants, '[]'::jsonb),
            "Attachments" = COALESCE(p_attachments, '[]'::jsonb), "UpdatedAt" = NOW()
        WHERE "Id" = p_id
        RETURNING "Id" INTO v_id;
        IF v_id IS NULL THEN RAISE EXCEPTION 'Management Review tidak ditemukan.'; END IF;
    END IF;
    RETURN jsonb_build_object('success', true, 'id', v_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.save_management_review_action(
    p_id BIGINT DEFAULT NULL,
    p_review_id BIGINT DEFAULT NULL,
    p_action_item TEXT DEFAULT '',
    p_pic_nama TEXT DEFAULT '',
    p_pic_qrcode TEXT DEFAULT '',
    p_due_date DATE DEFAULT NULL,
    p_status TEXT DEFAULT 'Open',
    p_notes TEXT DEFAULT '',
    p_attachments JSONB DEFAULT '[]'::jsonb
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id BIGINT;
BEGIN
    IF p_review_id IS NULL OR NULLIF(TRIM(p_action_item), '') IS NULL
       OR NULLIF(TRIM(p_pic_nama), '') IS NULL THEN
        RAISE EXCEPTION 'Review, action item, dan PIC wajib diisi.';
    END IF;
    IF p_status NOT IN ('Open', 'In Progress', 'Blocked', 'Completed', 'Cancelled') THEN
        RAISE EXCEPTION 'Status action item tidak valid.';
    END IF;
    IF p_id IS NULL THEN
        INSERT INTO "managementReviewActionTbl" (
            "ReviewId", "ActionItem", "PicNama", "PicQrCodeId", "DueDate", "Status",
            "Notes", "Attachments"
        ) VALUES (
            p_review_id, TRIM(p_action_item), TRIM(p_pic_nama), COALESCE(p_pic_qrcode, ''),
            p_due_date, p_status, COALESCE(p_notes, ''), COALESCE(p_attachments, '[]'::jsonb)
        ) RETURNING "Id" INTO v_id;
    ELSE
        UPDATE "managementReviewActionTbl"
        SET "ActionItem" = TRIM(p_action_item), "PicNama" = TRIM(p_pic_nama),
            "PicQrCodeId" = COALESCE(p_pic_qrcode, ''), "DueDate" = p_due_date,
            "Status" = p_status, "Notes" = COALESCE(p_notes, ''),
            "Attachments" = COALESCE(p_attachments, '[]'::jsonb), "UpdatedAt" = NOW()
        WHERE "Id" = p_id AND "ReviewId" = p_review_id
        RETURNING "Id" INTO v_id;
        IF v_id IS NULL THEN RAISE EXCEPTION 'Action item tidak ditemukan.'; END IF;
    END IF;
    UPDATE "managementReviewTbl" SET "UpdatedAt" = NOW() WHERE "Id" = p_review_id;
    RETURN jsonb_build_object('success', true, 'id', v_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_management_review_action(p_id BIGINT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    DELETE FROM "managementReviewActionTbl" WHERE "Id" = p_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Action item tidak ditemukan.'; END IF;
    RETURN jsonb_build_object('success', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_management_review(p_id BIGINT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    DELETE FROM "managementReviewTbl" WHERE "Id" = p_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Management Review tidak ditemukan.'; END IF;
    RETURN jsonb_build_object('success', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_management_review_checkin_info(p_id BIGINT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'found', true, 'id', r."Id", 'status', r."Status",
        'agenda', r."Agenda", 'tanggalReview', r."TanggalReview",
        'namaProject', p."NamaProject", 'noKontrak', p."NoKontrak",
        'jumlahPeserta', jsonb_array_length(r."Participants"),
        'participants', r."Participants"
    ) INTO v_result
    FROM "managementReviewTbl" r
    JOIN "projectTbl" p ON p."Id" = r."ProjectId"
    WHERE r."Id" = p_id;
    IF v_result IS NULL THEN RETURN jsonb_build_object('found', false); END IF;
    RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.checkin_management_review(
    p_id BIGINT,
    p_nama TEXT,
    p_qrcode TEXT,
    p_jabatan TEXT DEFAULT ''
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_status TEXT;
    v_participants JSONB;
    v_existing JSONB;
    v_entry JSONB;
    v_count INT;
BEGIN
    SELECT "Status", "Participants" INTO v_status, v_participants
    FROM "managementReviewTbl" WHERE "Id" = p_id;
    IF v_status IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'Management Review tidak ditemukan.');
    END IF;
    IF v_status IN ('Completed', 'Cancelled') THEN
        RETURN jsonb_build_object('success', false, 'message', 'Review ini sudah ditutup, absensi tidak tersedia.');
    END IF;
    SELECT elem INTO v_existing
    FROM jsonb_array_elements(COALESCE(v_participants, '[]'::jsonb)) elem
    WHERE UPPER(elem->>'qrCodeId') = UPPER(TRIM(p_qrcode))
    LIMIT 1;
    IF v_existing IS NOT NULL THEN
        RETURN jsonb_build_object(
            'success', false, 'duplicate', true,
            'nama', v_existing->>'nama'
        );
    END IF;
    v_entry := jsonb_build_object(
        'nama', TRIM(p_nama), 'qrCodeId', UPPER(TRIM(p_qrcode)),
        'jabatan', COALESCE(TRIM(p_jabatan), ''), 'jamHadir', NOW()
    );
    UPDATE "managementReviewTbl"
    SET "Participants" = COALESCE("Participants", '[]'::jsonb) || jsonb_build_array(v_entry),
        "UpdatedAt" = NOW()
    WHERE "Id" = p_id
    RETURNING jsonb_array_length("Participants") INTO v_count;
    RETURN jsonb_build_object('success', true, 'jumlahPeserta', v_count);
END;
$$;

-- Management Review selesai menjadi realisasi HSE Program otomatis.
UPDATE "hseProgramMasterItemTbl"
SET "SumberRealisasi" = 'OTOMATIS',
    "Keterangan" = 'Realisasi dari modul Management Review dengan status Completed'
WHERE "KodeItem" = 'MANAGEMENT_REVIEW';

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
        SELECT 'PTW', EXTRACT(MONTH FROM "TanggalWaktu")::INT, COUNT(*)
        FROM "ptwTbl" WHERE "ProjectId" = p_project_id
          AND EXTRACT(YEAR FROM "TanggalWaktu") = p_tahun GROUP BY 2
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
