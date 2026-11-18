// Histórico de vendas: consultar, editar, cancelar e excluir, igual ao v1.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/regras.dart';
import '../core/sessao.dart';
import '../models/modelos.dart';
import '../widgets/comuns.dart';

class HistoricoTela extends ConsumerStatefulWidget {
  const HistoricoTela({super.key, this.vendaId, this.dia, this.busca});
  final int? vendaId;
  final String? dia, busca;
  @override
  ConsumerState<HistoricoTela> createState() => _HistoricoTelaState();
}

class _HistoricoTelaState extends ConsumerState<HistoricoTela> {
  List<Venda> _vendas = [];
  bool _falhou = false;
  String _de = '', _ate = '', _status = '';
  late final _busca = TextEditingController(text: widget.busca ?? '');
  Timer? _espera;

  Sessao get _s => ref.read(sessaoProvider);

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  @override
  void dispose() {
    _espera?.cancel();
    _busca.dispose();
    super.dispose();
  }

  Future<void> _iniciar() async {
    await _s.sincronizar();
    final dia = widget.dia ?? _s.hojeOuAparelho;
    _de = dia;
    _ate = dia;
    await _carregar();
    final id = widget.vendaId;
    if (id != null && mounted) {
      final v = _vendas.where((x) => x.id == id).firstOrNull;
      if (v != null) await _detalhes(v);
    }
  }

  Future<void> _carregar() async {
    try {
      final r = await _s.api.get('/api/sales', query: {'from': _de, 'to': _ate, 'q': _busca.text.trim(), 'status': _status});
      if (!mounted) return;
      setState(() {
        _vendas = listaJson(r['sales']).map(Venda.deJson).toList();
        _falhou = false;
      });
    } catch (_) {
      if (mounted) setState(() => _falhou = true);
    }
  }

  Future<void> _detalhes(Venda v) => showDialog<void>(context: context, builder: (c) => _Detalhes(v));

  Future<void> _editar(Venda v) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _Editar(_s, v));
    if (ok == true) await _carregar();
  }

  Future<void> _autorizar(Venda v, {required bool excluir}) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _Autorizacao(_s, v, excluir));
    if (ok == true) await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessaoProvider);
    final fat = _vendas.where((v) => v.concluida).fold(0.0, (a, v) => a + v.total);
    return Pagina(
      cabecalho: const CabecalhoAba('Histórico de Vendas'),
      filhos: [
        Cartao(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            BarraFiltros(
              filhos: [
                CampoData(rotulo: 'De', valor: _de, aoMudar: (v) {
                  setState(() => _de = v);
                  _carregar();
                }),
                CampoData(rotulo: 'Até', valor: _ate, aoMudar: (v) {
                  setState(() => _ate = v);
                  _carregar();
                }),
                Campo(_busca, 'Buscar vendas', semRotulo: true, dica: 'Venda, produto ou operador...', largura: telaEstreita(context) ? double.infinity : 240, aoMudar: (_) {
                  _espera?.cancel();
                  _espera = Timer(const Duration(milliseconds: 250), _carregar);
                }),
                Escolha<String>(
                  rotulo: 'Filtrar por situação',
                  semRotulo: true,
                  largura: 110,
                  valor: _status,
                  opcoes: const [DropdownMenuItem(value: '', child: Text('Todas')), DropdownMenuItem(value: 'Concluída', child: Text('Concluídas')), DropdownMenuItem(value: 'Cancelada', child: Text('Canceladas'))],
                  aoMudar: (v) {
                    setState(() => _status = v ?? '');
                    _carregar();
                  },
                ),
                Botao('Hoje', () {
                  setState(() {
                    _de = _ate = s.hojeOuAparelho;
                    _busca.clear();
                    _status = '';
                  });
                  _carregar();
                }, tipo: TipoBotao.secundario, pequeno: true),
              ],
              fim: Dica('${_vendas.length} venda(s) • faturamento ${dinheiro(fat)}'),
            ),
            Tabela<Venda>(
              itens: _vendas,
              vazio: _falhou ? 'Falha ao carregar o histórico de vendas.' : 'Nenhuma venda encontrada para os filtros informados.',
              larguraMinima: 1040,
              apagado: (v) => !v.concluida,
              colunas: [
                Coluna('Venda', (v) => Text(v.codigo, style: const TextStyle(fontWeight: FontWeight.w700)), flex: 4),
                Coluna('Data', (v) => Text(dataBR(v.data)), flex: 4),
                Coluna('Operador', (v) => Text(v.usuario), flex: 3),
                Coluna('Pagamento', (v) => Text(v.forma), flex: 3),
                Coluna('Itens', (v) => Text(v.itens.map((i) => '${i.nome} x${quantidade(i.quantidade)}').join(', '), style: const TextStyle(fontSize: 13.1)), flex: 6),
                Coluna('Total', (v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(dinheiro(v.total)), if (v.desconto > 0) Pequeno('desc. ${dinheiro(v.desconto)}')]), flex: 3),
                Coluna('Situação', (v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [seloVenda(v.status), if (v.dataEdicao.isNotEmpty) const Pequeno('editada')]), flex: 3),
                Coluna(
                  'Ações',
                  (v) => Wrap(children: [
                    BotaoIcone('👁', 'Ver detalhes', () => _detalhes(v)),
                    if (v.concluida && s.pode('vendas:editar')) BotaoIcone('✎', 'Editar quantidades', () => _editar(v), tipo: TipoAcao.avancar),
                    if (v.concluida && s.pode('vendas:cancelar')) BotaoIcone('✕', 'Cancelar venda', () => _autorizar(v, excluir: false), tipo: TipoAcao.cancelar),
                    if (s.pode('vendas:excluir')) BotaoIcone('🗑', 'Excluir registro', () => _autorizar(v, excluir: true), tipo: TipoAcao.lixeira),
                  ]),
                  flex: 5,
                ),
              ],
            ),
          ]),
        ),
      ],
    );
  }
}

class _Detalhes extends StatelessWidget {
  const _Detalhes(this.v);
  final Venda v;
  @override
  Widget build(BuildContext context) => Modal(
        titulo: '${v.codigo} - ${v.status}',
        largo: true,
        acaoUnica: Botao('Fechar', () => Navigator.pop(context), tipo: TipoBotao.secundario, bloco: true),
        filhos: [
          Text('${dataBR(v.data)} • Operador: ${v.usuario} • ${v.forma}${v.nsu.isNotEmpty ? ' • NSU ${v.nsu}' : ''}', style: const TextStyle(color: Color(0xFF52525B), fontSize: 14)),
          Tabela<ItemVenda>(itens: v.itens, larguraMinima: 480, colunas: [
            Coluna('Produto', (i) => Text(i.nome), flex: 4),
            Coluna('Valor', (i) => Text(num2(i.valorUnitario))),
            Coluna('Quant.', (i) => Text('${quantidade(i.quantidade)} ${i.unidade}')),
            Coluna('Subtotal', (i) => Text(num2(i.subtotal))),
          ]),
          const SizedBox(height: 10),
          Wrap(alignment: WrapAlignment.end, spacing: 16, runSpacing: 4, children: [
            Text('Subtotal: ${dinheiro(v.subtotal)}', style: const TextStyle(fontSize: 14.4)),
            Text('Desconto: - ${dinheiro(v.desconto)}', style: const TextStyle(fontSize: 14.4)),
            Text('Total: ${dinheiro(v.total)}', style: const TextStyle(fontSize: 14.4, fontWeight: FontWeight.w700)),
            if ((v.troco ?? 0) > 0) Text('Recebido ${dinheiro(v.recebido)} • Troco ${dinheiro(v.troco)}', style: const TextStyle(fontSize: 14.4)),
          ]),
          if (!v.concluida)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(color: const Color(0xFFFEF2F2), border: Border.all(color: const Color(0xFFFECACA)), borderRadius: BorderRadius.circular(4)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Cancelada em ${dataBR(v.dataCancelamento)} por ${v.canceladaPor} (autorizada por ${v.autorizadaPor})', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF991B1B), fontSize: 13.1)),
                const SizedBox(height: 6),
                Text(v.motivoCancelamento, style: const TextStyle(fontStyle: FontStyle.italic, color: Color(0xFF1F2937), height: 1.45, fontSize: 14)),
              ]),
            ),
          if (v.dataEdicao.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text('Editada em ${dataBR(v.dataEdicao)} por ${v.editadaPor}.', style: const TextStyle(color: Color(0xFF52525B), fontSize: 14))),
        ],
      );
}

class _Editar extends StatefulWidget {
  const _Editar(this.s, this.v);
  final Sessao s;
  final Venda v;
  @override
  State<_Editar> createState() => _EditarState();
}

class _EditarState extends State<_Editar> {
  late final Map<int, TextEditingController> _qtd = {for (final i in widget.v.itens) i.id: TextEditingController(text: quantidade(i.quantidade).replaceAll('.', ''))};
  late final _recebido = TextEditingController(text: widget.v.recebido == null ? '' : num2(widget.v.recebido).replaceAll('.', ''));
  bool _ocupado = false;

  @override
  void dispose() {
    for (final c in _qtd.values) {
      c.dispose();
    }
    _recebido.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    final itens = <Map<String, dynamic>>[];
    for (final i in widget.v.itens) {
      final q = lerNumero(_qtd[i.id]!.text);
      final erro = erroQuantidade(i.unidade, q, nome: i.nome, aceitaZero: true);
      if (erro != null) {
        avisar('${i.nome}: $erro', tipo: TipoAviso.erro); // negativo não remove o item sem avisar
        return;
      }
      if (q! > 0) itens.add({'id_produto': i.idProduto, 'id_item_venda': i.id, 'quantidade': q});
    }
    if (itens.isEmpty) {
      avisar('A venda precisa ter ao menos um item. Para anulá-la, use o cancelamento.', tipo: TipoAviso.erro);
      return;
    }
    setState(() => _ocupado = true);
    final rec = lerNumero(_recebido.text);
    final r = await tentar(() => widget.s.api.put('/api/sales/${widget.v.id}', {'itens': itens, 'valor_recebido': ?rec}));
    if (!mounted) return;
    setState(() => _ocupado = false);
    if (r != null) {
      avisar(r['message'].toString(), tipo: TipoAviso.sucesso);
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.v;
    return Modal(
      titulo: 'Editar ${v.codigo}',
      largo: true,
      acoes: [
        Botao('Cancelar', () => Navigator.pop(context), tipo: TipoBotao.secundario),
        Botao('Salvar alterações', _ocupado ? null : _salvar),
      ],
      filhos: [
        const Text('Altere as quantidades. O estoque e o total serão recalculados. Use 0 para remover um item (a venda precisa manter ao menos um).', style: TextStyle(color: Color(0xFF52525B), fontSize: 14)),
        Tabela<ItemVenda>(itens: v.itens, larguraMinima: 480, colunas: [
          Coluna('Produto', (i) => Text(i.nome), flex: 4),
          Coluna('Valor', (i) => Text(num2(i.valorUnitario))),
          Coluna('Quantidade', (i) => Row(mainAxisSize: MainAxisSize.min, children: [SizedBox(width: 85, child: Campo(_qtd[i.id]!, 'Quantidade', semRotulo: true, numerico: true)), const SizedBox(width: 6), Text(i.unidade)]), flex: 3),
        ]),
        // Só em venda em dinheiro: é onde o troco precisa acompanhar o novo total.
        if (v.forma == 'Dinheiro') ...[
          espacoCampo,
          Campo(_recebido, 'Valor recebido (R\$)', numerico: true, dica: 'opcional'),
        ],
      ],
    );
  }
}

class _Autorizacao extends StatefulWidget {
  const _Autorizacao(this.s, this.v, this.excluir);
  final Sessao s;
  final Venda v;
  final bool excluir;
  @override
  State<_Autorizacao> createState() => _AutorizacaoState();
}

class _AutorizacaoState extends State<_Autorizacao> {
  final _motivo = TextEditingController(), _senha = TextEditingController();
  late final _email = TextEditingController(text: _emailInicial());
  bool _ocupado = false, _erroMotivo = false, _erroSenha = false;

  String _emailInicial() {
    final u = widget.s.usuario;
    final preencher = widget.excluir ? u?.admin == true : u?.gerente == true;
    return preencher ? u!.email : '';
  }

  @override
  void dispose() {
    _motivo.dispose();
    _senha.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final motivo = _motivo.text.trim();
    setState(() {
      _erroMotivo = false;
      _erroSenha = false;
    });
    if (!widget.excluir && motivo.length < 10) {
      setState(() => _erroMotivo = true);
      avisar('O motivo deve ter entre 10 e 5000 caracteres.', tipo: TipoAviso.erro);
      return;
    }
    if (_email.text.trim().isEmpty || _senha.text.isEmpty) {
      setState(() => _erroSenha = true);
      avisar('Informe o e-mail e a senha do autorizador.', tipo: TipoAviso.erro);
      return;
    }
    final corpo = {'motivo': motivo, 'autorizador_email': _email.text.trim(), 'autorizador_senha': _senha.text};
    setState(() => _ocupado = true);
    final r = await tentar(() => widget.excluir ? widget.s.api.delete('/api/sales/${widget.v.id}', corpo) : widget.s.api.post('/api/sales/${widget.v.id}/cancel', corpo));
    if (!mounted) return;
    setState(() => _ocupado = false);
    if (r != null) {
      avisar(r['message'].toString(), tipo: TipoAviso.sucesso);
      Navigator.pop(context, true);
    } else {
      _senha.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.v;
    final excluir = widget.excluir;
    const base = TextStyle(fontSize: 14.7, height: 1.45, color: Color(0xFF111827));
    const forte = TextStyle(fontWeight: FontWeight.w700);
    return Modal(
      titulo: '${excluir ? 'Excluir' : 'Cancelar'} ${v.codigo}',
      acoes: [
        Botao('Voltar', () => Navigator.pop(context), tipo: TipoBotao.secundario),
        Botao(excluir ? 'Excluir definitivamente' : 'Cancelar venda', _ocupado ? null : _enviar, tipo: TipoBotao.perigo),
      ],
      filhos: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text.rich(TextSpan(style: base, children: excluir
              ? [
                  const TextSpan(text: 'O registro será '),
                  const TextSpan(text: 'removido definitivamente', style: forte),
                  TextSpan(text: '${v.concluida ? ' e o estoque dos itens será estornado' : ''}. Prefira o cancelamento para manter o histórico financeiro.'),
                ]
              : [
                  const TextSpan(text: 'A venda de '),
                  TextSpan(text: dinheiro(v.total), style: forte),
                  const TextSpan(text: ' será cancelada e os itens retornarão ao estoque.'),
                ])),
        ),
        if (!excluir) ...[Campo(_motivo, 'Motivo * (10 a 5000 caracteres)', linhas: 3, max: 5000, erro: _erroMotivo), espacoCampo],
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: const Color(0xFFFAFAFA), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF9CA3AF))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Autorização ${excluir ? 'do Administrador' : 'de gerente'}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            espacoCampo,
            Campo(_email, 'E-mail do ${excluir ? 'administrador' : 'gerente (Administrador ou BackOffice)'}'),
            espacoCampo,
            Campo(_senha, 'Senha', senha: true, erro: _erroSenha, aoEnviar: (_) => _enviar()),
          ]),
        ),
      ],
    );
  }
}
