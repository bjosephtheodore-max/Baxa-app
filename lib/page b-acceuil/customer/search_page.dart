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
  Timer? _debounce;
  String searchText = "";

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      setState(() {
        searchText = _searchController.text.trim();
        // lance ici la requête Firestore filtrée par searchText
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Pas de flèche de retour pour les onglets bottom bar
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 75, 139, 94),
        title: const Text(
          'Recherche',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ✅ Champ de recherche
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: "Tapez le nom de la structure...",
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  searchText = value.trim();
                });
              },
            ),
            const SizedBox(height: 24),

            // ✅ Liste des résultats
            Expanded(
              child: searchText.isEmpty
                  ? const Center(
                      child: Text(
                        "Entrez un nom pour rechercher une entreprise",
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection("entreprises")
                          .where("nom", isGreaterThanOrEqualTo: searchText)
                          .where(
                            "nom",
                            isLessThanOrEqualTo: "$searchText\uf8ff",
                          )
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return const Center(
                            child: Text("Aucune entreprise trouvée"),
                          );
                        }

                        // ✅ Affichage des résultats cliquables
                        return ListView(
                          children: snapshot.data!.docs.map((doc) {
                            final entreprise =
                                doc.data() as Map<String, dynamic>;
                            return ListTile(
                              title: Text(entreprise["nom"]),
                              subtitle: Text(entreprise["email"]),
                              onTap: () {
                                // 👉 Action quand on clique sur une entreprise
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      "Tu as cliqué sur ${entreprise["nom"]}",
                                    ),
                                  ),
                                );
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => CompanyQueuePage(
                                      entrepriseId: doc.id,
                                      entrepriseNom: entreprise["nom"],
                                    ),
                                  ),
                                );
                              },
                            );
                          }).toList(),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
