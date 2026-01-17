import 'package:flutter/material.dart';
import 'package:baxa/page%20b-acceuil/customer/search_page.dart';
import 'package:baxa/page%20b-acceuil/customer/persona_page.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';

class HousePage extends StatefulWidget {
  const HousePage({super.key});
  @override
  State<HousePage> createState() => _HousePageState();
}

class _HousePageState extends State<HousePage> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final green = const Color.fromARGB(255, 70, 142, 91);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        // pas de flèche de retour si utilisé dans une bottom nav
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                // Top block (hero)
                Container(
                  width: double.infinity,
                  height: size.height * 0.32,
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + 12,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        green.withOpacity(0.95),
                        green.withOpacity(0.78),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(24),
                      bottomRight: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Top row: logo
                      Align(
                        alignment: Alignment.topCenter,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Spacer(flex: 5),
                            Text(
                              "Baxa",
                              textAlign: TextAlign.center,
                              style: GoogleFonts.pacifico(
                                color: Colors.white,
                                fontSize: 40,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            const Spacer(flex: 3),

                            CircleAvatar(
                              radius: 20,
                              backgroundColor: Colors.white24,
                              foregroundColor: Colors.white,
                              child: IconButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => PersonaPage(),
                                    ),
                                  );
                                },
                                icon: Icon(Icons.person),
                              ),
                            ),
                            const Spacer(flex: 1),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      // Title
                      Text(
                        'Réserver une place',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 5),
                      // Subtitle / helper
                      Text(
                        "Trouvez une structure et réservez votre tour rapidement",
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white70,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const Spacer(),

                      // Search button
                      SizedBox(
                        height: 48,
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SearchPage(),
                            ),
                          ),
                          icon: const Icon(Icons.search),
                          label: const Text('Rechercher'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: green,
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 70,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Prochains rendez-vous (placeholder)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Prochains rendez‑vous',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: green.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.event_available,
                                  color: green,
                                  size: 30,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: const [
                                    Text(
                                      "Aucun rendez‑vous pour l'instant",
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    SizedBox(height: 6),
                                    Text(
                                      "Votre historique et vos réservations récentes apparaîtront ici.",
                                      style: TextStyle(color: Colors.black54),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Favoris (placeholder horizontal list)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Favoris',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 110,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: 5,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 12),
                          padding: EdgeInsets.zero,
                          itemBuilder: (context, index) {
                            return Container(
                              width: 220,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 6,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 24,
                                    backgroundColor: green.withOpacity(0.12),
                                    child: Icon(Icons.store, color: green),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: const [
                                        Text(
                                          "Aucun favori",
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        SizedBox(height: 6),
                                        Text(
                                          "Ajoutez des entreprises à vos favoris pour les retrouver facilement.",
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.black54,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                // Intro / decorative area when empty
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    children: [
                      Icon(
                        Icons.queue_music,
                        size: 64,
                        color: green.withOpacity(0.18),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Baxa vous aide à gérer vos files d’attente. Recherchez une structure, réservez une place, et recevez une notification quand c’est votre tour.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.black54,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
