import 'package:flutter_test/flutter_test.dart';

import 'package:kidas_controle/core/api.dart';
import 'package:kidas_controle/core/data.dart';
import 'package:kidas_controle/core/palette.dart';
import 'package:kidas_controle/core/util.dart';

void main() {
  test('palettes : les deux thèmes exposent les mêmes jetons', () {
    const dark = Palette.dark;
    const light = Palette.light;
    expect(dark.accent, light.accent); // bleu Facebook identique
    expect(dark.bg, isNot(light.bg));
    expect(dark.ink, isNot(light.ink));
  });

  test('dayLabel : JJ/MM depuis les clés de date', () {
    expect(Api.dayLabel({'date': '2026-11-14T00:00:00Z'}), '14/11');
    expect(Api.dayLabel({'fin': '2026-01-02'}), '02/01');
    expect(Api.dayLabel({'sans_date': true}), isNull);
  });

  test('hint : messages d\'erreur parlants', () {
    expect(Api.hint(ApiError(401, 'Bad credentials', '/x')),
        'Jeton invalide ou expiré. Va dans Réglages.');
    expect(Api.hint(ApiError(403, 'Forbidden', '/repos/a/b/contents/posts/queue.json')),
        contains('Droit manquant'));
  });

  test('cp : encodage des segments de chemin', () {
    expect(Api.cp('posts/queue.json'), 'posts/queue.json');
    expect(Api.cp('media/a b.png'), 'media/a%20b.png');
  });

  test('util : formats français', () {
    expect(nf(1234567), '1\u202F234\u202F567');
    expect(nf(999), '999');
    expect(pct(120, 100), '+20,0\u00A0%');
    expect(pct(80, 100), '-20,0\u00A0%');
    expect(pct(100, 0), '');
    expect(fsize(500), '1\u00A0Ko');
    expect(fsize(3400000), '3,2\u00A0Mo');
    expect(kind('media/1-photo.mp4'), 'video');
    expect(kind('media/1-photo.png'), 'image');
    expect(stripStamp('1700000000-photo.jpg'), 'photo.jpg');
    expect(dur(45000), '45\u00A0s');
    expect(dur(125000), '2\u00A0min');
    expect(dur(9000000), '2\u00A0h 30\u00A0min');
    expect(iso('2026-11-14T10:00:00Z') > 0, isTrue);
    expect(iso(''), -1);
  });

  test('règles : la simulation prend la première règle active qui colle', () {
    final rs = [
      Regle(id: 'r1', actif: false, contient: 'prix'),
      Regle(id: 'r2', actif: true, contient: 'livraison',
          action: 'reponse', texte: 'Expédié sous 48 h.'),
      Regle(id: 'r3', actif: true, contient: ''),
    ];
    expect(Regles.simule(rs, 'Ma livraison ?')!.id, 'r2');
    expect(Regles.simule(rs, 'Bonjour')!.id, 'r3');
    expect(Regles.simule(rs, 'Quel est le prix ?')!.id, 'r3');
    expect(Regles.simule(const [], 'x'), isNull);
  });

  test('top posts : classement par nombre de commentaires', () {
    final cm = {'posts': [
      {
        'id': 'p1',
        'message': 'Premier',
        'comments': {'data': [{'id': 'c1'}, {'id': 'c2'}]},
      },
      {
        'id': 'p2',
        'message': 'Deuxième',
        'comments': {'data': [{'id': 'c3'}]},
      },
    ]};
    final top = topPosts(cm);
    expect(top.first.texte, 'Premier');
    expect(top.first.commentaires, 2);
    expect(top.length, 2);
  });

  test('sommes hebdo : 7 derniers jours contre 7 précédents', () {
    final vals = [for (var i = 1; i <= 14; i++) i.toDouble()];
    expect(sommeRecente(vals, 7), 77.0);
    expect(sommePrecedente(vals, 7), 28.0);
    expect(sommeRecente([3.0], 7), 3.0);
    expect(sommePrecedente([3.0], 7), 0.0);
  });

  test('journal : aller-retour carte vers JSON', () {
    final e = JournalEvent(1763000000000, 'post', 'Post mis en file',
        detail: 'concert');
    final f = JournalEvent.fromMap(e.toMap());
    expect(f.type, 'post');
    expect(f.label, 'Post mis en file');
    expect(f.detail, 'concert');
    expect(f.source, 'app');
    expect(f.at, e.at);
  });

  test('règle : aller-retour carte vers JSON', () {
    final r = Regle(id: 'r1', actif: false, contient: 'prix', action: 'urgent');
    final f = Regle.fromMap(r.toMap());
    expect(f.id, 'r1');
    expect(f.actif, isFalse);
    expect(f.contient, 'prix');
    expect(f.action, 'urgent');
    expect(f.libelle, 'Marquer urgent');
  });
}
