// Saída e Entrada de produtos, individuais ou em lote, iguais ao v1.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/regras.dart';
import '../core/sessao.dart';
import '../models/modelos.dart';
import '../widgets/comuns.dart';
import 'dialogos_estoque.dart';

class MovimentosTela extends ConsumerStatefulWidget {
  const MovimentosTela({super.key, required this.tipo});
  final String tipo;
  @override
  ConsumerState<MovimentosTela> createState() => _MovimentosTelaState();
}

class _MovimentosTelaState extends ConsumerState<MovimentosTela> {
  List<Movimentacao> _movs = [];
  bool _falhou = false;

  late final Sessao _s = ref.read(sessaoProvider);
  bool get _saida => widget.tipo == 'Saída';

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final r = await _s.api.get('/api/movements', query: {'tipo': widget.tipo});
      if (!mounted) return;
      setState(() {
        _movs = listaJson(r['movements']).map(Movimentacao.deJson).toList();
        _falhou = false;
      });
    } catch (_) {
      if (mounted) setState(() => _falhou = true);
    }
  }

  Future<void> _registrar() async {
    final produtos = await tentar(() => carregarProdutosAtivos(_s));
    if (produtos == null || !mounted) return;
    if (produtos.isEmpty) {
      avisar('Não há produtos ativos cadastrados.', tipo: TipoAviso.erro);
      return;
    }
    // Modal fixo do index.html do v1: não fecha com Esc nem com clique fora.
    final ok = await abrirModal<bool>(context, (_) => _Registro(_s, widget.tipo, produtos), estatico: true);
    if (ok == true) await _carregar();
  }

  Future<void> _perda() async {
    if (await abrirPerda(context, _s)) await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessaoProvider);
    final registrar = s.pode('movimentos:registrar');
    return Pagina(
      cabecalho: CabecalhoAba(_saida ? 'Saída de produtos' : 'Entrada de produtos', acoes: [
        if (_saida && registrar) Botao('🗑️ Registrar Perda / Sobra', _perda, tipo: TipoBotao.secundario),
        if (registrar) Botao(_saida ? '+ Registrar Nova Saída' : '+ Registrar Nova Entrada', _registrar, tipo: _saida ? TipoBotao.perigo : TipoBotao.primario),
      ]),
      filhos: [
        Cartao(
          child: Tabela<Movimentacao>(
            itens: _movs,
            vazio: _falhou ? 'Falha ao carregar as movimentações.' : 'Nenhuma movimentação encontrada.',
            larguraMinima: 1000,
            colunas: [
              Coluna('Data', (m) => Text(dataBR(m.data)), flex: 3),
              Coluna('Produto', (m) => Text(m.produto), flex: 4),
              Coluna('Cód', (m) => Text(m.codigo), flex: 2),
              Coluna('Quant', (m) => Text('${quantidade(m.quantidade)} ${m.unidade}')),
              Coluna('Unidade R\$', (m) => Text(num2(m.valorUnitario))),
              Coluna('Total R\$', (m) => Text(num2(m.valorTotal))),
              Coluna('Responsável', (m) => Text(m.usuario), flex: 3),
              // Selo de perda na mesma linha do texto, como no v1.
              Coluna(_saida ? 'Motivo / Observação' : 'Origem / Fornecedor', (m) => Text.rich(TextSpan(children: [if (m.origem == 'perda') ...[WidgetSpan(alignment: PlaceholderAlignment.middle, child: Selo.alerta('Perda: ${m.motivoPerda}')), const TextSpan(text: ' ')], TextSpan(text: m.observacao)])), flex: 5),
            ],
          ),
        ),
      ],
    );
  }
}

class _Registro extends StatefulWidget {
  const _Registro(this.s, this.tipo, this.produtos);
  final Sessao s;
  final String tipo;
  final List<Produto> produtos;
  @override
  State<_Registro> createState() => _RegistroState();
}

class _RegistroState extends State<_Registro> {
  final _obs = TextEditingController();
  late final List<LinhaMov> _linhas = [LinhaMov(widget.produtos.first.id, '1')];
  bool _ocupado = false, _erroObs = false;

  @override
  void dispose() {
    _obs.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    setState(() => _erroObs = false);
    final itens = lerLinhas(_linhas, widget.produtos);
    if (itens == null) {
      setState(() {});
      return;
    }
    final obs = _obs.text.trim();
    if (obs.length < 10) {
      setState(() => _erroObs = true);
      avisar('O motivo deve ter entre 10 e 5000 caracteres.', tipo: TipoAviso.erro);
      return;
    }
    setState(() => _ocupado = true);
    final r = await tentar(() => widget.s.api.post('/api/movements', {'tipo_movimentacao': widget.tipo, 'itens': itens, 'observacao': obs}));
    if (!mounted) return;
    setState(() => _ocupado = false);
    if (r != null) {
      avisar(r['message'].toString(), tipo: TipoAviso.sucesso);
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final saida = widget.tipo == 'Saída';
    return Modal(
      titulo: saida ? 'Registrar Saída de Estoque' : 'Registrar Entrada de Estoque',
      largo: true,
      acoes: [
        Botao('Cancelar', () => Navigator.pop(context), tipo: TipoBotao.secundario),
        Botao('Registrar Movimentação', _ocupado ? null : _enviar, tipo: saida ? TipoBotao.perigo : TipoBotao.primario),
      ],
      filhos: [
        EditorLinhas(linhas: _linhas, produtos: widget.produtos, aoMudar: () => setState(() {}), aoDigitar: () => setState(() {}), aoEnviar: _ocupado ? null : _enviar),
        espacoCampo,
        Campo(_obs, 'Motivo / Justificativa * (Mínimo 10, Máximo 5000 caracteres)', dica: 'Descreva o motivo da saída ou entrada...', linhas: 3, max: 5000, minContador: 10, erro: _erroObs),
      ],
    );
  }
}
