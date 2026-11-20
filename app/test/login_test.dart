// Tela de login, "Esqueci minha senha" e redefinição: textos, validações e mensagens do v1.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestfast/features/login_tela.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'apoio.dart';

bool _vermelho(WidgetTester t, String rotulo) {
  final d = t.widget<TextField>(campoRotulado(rotulo)).decoration!;
  return (d.enabledBorder as OutlineInputBorder).borderSide.color == const Color(0xFFDC2626);
}

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  testWidgets('textos do v1', (t) async {
    await abrirTela(t, await criarSessao(ApiFalsa({}), logar: false), const LoginTela());
    for (final x in ['GEST', 'FAST#', 'Gestão de estoque e vendas para panificadoras', 'E-mail', 'Senha', 'Manter-me conectado', 'Entrar', 'Esqueci minha senha', 'Servidor']) {
      expect(find.text(x), findsOneWidget, reason: x);
    }
    expect(find.text('seu@email.com'), findsOneWidget);
    expect(find.text('Sua senha'), findsOneWidget);
    expect(t.widget<TextField>(campoRotulado('E-mail')).autofocus, isTrue, reason: 'o v1 foca o e-mail');
  });

  testWidgets('campo vazio fica vermelho e não chama o servidor', (t) async {
    final api = ApiFalsa({});
    await abrirTela(t, await criarSessao(api, logar: false), const LoginTela());
    await t.enterText(campoRotulado('E-mail'), 'a@b.com');
    await t.tap(find.text('Entrar'));
    await t.pump();
    expect(find.text('Preencha o e-mail e a senha para continuar.'), findsOneWidget);
    expect(_vermelho(t, 'Senha'), isTrue);
    expect(_vermelho(t, 'E-mail'), isFalse);
    expect(api.chamadas, isEmpty);
  });

  testWidgets('login com sucesso envia e-mail sem espaços e "manter conectado"', (t) async {
    final api = ApiFalsa({...rotasBase(), 'POST /api/auth/login': (_) => (200, {'success': true, 'token': 'tok'})});
    final s = await criarSessao(api, logar: false);
    await abrirTela(t, s, const LoginTela());
    await t.enterText(campoRotulado('E-mail'), '  dono@x.com ');
    await t.enterText(campoRotulado('Senha'), 'admin123');
    await t.tap(find.text('Manter-me conectado'));
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(api.de('POST', '/api/auth/login').single.corpo, {'email': 'dono@x.com', 'senha': 'admin123', 'lembrar': true});
    expect(s.logado, isTrue);
  });

  testWidgets('erro do servidor: mensagem em vermelho e senha apagada', (t) async {
    final api = ApiFalsa({'POST /api/auth/login': (_) => (429, {'success': false, 'error': 'Muitas tentativas. Aguarde alguns minutos.'})});
    await abrirTela(t, await criarSessao(api, logar: false), const LoginTela());
    await t.enterText(campoRotulado('E-mail'), 'a@b.com');
    await t.enterText(campoRotulado('Senha'), 'x');
    await t.tap(find.text('Entrar'));
    await t.pumpAndSettle();
    final faixa = t.widget<Text>(find.text('Muitas tentativas. Aguarde alguns minutos.'));
    expect(faixa.style!.color, const Color(0xFFDC2626));
    expect(textoDe(t, 'Senha'), '');
  });

  testWidgets('app nativo: servidor fora da rede local precisa de https', (t) async {
    final api = ApiFalsa({});
    final s = await criarSessao(api, logar: false);
    await abrirTela(t, s, const LoginTela());
    await t.enterText(campoRotulado('Servidor'), 'http://exemplo.com');
    await t.enterText(campoRotulado('E-mail'), 'a@b.com');
    await t.enterText(campoRotulado('Senha'), 'x');
    await t.tap(find.text('Entrar'));
    await t.pumpAndSettle();
    expect(find.text('Fora da rede local, o servidor precisa usar https://.'), findsOneWidget);
    expect(api.chamadas, isEmpty);
  });

  testWidgets('aviso de sessão expirada aparece ao abrir o login', (t) async {
    final s = await criarSessao(ApiFalsa({}), logar: false);
    s.avisoLogin = 'Sua sessão expirou. Faça login novamente.';
    await abrirTela(t, s, const LoginTela());
    expect(find.text('Sua sessão expirou. Faça login novamente.'), findsOneWidget);
  });

  group('esqueci minha senha', () {
    testWidgets('textos, e-mail aproveitado do login e vazio só em vermelho', (t) async {
      final api = ApiFalsa({});
      await abrirTela(t, await criarSessao(api, logar: false), const LoginTela());
      await t.enterText(campoRotulado('E-mail'), 'x@y.com');
      await t.tap(find.text('Esqueci minha senha'));
      await t.pumpAndSettle();
      for (final x in ['Informe o e-mail cadastrado. Enviaremos um link para redefinir sua senha.', 'E-mail cadastrado', 'Enviar link de redefinição', 'Voltar ao login']) {
        expect(find.text(x), findsOneWidget, reason: x);
      }
      expect(textoDe(t, 'E-mail cadastrado'), 'x@y.com');
      await t.enterText(campoRotulado('E-mail cadastrado'), '');
      await t.tap(find.text('Enviar link de redefinição'));
      await t.pump();
      expect(_vermelho(t, 'E-mail cadastrado'), isTrue);
      expect(find.text('Informe o e-mail cadastrado.'), findsNothing, reason: 'o v1 não mostra mensagem');
      expect(api.chamadas, isEmpty);
      await t.tap(find.text('Voltar ao login'));
      await t.pumpAndSettle();
      expect(find.text('Entrar'), findsOneWidget);
    });

    testWidgets('resposta do servidor em verde', (t) async {
      const msg = 'Se o e-mail estiver cadastrado, enviaremos as instruções.';
      final api = ApiFalsa({'POST /api/auth/forgot': (_) => (200, {'success': true, 'message': msg})});
      await abrirTela(t, await criarSessao(api, logar: false), const LoginTela());
      await t.tap(find.text('Esqueci minha senha'));
      await t.pumpAndSettle();
      await t.enterText(campoRotulado('E-mail cadastrado'), 'dono@x.com');
      await t.tap(find.text('Enviar link de redefinição'));
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.text(msg)).style!.color, const Color(0xFF166534));
      expect(api.de('POST', '/api/auth/forgot').single.corpo, {'email': 'dono@x.com'});
    });
  });

  group('redefinir senha', () {
    testWidgets('textos e senhas diferentes', (t) async {
      final api = ApiFalsa({});
      await abrirTela(t, await criarSessao(api, logar: false), const LoginTela(redefinir: true, codigoRedefinicao: 'abc'));
      for (final x in ['Defina uma nova senha de acesso (mínimo 6 caracteres).', 'Nova senha', 'Confirmar nova senha', 'Redefinir senha', 'Voltar ao login']) {
        expect(find.text(x), findsOneWidget, reason: x);
      }
      expect(find.text('Código de redefinição'), findsNothing, reason: 'o código veio no link');
      await t.enterText(campoRotulado('Nova senha'), 'abcdef');
      await t.enterText(campoRotulado('Confirmar nova senha'), 'abcdeg');
      await t.tap(find.text('Redefinir senha'));
      await t.pump();
      expect(find.text('As senhas não conferem.'), findsOneWidget);
      expect(api.chamadas, isEmpty);
    });

    testWidgets('sem link pede o código; erro do servidor aparece', (t) async {
      final api = ApiFalsa({'POST /api/auth/reset': (_) => (400, {'success': false, 'error': 'Link de redefinição inválido ou expirado.'})});
      await abrirTela(t, await criarSessao(api, logar: false), const LoginTela());
      await t.tap(find.text('Esqueci minha senha'));
      await t.pumpAndSettle();
      await t.tap(find.text('Já tenho o código'));
      await t.pumpAndSettle();
      await t.enterText(campoRotulado('Nova senha'), 'abcdef');
      await t.enterText(campoRotulado('Confirmar nova senha'), 'abcdef');
      await t.tap(find.text('Redefinir senha'));
      await t.pump();
      expect(find.text('Informe o código de redefinição.'), findsOneWidget);
      await t.enterText(campoRotulado('Código de redefinição'), ' 123456 ');
      await t.tap(find.text('Redefinir senha'));
      await t.pumpAndSettle();
      expect(api.de('POST', '/api/auth/reset').single.corpo, {'token': '123456', 'senha': 'abcdef'});
      expect(find.text('Link de redefinição inválido ou expirado.'), findsOneWidget);
    });
  });
}
