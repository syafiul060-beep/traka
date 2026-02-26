/// Model untuk data kendaraan dan daftar merek/type mobil di Indonesia
class VehicleModel {
  /// Daftar merek mobil populer di Indonesia
  static const List<String> merekMobilIndonesia = [
    'Toyota',
    'Honda',
    'Daihatsu',
    'Suzuki',
    'Mitsubishi',
    'Nissan',
    'Hyundai',
    'Wuling',
    'KIA',
    'Mazda',
    'Isuzu',
    'Mercedes-Benz',
    'BMW',
    'Audi',
    'Volkswagen',
    'Ford',
    'Chevrolet',
    'Datsun',
  ];

  /// Type umum: mobil pribadi (model spesifik) + microbus/minibus
  static const String typeMicrobus = 'Microbus (Minibus)';

  /// Mapping type mobil berdasarkan merek (mobil pribadi + microbus/minibus)
  static Map<String, List<String>> get typeByMerek => {
    'Toyota': [
      'Avanza',
      'Innova',
      'Fortuner',
      'Rush',
      'Alphard',
      'Camry',
      'Corolla',
      'Yaris',
      'Vios',
      'Sienta',
      'Hiace',
      typeMicrobus,
    ],
    'Honda': [
      'Brio',
      'Mobilio',
      'BR-V',
      'HR-V',
      'CR-V',
      'Pilot',
      'Civic',
      'Accord',
      'City',
      'Odyssey',
      typeMicrobus,
    ],
    'Daihatsu': [
      'Ayla',
      'Sigra',
      'Terios',
      'Xenia',
      'Luxio',
      'Gran Max',
      typeMicrobus,
    ],
    'Suzuki': ['Ertiga', 'XL7', 'SX4', 'APV', 'Carry', 'Jimny', typeMicrobus],
    'Mitsubishi': [
      'Xpander',
      'Pajero Sport',
      'Triton',
      'Outlander',
      'Eclipse Cross',
      typeMicrobus,
    ],
    'Nissan': [
      'Livina',
      'Grand Livina',
      'X-Trail',
      'Navara',
      'Serena',
      typeMicrobus,
    ],
    'Hyundai': ['Creta', 'Santa Fe', 'Tucson', 'Palisade', typeMicrobus],
    'Wuling': ['Cortez', 'Almaz', 'Confero', typeMicrobus],
    'KIA': ['Seltos', 'Sportage', 'Sorento', typeMicrobus],
    'Mazda': ['CX-5', 'CX-8', 'CX-3', typeMicrobus],
    'Isuzu': ['Panther', 'MU-X', 'D-Max', typeMicrobus],
    'Mercedes-Benz': [
      'C-Class',
      'E-Class',
      'S-Class',
      'GLC',
      'GLE',
      typeMicrobus,
    ],
    'BMW': ['3 Series', '5 Series', 'X1', 'X3', 'X5', typeMicrobus],
    'Audi': ['A3', 'A4', 'Q3', 'Q5', typeMicrobus],
    'Volkswagen': ['Polo', 'Tiguan', 'Touareg', typeMicrobus],
    'Ford': ['Ranger', 'Everest', 'EcoSport', typeMicrobus],
    'Chevrolet': ['Trailblazer', 'Captiva', typeMicrobus],
    'Datsun': ['GO', 'GO+', typeMicrobus],
  };

  /// Mapping jumlah penumpang berdasarkan merek dan type (termasuk Microbus)
  static Map<String, Map<String, int>> get jumlahPenumpangByMerekType => {
    'Toyota': {
      'Avanza': 7,
      'Innova': 7,
      'Fortuner': 7,
      'Rush': 7,
      'Alphard': 7,
      'Camry': 5,
      'Corolla': 5,
      'Yaris': 5,
      'Vios': 5,
      'Sienta': 7,
      'Hiace': 15,
      typeMicrobus: 12,
    },
    'Honda': {
      'Brio': 5,
      'Mobilio': 7,
      'BR-V': 7,
      'HR-V': 5,
      'CR-V': 5,
      'Pilot': 7,
      'Civic': 5,
      'Accord': 5,
      'City': 5,
      'Odyssey': 7,
      typeMicrobus: 12,
    },
    'Daihatsu': {
      'Ayla': 5,
      'Sigra': 7,
      'Terios': 7,
      'Xenia': 7,
      'Luxio': 7,
      'Gran Max': 8,
      typeMicrobus: 12,
    },
    'Suzuki': {
      'Ertiga': 7,
      'XL7': 7,
      'SX4': 5,
      'APV': 7,
      'Carry': 8,
      'Jimny': 4,
      typeMicrobus: 12,
    },
    'Mitsubishi': {
      'Xpander': 7,
      'Pajero Sport': 7,
      'Triton': 5,
      'Outlander': 7,
      'Eclipse Cross': 5,
      typeMicrobus: 12,
    },
    'Nissan': {
      'Livina': 7,
      'Grand Livina': 7,
      'X-Trail': 5,
      'Navara': 5,
      'Serena': 7,
      typeMicrobus: 12,
    },
    'Hyundai': {
      'Creta': 5,
      'Santa Fe': 7,
      'Tucson': 5,
      'Palisade': 7,
      typeMicrobus: 12,
    },
    'Wuling': {'Cortez': 7, 'Almaz': 7, 'Confero': 7, typeMicrobus: 12},
    'KIA': {'Seltos': 5, 'Sportage': 5, 'Sorento': 7, typeMicrobus: 12},
    'Mazda': {'CX-5': 5, 'CX-8': 7, 'CX-3': 5, typeMicrobus: 12},
    'Isuzu': {'Panther': 7, 'MU-X': 7, 'D-Max': 5, typeMicrobus: 12},
    'Mercedes-Benz': {
      'C-Class': 5,
      'E-Class': 5,
      'S-Class': 5,
      'GLC': 5,
      'GLE': 7,
      typeMicrobus: 12,
    },
    'BMW': {
      '3 Series': 5,
      '5 Series': 5,
      'X1': 5,
      'X3': 5,
      'X5': 7,
      typeMicrobus: 12,
    },
    'Audi': {'A3': 5, 'A4': 5, 'Q3': 5, 'Q5': 5, typeMicrobus: 12},
    'Volkswagen': {'Polo': 5, 'Tiguan': 5, 'Touareg': 7, typeMicrobus: 12},
    'Ford': {'Ranger': 5, 'Everest': 7, 'EcoSport': 5, typeMicrobus: 12},
    'Chevrolet': {'Trailblazer': 7, 'Captiva': 7, typeMicrobus: 12},
    'Datsun': {'GO': 5, 'GO+': 7, typeMicrobus: 12},
  };

  /// Mendapatkan daftar type berdasarkan merek
  static List<String> getTypeByMerek(String merek) {
    return typeByMerek[merek] ?? [];
  }

  /// Mendapatkan jumlah penumpang berdasarkan merek dan type
  static int? getJumlahPenumpang(String merek, String type) {
    return jumlahPenumpangByMerekType[merek]?[type];
  }
}
