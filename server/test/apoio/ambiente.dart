// ambiente.dart - Apoio dos testes: banco de teste recriado do zero e servidor em processo.
//
// O MySQL de teste vem das variáveis TEST_DB_HOST/TEST_DB_PORT/TEST_DB_USER/TEST_DB_PASSWORD
// ou do .env da pasta server (DB_HOST, DB_PORT, ...). O banco é sempre um "*_test", recriado
// a partir de ../database/schema.sql e seed.sql: o banco "gestfast" nunca é tocado.
import 'dart:convert';
import 'dart:io';

import 'package:gestfast_server/gestfast_server.dart';
import 'package:mysql_dart/mysql_dart.dart';
import 'package:path/path.dart' as p;

Map<String, String> _envTeste() {
  final f = File('.env');
  final env = <String, String>{if (f.existsSync()) ...lerDotenv(f.readAsStringSync()), ...Platform.environment};
  String? v(String k) => env['TEST_$k'] ?? env[k];
  return {
    'host': v('DB_HOST') ?? 'localhost',
    'port': v('DB_PORT') ?? '3306',
    'user': v('DB_USER') ?? 'root',
    'password': v('DB_PASSWORD') ?? '',
  };
}

final Map<String, String> envTeste = _envTeste();

/// Pasta `database/` da raiz do repositório.
String get pastaDatabase => p.normalize(p.join(Directory.current.path, '..', 'database'));

String lerSql(String arquivo, String nomeBanco) => File(p.join(pastaDatabase, arquivo))
    .readAsStringSync()
    .replaceAll(RegExp(r'\bgestfast\b(?=\s*(;|DEFAULT|$))', multiLine: true), nomeBanco);

/// Divide um script em comandos (os .sql do projeto terminam cada comando com ";" no fim da linha).
List<String> comandosSql(String script) {
  final out = <String>[];
  final atual = StringBuffer();
  for (final linha in const LineSplitter().convert(script)) {
    final t = linha.trim();
    if (t.startsWith('--') || (t.isEmpty && atual.isEmpty)) continue;
    atual.writeln(linha);
    if (t.endsWith(';')) {
      out.add(atual.toString().trim().replaceFirst(RegExp(r';$'), ''));
      atual.clear();
    }
  }
  if (atual.toString().trim().isNotEmpty) out.add(atual.toString().trim());
  return out;
}

/// Recria o banco [nome] (precisa terminar em "_test"). Com [timestampSeg], o seed usa esse
/// instante como NOW()/CURDATE() (o mesmo do relógio fixo dos testes de contrato).
Future<void> recriarBancoDeTeste(String nome, {int? timestampSeg}) async {
  if (!nome.endsWith('_test')) throw ArgumentError('Banco de teste precisa terminar em "_test" (recebido: $nome).');
  final conn = await MySQLConnection.createConnection(
    host: envTeste['host']!,
    port: int.parse(envTeste['port']!),
    userName: envTeste['user']!,
    password: envTeste['password']!,
    secure: false,
    allowPublicKeyRetrieval: true,
    collation: 'utf8mb4_unicode_ci',
  );
  await conn.connect();
  try {
    if (timestampSeg != null) await conn.execute('SET TIMESTAMP = $timestampSeg');
    for (final arq in ['schema.sql', 'seed.sql']) {
      for (final cmd in comandosSql(lerSql(arq, nome))) {
        await conn.execute(cmd);
      }
    }
  } finally {
    await conn.close();
  }
}

/// Servidor completo (banco, dados, logger e HTTP) para os testes.
class Ambiente {
  Ambiente._(this.config, this.banco, this.dados, this.logger, this.servidor, this.base, this._sockets, this.tmp);

  final Config config;
  final Banco banco;
  final Dados dados;
  final Logger logger;
  final Servidor servidor;
  final String base;
  final List<HttpServer> _sockets;
  final Directory tmp;

  static Future<Ambiente> iniciar({
    required String nomeBanco,
    Map<String, String> extra = const {},
    int Function()? relogioFixo,
    int? timestampSeed,
    Dados Function(Banco banco, Relogio relogio, Logger logger)? criarDados,
    Directory? pasta,
  }) async {
    await recriarBancoDeTeste(nomeBanco, timestampSeg: timestampSeed);
    final tmp = pasta ?? Directory.systemTemp.createTempSync('gestfast-');
    final config = Config(
      {
        'DB_HOST': envTeste['host']!,
        'DB_PORT': envTeste['port']!,
        'DB_USER': envTeste['user']!,
        'DB_PASSWORD': envTeste['password']!,
        'DB_NAME': nomeBanco,
        'GESTFAST_UPLOAD_DIR': p.join(tmp.path, 'uploads'),
        'GESTFAST_LOG_DIR': p.join(tmp.path, 'logs'),
        'GESTFAST_QUIET': '1',
        ...extra,
      },
      pastaServidor: Directory.current.path,
    );
    final relogio = Relogio(config.fuso, agora: relogioFixo);
    final logger = Logger(config.pastaLogs, relogio, silencioso: true);
    final banco = Banco(
      host: config.dbHost,
      porta: config.dbPort,
      usuario: config.dbUser,
      senha: config.dbPassword,
      nome: config.dbName,
    );
    final dados = criarDados != null ? criarDados(banco, relogio, logger) : Dados(banco: banco, relogio: relogio, logger: logger);
    final servidor = Servidor(config: config, dados: dados, logger: logger, relogio: relogio);
    final sockets = await servidor.ouvir(porta: 0);
    return Ambiente._(config, banco, dados, logger, servidor, 'http://localhost:${sockets.first.port}', sockets, tmp);
  }

  Future<void> encerrar() async {
    for (final s in _sockets) {
      await s.close(force: true);
    }
    await banco.fechar();
    logger.fechar();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  }
}

/// Resposta simplificada: status, cabeçalhos e corpo (JSON quando der).
class Resp {
  Resp(this.status, this.headers, this.bytes);
  final int status;
  final HttpHeaders headers;
  final List<int> bytes;
  String get texto => utf8.decode(bytes, allowMalformed: true);
  Map<String, dynamic> get json {
    try {
      final d = jsonDecode(texto);
      return d is Map<String, dynamic> ? d : {'_': d};
    } catch (_) {
      return {'texto': texto};
    }
  }

  dynamic operator [](String k) => json[k];
  String? get error => json['error'] as String?;
}

final _http = HttpClient()..autoUncompress = false;

/// Requisição com a linha de pedido exatamente como escrita (sem normalizar o caminho).
Future<RespCrua> requisicaoCrua(String base, String alvo, {String metodo = 'GET', Map<String, String> headers = const {}}) async {
  final u = Uri.parse(base);
  final s = await Socket.connect(u.host == 'localhost' ? '127.0.0.1' : u.host, u.port);
  const crlf = '\r\n';
  final cab = StringBuffer('$metodo $alvo HTTP/1.1${crlf}Host: ${u.host}:${u.port}${crlf}Connection: close$crlf');
  headers.forEach((k, v) => cab.write('$k: $v$crlf'));
  cab.write(crlf);
  s.add(latin1.encode(cab.toString()));
  await s.flush();
  final bytes = await s.fold<List<int>>([], (a, c) => a..addAll(c));
  s.destroy();
  // separa cabeçalho e corpo (as respostas de erro do servidor não usam chunked)
  var i = 0;
  while (i + 3 < bytes.length && !(bytes[i] == 13 && bytes[i + 1] == 10 && bytes[i + 2] == 13 && bytes[i + 3] == 10)) {
    i++;
  }
  final cabecalho = latin1.decode(bytes.sublist(0, i));
  var corpo = bytes.sublist(i + 4 > bytes.length ? bytes.length : i + 4);
  final linhas = cabecalho.split(crlf);
  final status = int.parse(linhas.first.split(' ')[1]);
  final mapa = <String, String>{};
  for (final l in linhas.skip(1)) {
    final k = l.indexOf(':');
    if (k > 0) mapa[l.substring(0, k).toLowerCase()] = l.substring(k + 1).trim();
  }
  if ((mapa['transfer-encoding'] ?? '').contains('chunked')) corpo = _desfazerChunked(corpo);
  return RespCrua(status, mapa, corpo);
}

List<int> _desfazerChunked(List<int> b) {
  final out = <int>[];
  var i = 0;
  while (i < b.length) {
    var j = i;
    while (j + 1 < b.length && !(b[j] == 13 && b[j + 1] == 10)) {
      j++;
    }
    final tam = int.parse(latin1.decode(b.sublist(i, j)).split(';').first.trim(), radix: 16);
    if (tam == 0) break;
    out.addAll(b.sublist(j + 2, j + 2 + tam));
    i = j + 2 + tam + 2;
  }
  return out;
}

class RespCrua {
  RespCrua(this.status, this.headers, this.bytes);
  final int status;
  final Map<String, String> headers;
  final List<int> bytes;
  String get texto => utf8.decode(bytes, allowMalformed: true);
}

/// Requisição crua (sem cookie).
Future<Resp> requisitar(String metodo, String url, {Object? corpo = _semCorpo, Map<String, String> headers = const {}, List<int>? bytes}) async {
  final req = await _http.openUrl(metodo, Uri.parse(url));
  req.followRedirects = false;
  headers.forEach(req.headers.set);
  if (bytes != null) {
    req.add(bytes);
  } else if (!identical(corpo, _semCorpo)) {
    req.headers.contentType = ContentType.json;
    req.add(utf8.encode(jsonEncode(corpo)));
  }
  final res = await req.close();
  final b = await res.fold<List<int>>([], (a, c) => a..addAll(c));
  return Resp(res.statusCode, res.headers, b);
}

const _semCorpo = Object();

/// Cliente com cookie de sessão (como o fetch dos testes do Node).
class Cliente {
  Cliente(this.base);
  final String base;
  String cookie = '';

  Future<Resp> call(String metodo, String url, [Object? corpo = _semCorpo]) async {
    final r = await requisitar(metodo, base + url, corpo: corpo, headers: {'Content-Type': 'application/json', if (cookie.isNotEmpty) 'cookie': cookie});
    final sc = r.headers['set-cookie'];
    if (sc != null && sc.isNotEmpty) {
      final par = sc.first.split(';').first;
      cookie = par.endsWith('=') ? '' : par;
    }
    return r;
  }

  Future<Resp> get(String u) => call('GET', u);
  Future<Resp> post(String u, [Object? b = const <String, Object?>{}]) => call('POST', u, b);
  Future<Resp> put(String u, Object? b) => call('PUT', u, b);
  Future<Resp> patch(String u, Object? b) => call('PATCH', u, b);
  Future<Resp> del(String u, [Object? b = const <String, Object?>{}]) => call('DELETE', u, b);
}
