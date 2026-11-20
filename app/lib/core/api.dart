// Cliente da API REST do GestFast.
// Na web, servido pelo próprio backend, usa o cookie HttpOnly do navegador.
// Nos apps nativos, usa token Bearer.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.message, {this.status = 0});
  final String message;
  final int status;
  @override
  String toString() => message;
}

class Arquivo {
  Arquivo(this.nome, this.bytes);
  final String nome;
  final Uint8List bytes;
}

class ApiClient {
  ApiClient({http.Client? client, this.web = kIsWeb}) : _http = client ?? http.Client();

  final http.Client _http;
  final bool web;
  static const _tempoLimite = Duration(seconds: 30);
  static const _msgConexao = 'Erro de conexão com o sistema. Verifique a rede e tente novamente.';

  String baseUrl = '';
  String? token;
  VoidCallback? aoExpirarSessao;

  bool get usaCookie => web && baseUrl.isEmpty;

  Uri montarUri(String caminho, [Map<String, String?>? query]) {
    final q = <String, String>{};
    query?.forEach((k, v) {
      if (v != null && v.isNotEmpty) q[k] = v;
    });
    final base = baseUrl.isEmpty ? Uri.base : Uri.parse(baseUrl);
    final u = base.resolve(caminho);
    return u.replace(queryParameters: q.isEmpty ? null : q, fragment: null);
  }

  /// Endereço público de um arquivo do servidor (imagem de produto).
  String urlDoArquivo(String caminho) => montarUri('/$caminho').toString();

  Map<String, String> _cabecalhos({bool json = true}) => {
        if (json) 'Content-Type': 'application/json',
        if (!usaCookie) 'X-Client': 'app',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> get(String caminho, {Map<String, String?>? query}) =>
      _enviar('GET', caminho, query: query);
  Future<Map<String, dynamic>> post(String caminho, [Map<String, dynamic>? corpo]) =>
      _enviar('POST', caminho, corpo: corpo ?? const {});
  Future<Map<String, dynamic>> put(String caminho, Map<String, dynamic> corpo) => _enviar('PUT', caminho, corpo: corpo);
  Future<Map<String, dynamic>> patch(String caminho, Map<String, dynamic> corpo) =>
      _enviar('PATCH', caminho, corpo: corpo);
  Future<Map<String, dynamic>> delete(String caminho, [Map<String, dynamic>? corpo]) =>
      _enviar('DELETE', caminho, corpo: corpo ?? const {});

  Future<Map<String, dynamic>> _enviar(String metodo, String caminho, {Map<String, String?>? query, Map<String, dynamic>? corpo}) async {
    final http.Response res = await _executar(metodo, montarUri(caminho, query), corpo);
    Map<String, dynamic> dados;
    try {
      final d = jsonDecode(utf8.decode(res.bodyBytes));
      dados = d is Map<String, dynamic> ? d : <String, dynamic>{};
    } catch (_) {
      throw ApiException('O servidor respondeu de forma inesperada. Confira o endereço do servidor.', status: res.statusCode);
    }
    _verificarSessao(res.statusCode, caminho);
    if (res.statusCode >= 400 || dados['success'] == false) {
      throw ApiException((dados['error'] ?? 'Erro ao processar a operação.').toString(), status: res.statusCode);
    }
    return dados;
  }

  Future<http.Response> _executar(String metodo, Uri uri, Map<String, dynamic>? corpo) async {
    try {
      final req = http.Request(metodo, uri)..headers.addAll(_cabecalhos(json: corpo != null));
      if (corpo != null) req.body = jsonEncode(corpo);
      final enviado = await _http.send(req).timeout(_tempoLimite);
      return await http.Response.fromStream(enviado).timeout(_tempoLimite);
    } on TimeoutException {
      throw ApiException(_msgConexao);
    } on http.ClientException {
      throw ApiException(_msgConexao);
    } catch (e) {
      // SocketException e HandshakeException não existem na web; aqui todas viram erro de conexão.
      throw ApiException(_msgConexao);
    }
  }

  void _verificarSessao(int status, String caminho) {
    if (status == 401 && !caminho.startsWith('/api/auth/login') && !caminho.startsWith('/api/auth/me')) {
      aoExpirarSessao?.call();
    }
  }

  /// Baixa um arquivo gerado pelo servidor (PDF ou Excel).
  Future<Arquivo> baixar(String caminho, {Map<String, String?>? query, required String nomePadrao}) async {
    final res = await _executar('GET', montarUri(caminho, query), null);
    _verificarSessao(res.statusCode, caminho);
    if (res.statusCode >= 400) {
      var msg = 'Falha ao gerar o arquivo.';
      try {
        msg = (jsonDecode(utf8.decode(res.bodyBytes)) as Map)['error']?.toString() ?? msg;
      } catch (_) {}
      throw ApiException(msg, status: res.statusCode);
    }
    final m = RegExp(r'filename="([^"]+)"').firstMatch(res.headers['content-disposition'] ?? '');
    return Arquivo(m?.group(1) ?? nomePadrao, res.bodyBytes);
  }
}
