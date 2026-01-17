import 'package:flutter/material.dart'
    show
        AppBar,
        BuildContext,
        Card,
        Center,
        CircularProgressIndicator,
        EdgeInsets,
        ElevatedButton,
        ListTile,
        ListView,
        Navigator,
        Scaffold,
        ScaffoldMessenger,
        SnackBar,
        State,
        StatefulWidget,
        StreamBuilder,
        Text,
        Widget,
        showModalBottomSheet;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:baxa/services/notifications/notification_service.dart';

class CompanyQueuePage extends StatefulWidget {
  final String entrepriseId;
  final String entrepriseNom;

  const CompanyQueuePage({
    super.key,
    required this.entrepriseId,
    required this.entrepriseNom,
  });

  @override
  State<CompanyQueuePage> createState() => _CompanyQueuePageState();
}

class _CompanyQueuePageState extends State<CompanyQueuePage> {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final DateFormat _timeFmt = DateFormat('HH:mm');
  // ignore: unused_field
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.entrepriseNom)),
      body: StreamBuilder<QuerySnapshot>(
        stream: _fs
            .collection('companies') // harmonisé avec settings_page.dart
            .doc(widget.entrepriseId)
            .collection('queues')
            .orderBy('createdAt')
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());
          final queues = snapshot.data!.docs;
          if (queues.isEmpty) {
            return const Center(
              child: Text(
                "Aucune file d'attente disponible pour cette structure.",
              ),
            );
          }
          return ListView.builder(
            itemCount: queues.length,
            itemBuilder: (context, index) {
              final queueDoc = queues[index];
              final queueData = queueDoc.data() as Map<String, dynamic>;
              final queueId = queueDoc.id;
              final queueName = queueData['nom'] ?? 'File';

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  title: Text(queueName),
                  subtitle: Text(queueData['description'] ?? ''),
                  trailing: ElevatedButton(
                    child: const Text("Voir créneaux"),
                    onPressed: () => _showSlotsDialog(queueId, queueName),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showSlotsDialog(String queueId, String queueName) async {
    setState(() => _loading = true);
    try {
      final now = DateTime.now().toUtc();
      final slotsSnap = await _fs
          .collection('companies')
          .doc(widget.entrepriseId)
          .collection('queues')
          .doc(queueId)
          .collection('slots')
          .where('start', isGreaterThanOrEqualTo: now)
          .orderBy('start')
          .limit(100)
          .get();

      final available = slotsSnap.docs.where((d) {
        final data = d.data();
        final reserved = (data['reserved'] ?? 0) as int;
        final capacity = (data['capacity'] ?? 1) as int;
        final status = (data['status'] ?? 'open') as String;
        return status == 'open' && reserved < capacity;
      }).toList();

      if (!mounted) return;
      if (available.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aucun créneau disponible.')),
        );
        return;
      }

      await showModalBottomSheet(
        context: context,
        builder: (ctx) => ListView.builder(
          itemCount: available.length,
          itemBuilder: (ctx, i) {
            final doc = available[i];
            // ignore: unnecessary_cast
            final data = doc.data() as Map<String, dynamic>;
            final start = (data['start'] as Timestamp).toDate().toLocal();
            final end = (data['end'] as Timestamp).toDate().toLocal();
            final reserved = data['reserved'] ?? 0;
            final capacity = data['capacity'] ?? 1;

            return ListTile(
              title: Text(
                '${_timeFmt.format(start)} - ${_timeFmt.format(end)}',
              ),
              subtitle: Text('Places: $reserved / $capacity'),
              trailing: ElevatedButton(
                child: const Text('Réserver'),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _reserveSlot(
                    queueId: queueId,
                    queueName: queueName,
                    slotDocId: doc.id,
                    slotData: data,
                  );
                },
              ),
            );
          },
        ),
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _reserveSlot({
    required String queueId,
    required String queueName,
    required String slotDocId,
    required Map<String, dynamic> slotData,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Connectez-vous pour réserver.")),
        );
      return;
    }

    setState(() => _loading = true);
    try {
      // récupérer settings pour reservationDelay (en heures)
      final settingsDoc = await _fs
          .collection('companies')
          .doc(widget.entrepriseId)
          .collection('meta')
          .doc('settings')
          .get();
      final settings = settingsDoc.exists
          // ignore: unnecessary_cast
          ? (settingsDoc.data() ?? {}) as Map<String, dynamic>
          : {};
      final reservationDelayHours =
          (settings['reservationDelayHours'] ?? 0) as int;
      final minAdvanceMinutes = (reservationDelayHours * 60).clamp(0, 99999);

      final slotRef = _fs
          .collection('companies')
          .doc(widget.entrepriseId)
          .collection('queues')
          .doc(queueId)
          .collection('slots')
          .doc(slotDocId);

      final reservationsCol = _fs
          .collection('companies')
          .doc(widget.entrepriseId)
          .collection('reservations');
      final reservationRef = reservationsCol.doc(); // Pré-génère l'ID

      final now = DateTime.now().toUtc();

      // Transaction: vérifie capacité et délai, crée réservation et incrémente reserved
      await _fs.runTransaction((tx) async {
        final freshSlot = await tx.get(slotRef);
        if (!freshSlot.exists) throw Exception('Créneau introuvable');
        final freshData = freshSlot.data()!;
        final slotStart = (freshData['start'] as Timestamp).toDate().toUtc();
        final slotEnd = (freshData['end'] as Timestamp).toDate().toUtc();
        final capacity = (freshData['capacity'] ?? 1) as int;
        final reserved = (freshData['reserved'] ?? 0) as int;
        final status = (freshData['status'] ?? 'open') as String;

        if (status != 'open') throw Exception('Ce créneau n\'est plus ouvert.');
        if (reserved >= capacity) throw Exception('Ce créneau est complet.');

        final minutesUntilStart = slotStart.difference(now).inMinutes;
        final requiredMin = (minAdvanceMinutes).toInt();
        // imposer aussi au moins 10 minutes de délai pour validation (sécurité)
        final required = requiredMin > 10 ? requiredMin : 10;
        if (minutesUntilStart < required)
          throw Exception(
            'Réservation impossible : délai minimal requis non respecté.',
          );

        // create reservation document
        final reservationPayload = {
          'companyId': widget.entrepriseId,
          'queueId': queueId,
          'queueName': queueName,
          'slotId': slotDocId,
          'customerId': user.uid,
          'customerEmail': user.email,
          'slotStart': slotStart,
          'slotEnd': slotEnd,
          'createdAt': FieldValue.serverTimestamp(),
          'status': 'confirmed',
        };
        tx.set(reservationRef, reservationPayload);

        // incrémenter reserved
        tx.update(slotRef, {'reserved': FieldValue.increment(1)});
      });

      // scheduling notifications locaux
      final slotStartLocal = (slotData['start'] as Timestamp)
          .toDate()
          .toLocal();
      final slotEndLocal = (slotData['end'] as Timestamp).toDate().toLocal();
      // ignore: unused_local_variable
      final waitMinutes = slotStartLocal.difference(DateTime.now()).inMinutes;
      // ignore: unused_local_variable
      final slotDurationMinutes = slotEndLocal
          .difference(slotStartLocal)
          .inMinutes;

      await NotificationService().cancelAll();

      await NotificationService().scheduleReservationNotifications(
        waitMinutes: 180, // notification 30 minutes avant
        slotDurationMinutes: 15, // notification fin de créneau
      );

      // enregistrer la dernière file rejointe pour le suivi utilisateur
      await _fs
          .collection('users')
          .doc(user.uid)
          .collection('lastQueue')
          .doc('last')
          .set({
            'entrepriseId': widget.entrepriseId,
            'entrepriseNom': widget.entrepriseNom,
            'queueId': queueId,
            'queueNom': queueName,
            'slotId': slotDocId,
            'slotStart': slotData['start'],
          });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Réservation réussie.")));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur réservation: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }
}
