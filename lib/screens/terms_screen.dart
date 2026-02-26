import 'package:flutter/material.dart';

import '../services/privacy_terms_export_service.dart';

/// Halaman Syarat dan Ketentuan – sesuai UU Indonesia dan kebijakan Google Play.
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  Future<void> _shareAsPdf(BuildContext context) async {
    try {
      await PrivacyTermsExportService.shareTermsAsFile();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Buka file yang dibagikan dengan browser, lalu pilih Cetak > Simpan sebagai PDF.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal membagikan file.'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final headingStyle = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: Theme.of(context).colorScheme.onSurface,
    );
    final bodyStyle = TextStyle(
      fontSize: 14,
      color: Theme.of(context).colorScheme.onSurface,
      height: 1.6,
    );
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        elevation: 0,
        title: Text(
          'Syarat dan Ketentuan',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Simpan / Bagikan sebagai PDF',
            onPressed: () => _shareAsPdf(context),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                'Selamat datang di Traka. Dengan mengunduh, menginstal, atau menggunakan aplikasi Traka, Anda menyetujui syarat dan ketentuan berikut. '
                'Traka adalah platform penghubung antara penumpang dan driver travel di Kalimantan; kami bukan penyedia angkutan umum dan tidak memegang dana pengguna.',
                style: bodyStyle,
              ),
              const SizedBox(height: 20),
              SelectableText('1. Definisi Layanan', style: headingStyle),
              const SizedBox(height: 8),
              SelectableText(
                'Traka menyediakan aplikasi sebagai sarana penghubung (platform) antara pengguna yang membutuhkan jasa travel dan pengemudi/driver. '
                'Kami tidak memiliki kendali atas kendaraan, driver, atau penumpang. Seluruh transaksi keuangan (pembayaran, kesepakatan harga) '
                'terjadi langsung antara pengguna; aplikasi tidak menyimpan, memegang, atau mengelola uang pengguna.',
                style: bodyStyle,
              ),
              const SizedBox(height: 20),
              SelectableText('2. Kewajiban Pengguna', style: headingStyle),
              const SizedBox(height: 8),
              SelectableText(
                'Anda wajib: memberikan informasi akun yang benar, mematuhi peraturan lalu lintas dan hukum yang berlaku di Indonesia, '
                'tidak menggunakan layanan untuk tujuan ilegal atau yang melanggar hak pihak ketiga, serta menjaga kerahasiaan akun. '
                'Anda bertanggung jawab penuh atas transaksi dan kesepakatan yang Anda buat dengan pengguna lain.',
                style: bodyStyle,
              ),
              const SizedBox(height: 20),
              SelectableText('3. Batasan Layanan dan Tanggung Jawab', style: headingStyle),
              const SizedBox(height: 8),
              SelectableText(
                'Traka berfungsi sebagai perantara teknologi saja. Kami tidak menjamin ketersediaan driver, keamanan perjalanan, '
                'atau pemenuhan kesepakatan antar pengguna. Segala sengketa terkait pembayaran, perjalanan, atau cedera '
                'diselesaikan antara pengguna yang bersangkutan; sejauh diizinkan hukum, Traka tidak bertanggung jawab atas kerugian '
                'langsung maupun tidak langsung yang timbul dari penggunaan aplikasi atau transaksi antar pengguna.',
                style: bodyStyle,
              ),
              const SizedBox(height: 20),
              SelectableText('4. Kepatuhan Hukum', style: headingStyle),
              const SizedBox(height: 8),
              SelectableText(
                'Layanan tunduk pada hukum Republik Indonesia, termasuk namun tidak terbatas pada UU ITE, UU Perlindungan Data Pribadi, '
                'dan peraturan terkait transportasi dan perlindungan konsumen. Pengguna wajib mematuhi seluruh peraturan yang berlaku.',
                style: bodyStyle,
              ),
              const SizedBox(height: 20),
              SelectableText('5. Hak Kekayaan Intelektual', style: headingStyle),
              const SizedBox(height: 8),
              SelectableText(
                'Seluruh materi dalam aplikasi (logo, teks, desain, kode) merupakan hak Traka atau pemberi lisensi. '
                'Penggunaan hanya untuk kepentingan penggunaan layanan yang wajar; dilarang menyalin, mengubah, atau mengeksploitasi tanpa izin tertulis.',
                style: bodyStyle,
              ),
              const SizedBox(height: 20),
              SelectableText('6. Konfirmasi Perjalanan dan Biaya Pelanggaran', style: headingStyle),
              const SizedBox(height: 8),
              SelectableText(
                '6.1. Pengguna wajib melakukan scan barcode untuk konfirmasi penjemputan dan penyelesaian perjalanan sesuai ketentuan Aplikasi.',
                style: bodyStyle,
              ),
              const SizedBox(height: 8),
              SelectableText(
                '6.2. Apabila Pengguna tidak melakukan scan barcode, Aplikasi dapat melakukan konfirmasi otomatis berdasarkan data lokasi. Penggunaan konfirmasi otomatis dikenai biaya pelanggaran sebesar Rp 5.000 per perjalanan.',
                style: bodyStyle,
              ),
              const SizedBox(height: 8),
              SelectableText(
                '6.3. Untuk Penumpang: biaya pelanggaran wajib dibayar melalui metode pembayaran yang disediakan (termasuk Google Play) sebelum dapat menggunakan fitur pencarian travel kembali.',
                style: bodyStyle,
              ),
              const SizedBox(height: 8),
              SelectableText(
                '6.4. Untuk Driver: biaya pelanggaran ditambahkan ke pembayaran kontribusi dengan rincian yang disampaikan melalui Aplikasi.',
                style: bodyStyle,
              ),
              const SizedBox(height: 8),
              SelectableText(
                '6.5. Ketentuan ini tidak berlaku untuk layanan kirim barang.',
                style: bodyStyle,
              ),
              const SizedBox(height: 20),
              SelectableText('7. Penghentian Akun', style: headingStyle),
              const SizedBox(height: 8),
              SelectableText(
                'Kami dapat menangguhkan atau menghentikan akses akun jika pengguna melanggar syarat ini atau ketentuan hukum. '
                'Anda dapat menghentikan penggunaan kapan saja dengan menghapus akun sesuai prosedur di aplikasi.',
                style: bodyStyle,
              ),
              const SizedBox(height: 20),
              SelectableText('8. Aplikasi di Google Play', style: headingStyle),
              const SizedBox(height: 8),
              SelectableText(
                'Aplikasi didistribusikan melalui Google Play Store. Pengunduhan dan pembelian (jika ada) juga tunduk pada '
                'Ketentuan Layanan Google Play dan kebijakan Google. Setiap fitur berbayar atau donasi dalam aplikasi mengikuti '
                'kebijakan monetisasi Google Play yang berlaku.',
                style: bodyStyle,
              ),
              const SizedBox(height: 20),
              SelectableText('9. Perubahan Syarat', style: headingStyle),
              const SizedBox(height: 8),
              SelectableText(
                'Kami dapat mengubah syarat dan ketentuan ini. Perubahan material akan diberitahukan melalui aplikasi. '
                'Melanjutkan penggunaan setelah pemberitahuan dianggap sebagai penerimaan Anda terhadap perubahan.',
                style: bodyStyle,
              ),
              const SizedBox(height: 20),
              SelectableText('10. Kontak', style: headingStyle),
              const SizedBox(height: 8),
              SelectableText(
                'Pertanyaan mengenai syarat dan ketentuan dapat diajukan melalui saluran dukungan di aplikasi atau kontak resmi Traka.',
                style: bodyStyle,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
