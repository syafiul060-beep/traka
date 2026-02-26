import 'package:flutter/material.dart';

import '../services/privacy_terms_export_service.dart';

/// Halaman Kebijakan Privasi – sesuai UU PDP dan praktik aman.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  Future<void> _shareAsPdf(BuildContext context) async {
    try {
      await PrivacyTermsExportService.sharePrivacyAsFile();
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
          'Kebijakan Privasi',
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
                'Traka adalah aplikasi yang menghubungkan penumpang dengan driver travel di wilayah Kalimantan dan Wilayah diluar Kalimatan. '
                'Kami tidak menyimpan, memegang, atau mengontrol dana pengguna; seluruh transaksi keuangan terjadi langsung antar pengguna.',
                style: bodyStyle,
              ),
              const SizedBox(height: 20),
              SelectableText('1. Data yang Kami Kumpulkan', style: headingStyle),
              const SizedBox(height: 8),
              SelectableText(
                'Untuk keperluan layanan dan keamanan, kami dapat memproses: data akun (nama, email, nomor telepon jika Anda tambahkan), '
                'foto profil dan data verifikasi wajah (untuk keamanan akun), identifikasi perangkat (device ID), dan lokasi saat menggunakan layanan. '
                'Data verifikasi wajah dan data sensitif lainnya tidak disimpan dalam bentuk mentah yang dapat disalahgunakan; '
                'kami menggunakan layanan dan praktik yang aman sesuai kebutuhan teknis layanan.',
                style: bodyStyle,
              ),
              const SizedBox(height: 12),
              SelectableText('Pengambilan Data KTP dan STNK', style: headingStyle.copyWith(fontSize: 14)),
              const SizedBox(height: 6),
              SelectableText(
                'Untuk verifikasi identitas (KTP) dan data kendaraan (STNK), Aplikasi meminta pengambilan foto dokumen. '
                'Foto tersebut HANYA digunakan untuk ekstraksi data (misalnya nama, NIK, nomor plat) melalui teknologi pengenalan teks (OCR) '
                'dan TIDAK DISIMPAN di server kami. Setelah data diekstraksi, foto dihapus dari perangkat dan tidak dikirim atau disimpan secara permanen. '
                'Hanya data hasil ekstraksi (teks) yang disimpan untuk keperluan layanan.',
                style: bodyStyle,
              ),
              const SizedBox(height: 20),
              SelectableText('2. Penggunaan Data', style: headingStyle),
              const SizedBox(height: 8),
              SelectableText(
                'Data digunakan hanya untuk: menyediakan dan meningkatkan layanan Traka, verifikasi identitas dan keamanan akun, '
                'memenuhi kewajiban hukum, serta komunikasi terkait layanan. Kami tidak menjual data pribadi Anda kepada pihak ketiga untuk tujuan pemasaran.',
                style: bodyStyle,
              ),
              const SizedBox(height: 20),
              SelectableText('3. Tidak Ada Penyimpanan Dana', style: headingStyle),
              const SizedBox(height: 8),
              SelectableText(
                'Aplikasi Traka tidak memegang uang pengguna. Kami hanya mempertemukan penumpang dan driver; '
                'pembayaran dan kesepakatan harga merupakan transaksi langsung antara Anda dan pihak lain, di luar kendali dan penyimpanan kami.',
                style: bodyStyle,
              ),
              const SizedBox(height: 20),
              SelectableText('4. Keamanan Data', style: headingStyle),
              const SizedBox(height: 8),
              SelectableText(
                'Kami menerapkan langkah teknis dan organisasi yang wajar untuk melindungi data pribadi dari akses, pengubahan, '
                'atau pengungkapan yang tidak sah, sejalan dengan ketentuan peraturan perundang-undangan Indonesia.',
                style: bodyStyle,
              ),
              const SizedBox(height: 20),
              SelectableText('5. Hak Anda (UU PDP)', style: headingStyle),
              const SizedBox(height: 8),
              SelectableText(
                'Sesuai Undang-Undang Perlindungan Data Pribadi dan peraturan terkait, Anda berhak mengakses, memperbaiki, '
                'dan meminta penghapusan data pribadi Anda, serta mencabut persetujuan dengan batasan yang diatur hukum. '
                'Gunakan fitur pengaturan akun atau hubungi kami untuk menindaklanjuti hak tersebut.',
                style: bodyStyle,
              ),
              const SizedBox(height: 20),
              SelectableText('6. Layanan Pihak Ketiga', style: headingStyle),
              const SizedBox(height: 8),
              SelectableText(
                'Aplikasi menggunakan layanan seperti Firebase (Google) untuk infrastruktur. Pemrosesan data oleh pihak ketiga '
                'tunduk pada kebijakan privasi mereka dan perjanjian yang kami gunakan untuk memastikan perlindungan data.',
                style: bodyStyle,
              ),
              const SizedBox(height: 20),
              SelectableText('7. Perubahan Kebijakan', style: headingStyle),
              const SizedBox(height: 8),
              SelectableText(
                'Kebijakan privasi ini dapat diperbarui. Perubahan material akan diberitahukan melalui aplikasi atau saluran resmi. '
                'Penggunaan berkelanjutan setelah perubahan dianggap sebagai penerimaan Anda.',
                style: bodyStyle,
              ),
              const SizedBox(height: 20),
              SelectableText('8. Kontak', style: headingStyle),
              const SizedBox(height: 8),
              SelectableText(
                'Pertanyaan atau permintaan terkait data pribadi dapat diajukan melalui saluran dukungan di aplikasi atau kontak resmi Traka.',
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
