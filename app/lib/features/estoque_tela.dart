// Verificar Estoque: conferência física de inventário, igual ao v1.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/regras.dart';
import '../core/sessao.dart';
import '../core/tema.dart';
import '../models/modelos.dart';
import '../widgets/comuns.dart';

class EstoqueTela extends ConsumerStatefulWidget {
  const EstoqueTela({super.key, this.filtroInicial = ''});
  final String filtroInicial;
  @override
  ConsumerState<EstoqueTela> createState() => _EstoqueTelaState();
}

class _EstoqueTelaState extends ConsumerState<EstoqueTela> {
  List<Produto> _produtos = [];
  bool _falhou = false, _criticos = false, _validade = false;
  int? _categoria;
  late final _termo = TextEditingController(text: widget.filtroInicial);
  // A contagem fica fora da tabela: mudar o filtro não apaga o que já foi digitado.
  final Map<int, TextEditingController> _contagens = {};
  final Set<int> _alterados = {};

  Sessao get _s => ref.read(sessaoProvider);

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _termo.dispose();
    for (final c in _contagens.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _txt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString().replaceAll('.', ',');

  Future<void> _carregar() async {
    await _s.sincronizar();
    try {
      final r = await _s.api.get('/api/inventory');
      if (!mounted) return;
      final lista = listaJson(r['itensParaConferencia']).map(Produto.deJson).toList();
      setState(() {
        _produtos = lista;
        _falhou = false;
        // Como no v1, a contagem começa com o saldo do sistema. O que foi digitado continua.
        for (final p in lista) {
          final c = _contagens.putIfAbsent(p.id, TextEditingController.new);
          if (!_alterados.contains(p.id)) c.text = _txt(p.estoque);
        }
      });
    } catch (_) {
      if (mounted) setState(() => _falhou = true);
    }
  }

  List<Produto> get _filtrados {
    final t = semAcento(_termo.text.trim());
    return _produtos.where((p) {
      if (_categoria != null && p.idCategoria != _categoria) return false;
      if (_criticos && !p.critico) return false;
      if (_validade && situacaoValidade(p.validade, _s.hoje, _s.diasValidade)?.alerta != true) return false;
      return t.isEmpty || semAcento('${p.nome} ${p.codigo} ${p.lote} ${p.descricao}').contains(t);
    }).toList();
  }

  Future<void> _salvar() async {
    final visiveis = _filtrados;
    if (visiveis.isEmpty) {
      avisar('Nenhum item para conferir.', tipo: TipoAviso.erro);
      return;
    }
    // Se algo foi digitado, vai só o que foi contado. Sem nada digitado, confirma o que está na tela, como no v1.
    final contados = _alterados.isEmpty ? visiveis : _produtos.where((p) => _alterados.contains(p.id)).toList();
    final itens = <Map<String, dynamic>>[];
    for (final p in contados) {
      final v = lerNumero(_contagens[p.id]!.text);
      final erro = v == null || v < 0 ? 'Informe uma contagem física válida (zero ou mais).' : erroQuantidade(p.unidade, v, nome: p.nome, aceitaZero: true);
      if (erro != null) {
        avisar(erro, tipo: TipoAviso.erro);
        return;
      }
      // Com o saldo lido: se houve venda no meio, o servidor recusa em vez de desfazê-la.
      itens.add({'id_produto': p.id, 'quantidade_fisica': v, 'quantidade_sistema': p.estoque});
    }
    final divergentes = contados.where((p) => r3(lerNumero(_contagens[p.id]!.text)! - p.estoque) != 0).length;
    final ok = await showDialog<bool>(context: context, builder: (_) => _SalvarConferencia(_s, itens, divergentes));
    if (ok == true) {
      _alterados.clear();
      await _carregar();
    } else if (ok == false) {
      await _carregar(); // saldo mudou: mantém o que foi digitado e mostra o saldo novo
    }
  }

  Future<void> _historico() async {
    final r = await tentar(() => _s.api.get('/api/inventory'));
    if (r == null || !mounted) return;
    final confs = listaJson(r['conferencias']);
    await showDialog<void>(
      context: context,
      builder: (c) => Modal(
        titulo: 'Histórico de conferências',
        largo: true,
        filhos: [
          if (confs.isEmpty) const Padding(padding: EdgeInsets.all(18), child: Text('Nenhuma conferência registrada.', textAlign: TextAlign.center)),
          for (final f in confs) _ItemConferencia(f),
        ],
      ),
    );
  }

  Widget _celulaValidade(Produto p, Sessao s) {
    final v = situacaoValidade(p.validade, s.hoje, s.diasValidade);
    if (v == null) return const Text('-');
    if (!v.alerta) return Text(dataBR(p.validade));
    return Tooltip(message: v.texto, child: v.vencido ? Selo.perigo(dataBR(p.validade)) : Selo.alerta(dataBR(p.validade)));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessaoProvider);
    final lista = _filtrados;
    return Pagina(
      cabecalho: CabecalhoAba('Verificar Estoque', acoes: [Botao('💾 Salvar Conferência Física', _salvar)]),
      filhos: [
        Cartao(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            BarraFiltros(
              filhos: [
                Campo(_termo, 'Filtrar estoque por termo', semRotulo: true, dica: 'Filtrar por descrição ou código...', largura: telaEstreita(context) ? double.infinity : 240, aoMudar: (_) => setState(() {})),
                Escolha<int?>(
                  rotulo: 'Filtrar por Categoria',
                  semRotulo: true,
                  largura: 170,
                  valor: _categoria,
                  opcoes: [const DropdownMenuItem(value: null, child: Text('Todas as Categorias', overflow: TextOverflow.ellipsis)), for (final c in s.categorias) DropdownMenuItem(value: c.id, child: Text(c.nome, overflow: TextOverflow.ellipsis))],
                  aoMudar: (v) => setState(() => _categoria = v),
                ),
                Marcador('Apenas nível crítico', valor: _criticos, aoMudar: (v) => setState(() => _criticos = v)),
                Marcador('Apenas vencidos / vencendo', valor: _validade, aoMudar: (v) => setState(() => _validade = v)),
              ],
              fim: Botao('🕘 Histórico de conferências', _historico, tipo: TipoBotao.secundario, pequeno: true),
            ),
            Tabela<Produto>(
              itens: lista,
              vazio: _falhou ? 'Não foi possível carregar o estoque.' : 'Nenhum produto encontrado.',
              larguraMinima: 860,
              dica: (p) {
                final v = situacaoValidade(p.validade, s.hoje, s.diasValidade);
                return 'Mínimo ${quantidade(p.estoqueMinimo)} ${p.unidade}${v != null ? ' • ${v.texto}' : ''}';
              },
              colunas: [
                Coluna('Descrição', (p) => Text(p.nome, style: const TextStyle(fontWeight: FontWeight.w700)), flex: 7),
                Coluna('Unid', (p) => Text(p.unidade)),
                Coluna('Estoque', (p) => Text(quantidade(p.estoque), style: TextStyle(fontWeight: FontWeight.w700, color: p.critico ? Cores.perigo : const Color(0xFF111827)))),
                Coluna('Lote', (p) => Text(p.lote.isEmpty ? '-' : p.lote)),
                Coluna('Validade', (p) => _celulaValidade(p, s), flex: 3),
                Coluna(
                  'Contagem Física',
                  (p) => SizedBox(
                    width: 85,
                    child: Campo(_contagens.putIfAbsent(p.id, TextEditingController.new), 'Contagem física de ${p.nome}', semRotulo: true, numerico: true, aoMudar: (_) => setState(() => _alterados.add(p.id))),
                  ),
                  flex: 4,
                ),
                Coluna('Divergência', (p) {
                  final v = lerNumero(_contagens[p.id]?.text ?? '') ?? p.estoque;
                  return _Divergencia(r3(v - p.estoque));
                }, flex: 3),
              ],
            ),
          ]),
        ),
      ],
    );
  }
}

class _Divergencia extends StatelessWidget {
  const _Divergencia(this.d);
  final double d;
  @override
  Widget build(BuildContext context) => Text('${d > 0 ? '+' : ''}${quantidade(d)}', style: TextStyle(fontWeight: FontWeight.w700, color: d == 0 ? Cores.sucesso : (d < 0 ? Cores.perigo : Cores.primaria)));
}

/// Item expansível do histórico (.conf-item)
class _ItemConferencia extends StatefulWidget {
  const _ItemConferencia(this.f);
  final Json f;
  @override
  State<_ItemConferencia> createState() => _ItemConferenciaState();
}

class _ItemConferenciaState extends State<_ItemConferencia> {
  bool _aberto = false;
  @override
  Widget build(BuildContext context) {
    final f = widget.f;
    final itens = listaJson(f['itens']);
    final div = itens.where((i) => numero(i['divergencia']) != 0).length;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(border: Border.all(color: const Color(0xFFD4D4D8)), borderRadius: BorderRadius.circular(4)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => setState(() => _aberto = !_aberto),
          child: Row(children: [
            Icon(_aberto ? Icons.arrow_drop_down : Icons.arrow_right, size: 18),
            Expanded(
              child: Text.rich(TextSpan(style: const TextStyle(fontSize: 14.1, color: Color(0xFF111827)), children: [
                TextSpan(text: '#${f['id_conferencia']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: ' • ${dataBR('${f['data_conferencia']}')} • ${f['responsavel']} • $div divergência(s)'),
              ])),
            ),
          ]),
        ),
        if (_aberto) ...[
          const SizedBox(height: 6),
          Text('${f['observacao']} ${f['ajustou_estoque'] == false ? '(sem ajuste de estoque)' : ''}', style: const TextStyle(color: Color(0xFF52525B), fontSize: 14)),
          Tabela<Json>(
            itens: itens,
            larguraMinima: 480,
            colunas: [
              Coluna('Produto', (i) => Text('${i['nome_produto']}'), flex: 4),
              Coluna('Sistema', (i) => Text('${quantidade(i['quantidade_sistema'])} ${i['unidade']}')),
              Coluna('Físico', (i) => Text(quantidade(i['quantidade_fisica']))),
              Coluna('Divergência', (i) {
                final d = numero(i['divergencia']);
                return Text('${d > 0 ? '+' : ''}${quantidade(d)}', style: TextStyle(fontWeight: d == 0 ? FontWeight.w400 : FontWeight.w700, color: d < 0 ? Cores.perigo : (d > 0 ? const Color(0xFF15803D) : null)));
              }),
            ],
          ),
        ],
      ]),
    );
  }
}

/// Resposta: true = salvou; false = saldo mudou (recarregar); null = desistiu.
class _SalvarConferencia extends StatefulWidget {
  const _SalvarConferencia(this.s, this.itens, this.divergentes);
  final Sessao s;
  final List<Map<String, dynamic>> itens;
  final int divergentes;
  @override
  State<_SalvarConferencia> createState() => _SalvarConferenciaState();
}

class _SalvarConferenciaState extends State<_SalvarConferencia> {
  final _obs = TextEditingController();
  bool _ajustar = true, _ocupado = false, _erroObs = false;

  @override
  void dispose() {
    _obs.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final obs = _obs.text.trim();
    if (obs.length < 10) {
      setState(() => _erroObs = true);
      avisar('A observação deve ter pelo menos 10 caracteres.', tipo: TipoAviso.erro);
      return;
    }
    setState(() => _ocupado = true);
    try {
      await widget.s.api.post('/api/inventory', {'itens': widget.itens, 'observacao': obs, 'ajustar': _ajustar});
      avisar('Conferência de estoque salva com sucesso!', tipo: TipoAviso.sucesso);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      avisarErro(e);
      if (!mounted) return;
      setState(() => _ocupado = false);
      if (e.status == 409) Navigator.pop(context, false);
    }
  }

  @override
  Widget build(BuildContext context) => Modal(
        titulo: 'Salvar conferência de estoque',
        acoes: [
          Botao('Cancelar', () => Navigator.pop(context), tipo: TipoBotao.secundario),
          Botao('Salvar conferência', _ocupado ? null : _enviar),
        ],
        filhos: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text.rich(TextSpan(style: const TextStyle(fontSize: 14.7, height: 1.45, color: Color(0xFF111827)), children: [
              TextSpan(text: '${widget.itens.length} produto(s) conferido(s), '),
              TextSpan(text: '${widget.divergentes} com divergência', style: const TextStyle(fontWeight: FontWeight.w700)),
              const TextSpan(text: '.'),
            ])),
          ),
          Campo(_obs, 'Observação * (10 a 1000 caracteres)', dica: 'Ex: Conferência quinzenal do balcão e do depósito.', linhas: 3, max: 1000, minContador: 10, erro: _erroObs, autofoco: true),
          espacoCampo,
          Marcador('Ajustar o estoque do sistema para a contagem física', valor: _ajustar, aoMudar: (v) => setState(() => _ajustar = v)),
        ],
      );
}
