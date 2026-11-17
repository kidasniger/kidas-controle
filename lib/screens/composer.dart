import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/data.dart';
import '../core/fx.dart';
import '../core/palette.dart';
import '../core/util.dart';
import '../ui/common.dart';
import '../ui/forms.dart';

/// Brouillon conservé quand on change d'écran (comme dans la v1).
class PublishDraft {
  static String msg = '';
  static String media = '';
  static int whenMs = 0;
  static bool now = true;
}

/// Composer, comme sur la maquette : l'éditeur (texte + vignette du média
/// joint), trois lignes d'options (média, programmation, audience),
/// l'aperçu du rendu Facebook, la file d'attente en crans et le gros
/// bouton « Publier maintenant ». Les brouillons restent à portée via le
/// bouton d'en-tête. Le contenu part dans posts/queue.json ou
/// posts/avance.json ; le bot publie.
class ComposerScreen extends StatefulWidget {
  const ComposerScreen({super.key});
  @override
  State<ComposerScreen> createState() => _ComposerScreenState();
}

class _ComposerScreenState extends State<ComposerScreen> {
  late final TextEditingController _ed = TextEditingController(
    text: PublishDraft.msg,
  );
  String _status = '';
  List<Brouillon> _brouillons = [];
  bool _draftBusy = true;
  List<_QueueEntree>? _fileItems;

  @override
  void initState() {
    super.initState();
    _ed.addListener(() {
      PublishDraft.msg = _ed.text;
      if (mounted) setState(() {});
    });
    _loadBrouillons();
    _loadQueue();
  }

  @override
  void dispose() {
    _ed.dispose();
    super.dispose();
  }

  String get _mediaName => PublishDraft.media.isEmpty
      ? ''
      : stripStamp(PublishDraft.media.replaceFirst(RegExp(r'^media/'), ''));

  /* ---------- chargement des médias du dépôt (aperçus) ---------- */

  String _mediaUrl(String path) =>
      'https://api.github.com/repos/${Api.data}/contents/${Api.cp(path)}';

  Map<String, String> get _mediaHeaders => {
    'Authorization': 'Bearer ${Api.tok}',
    'Accept': 'application/vnd.github.raw+json',
    'User-Agent': 'kidas-controle',
  };

  /* ---------- brouillons ---------- */

  Future<void> _loadBrouillons() async {
    try {
      final b = await Brouillons.charge();
      if (!mounted) return;
      setState(() {
        _brouillons = b.reversed.toList();
        _draftBusy = false;
      });
    } catch (_) {
      if (mounted) setState(() => _draftBusy = false);
    }
  }

  Future<void> _sauverBrouillon() async {
    final t = _ed.text.trim();
    if (t.isEmpty && PublishDraft.media.isEmpty) {
      throw Exception(
        'Rien à enregistrer : écris un texte ou choisis un média.',
      );
    }
    await Brouillons.ajoute(t, PublishDraft.media, PublishDraft.whenMs);
    if (!mounted) return;
    kToast(context, 'Brouillon enregistré.');
    _loadBrouillons();
  }

  Future<void> _chargerBrouillon(Brouillon b) async {
    setState(() {
      _ed.text = b.texte;
      PublishDraft.msg = b.texte;
      PublishDraft.media = b.media;
      PublishDraft.whenMs = b.whenMs;
    });
    if (mounted) kToast(context, 'Brouillon chargé.');
  }

  /* ---------- média ---------- */

  Future<void> _upload() async {
    final f = await FilePicker.pickFile(type: FileType.any);
    if (f == null || f.path == null) return;
    setState(() => _status = 'Envoi...');
    try {
      final path = await Api.upload(
        File(f.path!),
        f.name,
        say: (s) {
          if (mounted) setState(() => _status = s);
        },
      );
      PublishDraft.media = path;
      setState(() => _status = '');
      if (mounted) kToast(context, 'Média envoyé.');
      await Journal.ajoute('media', 'Média envoyé', detail: f.name);
    } catch (e) {
      setState(() => _status = '');
      if (mounted) kToast(context, Api.hint(e), bad: true);
    }
  }

  Future<void> _pickLibrary() async {
    setState(() => _status = 'Chargement de la bibliothèque...');
    try {
      final arr = await Api.listDir('media');
      final files = <Map<String, dynamic>>[];
      for (final e in arr) {
        final o = asObj(e);
        if (o.os('type') == 'file') files.add(o);
      }
      files.sort((a, b) => b.os('name').compareTo(a.os('name')));
      if (!mounted) return;
      setState(() => _status = '');
      if (files.isEmpty) {
        kToast(context, 'Aucun média dans la bibliothèque.');
        return;
      }
      final path = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          backgroundColor: ctx.p.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: ctx.p.line),
          ),
          title: Text('Choisir un média', style: T.title(ctx.p)),
          children: [
            for (var i = 0; i < files.length && i < 60; i++)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, files[i].os('path')),
                child: Text(
                  '${stripStamp(files[i].os('name'))} (${fsize(files[i].oi('size'))})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.body(ctx.p),
                ),
              ),
          ],
        ),
      );
      if (path != null) setState(() => PublishDraft.media = path);
    } catch (e) {
      setState(() => _status = '');
      if (mounted) kToast(context, Api.hint(e), bad: true);
    }
  }

  Future<void> _pickWhen() async {
    Fx.tick();
    final now = DateTime.now();
    final init = PublishDraft.whenMs > 0
        ? DateTime.fromMillisecondsSinceEpoch(PublishDraft.whenMs)
        : now.add(const Duration(hours: 1));
    final d = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: now,
      lastDate: now.add(const Duration(days: 60)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: ctx.p.accent,
            brightness: Theme.of(ctx).brightness,
          ),
        ),
        child: child ?? const SizedBox(),
      ),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(init),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: ctx.p.accent,
            brightness: Theme.of(ctx).brightness,
          ),
        ),
        child: child ?? const SizedBox(),
      ),
    );
    if (t == null || !mounted) return;
    final x = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    setState(() => PublishDraft.whenMs = x.millisecondsSinceEpoch);
  }

  /* ---------- feuilles d'options (comme les lignes de la maquette) ---------- */

  void _feuilleMedia(Palette c) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.card,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        side: BorderSide(color: c.line),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Photo ou vidéo', style: T.title(c)),
              const SizedBox(height: 4),
              Text(
                PublishDraft.media.isEmpty
                    ? 'Aucun fichier joint.'
                    : 'Joint : $_mediaName',
                style: T.caption(c),
              ),
              const SizedBox(height: 14),
              ActionBtn(
                'Choisir dans la bibliothèque',
                variant: KBtnVariant.ghost,
                height: 44,
                job: () async {
                  Navigator.pop(ctx);
                  await _pickLibrary();
                },
              ),
              const SizedBox(height: 8),
              ActionBtn(
                'Envoyer un fichier',
                height: 44,
                job: () async {
                  Navigator.pop(ctx);
                  await _upload();
                },
              ),
              if (PublishDraft.media.isNotEmpty) ...[
                const SizedBox(height: 8),
                ActionBtn(
                  'Retirer le média',
                  variant: KBtnVariant.danger,
                  height: 44,
                  job: () async {
                    Navigator.pop(ctx);
                    if (mounted) setState(() => PublishDraft.media = '');
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _feuilleProg(Palette c) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.card,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        side: BorderSide(color: c.line),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Programmer', style: T.title(c)),
              const SizedBox(height: 4),
              Text(
                PublishDraft.whenMs > 0
                    ? 'Pour le ${fdate(PublishDraft.whenMs)}'
                    : 'Publication immédiate.',
                style: T.caption(c),
              ),
              const SizedBox(height: 14),
              ActionBtn(
                'Choisir date et heure',
                icon: Icons.schedule_outlined,
                variant: KBtnVariant.ghost,
                height: 44,
                job: () async {
                  Navigator.pop(ctx);
                  await _pickWhen();
                },
              ),
              if (PublishDraft.whenMs > 0) ...[
                const SizedBox(height: 8),
                ActionBtn(
                  'Annuler la programmation',
                  variant: KBtnVariant.danger,
                  height: 44,
                  job: () async {
                    Navigator.pop(ctx);
                    if (mounted) setState(() => PublishDraft.whenMs = 0);
                  },
                ),
              ],
              const SizedBox(height: 14),
              KSwitchRow(
                'Lancer tout de suite',
                desc: 'Sinon le contrôle automatique le prend sous 5 à 10 min.',
                value: PublishDraft.now,
                job: (v) async => PublishDraft.now = v,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _feuilleBrouillons(Palette c) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.card,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        side: BorderSide(color: c.line),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setF) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Brouillons', style: T.title(c)),
                const SizedBox(height: 4),
                Text(
                  PublishDraft.msg.trim().isEmpty && PublishDraft.media.isEmpty
                      ? 'Écris ou charge un texte pour en garder un.'
                      : 'Garde le texte actuel pour le reprendre plus tard.',
                  style: T.caption(c),
                ),
                const SizedBox(height: 14),
                ActionBtn(
                  'Garder le texte actuel en brouillon',
                  icon: Icons.bookmark_border_outlined,
                  variant: KBtnVariant.ghost,
                  height: 44,
                  job: () async {
                    Navigator.pop(ctx2);
                    await _sauverBrouillon();
                  },
                ),
                const SizedBox(height: 14),
                if (_draftBusy)
                  const KSkeleton(60)
                else if (_brouillons.isEmpty)
                  Text(
                    'Aucun brouillon gardé.',
                    style: T.body(c).copyWith(color: c.muted),
                  )
                else
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final b in _brouillons.take(12))
                            _ligneBrouillon(c, b, setF, ctx2),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _ligneBrouillon(
    Palette c,
    Brouillon b,
    StateSetter setF,
    BuildContext ctx2,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: KCard(
        pad: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    b.texte.isEmpty
                        ? '(média seul)'
                        : (b.texte.length > 80
                              ? '${b.texte.substring(0, 80)}…'
                              : b.texte),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: T.body(c),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    b.whenMs > 0
                        ? 'prévu pour le ${fdate(b.whenMs)}'
                        : 'publication immédiate',
                    style: T.caption(c),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Press(
              onTap: () {
                Navigator.pop(context);
                _chargerBrouillon(b);
              },
              child: Icon(
                Icons.open_in_new_outlined,
                size: 18,
                color: c.accent,
              ),
            ),
            const SizedBox(width: 12),
            Press(
              onTap: () async {
                await Brouillons.supprime(b.id);
                _loadBrouillons();
                if (ctx2.mounted) setF(() {});
              },
              child: Icon(Icons.delete_outline, size: 18, color: c.muted),
            ),
          ],
        ),
      ),
    );
  }

  /* ---------- mise en file ---------- */

  Future<void> _submit() async {
    final text = _ed.text.trim();
    final mediaP = PublishDraft.media;
    final when = PublishDraft.whenMs;
    final launch = PublishDraft.now;
    if (text.isEmpty && mediaP.isEmpty) {
      throw Exception('Écris un texte ou choisis un média.');
    }
    final entry = <String, dynamic>{'message': text, 'status': 'pending'};
    var file = 'posts/queue.json';
    if (mediaP.isNotEmpty) {
      entry[kind(mediaP) == 'video' ? 'video_path' : 'image_path'] = mediaP;
      file = 'posts/avance.json';
    }
    if (when > 0) {
      final d = when - DateTime.now().millisecondsSinceEpoch;
      if (d < 10 * 60000) {
        throw Exception('La programmation doit être à plus de 10 minutes.');
      }
      if (d > 30 * 86400000) {
        throw Exception('La programmation est limitée à 30 jours.');
      }
      entry['publish_at'] = isoOf(when);
      file = 'posts/avance.json';
    }
    await Api.updateJson(file, true, (cur) {
      final a = (cur is List ? cur : <dynamic>[]).toList();
      a.add(entry);
      return a;
    }, 'Nouveau post (appli de contrôle)');
    var launched = false;
    if (launch) {
      try {
        await Api.dispatch(
          file == 'posts/queue.json' ? 'publier.yml' : 'publier-avance.yml',
          null,
        );
        launched = true;
      } catch (_) {
        launched = false;
      }
    }
    await Journal.ajoute(
      'post',
      'Post mis en file',
      detail: text.isEmpty ? '(média seul)' : text,
    );
    _ed.clear();
    PublishDraft.msg = '';
    PublishDraft.media = '';
    PublishDraft.whenMs = 0;
    PublishDraft.now = true;
    if (!mounted) return;
    setState(() {});
    _loadQueue();
    final okMsg = launch
        ? (launched
              ? 'Mis en file et lancé.'
              : 'Mis en file, mais pas lancé : traité sous 5 à 10 min.')
        : 'Mis en file (traité sous 5 à 10 min).';
    if (!mounted) return;
    kToast(context, okMsg);
  }

  /* ---------- rendu ---------- */

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 96),
      children: [
        _pageHead(c),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: _editeur(c),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: _options(c),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: KSection('Aperçu Facebook'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: _apercu(c),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: KSection("File d'attente"),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: _fileAttente(c),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: ActionBtn(
            PublishDraft.whenMs > 0
                ? 'Programmer ce post'
                : 'Publier maintenant',
            height: 50,
            job: _submit,
          ),
        ),
      ],
    );
  }

  Widget _pageHead(Palette c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Text('Composer', style: T.hero(c)),
          const Spacer(),
          Press(
            onTap: () {
              Fx.tick();
              _feuilleBrouillons(c);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Text(
                'Brouillons',
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

  /* ---------- éditeur : texte + vignette du média joint ---------- */

  Widget _editeur(Palette c) {
    return KCard(
      pad: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KEdit(
            controller: _ed,
            hint: 'Texte du post...',
            minLines: 4,
            maxLines: 10,
          ),
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(_status, style: T.caption(c)),
          ],
          if (PublishDraft.media.isNotEmpty) ...[
            const SizedBox(height: 10),
            _vignetteMedia(c),
          ],
        ],
      ),
    );
  }

  Widget _vignetteMedia(Palette c) {
    final m = PublishDraft.media;
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: 150,
            width: double.infinity,
            child: kind(m) == 'video'
                ? Container(
                    color: c.soft,
                    child: Icon(
                      Icons.play_circle_outline,
                      size: 34,
                      color: c.ink,
                    ),
                  )
                : Image.network(
                    _mediaUrl(m),
                    headers: _mediaHeaders,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: c.soft,
                      child: Icon(
                        Icons.image_outlined,
                        size: 26,
                        color: c.muted,
                      ),
                    ),
                  ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Press(
            onTap: () {
              Fx.tick();
              setState(() => PublishDraft.media = '');
            },
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .55),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  /* ---------- options : média, programmation, audience ---------- */

  Widget _options(Palette c) {
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line),
      ),
      child: Column(
        children: [
          _optRow(
            c,
            Icons.image_outlined,
            'Photo ou vidéo',
            PublishDraft.media.isEmpty ? 'Aucun fichier joint' : _mediaName,
            () => _feuilleMedia(c),
          ),
          Divider(height: 1, thickness: 1, color: c.line, indent: 52),
          _optRow(
            c,
            Icons.event_outlined,
            'Programmer',
            PublishDraft.whenMs > 0
                ? 'Pour le ${fdate(PublishDraft.whenMs)}'
                : 'Publication immédiate',
            () => _feuilleProg(c),
          ),
          Divider(height: 1, thickness: 1, color: c.line, indent: 52),
          _optRow(c, Icons.public, 'Audience', 'Public', () {
            Fx.tick();
            kToast(context, 'Le bot publie toujours en public.');
          }),
        ],
      ),
    );
  }

  Widget _optRow(
    Palette c,
    IconData ic,
    String titre,
    String sous,
    VoidCallback f,
  ) {
    return Press(
      onTap: f,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: c.soft,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(ic, size: 15, color: c.ink),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titre, style: T.strong(c).copyWith(fontSize: 14)),
                  const SizedBox(height: 1),
                  Text(
                    sous,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.caption(c),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: c.muted),
          ],
        ),
      ),
    );
  }

  /* ---------- aperçu Facebook ---------- */

  Widget _apercu(Palette c) {
    final texte = _ed.text.trim();
    final planifie = PublishDraft.whenMs > 0;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: c.ink,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'K',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: c.bg,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Aboubacar Sidik | KI DAS',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: T.strong(c),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: c.accent,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check,
                              size: 10,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            planifie
                                ? relMs(PublishDraft.whenMs)
                                : "à l'instant",
                            style: T.caption(c).copyWith(fontSize: 11.5),
                          ),
                          const SizedBox(width: 5),
                          Icon(Icons.public, size: 12, color: c.muted),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Text(
              texte.isEmpty ? 'Ton texte apparaîtra ici…' : texte,
              style: texte.isEmpty
                  ? T.body(c).copyWith(color: c.muted)
                  : T.body(c).copyWith(fontSize: 14.5),
            ),
          ),
          _apercuMedia(c),
          Container(height: 1, color: c.line),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              children: [
                Icon(Icons.thumb_up_outlined, size: 13, color: c.muted),
                const SizedBox(width: 5),
                Text('—', style: T.caption(c)),
                const Spacer(),
                Text('0 commentaire · 0 partage', style: T.caption(c)),
              ],
            ),
          ),
          Container(height: 1, color: c.line),
          Row(
            children: [
              _act(c, Icons.thumb_up_outlined, "J'aime"),
              Container(width: 1, height: 34, color: c.line),
              _act(c, Icons.chat_bubble_outline, 'Commenter'),
              Container(width: 1, height: 34, color: c.line),
              _act(c, Icons.share_outlined, 'Partager'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _apercuMedia(Palette c) {
    final m = PublishDraft.media;
    if (m.isEmpty) return const SizedBox.shrink();
    if (kind(m) == 'video') {
      return Container(
        height: 190,
        width: double.infinity,
        color: c.soft,
        child: Icon(Icons.play_circle_outline, size: 40, color: c.ink),
      );
    }
    return SizedBox(
      height: 190,
      width: double.infinity,
      child: Image.network(
        _mediaUrl(m),
        headers: _mediaHeaders,
        fit: BoxFit.cover,
        loadingBuilder: (_, child, prog) =>
            prog != null &&
                prog.expectedTotalBytes != null &&
                prog.cumulativeBytesLoaded < prog.expectedTotalBytes!
            ? Container(color: c.soft)
            : child,
        errorBuilder: (_, __, ___) => Container(
          color: c.soft,
          child: Icon(Icons.image_outlined, size: 30, color: c.muted),
        ),
      ),
    );
  }

  Widget _act(Palette c, IconData ic, String label) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(ic, size: 14, color: c.muted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: c.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /* ---------- file d'attente : crans avec vignette ---------- */

  Widget _fileAttente(Palette c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_fileItems == null)
          const KSkeleton(70)
        else if (_fileItems!.isEmpty)
          KEmpty(
            Icons.schedule_outlined,
            'Rien en file.',
            sub: 'Les posts mis en file attendent le cycle du bot.',
          )
        else
          Container(
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.line),
            ),
            child: Column(
              children: [
                for (var i = 0; i < _fileItems!.length && i < 10; i++) ...[
                  if (i > 0) Divider(height: 1, thickness: 1, color: c.line),
                  _slot(c, _fileItems![i]),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _slot(Palette c, _QueueEntree it) {
    final m = it.mediaPath;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Container(
              width: 44,
              height: 33,
              color: c.soft,
              child: m.isEmpty
                  ? Icon(Icons.description_outlined, size: 15, color: c.muted)
                  : it.isVideo
                  ? Icon(Icons.play_circle_outline, size: 17, color: c.ink)
                  : Image.network(
                      _mediaUrl(m),
                      headers: _mediaHeaders,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          Icon(Icons.image_outlined, size: 15, color: c.muted),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(it.st, style: T.strong(c).copyWith(fontSize: 12.5)),
                const SizedBox(height: 2),
                Text(
                  it.ss,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: T.caption(c),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadQueue() async {
    try {
      final out = <_QueueEntree>[];
      for (final q in const ['queue', 'avance']) {
        final a = await Api.readArr('posts/$q.json');
        for (final e in a) {
          final o = asObj(e);
          if (o.isEmpty) continue;
          out.add(_QueueEntree(o));
        }
      }
      out.sort((a, b) {
        final wa = a.when, wb = b.when;
        if (wa != wb && (wa > 0 || wb > 0)) return wb.compareTo(wa);
        return b.created.compareTo(a.created);
      });
      if (!mounted) return;
      setState(() => _fileItems = out);
    } catch (_) {
      if (mounted) setState(() => _fileItems = const []);
    }
  }
}

/* ---------- entrée de file (lecture seule ici) ---------- */

class _QueueEntree {
  final Map<String, dynamic> e;
  const _QueueEntree(this.e);

  int get created => iso(e.os('created'));
  int get when => iso(e.os('publish_at'));

  String get mediaPath =>
      e.os('image_path').isEmpty ? e.os('video_path') : e.os('image_path');

  bool get isVideo => mediaPath.isNotEmpty && kind(mediaPath) == 'video';

  String get statut {
    final st = e.os('status');
    return switch (st) {
      'published' => 'Publié',
      'done' => 'Fait',
      'error' => 'Erreur',
      'cancelled' => 'Annulé',
      'scheduled' => 'Programmé',
      _ => 'En attente',
    };
  }

  bool get fini =>
      statut == 'Publié' ||
      statut == 'Fait' ||
      statut == 'Erreur' ||
      statut == 'Annulé';

  /// Première ligne du cran : état réel, sinon la date prévue.
  String get st => fini ? statut : (when > 0 ? fdate(when) : 'En attente');

  /// Deuxième ligne : le texte, sinon le nom du média, sinon rien.
  String get ss {
    final t = e.os('message').trim();
    if (t.isNotEmpty) return t;
    if (mediaPath.isNotEmpty) {
      return stripStamp(mediaPath.replaceFirst(RegExp(r'^media/'), ''));
    }
    return '(sans texte)';
  }
}
