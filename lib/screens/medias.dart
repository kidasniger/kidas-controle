import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/data.dart';
import '../core/fx.dart';
import '../core/palette.dart';
import '../core/util.dart';
import '../ui/common.dart';
import '../ui/forms.dart';
import '../ui/shell.dart' show SubPage;
import 'composer.dart';

/// Studio Médias, comme sur la maquette : titre avec « Sélectionner »,
/// chips Tout / Photos / Vidéos / Taggés avec compteurs, grille carrée de
/// vignettes (sélection par appui long ou mode sélection), barre de
/// sélection pour utiliser, étiqueter ou supprimer. L'envoi reste vers
/// media/ (dépôt de données).
class MediasScreen extends StatefulWidget {
  const MediasScreen({super.key});
  @override
  State<MediasScreen> createState() => _MediasScreenState();
}

class _MediasScreenState extends State<MediasScreen> {
  List<Map<String, dynamic>>? _files;
  Map<String, List<String>> _tags = {};
  final _sel = <String>{};
  bool _modeSel = false;
  bool _cherche = false;
  String _recherche = '';
  String _filtre = ''; // '', 'photos', 'videos', 'tagges' ou une étiquette
  String _status = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final arr = await Api.listDir('media');
      final files = <Map<String, dynamic>>[];
      for (final e in arr) {
        final o = asObj(e);
        if (o.os('type') == 'file') files.add(o);
      }
      files.sort((a, b) => b.os('name').compareTo(a.os('name')));
      final tags = await MediaTags.charge();
      if (!mounted) return;
      setState(() {
        _files = files;
        _tags = tags;
        _sel.clear();
        _modeSel = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = Api.hint(e));
    }
  }

  List<Map<String, dynamic>> get _filtrees {
    final f = _files ?? const [];
    return f.where((e) {
      final name = stripStamp(e.os('name')).toLowerCase();
      if (_recherche.isNotEmpty && !name.contains(_recherche.toLowerCase())) {
        return false;
      }
      final tags = _tags[e.os('path')] ?? const <String>[];
      switch (_filtre) {
        case 'photos':
          return kind(e.os('name')) != 'video';
        case 'videos':
          return kind(e.os('name')) == 'video';
        case 'tagges':
          return tags.isNotEmpty;
        default:
          return _filtre.isEmpty || tags.contains(_filtre);
      }
    }).toList();
  }

  int get _nbPhotos =>
      (_files ?? const []).where((e) => kind(e.os('name')) != 'video').length;
  int get _nbVideos =>
      (_files ?? const []).where((e) => kind(e.os('name')) == 'video').length;
  int get _nbTagges => (_files ?? const [])
      .where((e) => (_tags[e.os('path')] ?? const <String>[]).isNotEmpty)
      .length;

  Set<String> get _etiquettesUtilisees {
    final s = <String>{};
    _tags.forEach((_, tags) => s.addAll(tags));
    return s;
  }

  /* ---------- actions par lot ---------- */

  Future<void> _utiliserSelection() async {
    final paths = _sel.toList();
    if (paths.isEmpty) return;
    PublishDraft.media = paths.first;
    await Journal.ajoute(
      'media',
      'Média choisi pour un post',
      detail: stripStamp(paths.first.split('/').last),
    );
    _sel.clear();
    _modeSel = false;
    setState(() {});
    if (!mounted) return;
    if (paths.length > 1) {
      kToast(
        context,
        'Premier média chargé (${paths.length} sélectionnés : les autres pour de prochains posts).',
      );
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const SubPage('Composer', child: ComposerScreen()),
      ),
    );
  }

  Future<void> _etiqueter() async {
    final paths = _sel.toList();
    if (paths.isEmpty) return;
    final ed = TextEditingController(
      text: (_tags[paths.first] ?? const []).join(', '),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.p.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: ctx.p.line),
        ),
        title: Text('Étiqueter (${paths.length})', style: T.title(ctx.p)),
        content: KEdit(controller: ed, hint: 'concert, promo, photo...'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Annuler', style: TextStyle(color: ctx.p.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Enregistrer',
              style: TextStyle(
                color: ctx.p.accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final tags = ed.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    for (final p in paths) {
      await MediaTags.definit(p, tags);
    }
    if (mounted) kToast(context, 'Étiquettes enregistrées.');
    _load();
  }

  Future<void> _supprimerSelection() async {
    final paths = _sel.toList();
    if (paths.isEmpty) return;
    if (!await kConfirm(
      context,
      'Supprimer ${paths.length} fichier(s) du dépôt ?',
    )) {
      return;
    }
    var ok = 0;
    for (final p in paths) {
      final f = (_files ?? const []).where((e) => e.os('path') == p).toList();
      if (f.isEmpty) continue;
      try {
        await Api.deleteFile(p, f.first.os('name'), f.first.os('sha'));
        ok++;
      } catch (e) {
        if (mounted) kToast(context, Api.hint(e), bad: true);
      }
    }
    if (ok > 0) {
      await Journal.ajoute('media', 'Médias supprimés ($ok)');
      if (mounted) kToast(context, '$ok fichier(s) supprimé(s).');
    }
    _load();
  }

  Future<void> _uploadAll() async {
    final picked = await FilePicker.pickFiles(type: FileType.any);
    if (picked.isEmpty) return;
    setState(() => _status = 'Préparation...');
    var ok = 0;
    for (var i = 0; i < picked.length; i++) {
      final f = picked[i];
      if (f.path == null) continue;
      try {
        await Api.upload(
          File(f.path!),
          f.name,
          say: (s) {
            if (mounted) {
              setState(
                () => _status = '(${i + 1}/${picked.length}) ${f.name} : $s',
              );
            }
          },
        );
        ok++;
      } catch (e) {
        if (picked.length == 1) {
          setState(() => _status = '');
          if (mounted) kToast(context, Api.hint(e), bad: true);
          return;
        }
      }
    }
    if (ok == 0) throw Exception('Aucun fichier envoyé.');
    await Journal.ajoute('media', 'Médias envoyés ($ok)');
    setState(() => _status = '');
    if (mounted) kToast(context, '$ok fichier(s) envoyé(s).');
    _load();
  }

  /* ---------- rendu ---------- */

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    final files = _filtrees;
    return Column(
      children: [
        _pageHead(c),
        if (_cherche) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: KEdit(
              text: _recherche,
              hint: 'Chercher un fichier...',
              onChanged: (v) => setState(() => _recherche = v),
            ),
          ),
        ],
        const SizedBox(height: 8),
        _chips(c),
        if (_status.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
            child: Text(_status, style: T.caption(c)),
          ),
        const SizedBox(height: 10),
        Expanded(
          child: _files == null
              ? ListView(
                  padding: const EdgeInsets.all(14),
                  children: const [
                    KSkeleton(110),
                    SizedBox(height: 10),
                    KSkeleton(110),
                  ],
                )
              : files.isEmpty
              ? KEmpty(
                  Icons.image_outlined,
                  _recherche.isEmpty && _filtre.isEmpty
                      ? 'Aucun média. Envoie ta première image ou vidéo.'
                      : 'Aucun résultat pour ce filtre.',
                  sub: _recherche.isEmpty && _filtre.isEmpty
                      ? "Utilise l'icône d'envoi en haut."
                      : 'Essaie un autre mot ou un autre filtre.',
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 120),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                    childAspectRatio: 1,
                  ),
                  itemCount: files.length,
                  itemBuilder: (ctx, i) => _cellule(c, files[i]),
                ),
        ),
        if (_modeSel && _sel.isNotEmpty) _barreActions(c),
      ],
    );
  }

  Widget _pageHead(Palette c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Row(
        children: [
          Text('Médias', style: T.hero(c)),
          const Spacer(),
          _ic(c, Icons.search_outlined, () {
            Fx.tick();
            setState(() {
              _cherche = !_cherche;
              if (!_cherche) _recherche = '';
            });
          }),
          const SizedBox(width: 8),
          _ic(c, Icons.file_upload_outlined, _uploadAll),
          const SizedBox(width: 10),
          Press(
            onTap: () {
              Fx.tick();
              setState(() => _modeSel = !_modeSel);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Text(
                _modeSel ? 'Annuler' : 'Sélectionner',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: c.accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ic(Palette c, IconData ic, VoidCallback f) {
    return Press(
      onTap: f,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: c.chip,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(ic, size: 17, color: c.ink),
      ),
    );
  }

  Widget _chips(Palette c) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shrinkWrap: true,
        children: [
          _chip(c, 'Tout', _filtre.isEmpty, () => setState(() => _filtre = '')),
          _chip(
            c,
            'Photos $_nbPhotos',
            _filtre == 'photos',
            () => setState(() => _filtre = _filtre == 'photos' ? '' : 'photos'),
          ),
          _chip(
            c,
            'Vidéos $_nbVideos',
            _filtre == 'videos',
            () => setState(() => _filtre = _filtre == 'videos' ? '' : 'videos'),
          ),
          _chip(
            c,
            'Taggés $_nbTagges',
            _filtre == 'tagges',
            () => setState(() => _filtre = _filtre == 'tagges' ? '' : 'tagges'),
          ),
          for (final t in _etiquettesUtilisees)
            _chip(
              c,
              t,
              _filtre == t,
              () => setState(() => _filtre = _filtre == t ? '' : t),
            ),
        ],
      ),
    );
  }

  Widget _chip(Palette c, String label, bool on, VoidCallback f) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Press(
        onTap: () {
          Fx.tick();
          f();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: on ? c.accent : c.soft,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: on ? c.onAccent : c.muted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _cellule(Palette c, Map<String, dynamic> f) {
    final name = f.os('name');
    final path = f.os('path');
    final isVideo = kind(name) == 'video';
    final selected = _sel.contains(path);
    return Press(
      onLongPress: () {
        Fx.medium();
        setState(() => _modeSel = true);
        _toggle(path);
      },
      onTap: () {
        if (_modeSel) {
          _toggle(path);
        } else {
          _feuille(c, f);
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? c.accent : c.line,
                width: selected ? 2 : 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: !isVideo && f.oi('size') < 1500000
                  ? Image.network(
                      'https://api.github.com/repos/${Api.data}/contents/${Api.cp(path)}',
                      headers: {
                        'Authorization': 'Bearer ${Api.tok}',
                        'Accept': 'application/vnd.github.raw+json',
                        'User-Agent': 'kidas-controle',
                      },
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          Icon(Icons.image_outlined, size: 26, color: c.muted),
                    )
                  : Icon(
                      isVideo
                          ? Icons.play_circle_outline
                          : Icons.image_outlined,
                      size: 26,
                      color: c.muted,
                    ),
            ),
          ),
          if (_modeSel)
            Positioned(
              top: 5,
              right: 5,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: selected ? c.accent : c.card,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.accent, width: 1.5),
                ),
                child: selected
                    ? Icon(Icons.check, size: 13, color: c.onAccent)
                    : null,
              ),
            ),
        ],
      ),
    );
  }

  void _toggle(String path) {
    setState(() {
      if (_sel.contains(path)) {
        _sel.remove(path);
        if (_sel.isEmpty) _modeSel = false;
      } else {
        _sel.add(path);
      }
    });
  }

  Future<void> _feuille(Palette c, Map<String, dynamic> f) async {
    final path = f.os('path');
    final action = await kSheet<String>(
      context,
      title: stripStamp(f.os('name')),
      children: [
        _row(context, Icons.edit_outlined, 'Utiliser dans un post', 'use'),
        _row(context, Icons.sell_outlined, 'Étiqueter', 'tag'),
        _row(context, Icons.copy_outlined, 'Copier le chemin', 'copy'),
        _row(context, Icons.delete_outline, 'Supprimer', 'del'),
      ],
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'use':
        PublishDraft.media = path;
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const SubPage('Composer', child: ComposerScreen()),
          ),
        );
      case 'tag':
        setState(() {
          _sel.clear();
          _sel.add(path);
          _modeSel = true;
        });
        _etiqueter();
      case 'copy':
        await Clipboard.setData(ClipboardData(text: path));
        if (mounted) kToast(context, 'Copié.');
      case 'del':
        if (!await kConfirm(context, 'Supprimer ce fichier du dépôt ?')) return;
        try {
          await Api.deleteFile(path, f.os('name'), f.os('sha'));
          await Journal.ajoute(
            'media',
            'Média supprimé',
            detail: stripStamp(f.os('name')),
          );
          if (mounted) kToast(context, 'Supprimé.');
        } catch (e) {
          if (mounted) kToast(context, Api.hint(e), bad: true);
        }
        _load();
    }
  }

  Widget _row(BuildContext ctx, IconData ic, String label, String v) {
    final c = ctx.p;
    return Press(
      onTap: () {
        Fx.tick();
        Navigator.pop(ctx, v);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            IconBox(ic),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: c.ink,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: c.muted),
          ],
        ),
      ),
    );
  }

  /* ---------- barre de sélection ---------- */

  Widget _barreActions(Palette c) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: c.navBg,
        border: Border(top: BorderSide(color: c.navLine)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Text('${_sel.length} sélectionnée(s)', style: T.strong(c)),
            ),
            const SizedBox(width: 8),
            ActionBtn(
              'Utiliser',
              height: 38,
              variant: KBtnVariant.accent,
              job: _utiliserSelection,
            ),
            const SizedBox(width: 6),
            ActionBtn(
              'Étiqueter',
              height: 38,
              variant: KBtnVariant.ghost,
              job: _etiqueter,
            ),
            const SizedBox(width: 6),
            Press(
              onTap: () {
                Fx.tick();
                _supprimerSelection();
              },
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: c.soft,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: c.line),
                ),
                child: Icon(Icons.delete_outline, size: 17, color: c.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
