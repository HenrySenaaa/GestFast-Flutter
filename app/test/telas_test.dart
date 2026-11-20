// Testes de widget dos fluxos principais, com os textos do v1, e dos bugs de tela corrigidos no porte.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestfast/core/rotas.dart';
import 'package:gestfast/core/sessao.dart';
import 'package:gestfast/features/dialogos_estoque.dart';
import 'package:gestfast/features/estoque_tela.dart';
import 'package:gestfast/features/historico_tela.dart';
import 'package:gestfast/features/login_tela.dart';
import 'package:gestfast/features/produtos_tela.dart';
import 'package:gestfast/features/vendas_tela.dart';
import 'package:gestfast/widgets/comuns.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'apoio.dart';

const _todasPermissoes = ['vendas:vender', 'vendas:ver', 'vendas:editar', 'vendas:cancelar', 'requisicoes:criar', 'movimentos:registrar', 'dashboard:ver'];

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  group('Login', () {
    testWidgets('erro depois de um sucesso aparece como erro (bug 24)', (t) async {
      final api = ApiFalsa({
        'POST /api/auth/reset': (_) => (200, {'success': true, 'message': 'Senha redefinida com sucesso.'}),
        'POST /api/auth/login': (_) => (401, {'success': false, 'error': 'E-mail ou senha incorretos'}),
      });
      final s = await criarSessao(api, logar: false);
      await abrirTela(t, s, const LoginTela(redefinir: true, codigoRedefinicao: 'cod'));
      await t.enterText(campoRotulado('Nova senha'), 'senha123');
      await t.enterText(campoRotulado('Confirmar nova senha'), 'senha123');
      await t.tap(find.text('Redefinir senha'));
      await t.pumpAndSettle();
      expect(find.text('Senha redefinida com sucesso.'), findsOneWidget);

      await t.enterText(campoRotulado('E-mail'), 'a@b.com');
      await t.enterText(campoRotulado('Senha'), 'errada');
      await t.tap(find.text('Entrar'));
      await t.pumpAndSettle();
      expect(find.text('Senha redefinida com sucesso.'), findsNothing);
      expect(find.text('E-mail ou senha incorretos'), findsOneWidget);
    });

    testWidgets('campos vazios não chamam o servidor', (t) async {
      final api = ApiFalsa({});
      await abrirTela(t, await criarSessao(api, logar: false), const LoginTela());
      await t.tap(find.text('Entrar'));
      await t.pumpAndSettle();
      expect(find.text('Preencha o e-mail e a senha para continuar.'), findsOneWidget);
      expect(api.chamadas, isEmpty);
    });
  });

  group('Conferência', () {
    ApiFalsa montar(List<Map<String, dynamic>> enviados) => ApiFalsa({
          ...rotasBase(),
          'GET /api/inventory': (_) => (200, {'success': true, 'conferencias': [], 'itensParaConferencia': [produtoJson(1, 'Pão', estoque: 10), produtoJson(2, 'Bala', estoque: 7)]}),
          'POST /api/inventory': (c) {
            enviados.addAll((c.corpo!['itens'] as List).cast<Map<String, dynamic>>());
            return (201, {'success': true, 'message': 'Conferência salva'});
          },
        });

    Future<void> salvar(WidgetTester t) async {
      await t.tap(find.text('💾 Salvar Conferência Física'));
      await t.pumpAndSettle();
      await t.enterText(campoRotulado('Observação * (10 a 1000 caracteres)'), 'Conferência quinzenal do balcão');
      await t.tap(find.text('Salvar conferência'));
      await t.pumpAndSettle();
    }

    testWidgets('como no v1, a contagem começa com o saldo do sistema', (t) async {
      await abrirTela(t, await criarSessao(montar([])), const EstoqueTela());
      expect(t.widget<TextField>(campoRotulado('Contagem física de Pão')).controller!.text, '10');
    });

    testWidgets('filtro não apaga a contagem (bug 21) e só o contado é enviado, com o saldo lido (bug 2)', (t) async {
      final enviados = <Map<String, dynamic>>[];
      await abrirTela(t, await criarSessao(montar(enviados)), const EstoqueTela());
      await t.enterText(campoRotulado('Contagem física de Pão'), '9');
      await t.pump();
      expect(find.text('-1'), findsOneWidget);

      await t.enterText(campoRotulado('Filtrar estoque por termo'), 'bala');
      await t.pump();
      expect(find.text('Pão'), findsNothing);
      await t.enterText(campoRotulado('Filtrar estoque por termo'), '');
      await t.pump();
      expect(find.text('-1'), findsOneWidget, reason: 'a contagem digitada continua lá');

      await salvar(t);
      expect(enviados, [{'id_produto': 1, 'quantidade_fisica': 9.0, 'quantidade_sistema': 10.0}]);
    });

    testWidgets('sem nada digitado, confirma o que está na tela, como no v1, com o saldo lido', (t) async {
      final enviados = <Map<String, dynamic>>[];
      await abrirTela(t, await criarSessao(montar(enviados)), const EstoqueTela());
      await salvar(t);
      expect(enviados, [
        {'id_produto': 1, 'quantidade_fisica': 10.0, 'quantidade_sistema': 10.0},
        {'id_produto': 2, 'quantidade_fisica': 7.0, 'quantidade_sistema': 7.0},
      ]);
    });
  });

  group('Caixa', () {
    Future<void> inserir(WidgetTester t, {String? qtd}) async {
      await t.enterText(campoRotulado('Código de barras / nome:'), '7891');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      if (qtd != null) await t.enterText(campoRotulado('Quant.:'), qtd);
      await t.tap(find.text('Inserir no Pedido'));
      await t.pumpAndSettle();
    }

    testWidgets('fluxo: localiza por código, insere e finaliza com troco', (t) async {
      Map<String, dynamic>? venda;
      final api = ApiFalsa({
        ...rotasBase(permissoes: _todasPermissoes),
        'GET /api/products': (_) => (200, {'success': true, 'products': [produtoJson(1, 'Pão', estoque: 10, venda: 5)]}),
        'POST /api/sales': (c) {
          venda = c.corpo;
          return (201, {'success': true, 'message': 'Venda realizada com sucesso', 'sale': {'id_venda': 1, 'codigo_venda': 'VENDA-1001', 'valor_total': 10, 'troco': 10, 'itens': []}});
        },
      });
      await abrirTela(t, await criarSessao(api), const VendasTela());
      await inserir(t, qtd: '2');
      expect(find.text('10,00'), findsWidgets);

      await t.enterText(campoRotulado('Valor recebido R\$:'), '20');
      await t.pump();
      expect(find.text('R\$ 10,00'), findsOneWidget, reason: 'troco');

      await t.tap(find.text('Finalizar Venda & Baixar Estoque'));
      await t.pumpAndSettle();
      expect(venda!['itens'], [{'id_produto': 1, 'quantidade': 2.0}]);
      expect(venda!['forma_pagamento'], 'Dinheiro');
      expect(venda!['valor_recebido'], 20.0);
      expect(find.text('0,00'), findsOneWidget, reason: 'a venda é limpa depois de finalizar');
    });

    testWidgets('cartão negado mantém a venda aberta', (t) async {
      final api = ApiFalsa({
        ...rotasBase(permissoes: _todasPermissoes),
        'GET /api/products': (_) => (200, {'success': true, 'products': [produtoJson(1, 'Pão', estoque: 10, venda: 5)]}),
        'POST /api/sales': (_) => (402, {'success': false, 'error': 'Transação Negada pela Operadora'}),
      });
      await abrirTela(t, await criarSessao(api), const VendasTela());
      await inserir(t);
      await t.tap(find.text('Finalizar Venda & Baixar Estoque'));
      await t.pumpAndSettle();
      expect(find.text('Transação Negada pela Operadora'), findsOneWidget);
      expect(find.text('5,00'), findsWidgets);
    });
  });

  group('Histórico', () {
    Map<String, dynamic> venda() => {
          'id_venda': 5, 'codigo_venda': 'VENDA-1005', 'data_venda': '2026-11-03 10:00', 'valor_subtotal': 10, 'desconto': 0, 'valor_total': 10, 'forma_pagamento': 'Dinheiro', 'valor_recebido': 20, 'troco': 10, 'status_venda': 'Concluída', 'usuario_nome': 'Henry',
          'itens': [{'id_item_venda': 77, 'id_produto': 1, 'nome_produto': 'Pão', 'unidade': 'UN', 'quantidade': 2, 'valor_unitario': 5, 'subtotal': 10}],
        };

    testWidgets('editar envia a linha do item; quantidade negativa é recusada (bug 23)', (t) async {
      Map<String, dynamic>? corpo;
      final api = ApiFalsa({
        ...rotasBase(permissoes: _todasPermissoes),
        'GET /api/sales': (_) => (200, {'success': true, 'sales': [venda()]}),
        'PUT /api/sales/5': (c) {
          corpo = c.corpo;
          return (200, {'success': true, 'message': 'Venda atualizada com sucesso', 'sale': venda()});
        },
      });
      await abrirTela(t, await criarSessao(api), const HistoricoTela());
      await t.tap(find.byTooltip('Editar quantidades'));
      await t.pumpAndSettle();

      await t.enterText(campoRotulado('Quantidade'), '-3');
      await t.tap(find.text('Salvar alterações'));
      await t.pumpAndSettle();
      expect(corpo, isNull);
      expect(find.textContaining('Informe zero ou mais'), findsOneWidget);

      await t.enterText(campoRotulado('Quantidade'), '3');
      await t.enterText(campoRotulado('Valor recebido (R\$)'), '50');
      await t.tap(find.text('Salvar alterações'));
      await t.pumpAndSettle();
      expect(corpo, {'itens': [{'id_produto': 1, 'id_item_venda': 77, 'quantidade': 3.0}], 'valor_recebido': 50.0});
    });
  });

  group('Nova requisição', () {
    testWidgets('a quantidade sugerida volta ao trocar de produto (bug 22) e a entrega usa a data do servidor (bug 25)', (t) async {
      final api = ApiFalsa({
        ...rotasBase(permissoes: _todasPermissoes),
        'GET /api/suppliers': (_) => (200, {'success': true, 'suppliers': ['Moinho']}),
        'GET /api/products': (_) => (200, {'success': true, 'products': [{...produtoJson(1, 'Pão', estoque: 2), 'estoque_minimo': 10}, produtoJson(2, 'Bala')]}),
      });
      final s = await criarSessao(api);
      late BuildContext ctx;
      await abrirTela(t, s, Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }));
      abrirNovaRequisicao(ctx, s, idProduto: 1);
      await t.pumpAndSettle();
      final qtd = campoRotulado('Quantidade *');
      expect(t.widget<TextField>(qtd).controller!.text, '18', reason: 'mínimo 10 x 2 - saldo 2');
      expect(find.text('07/11/2026'), findsOneWidget, reason: 'hoje do servidor (03/11) + 4 dias');

      await t.enterText(qtd, '99');
      await t.tap(find.text('Pão (UN)'));
      await t.pumpAndSettle();
      await t.tap(find.text('Bala (UN)').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Bala (UN)').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Pão (UN)').last);
      await t.pumpAndSettle();
      expect(t.widget<TextField>(campoRotulado('Quantidade *')).controller!.text, '18');
    });
  });

  group('Produto', () {
    testWidgets('na edição o estoque é só leitura e não vai ao servidor (bug 1)', (t) async {
      Map<String, dynamic>? corpo;
      final p = {...produtoJson(1, 'Pão', estoque: 10), 'preco_custo': 1.5};
      final api = ApiFalsa({
        ...rotasBase(permissoes: _todasPermissoes),
        'GET /api/products': (_) => (200, {'success': true, 'products': [p]}),
        'GET /api/products/1': (_) => (200, {'success': true, 'product': p}),
        'PUT /api/products/1': (c) {
          corpo = c.corpo;
          return (200, {'success': true, 'message': 'Produto atualizado com sucesso!', 'product': p});
        },
      });
      await abrirTela(t, await criarSessao(api), const ProdutosTela(abrirId: 1));
      final estoque = t.widget<TextField>(campoRotulado('Estoque Atual Inicial'));
      expect(estoque.readOnly, isTrue);
      expect(estoque.controller!.text, '10');
      expect(t.widget<TextField>(campoRotulado('Preço custo')).controller!.text, '1,5', reason: 'decimal com vírgula');
      await t.tap(find.text('✓ Confirmar alterações'));
      await t.pumpAndSettle();
      expect(corpo, isNotNull);
      expect(corpo!.containsKey('quantidade_estoque'), isFalse);
      expect(corpo!['preco_custo'], 1.5);
    });
  });

  group('Avisos', () {
    testWidgets('toast aparece por cima de um modal aberto e some sozinho', (t) async {
      await abrirTela(t, await criarSessao(ApiFalsa(rotasBase())), Builder(builder: (c) => TextButton(onPressed: () => showDialog<void>(context: c, builder: (_) => const Modal(titulo: 'Modal', filhos: [])), child: const Text('abrir'))));
      await t.tap(find.text('abrir'));
      await t.pumpAndSettle();
      avisar('Erro visível', tipo: TipoAviso.erro);
      await t.pump();
      expect(find.text('Erro visível').hitTestable(), findsOneWidget, reason: 'o modal não cobre o aviso');
      await t.pump(const Duration(seconds: 7));
      expect(find.text('Erro visível'), findsNothing);
    });
  });

  group('Permissões', () {
    testWidgets('BackOffice não acessa o caixa pelo endereço nem vê no menu (bug 26)', (t) async {
      final api = ApiFalsa({
        ...rotasBase(perfil: 'BackOffice', permissoes: const ['dashboard:ver', 'produtos:editar']),
        'GET /api/dashboard': (_) => (200, {'success': true, 'latencyMs': 1, 'data': {
              'metricas': {},
              'validades': {'itens': [], 'vencidos': 0, 'dias': 3}, 'alertas': [], 'ultimasCompras': [], 'distribuicaoEstoque': [],
            }}),
      });
      final s = await criarSessao(api);
      final rotas = criarRotas(s);
      t.view.physicalSize = const Size(1400, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(
        overrides: [sessaoProvider.overrideWith((ref) => s)],
        child: MaterialApp.router(builder: (_, filho) => CamadaAvisos(child: filho!), routerConfig: rotas),
      ));
      await t.pump();
      rotas.go('/venda');
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(rotas.state.matchedLocation, '/painel');
      expect(find.text('Cadastro de Produtos'), findsOneWidget);
      expect(find.text('Venda'), findsNothing);
      expect(find.text('🛒 Abrir Caixa'), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 4));
    });
  });
}
