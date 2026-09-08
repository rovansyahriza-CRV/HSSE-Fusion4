-- Management Review: Closing Statement + topik ke-8 "Lain-lain".
-- Run after 050. Safe to rerun (ALTER ... ADD COLUMN IF NOT EXISTS,
-- CREATE OR REPLACE FUNCTION).
--
-- Latar belakang: karena Action Plan sekarang ditambahkan langsung per item
-- lewat popup "+ Action Plan" pada Frame Topik Pembahasan (bukan lagi lewat
-- form tunggal di bawah), form "Action Plan" yang lama digantikan dengan
-- "Closing Statement" -- kesimpulan/penutup review. Topik ke-8 "Lain-lain"
-- ditambahkan sebagai wadah manual untuk hal-hal yang belum tercakup 7 topik
-- tetap sebelumnya.

ALTER TABLE "managementReviewTbl"
    ADD COLUMN IF NOT EXISTS "ClosingStatement" TEXT NOT NULL DEFAULT '';

CREATE OR REPLACE FUNCTION public.save_management_review_closing_statement(
    p_review_id BIGINT DEFAULT NULL,
    p_closing_statement TEXT DEFAULT ''
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id BIGINT;
BEGIN
    IF p_review_id IS NULL THEN
        RAISE EXCEPTION 'Review wajib dipilih sebelum menyimpan closing statement.';
    END IF;
    UPDATE "managementReviewTbl"
    SET "ClosingStatement" = COALESCE(p_closing_statement, ''), "UpdatedAt" = NOW()
    WHERE "Id" = p_review_id
    RETURNING "Id" INTO v_id;
    IF v_id IS NULL THEN
        RAISE EXCEPTION 'Management Review tidak ditemukan.';
    END IF;
    RETURN jsonb_build_object('success', true, 'id', v_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.save_management_review_closing_statement(BIGINT, TEXT)
TO anon, authenticated;

-- Sertakan ClosingStatement di daftar review (dipakai UI untuk prefill textarea
-- Closing Statement dan ditampilkan di ringkasan Daftar Review).
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
            'documentNo', r."DocumentNo", 'agenda', r."Agenda", 'reviewInputs', r."ReviewInputs",
            'decisions', r."Decisions", 'closingStatement', r."ClosingStatement",
            'status', r."Status", 'createdByNama', r."CreatedByNama",
            'createdByQrCodeId', r."CreatedByQrCodeId", 'participants', r."Participants",
            'attachments', r."Attachments", 'createdAt', r."CreatedAt", 'updatedAt', r."UpdatedAt",
            'namaProject', p."NamaProject", 'noKontrak', p."NoKontrak",
            'actions', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                    'id', a."Id", 'reviewId', a."ReviewId", 'topic', a."Topic",
                    'actionItem', a."ActionItem", 'picNama', a."PicNama", 'picQrCodeId', a."PicQrCodeId",
                    'dueDate', a."DueDate", 'status', a."Status", 'notes', a."Notes",
                    'attachments', a."Attachments", 'createdAt', a."CreatedAt", 'updatedAt', a."UpdatedAt"
                ) ORDER BY a."DueDate" NULLS LAST, a."Id")
                FROM "managementReviewActionTbl" a WHERE a."ReviewId" = r."Id"
            ), '[]'::jsonb)
        ) AS row_data, r."TanggalReview" AS review_date, r."Id" AS id
        FROM "managementReviewTbl" r
        JOIN "projectTbl" p ON p."Id" = r."ProjectId"
        WHERE (p_project_id IS NULL OR r."ProjectId" = p_project_id)
          AND (p_status IS NULL OR p_status = '' OR r."Status" = p_status)
          AND (
            p_search IS NULL OR p_search = '' OR r."Agenda" ILIKE '%' || p_search || '%'
            OR r."ReviewInputs" ILIKE '%' || p_search || '%'
            OR r."Decisions" ILIKE '%' || p_search || '%'
            OR r."ClosingStatement" ILIKE '%' || p_search || '%'
            OR EXISTS (
                SELECT 1 FROM "managementReviewActionTbl" ax
                WHERE ax."ReviewId" = r."Id"
                  AND (ax."ActionItem" ILIKE '%' || p_search || '%' OR ax."PicNama" ILIKE '%' || p_search || '%')
            )
          )
    ) q;
    RETURN v_result;
END;
$$;
