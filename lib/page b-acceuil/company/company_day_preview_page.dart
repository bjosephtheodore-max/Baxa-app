import 'dart:async';

import 'package:baxa/page%20b-acceuil/company/company_onboarding_page.dart';
import 'package:baxa/page%20b-acceuil/company/signin_page.dart';
import 'package:flutter/material.dart';

// ============================================================
// UNE JOURNÉE CHEZ [NOM] — dernier écran avant l'inscription
// ============================================================
// Animation en boucle construite avec l'apparence réelle de l'agenda
// (en-tête de file, tuiles de stats, cartes de créneaux) et personnalisée
// avec le nom saisi. Les valeurs du formulaire sont transmises telles
// quelles à SigninPage, comme le faisait PrereceptionPage auparavant.

const Color _green = Color(0xFF4B8B5E);
const Color _greenDark = Color(0xFF3F7A51);
const Color _dark = Color(0xFF1A2E1F);

class CompanyDayPreviewPage extends StatefulWidget {
  final String nomEntreprise;
  final String typeEntreprise;
  final String typeCategorie;
  final String ville;
  final String country;
  final String? language;
  final String? locale;

  const CompanyDayPreviewPage({
    super.key,
    required this.nomEntreprise,
    required this.typeEntreprise,
    required this.typeCategorie,
    required this.ville,
    required this.country,
    this.language,
    this.locale,
  });

  @override
  State<CompanyDayPreviewPage> createState() => _CompanyDayPreviewPageState();
}

class _CompanyDayPreviewPageState extends State<CompanyDayPreviewPage> {
  // 8 temps de 1,5 s : plage → créneaux → 3 réservations → notification →
  // résumé (2 temps), puis on recommence.
  static const int _ticks = 8;
  static const Duration _tick = Duration(milliseconds: 1500);

  Timer? _timer;
  int _t = 0;

  // Une administration reçoit des « usagers », les autres des « clients ».
  bool get _isAdministration => widget.typeCategorie == 'Administration';
  String get _people => _isAdministration ? 'usagers' : 'clients';
  String get _person => _isAdministration ? 'usager' : 'client';

  @override
  void initState() {
    super.initState();
    CompanyOnboarding.logStep('journee');
    _timer = Timer.periodic(_tick, (_) {
      if (mounted) setState(() => _t = (_t + 1) % _ticks);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _createAccount() {
    CompanyOnboarding.logStep('inscription');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SigninPage(
          nomEntreprise: widget.nomEntreprise,
          typeEntreprise: widget.typeEntreprise,
          typeCategorie: widget.typeCategorie,
          ville: widget.ville,
          country: widget.country,
          language: widget.language,
          locale: widget.locale,
        ),
      ),
    );
  }

  // t → étape affichée (0 à 4).
  int get _phase => const [0, 1, 2, 2, 2, 3, 4, 4][_t];

  // Réservations par créneau (2 places chacun) au fil de l'animation.
  List<int> get _perSlot => _t >= 4
      ? const [2, 2, 1]
      : _t == 3
      ? const [2, 1, 0]
      : _t == 2
      ? const [1, 0, 0]
      : const [0, 0, 0];

  @override
  Widget build(BuildContext context) {
    final captions = [
      '1 · Vous créez une plage',
      '2 · Elle se découpe en créneaux',
      '3 · Vos $_people réservent',
      '4 · Ils sont prévenus',
      '5 · Votre matinée est organisée',
    ];
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Retour',
                  icon: const Icon(
                    Icons.chevron_left_rounded,
                    color: _greenDark,
                    size: 30,
                  ),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Une journée chez ${widget.nomEntreprise}',
                      style: const TextStyle(
                        fontSize: 24,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        color: _dark,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Voici comment Baxa organise votre accueil.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      height: 456,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F7F5),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Progress(phase: _phase),
                          const SizedBox(height: 8),
                          Text(
                            captions[_phase],
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF2F5E3D),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: AnimatedSwitcher(
                              duration: reduceMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 420),
                              transitionBuilder: (child, anim) =>
                                  FadeTransition(
                                opacity: anim,
                                child: SlideTransition(
                                  position: Tween(
                                    begin: const Offset(0, 0.04),
                                    end: Offset.zero,
                                  ).animate(anim),
                                  child: child,
                                ),
                              ),
                              child: _buildStage(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _createAccount,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _greenDark,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Créer mon compte',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Une clé par « scène » : AnimatedSwitcher ne fond l'une dans l'autre que
  // lors d'un vrai changement de scène, pas à chaque réservation.
  Widget _buildStage() {
    if (_t == 0) {
      return const _PlageScene(key: ValueKey('plage'));
    }
    if (_t >= 6) {
      return const _SummaryScene(key: ValueKey('resume'));
    }
    return Stack(
      key: const ValueKey('agenda'),
      clipBehavior: Clip.none,
      children: [
        // Grand texte système : on coupe proprement le bas plutôt que de
        // déborder du cadre (le contenu reste illustratif).
        SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: _AgendaScene(name: widget.nomEntreprise, perSlot: _perSlot),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 40,
          child: AnimatedSlide(
            offset: _t == 5 ? Offset.zero : const Offset(0, -0.3),
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: _t == 5 ? 1 : 0,
              duration: const Duration(milliseconds: 300),
              child: _NotificationCard(
                person: _person,
                name: widget.nomEntreprise,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  final int phase;
  const _Progress({required this.phase});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < 5; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 5,
              decoration: BoxDecoration(
                color: i <= phase ? _greenDark : const Color(0xFFD5DED8),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Scène 1 : la plage ──────────────────────────────────────────────────────
class _PlageScene extends StatelessWidget {
  const _PlageScene({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: _dark.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 5, color: _green),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE4EFE7),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.schedule_rounded,
                                color: _greenDark,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'PLAGE HORAIRE',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF5B6660),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                Text(
                                  '08:00 → 12:00',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: _dark,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _Chip('15 min par créneau'),
                            _Chip('2 pers. par créneau'),
                            _Chip('Lun → Ven'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Réglée une seule fois. Baxa s\'occupe du reste.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  const _Chip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFE4EFE7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFF2F5E3D),
        ),
      ),
    );
  }
}

// ── Scènes 2-4 : l'agenda qui se remplit ────────────────────────────────────
class _AgendaScene extends StatelessWidget {
  final String name;
  final List<int> perSlot;

  const _AgendaScene({required this.name, required this.perSlot});

  static const _capacity = 32; // 16 créneaux × 2 places
  static const _times = ['08:00 – 08:15', '08:15 – 08:30', '08:30 – 08:45'];

  @override
  Widget build(BuildContext context) {
    final reserved = perSlot.fold<int>(0, (a, b) => a + b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: _dark.withValues(alpha: 0.06),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _dark,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F3EB),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(radius: 3.5, backgroundColor: _greenDark),
                        SizedBox(width: 6),
                        Text(
                          'Active',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2F5E3D),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _Stat(
                      value: reserved,
                      label: 'Réservées',
                      color: Colors.blue.shade600,
                      bg: Colors.blue.shade50,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Stat(
                      value: 0,
                      label: 'En attente',
                      color: Colors.grey.shade500,
                      bg: Colors.grey.shade100,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Stat(
                      value: _capacity - reserved,
                      label: 'Disponibles',
                      color: _green,
                      bg: const Color(0xFFECF7F0),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < _times.length; i++)
          _SlotCard(time: _times[i], reserved: perSlot[i], capacity: 2),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final int value;
  final String label;
  final Color color;
  final Color bg;

  const _Stat({
    required this.value,
    required this.label,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

// Même rendu que la carte de créneau de l'agenda (_SlotCard de
// house_widgets.dart) : libre / « X résa » / complet sur fond vert doux.
class _SlotCard extends StatelessWidget {
  final String time;
  final int reserved;
  final int capacity;

  const _SlotCard({
    required this.time,
    required this.reserved,
    required this.capacity,
  });

  @override
  Widget build(BuildContext context) {
    final isFull = reserved >= capacity;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isFull ? const Color(0xFFF4FAF6) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isFull ? Colors.transparent : Colors.grey.shade200,
          width: 1.5,
        ),
        boxShadow: isFull
            ? [
                BoxShadow(
                  color: _green.withValues(alpha: 0.13),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ]
            : const [],
      ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 350),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isFull
                  ? _green
                  : const Color(0xFFB2D3C2).withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isFull ? Icons.people : Icons.event_available,
              color: isFull ? Colors.white : _green,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  time,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _dark,
                  ),
                ),
                Text(
                  reserved == 0 ? 'Disponible' : '$reserved résa',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight:
                        reserved > 0 ? FontWeight.w500 : FontWeight.w400,
                    color: reserved > 0
                        ? _green.withValues(alpha: 0.85)
                        : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          if (isFull)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: _green,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_rounded, size: 12, color: Colors.white),
                  SizedBox(width: 3),
                  Text(
                    'Complet',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final String person;
  final String name;

  const _NotificationCard({required this.person, required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: _dark.withValues(alpha: 0.22),
            blurRadius: 34,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _dark,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'VOTRE ${person.toUpperCase()} REÇOIT',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _greenDark,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.notifications_none_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'C\'est bientôt votre tour',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _dark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$name · votre passage est à 08:15.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Scène 5 : le résumé ─────────────────────────────────────────────────────
class _SummaryScene extends StatelessWidget {
  const _SummaryScene({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(
            color: _greenDark,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_rounded, color: Colors.white, size: 36),
        ),
        const SizedBox(height: 14),
        const Text(
          'Votre matinée est organisée',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: _dark,
          ),
        ),
        const SizedBox(height: 14),
        const Row(
          children: [
            Expanded(child: _SummaryStat(value: '16', label: 'créneaux')),
            SizedBox(width: 8),
            Expanded(child: _SummaryStat(value: '32', label: 'places')),
            SizedBox(width: 8),
            Expanded(child: _SummaryStat(value: '0', label: 'en file')),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'Chacun arrive à son heure.',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
        ),
      ],
    );
  }
}

class _SummaryStat extends StatelessWidget {
  final String value;
  final String label;

  const _SummaryStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF2F5E3D),
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
