import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

class _ReminderOption {
  final int minutes;
  final String label;
  const _ReminderOption(this.minutes, this.label);
}

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  static const Color _green = Color(0xFF4B8B5E);
  static const Color _bgColor = Color(0xFFF6F8FA);
  static const Color _dark = Color(0xFF1A1C2E);

  // Une liste différente par pilier (pas une liste commune) : les 3 ne se
  // chevauchent jamais, donc deux rappels ne peuvent jamais tomber sur la
  // même valeur — pas besoin de vérifier les doublons entre eux.
  static const List<List<_ReminderOption>> _pillarOptions = [
    [
      _ReminderOption(1440, '24 heures'),
      _ReminderOption(720, '12 heures'),
      _ReminderOption(360, '6 heures'),
      _ReminderOption(180, '3 heures'),
    ],
    [
      _ReminderOption(120, '2 heures'),
      _ReminderOption(60, '1 heure'),
      _ReminderOption(30, '30 minutes'),
    ],
    [_ReminderOption(15, '15 minutes'), _ReminderOption(5, '5 minutes')],
  ];

  static const List<int> _defaultOffsets = [1440, 60, 15];

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? _uid;
  bool _isLoading = true;
  List<int> _offsets = List.of(_defaultOffsets);
  int? _expandedIndex;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
    _load();
  }

  Future<void> _load() async {
    if (_uid == null) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      final doc = await _firestore.collection('users').doc(_uid).get();
      final raw = (doc.data()?['reminderOffsets'] as List?)?.cast<num>();
      if (mounted) {
        setState(() {
          if (raw != null && raw.length == 3) {
            final candidate = raw.map((n) => n.toInt()).toList();
            // On ignore une config enregistrée qui ne respecterait plus les
            // listes par pilier actuelles (ex. réglage fait avant cette
            // refonte) — retombe simplement sur les valeurs par défaut.
            final valid = List.generate(
              3,
              (i) => _pillarOptions[i].any((o) => o.minutes == candidate[i]),
            ).every((ok) => ok);
            if (valid) _offsets = candidate;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectOption(int pillarIndex, int minutes) async {
    if (_uid == null) return;
    final previous = List<int>.of(_offsets);
    setState(() {
      _offsets[pillarIndex] = minutes;
      _expandedIndex = null; // se referme automatiquement après le choix
    });

    try {
      await _firestore.collection('users').doc(_uid).set({
        'reminderOffsets': _offsets,
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Préférences mises à jour'),
            backgroundColor: _green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _offsets = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _shortLabel(int minutes) {
    if (minutes % 60 == 0) return '${minutes ~/ 60}h';
    return '${minutes}min';
  }

  void _toggleColumn(int index) {
    setState(() => _expandedIndex = _expandedIndex == index ? null : index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.black87,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Rappels de réservation',
          style: GoogleFonts.poppins(
            color: Colors.black87,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Choisis un délai pour chacun des 3 rappels avant ton créneau.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            for (var i = 0; i < 3; i++) ...[
                              if (i > 0) const SizedBox(width: 10),
                              Expanded(child: _buildColumnHeader(i)),
                            ],
                          ],
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                          alignment: Alignment.topCenter,
                          child: _expandedIndex == null
                              ? const SizedBox(width: double.infinity)
                              : Padding(
                                  padding: const EdgeInsets.only(top: 14),
                                  child: _buildOptionsPanel(_expandedIndex!),
                                ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Un changement ne s\'applique qu\'aux prochaines réservations — pas à celles déjà en cours.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildColumnHeader(int index) {
    final isOpen = _expandedIndex == index;
    final currentLabel = _shortLabel(_offsets[index]);

    return InkWell(
      onTap: () => _toggleColumn(index),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isOpen
              ? _green.withValues(alpha: 0.08)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isOpen ? _green : Colors.grey.shade200,
            width: isOpen ? 1.4 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              Icons.alarm_rounded,
              color: isOpen ? _green : Colors.grey.shade500,
              size: 18,
            ),
            const SizedBox(height: 6),
            Text(
              'Rappel ${index + 1}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              currentLabel,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: isOpen ? _green : _dark,
              ),
            ),
            const SizedBox(height: 2),
            Icon(
              isOpen
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionsPanel(int pillarIndex) {
    final options = _pillarOptions[pillarIndex];
    final selected = _offsets[pillarIndex];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _green.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: options.map((o) {
          final isSelected = o.minutes == selected;
          return ChoiceChip(
            label: Text(o.label),
            selected: isSelected,
            showCheckmark: false,
            onSelected: (_) => _selectOption(pillarIndex, o.minutes),
            selectedColor: _green,
            backgroundColor: Colors.white,
            labelStyle: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isSelected ? Colors.white : _dark,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: isSelected ? _green : Colors.grey.shade300,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
