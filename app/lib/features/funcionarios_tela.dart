// Funcionários: cadastrar, alterar, trocar perfil e ativar/desativar, igual ao v1.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/regras.dart';
import '../core/sessao.dart';
import '../models/modelos.dart';
import '../widgets/comuns.dart';

class FuncionariosTela extends ConsumerStatefulWidget {
  const FuncionariosTela({super.key, this.buscaInicial = ''});
  final String buscaInicial;
  @override
  ConsumerState<FuncionariosTela> createState() => _FuncionariosTelaState();
}

class _FuncionariosTelaState extends ConsumerState<FuncionariosTela> {
  List<Usuario> _usuarios = [];
  List<Json> _perfis = [];
  bool _falhou = false;
  // v1: os filtros continuavam como estavam ao voltar para a tela.
  late final _m = (_s.memoria['func'] as Map<String, Object?>?) ?? const {};
  late int? _perfil = _m['perfil'] as int?;
  late String _status = (_m['status'] as String?) ?? '';
  late final _busca = TextEditingController(text: widget.buscaInicial.isNotEmpty ? widget.buscaInicial : (_m['busca'] as String?) ?? '');
  Timer? _espera;

  late final Sessao _s = ref.read(sessaoProvider);

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  @override
  void dispose() {
    _s.memoria['func'] = {'perfil': _perfil, 'status': _status, 'busca': _busca.text};
    _espera?.cancel();
    _busca.dispose();
    super.dispose();
  }

  Future<void> _iniciar() async {
    final r = await tentar(() => _s.api.get('/api/profiles'));
    if (r != null && mounted) setState(() => _perfis = listaJson(r['profiles']));
    await _carregar();
  }

  Future<void> _carregar() async {
    try {
      final r = await _s.api.get('/api/users', query: {'q': _busca.text.trim(), 'id_perfil': _perfil?.toString(), 'status': _status});
      if (!mounted) return;
      setState(() {
        _usuarios = listaJson(r['users']).map(Usuario.deJson).toList();
        _falhou = false;
      });
    } catch (_) {
      if (mounted) setState(() => _falhou = true);
    }
  }

  Future<void> _formulario([Usuario? u]) async {
    final ok = await abrirModal<bool>(context, (_) => _Formulario(_s, _perfis, u));
    if (ok == true) await _carregar();
  }

  Future<void> _mudarStatus(Usuario u, String status) async {
    if (status == 'Inativo' && !await confirmar(context, 'Desativar o acesso de ${u.nome}? Ele será desconectado e não poderá entrar no sistema, mas o histórico é preservado.', ok: 'Desativar', perigo: true)) return;
    final r = await tentar(() => _s.api.patch('/api/users/${u.id}/status', {'status': status}));
    if (r != null) {
      avisar(r['message'].toString(), tipo: TipoAviso.sucesso);
      await _carregar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessaoProvider);
    return Pagina(
      cabecalho: CabecalhoAba('Funcionários', acoes: [Botao('+ Cadastrar Funcionário', () => _formulario())]),
      filhos: [
        Cartao(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            BarraFiltros(
              filhos: [
                Campo(_busca, 'Filtrar funcionários', semRotulo: true, dica: 'Filtrar por nome, login ou cargo...', largura: telaEstreita(context) ? double.infinity : 240, aoMudar: (_) {
                  _espera?.cancel();
                  _espera = Timer(const Duration(milliseconds: 250), _carregar);
                }),
                Escolha<int?>(
                  rotulo: 'Filtrar por perfil',
                  semRotulo: true,
                  largura: 160,
                  valor: _perfil,
                  opcoes: [const DropdownMenuItem(value: null, child: Text('Todos os perfis')), for (final p in _perfis) DropdownMenuItem(value: (p['id_perfil'] as num).toInt(), child: Text(nomePerfil('${p['nome_perfil']}')))],
                  aoMudar: (v) {
                    setState(() => _perfil = v);
                    _carregar();
                  },
                ),
                Escolha<String>(
                  rotulo: 'Filtrar por situação',
                  semRotulo: true,
                  largura: 170,
                  valor: _status,
                  opcoes: const [DropdownMenuItem(value: '', child: Text('Todas as situações')), DropdownMenuItem(value: 'Ativo', child: Text('Ativos')), DropdownMenuItem(value: 'Inativo', child: Text('Inativos'))],
                  aoMudar: (v) {
                    setState(() => _status = v ?? '');
                    _carregar();
                  },
                ),
              ],
              fim: Dica('${_usuarios.length} funcionário(s)'),
            ),
            Tabela<Usuario>(
              itens: _usuarios,
              vazio: _falhou ? 'Falha ao carregar os funcionários.' : 'Nenhum funcionário encontrado.',
              larguraMinima: 820,
              apagado: (u) => !u.ativo,
              colunas: [
                Coluna('Nome', (u) => Text.rich(TextSpan(children: [TextSpan(text: u.nome, style: const TextStyle(fontWeight: FontWeight.w700)), if (u.id == s.usuario?.id) const TextSpan(text: ' (você)', style: TextStyle(fontSize: 12.8, color: Color(0xFF52525B)))])), flex: 3),
                Coluna('Login (e-mail)', (u) => Text(u.email), flex: 4),
                Coluna('Cargo', (u) => Text(u.cargo.isEmpty ? '-' : u.cargo)),
                Coluna('Perfil', (u) => Text(nomePerfil(u.perfil))),
                Coluna('Situação', (u) => seloAtivo(u.status)),
                Coluna(
                  'Ações',
                  (u) => Wrap(children: [
                    BotaoIcone('✎', 'Alterar dados e perfil', () => _formulario(u)),
                    u.ativo ? BotaoIcone('⏻', 'Desativar acesso', () => _mudarStatus(u, 'Inativo'), tipo: TipoAcao.cancelar) : BotaoIcone('↺', 'Reativar acesso', () => _mudarStatus(u, 'Ativo'), tipo: TipoAcao.aceitar),
                  ]),
                ),
              ],
            ),
          ]),
        ),
      ],
    );
  }
}

class _Formulario extends StatefulWidget {
  const _Formulario(this.s, this.perfis, this.usuario);
  final Sessao s;
  final List<Json> perfis;
  final Usuario? usuario;
  @override
  State<_Formulario> createState() => _FormularioState();
}

class _FormularioState extends State<_Formulario> {
  late final _nome = TextEditingController(text: widget.usuario?.nome);
  late final _email = TextEditingController(text: widget.usuario?.email);
  late final _cargo = TextEditingController(text: widget.usuario?.cargo);
  final _senha = TextEditingController();
  late int? _perfil = widget.usuario?.idPerfil ?? (widget.perfis.firstOrNull?['id_perfil'] as num?)?.toInt();
  bool _ocupado = false, _erroNome = false, _erroEmail = false, _erroSenha = false;

  @override
  void dispose() {
    for (final c in [_nome, _email, _cargo, _senha]) {
      c.dispose();
    }
    super.dispose();
  }

  void _enviarSeLivre() {
    if (!_ocupado) _enviar();
  }

  Future<void> _enviar() async {
    final novo = widget.usuario == null;
    setState(() {
      _erroNome = _erroEmail = _erroSenha = false;
    });
    if (_nome.text.trim().length < 2) {
      setState(() => _erroNome = true);
      avisar('Informe o nome do funcionário.', tipo: TipoAviso.erro);
      return;
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim())) {
      setState(() => _erroEmail = true);
      avisar('Informe um login (e-mail) válido.', tipo: TipoAviso.erro);
      return;
    }
    if ((novo || _senha.text.isNotEmpty) && _senha.text.length < 6) {
      setState(() => _erroSenha = true);
      avisar('A senha deve ter no mínimo 6 caracteres.', tipo: TipoAviso.erro);
      return;
    }
    final corpo = {'nome': _nome.text.trim(), 'email': _email.text.trim(), 'cargo': _cargo.text.trim(), 'id_perfil': _perfil, if (_senha.text.isNotEmpty) 'senha': _senha.text};
    setState(() => _ocupado = true);
    try {
      final r = await (novo ? widget.s.api.post('/api/users', corpo) : widget.s.api.put('/api/users/${widget.usuario!.id}', corpo));
      avisar(r['message'].toString(), tipo: TipoAviso.sucesso);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      avisarErro(e);
      // v1: erro que fala do login (ex.: já cadastrado) marca o campo de e-mail.
      if (mounted && RegExp('login', caseSensitive: false).hasMatch(e.toString())) setState(() => _erroEmail = true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final novo = widget.usuario == null;
    return Modal(
      titulo: novo ? 'Cadastrar funcionário' : 'Alterar ${widget.usuario!.nome}',
      acoes: [
        Botao('Cancelar', () => Navigator.pop(context), tipo: TipoBotao.secundario),
        Botao(novo ? 'Cadastrar' : 'Salvar alterações', _ocupado ? null : _enviar),
      ],
      filhos: [
        // <form>: Enter em qualquer campo envia, como no v1.
        Campo(_nome, 'Nome completo *', max: 150, erro: _erroNome, autofoco: true, aoEnviar: (_) => _enviarSeLivre()),
        espacoCampo,
        Campo(_email, 'Login (e-mail) *', max: 150, erro: _erroEmail, aoEnviar: (_) => _enviarSeLivre()),
        espacoCampo,
        Campo(_cargo, 'Cargo', max: 100, aoEnviar: (_) => _enviarSeLivre()),
        espacoCampo,
        Escolha<int>(rotulo: 'Perfil de acesso *', valor: _perfil, opcoes: [for (final p in widget.perfis) DropdownMenuItem(value: (p['id_perfil'] as num).toInt(), child: Text(nomePerfil('${p['nome_perfil']}')))], aoMudar: (v) => setState(() => _perfil = v)),
        espacoCampo,
        Campo(_senha, novo ? 'Senha inicial * (mínimo 6 caracteres)' : 'Nova senha (deixe em branco para manter)', senha: true, erro: _erroSenha, aoEnviar: (_) => _enviarSeLivre()),
      ],
    );
  }
}
