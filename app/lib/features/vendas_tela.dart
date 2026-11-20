// Caixa (PDV): painel escuro à esquerda e pedido à direita, iguais ao v1.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/regras.dart';
import '../core/sessao.dart';
import '../core/tema.dart';
import '../models/modelos.dart';
import '../widgets/comuns.dart';
import 'carrinho.dart';
import 'dialogos_estoque.dart';

class VendasTela extends ConsumerStatefulWidget {
  const VendasTela({super.key});
  @override
  ConsumerState<VendasTela> createState() => _VendasTelaState();
}

class _VendasTelaState extends ConsumerState<VendasTela> {
  final _carrinho = Carrinho();
  List<Produto> _produtos = [];
  int? _produto;
  final _busca = TextEditingController(), _qtd = TextEditingController(text: '1'), _desconto = TextEditingController(text: '0'), _recebido = TextEditingController();
  final _focoBusca = FocusNode(), _focoQtd = FocusNode(), _focoDesconto = FocusNode();
  String _forma = 'Dinheiro', _tipoDesconto = 'valor';
  bool _finalizando = false, _erroBusca = false, _erroQtd = false;
  int? _selecionado;

  Sessao get _s => ref.read(sessaoProvider);
  Produto? get _p => _produtos.where((x) => x.id == _produto).firstOrNull;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  @override
  void dispose() {
    for (final c in [_busca, _qtd, _desconto, _recebido]) {
      c.dispose();
    }
    _focoBusca.dispose();
    _focoQtd.dispose();
    _focoDesconto.dispose();
    super.dispose();
  }

  Future<void> _iniciar() async {
    await _s.sincronizar();
    await _carregarProdutos();
    if (mounted) _focoBusca.requestFocus();
  }

  Future<void> _carregarProdutos() async {
    final lista = await tentar(() => carregarProdutosAtivos(_s));
    if (!mounted) return;
    setState(() {
      if (lista != null) _produtos = lista;
    });
  }

  double get _descontoValor => lerNumero(_desconto.text) ?? 0;
  double? get _recebidoValor => lerNumero(_recebido.text);
  Totais get _totais => _carrinho.totais(tipoDesconto: _tipoDesconto, desconto: _descontoValor);

  void _buscarCodigo() {
    if (_busca.text.trim().isEmpty) return;
    final achados = Carrinho.buscar(_produtos, _busca.text);
    if (achados.isEmpty) {
      setState(() => _erroBusca = true);
      avisar('Produto não cadastrado.', tipo: TipoAviso.erro);
      _focoBusca.requestFocus();
      return;
    }
    if (achados.length > 1) avisar('${achados.length} produtos encontrados: refine a busca ou escolha na lista.');
    setState(() {
      _produto = achados.first.id;
      _busca.clear();
      _erroBusca = false;
    });
    _focoQtd.requestFocus();
    _qtd.selection = TextSelection(baseOffset: 0, extentOffset: _qtd.text.length);
  }

  Future<void> _adicionar() async {
    final p = _p;
    if (p == null) {
      avisar('Selecione um produto para inserir no pedido.', tipo: TipoAviso.erro);
      return;
    }
    final v = situacaoValidade(p.validade, _s.hoje, _s.diasValidade);
    if (v?.vencido == true && !await confirmar(context, '"${p.nome}" está VENCIDO (validade ${dataBR(p.validade)}). Deseja adicionar ao pedido mesmo assim?', titulo: 'Produto vencido', ok: 'Adicionar mesmo assim', perigo: true)) {
      return;
    }
    final erro = _carrinho.adicionar(p, lerNumero(_qtd.text));
    if (erro != null) {
      setState(() => _erroQtd = true);
      avisar(erro, tipo: TipoAviso.erro);
      _focoQtd.requestFocus();
      return;
    }
    setState(() {
      _selecionado = null;
      _erroQtd = false;
      _qtd.text = '1';
    });
    _focoBusca.requestFocus();
  }

  void _remover() {
    if (_carrinho.itens.isEmpty) {
      avisar('Não há itens para remover.');
      return;
    }
    final i = _selecionado != null && _selecionado! < _carrinho.itens.length ? _selecionado! : _carrinho.itens.length - 1;
    final item = _carrinho.itens.removeAt(i);
    setState(() => _selecionado = null);
    avisar('"${item.nome}" removido do pedido.');
  }

  void _limparVenda() => setState(() {
        _carrinho.itens.clear();
        _selecionado = null;
        _desconto.text = '0';
        _recebido.clear();
        _qtd.text = '1';
      });

  Future<void> _finalizar() async {
    if (_carrinho.itens.isEmpty) {
      avisar('Nenhum item inserido na venda.', tipo: TipoAviso.erro);
      return;
    }
    final t = _totais;
    final erro = _carrinho.erroDesconto(tipoDesconto: _tipoDesconto, desconto: _descontoValor, limitePercent: _s.config?.descontoMaximo ?? 0, admin: _s.usuario?.admin == true);
    if (erro != null) {
      avisar(erro, tipo: TipoAviso.erro);
      _focoDesconto.requestFocus();
      return;
    }
    final emDinheiro = _forma == 'Dinheiro';
    final rec = _recebidoValor;
    if (emDinheiro && _recebido.text.trim().isNotEmpty && (rec == null || rec < t.total)) {
      avisar('O valor recebido é menor que o total da venda.', tipo: TipoAviso.erro);
      return;
    }
    setState(() => _finalizando = true);
    // Em erro (ex.: cartão negado), a venda continua aberta.
    final r = await tentar(() => _s.api.post('/api/sales', {
          'itens': [for (final i in _carrinho.itens) {'id_produto': i.idProduto, 'quantidade': i.qtd}],
          'forma_pagamento': _forma,
          'desconto': _descontoValor,
          'desconto_tipo': _tipoDesconto,
          if (emDinheiro && rec != null) 'valor_recebido': rec,
        }));
    if (!mounted) return;
    setState(() => _finalizando = false);
    if (r == null) return;
    final v = Venda.deJson(Json.from(r['sale'] as Map));
    avisar('${r['message']} • ${v.codigo} • ${dinheiro(v.total)}${(v.troco ?? 0) > 0 ? ' • Troco ${dinheiro(v.troco)}' : ''}', tipo: TipoAviso.sucesso);
    _limparVenda();
    await _carregarProdutos();
    if (mounted) _focoBusca.requestFocus();
  }

  // ---------------------------------------------------------- painel escuro
  Widget _botaoEscuro(String t, VoidCallback f, {bool ativo = false}) => Semantics(
        button: true,
        label: t,
        excludeSemantics: true,
        child: InkWell(
          onTap: f,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: ativo ? Cores.escuroCampo : Colors.transparent,
              border: Border.all(color: ativo ? const Color(0xFF60A5FA) : Cores.escuroBorda),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 15.2, fontWeight: FontWeight.w700)),
          ),
        ),
      );

  Widget _caixaViva(String rotulo, String valor, {bool baixo = false}) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(rotulo, style: rotuloEscuro),
        const SizedBox(height: 3),
        Semantics(
          label: '$rotulo $valor',
          excludeSemantics: true,
          child: Container(
            height: 34,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(color: baixo ? Cores.perigoClaro : const Color(0xFF111827), border: Border.all(color: const Color(0xFF374151)), borderRadius: BorderRadius.circular(4)),
            child: Text(valor, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: baixo ? Cores.perigo : const Color(0xFF4ADE80), fontWeight: FontWeight.w900, fontSize: 13.6)),
          ),
        ),
      ]);

  Widget _painel() {
    final p = _p;
    final disp = p == null ? null : _carrinho.disponivel(p);
    final t = _totais;
    final emDinheiro = _forma == 'Dinheiro';
    final troco = _carrinho.troco(_recebidoValor, t.total);
    const g = SizedBox(height: 8);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Cores.escuro, borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _botaoEscuro('Adicionar Item', () => _focoBusca.requestFocus(), ativo: true),
        const SizedBox(height: 10),
        _botaoEscuro('Remover Item', _remover),
        const SizedBox(height: 10),
        _botaoEscuro('Aplicar Desconto', () {
          _focoDesconto.requestFocus();
          _desconto.selection = TextSelection(baseOffset: 0, extentOffset: _desconto.text.length);
        }),
        Container(height: 1, margin: const EdgeInsets.only(top: 20, bottom: 12), color: Cores.escuroBorda),
        Campo(_busca, 'Código de barras / nome:', escuro: true, dica: 'Digite e pressione Enter', foco: _focoBusca, erro: _erroBusca, aoMudar: (_) {
          if (_erroBusca) setState(() => _erroBusca = false);
        }, aoEnviar: (_) => _buscarCodigo()),
        g,
        Escolha<int>(
          rotulo: 'Produto:',
          escuro: true,
          valor: _produto,
          opcoes: [
            const DropdownMenuItem(value: null, child: Text('Selecione...')),
            for (final x in _produtos) DropdownMenuItem(value: x.id, enabled: x.estoque > 0, child: Text('${x.nome} - ${dinheiro(x.venda)}/${x.unidade}', overflow: TextOverflow.ellipsis, style: x.estoque > 0 ? null : const TextStyle(color: Color(0xFF9CA3AF)))),
          ],
          aoMudar: (v) => setState(() => _produto = v),
        ),
        g,
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Campo(_qtd, 'Quant.:', escuro: true, numerico: true, foco: _focoQtd, erro: _erroQtd, aoEnviar: (_) => _adicionar())),
          const SizedBox(width: 8),
          Expanded(child: _caixaViva('Disponível:', p == null ? '--' : '${quantidade(disp)} ${p.unidade}', baixo: p != null && disp! <= p.estoqueMinimo)),
        ]),
        g,
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Escolha<String>(rotulo: 'Pagamento:', escuro: true, valor: _forma, opcoes: [for (final f in formasPagamento) DropdownMenuItem(value: f, child: Text(f, overflow: TextOverflow.ellipsis))], aoMudar: (v) => setState(() => _forma = v ?? _forma))),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Desconto:', style: rotuloEscuro),
              const SizedBox(height: 3),
              Row(children: [
                Expanded(child: Campo(_desconto, 'Desconto', semRotulo: true, escuro: true, numerico: true, foco: _focoDesconto, aoMudar: (_) => setState(() {}))),
                const SizedBox(width: 4),
                SizedBox(
                  width: 58,
                  child: Escolha<String>(
                    rotulo: 'Tipo de desconto',
                    semRotulo: true,
                    escuro: true,
                    valor: _tipoDesconto,
                    opcoes: const [DropdownMenuItem(value: 'valor', child: Text('R\$')), DropdownMenuItem(value: 'percentual', child: Text('%'))],
                    aoMudar: (v) => setState(() => _tipoDesconto = v ?? 'valor'),
                  ),
                ),
              ]),
            ]),
          ),
        ]),
        if (emDinheiro) ...[
          g,
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Campo(_recebido, 'Valor recebido R\$:', escuro: true, dica: 'opcional', numerico: true, aoMudar: (_) => setState(() {}))),
            const SizedBox(width: 8),
            Expanded(child: _caixaViva('Troco:', troco == null ? '--' : (troco >= 0 ? dinheiro(troco) : 'insuficiente'), baixo: troco != null && troco < 0)),
          ]),
        ],
        const SizedBox(height: 12),
        Semantics(
          button: true,
          label: 'Inserir no Pedido',
          excludeSemantics: true,
          child: Material(
            color: Cores.primaria,
            borderRadius: BorderRadius.circular(4),
            child: InkWell(
              onTap: _adicionar,
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.add, size: 17, color: Color(0xFFEC4899)),
                  SizedBox(width: 4),
                  Flexible(child: Text('Inserir no Pedido', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14.4))),
                ]),
              ),
            ),
          ),
        ),
        g,
        Semantics(
          button: true,
          label: 'Limpar Venda',
          excludeSemantics: true,
          child: Material(
            color: const Color(0xFF374151),
            borderRadius: BorderRadius.circular(4),
            child: InkWell(
              onTap: () async {
                if (_carrinho.itens.isEmpty || await confirmar(context, 'Descartar todos os itens da venda atual?', ok: 'Limpar venda', perigo: true)) {
                  _limparVenda();
                  avisar('Venda limpa.');
                }
              },
              child: const Padding(padding: EdgeInsets.all(6), child: Text('Limpar Venda', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFE5E7EB), fontSize: 12))),
            ),
          ),
        ),
      ]),
    );
  }

  // ---------------------------------------------------------- pedido
  Widget _pedido(bool estreita) {
    final t = _totais;
    const preto = TextStyle(fontSize: 14.1, color: Color(0xFF111827));
    final tabela = Tabela<ItemCarrinho>(
      itens: _carrinho.itens,
      estilo: EstiloTabela.venda,
      vazio: 'Nenhum item na venda. Selecione um produto e clique em "Inserir no Pedido".',
      larguraMinima: 560,
      selecionado: (i) => _carrinho.itens.indexOf(i) == _selecionado,
      aoTocar: (i) => setState(() => _selecionado = _carrinho.itens.indexOf(i)),
      colunas: [
        Coluna('Produto', (i) => Text(i.nome), flex: 4),
        Coluna('Valor', (i) => Text(num2(i.preco))),
        Coluna('Quant.', (i) => Text('${quantidade(i.qtd)} ${i.unidade}')),
        Coluna('Total', (i) => Text(num2(i.subtotal))),
        Coluna('Remover', (i) => BotaoIcone(Icons.delete_outline, 'Remover ${i.nome}', () => setState(() {
              _carrinho.itens.remove(i);
              _selecionado = null;
            }), tipo: TipoAcao.cancelar)),
      ],
    );
    final rodape = Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Cores.bordaCartao, width: 2))),
      child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, runSpacing: 10, children: [
        Wrap(spacing: 18, children: [
          Text.rich(TextSpan(style: preto, children: [const TextSpan(text: 'Subtotal: '), TextSpan(text: dinheiro(t.subtotal), style: const TextStyle(fontWeight: FontWeight.w700))])),
          Text.rich(TextSpan(style: preto, children: [const TextSpan(text: 'Desconto: '), TextSpan(text: '- ${dinheiro(t.desconto)}', style: const TextStyle(fontWeight: FontWeight.w700))])),
        ]),
        Semantics(
          label: 'Total R\$ ${num2(t.total)}',
          excludeSemantics: true,
          child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            const Text('R\$:', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.black)),
            const SizedBox(width: 6),
            Text(num2(t.total), style: const TextStyle(fontSize: 28.8, fontWeight: FontWeight.w900, color: Colors.black)),
          ]),
        ),
        Semantics(
          button: true,
          label: 'Finalizar Venda & Baixar Estoque',
          excludeSemantics: true,
          child: Material(
            color: Cores.sucesso,
            borderRadius: BorderRadius.circular(4),
            child: InkWell(
              onTap: _finalizando ? null : _finalizar,
              child: const Padding(padding: EdgeInsets.symmetric(horizontal: 24, vertical: 10), child: Text('Finalizar Venda & Baixar Estoque', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900))),
            ),
          ),
        ),
      ]),
    );
    final cabecalho = Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text('Venda', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Cores.texto)),
    );
    return Cartao(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [cabecalho, tabela, rodape]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessaoProvider);
    final estreita = MediaQuery.sizeOf(context).width <= 900;
    return Pagina(
      cabecalho: CabecalhoAba('Venda', acoes: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: Cores.infoClaro, borderRadius: BorderRadius.circular(99)),
          child: Text('Atendente: ${s.usuario?.nome ?? '-'}', style: const TextStyle(color: Cores.info, fontSize: 11.5, fontWeight: FontWeight.w900)),
        ),
      ]),
      filhos: [
        if (estreita)
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_painel(), const SizedBox(height: 16), _pedido(true)])
        else
          AlturaIgual(larguraEsquerda: 280, esquerda: _painel(), direita: _pedido(false)),
      ],
    );
  }
}
