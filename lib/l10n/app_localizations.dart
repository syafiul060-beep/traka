/// Lokalisasi untuk Traka – default Bahasa Indonesia.
enum AppLocale { id, en }

class AppLocalizations {
  final AppLocale locale;

  AppLocalizations({this.locale = AppLocale.id});

  // Bahasa
  String get language => locale == AppLocale.id ? 'Bahasa' : 'Language';

  // Logo & branding
  String get appName => 'Traka';
  String get tagline => 'Travel Kalimantan';

  // Form login
  String get emailHint =>
      locale == AppLocale.id ? 'Masukan email anda' : 'Enter your email';
  String get passwordHint =>
      locale == AppLocale.id ? 'Masukan sandi anda' : 'Enter your password';
  String get loginButton => locale == AppLocale.id ? 'Masuk' : 'Login';
  String get rememberMe => 'Remember Me';
  String get forgotPassword =>
      locale == AppLocale.id ? 'Lupa kata sandi' : 'Forgot password';
  String get register => locale == AppLocale.id ? 'Daftar' : 'Register';
  String get registerPrompt => locale == AppLocale.id
      ? 'Belum Punya Akun...? Daftar'
      : "Don't have an account...? Register";
  String get penumpang => locale == AppLocale.id ? 'Penumpang' : 'Passenger';
  String get driver => 'Driver';

  // Form registrasi
  String get uploadPhoto =>
      locale == AppLocale.id ? 'Silahkan isi foto diri' : 'Upload self photo';
  String get nameHint => locale == AppLocale.id
      ? 'Silahkan isi nama lengkap'
      : 'Please fill in full name';
  String get emailHintRegister => locale == AppLocale.id
      ? 'Silahkan isi alamat email'
      : 'Please fill in email address';
  String get verificationCodeHint => locale == AppLocale.id
      ? 'Masukkan kode verifikasi'
      : 'Enter verification code';
  String get passwordHintRegister => locale == AppLocale.id
      ? 'Masukkan kata sandi anda'
      : 'Enter your password';
  String get confirmPasswordHint =>
      locale == AppLocale.id ? 'Konfirmasi sandi' : 'Confirm password';
  String get passwordRequirement => locale == AppLocale.id
      ? 'Panjang kata sandi minimal 8, harus mengandung angka'
      : 'Password minimum 8 characters, must contain a number';
  String get submitButton => locale == AppLocale.id ? 'Ajukan' : 'Submit';
  String get agreeTerms =>
      'I agree with the Terms of Service and Privacy Policy';
  String get termsOfService => 'Terms of Service';
  String get privacyPolicy => 'Privacy Policy';
  String get backToLogin =>
      locale == AppLocale.id ? 'Kembali ke Login' : 'Back to Login';
  String get registerSuccess => locale == AppLocale.id
      ? 'Pendaftaran berhasil silahkan login'
      : 'Registration successful, please login';
  String get registerFailure => locale == AppLocale.id
      ? 'Pendaftaran belum berhasil silahkan periksa ulang data pendaftaran yang benar'
      : 'Registration failed, please check your registration data';
  String get faceNotDetected => locale == AppLocale.id
      ? 'Wajah tidak terdeteksi. Silakan ulangi pengambilan foto.'
      : 'Face not detected. Please retake the photo.';

  /// Pesan jika lokasi driver di luar Indonesia.
  String get trakaIndonesiaOnly => locale == AppLocale.id
      ? 'Bahwa Traka hanya dapat di gunakan di Indonesia'
      : 'Traka can only be used in Indonesia';

  /// Gagal memperoleh lokasi (untuk driver).
  String get locationError => locale == AppLocale.id
      ? 'Tidak dapat memperoleh lokasi. Pastikan izin lokasi diaktifkan dan GPS menyala.'
      : 'Unable to get location. Please enable location permission and GPS.';

  /// Peringatan saat Fake GPS / lokasi palsu terdeteksi.
  String get fakeGpsWarning => locale == AppLocale.id
      ? 'Aplikasi Traka melindungi pengguna dari berbagai modus kejahatan yang disengaja, matikan Fake GPS/Lokasi palsu jika ingin menggunakan Traka...!'
      : 'Traka protects users from intentional fraud; turn off Fake GPS/spoofed location to use Traka...!';

  AppLocalizations copyWith({AppLocale? locale}) {
    return AppLocalizations(locale: locale ?? this.locale);
  }
}
