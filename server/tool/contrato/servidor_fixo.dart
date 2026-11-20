// servidor_fixo.dart - Servidor Dart com relógio fixo (GESTFAST_AGORA_MS), para os testes de contrato.
// Igual ao bin/server.dart, mas com o instante congelado como no Node pré-carregado com relogio-fixo.js.
import 'dart:io';

import 'package:gestfast_server/gestfast_server.dart';

Future<void> main() async {
  final config = Config.carregar();
  final agora = int.parse(Platform.environment['GESTFAST_AGORA_MS']!);
  final relogio = Relogio(config.fuso, agora: () => agora);
  final logger = Logger(config.pastaLogs, relogio, silencioso: config.silencioso);
  final banco = Banco(host: config.dbHost, porta: config.dbPort, usuario: config.dbUser, senha: config.dbPassword, nome: config.dbName);
  final dados = Dados(banco: banco, relogio: relogio, logger: logger);
  await banco.testarConexao();
  await dados.sincronizarTodosAlertas();
  final servidor = Servidor(config: config, dados: dados, logger: logger, relogio: relogio);
  await servidor.ouvir(host: config.host, porta: config.porta!);
  stdout.writeln('[GestFast ERP] Servidor rodando em http://localhost:${config.portaTexto}');
}
