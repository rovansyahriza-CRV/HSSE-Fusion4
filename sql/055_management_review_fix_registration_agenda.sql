-- Management Review: perbaiki Agenda registrasi lama yang belum menyertakan
-- suffix nomor bundle laporan (-R######). Run after 054. Safe to rerun.
--
-- Latar belakang: field "Agenda" untuk registrasi absensi diisi otomatis
-- sebagai "Registrasi <DocumentNo>" saat tombol Aktifkan Absensi diklik.
-- Sebelum perbaikan pada management-review.html, teks ini memakai nomor
-- preview (belum final) sehingga tersimpan tanpa suffix -R######, walau
-- kolom DocumentNo sendiri sudah benar. Migrasi ini menyamakan kembali teks
-- Agenda dengan DocumentNo final untuk baris yang masih memakai pola lama,
-- tanpa menyentuh Agenda yang sudah diisi manual oleh user.

UPDATE "managementReviewTbl"
SET "Agenda" = 'Registrasi ' || "DocumentNo", "UpdatedAt" = NOW()
WHERE "Agenda" ~ '^Registrasi MR-[0-9]{8}-P[0-9]+$'
  AND "DocumentNo" ~ '^MR-[0-9]{8}-P[0-9]+-R[0-9]+$'
  AND "Agenda" <> ('Registrasi ' || "DocumentNo");
