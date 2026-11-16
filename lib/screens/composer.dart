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

/// Composer : écrire un post, voir l'aperçu façon Facebook, joindre un
/// média, programmer, garder un brouillon et suivre la file. Le contenu
/// part dans posts/queue.json ou posts/avance.json ; le bot publie.
class ComposerScreen extends StatefulWidget {
  const ComposerScreen({super.key});
  @override
  State<ComposerScreen> createState() => _ComposerScreenState();
}

class _ComposerScreenState extends State<ComposerScreen> {
  late final TextEditingController _ed =
      TextEditingController(text: PublishDraft.msg);
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
      throw Exception('Rien à enregistrer : écris un texte ou choisis un média.');
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
      final path = await Api.upload(File(f.path!), f.name,
          say: (s) {
            if (mounted) setState(() => _status = s);
          });
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
              side: BorderSide(color: ctx.p.line)),
          title: Text('Choisir un média', style: T.title(ctx.p)),
          children: [
            for (var i = 0; i < files.length && i < 60; i++)
              SimpleDialogOption(
                onPressed: () =>
                    Navigator.pop(ctx, files[i].os('path')),
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
                  brightness: Theme.of(ctx).brightness)),
          child: child ?? const SizedBox()),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(init),
      builder: (ctx, child) => Theme(
          data: Theme.of(ctx).copyWith(
              colorScheme: ColorScheme.fromSeed(
                  seedColor: ctx.p.accent,
                  brightness: Theme.of(ctx).brightness)),
          child: child ?? const SizedBox()),
    );
    if (t == null || !mounted) return;
    final x = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    setState(() => PublishDraft.whenMs = x.millisecondsSinceEpoch);
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
    final entry = <String, dynamic>{
      'message': text,
      'status': 'pending',
    };
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
            null);
        launched = true;
      } catch (_) {
        launched = false;
      }
    }
    await Journal.ajoute('post', 'Post mis en file',
        detail: text.isEmpty ? '(média seul)' : text);
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
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        _apercu(c),
        const SizedBox(height: 14),
        _redaction(c),
        const SizedBox(height: 14),
        _programmation(c),
        const SizedBox(height: 14),
        _brouillonsBloc(c),
        const SizedBox(height: 14),
        _fileAttente(c),
      ],
    );
  }

  /* ---------- aperçu Facebook ---------- */

  Widget _apercu(Palette c) {
    final texte = _ed.text.trim();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      KSection('Aperçu Facebook'),
      KCard(
        pad: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: c.ink, borderRadius: BorderRadius.circular(13)),
              child: Center(
                  child: Text('K',
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w900,
                          color: c.bg))),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Aboubacar Sidik | KI DAS', style: T.strong(c)),
                    Row(children: [
                      Text("à l'instant",
                          style: T.caption(c).copyWith(fontSize: 11.5)),
                      const SizedBox(width: 5),
                      Icon(Icons.public, size: 12, color: c.muted),
                    ]),
                  ]),
            ),
          ]),
          if (texte.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(texte, style: T.body(c).copyWith(fontSize: 14.5)),
          ] else ...[
            const SizedBox(height: 10),
            Text('Ton texte apparaîtra ici…',
                style: T.body(c).copyWith(color: c.muted)),
          ],
          if (PublishDraft.media.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              height: 90,
              width: double.infinity,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                  color: c.soft,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.line)),
              child: Row(children: [
                Icon(
                    kind(PublishDraft.media) == 'video'
                        ? Icons.play_circle_outline
                        : Icons.image_outlined,
                    size: 22, color: c.ink),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(_mediaName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.body(c)),
                ),
              ]),
            ),
          ],
        ]),
      ),
    ]);
  }

  /* ---------- rédaction ---------- */

  Widget _redaction(Palette c) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      KSection('Rédaction'),
      KCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          KEdit(controller: _ed, hint: 'Texte du post...', minLines: 5),
          const SizedBox(height: 6),
          Text('${_ed.text.length} caractères', style: T.caption(c)),
          if (_status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(_status, style: T.caption(c)),
            ),
          const SizedBox(height: 12),
          Text('Média (image ou vidéo)', style: T.micro(c)),
          const SizedBox(height: 4),
          Text(
            PublishDraft.media.isEmpty ? 'Aucun média' : _mediaName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PublishDraft.media.isEmpty
                ? T.body(c).copyWith(color: c.muted)
                : T.body(c),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: ActionBtn('Bibliothèque',
                  height: 38,
                  variant: KBtnVariant.ghost,
                  job: _pickLibrary),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ActionBtn('Envoyer un fichier',
                  height: 38, variant: KBtnVariant.accent, job: _upload),
            ),
            if (PublishDraft.media.isNotEmpty) ...[
              const SizedBox(width: 8),
              _iconBtn(c, Icons.close, () {
                setState(() => PublishDraft.media = '');
              }),
            ],
          ]),
        ]),
      ),
    ]);
  }

  /* ---------- programmation ---------- */

  Widget _programmation(Palette c) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      KSection('Programmation'),
      KCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            PublishDraft.whenMs > 0
                ? 'Pour le ${fdate(PublishDraft.whenMs)}'
                : 'Publication immédiate',
            style: PublishDraft.whenMs > 0
                ? T.body(c)
                : T.body(c).copyWith(color: c.muted),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: ActionBtn('Choisir date et heure',
                  height: 38,
                  variant: KBtnVariant.ghost,
                  icon: Icons.schedule_outlined,
                  job: _pickWhen),
            ),
            if (PublishDraft.whenMs > 0) ...[
              const SizedBox(width: 8),
              _iconBtn(c, Icons.close, () {
                setState(() => PublishDraft.whenMs = 0);
              }),
            ],
          ]),
          const SizedBox(height: 10),
          KSwitchRow(
            'Lancer tout de suite',
            desc: 'Sinon le contrôle automatique le prend sous 5 à 10 min.',
            value: PublishDraft.now,
            job: (v) async => PublishDraft.now = v,
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: ActionBtn('Brouillon',
                  height: 44,
                  variant: KBtnVariant.ghost,
                  icon: Icons.bookmark_border_outlined,
                  job: _sauverBrouillon),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ActionBtn('Mettre en file', job: _submit),
            ),
          ]),
        ]),
      ),
    ]);
  }

  /* ---------- brouillons ---------- */

  Widget _brouillonsBloc(Palette c) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      KSection('Brouillons'),
      if (_draftBusy)
        const KSkeleton(70)
      else if (_brouillons.isEmpty)
        KCard(
          child: Text('Aucun brouillon gardé.',
              style: T.body(c).copyWith(color: c.muted)),
        )
      else
        for (final b in _brouillons.take(6))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: KCard(
              pad: const EdgeInsets.all(12),
              child: Row(children: [
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
                            style: T.body(c)),
                        const SizedBox(height: 3),
                        Text(
                          b.whenMs > 0
                              ? 'prévu pour le ${fdate(b.whenMs)}'
                              : 'publication immédiate',
                          style: T.caption(c),
                        ),
                      ]),
                ),
                const SizedBox(width: 8),
                _iconBtn(c, Icons.open_in_new_outlined,
                    () => _chargerBrouillon(b)),
                const SizedBox(width: 6),
                _iconBtn(c, Icons.delete_outline, () async {
                  await Brouillons.supprime(b.id);
                  _loadBrouillons();
                }),
              ]),
            ),
          ),
    ]);
  }

  /* ---------- file d'attente ---------- */

  Widget _fileAttente(Palette c) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      KSection('En file et programmés'),
      if (_fileItems == null)
        const KSkeleton(70)
      else if (_fileItems!.isEmpty)
        KCard(
          child: Text('Rien en attente.',
              style: T.body(c).copyWith(color: c.muted)),
        )
      else
        for (final it in _fileItems!.take(10))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: KCard(
              pad: const EdgeInsets.all(12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Text(it.meta,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: T.caption(c))),
                      const SizedBox(width: 8),
                      StatusChip(it.statut, kind: it.kind),
                    ]),
                    const SizedBox(height: 4),
                    Text(it.corps,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: T.body(c).copyWith(fontSize: 14.5)),
                  ]),
            ),
          ),
    ]);
  }

  Future<void> _loadQueue() async {
    try {
      final out = <_QueueEntree>[];
      for (final q in const ['queue', 'avance']) {
        final a = await Api.readArr('posts/$q.json');
        for (final e in a) {
          final o = asObj(e);
          if (o.isEmpty) continue;
          out.add(_QueueEntree(o, q));
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

  Widget _iconBtn(Palette c, IconData ic, VoidCallback onTap) {
    return Press(
      onTap: () {
        Fx.tick();
        onTap();
      },
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
            color: c.soft,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: c.line)),
        child: Icon(ic, size: 16, color: c.ink),
      ),
    );
  }
}

/* ---------- entrée de file (lecture seule ici) ---------- */

class _QueueEntree {
  final Map<String, dynamic> e;
  final String src;
  const _QueueEntree(this.e, this.src);

  int get created => iso(e.os('created'));
  int get when => iso(e.os('publish_at'));

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

  int get kind => switch (e.os('status')) {
        'published' || 'done' => 1,
        'error' => 3,
        _ => 2,
      };

  String get meta {
    final b = StringBuffer(src == 'avance' ? 'Post média' : 'Post texte');
    if (when > 0) b.write(' · pour le ${fdate(when)}');
    final mp = e.os('image_path').isEmpty
        ? e.os('video_path')
        : e.os('image_path');
    if (mp.isNotEmpty) {
      b.write(' · ${stripStamp(mp.replaceFirst(RegExp(r'^media/'), ''))}');
    }
    return b.toString();
  }

  String get corps {
    final t = e.os('message');
    return t.isEmpty ? '(sans texte)' : t;
  }
}
