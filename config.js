// =====================================================================================
// HSSE-Fusion4 — Konfigurasi Supabase (project HSSE sendiri)
// Project Supabase TERPISAH dari Fusion4 (SmartGate absensi), sesuai keputusan awal
// biar data HSSE gak nyampur sama data absensi. Ini dipakai buat submit/baca laporan
// CERMAT, data project/kontrak, dll -- SEMUA data HSSE ada di sini.
// =====================================================================================
const SUPABASE_URL = 'https://wvzajdnxmjegblqrvgfs.supabase.co';
const SUPABASE_KEY = 'sb_publishable_BsYvIC-QEgxEfE2UP1siZg_85Rx0XYP';

// =====================================================================================
// Fusion4 SmartGate — dipakai KHUSUS buat identifikasi Pelapor (Scan QR / Scan Wajah)
// di form-form HSSE. Sengaja BACA-SAJA (cuma manggil RPC get_person_face_data &
// get_all_face_data), gak pernah nulis apa-apa ke project Fusion4. Key ini adalah
// "publishable/anon" key yang sama yang sudah dipakai publik di GitHub Pages Fusion4
// sendiri, jadi bukan tambahan resiko keamanan baru.
// =====================================================================================
const FUSION4_SUPABASE_URL = 'https://nhmpwjriextmbotmvvbu.supabase.co';
const FUSION4_SUPABASE_KEY = 'sb_publishable_XNqLw7iz873TtrLn9ag8dQ_AkL2rImz';

// =====================================================================================
// HSSE-Fusion4 — Konfigurasi Drive Bridge (dipakai oleh driveBridge.js)
// Diambil dari deployment Google Apps Script Web App kamu sendiri (lihat
// AppsScript-Code.gs -> deploy dulu -> baru isi 2 baris di bawah ini).
// Folder Drive: https://drive.google.com/drive/folders/1nvBha62Ldm3959CAsBe7PW2VtO01IKVp
// Sengaja BEDA dari DRIVE_BRIDGE_URL/TOKEN Fusion4 & SMMS (biar file HSSE gak nyampur).
// =====================================================================================
const DRIVE_BRIDGE_URL = 'https://script.google.com/macros/s/AKfycbzdGS6OVWY2dL1BwuvmS8Jc-aFH1bxbk2OauXjQq4oBGW_l1nCHcL6EsvRO620SeZPY4Q/exec';
const DRIVE_BRIDGE_TOKEN = 'Bismillah SHSSEMS - Smart HSSE Management System';
