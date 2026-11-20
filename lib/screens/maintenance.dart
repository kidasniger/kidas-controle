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
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final report = await Diagnostics.run();
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
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        KCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('État des services', style: T.title(c)),
              const SizedBox(height: 5),
              Text(
                'Vérifications en lecture seule. Aucun workflow ne sera lancé ou arrêté.',
                style: T.caption(c),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _run,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                  label: Text(_busy ? 'Vérification…' : 'Relancer le diagnostic'),
                ),
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          KCard(child: Text(_error!)),
        ],
        if (_report != null) ...[
          const SizedBox(height: 14),
          for (final check in _report!.checks) ...[
            KCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    switch (check.level) {
                      CheckLevel.success => Icons.check_circle_rounded,
                      CheckLevel.warning => Icons.warning_amber_rounded,
                      CheckLevel.error => Icons.error_rounded,
                    },
                    color: switch (check.level) {
                      CheckLevel.success => Colors.green,
                      CheckLevel.warning => Colors.orange,
                      CheckLevel.error => Colors.red,
                    },
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(check.title, style: T.strong(c)),
                        const SizedBox(height: 3),
                        Text(check.detail, style: T.caption(c)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            'Contrôle effectué le ${_report!.checkedAt.toLocal()}',
            style: T.caption(c),
          ),
        ],
      ],
    );
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
      padding: const EdgeInsets.all(14),
      children: [
        KCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sauvegarde des paramètres', style: T.title(c)),
              const SizedBox(height: 6),
              Text(
                'Enregistre les préférences et les références des dépôts dans un fichier JSON local.',
                style: T.caption(c),
              ),
              const SizedBox(height: 8),
              Text(
                'Sécurité : les jetons GitHub, mots de passe et secrets ne sont jamais exportés ni restaurés.',
                style: T.caption(c).copyWith(color: Colors.green),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _create,
                  icon: const Icon(Icons.backup_outlined),
                  label: const Text('Créer une sauvegarde'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _restore,
                  icon: const Icon(Icons.restore_rounded),
                  label: const Text('Restaurer un fichier JSON'),
                ),
              ),
              if (_lastFile != null) ...[
                const SizedBox(height: 12),
                Text('Dernier fichier créé :', style: T.caption(c)),
                SelectableText(_lastFile!, style: T.caption(c)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
