import 'package:flutter_test/flutter_test.dart';
import 'package:gestfast/core/api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'apoio.dart';

void main() {
  test('app nativo: login devolve token, guardado só com "manter conectado"', () async {
    final api = ApiFalsa({
      ...rotasBase(),
      'POST /api/auth/login': (_) => (200, {'success': true, 'token': 'abc123'}),
      'POST /api/auth/logout': (_) => (200, {'success': true}),
    });
    final cofre = CofreFalso();
    final s = await criarSessao(api, logar: false, cofre: cofre);

    await s.entrar('a@b.com', 'x', false);
    expect(api.de('POST', '/api/auth/login').single.cabecalhos['X-Client'], 'app');
    expect(s.api.token, 'abc123');
    expect(cofre.valor, isNull);
    expect(s.logado, isTrue);
    expect(api.de('GET', '/api/auth/me').single.cabecalhos['Authorization'], 'Bearer abc123');

    await s.entrar('a@b.com', 'x', true);
    expect(cofre.valor, 'abc123');

    await s.sair();
    expect(s.logado, isFalse);
    expect(s.api.token, isNull);
    expect(cofre.valor, isNull);
  });

  test('web no mesmo servidor usa o cookie: sem X-Client e sem token', () async {
    late http.Request visto;
    final c = ApiClient(client: MockClient((r) async {
      visto = r;
      return http.Response('{"success":true}', 200);
    }), web: true);
    expect(c.usaCookie, isTrue);
    await c.get('/api/x');
    expect(visto.headers.containsKey('X-Client'), isFalse);
    expect(visto.headers.containsKey('Authorization'), isFalse);
  });

  test('erro da API vira ApiException com a mensagem do servidor', () async {
    final s = await criarSessao(ApiFalsa({...rotasBase(), 'GET /api/x': (_) => (400, {'success': false, 'error': 'Estoque insuficiente'})}));
    await expectLater(s.api.get('/api/x'), throwsA(isA<ApiException>().having((e) => e.message, 'mensagem', 'Estoque insuficiente').having((e) => e.status, 'status', 400)));
  });

  test('sessão expirada em operação comum leva ao login com aviso', () async {
    final s = await criarSessao(ApiFalsa({...rotasBase(), 'GET /api/x': (_) => (401, {'success': false, 'error': 'Sessão expirada.'})}));
    expect(s.logado, isTrue);
    await expectLater(s.api.get('/api/x'), throwsA(isA<ApiException>()));
    expect(s.logado, isFalse);
    expect(s.avisoLogin, contains('expirou'));
  });

  test('senha errada no login não é tratada como sessão expirada', () async {
    final s = await criarSessao(ApiFalsa({'POST /api/auth/login': (_) => (401, {'success': false, 'error': 'E-mail ou senha incorretos'})}), logar: false);
    await expectLater(s.entrar('a@b.com', 'x', false), throwsA(isA<ApiException>()));
    expect(s.avisoLogin, isNull);
  });

  test('falha de rede e resposta que não é JSON têm mensagens claras', () async {
    final semRede = ApiClient(client: MockClient((_) async => throw http.ClientException('sem rede')), web: false)..baseUrl = 'http://x.local';
    await expectLater(semRede.get('/api/x'), throwsA(isA<ApiException>().having((e) => e.message, 'mensagem', contains('conexão'))));
    final html = ApiClient(client: MockClient((_) async => http.Response('<html>', 200)), web: false)..baseUrl = 'http://x.local';
    await expectLater(html.get('/api/x'), throwsA(isA<ApiException>().having((e) => e.message, 'mensagem', contains('endereço do servidor'))));
  });

  test('download usa o nome enviado pelo servidor', () async {
    final c = ApiClient(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200, headers: {'content-disposition': 'attachment; filename="gestfast-vendas-2026-11-03.pdf"'})), web: false)..baseUrl = 'http://x.local';
    final a = await c.baixar('/api/reports/sales', nomePadrao: 'padrao.pdf');
    expect(a.nome, 'gestfast-vendas-2026-11-03.pdf');
    expect(a.bytes, [1, 2, 3]);
  });

  test('parâmetros vazios não vão na URL', () {
    final c = ApiClient(web: false)..baseUrl = 'http://x.local:3000';
    expect(c.montarUri('/api/sales', {'from': '', 'to': null, 'q': 'pão'}).toString(), 'http://x.local:3000/api/sales?q=p%C3%A3o');
    expect(c.urlDoArquivo('uploads/a.png'), 'http://x.local:3000/uploads/a.png');
  });
}
