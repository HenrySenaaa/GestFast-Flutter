// servidor.dart - Servidor HTTP e API REST do GestFast ERP (shelf + MySQL).
//
// Mesmas rotas, status, mensagens, cabeçalhos e cookies do servidor Node (server.js).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'caminhos.dart';
import 'config.dart';
import 'dados.dart';
import 'erros.dart';
import 'exportacao.dart';
import 'js.dart';
import 'limitador.dart';
import 'logger.dart';
import 'permissoes.dart';
import 'relogio.dart';
import 'url.dart';

const _cookie = 'gf_session';
const maxCorpo = 4 * 1024 * 1024;

const _mime = {
  '.html': 'text/html; charset=UTF-8',
  '.css': 'text/css; charset=UTF-8',
  '.js': 'application/javascript; charset=UTF-8',
  '.json': 'application/json; charset=UTF-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.wasm': 'application/wasm',
  '.mjs': 'application/javascript; charset=UTF-8',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff2': 'font/woff2',
  '.bin': 'application/octet-stream',
  '.map': 'application/json',
};

const cabecalhosSeguranca = {
  'X-Content-Type-Options': 'nosniff',
  'X-Frame-Options': 'DENY',
  'Referrer-Policy': 'same-origin',
  'Content-Security-Policy':
      "default-src 'self'; img-src 'self' data: blob:; style-src 'self' 'unsafe-inline'; script-src 'self' 'wasm-unsafe-eval'; font-src 'self' data:; connect-src 'self'; worker-src 'self' blob:; frame-ancestors 'none'",
};

/// Resposta de uma rota: JSON (`corpo`) ou arquivo (`bytes`).
class Saida {
  Saida.json(this.corpo, {this.status = 200, this.cabecalhos = const {}}) : bytes = null;
  Saida.arquivo(this.bytes, {required this.cabecalhos}) : corpo = null, status = 200;
  final Obj? corpo;
  final Uint8List? bytes;
  final int status;
  final Map<String, String> cabecalhos;
}

Saida ok([Obj dados = const {}, int status = 200]) => Saida.json({'success': true, ...dados}, status: status);

class Contexto {
  Contexto(this.req, this.params, this.query, this.user, this.ip);
  final Request req;
  final Map<String, String> params;
  final Map<String, String> query;
  final Obj? user;
  final String ip;
  Object? body = <String, Object?>{};
  Object? q(String k) => query.containsKey(k) ? query[k] : undefined;
  Object? b(String k) => prop(body, k);
  Obj get usuario => user!;
}

class _Rota {
  _Rota(this.metodo, String padrao, this.publica, this.perm, this.fn)
      : chaves = [for (final m in RegExp(r':([a-z_]+)', caseSensitive: false).allMatches(padrao)) m[1]!],
        re = RegExp('^${padrao.replaceAllMapped(RegExp(r':([a-z_]+)', caseSensitive: false), (_) => '([^/]+)')}/?\$');
  final String metodo;
  final RegExp re;
  final List<String> chaves;
  final bool publica;
  final String? perm;
  final Future<Saida> Function(Contexto ctx) fn;
}

/// `Buffer.from(texto, 'base64')` do Node: lê até o primeiro "=".
Uint8List base64Node(String s) {
  final fim = s.indexOf('=');
  final t = fim >= 0 ? s.substring(0, fim) : s;
  const alfabeto = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  final out = BytesBuilder(copy: false);
  var acc = 0, bits = 0;
  for (final ch in t.codeUnits) {
    final v = alfabeto.indexOf(String.fromCharCode(ch));
    if (v < 0) continue;
    acc = (acc << 6) | v;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      out.addByte((acc >> bits) & 0xff);
    }
  }
  return out.takeBytes();
}

class Servidor {
  Servidor({required this.config, required this.dados, required this.logger, required this.relogio, Limitador? limitador})
      : limite = limitador ?? Limitador(relogio: relogio.agoraMs),
        caminhos = CaminhosNode.daPlataforma() {
    pastaWeb = caminhos.normalize(config.pastaWeb);
    origensCors = config.origensCors;
    _montarRotas();
  }

  final Config config;
  final Dados dados;
  final Logger logger;
  final Relogio relogio;
  final CaminhosNode caminhos;

  /// Limitação de tentativas de login e de senha de gerente (por e-mail + IP).
  final Limitador limite;
  late final String pastaWeb;
  late final List<String> origensCors;
  final _rotas = <_Rota>[];

  String get pastaUploads => config.pastaUploads;

  // ------------------------------------------------------------------ utilidades HTTP
  Response _json(int status, Object? dadosJson, [Map<String, String> extra = const {}]) => Response(
        status,
        body: utf8.encode(jsonStringify(dadosJson)),
        headers: {
          'Content-Type': 'application/json; charset=UTF-8',
          'Cache-Control': 'no-store',
          ...cabecalhosSeguranca,
          ...extra,
        },
      );

  Future<Object?> _lerCorpo(Request req) async {
    final partes = BytesBuilder(copy: false);
    await for (final c in req.read()) {
      if (partes.length + c.length > maxCorpo) throw HttpErro(413, 'Requisição muito grande.');
      partes.add(c);
    }
    try {
      final s = utf8.decode(partes.takeBytes(), allowMalformed: true);
      final corpo = s.isNotEmpty ? jsonParse(s) : <String, Object?>{};
      if (corpo is! Map) throw const FormatException('não é objeto');
      return corpo;
    } catch (_) {
      throw HttpErro(400, 'Corpo da requisição inválido (JSON esperado).');
    }
  }

  Map<String, String> _cookies(Request req) {
    final out = <String, String>{};
    for (final p in (req.headers['cookie'] ?? '').split(';')) {
      final i = p.indexOf('=');
      if (i <= 0) continue;
      final valor = jsTrim(p.substring(i + 1));
      final nome = jsTrim(p.substring(0, i));
      try {
        out[nome] = decodeURIComponent(valor);
      } on ErroUri {
        out[nome] = valor;
      }
    }
    return out;
  }

  // Token da sessão: "Authorization: Bearer" (app nativo) ou cookie HttpOnly (navegador).
  String? tokenDaRequisicao(Request req) {
    final m = RegExp(r'^Bearer\s+(\S+)$', caseSensitive: false).firstMatch(req.headers['authorization'] ?? '');
    return m != null ? m[1] : _cookies(req)[_cookie];
  }

  bool _ehApp(Request req) => (req.headers['x-client'] ?? '').toLowerCase() == 'app';

  Map<String, String> _cors(Request req) {
    final origem = req.headers['origin'];
    if (origem == null || origem.isEmpty || !origensCors.contains(origem)) return const {};
    return {
      'Access-Control-Allow-Origin': origem,
      'Vary': 'Origin',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Client',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
      'Access-Control-Expose-Headers': 'Content-Disposition',
      'Access-Control-Max-Age': '600',
    };
  }

  String _cookieSessao(String token, int? maxAge) =>
      '$_cookie=$token; Path=/; HttpOnly; SameSite=Lax${maxAge != null && maxAge != 0 ? '; Max-Age=$maxAge' : ''}';
  static const _cookieLimpo = '$_cookie=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0';

  String _ip(Request req) {
    final info = req.context['shelf.io.connection_info'];
    return info is HttpConnectionInfo ? info.remoteAddress.address : '';
  }

  // Confere a senha de gerente, com o mesmo limite de tentativas do login.
  Future<Obj> _autorizarGerente(Contexto ctx, [List<String>? aceitos]) async {
    final chave = 'gerente|${toStr(or(ctx.b('autorizador_email'), '')).toLowerCase()}|${ctx.ip}';
    limite.checar(chave);
    try {
      final aut = aceitos == null
          ? await dados.authorizeManager(ctx.b('autorizador_email'), ctx.b('autorizador_senha'))
          : await dados.authorizeManager(ctx.b('autorizador_email'), ctx.b('autorizador_senha'), aceitos);
      limite.sucesso(chave);
      return aut;
    } catch (e) {
      if (e is HttpErro && e.status == 403) limite.falhou(chave);
      rethrow;
    }
  }

  void _exigir(Contexto ctx, String perm) {
    if (!pode(ctx.usuario['perfil'], perm)) throw HttpErro(403, 'Usuário sem permissão para esta operação.');
  }

  void _rota(String metodo, String padrao, Future<Saida> Function(Contexto) fn, {bool publica = false, String? perm}) =>
      _rotas.add(_Rota(metodo, padrao, publica, perm, fn));

  String _hoje() => relogio.dataISO();

  // ------------------------------------------------------------------ produtos (imagem)
  ({Uint8List buf, String ext}) _lerImagem(Object? dataUrl) {
    final m = RegExp(r'^data:(image\/(png|jpeg|webp|gif));base64,([A-Za-z0-9+/=]+)$').firstMatch(toStr(or(dataUrl, '')));
    if (m == null) throw erro('Imagem inválida. Envie um arquivo PNG, JPG, WEBP ou GIF.');
    final buf = base64Node(m[3]!);
    if (buf.length > 2 * 1024 * 1024) throw erro('A imagem deve ter no máximo 2 MB.');
    return (buf: buf, ext: m[2] == 'jpeg' ? 'jpg' : m[2]!);
  }

  // Devolve a função que grava o arquivo. O Dados só a chama depois de validar o produto.
  GravarImagem? _gravadorDeImagem(Object? imagemData) {
    if (!truthy(imagemData)) return null;
    final img = _lerImagem(imagemData);
    return (idRef) {
      Directory(pastaUploads).createSync(recursive: true);
      final nome = 'prod-${toStr(idRef)}-${relogio.agoraMs()}.${img.ext}';
      File(caminhos.join([pastaUploads, nome])).writeAsBytesSync(img.buf);
      return 'uploads/$nome';
    };
  }

  // Id e caminho da imagem nunca vêm do corpo enviado pelo cliente.
  (Obj, GravarImagem?) _dadosDoProduto(Object? corpo) {
    final c = (corpo as Map).cast<String, Object?>();
    final d = Map<String, Object?>.of(c)
      ..remove('imagem_data')
      ..remove('imagem')
      ..remove('id_produto');
    return (d, _gravadorDeImagem(prop(c, 'imagem_data')));
  }

  // ------------------------------------------------------------------ rotas
  void _montarRotas() {
    // ---------------- autenticação
    _rota('POST', '/api/auth/login', publica: true, (ctx) async {
      final email = ctx.b('email'), senha = ctx.b('senha'), lembrar = ctx.b('lembrar');
      final chave = '${toStr(or(email, '')).toLowerCase()}|${ctx.ip}';
      limite.checar(chave);
      Obj u;
      try {
        u = await dados.authenticate(email, senha);
      } catch (e) {
        if (e is HttpErro && e.status == 401) limite.falhou(chave);
        logger.log('AVISO', 'login_falhou', {'email': sliceStr(toStr(or(email, '')), 100), 'motivo': mensagemDe(e)});
        rethrow;
      }
      limite.sucesso(chave);
      final s = await dados.createSession(u['id_usuario'], lembrar);
      logger.log('INFO', 'login', {}, toStr(u['email']));
      final d = {'message': 'Login realizado com sucesso', 'user': dados.publicUser(u), 'permissoes': permissoesDe(u['nome_perfil'])};
      // O app nativo guarda o token e usa "Authorization: Bearer"; o navegador fica só com o cookie HttpOnly.
      if (_ehApp(ctx.req)) return ok({...d, 'token': s.token});
      return Saida.json({'success': true, ...d}, cabecalhos: {'Set-Cookie': _cookieSessao(s.token, s.maxAgeSeg)});
    });

    _rota('POST', '/api/auth/logout', publica: true, (ctx) async {
      final token = tokenDaRequisicao(ctx.req);
      if (ctx.user != null) logger.log('INFO', 'logout', {}, toStr(ctx.user!['email']));
      await dados.deleteSession(token);
      return Saida.json({'success': true, 'message': 'Sessão encerrada.'}, cabecalhos: {'Set-Cookie': _cookieLimpo});
    });

    _rota('GET', '/api/auth/me', publica: true, (ctx) async {
      if (ctx.user == null) throw HttpErro(401, 'Sessão expirada. Faça login novamente.');
      return ok({
        'user': ctx.user,
        'permissoes': permissoesDe(ctx.usuario['perfil']),
        'settings': await dados.getSettings(),
        'hoje': _hoje(),
      });
    });

    _rota('POST', '/api/auth/forgot', publica: true, (ctx) async {
      final r = await dados.createResetToken(ctx.b('email'));
      if (r != null) {
        // Sem servidor SMTP configurado, o código é escrito só no console (simulação de envio de e-mail).
        // O token nunca vai para o arquivo de log, que aparece na tela de Logs.
        final email = toStr(r.user['email']);
        logger.log('INFO', 'redefinicao_senha_solicitada', {}, email);
        if (!config.silencioso) {
          stdout.writeln(
            '[GestFast] Redefinição de senha para $email: http://localhost:${config.portaTexto}/#/redefinir?codigo=${r.token} (código: ${r.token})',
          );
        }
      }
      return ok({'message': 'Se o e-mail estiver cadastrado, enviaremos um link de redefinição.'});
    });

    _rota('POST', '/api/auth/reset', publica: true, (ctx) async {
      final u = await dados.resetPassword(ctx.b('token'), ctx.b('senha'));
      logger.log('INFO', 'senha_redefinida', {}, toStr(u?['email']));
      return ok({'message': 'Senha redefinida com sucesso. Faça login com a nova senha.'});
    });

    _rota('POST', '/api/auth/change-password', (ctx) async {
      await dados.changePassword(ctx.usuario['id_usuario'], ctx.b('senha_atual'), ctx.b('nova_senha'), tokenDaRequisicao(ctx.req));
      return ok({'message': 'Senha alterada com sucesso!'});
    });

    // ---------------- busca global
    _rota('GET', '/api/search', (ctx) async => ok({'results': await dados.buscaGlobal(ctx.q('q'), (p) => pode(ctx.usuario['perfil'], p))}));

    // ---------------- dashboard e dados de apoio
    _rota('GET', '/api/dashboard', perm: 'dashboard:ver', (ctx) async {
      final t0 = relogio.agoraMs();
      final data = await dados.getDashboardData(ctx.user);
      return ok({'data': data, 'latencyMs': (relogio.agoraMs() - t0).toDouble()});
    });
    _rota('GET', '/api/alerts', perm: 'dashboard:ver', (ctx) async => ok({'alerts': await dados.getAlertasCriticos()}));
    _rota('GET', '/api/categories', (ctx) async => ok({'categories': await dados.listCategorias()}));
    _rota('GET', '/api/suppliers', (ctx) async => ok({'suppliers': await dados.listFornecedores()}));
    _rota('GET', '/api/profiles', perm: 'usuarios:gerir', (ctx) async => ok({'profiles': await dados.listPerfis()}));
    _rota('GET', '/api/settings', (ctx) async => ok({'settings': await dados.getSettings(), 'hoje': _hoje()}));
    _rota(
      'PUT',
      '/api/settings',
      perm: 'config:gerir',
      (ctx) async => ok({'settings': await dados.updateSettings(ctx.body), 'message': 'Configurações salvas com sucesso!'}),
    );
    _rota('GET', '/api/logs', perm: 'logs:ver', (ctx) async => ok({'logs': logger.recentes(limiteDeLogs(ctx.q('limit')))}));

    // ---------------- funcionários
    _rota(
      'GET',
      '/api/users',
      perm: 'usuarios:gerir',
      (ctx) async => ok({'users': await dados.listUsers(q: ctx.q('q'), idPerfil: ctx.q('id_perfil'), status: ctx.q('status'))}),
    );
    _rota('POST', '/api/users', perm: 'usuarios:gerir', (ctx) async {
      final u = await dados.createUser(ctx.body);
      return ok({'user': u, 'message': 'Funcionário cadastrado com sucesso!'}, 201);
    });
    _rota(
      'PUT',
      '/api/users/:id',
      perm: 'usuarios:gerir',
      (ctx) async => ok({
        'user': await dados.updateUser(ctx.params['id'], ctx.body, ctx.user, tokenDaRequisicao(ctx.req)),
        'message': 'Funcionário atualizado com sucesso!',
      }),
    );
    _rota('PATCH', '/api/users/:id/status', perm: 'usuarios:gerir', (ctx) async {
      final u = await dados.setUserStatus(ctx.params['id'], ctx.b('status'), ctx.user);
      return ok({
        'user': u,
        'message': u!['status'] == 'Ativo' ? 'Acesso do funcionário reativado!' : 'Acesso do funcionário desativado com sucesso!',
      });
    });

    // ---------------- produtos
    _rota(
      'GET',
      '/api/products',
      perm: 'produtos:ver',
      (ctx) async => ok({'products': await dados.getProducts(ctx.q('q'), ctx.q('category'), or(ctx.q('status'), 'Ativo'))}),
    );
    _rota('GET', '/api/products/:id', perm: 'produtos:ver', (ctx) async {
      final p = await dados.getProductById(ctx.params['id']);
      if (p == null) throw HttpErro(404, 'Produto não encontrado');
      return ok({'product': p});
    });
    _rota('POST', '/api/products', perm: 'produtos:editar', (ctx) async {
      final (d, gravar) = _dadosDoProduto(ctx.body);
      return ok({'product': await dados.saveProduct(d, ctx.user, gravar), 'message': 'Produto cadastrado com sucesso!'}, 201);
    });
    _rota('PUT', '/api/products/:id', perm: 'produtos:editar', (ctx) async {
      final (d, gravar) = _dadosDoProduto(ctx.body);
      d['id_produto'] = ctx.params['id'];
      return ok({'product': await dados.saveProduct(d, ctx.user, gravar), 'message': 'Produto atualizado com sucesso!'});
    });
    _rota('DELETE', '/api/products/:id', perm: 'produtos:editar', (ctx) async {
      await dados.setProductStatus(ctx.params['id'], 'Inativo');
      return ok({'message': 'Produto inativado do catálogo com sucesso!'});
    });
    _rota('PATCH', '/api/products/:id/status', perm: 'produtos:editar', (ctx) async {
      final p = await dados.setProductStatus(ctx.params['id'], ctx.b('status'));
      return ok({'product': p, 'message': p['status'] == 'Ativo' ? 'Produto reativado no catálogo!' : 'Produto inativado do catálogo com sucesso!'});
    });

    // ---------------- requisições
    _rota('GET', '/api/requisitions', perm: 'requisicoes:ver', (ctx) async => ok({'requisicoes': await dados.listRequisicoes()}));
    _rota('GET', '/api/requisitions/:id', perm: 'requisicoes:ver', (ctx) async {
      final r = await dados.getRequisicao(ctx.params['id']);
      if (r == null) throw HttpErro(404, 'Requisição não encontrada');
      return ok({'requisicao': r});
    });
    _rota(
      'POST',
      '/api/requisitions',
      perm: 'requisicoes:criar',
      (ctx) async => ok({'requisicao': await dados.createRequisicao(ctx.body, ctx.user), 'message': 'Pedido realizado com sucesso'}, 201),
    );
    _rota('PATCH', '/api/requisitions/:id/status', (ctx) async {
      final sit = ctx.b('situacao');
      _exigir(ctx, sit == 'Cancelado' ? 'requisicoes:cancelar' : (sit == 'Finalizado' ? 'requisicoes:receber' : 'requisicoes:avancar'));
      final r = await dados.updateRequisicaoStatus(ctx.params['id'], ctx.body, ctx.user);
      final msg = sit == 'Cancelado'
          ? 'Solicitação de cancelamento encaminhada com sucesso'
          : sit == 'Finalizado'
              ? (truthy(r['parcial']) ? 'Recebimento parcial registrado e estoque atualizado!' : 'Mercadoria recebida e estoque atualizado!')
              : 'Requisição atualizada para "${toStr(r['situacao'])}"!';
      return ok({'requisicao': r, 'message': msg});
    });

    // ---------------- movimentações
    _rota(
      'GET',
      '/api/movements',
      perm: 'movimentos:ver',
      (ctx) async => ok({'movements': await dados.getMovimentacoes(tipo: ctx.q('tipo'), from: ctx.q('from'), to: ctx.q('to'))}),
    );
    _rota('POST', '/api/movements', perm: 'movimentos:registrar', (ctx) async {
      final movs = await dados.registrarMovimentacoes(ctx.body, ctx.user);
      final tipo = toStr(ctx.b('tipo_movimentacao'));
      return ok({
        'movements': movs,
        'movement': movs.isEmpty ? undefined : movs.first,
        'message': movs.length > 1 ? '$tipo em lote registrada (${movs.length} itens)!' : '$tipo registrada com sucesso!',
      }, 201);
    });

    // ---------------- validade e perdas/sobras
    _rota('GET', '/api/expiring', perm: 'produtos:ver', (ctx) async => ok(await dados.getValidades()));
    _rota('POST', '/api/losses', perm: 'movimentos:registrar', (ctx) async {
      final movs = await dados.registrarPerdas(ctx.body, ctx.user);
      logger.log('INFO', 'perda_registrada', {'motivo': ctx.b('motivo_perda'), 'itens': movs.length.toDouble()}, toStr(ctx.usuario['email']));
      return ok({
        'movements': movs,
        'message': movs.length > 1 ? 'Perda registrada (${movs.length} itens) e estoque atualizado!' : 'Perda registrada e estoque atualizado!',
      }, 201);
    });

    // ---------------- vendas
    _rota(
      'GET',
      '/api/sales',
      perm: 'vendas:ver',
      (ctx) async => ok({'sales': await dados.getVendas(from: ctx.q('from'), to: ctx.q('to'), q: ctx.q('q'), status: ctx.q('status'))}),
    );
    _rota('GET', '/api/sales/:id', perm: 'vendas:ver', (ctx) async {
      final v = await dados.getVenda(ctx.params['id']);
      if (v == null) throw HttpErro(404, 'Venda não encontrada');
      return ok({'sale': v});
    });
    _rota(
      'POST',
      '/api/sales',
      perm: 'vendas:vender',
      (ctx) async => ok({'sale': await dados.realizarVenda(ctx.body, ctx.usuario), 'message': 'Venda realizada com sucesso'}, 201),
    );
    _rota(
      'PUT',
      '/api/sales/:id',
      perm: 'vendas:editar',
      (ctx) async => ok({'sale': await dados.editarVenda(ctx.params['id'], ctx.body, ctx.usuario), 'message': 'Venda atualizada com sucesso'}),
    );
    _rota('POST', '/api/sales/:id/cancel', perm: 'vendas:cancelar', (ctx) async {
      final aut = await _autorizarGerente(ctx);
      final v = await dados.cancelarVenda(ctx.params['id'], ctx.body, ctx.usuario, aut);
      logger.log('INFO', 'venda_cancelada', {'venda': v?['codigo_venda'], 'autorizadaPor': aut['email']}, toStr(ctx.usuario['email']));
      return ok({'sale': v, 'message': 'Venda cancelada e estoque estornado!'});
    });
    _rota('DELETE', '/api/sales/:id', perm: 'vendas:excluir', (ctx) async {
      await _autorizarGerente(ctx, const ['Administrador']);
      final v = await dados.excluirVenda(ctx.params['id'], ctx.usuario);
      return ok({'message': 'Venda excluída com sucesso', 'sale': v});
    });

    // ---------------- conferência
    _rota(
      'GET',
      '/api/inventory',
      perm: 'estoque:conferir',
      (ctx) async => ok({'conferencias': await dados.listConferencias(), 'itensParaConferencia': await dados.listProdutosAtivos()}),
    );
    _rota(
      'POST',
      '/api/inventory',
      perm: 'estoque:conferir',
      (ctx) async =>
          ok({'conferencia': await dados.salvarConferencia(ctx.body, ctx.usuario), 'message': 'Conferência de estoque salva com sucesso!'}, 201),
    );

    // ---------------- relatórios (+ exportação PDF/XLSX)
    _rota('GET', '/api/reports/sales', perm: 'relatorios:ver', (ctx) async {
      final r = await dados.getRelatorioVendas(from: ctx.q('from'), to: ctx.q('to'), categoria: ctx.q('categoria'));
      return _entregarRelatorio(ctx, 'vendas', r, _montarVendas);
    });
    _rota('GET', '/api/reports/stock', perm: 'relatorios:ver', (ctx) async {
      final r = await dados.getRelatorioEstoque(from: ctx.q('from'), to: ctx.q('to'), categoria: ctx.q('categoria'));
      return _entregarRelatorio(ctx, 'estoque', r, _montarEstoque);
    });
    _rota('GET', '/api/reports/losses', perm: 'relatorios:ver', (ctx) async {
      final r = await dados.getRelatorioPerdas(from: ctx.q('from'), to: ctx.q('to'), categoria: ctx.q('categoria'));
      return _entregarRelatorio(ctx, 'perdas', r, _montarPerdas);
    });
  }

  /// Linhas do log: inteiro de 1 a 1000; ausente, zero, negativo ou inválido usa 200.
  static int limiteDeLogs(Object? valor) {
    final n = jsTrunc(toNumber(valor));
    if (!n.isFinite || n < 1) return 200;
    return n > 1000 ? 1000 : n.toInt();
  }

  // ------------------------------------------------------------------ relatórios
  static String brl(Object? n) => 'R\$ ${toFixed(toNumber(n), 2).replaceFirst('.', ',')}';
  static String numBr(Object? n) => numStr(toNumber(n)).replaceFirst('.', ',');
  static String dataBR(Object? s) => truthy(s) ? toStr(s).split('-').reversed.join('/') : '';

  static String descPeriodo(Obj f, List<Obj> categorias) {
    final cat = truthy(f['categoria'])
        ? toStr(categorias.where((c) => c['id_categoria'] == f['categoria']).firstOrNull?['nome_categoria'] ?? undefined)
        : 'Todas as categorias';
    final per = (truthy(f['from']) || truthy(f['to']))
        ? '${truthy(f['from']) ? dataBR(f['from']) : 'início'} a ${truthy(f['to']) ? dataBR(f['to']) : 'hoje'}'
        : 'Todo o período';
    return 'Período: $per  |  Categoria: $cat';
  }

  Future<Saida> _entregarRelatorio(Contexto ctx, String tipo, Obj dadosRel, _Montagem Function(Obj d, List<Obj> cats) montar) async {
    final formato = toStr(or(ctx.q('format'), 'json')).toLowerCase();
    await dados.registrarRelatorio('$tipo ($formato)', ctx.usuario['id_usuario']);
    if (formato == 'json') return ok({'report': dadosRel});
    final m = montar(dadosRel, await dados.listCategorias());
    final stamp = _hoje();
    if (formato == 'xlsx') {
      return Saida.arquivo(
        gerarXlsx(m.sheets),
        cabecalhos: {
          'Content-Type': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          'Content-Disposition': 'attachment; filename="gestfast-$tipo-$stamp.xlsx"',
        },
      );
    }
    if (formato == 'pdf') {
      final settings = await dados.getSettings();
      return Saida.arquivo(
        gerarPdf(
          title: m.titulo,
          subtitle: m.subtitulo,
          sections: m.sections,
          footer: 'GestFast - ${toStr(settings['estabelecimento'])} - gerado em ${relogio.dataHora()} por ${toStr(ctx.usuario['nome'])}',
          landscape: m.landscape,
        ),
        cabecalhos: {'Content-Type': 'application/pdf', 'Content-Disposition': 'attachment; filename="gestfast-$tipo-$stamp.pdf"'},
      );
    }
    throw HttpErro(400, 'Formato inválido. Use json, pdf ou xlsx.');
  }

  static List<Obj> _l(Object? v) => (v as List).cast<Obj>();

  static _Montagem _montarVendas(Obj d, List<Obj> cats) {
    final filtros = d['filtros'] as Obj;
    final resumo = [
      descPeriodo(filtros, cats),
      'Transações: ${toStr(d['quantidadeTransacoes'])}  |  Bruto: ${brl(d['totalBruto'])}  |  Descontos: ${brl(d['totalDescontos'])}  |  Faturamento: ${brl(d['totalGeral'])}  |  Ticket médio: ${brl(d['ticketMedio'])}',
    ];
    const colItens = [
      ColunaPlanilha('Produto', 36),
      ColunaPlanilha('Categoria', 24),
      ColunaPlanilha('Unid', 8),
      ColunaPlanilha('Valor médio', 14, 'money'),
      ColunaPlanilha('Quant.', 10, 'dec'),
      ColunaPlanilha('Total bruto', 14, 'money'),
    ];
    final itens = _l(d['itensVendidos']);
    final trans = _l(d['transacoes']);
    final linhasItens = [
      for (final i in itens) Linha([i['nome_produto'], i['categoria'], i['unidade'], i['valor_unitario'], i['quantidade'], i['total']]),
    ];
    const colTrans = [
      ColunaPlanilha('Venda', 14),
      ColunaPlanilha('Data', 17),
      ColunaPlanilha('Operador', 18),
      ColunaPlanilha('Pagamento', 16),
      ColunaPlanilha('Itens', 50),
      ColunaPlanilha('Bruto', 12, 'money'),
      ColunaPlanilha('Desconto', 12, 'money'),
      ColunaPlanilha('Total', 12, 'money'),
    ];
    final linhasTrans = [
      for (final t in trans)
        Linha([t['codigo_venda'], t['data_venda'], t['usuario_nome'], t['forma_pagamento'], t['itens_resumo'], t['bruto'], t['desconto'], t['valor_total']]),
    ];
    final totalRow = Linha(['TOTAL', '', '', '', '', d['totalBruto'], d['totalDescontos'], d['totalGeral']], negrito: true);
    return _Montagem(
      titulo: 'Relatório de Faturamento e Vendas',
      subtitulo: resumo,
      landscape: true,
      sheets: [
        Planilha(name: 'Vendidos por produto', title: 'Relatório de Faturamento e Vendas', subtitle: resumo[0], columns: colItens, rows: linhasItens),
        Planilha(name: 'Transações', title: 'Transações do período', subtitle: resumo[1], columns: colTrans, rows: [...linhasTrans, totalRow]),
      ],
      sections: [
        SecaoPdf(
          heading: 'Produtos vendidos',
          columns: const [
            ColunaPdf('Produto', 4),
            ColunaPdf('Categoria', 3),
            ColunaPdf('Unid', 1),
            ColunaPdf('Valor médio', 2, 'right'),
            ColunaPdf('Quant.', 1.5, 'right'),
            ColunaPdf('Total bruto', 2, 'right'),
          ],
          rows: [
            for (final i in itens)
              Linha([i['nome_produto'], i['categoria'], i['unidade'], brl(i['valor_unitario']), numBr(i['quantidade']), brl(i['total'])]),
          ],
        ),
        SecaoPdf(
          heading: 'Transações',
          columns: const [
            ColunaPdf('Venda', 2),
            ColunaPdf('Data', 2.4),
            ColunaPdf('Operador', 2.4),
            ColunaPdf('Pagamento', 2.2),
            ColunaPdf('Itens', 6),
            ColunaPdf('Total', 2, 'right'),
          ],
          rows: [
            for (final t in trans)
              Linha([t['codigo_venda'], t['data_venda'], t['usuario_nome'], t['forma_pagamento'], t['itens_resumo'], brl(t['valor_total'])]),
            Linha(['TOTAL', '', '', '', '', brl(d['totalGeral'])], negrito: true),
          ],
        ),
      ],
    );
  }

  static _Montagem _montarEstoque(Obj d, List<Obj> cats) {
    final sub = [
      descPeriodo(d['filtros'] as Obj, cats),
      'Produtos: ${toStr(d['totalProdutos'])}  |  Em nível crítico: ${toStr(d['totalCriticos'])}  |  Valor em estoque (custo): ${brl(d['valorTotalEstoque'])}',
    ];
    final linhas = _l(d['linhas']);
    return _Montagem(
      titulo: 'Relatório de Estoque (entradas, saídas e saldo)',
      subtitulo: sub,
      landscape: true,
      sheets: [
        Planilha(
          name: 'Estoque',
          title: 'Relatório de Estoque',
          subtitle: sub[0],
          columns: const [
            ColunaPlanilha('Código', 12),
            ColunaPlanilha('Produto', 36),
            ColunaPlanilha('Categoria', 24),
            ColunaPlanilha('Unid', 8),
            ColunaPlanilha('Entradas', 11, 'dec'),
            ColunaPlanilha('Saídas', 11, 'dec'),
            ColunaPlanilha('Saldo atual', 12, 'dec'),
            ColunaPlanilha('Estoque mín.', 12, 'dec'),
            ColunaPlanilha('Valor em estoque', 16, 'money'),
            ColunaPlanilha('Situação', 11),
          ],
          rows: [
            for (final l in linhas)
              Linha([
                l['codigo_barras'],
                l['nome_produto'],
                l['categoria'],
                l['unidade'],
                l['entradas'],
                l['saidas'],
                l['saldo_atual'],
                l['estoque_minimo'],
                l['valor_em_estoque'],
                l['situacao'],
              ]),
          ],
        ),
      ],
      sections: [
        SecaoPdf(
          columns: const [
            ColunaPdf('Código', 1.6),
            ColunaPdf('Produto', 4.5),
            ColunaPdf('Categoria', 3),
            ColunaPdf('Unid', 1),
            ColunaPdf('Entradas', 1.4, 'right'),
            ColunaPdf('Saídas', 1.4, 'right'),
            ColunaPdf('Saldo', 1.4, 'right'),
            ColunaPdf('Mín.', 1.2, 'right'),
            ColunaPdf('Situação', 1.6),
          ],
          rows: [
            for (final l in linhas)
              Linha([
                l['codigo_barras'],
                l['nome_produto'],
                l['categoria'],
                l['unidade'],
                numBr(l['entradas']),
                numBr(l['saidas']),
                numBr(l['saldo_atual']),
                numBr(l['estoque_minimo']),
                l['situacao'],
              ]),
          ],
        ),
      ],
    );
  }

  static _Montagem _montarPerdas(Obj d, List<Obj> cats) {
    final motivos = _l(d['porMotivo']).map((m) => '${toStr(m['motivo'])}: ${brl(m['valor_total'])}').join('  |  ');
    final sub = [
      descPeriodo(d['filtros'] as Obj, cats),
      'Registros: ${toStr(d['totalRegistros'])}  |  Valor perdido (custo): ${brl(d['valorTotal'])}${motivos.isNotEmpty ? '  |  $motivos' : ''}',
    ];
    final porProduto = _l(d['porProduto']);
    final registros = _l(d['registros']);
    final totalRow = Linha(['TOTAL', '', '', '', d['valorTotal']], negrito: true);
    return _Montagem(
      titulo: 'Relatório de Desperdício (perdas e sobras)',
      subtitulo: sub,
      landscape: true,
      sheets: [
        Planilha(
          name: 'Por produto',
          title: 'Relatório de Desperdício',
          subtitle: sub[0],
          columns: const [
            ColunaPlanilha('Produto', 36),
            ColunaPlanilha('Categoria', 24),
            ColunaPlanilha('Unid', 8),
            ColunaPlanilha('Quant. perdida', 14, 'dec'),
            ColunaPlanilha('Valor (custo)', 14, 'money'),
          ],
          rows: [
            for (final p in porProduto) Linha([p['nome_produto'], p['categoria'], p['unidade'], p['quantidade'], p['valor_total']]),
            totalRow,
          ],
        ),
        Planilha(
          name: 'Registros',
          title: 'Registros de perda',
          subtitle: sub[1],
          columns: const [
            ColunaPlanilha('Data', 17),
            ColunaPlanilha('Produto', 36),
            ColunaPlanilha('Motivo', 16),
            ColunaPlanilha('Quant.', 10, 'dec'),
            ColunaPlanilha('Unid', 8),
            ColunaPlanilha('Valor (custo)', 14, 'money'),
            ColunaPlanilha('Responsável', 18),
            ColunaPlanilha('Observação', 40),
          ],
          rows: [
            for (final r in registros)
              Linha([
                r['data_movimentacao'],
                r['produto_nome'],
                r['motivo_perda'],
                r['quantidade'],
                r['unidade'],
                r['valor_total'],
                r['usuario_nome'],
                r['observacao'],
              ]),
          ],
        ),
      ],
      sections: [
        SecaoPdf(
          heading: 'Perdas por produto',
          columns: const [
            ColunaPdf('Produto', 4.5),
            ColunaPdf('Categoria', 3),
            ColunaPdf('Unid', 1),
            ColunaPdf('Quant.', 1.5, 'right'),
            ColunaPdf('Valor (custo)', 2, 'right'),
          ],
          rows: [
            for (final p in porProduto) Linha([p['nome_produto'], p['categoria'], p['unidade'], numBr(p['quantidade']), brl(p['valor_total'])]),
            Linha(['TOTAL', '', '', '', brl(d['valorTotal'])], negrito: true),
          ],
        ),
        SecaoPdf(
          heading: 'Registros',
          columns: const [
            ColunaPdf('Data', 2.4),
            ColunaPdf('Produto', 4),
            ColunaPdf('Motivo', 2.2),
            ColunaPdf('Quant.', 1.4, 'right'),
            ColunaPdf('Valor', 1.8, 'right'),
            ColunaPdf('Responsável', 2.4),
          ],
          rows: [
            for (final r in registros)
              Linha([
                r['data_movimentacao'],
                r['produto_nome'],
                r['motivo_perda'],
                '${numBr(r['quantidade'])} ${toStr(r['unidade'])}',
                brl(r['valor_total']),
                r['usuario_nome'],
              ]),
          ],
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ atendimento
  /// Handler shelf de todo o servidor.
  Future<Response> call(Request req) async {
    try {
      return await _atender(req);
    } catch (err, st) {
      // Último recurso: um erro aqui não pode derrubar o processo.
      logger.log('ERRO', 'falha_interna', {'rota': sliceStr(req.requestedUri.toString(), 200), 'erro': '$err\n$st'});
      return Response(500, headers: cabecalhosSeguranca);
    }
  }

  Response _texto(int status, String texto, [Map<String, String> extra = const {}]) =>
      Response(status, body: utf8.encode(texto), headers: {...extra, ...cabecalhosSeguranca});

  Future<Response> _atender(Request req) async {
    String pathname;
    try {
      var caminho = req.requestedUri.path;
      if (caminho.isEmpty) caminho = '/';
      pathname = decodeURIComponent(caminho);
      if (pathname.contains('\u0000')) throw const ErroUri();
    } catch (_) {
      return Response(
        400,
        body: utf8.encode('Endereço inválido.'),
        headers: {'Content-Type': 'text/plain; charset=UTF-8', ...cabecalhosSeguranca},
      );
    }
    final metodo = req.method;

    if (pathname.startsWith('/api/')) return _api(req, metodo, pathname);

    // Arquivos enviados (imagens de produtos)
    if (pathname.startsWith('/uploads/')) {
      final f = caminhos.join([pastaUploads, caminhos.basename(pathname)]);
      Uint8List buf;
      try {
        buf = await File(f).readAsBytes();
      } catch (_) {
        return _texto(404, 'Não encontrado');
      }
      return Response(200, body: buf, headers: {
        'Content-Type': _mime[caminhos.extname(f).toLowerCase()] ?? 'application/octet-stream',
        'Cache-Control': 'public, max-age=86400',
        ...cabecalhosSeguranca,
        ..._cors(req),
      });
    }

    // Frontend estático (SPA)
    final arquivo = caminhos.join([pastaWeb, pathname == '/' ? 'index.html' : pathname]);
    if (!arquivo.startsWith('$pastaWeb${caminhos.sep}')) return _texto(403, 'Acesso Negado');
    Uint8List conteudo;
    try {
      conteudo = await File(arquivo).readAsBytes();
    } catch (_) {
      if (caminhos.extname(pathname).isNotEmpty) return _texto(404, 'Não encontrado');
      try {
        final idx = await File(caminhos.join([pastaWeb, 'index.html'])).readAsBytes();
        return Response(200, body: idx, headers: {'Content-Type': 'text/html; charset=UTF-8', ...cabecalhosSeguranca});
      } catch (_) {
        return _texto(404, 'App web não encontrado. Rode "flutter build web" na pasta app.', {'Content-Type': 'text/plain; charset=UTF-8'});
      }
    }
    final ext = caminhos.extname(arquivo).toLowerCase();
    return Response(200, body: conteudo, headers: {
      'Content-Type': _mime[ext] ?? 'application/octet-stream',
      'Cache-Control': 'no-cache',
      ...cabecalhosSeguranca,
    });
  }

  Future<Response> _api(Request req, String metodo, String pathname) async {
    final cors = _cors(req);
    if (metodo == 'OPTIONS' && cors.isNotEmpty) return Response(204, headers: {...cors, ...cabecalhosSeguranca});
    Obj? user;
    try {
      final rota = _rotas.where((r) => r.metodo == metodo && r.re.hasMatch(pathname)).firstOrNull;
      if (rota == null) {
        if (_rotas.any((r) => r.re.hasMatch(pathname))) throw HttpErro(405, 'Método não permitido.');
        throw HttpErro(404, 'Rota não encontrada.');
      }
      final m = rota.re.firstMatch(pathname)!;
      final params = {for (var i = 0; i < rota.chaves.length; i++) rota.chaves[i]: m[i + 1]!};
      final dbUser = await dados.getSessionUser(tokenDaRequisicao(req));
      user = dbUser != null ? dados.publicUser(dbUser) : null;
      if (!rota.publica && user == null) throw HttpErro(401, 'Sessão expirada. Faça login novamente.');
      final ctx = Contexto(req, params, lerQuery(req.requestedUri.query), user, _ip(req));
      if (user != null && rota.perm != null) _exigir(ctx, rota.perm!);
      if (const ['POST', 'PUT', 'PATCH', 'DELETE'].contains(metodo)) ctx.body = await _lerCorpo(req);
      final out = await rota.fn(ctx);
      if (user != null && metodo != 'GET' && !pathname.startsWith('/api/auth/')) {
        logger.log('INFO', 'operacao', {'metodo': metodo, 'rota': pathname}, toStr(user['email']));
      }
      if (out.bytes != null) {
        return Response(out.status, body: out.bytes, headers: {...cabecalhosSeguranca, ...cors, ...out.cabecalhos});
      }
      return _json(out.status, out.corpo, {...cors, ...out.cabecalhos});
    } catch (err, st) {
      // Só erros de regra (HttpErro) mostram a própria mensagem; o resto é falha interna.
      final conhecido = err is HttpErro;
      final status = conhecido ? err.status : 500;
      final quem = user != null ? toStr(user['email']) : null;
      if (!conhecido) {
        logger.log('ERRO', 'falha_interna', {'rota': pathname, 'erro': '$err\n$st'}, quem);
      } else if (status >= 500) {
        // 5xx de regra (ex.: 503 do fornecedor simulado) é falha de integração prevista, não erro do sistema.
        logger.log('AVISO', 'falha_externa', {'rota': pathname, 'status': status.toDouble(), 'motivo': err.mensagem}, quem);
      } else if (status == 401 || status == 403) {
        logger.log('AVISO', 'acesso_negado', {'rota': pathname, 'status': status.toDouble(), 'motivo': err.mensagem}, quem);
      }
      final mensagem = conhecido ? err.mensagem : 'Erro interno no servidor. Tente novamente; se persistir, avise o administrador.';
      final resp = _json(status, {'success': false, 'error': mensagem}, cors);
      // Corpo grande demais: o Node derrubava a conexão; aqui ela é fechada depois da resposta.
      return status == 413 ? resp.change(headers: {'Connection': 'close'}) : resp;
    }
  }

  // ------------------------------------------------------------------ subir o servidor
  /// Recebe a requisição do dart:io. Endereço com %XX malformado é respondido aqui, antes do
  /// shelf (que o recusaria com uma resposta própria), com a mesma resposta do servidor Node.
  void _receber(HttpRequest r) {
    runZonedGuarded(() async {
      var caminho = r.uri.path;
      if (caminho.isEmpty) caminho = '/';
      var valido = true;
      try {
        if (decodeURIComponent(caminho).contains('\u0000')) valido = false;
      } on ErroUri {
        valido = false;
      }
      if (valido) {
        await shelf_io.handleRequest(r, call, poweredByHeader: null);
        return;
      }
      final res = r.response;
      res.statusCode = 400;
      res.headers.set('Content-Type', 'text/plain; charset=UTF-8');
      cabecalhosSeguranca.forEach(res.headers.set);
      res.add(utf8.encode('Endereço inválido.'));
      await res.close();
    }, (erro, pilha) {
      logger.log('ERRO', 'falha_interna', {'rota': sliceStr(r.uri.toString(), 200), 'erro': '$erro\n$pilha'});
    });
  }

  /// Escuta em [host] (padrão: só este computador) e na [porta]. Devolve os sockets abertos.
  Future<List<HttpServer>> ouvir({String? host, required int porta}) async {
    final enderecos = <Object>[];
    if (host == null || host == 'localhost') {
      enderecos.addAll([InternetAddress.loopbackIPv4, InternetAddress.loopbackIPv6]);
    } else {
      enderecos.add(host);
    }
    final servidores = <HttpServer>[];
    var p = porta;
    try {
      for (final e in enderecos) {
        HttpServer s;
        try {
          s = await HttpServer.bind(e, p);
        } on SocketException catch (erro) {
          // IPv6 desligado no computador: fica só com o IPv4.
          if (e == InternetAddress.loopbackIPv6 && servidores.isNotEmpty && erro.osError?.errorCode != 10048 && erro.osError?.errorCode != 98) {
            continue;
          }
          rethrow;
        }
        p = s.port;
        s
          ..idleTimeout = const Duration(seconds: 5)
          ..autoCompress = false
          ..defaultResponseHeaders.clear();
        s.listen(_receber);
        servidores.add(s);
      }
    } catch (_) {
      for (final s in servidores) {
        await s.close(force: true);
      }
      rethrow;
    }
    return servidores;
  }
}

class _Montagem {
  _Montagem({required this.titulo, required this.subtitulo, required this.landscape, required this.sheets, required this.sections});
  final String titulo;
  final List<String> subtitulo;
  final bool landscape;
  final List<Planilha> sheets;
  final List<SecaoPdf> sections;
}
