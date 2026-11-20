// Confere o js.dart contra valores calculados pelo próprio Node
// (test/golden/js_semantica.json, gerado por tool/contrato/gerar-golden-js.js).
import 'dart:convert';
import 'dart:io';

import 'package:gestfast_server/src/js.dart';
import 'package:test/test.dart';

void main() {
  final g = jsonDecode(File('test/golden/js_semantica.json').readAsStringSync()) as Map<String, dynamic>;
  double n(Object? v) => (v as num).toDouble();

  test('Number(texto)', () {
    for (final c in g['number'] as List) {
      expect(numStr(numeroDeTexto(c[0] as String)), c[1], reason: 'Number(${jsonEncode(c[0])})');
    }
  });
  test('String(número)', () {
    for (final c in g['string'] as List) {
      expect(numStr(n(c[0])), c[1], reason: '${c[0]}');
    }
  });
  test('toFixed(2)', () {
    for (final c in g['toFixed2'] as List) {
      expect(toFixed(n(c[0]), 2), c[1], reason: '${c[0]}');
    }
  });
  test('Math.round, r2 e r3', () {
    for (final c in g['round'] as List) {
      expect(numStr(jsRound(n(c[0]))), c[1], reason: 'round ${c[0]}');
    }
    for (final c in g['r2'] as List) {
      expect(numStr(r2(n(c[0]))), c[1], reason: 'r2 ${c[0]}');
    }
    for (final c in g['r3'] as List) {
      expect(numStr(r3(n(c[0]))), c[1], reason: 'r3 ${c[0]}');
    }
  });
  test('trim()', () {
    for (final c in g['trim'] as List) {
      expect(jsTrim(c[0] as String), c[1], reason: jsonEncode(c[0]));
    }
  });
  test('JSON.stringify', () {
    for (final c in g['stringify'] as List) {
      expect(jsonStringify(c[0]), c[1]);
    }
    for (final c in g['valores'] as List) {
      expect(jsonStringify(jsonParse(jsonEncode(c[0]))), c[1]);
    }
  });
  test('String(v) e Number(v) de valores não numéricos', () {
    for (final c in g['stringOf'] as List) {
      expect(toStr(jsonParse(jsonEncode(c[0]))), c[1]);
    }
    for (final c in g['numberOf'] as List) {
      expect(numStr(toNumber(jsonParse(jsonEncode(c[0])))), c[1]);
    }
  });
  test('ordenação estável como no V8', () {
    final l = [for (var i = 0; i < 100; i++) (i % 3, i)];
    sortJs(l, (a, b) => a.$1 - b.$1);
    for (var i = 1; i < l.length; i++) {
      final a = l[i - 1], b = l[i];
      expect(a.$1 < b.$1 || (a.$1 == b.$1 && a.$2 < b.$2), isTrue);
    }
  });
  test('truthy e prop', () {
    expect([null, undefined, false, 0.0, double.nan, ''].any(truthy), isFalse);
    expect([true, 1.0, 'a', <Object?>[], <String, Object?>{}].every(truthy), isTrue);
    expect(prop({'a': null}, 'a'), isNull);
    expect(prop({'a': null}, 'b'), same(undefined));
    expect(prop('texto', 'a'), same(undefined));
  });
}
