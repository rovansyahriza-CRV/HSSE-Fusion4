-- Management Review: unique document numbers.
-- Run after 051. Safe to rerun.
--
-- Format baru: MR-YYYYMMDD-P<project_id>-R<review_id>
-- Review ID dipakai sebagai suffix immutable agar nomor selalu unik walaupun
-- beberapa review dibuat pada tanggal dan project yang sama.

WITH duplicate_numbers AS (
    SELECT "DocumentNo"
    FROM "managementReviewTbl"
    WHERE NULLIF(TRIM("DocumentNo"), '') IS NOT NULL
    GROUP BY "DocumentNo"
    HAVING COUNT(*) > 1
)
UPDATE "managementReviewTbl" r
SET "DocumentNo" = TRIM(r."DocumentNo") || '-R' || LPAD(r."Id"::TEXT, 6, '0')
FROM duplicate_numbers d
WHERE r."DocumentNo" = d."DocumentNo";

CREATE UNIQUE INDEX IF NOT EXISTS uq_management_review_document_no
    ON "managementReviewTbl" ("DocumentNo")
    WHERE NULLIF(TRIM("DocumentNo"), '') IS NOT NULL;

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
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_id BIGINT;
    v_document_no TEXT;
BEGIN
    IF p_project_id IS NULL OR p_tanggal_review IS NULL
       OR NULLIF(TRIM(p_agenda), '') IS NULL
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
            p_project_id, p_tanggal_review, '',
            TRIM(p_agenda), COALESCE(p_review_inputs, ''), COALESCE(p_decisions, ''), p_status,
            TRIM(p_created_by_nama), COALESCE(p_created_by_qrcode, ''),
            COALESCE(p_participants, '[]'::jsonb), COALESCE(p_attachments, '[]'::jsonb)
        ) RETURNING "Id" INTO v_id;

        v_document_no := CASE
            WHEN NULLIF(TRIM(p_document_no), '') IS NOT NULL
                 AND TRIM(p_document_no) !~ '^MR-[0-9]{8}-P[0-9]+$'
                THEN TRIM(p_document_no)
            ELSE 'MR-' || TO_CHAR(p_tanggal_review, 'YYYYMMDD')
                 || '-P' || p_project_id || '-R' || LPAD(v_id::TEXT, 6, '0')
        END;

        UPDATE "managementReviewTbl"
        SET "DocumentNo" = v_document_no, "UpdatedAt" = NOW()
        WHERE "Id" = v_id;
    ELSE
        UPDATE "managementReviewTbl"
        SET "ProjectId" = p_project_id,
            "TanggalReview" = p_tanggal_review,
            "DocumentNo" = CASE
                WHEN NULLIF(TRIM(p_document_no), '') IS NOT NULL
                     AND TRIM(p_document_no) !~ '^MR-[0-9]{8}-P[0-9]+$'
                    THEN TRIM(p_document_no)
                WHEN NULLIF(TRIM("DocumentNo"), '') IS NOT NULL
                    THEN "DocumentNo"
                ELSE 'MR-' || TO_CHAR(p_tanggal_review, 'YYYYMMDD')
                     || '-P' || p_project_id || '-R' || LPAD("Id"::TEXT, 6, '0')
            END,
            "Agenda" = TRIM(p_agenda),
            "ReviewInputs" = COALESCE(p_review_inputs, ''),
            "Decisions" = COALESCE(p_decisions, ''),
            "Status" = p_status,
            "Participants" = COALESCE(p_participants, '[]'::jsonb),
            "Attachments" = COALESCE(p_attachments, '[]'::jsonb),
            "UpdatedAt" = NOW()
        WHERE "Id" = p_id
        RETURNING "Id" INTO v_id;
        IF v_id IS NULL THEN
            RAISE EXCEPTION 'Management Review tidak ditemukan.';
        END IF;
    END IF;

    SELECT "DocumentNo" INTO v_document_no
    FROM "managementReviewTbl"
    WHERE "Id" = v_id;

    RETURN jsonb_build_object('success', true, 'id', v_id, 'documentNo', v_document_no);
END;
$$;

GRANT EXECUTE ON FUNCTION public.save_management_review(
    BIGINT, BIGINT, DATE, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, JSONB, TEXT
) TO anon, authenticated;
