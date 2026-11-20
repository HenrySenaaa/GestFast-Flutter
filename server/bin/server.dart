// server.dart - Sobe o servidor do GestFast ERP.
//   dart run bin/server.dart          (na pasta server, com o .env preenchido)
import 'dart:io';

import 'package:gestfast_server/gestfast_server.dart';

Future<void> main() async {
  final config = Config.carregar();
  final relogio = Relogio(config.fuso);
  final logger = Logger(config.pastaLogs, relogio, silencioso: config.silencioso);
  final banco = Banco(
    host: config.dbHost,
    porta: config.dbPort,
    usuario: config.dbUser,
    senha: config.dbPassword,
    nome: config.dbName,
  );
  final dados = Dados(banco: banco, relogio: relogio, logger: logger);

  try {
    await banco.testarConexao();
  } catch (e) {
    stderr
      ..writeln('[GestFast ERP] Não foi possível conectar ao MySQL: ${mensagemDe(e)}')
      ..writeln('Confira se o MySQL está rodando e se o arquivo .env existe com a senha certa (modelo em .env.example).');
    exit(1);
  }

  // Alertas de estoque são atualizados só para o produto tocado em cada operação; ao subir,
  // refaz todos uma vez (corrige alertas defasados). Falha aqui não impede o servidor de subir.
  try {
    await dados.sincronizarTodosAlertas();
  } catch (e) {
    logger.log('ERRO', 'falha_alerta_estoque', {'produtos': 'todos (inicialização)', 'erro': mensagemDe(e)});
  }

  final porta = config.porta;
  if (porta == null) {
    stderr.writeln('[GestFast ERP] Porta inválida: "${config.portaTexto}". Use um número (ex.: PORT=3001 no .env).');
    exit(1);
  }
  final servidor = Servidor(config: config, dados: dados, logger: logger, relogio: relogio);
  try {
    await servidor.ouvir(host: config.host, porta: porta);
  } on SocketException catch (e) {
    final codigo = e.osError?.errorCode;
    if (codigo == 10048 || codigo == 98 || codigo == 48) {
      stderr
        ..writeln('[GestFast ERP] A porta ${config.portaTexto} já está em uso por outro programa. O banco conectou normalmente.')
        ..writeln('Feche o outro servidor ou escolha outra porta (ex.: PORT=3001 no .env).');
    } else {
      stderr.writeln('[GestFast ERP] Não foi possível iniciar o servidor: ${e.message}');
    }
    exit(1);
  }
  stdout
    ..writeln('[GestFast ERP] Servidor rodando em http://${config.host ?? 'localhost'}:${config.portaTexto}')
    ..writeln('[GestFast ERP] Banco MySQL: ${config.dbName} em ${config.dbHost}:${config.dbPort}');
}
