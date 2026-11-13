import 'package:flutter_test/flutter_test.dart';

import 'package:kidas_controle/core/api.dart';
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
}
