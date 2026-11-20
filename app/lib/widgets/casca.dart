// Cabeçalho, menu lateral, busca global e menu do usuário, iguais ao GestFast v1.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/regras.dart';
import '../core/rotas.dart';
import '../core/sessao.dart';
import '../core/tema.dart';
import '../features/configuracoes_tela.dart';
import '../models/modelos.dart';

/// .gestfast-logo: GEST e FAST# em duas linhas
class Logo extends StatelessWidget {
  const Logo({super.key, this.tamanho = 20.8, this.cor = Colors.black, this.centralizado = false});
  final double tamanho;
  final Color cor;
  final bool centralizado;
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: centralizado ? CrossAxisAlignment.center : CrossAxisAlignment.start, children: [
        Text('GEST', style: TextStyle(fontSize: tamanho, height: 1, fontWeight: FontWeight.w900, letterSpacing: .5, color: cor)),
        Text('FAST#', style: TextStyle(fontSize: tamanho, height: 1, fontWeight: FontWeight.w900, letterSpacing: -.5, color: Colors.black)),
      ]);
}

class _BotaoCirculo extends StatelessWidget {
  const _BotaoCirculo({required this.filho, required this.dica, required this.aoClicar});
  final Widget filho;
  final String dica;
  final VoidCallback aoClicar;
  @override
  Widget build(BuildContext context) => Tooltip(
        message: dica,
        child: Semantics(
          button: true,
          label: dica,
          child: InkWell(
            onTap: aoClicar,
            customBorder: const CircleBorder(),
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: Cores.bordaBusca, width: 1.5)),
              child: filho,
            ),
          ),
        ),
      );
}

class Casca extends ConsumerStatefulWidget {
  const Casca({super.key, required this.filho});
  final Widget filho;
  @override
  ConsumerState<Casca> createState() => _CascaState();
}

class _ResultadoBusca {
  const _ResultadoBusca(this.icone, this.etiqueta, this.titulo, this.detalhe, this.abrir);
  final String icone, etiqueta, titulo, detalhe;
  final void Function(BuildContext) abrir;
}

class _GrupoBusca {
  const _GrupoBusca(this.titulo, this.itens);
  final String titulo;
  final List<_ResultadoBusca> itens;
}

class _CascaState extends ConsumerState<Casca> {
  final _chaveScaffold = GlobalKey<ScaffoldState>();
  final _chaveBusca = GlobalKey();
  final _chaveUsuario = GlobalKey();
  final _pilha = GlobalKey();
  final _texto = TextEditingController();
  final _foco = FocusNode();
  bool _menuAberto = false, _buscaAberta = false, _buscando = false;
  List<_GrupoBusca> _remotos = [];
  String _remotosDe = '';
  int _ativo = 0, _seq = 0;
  Timer? _espera;

  Sessao get _s => ref.read(sessaoProvider);

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_atalhos);
    _foco.addListener(() {
      if (_foco.hasFocus && !_buscaAberta) setState(() => _buscaAberta = true);
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_atalhos);
    _espera?.cancel();
    _texto.dispose();
    _foco.dispose();
    super.dispose();
  }

  bool _digitando() {
    final c = FocusManager.instance.primaryFocus?.context;
    return c != null && c.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  // "/" fora de um campo de texto, ou Ctrl+K em qualquer lugar, foca a busca.
  bool _atalhos(KeyEvent e) {
    if (e is! KeyDownEvent) return false;
    final t = HardwareKeyboard.instance;
    final ctrlK = (t.isControlPressed || t.isMetaPressed) && e.logicalKey == LogicalKeyboardKey.keyK;
    if (ctrlK || (e.character == '/' && !_digitando())) {
      _foco.requestFocus();
      _texto.selection = TextSelection(baseOffset: 0, extentOffset: _texto.text.length);
      return true;
    }
    return false;
  }

  // ---------------------------------------------------------- busca
  List<_ResultadoBusca> _telas(String q, Sessao s) {
    final t = semAcento(q);
    return [
      for (final d in destinos)
        if ((d.perm == null || s.pode(d.perm!)) && (t.isEmpty || semAcento(d.rotuloBusca).contains(t) || d.chaves.contains(t) || semAcento(d.descricao).contains(t)))
          _ResultadoBusca(d.emoji, 'Tela', d.rotuloBusca, d.descricao, (c) => c.go(d.caminho)),
    ];
  }

  void _digitou(String _) {
    final q = _texto.text.trim();
    _espera?.cancel();
    setState(() {
      _ativo = 0;
      _remotos = [];
      _remotosDe = '';
      _buscando = q.length >= 2;
      _buscaAberta = true;
    });
    if (q.length < 2) return;
    final meu = ++_seq;
    _espera = Timer(const Duration(milliseconds: 220), () async {
      final s = _s;
      var achados = <_GrupoBusca>[];
      try {
        final r = await s.api.get('/api/search', query: {'q': q});
        achados = _converter(Json.from(r['results'] as Map), s);
      } catch (_) {
        achados = [];
      }
      if (meu != _seq || !mounted) return;
      setState(() {
        _buscando = false;
        _remotos = achados;
        _remotosDe = q;
      });
    });
  }

  List<_GrupoBusca> _converter(Json r, Sessao s) {
    final produtos = listaJson(r['produtos']), reqs = listaJson(r['requisicoes']), vendas = listaJson(r['vendas']), usuarios = listaJson(r['usuarios']);
    return [
      if (produtos.isNotEmpty)
        _GrupoBusca('Produtos', [
          for (final p in produtos)
            _ResultadoBusca('📦', 'Produto', '${p['nome_produto']}', '${p['codigo_barras']} • ${p['categoria']} • ${quantidade(p['quantidade_estoque'])} ${p['unidade']} em estoque${p['status'] == 'Inativo' ? ' • Inativo' : ''}',
                (c) => s.pode('produtos:editar') ? c.go('/produtos?id=${p['id_produto']}') : c.go('/estoque?q=${Uri.encodeQueryComponent('${p['nome_produto']}')}')),
        ]),
      if (reqs.isNotEmpty)
        _GrupoBusca('Requisições de compra', [
          for (final x in reqs) _ResultadoBusca('📝', 'Requisição', '${x['codigo_pedido']} • ${x['produto_nome']}', '${x['fornecedor']} • ${x['situacao']}', (c) => c.go('/requisicoes?id=${x['id_requisicao']}')),
        ]),
      if (vendas.isNotEmpty)
        _GrupoBusca('Vendas', [
          for (final v in vendas)
            _ResultadoBusca('🧾', 'Venda', '${v['codigo_venda']} • ${dinheiro(v['valor_total'])}', '${dataBR('${v['data_venda']}')} • ${v['usuario_nome']} • ${v['status_venda']}',
                (c) => c.go('/historico?venda=${v['id_venda']}&dia=${'${v['data_venda']}'.substring(0, 10)}&q=${Uri.encodeQueryComponent('${v['codigo_venda']}')}')),
        ]),
      if (usuarios.isNotEmpty)
        _GrupoBusca('Funcionários', [
          for (final u in usuarios) _ResultadoBusca('👤', 'Funcionário', '${u['nome']}', '${u['email']} • ${nomePerfil('${u['perfil']}')} • ${u['status']}', (c) => c.go('/funcionarios?q=${Uri.encodeQueryComponent('${u['nome']}')}')),
        ]),
    ];
  }

  List<_GrupoBusca> _grupos(Sessao s) {
    final q = _texto.text.trim();
    final telas = _telas(q, s);
    return [
      if (telas.isNotEmpty) _GrupoBusca(q.isNotEmpty ? 'Ir para' : 'Telas do sistema', q.isNotEmpty ? telas.take(4).toList() : telas),
      if (_remotosDe == q) ..._remotos,
    ];
  }

  void _fecharBusca() {
    if (_buscaAberta) setState(() => _buscaAberta = false);
    _foco.unfocus();
  }

  void _abrir(_ResultadoBusca r) {
    _texto.clear();
    setState(() {
      _buscaAberta = false;
      _remotos = [];
      _remotosDe = '';
      _ativo = 0;
    });
    _foco.unfocus();
    r.abrir(context);
  }

  KeyEventResult _teclaBusca(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final itens = _grupos(_s).expand((g) => g.itens).toList();
    final ultimo = itens.isEmpty ? 0 : itens.length - 1;
    if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _buscaAberta = true;
        _ativo = (_ativo + 1).clamp(0, ultimo);
      });
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() => _ativo = (_ativo - 1).clamp(0, ultimo));
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      _fecharBusca();
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.tab) {
      final p = _previsao(_s);
      if (p.isNotEmpty) {
        _texto.text = p;
        _texto.selection = TextSelection.collapsed(offset: p.length);
        _digitou(p);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  // Previsão fantasma: completa o nome da primeira tela que começa com o texto digitado.
  String _previsao(Sessao s) {
    final q = _texto.text;
    if (q.trim().isEmpty) return '';
    final telas = _telas(q.trim(), s);
    if (telas.isEmpty) return '';
    return semAcento(telas.first.titulo).startsWith(semAcento(q.trim())) ? telas.first.titulo : '';
  }

  // ---------------------------------------------------------- construção
  Rect? _retangulo(GlobalKey k) {
    final caixa = k.currentContext?.findRenderObject() as RenderBox?;
    final pilha = _pilha.currentContext?.findRenderObject() as RenderBox?;
    if (caixa == null || pilha == null) return null;
    return caixa.localToGlobal(Offset.zero, ancestor: pilha) & caixa.size;
  }

  @override
  Widget build(BuildContext context) {
    final sessao = ref.watch(sessaoProvider);
    final largo = MediaQuery.sizeOf(context).width > 900;
    final atual = GoRouterState.of(context).matchedLocation;
    Theme.of(context);
    return Scaffold(
      key: _chaveScaffold,
      backgroundColor: Cores.pagina,
      drawerScrimColor: const Color(0x73000000),
      drawer: largo ? null : Drawer(width: 250, backgroundColor: Cores.pagina, shape: const RoundedRectangleBorder(), child: SafeArea(child: _Menu(atual: atual, sessao: sessao, aoEscolher: () => Navigator.of(context).maybePop()))),
      body: SafeArea(
        child: Stack(key: _pilha, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _cabecalho(sessao, largo),
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (largo)
                  Container(
                    width: 220,
                    decoration: BoxDecoration(color: Cores.pagina, border: Border(right: BorderSide(color: Cores.linhaLayout, width: 2))),
                    child: _Menu(atual: atual, sessao: sessao),
                  ),
                Expanded(child: widget.filho),
              ]),
            ),
          ]),
          if (_buscaAberta || _menuAberto)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  _fecharBusca();
                  if (_menuAberto) setState(() => _menuAberto = false);
                },
              ),
            ),
          if (_buscaAberta) _listaBusca(sessao),
          if (_menuAberto) _menuUsuario(sessao),
        ]),
      ),
    );
  }

  Widget _cabecalho(Sessao s, bool largo) {
    final esquerda = Row(mainAxisSize: MainAxisSize.min, children: [
      if (!largo) ...[
        _BotaoCirculo(filho: const Icon(Icons.menu, size: 18, color: Colors.black87), dica: 'Abrir menu', aoClicar: () => _chaveScaffold.currentState?.openDrawer()),
        const SizedBox(width: 16),
      ],
      Tooltip(message: 'Ir para o Início', child: InkWell(onTap: () => context.go('/painel'), child: const Logo())),
      const SizedBox(width: 16),
      _BotaoCirculo(filho: const Text('🏠', style: TextStyle(fontSize: 17.6)), dica: 'Voltar ao Início', aoClicar: () => context.go('/painel')),
    ]);
    final u = s.usuario;
    final usuario = Tooltip(
      message: 'Menu do usuário',
      child: Semantics(
        button: true,
        label: 'Menu do usuário',
        child: InkWell(
          key: _chaveUsuario,
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _menuAberto = !_menuAberto),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: _menuAberto ? const Color(0x12000000) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 38, height: 38, alignment: Alignment.center, decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle), child: const Text('👤', style: TextStyle(fontSize: 18.4))),
              if (largo) ...[
                const SizedBox(width: 10),
                Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(u?.nome ?? '-', style: TextStyle(fontSize: 13.8, fontWeight: FontWeight.w900, color: Cores.preto)),
                  Text(u?.cargo.isNotEmpty == true ? u!.cargo : nomePerfil(u?.perfil), style: const TextStyle(fontSize: 11.5, color: Color(0xFF6B7280))),
                ]),
              ],
            ]),
          ),
        ),
      ),
    );
    final busca = _campoBusca(s);
    return Container(
      decoration: BoxDecoration(color: Cores.pagina, border: Border(bottom: BorderSide(color: Cores.linhaLayout, width: 2))),
      padding: largo ? const EdgeInsets.symmetric(horizontal: 20) : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      height: largo ? 64 : null,
      child: largo
          ? Row(children: [
              esquerda,
              Expanded(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 580), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: busca)))),
              usuario,
            ])
          : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [esquerda, const Spacer(), usuario]),
              const SizedBox(height: 8),
              busca,
            ]),
    );
  }

  Widget _campoBusca(Sessao s) {
    final q = _texto.text;
    final previsao = _previsao(s);
    return Container(
      key: _chaveBusca,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(99), border: Border.all(color: Cores.bordaBusca, width: 1.8)),
      child: Row(children: [
        const Text('🔍', style: TextStyle(fontSize: 15.2)),
        const SizedBox(width: 8),
        Expanded(
          child: Stack(alignment: Alignment.centerLeft, children: [
            if (previsao.isNotEmpty && previsao.length >= q.length) Text(q + previsao.substring(q.length), maxLines: 1, style: const TextStyle(fontSize: 14.1, color: Color(0xFF9CA3AF))),
            Focus(
              onKeyEvent: _teclaBusca,
              child: Semantics(
                label: 'Buscar opções e telas do sistema',
                child: TextField(
                  key: const ValueKey('busca-global'),
                  controller: _texto,
                  focusNode: _foco,
                  style: const TextStyle(fontSize: 14.1, color: Color(0xFF1F2937)),
                  decoration: const InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'Para onde deseja ir ou o que procura? (ex: estoque, pão, REQ-9661, venda...)',
                    hintMaxLines: 1,
                    hintStyle: TextStyle(fontSize: 14.1, color: Color(0xFF6B7280), overflow: TextOverflow.ellipsis),
                  ),
                  onChanged: _digitou,
                  onSubmitted: (_) {
                    final itens = _grupos(s).expand((g) => g.itens).toList();
                    if (itens.isNotEmpty) _abrir(itens[_ativo.clamp(0, itens.length - 1)]);
                  },
                ),
              ),
            ),
          ]),
        ),
        if (q.isNotEmpty)
          Semantics(
            button: true,
            label: 'Limpar pesquisa',
            child: InkWell(
              onTap: () {
                _texto.clear();
                _digitou('');
                _foco.requestFocus();
              },
              child: const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.close, size: 16, color: Color(0xFF9CA3AF))),
            ),
          ),
      ]),
    );
  }

  Widget _listaBusca(Sessao s) {
    final caixa = _retangulo(_chaveBusca);
    if (caixa == null) return const SizedBox.shrink();
    final q = _texto.text.trim();
    final largo = MediaQuery.sizeOf(context).width > 900;
    final grupos = _grupos(s);
    final total = grupos.fold(0, (a, g) => a + g.itens.length);
    if (_ativo >= total) _ativo = total == 0 ? 0 : total - 1;
    var n = -1;
    final altura = MediaQuery.sizeOf(context).height;
    return Positioned(
      left: caixa.left,
      top: caixa.top + 54 - (largo ? 0 : 4),
      width: caixa.width,
      child: Material(
        color: Colors.white,
        elevation: 14,
        shadowColor: const Color(0x470F172A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFFCBD5E1))),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            color: const Color(0xFFF8FAFC),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Text(q.isNotEmpty ? 'Resultados para “$q”' : 'Para onde deseja ir?', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF64748B), letterSpacing: .25)),
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: (altura * .62).clamp(0, 430)),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                for (final g in grupos) ...[
                  Padding(padding: const EdgeInsets.fromLTRB(10, 12, 10, 6), child: Text(g.titulo.toUpperCase(), style: const TextStyle(fontSize: 11.2, fontWeight: FontWeight.w900, letterSpacing: .8, color: Color(0xFF64748B)))),
                  for (final it in g.itens) _opcao(it, ++n, q),
                ],
                if (q.length == 1) const _StatusBusca('Digite ao menos 2 letras para buscar produtos, requisições e vendas.'),
                if (q.length >= 2 && _buscando) const _StatusBusca('🔎 Buscando produtos, requisições e vendas…'),
                if (q.isNotEmpty && !_buscando && q.length >= 2 && total == 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                    child: Column(children: [
                      Text('Nenhum resultado para “$q”', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.6, color: Color(0xFF1E293B))),
                      const SizedBox(height: 4),
                      const Text('Tente outro termo, o código de barras ou o número do pedido (ex.: REQ-9661).', textAlign: TextAlign.center, style: TextStyle(fontSize: 13.6, color: Color(0xFF64748B))),
                    ]),
                  ),
              ]),
            ),
          ),
          if (largo) ...[
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            Container(
              color: const Color(0xFFF8FAFC),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              child: const Row(children: [
                _Tecla('↑'), _Tecla('↓'), Text('navegar', style: _estiloRodape), SizedBox(width: 18),
                _Tecla('Enter'), Text('abrir', style: _estiloRodape), SizedBox(width: 18),
                _Tecla('Esc'), Text('fechar', style: _estiloRodape),
              ]),
            ),
          ],
        ]),
      ),
    );
  }

  static const _coresEtiqueta = {
    'Produto': (Color(0xFFDBEAFE), Color(0xFF1D4ED8)),
    'Requisição': (Color(0xFFFEF3C7), Color(0xFF92400E)),
    'Venda': (Color(0xFFDCFCE7), Color(0xFF166534)),
    'Funcionário': (Color(0xFFEDE9FE), Color(0xFF6D28D9)),
    'Tela': (Color(0xFFE2E8F0), Color(0xFF334155)),
  };

  // Destaca o trecho digitado, sem diferenciar acentos e maiúsculas.
  TextSpan _marcado(String texto, String q, TextStyle base) {
    final nt = semAcento(texto), nq = semAcento(q);
    final i = nq.isEmpty || nt.length != texto.length ? -1 : nt.indexOf(nq);
    if (i < 0) return TextSpan(text: texto, style: base);
    return TextSpan(style: base, children: [
      TextSpan(text: texto.substring(0, i)),
      TextSpan(text: texto.substring(i, i + nq.length), style: const TextStyle(backgroundColor: Color(0xFFFDE68A))),
      TextSpan(text: texto.substring(i + nq.length)),
    ]);
  }

  Widget _opcao(_ResultadoBusca it, int i, String q) {
    final ativo = i == _ativo;
    final (fundo, frente) = _coresEtiqueta[it.etiqueta] ?? _coresEtiqueta['Tela']!;
    return MouseRegion(
      onEnter: (_) {
        if (_ativo != i) setState(() => _ativo = i);
      },
      child: InkWell(
        onTap: () => _abrir(it),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: ativo ? const Color(0xFFEFF6FF) : Colors.transparent, borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: ativo ? const Color(0xFFDBEAFE) : const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(10)),
              child: Text(it.icone, style: const TextStyle(fontSize: 18.4)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text.rich(_marcado(it.titulo, q, const TextStyle(fontSize: 14.7, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Text.rich(_marcado(it.detalhe, q, const TextStyle(fontSize: 12.5, color: Color(0xFF64748B))), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            const SizedBox(width: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(color: fundo, borderRadius: BorderRadius.circular(99)),
              child: Text(it.etiqueta, style: TextStyle(fontSize: 10.6, fontWeight: FontWeight.w900, color: frente)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _menuUsuario(Sessao s) {
    final caixa = _retangulo(_chaveUsuario);
    if (caixa == null) return const SizedBox.shrink();
    final largura = MediaQuery.sizeOf(context).width;
    Widget item(String rotulo, VoidCallback acao, {Widget? icone, bool perigo = false}) => Semantics(
          button: true,
          label: rotulo,
          excludeSemantics: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              setState(() => _menuAberto = false);
              acao();
            },
            child: Padding(
              padding: const EdgeInsets.all(11),
              child: Row(children: [
                ?icone,
                if (icone != null) const SizedBox(width: 6),
                Flexible(child: Text(rotulo, style: TextStyle(fontSize: 14.1, color: perigo ? Cores.perigo : const Color(0xFF1E293B), fontWeight: perigo ? FontWeight.w700 : FontWeight.w400))),
              ]),
            ),
          ),
        );
    Widget a11y(String t, String dica, VoidCallback f) => Tooltip(
          message: dica,
          child: Semantics(
            button: true,
            label: dica,
            excludeSemantics: true,
            child: InkWell(
              onTap: f,
              child: Container(
                constraints: const BoxConstraints(minWidth: 34),
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFF9CA3AF)), borderRadius: BorderRadius.circular(4)),
                child: Text(t, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.6, color: Colors.black)),
              ),
            ),
          ),
        );
    return Positioned(
      right: (largura - caixa.right).clamp(0, largura),
      top: caixa.bottom + 8,
      width: 260,
      child: Material(
        color: Colors.white,
        elevation: 14,
        shadowColor: const Color(0x470F172A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFFCBD5E1))),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            item('Alterar minha senha', () => abrirTrocaSenha(context, s), icone: const Text('🔑', style: TextStyle(fontSize: 14))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: [
                const Expanded(child: Text('Tamanho do texto', style: TextStyle(fontSize: 14.1, color: Color(0xFF1E293B)))),
                a11y('A-', 'Diminuir tamanho do texto', () => s.mudarZoom(-1)),
                const SizedBox(width: 4),
                a11y('A+', 'Aumentar tamanho do texto', () => s.mudarZoom(1)),
              ]),
            ),
            item('Alto contraste', s.alternarContraste, icone: const Icon(Icons.contrast, size: 14, color: Colors.black)),
            const Divider(height: 8, color: Color(0xFFE2E8F0)),
            item('Sair do sistema', s.sair, icone: const Icon(Icons.power_settings_new, size: 15, color: Cores.perigo), perigo: true),
          ]),
        ),
      ),
    );
  }
}

const _estiloRodape = TextStyle(fontSize: 11.5, color: Color(0xFF64748B));

class _Tecla extends StatelessWidget {
  const _Tecla(this.t);
  final String t;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(right: 4),
        constraints: const BoxConstraints(minWidth: 18),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(5),
          border: const Border(top: BorderSide(color: Color(0xFFCBD5E1)), left: BorderSide(color: Color(0xFFCBD5E1)), right: BorderSide(color: Color(0xFFCBD5E1)), bottom: BorderSide(color: Color(0xFFCBD5E1), width: 2)),
        ),
        child: Text(t, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.2, color: Color(0xFF334155))),
      );
}

class _StatusBusca extends StatelessWidget {
  const _StatusBusca(this.t);
  final String t;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16), child: Text(t, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13.6, color: Color(0xFF64748B))));
}

class _Menu extends StatelessWidget {
  const _Menu({required this.atual, required this.sessao, this.aoEscolher});
  final String atual;
  final Sessao sessao;
  final VoidCallback? aoEscolher;

  @override
  Widget build(BuildContext context) {
    final permitidos = destinos.where((d) => d.perm == null || sessao.pode(d.perm!)).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: ListView(padding: EdgeInsets.zero, children: [
            for (final d in permitidos) ...[
              if (d.caminho == '/configuracoes') Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), color: Cores.linhaLayout),
              _ItemMenu(d, atual == d.caminho, () {
                aoEscolher?.call();
                context.go(d.caminho);
              }),
            ],
          ]),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('GestFast v1.3', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: Color(0xFF71717A))),
            Text('USCS - ADS', style: TextStyle(fontSize: 11.5, color: Color(0xFF71717A))),
          ]),
        ),
      ]),
    );
  }
}

class _ItemMenu extends StatefulWidget {
  const _ItemMenu(this.d, this.ativo, this.aoClicar);
  final Destino d;
  final bool ativo;
  final VoidCallback aoClicar;
  @override
  State<_ItemMenu> createState() => _ItemMenuState();
}

class _ItemMenuState extends State<_ItemMenu> {
  bool _sobre = false;
  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final secundario = widget.d.caminho == '/configuracoes' || widget.d.caminho == '/ajuda';
    final fundo = widget.ativo ? Cores.menuAtivo : (_sobre ? Cores.menuHover : Colors.transparent);
    final cor = widget.ativo || (_sobre && Cores.altoContraste) ? Cores.textoMenuAtivo : (secundario ? Cores.fraco : Cores.texto);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Semantics(
        button: true,
        selected: widget.ativo,
        label: widget.d.rotulo,
        excludeSemantics: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _sobre = true),
          onExit: (_) => setState(() => _sobre = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.aoClicar,
            child: Container(
              color: fundo,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text(widget.d.rotulo, style: TextStyle(fontSize: secundario ? 14.4 : 16.8, fontWeight: widget.ativo ? FontWeight.w900 : FontWeight.w500, color: cor)),
            ),
          ),
        ),
      ),
    );
  }
}
