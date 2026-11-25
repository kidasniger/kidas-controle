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
  List<Brouillon> _draftsCache = const [];
  bool _loading = true;
  String? _error;
  String _category = 'tout';

  static const _filters = [
    ('tout', 'Tout', Icons.apps_outlined),
    ('conversation', 'Conversations', Icons.forum_outlined),
    ('commentaire', 'Commentaires', Icons.chat_bubble_outline),
    ('publication', 'Publications', Icons.article_outlined),
    ('brouillon', 'Brouillons', Icons.edit_note_outlined),
    ('activite', 'Activité', Icons.history),
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
      if (mounted) {
        setState(() {
          _index = index;
          _draftsCache = drafts;
          _loading = false;
        });
      }
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
          builder: (_) => SubPage(
            'Boîte de réception',
            child: BoiteScreen(
              filtreInitial: 1,
              rechercheInitiale: hit.body.isNotEmpty ? hit.body : hit.title,
            ),
          ),
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
    for (final draft in _draftsCache) {
      if (draft.id == id) return draft;
    }
    return null;
  }

  void _clearSearch() {
    _controller.clear();
    FocusScope.of(context).unfocus();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    final query = _controller.text.trim();
    final results = _results;
    return SubPage(
      'Recherche globale',
      trailing: IconButton(
        tooltip: 'Actualiser les données',
        onPressed: _loading ? null : _load,
        icon: Icon(Icons.refresh, color: _loading ? c.muted : c.ink),
      ),
      child: Column(
        children: [
          _searchHeader(c),
          _filterBar(c),
          if (query.isNotEmpty || !_loading)
            _resultSummary(c, query, results.length),
          Expanded(child: _content(c, query, results)),
        ],
      ),
    );
  }

  Widget _searchHeader(Palette c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Retrouver rapidement', style: T.title(c)),
          const SizedBox(height: 4),
          Text(
            'Conversations, commentaires, publications et activité.',
            style: T.caption(c),
          ),
          const SizedBox(height: 13),
          Container(
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.line),
            ),
            child: TextField(
              controller: _controller,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Nom, message, mot-clé…',
                hintStyle: TextStyle(color: c.muted, fontSize: 13),
                prefixIcon: Icon(Icons.search_rounded, color: c.accent),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Effacer la recherche',
                        onPressed: _clearSearch,
                        icon: Icon(Icons.close_rounded, color: c.muted, size: 19),
                      ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterBar(Palette c) {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        children: [
          for (final filter in _filters)
            Padding(
              padding: const EdgeInsets.only(right: 7),
              child: ChoiceChip(
                avatar: Icon(
                  filter.$3,
                  size: 15,
                  color: _category == filter.$1 ? c.onAccent : c.muted,
                ),
                label: Text(filter.$2),
                selected: _category == filter.$1,
                onSelected: (_) => setState(() => _category = filter.$1),
                showCheckmark: false,
                backgroundColor: c.card,
                selectedColor: c.accent,
                side: BorderSide(
                  color: _category == filter.$1 ? c.accent : c.line,
                ),
                labelStyle: TextStyle(
                  color: _category == filter.$1 ? c.onAccent : c.ink,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 5),
              ),
            ),
        ],
      ),
    );
  }

  Widget _resultSummary(Palette c, String query, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              query.isEmpty
                  ? 'INDEX DE RECHERCHE'
                  : '${count} résultat${count > 1 ? 's' : ''}',
              style: T.caption(c).copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: .8,
              ),
            ),
          ),
          if (_loading)
            SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                color: c.accent,
              ),
            )
          else
            Text(
              '${_index.length} éléments',
              style: T.caption(c).copyWith(fontSize: 10.5),
            ),
        ],
      ),
    );
  }

  Widget _content(Palette c, String query, List<SearchHit> results) {
    if (_loading && _index.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
        children: const [
          KSkeleton(76),
          SizedBox(height: 9),
          KSkeleton(76),
          SizedBox(height: 9),
          KSkeleton(76),
        ],
      );
    }

    if (_error != null && _index.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _stateIcon(c, Icons.cloud_off_outlined),
              const SizedBox(height: 13),
              Text('Données indisponibles', style: T.strong(c)),
              const SizedBox(height: 5),
              Text(
                'La recherche n’a pas pu charger les données.',
                textAlign: TextAlign.center,
                style: T.caption(c),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 17),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    if (query.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _stateIcon(c, Icons.manage_search_rounded),
              const SizedBox(height: 14),
              Text('Votre contenu, au même endroit', style: T.strong(c)),
              const SizedBox(height: 6),
              Text(
                'Saisis un nom ou quelques mots pour rechercher dans les données synchronisées.',
                textAlign: TextAlign.center,
                style: T.caption(c),
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 7,
                runSpacing: 7,
                children: const [
                  _HintPill(label: 'Messages'),
                  _HintPill(label: 'Commentaires'),
                  _HintPill(label: 'Brouillons'),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _stateIcon(c, Icons.search_off_rounded),
              const SizedBox(height: 12),
              Text('Aucun résultat', style: T.strong(c)),
              const SizedBox(height: 5),
              Text(
                'Essaie un autre terme ou change de catégorie.',
                textAlign: TextAlign.center,
                style: T.caption(c),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => setState(() => _category = 'tout'),
                icon: const Icon(Icons.filter_alt_off_outlined, size: 17),
                label: const Text('Afficher toutes les catégories'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 28),
      itemCount: results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _resultTile(c, results[index]),
    );
  }

  Widget _stateIcon(Palette c, IconData icon) {
    return Container(
      width: 58,
      height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.soft,
        borderRadius: BorderRadius.circular(19),
      ),
      child: Icon(icon, size: 27, color: c.accent),
    );
  }

  Widget _resultTile(Palette c, SearchHit hit) {
    return Material(
      color: c.card,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () => _open(hit),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: c.line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.soft,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(_icon(hit.category), size: 19, color: c.ink),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            hit.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: T.strong(c).copyWith(fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 7),
                        _typeLabel(c, hit.category),
                      ],
                    ),
                    if (hit.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        hit.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: T.caption(c),
                      ),
                    ],
                    if (hit.body.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        hit.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: T.body(c).copyWith(fontSize: 12.5),
                      ),
                    ],
                    const SizedBox(height: 7),
                    Text(_date(hit.timestamp), style: T.caption(c).copyWith(fontSize: 10.5)),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Icon(Icons.chevron_right_rounded, color: c.muted, size: 19),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeLabel(Palette c, String category) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: c.soft,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        _categoryName(category),
        style: T.caption(c).copyWith(
          fontSize: 8.5,
          fontWeight: FontWeight.w800,
          letterSpacing: .35,
        ),
      ),
    );
  }
}

class _HintPill extends StatelessWidget {
  final String label;
  const _HintPill({required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: c.line),
      ),
      child: Text(label, style: T.caption(c).copyWith(fontSize: 10.5)),
    );
  }
}
