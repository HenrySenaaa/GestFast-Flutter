// http_cru.dart - Cliente HTTP/1.1 mínimo sobre socket.
//
// Os testes de contrato precisam mandar exatamente os mesmos bytes aos dois servidores
// (inclusive endereços malformados como /%E0%A4%A, que o HttpClient do Dart recusaria ou
// reescreveria). Por isso a requisição é escrita à mão.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class RespostaCrua {
  RespostaCrua(this.status, this.cabecalhos, this.corpo, {this.erro});

  /// 0 quando a conexão caiu antes de uma resposta completa.
  final int status;

  /// Nome em minúsculas -> valores (na ordem recebida).
  final Map<String, List<String>> cabecalhos;
  final List<int> corpo;
  final String? erro;

  String? cabecalho(String nome) {
    final v = cabecalhos[nome.toLowerCase()];
    return v?.join(', ');
  }
}

Future<RespostaCrua> enviarCru({
  required String host,
  required int porta,
  required String metodo,
  required String alvo,
  Map<String, String> cabecalhos = const {},
  List<int>? corpo,
  Duration limite = const Duration(seconds: 60),
}) async {
  Socket? s;
  try {
    s = await Socket.connect(host, porta, timeout: const Duration(seconds: 10));
    final cab = StringBuffer()
      ..write('$metodo $alvo HTTP/1.1\r\n')
      ..write('Host: $host:$porta\r\n')
      ..write('Connection: close\r\n');
    cabecalhos.forEach((k, v) => cab.write('$k: $v\r\n'));
    if (corpo != null) cab.write('Content-Length: ${corpo.length}\r\n');
    cab.write('\r\n');
    final dados = BytesBuilder(copy: false);
    final fim = Completer<void>();
    s.listen(dados.add, onDone: () => fim.isCompleted ? null : fim.complete(), onError: (Object e) => fim.isCompleted ? null : fim.completeError(e));
    s.add(latin1.encode(cab.toString()));
    if (corpo != null) s.add(corpo);
    try {
      await s.flush();
    } catch (_) {
      // o servidor pode fechar antes de receber tudo (corpo grande demais)
    }
    String? erro;
    try {
      await fim.future.timeout(limite);
    } catch (e) {
      erro = 'conexão: ${e.runtimeType}';
    }
    return _interpretar(dados.takeBytes(), metodo == 'HEAD', erro);
  } catch (e) {
    return RespostaCrua(0, const {}, const [], erro: 'conexão: ${e.runtimeType}');
  } finally {
    s?.destroy();
  }
}

RespostaCrua _interpretar(List<int> b, bool head, String? erro) {
  var i = 0;
  while (i + 3 < b.length && !(b[i] == 13 && b[i + 1] == 10 && b[i + 2] == 13 && b[i + 3] == 10)) {
    i++;
  }
  if (i + 3 >= b.length) return RespostaCrua(0, const {}, const [], erro: erro ?? 'resposta incompleta');
  final linhas = latin1.decode(b.sublist(0, i)).split('\r\n');
  final partes = linhas.first.split(' ');
  final status = partes.length > 1 ? int.tryParse(partes[1]) ?? 0 : 0;
  final cab = <String, List<String>>{};
  for (final l in linhas.skip(1)) {
    final k = l.indexOf(':');
    if (k <= 0) continue;
    cab.putIfAbsent(l.substring(0, k).trim().toLowerCase(), () => []).add(l.substring(k + 1).trim());
  }
  var corpo = b.sublist(i + 4);
  if (head) {
    corpo = [];
  } else if ((cab['transfer-encoding']?.join(',') ?? '').toLowerCase().contains('chunked')) {
    corpo = _desfazerChunked(corpo);
  } else if (cab['content-length'] != null) {
    final n = int.tryParse(cab['content-length']!.first) ?? corpo.length;
    if (n < corpo.length) corpo = corpo.sublist(0, n);
  }
  return RespostaCrua(status, cab, corpo, erro: erro);
}

List<int> _desfazerChunked(List<int> b) {
  final out = <int>[];
  var i = 0;
  while (i < b.length) {
    var j = i;
    while (j + 1 < b.length && !(b[j] == 13 && b[j + 1] == 10)) {
      j++;
    }
    final tam = int.tryParse(latin1.decode(b.sublist(i, j)).split(';').first.trim(), radix: 16) ?? 0;
    if (tam == 0 || j + 2 + tam > b.length) break;
    out.addAll(b.sublist(j + 2, j + 2 + tam));
    i = j + 2 + tam + 2;
  }
  return out;
}
