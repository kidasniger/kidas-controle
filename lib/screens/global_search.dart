import 'package:flutter/material.dart';

import '../core/data.dart';
import '../core/palette.dart';
import '../core/search.dart';
import '../ui/common.dart';
import '../ui/shell.dart' show SubPage;
import 'boite.dart';
import 'composer.dart';
import 'conversation_detail.dart';
import 'journal.dart';

/// Recherche transversale dans les données déjà synchronisées de l'application.
class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});
  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final _controller = TextEditingController();
  List<SearchHit> _index = const [];
  bool _loading = true;
  String? _error;
  String _category = 'tout';

  static const _filters = [
    ('tout', 'Tout'),
    ('conversation', 'Conversations'),
    ('commentaire', 'Commentaires'),
    ('publication', 'Publications'),
    ('brouillon', 'Brouillons'),
    ('activite', 'Activité'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait<dynamic>([
        Boite.charge(),
        Brouillons.charge(),
        Journal.charge(max: 400),
      ]);
      final inbox = results[0] as (List<UnifiedItem>, String);
      final drafts = results[1] as List<Brouillon>;
      final events = results[2] as List<JournalEvent>;
      final index = GlobalSearch.build(inbox: inbox.$1, drafts: drafts, events: events);
      if (mounted) setState(() { _index = index; _draftsCache = drafts; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  List<SearchHit> get _results =>
      GlobalSearch.query(_index, _controller.text, category: _category);

  String _date(int timestamp) {
    if (timestamp <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal();
    final now = DateTime.now();
    final sameDay = d.year == now.year && d.month == now.month && d.day == now.day;
    final time = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (sameDay) return "Aujourd'hui · $time";
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} · $time';
  }

  String _categoryName(String category) => switch (category) {
    'conversation' => 'MESSENGER',
    'commentaire' => 'COMMENTAIRE',
    'publication' => 'PUBLICATION',
    'brouillon' => 'BROUILLON',
    _ => 'ACTIVITÉ',
  };

  IconData _icon(String category) => switch (category) {
    'conversation' => Icons.forum_outlined,
    'commentaire' => Icons.chat_bubble_outline,
    'publication' => Icons.article_outlined,
    'brouillon' => Icons.edit_note_outlined,
    _ => Icons.history,
  };

  Future<void> _open(SearchHit hit) async {
    switch (hit.category) {
      case 'conversation':
        final id = hit.conversationId;
        if (id != null && id.isNotEmpty) {
          await Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => ConversationDetailScreen(conversationId: id),
          ));
        }
        return;
      case 'commentaire':
      case 'publication':
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => SubPage('Boîte de réception', child: BoiteScreen(filtreInitial: 1, rechercheInitiale: hit.body.isNotEmpty ? hit.body : hit.title)),
        ));
        return;
      case 'brouillon':
        final draftId = hit.id.substring('draft:'.length);
        final draft = _indexDraft(draftId);
        if (draft != null) {
          PublishDraft.msg = draft.texte;
          PublishDraft.media = draft.media;
          PublishDraft.whenMs = draft.whenMs;
          PublishDraft.now = draft.whenMs <= 0;
          await Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const SubPage('Composer', child: ComposerScreen()),
          ));
        }
        return;
      case 'activite':
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const SubPage('Journal', child: JournalScreen()),
        ));
        return;
    }
  }

  Brouillon? _indexDraft(String id) {
    // Les brouillons sont chargés à la demande pour éviter de conserver
    // une deuxième copie mutable de leur contenu dans l'index.
    for (final draft in _draftsCache) {
      if (draft.id == id) return draft;
    }
    return null;
  }

  List<Brouillon> _draftsCache = const [];

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    final results = _results;
    return SubPage(
      'Recherche globale',
      trailing: IconButton(
        tooltip: 'Actualiser les données',
        onPressed: _loading ? null : _load,
        icon: Icon(Icons.refresh, color: c.ink),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: TextField(
              controller: _controller,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Nom, message, commentaire, publication…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _controller.text.isEmpty ? null : IconButton(
                  tooltip: 'Effacer',
                  onPressed: () { _controller.clear(); setState(() {}); },
                  icon: const Icon(Icons.close),
                ),
                filled: true,
                fillColor: c.card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: c.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: c.line),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                for (final filter in _filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: ChoiceChip(
                      label: Text(filter.$2),
                      selected: _category == filter.$1,
                      onSelected: (_) => setState(() => _category = filter.$1),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading && _index.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                ? Center(child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.cloud_off_outlined, size: 34),
                      const SizedBox(height: 10),
                      Text('Impossible de charger les données', style: T.strong(c)),
                      const SizedBox(height: 5),
                      Text(_error!, textAlign: TextAlign.center, style: T.caption(c)),
                      TextButton(onPressed: _load, child: const Text('Réessayer')),
                    ]),
                  ))
                : _controller.text.trim().isEmpty
                  ? Center(child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.manage_search, size: 42, color: c.muted),
                        const SizedBox(height: 10),
                        Text('Recherche dans KIDAS Contrôle', style: T.strong(c)),
                        const SizedBox(height: 5),
                        Text('${_index.length} éléments indexés · saisis un mot ou un nom.',
                          textAlign: TextAlign.center, style: T.caption(c)),
                      ]),
                    ))
                  : results.isEmpty
                    ? KEmpty(Icons.search_off, 'Aucun résultat', sub: 'Essaie un autre terme ou une autre catégorie.')
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
                        itemCount: results.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 7),
                        itemBuilder: (context, index) {
                          final hit = results[index];
                          return Material(
                            color: c.card,
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => _open(hit),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: c.line),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 38, height: 38,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: c.soft,
                                        borderRadius: BorderRadius.circular(11),
                                      ),
                                      child: Icon(_icon(hit.category), size: 18, color: c.ink),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(children: [
                                          Expanded(child: Text(hit.title, maxLines: 1,
                                            overflow: TextOverflow.ellipsis, style: T.strong(c))),
                                          Text(_categoryName(hit.category),
                                            style: T.caption(c).copyWith(fontSize: 9, fontWeight: FontWeight.w800)),
                                        ]),
                                        if (hit.subtitle.isNotEmpty) ...[
                                          const SizedBox(height: 3),
                                          Text(hit.subtitle, maxLines: 1,
                                            overflow: TextOverflow.ellipsis, style: T.caption(c)),
                                        ],
                                        if (hit.body.isNotEmpty) ...[
                                          const SizedBox(height: 5),
                                          Text(hit.body, maxLines: 3,
                                            overflow: TextOverflow.ellipsis, style: T.body(c)),
                                        ],
                                        const SizedBox(height: 5),
                                        Text(_date(hit.timestamp), style: T.caption(c)),
                                      ],
                                    )),
                                    const SizedBox(width: 4),
                                    Icon(Icons.chevron_right, color: c.muted, size: 19),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
