// Regressão da fase 2 (fidelidade ao v1): modais de Requisições, filtro ativo, Previsão de Entrega e texto de desativar.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestfast/core/regras.dart';
import 'package:gestfast/features/dialogos_estoque.dart';
import 'package:gestfast/features/funcionarios_tela.dart';
import 'package:gestfast/features/requisicoes_tela.dart';
import 'package:gestfast/widgets/comuns.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'apoio.dart';

const _permissoes = ['requisicoes:criar', 'requisicoes:receber', 'requisicoes:avancar', 'requisicoes:cancelar', 'dashboard:ver', 'usuarios:gerenciar'];

Map<String, dynamic> _req(int id, String situacao) => {
      'id_requisicao': id, 'codigo_pedido': 'REQ-00$id', 'fornecedor': 'Moinho', 'id_produto': 1, 'produto_nome': 'Farinha', 'quantidade_pedida': 10, 'quantidade_atendida': 0,
      'unidade': 'UN', 'valor_unitario': 2, 'valor_total': 20, 'situacao': situacao, 'data_pedido': '2026-11-03', 'previsao_entrega': '2026-11-07',
      'endereco_entrega': 'Rua A', 'observacao': '', 'justificativa_cancelamento': '', 'historico': [],
    };

Future<ApiFalsa> _abrirRequisicoes(WidgetTester t, {required bool servidorAceita}) async {
  final api = ApiFalsa({
    ...rotasBase(permissoes: _permissoes),
    'GET /api/requisitions': (_) => (200, {'success': true, 'requisicoes': [_req(1, 'Em Aberto'), _req(2, 'Cancelado')]}),
    'GET /api/products': (_) => (200, {'success': true, 'products': [produtoJson(1, 'Farinha')]}),
    'PATCH /api/requisitions/1/status': (_) => servidorAceita
        ? (200, {'success': true, 'message': 'Requisição atualizada.'})
        : (503, {'success': false, 'error': 'Sistema do fornecedor indisponível.'}),
  });
  final s = await criarSessao(api);
  await abrirTela(t, s, const RequisicoesTela());
  return api;
}

Future<void> _encerrar(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 6));
}

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  group('Requisições: modais só fecham no sucesso, como no v1 (item 2)', () {
    testWidgets('Cancelar com erro do servidor mantém o modal e a justificativa', (t) async {
      final api = await _abrirRequisicoes(t, servidorAceita: false);
      await t.tap(find.byTooltip('Cancelar Requisição'));
      await t.pumpAndSettle();
      const texto = 'Fornecedor atrasou a entrega do pedido';
      await t.enterText(find.byType(TextField).last, texto);
      await t.tap(find.text('Enviar'));
      await t.pumpAndSettle();
      expect(api.de('PATCH', '/api/requisitions/1/status').single.corpo, {'situacao': 'Cancelado', 'justificativa': texto});
      expect(find.text('Cancelar Requisição de Compra'), findsOneWidget, reason: 'o modal continua aberto');
      expect(t.widget<TextField>(find.byType(TextField).last).controller!.text, texto);
      await _encerrar(t);
    });

    testWidgets('Cancelar com sucesso fecha o modal', (t) async {
      await _abrirRequisicoes(t, servidorAceita: true);
      await t.tap(find.byTooltip('Cancelar Requisição'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).last, 'Fornecedor atrasou a entrega do pedido');
      await t.tap(find.text('Enviar'));
      await t.pumpAndSettle();
      expect(find.text('Cancelar Requisição de Compra'), findsNothing);
      await _encerrar(t);
    });

    testWidgets('Receber com erro do servidor mantém o modal e a quantidade', (t) async {
      final api = await _abrirRequisicoes(t, servidorAceita: false);
      await t.tap(find.byTooltip('Confirmar e Receber Mercadoria (Entrada no Estoque)'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).last, '4');
      await t.tap(find.text('Confirmar recebimento'));
      await t.pumpAndSettle();
      expect(api.de('PATCH', '/api/requisitions/1/status').single.corpo, {'situacao': 'Finalizado', 'quantidade_recebida': 4});
      expect(find.text('Receber mercadoria - REQ-001'), findsOneWidget);
      expect(t.widget<TextField>(find.byType(TextField).last).controller!.text, '4');
      await _encerrar(t);
    });

    testWidgets('Receber com sucesso fecha o modal', (t) async {
      await _abrirRequisicoes(t, servidorAceita: true);
      await t.tap(find.byTooltip('Confirmar e Receber Mercadoria (Entrada no Estoque)'));
      await t.pumpAndSettle();
      await t.tap(find.text('Confirmar recebimento'));
      await t.pumpAndSettle();
      expect(find.text('Receber mercadoria - REQ-001'), findsNothing);
      await _encerrar(t);
    });
  });

  testWidgets('Requisições: o filtro atual fica marcado, como o .active do v1 (item 3)', (t) async {
    await _abrirRequisicoes(t, servidorAceita: true);
    bool? marcado(String texto) => t.widget<Botao>(find.widgetWithText(Botao, texto)).selecionado;
    expect(marcado('Todos'), isTrue);
    expect(marcado('Cancelado'), isFalse);
    await t.tap(find.widgetWithText(Botao, 'Cancelado'));
    await t.pumpAndSettle();
    expect(marcado('Todos'), isFalse);
    expect(marcado('Cancelado'), isTrue);
    expect(find.text('REQ-001'), findsNothing);
    await _encerrar(t);
  });

  group('Previsão de Entrega começa hoje, sem oferecer ontem em UTC-3 (item 8)', () {
    test('dataLocal é meia-noite local do mesmo dia', () {
      final d = dataLocal('2026-11-03')!;
      expect(d.isUtc, isFalse);
      expect([d.year, d.month, d.day, d.hour], [2026, 11, 3, 0]);
      expect(dataLocal(''), isNull);
    });

    testWidgets('o calendário tem como primeiro dia o hoje do servidor', (t) async {
      final api = ApiFalsa({
        ...rotasBase(permissoes: _permissoes),
        'GET /api/suppliers': (_) => (200, {'success': true, 'suppliers': ['Moinho']}),
        'GET /api/products': (_) => (200, {'success': true, 'products': [produtoJson(1, 'Pão')]}),
      });
      final s = await criarSessao(api);
      late BuildContext ctx;
      await abrirTela(t, s, Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }));
      abrirNovaRequisicao(ctx, s, idProduto: 1);
      await t.pumpAndSettle();
      final campo = t.widget<CampoData>(find.byWidgetPredicate((w) => w is CampoData && w.rotulo == 'Previsão de Entrega'));
      expect(campo.primeira, DateTime(2026, 11, 3), reason: 'primeiro dia do calendário = hoje do servidor em hora local (não 02/11 21h)');
      await _encerrar(t);
    });
  });

  testWidgets('Funcionários: confirmação de desativar com o texto do v1 (item 9)', (t) async {
    final api = ApiFalsa({
      ...rotasBase(permissoes: _permissoes),
      'GET /api/profiles': (_) => (200, {'success': true, 'profiles': [{'id_perfil': 3, 'nome_perfil': 'Funcionario'}]}),
      'GET /api/users': (_) => (200, {'success': true, 'users': [{'id_usuario': 2, 'nome': 'Maria', 'email': 'maria@x.com', 'cargo': '', 'perfil': 'Funcionario', 'id_perfil': 3, 'status': 'Ativo'}]}),
    });
    final s = await criarSessao(api);
    await abrirTela(t, s, const FuncionariosTela());
    await t.tap(find.byTooltip('Desativar acesso'));
    await t.pumpAndSettle();
    expect(find.text('Desativar o acesso de Maria? Ele será desconectado e não poderá entrar no sistema, mas o histórico é preservado.'), findsOneWidget);
    await _encerrar(t);
  });
}
