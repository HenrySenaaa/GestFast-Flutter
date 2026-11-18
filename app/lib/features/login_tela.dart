// Login, recuperação e redefinição de senha, com o visual do v1.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/sessao.dart';
import '../core/tema.dart';
import '../widgets/casca.dart';
import '../widgets/comuns.dart';

enum _Painel { login, esqueci, redefinir }

class LoginTela extends ConsumerStatefulWidget {
  const LoginTela({super.key, this.codigoRedefinicao = '', this.redefinir = false});
  final String codigoRedefinicao;
  final bool redefinir;
  @override
  ConsumerState<LoginTela> createState() => _LoginTelaState();
}

class _LoginTelaState extends ConsumerState<LoginTela> {
  late _Painel _painel = widget.redefinir ? _Painel.redefinir : _Painel.login;
  final _email = TextEditingController();
  final _senha = TextEditingController();
  final _servidor = TextEditingController();
  late final _codigo = TextEditingController(text: widget.codigoRedefinicao);
  final _nova = TextEditingController();
  final _nova2 = TextEditingController();
  bool _lembrar = false, _ocupado = false, _erroEmail = false, _erroSenha = false;
  String? _erro, _sucesso;
  final _focoSenha = FocusNode();

  @override
  void initState() {
    super.initState();
    final s = ref.read(sessaoProvider);
    _servidor.text = s.servidor;
    _erro = s.avisoLogin;
  }

  @override
  void dispose() {
    for (final c in [_email, _senha, _servidor, _codigo, _nova, _nova2]) {
      c.dispose();
    }
    _focoSenha.dispose();
    super.dispose();
  }

  void _mensagem({String? erro, String? sucesso}) => setState(() {
        _erro = erro;
        _sucesso = sucesso;
      });

  // Cada envio limpa a mensagem anterior: erro nunca herda a cor de um sucesso.
  Future<void> _rodar(Future<void> Function(Sessao) acao) async {
    final s = ref.read(sessaoProvider);
    _mensagem();
    setState(() => _ocupado = true);
    try {
      if (!kIsWeb || _servidor.text.trim().isNotEmpty) await s.definirServidor(_servidor.text);
      await acao(s);
    } on FormatException catch (e) {
      _mensagem(erro: e.message);
    } catch (e) {
      _mensagem(erro: e.toString());
      // v1: a senha é apagada e o cursor volta para ela.
      _senha.clear();
      if (_painel == _Painel.login) _focoSenha.requestFocus();
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _entrar() async {
    setState(() {
      _erroEmail = _email.text.trim().isEmpty;
      _erroSenha = !_erroEmail && _senha.text.isEmpty;
    });
    if (_erroEmail || _erroSenha) {
      _mensagem(erro: 'Preencha o e-mail e a senha para continuar.');
      return;
    }
    await _rodar((s) => s.entrar(_email.text.trim(), _senha.text, _lembrar));
  }

  Future<void> _esqueci() async {
    // v1: e-mail vazio só marca o campo em vermelho, sem mensagem.
    setState(() => _erroEmail = _email.text.trim().isEmpty);
    if (_erroEmail) return;
    await _rodar((s) async {
      final r = await s.api.post('/api/auth/forgot', {'email': _email.text.trim()});
      _mensagem(sucesso: r['message'].toString());
    });
  }

  Future<void> _redefinir() async {
    if (_nova.text != _nova2.text) {
      _mensagem(erro: 'As senhas não conferem.');
      return;
    }
    if (_codigo.text.trim().isEmpty) {
      _mensagem(erro: 'Informe o código de redefinição.');
      return;
    }
    await _rodar((s) async {
      final r = await s.api.post('/api/auth/reset', {'token': _codigo.text.trim(), 'senha': _nova.text});
      _nova.clear();
      _nova2.clear();
      _codigo.clear();
      setState(() => _painel = _Painel.login);
      _mensagem(sucesso: r['message'].toString());
    });
  }

  void _voltar() {
    _mensagem();
    if (widget.redefinir) {
      context.go('/login');
    } else {
      setState(() => _painel = _Painel.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(sessaoProvider);
    return Scaffold(
      backgroundColor: Cores.escuro,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 30),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(color: Color(0x59000000), blurRadius: 40, offset: Offset(0, 20))]),
              child: AutofillGroup(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Center(child: Logo(cor: Cores.escuro, centralizado: true)),
                  const SizedBox(height: 4),
                  const Text('Gestão de estoque e vendas para panificadoras', textAlign: TextAlign.center, style: TextStyle(fontSize: 13.6, color: Color(0xFF52525B))),
                  const SizedBox(height: 20),
                  ...switch (_painel) { _Painel.login => _formLogin(), _Painel.esqueci => _formEsqueci(), _Painel.redefinir => _formRedefinir() },
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _mensagens() => [
        if (_erro != null) _Faixa(_erro!, fundo: Cores.perigoClaro, cor: Cores.perigo),
        if (_sucesso != null) _Faixa(_sucesso!, fundo: Cores.sucessoClaro, cor: Cores.sucessoEscuro),
      ];

  // Só nos apps nativos: na web o servidor é o mesmo endereço da página.
  List<Widget> _campoServidor() => kIsWeb
      ? const []
      : [Campo(_servidor, 'Servidor', dica: 'http://192.168.0.10:3000'), espacoCampo];

  Widget _link(String texto, VoidCallback acao) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Center(
          child: Semantics(
            button: true,
            label: texto,
            excludeSemantics: true,
            child: InkWell(onTap: acao, child: Text(texto, style: const TextStyle(fontSize: 13.4, color: Cores.primaria, decoration: TextDecoration.underline, decorationColor: Cores.primaria))),
          ),
        ),
      );

  List<Widget> _formLogin() => [
        ..._campoServidor(),
        Campo(_email, 'E-mail', dica: 'seu@email.com', autofoco: true, erro: _erroEmail, autofill: const [AutofillHints.username], aoEnviar: (_) => _entrar()),
        espacoCampo,
        Campo(_senha, 'Senha', dica: 'Sua senha', senha: true, foco: _focoSenha, erro: _erroSenha, autofill: const [AutofillHints.password], aoEnviar: (_) => _entrar()),
        const SizedBox(height: 14),
        Marcador('Manter-me conectado', valor: _lembrar, aoMudar: (v) => setState(() => _lembrar = v)),
        const SizedBox(height: 12),
        ..._mensagens(),
        Botao('Entrar', _ocupado ? null : _entrar, bloco: true),
        _link('Esqueci minha senha', () {
          _mensagem();
          setState(() => _painel = _Painel.esqueci);
        }),
      ];

  List<Widget> _formEsqueci() => [
        const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('Informe o e-mail cadastrado. Enviaremos um link para redefinir sua senha.', style: TextStyle(fontSize: 13.6, color: Color(0xFF52525B)))),
        ..._campoServidor(),
        Campo(_email, 'E-mail cadastrado', dica: 'seu@email.com', autofoco: true, erro: _erroEmail, aoEnviar: (_) => _esqueci()),
        espacoCampo,
        ..._mensagens(),
        Botao('Enviar link de redefinição', _ocupado ? null : _esqueci, bloco: true),
        _link('Já tenho o código', () {
          _mensagem();
          setState(() => _painel = _Painel.redefinir);
        }),
        _link('Voltar ao login', _voltar),
      ];

  List<Widget> _formRedefinir() => [
        const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('Defina uma nova senha de acesso (mínimo 6 caracteres).', style: TextStyle(fontSize: 13.6, color: Color(0xFF52525B)))),
        ..._campoServidor(),
        if (widget.codigoRedefinicao.isEmpty) ...[Campo(_codigo, 'Código de redefinição'), espacoCampo],
        Campo(_nova, 'Nova senha', senha: true, autofill: const [AutofillHints.newPassword]),
        espacoCampo,
        Campo(_nova2, 'Confirmar nova senha', senha: true, autofill: const [AutofillHints.newPassword], aoEnviar: (_) => _redefinir()),
        espacoCampo,
        ..._mensagens(),
        Botao('Redefinir senha', _ocupado ? null : _redefinir, bloco: true),
        _link('Voltar ao login', _voltar),
      ];
}

class _Faixa extends StatelessWidget {
  const _Faixa(this.texto, {required this.fundo, required this.cor});
  final String texto;
  final Color fundo, cor;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: fundo, borderRadius: BorderRadius.circular(4)),
        child: Text(texto, style: TextStyle(color: cor, fontSize: 13.4, fontWeight: FontWeight.w600)),
      );
}
