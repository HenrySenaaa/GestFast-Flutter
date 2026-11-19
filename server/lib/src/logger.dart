// logger.dart - Registro de logs (RNF 06): acessos, operações e erros.
// Uma linha JSON por evento em <GESTFAST_LOG_DIR>/gestfast.log; acima de 5 MB vira gestfast.log.1.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'js.dart';
import 'relogio.dart';

class Logger {
  Logger(this.pasta, this.relogio, {this.silencioso = false}) : arquivo = p.join(pasta, 'gestfast.log');

  final String pasta;
  final String arquivo;
  final Relogio relogio;
  final bool silencioso;
  static const _maxBytes = 5 * 1024 * 1024;

  void log(String nivel, String evento, [Map<String, Object?> detalhes = const {}, String? usuario]) {
    final linha = jsonStringify(<String, Object?>{
      'ts': relogio.isoUtc(),
      'nivel': nivel,
      'evento': evento,
      'usuario': usuario,
      ...detalhes,
    });
    try {
      _escrever('$linha\n');
    } catch (_) {
      // log nunca derruba o sistema; na próxima linha o arquivo é reaberto
      _fechar();
    }
    if (nivel == 'ERRO' && !silencioso) stderr.writeln('[ERRO] $evento ${jsonStringify(detalhes)}');
  }

  // O arquivo fica aberto (abrir e fechar a cada linha é lento no Windows). Acima de 5 MB ele
  // vira gestfast.log.1 e um novo é aberto, como no servidor Node.
  RandomAccessFile? _arq;

  void _escrever(String texto) {
    var arq = _arq;
    if (arq == null) {
      Directory(pasta).createSync(recursive: true);
      arq = _arq = File(arquivo).openSync(mode: FileMode.append);
    }
    if (arq.lengthSync() > _maxBytes) {
      _fechar();
      final antigo = File('$arquivo.1');
      if (antigo.existsSync()) antigo.deleteSync();
      File(arquivo).renameSync('$arquivo.1');
      arq = _arq = File(arquivo).openSync(mode: FileMode.append);
    }
    arq.writeStringSync(texto);
  }

  void _fechar() {
    try {
      _arq?.closeSync();
    } catch (_) {}
    _arq = null;
  }

  /// Fecha o arquivo de log (ao encerrar o servidor e nos testes).
  void fechar() => _fechar();

  /// As últimas [limite] linhas, da mais nova para a mais antiga.
  List<Object?> recentes([int limite = 200]) {
    List<String> linhas;
    try {
      final texto = utf8.decode(File(arquivo).readAsBytesSync(), allowMalformed: true);
      linhas = texto.split('\n').where((l) => l.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
    final ult = linhas.length > limite ? linhas.sublist(linhas.length - limite) : linhas;
    final out = <Object?>[];
    for (final l in ult.reversed) {
      try {
        out.add(jsonParse(l));
      } catch (_) {
        out.add(<String, Object?>{'raw': l});
      }
    }
    return out;
  }
}
