// contrato_test.dart - O servidor Dart responde igual ao Node de referência.
//
// Roda os 438 passos de tool/contrato/cenarios.dart no servidor Dart (relógio fixo, banco
// recém-semeado) e compara cada resposta normalizada com a gravada do servidor Node em
// test/golden/contrato.json (gerado por tool/contrato/harness.dart --gravar).
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../tool/contrato/executor.dart';
import '../tool/contrato/preparo.dart';

void main() {
  test('contrato: respostas do Dart iguais ao golden do Node', () async {
    final golden = (jsonDecode(File(arquivoGolden).readAsStringSync()) as List).cast<Map<String, Object?>>();
    final base = Directory.systemTemp.createTempSync('gestfast-contrato-');
    final dart = await iniciarDart('contrato_dart_test', base);
    try {
      final respostas = await dart.rodar();
      expect(respostas.map((r) => r['nome']), golden.map((g) => g['nome']), reason: 'cenários e golden fora de sincronia');
      final falhas = <String>[];
      for (var i = 0; i < golden.length; i++) {
        final dif = comparar(golden[i]['resposta'], respostas[i]['resposta']);
        if (dif.isNotEmpty) falhas.add('[$i] ${golden[i]['nome']}\n    ${dif.take(5).join('\n    ')}');
      }
      expect(falhas, isEmpty, reason: falhas.join('\n'));
    } finally {
      dart.parar();
      try {
        base.deleteSync(recursive: true);
      } catch (_) {}
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
