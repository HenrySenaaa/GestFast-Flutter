// Configuração: parâmetros, minha conta, acessibilidade e logs, na mesma ordem do v1.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/regras.dart';
import '../core/sessao.dart';
import '../core/tema.dart';
import '../models/modelos.dart';
import '../widgets/comuns.dart';

Future<void> abrirTrocaSenha(BuildContext context, Sessao s) => abrirModal<void>(context, (_) => _TrocaSenha(s));

class _TrocaSenha extends StatefulWidget {
  const _TrocaSenha(this.s);
  final Sessao s;
  @override
  State<_TrocaSenha> createState() => _TrocaSenhaState();
}

class _TrocaSenhaState extends State<_TrocaSenha> {
  final _atual = TextEditingController(), _nova = TextEditingController(), _conf = TextEditingController();
  bool _ocupado = false;

  @override
  void dispose() {
    _atual.dispose();
    _nova.dispose();
    _conf.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_ocupado) return;
    if (_nova.text != _conf.text) {
      avisar('A confirmação não confere com a nova senha.', tipo: TipoAviso.erro);
      return;
    }
    setState(() => _ocupado = true);
    final r = await tentar(() => widget.s.api.post('/api/auth/change-password', {'senha_atual': _atual.text, 'nova_senha': _nova.text}));
    if (!mounted) return;
    setState(() => _ocupado = false);
    if (r != null) {
      avisar(r['message'].toString(), tipo: TipoAviso.sucesso);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => Modal(
        titulo: 'Alterar minha senha',
        acoes: [
          Botao('Cancelar', () => Navigator.pop(context), tipo: TipoBotao.secundario),
          Botao('Salvar senha', _ocupado ? null : _enviar),
        ],
        filhos: [
          // <form>: Enter em qualquer campo envia, como no v1.
          Campo(_atual, 'Senha atual', senha: true, autofoco: true, autofill: const [AutofillHints.password], aoEnviar: (_) => _enviar()),
          espacoCampo,
          Campo(_nova, 'Nova senha (mínimo 6 caracteres)', senha: true, autofill: const [AutofillHints.newPassword], aoEnviar: (_) => _enviar()),
          espacoCampo,
          Campo(_conf, 'Confirmar nova senha', senha: true, autofill: const [AutofillHints.newPassword], aoEnviar: (_) => _enviar()),
        ],
      );
}

class ConfiguracoesTela extends ConsumerStatefulWidget {
  const ConfiguracoesTela({super.key});
  @override
  ConsumerState<ConfiguracoesTela> createState() => _ConfiguracoesTelaState();
}

class _ConfiguracoesTelaState extends ConsumerState<ConfiguracoesTela> {
  final _estab = TextEditingController(), _desconto = TextEditingController(), _intervalo = TextEditingController(), _validade = TextEditingController(), _servidor = TextEditingController();
  bool _simCartao = false, _simFornecedor = false, _salvando = false;
  List<Json> _logs = [];

  late final Sessao _s = ref.read(sessaoProvider);

  @override
  void initState() {
    super.initState();
    _servidor.text = _s.servidor;
    _iniciar();
  }

  @override
  void dispose() {
    for (final c in [_estab, _desconto, _intervalo, _validade, _servidor]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _iniciar() async {
    await _s.sincronizar();
    if (!mounted) return;
    _preencher(_s.config);
    await _carregarLogs();
  }

  void _preencher(Configuracoes? c) {
    if (c == null) return;
    setState(() {
      _estab.text = c.estabelecimento;
      _desconto.text = quantidade(c.descontoMaximo);
      _intervalo.text = '${c.intervaloSeg}';
      _validade.text = '${c.diasValidade}';
      _simCartao = c.simularCartao;
      _simFornecedor = c.simularFornecedor;
    });
  }

  Future<void> _carregarLogs() async {
    if (!_s.pode('logs:ver')) return;
    final r = await tentar(() => _s.api.get('/api/logs', query: {'limit': '150'}));
    if (r != null && mounted) setState(() => _logs = listaJson(r['logs']));
  }

  Future<void> _salvar() async {
    if (_salvando) return;
    setState(() => _salvando = true);
    final r = await tentar(() => _s.api.put('/api/settings', {
          'estabelecimento': _estab.text,
          // Como o Number('') do v1: campo vazio vai como 0 (o servidor valida os limites).
          'descontoMaximoPercent': lerNumero(_desconto.text) ?? 0,
          'intervaloAtualizacaoSeg': lerNumero(_intervalo.text) ?? 0,
          'diasAlertaValidade': lerNumero(_validade.text) ?? 0,
          'simularCartaoNegado': _simCartao,
          'simularFornecedorIndisponivel': _simFornecedor,
        }));
    if (!mounted) return;
    setState(() => _salvando = false);
    if (r == null) return;
    _s.aplicarConfig(Configuracoes.deJson(Json.from(r['settings'] as Map)));
    avisar(r['message'].toString(), tipo: TipoAviso.sucesso);
    await _carregarLogs();
  }

  Future<void> _salvarServidor() async {
    try {
      await _s.definirServidor(_servidor.text);
      avisar('Endereço do servidor salvo.', tipo: TipoAviso.sucesso);
    } on FormatException catch (e) {
      avisar(e.message, tipo: TipoAviso.erro);
    }
  }

  Widget _parametros(Sessao s) {
    final c = s.config;
    if (!s.pode('config:gerir')) {
      // <p> de 16px, sem margem entre eles (.config-details-list não tem estilo próprio).
      Widget p(String r, String v) => Text.rich(TextSpan(style: TextStyle(fontSize: 16, color: Cores.texto), children: [TextSpan(text: '$r: ', style: const TextStyle(fontWeight: FontWeight.w700)), TextSpan(text: v)]));
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        p('Estabelecimento', c?.estabelecimento ?? '-'),
        p('Desconto máximo no caixa', '${quantidade(c?.descontoMaximo)}% do subtotal'),
        p('Aviso de validade', '${c?.diasValidade ?? '-'} dia(s) antes de vencer'),
        Text('Somente o Administrador pode alterar os parâmetros.', style: TextStyle(color: Cores.fraco, fontSize: 16)),
      ]);
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 8),
        // <form id="form-config">: Enter em qualquer campo salva, como no v1.
        Campo(_estab, 'Estabelecimento', max: 150, aoEnviar: (_) => _salvar()),
        espacoCampo,
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: Campo(_desconto, 'Desconto máximo no caixa (% do subtotal)', numerico: true, aoEnviar: (_) => _salvar())),
          const SizedBox(width: 10),
          Expanded(child: Campo(_intervalo, 'Atualização do painel (segundos)', numerico: true, aoEnviar: (_) => _salvar())),
        ]),
        espacoCampo,
        Row(children: [
          Expanded(child: Campo(_validade, 'Aviso de validade (dias de antecedência)', numerico: true, aoEnviar: (_) => _salvar())),
          const SizedBox(width: 10),
          const Expanded(child: SizedBox()),
        ]),
        const SizedBox(height: 14),
        // <fieldset class="cfg-sim">
        Stack(clipBehavior: Clip.none, children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
            decoration: BoxDecoration(border: Border.all(color: Cores.bordaCartao), borderRadius: BorderRadius.circular(4)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Marcador('Operadora de cartão nega as transações', valor: _simCartao, aoMudar: (v) => setState(() => _simCartao = v)),
              const SizedBox(height: 6),
              Marcador('Sistema do fornecedor fora do ar', valor: _simFornecedor, aoMudar: (v) => setState(() => _simFornecedor = v)),
            ]),
          ),
          Positioned(
            left: 8,
            top: -2,
            child: Container(
              color: Cores.cartao,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: const Text('Simulação de falhas externas (para testes e demonstração)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        // .btn sem .btn-block, esticado pelo flex em coluna do .config-form: largura toda e texto à esquerda.
        Botao('💾 Salvar parâmetros', _salvando ? null : _salvar, esticado: true),
      ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessaoProvider);
    final u = s.usuario;
    return Pagina(
      cabecalho: const CabecalhoAba('Configuração'),
      filhos: [
        Cartao(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const TituloH3('Parâmetros Operacionais'), _parametros(s)])),
        Cartao(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const TituloH3('Minha conta'),
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 10),
              child: Text.rich(TextSpan(style: TextStyle(fontSize: 14.1, color: Cores.texto), children: [TextSpan(text: u?.nome, style: const TextStyle(fontWeight: FontWeight.w700)), TextSpan(text: ' • ${u?.email} • Perfil: ${nomePerfil(u?.perfil)}')])),
            ),
            Align(alignment: Alignment.centerLeft, child: Botao('🔑 Alterar minha senha', () => abrirTrocaSenha(context, s), tipo: TipoBotao.secundario)),
          ]),
        ),
        Cartao(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const TituloH3('Acessibilidade'),
            Padding(padding: const EdgeInsets.only(top: 6, bottom: 10), child: Text('Ajuste o tamanho do texto e o contraste. As preferências ficam salvas neste dispositivo.', style: TextStyle(fontSize: 14.1, color: Cores.texto))),
            Wrap(spacing: 8, runSpacing: 8, children: [
              Botao('A- Diminuir texto', () => s.mudarZoom(-1), tipo: TipoBotao.secundario),
              Botao('A+ Aumentar texto', () => s.mudarZoom(1), tipo: TipoBotao.secundario),
              Botao('◐ Alto contraste', s.alternarContraste, tipo: TipoBotao.secundario),
              Botao('Restaurar padrão', s.restaurarAcessibilidade, tipo: TipoBotao.secundario),
            ]),
          ]),
        ),
        // Só nos apps nativos: na web o servidor é o mesmo endereço da página.
        if (!kIsWeb)
          Cartao(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const TituloH3('Servidor'),
              Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.end, children: [
                Campo(_servidor, 'Endereço do servidor', largura: 320, dica: 'http://192.168.0.10:3000'),
                Botao('Salvar endereço', _salvarServidor, tipo: TipoBotao.secundario),
              ]),
            ]),
          ),
        if (s.pode('logs:ver'))
          Cartao(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TituloCartao('Registro de atividades (logs)', h3: true, direita: Botao('🔄 Atualizar', _carregarLogs, tipo: TipoBotao.secundario, pequeno: true)),
              Tabela<Json>(
                itens: _logs,
                vazio: 'Sem registros.',
                larguraMinima: 820,
                alturaMaxima: 420,
                colunas: [
                  Coluna('Data/hora', (l) => Text(_dataLog('${l['ts']}')), flex: 3),
                  Coluna('Nível', (l) => switch ('${l['nivel']}') { 'ERRO' => const Selo.perigo('ERRO'), 'AVISO' => const Selo.alerta('AVISO'), final n => Selo(n) }),
                  Coluna('Evento', (l) => Text('${l['evento']}'), flex: 3),
                  Coluna('Usuário', (l) => Text(l['usuario'] == null ? '-' : '${l['usuario']}'), flex: 4),
                  Coluna('Detalhes', (l) => Text(_detalhesLog(l), style: const TextStyle(fontSize: 13.1)), flex: 5),
                ],
              ),
            ]),
          ),
      ],
    );
  }

  String _dataLog(String ts) {
    final d = DateTime.tryParse(ts)?.toLocal();
    if (d == null) return '';
    String p(int n) => n.toString().padLeft(2, '0');
    return '${dataBR(dataISO(d))}, ${p(d.hour)}:${p(d.minute)}:${p(d.second)}';
  }

  String _detalhesLog(Json l) {
    final resto = Map<String, dynamic>.from(l)..removeWhere((k, _) => const ['ts', 'nivel', 'evento', 'usuario'].contains(k));
    return resto.isEmpty ? '' : jsonEncode(resto);
  }
}
