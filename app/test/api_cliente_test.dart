// Cliente da API com respostas simuladas: códigos de erro, sessão expirada, tempo esgotado, cabeçalhos e download.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gestfast/core/api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

ApiClient _cliente(Future<http.Response> Function(http.Request) f, {Duration tempo = const Duration(seconds: 30)}) =>
    ApiClient(client: MockClient(f), web: false, tempoLimite: tempo)..baseUrl = 'http://servidor.local:3000';

http.Response _json(int status, Object corpo, {Map<String, String> cabecalhos = const {}}) =>
    http.Response.bytes(utf8.encode(jsonEncode(corpo)), status, headers: {'content-type': 'application/json', ...cabecalhos});

Matcher _erro(String mensagem, int status) => throwsA(isA<ApiException>().having((e) => e.message, 'mensagem', mensagem).having((e) => e.status, 'status', status));

void main() {
  group('códigos de erro do servidor viram a mensagem dele', () {
    for (final status in [400, 403, 404, 409, 500, 502, 503]) {
      test('$status', () async {
        final c = _cliente((_) async => _json(status, {'success': false, 'error': 'Mensagem $status'}));
        await expectLater(c.get('/api/x'), _erro('Mensagem $status', status));
      });
    }

    test('sem o campo "error" usa a mensagem padrão do v1', () async {
      final c = _cliente((_) async => _json(500, {'success': false}));
      await expectLater(c.get('/api/x'), _erro('Erro ao processar a operação.', 500));
    });

    test('200 com success: false também é erro', () async {
      final c = _cliente((_) async => _json(200, {'success': false, 'error': 'Estoque insuficiente'}));
      await expectLater(c.post('/api/sales', {}), _erro('Estoque insuficiente', 200));
    });

    test('mensagem com acento chega intacta (UTF-8)', () async {
      final c = _cliente((_) async => _json(400, {'success': false, 'error': 'Requisição não encontrada.'}));
      await expectLater(c.get('/api/x'), _erro('Requisição não encontrada.', 400));
    });

    test('corpo JSON que não é objeto vira resposta vazia', () async {
      final c = _cliente((_) async => http.Response('[1,2]', 200));
      expect(await c.get('/api/x'), isEmpty);
    });
  });

  group('sessão expirada (401)', () {
    test('em operação comum chama o aviso de sessão expirada', () async {
      var avisos = 0;
      final c = _cliente((_) async => _json(401, {'success': false, 'error': 'Não autenticado.'}))..aoExpirarSessao = () => avisos++;
      await expectLater(c.get('/api/products'), _erro('Não autenticado.', 401));
      expect(avisos, 1);
    });

    test('no login e no /me não é sessão expirada', () async {
      var avisos = 0;
      final c = _cliente((_) async => _json(401, {'success': false, 'error': 'E-mail ou senha incorretos'}))..aoExpirarSessao = () => avisos++;
      await expectLater(c.post('/api/auth/login', {}), throwsA(isA<ApiException>()));
      await expectLater(c.get('/api/auth/me'), throwsA(isA<ApiException>()));
      expect(avisos, 0);
    });

    test('403 não encerra a sessão', () async {
      var avisos = 0;
      final c = _cliente((_) async => _json(403, {'success': false, 'error': 'Seu perfil não tem permissão para esta operação.'}))..aoExpirarSessao = () => avisos++;
      await expectLater(c.delete('/api/sales/1'), _erro('Seu perfil não tem permissão para esta operação.', 403));
      expect(avisos, 0);
    });

    test('download com 401 também avisa', () async {
      var avisos = 0;
      final c = _cliente((_) async => _json(401, {'success': false, 'error': 'Sessão expirada.'}))..aoExpirarSessao = () => avisos++;
      await expectLater(c.baixar('/api/reports/sales', nomePadrao: 'a.pdf'), _erro('Sessão expirada.', 401));
      expect(avisos, 1);
    });
  });

  group('falhas de conexão: mensagem do v1', () {
    const conexao = 'Erro de conexão com o sistema. Verifique a rede e tente novamente.';

    test('tempo esgotado', () async {
      final c = _cliente((_) => Completer<http.Response>().future, tempo: const Duration(milliseconds: 50));
      await expectLater(c.get('/api/dashboard'), _erro(conexao, 0));
    });

    test('rede fora do ar', () async {
      final c = _cliente((_) async => throw http.ClientException('Connection refused'));
      await expectLater(c.post('/api/auth/login', {}), _erro(conexao, 0));
    });

    test('qualquer outra exceção do transporte', () async {
      final c = _cliente((_) async => throw StateError('handshake'));
      await expectLater(c.get('/api/x'), _erro(conexao, 0));
    });

    test('download sem rede', () async {
      final c = _cliente((_) async => throw http.ClientException('sem rede'));
      await expectLater(c.baixar('/api/reports/sales', nomePadrao: 'a.pdf'), _erro(conexao, 0));
    });

    test('resposta que não é JSON (endereço errado)', () async {
      final c = _cliente((_) async => http.Response('<!DOCTYPE html>', 200));
      await expectLater(c.get('/api/x'), _erro('O servidor respondeu de forma inesperada. Confira o endereço do servidor.', 200));
    });
  });

  group('requisição montada', () {
    test('métodos, corpo JSON e cabeçalhos do app nativo', () async {
      final vistos = <http.Request>[];
      final c = _cliente((r) async {
        vistos.add(r);
        return _json(200, {'success': true});
      })..token = 'tok';
      await c.get('/api/a', query: {'q': 'pão de queijo', 'vazio': ''});
      await c.post('/api/b', {'x': 1});
      await c.post('/api/c');
      await c.put('/api/d', {'y': 'ç'});
      await c.patch('/api/e', {'status': 'Inativo'});
      await c.delete('/api/f', {'motivo': 'm'});
      await c.delete('/api/g');
      expect(vistos.map((r) => r.method), ['GET', 'POST', 'POST', 'PUT', 'PATCH', 'DELETE', 'DELETE']);
      expect(vistos.first.url.toString(), 'http://servidor.local:3000/api/a?q=p%C3%A3o+de+queijo');
      expect(vistos.first.headers.containsKey('Content-Type'), isFalse, reason: 'GET sem corpo');
      expect(jsonDecode(vistos[1].body), {'x': 1});
      expect(jsonDecode(vistos[2].body), <String, dynamic>{}, reason: 'POST sem corpo manda {} como o v1');
      expect(jsonDecode(utf8.decode(vistos[3].bodyBytes)), {'y': 'ç'});
      expect(jsonDecode(vistos[6].body), <String, dynamic>{});
      for (final r in vistos) {
        expect(r.headers['Authorization'], 'Bearer tok');
        expect(r.headers['X-Client'], 'app');
      }
      expect(vistos[1].headers['Content-Type'], startsWith('application/json'));
    });

    test('sem token não manda Authorization', () async {
      late http.Request visto;
      final c = _cliente((r) async {
        visto = r;
        return _json(200, {'success': true});
      });
      await c.get('/api/x');
      expect(visto.headers.containsKey('Authorization'), isFalse);
    });

    test('na web em outro servidor também manda X-Client', () {
      final c = ApiClient(web: true)..baseUrl = 'http://192.168.0.10:3000';
      expect(c.usaCookie, isFalse);
    });

    test('endereço do servidor com caminho e porta', () {
      final c = ApiClient(web: false)..baseUrl = 'https://gestfast.exemplo.com';
      expect(c.montarUri('/api/x', {'a': '1', 'b': null}).toString(), 'https://gestfast.exemplo.com/api/x?a=1');
      expect(c.urlDoArquivo('uploads/produto 1.png'), 'https://gestfast.exemplo.com/uploads/produto%201.png');
    });
  });

  group('download de relatório', () {
    test('sem Content-Disposition usa o nome padrão', () async {
      final c = _cliente((_) async => http.Response.bytes([9], 200));
      expect((await c.baixar('/api/reports/stock', query: {'format': 'xlsx'}, nomePadrao: 'gestfast-estoque.xlsx')).nome, 'gestfast-estoque.xlsx');
    });

    test('erro com JSON mostra a mensagem do servidor', () async {
      final c = _cliente((_) async => _json(400, {'success': false, 'error': 'Período inválido.'}));
      await expectLater(c.baixar('/api/reports/sales', nomePadrao: 'a.pdf'), _erro('Período inválido.', 400));
    });

    test('erro sem JSON mostra a mensagem padrão do v1', () async {
      final c = _cliente((_) async => http.Response.bytes([0, 1, 2], 500));
      await expectLater(c.baixar('/api/reports/sales', nomePadrao: 'a.pdf'), _erro('Falha ao gerar o arquivo.', 500));
    });

    test('a consulta leva o formato', () async {
      late Uri url;
      final c = _cliente((r) async {
        url = r.url;
        return http.Response.bytes([1], 200);
      });
      await c.baixar('/api/reports/losses', query: {'from': '2026-11-01', 'to': '', 'format': 'pdf'}, nomePadrao: 'x.pdf');
      expect(url.queryParameters, {'from': '2026-11-01', 'format': 'pdf'});
    });
  });
}
