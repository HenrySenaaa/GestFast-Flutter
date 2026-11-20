// Relatórios: categorias no painel escuro e relatório ao lado, iguais ao v1, com exportação em PDF e Excel.
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/regras.dart';
import '../core/sessao.dart';
import '../core/tema.dart';
import '../models/modelos.dart';
import '../widgets/comuns.dart';

const _rotas = {'vendas': 'sales', 'estoque': 'stock', 'perdas': 'losses'};

class RelatoriosTela extends ConsumerStatefulWidget {
  const RelatoriosTela({super.key});
  @override
  ConsumerState<RelatoriosTela> createState() => _RelatoriosTelaState();
}

class _RelatoriosTelaState extends ConsumerState<RelatoriosTela> {
  String _tipo = 'vendas', _de = '', _ate = '';
  int? _categoria;
  bool _datasDoUsuario = false, _exportando = false, _erroPeriodo = false;
  Json? _relatorio;

  /// v1 (variável "ultimo"): se a última geração falhou, a tabela antiga continua na tela, mas não dá para exportar.
  bool _valido = false;

  late final Sessao _s = ref.read(sessaoProvider);

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  @override
  void deactivate() {
    _s.memoria['rel'] = {'tipo': _tipo, 'de': _de, 'ate': _ate, 'categoria': _categoria, 'datasDoUsuario': _datasDoUsuario};
    super.deactivate();
  }

  // v1: aba, período e categoria continuavam como estavam ao voltar; período vazio volta a ser o dia de hoje.
  Future<void> _iniciar() async {
    final m = _s.memoria['rel'] as Map<String, Object?>?;
    if (m != null) {
      _tipo = m['tipo'] as String;
      _de = m['de'] as String;
      _ate = m['ate'] as String;
      _categoria = m['categoria'] as int?;
      _datasDoUsuario = m['datasDoUsuario'] as bool;
    }
    await _s.sincronizar();
    if (_s.categorias.isEmpty) await tentar(_s.carregarCategorias);
    if (_de.isEmpty) _de = _ate = _s.hojeOuAparelho;
    if (mounted) setState(() {});
    await _gerar();
  }

  Map<String, String?> _query([String? formato]) => {'from': _de, 'to': _ate, 'categoria': _categoria?.toString(), 'format': formato};

  bool _periodoValido() {
    if (_de.isNotEmpty && _ate.isNotEmpty && _de.compareTo(_ate) > 0) {
      setState(() => _erroPeriodo = true);
      avisar('A data inicial não pode ser posterior à data final.', tipo: TipoAviso.erro);
      return false;
    }
    if (_erroPeriodo) setState(() => _erroPeriodo = false);
    return true;
  }

  Future<void> _gerar() async {
    if (!_periodoValido()) return;
    final tipo = _tipo;
    final r = await tentar(() => _s.api.get('/api/reports/${_rotas[tipo]}', query: _query()));
    if (!mounted || tipo != _tipo) return;
    setState(() {
      _valido = r != null;
      if (r != null) _relatorio = Json.from(r['report'] as Map);
    });
  }

  // Mesma regra do v1 ao trocar de aba: sem período escolhido pelo usuário, Estoque e Perdas abrem com todo o período
  // e Vendas volta para hoje.
  void _mudarTipo(String t) {
    setState(() {
      _tipo = t;
      if (t != 'vendas' && !_datasDoUsuario) _de = _ate = '';
      if (t == 'vendas' && _de.isEmpty) _de = _ate = _s.hojeOuAparelho;
      _relatorio = null;
      _valido = false;
    });
    _gerar();
  }

  List<dynamic> get _linhas => switch (_tipo) {
        'vendas' => (_relatorio?['itensVendidos'] as List?) ?? const [],
        'estoque' => (_relatorio?['linhas'] as List?) ?? const [],
        _ => (_relatorio?['porProduto'] as List?) ?? const [],
      };

  Future<void> _exportar(String formato) async {
    if (!_periodoValido()) return;
    if (!_valido || _relatorio == null || _linhas.isEmpty) {
      avisar('Não há dados para exportar. Gere um relatório com resultados primeiro.', tipo: TipoAviso.erro);
      return;
    }
    setState(() => _exportando = true);
    final ok = await tentar(() async {
      final a = await _s.api.baixar('/api/reports/${_rotas[_tipo]}', query: _query(formato), nomePadrao: 'gestfast-$_tipo.$formato');
      final nome = a.nome.replaceAll(RegExp(r'\.(pdf|xlsx)$'), '');
      await FileSaver.instance.saveFile(name: nome, bytes: a.bytes, fileExtension: formato, mimeType: formato == 'pdf' ? MimeType.pdf : MimeType.microsoftExcel);
      return true;
    });
    if (!mounted) return;
    setState(() => _exportando = false);
    if (ok == true) avisar('Relatório exportado em ${formato == 'pdf' ? 'PDF' : 'Excel'} com sucesso!', tipo: TipoAviso.sucesso);
  }

  String get _periodo {
    if (_de.isNotEmpty && _de == _ate) return _de == _s.hojeOuAparelho ? 'do Dia' : 'de ${dataBR(_de)}';
    if (_de.isNotEmpty || _ate.isNotEmpty) return 'de ${_de.isNotEmpty ? dataBR(_de) : 'início'} a ${_ate.isNotEmpty ? dataBR(_ate) : 'hoje'}';
    return 'de Todo o Período';
  }

  Widget _aba(String id, String texto) {
    final ativa = _tipo == id;
    return Semantics(
      button: true,
      selected: ativa,
      label: texto,
      excludeSemantics: true,
      child: InkWell(
        onTap: () => _mudarTipo(id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(color: ativa ? Cores.escuro : Colors.white, border: Border.all(color: ativa ? Cores.escuro : const Color(0xFFD1D5DB)), borderRadius: BorderRadius.circular(4)),
          child: Text(texto, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.6, color: ativa ? Colors.white : const Color(0xFF111827))),
        ),
      ),
    );
  }

  Widget _categorias(Sessao s) {
    // .rel-cat-item (:hover e .active: fundo #374151, branco, peso 800)
    Widget item(int? id, String nome) {
      final ativa = _categoria == id;
      return Semantics(
        button: true,
        selected: ativa,
        label: nome,
        excludeSemantics: true,
        child: Pairar(
          builder: (context, sobre) => InkWell(
            onTap: () {
              setState(() => _categoria = id);
              _gerar();
            },
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(color: ativa || sobre ? const Color(0xFF374151) : Colors.transparent, borderRadius: BorderRadius.circular(4)),
              child: Text(nome, style: TextStyle(color: ativa || sobre ? Colors.white : const Color(0xFFD1D5DB), fontSize: 14.7, fontWeight: ativa || sobre ? FontWeight.w800 : FontWeight.w600)),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      decoration: BoxDecoration(color: Cores.escuro, borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        item(null, 'Geral'),
        for (final c in s.categorias) Padding(padding: const EdgeInsets.only(top: 2), child: item(c.id, c.nome)),
      ]),
    );
  }

  Widget _painel(Sessao s) {
    final r = _relatorio;
    final nomeCategoria = s.categorias.where((c) => c.id == _categoria).firstOrNull?.nome;
    final titulo = {'vendas': 'Vendidos $_periodo', 'estoque': 'Estoque • movimentações $_periodo', 'perdas': 'Perdas e sobras $_periodo'}[_tipo]!;
    final resumo = r == null ? '' : _resumo(r);
    final total = r == null ? 0 : (_tipo == 'estoque' ? r['valorTotalEstoque'] : _tipo == 'perdas' ? r['valorTotal'] : r['totalGeral']);
    return Cartao(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // h2 com margin-bottom 12 e <p class="rel-resumo"> com margin -4px 0 10px (o espaço fica mesmo sem texto).
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('$titulo${nomeCategoria != null ? ' • $nomeCategoria' : ''}', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Cores.texto)),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: resumo.isEmpty
                ? const SizedBox.shrink()
                : Tooltip(
                    message: _tipo == 'vendas' && r != null ? listaJson(r['porPagamento']).map((p) => '${p['forma']} ${dinheiro(p['total'])}').join(' • ') : '',
                    child: Text(resumo, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.8, color: Cores.fraco)),
                  ),
          ),
          if (r != null) switch (_tipo) { 'vendas' => _tabelaVendas(r), 'estoque' => _tabelaEstoque(r), _ => _tabelaPerdas(r) },
        ]),
        Container(
          margin: const EdgeInsets.only(top: 16),
          padding: const EdgeInsets.only(top: 16),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: Cores.bordaCartao, width: 2))),
          child: Semantics(
            label: 'Total R\$ ${num2(total)}',
            excludeSemantics: true,
            child: Row(mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              const Text('R\$:', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.black)),
              const SizedBox(width: 6),
              Text(num2(total), style: const TextStyle(fontSize: 28.8, fontWeight: FontWeight.w900, color: Colors.black)),
            ]),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessaoProvider);
    final estreita = MediaQuery.sizeOf(context).width <= 900;
    return Pagina(
      cabecalho: CabecalhoAba('Relatórios', acoes: [
        Wrap(spacing: 4, children: [_aba('vendas', 'Vendas'), _aba('estoque', 'Estoque'), _aba('perdas', 'Perdas')]),
        CampoData(rotulo: 'De', valor: _de, erro: _erroPeriodo, aoMudar: (v) {
          setState(() {
            _de = v;
            _datasDoUsuario = true;
          });
          _gerar();
        }),
        CampoData(rotulo: 'Até', valor: _ate, aoMudar: (v) {
          setState(() {
            _ate = v;
            _datasDoUsuario = true;
          });
          _gerar();
        }),
        Botao('📄 Exportar PDF', _exportando ? null : () => _exportar('pdf'), tipo: TipoBotao.secundario),
        Botao('📊 Exportar Excel', _exportando ? null : () => _exportar('xlsx'), tipo: TipoBotao.secundario),
      ]),
      filhos: [
        if (estreita)
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_categorias(s), const SizedBox(height: 16), _painel(s)])
        else
          AlturaIgual(larguraEsquerda: 220, esquerda: _categorias(s), direita: _painel(s)),
      ],
    );
  }

  String _resumo(Json r) {
    if (_tipo == 'vendas') {
      final n = numero(r['quantidadeTransacoes']).toInt();
      return n == 0 ? '' : '$n venda(s) • ticket médio ${dinheiro(r['ticketMedio'])} • descontos ${dinheiro(r['totalDescontos'])}';
    }
    if (_tipo == 'estoque') return '${r['totalProdutos']} produto(s) • ${r['totalCriticos']} em nível crítico • valor em estoque (custo) ${dinheiro(r['valorTotalEstoque'])}';
    final n = numero(r['totalRegistros']).toInt();
    return n == 0 ? '' : '$n registro(s) • ${listaJson(r['porMotivo']).map((m) => '${m['motivo']} ${dinheiro(m['valor_total'])}').join(' • ')}';
  }

  Widget _tabelaVendas(Json r) => Tabela<Json>(
        itens: listaJson(r['itensVendidos']),
        estilo: EstiloTabela.relatorio,
        larguraMinima: 560,
        vazioSimples: true,
        vazio: 'Nenhum dado encontrado para o período ou categoria informada.',
        colunas: [
          Coluna('Produto', (i) => Text('${i['nome_produto']}', style: const TextStyle(fontWeight: FontWeight.w700)), flex: 6),
          Coluna('Valor', (i) => Text('R\$ ${num2(i['valor_unitario'])}')),
          Coluna('Quant.', (i) => Text('x${quantidade(i['quantidade'])}${aceitaFracao('${i['unidade']}') ? ' ${i['unidade']}' : ''}')),
          Coluna('Total', (i) => Text(num2(i['total']), style: const TextStyle(fontWeight: FontWeight.w700))),
        ],
      );

  Widget _tabelaEstoque(Json r) => Tabela<Json>(
        itens: listaJson(r['linhas']),
        estilo: EstiloTabela.relatorio,
        larguraMinima: 820,
        critico: (l) => l['situacao'] == 'Crítico',
        vazio: 'Nenhum dado encontrado para o período ou categoria informada.',
        colunas: [
          Coluna('Produto', (l) => Text('${l['nome_produto']}'), flex: 4),
          Coluna('Categoria', (l) => Text('${l['categoria']}'), flex: 3),
          Coluna('Entradas', (l) => Text(numero(l['entradas']) != 0 ? '+${quantidade(l['entradas'])}' : '0', style: const TextStyle(color: Color(0xFF15803D), fontWeight: FontWeight.w700))),
          Coluna('Saídas', (l) => Text(numero(l['saidas']) != 0 ? '-${quantidade(l['saidas'])}' : '0', style: const TextStyle(color: Cores.perigo, fontWeight: FontWeight.w700))),
          Coluna('Saldo atual', (l) => Text('${quantidade(l['saldo_atual'])} ${l['unidade']}', style: const TextStyle(fontWeight: FontWeight.w700))),
          Coluna('Mín.', (l) => Text(quantidade(l['estoque_minimo'])), flex: 1),
          Coluna('Situação', (l) => l['situacao'] == 'Crítico' ? const Selo.perigo('Crítico') : Selo.sucesso('${l['situacao']}')),
        ],
      );

  Widget _tabelaPerdas(Json r) => Tabela<Json>(
        itens: listaJson(r['porProduto']),
        estilo: EstiloTabela.relatorio,
        larguraMinima: 640,
        vazio: 'Nenhuma perda registrada no período ou categoria informada.',
        colunas: [
          Coluna('Produto', (p) => Text('${p['nome_produto']}', style: const TextStyle(fontWeight: FontWeight.w700)), flex: 4),
          Coluna('Categoria', (p) => Text('${p['categoria']}'), flex: 3),
          Coluna('Registros', (p) => Text('${p['registros']}')),
          Coluna('Quant. perdida', (p) => Text('${quantidade(p['quantidade'])} ${p['unidade']}', style: const TextStyle(color: Cores.perigo, fontWeight: FontWeight.w700))),
          Coluna('Valor (custo)', (p) => Text(num2(p['valor_total']), style: const TextStyle(fontWeight: FontWeight.w700))),
        ],
      );
}
