import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:baxa/page%20b-acceuil/customer/companyqueue_page.dart';
import 'package:flutter/material.dart';
import 'dart:async';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounce;
  String searchText = "";
  String? typeSelectionne;

  final List<String> typesEntreprises = [
    'Tous',
    'Banque',
    'Restaurant',
    'Commerce',
    'Administration',
    'Autre',
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    // Auto-focus sur le champ de recherche
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          searchText = _searchController.text.trim();
        });
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  bool _matchesSearch(String nomEntreprise, String searchQuery) {
    if (searchQuery.isEmpty) return true;

    final nom = nomEntreprise.toLowerCase();
    final query = searchQuery.toLowerCase();

    return nom.startsWith(query) ||
        nom.contains(query) ||
        nom.split(' ').any((word) => word.startsWith(query));
  }

  Stream<QuerySnapshot> _getEntreprisesStream() {
    Query query = FirebaseFirestore.instance.collection("Entreprises");

    if (typeSelectionne != null && typeSelectionne != 'Tous') {
      query = query.where("type", isEqualTo: typeSelectionne);
    }

    return query.snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color.fromARGB(255, 75, 139, 94),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Rechercher',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ),
      body: Column(
        children: [
          // En-tête avec champ de recherche
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              children: [
                // Champ de recherche amélioré
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _searchFocusNode.hasFocus
                          ? const Color.fromARGB(255, 75, 139, 94)
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    decoration: InputDecoration(
                      prefixIcon: Icon(
                        Icons.search,
                        color: Colors.grey.shade600,
                      ),
                      hintText:
                          typeSelectionne != null && typeSelectionne != 'Tous'
                          ? "Rechercher dans $typeSelectionne..."
                          : "Nom de l'entreprise, lieu...",
                      hintStyle: TextStyle(color: Colors.grey.shade500),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      suffixIcon: searchText.isNotEmpty
                          ? IconButton(
                              icon: Icon(
                                Icons.clear,
                                color: Colors.grey.shade600,
                              ),
                              onPressed: () {
                                _searchController.clear();
                                if (mounted) {
                                  setState(() {
                                    searchText = "";
                                  });
                                }
                              },
                            )
                          : null,
                    ),
                  ),
                ),

                // Compteur de résultats
                if (searchText.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: StreamBuilder<QuerySnapshot>(
                      stream: _getEntreprisesStream(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const SizedBox.shrink();

                        final filtered = snapshot.data!.docs.where((doc) {
                          final entreprise = doc.data() as Map<String, dynamic>;
                          final nom = entreprise["nom"] ?? "";
                          return _matchesSearch(nom, searchText);
                        }).length;

                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '$filtered résultat${filtered > 1 ? 's' : ''} trouvé${filtered > 1 ? 's' : ''}',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // Barre de filtres horizontale
          Container(
            height: 56,
            color: Colors.white,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              physics: const BouncingScrollPhysics(),
              itemCount: typesEntreprises.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final type = typesEntreprises[index];
                final isSelected =
                    typeSelectionne == type ||
                    (typeSelectionne == null && type == 'Tous');

                return FilterChip(
                  selected: isSelected,
                  label: Text(type),
                  onSelected: (selected) {
                    if (mounted) {
                      setState(() {
                        typeSelectionne = type == 'Tous' ? null : type;
                      });
                    }
                  },
                  backgroundColor: Colors.white,
                  selectedColor: const Color.fromARGB(255, 178, 211, 194),
                  labelStyle: TextStyle(
                    color: isSelected
                        ? const Color.fromARGB(255, 75, 139, 94)
                        : Colors.black87,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                    fontSize: 13,
                  ),
                  side: BorderSide(
                    color: isSelected
                        ? const Color.fromARGB(255, 75, 139, 94)
                        : Colors.grey.shade300,
                    width: isSelected ? 1.5 : 1,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                );
              },
            ),
          ),

          const Divider(height: 1),

          // Liste des résultats
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _getEntreprisesStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: Color.fromARGB(255, 75, 139, 94),
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return _buildEmptyState(
                    icon: Icons.business_outlined,
                    title: "Aucune entreprise",
                    subtitle:
                        typeSelectionne != null && typeSelectionne != 'Tous'
                        ? "Aucun(e) $typeSelectionne trouvé(e)"
                        : "Aucune entreprise n'est encore inscrite",
                  );
                }

                final allDocs = snapshot.data!.docs;
                final filteredDocs = allDocs.where((doc) {
                  final entreprise = doc.data() as Map<String, dynamic>;
                  final nom = entreprise["nom"] ?? "";
                  return _matchesSearch(nom, searchText);
                }).toList();

                if (filteredDocs.isEmpty) {
                  return _buildEmptyState(
                    icon: Icons.search_off,
                    title: "Aucun résultat",
                    subtitle: searchText.isNotEmpty
                        ? "Aucune entreprise trouvée pour \"$searchText\""
                        : "Sélectionnez un type ou tapez un nom",
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: filteredDocs.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1, indent: 72),
                  itemBuilder: (context, index) {
                    final doc = filteredDocs[index];
                    final entreprise = doc.data() as Map<String, dynamic>;
                    final nom = entreprise["nom"] ?? "Sans nom";
                    final type = entreprise["type"];
                    final email = entreprise["email"];

                    return _buildCompanyCard(
                      doc: doc,
                      nom: nom,
                      type: type,
                      email: email,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompanyCard({
    required DocumentSnapshot doc,
    required String nom,
    String? type,
    String? email,
  }) {
    // Mise en évidence du texte recherché
    Widget titleWidget = _buildHighlightedText(nom);

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  CompanyQueuePage(entrepriseId: doc.id, entrepriseNom: nom),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Avatar avec initiale
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color.fromARGB(255, 75, 139, 94),
                      Color.fromARGB(255, 95, 159, 114),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    nom.isNotEmpty ? nom[0].toUpperCase() : "?",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 16),

              // Informations
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleWidget,
                    const SizedBox(height: 4),
                    if (type != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color.fromARGB(
                            255,
                            178,
                            211,
                            194,
                          ).withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          type,
                          style: const TextStyle(
                            color: Color.fromARGB(255, 75, 139, 94),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (email != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        email,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),

              // Icône flèche
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color.fromARGB(
                    255,
                    178,
                    211,
                    194,
                  ).withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: Color.fromARGB(255, 75, 139, 94),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHighlightedText(String nom) {
    if (searchText.isEmpty ||
        !nom.toLowerCase().contains(searchText.toLowerCase())) {
      return Text(
        nom,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 16,
          color: Colors.black87,
        ),
      );
    }

    final startIndex = nom.toLowerCase().indexOf(searchText.toLowerCase());
    final endIndex = startIndex + searchText.length;

    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 16,
          color: Colors.black87,
        ),
        children: [
          TextSpan(text: nom.substring(0, startIndex)),
          TextSpan(
            text: nom.substring(startIndex, endIndex),
            style: const TextStyle(
              backgroundColor: Color.fromARGB(255, 255, 235, 59),
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(text: nom.substring(endIndex)),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color.fromARGB(
                  255,
                  178,
                  211,
                  194,
                ).withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 64, color: Colors.grey.shade400),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
