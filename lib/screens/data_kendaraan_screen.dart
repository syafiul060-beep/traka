import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../models/vehicle_model.dart';
import '../services/vehicle_brand_service.dart';

/// Screen untuk mengisi data kendaraan driver
class DataKendaraanScreen extends StatefulWidget {
  const DataKendaraanScreen({super.key});

  @override
  State<DataKendaraanScreen> createState() => _DataKendaraanScreenState();
}

class _DataKendaraanScreenState extends State<DataKendaraanScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _formKey = GlobalKey<FormState>();
  final _platController = TextEditingController();

  String? _selectedMerek;
  String? _selectedType;
  int? _jumlahPenumpang;
  bool _isLoading = false;
  bool _isCheckingPlat = false;
  String? _existingPlat; // Plat yang sudah ada untuk driver ini

  // Data merek dan type dari Firestore (dinamis)
  List<String> _merekList = [];
  List<String> _typeList = [];
  bool _isLoadingMerek = true;

  @override
  void initState() {
    super.initState();
    _loadMerekMobil(); // Load merek mobil dari Firestore
    _loadExistingVehicleData();
  }

  @override
  void dispose() {
    _platController.dispose();
    super.dispose();
  }

  /// Load daftar merek mobil dari Firestore (dengan fallback ke data default)
  Future<void> _loadMerekMobil() async {
    setState(() => _isLoadingMerek = true);
    try {
      final merekList = await VehicleBrandService.getMerekMobil();
      if (mounted) {
        setState(() {
          _merekList = merekList;
          _isLoadingMerek = false;
        });
      }
    } catch (e) {
      // Fallback ke data default jika error
      if (mounted) {
        setState(() {
          _merekList = VehicleModel.merekMobilIndonesia;
          _isLoadingMerek = false;
        });
      }
    }
  }

  /// Load daftar type mobil berdasarkan merek yang dipilih
  Future<void> _loadTypeByMerek(String merek) async {
    if (merek.isEmpty) {
      setState(() {
        _typeList = [];
        _selectedType = null;
        _jumlahPenumpang = null;
      });
      return;
    }

    try {
      final typeList = await VehicleBrandService.getTypeByMerek(merek);
      if (mounted) {
        setState(() {
          _typeList = typeList;
          _selectedType = null; // Reset type saat merek berubah
          _jumlahPenumpang = null; // Reset jumlah penumpang
        });
      }
    } catch (e) {
      // Fallback ke data default jika error
      if (mounted) {
        setState(() {
          _typeList = VehicleModel.getTypeByMerek(merek);
          _selectedType = null;
          _jumlahPenumpang = null;
        });
      }
    }
  }

  /// Set jumlah penumpang berdasarkan merek dan type
  Future<void> _setJumlahPenumpang(String merek, String type) async {
    try {
      final jumlah = await VehicleBrandService.getJumlahPenumpang(merek, type);
      if (mounted) {
        setState(() {
          _jumlahPenumpang = jumlah;
        });
      }
    } catch (e) {
      // Fallback ke data default jika error
      if (mounted) {
        setState(() {
          _jumlahPenumpang = VehicleModel.getJumlahPenumpang(merek, type);
        });
      }
    }
  }

  /// Load data kendaraan yang sudah ada untuk driver ini
  Future<void> _loadExistingVehicleData() async {
    final user = _auth.currentUser;
    if (user == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists && userDoc.data() != null) {
        final data = userDoc.data()!;
        final plat = data['vehiclePlat'] as String?;
        final merek = data['vehicleMerek'] as String?;
        final type = data['vehicleType'] as String?;
        final jumlahPenumpang = data['vehicleJumlahPenumpang'] as int?;

        if (mounted && plat != null) {
          setState(() {
            _existingPlat = plat;
            _platController.text = plat;
            _selectedMerek = merek;
            _selectedType = type;
            _jumlahPenumpang = jumlahPenumpang;
            _isLoading = false;
          });

          // Load type list jika merek sudah ada
          if (merek != null) {
            _loadTypeByMerek(merek);
          }
        }
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Cek apakah nomor plat sudah ada di Firebase (milik driver lain)
  Future<bool> _checkPlatExists(String plat) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final platUpper = plat.toUpperCase();

      // Cek di collection users apakah ada driver lain yang punya plat ini
      final querySnapshot = await _firestore
          .collection('users')
          .where('vehiclePlat', isEqualTo: platUpper)
          .limit(1)
          .get();

      // Jika ada hasil, cek apakah itu milik driver lain (bukan driver saat ini)
      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        return doc.id != user.uid; // True jika milik driver lain
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  /// Validasi nomor plat saat user mengetik
  Future<void> _validatePlat(String plat) async {
    if (plat.isEmpty) {
      setState(() => _isCheckingPlat = false);
      return;
    }

    final platUpper = plat.toUpperCase();

    // Jika plat sama dengan plat yang sudah ada untuk driver ini, tidak perlu validasi
    if (_existingPlat != null && platUpper == _existingPlat) {
      setState(() => _isCheckingPlat = false);
      return;
    }

    setState(() => _isCheckingPlat = true);

    final exists = await _checkPlatExists(platUpper);

    if (mounted) {
      setState(() => _isCheckingPlat = false);

      if (exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mobil milik Driver lain'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _formKey.currentState?.validate();
      }
    }
  }

  /// Simpan data kendaraan ke Firebase
  Future<void> _saveVehicleData() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedMerek == null ||
        _selectedType == null ||
        _jumlahPenumpang == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mohon lengkapi semua data kendaraan'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Cek lagi apakah plat sudah ada
    final platExists = await _checkPlatExists(
      _platController.text.toUpperCase(),
    );
    if (platExists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mobil milik Driver lain'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = _auth.currentUser;
      if (user == null) return;

      // Simpan ke collection vehicles dengan nomor plat sebagai document ID
      await _firestore
          .collection('vehicles')
          .doc(_platController.text.toUpperCase())
          .set({
            'driverUid': user.uid,
            'nomorPlat': _platController.text.toUpperCase(),
            'merek': _selectedMerek,
            'type': _selectedType,
            'jumlahPenumpang': _jumlahPenumpang,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });

      // Update juga di document user untuk referensi cepat
      await _firestore.collection('users').doc(user.uid).update({
        'vehiclePlat': _platController.text.toUpperCase(),
        'vehicleMerek': _selectedMerek,
        'vehicleType': _selectedType,
        'vehicleJumlahPenumpang': _jumlahPenumpang,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _existingPlat != null
                  ? 'Data kendaraan berhasil diperbarui'
                  : 'Data kendaraan berhasil disimpan',
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menyimpan data: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Kendaraan'),
        elevation: 0,
      ),
      body: _isLoading && _existingPlat == null
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Nomor Plat Kendaraan
                    Text(
                      'Nomor Plat Kendaraan',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _platController,
                      decoration: InputDecoration(
                        hintText: 'Contoh: B 1234 ABC',
                        border: const OutlineInputBorder(),
                        suffixIcon: _isCheckingPlat
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: Padding(
                                  padding: EdgeInsets.all(12),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : null,
                      ),
                      textCapitalization: TextCapitalization.characters,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Nomor plat wajib diisi';
                        }
                        return null;
                      },
                      onChanged: (value) {
                        if (value.length >= 3) {
                          _validatePlat(value);
                        }
                      },
                    ),
                    const SizedBox(height: 24),

                    // Merek Kendaraan
                    Text(
                      'Merek Kendaraan',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _isLoadingMerek
                        ? const Center(child: CircularProgressIndicator())
                        : DropdownButtonFormField<String>(
                            initialValue: _selectedMerek,
                            decoration: const InputDecoration(
                              hintText: 'Pilih Merek Mobil',
                              border: OutlineInputBorder(),
                            ),
                            items: _merekList.map((merek) {
                              return DropdownMenuItem(
                                value: merek,
                                child: Text(merek),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                _loadTypeByMerek(value);
                              }
                            },
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Merek kendaraan wajib dipilih';
                              }
                              return null;
                            },
                          ),
                    const SizedBox(height: 24),

                    // Type Kendaraan
                    if (_selectedMerek != null &&
                        _selectedMerek!.isNotEmpty) ...[
                      Text(
                        'Type Kendaraan',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _typeList.isEmpty
                          ? const Center(child: CircularProgressIndicator())
                          : DropdownButtonFormField<String>(
                              initialValue: _selectedType,
                              decoration: const InputDecoration(
                                hintText: 'Pilih Type Mobil',
                                border: OutlineInputBorder(),
                              ),
                              items: _typeList.map((type) {
                                return DropdownMenuItem(
                                  value: type,
                                  child: Text(type),
                                );
                              }).toList(),
                              onChanged: (value) {
                                if (value != null && _selectedMerek != null) {
                                  setState(() {
                                    _selectedType = value;
                                  });
                                  _setJumlahPenumpang(_selectedMerek!, value);
                                }
                              },
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Type kendaraan wajib dipilih';
                                }
                                return null;
                              },
                            ),
                      const SizedBox(height: 24),
                    ],

                    // Jumlah Penumpang
                    if (_jumlahPenumpang != null) ...[
                      Text(
                        'Jumlah Penumpang',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Theme.of(context).colorScheme.outline),
                        ),
                        child: Text(
                          '$_jumlahPenumpang Penumpang',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Tombol Simpan
                    FilledButton(
                      onPressed: _isLoading ? null : _saveVehicleData,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Theme.of(context).colorScheme.primary,
                      ),
                      child: _isLoading
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Theme.of(context).colorScheme.onPrimary,
                                ),
                              ),
                            )
                          : const Text(
                              'Simpan Data Kendaraan',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Widget form untuk digunakan di modal bottom sheet
class DataKendaraanFormSheet extends StatefulWidget {
  final ScrollController scrollController;
  /// Plat dari hasil scan (saat driver klik Data Kendaraan lalu pilih Scan)
  final String? initialPlatFromScan;

  const DataKendaraanFormSheet({
    super.key,
    required this.scrollController,
    this.initialPlatFromScan,
  });

  @override
  State<DataKendaraanFormSheet> createState() => _DataKendaraanFormSheetState();
}

class _DataKendaraanFormSheetState extends State<DataKendaraanFormSheet> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _formKey = GlobalKey<FormState>();
  final _platController = TextEditingController();

  String? _selectedMerek;
  String? _selectedType;
  int? _jumlahPenumpang;
  bool _isLoading = false;
  bool _isCheckingPlat = false;
  String? _existingPlat;

  // Data merek dan type dari Firestore (dinamis)
  List<String> _merekList = [];
  List<String> _typeList = [];
  bool _isLoadingMerek = true;

  @override
  void initState() {
    super.initState();
    _loadMerekMobil();
    _loadExistingVehicleData();
    if (widget.initialPlatFromScan != null &&
        widget.initialPlatFromScan!.isNotEmpty) {
      _platController.text = widget.initialPlatFromScan!;
      if (widget.initialPlatFromScan!.length >= 3) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _validatePlat(widget.initialPlatFromScan!);
        });
      }
    }
  }

  @override
  void dispose() {
    _platController.dispose();
    super.dispose();
  }

  /// Load daftar merek mobil dari Firestore
  Future<void> _loadMerekMobil() async {
    setState(() => _isLoadingMerek = true);
    try {
      final merekList = await VehicleBrandService.getMerekMobil();
      if (mounted) {
        setState(() {
          _merekList = merekList;
          _isLoadingMerek = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _merekList = VehicleModel.merekMobilIndonesia;
          _isLoadingMerek = false;
        });
      }
    }
  }

  /// Load data kendaraan yang sudah ada
  Future<void> _loadExistingVehicleData() async {
    final user = _auth.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      // Tambahkan timeout untuk mencegah loading terlalu lama
      final userDoc = await _firestore
          .collection('users')
          .doc(user.uid)
          .get()
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException('Request timeout');
            },
          );

      if (mounted) {
        if (userDoc.exists && userDoc.data() != null) {
          final data = userDoc.data()!;
          final plat = data['vehiclePlat'] as String?;
          final merek = data['vehicleMerek'] as String?;
          final type = data['vehicleType'] as String?;
          final jumlahPenumpang = data['vehicleJumlahPenumpang'] as int?;

          if (plat != null) {
            final scannedSameAsExisting = widget.initialPlatFromScan != null &&
                widget.initialPlatFromScan!.isNotEmpty &&
                plat.toUpperCase() ==
                    widget.initialPlatFromScan!.trim().toUpperCase();
            setState(() {
              _existingPlat = plat;
              // Jangan overwrite plat jika ada initialPlatFromScan (hasil scan baru)
              if (widget.initialPlatFromScan == null ||
                  widget.initialPlatFromScan!.isEmpty) {
                _platController.text = plat;
                _selectedMerek = merek;
                _selectedType = type;
                _jumlahPenumpang = jumlahPenumpang;
              } else if (scannedSameAsExisting) {
                // Scan plat sama dengan existing - pakai data lengkap
                _platController.text = plat;
                _selectedMerek = merek;
                _selectedType = type;
                _jumlahPenumpang = jumlahPenumpang;
              }
              // else: plat dari scan berbeda (ganti kendaraan), tetap pakai initialPlatFromScan, merek/type kosong
              _isLoading = false;
            });
            if (merek != null && (scannedSameAsExisting || widget.initialPlatFromScan == null)) {
              _loadTypeByMerek(
                merek,
                preserveType: type,
                preserveJumlahPenumpang: jumlahPenumpang,
              );
            }
          } else {
            setState(() => _isLoading = false);
          }
        } else {
          // Tidak ada data, set loading ke false
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      // Pastikan loading selalu di-set ke false meskipun error
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Load type berdasarkan merek
  Future<void> _loadTypeByMerek(
    String merek, {
    String? preserveType,
    int? preserveJumlahPenumpang,
  }) async {
    if (merek.isEmpty) {
      setState(() {
        _typeList = [];
        if (preserveType == null) {
          _selectedType = null;
          _jumlahPenumpang = null;
        }
      });
      return;
    }

    // Simpan type yang sudah dipilih sebelumnya jika ada
    final currentType = preserveType ?? _selectedType;
    final currentJumlahPenumpang = preserveJumlahPenumpang ?? _jumlahPenumpang;

    // Set loading state untuk type
    setState(() {
      _typeList = [];
      // Jangan reset _selectedType jika ada preserveType
      if (preserveType == null) {
        _selectedType = null;
        _jumlahPenumpang = null;
      }
    });

    try {
      // Tambahkan timeout untuk mencegah loading terlalu lama
      final typeList = await VehicleBrandService.getTypeByMerek(merek).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          return VehicleModel.getTypeByMerek(merek);
        },
      );
      if (mounted) {
        setState(() {
          _typeList = typeList;
          // Kembalikan type yang sudah dipilih sebelumnya jika masih ada di list
          if (currentType != null && typeList.contains(currentType)) {
            _selectedType = currentType;
            // Jika ada preserveJumlahPenumpang, gunakan itu, jika tidak load dari service
            if (preserveJumlahPenumpang != null) {
              _jumlahPenumpang = preserveJumlahPenumpang;
            } else {
              // Jika type sudah ada tapi tidak ada preserveJumlahPenumpang, load dari service
              _setJumlahPenumpang(merek, currentType);
            }
          } else if (preserveType == null) {
            _selectedType = null;
            _jumlahPenumpang = null;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        final fallbackTypeList = VehicleModel.getTypeByMerek(merek);
        setState(() {
          _typeList = fallbackTypeList;
          // Kembalikan type yang sudah dipilih sebelumnya jika masih ada di list
          if (currentType != null && fallbackTypeList.contains(currentType)) {
            _selectedType = currentType;
            // Jika ada preserveJumlahPenumpang, gunakan itu, jika tidak load dari service
            if (preserveJumlahPenumpang != null) {
              _jumlahPenumpang = preserveJumlahPenumpang;
            } else {
              // Jika type sudah ada tapi tidak ada preserveJumlahPenumpang, load dari service
              _setJumlahPenumpang(merek, currentType);
            }
          } else if (preserveType == null) {
            _selectedType = null;
            _jumlahPenumpang = null;
          }
        });
      }
    }
  }

  /// Set jumlah penumpang
  Future<void> _setJumlahPenumpang(String merek, String type) async {
    try {
      final jumlah = await VehicleBrandService.getJumlahPenumpang(merek, type);
      if (mounted) {
        setState(() {
          _jumlahPenumpang = jumlah;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _jumlahPenumpang = VehicleModel.getJumlahPenumpang(merek, type);
        });
      }
    }
  }

  /// Cek apakah plat sudah ada
  Future<bool> _checkPlatExists(String plat) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final platUpper = plat.toUpperCase();
      final querySnapshot = await _firestore
          .collection('users')
          .where('vehiclePlat', isEqualTo: platUpper)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        return doc.id != user.uid;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Validasi plat
  Future<void> _validatePlat(String plat) async {
    if (plat.isEmpty) {
      setState(() => _isCheckingPlat = false);
      return;
    }

    final platUpper = plat.toUpperCase();
    if (_existingPlat != null && platUpper == _existingPlat) {
      setState(() => _isCheckingPlat = false);
      return;
    }

    setState(() => _isCheckingPlat = true);
    final exists = await _checkPlatExists(platUpper);

    if (mounted) {
      setState(() => _isCheckingPlat = false);
      if (exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mobil milik Driver lain'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _formKey.currentState?.validate();
      }
    }
  }

  /// Simpan data kendaraan
  Future<void> _saveVehicleData() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedMerek == null ||
        _selectedType == null ||
        _jumlahPenumpang == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mohon lengkapi semua data kendaraan'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final platUpper = _platController.text.toUpperCase();
    final platExists = await _checkPlatExists(platUpper);

    if (platExists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mobil milik Driver lain'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = _auth.currentUser;
      if (user == null) return;

      if (_existingPlat != null && _existingPlat != platUpper) {
        try {
          await _firestore.collection('vehicles').doc(_existingPlat).delete();
        } catch (_) {}
      }

      await _firestore.collection('vehicles').doc(platUpper).set({
        'driverUid': user.uid,
        'nomorPlat': platUpper,
        'merek': _selectedMerek,
        'type': _selectedType,
        'jumlahPenumpang': _jumlahPenumpang,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await _firestore.collection('users').doc(user.uid).update({
        'vehiclePlat': platUpper,
        'vehicleMerek': _selectedMerek,
        'vehicleType': _selectedType,
        'vehicleJumlahPenumpang': _jumlahPenumpang,
        'vehicleUpdatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _existingPlat != null
                  ? 'Data kendaraan berhasil diperbarui'
                  : 'Data kendaraan berhasil disimpan',
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menyimpan data: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        // Handle bar untuk drag
        Container(
          margin: const EdgeInsets.only(top: 12, bottom: 8),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: colorScheme.outline,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        // Title
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.directions_car,
                    color: colorScheme.onSurface,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Data Kendaraan',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: Icon(Icons.close, color: colorScheme.onSurface),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        Divider(color: colorScheme.outline),
        // Form content - background mengikuti tema
        Expanded(
          child: Container(
            color: colorScheme.surface,
            child: (_isLoading && _existingPlat == null) || _isLoadingMerek
                ? const Center(child: CircularProgressIndicator())
                : Form(
                    key: _formKey,
                    child: SingleChildScrollView(
                      controller: widget.scrollController,
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Nomor Plat Kendaraan
                          Text(
                            'Nomor Plat Kendaraan',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _platController,
                            style: TextStyle(color: colorScheme.onSurface),
                            decoration: InputDecoration(
                              hintText: 'Contoh: B 1234 ABC',
                              hintStyle: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                              ),
                              filled: true,
                              fillColor: colorScheme.surfaceContainerHighest,
                              border: OutlineInputBorder(
                                borderSide: BorderSide(color: colorScheme.outline),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: colorScheme.outline),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: AppTheme.primary,
                                  width: 2,
                                ),
                              ),
                              suffixIcon: _isCheckingPlat
                                  ? SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppTheme.primary,
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                            textCapitalization: TextCapitalization.characters,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Nomor plat wajib diisi';
                              }
                              return null;
                            },
                            onChanged: (value) {
                              if (value.length >= 3) {
                                _validatePlat(value);
                              }
                            },
                          ),
                          if (widget.initialPlatFromScan != null &&
                              widget.initialPlatFromScan!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                'Periksa dan perbaiki jika scan salah baca.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          const SizedBox(height: 24),

                          // Merek Kendaraan
                          Text(
                            'Merek Kendaraan',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _isLoadingMerek
                              ? Center(
                                  child: CircularProgressIndicator(
                                    color: AppTheme.primary,
                                  ),
                                )
                              : DropdownButtonFormField<String>(
                                  initialValue: _selectedMerek,
                                  dropdownColor: colorScheme.surfaceContainerHighest,
                                  style: TextStyle(color: colorScheme.onSurface),
                                  decoration: InputDecoration(
                                    hintText: 'Pilih Merek Mobil',
                                    hintStyle: TextStyle(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                    filled: true,
                                    fillColor: colorScheme.surfaceContainerHighest,
                                    border: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: colorScheme.outline,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: colorScheme.outline,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: AppTheme.primary,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                  items: _merekList.map((merek) {
                                    return DropdownMenuItem(
                                      value: merek,
                                      child: Text(
                                        merek,
                                        style: TextStyle(
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() {
                                        _selectedMerek = value;
                                      });
                                      _loadTypeByMerek(value);
                                    }
                                  },
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Merek kendaraan wajib dipilih';
                                    }
                                    return null;
                                  },
                                ),
                          const SizedBox(height: 24),

                          // Type Kendaraan - selalu muncul jika merek sudah dipilih
                          if (_selectedMerek != null &&
                              _selectedMerek!.isNotEmpty) ...[
                            Text(
                              'Type Kendaraan',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _typeList.isEmpty && !_isLoadingMerek
                                ? Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    child: Center(
                                      child: Text(
                                        'Memuat data type...',
                                        style: TextStyle(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  )
                                : _typeList.isEmpty
                                ? Center(
                                    child: CircularProgressIndicator(
                                      color: AppTheme.primary,
                                    ),
                                  )
                                : DropdownButtonFormField<String>(
                                    initialValue: _selectedType,
                                    dropdownColor: colorScheme.surfaceContainerHighest,
                                    style: TextStyle(color: colorScheme.onSurface),
                                    decoration: InputDecoration(
                                      hintText: 'Pilih Type Mobil',
                                      hintStyle: TextStyle(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                      filled: true,
                                      fillColor: colorScheme.surfaceContainerHighest,
                                      border: OutlineInputBorder(
                                        borderSide: BorderSide(
                                          color: colorScheme.outline,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderSide: BorderSide(
                                          color: colorScheme.outline,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderSide: BorderSide(
                                          color: AppTheme.primary,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                    items: _typeList.map((type) {
                                    return DropdownMenuItem(
                                      value: type,
                                      child: Text(
                                        type,
                                        style: TextStyle(
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                    );
                                    }).toList(),
                                    onChanged: (value) {
                                      if (value != null &&
                                          _selectedMerek != null) {
                                        setState(() {
                                          _selectedType = value;
                                        });
                                        _setJumlahPenumpang(
                                          _selectedMerek!,
                                          value,
                                        );
                                      }
                                    },
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Type kendaraan wajib dipilih';
                                      }
                                      return null;
                                    },
                                  ),
                            const SizedBox(height: 24),
                          ],

                          // Jumlah Penumpang - muncul jika type sudah dipilih
                          if (_selectedType != null &&
                              _selectedType!.isNotEmpty) ...[
                            Text(
                              'Jumlah Penumpang',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: colorScheme.outline.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: colorScheme.outline),
                              ),
                              child: Text(
                                _jumlahPenumpang != null
                                    ? '$_jumlahPenumpang Penumpang'
                                    : 'Memuat jumlah penumpang...',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],

                          // Tombol Simpan
                          FilledButton(
                            onPressed: _isLoading ? null : _saveVehicleData,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: AppTheme.primary,
                              foregroundColor: AppTheme.onPrimary,
                            ),
                            child: _isLoading
                                ? SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppTheme.onPrimary,
                                    ),
                                  )
                                : const Text(
                                    'Simpan Data Kendaraan',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
