import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Membuat dokumen HTML rapi untuk Kebijakan Privasi atau Syarat & Ketentuan,
/// lalu membagikannya. Pengguna dapat membuka file di browser dan pilih
/// "Cetak" → "Simpan sebagai PDF" untuk mendapatkan PDF.
class PrivacyTermsExportService {
  static const String _htmlHeader = '''
<!DOCTYPE html>
<html lang="id">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>%TITLE%</title>
  <style>
    body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; line-height: 1.6; color: #333; max-width: 700px; margin: 0 auto; padding: 24px; }
    h1 { font-size: 22px; color: #111; border-bottom: 2px solid #2563eb; padding-bottom: 8px; margin-top: 28px; }
    h2 { font-size: 16px; font-weight: 600; color: #111; margin-top: 20px; margin-bottom: 8px; }
    p { margin: 0 0 12px 0; text-align: justify; }
    .intro { margin-bottom: 20px; }
    .section { margin-bottom: 20px; }
    @media print { body { padding: 16px; } }
  </style>
</head>
<body>
''';

  static const String _htmlFooter = '''
</body>
</html>
''';

  static String get privacyHtml => _htmlHeader.replaceFirst('%TITLE%', 'Kebijakan Privasi - Traka') + '''
  <h1>Kebijakan Privasi</h1>
  <p class="intro">Traka adalah aplikasi yang menghubungkan penumpang dengan driver travel di wilayah Kalimantan dan wilayah di luar Kalimantan. Kami tidak menyimpan, memegang, atau mengontrol dana pengguna; seluruh transaksi keuangan terjadi langsung antar pengguna.</p>

  <div class="section">
    <h2>1. Data yang Kami Kumpulkan</h2>
    <p>Untuk keperluan layanan dan keamanan, kami dapat memproses: data akun (nama, email, nomor telepon jika Anda tambahkan), foto profil dan data verifikasi wajah (untuk keamanan akun), identifikasi perangkat (device ID), dan lokasi saat menggunakan layanan. Data verifikasi wajah dan data sensitif lainnya tidak disimpan dalam bentuk mentah yang dapat disalahgunakan; kami menggunakan layanan dan praktik yang aman sesuai kebutuhan teknis layanan.</p>
    <h3 style="font-size: 14px; font-weight: 600; margin-top: 12px;">Pengambilan Data KTP dan STNK</h3>
    <p>Untuk verifikasi identitas (KTP) dan data kendaraan (STNK), Aplikasi meminta pengambilan foto dokumen. Foto tersebut HANYA digunakan untuk ekstraksi data (misalnya nama, NIK, nomor plat) melalui teknologi pengenalan teks (OCR) dan TIDAK DISIMPAN di server kami. Setelah data diekstraksi, foto dihapus dari perangkat dan tidak dikirim atau disimpan secara permanen. Hanya data hasil ekstraksi (teks) yang disimpan untuk keperluan layanan.</p>
  </div>

  <div class="section">
    <h2>2. Penggunaan Data</h2>
    <p>Data digunakan hanya untuk: menyediakan dan meningkatkan layanan Traka, verifikasi identitas dan keamanan akun, memenuhi kewajiban hukum, serta komunikasi terkait layanan. Kami tidak menjual data pribadi Anda kepada pihak ketiga untuk tujuan pemasaran.</p>
  </div>

  <div class="section">
    <h2>3. Tidak Ada Penyimpanan Dana</h2>
    <p>Aplikasi Traka tidak memegang uang pengguna. Kami hanya mempertemukan penumpang dan driver; pembayaran dan kesepakatan harga merupakan transaksi langsung antara Anda dan pihak lain, di luar kendali dan penyimpanan kami.</p>
  </div>

  <div class="section">
    <h2>4. Keamanan Data</h2>
    <p>Kami menerapkan langkah teknis dan organisasi yang wajar untuk melindungi data pribadi dari akses, pengubahan, atau pengungkapan yang tidak sah, sejalan dengan ketentuan peraturan perundang-undangan Indonesia.</p>
  </div>

  <div class="section">
    <h2>5. Hak Anda (UU PDP)</h2>
    <p>Sesuai Undang-Undang Perlindungan Data Pribadi dan peraturan terkait, Anda berhak mengakses, memperbaiki, dan meminta penghapusan data pribadi Anda, serta mencabut persetujuan dengan batasan yang diatur hukum. Gunakan fitur pengaturan akun atau hubungi kami untuk menindaklanjuti hak tersebut.</p>
  </div>

  <div class="section">
    <h2>6. Layanan Pihak Ketiga</h2>
    <p>Aplikasi menggunakan layanan seperti Firebase (Google) untuk infrastruktur. Pemrosesan data oleh pihak ketiga tunduk pada kebijakan privasi mereka dan perjanjian yang kami gunakan untuk memastikan perlindungan data.</p>
  </div>

  <div class="section">
    <h2>7. Perubahan Kebijakan</h2>
    <p>Kebijakan privasi ini dapat diperbarui. Perubahan material akan diberitahukan melalui aplikasi atau saluran resmi. Penggunaan berkelanjutan setelah perubahan dianggap sebagai penerimaan Anda.</p>
  </div>

  <div class="section">
    <h2>8. Kontak</h2>
    <p>Pertanyaan atau permintaan terkait data pribadi dapat diajukan melalui saluran dukungan di aplikasi atau kontak resmi Traka.</p>
  </div>
''' + _htmlFooter;

  static String get termsHtml => _htmlHeader.replaceFirst('%TITLE%', 'Syarat dan Ketentuan - Traka') + '''
  <h1>Syarat dan Ketentuan</h1>
  <p class="intro">Selamat datang di Traka. Dengan mengunduh, menginstal, atau menggunakan aplikasi Traka, Anda menyetujui syarat dan ketentuan berikut. Traka adalah platform penghubung antara penumpang dan driver travel di Kalimantan; kami bukan penyedia angkutan umum dan tidak memegang dana pengguna.</p>

  <div class="section">
    <h2>1. Definisi Layanan</h2>
    <p>Traka menyediakan aplikasi sebagai sarana penghubung (platform) antara pengguna yang membutuhkan jasa travel dan pengemudi/driver. Kami tidak memiliki kendali atas kendaraan, driver, atau penumpang. Seluruh transaksi keuangan (pembayaran, kesepakatan harga) terjadi langsung antara pengguna; aplikasi tidak menyimpan, memegang, atau mengelola uang pengguna.</p>
  </div>

  <div class="section">
    <h2>2. Kewajiban Pengguna</h2>
    <p>Anda wajib: memberikan informasi akun yang benar, mematuhi peraturan lalu lintas dan hukum yang berlaku di Indonesia, tidak menggunakan layanan untuk tujuan ilegal atau yang melanggar hak pihak ketiga, serta menjaga kerahasiaan akun. Anda bertanggung jawab penuh atas transaksi dan kesepakatan yang Anda buat dengan pengguna lain.</p>
  </div>

  <div class="section">
    <h2>3. Konfirmasi Perjalanan dan Biaya Pelanggaran</h2>
    <p><strong>3.1.</strong> Pengguna wajib melakukan scan barcode untuk konfirmasi penjemputan dan penyelesaian perjalanan sesuai ketentuan Aplikasi.</p>
    <p><strong>3.2.</strong> Apabila Pengguna tidak melakukan scan barcode, Aplikasi dapat melakukan konfirmasi otomatis berdasarkan data lokasi. Penggunaan konfirmasi otomatis dikenai biaya pelanggaran sebesar Rp 5.000 per perjalanan.</p>
    <p><strong>3.3.</strong> Untuk Penumpang: biaya pelanggaran wajib dibayar melalui metode pembayaran yang disediakan (termasuk Google Play) sebelum dapat menggunakan fitur pencarian travel kembali.</p>
    <p><strong>3.4.</strong> Untuk Driver: biaya pelanggaran ditambahkan ke pembayaran kontribusi dengan rincian yang disampaikan melalui Aplikasi.</p>
    <p><strong>3.5.</strong> Ketentuan ini tidak berlaku untuk layanan kirim barang.</p>
  </div>

  <div class="section">
    <h2>4. Batasan Layanan dan Tanggung Jawab</h2>
    <p>Traka berfungsi sebagai perantara teknologi saja. Kami tidak menjamin ketersediaan driver, keamanan perjalanan, atau pemenuhan kesepakatan antar pengguna. Segala sengketa terkait pembayaran, perjalanan, atau cedera diselesaikan antara pengguna yang bersangkutan; sejauh diizinkan hukum, Traka tidak bertanggung jawab atas kerugian langsung maupun tidak langsung yang timbul dari penggunaan aplikasi atau transaksi antar pengguna.</p>
  </div>

  <div class="section">
    <h2>5. Kepatuhan Hukum</h2>
    <p>Layanan tunduk pada hukum Republik Indonesia, termasuk namun tidak terbatas pada UU ITE, UU Perlindungan Data Pribadi, dan peraturan terkait transportasi dan perlindungan konsumen. Pengguna wajib mematuhi seluruh peraturan yang berlaku.</p>
  </div>

  <div class="section">
    <h2>6. Hak Kekayaan Intelektual</h2>
    <p>Seluruh materi dalam aplikasi (logo, teks, desain, kode) merupakan hak Traka atau pemberi lisensi. Penggunaan hanya untuk kepentingan penggunaan layanan yang wajar; dilarang menyalin, mengubah, atau mengeksploitasi tanpa izin tertulis.</p>
  </div>

  <div class="section">
    <h2>7. Penghentian Akun</h2>
    <p>Kami dapat menangguhkan atau menghentikan akses akun jika pengguna melanggar syarat ini atau ketentuan hukum. Anda dapat menghentikan penggunaan kapan saja dengan menghapus akun sesuai prosedur di aplikasi.</p>
  </div>

  <div class="section">
    <h2>8. Aplikasi di Google Play</h2>
    <p>Aplikasi didistribusikan melalui Google Play Store. Pengunduhan dan pembelian (jika ada) juga tunduk pada Ketentuan Layanan Google Play dan kebijakan Google. Setiap fitur berbayar atau donasi dalam aplikasi mengikuti kebijakan monetisasi Google Play yang berlaku.</p>
  </div>

  <div class="section">
    <h2>9. Perubahan Syarat</h2>
    <p>Kami dapat mengubah syarat dan ketentuan ini. Perubahan material akan diberitahukan melalui aplikasi. Melanjutkan penggunaan setelah pemberitahuan dianggap sebagai penerimaan Anda terhadap perubahan.</p>
  </div>

  <div class="section">
    <h2>10. Kontak</h2>
    <p>Pertanyaan mengenai syarat dan ketentuan dapat diajukan melalui saluran dukungan di aplikasi atau kontak resmi Traka.</p>
  </div>
''' + _htmlFooter;

  /// Membagikan Kebijakan Privasi sebagai file HTML. Pengguna dapat membuka di browser lalu Cetak → Simpan sebagai PDF.
  static Future<void> sharePrivacyAsFile() async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/Kebijakan_Privasi_Traka.html');
    await file.writeAsString(privacyHtml, encoding: utf8);
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Kebijakan Privasi - Traka',
      text: 'Buka file ini dengan browser, lalu pilih Cetak > Simpan sebagai PDF untuk mendapatkan PDF.',
    );
  }

  /// Membagikan Syarat dan Ketentuan sebagai file HTML. Pengguna dapat membuka di browser lalu Cetak → Simpan sebagai PDF.
  static Future<void> shareTermsAsFile() async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/Syarat_dan_Ketentuan_Traka.html');
    await file.writeAsString(termsHtml, encoding: utf8);
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Syarat dan Ketentuan - Traka',
      text: 'Buka file ini dengan browser, lalu pilih Cetak > Simpan sebagai PDF untuk mendapatkan PDF.',
    );
  }
}
