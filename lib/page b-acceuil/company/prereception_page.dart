import 'package:baxa/page%20b-acceuil/company/signin_page.dart';
import 'package:flutter/material.dart';

class PrereceptionPage extends StatefulWidget {
  const PrereceptionPage({super.key});

  @override
  State<PrereceptionPage> createState() => _PrereceptionPageState();
}

class _PrereceptionPageState extends State<PrereceptionPage> {
  final _formKey = GlobalKey<FormState>();
  final _nomEntrepriseController = TextEditingController();
  final _autreTypeController = TextEditingController();

  String? _typeEntrepriseSelectionne;
  bool _afficherChampAutre = false;

  final List<String> _typesEntreprises = [
    'Banque',
    'Restaurant',
    'Commerce',
    'Administration',
    'Autre',
  ];

  @override
  void dispose() {
    _nomEntrepriseController.dispose();
    _autreTypeController.dispose();
    super.dispose();
  }

  void _continuer() {
    if (_formKey.currentState!.validate()) {
      // Déterminer le type final
      String typeFinal = _afficherChampAutre
          ? _autreTypeController.text.trim()
          : _typeEntrepriseSelectionne ?? '';

      // Naviguer vers la page d'inscription avec les données
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SigninPage(
            nomEntreprise: _nomEntrepriseController.text.trim(),
            typeEntreprise: typeFinal,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Icône et titre
                  Container(
                    padding: const EdgeInsets.all(20),
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
                      Icons.business_outlined,
                      size: 60,
                      color: Color.fromARGB(255, 75, 139, 94),
                    ),
                  ),

                  const SizedBox(height: 24),

                  const Text(
                    'Bienvenue sur Baxa',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'Parlez-nous de votre entreprise',
                    style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
                  ),

                  const SizedBox(height: 40),

                  // Formulaire
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Champ Nom de l'entreprise
                          TextFormField(
                            controller: _nomEntrepriseController,
                            textCapitalization: TextCapitalization.words,
                            decoration: InputDecoration(
                              labelText: 'Nom de l\'entreprise',
                              hintText: 'Ex: Restaurant Chez Marie',
                              prefixIcon: const Icon(Icons.store_outlined),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Le nom de l\'entreprise est obligatoire';
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 20),

                          // Dropdown Type d'entreprise
                          DropdownButtonFormField<String>(
                            value: _typeEntrepriseSelectionne,
                            decoration: InputDecoration(
                              labelText: 'Type d\'entreprise',
                              hintText: 'Sélectionnez le type',
                              prefixIcon: const Icon(Icons.category_outlined),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                            ),
                            items: _typesEntreprises.map((String type) {
                              return DropdownMenuItem<String>(
                                value: type,
                                child: Text(type),
                              );
                            }).toList(),
                            onChanged: (String? nouvelleValeur) {
                              setState(() {
                                _typeEntrepriseSelectionne = nouvelleValeur;
                                _afficherChampAutre = nouvelleValeur == 'Autre';

                                if (!_afficherChampAutre) {
                                  _autreTypeController.clear();
                                }
                              });
                            },
                            validator: (value) {
                              if (value == null) {
                                return 'Veuillez sélectionner un type d\'entreprise';
                              }
                              if (value == 'Autre' &&
                                  _autreTypeController.text.trim().isEmpty) {
                                return 'Veuillez préciser le type';
                              }
                              return null;
                            },
                          ),

                          // Champ "Autre" si sélectionné
                          if (_afficherChampAutre) ...[
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _autreTypeController,
                              textCapitalization: TextCapitalization.words,
                              decoration: InputDecoration(
                                labelText: 'Précisez le type',
                                hintText: 'Ex: Hôtel, École, Salon de coiffure',
                                prefixIcon: const Icon(Icons.edit_outlined),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: Colors.grey.shade50,
                              ),
                              validator: (value) {
                                if (_afficherChampAutre &&
                                    (value == null || value.trim().isEmpty)) {
                                  return 'Veuillez préciser le type d\'entreprise';
                                }
                                return null;
                              },
                            ),
                          ],

                          const SizedBox(height: 8),

                          // Texte informatif
                          Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 16,
                                color: Colors.grey.shade500,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Ces informations nous permettent de mieux adapter Baxa à vos besoins',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Bouton Suivant
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _continuer,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color.fromARGB(255, 75, 139, 94),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Text(
                            'Suivant',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward, size: 20),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
