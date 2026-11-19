// config.dart - Configuração do servidor: variáveis de ambiente + arquivo .env.
//
// Mesmas variáveis do servidor Node (veja .env.example). Uma variável já definida no
// ambiente vale mais que a do .env, como no dotenv.
import 'dart:io';

import 'package:path/path.dart' as p;

import 'js.dart';

/// Lê um .env com as mesmas regras do dotenv (parser padrão).
Map<String, String> lerDotenv(String texto) {
  final out = <String, String>{};
  final t = texto.replaceAll(RegExp(r'\r\n?'), '\n');
  final linha = RegExp(
    r'''(?:^|^)\s*(?:export\s+)?([\w.-]+)(?:\s*=\s*?|:\s+?)(\s*'(?:\\'|[^'])*'|\s*"(?:\\"|[^"])*"|\s*`(?:\\`|[^`])*`|[^#\r\n]+)?\s*(?:#.*)?(?:$|$)''',
    multiLine: true,
  );
  final aspas = RegExp(r'''^(['"`])([\s\S]*)\1$''', multiLine: true);
  for (final m in linha.allMatches(t)) {
    var v = jsTrim(m.group(2) ?? '');
    final primeiro = v.isEmpty ? '' : v[0];
    v = v.replaceAllMapped(aspas, (x) => x.group(2)!);
    if (primeiro == '"') v = v.replaceAll(r'\n', '\n').replaceAll(r'\r', '\r');
    out[m.group(1)!] = v;
  }
  return out;
}

class Config {
  Config(this.env, {required this.pastaServidor});

  /// Ambiente do processo com o .env da pasta atual por baixo.
  factory Config.carregar({Map<String, String>? ambiente, String? pastaServidor, String? arquivoEnv}) {
    final env = <String, String>{};
    final f = File(arquivoEnv ?? p.join(Directory.current.path, '.env'));
    if (f.existsSync()) {
      try {
        env.addAll(lerDotenv(f.readAsStringSync()));
      } catch (_) {}
    }
    env.addAll(ambiente ?? Platform.environment);
    return Config(env, pastaServidor: pastaServidor ?? pastaDoServidor());
  }

  final Map<String, String> env;

  /// Pasta do pacote `server/` (base dos padrões de logs e uploads, como era o `backend/`).
  final String pastaServidor;

  String? _v(String k) {
    final v = env[k];
    return (v == null || v.isEmpty) ? null : v;
  }

  String get dbHost => _v('DB_HOST') ?? 'localhost';
  int get dbPort {
    final n = toNumber(env['DB_PORT'] ?? '');
    return (n.isFinite && n != 0) ? n.toInt() : 3306;
  }

  String get dbUser => _v('DB_USER') ?? 'root';
  String get dbPassword => env['DB_PASSWORD'] ?? '';
  String get dbName => _v('DB_NAME') ?? 'gestfast';

  /// Texto da porta, como aparece nas mensagens (`process.env.PORT || 3000`).
  String get portaTexto => _v('PORT') ?? '3000';
  int? get porta => int.tryParse(portaTexto.trim());
  String? get host => _v('HOST');
  String get fuso => _v('TZ') ?? 'America/Sao_Paulo';

  String get pastaWeb =>
      p.normalize(p.absolute(_v('GESTFAST_WEB_DIR') ?? p.join(pastaServidor, '..', 'app', 'build', 'web')));
  String get pastaUploads => _v('GESTFAST_UPLOAD_DIR') ?? p.join(pastaServidor, 'data', 'uploads');
  String get pastaLogs => _v('GESTFAST_LOG_DIR') ?? p.join(pastaServidor, 'logs');
  List<String> get origensCors =>
      (env['CORS_ORIGINS'] ?? '').split(',').map(jsTrim).where((s) => s.isNotEmpty).toList();
  bool get silencioso => env['GESTFAST_QUIET'] == '1';
}

/// server/ = primeira pasta com pubspec.yaml acima do script em execução.
String pastaDoServidor() {
  final script = Platform.script;
  if (script.scheme == 'file') {
    var dir = p.dirname(script.toFilePath());
    for (var i = 0; i < 5; i++) {
      if (File(p.join(dir, 'pubspec.yaml')).existsSync()) return dir;
      dir = p.dirname(dir);
    }
    return p.dirname(p.dirname(script.toFilePath()));
  }
  return Directory.current.path;
}
