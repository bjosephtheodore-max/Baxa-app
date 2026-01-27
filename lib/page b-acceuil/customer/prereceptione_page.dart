import 'package:baxa/page%20b-acceuil/customer/signine_page.dart';
import 'package:flutter/material.dart';

class PrereceptionePage extends StatefulWidget {
  const PrereceptionePage({super.key});

  @override
  State<PrereceptionePage> createState() => _PrereceptionePageState();
}

class _PrereceptionePageState extends State<PrereceptionePage> {
  final _formKey = GlobalKey<FormState>();
  final _nomController = TextEditingController();
  final _prenomController = TextEditingController();
  final _professionController = TextEditingController();

  @override
  void dispose() {
    _nomController.dispose();
    _prenomController.dispose();
    _professionController.dispose();
    super.dispose();
  }

  void _continuer() {
    if (_formKey.currentState!.validate()) {
      // Naviguer vers la page d'inscription avec les données
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SigninePage(
            nom: _nomController.text.trim(),
            prenom: _prenomController.text.trim(),
            profession: _professionController.text.trim(),
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
                      Icons.person_add_outlined,
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
                    'Commençons par faire connaissance',
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
                          // Champ Nom
                          TextFormField(
                            controller: _nomController,
                            textCapitalization: TextCapitalization.words,
                            decoration: InputDecoration(
                              labelText: 'Nom',
                              hintText: 'Votre nom de famille',
                              prefixIcon: const Icon(Icons.person_outline),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Le nom est obligatoire';
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 20),

                          // Champ Prénom
                          TextFormField(
                            controller: _prenomController,
                            textCapitalization: TextCapitalization.words,
                            decoration: InputDecoration(
                              labelText: 'Prénom',
                              hintText: 'Votre prénom',
                              prefixIcon: const Icon(Icons.badge_outlined),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Le prénom est obligatoire';
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 20),

                          // Champ Profession (optionnel)
                          TextFormField(
                            controller: _professionController,
                            textCapitalization: TextCapitalization.words,
                            decoration: InputDecoration(
                              labelText: 'Profession (optionnel)',
                              hintText: 'Ex: Étudiant, Employé, etc.',
                              prefixIcon: const Icon(Icons.work_outline),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                            ),
                          ),

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
                                  'Ces informations nous aident à personnaliser votre expérience',
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
