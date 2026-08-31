import 'dart:async';

import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Icône « Notifications » de barre de navigation, avec pastille du nombre
/// de non-lus. Partagée par les trois espaces (customer, company admin,
/// staff) pour garantir un comportement identique partout.
///
/// « Non lu » = notification dont `createdAt` est postérieur à
/// `users/{uid}.notificationsLastSeenAt` — pas un suivi par notification,
/// même logique que la plupart des apps grand public. Ce même curseur pilote
/// aussi la pastille de l'icône de l'app (via app_badge_plus).
///
/// Le comptage se fait EN MÉMOIRE à partir du flux `recentNotifications`
/// (déjà trié / limité, le même que la liste de l'onglet) : aucun index
/// Firestore composite supplémentaire n'est requis, et une pastille plafonnée
/// à « 9+ » n'a pas besoin d'être exacte au-delà.
class NotificationsNavIcon extends StatefulWidget {
  const NotificationsNavIcon({
    super.key,
    required this.recentNotifications,
    this.icon = Icons.notifications,
    this.badgeColor = const Color(0xFFFF6F59),
  });

  /// Flux des notifications récentes de l'utilisateur courant, trié
  /// `createdAt` décroissant et limité. Doit être STABLE entre deux `build`
  /// (le stocker dans un champ `late final`, pas le reconstruire à chaque
  /// rebuild) pour éviter de ré-attacher l'écoute inutilement.
  final Query<Map<String, dynamic>> recentNotifications;

  final IconData icon;
  final Color badgeColor;

  /// Repositionne le curseur « vu » à maintenant et efface la pastille de
  /// l'icône de l'app. À appeler à l'entrée ET à la sortie de l'onglet
  /// Notifications (couvre le cas d'une notif reçue pendant la consultation).
  static Future<void> markSeen() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance.collection('users').doc(uid).set(
      {'notificationsLastSeenAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
    try {
      await AppBadgePlus.updateBadge(0);
    } catch (_) {}
  }

  @override
  State<NotificationsNavIcon> createState() => _NotificationsNavIconState();
}

class _NotificationsNavIconState extends State<NotificationsNavIcon> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _notifSub;

  int _unread = 0;
  Timestamp? _lastSeen;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _latest = const [];

  // Tant que le serveur n'a pas confirmé un FieldValue.serverTimestamp(),
  // Firestore relit ce champ comme `null` en local (comportement documenté du
  // SDK). Sans ce verrou, chaque écriture réaffiche `null` aussitôt, ce qui
  // redéclenche une écriture, en boucle. (Repris de customer_page.dart.)
  bool _bootstrapping = false;

  @override
  void initState() {
    super.initState();
    _attachUserListener();
    _attachNotifListener();
  }

  @override
  void didUpdateWidget(NotificationsNavIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recentNotifications != widget.recentNotifications) {
      _attachNotifListener();
    }
  }

  void _attachUserListener() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _userSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((doc) {
      final lastSeen =
          doc.data()?['notificationsLastSeenAt'] as Timestamp?;

      if (lastSeen == null) {
        if (!_bootstrapping) {
          _bootstrapping = true;
          FirebaseFirestore.instance.collection('users').doc(uid).set(
            {'notificationsLastSeenAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true),
          );
        }
        return;
      }
      _bootstrapping = false;

      if (_lastSeen == lastSeen) return;
      _lastSeen = lastSeen;
      _recount();
    });
  }

  void _attachNotifListener() {
    _notifSub?.cancel();
    _notifSub = widget.recentNotifications.snapshots().listen((snap) {
      _latest = snap.docs;
      _recount();
    });
  }

  void _recount() {
    final cursor = _lastSeen;
    final count = cursor == null
        ? 0
        : _latest.where((d) {
            final ts = d.data()['createdAt'];
            return ts is Timestamp && ts.compareTo(cursor) > 0;
          }).length;

    if (mounted && count != _unread) {
      setState(() => _unread = count);
    }
    try {
      AppBadgePlus.updateBadge(count);
    } catch (_) {}
  }

  @override
  void dispose() {
    _userSub?.cancel();
    _notifSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final icon = Icon(widget.icon);
    if (_unread == 0) return icon;
    return Badge(
      backgroundColor: widget.badgeColor,
      label: Text(_unread > 9 ? '9+' : '$_unread'),
      child: icon,
    );
  }
}
