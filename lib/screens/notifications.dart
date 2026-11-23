import 'package:flutter/material.dart';

import '../core/notification_center.dart';
import '../core/palette.dart';
import '../ui/common.dart';
import '../ui/pictos.dart';

/// Centre local des alertes de l'application.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  String _filter = 'all';

  static const _filters = [
    ('all', 'Tout'),
    ('unread', 'Non lues'),
    ('moderation', 'Modération'),
    ('bot', 'Bot'),
    ('security', 'Sécurité'),
  ];

  @override
  void initState() {
    super.initState();
    NotificationCenter.load();
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Effacer les notifications ?'),
        content: const Text('L’historique local sera supprimé de cet appareil.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Effacer'),
          ),
        ],
      ),
    );
    if (confirmed == true) await NotificationCenter.clear();
  }

  String _date(DateTime date) {
    final d = date.toLocal();
    final now = DateTime.now();
    final sameDay = d.year == now.year && d.month == now.month && d.day == now.day;
    final yesterday = DateTime(now.year, now.month, now.day)
        .difference(DateTime(d.year, d.month, d.day))
        .inDays == 1;
    final time =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (sameDay) return "Aujourd’hui · $time";
    if (yesterday) return 'Hier · $time';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} · $time';
  }

  String _categoryLabel(String category) {
    switch (category) {
      case 'bot':
        return 'BOT';
      case 'moderation':
        return 'MODÉRATION';
      case 'security':
        return 'SÉCURITÉ';
      default:
        return 'INFORMATION';
    }
  }

  String _iconName(String category) {
    switch (category) {
      case 'security':
        return 'shield';
      case 'bot':
        return 'bot';
      case 'moderation':
        return 'shield';
      default:
        return 'bell';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return ValueListenableBuilder<List<NotificationEntry>>(
      valueListenable: NotificationCenter.entries,
      builder: (context, entries, _) {
        final unread = entries.where((item) => !item.read).length;
        final visible = entries.where((item) {
          if (_filter == 'unread') return !item.read;
          if (_filter == 'security') return item.category == 'security';
          if (_filter == 'moderation') return item.category == 'moderation';
          if (_filter == 'bot') return item.category == 'bot';
          return true;
        }).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 34),
          children: [
            Container(
              padding: const EdgeInsets.all(17),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: c.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: c.accent.withValues(alpha: .13),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Picto('bell', color: c.accent, size: 21),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Votre activité', style: T.strong(c)),
                            const SizedBox(height: 3),
                            Text(
                              unread == 0
                                  ? 'Vous êtes à jour'
                                  : '$unread notification${unread > 1 ? 's' : ''} à consulter',
                              style: T.caption(c),
                            ),
                          ],
                        ),
                      ),
                      if (unread > 0)
                        TextButton(
                          onPressed: () => NotificationCenter.markAllRead(),
                          child: const Text('Tout lire'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _counter(c, 'TOTAL', entries.length.toString(), Icons.notifications_none_rounded),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _counter(c, 'NON LUES', unread.toString(), Icons.mark_email_unread_outlined),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: Text('Notifications', style: T.strong(c).copyWith(fontSize: 17))),
                Text('${visible.length} résultat${visible.length > 1 ? 's' : ''}', style: T.caption(c)),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final option in _filters)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(option.$2),
                        selected: _filter == option.$1,
                        onSelected: (_) => setState(() => _filter = option.$1),
                        showCheckmark: false,
                        labelStyle: TextStyle(
                          color: _filter == option.$1 ? c.accent : c.ink,
                          fontWeight: _filter == option.$1 ? FontWeight.w700 : FontWeight.w500,
                        ),
                        backgroundColor: c.card,
                        selectedColor: c.accent.withValues(alpha: .13),
                        side: BorderSide(
                          color: _filter == option.$1 ? c.accent.withValues(alpha: .5) : c.line,
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (visible.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 34),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: c.line),
                ),
                child: KEmpty(
                  Icons.notifications_none_rounded,
                  entries.isEmpty ? 'Aucune notification' : 'Aucun résultat',
                  sub: entries.isEmpty
                      ? 'Les alertes du bot, de la modération et de la sécurité apparaîtront ici.'
                      : 'Aucune notification ne correspond à ce filtre.',
                ),
              )
            else
              for (final item in visible)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: c.card,
                      borderRadius: BorderRadius.circular(19),
                      border: Border.all(
                        color: item.read ? c.line : c.accent.withValues(alpha: .55),
                        width: item.read ? 1 : 1.25,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: c.accent.withValues(alpha: .11),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Picto(
                                  _iconName(item.category),
                                  size: 19,
                                  color: c.accent,
                                ),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _categoryLabel(item.category),
                                      style: T.caption(c).copyWith(
                                        color: c.accent,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: .7,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(item.title, style: T.strong(c)),
                                  ],
                                ),
                              ),
                              if (!item.read)
                                Container(
                                  width: 9,
                                  height: 9,
                                  margin: const EdgeInsets.only(top: 5),
                                  decoration: BoxDecoration(
                                    color: c.accent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(item.body, style: T.body(c)),
                          const SizedBox(height: 12),
                          Divider(height: 1, color: c.line),
                          const SizedBox(height: 7),
                          Row(
                            children: [
                              Icon(Icons.schedule_rounded, size: 14, color: c.muted),
                              const SizedBox(width: 5),
                              Expanded(child: Text(_date(item.createdAt), style: T.caption(c))),
                              if (!item.read)
                                TextButton(
                                  onPressed: () => NotificationCenter.markRead(item.id),
                                  child: const Text('Marquer comme lue'),
                                ),
                              IconButton(
                                tooltip: 'Supprimer',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => NotificationCenter.remove(item.id),
                                icon: Icon(Icons.delete_outline_rounded, size: 19, color: c.muted),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            if (entries.isNotEmpty) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.center,
                child: TextButton.icon(
                  onPressed: _clear,
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: const Text('Effacer tout l’historique'),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _counter(Palette c, String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: c.chip,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: c.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: T.caption(c).copyWith(fontSize: 9, letterSpacing: .6)),
                const SizedBox(height: 2),
                Text(value, style: T.strong(c).copyWith(fontSize: 18)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
