// Estado global: usuário logado, permissões, parâmetros, categorias e preferências do aparelho.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/modelos.dart';
import 'api.dart';
import 'regras.dart';

/// Onde o token do "manter conectado" fica guardado nos apps nativos.
abstract class CofreToken {
  Future<String?> ler();
  Future<void> gravar(String token);
  Future<void> apagar();
}

class CofreSeguro implements CofreToken {
  static const _chave = 'gf_token';
  final _s = const FlutterSecureStorage();
  @override
  Future<String?> ler() => _s.read(key: _chave);
  @override
  Future<void> gravar(String token) => _s.write(key: _chave, value: token);
  @override
  Future<void> apagar() => _s.delete(key: _chave);
}

/// Em desenvolvimento, o app web roda em outra porta: --dart-define=GESTFAST_API=http://localhost:3001
const _apiPadrao = String.fromEnvironment('GESTFAST_API');

class Sessao extends ChangeNotifier {
  Sessao({ApiClient? api, CofreToken? cofre})
      : api = api ?? ApiClient(),
        _cofre = cofre ?? CofreSeguro() {
    this.api.aoExpirarSessao = () => encerrarLocal('Sua sessão expirou. Faça login novamente.');
  }

  final ApiClient api;
  final CofreToken _cofre;

  bool iniciada = false;
  Usuario? usuario;
  Set<String> permissoes = {};
  Configuracoes? config;
  String? hoje;
  List<Categoria> categorias = [];
  String? avisoLogin;

  double zoom = 1;
  bool altoContraste = false;
  String servidor = '';

  bool get logado => usuario != null;
  bool pode(String p) => permissoes.contains(p);
  String get hojeOuAparelho => hoje ?? dataISO(DateTime.now());
  int get diasValidade => config?.diasValidade ?? 3;
  String get estabelecimento => config?.estabelecimento ?? '';

  static const zooms = [1.0, 1.15, 1.3, 1.5];

  SharedPreferences? _prefs;

  Future<void> iniciar() async {
    servidor = _apiPadrao;
    api.baseUrl = servidor;
    try {
      final p = await SharedPreferences.getInstance();
      _prefs = p;
      zoom = p.getDouble('gf_zoom') ?? 1;
      altoContraste = p.getBool('gf_hc') ?? false;
      final salvo = p.getString('gf_servidor') ?? '';
      if (salvo.isNotEmpty) {
        servidor = salvo;
        api.baseUrl = salvo;
      }
    } catch (_) {
      // Sem armazenamento local, o app segue com o padrão.
    }
    final podeRestaurar = api.usaCookie || servidor.isNotEmpty;
    if (podeRestaurar) {
      try {
        if (!api.usaCookie && !kIsWeb) api.token = await _cofre.ler();
        if (api.usaCookie || api.token != null) await carregarPerfil();
      } catch (_) {
        api.token = null;
      }
    }
    iniciada = true;
    notifyListeners();
  }

  Future<void> definirServidor(String endereco) async {
    final normal = endereco.trim().isEmpty && kIsWeb ? '' : validarServidor(endereco);
    servidor = normal;
    api.baseUrl = normal;
    await _prefs?.setString('gf_servidor', normal);
    notifyListeners();
  }

  Future<void> carregarPerfil() async {
    final me = await api.get('/api/auth/me');
    _aplicarPerfil(me);
    await carregarCategorias();
    notifyListeners();
  }

  void _aplicarPerfil(Map<String, dynamic> me) {
    usuario = Usuario.deJson(Json.from(me['user'] as Map));
    permissoes = ((me['permissoes'] as List?) ?? const []).map((e) => e.toString()).toSet();
    if (me['settings'] is Map) config = Configuracoes.deJson(Json.from(me['settings'] as Map));
    if (me['hoje'] != null) hoje = me['hoje'].toString();
    avisoLogin = null;
  }

  Future<void> carregarCategorias() async {
    final r = await api.get('/api/categories');
    categorias = listaJson(r['categories']).map(Categoria.deJson).toList();
  }

  /// Atualiza data do servidor e parâmetros (usado ao abrir telas que dependem deles).
  Future<void> sincronizar() async {
    try {
      final r = await api.get('/api/settings');
      hoje = r['hoje']?.toString() ?? hoje;
      if (r['settings'] is Map) config = Configuracoes.deJson(Json.from(r['settings'] as Map));
      notifyListeners();
    } catch (_) {
      // Mantém os últimos valores.
    }
  }

  void aplicarConfig(Configuracoes c) {
    config = c;
    notifyListeners();
  }

  Future<void> entrar(String email, String senha, bool lembrar) async {
    final r = await api.post('/api/auth/login', {'email': email, 'senha': senha, 'lembrar': lembrar});
    if (r['token'] != null) {
      api.token = r['token'].toString();
      if (lembrar && !kIsWeb) await _cofre.gravar(api.token!);
    }
    await carregarPerfil();
  }

  Future<void> sair() async {
    try {
      await api.post('/api/auth/logout');
    } catch (_) {
      // Sessão já expirada ou servidor fora do ar: encerra no aparelho do mesmo jeito.
    }
    encerrarLocal();
  }

  void encerrarLocal([String? aviso]) {
    if (!kIsWeb) _cofre.apagar();
    api.token = null;
    usuario = null;
    permissoes = {};
    avisoLogin = aviso;
    notifyListeners();
  }

  Future<void> mudarZoom(int direcao) async {
    final i = zooms.indexOf(zoom);
    zoom = zooms[((i < 0 ? 0 : i) + direcao).clamp(0, zooms.length - 1)];
    await _prefs?.setDouble('gf_zoom', zoom);
    notifyListeners();
  }

  Future<void> alternarContraste() async {
    altoContraste = !altoContraste;
    await _prefs?.setBool('gf_hc', altoContraste);
    notifyListeners();
  }

  Future<void> restaurarAcessibilidade() async {
    zoom = 1;
    altoContraste = false;
    await _prefs?.remove('gf_zoom');
    await _prefs?.remove('gf_hc');
    notifyListeners();
  }
}

final sessaoProvider = ChangeNotifierProvider<Sessao>((ref) => throw UnimplementedError('Sessão criada no main()'));
