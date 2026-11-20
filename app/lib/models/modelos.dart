// Modelos das respostas da API do GestFast.
import '../core/regras.dart';

typedef Json = Map<String, dynamic>;

String _s(dynamic v) => v == null ? '' : v.toString();
int _i(dynamic v) => v is num ? v.toInt() : int.tryParse(_s(v)) ?? 0;
int? _iOu(dynamic v) => v == null ? null : _i(v);
double? _dOu(dynamic v) => v == null ? null : numero(v);
List<Json> listaJson(dynamic v) => v is List ? v.whereType<Map>().map((e) => Json.from(e)).toList() : <Json>[];

class Usuario {
  Usuario.deJson(Json j)
      : id = _i(j['id_usuario']),
        nome = _s(j['nome']),
        email = _s(j['email']),
        cargo = _s(j['cargo']),
        perfil = _s(j['perfil']),
        idPerfil = _i(j['id_perfil']),
        status = _s(j['status']);
  final int id, idPerfil;
  final String nome, email, cargo, perfil, status;
  bool get ativo => status == 'Ativo';
  bool get admin => perfil == 'Administrador';
  bool get gerente => admin || perfil == 'BackOffice';
}

class Categoria {
  Categoria.deJson(Json j)
      : id = _i(j['id_categoria']),
        nome = _s(j['nome_categoria']);
  final int id;
  final String nome;
}

class Produto {
  Produto.deJson(Json j)
      : id = _i(j['id_produto']),
        codigo = _s(j['codigo_barras']),
        nome = _s(j['nome_produto']),
        descricao = _s(j['descricao']),
        unidade = _s(j['unidade']),
        peso = _s(j['peso']),
        custo = numero(j['preco_custo']),
        venda = numero(j['preco_venda']),
        minimo = numero(j['preco_min']),
        maximo = numero(j['preco_max']),
        estoque = numero(j['quantidade_estoque']),
        estoqueMinimo = numero(j['estoque_minimo']),
        lote = _s(j['lote']),
        validade = _s(j['validade']),
        imagem = _s(j['imagem']),
        status = _s(j['status']),
        idCategoria = _i(j['id_categoria']);
  final int id, idCategoria;
  final String codigo, nome, descricao, unidade, peso, lote, validade, imagem, status;
  final double custo, venda, minimo, maximo, estoque, estoqueMinimo;
  bool get ativo => status == 'Ativo';
  bool get critico => estoque <= estoqueMinimo;
}

class Movimentacao {
  Movimentacao.deJson(Json j)
      : id = _i(j['id_movimentacao']),
        tipo = _s(j['tipo_movimentacao']),
        idProduto = _i(j['id_produto']),
        quantidade = numero(j['quantidade']),
        data = _s(j['data_movimentacao']),
        observacao = _s(j['observacao']),
        produto = _s(j['produto_nome']),
        codigo = _s(j['codigo_barras']),
        unidade = _s(j['unidade']),
        valorUnitario = numero(j['valor_unitario']),
        valorTotal = numero(j['valor_total']),
        usuario = _s(j['usuario_nome']),
        origem = _s(j['origem']),
        motivoPerda = _s(j['motivo_perda']);
  final int id, idProduto;
  final String tipo, data, observacao, produto, codigo, unidade, usuario, origem, motivoPerda;
  final double quantidade, valorUnitario, valorTotal;
}

class ItemVenda {
  ItemVenda.deJson(Json j)
      : id = _i(j['id_item_venda']),
        idProduto = _i(j['id_produto']),
        nome = _s(j['nome_produto']),
        unidade = _s(j['unidade']),
        quantidade = numero(j['quantidade']),
        valorUnitario = numero(j['valor_unitario']),
        subtotal = numero(j['subtotal']);
  final int id, idProduto;
  final String nome, unidade;
  final double quantidade, valorUnitario, subtotal;
}

class Venda {
  Venda.deJson(Json j)
      : id = _i(j['id_venda']),
        codigo = _s(j['codigo_venda']),
        data = _s(j['data_venda']),
        subtotal = numero(j['valor_subtotal']),
        desconto = numero(j['desconto']),
        total = numero(j['valor_total']),
        forma = _s(j['forma_pagamento']),
        recebido = _dOu(j['valor_recebido']),
        troco = _dOu(j['troco']),
        nsu = _s(j['nsu']),
        status = _s(j['status_venda']),
        usuario = _s(j['usuario_nome']),
        motivoCancelamento = _s(j['motivo_cancelamento']),
        canceladaPor = _s(j['cancelada_por']),
        autorizadaPor = _s(j['autorizada_por']),
        dataCancelamento = _s(j['data_cancelamento']),
        editadaPor = _s(j['editada_por']),
        dataEdicao = _s(j['data_edicao']),
        itens = listaJson(j['itens']).map(ItemVenda.deJson).toList();
  final int id;
  final String codigo, data, forma, nsu, status, usuario, motivoCancelamento, canceladaPor, autorizadaPor, dataCancelamento, editadaPor, dataEdicao;
  final double subtotal, desconto, total;
  final double? recebido, troco;
  final List<ItemVenda> itens;
  bool get concluida => status == 'Concluída';
}

class Requisicao {
  Requisicao.deJson(Json j)
      : id = _i(j['id_requisicao']),
        codigo = _s(j['codigo_pedido']),
        fornecedor = _s(j['fornecedor']),
        idProduto = _iOu(j['id_produto']),
        produto = _s(j['produto_nome']),
        pedida = numero(j['quantidade_pedida']),
        atendida = numero(j['quantidade_atendida']),
        unidade = _s(j['unidade']),
        valorUnitario = numero(j['valor_unitario']),
        valorTotal = numero(j['valor_total']),
        situacao = _s(j['situacao']),
        dataPedido = _s(j['data_pedido']),
        previsao = _s(j['previsao_entrega']),
        endereco = _s(j['endereco_entrega']),
        observacao = _s(j['observacao']),
        justificativa = _s(j['justificativa_cancelamento']),
        historico = listaJson(j['historico']);
  final int id;
  final int? idProduto;
  final String codigo, fornecedor, produto, unidade, situacao, dataPedido, previsao, endereco, observacao, justificativa;
  final double pedida, atendida, valorUnitario, valorTotal;
  final List<Json> historico;
  bool get aberta => situacoesAbertas.contains(situacao);
  double get pendente => r3(pedida - atendida);
}

class Configuracoes {
  Configuracoes.deJson(Json j)
      : estabelecimento = _s(j['estabelecimento']),
        descontoMaximo = numero(j['descontoMaximoPercent']),
        intervaloSeg = _i(j['intervaloAtualizacaoSeg']),
        diasValidade = _i(j['diasAlertaValidade']),
        simularCartao = j['simularCartaoNegado'] == true,
        simularFornecedor = j['simularFornecedorIndisponivel'] == true;
  final String estabelecimento;
  final double descontoMaximo;
  final int intervaloSeg, diasValidade;
  final bool simularCartao, simularFornecedor;
}
