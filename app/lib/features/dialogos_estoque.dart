// Modais abertos de mais de uma tela: nova requisição e perda/sobra, com os textos do v1.
import 'package:flutter/material.dart';

import '../core/regras.dart';
import '../core/sessao.dart';
import '../models/modelos.dart';
import '../widgets/comuns.dart';

Future<List<Produto>> carregarProdutosAtivos(Sessao s) async {
  final r = await s.api.get('/api/products');
  return listaJson(r['products']).map(Produto.deJson).toList();
}

/// Devolve a requisição criada, ou null se cancelou.
Future<Requisicao?> abrirNovaRequisicao(BuildContext context, Sessao s, {int? idProduto}) async {
  final dados = await tentar(() async {
    await s.sincronizar();
    final f = await s.api.get('/api/suppliers');
    return (await carregarProdutosAtivos(s), ((f['suppliers'] as List?) ?? const []).map((e) => e.toString()).toList());
  });
  if (dados == null || !context.mounted) return null;
  return showDialog<Requisicao>(context: context, builder: (_) => _NovaRequisicao(s, dados.$1, dados.$2, idProduto));
}

class _NovaRequisicao extends StatefulWidget {
  const _NovaRequisicao(this.s, this.produtos, this.fornecedores, this.idProduto);
  final Sessao s;
  final List<Produto> produtos;
  final List<String> fornecedores;
  final int? idProduto;
  @override
  State<_NovaRequisicao> createState() => _NovaRequisicaoState();
}

class _NovaRequisicaoState extends State<_NovaRequisicao> {
  final _qtd = TextEditingController(text: '20');
  final _unidade = TextEditingController();
  final _valor = TextEditingController();
  final _obs = TextEditingController();
  int? _produto;
  String? _fornecedor;
  late String _entrega = somarDias(widget.s.hojeOuAparelho, 4);
  bool _qtdEditada = false, _ocupado = false, _erroQtd = false, _erroObs = false;

  Produto? get _p => widget.produtos.where((x) => x.id == _produto).firstOrNull;

  @override
  void initState() {
    super.initState();
    _fornecedor = widget.fornecedores.firstOrNull;
    _produto = widget.idProduto != null && widget.produtos.any((x) => x.id == widget.idProduto) ? widget.idProduto : widget.produtos.firstOrNull?.id;
    _sincronizar();
  }

  @override
  void dispose() {
    _qtd.dispose();
    _unidade.dispose();
    _valor.dispose();
    _obs.dispose();
    super.dispose();
  }

  // Trocar de produto preenche unidade e custo; vindo de um alerta, sugere repor até o dobro do mínimo.
  void _sincronizar() {
    final p = _p;
    if (p == null) return;
    _unidade.text = p.unidade;
    _valor.text = num2(p.custo).replaceAll('.', '');
    if (!_qtdEditada && p.id == widget.idProduto) {
      final sugestao = (p.estoqueMinimo * 2 - p.estoque).ceil();
      _qtd.text = (sugestao < 1 ? 1 : sugestao).toString();
    }
  }

  Future<void> _enviar() async {
    final p = _p;
    final q = lerNumero(_qtd.text);
    final erro = erroQuantidade(p?.unidade, q, nome: p?.nome ?? 'Este produto');
    setState(() {
      _erroQtd = erro != null;
      _erroObs = false;
    });
    if (p == null || erro != null) {
      avisar(erro ?? 'Selecione um produto.', tipo: TipoAviso.erro);
      return;
    }
    final obs = _obs.text.trim();
    if (obs.isNotEmpty && obs.length < 10) {
      setState(() => _erroObs = true);
      avisar('A observação deve ter no mínimo 10 caracteres (ou deixe em branco).', tipo: TipoAviso.erro);
      return;
    }
    if (_entrega.isNotEmpty && _entrega.compareTo(widget.s.hojeOuAparelho) < 0) {
      avisar('A previsão de entrega não pode estar no passado.', tipo: TipoAviso.erro);
      return;
    }
    setState(() => _ocupado = true);
    final r = await tentar(() => widget.s.api.post('/api/requisitions', {
          'id_produto': p.id,
          'quantidade_pedida': q,
          'fornecedor': _fornecedor,
          'valor_unitario': lerNumero(_valor.text) ?? '',
          'previsao_entrega': _entrega,
          'observacao': obs,
        }));
    if (!mounted) return;
    setState(() => _ocupado = false);
    if (r != null) {
      avisar(r['message'].toString(), tipo: TipoAviso.sucesso);
      Navigator.pop(context, Requisicao.deJson(Json.from(r['requisicao'] as Map)));
    }
  }

  @override
  Widget build(BuildContext context) => Modal(
        titulo: 'Nova Requisição de Fornecedor',
        acaoUnica: Botao('📨 Enviar Requisição', _ocupado ? null : _enviar, bloco: true),
        filhos: [
          Escolha<int>(
            rotulo: 'Produto *',
            valor: _produto,
            opcoes: [for (final p in widget.produtos) DropdownMenuItem(value: p.id, child: Text('${p.nome} (${p.unidade})', overflow: TextOverflow.ellipsis))],
            aoMudar: (v) => setState(() {
              _produto = v;
              _qtdEditada = false;
              _sincronizar();
            }),
          ),
          espacoCampo,
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 2, child: Campo(_qtd, 'Quantidade *', numerico: true, erro: _erroQtd, aoMudar: (_) => _qtdEditada = true)),
            const SizedBox(width: 10),
            Expanded(child: Campo(_unidade, 'Unidade', somenteLeitura: true)),
          ]),
          espacoCampo,
          Escolha<String>(rotulo: 'Fornecedor Cadastrado *', valor: _fornecedor, opcoes: [for (final f in widget.fornecedores) DropdownMenuItem(value: f, child: Text(f, overflow: TextOverflow.ellipsis))], aoMudar: (v) => setState(() => _fornecedor = v)),
          espacoCampo,
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Campo(_valor, 'Preço Unitário (R\$)', numerico: true)),
            const SizedBox(width: 10),
            Expanded(child: CampoData(rotulo: 'Previsão de Entrega', valor: _entrega, emLinha: false, primeira: dataLocal(widget.s.hojeOuAparelho), aoMudar: (v) => setState(() => _entrega = v))),
          ]),
          espacoCampo,
          Campo(_obs, 'Observações do Pedido (opcional; se preenchida: mínimo 10, máximo 5000 caracteres)', dica: 'Ex: Pedido com prioridade alta para o turno da manhã...', linhas: 2, max: 5000, minContador: 10, erro: _erroObs),
        ],
      );
}

/// Linhas de produto + quantidade usadas em entradas, saídas e perdas (.mov-linha).
class LinhaMov {
  LinhaMov(this.idProduto, String quantidade) : qtd = TextEditingController(text: quantidade);
  int? idProduto;
  final TextEditingController qtd;
}

class EditorLinhas extends StatelessWidget {
  const EditorLinhas({super.key, required this.linhas, required this.produtos, required this.aoMudar, this.aoDigitar, this.rotuloAdicionar = '+ Adicionar outro item (lote)'});
  final List<LinhaMov> linhas;
  final List<Produto> produtos;
  final VoidCallback aoMudar;
  final VoidCallback? aoDigitar;
  final String rotuloAdicionar;

  @override
  Widget build(BuildContext context) {
    final estreita = MediaQuery.sizeOf(context).width <= 520;
    final qtdLargura = estreita ? 90.0 : 130.0;
    const titulo = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          const Expanded(child: Text('Produto *', style: titulo)),
          const SizedBox(width: 8),
          SizedBox(width: qtdLargura, child: const Text('Quantidade *', style: titulo)),
          const SizedBox(width: 42),
        ]),
      ),
      for (var i = 0; i < linhas.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Expanded(
              child: Escolha<int>(
                rotulo: 'Produto',
                semRotulo: true,
                valor: linhas[i].idProduto,
                opcoes: [for (final p in produtos) DropdownMenuItem(value: p.id, child: Text('${p.nome} (${quantidade(p.estoque)} ${p.unidade})', overflow: TextOverflow.ellipsis))],
                aoMudar: (v) {
                  linhas[i].idProduto = v;
                  aoMudar();
                },
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(width: qtdLargura, child: Campo(linhas[i].qtd, 'Quantidade', semRotulo: true, numerico: true, aoMudar: (_) => aoDigitar?.call())),
            const SizedBox(width: 8),
            SizedBox(
              width: 34,
              child: linhas.length > 1
                  ? BotaoIcone('✕', 'Remover linha', () {
                      linhas.removeAt(i);
                      aoMudar();
                    }, tipo: TipoAcao.cancelar)
                  : null,
            ),
          ]),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: Botao(rotuloAdicionar, () {
          linhas.add(LinhaMov(produtos.firstOrNull?.id, '1'));
          aoMudar();
        }, tipo: TipoBotao.secundario, pequeno: true),
      ),
    ]);
  }
}

/// Valida as linhas e monta os itens; mostra o aviso e devolve null se houver erro.
List<Map<String, dynamic>>? lerLinhas(List<LinhaMov> linhas, List<Produto> produtos) {
  final itens = <Map<String, dynamic>>[];
  for (final l in linhas) {
    final p = produtos.where((x) => x.id == l.idProduto).firstOrNull;
    final q = lerNumero(l.qtd.text);
    final erro = p == null ? 'Selecione o produto de todas as linhas.' : erroQuantidade(p.unidade, q, nome: p.nome);
    if (erro != null) {
      avisar(erro, tipo: TipoAviso.erro);
      return null;
    }
    itens.add({'id_produto': p!.id, 'quantidade': q});
  }
  return itens;
}

/// Perda ou sobra: baixa no estoque valorizada pelo custo. Devolve true se registrou.
Future<bool> abrirPerda(BuildContext context, Sessao s, {int? idProduto, double? quantidadePreset, String motivo = 'Vencido'}) async {
  final produtos = await tentar(() => carregarProdutosAtivos(s));
  if (produtos == null || !context.mounted) return false;
  final comEstoque = produtos.where((p) => p.estoque > 0).toList();
  if (comEstoque.isEmpty) {
    avisar('Não há produtos com estoque para registrar perda.', tipo: TipoAviso.erro);
    return false;
  }
  final r = await showDialog<bool>(context: context, builder: (_) => _Perda(s, comEstoque, idProduto, quantidadePreset, motivo));
  return r == true;
}

class _Perda extends StatefulWidget {
  const _Perda(this.s, this.produtos, this.idProduto, this.quantidade, this.motivo);
  final Sessao s;
  final List<Produto> produtos;
  final int? idProduto;
  final double? quantidade;
  final String motivo;
  @override
  State<_Perda> createState() => _PerdaState();
}

class _PerdaState extends State<_Perda> {
  late String _motivo = widget.motivo;
  final _obs = TextEditingController();
  late final List<LinhaMov> _linhas = [
    LinhaMov(widget.produtos.any((p) => p.id == widget.idProduto) ? widget.idProduto : widget.produtos.first.id, widget.quantidade == null ? '1' : quantidade(widget.quantidade).replaceAll('.', '')),
  ];
  bool _ocupado = false;

  @override
  void dispose() {
    _obs.dispose();
    super.dispose();
  }

  double get _valor => _linhas.fold(0.0, (a, l) {
        final p = widget.produtos.where((x) => x.id == l.idProduto).firstOrNull;
        return a + (p?.custo ?? 0) * (lerNumero(l.qtd.text) ?? 0);
      });

  Future<void> _enviar() async {
    final itens = lerLinhas(_linhas, widget.produtos);
    if (itens == null) return;
    final obs = _obs.text.trim();
    if ((_motivo == 'Outro' || obs.isNotEmpty) && obs.length < 10) {
      avisar('A observação deve ter pelo menos 10 caracteres.', tipo: TipoAviso.erro);
      return;
    }
    setState(() => _ocupado = true);
    final r = await tentar(() => widget.s.api.post('/api/losses', {'motivo_perda': _motivo, 'itens': itens, 'observacao': obs}));
    if (!mounted) return;
    setState(() => _ocupado = false);
    if (r != null) {
      avisar(r['message'].toString(), tipo: TipoAviso.sucesso);
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) => Modal(
        titulo: 'Registrar Perda / Sobra',
        largo: true,
        acoes: [
          Botao('Cancelar', () => Navigator.pop(context), tipo: TipoBotao.secundario),
          Botao('Registrar perda', _ocupado ? null : _enviar, tipo: TipoBotao.perigo),
        ],
        filhos: [
          Escolha<String>(rotulo: 'Motivo *', valor: _motivo, opcoes: [for (final m in motivosPerda) DropdownMenuItem(value: m, child: Text(m))], aoMudar: (v) => setState(() => _motivo = v ?? _motivo)),
          espacoCampo,
          EditorLinhas(linhas: _linhas, produtos: widget.produtos, rotuloAdicionar: '+ Adicionar outro item', aoMudar: () => setState(() {}), aoDigitar: () => setState(() {})),
          espacoCampo,
          Campo(_obs, 'Observação (obrigatória quando o motivo é "Outro"; mínimo 10 caracteres)', dica: 'Ex: Bandeja caiu no transporte para o balcão.', linhas: 2, max: 5000),
          espacoCampo,
          Text('Valor perdido (preço de custo): ${dinheiro(_valor)}', style: const TextStyle(color: Color(0xFF52525B), fontSize: 14)),
        ],
      );
}
