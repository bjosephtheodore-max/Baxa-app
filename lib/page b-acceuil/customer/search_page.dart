import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:baxa/page%20b-acceuil/customer/companyqueue_page.dart';
import 'package:baxa/page%20b-acceuil/customer/signine_page.dart';
import 'package:baxa/page%20b-acceuil/customer/slots_page.dart';
import 'package:baxa/services/favorites_service.dart';
import 'package:baxa/services/geo_address_service.dart';
import 'package:baxa/services/locale_service.dart';
import 'package:baxa/services/location_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart' hide GeoPoint;
import 'package:shared_preferences/shared_preferences.dart';

part 'search_logic.dart';
part 'search_dialogs.dart';
part 'search_widgets.dart';
part 'search_qr_scanner.dart';

// ── Palette (niveau bibliothèque — accessible dans tous les parts) ────────────
const Color _green = Color(0xFF4B8B5E);
const Color _greenLight = Color(0xFFE8F5ED);
const Color _greenMid = Color(0xFFB2D3C2);
const Color _dark = Color(0xFF1E2D23);
const String _locationPromptCountKeyPrefix = 'location_prompt_count_';

class SearchPage extends StatefulWidget {
  final bool openScanner;
  const SearchPage({super.key, this.openScanner = false});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounce;
  String searchText = '';
  String? typeSelectionne;

  Set<String> _favoriteIds = {};

  String? _pendingFavoriteId;
  String? _pendingFavoriteName;
  String? _pendingFavoriteType;

  // Historique de structures visitées : {id, nom, type, ville, visitedAt}
  List<Map<String, dynamic>> _recentCompanies = [];
  bool _historyLoaded = false;
  static const String _cacheKeyPrefix = 'recent_companies_';

  late Stream<QuerySnapshot> _entreprisesStream;

  // Empêche un double/triple tap sur une carte de déclencher plusieurs
  // navigations en parallèle (chacune finirait par empiler sa propre page
  // de créneaux une fois sa requête résolue) — un seul tap "gagne" à la fois.
  bool _isOpeningCompany = false;

  // ── Géolocalisation ────────────────────────────────────────────────────────
  final LocationService _locationService = LocationService();
  Position? _userPosition;
  bool _locationPromptAttempted = false;
  bool _locationRefreshing = false;
  StreamSubscription<ServiceStatus>? _serviceStatusSub;

  // Pays du client (code ISO majuscules) : sert à ne montrer que les
  // structures du même pays. Priorité : GPS live > `country` du doc
  // `users` (fixé à l'inscription, déjà affiné par GPS) > locale du
  // téléphone (repli initial).
  String? _userCountryCode = LocaleService.countryCode?.toUpperCase();
  bool _countryResolvedFromGps = false;

  final List<String> typesEntreprises = [
    'Tous',
    'Banque',
    'Commerce',
    'Administration',
    'Médical',
    'Restaurant',
    'Autre',
  ];

  // ── Clés des chips de filtre — pour les recentrer au tap ─────────────────
  final GlobalKey _nearbyChipKey = GlobalKey();
  late final Map<String, GlobalKey> _typeChipKeys = {
    for (final t in typesEntreprises) t: GlobalKey(),
  };

  // Fait défiler la ligne de chips pour amener le chip tapé au centre —
  // révèle naturellement qu'on peut scroller vers les chips hors champ,
  // sans jamais dépasser les bords (Scrollable.ensureVisible s'en charge).
  void _centerChip(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  void initState() {
    super.initState();
    _entreprisesStream = _getEntreprisesStream();
    _searchController.addListener(_onSearchChanged);
    _loadFavoriteIds();
    _loadRecentCompanies();
    _loadUserCountry();
    _initLocation();
    // Réagit en direct au GPS pendant que le client est déjà sur cette
    // page (comme Google Maps) : activation → récupère la position sans
    // qu'il ait besoin de quitter puis rouvrir la page ; désactivation →
    // revient à l'état initial (icône grise, plus de distance affichée)
    // plutôt que de garder une position qui n'est plus à jour.
    _serviceStatusSub = Geolocator.getServiceStatusStream().listen((status) {
      if (status == ServiceStatus.enabled && _userPosition == null) {
        _initLocation();
      } else if (status == ServiceStatus.disabled && _userPosition != null) {
        setState(() => _userPosition = null);
      }
    });
    if (widget.openScanner) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openQrScanner());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _serviceStatusSub?.cancel();
    super.dispose();
  }

  // ── Localisation ──────────────────────────────────────────────────────────
  // Vérification silencieuse : si la permission est déjà accordée (activée
  // précédemment) et le GPS allumé, on récupère la position tout de suite,
  // sans aucune sollicitation visible pour le client.
  Future<void> _initLocation() async {
    final permission = await _locationService.checkPermission();
    if (permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse) {
      final pos = await _locationService.getCurrentPosition();
      if (pos != null) _setUserPosition(pos);
    }
  }

  // Déclenchement manuel (icône dans l'en-tête) : demande la permission si
  // besoin, montre un indicateur de chargement pendant la récupération, et
  // explique clairement l'échec (GPS éteint vs permission refusée) plutôt
  // que de rester silencieux.
  Future<void> _refreshLocation() async {
    if (_locationRefreshing) return;
    setState(() => _locationRefreshing = true);

    final pos = await _locationService.getCurrentPosition();
    if (!mounted) return;

    if (pos != null) {
      setState(() {
        _userPosition = pos;
        _locationRefreshing = false;
      });
      _updateCountryFromPosition(pos);
      return;
    }

    final serviceOn = await _locationService.isServiceEnabled();
    if (!mounted) return;
    setState(() => _locationRefreshing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          serviceOn
              ? 'Autorisez Baxa à utiliser votre localisation pour repérer '
                    'les établissements les plus proches de vous — ça se '
                    'passe dans les réglages du téléphone.'
              : 'Activez la localisation de votre téléphone pour repérer '
                    'en un instant les établissements les plus proches de vous.',
        ),
        backgroundColor: Colors.grey.shade800,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // Point d'entrée unique pour mettre à jour la position connue —
  // appelable depuis les extensions (search_dialogs.dart) sans jamais
  // toucher directement à `setState`, qui est @protected sur `State`
  // et donc inaccessible depuis une extension.
  void _setUserPosition(Position pos) {
    if (mounted) setState(() => _userPosition = pos);
    _updateCountryFromPosition(pos);
  }

  // Pays enregistré sur le doc `users` (fixé à l'inscription, déjà affiné
  // GPS). Sert de défaut sans redemander aucune permission ici. N'écrase
  // pas une valeur déjà obtenue du GPS live pendant cette session.
  Future<void> _loadUserCountry() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final code = (snap.data()?['country'] as String?)?.toUpperCase();
      if (code != null &&
          code.isNotEmpty &&
          code != 'XX' &&
          !_countryResolvedFromGps &&
          code != _userCountryCode &&
          mounted) {
        setState(() => _userCountryCode = code);
      }
    } catch (_) {}
  }

  // Affine le pays du client à partir de sa position réelle (le GPS prime
  // sur la locale du téléphone et sur le doc `users`, car il peut ne pas
  // correspondre au pays où l'utilisateur se trouve). Silencieux.
  Future<void> _updateCountryFromPosition(Position pos) async {
    final geo = await GeoAddressService().fromCoordinates(
      pos.latitude,
      pos.longitude,
    );
    final code = geo?.countryCode;
    if (code == null || code.isEmpty) return;
    _countryResolvedFromGps = true;
    if (code != _userCountryCode && mounted) {
      setState(() => _userCountryCode = code);
    }
  }

  // Idem : point d'entrée non-protected pour fixer le texte de recherche
  // depuis les extensions (ex. tap sur la carte "Voir les structures à X").
  void _setSearchText(String value) {
    _searchController.text = value;
    if (mounted) setState(() => searchText = value);
  }

  // ── Favoris ───────────────────────────────────────────────────────────────
  Future<void> _loadFavoriteIds() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('favorites')
          .get();
      if (mounted) {
        setState(() => _favoriteIds = snap.docs.map((d) => d.id).toSet());
      }
    } catch (_) {}
  }

  // ── Historique de structures visitées ────────────────────────────────────
  Future<void> _loadRecentCompanies() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _historyLoaded = true);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final cacheKey = '$_cacheKeyPrefix${user.uid}';

    // 1. Chargement du cache local d'abord (instantané)
    final cached = prefs.getString(cacheKey);
    if (cached != null && mounted) {
      try {
        final list = (jsonDecode(cached) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        setState(() {
          _recentCompanies = list;
          _historyLoaded = true;
        });
      } catch (_) {}
    }

    // 2. Sync Firestore en arrière-plan
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('recentCompanies')
          .orderBy('visitedAt', descending: true)
          .limit(15)
          .get();

      final list = snap.docs.map((d) {
        final data = d.data();
        return {
          'id': d.id,
          'nom': data['nom'] ?? '',
          'type': data['type'] ?? '',
          'ville': data['ville'] ?? '',
          'visitedAt':
              (data['visitedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0,
        };
      }).toList();

      await prefs.setString(cacheKey, jsonEncode(list));
      if (mounted) {
        setState(() {
          _recentCompanies = list;
          _historyLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _historyLoaded = true);
    }
  }

  Future<void> _recordVisit({
    required String companyId,
    required String nom,
    String? type,
    String? ville,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final entry = {
      'id': companyId,
      'nom': nom,
      'type': type ?? '',
      'ville': ville ?? '',
      'visitedAt': DateTime.now().millisecondsSinceEpoch,
    };

    final updated = [
      entry,
      ..._recentCompanies.where((e) => e['id'] != companyId),
    ];
    if (updated.length > 15) updated.removeLast();

    if (mounted) setState(() => _recentCompanies = updated);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_cacheKeyPrefix${user.uid}', jsonEncode(updated));

    FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('recentCompanies')
        .doc(companyId)
        .set({
          'nom': nom,
          'type': type ?? '',
          'ville': ville ?? '',
          'visitedAt': FieldValue.serverTimestamp(),
          'companyId': companyId,
        })
        .catchError((_) {});
  }

  Future<void> _clearRecentCompanies() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (mounted) setState(() => _recentCompanies = []);

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_cacheKeyPrefix${user.uid}');

    FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('recentCompanies')
        .get()
        .then((snap) {
          if (snap.docs.isEmpty) return;
          final batch = FirebaseFirestore.instance.batch();
          for (final doc in snap.docs) {
            batch.delete(doc.reference);
          }
          batch.commit();
        })
        .catchError((_) {});
  }

  // ── Recherche ─────────────────────────────────────────────────────────────
  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() => searchText = _searchController.text.trim());

      // Première recherche effectuée sans position connue : on propose au
      // client d'activer sa localisation pour affiner ses résultats.
      if (searchText.isNotEmpty &&
          _userPosition == null &&
          !_locationPromptAttempted) {
        _locationPromptAttempted = true;
        _maybeShowLocationPrompt();
      }
    });
  }

  // ── Navigation vers une entreprise (skip si 1 seule file) ────────────────
  Future<void> _navigateToCompany(String companyId, String nom) async {
    if (_isOpeningCompany) return;
    _isOpeningCompany = true;

    // LOG TEMPORAIRE DE DIAGNOSTIC — à retirer une fois la cause trouvée.
    final tapAt = DateTime.now();
    debugPrint('🔎[NAV] tap "$nom" ($companyId) @ $tapAt');

    try {
      final queuesSnap = await FirebaseFirestore.instance
          .collection('companies')
          .doc(companyId)
          .collection('queues')
          .orderBy('createdAt')
          .get();

      debugPrint(
        '🔎[NAV] queuesSnap "$nom" reçu après '
        '${DateTime.now().difference(tapAt).inMilliseconds}ms '
        '(fromCache=${queuesSnap.metadata.isFromCache})',
      );

      if (!mounted) return;

      if (queuesSnap.docs.length == 1) {
        final queueDoc = queuesSnap.docs.first;
        final queueData = queueDoc.data();
        debugPrint(
          '🔎[NAV] push SlotsPage "$nom" @ '
          '+${DateTime.now().difference(tapAt).inMilliseconds}ms',
        );
        SlotsPage.prefetch(companyId, queueDoc.id);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SlotsPage.fromQueueData(
              companyId: companyId,
              queueId: queueDoc.id,
              queueData: queueData,
              entrepriseNom: nom,
              primaryGreen: _green,
              lightGreen: _greenMid,
              onReservationSuccess: () {},
            ),
          ),
        );
      } else {
        debugPrint(
          '🔎[NAV] push CompanyQueuePage "$nom" @ '
          '+${DateTime.now().difference(tapAt).inMilliseconds}ms',
        );
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                CompanyQueuePage(entrepriseId: companyId, entrepriseNom: nom),
          ),
        );
      }
    } catch (e) {
      debugPrint(
        '🔎[NAV] erreur "$nom" @ '
        '+${DateTime.now().difference(tapAt).inMilliseconds}ms: $e',
      );
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                CompanyQueuePage(entrepriseId: companyId, entrepriseNom: nom),
          ),
        );
      }
    } finally {
      _isOpeningCompany = false;
    }
  }

  // ── Scanner QR ────────────────────────────────────────────────────────────
  Future<void> _openQrScanner() async {
    unawaited(
      FirebaseAnalytics.instance.logEvent(
        name: 'ui_interaction',
        parameters: {'widget_name': 'qr_scan_icon'},
      ),
    );
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _QrScannerPage(
          onScanned: (companyId, companyNom, type, ville) {
            _recordVisit(
              companyId: companyId,
              nom: companyNom,
              type: type,
              ville: ville,
            );
            Navigator.pop(context);
            _navigateToCompany(companyId, companyNom);
          },
        ),
      ),
    );
  }

  Future<void> _toggleFavorite({
    required String companyId,
    required String nom,
    required String? type,
    required bool isFav,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('favorites')
        .doc(companyId);

    try {
      if (isFav) {
        await ref.delete();
        setState(() => _favoriteIds.remove(companyId));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$nom retiré des favoris'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.grey.shade700,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      } else {
        await FavoritesService.addFavorite(
          companyId: companyId,
          nom: nom,
          type: type,
        );
        setState(() => _favoriteIds.add(companyId));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$nom ajouté aux favoris ⭐'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: _green,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F7F4),
      body: Column(
        children: [
          _buildHeader(),
          _buildFilters(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _entreprisesStream,
              builder: (ctx, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting ||
                    !_historyLoaded) {
                  return _buildSkeleton();
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return _buildEmptyState(
                    icon: Icons.business_outlined,
                    title: 'Aucune structure',
                    subtitle: 'Aucune structure inscrite pour le moment',
                  );
                }

                final myCountry = _userCountryCode;
                final docs = snapshot.data!.docs.where((d) {
                  final data = d.data() as Map<String, dynamic>;
                  if (data['status'] == 'deleted') return false;

                  // Filtre pays : n'exclut une structure que si son pays
                  // ET celui du client sont connus et différents. Une
                  // structure sans pays défini (anciennes inscriptions)
                  // reste visible partout — compatibilité ascendante.
                  final comp = (data['country'] as String?)?.toUpperCase();
                  if (myCountry != null &&
                      myCountry.isNotEmpty &&
                      myCountry != 'XX' &&
                      comp != null &&
                      comp.isNotEmpty &&
                      comp != 'XX' &&
                      comp != myCountry) {
                    return false;
                  }
                  return true;
                }).toList();
                if (docs.isEmpty) {
                  return _buildEmptyState(
                    icon: Icons.business_outlined,
                    title: 'Aucune structure',
                    subtitle: 'Aucune structure inscrite pour le moment',
                  );
                }
                return searchText.isEmpty
                    ? _buildDefaultState(docs)
                    : _buildSearchResults(docs);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 12, 12),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Color(0xFF1A1C2E)),
                onPressed: () => Navigator.pop(context),
              ),
              Expanded(
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      Icon(
                        Icons.search_rounded,
                        color: Colors.grey.shade400,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          autofocus: !widget.openScanner,
                          decoration: InputDecoration(
                            hintText:
                                typeSelectionne != null &&
                                    typeSelectionne != 'Tous'
                                ? 'Dans $typeSelectionne...'
                                : 'Nom ou ville d\'une structure',
                            hintStyle: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          style: const TextStyle(
                            fontSize: 15,
                            color: Color(0xFF1A1C2E),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (searchText.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            if (mounted) setState(() => searchText = '');
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Icon(
                              Icons.close_rounded,
                              color: Colors.grey.shade400,
                              size: 18,
                            ),
                          ),
                        )
                      else
                        GestureDetector(
                          onTap: _openQrScanner,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Icon(
                              Icons.qr_code_scanner_rounded,
                              color: _green,
                              size: 24,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 50,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  _buildNearbyChip(),
                  ...typesEntreprises.map((type) {
                    final isSelected =
                        typeSelectionne == type ||
                        (typeSelectionne == null && type == 'Tous');
                    return GestureDetector(
                      key: _typeChipKeys[type],
                      onTap: () {
                        if (mounted) {
                          setState(() {
                            typeSelectionne = type == 'Tous' ? null : type;
                            _entreprisesStream = _getEntreprisesStream();
                          });
                        }
                        _centerChip(_typeChipKeys[type]!);
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected ? _green : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected ? _green : Colors.grey.shade200,
                          ),
                        ),
                        child: Text(
                          type,
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFF1A1C2E),
                            fontSize: 13,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: Colors.grey.shade100),
        ],
      ),
    );
  }

  // Chip "À proximité" — regroupe ce que faisait l'icône de localisation de
  // l'ancienne en-tête : déclenche/rafraîchit la position d'un tap, et son
  // état (vert/gris) reflète si le tri par distance est actif ou non.
  Widget _buildNearbyChip() {
    final isActive = _userPosition != null;
    return GestureDetector(
      key: _nearbyChipKey,
      onTap: _locationRefreshing
          ? null
          : () {
              _centerChip(_nearbyChipKey);
              _refreshLocation();
            },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? _green : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isActive ? _green : Colors.grey.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_locationRefreshing)
              SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: isActive ? Colors.white : _green,
                ),
              )
            else
              Icon(
                isActive
                    ? Icons.my_location_rounded
                    : Icons.location_on_outlined,
                size: 15,
                color: isActive ? Colors.white : Colors.grey.shade500,
              ),
            const SizedBox(width: 6),
            Text(
              'À proximité',
              style: TextStyle(
                color: isActive ? Colors.white : const Color(0xFF1A1C2E),
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── État vide : historique + populaires (30 max) ──────────────────────────
  Widget _buildDefaultState(List<DocumentSnapshot> allDocs) {
    final allDocMap = {for (final d in allDocs) d.id: d};

    final historyDocs = _recentCompanies
        .where((e) => allDocMap.containsKey(e['id'] as String))
        // On garde une structure fermée dans l'historique (avec sa mention —
        // utile pour savoir quand elle rouvre), mais pas une structure sans
        // aucune file.
        .where(
          (e) => !_companyHasNoQueue(
            allDocMap[e['id'] as String]!.data() as Map<String, dynamic>,
          ),
        )
        .take(15)
        .toList();
    final historyIds = historyDocs.map((e) => e['id'] as String).toSet();

    final remaining = 30 - historyDocs.length;
    final popularDocs = _getDiversePopular(allDocs, historyIds, remaining);

    final List<Widget> items = [];

    // Carte QR scan — uniquement si pas d'historique
    if (historyDocs.isEmpty) {
      items.add(_buildQrInvitationCard());
    }

    // Section historique
    if (historyDocs.isNotEmpty) {
      items.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              Icon(
                Icons.history_rounded,
                size: 14,
                color: Colors.grey.shade500,
              ),
              const SizedBox(width: 6),
              Text(
                'Récemment visités',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _clearRecentCompanies,
                child: Text(
                  'Tout effacer',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade400,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      for (int i = 0; i < historyDocs.length; i++) {
        final entry = historyDocs[i];
        final doc = allDocMap[entry['id'] as String]!;
        final data = doc.data() as Map<String, dynamic>;
        items.add(
          _buildAnimatedCard(
            _buildCompanyCard(
              doc: doc,
              nom: data['nom'] ?? 'Sans nom',
              type: data['type'] as String?,
              ville: data['ville'] as String?,
              isHistory: true,
            ),
            i,
            uniqueKey: 'hist-${doc.id}',
          ),
        );
      }
    }

    // Section populaires
    if (popularDocs.isNotEmpty) {
      items.add(
        Padding(
          padding: EdgeInsets.fromLTRB(16, historyDocs.isEmpty ? 14 : 8, 16, 8),
          child: Row(
            children: [
              Icon(
                Icons.trending_up_rounded,
                size: 14,
                color: Colors.grey.shade500,
              ),
              const SizedBox(width: 6),
              Text(
                historyDocs.isEmpty ? 'Populaires' : 'Autres structures',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      );
      for (int i = 0; i < popularDocs.length; i++) {
        final doc = popularDocs[i];
        final data = doc.data() as Map<String, dynamic>;
        items.add(
          _buildAnimatedCard(
            _buildCompanyCard(
              doc: doc,
              nom: data['nom'] ?? 'Sans nom',
              type: data['type'] as String?,
              ville: data['ville'] as String?,
            ),
            historyDocs.length + i,
            uniqueKey: 'pop-${doc.id}',
          ),
        );
      }
    }

    if (items.isEmpty) {
      return _buildEmptyState(
        icon: Icons.business_outlined,
        title: 'Aucune structure',
        subtitle: 'Aucune structure inscrite pour le moment',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 24),
      children: items,
    );
  }

  // ── Résultats de recherche ────────────────────────────────────────────────
  Widget _buildSearchResults(List<DocumentSnapshot> docs) {
    final detectedCity = _detectCity(docs, searchText);

    var scored =
        docs
            .map((d) {
              final data = d.data() as Map<String, dynamic>;
              var score = _scoreMatch(data, searchText);

              // Filtre strict par ville si une ville est détectée dans la saisie
              if (detectedCity != null && score > 0) {
                final ville = _normalize(data['ville'] as String? ?? '');
                final cityNorm = _normalize(detectedCity);
                if (!ville.contains(cityNorm)) score = 0.0;
              }

              return (doc: d, score: score);
            })
            .where((item) => item.score > 0)
            .toList()
          ..sort((a, b) {
            // Rétrograde doucement les fermées / sans file, sans écraser une
            // correspondance de nom forte.
            final sa =
                a.score -
                _searchStatePenalty(a.doc.data() as Map<String, dynamic>);
            final sb =
                b.score -
                _searchStatePenalty(b.doc.data() as Map<String, dynamic>);
            return sb.compareTo(sa);
          });

    if (scored.length > 30) scored = scored.sublist(0, 30);

    if (scored.isEmpty) {
      return Column(
        children: [
          if (detectedCity != null) _buildCitySuggestionCard(detectedCity),
          Expanded(
            child: _buildEmptyState(
              icon: Icons.search_off,
              title: 'Aucun résultat',
              subtitle:
                  'Aucune structure trouvée pour "$searchText".\n'
                  'Vérifiez l\'orthographe ou essayez un autre mot.',
            ),
          ),
        ],
      );
    }

    final hasCityCard = detectedCity != null;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 24),
      itemCount: scored.length + (hasCityCard ? 1 : 0),
      itemBuilder: (_, i) {
        if (hasCityCard && i == 0) {
          return _buildCitySuggestionCard(detectedCity);
        }
        final offset = hasCityCard ? 1 : 0;
        final item = scored[i - offset];
        final data = item.doc.data() as Map<String, dynamic>;
        return _buildAnimatedCard(
          _buildCompanyCard(
            doc: item.doc,
            nom: data['nom'] ?? 'Sans nom',
            type: data['type'] as String?,
            ville: data['ville'] as String?,
          ),
          i,
          uniqueKey: '$searchText-${item.doc.id}',
        );
      },
    );
  }
}
