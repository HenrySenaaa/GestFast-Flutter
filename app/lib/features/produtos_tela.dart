// Cadastro de Produto: formulário de três colunas e catálogo ao lado, iguais ao v1.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/regras.dart';
import '../core/sessao.dart';
import '../core/tema.dart';
import '../models/modelos.dart';
import '../widgets/comuns.dart';

class ProdutosTela extends ConsumerStatefulWidget {
  const ProdutosTela({super.key, this.abrirId});
  final int? abrirId;
  @override
  ConsumerState<ProdutosTela> createState() => _ProdutosTelaState();
}

class _ProdutosTelaState extends ConsumerState<ProdutosTela> {
  final _nome = TextEditingController(), _codigo = TextEditingController(), _custo = TextEditingController(), _min = TextEditingController(), _max = TextEditingController(), _venda = TextEditingController(), _estMin = TextEditingController(), _estAtual = TextEditingController(), _peso = TextEditingController(), _lote = TextEditingController(), _desc = TextEditingController(), _busca = TextEditingController();
  String _unidade = 'UN', _validade = '', _status = 'Ativo';
  int? _categoria, _filtroCategoria;
  Produto? _editando;
  Uint8List? _imagemBytes;
  String? _imagemData;
  List<Produto> _lista = [];
  bool _falhou = false, _salvando = false, _erroNome = false, _erroVenda = false, _erroEstMin = false, _erroEstAtual = false, _erroDesc = false;
  Timer? _espera;
  final _chaveFormulario = GlobalKey();

  late final Sessao _s = ref.read(sessaoProvider);

  @override
  void initState() {
    super.initState();
    _categoria = _s.categorias.firstOrNull?.id;
    _restaurar();
    _iniciar();
  }

  List<TextEditingController> get _camposForm => [_nome, _codigo, _custo, _min, _max, _venda, _estMin, _estAtual, _peso, _lote, _desc];

  // v1: ao voltar para a tela, os filtros do catálogo continuavam e o produto em edição seguia no formulário,
  // com o que já tinha sido digitado (sem edição, o formulário era limpo).
  void _restaurar() {
    final m = _s.memoria;
    _busca.text = (m['prod.busca'] as String?) ?? '';
    _filtroCategoria = m['prod.categoria'] as int?;
    _status = (m['prod.status'] as String?) ?? 'Ativo';
    final f = m['prod.form'];
    if (f is! Map) return;
    _editando = f['editando'] as Produto?;
    final textos = f['textos'] as List<String>;
    for (var i = 0; i < textos.length; i++) {
      _camposForm[i].text = textos[i];
    }
    _unidade = f['unidade'] as String;
    _categoria = f['categoria'] as int?;
    _validade = f['validade'] as String;
    _imagemBytes = f['imagemBytes'] as Uint8List?;
    _imagemData = f['imagemData'] as String?;
  }

  @override
  void deactivate() {
    _s.memoria
      ..['prod.busca'] = _busca.text
      ..['prod.categoria'] = _filtroCategoria
      ..['prod.status'] = _status
      ..['prod.form'] = _editando == null
          ? null
          : {'editando': _editando, 'textos': [for (final c in _camposForm) c.text], 'unidade': _unidade, 'categoria': _categoria, 'validade': _validade, 'imagemBytes': _imagemBytes, 'imagemData': _imagemData};
    super.deactivate();
  }

  Future<void> _iniciar() async {
    if (_s.categorias.isEmpty) await tentar(_s.carregarCategorias);
    if (mounted && _categoria == null) setState(() => _categoria = _s.categorias.firstOrNull?.id);
    await _carregar();
    final id = widget.abrirId;
    if (id != null) {
      final r = await tentar(() => _s.api.get('/api/products/$id'));
      if (r != null && mounted) _preencher(Produto.deJson(Json.from(r['product'] as Map)));
    }
  }

  @override
  void dispose() {
    _espera?.cancel();
    for (final c in [_nome, _codigo, _custo, _min, _max, _venda, _estMin, _estAtual, _peso, _lote, _desc, _busca]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final r = await _s.api.get('/api/products', query: {'q': _busca.text.trim(), 'category': _filtroCategoria?.toString(), 'status': _status});
      if (!mounted) return;
      setState(() {
        _lista = listaJson(r['products']).map(Produto.deJson).toList();
        _falhou = false;
      });
    } catch (_) {
      if (mounted) setState(() => _falhou = true);
    }
  }

  void _limparErros() => _erroNome = _erroVenda = _erroEstMin = _erroEstAtual = _erroDesc = false;

  void _limpar() => setState(() {
        _editando = null;
        _imagemBytes = null;
        _imagemData = null;
        for (final c in [_nome, _codigo, _custo, _min, _max, _venda, _estMin, _estAtual, _peso, _lote, _desc]) {
          c.clear();
        }
        _unidade = 'UN';
        _validade = '';
        _categoria = _s.categorias.firstOrNull?.id;
        _limparErros();
      });

  String _txt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString().replaceAll('.', ',');

  void _preencher(Produto p) {
    _preencherCampos(p);
    // v1: rola até o formulário (no celular o catálogo fica embaixo).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _chaveFormulario.currentContext;
      if (c != null && c.mounted) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 300));
    });
  }

  void _preencherCampos(Produto p) => setState(() {
        _editando = p;
        _imagemBytes = null;
        _imagemData = null;
        _nome.text = p.nome;
        _codigo.text = p.codigo;
        _custo.text = _txt(p.custo);
        _min.text = _txt(p.minimo);
        _max.text = _txt(p.maximo);
        _venda.text = _txt(p.venda);
        _estMin.text = _txt(p.estoqueMinimo);
        _estAtual.text = _txt(p.estoque);
        _peso.text = p.peso;
        _unidade = unidades.contains(p.unidade) ? p.unidade : 'UN';
        _categoria = p.idCategoria;
        _lote.text = p.lote;
        _validade = p.validade;
        _desc.text = p.descricao;
        _limparErros();
      });

  bool _validar() {
    _limparErros();
    final erros = <String>[];
    void erro(String m, void Function() marca) {
      marca();
      erros.add(m);
    }

    final venda = lerNumero(_venda.text);
    if (_nome.text.trim().length < 2) erro('Informe o nome do produto.', () => _erroNome = true);
    if (venda == null || venda <= 0) {
      erro('O preço de venda deve ser maior que zero.', () => _erroVenda = true);
    } else {
      final min = lerNumero(_min.text) ?? venda * .8;
      final max = lerNumero(_max.text) ?? venda * 1.3;
      if (min > venda || venda > max) erro('O preço de venda deve estar entre o preço mínimo e o máximo.', () => _erroVenda = true);
    }
    final inteiro = !aceitaFracao(_unidade);
    final eMin = lerNumero(_estMin.text);
    if (eMin == null || eMin < 0) {
      erro('Informe o estoque mínimo (zero ou mais).', () => _erroEstMin = true);
    } else if (inteiro && eMin != eMin.roundToDouble()) {
      erro('Produtos em $_unidade só aceitam estoque mínimo inteiro.', () => _erroEstMin = true);
    }
    if (_editando == null && _estAtual.text.trim().isNotEmpty) {
      final eAt = lerNumero(_estAtual.text);
      if (eAt == null || eAt < 0) {
        erro('O estoque atual não pode ser negativo.', () => _erroEstAtual = true);
      } else if (inteiro && eAt != eAt.roundToDouble()) {
        erro('Produtos em $_unidade só aceitam estoque inteiro.', () => _erroEstAtual = true);
      }
    }
    final d = _desc.text.trim().length;
    if (d < 10 || d > 5000) erro('A descrição deve ter entre 10 e 5000 caracteres.', () => _erroDesc = true);
    setState(() {});
    if (erros.isNotEmpty) avisar(erros.first, tipo: TipoAviso.erro);
    return erros.isEmpty;
  }

  Future<void> _salvar({required bool continuar}) async {
    if (!_validar()) return;
    Object n(TextEditingController c) => lerNumero(c.text) ?? '';
    final corpo = <String, dynamic>{
      'nome_produto': _nome.text.trim(),
      'codigo_barras': _codigo.text.trim(),
      'descricao': _desc.text.trim(),
      'unidade': _unidade,
      'peso': _peso.text.trim(),
      'preco_custo': n(_custo),
      'preco_venda': n(_venda),
      'preco_min': n(_min),
      'preco_max': n(_max),
      'estoque_minimo': n(_estMin),
      // Saldo de produto existente só muda por movimentação.
      if (_editando == null) 'quantidade_estoque': n(_estAtual),
      'id_categoria': _categoria,
      'lote': _lote.text.trim(),
      'validade': _validade,
      if (_imagemData != null) 'imagem_data': _imagemData,
    };
    setState(() => _salvando = true);
    final editando = _editando;
    final r = await tentar(() => editando != null ? _s.api.put('/api/products/${editando.id}', corpo) : _s.api.post('/api/products', corpo));
    if (!mounted) return;
    setState(() => _salvando = false);
    if (r == null) return;
    avisar(r['message'].toString(), tipo: TipoAviso.sucesso);
    await _carregar();
    if (continuar) {
      _preencher(Produto.deJson(Json.from(r['product'] as Map)));
    } else {
      _limpar();
    }
  }

  // Enter em um campo do formulário equivale ao botão "✓ Confirmar" (submit do <form> no v1).
  void _enviarForm(String _) {
    if (!_salvando) _salvar(continuar: false);
  }

  Future<void> _escolherImagem() async {
    final arquivos = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'gif']);
    final f = arquivos.firstOrNull;
    if (f == null) return;
    final bytes = await f.readAsBytes();
    if (!mounted) return;
    if (bytes.length > 2 * 1024 * 1024) {
      avisar('A imagem deve ter no máximo 2 MB.', tipo: TipoAviso.erro);
      return;
    }
    final mime = const {'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'webp': 'image/webp', 'gif': 'image/gif'}[(f.extension ?? '').toLowerCase()];
    if (mime == null) {
      avisar('Formato inválido. Use PNG, JPG, WEBP ou GIF.', tipo: TipoAviso.erro);
      return;
    }
    setState(() {
      _imagemBytes = bytes;
      _imagemData = 'data:$mime;base64,${base64Encode(bytes)}';
    });
  }

  Future<void> _mudarStatus(Produto p, String status) async {
    if (status == 'Inativo' && !await confirmar(context, 'Inativar "${p.nome}"? Ele deixará de aparecer no catálogo e no caixa, mas o histórico de vendas e movimentações será preservado.', ok: 'Inativar', perigo: true)) return;
    final r = await tentar(() => _s.api.patch('/api/products/${p.id}/status', {'status': status}));
    if (r == null) return;
    avisar(r['message'].toString(), tipo: TipoAviso.sucesso);
    if (_editando?.id == p.id) _limpar();
    await _carregar();
  }

  Widget _botaoAcao(String t, VoidCallback? f, {required Color fundo, required Color frente, required Color borda}) => Semantics(
        button: true,
        label: t,
        excludeSemantics: true,
        child: Material(
          color: fundo,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: BorderSide(color: borda)),
          child: InkWell(
            onTap: f,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8), child: Text(t, style: TextStyle(color: frente, fontSize: 14.1, fontWeight: FontWeight.w700))),
          ),
        ),
      );

  Widget _colunaFoto() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(
          child: Container(
            width: 120,
            height: 90,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFD4D4D8)), borderRadius: BorderRadius.circular(4)),
            // Em edição, a ilustração é a da categoria salva (no v1 trocar a categoria só muda a prévia de produto novo).
            child: ImagemProduto(bytes: _imagemBytes, url: _imagemBytes == null && _editando?.imagem.isNotEmpty == true ? _s.api.urlDoArquivo(_editando!.imagem) : null, idCategoria: _editando?.idCategoria ?? _categoria, tamanhoEmoji: 48),
          ),
        ),
        const SizedBox(height: 6),
        Semantics(
          button: true,
          label: 'Upload image',
          excludeSemantics: true,
          child: Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: const BorderSide(color: Color(0xFFD4D4D8))),
            child: InkWell(
              onTap: _escolherImagem,
              child: const Padding(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: Text('📷 Upload image', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF111827)))),
            ),
          ),
        ),
        const SizedBox(height: 14),
        // Em produto cadastrado, o saldo muda só por entrada, saída ou conferência.
        Campo(_estAtual, 'Estoque Atual Inicial', figma: true, dica: '10', numerico: true, somenteLeitura: _editando != null, erro: _erroEstAtual, aoEnviar: _enviarForm),
        const SizedBox(height: 14),
        Campo(_lote, 'Lote', figma: true, dica: '546320', max: 40, aoEnviar: _enviarForm),
        const SizedBox(height: 14),
        CampoData(rotulo: 'Validade', figma: true, emLinha: false, valor: _validade, aoMudar: (v) => setState(() => _validade = v)),
      ]);

  Widget _formulario(Sessao s, bool estreita) {
    const g = SizedBox(height: 10);
    final col1 = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Campo(_nome, 'Nome do Produto *', figma: true, dica: 'Pão de Queijo', max: 200, erro: _erroNome, aoEnviar: _enviarForm),
      g,
      Campo(_codigo, 'Código', figma: true, dica: '78910001', max: 100, aoEnviar: _enviarForm),
      g,
      Campo(_custo, 'Preço custo', figma: true, dica: '1.20', numerico: true, aoEnviar: _enviarForm),
      g,
      Campo(_min, 'Preço Min', figma: true, dica: '2.50', numerico: true, aoEnviar: _enviarForm),
      g,
      Campo(_estMin, 'Estoque Min *', figma: true, dica: '15', numerico: true, erro: _erroEstMin, aoEnviar: _enviarForm),
    ]);
    final col2 = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Campo(_peso, 'Peso', figma: true, dica: '50g', max: 30, aoEnviar: _enviarForm),
      g,
      Escolha<String>(rotulo: 'Unidade', figma: true, valor: _unidade, opcoes: [for (final u in unidades) DropdownMenuItem(value: u, child: Text(u))], aoMudar: (v) => setState(() => _unidade = v ?? 'UN')),
      g,
      Campo(_venda, 'Preço Venda *', figma: true, dica: '3.50', numerico: true, erro: _erroVenda, aoEnviar: _enviarForm),
      g,
      Campo(_max, 'Preço Max', figma: true, dica: '5.00', numerico: true, aoEnviar: _enviarForm),
      g,
      Escolha<int>(rotulo: 'Categoria *', figma: true, valor: _categoria, opcoes: [for (final c in s.categorias) DropdownMenuItem(value: c.id, child: Text(c.nome, overflow: TextOverflow.ellipsis))], aoMudar: (v) => setState(() => _categoria = v)),
    ]);
    final colunas = estreita
        ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [col1, const SizedBox(height: 12), col2, const SizedBox(height: 12), _colunaFoto()])
        : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: col1), const SizedBox(width: 12), Expanded(child: col2), const SizedBox(width: 12), SizedBox(width: 130, child: _colunaFoto())]);
    return Cartao(
      key: _chaveFormulario,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        colunas,
        const SizedBox(height: 10),
        Campo(_desc, 'Descrição do Produto (Mínimo 10, Máximo 5000 caracteres)', figma: true, dica: 'Insira os detalhes e características técnicas do produto...', linhas: 2, max: 5000, minContador: 10, erro: _erroDesc),
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 8, children: [
          _botaoAcao(_editando == null ? '✓ Confirmar' : '✓ Confirmar alterações', _salvando ? null : () => _salvar(continuar: false), fundo: Cores.primaria, frente: Colors.white, borda: const Color(0xFF1D4ED8)),
          _botaoAcao('💾 Salvar', _salvando ? null : () => _salvar(continuar: true), fundo: Colors.white, frente: const Color(0xFF1F2429), borda: const Color(0xFFD4D4D8)),
          _botaoAcao('⊗ Cancelar', _limpar, fundo: const Color(0xFFF1F5F9), frente: const Color(0xFF475569), borda: const Color(0xFFD4D4D8)),
        ]),
      ]),
    );
  }

  Widget _catalogo(Sessao s) => Cartao(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const TituloH3('Buscar Produto Cadastrado'),
          Campo(_busca, 'Buscar produtos no catálogo', semRotulo: true, figma: true, dica: 'Código ou Nome do Produto', aoMudar: (_) {
            _espera?.cancel();
            _espera = Timer(const Duration(milliseconds: 250), _carregar);
          }),
          const SizedBox(height: 10),
          Wrap(spacing: 12, runSpacing: 8, children: [
            Escolha<int?>(
              rotulo: 'Filtrar catálogo por categoria',
              semRotulo: true,
              largura: 170,
              valor: _filtroCategoria,
              opcoes: [const DropdownMenuItem(value: null, child: Text('Todas as categorias', overflow: TextOverflow.ellipsis)), for (final c in s.categorias) DropdownMenuItem(value: c.id, child: Text(c.nome, overflow: TextOverflow.ellipsis))],
              aoMudar: (v) {
                setState(() => _filtroCategoria = v);
                _carregar();
              },
            ),
            Escolha<String>(
              rotulo: 'Filtrar catálogo por situação',
              semRotulo: true,
              largura: 90,
              valor: _status,
              opcoes: const [DropdownMenuItem(value: 'Ativo', child: Text('Ativos')), DropdownMenuItem(value: 'Inativo', child: Text('Inativos')), DropdownMenuItem(value: 'todos', child: Text('Todos'))],
              aoMudar: (v) {
                setState(() => _status = v ?? 'Ativo');
                _carregar();
              },
            ),
          ]),
          const SizedBox(height: 8),
          Tabela<Produto>(
            itens: _lista,
            vazio: _falhou ? 'Falha ao carregar o catálogo.' : 'Nenhum produto encontrado.',
            vazioSimples: !_falhou,
            larguraMinima: 400,
            alturaMaxima: 260,
            respiro: 8,
            selecionado: (p) => p.id == _editando?.id,
            apagado: (p) => !p.ativo,
            aoTocar: (p) {
              if (p.ativo) _preencher(p);
            },
            colunas: [
              Coluna('Cód', (p) => Text(p.codigo), flex: 5),
              Coluna('Produto', (p) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(p.nome, style: const TextStyle(fontWeight: FontWeight.w700)), Pequeno('${p.unidade} - ${p.peso}${p.ativo ? '' : ' • Inativo'}')]), flex: 5),
              Coluna('Preço Venda', (p) => Text('R\$ ${p.venda.toStringAsFixed(2)}'), flex: 4),
              Coluna('Estoque', (p) => Text(quantidade(p.estoque), style: const TextStyle(fontWeight: FontWeight.w700)), flex: 4),
              Coluna(
                'Ações',
                (p) => p.ativo
                    // .btn.btn-sm com emoji (não são .btn-icon)
                    ? Wrap(spacing: 4, runSpacing: 2, children: [
                        Botao('✏️', () => _preencher(p), tipo: TipoBotao.secundario, pequeno: true, dica: 'Alterar produto'),
                        Botao('🗑️', () => _mudarStatus(p, 'Inativo'), tipo: TipoBotao.perigo, pequeno: true, dica: 'Inativar produto'),
                      ])
                    : Botao('↺ Reativar', () => _mudarStatus(p, 'Ativo'), tipo: TipoBotao.secundario, pequeno: true),
                flex: 4,
              ),
            ],
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessaoProvider);
    final largura = MediaQuery.sizeOf(context).width;
    return Pagina(
      cabecalho: CabecalhoAba('Cadastro de Produto', acoes: [Botao('Limpar Formulário', _limpar, tipo: TipoBotao.secundario)]),
      filhos: [
        if (largura <= 1100)
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_formulario(s, largura <= 900), const SizedBox(height: 16), _catalogo(s)])
        else
          // grid 1.4fr 1fr: os dois cartões com a mesma altura
          AlturaIgual(fracaoEsquerda: 1.4 / 2.4, esquerda: _formulario(s, false), direita: _catalogo(s)),
      ],
    );
  }
}
