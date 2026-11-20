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
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 36),
          children: [
            KCard(
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.accent.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Picto('bell', color: c.accent, size: 19),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Centre de notifications', style: T.strong(c)),
                        Text(
                          '$unread non lue${unread > 1 ? 's' : ''} · ${entries.length} au total',
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
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final option in const [
                    ('all', 'Tout'),
                    ('unread', 'Non lues'),
                    ('moderation', 'Modération'),
                    ('bot', 'Bot'),
                    ('security', 'Sécurité'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: ChoiceChip(
                        label: Text(option.$2),
                        selected: _filter == option.$1,
                        onSelected: (_) => setState(() => _filter = option.$1),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (visible.isEmpty)
              KEmpty(
                Icons.notifications_none_rounded,
                entries.isEmpty ? 'Aucune notification' : 'Aucun résultat',
                sub: entries.isEmpty
                    ? 'Les alertes de modération et de sécurité apparaîtront ici.'
                    : 'Essaie un autre filtre.',
              )
            else ...[
              for (final item in visible)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: c.card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: item.read ? c.line : c.accent.withValues(alpha: .45),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: c.chip,
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Picto(
                              item.category == 'security'
                                  ? 'shield'
                                  : item.category == 'bot'
                                      ? 'bot'
                                      : 'bell',
                              size: 16,
                              color: item.category == 'security' || item.category == 'bot'
                                  ? c.accent
                                  : c.ink,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(item.title, style: T.strong(c)),
                                    ),
                                    if (!item.read)
                                      Container(
                                        width: 7,
                                        height: 7,
                                        decoration: BoxDecoration(
                                          color: c.accent,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(item.body, style: T.body(c)),
                                const SizedBox(height: 5),
                                Text(_date(item.createdAt), style: T.caption(c)),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Wrap(
                                    spacing: 4,
                                    children: [
                                      if (!item.read)
                                        TextButton(
                                          onPressed: () => NotificationCenter.markRead(item.id),
                                          child: const Text('Marquer comme lue'),
                                        ),
                                      IconButton(
                                        tooltip: 'Supprimer',
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () => NotificationCenter.remove(item.id),
                                        icon: Icon(Icons.delete_outline, size: 18, color: c.muted),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _clear,
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: const Text('Effacer l’historique'),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
