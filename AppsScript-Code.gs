// =====================================================================================
// HSSE-Fusion4 — Google Apps Script Drive Bridge (server-side)
// Ini file yang di-DEPLOY di script.google.com, BUKAN dijalankan di browser/VS Code.
// Dipanggil oleh driveBridge.js (client) buat upload & baca foto/PDF laporan HSSE
// dari/ke folder Google Drive 100GB yang sudah kamu siapkan, terpisah dari Drive
// Bridge Fusion4/SMMS yang sudah ada.
//
// CARA DEPLOY:
// 1. Buka https://script.google.com -> klik "New project".
// 2. Hapus semua isi default "Code.gs" yang muncul, ganti dengan SELURUH isi file ini.
// 3. ROOT_FOLDER_ID di bawah sudah aku isi otomatis dari link folder Drive yang kamu
//    kasih (https://drive.google.com/drive/folders/1nvBha62Ldm3959CAsBe7PW2VtO01IKVp).
//    Kalau ternyata mau folder lain, ganti ID-nya (bagian setelah "/folders/" di URL).
// 4. Ganti SCRIPT_TOKEN di bawah jadi kata sandi rahasia versi kamu sendiri (bebas,
//    asal panjang & gak gampang ditebak -- ini yang jadi "kunci" API-nya).
// 5. Klik "Deploy" (kanan atas) -> "New deployment" -> ikon gerigi -> pilih "Web app".
//    - Description: bebas, misal "HSSE Drive Bridge v1"
//    - Execute as: Me (akun Google kamu)
//    - Who has access: Anyone
//    Klik "Deploy". Google mungkin minta izin akses Drive -- klik Allow/Izinkan.
// 6. Copy URL yang muncul (bentuknya https://script.google.com/macros/s/.../exec).
//    Itu jadi nilai DRIVE_BRIDGE_URL di config.js project HSSE-Fusion4.
// 7. SCRIPT_TOKEN yang kamu isi di langkah 4 juga jadi nilai DRIVE_BRIDGE_TOKEN di
//    config.js -- HARUS SAMA PERSIS antara di sini dan di config.js.
//
// CATATAN KEAMANAN: file yang diupload lewat sini di-set "Anyone with the link can
// view" (biar bisa ditampilkan langsung di halaman/PDF tanpa login Google). Artinya
// siapapun yang punya link filenya bisa lihat isinya -- ini pola yang sama kayak
// Fusion4/SMMS. Kalau nanti ada foto/PDF insiden yang sensitif banget, pertimbangkan
// buat gak nge-share link-nya sembarangan di luar sistem.
// =====================================================================================

const ROOT_FOLDER_ID = '1nvBha62Ldm3959CAsBe7PW2VtO01IKVp';
const SCRIPT_TOKEN = 'GANTI_DENGAN_TOKEN_RAHASIA_SENDIRI';

// Kategori -> nama subfolder di dalam ROOT_FOLDER_ID (dibuat otomatis kalau belum ada).
// Tambah baris baru di sini kalau nanti butuh kategori lain (misal per-modul HSSE).
const CATEGORY_FOLDERS = {
  photos: 'HSSE-Photos',
  reports: 'HSSE-Reports',
};

function doPost(e) {
  try {
    const body = JSON.parse(e.postData.contents);
    checkToken_(body.token);

    if (body.action === 'upload') {
      return jsonResponse_(uploadFile_(body));
    }

    throw new Error('Action tidak dikenal: ' + body.action);
  } catch (err) {
    return jsonResponse_({ error: err.message });
  }
}

function doGet(e) {
  try {
    checkToken_(e.parameter.token);

    if (e.parameter.action === 'read') {
      return jsonResponse_(readFile_(e.parameter.fileId));
    }

    throw new Error('Action tidak dikenal: ' + e.parameter.action);
  } catch (err) {
    return jsonResponse_({ error: err.message });
  }
}

function checkToken_(token) {
  if (!token || token !== SCRIPT_TOKEN) {
    throw new Error('Token tidak valid.');
  }
}

function uploadFile_(body) {
  const folder = getOrCreateCategoryFolder_(body.category);
  const bytes = Utilities.base64Decode(body.base64Data);
  const blob = Utilities.newBlob(bytes, body.mimeType, body.fileName);
  const file = folder.createFile(blob);
  file.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);

  const fileId = file.getId();
  return {
    fileId: fileId,
    viewUrl: file.getUrl(),
    directUrl: 'https://drive.google.com/uc?export=view&id=' + fileId,
  };
}

function readFile_(fileId) {
  const file = DriveApp.getFileById(fileId);
  const blob = file.getBlob();
  return {
    fileName: file.getName(),
    mimeType: blob.getContentType(),
    base64Data: Utilities.base64Encode(blob.getBytes()),
  };
}

function getOrCreateCategoryFolder_(category) {
  const rootFolder = DriveApp.getFolderById(ROOT_FOLDER_ID);
  const subfolderName = CATEGORY_FOLDERS[category] || category;

  const existing = rootFolder.getFoldersByName(subfolderName);
  if (existing.hasNext()) {
    return existing.next();
  }
  return rootFolder.createFolder(subfolderName);
}

function jsonResponse_(obj) {
  return ContentService
    .createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}
