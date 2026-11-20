// Casca do app: menu por perfil, busca do topo com atalhos, menu do usuário, rotas e zoom.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestfast/core/sessao.dart';
import 'package:gestfast/widgets/comuns.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'apoio.dart';

const _menuCompleto = ['Início', 'Verificar Estoque', 'Requisição', 'Cadastro de Produtos', 'Saída de Produtos', 'Entrada de Produtos', 'Venda', 'Histórico de Vendas', 'Relatórios', 'Funcionários', 'Configuração', 'Ajuda'];

Map<String, Resposta Function(Chamada)> _rotas(String perfil, List<String> permissoes, {Map<String, Resposta Function(Chamada)> extra = const {}}) => {
      ...rotasBase(perfil: perfil, permissoes: permissoes),
      'GET /api/dashboard': (_) => (200, painelJson()),
      'GET /api/search': (c) => (200, {'success': true, 'results': {'produtos': [], 'requisicoes': [], 'vendas': [], 'usuarios': []}}),
      'POST /api/auth/logout': (_) => (200, {'success': true}),
      ...extra,
    };

List<String> _menuVisivel(WidgetTester t) => [
      for (final r in _menuCompleto)
        if (find.descendant(of: find.byType(Drawer).evaluate().isEmpty ? find.byType(Scaffold).first : find.byType(Drawer), matching: find.text(r)).evaluate().isNotEmpty) r,
    ];

Future<void> _tecla(WidgetTester t, LogicalKeyboardKey k, {bool ctrl = false}) async {
  if (ctrl) await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await t.sendKeyEvent(k);
  if (ctrl) await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await t.pump();
}

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('menu lateral por perfil (data-perm do v1)', () {
    testWidgets('Administrador vê tudo, com rodapé "GestFast v1.3" e "USCS - ADS"', (t) async {
      final s = await criarSessao(ApiFalsa(_rotas('Administrador', permissoesAdmin)));
      await abrirApp(t, s);
      expect(_menuVisivel(t), _menuCompleto);
      expect(find.text('GestFast v1.3'), findsOneWidget);
      expect(find.text('USCS - ADS'), findsOneWidget);
      await encerrar(t);
    });

    testWidgets('BackOffice: sem Venda e sem Funcionários', (t) async {
      final s = await criarSessao(ApiFalsa(_rotas('BackOffice', permissoesBackOffice)));
      await abrirApp(t, s);
      expect(_menuVisivel(t), ['Início', 'Verificar Estoque', 'Requisição', 'Cadastro de Produtos', 'Saída de Produtos', 'Entrada de Produtos', 'Histórico de Vendas', 'Relatórios', 'Configuração', 'Ajuda']);
      expect(find.text('🛒 Abrir Caixa'), findsNothing);
      await encerrar(t);
    });

    testWidgets('Funcionário: sem Cadastro, Relatórios e Funcionários', (t) async {
      final s = await criarSessao(ApiFalsa(_rotas('Funcionario', permissoesFuncionario)));
      await abrirApp(t, s);
      expect(_menuVisivel(t), ['Início', 'Verificar Estoque', 'Requisição', 'Saída de Produtos', 'Entrada de Produtos', 'Venda', 'Histórico de Vendas', 'Configuração', 'Ajuda']);
      expect(find.text('Funcionário'), findsOneWidget, reason: 'sem cargo, o cabeçalho mostra o perfil com acento');
      await encerrar(t);
    });

    testWidgets('celular (até 900px): menu no ☰, com o cabeçalho em duas linhas', (t) async {
      final s = await criarSessao(ApiFalsa(_rotas('Administrador', permissoesAdmin)));
      await abrirApp(t, s, tamanho: const Size(800, 1200));
      expect(find.text('Verificar Estoque'), findsNothing);
      expect(find.text('Francisco'), findsNothing, reason: '.user-info-text some no celular');
      await t.tap(find.text('☰'));
      await assentar(t);
      expect(find.text('Verificar Estoque'), findsOneWidget);
      await t.tap(find.text('Ajuda'));
      await assentar(t);
      expect(find.text('Dicas rápidas'), findsOneWidget);
      expect(find.byType(Drawer), findsNothing, reason: 'escolher uma tela fecha o menu');
      await encerrar(t);
    });
  });

  group('rotas', () {
    testWidgets('endereço sem permissão volta ao Início com o aviso do v1', (t) async {
      final s = await criarSessao(ApiFalsa(_rotas('BackOffice', permissoesBackOffice)));
      final rotas = await abrirApp(t, s, local: '/funcionarios');
      expect(rotas.state.matchedLocation, '/painel');
      expect(find.text('Seu perfil não tem permissão para acessar esta área.'), findsOneWidget);
      await encerrar(t);
    });

    testWidgets('endereço desconhecido abre o Início', (t) async {
      final s = await criarSessao(ApiFalsa(_rotas('Administrador', permissoesAdmin)));
      final rotas = await abrirApp(t, s, local: '/nao-existe');
      expect(rotas.state.matchedLocation, '/painel');
      await encerrar(t);
    });

    testWidgets('sessão expirada: login com o aviso e, depois, volta para a mesma tela', (t) async {
      final api = ApiFalsa(_rotas('Administrador', permissoesAdmin, extra: {
        'GET /api/movements': (_) => (200, {'success': true, 'movements': []}),
        'POST /api/auth/login': (_) => (200, {'success': true, 'token': 't'}),
      }));
      final s = await criarSessao(api);
      final rotas = await abrirApp(t, s, local: '/entradas');
      s.encerrarLocal('Sua sessão expirou. Faça login novamente.');
      await assentar(t);
      expect(rotas.state.matchedLocation, '/login');
      expect(find.text('Sua sessão expirou. Faça login novamente.'), findsOneWidget);
      await t.enterText(campoRotulado('E-mail'), 'dono@x.com');
      await t.enterText(campoRotulado('Senha'), 'admin123');
      await t.tap(find.text('Entrar'));
      await assentar(t);
      expect(rotas.state.matchedLocation, '/entradas');
      await encerrar(t);
    });

    testWidgets('sair pelo menu: o próximo login começa no Início', (t) async {
      final api = ApiFalsa(_rotas('Administrador', permissoesAdmin, extra: {
        'GET /api/movements': (_) => (200, {'success': true, 'movements': []}),
        'POST /api/auth/login': (_) => (200, {'success': true, 'token': 't'}),
      }));
      final s = await criarSessao(api);
      final rotas = await abrirApp(t, s, local: '/saidas');
      await t.tap(find.text('Francisco'));
      await assentar(t);
      await t.tap(find.text('⏻ Sair do sistema'));
      await assentar(t);
      expect(rotas.state.matchedLocation, '/login');
      expect(find.text('Sua sessão expirou. Faça login novamente.'), findsNothing);
      await t.enterText(campoRotulado('E-mail'), 'dono@x.com');
      await t.enterText(campoRotulado('Senha'), 'admin123');
      await t.tap(find.text('Entrar'));
      await assentar(t);
      expect(rotas.state.matchedLocation, '/painel');
      await encerrar(t);
    });

    testWidgets('logo e 🏠 voltam ao Início', (t) async {
      final api = ApiFalsa(_rotas('Administrador', permissoesAdmin));
      final s = await criarSessao(api);
      final rotas = await abrirApp(t, s, local: '/ajuda');
      await t.tap(find.text('🏠'));
      await assentar(t);
      expect(rotas.state.matchedLocation, '/painel');
      rotas.go('/ajuda');
      await assentar(t);
      await t.tap(find.text('GEST'));
      await assentar(t);
      expect(rotas.state.matchedLocation, '/painel');
      await encerrar(t);
    });
  });

  group('busca do topo', () {
    Future<Sessao> sessaoBusca(Map<String, dynamic> resultados) async => criarSessao(ApiFalsa(_rotas('Administrador', permissoesAdmin, extra: {
          'GET /api/search': (_) => (200, {'success': true, 'results': resultados}),
          'GET /api/inventory': (_) => (200, {'success': true, 'conferencias': [], 'itensParaConferencia': []}),
          'GET /api/products': (_) => (200, {'success': true, 'products': []}),
          'GET /api/requisitions': (_) => (200, {'success': true, 'requisicoes': []}),
        })));

    testWidgets('foco abre a lista com todas as telas permitidas e o rodapé de teclas', (t) async {
      await abrirApp(t, await sessaoBusca({}));
      await t.tap(find.byKey(const ValueKey('busca-global')));
      await t.pump();
      expect(find.text('Para onde deseja ir?'), findsOneWidget);
      expect(find.text('TELAS DO SISTEMA'), findsOneWidget);
      expect(find.text('Início (Dashboard)'), findsOneWidget);
      expect(find.text('Conferência física e divergências'), findsOneWidget);
      for (final x in ['navegar', 'abrir', 'fechar', 'Enter', 'Esc']) {
        expect(find.text(x), findsOneWidget);
      }
      await encerrar(t);
    });

    testWidgets('"/" e Ctrl+K focam a busca; Esc fecha', (t) async {
      await abrirApp(t, await sessaoBusca({}));
      final foco = t.widget<TextField>(find.byKey(const ValueKey('busca-global'))).focusNode!;
      expect(foco.hasFocus, isFalse);
      await _tecla(t, LogicalKeyboardKey.slash);
      expect(foco.hasFocus, isTrue);
      await _tecla(t, LogicalKeyboardKey.escape);
      expect(foco.hasFocus, isFalse);
      expect(find.text('Para onde deseja ir?'), findsNothing);
      await _tecla(t, LogicalKeyboardKey.keyK, ctrl: true);
      expect(foco.hasFocus, isTrue);
      await encerrar(t);
    });

    testWidgets('uma letra pede mais; previsão completa com Tab; Enter abre a tela', (t) async {
      final s = await sessaoBusca({});
      final rotas = await abrirApp(t, s);
      await t.tap(find.byKey(const ValueKey('busca-global')));
      await t.enterText(find.byKey(const ValueKey('busca-global')), 'v');
      await t.pump();
      expect(find.text('Digite ao menos 2 letras para buscar produtos, requisições e vendas.'), findsOneWidget);
      expect(find.text('IR PARA'), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('busca-global')), 'verif');
      await t.pump();
      expect(find.text('🔎 Buscando produtos, requisições e vendas…'), findsOneWidget);
      expect(find.text('Verificar Estoque', skipOffstage: false), findsWidgets, reason: 'previsão fantasma');
      await _tecla(t, LogicalKeyboardKey.tab);
      expect(t.widget<TextField>(find.byKey(const ValueKey('busca-global'))).controller!.text, 'Verificar Estoque');
      await t.pump(const Duration(milliseconds: 300));
      await t.testTextInput.receiveAction(TextInputAction.done);
      await assentar(t);
      expect(rotas.state.matchedLocation, '/estoque');
      await encerrar(t);
    });

    testWidgets('resultados do servidor em grupos e sem resultado com a dica do v1', (t) async {
      final s = await sessaoBusca({
        'produtos': [{'id_produto': 1, 'nome_produto': 'Pão Francês', 'codigo_barras': '7891', 'categoria': 'Pães', 'quantidade_estoque': 2.5, 'unidade': 'KG', 'status': 'Inativo'}],
        'requisicoes': [{'id_requisicao': 4, 'codigo_pedido': 'REQ-9661', 'produto_nome': 'Farinha', 'fornecedor': 'Moinho', 'situacao': 'Em Aberto'}],
        'vendas': [{'id_venda': 9, 'codigo_venda': 'VENDA-1009', 'valor_total': 12.5, 'data_venda': '2026-11-02 10:00', 'usuario_nome': 'Henry', 'status_venda': 'Concluída'}],
        'usuarios': [{'id_usuario': 3, 'nome': 'Henry', 'email': 'h@x.com', 'perfil': 'Funcionario', 'status': 'Ativo'}],
      });
      await abrirApp(t, s);
      await t.tap(find.byKey(const ValueKey('busca-global')));
      await t.enterText(find.byKey(const ValueKey('busca-global')), 'xq');
      await t.pump(const Duration(milliseconds: 300));
      await t.pump();
      expect(find.text('Resultados para “xq”'), findsOneWidget);
      for (final g in ['PRODUTOS', 'REQUISIÇÕES DE COMPRA', 'VENDAS', 'FUNCIONÁRIOS']) {
        expect(find.text(g), findsOneWidget);
      }
      expect(find.text('7891 • Pães • 2,5 KG em estoque • Inativo'), findsOneWidget);
      expect(find.text('REQ-9661 • Farinha'), findsOneWidget);
      expect(find.text('VENDA-1009 • R\$ 12,50'), findsOneWidget);
      expect(find.text('02/11/2026 10:00 • Henry • Concluída'), findsOneWidget);
      expect(find.text('h@x.com • Funcionário • Ativo'), findsOneWidget);
      for (final e in ['Produto', 'Requisição', 'Venda', 'Funcionário']) {
        expect(find.text(e), findsWidgets);
      }
      await encerrar(t);
    });

    testWidgets('nenhum resultado', (t) async {
      await abrirApp(t, await sessaoBusca({'produtos': [], 'requisicoes': [], 'vendas': [], 'usuarios': []}));
      await t.tap(find.byKey(const ValueKey('busca-global')));
      await t.enterText(find.byKey(const ValueKey('busca-global')), 'zzzz');
      await t.pump(const Duration(milliseconds: 300));
      await t.pump();
      expect(find.text('Nenhum resultado para “zzzz”'), findsOneWidget);
      expect(find.text('Tente outro termo, o código de barras ou o número do pedido (ex.: REQ-9661).'), findsOneWidget);
      await encerrar(t);
    });

    testWidgets('escolher um produto sem permissão de cadastro abre o estoque filtrado', (t) async {
      final s = await criarSessao(ApiFalsa(_rotas('Funcionario', permissoesFuncionario, extra: {
        'GET /api/search': (_) => (200, {'success': true, 'results': {'produtos': [{'id_produto': 1, 'nome_produto': 'Sonho', 'codigo_barras': '7', 'categoria': 'Doces', 'quantidade_estoque': 1, 'unidade': 'UN', 'status': 'Ativo'}], 'requisicoes': [], 'vendas': [], 'usuarios': []}}),
        'GET /api/inventory': (_) => (200, {'success': true, 'conferencias': [], 'itensParaConferencia': [produtoJson(1, 'Sonho'), produtoJson(2, 'Bala')]}),
      })));
      final rotas = await abrirApp(t, s);
      await t.tap(find.byKey(const ValueKey('busca-global')));
      await t.enterText(find.byKey(const ValueKey('busca-global')), 'son');
      await t.pump(const Duration(milliseconds: 300));
      await t.pump();
      await t.tap(find.text('Sonho'));
      await assentar(t);
      expect(rotas.state.matchedLocation, '/estoque');
      expect(textoDe(t, 'Filtrar estoque por termo'), 'Sonho');
      expect(find.text('Bala'), findsNothing);
      await encerrar(t);
    });
  });

  group('menu do usuário', () {
    testWidgets('itens do v1, Esc fecha e A+ aplica zoom na página', (t) async {
      final s = await criarSessao(ApiFalsa(_rotas('Administrador', permissoesAdmin)));
      await abrirApp(t, s);
      await t.tap(find.text('Francisco'));
      await assentar(t);
      for (final x in ['🔑 Alterar minha senha', 'Tamanho do texto', 'A-', 'A+', '◐ Alto contraste', '⏻ Sair do sistema']) {
        expect(find.text(x), findsOneWidget, reason: x);
      }
      await _tecla(t, LogicalKeyboardKey.escape);
      await assentar(t);
      expect(find.text('Tamanho do texto'), findsNothing);

      await t.tap(find.text('Francisco'));
      await assentar(t);
      await t.tap(find.text('A+'));
      await assentar(t);
      expect(s.zoom, 1.15);
      final zoom = t.widget<Transform>(find.descendant(of: find.byType(Zoom), matching: find.byType(Transform)).first);
      expect(zoom.transform.getMaxScaleOnAxis(), closeTo(1.15, 1e-9));
      await t.tap(find.text('◐ Alto contraste'));
      await assentar(t);
      expect(s.altoContraste, isTrue);
      await encerrar(t);
    });

    testWidgets('alterar minha senha: confirmação diferente e sucesso', (t) async {
      final api = ApiFalsa(_rotas('Administrador', permissoesAdmin, extra: {
        'POST /api/auth/change-password': (_) => (200, {'success': true, 'message': 'Senha alterada com sucesso.'}),
      }));
      await abrirApp(t, await criarSessao(api));
      await t.tap(find.text('Francisco'));
      await assentar(t);
      await t.tap(find.text('🔑 Alterar minha senha'));
      await assentar(t);
      expect(find.text('Alterar minha senha'), findsOneWidget);
      await t.enterText(campoRotulado('Senha atual'), 'velha123');
      await t.enterText(campoRotulado('Nova senha (mínimo 6 caracteres)'), 'nova1234');
      await t.enterText(campoRotulado('Confirmar nova senha'), 'outra');
      await t.tap(find.text('Salvar senha'));
      await t.pump();
      expect(find.text('A confirmação não confere com a nova senha.'), findsOneWidget);
      expect(api.de('POST', '/api/auth/change-password'), isEmpty);
      await t.enterText(campoRotulado('Confirmar nova senha'), 'nova1234');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await assentar(t);
      expect(api.de('POST', '/api/auth/change-password').single.corpo, {'senha_atual': 'velha123', 'nova_senha': 'nova1234'});
      expect(find.text('Senha alterada com sucesso.'), findsOneWidget);
      expect(find.text('Salvar senha'), findsNothing);
      await encerrar(t);
    });
  });
}
