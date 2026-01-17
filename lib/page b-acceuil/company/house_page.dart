import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:baxa/services/notifications/notification_service.dart';

class HousePage extends StatefulWidget {
  const HousePage({super.key});

  @override
  State<HousePage> createState() => _HousePageState();
}

class _HousePageState extends State<HousePage> {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final DateFormat _dateFmt = DateFormat('EEEE d MMM', 'fr_FR');
  final DateFormat _timeFmt = DateFormat('HH:mm');

  String? _companyId; // récupéré depuis FirebaseAuth
  DateTime _selectedDate = DateTime.now();

  // timeline config
  final int _startHour = 8;
  final int _endHour = 18;
  final double _pxPerMinute = 1.2; // ajustable : 72 px / heure

  // adaptive pixel density for small screens
  double get _effectivePxPerMinute {
    try {
      final w = MediaQuery.of(context).size.width;
      if (w < 360) return _pxPerMinute * 0.88;
      if (w < 420) return _pxPerMinute * 0.95;
    } catch (e) {
      // if called before build, fall back
    }
    return _pxPerMinute;
  }

  List<AgendaSlot> _slots = [];
  bool _loading = true;

  // computed layout and display helpers
  final Map<String, SlotLayout> _slotLayouts =
      {}; // slotId -> layout info (column index, columns count)
  final Map<String, String> _slotDisplayNames =
      {}; // slotId -> formatted name for single-capacity slots
  final Map<String, Color> _queueColors = {}; // cache queue color by id

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _companyId = user?.uid;
    _loadSlotsForDate(_selectedDate);
  }

  Future<void> _loadSlotsForDate(DateTime date) async {
    if (_companyId == null) return;
    setState(() => _loading = true);

    try {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      // Charger tous les créneaux de la company (toutes queues)
      final snap = await _fs
          .collection('companies')
          .doc(_companyId)
          .collection('queues')
          .get();

      final queues = snap.docs.map((d) => d.id).toList();
      final slots = <AgendaSlot>[];

      for (final qid in queues) {
        final s = await _fs
            .collection('companies')
            .doc(_companyId)
            .collection('queues')
            .doc(qid)
            .collection('slots')
            .where('start', isGreaterThanOrEqualTo: startOfDay)
            .where('start', isLessThan: endOfDay)
            .orderBy('start')
            .get();

        for (final doc in s.docs) {
          final data = doc.data();
          slots.add(AgendaSlot.fromMap(queueId: qid, id: doc.id, data: data));
        }
      }

      // trier par start
      slots.sort((a, b) => a.start.compareTo(b.start));

      // fetch display names for single-capacity reserved slots
      _slotDisplayNames.clear();
      _queueColors.clear();
      for (final slot in slots) {
        // cache color per queue
        _queueColors[slot.queueId] =
            _queueColors[slot.queueId] ?? _colorForQueue(slot.queueId);

        if (slot.capacity == 1 && slot.reserved > 0) {
          try {
            final resSnap = await _fs
                .collection('companies')
                .doc(_companyId)
                .collection('reservations')
                .where('slotId', isEqualTo: slot.id)
                .where('status', isEqualTo: 'confirmed')
                .limit(1)
                .get();

            if (resSnap.docs.isNotEmpty) {
              final r = resSnap.docs.first.data();
              final customerId = r['customerId'] as String?;
              final customerEmail = r['customerEmail'] as String?;
              String name = '';
              if (customerId != null) {
                final userDoc = await _fs
                    .collection('users')
                    .doc(customerId)
                    .get();
                if (userDoc.exists) {
                  final ud = userDoc.data() ?? {};
                  name =
                      (ud['displayName'] ??
                              ud['name'] ??
                              ud['prenom'] ??
                              ud['fullName'])
                          as String? ??
                      '';
                }
              }
              if (name.isEmpty && customerEmail != null) {
                name = customerEmail.split('@').first;
              }
              if (name.isNotEmpty) {
                _slotDisplayNames[slot.id] = _formatCustomerName(name);
              }
            }
          } catch (e) {
            debugPrint('Erreur fetch reservation name: $e');
          }
        }
      }

      // compute layout (columns for overlapping slots)
      _slotLayouts.clear();
      final layouts = _computeLayouts(slots);
      _slotLayouts.addAll(layouts);

      if (mounted)
        setState(() {
          _slots = slots;
        });
    } catch (e) {
      debugPrint('Erreur chargement agenda house_page: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur chargement agenda: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('fr'),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _loadSlotsForDate(picked);
    }
  }

  double _timeToOffset(DateTime t) {
    final dayStart = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _startHour,
    );
    final minutes = t.difference(dayStart).inMinutes;
    return minutes * _effectivePxPerMinute;
  }

  double _durationToHeight(DateTime start, DateTime end) {
    final minutes = end.difference(start).inMinutes;
    return minutes * _effectivePxPerMinute;
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'open':
        return Colors.green.withOpacity(0.15);
      case 'full':
        return Colors.red.withOpacity(0.15);
      case 'closed':
        return Colors.grey.withOpacity(0.12);
      default:
        return Colors.blue.withOpacity(0.12);
    }
  }

  @override
  Widget build(BuildContext context) {
    final companyName = 'Baxa';
    final timelineHeight = (_endHour - _startHour) * 60 * _pxPerMinute;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.calendar_month),
            const SizedBox(width: 8),
            Expanded(child: Text(companyName)),
            TextButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today, color: Colors.white70),
              label: Text(
                _dateFmt.format(_selectedDate),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF6FCF97),
        automaticallyImplyLeading: false,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Top indicators row
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Agenda',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Vue quotidienne — ${_dateFmt.format(_selectedDate)}',
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ],
                      ),
                      // placeholder for fill rate (calculable)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'Taux de remplissage',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _computeFillRateText(),
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    child: SizedBox(
                      height: timelineHeight,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Time labels
                          Container(
                            width: 72,
                            color: Colors.grey.shade50,
                            child: Column(
                              children: List.generate(
                                _endHour - _startHour + 1,
                                (i) {
                                  final hour = _startHour + i;
                                  return SizedBox(
                                    height: 60 * _pxPerMinute,
                                    child: Align(
                                      alignment: Alignment.topCenter,
                                      child: Text(
                                        '${hour.toString().padLeft(2, '0')}:00',
                                        style: const TextStyle(
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          // Timeline stack
                          Expanded(
                            child: Container(
                              color: Colors.white,
                              child: Stack(
                                children: [
                                  // hour lines
                                  ...List.generate(_endHour - _startHour + 1, (
                                    i,
                                  ) {
                                    final top = i * 60 * _pxPerMinute;
                                    return Positioned(
                                      top: top,
                                      left: 0,
                                      right: 0,
                                      child: Container(
                                        height: 1,
                                        color: Colors.grey.shade200,
                                      ),
                                    );
                                  }),

                                  // slots laid out in columns when overlapping
                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      final availableWidth =
                                          constraints.maxWidth - 24;
                                      final widgets = <Widget>[];
                                      for (final slot in _slots) {
                                        final top = _timeToOffset(slot.start);
                                        final height = _durationToHeight(
                                          slot.start,
                                          slot.end,
                                        ).clamp(28.0, timelineHeight);
                                        final layout = _slotLayouts[slot.id];
                                        final colIndex = layout?.colIndex ?? 0;
                                        final cols = layout?.cols ?? 1;
                                        final colWidth = availableWidth / cols;
                                        final leftPx =
                                            12 +
                                            colIndex * colWidth +
                                            6 * colIndex;
                                        final slotWidth = colWidth - 6;

                                        String displayText;
                                        if (slot.capacity == 1) {
                                          if (slot.reserved > 0) {
                                            displayText =
                                                _slotDisplayNames[slot.id] ??
                                                'Réservé';
                                          } else {
                                            displayText = 'Disponible';
                                          }
                                        } else {
                                          displayText =
                                              '${slot.reserved}/${slot.capacity}';
                                        }

                                        widgets.add(
                                          Positioned(
                                            top: top.clamp(
                                              0.0,
                                              timelineHeight - 20,
                                            ),
                                            left: leftPx,
                                            width: slotWidth,
                                            height: height,
                                            child: Semantics(
                                              label:
                                                  '${_timeFmt.format(slot.start)} — ${slot.queueName ?? ''}. ${displayText}',
                                              button: true,
                                              child: Tooltip(
                                                message:
                                                    '${_timeFmt.format(slot.start)} — ${slot.queueName ?? ''}\n$displayText',
                                                child: Material(
                                                  color: Colors.transparent,
                                                  child: InkWell(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                    onTap: () =>
                                                        _showSlotDetails(slot),
                                                    child: Container(
                                                      constraints:
                                                          const BoxConstraints(
                                                            minHeight: 48,
                                                          ),
                                                      padding:
                                                          const EdgeInsets.all(
                                                            8,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: _statusColor(
                                                          slot.status,
                                                        ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                        border: Border.all(
                                                          color: Colors
                                                              .grey
                                                              .shade200,
                                                        ),
                                                      ),
                                                      child: Row(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .stretch,
                                                        children: [
                                                          // left color stripe
                                                          Container(
                                                            width: 6,
                                                            margin:
                                                                const EdgeInsets.only(
                                                                  right: 8,
                                                                  top: 4,
                                                                  bottom: 4,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color:
                                                                  (_queueColors[slot
                                                                      .queueId] ??
                                                                  Colors.grey),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    4,
                                                                  ),
                                                            ),
                                                          ),
                                                          Expanded(
                                                            child: Column(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              mainAxisAlignment:
                                                                  MainAxisAlignment
                                                                      .center,
                                                              children: [
                                                                Text(
                                                                  '${_timeFmt.format(slot.start)} - ${_timeFmt.format(slot.end)}',
                                                                  style: Theme.of(context)
                                                                      .textTheme
                                                                      .bodyLarge
                                                                      ?.copyWith(
                                                                        fontWeight:
                                                                            FontWeight.bold,
                                                                      ),
                                                                ),
                                                                const SizedBox(
                                                                  height: 4,
                                                                ),
                                                                Text(
                                                                  displayText,
                                                                  style:
                                                                      Theme.of(
                                                                        context,
                                                                      ).textTheme.bodyMedium?.copyWith(
                                                                        fontSize:
                                                                            13,
                                                                      ),
                                                                  maxLines: 3,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            width: 8,
                                                          ),
                                                          Container(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal: 8,
                                                                  vertical: 6,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color: Colors
                                                                  .white
                                                                  .withOpacity(
                                                                    0.85,
                                                                  ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    6,
                                                                  ),
                                                            ),
                                                            child: Text(
                                                              '${slot.reserved}/${slot.capacity}',
                                                              style: const TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            width: 8,
                                                          ),
                                                          // queue badge
                                                          Container(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal: 6,
                                                                  vertical: 6,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color:
                                                                  (_queueColors[slot
                                                                              .queueId] ??
                                                                          Colors
                                                                              .grey)
                                                                      .withOpacity(
                                                                        0.95,
                                                                      ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    6,
                                                                  ),
                                                            ),
                                                            child: Text(
                                                              (slot.queueName ??
                                                                      slot.queueId)
                                                                  .split(' ')
                                                                  .map(
                                                                    (w) =>
                                                                        w.isNotEmpty
                                                                        ? w[0]
                                                                        : '',
                                                                  )
                                                                  .take(2)
                                                                  .join(),
                                                              style: const TextStyle(
                                                                color: Colors
                                                                    .white,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      }
                                      return Stack(children: widgets);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  String _computeFillRateText() {
    if (_slots.isEmpty) return '0% (0/0 places)';
    int totalPlaces = 0;
    int reserved = 0;
    for (final s in _slots) {
      totalPlaces += s.capacity;
      reserved += s.reserved;
    }
    final pct = totalPlaces == 0 ? 0 : ((reserved / totalPlaces) * 100).round();
    return '$pct% ($reserved/$totalPlaces places)';
  }

  Future<void> _showSlotDetails(AgendaSlot slot) async {
    if (!mounted) return;

    // fetch reservation names for this slot (if any)
    final List<String> names = [];
    try {
      final resSnap = await _fs
          .collection('companies')
          .doc(_companyId)
          .collection('reservations')
          .where('slotId', isEqualTo: slot.id)
          .where('status', isEqualTo: 'confirmed')
          .orderBy('createdAt')
          .get();

      for (final rdoc in resSnap.docs) {
        final r = rdoc.data();
        String name = '';
        final customerId = r['customerId'] as String?;
        if (customerId != null) {
          final userDoc = await _fs.collection('users').doc(customerId).get();
          if (userDoc.exists) {
            final ud = userDoc.data() ?? {};
            name =
                (ud['displayName'] ??
                        ud['name'] ??
                        ud['prenom'] ??
                        ud['fullName'])
                    as String? ??
                '';
          }
        }
        if (name.isEmpty) {
          final email = r['customerEmail'] as String?;
          if (email != null) name = email.split('@').first;
        }
        if (name.isNotEmpty) names.add(_formatCustomerName(name));
      }
    } catch (e) {
      debugPrint('Erreur fetch reservations for details: $e');
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${_timeFmt.format(slot.start)} — ${slot.queueName ?? ''}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Statut: ${slot.status}'),
              const SizedBox(height: 8),
              Text('Places: ${slot.reserved}/${slot.capacity}'),
              const SizedBox(height: 8),
              if (slot.title != null) Text('Info: ${slot.title}'),
              const SizedBox(height: 12),
              if (slot.capacity > 1)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Réservations (${names.length}):',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    if (names.isEmpty) const Text('Aucune réservation'),
                    if (names.isNotEmpty) ...names.map((n) => Text(n)).toList(),
                  ],
                ),
              if (slot.capacity == 1)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Client:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      names.isNotEmpty
                          ? names.first
                          : (slot.reserved == 0 ? 'Disponible' : 'Réservé'),
                    ),
                  ],
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fermer'),
          ),
          if (slot.status == 'open' && slot.reserved < slot.capacity)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _showQuickCreateDialog(slot);
              },
              child: const Text('Nouveau RDV'),
            ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _toggleSlotStatus(slot);
            },
            child: Text(slot.status == 'open' ? 'Bloquer' : 'Ouvrir'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Confirmer la suppression'),
                  content: const Text(
                    'Supprimer ce créneau ? Les clients seront notifiés.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Annuler'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Supprimer'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) await _deleteSlotWithNotification(slot);
            },
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => _loadSlotsForDate(_selectedDate),
            child: const Text('Rafraîchir'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleSlotStatus(AgendaSlot slot) async {
    if (_companyId == null) return;
    try {
      final slotRef = _fs
          .collection('companies')
          .doc(_companyId)
          .collection('queues')
          .doc(slot.queueId)
          .collection('slots')
          .doc(slot.id);
      final newStatus = slot.status == 'open' ? 'closed' : 'open';
      await slotRef.update({
        'status': newStatus,
        'statusUpdatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Statut mis à jour: $newStatus')),
        );
        _loadSlotsForDate(_selectedDate);
      }
    } catch (e) {
      debugPrint('Erreur toggle slot status: $e');
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  Future<void> _deleteSlotWithNotification(AgendaSlot slot) async {
    if (_companyId == null) return;
    try {
      final reservations = await _fs
          .collection('companies')
          .doc(_companyId)
          .collection('reservations')
          .where('slotId', isEqualTo: slot.id)
          .get();

      for (final r in reservations.docs) {
        final customerId = r.data()['customerId'] as String?;
        if (customerId == null) continue;
        await _fs
            .collection('customers')
            .doc(customerId)
            .collection('notifications')
            .add({
              'type': 'slot_cancelled',
              'slotId': slot.id,
              'slotStart': slot.start,
              'reason': 'Annulé par l\'entreprise',
              'companyId': _companyId,
              'createdAt': FieldValue.serverTimestamp(),
            });
      }

      final slotRef = _fs
          .collection('companies')
          .doc(_companyId)
          .collection('queues')
          .doc(slot.queueId)
          .collection('slots')
          .doc(slot.id);
      await slotRef.delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Créneau supprimé et clients notifiés.'),
          ),
        );
        _loadSlotsForDate(_selectedDate);
      }
    } catch (e) {
      debugPrint('Erreur suppression créneau: $e');
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  Future<void> _showQuickCreateDialog(AgendaSlot slot) async {
    if (!mounted) return;
    final _formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouveau RDV'),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Nom (Prénom Nom)',
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Nom requis' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: emailCtrl,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Email (optionnel)',
                  prefixIcon: Icon(Icons.email),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              if (!_formKey.currentState!.validate()) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Créer'),
          ),
        ],
      ),
    );

    if (result != true) return;

    final name = nameCtrl.text.trim();
    final email = emailCtrl.text.trim();
    await _createReservationQuick(
      slot: slot,
      customerName: name,
      customerEmail: email,
    );
  }

  Future<void> _createReservationQuick({
    required AgendaSlot slot,
    required String customerName,
    required String customerEmail,
  }) async {
    if (_companyId == null) return;

    final slotRef = _fs
        .collection('companies')
        .doc(_companyId)
        .collection('queues')
        .doc(slot.queueId)
        .collection('slots')
        .doc(slot.id);

    final reservationsCol = _fs
        .collection('companies')
        .doc(_companyId)
        .collection('reservations');
    final reservationRef = reservationsCol.doc();
    final now = DateTime.now().toUtc();

    try {
      await _fs.runTransaction((tx) async {
        final freshSlot = await tx.get(slotRef);
        if (!freshSlot.exists) throw Exception('Créneau introuvable');
        final freshData = freshSlot.data()!;
        final slotStart = (freshData['start'] as Timestamp).toDate().toUtc();
        final capacity = (freshData['capacity'] ?? 1) as int;
        final reserved = (freshData['reserved'] ?? 0) as int;
        final status = (freshData['status'] ?? 'open') as String;

        if (status != 'open') throw Exception('Ce créneau n\'est plus ouvert.');
        if (reserved >= capacity) throw Exception('Ce créneau est complet.');

        final minutesUntilStart = slotStart.difference(now).inMinutes;
        final required = 10; // délai minimum 10 min
        if (minutesUntilStart < required)
          throw Exception('Délai minimal requis non respecté.');

        final reservationPayload = {
          'companyId': _companyId,
          'queueId': slot.queueId,
          'queueName': slot.queueName,
          'slotId': slot.id,
          'customerName': customerName,
          'customerEmail': customerEmail.isNotEmpty ? customerEmail : null,
          'createdAt': FieldValue.serverTimestamp(),
          'status': 'confirmed',
          'createdBy': FirebaseAuth.instance.currentUser?.uid,
        };

        tx.set(reservationRef, reservationPayload);
        tx.update(slotRef, {'reserved': FieldValue.increment(1)});
      });

      // schedule notifications minimally
      await NotificationService().cancelAll();
      await NotificationService().scheduleReservationNotifications(
        waitMinutes: 180,
        slotDurationMinutes: 15,
      );

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Réservation créée.')));
        _loadSlotsForDate(_selectedDate);
      }
    } catch (e) {
      debugPrint('Erreur création RDV: $e');
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur création RDV: $e')));
    }
  }

  // Layout computation: group overlapping slots and assign column indices per group
  Map<String, SlotLayout> _computeLayouts(List<AgendaSlot> slots) {
    final Map<String, SlotLayout> layouts = {};
    if (slots.isEmpty) return layouts;

    // group contiguous overlapping slots
    final sorted = List<AgendaSlot>.from(slots)
      ..sort((a, b) => a.start.compareTo(b.start));
    List<List<AgendaSlot>> groups = [];
    List<AgendaSlot> currentGroup = [sorted.first];
    DateTime groupEnd = sorted.first.end;

    for (var i = 1; i < sorted.length; i++) {
      final s = sorted[i];
      if (s.start.isBefore(groupEnd)) {
        currentGroup.add(s);
        if (s.end.isAfter(groupEnd)) groupEnd = s.end;
      } else {
        groups.add(currentGroup);
        currentGroup = [s];
        groupEnd = s.end;
      }
    }
    if (currentGroup.isNotEmpty) groups.add(currentGroup);

    // for each group, do interval partitioning to assign columns
    for (final group in groups) {
      // columns end times
      final List<DateTime> colEnds = [];
      final Map<AgendaSlot, int> assignment = {};

      for (final s in group..sort((a, b) => a.start.compareTo(b.start))) {
        // find first column that is free
        int found = -1;
        for (var c = 0; c < colEnds.length; c++) {
          if (!s.start.isBefore(colEnds[c])) {
            found = c;
            break;
          }
        }
        if (found == -1) {
          // new column
          colEnds.add(s.end);
          assignment[s] = colEnds.length - 1;
        } else {
          colEnds[found] = s.end.isAfter(colEnds[found])
              ? s.end
              : colEnds[found];
          assignment[s] = found;
        }
      }

      final colsCount = colEnds.length;
      for (final entry in assignment.entries) {
        layouts[entry.key.id] = SlotLayout(
          colIndex: entry.value,
          cols: colsCount,
        );
      }
    }

    return layouts;
  }

  String _formatCustomerName(String raw) {
    if (raw.trim().isEmpty) return raw;
    final parts = raw.trim().split(RegExp(r"\s+"));
    if (parts.length == 1) return _capitalize(parts[0]);
    final first = _capitalize(parts.first);
    final last = _capitalize(parts.last);
    final middle = parts
        .sublist(1, parts.length - 1)
        .map((p) => p.isNotEmpty ? '${p[0].toUpperCase()}.' : '')
        .join(' ');
    final result = '$first ${middle.isNotEmpty ? middle + ' ' : ''}$last';
    return result;
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  Color _colorForQueue(String queueId) {
    const palette = [
      Color(0xFF6FCF97),
      Color(0xFF7ED6A3),
      Color(0xFF52C1A6),
      Color(0xFF8AD0B9),
      Color(0xFFFFC107),
      Color(0xFF00ACC1),
      Color(0xFF9C27B0),
      Color(0xFFEF5350),
    ];
    final idx = queueId.hashCode.abs() % palette.length;
    return palette[idx];
  }

  // small helper to store layout info
}

class SlotLayout {
  final int colIndex;
  final int cols;
  SlotLayout({required this.colIndex, required this.cols});
}

// Modèle simplifié pour l'affichage dans la timeline
class AgendaSlot {
  final String id;
  final String queueId;
  final String? queueName;
  final DateTime start;
  final DateTime end;
  final int capacity;
  final int reserved;
  final String status;
  final String? title;

  AgendaSlot({
    required this.id,
    required this.queueId,
    this.queueName,
    required this.start,
    required this.end,
    required this.capacity,
    required this.reserved,
    this.status = 'open',
    this.title,
  });

  static AgendaSlot fromMap({
    required String queueId,
    required String id,
    required Map<String, dynamic> data,
  }) {
    final startTs = data['start'] as Timestamp;
    final endTs = data['end'] as Timestamp? ?? startTs;
    return AgendaSlot(
      id: id,
      queueId: queueId,
      queueName: data['queueName'] as String?,
      start: startTs.toDate().toLocal(),
      end: endTs.toDate().toLocal(),
      capacity: (data['capacity'] ?? 1) as int,
      reserved: (data['reserved'] ?? 0) as int,
      status: (data['status'] ?? 'open') as String,
      title: data['title'] as String?,
    );
  }
}
