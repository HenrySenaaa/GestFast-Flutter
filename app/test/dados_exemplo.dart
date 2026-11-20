// Dados de exemplo da API para abrir qualquer tela nos testes (mesmos campos que o servidor devolve).
import 'apoio.dart';

Map<String, dynamic> requisicaoJson(int id, String situacao, {String produto = 'Farinha de Trigo Especial', num pedida = 10, num atendida = 0}) => {
      'id_requisicao': id, 'codigo_pedido': 'REQ-${9660 + id}', 'fornecedor': 'Moinho Santa Clara', 'id_produto': 1, 'produto_nome': produto, 'quantidade_pedida': pedida, 'quantidade_atendida': atendida,
      'unidade': 'KG', 'valor_unitario': 4.5, 'valor_total': pedida * 4.5, 'situacao': situacao, 'data_pedido': '2026-11-03 09:15', 'previsao_entrega': '2026-11-07',
      'endereco_entrega': 'Rua das Padarias, 123 - Centro', 'observacao': 'Entregar pela manhã, antes das 7h.', 'justificativa_cancelamento': situacao == 'Cancelado' ? 'Fornecedor sem estoque no momento.' : '',
      'historico': [
        {'situacao': 'Em Aberto', 'data': '2026-11-03 09:15', 'usuario': 'Francisco'},
        if (situacao != 'Em Aberto') {'situacao': situacao, 'data': '2026-11-04 10:00', 'usuario': 'Henry'},
      ],
    };

Map<String, dynamic> vendaJson(int id, {String status = 'Concluída', String forma = 'Dinheiro', num desconto = 0, String dataEdicao = ''}) => {
      'id_venda': id, 'codigo_venda': 'VENDA-${1000 + id}', 'data_venda': '2026-11-03 10:0$id', 'valor_subtotal': 20, 'desconto': desconto, 'valor_total': 20 - desconto, 'forma_pagamento': forma,
      'valor_recebido': forma == 'Dinheiro' ? 50 : null, 'troco': forma == 'Dinheiro' ? 30 + desconto : null, 'nsu': forma == 'Dinheiro' ? '' : '123456', 'status_venda': status, 'usuario_nome': 'Henry Sena',
      'motivo_cancelamento': status == 'Cancelada' ? 'Cliente desistiu da compra no caixa.' : '', 'cancelada_por': status == 'Cancelada' ? 'Henry Sena' : '', 'autorizada_por': status == 'Cancelada' ? 'Francisco' : '',
      'data_cancelamento': status == 'Cancelada' ? '2026-11-03 11:00' : '', 'editada_por': dataEdicao.isEmpty ? '' : 'Francisco', 'data_edicao': dataEdicao,
      'itens': [
        {'id_item_venda': id * 10, 'id_produto': 1, 'nome_produto': 'Pão Francês', 'unidade': 'KG', 'quantidade': 1.5, 'valor_unitario': 10, 'subtotal': 15},
        {'id_item_venda': id * 10 + 1, 'id_produto': 2, 'nome_produto': 'Sonho de Creme', 'unidade': 'UN', 'quantidade': 1, 'valor_unitario': 5, 'subtotal': 5},
      ],
    };

final painelExemplo = painelJson(
  alertas: [
    {'id_produto': 1, 'nome_produto': 'Farinha de Trigo Especial Tipo 1 com nome longo', 'quantidade_estoque': 2, 'estoque_minimo': 10, 'unidade': 'KG', 'mensagem': 'Estoque abaixo do mínimo'},
  ],
  validades: [
    {'id_produto': 2, 'nome_produto': 'Iogurte Natural', 'validade': '2026-11-01', 'dias_restantes': -2, 'lote': 'L9', 'quantidade_estoque': 4, 'unidade': 'UN', 'valor_em_risco': 8},
    {'id_produto': 3, 'nome_produto': 'Presunto Fatiado', 'validade': '2026-11-03', 'dias_restantes': 0, 'lote': '', 'quantidade_estoque': 1.25, 'unidade': 'KG', 'valor_em_risco': 30},
    {'id_produto': 4, 'nome_produto': 'Queijo Minas', 'validade': '2026-11-05', 'dias_restantes': 2, 'lote': 'Q1', 'quantidade_estoque': 3, 'unidade': 'KG', 'valor_em_risco': 60},
  ],
  vencidos: 1,
  compras: [
    {'id_requisicao': 1, 'produto_nome': 'Farinha de Trigo', 'quantidade_pedida': 50, 'codigo_pedido': 'REQ-9661', 'fornecedor': 'Moinho', 'situacao': 'Em Aberto'},
  ],
  distribuicao: [
    {'categoria': 'Pães', 'quantidade': 60, 'porcentagem': 60},
    {'categoria': 'Bebidas', 'quantidade': 25, 'porcentagem': 25},
    {'categoria': 'Frios', 'quantidade': 15, 'porcentagem': 15},
  ],
);

final produtosExemplo = [
  produtoJson(1, 'Pão Francês', unidade: 'KG', estoque: 12.5, venda: 16.9),
  produtoJson(2, 'Sonho de Creme', estoque: 8, venda: 6.5),
  produtoJson(3, 'Bolo de Cenoura', estoque: 0),
];

final movimentosExemplo = [
  {
    'id_movimentacao': 1, 'tipo_movimentacao': 'Saída', 'quantidade': 2, 'data_movimentacao': '2026-11-03 08:00', 'observacao': 'Baixa do lote L9 (sistema 6 → físico 4)', 'produto_nome': 'Iogurte Natural',
    'codigo_barras': '7892', 'unidade': 'UN', 'valor_unitario': 2, 'valor_total': 4, 'usuario_nome': 'Henry Sena', 'origem': 'perda', 'motivo_perda': 'Vencido',
  },
  {
    'id_movimentacao': 2, 'tipo_movimentacao': 'Entrada', 'quantidade': 10.5, 'data_movimentacao': '2026-11-03 07:00', 'observacao': 'Recebimento do fornecedor', 'produto_nome': 'Pão Francês',
    'codigo_barras': '7891', 'unidade': 'KG', 'valor_unitario': 8, 'valor_total': 84, 'usuario_nome': 'Francisco', 'origem': 'manual', 'motivo_perda': '',
  },
];

final relVendasExemplo = {
  'itensVendidos': [
    {'nome_produto': 'Pão Francês', 'valor_unitario': 16.9, 'quantidade': 3.5, 'unidade': 'KG', 'total': 59.15},
    {'nome_produto': 'Sonho de Creme', 'valor_unitario': 6.5, 'quantidade': 4, 'unidade': 'UN', 'total': 26},
  ],
  'porPagamento': [{'forma': 'Dinheiro', 'total': 50}, {'forma': 'PIX', 'total': 35.15}],
  'quantidadeTransacoes': 3, 'ticketMedio': 28.38, 'totalDescontos': 2, 'totalGeral': 85.15,
};

final relEstoqueExemplo = {
  'linhas': [
    {'nome_produto': 'Pão Francês', 'categoria': 'Pães', 'entradas': 10.5, 'saidas': 3.5, 'saldo_atual': 12.5, 'unidade': 'KG', 'estoque_minimo': 1, 'situacao': 'Regular'},
    {'nome_produto': 'Iogurte Natural', 'categoria': 'Laticínios', 'entradas': 0, 'saidas': 2, 'saldo_atual': 0, 'unidade': 'UN', 'estoque_minimo': 5, 'situacao': 'Crítico'},
  ],
  'totalProdutos': 2, 'totalCriticos': 1, 'valorTotalEstoque': 125,
};

final relPerdasExemplo = {
  'porProduto': [{'nome_produto': 'Iogurte Natural', 'categoria': 'Laticínios', 'registros': 1, 'quantidade': 2, 'unidade': 'UN', 'valor_total': 4}],
  'porMotivo': [{'motivo': 'Vencido', 'valor_total': 4}],
  'totalRegistros': 1, 'valorTotal': 4,
};

final usuariosExemplo = [
  usuarioJson(),
  {'id_usuario': 2, 'nome': 'Henry Sena', 'email': 'henry@padarianovayork.com', 'cargo': 'Atendente de balcão', 'perfil': 'Funcionario', 'id_perfil': 3, 'status': 'Ativo'},
  {'id_usuario': 3, 'nome': 'Nicolas Viana', 'email': 'nicolas@x.com', 'cargo': '', 'perfil': 'BackOffice', 'id_perfil': 2, 'status': 'Inativo'},
];

const perfisExemplo = [
  {'id_perfil': 1, 'nome_perfil': 'Administrador'},
  {'id_perfil': 2, 'nome_perfil': 'BackOffice'},
  {'id_perfil': 3, 'nome_perfil': 'Funcionario'},
];

final logsExemplo = [
  {'ts': '2026-11-03T13:05:09.000Z', 'nivel': 'INFO', 'evento': 'login', 'usuario': 'dono@x.com', 'ip': '127.0.0.1'},
  {'ts': '2026-11-03T13:06:00.000Z', 'nivel': 'AVISO', 'evento': 'login_falhou', 'usuario': null, 'email': 'x@y.com'},
  {'ts': '2026-11-03T13:07:00.000Z', 'nivel': 'ERRO', 'evento': 'erro_interno', 'usuario': 'henry@x.com'},
];

final conferenciasExemplo = [
  {
    'id_conferencia': 7, 'data_conferencia': '2026-11-02 18:00', 'responsavel': 'Henry Sena', 'observacao': 'Conferência quinzenal do balcão.', 'ajustou_estoque': false,
    'itens': [
      {'nome_produto': 'Pão Francês', 'quantidade_sistema': 12, 'quantidade_fisica': 11.5, 'divergencia': -0.5, 'unidade': 'KG'},
      {'nome_produto': 'Queijo Minas', 'quantidade_sistema': 3, 'quantidade_fisica': 4, 'divergencia': 1, 'unidade': 'KG'},
      {'nome_produto': 'Bala', 'quantidade_sistema': 3, 'quantidade_fisica': 3, 'divergencia': 0, 'unidade': 'UN'},
    ],
  },
];

/// Todas as rotas de leitura da API com os dados de exemplo.
Map<String, Resposta Function(Chamada)> rotasCompletas({String perfil = 'Administrador', List<String> permissoes = permissoesAdmin}) => {
      ...rotasBase(perfil: perfil, permissoes: permissoes),
      'GET /api/dashboard': (_) => (200, painelExemplo),
      'GET /api/inventory': (_) => (200, {
            'success': true,
            'itensParaConferencia': [
              produtoJson(1, 'Pão Francês', unidade: 'KG', estoque: 12.5),
              {...produtoJson(2, 'Iogurte Natural', estoque: 0, validade: '2026-11-01'), 'estoque_minimo': 5},
              produtoJson(3, 'Queijo Minas', validade: '2026-11-05'),
            ],
            'conferencias': conferenciasExemplo,
          }),
      'GET /api/requisitions': (_) => (200, {'success': true, 'requisicoes': [requisicaoJson(1, 'Em Aberto'), requisicaoJson(2, 'Cotado'), requisicaoJson(3, 'Finalizado', atendida: 10), requisicaoJson(4, 'Cancelado')]}),
      'GET /api/products': (_) => (200, {'success': true, 'products': produtosExemplo}),
      'GET /api/products/1': (_) => (200, {'success': true, 'product': produtosExemplo.first}),
      'GET /api/suppliers': (_) => (200, {'success': true, 'suppliers': ['Moinho Santa Clara', 'Laticínios Bom Leite']}),
      'GET /api/movements': (_) => (200, {'success': true, 'movements': movimentosExemplo}),
      'GET /api/sales': (_) => (200, {'success': true, 'sales': [vendaJson(1, desconto: 2), vendaJson(2, status: 'Cancelada', forma: 'PIX'), vendaJson(3, forma: 'Cartão Crédito', dataEdicao: '2026-11-03 12:00')]}),
      'GET /api/reports/sales': (_) => (200, {'success': true, 'report': relVendasExemplo}),
      'GET /api/reports/stock': (_) => (200, {'success': true, 'report': relEstoqueExemplo}),
      'GET /api/reports/losses': (_) => (200, {'success': true, 'report': relPerdasExemplo}),
      'GET /api/profiles': (_) => (200, {'success': true, 'profiles': perfisExemplo}),
      'GET /api/users': (_) => (200, {'success': true, 'users': usuariosExemplo}),
      'GET /api/logs': (_) => (200, {'success': true, 'logs': logsExemplo}),
      'GET /api/search': (_) => (200, {'success': true, 'results': {'produtos': [], 'requisicoes': [], 'vendas': [], 'usuarios': []}}),
    };
