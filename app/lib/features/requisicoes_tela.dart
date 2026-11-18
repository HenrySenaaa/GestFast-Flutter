// Requisições de compra: vitrine da requisição selecionada e tabela, iguais ao v1.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/regras.dart';
import '../core/sessao.dart';
import '../core/tema.dart';
import '../models/modelos.dart';
import '../widgets/comuns.dart';
import 'dialogos_estoque.dart';

class RequisicoesTela extends ConsumerStatefulWidget {
  const RequisicoesTela({super.key, this.selecionarId});
  final int? selecionarId;
  @override
  ConsumerState<RequisicoesTela> createState() => _RequisicoesTelaState();
}

class _RequisicoesTelaState extends ConsumerState<RequisicoesTela> {
  List<Requisicao> _reqs = [];
  List<Produto> _produtos = [];
  bool _falhou = false;
  String _filtro = 'TODOS';
  late int? _selecionada = widget.selecionarId;

  Sessao get _s => ref.read(sessaoProvider);

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final resultados = await Future.wait([_s.api.get('/api/requisitions'), _s.api.get('/api/products')]);
      if (!mounted) return;
      final lista = listaJson(resultados[0]['requisicoes']).map(Requisicao.deJson).toList();
      setState(() {
        _reqs = lista;
        _produtos = listaJson(resultados[1]['products']).map(Produto.deJson).toList();
        _falhou = false;
        if (!lista.any((x) => x.id == _selecionada)) {
          _selecionada = (lista.where((x) => x.aberta).firstOrNull ?? lista.firstOrNull)?.id;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _falhou = true);
    }
  }

  List<Requisicao> get _filtradas => _reqs.where((r) => _filtro == 'TODOS' || (_filtro == 'Em Aberto' ? r.aberta : r.situacao == _filtro)).toList();

  Future<void> _nova() async {
    final r = await abrirNovaRequisicao(context, _s);
    if (r != null) {
      _selecionada = r.id;
      await _carregar();
    }
  }

  /// Devolve true no sucesso. Os modais Receber e Cancelar só fecham nesse caso, como no v1.
  Future<bool> _mudar(Requisicao r, Map<String, dynamic> corpo) async {
    final res = await tentar(() => _s.api.patch('/api/requisitions/${r.id}/status', corpo));
    if (res == null) return false;
    avisar(res['message'].toString(), tipo: TipoAviso.sucesso);
    await _carregar();
    return true;
  }

  Future<void> _avancar(Requisicao r) async {
    final alvo = r.situacao == 'Em Aberto' ? 'Cotado' : 'AF Gerada';
    if (await confirmar(context, 'Atualizar a requisição ${r.codigo} para "$alvo"?', ok: 'Atualizar')) {
      await _mudar(r, {'situacao': alvo});
    }
  }

  Future<void> _receber(Requisicao r) => showDialog<void>(context: context, builder: (_) => _Receber(r, (v) => _mudar(r, {'situacao': 'Finalizado', 'quantidade_recebida': v})));

  Future<void> _cancelar(Requisicao r) => showDialog<void>(context: context, builder: (_) => _Cancelar(r, (j) => _mudar(r, {'situacao': 'Cancelado', 'justificativa': j})));

  Future<void> _detalhes(Requisicao r) => showDialog<void>(context: context, builder: (c) => r.situacao == 'Cancelado' ? _DetalheCancelamento(r) : _Historico(r));

  Widget _selo(Requisicao r) {
    if (r.situacao == 'Cancelado') {
      return Tooltip(
        message: 'Clique para ver o motivo do cancelamento',
        child: Semantics(
          button: true,
          label: 'Cancelado',
          excludeSemantics: true,
          child: InkWell(
            onTap: () => _detalhes(r),
            borderRadius: BorderRadius.circular(99),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Cores.perigoClaro, border: Border.all(color: const Color(0xFFF87171)), borderRadius: BorderRadius.circular(99)),
              child: const Text('✕ Cancelado ℹ️', style: TextStyle(color: Cores.perigo, fontSize: 12.5, fontWeight: FontWeight.w900)),
            ),
          ),
        ),
      );
    }
    return Tooltip(
      message: 'Clique para ver o histórico',
      child: InkWell(onTap: () => _detalhes(r), child: r.situacao == 'Finalizado' ? Selo(r.situacao) : Selo.alerta(r.situacao)),
    );
  }

  Widget _acoes(Requisicao r, Sessao s) {
    if (!r.aberta) return const Text('Concluído', style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)));
    return Wrap(children: [
      if (s.pode('requisicoes:receber')) BotaoIcone('✔', 'Confirmar e Receber Mercadoria (Entrada no Estoque)', () => _receber(r), tipo: TipoAcao.aceitar),
      if (s.pode('requisicoes:avancar') && r.situacao != 'AF Gerada') BotaoIcone('➜', r.situacao == 'Em Aberto' ? 'Marcar como cotado' : 'Gerar AF', () => _avancar(r), tipo: TipoAcao.avancar),
      if (s.pode('requisicoes:cancelar')) BotaoIcone('✕', 'Cancelar Requisição', () => _cancelar(r), tipo: TipoAcao.cancelar),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessaoProvider);
    final sel = _reqs.where((r) => r.id == _selecionada).firstOrNull;
    return Pagina(
      cabecalho: CabecalhoAba('Requisições', acoes: [if (s.pode('requisicoes:criar')) Botao('+ Nova Requisição de Compra', _nova)]),
      filhos: [
        _Vitrine(sel, sel == null ? null : _produtos.where((p) => p.id == sel.idProduto).firstOrNull, s),
        Cartao(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            BarraFiltros(filhos: [
              Text('Filtrar por Situação:', style: TextStyle(fontSize: 14.4, color: Cores.texto)),
              for (final f in const ['TODOS', 'Em Aberto', 'Finalizado', 'Cancelado'])
                // v1: .filter-req-btn.active marca o filtro atual (sem estilo próprio no style.css).
                Botao(f == 'TODOS' ? 'Todos' : f, () => setState(() => _filtro = f), tipo: TipoBotao.secundario, pequeno: true, selecionado: _filtro == f),
            ]),
            Tabela<Requisicao>(
              itens: _filtradas,
              vazio: _falhou ? 'Não foi possível carregar as requisições.' : 'Nenhuma requisição encontrada.',
              larguraMinima: 1040,
              selecionado: (r) => r.id == _selecionada,
              aoTocar: (r) => setState(() => _selecionada = r.id),
              colunas: [
                Coluna('Nº Pedido', (r) => Text(r.codigo, style: const TextStyle(fontWeight: FontWeight.w700)), flex: 5),
                Coluna('Fornecedor', (r) => Text(r.fornecedor), flex: 6),
                Coluna('Produto Solicitado', (r) => Text(r.produto), flex: 6),
                Coluna('Qtd.', (r) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('x${quantidade(r.pedida)}'), if (r.atendida > 0) Pequeno('recebido ${quantidade(r.atendida)}')]), flex: 4),
                Coluna('Unid', (r) => Text(r.unidade), flex: 4),
                Coluna('Total R\$', (r) => Text('R\$ ${r.valorTotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w700)), flex: 4),
                Coluna('Data', (r) => Text(r.dataPedido, softWrap: false, style: const TextStyle(fontSize: 12.8)), flex: 4),
                Coluna('Previsão', (r) => Text(r.previsao, softWrap: false, style: const TextStyle(fontSize: 12.8)), flex: 4),
                Coluna('Situação', (r) => _selo(r), flex: 5),
                Coluna('Ações', (r) => _acoes(r, s), flex: 5),
              ],
            ),
          ]),
        ),
      ],
    );
  }
}

/// .requisicao-figma-showcase
class _Vitrine extends StatelessWidget {
  const _Vitrine(this.r, this.p, this.s);
  final Requisicao? r;
  final Produto? p;
  final Sessao s;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final vazio = r == null;
    final estreita = telaEstreita(context);
    final x = r;
    Widget campo(String rotulo, String valor, {bool forte = true}) => Row(mainAxisSize: MainAxisSize.min, children: [
          Text(rotulo, style: const TextStyle(fontSize: 14.1, color: Color(0xFF4B5563))),
          const SizedBox(width: 6),
          Flexible(child: Text(valor, style: const TextStyle(fontSize: 14.1, fontWeight: FontWeight.w700, color: Color(0xFF111827)))),
        ]);
    Widget situacao() => Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('Situação:', style: TextStyle(fontSize: 14.1, color: Color(0xFF4B5563))),
          const SizedBox(width: 6),
          if (x == null) const Selo('-') else switch (x.situacao) { 'Em Aberto' => Selo.alerta(x.situacao), 'Finalizado' => Selo.sucesso(x.situacao), 'Cancelado' => Selo.perigo(x.situacao), _ => Selo(x.situacao) },
        ]);
    final grade = LayoutBuilder(builder: (context, lim) {
      final largura = estreita ? lim.maxWidth : (lim.maxWidth - 28) / 3;
      Widget c(Widget w) => SizedBox(width: largura, child: Align(alignment: Alignment.centerLeft, child: w));
      return Wrap(spacing: 14, runSpacing: 8, children: [
        c(campo('Pedido:', vazio ? '-' : x!.produto)),
        c(campo('Cód:', vazio ? '-' : x!.codigo.replaceFirst('REQ-', ''))),
        c(campo('QTDE. Ped:', vazio ? '-' : 'X${quantidade(x!.pedida)}')),
        c(campo('QTDE Atendida:', vazio ? '-' : 'X${quantidade(x!.atendida)}')),
        c(campo('UND:', vazio ? '-' : x!.unidade)),
        c(situacao()),
      ]);
    });
    final thumb = Container(
      width: 130,
      height: 100,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFD4D4D8)), borderRadius: BorderRadius.circular(4)),
      child: ImagemProduto(url: p != null && p!.imagem.isNotEmpty ? s.api.urlDoArquivo(p!.imagem) : null, idCategoria: p?.idCategoria, tamanhoEmoji: 52),
    );
    final dados = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(color: const Color(0xFFDEDEDE), borderRadius: BorderRadius.circular(99)),
        child: Text(vazio ? 'Nenhuma requisição selecionada' : x!.fornecedor, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16.8, color: Color(0xFF111827))),
      ),
      grade,
    ]);
    final endereco = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text.rich(TextSpan(style: const TextStyle(fontSize: 14.7, color: Color(0xFF111827)), children: [const TextSpan(text: 'Endereço de entrega: '), TextSpan(text: vazio ? '-' : x!.endereco, style: const TextStyle(fontWeight: FontWeight.w700))])),
      const SizedBox(height: 2),
      Text.rich(TextSpan(style: const TextStyle(fontSize: 14.7, color: Color(0xFF111827)), children: [const TextSpan(text: 'Data prevista: '), TextSpan(text: vazio ? '-' : dataBR(x!.previsao), style: const TextStyle(fontWeight: FontWeight.w700))])),
    ]);
    final valores = Wrap(spacing: 16, children: [
      Text.rich(TextSpan(style: const TextStyle(fontSize: 16, color: Color(0xFF111827)), children: [const TextSpan(text: 'Valor Unit: '), TextSpan(text: vazio ? '-' : dinheiro(x!.valorUnitario), style: const TextStyle(fontWeight: FontWeight.w700))])),
      Text.rich(TextSpan(style: const TextStyle(fontSize: 16, color: Color(0xFF111827)), children: [const TextSpan(text: 'Total: '), TextSpan(text: vazio ? '-' : dinheiro(x!.valorTotal), style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.black))])),
    ]);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Cores.altoContraste ? Colors.white : const Color(0xFFF4F4F4), border: Border.all(color: Cores.bordaCartao), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (estreita)
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [thumb, const SizedBox(height: 10), dados])
        else
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [thumb, const SizedBox(width: 16), Expanded(child: dados)]),
        Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: const Color(0xFFE5E5E5), borderRadius: BorderRadius.circular(4)),
          child: Text(vazio ? 'Selecione uma requisição na tabela para ver os detalhes.' : (x!.observacao.isEmpty ? 'Sem observações.' : x.observacao), style: const TextStyle(fontSize: 14.1, height: 1.4, color: Color(0xFF374151))),
        ),
        Container(
          padding: const EdgeInsets.only(top: 8),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: Cores.bordaCartao))),
          child: estreita
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [endereco, const SizedBox(height: 10), valores])
              : Row(children: [Expanded(child: endereco), const SizedBox(width: 12), valores]),
        ),
      ]),
    );
  }
}

class _Historico extends StatelessWidget {
  const _Historico(this.r);
  final Requisicao r;
  @override
  Widget build(BuildContext context) => Modal(
        titulo: 'Histórico - ${r.codigo}',
        acaoUnica: Botao('Fechar', () => Navigator.pop(context), tipo: TipoBotao.secundario, bloco: true),
        filhos: [
          Mensagem('${r.produto} • ${r.fornecedor}'),
          for (var i = 0; i < r.historico.length; i++)
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 18, child: Text('${i + 1}.', style: const TextStyle(fontSize: 14))),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${r.historico[i]['situacao']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    Text('${dataBR('${r.historico[i]['data']}')} • ${r.historico[i]['usuario']}', style: const TextStyle(fontSize: 12.8)),
                  ]),
                ),
              ]),
            ),
        ],
      );
}

class _DetalheCancelamento extends StatelessWidget {
  const _DetalheCancelamento(this.r);
  final Requisicao r;
  @override
  Widget build(BuildContext context) {
    Widget linha(String rotulo, String valor, {bool forte = false}) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(rotulo, style: const TextStyle(fontSize: 14.1, fontWeight: FontWeight.w700, color: Color(0xFF4B5563))),
            const SizedBox(width: 8),
            Expanded(child: Text(valor, style: TextStyle(fontSize: 14.1, fontWeight: forte ? FontWeight.w700 : FontWeight.w400))),
          ]),
        );
    final texto = r.justificativa.isEmpty ? 'Sem justificativa registrada.' : r.justificativa;
    return Modal(
      titulo: 'Motivo do Cancelamento da Requisição',
      acaoUnica: Botao('Fechar', () => Navigator.pop(context), tipo: TipoBotao.secundario, bloco: true),
      filhos: [
        linha('Nº do Pedido:', r.codigo, forte: true),
        linha('Fornecedor:', r.fornecedor),
        linha('Produto Solicitado:', r.produto),
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(top: 6, bottom: 8),
          decoration: BoxDecoration(color: const Color(0xFFFEF2F2), border: Border.all(color: const Color(0xFFFECACA)), borderRadius: BorderRadius.circular(4)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Justificativa Registrada pelo Operador:', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF991B1B), fontSize: 13.1)),
            const SizedBox(height: 6),
            Text(texto, style: const TextStyle(fontStyle: FontStyle.italic, color: Color(0xFF1F2937), height: 1.45, fontSize: 14.1)),
          ]),
        ),
        Text('${r.justificativa.length} caracteres', textAlign: TextAlign.right, style: const TextStyle(fontSize: 11.5, color: Color(0xFF6B7280))),
      ],
    );
  }
}

class _Receber extends StatefulWidget {
  const _Receber(this.r, this.enviar);
  final Requisicao r;
  final Future<bool> Function(double) enviar;
  @override
  State<_Receber> createState() => _ReceberState();
}

class _ReceberState extends State<_Receber> {
  late final _qtd = TextEditingController(text: quantidade(widget.r.pendente).replaceAll('.', ''));
  bool _erro = false, _ocupado = false;
  @override
  void dispose() {
    _qtd.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    if (_ocupado) return;
    final r = widget.r;
    final v = lerNumero(_qtd.text);
    final erro = erroQuantidade(r.unidade, v, nome: r.produto);
    if (erro != null || v! > r.pendente) {
      setState(() => _erro = true);
      avisar(erro ?? 'Informe uma quantidade entre 0 e ${quantidade(r.pendente)}.', tipo: TipoAviso.erro);
      return;
    }
    // v1: o modal só fecha se o servidor aceitar; no erro a quantidade digitada fica.
    _ocupado = true;
    final ok = await widget.enviar(v);
    _ocupado = false;
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.r;
    return Modal(
      titulo: 'Receber mercadoria - ${r.codigo}',
      acoes: [
        Botao('Cancelar', () => Navigator.pop(context), tipo: TipoBotao.secundario),
        Botao('Confirmar recebimento', _confirmar),
      ],
      filhos: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text.rich(TextSpan(style: const TextStyle(fontSize: 14.7, height: 1.45, color: Color(0xFF111827)), children: [
            TextSpan(text: r.produto, style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: ' • ${r.fornecedor}\nPedido: ${quantidade(r.pedida)} ${r.unidade} • Já recebido: ${quantidade(r.atendida)} • Pendente: '),
            TextSpan(text: quantidade(r.pendente), style: const TextStyle(fontWeight: FontWeight.w700)),
          ])),
        ),
        Campo(_qtd, 'Quantidade recebida agora (${r.unidade})', numerico: true, autofoco: true, erro: _erro, aoEnviar: (_) => _confirmar()),
        espacoCampo,
        Text('${r.idProduto != null ? 'O estoque será atualizado automaticamente (entrada).' : 'Produto fora do catálogo: nenhum estoque será alterado.'} Se receber menos que o pendente, o pedido continua aberto.', style: const TextStyle(fontSize: 14, color: Color(0xFF52525B))),
      ],
    );
  }
}

class _Cancelar extends StatefulWidget {
  const _Cancelar(this.r, this.enviar);
  final Requisicao r;
  final Future<bool> Function(String) enviar;
  @override
  State<_Cancelar> createState() => _CancelarState();
}

class _CancelarState extends State<_Cancelar> {
  final _j = TextEditingController();
  bool _erro = false, _ocupado = false;

  Future<void> _enviar() async {
    final t = _j.text.trim();
    if (t.length < 10) {
      setState(() => _erro = true);
      avisar('A justificativa deve ter entre 10 e 5000 caracteres.', tipo: TipoAviso.erro);
      return;
    }
    // v1: botão desabilitado durante o envio e o modal só fecha no sucesso; no erro a justificativa fica.
    setState(() => _ocupado = true);
    final ok = await widget.enviar(t);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() => _ocupado = false);
    }
  }
  @override
  void dispose() {
    _j.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.r;
    return Modal(
      titulo: 'Cancelar Requisição de Compra',
      acoes: [
        Botao('Voltar', () => Navigator.pop(context), tipo: TipoBotao.secundario),
        Botao('Enviar', _ocupado ? null : _enviar, tipo: TipoBotao.perigo),
      ],
      filhos: [
        Container(
          padding: const EdgeInsets.all(10),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: const Color(0xFFFEF2F2), border: Border.all(color: const Color(0xFFFECACA)), borderRadius: BorderRadius.circular(4)),
          child: Text.rich(TextSpan(style: const TextStyle(fontSize: 13.6, color: Color(0xFF991B1B)), children: [
            TextSpan(text: r.codigo, style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: ' • ${r.produto} • ${r.fornecedor}\n'),
            TextSpan(text: '${quantidade(r.pedida)} ${r.unidade} • ${dinheiro(r.valorTotal)}', style: const TextStyle(fontSize: 12)),
          ])),
        ),
        Campo(_j, 'Motivo / Justificativa do Cancelamento * (10 a 5000 caracteres)', dica: 'Descreva de forma clara o motivo do cancelamento deste pedido...', linhas: 4, max: 5000, minContador: 10, erro: _erro, autofoco: true),
      ],
    );
  }
}
