import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class SettingsPage extends StatefulWidget {
  final String companyId;
  final String queueId;

  const SettingsPage({
    super.key,
    required this.companyId,
    required this.queueId,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _nameCtrl = TextEditingController();
  // weekdays 1=Mon ... 7=Sun
  List<bool> _selectedDays = List.filled(7, true);

  @override
  void initState() {
    super.initState();
    _loadQueue();
  }

  Future<void> _loadQueue() async {
    final doc = await _firestore
        .collection('companies')
        .doc(widget.companyId)
        .collection('queues')
        .doc(widget.queueId)
        .get();

    if (!doc.exists) return;
    final data = doc.data();
    if (data == null) return;
    setState(() {
      _nameCtrl.text = (data['name'] as String?) ?? '';
      final days = (data['weekdays'] as List<dynamic>?)
          ?.map((e) => (e as int))
          .toList();
      if (days != null) {
        _selectedDays = List.filled(7, false);
        for (final d in days) {
          if (d >= 1 && d <= 7) _selectedDays[d - 1] = true;
        }
      }
    });
  }

  Future<void> _saveQueueSettings() async {
    final weekdays = <int>[];
    for (int i = 0; i < 7; i++) {
      if (_selectedDays[i]) weekdays.add(i + 1);
    }

    await _firestore
        .collection('companies')
        .doc(widget.companyId)
        .collection('queues')
        .doc(widget.queueId)
        .set({
          'name': _nameCtrl.text.trim(),
          'weekdays': weekdays,
        }, SetOptions(merge: true));

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Paramètres sauvegardés')));
  }

  String _formatTimeOfDay(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _showSlotDialog({DocumentSnapshot? doc}) async {
    TimeOfDay? start = TimeOfDay(hour: 9, minute: 0);
    TimeOfDay? end = TimeOfDay(hour: 12, minute: 0);
    final svcCtrl = TextEditingController(text: '10');
    final capCtrl = TextEditingController(text: '1');
    final maxPerDayCtrl = TextEditingController(text: '1');
    final deadlineCtrl = TextEditingController(text: '0');
    final advanceCtrl = TextEditingController(text: '7');
    List<bool> slotDays = List.from(_selectedDays);

    if (doc != null) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data != null) {
        if (data['start'] is String) {
          final parts = (data['start'] as String).split(':');
          start = TimeOfDay(
            hour: int.parse(parts[0]),
            minute: int.parse(parts[1]),
          );
        }
        if (data['end'] is String) {
          final parts = (data['end'] as String).split(':');
          end = TimeOfDay(
            hour: int.parse(parts[0]),
            minute: int.parse(parts[1]),
          );
        }
        svcCtrl.text = (data['serviceDurationMinutes']?.toString() ?? '10');
        capCtrl.text = (data['capacity']?.toString() ?? '1');
        maxPerDayCtrl.text = (data['maxReservationsPerDay']?.toString() ?? '1');
        deadlineCtrl.text =
            (data['reservationDeadlineMinutes']?.toString() ?? '0');
        advanceCtrl.text = (data['maxAdvanceDays']?.toString() ?? '7');
        if (data['days'] is List) {
          slotDays = List.filled(7, false);
          for (final d in (data['days'] as List)) {
            if (d is int && d >= 1 && d <= 7) slotDays[d - 1] = true;
          }
        }
      }
    }

    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (ctx, setStateSB) {
          return AlertDialog(
            title: Text(
              doc == null ? 'Ajouter une plage horaire' : 'Modifier la plage',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () async {
                            final t = await showTimePicker(
                              context: ctx,
                              initialTime: start!,
                            );
                            if (t != null) setStateSB(() => start = t);
                          },
                          child: Text('Début: ${_formatTimeOfDay(start!)}'),
                        ),
                      ),
                      Expanded(
                        child: TextButton(
                          onPressed: () async {
                            final t = await showTimePicker(
                              context: ctx,
                              initialTime: end!,
                            );
                            if (t != null) setStateSB(() => end = t);
                          },
                          child: Text('Fin: ${_formatTimeOfDay(end!)}'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: svcCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Durée service (minutes)',
                    ),
                  ),
                  TextField(
                    controller: capCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Capacité par créneau',
                    ),
                  ),
                  TextField(
                    controller: maxPerDayCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Max réservations par jour (par personne)",
                    ),
                  ),
                  TextField(
                    controller: deadlineCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Délai réservation (minutes avant, défaut 0)',
                    ),
                  ),
                  TextField(
                    controller: advanceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Anticipation max (jours, défaut 7)",
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: List.generate(7, (i) {
                      final labels = [
                        'Lun',
                        'Mar',
                        'Mer',
                        'Jeu',
                        'Ven',
                        'Sam',
                        'Dim',
                      ];
                      return FilterChip(
                        selected: slotDays[i],
                        label: Text(labels[i]),
                        onSelected: (v) => setStateSB(() => slotDays[i] = v),
                      );
                    }),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final sd = int.tryParse(svcCtrl.text.trim()) ?? 10;
                  final cap = int.tryParse(capCtrl.text.trim()) ?? 1;
                  final maxPerDay =
                      int.tryParse(maxPerDayCtrl.text.trim()) ?? 1;
                  final deadline = int.tryParse(deadlineCtrl.text.trim()) ?? 0;
                  final advance = int.tryParse(advanceCtrl.text.trim()) ?? 7;

                  final daysList = <int>[];
                  for (int i = 0; i < 7; i++)
                    if (slotDays[i]) daysList.add(i + 1);

                  final payload = {
                    'start': _formatTimeOfDay(start!),
                    'end': _formatTimeOfDay(end!),
                    'serviceDurationMinutes': sd,
                    'capacity': cap,
                    'maxReservationsPerDay': maxPerDay,
                    'reservationDeadlineMinutes': deadline,
                    'maxAdvanceDays': advance,
                    'days': daysList,
                    'updatedAt': FieldValue.serverTimestamp(),
                  };

                  final col = _firestore
                      .collection('companies')
                      .doc(widget.companyId)
                      .collection('queues')
                      .doc(widget.queueId)
                      .collection('slots');

                  if (doc == null) {
                    await col.add(payload);
                  } else {
                    await col.doc(doc.id).set(payload, SetOptions(merge: true));
                  }

                  if (!mounted) return;
                  Navigator.pop(ctx);
                },
                child: const Text('Enregistrer'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteSlot(String slotId) async {
    await _firestore
        .collection('companies')
        .doc(widget.companyId)
        .collection('queues')
        .doc(widget.queueId)
        .collection('slots')
        .doc(slotId)
        .delete();
  }

  @override
  Widget build(BuildContext context) {
    final slotsRef = _firestore
        .collection('companies')
        .doc(widget.companyId)
        .collection('queues')
        .doc(widget.queueId)
        .collection('slots')
        .orderBy('start');

    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres de la file')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Nom de la file'),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: const Text('Jours réservables (par défaut tous)'),
            ),
            Wrap(
              spacing: 6,
              children: List.generate(7, (i) {
                final labels = [
                  'Lun',
                  'Mar',
                  'Mer',
                  'Jeu',
                  'Ven',
                  'Sam',
                  'Dim',
                ];
                return FilterChip(
                  selected: _selectedDays[i],
                  label: Text(labels[i]),
                  onSelected: (v) => setState(() => _selectedDays[i] = v),
                );
              }),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _saveQueueSettings,
              icon: const Icon(Icons.save),
              label: const Text('Sauvegarder paramètres de la file'),
            ),
            const SizedBox(height: 12),
            const Divider(),
            Align(
              alignment: Alignment.centerLeft,
              child: const Text(
                'Plages horaires',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: slotsRef.snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting)
                    return const Center(child: CircularProgressIndicator());
                  if (snap.hasError)
                    return Center(child: Text('Erreur: ${snap.error}'));
                  final docs = snap.data?.docs ?? [];
                  if (docs.isEmpty)
                    return const Center(
                      child: Text('Aucune plage horaire. Ajoutez-en une.'),
                    );

                  return ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, i) {
                      final d = docs[i];
                      final data = d.data() as Map<String, dynamic>?;
                      final start = (data?['start'] as String?) ?? '--';
                      final end = (data?['end'] as String?) ?? '--';
                      final cap = (data?['capacity']?.toString() ?? '');
                      final svc =
                          (data?['serviceDurationMinutes']?.toString() ?? '');
                      return ListTile(
                        title: Text('$start – $end'),
                        subtitle: Text('Durée: ${svc}min • Capacité: $cap'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: () => _showSlotDialog(doc: d),
                              icon: const Icon(Icons.edit),
                            ),
                            IconButton(
                              onPressed: () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (c) => AlertDialog(
                                    title: const Text('Supprimer la plage ?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(c, false),
                                        child: const Text('Annuler'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () => Navigator.pop(c, true),
                                        child: const Text('Supprimer'),
                                      ),
                                    ],
                                  ),
                                );
                                if (ok == true) await _deleteSlot(d.id);
                              },
                              icon: const Icon(Icons.delete),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () => _showSlotDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter une nouvelle plage horaire'),
            ),
          ],
        ),
      ),
    );
  }
}
