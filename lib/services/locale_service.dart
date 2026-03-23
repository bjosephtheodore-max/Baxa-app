import 'dart:ui';

/// Service de détection automatique du pays/langue
/// Basé uniquement sur le locale du téléphone — aucune API externe
class LocaleService {
  static final Locale _locale = PlatformDispatcher.instance.locale;

  /// Code pays ex: "SN", "CI", "CM" — null si non détecté
  static String? get countryCode => _locale.countryCode;

  /// Code langue ex: "fr", "en"
  static String get languageCode => _locale.languageCode;

  /// Locale complet ex: "fr_SN"
  static String get localeString =>
      '${_locale.languageCode}_${_locale.countryCode ?? 'XX'}';

  /// Nom complet du pays détecté
  static String get countryName {
    switch (countryCode) {
      case 'SN':
        return 'Sénégal';
      case 'CI':
        return 'Côte d\'Ivoire';
      case 'CM':
        return 'Cameroun';
      case 'ML':
        return 'Mali';
      case 'BF':
        return 'Burkina Faso';
      case 'GN':
        return 'Guinée';
      case 'TG':
        return 'Togo';
      case 'BJ':
        return 'Bénin';
      case 'NE':
        return 'Niger';
      case 'MR':
        return 'Mauritanie';
      case 'GA':
        return 'Gabon';
      case 'CG':
        return 'Congo';
      case 'CD':
        return 'RD Congo';
      case 'MA':
        return 'Maroc';
      case 'DZ':
        return 'Algérie';
      case 'TN':
        return 'Tunisie';
      default:
        return countryCode ?? 'Inconnu';
    }
  }

  /// Villes du pays détecté — liste vide si pays non supporté
  static List<String> get villes {
    switch (countryCode) {
      case 'SN':
        return [
          'Dakar',
          'Saint-Louis',
          'Thiès',
          'Ziguinchor',
          'Kaolack',
          'Mbour',
          'Touba',
          'Diourbel',
          'Louga',
          'Tambacounda',
          'Kolda',
          'Fatick',
          'Sédhiou',
          'Kédougou',
          'Matam',
        ];
      case 'CI':
        return [
          'Abidjan',
          'Bouaké',
          'Daloa',
          'San-Pédro',
          'Yamoussoukro',
          'Korhogo',
          'Man',
          'Gagnoa',
          'Divo',
          'Abengourou',
        ];
      case 'CM':
        return [
          'Douala',
          'Yaoundé',
          'Bafoussam',
          'Garoua',
          'Bamenda',
          'Maroua',
          'Ngaoundéré',
          'Bertoua',
          'Ebolowa',
          'Kumba',
        ];
      case 'ML':
        return [
          'Bamako',
          'Sikasso',
          'Ségou',
          'Mopti',
          'Koutiala',
          'Kayes',
          'Gao',
          'Kidal',
          'Tombouctou',
        ];
      case 'BF':
        return [
          'Ouagadougou',
          'Bobo-Dioulasso',
          'Koudougou',
          'Ouahigouya',
          'Banfora',
          'Dédougou',
          'Fada N\'Gourma',
        ];
      case 'GN':
        return [
          'Conakry',
          'Nzérékoré',
          'Kankan',
          'Kindia',
          'Labé',
          'Siguiri',
          'Guéckédou',
        ];
      case 'TG':
        return [
          'Lomé',
          'Sokodé',
          'Kara',
          'Kpalimé',
          'Atakpamé',
          'Dapaong',
          'Tsévié',
        ];
      case 'BJ':
        return [
          'Cotonou',
          'Porto-Novo',
          'Parakou',
          'Djougou',
          'Bohicon',
          'Abomey',
          'Natitingou',
        ];
      case 'NE':
        return [
          'Niamey',
          'Zinder',
          'Maradi',
          'Agadez',
          'Tahoua',
          'Dosso',
          'Diffa',
        ];
      case 'MR':
        return ['Nouakchott', 'Nouadhibou', 'Rosso', 'Kaédi', 'Zouerate'];
      case 'GA':
        return ['Libreville', 'Port-Gentil', 'Franceville', 'Oyem', 'Moanda'];
      case 'CG':
        return ['Brazzaville', 'Pointe-Noire', 'Dolisie', 'Nkayi', 'Impfondo'];
      case 'CD':
        return [
          'Kinshasa',
          'Lubumbashi',
          'Mbuji-Mayi',
          'Kisangani',
          'Goma',
          'Bukavu',
          'Kananga',
        ];
      case 'MA':
        return [
          'Casablanca',
          'Rabat',
          'Fès',
          'Marrakech',
          'Tanger',
          'Agadir',
          'Meknès',
          'Oujda',
        ];
      case 'DZ':
        return [
          'Alger',
          'Oran',
          'Constantine',
          'Annaba',
          'Blida',
          'Sétif',
          'Tlemcen',
        ];
      case 'TN':
        return [
          'Tunis',
          'Sfax',
          'Sousse',
          'Gabès',
          'Bizerte',
          'Kairouan',
          'Monastir',
        ];
      default:
        return []; // Pays non supporté → champ libre
    }
  }

  /// Le pays est-il supporté (liste de villes disponible) ?
  static bool get isPaysSupporte => villes.isNotEmpty;

  /// Map complète pour Firestore
  static Map<String, dynamic> toFirestoreMap() => {
    'country': countryCode ?? 'XX',
    'language': languageCode,
    'locale': localeString,
  };
}
