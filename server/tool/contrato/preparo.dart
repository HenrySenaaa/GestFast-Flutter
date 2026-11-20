// preparo.dart - Infraestrutura comum do teste de contrato: relógio fixo, banco recém-semeado,
// pasta web de exemplo e servidores (Node de referência e Dart) como processos filhos.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../test/apoio/ambiente.dart';
import 'cenarios.dart';
import 'executor.dart';

/// Instante fixo dos dois servidores e do seed (15/06/2026 12:00 em São Paulo).
final int agoraContrato = DateTime.utc(2026, 6, 15, 15).millisecondsSinceEpoch;

/// Golden com as respostas do servidor Node (gravado por harness.dart --gravar).
String get arquivoGolden => p.join(pastaServidorDart, 'test', 'golden', 'contrato.json');

/// Pasta do pacote server/ (os comandos rodam a partir dela).
String get pastaServidorDart => Directory.current.path;

/// Cria a pasta web de exemplo (e uma pasta irmã "web-secreto" para as tentativas de fuga).
String criarPastaWeb(Directory base) {
  final web = p.join(base.path, 'web');
  void arq(String nome, List<int> bytes) => File(p.join(web, nome))
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes);
  arq('index.html', utf8.encode('<!doctype html><html><head><title>GestFast</title></head><body>app</body></html>\n'));
  arq('main.dart.js', utf8.encode('console.log("GestFast");\n'));
  arq('assets/fonte.ttf', [0, 1, 0, 0, 0, 10, 0, 128]);
  arq('canvaskit.wasm', [0, 97, 115, 109, 1, 0, 0, 0]);
  arq('arquivo.xyz', utf8.encode('conteúdo desconhecido'));
  arq('IMAGEM.PNG', base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='));
  Directory(p.join(web, 'pasta.d')).createSync(recursive: true);
  File(p.join(base.path, 'web-secreto', 'x.txt'))
    ..createSync(recursive: true)
    ..writeAsStringSync('segredo');
  return web;
}

Future<int> portaLivre() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final porta = s.port;
  await s.close();
  return porta;
}

/// Um servidor rodando como processo filho, com o console capturado.
class ServidorFilho {
  ServidorFilho._(this.processo, this.porta, this.console);
  final Process processo;
  final int porta;
  final List<String> console;

  /// [base]: pasta temporária própria (uploads e logs); [web]: pasta web de exemplo.
  static Future<ServidorFilho> iniciar({
    required String executavel,
    required List<String> argumentos,
    required String cwd,
    required String banco,
    required String base,
    required String web,
  }) async {
    final porta = await portaLivre();
    final env = <String, String>{
      'PORT': '$porta',
      'HOST': '',
      'TZ': 'America/Sao_Paulo',
      'DB_HOST': envTeste['host']!,
      'DB_PORT': envTeste['port']!,
      'DB_USER': envTeste['user']!,
      'DB_PASSWORD': envTeste['password']!,
      'DB_NAME': banco,
      'GESTFAST_WEB_DIR': web,
      'GESTFAST_UPLOAD_DIR': p.join(base, 'uploads'),
      'GESTFAST_LOG_DIR': p.join(base, 'logs'),
      'GESTFAST_QUIET': '0',
      'CORS_ORIGINS': 'http://app.test',
      'GESTFAST_AGORA_MS': '$agoraContrato',
    };
    final proc = await Process.start(executavel, argumentos, workingDirectory: cwd, environment: env);
    final console = <String>[];
    final erros = StringBuffer();
    final pronto = Completer<void>();
    proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((l) {
      console.add(l);
      if (l.contains('Servidor rodando') && !pronto.isCompleted) pronto.complete();
    });
    proc.stderr.transform(utf8.decoder).listen(erros.write);
    unawaited(proc.exitCode.then((c) {
      if (!pronto.isCompleted) pronto.completeError(StateError('$executavel saiu com código $c:\n$erros'));
    }));
    await pronto.future.timeout(const Duration(minutes: 3));
    return ServidorFilho._(proc, porta, console);
  }

  /// Executa todos os cenários e devolve as respostas normalizadas, na ordem.
  Future<List<Map<String, Object?>>> rodar() async {
    final e = Estado('127.0.0.1', porta, lerConsole: () => console);
    return [for (final passo in cenarios()) {'nome': passo.nome, 'resposta': await executar(passo, e)}];
  }

  void parar() => processo.kill();
}

/// Sobe o servidor Dart (servidor_fixo.dart) contra o banco [banco], recém-recriado.
Future<ServidorFilho> iniciarDart(String banco, Directory base) async {
  await recriarBancoDeTeste(banco, timestampSeg: agoraContrato ~/ 1000);
  return ServidorFilho.iniciar(
    executavel: Platform.resolvedExecutable,
    argumentos: [p.join(pastaServidorDart, 'tool', 'contrato', 'servidor_fixo.dart')],
    cwd: pastaServidorDart,
    banco: banco,
    base: p.join(base.path, 'dart'),
    web: criarPastaWeb(base),
  );
}

/// Sobe o servidor Node de referência ([pastaNode] = pasta do backend) com Date congelado.
Future<ServidorFilho> iniciarNode(String banco, Directory base, String pastaNode) async {
  await recriarBancoDeTeste(banco, timestampSeg: agoraContrato ~/ 1000);
  return ServidorFilho.iniciar(
    executavel: 'node',
    argumentos: ['-r', p.join(pastaServidorDart, 'tool', 'contrato', 'relogio-fixo.js'), p.join(pastaNode, 'server.js')],
    cwd: pastaNode,
    banco: banco,
    base: p.join(base.path, 'node'),
    web: criarPastaWeb(base),
  );
}
