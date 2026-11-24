import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/backup.dart';
import '../core/diagnostics.dart';
import '../core/palette.dart';
import '../ui/common.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  DiagnosticReport? _report;
  bool _busy = false;
  String? _error;

  Future<void> _run() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final report = await Diagnostics.run().timeout(
        const Duration(seconds: 45),
        onTimeout: () => throw Exception(
          'Le diagnostic dépasse 45 secondes. Vérifie la connexion puis réessaie.',
        ),
      );
      if (mounted) setState(() => _report = report);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    final report = _report;
    final checks = report?.checks ?? const <DiagnosticCheck>[];
    final errors = checks.where((x) => x.level == CheckLevel.error).length;
    final warnings = checks.where((x) => x.level == CheckLevel.warning).length;
    final passed = checks.where((x) => x.level == CheckLevel.success).length;
    final healthy = report != null && errors == 0 && warnings == 0;

    return RefreshIndicator(
      onRefresh: _run,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 34),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
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
                      decoration: BoxDecoration(
                        color: c.accent.withValues(alpha: .13),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(Icons.health_and_safety_outlined,
                          color: c.accent, size: 23),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Centre de diagnostic', style: T.title(c)),
                          const SizedBox(height: 3),
                          Text(
                            'Contrôle des connexions et services',
                            style: T.caption(c),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Relancer le diagnostic',
                      onPressed: _busy ? null : _run,
                      icon: _busy
                          ? SizedBox(
                              width: 19,
                              height: 19,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: c.accent,
                              ),
                            )
                          : Icon(Icons.refresh_rounded, color: c.accent),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _busy
                        ? c.accent.withValues(alpha: .08)
                        : report == null
                            ? c.chip
                            : healthy
                                ? Colors.green.withValues(alpha: .09)
                                : errors > 0
                                    ? Colors.red.withValues(alpha: .08)
                                    : Colors.orange.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: _busy
                          ? c.accent.withValues(alpha: .25)
                          : report == null
                              ? c.line
                              : healthy
                                  ? Colors.green.withValues(alpha: .25)
                                  : errors > 0
                                      ? Colors.red.withValues(alpha: .25)
                                      : Colors.orange.withValues(alpha: .25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _busy
                            ? Icons.sync_rounded
                            : report == null
                                ? Icons.hourglass_empty_rounded
                                : healthy
                                    ? Icons.check_circle_rounded
                                    : errors > 0
                                        ? Icons.error_rounded
                                        : Icons.warning_amber_rounded,
                        color: _busy
                            ? c.accent
                            : report == null
                                ? c.muted
                                : healthy
                                    ? Colors.green
                                    : errors > 0
                                        ? Colors.red
                                        : Colors.orange,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _busy
                                  ? 'Vérification en cours'
                                  : report == null
                                      ? 'Diagnostic non effectué'
                                      : healthy
                                          ? 'Tous les contrôles sont corrects'
                                          : 'Une attention est nécessaire',
                              style: T.strong(c),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _busy
                                  ? 'Lecture des services. Aucun workflow ne sera lancé ou arrêté.'
                                  : report == null
                                      ? 'Lance une vérification pour obtenir un état.'
                                      : '$passed réussi(s) · $warnings avertissement(s) · $errors erreur(s)',
                              style: T.caption(c),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_busy) ...[
                  const SizedBox(height: 13),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: const LinearProgressIndicator(minHeight: 4),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: T.caption(c).copyWith(color: Colors.red)),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _busy ? null : _run,
                      icon: const Icon(Icons.replay_rounded),
                      label: const Text('Réessayer'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text('ÉTAT DES SERVICES', style: T.micro(c)),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(child: _metric(c, 'OK', passed, Colors.green, Icons.check_circle_outline_rounded)),
              const SizedBox(width: 8),
              Expanded(child: _metric(c, 'À vérifier', warnings, Colors.orange, Icons.warning_amber_rounded)),
              const SizedBox(width: 8),
              Expanded(child: _metric(c, 'Erreurs', errors, Colors.red, Icons.error_outline_rounded)),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: Text('RÉSULTATS DÉTAILLÉS', style: T.micro(c))),
              if (report != null)
                Text(
                  '${checks.length} contrôles',
                  style: T.caption(c),
                ),
            ],
          ),
          const SizedBox(height: 9),
          if (report == null && !_busy && _error == null)
            KCard(
              child: Text(
                'Les résultats du diagnostic apparaîtront ici.',
                style: T.caption(c),
              ),
            ),
          for (final check in checks) ...[
            _checkTile(c, check),
            const SizedBox(height: 8),
          ],
          if (report != null) ...[
            const SizedBox(height: 5),
            Text(
              'Dernière vérification : ${_formatDate(report.checkedAt.toLocal())}',
              style: T.caption(c),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.chip,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, color: c.muted, size: 19),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Diagnostic en lecture seule : aucun workflow GitHub n’est démarré, arrêté ou modifié.',
                      style: T.caption(c),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metric(Palette c, String label, int value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 8),
          Text(value.toString(), style: T.strong(c).copyWith(fontSize: 22, color: color)),
          Text(label, style: T.caption(c).copyWith(fontSize: 10)),
        ],
      ),
    );
  }

  Widget _checkTile(Palette c, DiagnosticCheck check) {
    final color = switch (check.level) {
      CheckLevel.success => Colors.green,
      CheckLevel.warning => Colors.orange,
      CheckLevel.error => Colors.red,
    };
    final icon = switch (check.level) {
      CheckLevel.success => Icons.check_circle_rounded,
      CheckLevel.warning => Icons.warning_amber_rounded,
      CheckLevel.error => Icons.error_rounded,
    };
    final label = switch (check.level) {
      CheckLevel.success => 'OK',
      CheckLevel.warning => 'À vérifier',
      CheckLevel.error => 'Erreur',
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: c.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(check.title, style: T.strong(c)),
                const SizedBox(height: 4),
                Text(check.detail, style: T.caption(c)),
                const SizedBox(height: 7),
                Text(
                  label.toUpperCase(),
                  style: T.micro(c).copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} à ${two(date.hour)}:${two(date.minute)}';
  }
}

class SettingsBackupScreen extends StatefulWidget {
  const SettingsBackupScreen({super.key});

  @override
  State<SettingsBackupScreen> createState() => _SettingsBackupScreenState();
}

class _SettingsBackupScreenState extends State<SettingsBackupScreen> {
  bool _busy = false;
  String? _lastFile;

  Future<void> _create() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await AppBackup.create();
      final destination = await FilePicker.saveFile(
        fileName: file.uri.pathSegments.last,
        bytes: await file.readAsBytes(),
        mimeType: 'application/json',
      );
      if (!mounted) return;
      setState(() => _lastFile = destination?.toString() ?? file.path);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sauvegarde créée sur cet appareil.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Échec de la sauvegarde : $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (files.isEmpty) return;
    final bytes = await files.single.readAsBytes();
    setState(() => _busy = true);
    try {
      final temp = File(
        '${Directory.systemTemp.path}/kidas-restore-${DateTime.now().microsecondsSinceEpoch}.json',
      );
      await temp.writeAsBytes(bytes, flush: true);
      final count = await AppBackup.restore(temp);
      await temp.delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$count paramètre(s) restauré(s). Redémarre l’application pour appliquer tous les réglages.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sauvegarde refusée : $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 34),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(21),
            border: Border.all(color: c.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: c.accent.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.backup_outlined, color: c.accent),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sauvegarde et restauration', style: T.title(c)),
                        Text('Préserve tes préférences', style: T.caption(c)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Exporte les préférences et les références des dépôts dans un fichier JSON local.',
                style: T.body(c),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lock_outline_rounded, color: Colors.green, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Les jetons GitHub, mots de passe et secrets ne sont jamais exportés ni restaurés.',
                        style: T.caption(c),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _create,
                  icon: const Icon(Icons.save_alt_rounded),
                  label: Text(_busy ? 'Traitement…' : 'Créer une sauvegarde'),
                ),
              ),
              const SizedBox(height: 9),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _restore,
                  icon: const Icon(Icons.restore_rounded),
                  label: const Text('Restaurer un fichier JSON'),
                ),
              ),
              if (_lastFile != null) ...[
                const SizedBox(height: 14),
                Text('Dernier fichier créé', style: T.caption(c)),
                const SizedBox(height: 4),
                SelectableText(_lastFile!, style: T.caption(c)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
