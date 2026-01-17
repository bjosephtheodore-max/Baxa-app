import 'package:baxa/services/firebase/auth.dart';
import 'package:flutter/material.dart';

class PersonaPage extends StatelessWidget {
  const PersonaPage({super.key});

  Future<void> _confirmAndLogout(BuildContext context) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Se déconnecter'),
        content: const Text('Êtes-vous sûr de vouloir vous déconnecter ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Déconnexion'),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      try {
        await Auth().logout(); // ta logique existante
        // replace '/login' with the route name of your login screen if different:
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Déconnecté avec succès')));
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la déconnexion : $e')),
        );
      }
    }
  }

  Widget _buildTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        leading: Icon(icon, color: Colors.teal.shade700, size: 28),
        title: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final headerBg = const Color.fromARGB(255, 75, 139, 94);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: headerBg,
        title: const Text(
          'Profil',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            children: [
              // --- Header profil (avatar + nom + email) ---
              Row(
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.person, size: 40, color: headerBg),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Nom Prénom',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'email@example.com',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      // TODO: replace with "edit profile" navigation
                    },
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Modifier'),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // --- Menu list ---
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        'Compte',
                        style: TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _buildTile(
                      context: context,
                      icon: Icons.person_outline,
                      title: 'Profil',
                      onTap: () {
                        // ouvrir page profil détaillé
                      },
                    ),
                    _buildTile(
                      context: context,
                      icon: Icons.search,
                      title: 'Historique des recherches',
                      onTap: () {
                        // ouvrir historique
                      },
                    ),
                    const SizedBox(height: 12),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        'Paramètres',
                        style: TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _buildTile(
                      context: context,
                      icon: Icons.notifications_none,
                      title: 'Notifications',
                      onTap: () {
                        // ouvrir notifications settings
                      },
                    ),
                    _buildTile(
                      context: context,
                      icon: Icons.rate_review_outlined,
                      title: 'Avis',
                      onTap: () {
                        // ouvrir avis
                      },
                    ),
                    _buildTile(
                      context: context,
                      icon: Icons.help_outline,
                      title: 'Aide',
                      onTap: () {
                        // ouvrir aide
                      },
                    ),
                  ],
                ),
              ),

              // --- Déconnexion ---
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => _confirmAndLogout(context),
                  child: const Text(
                    'Se déconnecter',
                    style: TextStyle(fontSize: 16, color: Colors.white),
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
