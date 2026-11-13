import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/fx.dart';
import '../core/palette.dart';
import '../core/util.dart';
import '../ui/common.dart';
import '../ui/forms.dart';

/// Brouillon conservé quand on change d'écran (comme les statics Java).
class PublishDraft {
  static String msg = '';
  static String media = '';
  static int whenMs = 0;
  static bool now = true;
}

/// Publier : texte, média, programmation, files d'attente.
/// Port fidèle de PublishScreen.java.
class PublishScreen extends StatefulWidget {
  const PublishScreen({super.key});
  @override
  State<PublishScreen> createState() => _PublishScreenState();
}

class _PublishScreenState extends State<PublishScreen> {
  late final TextEditingController _ed =
      TextEditingController(text: PublishDraft.msg);
  String _status = '';

  @override
  void initState() {
    super.initState();
    _ed.addListener(() => PublishDraft.msg = _ed.text);
  }

  @override
  void dispose() {
    _ed.dispose();
    super.dispose();
  }

  String get _mediaName => PublishDraft.media.isEmpty
      ? ''
      : stripStamp(PublishDraft.media.replaceFirst(RegExp(r'^media/'), ''));

  /* ---------- envoi ---------- */

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
      setState(() => _status = 'Envoyé.');
      kToast(context, 'Média envoyé.');
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
      builder: (ctx, child) =>
          Theme(data: Theme.of(ctx).copyWith(colorScheme: ColorScheme.fromSeed(seedColor: ctx.p.accent, brightness: Theme.of(ctx).brightness)), child: child ?? const SizedBox()),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(init),
      builder: (ctx, child) =>
          Theme(data: Theme.of(ctx).copyWith(colorScheme: ColorScheme.fromSeed(seedColor: ctx.p.accent, brightness: Theme.of(ctx).brightness)), child: child ?? const SizedBox()),
    );
    if (t == null || !mounted) return;
    final x = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    setState(() => PublishDraft.whenMs = x.millisecondsSinceEpoch);
  }

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
    _ed.clear();
    PublishDraft.msg = '';
    PublishDraft.media = '';
    PublishDraft.whenMs = 0;
    PublishDraft.now = true;
    if (!mounted) return;
    setState(() {});
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
        KSection('Nouveau post'),
        KCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            KEdit(controller: _ed, hint: 'Texte du post...', minLines: 5),
            const SizedBox(height: 6),
            Text('${_ed.text.length} caractères', style: T.caption(c)),
            const SizedBox(height: 12),
            Text('Média (image ou vidéo)', style: T.micro(c)),
            const SizedBox(height: 4),
            Text(
              PublishDraft.media.isEmpty
                  ? 'Aucun média'
                  : _mediaName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PublishDraft.media.isEmpty
                  ? T.body(c).copyWith(color: c.muted)
                  : T.body(c),
            ),
            if (_status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(_status, style: T.caption(c)),
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
                child: ActionBtn('Envoyer',
                    height: 38, variant: KBtnVariant.accent, job: _upload),
              ),
              if (PublishDraft.media.isNotEmpty) ...[
                const SizedBox(width: 8),
                _iconBtn(c, Icons.close, () {
                  setState(() => PublishDraft.media = '');
                }),
              ],
            ]),
            const SizedBox(height: 16),
            Text('Programmer (facultatif)', style: T.micro(c)),
            const SizedBox(height: 4),
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
            const SizedBox(height: 10),
            SizedBox(
                width: double.infinity,
                child: ActionBtn('Mettre en file', job: _submit)),
          ]),
        ),
        const SizedBox(height: 16),
        _QueuesBlock(onChanged: () {}),
      ],
    );
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

/* ---------- files d'attente (port de loadQueues / card) ---------- */

class _QueuesBlock extends StatefulWidget {
  final VoidCallback onChanged;
  const _QueuesBlock({required this.onChanged});
  @override
  State<_QueuesBlock> createState() => _QueuesBlockState();
}

class _QueueItem {
  final Map<String, dynamic> e;
  final int i;
  final int src;
  _QueueItem(this.e, this.i, this.src);
}

class _QueuesBlockState extends State<_QueuesBlock> {
  List<_QueueItem>? _items;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final errs = <String>[];
    final items = <_QueueItem>[];
    await Future.wait<dynamic>([
      for (var s = 0; s < Api.queues.length; s++)
        Api.readArr('posts/${Api.queues[s]}.json').then((a) {
          for (var i = 0; i < a.length; i++) {
            final o = asObj(a[i]);
            if (o.isNotEmpty) items.add(_QueueItem(o, i, s));
          }
        }).catchError((Object e) {
          errs.add(Api.hint(e));
        }),
    ]);
    if (!mounted) return;
    setState(() {
      if (items.isEmpty && errs.isNotEmpty) {
        _err = errs.first;
      } else {
        _err = null;
      }
      _items = items;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      KSection("Files d'attente"),
      if (_items == null)
        const KSkeleton(90)
      else if (_err != null)
        ErrBox(_err!)
      else ...[
        ..._pendingCards(c),
        if (_historyCards(c).isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('HISTORIQUE RÉCENT', style: T.micro(c)),
          const SizedBox(height: 8),
          ..._historyCards(c),
        ],
        if (_items!.isEmpty)
          KEmpty(Icons.inbox_outlined, 'Rien dans les files.'),
      ],
    ]);
  }

  List<Widget> _pendingCards(Palette c) {
    final out = <Widget>[];
    for (var k = _items!.length - 1; k >= 0; k--) {
      final it = _items![k];
      if (it.e.os('status') == 'pending') {
        out.add(Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _QueueCard(item: it, onDone: () {
              widget.onChanged();
              _load();
            })));
      }
    }
    return out;
  }

  List<Widget> _historyCards(Palette c) {
    final out = <Widget>[];
    var n = 0;
    for (var k = _items!.length - 1; k >= 0 && n < 25; k--) {
      final it = _items![k];
      if (it.e.os('status') != 'pending') {
        n++;
        out.add(Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _QueueCard(item: it, onDone: () {
              widget.onChanged();
              _load();
            })));
      }
    }
    return out;
  }
}

const _statusLabels = {
  'published': ('Publié', 1),
  'replied': ('Répondu', 1),
  'done': ('Fait', 1),
  'scheduled': ('Programmé', 2),
  'error': ('Erreur', 3),
  'cancelled': ('Annulé', 0),
  'pending': ('En attente', 2),
};

class _QueueCard extends StatelessWidget {
  final _QueueItem item;
  final VoidCallback onDone;
  const _QueueCard({required this.item, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    final e = item.e;
    final st = e.os('status');
    final (txt, kind) =
        _statusLabels[st] ?? (st.isEmpty ? '?' : st, 0);
    final meta = StringBuffer(queuesLibelles[Api.queues[item.src]] ?? '');
    if (e.os('publish_at').isNotEmpty) {
      meta.write(' · pour le ${fdate(iso(e.os('publish_at')))}');
    }
    final mp = e.os('image_path').isEmpty
        ? e.os('video_path')
        : e.os('image_path');
    if (mp.isNotEmpty) meta.write(' · ${stripStamp(mp.replaceFirst(RegExp(r'^media/'), ''))}');
    if (e.os('action').isNotEmpty) meta.write(' · ${e.os('action')}');
    var body = e.os('message');
    if (body.isEmpty) {
      body = e.os('comment_id').isEmpty
          ? e.os('post_id')
          : e.os('comment_id');
    }
    return KCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(meta.toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: T.caption(c))),
          const SizedBox(width: 8),
          StatusChip(txt, kind: kind),
        ]),
        const SizedBox(height: 4),
        Text(body,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: T.body(c).copyWith(fontSize: 14.5)),
        if (st == 'pending') ...[
          const SizedBox(height: 10),
          ActionBtn('Annuler',
              height: 38,
              variant: KBtnVariant.danger,
              job: () async {
                if (!await kConfirm(context, 'Annuler cette entrée ?')) {
                  throw Cancelled();
                }
                await _setStatus(context, 'cancelled');
              },
              ok: 'Annulé.',
              after: onDone),
        ] else if (st == 'error') ...[
          const SizedBox(height: 10),
          ActionBtn('Remettre en attente',
              height: 38,
              variant: KBtnVariant.ghost,
              icon: Icons.refresh,
              job: () => _setStatus(context, 'pending'),
              ok: 'Remis en attente.',
              after: onDone),
        ],
      ]),
    );
  }

  Future<void> _setStatus(BuildContext context, String s) async {
    await Api.updateJson('posts/${Api.queues[item.src]}.json', true, (cur) {
      final a = (cur is List ? cur : <dynamic>[]).toList();
      final t = a.length > item.i ? asObj(a[item.i]) : <String, dynamic>{};
      if (t.isEmpty ||
          t.os('message') != item.e.os('message') ||
          t.os('comment_id') != item.e.os('comment_id')) {
        throw Exception('Le fichier a changé, actualise l\'écran.');
      }
      t['status'] = s;
      a[item.i] = t;
      return a;
    }, 'Mise à jour du statut (appli de contrôle)');
  }
}
