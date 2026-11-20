// Sessão: restauração do login, preferências de acessibilidade, servidor e memória das telas entre navegações.
import 'package:flutter_test/flutter_test.dart';
import 'package:gestfast/core/api.dart';
import 'package:gestfast/core/sessao.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'apoio.dart';

Sessao _nova(ApiFalsa api, CofreFalso cofre) => Sessao(api: ApiClient(client: api.cliente, web: false), cofre: cofre);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('iniciar', () {
    test('app nativo sem servidor salvo vai para o login sem chamar a API', () async {
      final api = ApiFalsa(rotasBase());
      final s = _nova(api, CofreFalso());
      await s.iniciar();
      expect(s.iniciada, isTrue);
      expect(s.logado, isFalse);
      expect(api.chamadas, isEmpty);
    });

    test('"manter conectado": servidor e token salvos restauram a sessão', () async {
      SharedPreferences.setMockInitialValues({'gf_servidor': 'http://192.168.0.10:3000', 'gf_zoom': 1.3, 'gf_hc': true});
      final api = ApiFalsa(rotasBase(permissoes: const ['vendas:vender']));
      final s = _nova(api, CofreFalso()..valor = 'tok');
      await s.iniciar();
      expect(s.logado, isTrue);
      expect(s.usuario!.nome, 'Francisco');
      expect(s.pode('vendas:vender'), isTrue);
      expect(s.pode('usuarios:gerir'), isFalse);
      expect(s.hoje, '2026-11-03');
      expect(s.categorias.single.nome, 'Pães');
      expect(s.zoom, 1.3);
      expect(s.altoContraste, isTrue);
      expect(api.de('GET', '/api/auth/me').single.cabecalhos['Authorization'], 'Bearer tok');
    });

    test('token vencido: fica no login, sem aviso de sessão expirada', () async {
      SharedPreferences.setMockInitialValues({'gf_servidor': 'http://192.168.0.10:3000'});
      final api = ApiFalsa({'GET /api/auth/me': (_) => (401, {'success': false, 'error': 'Sessão expirada.'})});
      final s = _nova(api, CofreFalso()..valor = 'velho');
      await s.iniciar();
      expect(s.logado, isFalse);
      expect(s.api.token, isNull);
      expect(s.avisoLogin, isNull);
    });
  });

  group('acessibilidade (gf_zoom e gf_hc do v1)', () {
    test('zoom em 100, 115, 130 e 150% e volta, salvo no aparelho', () async {
      final s = _nova(ApiFalsa({}), CofreFalso());
      await s.iniciar();
      final vistos = <double>[];
      for (var i = 0; i < 5; i++) {
        await s.mudarZoom(1);
        vistos.add(s.zoom);
      }
      expect(vistos, [1.15, 1.3, 1.5, 1.5, 1.5]);
      expect((await SharedPreferences.getInstance()).getDouble('gf_zoom'), 1.5);
      await s.mudarZoom(-1);
      expect(s.zoom, 1.3);
      await s.alternarContraste();
      expect(s.altoContraste, isTrue);
      await s.restaurarAcessibilidade();
      expect([s.zoom, s.altoContraste], [1, false]);
      final p = await SharedPreferences.getInstance();
      expect(p.containsKey('gf_zoom'), isFalse);
      expect(p.containsKey('gf_hc'), isFalse);
    });
  });

  test('servidor: valida e guarda o endereço', () async {
    final s = _nova(ApiFalsa({}), CofreFalso());
    await s.iniciar();
    await s.definirServidor('192.168.0.20:3000');
    expect(s.servidor, 'http://192.168.0.20:3000');
    expect(s.api.baseUrl, 'http://192.168.0.20:3000');
    expect((await SharedPreferences.getInstance()).getString('gf_servidor'), 'http://192.168.0.20:3000');
    expect(() => s.definirServidor('http://exemplo.com'), throwsFormatException);
  });

  test('sincronizar atualiza a data e os parâmetros do servidor; falha mantém os anteriores', () async {
    var falhar = false;
    final api = ApiFalsa({
      ...rotasBase(),
      'GET /api/settings': (_) => falhar ? (500, {'success': false}) : (200, {'success': true, 'hoje': '2026-12-01', 'settings': {...configJson, 'diasAlertaValidade': 7}}),
    });
    final s = await criarSessao(api);
    await s.sincronizar();
    expect([s.hoje, s.diasValidade], ['2026-12-01', 7]);
    falhar = true;
    await s.sincronizar();
    expect([s.hoje, s.diasValidade], ['2026-12-01', 7]);
  });

  group('memória das telas', () {
    test('sessão expirada: o mesmo usuário reencontra as telas e volta para onde estava', () async {
      final api = ApiFalsa({...rotasBase(), 'POST /api/auth/login': (_) => (200, {'success': true, 'token': 't'})});
      final s = await criarSessao(api);
      s.memoria['pdv'] = {'qtd': '3'};
      s.encerrarLocal('Sua sessão expirou. Faça login novamente.');
      expect(s.logado, isFalse);
      expect(s.avisoLogin, 'Sua sessão expirou. Faça login novamente.');
      expect(s.lembrarDestino, isTrue);
      await s.entrar('dono@x.com', 'x', false);
      expect(s.memoria['pdv'], {'qtd': '3'});
      expect(s.avisoLogin, isNull);
    });

    test('outro usuário começa do zero', () async {
      var id = 1;
      final api = ApiFalsa({
        ...rotasBase(),
        'GET /api/auth/me': (_) => (200, {...meJson(), 'user': {...usuarioJson(), 'id_usuario': id}}),
        'POST /api/auth/login': (_) => (200, {'success': true}),
      });
      final s = await criarSessao(api);
      s.memoria['pdv'] = {'qtd': '3'};
      s.encerrarLocal('expirou');
      id = 2;
      await s.entrar('outro@x.com', 'x', false);
      expect(s.memoria.containsKey('pdv'), isFalse);
    });

    test('sair pelo menu limpa a memória e o destino', () async {
      final api = ApiFalsa({...rotasBase(), 'POST /api/auth/logout': (_) => (200, {'success': true})});
      final s = await criarSessao(api);
      s.memoria['pdv'] = {'qtd': '3'};
      s.destinoPosLogin = '/venda';
      await s.sair();
      expect(s.memoria, isEmpty);
      expect(s.destinoPosLogin, isNull);
      expect(s.lembrarDestino, isFalse);
      expect(s.avisoLogin, isNull);
    });

    test('sair com o servidor fora do ar encerra no aparelho do mesmo jeito', () async {
      final api = ApiFalsa({...rotasBase(), 'POST /api/auth/logout': (_) => (503, {'success': false})});
      final s = await criarSessao(api);
      await s.sair();
      expect(s.logado, isFalse);
    });
  });
}
