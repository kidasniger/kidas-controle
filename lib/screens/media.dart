import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/fx.dart';
import '../core/palette.dart';
import '../core/util.dart';
import '../ui/common.dart';
import '../ui/forms.dart';
import '../ui/shell.dart' show SubPage;
import 'publish.dart';

/// Médias : envoi multiple vers media/, bibliothèque avec vignettes,
/// utiliser / copier / supprimer. Port fidèle de MediaScreen.java.
class MediaScreen extends StatefulWidget {
  const MediaScreen({super.key});
  @override
  State<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends State<MediaScreen> {
  String _status = '';
  List<Map<String, dynamic>>? _files;

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
      if (!mounted) return;
      setState(() => _files = files);
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = Api.hint(e));
    }
  }

  Future<void> _uploadAll() async {
    final res = await FilePicker.platform
        .pickFiles(type: FileType.any, allowMultiple: true);
    if (res == null || res.files.isEmpty) return;
    final picked = res.files;
    setState(() => _status = 'Préparation...');
    var ok = 0;
    String last = '';
    for (var i = 0; i < picked.length; i++) {
      final f = picked[i];
      if (f.path == null) continue;
      try {
        last = await Api.upload(File(f.path!), f.name, say: (s) {
          if (mounted) {
            setState(() => _status = '(${i + 1}/${picked.length}) ${f.name} : $s');
          }
        });
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
    PublishDraft.media = last;
    setState(() => _status = '');
    if (mounted) kToast(context, '$ok fichier(s) envoyé(s).');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    final files = _files;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        KSection('Envoyer'),
        KCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
                width: double.infinity,
                child: ActionBtn('Choisir des fichiers',
                    icon: Icons.file_upload_outlined, job: _uploadAll)),
            if (_status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_status, style: T.caption(c)),
              ),
            const SizedBox(height: 8),
            Text(
              "Images et vidéos jusqu'à 50 Mo. Reprise automatique en cas de conflit avec le bot.",
              style: T.caption(c),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        KSection('Bibliothèque'),
        if (files == null)
          const KSkeleton(120)
        else if (files.isEmpty)
          KEmpty(Icons.image_outlined, 'Aucun média.')
        else ...[
          for (var i = 0; i < files.length && i < 60; i += 2)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: _MediaCell(
                    f: files[i],
                    onChanged: () => _load(),
                  ),
                ),
                const SizedBox(width: 10),
                if (i + 1 < files.length)
                  Expanded(
                    child: _MediaCell(
                      f: files[i + 1],
                      onChanged: () => _load(),
                    ),
                  )
                else
                  const Expanded(child: SizedBox.shrink()),
              ]),
            ),
          if (files.length > 60)
            KEmpty(Icons.folder_outlined,
                '60 plus récents affichés sur ${files.length}.'),
        ],
      ],
    );
  }
}

class _MediaCell extends StatefulWidget {
  final Map<String, dynamic> f;
  final VoidCallback onChanged;
  const _MediaCell({required this.f, required this.onChanged});
  @override
  State<_MediaCell> createState() => _MediaCellState();
}

class _MediaCellState extends State<_MediaCell> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    final f = widget.f;
    final name = f.os('name');
    final path = f.os('path');
    final isVideo = kind(name) == 'video';
    final ts = int.tryParse(name.split('-').first) ?? 0;

    Widget preview;
    if (isVideo) {
      preview = Icon(Icons.play_circle_outline, size: 34, color: c.muted);
    } else if (f.oi('size') < 1500000) {
      final url =
          'https://api.github.com/repos/${Api.data}/contents/${Api.cp(path)}';
      preview = Image.network(
        url,
        headers: {
          'Authorization': 'Bearer ${Api.tok}',
          'Accept': 'application/vnd.github.raw+json',
          'User-Agent': 'kidas-controle',
        },
        fit: BoxFit.cover,
        width: double.infinity,
        height: 110,
        errorBuilder: (_, __, ___) =>
            Icon(Icons.image_outlined, size: 34, color: c.muted),
      );
    } else {
      preview = Icon(Icons.image_outlined, size: 34, color: c.muted);
    }

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
          color: c.soft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
              height: 110,
              width: double.infinity,
              color: c.bg,
              child: isVideo || f.oi('size') >= 1500000
                  ? Center(child: preview)
                  : preview),
        ),
        const SizedBox(height: 8),
        Text(stripStamp(name),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: T.strong(c).copyWith(fontSize: 12.5)),
        Text(
          '${fsize(f.oi('size'))}${ts > 0 ? ' · ${fdate(ts)}' : ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: T.caption(c).copyWith(fontSize: 11.5),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: ActionBtn('Utiliser',
                height: 34,
                variant: KBtnVariant.accent,
                job: () async {
                  PublishDraft.media = path;
                  if (!mounted) return;
                  Fx.tick();
                  await Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) =>
                          const SubPage('Publier', child: PublishScreen())));
                }),
          ),
          const SizedBox(width: 6),
          _miniBtn(c, Icons.copy_outlined, () async {
            await Clipboard.setData(ClipboardData(text: path));
            if (mounted) kToast(context, 'Copié.');
          }),
          const SizedBox(width: 6),
          _miniBtn(c, Icons.delete_outline, () async {
            if (_busy) return;
            if (!await kConfirm(context, 'Supprimer ce fichier du dépôt ?')) {
              return;
            }
            setState(() => _busy = true);
            try {
              await Api.deleteFile(path, name, f.os('sha'));
              if (mounted) kToast(context, 'Supprimé.');
              widget.onChanged();
            } catch (e) {
              if (mounted) kToast(context, Api.hint(e), bad: true);
            }
            if (mounted) setState(() => _busy = false);
          }),
        ]),
      ]),
    );
  }

  Widget _miniBtn(Palette c, IconData ic, VoidCallback onTap) {
    return Press(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.line)),
        child: Icon(ic, size: 15, color: c.ink),
      ),
    );
  }
}
