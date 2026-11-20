// harness.dart - Teste de contrato Node x Dart.
//
// Sobe o servidor Node de referência e o Dart contra dois bancos idênticos recém-semeados (mesmo
// relógio fixo), roda a mesma sequência de requisições (cenarios.dart) e compara status,
// cabeçalhos relevantes e corpo, ignorando só os campos voláteis (executor.dart).
//
//   dart run tool/contrato/harness.dart [--node ../backend] [--gravar]
//
// --gravar escreve as respostas do Node em test/golden/contrato.json (usado por test/contrato_test.dart).
// O banco vem de TEST_DB_* (ou do .env); os bancos usados são contrato_node_test e contrato_dart_test.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'executor.dart';
import 'preparo.dart';

Future<void> main(List<String> args) async {
  final i = args.indexOf('--node');
  final pastaNode = p.normalize(p.absolute(i >= 0 ? args[i + 1] : p.join('..', 'backend')));
  final gravar = args.contains('--gravar');
  final base = Directory.systemTemp.createTempSync('gestfast-contrato-');
  ServidorFilho? node, dart;
  try {
    node = await iniciarNode('contrato_node_test', Directory(p.join(base.path, 'n')), pastaNode);
    final rn = await node.rodar();
    node.parar();
    dart = await iniciarDart('contrato_dart_test', Directory(p.join(base.path, 'd')));
    final rd = await dart.rodar();
    dart.parar();

    var falhas = 0;
    for (var k = 0; k < rn.length; k++) {
      final dif = comparar(rn[k]['resposta'], rd[k]['resposta']);
      if (dif.isEmpty) continue;
      falhas++;
      stdout.writeln('✗ [$k] ${rn[k]['nome']}');
      for (final d in dif.take(8)) {
        stdout.writeln('    $d');
      }
    }
    stdout.writeln('${rn.length} passos, $falhas com diferença.');
    if (gravar) {
      File(arquivoGolden).writeAsStringSync('${const JsonEncoder.withIndent(' ').convert(rn)}\n');
      stdout.writeln('Golden gravado em $arquivoGolden');
    }
    exitCode = falhas == 0 ? 0 : 1;
  } finally {
    node?.parar();
    dart?.parar();
    try {
      base.deleteSync(recursive: true);
    } catch (_) {}
  }
}
