import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api.dart';
import 'store.dart';
import 'notification_center.dart';

/// Notifications locales : commentaires urgents détectés à l'ouverture de
/// la Modération, jeton Facebook bientôt expiré au démarrage. Réglage
/// « Notifications » dans Réglages > Apparence (Store notifs_on, activé
/// par défaut). Chaque commentaire n'est annoncé qu'une fois, le jeton
/// une fois par jour — jamais de spam.
class Notifs {
  static const _canal = 'kidas_alertes';
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _init = false;

  /// État du réglage, partagé avec l'interrupteur des Réglages.
  static final ValueNotifier<bool> activ = ValueNotifier(true);

  /// Vrai après une initialisation réussie du plugin.
  static bool pret = false;

  static Future<void> init() async {
    if (_init) return;
    _init = true;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      await _plugin.initialize(
        settings: const InitializationSettings(android: android),
      );
      pret = true;
    } catch (_) {
      /* pas critique : l'app vit sans notifications */
    }
    activ.value = (await Store.get('notifs_on')) != '0';
    if (activ.value && pret) await _permission();
  }

  /// Bascule du réglage (Réglages > Apparence).
  static Future<void> set(bool v) async {
    activ.value = v;
    await Store.set('notifs_on', v ? '1' : '0');
    if (v && pret) await _permission();
  }

  /// Permission Android 13+ (canal POST_NOTIFICATIONS).
  static Future<void> _permission() async {
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } catch (_) {
      /* refus ou plateforme sans permission : sans effet */
    }
  }

  /// Alerte jeton au démarrage (une seule fois par jour, réglage ON).
  static Future<void> auDemarrage() async {
    await init();
    if (!activ.value || !pret) return;
    final j = Api.joursAvantExp();
    if (j == null || j > 3) return;
    final auj = DateTime.now().toIso8601String().split('T').first;
    if (await Store.get('notifs_jeton') == auj) return;
    await Store.set('notifs_jeton', auj);
    await montre(
      'Jeton Facebook',
      j < 0
          ? 'Le jeton est expiré — reconnecte-toi.'
          : j == 0
          ? "Le jeton expire aujourd'hui — renouvelle-le."
          : 'Le jeton expire dans $j jour${j > 1 ? 's' : ''}.',
    );
  }

  /// Annonce des commentaires urgents détectés (une fois par commentaire).
  static Future<void> urgents(List<String> ids) async {
    if (ids.isEmpty) return;
    if (!activ.value || !pret) return;
    final deja = await Store.get('notifs_urgents');
    final connus = deja.isEmpty ? <String>{} : deja.split(' ').toSet();
    final neufs = ids.where((x) => !connus.contains(x)).toList();
    if (neufs.isEmpty) return;
    connus.addAll(neufs);
    final garde = connus.toList();
    if (garde.length > 200) garde.removeRange(0, garde.length - 200);
    await Store.set('notifs_urgents', garde.join(' '));
    await montre(
      'Modération',
      '${neufs.length} commentaire${neufs.length > 1 ? 's' : ''} '
          'urgent${neufs.length > 1 ? 's' : ''} à traiter.',
    );
  }

  static Future<void> montre(String titre, String corps) async {
    await NotificationCenter.add(
      title: titre,
      body: corps,
      category: titre == 'Jeton Facebook' ? 'security' : 'moderation',
    );
    try {
      const d = AndroidNotificationDetails(
        _canal,
        'Alertes KI DAS',
        channelDescription: 'Commentaires urgents, jeton Facebook, bot',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      );
      await _plugin.show(
        id: DateTime.now().millisecondsSinceEpoch % 2147483647,
        title: titre,
        body: corps,
        notificationDetails: const NotificationDetails(android: d),
      );
    } catch (_) {
      /* jamais bloquant */
    }
  }
}
