// dados.dart - Regras de negócio, validações e consultas ao MySQL do GestFast ERP.
//
// Tradução direta do db.js do servidor Node (mesmas mensagens, mesmas validações, mesmos
// campos e a mesma ordem das chaves no JSON). Toda operação que altera estoque roda numa
// transação: se algo falhar, nada é gravado.
import 'dart:math' as math;

import 'banco.dart';
import 'erros.dart';
import 'gateways.dart' as gateways;
import 'js.dart';
import 'logger.dart';
import 'relogio.dart';
import 'senhas.dart' as senhas;

typedef Obj = Map<String, Object?>;

// ------------------------------------------------------------------ utilitários
final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
final _dataRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// Confere o formato e se o dia existe (31/02 não passa). Como no JS, anos 0-99 não passam
/// (o `Date.UTC` do JavaScript os trata como 1900-1999).
bool dataValida(Object? s) {
  if (s is! String || !_dataRe.hasMatch(s)) return false;
  final partes = s.split('-').map(int.parse).toList();
  final a = partes[0], m = partes[1], d = partes[2];
  if (a <= 99) return false;
  final dt = DateTime.utc(a, m, d);
  return dt.year == a && dt.month == m && dt.day == d;
}

// Tetos dos campos numéricos, abaixo do limite das colunas: estouro vira 400 com mensagem, não 500.
const double maxQuantidade = 999999999; // DECIMAL(12,3)
const double maxPreco = 99999999; // DECIMAL(10,2)
const double maxTotal = 9999999999.99; // DECIMAL(12,2) (totais de venda e requisição)

double _num(Object? v) => toNumber(v);

/// DATETIME do MySQL vem como 'AAAA-MM-DD HH:MM:SS'; a interface usa 'AAAA-MM-DD HH:MM'.
Object? hm(Object? s) => truthy(s) ? sliceStr(toStr(s), 16) : s;
bool _bool(Object? v) => truthy(toNumber(v));
double idNum(Object? v) {
  final n = toNumber(v);
  return isInteger(n) ? n : 0;
}

/// Texto para LIKE: escapa os curingas digitados pelo usuário.
String like(Object? t) => '%${toStr(t).replaceAllMapped(RegExp(r'[\\%_]'), (m) => '\\${m[0]}')}%';

/// Unidades que aceitam fração (peso/volume). As demais só aceitam quantidades inteiras.
bool aceitaFracao(Object? un) => const ['kg', 'lt', 'l'].contains(toStr(or(un, '')).toLowerCase());

void validarSaldoTeto(Obj prod, double saldo) {
  if (saldo > maxQuantidade) {
    throw erro('O estoque de "${toStr(prod['nome_produto'])}" ficaria grande demais (máximo ${numStr(maxQuantidade)}).');
  }
}

double validarSaldo(Obj prod, double saldo) {
  validarSaldoTeto(prod, saldo);
  return saldo;
}

double validarQuantidade(Obj prod, Object? valor, [String rotulo = 'A quantidade']) {
  final q = toNumber(valor);
  if (!q.isFinite || r3(q) <= 0) throw erro('$rotulo deve ser maior que zero.');
  if (q > maxQuantidade) throw erro('$rotulo é grande demais.');
  if (!aceitaFracao(prod['unidade']) && !isInteger(q)) {
    throw erro('"${toStr(prod['nome_produto'])}" é controlado em ${toStr(prod['unidade'])} e só aceita quantidades inteiras.');
  }
  return r3(q);
}

/// Itens enviados pelo cliente precisam ser objetos.
List<Obj> validarItens(List<Object?> itens) {
  if (itens.any((i) => i is! Map)) throw erro('A lista de itens é inválida.');
  return [for (final i in itens) (i as Map).cast<String, Object?>()];
}

String validarTexto(Object? valor, String rotulo, {bool obrigatorio = false, int min = 10, int max = 5000}) {
  final t = txt(valor);
  if (t.isEmpty) {
    if (obrigatorio) throw erro('$rotulo é obrigatório(a) e deve ter entre $min e $max caracteres.');
    return '';
  }
  if (t.length < min || t.length > max) throw erro('$rotulo deve ter entre $min e $max caracteres.');
  return t;
}

const formasPagamento = ['Dinheiro', 'Cartão Débito', 'Cartão Crédito', 'PIX'];
const situacoesAbertas = ['Em Aberto', 'Cotado', 'AF Gerada'];
const motivosPerda = ['Vencido', 'Quebra/Avaria', 'Sobra do dia', 'Outro'];

// ------------------------------------------------------------------ consultas e conversões de linhas
const _sqlUsuario = 'SELECT u.*, p.nome_perfil FROM usuario u JOIN perfil p ON p.id_perfil = u.id_perfil';

Obj? mapProduto(Obj? p) {
  if (p == null) return null;
  return {
    ...p,
    'descricao': or(p['descricao'], ''),
    'peso': or(p['peso'], ''),
    'lote': or(p['lote'], ''),
    'validade': or(p['validade'], ''),
    'imagem': or(p['imagem'], ''),
  };
}

const _sqlMov =
    '''SELECT m.*, p.nome_produto AS produto_nome, p.codigo_barras, p.unidade, u.nome AS usuario_nome
  FROM movimentacao_estoque m JOIN produto p ON p.id_produto = m.id_produto LEFT JOIN usuario u ON u.id_usuario = m.id_usuario''';

Obj mapMov(Obj m) => {
      'id_movimentacao': m['id_movimentacao'],
      'tipo_movimentacao': m['tipo_movimentacao'],
      'quantidade': m['quantidade'],
      'data_movimentacao': hm(m['data_movimentacao']),
      'observacao': or(m['observacao'], ''),
      'id_produto': m['id_produto'],
      'produto_nome': m['produto_nome'],
      'codigo_barras': m['codigo_barras'],
      'unidade': m['unidade'],
      'valor_unitario': m['valor_unitario'],
      'valor_total': r2(_num(m['quantidade']) * _num(m['valor_unitario'])),
      'id_usuario': m['id_usuario'],
      'usuario_nome': or(m['usuario_nome'], 'Sistema'),
      'origem': m['origem'],
      'motivo_perda': or(m['motivo_perda'], null),
    };

const _sqlVenda = '''SELECT v.*, u.nome AS usuario_nome, uc.nome AS cancelada_por_nome, ua.nome AS autorizada_por_nome,
    ue.nome AS editada_por_nome
  FROM venda v JOIN usuario u ON u.id_usuario = v.id_usuario
  LEFT JOIN usuario uc ON uc.id_usuario = v.cancelada_por
  LEFT JOIN usuario ua ON ua.id_usuario = v.autorizada_por
  LEFT JOIN usuario ue ON ue.id_usuario = v.editada_por''';

Obj mapVenda(Obj v, Object? itens) {
  final o = <String, Object?>{
    'id_venda': v['id_venda'],
    'codigo_venda': v['codigo_venda'],
    'data_venda': hm(v['data_venda']),
    'valor_subtotal': v['valor_subtotal'],
    'desconto': v['desconto'],
    'desconto_tipo': v['desconto_tipo'],
    'desconto_informado': v['desconto_informado'],
    'valor_total': v['valor_total'],
    'forma_pagamento': v['forma_pagamento'],
    'valor_recebido': v['valor_recebido'],
    'troco': v['troco'],
    'nsu': v['nsu'],
    'status_venda': v['status_venda'],
    'id_usuario': v['id_usuario'],
    'usuario_nome': v['usuario_nome'],
    'itens': itens,
  };
  if (v['status_venda'] == 'Cancelada') {
    o.addAll({
      'motivo_cancelamento': v['motivo_cancelamento'],
      'cancelada_por': v['cancelada_por_nome'],
      'autorizada_por': v['autorizada_por_nome'],
      'data_cancelamento': hm(v['data_cancelamento']),
    });
  }
  if (truthy(v['editada_por'])) o.addAll({'editada_por': v['editada_por_nome'], 'data_edicao': hm(v['data_edicao'])});
  return o;
}

const _sqlReq = 'SELECT r.*, f.nome AS fornecedor FROM requisicao r JOIN fornecedor f ON f.id_fornecedor = r.id_fornecedor';

/// Função que grava a imagem do produto e devolve o caminho público (`uploads/...`).
typedef GravarImagem = String Function(Object idRef);

class Dados {
  Dados({required this.banco, required this.relogio, required this.logger});

  final Banco banco;
  final Relogio relogio;
  final Logger logger;

  /// Pontos de troca para os testes (o Node fazia isso trocando a função do módulo).
  Future<bool> Function(Object? senha, Object? hash) verificarSenha = senhas.verificarSenha;
  Future<String> Function(Object? senha) hashSenha = senhas.hashSenha;

  /// Hash de uma senha que nunca confere: iguala o tempo de resposta do login.
  late final Future<String> _hashFalso = senhas.hashSenha('senha-que-nunca-confere');

  String dataISO([int? ms]) => relogio.dataISO(ms);
  String dataHora([int? ms]) => relogio.dataHora(ms);

  // Consulta direta (usada nos testes e em leituras simples).
  Future<List<Registro>> query(String sql, [List<Object?> params = const []]) => banco.linhas(sql, params);

  // Transação: roda fn(c); erro = rollback de tudo.
  // Os produtos travados na transação (travarProdutos / getProductById com lock) ficam anotados em
  // c.produtosTocados; depois do COMMIT os alertas de estoque mínimo SÓ desses produtos são atualizados,
  // numa transação curta própria (ver sincronizarAlertas).
  Future<T> tx<T>(Future<T> Function(Transacao c) fn) async {
    Set<double>? tocados;
    final r = await banco.transacao((c) async {
      tocados = c.produtosTocados;
      return fn(c);
    });
    final t = tocados!;
    if (t.isNotEmpty) {
      // A operação já foi gravada: uma falha aqui não pode virar erro para quem vendeu/movimentou.
      try {
        await sincronizarAlertas(t.toList());
      } catch (e) {
        logger.log('ERRO', 'falha_alerta_estoque', {'produtos': t.toList(), 'erro': mensagemDe(e)});
      }
    }
    return r;
  }

  // Anota o produto como alterado nesta transação (para a sincronização de alertas no fim).
  void tocar(Executor c, Object? id) {
    if (c is Transacao && truthy(id)) c.produtosTocados.add(idNum(id));
  }

  // ---------------------------------------------------------------- dados de apoio
  Future<List<Obj>> listCategorias([Executor? c]) => (c ?? banco).linhas('SELECT * FROM categoria ORDER BY id_categoria');

  Future<List<Object?>> listFornecedores([Executor? c]) async =>
      [for (final r in await (c ?? banco).linhas('SELECT nome FROM fornecedor ORDER BY id_fornecedor')) r['nome']];

  Future<List<Obj>> listPerfis([Executor? c]) => (c ?? banco).linhas('SELECT * FROM perfil ORDER BY id_perfil');

  // ---------------------------------------------------------------- configurações
  Future<Obj> getSettings([Executor? c]) async {
    final rows = await (c ?? banco).linhas('SELECT * FROM configuracao WHERE id = 1');
    if (rows.isEmpty) throw erro('Configuração do sistema não encontrada. Rode o database/seed.sql.', 500);
    final r = rows.first;
    return {
      'estabelecimento': r['estabelecimento'],
      'descontoMaximoPercent': _num(r['desconto_maximo_percent']),
      'intervaloAtualizacaoSeg': _num(r['intervalo_atualizacao_seg']),
      'simularCartaoNegado': _bool(r['simular_cartao_negado']),
      'simularFornecedorIndisponivel': _bool(r['simular_fornecedor_indisponivel']),
      'diasAlertaValidade': _num(r['dias_alerta_validade']),
    };
  }

  Future<Obj> updateSettings(Object? d) => tx((c) async {
        final s = await getSettings(c);
        if (!isUndef(prop(d, 'estabelecimento'))) {
          final e = txt(prop(d, 'estabelecimento'));
          if (e.length < 3 || e.length > 150) throw erro('O nome do estabelecimento deve ter entre 3 e 150 caracteres.');
          s['estabelecimento'] = e;
        }
        if (!isUndef(prop(d, 'descontoMaximoPercent'))) {
          final n = _num(prop(d, 'descontoMaximoPercent'));
          if (!n.isFinite || n < 0 || n > 100) throw erro('O desconto máximo deve estar entre 0% e 100%.');
          s['descontoMaximoPercent'] = n;
        }
        if (!isUndef(prop(d, 'intervaloAtualizacaoSeg'))) {
          final n = _num(prop(d, 'intervaloAtualizacaoSeg'));
          if (!n.isFinite || n < 2 || n > 60) throw erro('O intervalo de atualização deve estar entre 2 e 60 segundos.');
          s['intervaloAtualizacaoSeg'] = n;
        }
        if (!isUndef(prop(d, 'diasAlertaValidade'))) {
          final n = _num(prop(d, 'diasAlertaValidade'));
          if (!isInteger(n) || n < 0 || n > 60) throw erro('O aviso de validade deve ser de 0 a 60 dias de antecedência.');
          s['diasAlertaValidade'] = n;
        }
        for (final k in ['simularCartaoNegado', 'simularFornecedorIndisponivel']) {
          final v = prop(d, k);
          if (isUndef(v)) continue;
          if (v is! bool) throw erro('As opções de simulação devem ser verdadeiro ou falso.');
          s[k] = v;
        }
        await c.query(
          '''UPDATE configuracao SET estabelecimento = ?, desconto_maximo_percent = ?, intervalo_atualizacao_seg = ?,
           simular_cartao_negado = ?, simular_fornecedor_indisponivel = ?, dias_alerta_validade = ? WHERE id = 1''',
          [
            s['estabelecimento'],
            s['descontoMaximoPercent'],
            s['intervaloAtualizacaoSeg'],
            s['simularCartaoNegado'],
            s['simularFornecedorIndisponivel'],
            s['diasAlertaValidade'],
          ],
        );
        return s;
      });

  // ---------------------------------------------------------------- usuários, sessões e login
  Obj? publicUser(Obj? u) {
    if (u == null) return null;
    final resto = Map<String, Object?>.of(u)
      ..remove('senha')
      ..remove('nome_perfil');
    return {...resto, 'cargo': or(resto['cargo'], ''), 'perfil': or(u['nome_perfil'], '')};
  }

  Future<Obj?> getUserById(Object? id, [Executor? c]) async {
    final rows = await (c ?? banco).linhas('$_sqlUsuario WHERE u.id_usuario = ?', [idNum(id)]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<Obj?> getUserByEmail(Object? email, [Executor? c]) async {
    final rows = await (c ?? banco).linhas('$_sqlUsuario WHERE u.email = ?', [jsLower(txt(email))]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<Obj> authenticate(Object? email, Object? senha) async {
    if (txt(email).isEmpty || !truthy(senha)) throw erro('Informe o e-mail e a senha.');
    final u = await getUserByEmail(email);
    final confere = await verificarSenha(senha, u != null ? u['senha'] : await _hashFalso);
    if (u == null || !confere) throw erro('E-mail ou senha incorretos', 401);
    if (u['status'] != 'Ativo') throw erro('Sua conta está inativa. Entre em contato com o administrador', 403);
    return u;
  }

  // Autorização de gerente (cancelamento de vendas): exige credenciais de Administrador ou BackOffice.
  Future<Obj> authorizeManager(Object? email, Object? senha, [List<String> aceitos = const ['Administrador', 'BackOffice']]) async {
    final u = await getUserByEmail(email);
    if (u == null ||
        u['status'] != 'Ativo' ||
        !await verificarSenha(or(senha, ''), u['senha']) ||
        !aceitos.contains(u['nome_perfil'])) {
      throw erro('Autorização negada: informe e-mail e senha de um perfil gerente válido.', 403);
    }
    return u;
  }

  Future<({String token, int? maxAgeSeg})> createSession(Object? idUsuario, Object? lembrar) async {
    final token = senhas.novoToken();
    final agora = relogio.agoraMs();
    final l = truthy(lembrar);
    await banco.query('DELETE FROM sessao WHERE expira <= ?', [agora]);
    await banco.query(
      'INSERT INTO sessao (hash, id_usuario, lembrar, criado, expira) VALUES (?, ?, ?, ?, ?)',
      [senhas.hashToken(token), idUsuario, l, agora, agora + (l ? 30 * 86400000 : 8 * 3600000)],
    );
    return (token: token, maxAgeSeg: l ? 30 * 86400 : null);
  }

  Future<Obj?> getSessionUser(String? token) async {
    if (token == null || token.isEmpty) return null;
    final rows = await banco.linhas(
      "$_sqlUsuario JOIN sessao s ON s.id_usuario = u.id_usuario WHERE s.hash = ? AND s.expira > ? AND u.status = 'Ativo'",
      [senhas.hashToken(token), relogio.agoraMs()],
    );
    if (rows.isEmpty) return null;
    return Map.of(rows.first)
      ..remove('hash')
      ..remove('lembrar')
      ..remove('criado')
      ..remove('expira');
  }

  Future<void> deleteSession(String? token) async {
    if (token == null || token.isEmpty) return;
    await banco.query('DELETE FROM sessao WHERE hash = ?', [senhas.hashToken(token)]);
  }

  Future<bool> changePassword(Object? id, Object? atual, Object? nova, String? tokenAtual) => tx((c) async {
        final u = await getUserById(id, c);
        if (u == null || !await verificarSenha(or(atual, ''), u['senha'])) throw erro('A senha atual está incorreta.');
        validarSenha(nova);
        await c.query('UPDATE usuario SET senha = ? WHERE id_usuario = ?', [await hashSenha(nova), u['id_usuario']]);
        await c.query('DELETE FROM sessao WHERE id_usuario = ? AND hash <> ?', [u['id_usuario'], senhas.hashToken(tokenAtual ?? '')]);
        return true;
      });

  void validarSenha(Object? s) {
    if (!truthy(s) || toStr(s).length < 6 || toStr(s).length > 100) throw erro('A senha deve ter entre 6 e 100 caracteres.');
  }

  Future<({String token, Obj user})?> createResetToken(Object? email) async {
    final u = await getUserByEmail(email);
    if (u == null || u['status'] != 'Ativo') return null;
    final token = senhas.novoToken();
    await banco.query('DELETE FROM token_reset WHERE expira <= ? OR id_usuario = ?', [relogio.agoraMs(), u['id_usuario']]);
    await banco.query(
      'INSERT INTO token_reset (hash, id_usuario, expira) VALUES (?, ?, ?)',
      [senhas.hashToken(token), u['id_usuario'], relogio.agoraMs() + 30 * 60000],
    );
    return (token: token, user: u);
  }

  Future<Obj?> resetPassword(Object? token, Object? nova) => tx((c) async {
        final h = senhas.hashToken(or(token, ''));
        final rows = await c.linhas('SELECT * FROM token_reset WHERE hash = ? AND expira > ? FOR UPDATE', [h, relogio.agoraMs()]);
        if (rows.isEmpty) throw erro('O link de redefinição é inválido ou expirou.');
        final t = rows.first;
        validarSenha(nova);
        await c.query('UPDATE usuario SET senha = ? WHERE id_usuario = ?', [await hashSenha(nova), t['id_usuario']]);
        await c.query('DELETE FROM token_reset WHERE hash = ?', [h]);
        await c.query('DELETE FROM sessao WHERE id_usuario = ?', [t['id_usuario']]);
        return getUserById(t['id_usuario'], c);
      });

  Future<List<Obj?>> listUsers({Object? q, Object? idPerfil, Object? status}) async {
    final where = <String>[], params = <Object?>[];
    if (truthy(idPerfil)) {
      where.add('u.id_perfil = ?');
      params.add(idNum(idPerfil));
    }
    if (truthy(status)) {
      where.add('u.status = ?');
      params.add(status);
    }
    if (txt(q).isNotEmpty) {
      where.add('(u.nome LIKE ? OR u.email LIKE ? OR u.cargo LIKE ?)');
      params.addAll([like(txt(q)), like(txt(q)), like(txt(q))]);
    }
    final rows = await banco.linhas('$_sqlUsuario${where.isNotEmpty ? ' WHERE ${where.join(' AND ')}' : ''} ORDER BY u.id_usuario', params);
    return rows.map(publicUser).toList();
  }

  Future<double> adminsAtivos(Object? excluindoId, [Executor? c]) async {
    final rows = await (c ?? banco).linhas(
      '''SELECT COUNT(*) AS n FROM usuario u JOIN perfil p ON p.id_perfil = u.id_perfil
       WHERE u.status = 'Ativo' AND p.nome_perfil = 'Administrador' AND u.id_usuario <> ?''',
      [idNum(excluindoId)],
    );
    return _num(rows.first['n']);
  }

  Future<bool> perfilExiste(Object? id, Executor c) async =>
      (await c.linhas('SELECT 1 FROM perfil WHERE id_perfil = ?', [idNum(id)])).isNotEmpty;

  Future<Obj?> createUser(Object? d) => tx((c) async {
        final nome = txt(prop(d, 'nome')), email = jsLower(txt(prop(d, 'email')));
        if (nome.length < 2 || nome.length > 150) throw erro('Informe o nome do funcionário (2 a 150 caracteres).');
        if (!_emailRe.hasMatch(email)) throw erro('Informe um login (e-mail) válido.');
        validarSenha(prop(d, 'senha'));
        if (!await perfilExiste(prop(d, 'id_perfil'), c)) throw erro('Selecione um perfil de acesso válido.');
        if (await getUserByEmail(email, c) != null) throw erro('O login informado já está em uso. Informe outro identificador.');
        final r = await c.query(
          "INSERT INTO usuario (nome, email, senha, cargo, status, data_criacao, id_perfil) VALUES (?, ?, ?, ?, 'Ativo', ?, ?)",
          [nome, email, await hashSenha(prop(d, 'senha')), sliceStr(txt(prop(d, 'cargo')), 100), dataISO(), _num(prop(d, 'id_perfil'))],
        );
        return publicUser(await getUserById(r.insertId, c));
      });

  Future<Obj?> updateUser(Object? id, Object? d, Obj? ator, String? tokenAtual) => tx((c) async {
        final u = await getUserById(id, c);
        if (u == null) throw erro('Funcionário não encontrado.', 404);
        if (!isUndef(prop(d, 'nome'))) {
          final nome = txt(prop(d, 'nome'));
          if (nome.length < 2 || nome.length > 150) throw erro('Informe o nome do funcionário (2 a 150 caracteres).');
          u['nome'] = nome;
        }
        if (!isUndef(prop(d, 'email'))) {
          final email = jsLower(txt(prop(d, 'email')));
          if (!_emailRe.hasMatch(email)) throw erro('Informe um login (e-mail) válido.');
          final outro = await getUserByEmail(email, c);
          if (outro != null && outro['id_usuario'] != u['id_usuario']) {
            throw erro('O login informado já está em uso. Informe outro identificador.');
          }
          u['email'] = email;
        }
        if (!isUndef(prop(d, 'cargo'))) u['cargo'] = sliceStr(txt(prop(d, 'cargo')), 100);
        if (!isUndef(prop(d, 'id_perfil')) && _num(prop(d, 'id_perfil')) != u['id_perfil']) {
          if (!await perfilExiste(prop(d, 'id_perfil'), c)) throw erro('Selecione um perfil de acesso válido.');
          if (u['nome_perfil'] == 'Administrador' && u['status'] == 'Ativo' && !truthy(await adminsAtivos(u['id_usuario'], c))) {
            throw erro('Não é possível remover o perfil do único Administrador ativo.');
          }
          u['id_perfil'] = _num(prop(d, 'id_perfil'));
        }
        if (truthy(prop(d, 'senha'))) {
          validarSenha(prop(d, 'senha'));
          u['senha'] = await hashSenha(prop(d, 'senha'));
          // Senha de outro funcionário: derruba todas as sessões dele. A própria senha: derruba as OUTRAS
          // sessões e mantém a atual (mesma regra de changePassword).
          if (ator == null || ator['id_usuario'] != u['id_usuario']) {
            await c.query('DELETE FROM sessao WHERE id_usuario = ?', [u['id_usuario']]);
          } else {
            await c.query('DELETE FROM sessao WHERE id_usuario = ? AND hash <> ?', [u['id_usuario'], senhas.hashToken(tokenAtual ?? '')]);
          }
        }
        await c.query(
          'UPDATE usuario SET nome = ?, email = ?, cargo = ?, id_perfil = ?, senha = ? WHERE id_usuario = ?',
          [u['nome'], u['email'], u['cargo'], u['id_perfil'], u['senha'], u['id_usuario']],
        );
        return publicUser(await getUserById(u['id_usuario'], c));
      });

  Future<Obj?> setUserStatus(Object? id, Object? status, Obj? ator) => tx((c) async {
        final u = await getUserById(id, c);
        if (u == null) throw erro('Funcionário não encontrado.', 404);
        if (!const ['Ativo', 'Inativo'].contains(status)) throw erro('Situação inválida.');
        if (status == 'Inativo') {
          if (ator != null && ator['id_usuario'] == u['id_usuario']) throw erro('Você não pode desativar o seu próprio acesso.');
          if (u['nome_perfil'] == 'Administrador' && !truthy(await adminsAtivos(u['id_usuario'], c))) {
            throw erro('Não é possível desativar o único Administrador ativo.');
          }
          await c.query('DELETE FROM sessao WHERE id_usuario = ?', [u['id_usuario']]);
        }
        await c.query('UPDATE usuario SET status = ? WHERE id_usuario = ?', [status, u['id_usuario']]);
        return publicUser({...u, 'status': status});
      });

  // ---------------------------------------------------------------- produtos
  Future<List<Obj>> getProducts(Object? query, Object? categoriaId, [Object? status = 'Ativo']) async {
    if (isUndef(status)) status = 'Ativo';
    final where = <String>[], params = <Object?>[];
    if (status == 'Inativo') {
      where.add("status = 'Inativo'");
    } else if (status != 'todos') {
      where.add("status <> 'Inativo'");
    }
    if (truthy(categoriaId)) {
      where.add('id_categoria = ?');
      params.add(idNum(categoriaId));
    }
    if (txt(query).isNotEmpty) {
      where.add('(nome_produto LIKE ? OR codigo_barras LIKE ? OR descricao LIKE ?)');
      params.addAll([like(txt(query)), like(txt(query)), like(txt(query))]);
    }
    final rows = await banco.linhas('SELECT * FROM produto${where.isNotEmpty ? ' WHERE ${where.join(' AND ')}' : ''} ORDER BY id_produto', params);
    return [for (final r in rows) mapProduto(r)!];
  }

  // lock = true trava a linha até o fim da transação (evita duas vendas baixarem o mesmo saldo).
  Future<Obj?> getProductById(Object? id, [Executor? c, bool lock = false]) async {
    final ex = c ?? banco;
    final rows = await ex.linhas('SELECT * FROM produto WHERE id_produto = ?${lock ? ' FOR UPDATE' : ''}', [idNum(id)]);
    if (lock && rows.isNotEmpty) tocar(ex, rows.first['id_produto']);
    return mapProduto(rows.isEmpty ? null : rows.first);
  }

  // Trava os produtos em ordem de id: duas operações simultâneas nunca travam uma à outra (deadlock).
  Future<void> travarProdutos(Executor c, Iterable<Object?> ids) async {
    final unicos = sortJs([...{for (final i in ids) idNum(i)}.where(truthy)], (a, b) => a - b);
    if (unicos.isEmpty) return;
    final rows = await c.linhas('SELECT id_produto FROM produto WHERE id_produto IN (?) ORDER BY id_produto FOR UPDATE', [unicos]);
    for (final r in rows) {
      tocar(c, r['id_produto']);
    }
  }

  Future<Obj> validarProduto(Obj data, Obj? existente, Executor c) async {
    final nome = txt(data['nome_produto']);
    if (nome.length < 2 || nome.length > 200) throw erro('Informe o nome do produto (2 a 200 caracteres).');
    final venda = _num(prop(data, 'preco_venda'));
    if (!venda.isFinite || venda <= 0) throw erro('O preço de venda deve ser maior que zero.');
    if (venda > maxPreco) throw erro('O preço de venda é grande demais.');
    bool vazio(Object? v) => v == '' || v == null || v is Undefined;
    final custo = vazio(prop(data, 'preco_custo')) ? 0.0 : _num(prop(data, 'preco_custo'));
    if (!custo.isFinite || custo < 0) throw erro('O preço de custo não pode ser negativo.');
    if (custo > maxPreco) throw erro('O preço de custo é grande demais.');
    final min = vazio(prop(data, 'preco_min')) ? r2(venda * 0.8) : _num(prop(data, 'preco_min'));
    final max = vazio(prop(data, 'preco_max')) ? jsMin(r2(venda * 1.3), maxPreco) : _num(prop(data, 'preco_max'));
    if (!min.isFinite || min < 0 || !max.isFinite || max <= 0) throw erro('Os preços mínimo e máximo são inválidos.');
    if (min > maxPreco || max > maxPreco) throw erro('Os preços mínimo e máximo são grandes demais.');
    if (min > venda || venda > max) throw erro('O preço de venda deve estar entre o preço mínimo e o preço máximo.');
    final emin = vazio(prop(data, 'estoque_minimo')) ? 10.0 : _num(prop(data, 'estoque_minimo'));
    if (!emin.isFinite || emin < 0) throw erro('O estoque mínimo deve ser um número maior ou igual a zero.');
    if (emin > maxQuantidade) throw erro('O estoque mínimo é grande demais.');
    // Em produto já cadastrado o saldo só muda por movimentação: o valor do formulário pode estar desatualizado.
    final qtd = existente != null
        ? _num(existente['quantidade_estoque'])
        : (vazio(prop(data, 'quantidade_estoque')) ? 0.0 : _num(prop(data, 'quantidade_estoque')));
    if (!qtd.isFinite || qtd < 0) throw erro('O estoque atual não pode ser negativo.');
    if (qtd > maxQuantidade) throw erro('O estoque atual é grande demais.');
    final unidadeTxt = txt(prop(data, 'unidade'));
    final Object? unidade = unidadeTxt.isNotEmpty ? unidadeTxt : (existente != null ? existente['unidade'] : 'UN');
    if (!aceitaFracao(unidade) && !isInteger(qtd)) throw erro('Produtos em ${toStr(unidade)} só aceitam estoque inteiro.');
    if (!aceitaFracao(unidade) && !isInteger(emin)) throw erro('Produtos em ${toStr(unidade)} só aceitam estoque mínimo inteiro.');
    final cat = idNum(prop(data, 'id_categoria'));
    final cats = await c.linhas('SELECT 1 FROM categoria WHERE id_categoria = ?', [cat]);
    if (cats.isEmpty) throw erro('Selecione uma categoria válida.');
    final descricao = validarTexto(prop(data, 'descricao'), 'A descrição do produto', min: 10, max: 5000);
    final validade = txt(prop(data, 'validade'));
    if (validade.isNotEmpty && !dataValida(validade)) throw erro('A data de validade é inválida.');
    return {
      'nome': nome,
      'venda': r2(venda),
      'custo': r2(custo),
      'min': r2(min),
      'max': r2(max),
      'emin': r3(emin),
      'qtd': r3(qtd),
      'unidade': unidade,
      'cat': cat,
      'descricao': descricao,
      'validade': validade,
    };
  }

  Future<bool> codigoEmUso(String cod, Object? excetoId, Executor c) async =>
      (await c.linhas('SELECT 1 FROM produto WHERE codigo_barras = ? AND id_produto <> ?', [cod, idNum(excetoId)])).isNotEmpty;

  Future<Obj?> saveProduct(Obj data, Obj? ator, GravarImagem? gravarImagem) => tx((c) async {
        final idInformado = prop(data, 'id_produto');
        final existente = truthy(idInformado) ? await getProductById(idInformado, c, true) : null;
        if (truthy(idInformado) && existente == null) throw erro('Produto não encontrado.', 404);
        final v = await validarProduto(data, existente, c);
        var cod = txt(prop(data, 'codigo_barras'));
        if (cod.isNotEmpty && await codigoEmUso(cod, existente != null ? existente['id_produto'] : 0, c)) {
          throw erro('O código "$cod" já está cadastrado em outro produto.');
        }
        final imagem = gravarImagem?.call(existente != null ? existente['id_produto']! : 'novo');
        final campos = <String, Object?>{
          'nome_produto': v['nome'],
          'descricao': v['descricao'],
          'unidade': v['unidade'],
          'peso': txt(prop(data, 'peso')),
          'preco_custo': v['custo'],
          'preco_venda': v['venda'],
          'preco_min': v['min'],
          'preco_max': v['max'],
          'quantidade_estoque': v['qtd'],
          'estoque_minimo': v['emin'],
          'id_categoria': v['cat'],
          'lote': txt(prop(data, 'lote')),
          'validade': or(v['validade'], null),
        };
        if (imagem != null) campos['imagem'] = imagem;
        if (existente != null) {
          if (cod.isNotEmpty) campos['codigo_barras'] = cod;
          if (!truthy(campos['lote'])) campos['lote'] = or(existente['lote'], '-');
          await c.query('UPDATE produto SET ? WHERE id_produto = ?', [campos, existente['id_produto']]);
          return getProductById(existente['id_produto'], c);
        }
        if (!truthy(campos['lote'])) campos['lote'] = 'L-${numStr((100000 + _aleatorio() * 900000).floorToDouble())}';
        // Sem código informado: grava um provisório e depois gera 789100 + id (como na versão anterior).
        final r = await c.query('INSERT INTO produto SET ?', [
          {
            ...campos,
            'codigo_barras': cod.isNotEmpty ? cod : 'TMP-${senhas.novoToken().substring(0, 16)}',
            'status': 'Ativo',
            'imagem': or(campos['imagem'], ''),
          },
        ]);
        tocar(c, r.insertId);
        if (cod.isEmpty) {
          cod = '789100${r.insertId.toString().padLeft(2, '0')}';
          while (await codigoEmUso(cod, r.insertId, c)) {
            cod += '1';
          }
          await c.query('UPDATE produto SET codigo_barras = ? WHERE id_produto = ?', [cod, r.insertId]);
        }
        final criado = (await getProductById(r.insertId, c))!;
        // O estoque inicial também entra no histórico, para o relatório bater com o saldo.
        if (_num(v['qtd']) > 0) {
          await addMovimentacao(
            c,
            {
              'tipo_movimentacao': 'Entrada',
              'quantidade': v['qtd'],
              'origem': 'ajuste',
              'observacao': 'Estoque inicial do cadastro do produto',
            },
            criado,
            ator,
          );
        }
        return criado;
      });

  Future<Obj> setProductStatus(Object? id, Object? status) => tx((c) async {
        final p = await getProductById(id, c, true);
        if (p == null) throw erro('Produto não encontrado.', 404);
        if (!const ['Ativo', 'Inativo'].contains(status)) throw erro('Situação inválida.');
        if (p['status'] == status) throw erro(status == 'Inativo' ? 'Este produto já está inativo.' : 'Este produto já está ativo.');
        await c.query('UPDATE produto SET status = ? WHERE id_produto = ?', [status, p['id_produto']]);
        return {...p, 'status': status};
      });

  // ---------------------------------------------------------------- alertas de estoque (RF 11)
  // Abre alerta para produto ativo no mínimo ou abaixo; resolve os que voltaram ao normal.
  // Recebe só os produtos alterados e roda numa transação curta, depois do COMMIT da operação:
  //  1) trava esses produtos (FOR UPDATE, em ordem de id) — só record locks;
  //  2) lê os alertas ativos com leitura simples, depois do lock;
  //  3) grava por id (INSERT novo / UPDATE por id_alerta), sem varrer tabelas.
  Future<void> sincronizarAlertas(List<Object?> ids) async {
    final unicos = sortJs([...{for (final i in ids) idNum(i)}.where(truthy)], (a, b) => a - b);
    if (unicos.isEmpty) return;
    await banco.transacao((c) async {
      final prods = await c.linhas(
        'SELECT id_produto, nome_produto, status, quantidade_estoque, estoque_minimo FROM produto WHERE id_produto IN (?) ORDER BY id_produto FOR UPDATE',
        [unicos],
      );
      if (prods.isEmpty) return;
      final ativos = await c.linhas(
        "SELECT id_alerta, id_produto FROM alerta_estoque WHERE id_produto IN (?) AND status_alerta = 'Ativo'",
        [unicos],
      );
      final critico = <Object?, bool>{
        for (final p in prods)
          p['id_produto']: p['status'] == 'Ativo' && _num(p['quantidade_estoque']) <= _num(p['estoque_minimo']),
      };
      final comAlerta = {for (final a in ativos) a['id_produto']};
      final quando = dataHora();
      final novos = [
        for (final p in prods)
          if (critico[p['id_produto']]! && !comAlerta.contains(p['id_produto']))
            [quando, sliceStr('Atenção: ${toStr(p['nome_produto'])} atingiu o estoque mínimo', 255), 'Ativo', p['id_produto']],
      ];
      final resolver = [
        for (final a in ativos)
          if (critico.containsKey(a['id_produto']) && !critico[a['id_produto']]!) a['id_alerta'],
      ];
      if (novos.isNotEmpty) {
        await c.query('INSERT INTO alerta_estoque (data_alerta, mensagem, status_alerta, id_produto) VALUES ?', [novos]);
      }
      if (resolver.isNotEmpty) {
        await c.query("UPDATE alerta_estoque SET status_alerta = 'Resolvido' WHERE id_alerta IN (?)", [resolver]);
      }
    });
  }

  // Sincronização completa, para rodar uma vez ao subir o servidor (lotes de 200 produtos).
  Future<void> sincronizarTodosAlertas() async {
    final rows = await banco.linhas('SELECT id_produto FROM produto ORDER BY id_produto');
    for (var i = 0; i < rows.length; i += 200) {
      await sincronizarAlertas([for (final r in rows.skip(i).take(200)) r['id_produto']]);
    }
  }

  Future<List<Obj>> getAlertasCriticos() async {
    final rows = await banco.linhas(
      '''SELECT a.id_alerta, a.data_alerta, a.mensagem, p.id_produto, p.nome_produto, p.unidade, p.quantidade_estoque,
              p.estoque_minimo, p.lote, p.id_categoria AS categoria_id
       FROM alerta_estoque a JOIN produto p ON p.id_produto = a.id_produto
       WHERE a.status_alerta = 'Ativo' ORDER BY a.id_alerta''',
    );
    return [
      for (final a in rows) {...a, 'lote': or(a['lote'], ''), 'data_alerta': hm(a['data_alerta'])},
    ];
  }

  // ---------------------------------------------------------------- alerta de validade
  // Produtos ativos, com saldo, vencidos ou que vencem em até N dias (N vem das configurações).
  Future<Obj> getValidades([Executor? c]) async {
    final ex = c ?? banco;
    final dias = (await getSettings(ex))['diasAlertaValidade'] as double;
    final hoje = dataISO();
    final rows = await ex.linhas(
      '''SELECT p.id_produto, p.nome_produto, p.codigo_barras, p.unidade, p.lote, p.validade, p.quantidade_estoque, p.preco_custo,
              c.nome_categoria AS categoria, DATEDIFF(p.validade, ?) AS dias_restantes
       FROM produto p JOIN categoria c ON c.id_categoria = p.id_categoria
       WHERE p.status = 'Ativo' AND p.validade IS NOT NULL AND p.quantidade_estoque > 0 AND p.validade <= ?
       ORDER BY p.validade, p.nome_produto''',
      [hoje, dataISO(relogio.deslocar(dias))],
    );
    final itens = [
      for (final p in rows)
        () {
          final d = _num(p['dias_restantes']);
          return <String, Object?>{
            ...p,
            'lote': or(p['lote'], ''),
            'dias_restantes': d,
            'valor_em_risco': r2(_num(p['quantidade_estoque']) * _num(p['preco_custo'])),
            'situacao': d < 0 ? 'Vencido' : (d == 0 ? 'Vence hoje' : 'Vencendo'),
          };
        }(),
    ];
    return {
      'dias': dias,
      'hoje': hoje,
      'vencidos': itens.where((i) => (i['dias_restantes'] as double) < 0).length.toDouble(),
      'itens': itens,
    };
  }

  // ---------------------------------------------------------------- dashboard (RF 10)
  Future<Obj> getDashboardData(Obj? usuario) async {
    final hoje = dataISO();
    final ativos = await banco.linhas("SELECT id_categoria, quantidade_estoque FROM produto WHERE status = 'Ativo'");
    final alertas = await getAlertasCriticos();
    final validades = await getValidades();
    final vh = (await banco.linhas(
      "SELECT COUNT(*) AS n, COALESCE(SUM(valor_total), 0) AS total FROM venda WHERE status_venda = 'Concluída' AND DATE(data_venda) = ?",
      [hoje],
    ))
        .first;
    final ra = (await banco.linhas('SELECT COUNT(*) AS n FROM requisicao WHERE situacao IN (?)', [situacoesAbertas])).first;
    final categorias = await listCategorias();
    final totalEmEstoque = ativos.fold<double>(0, (a, p) => a + _num(p['quantidade_estoque']));
    final faturamentoHoje = _num(vh['total']), vendasHoje = _num(vh['n']);
    final categoriasMap = <Object?, Obj>{};
    for (final c in categorias) {
      categoriasMap[c['id_categoria']] = {'nome': c['nome_categoria'], 'total': 0.0};
    }
    for (final p in ativos) {
      final cm = categoriasMap[p['id_categoria']];
      if (cm != null) cm['total'] = (cm['total'] as double) + _num(p['quantidade_estoque']);
    }
    final ultimasCompras = await listRequisicoes(limite: 6);
    return {
      'usuarioAtivo': (usuario != null && !isUndef(prop(usuario, 'perfil'))) ? usuario : publicUser(usuario),
      'metricas': {
        'totalProdutos': ativos.length.toDouble(),
        'alertasCriticosCount': alertas.length.toDouble(),
        'totalItensEstoque': r3(totalEmEstoque),
        'requisicoesAbertasCount': _num(ra['n']),
        'totalVendasHoje': toFixed(r2(faturamentoHoje), 2),
        'vendasHojeCount': vendasHoje,
        'ticketMedioHoje': truthy(vendasHoje) ? toFixed(r2(faturamentoHoje / vendasHoje), 2) : '0.00',
        'produtosVencendoCount': (validades['itens'] as List).length.toDouble(),
        'produtosVencidosCount': validades['vencidos'],
      },
      'alertas': alertas,
      'validades': validades,
      'ultimasCompras': ultimasCompras,
      'distribuicaoEstoque': [
        for (final i in categoriasMap.values)
          if ((i['total'] as double) > 0)
            {
              'categoria': i['nome'],
              'quantidade': r3(i['total']),
              'porcentagem': totalEmEstoque > 0 ? toFixed(((i['total'] as double) / totalEmEstoque) * 100, 1) : '0',
            },
      ],
    };
  }

  // ---------------------------------------------------------------- requisições de compra (RF 05)
  Future<List<Obj>> montarRequisicoes(List<Obj> rows, [Executor? c]) async {
    if (rows.isEmpty) return [];
    final hist = await (c ?? banco).linhas(
      '''SELECT h.id_requisicao, h.data_registro, h.situacao, u.nome AS usuario
       FROM requisicao_historico h LEFT JOIN usuario u ON u.id_usuario = h.id_usuario
       WHERE h.id_requisicao IN (?) ORDER BY h.id_historico''',
      [for (final r in rows) r['id_requisicao']],
    );
    return [
      for (final r in rows)
        {
          ...(Map.of(r)..remove('id_fornecedor')),
          'observacao': or(r['observacao'], ''),
          'historico': [
            for (final h in hist)
              if (h['id_requisicao'] == r['id_requisicao'])
                {'data': hm(h['data_registro']), 'situacao': h['situacao'], 'usuario': or(h['usuario'], '-')},
          ],
        },
    ];
  }

  Future<List<Obj>> listRequisicoes({int? limite}) async {
    final rows = await banco.linhas(
      '$_sqlReq ORDER BY r.id_requisicao DESC${limite != null ? ' LIMIT ?' : ''}',
      limite != null ? [limite] : [],
    );
    return montarRequisicoes(rows);
  }

  Future<Obj?> getRequisicao(Object? id, [Executor? c, bool lock = false]) async {
    final ex = c ?? banco;
    final rows = await ex.linhas('$_sqlReq WHERE r.id_requisicao = ?${lock ? ' FOR UPDATE' : ''}', [idNum(id)]);
    final l = await montarRequisicoes(rows, ex);
    return l.isEmpty ? null : l.first;
  }

  Future<void> registrarHistorico(Executor c, Object? idReq, String situacao, Obj? ator) async {
    await c.query(
      'INSERT INTO requisicao_historico (id_requisicao, data_registro, situacao, id_usuario) VALUES (?, ?, ?, ?)',
      [idReq, dataHora(), situacao, ator?['id_usuario']],
    );
  }

  Future<Obj?> createRequisicao(Object? data, Obj? ator) => tx((c) async {
        final forn = await c.linhas('SELECT id_fornecedor FROM fornecedor WHERE nome = ?', [txt(prop(data, 'fornecedor'))]);
        if (!truthy(prop(data, 'fornecedor')) || forn.isEmpty) throw erro('Selecione um fornecedor da lista.');
        final idp = prop(data, 'id_produto');
        final prod = truthy(idp) ? await getProductById(idp, c) : null;
        if (truthy(idp) && prod == null) throw erro('Produto não encontrado.', 404);
        final nomeProd = prod != null ? toStr(prod['nome_produto']) : txt(prop(data, 'produto_nome'));
        if (nomeProd.isEmpty) throw erro('O nome do produto é obrigatório.');
        final qtd = _num(prop(data, 'quantidade_pedida'));
        if (!qtd.isFinite || r3(qtd) <= 0) throw erro('A quantidade pedida deve ser maior que zero.');
        if (qtd > maxQuantidade) throw erro('A quantidade pedida é grande demais.');
        final unTxt = txt(prop(data, 'unidade'));
        final Object? un = prod != null ? prod['unidade'] : (unTxt.isNotEmpty ? unTxt : 'UN');
        if (!aceitaFracao(un) && !isInteger(qtd)) throw erro('A unidade ${toStr(un)} só aceita quantidades inteiras.');
        final vuRaw = prop(data, 'valor_unitario');
        final vu = (vuRaw == '' || isUndef(vuRaw)) ? (prod != null ? _num(prod['preco_custo']) : 0.0) : _num(vuRaw);
        if (!vu.isFinite || vu < 0) throw erro('O preço unitário é inválido.');
        if (vu > maxPreco) throw erro('O preço unitário é grande demais.');
        if (r2(qtd * vu) > maxTotal) throw erro('O valor total da requisição é grande demais.');
        final prevTxt = txt(prop(data, 'previsao_entrega'));
        final prev = prevTxt.isNotEmpty ? prevTxt : dataISO(relogio.deslocar(4));
        if (!dataValida(prev) || prev.compareTo(dataISO()) < 0) throw erro('A previsão de entrega deve ser uma data a partir de hoje.');
        final obs = validarTexto(prop(data, 'observacao'), 'A observação da requisição', min: 10, max: 5000);
        gateways.comunicarFornecedor(await getSettings(c));
        // Código = maior número existente + 1 (não depende do id, que pode pular).
        final mx = (await c.linhas(
          'SELECT COALESCE(MAX(CAST(SUBSTRING(codigo_pedido, 5) AS UNSIGNED)), 9660) AS n FROM requisicao FOR UPDATE',
        ))
            .first;
        final endTxt = txt(prop(data, 'endereco_entrega'));
        final r = await c.query(
          '''INSERT INTO requisicao (codigo_pedido, id_fornecedor, id_produto, produto_nome, quantidade_pedida, quantidade_atendida, unidade,
           valor_unitario, valor_total, situacao, data_pedido, previsao_entrega, endereco_entrega, observacao)
         VALUES (?, ?, ?, ?, ?, 0, ?, ?, ?, 'Em Aberto', ?, ?, ?, ?)''',
          [
            'REQ-${numStr(_num(mx['n']) + 1)}',
            forn.first['id_fornecedor'],
            prod?['id_produto'],
            nomeProd,
            r3(qtd),
            un,
            r2(vu),
            r2(qtd * vu),
            dataISO(),
            prev,
            endTxt.isNotEmpty ? endTxt : 'Padrão - Padaria Nova York',
            obs,
          ],
        );
        await registrarHistorico(c, r.insertId, 'Em Aberto', ator);
        return getRequisicao(r.insertId, c);
      });

  Future<Obj> updateRequisicaoStatus(Object? id, Object? body, Obj? ator) => tx((c) async {
        final req = await getRequisicao(id, c, true);
        if (req == null) throw erro('Requisição não encontrada.', 404);
        final nova = prop(body, 'situacao');
        if (!const ['Cotado', 'AF Gerada', 'Cancelado', 'Finalizado'].contains(nova)) throw erro('Situação inválida.');
        if (!situacoesAbertas.contains(req['situacao'])) {
          throw erro('A requisição já está "${toStr(req['situacao'])}" e não pode mais ser alterada.');
        }
        final idr = req['id_requisicao'];
        var parcial = false;

        if (nova == 'Cotado') {
          if (req['situacao'] != 'Em Aberto') throw erro('Somente requisições em aberto podem ser cotadas.');
          await c.query("UPDATE requisicao SET situacao = 'Cotado' WHERE id_requisicao = ?", [idr]);
          await registrarHistorico(c, idr, 'Cotado', ator);
        } else if (nova == 'AF Gerada') {
          if (req['situacao'] == 'AF Gerada') throw erro('A Autorização de Fornecimento já foi gerada.');
          await c.query("UPDATE requisicao SET situacao = 'AF Gerada' WHERE id_requisicao = ?", [idr]);
          await registrarHistorico(c, idr, 'AF Gerada', ator);
        } else if (nova == 'Cancelado') {
          final just = validarTexto(prop(body, 'justificativa'), 'O motivo do cancelamento', obrigatorio: true);
          gateways.comunicarFornecedor(await getSettings(c));
          await c.query("UPDATE requisicao SET situacao = 'Cancelado', justificativa_cancelamento = ? WHERE id_requisicao = ?", [just, idr]);
          await registrarHistorico(c, idr, 'Cancelado', ator);
        } else {
          final restante = r3(_num(req['quantidade_pedida']) - _num(req['quantidade_atendida']));
          final qr = prop(body, 'quantidade_recebida');
          final recebida = (isUndef(qr) || qr == '') ? restante : _num(qr);
          if (!recebida.isFinite || r3(recebida) <= 0) throw erro('Informe a quantidade recebida (maior que zero).');
          if (recebida > restante) {
            throw erro('A quantidade recebida (${numStr(recebida)}) excede o saldo pendente do pedido (${numStr(restante)}).');
          }
          if (!aceitaFracao(req['unidade']) && !isInteger(recebida)) {
            throw erro('A unidade ${toStr(req['unidade'])} só aceita quantidades inteiras.');
          }
          final prod = truthy(req['id_produto']) ? await getProductById(req['id_produto'], c, true) : null;
          if (prod != null) {
            await c.query('UPDATE produto SET quantidade_estoque = ? WHERE id_produto = ?', [
              validarSaldo(prod, r3(_num(prod['quantidade_estoque']) + recebida)),
              prod['id_produto'],
            ]);
            await addMovimentacao(
              c,
              {
                'tipo_movimentacao': 'Entrada',
                'quantidade': recebida,
                'origem': 'requisicao',
                'observacao': 'Entrada automática por recebimento da requisição ${toStr(req['codigo_pedido'])} (${toStr(req['fornecedor'])})',
                'valor_unitario': req['valor_unitario'],
              },
              prod,
              ator,
            );
          }
          final atendida = r3(_num(req['quantidade_atendida']) + recebida);
          final fim = atendida >= _num(req['quantidade_pedida']);
          await c.query(
            'UPDATE requisicao SET quantidade_atendida = ?, situacao = ? WHERE id_requisicao = ?',
            [atendida, fim ? 'Finalizado' : req['situacao'], idr],
          );
          await registrarHistorico(c, idr, fim ? 'Finalizado' : 'Recebimento parcial (${numStr(recebida)} ${toStr(req['unidade'])})', ator);
          parcial = !fim;
        }
        return {...(await getRequisicao(idr, c))!, 'parcial': parcial};
      });

  // ---------------------------------------------------------------- movimentações de estoque (RF 04)
  // Grava a movimentação; quem chama já atualizou o saldo do produto na mesma transação.
  Future<Obj> addMovimentacao(Executor c, Obj data, Obj prod, Obj? ator) async {
    final vuInf = prop(data, 'valor_unitario');
    final vu = !isUndef(vuInf)
        ? _num(vuInf)
        : (data['tipo_movimentacao'] == 'Saída' ? _num(prod['preco_venda']) : _num(prod['preco_custo']));
    final quando = dataHora();
    final r = await c.query(
      '''INSERT INTO movimentacao_estoque (tipo_movimentacao, quantidade, data_movimentacao, observacao, origem, motivo_perda, valor_unitario, id_produto, id_usuario)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        data['tipo_movimentacao'],
        r3(prop(data, 'quantidade')),
        quando,
        or(prop(data, 'observacao'), ''),
        or(prop(data, 'origem'), 'manual'),
        or(prop(data, 'motivo_perda'), null),
        r2(vu),
        prod['id_produto'],
        ator?['id_usuario'],
      ],
    );
    return mapMov({
      'id_movimentacao': r.insertId.toDouble(),
      'tipo_movimentacao': data['tipo_movimentacao'],
      'quantidade': r3(prop(data, 'quantidade')),
      'data_movimentacao': quando,
      'observacao': prop(data, 'observacao'),
      'id_produto': prod['id_produto'],
      'produto_nome': prod['nome_produto'],
      'codigo_barras': prod['codigo_barras'],
      'unidade': prod['unidade'],
      'valor_unitario': r2(vu),
      'id_usuario': ator?['id_usuario'],
      'usuario_nome': ator?['nome'],
      'origem': or(prop(data, 'origem'), 'manual'),
      'motivo_perda': prop(data, 'motivo_perda'),
    });
  }

  // Registra uma ou várias movimentações de uma só vez (individual ou em lote).
  Future<List<Obj>> registrarMovimentacoes(Object? body, Obj? ator) => tx((c) async {
        final tipo = prop(body, 'tipo_movimentacao');
        if (!const ['Entrada', 'Saída'].contains(tipo)) throw erro('Tipo de movimentação inválido.');
        final obs = validarTexto(prop(body, 'observacao'), 'O motivo da movimentação', obrigatorio: true);
        return movimentarItens(c, tipo as String, body, (_) => {'observacao': obs}, ator);
      });

  // Perda/sobra: saída de estoque com motivo, valorizada pelo preço de custo (o que a padaria perdeu).
  Future<List<Obj>> registrarPerdas(Object? body, Obj? ator) => tx((c) async {
        final motivo = prop(body, 'motivo_perda');
        if (!motivosPerda.contains(motivo)) throw erro('Informe o motivo da perda: ${motivosPerda.join(', ')}.');
        final obs = validarTexto(prop(body, 'observacao'), 'A observação', obrigatorio: motivo == 'Outro');
        return movimentarItens(
          c,
          'Saída',
          body,
          (prod) => {'observacao': obs, 'origem': 'perda', 'motivo_perda': motivo, 'valor_unitario': prod['preco_custo']},
          ator,
        );
      });

  // Valida os itens (somando produtos repetidos), atualiza o saldo e grava uma movimentação por produto.
  Future<List<Obj>> movimentarItens(Executor c, String tipo, Object? body, Obj Function(Obj prod) extra, Obj? ator) async {
    final itensBrutos = prop(body, 'itens');
    final itens = validarItens(
      itensBrutos is List
          ? itensBrutos
          : [
              {'id_produto': prop(body, 'id_produto'), 'quantidade': prop(body, 'quantidade')},
            ],
    );
    if (itens.isEmpty) throw erro('Informe ao menos um item.');
    await travarProdutos(c, itens.map((i) => prop(i, 'id_produto')));
    final acumulado = <Object?, ({Obj prod, double qtd})>{};
    for (final it in itens) {
      final prod = await getProductById(prop(it, 'id_produto'), c, true);
      if (prod == null) throw erro('Produto não cadastrado.', 404);
      final q = validarQuantidade(prod, prop(it, 'quantidade'));
      final a = acumulado[prod['id_produto']] ?? (prod: prod, qtd: 0.0);
      acumulado[prod['id_produto']] = (prod: a.prod, qtd: r3(a.qtd + q));
    }
    final movs = <Obj>[];
    for (final (:prod, :qtd) in acumulado.values) {
      final qe = _num(prod['quantidade_estoque']);
      if (tipo == 'Saída' && qe < qtd) {
        throw erro('Estoque insuficiente de "${toStr(prod['nome_produto'])}"! Saldo disponível: ${numStr(qe)} ${toStr(prod['unidade'])}.');
      }
      final saldo = validarSaldo(prod, r3(tipo == 'Saída' ? qe - qtd : qe + qtd));
      await c.query('UPDATE produto SET quantidade_estoque = ? WHERE id_produto = ?', [saldo, prod['id_produto']]);
      movs.add(await addMovimentacao(c, {'tipo_movimentacao': tipo, 'quantidade': qtd, ...extra(prod)}, prod, ator));
    }
    return movs;
  }

  Future<List<Obj>> getMovimentacoes({Object? tipo, Object? from, Object? to}) async {
    validarPeriodo(from, to);
    final where = <String>[], params = <Object?>[];
    if (truthy(tipo)) {
      where.add('m.tipo_movimentacao = ?');
      params.add(tipo);
    }
    if (truthy(from)) {
      where.add('m.data_movimentacao >= ?');
      params.add('${toStr(from)} 00:00:00');
    }
    if (truthy(to)) {
      where.add('m.data_movimentacao <= ?');
      params.add('${toStr(to)} 23:59:59');
    }
    final rows = await banco.linhas('$_sqlMov${where.isNotEmpty ? ' WHERE ${where.join(' AND ')}' : ''} ORDER BY m.id_movimentacao DESC', params);
    return rows.map(mapMov).toList();
  }

  // ---------------------------------------------------------------- vendas (RF 07, 08, 09)
  ({String tipo, double valor}) resolverDesconto(double subtotal, Object? d, Obj? ator, Obj cfg) {
    final tipo = prop(d, 'desconto_tipo') == 'percentual' ? 'percentual' : 'valor';
    final dv = prop(d, 'desconto');
    final bruto = (dv == '' || isNullish(dv)) ? 0.0 : _num(dv);
    if (!bruto.isFinite || bruto < 0) throw erro('O desconto informado é inválido.');
    if (tipo == 'percentual' && bruto > 100) throw erro('O desconto percentual não pode passar de 100%.');
    final valor = tipo == 'percentual' ? r2(subtotal * bruto / 100) : r2(bruto);
    if (valor > subtotal) throw erro('O desconto não pode ser maior que o subtotal da venda.');
    final max = cfg['descontoMaximoPercent'] as double;
    final admin = ator != null && ator['perfil'] == 'Administrador';
    if (!admin && subtotal > 0 && (valor / subtotal) * 100 > max + 1e-9) {
      throw erro('Desconto acima do limite permitido (${numStr(max)}% do subtotal).');
    }
    return (tipo: tipo, valor: valor);
  }

  Future<Map<Object?, List<Obj>>> itensDasVendas(List<Object?> ids, [Executor? c]) async {
    if (ids.isEmpty) return {};
    final rows = await (c ?? banco).linhas(
      '''SELECT i.id_item_venda, i.id_venda, i.id_produto, p.nome_produto, p.unidade, i.quantidade, i.valor_unitario, i.subtotal
       FROM item_venda i JOIN produto p ON p.id_produto = i.id_produto WHERE i.id_venda IN (?) ORDER BY i.id_item_venda''',
      [ids],
    );
    final mapa = <Object?, List<Obj>>{for (final id in ids) id: []};
    for (final r in rows) {
      mapa[r['id_venda']]!.add(Map.of(r)..remove('id_venda'));
    }
    return mapa;
  }

  Future<Obj?> getVenda(Object? id, [Executor? c, bool lock = false]) async {
    final ex = c ?? banco;
    final rows = await ex.linhas('$_sqlVenda WHERE v.id_venda = ?${lock ? ' FOR UPDATE' : ''}', [idNum(id)]);
    if (rows.isEmpty) return null;
    final itens = await itensDasVendas([rows.first['id_venda']], ex);
    return mapVenda(rows.first, itens[rows.first['id_venda']]);
  }

  Future<List<Obj>> getVendas({Object? from, Object? to, Object? q, Object? status, int? limite}) async {
    validarPeriodo(from, to);
    final where = <String>[], params = <Object?>[];
    if (truthy(from)) {
      where.add('v.data_venda >= ?');
      params.add('${toStr(from)} 00:00:00');
    }
    if (truthy(to)) {
      where.add('v.data_venda <= ?');
      params.add('${toStr(to)} 23:59:59');
    }
    if (truthy(status)) {
      where.add('v.status_venda = ?');
      params.add(status);
    }
    if (txt(q).isNotEmpty) {
      final t = like(txt(q));
      where.add('''(v.codigo_venda LIKE ? OR u.nome LIKE ? OR v.forma_pagamento LIKE ? OR EXISTS (
        SELECT 1 FROM item_venda i JOIN produto p ON p.id_produto = i.id_produto WHERE i.id_venda = v.id_venda AND p.nome_produto LIKE ?))''');
      params.addAll([t, t, t, t]);
    }
    final rows = await banco.linhas(
      '$_sqlVenda${where.isNotEmpty ? ' WHERE ${where.join(' AND ')}' : ''} ORDER BY v.id_venda DESC${limite != null ? ' LIMIT ?' : ''}',
      limite != null ? [...params, limite] : params,
    );
    final itens = await itensDasVendas([for (final v in rows) v['id_venda']]);
    return [for (final v in rows) mapVenda(v, itens[v['id_venda']])];
  }

  Future<void> gravarItensVenda(Executor c, Object? idVenda, List<Obj> itens) async {
    if (itens.isEmpty) return;
    await c.query('INSERT INTO item_venda (id_venda, id_produto, quantidade, valor_unitario, subtotal) VALUES ?', [
      [
        for (final i in itens) [idVenda, i['id_produto'], i['quantidade'], i['valor_unitario'], i['subtotal']],
      ],
    ]);
  }

  Future<Obj?> realizarVenda(Object? data, Obj ator) => tx((c) async {
        final brutos = prop(data, 'itens');
        final itens = validarItens(brutos is List ? brutos : const []);
        if (itens.isEmpty) throw erro('Nenhum item inserido na venda.');
        await travarProdutos(c, itens.map((i) => prop(i, 'id_produto')));
        final forma = or(prop(data, 'forma_pagamento'), 'Dinheiro');
        if (!formasPagamento.contains(forma)) throw erro('Forma de pagamento inválida.');
        final formaTxt = forma as String;
        final cfg = await getSettings(c);

        final produtos = <Object?, Obj>{};
        final linhas = <String, ({Obj prod, double preco, double qtd})>{};
        for (final it in itens) {
          final prod = produtos[idNum(prop(it, 'id_produto'))] ?? await getProductById(prop(it, 'id_produto'), c, true);
          if (prod == null) throw erro('Produto não cadastrado.', 404);
          produtos[prod['id_produto']] = prod;
          if (prod['status'] != 'Ativo') throw erro('"${toStr(prod['nome_produto'])}" está inativo e não pode ser vendido.');
          final q = validarQuantidade(prod, prop(it, 'quantidade'));
          final vu = prop(it, 'valor_unitario');
          final preco = (isUndef(vu) || vu == '') ? _num(prod['preco_venda']) : _num(vu);
          if (!preco.isFinite || preco <= 0) throw erro('Preço unitário inválido.');
          final pmin = _num(prod['preco_min']), pmax = _num(prod['preco_max']);
          if (preco < pmin || preco > pmax) {
            throw erro('O preço de "${toStr(prod['nome_produto'])}" deve ficar entre R\$ ${toFixed(pmin, 2)} e R\$ ${toFixed(pmax, 2)}.');
          }
          final chave = '${toStr(prod['id_produto'])}|${numStr(preco)}';
          final l = linhas[chave] ?? (prod: prod, preco: r2(preco), qtd: 0.0);
          linhas[chave] = (prod: l.prod, preco: l.preco, qtd: r3(l.qtd + q));
        }
        final totalPorProduto = <Object?, double>{};
        for (final l in linhas.values) {
          totalPorProduto[l.prod['id_produto']] = r3((totalPorProduto[l.prod['id_produto']] ?? 0) + l.qtd);
        }
        for (final MapEntry(key: idp, value: q) in totalPorProduto.entries) {
          final p = produtos[idp]!;
          if (_num(p['quantidade_estoque']) < q) {
            throw erro(
              'Quantidade indisponível em estoque para "${toStr(p['nome_produto'])}"! Solicitado: ${numStr(q)}, em estoque: ${toStr(p['quantidade_estoque'])} ${toStr(p['unidade'])}.',
            );
          }
        }

        final itensProc = <Obj>[];
        var subtotal = 0.0;
        for (final l in linhas.values) {
          final sub = r2(l.qtd * l.preco);
          subtotal = r2(subtotal + sub);
          itensProc.add({
            'id_produto': l.prod['id_produto'],
            'nome_produto': l.prod['nome_produto'],
            'unidade': l.prod['unidade'],
            'quantidade': l.qtd,
            'valor_unitario': l.preco,
            'subtotal': sub,
          });
        }
        if (subtotal > maxTotal) throw erro('O valor total da venda é grande demais.');
        final desc = resolverDesconto(subtotal, data, ator, cfg);
        final total = r2(subtotal - desc.valor);

        double? recebido, troco;
        final vr = prop(data, 'valor_recebido');
        if (formaTxt == 'Dinheiro' && !isUndef(vr) && vr != '' && vr != null) {
          recebido = _num(vr);
          if (!recebido.isFinite || recebido < total) throw erro('O valor recebido é menor que o total da venda.');
          if (recebido > maxTotal) throw erro('O valor recebido é grande demais.');
          troco = r2(recebido - total);
        }
        final aut = gateways.autorizarPagamento(formaTxt, cfg);

        // Código provisório; depois vira VENDA-(1000 + id), como na versão anterior.
        final dInf = _num(prop(data, 'desconto'));
        final r = await c.query(
          '''INSERT INTO venda (codigo_venda, data_venda, valor_subtotal, desconto, desconto_tipo, desconto_informado, valor_total,
           forma_pagamento, valor_recebido, troco, nsu, status_venda, id_usuario)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'Concluída', ?)''',
          [
            'TMP-${senhas.novoToken().substring(0, 12)}',
            dataHora(),
            subtotal,
            desc.valor,
            desc.tipo,
            truthy(dInf) ? dInf : 0.0,
            total,
            formaTxt,
            recebido,
            troco,
            formaTxt.startsWith('Cartão') ? aut.nsu : null,
            ator['id_usuario'],
          ],
        );
        final codigo = 'VENDA-${1000 + r.insertId}';
        await c.query('UPDATE venda SET codigo_venda = ? WHERE id_venda = ?', [codigo, r.insertId]);
        await gravarItensVenda(c, r.insertId, itensProc);

        for (final MapEntry(key: idp, value: q) in totalPorProduto.entries) {
          final p = produtos[idp]!;
          await c.query('UPDATE produto SET quantidade_estoque = ? WHERE id_produto = ?', [r3(_num(p['quantidade_estoque']) - q), idp]);
        }
        for (final it in itensProc) {
          await addMovimentacao(
            c,
            {
              'tipo_movimentacao': 'Saída',
              'quantidade': it['quantidade'],
              'origem': 'venda',
              'observacao': 'Baixa automática da $codigo',
              'valor_unitario': it['valor_unitario'],
            },
            produtos[it['id_produto']]!,
            ator,
          );
        }
        return getVenda(r.insertId, c);
      });

  Future<void> estornarItensVenda(Executor c, Obj venda, Obj? ator, String motivo) async {
    final itens = (venda['itens'] as List).cast<Obj>();
    await travarProdutos(c, itens.map((i) => i['id_produto']));
    for (final item in itens) {
      final p = await getProductById(item['id_produto'], c, true);
      if (p == null) continue;
      await c.query('UPDATE produto SET quantidade_estoque = ? WHERE id_produto = ?', [
        validarSaldo(p, r3(_num(p['quantidade_estoque']) + _num(item['quantidade']))),
        p['id_produto'],
      ]);
      await addMovimentacao(
        c,
        {
          'tipo_movimentacao': 'Entrada',
          'quantidade': item['quantidade'],
          'origem': 'estorno',
          'observacao': '$motivo (${toStr(venda['codigo_venda'])})',
          'valor_unitario': item['valor_unitario'],
        },
        p,
        ator,
      );
    }
  }

  Future<Obj?> cancelarVenda(Object? id, Object? body, Obj ator, Obj? autorizador) => tx((c) async {
        final venda = await getVenda(id, c, true);
        if (venda == null) throw erro('Venda não encontrada.', 404);
        if (venda['status_venda'] == 'Cancelada') throw erro('Esta venda já está cancelada.');
        final motivo = validarTexto(prop(body, 'motivo'), 'O motivo do cancelamento', obrigatorio: true);
        await estornarItensVenda(c, venda, ator, 'Estorno de estoque por cancelamento');
        await c.query(
          '''UPDATE venda SET status_venda = 'Cancelada', motivo_cancelamento = ?, cancelada_por = ?, autorizada_por = ?, data_cancelamento = ?
         WHERE id_venda = ?''',
          [motivo, ator['id_usuario'], (autorizador ?? ator)['id_usuario'], dataHora(), venda['id_venda']],
        );
        return getVenda(venda['id_venda'], c);
      });

  Future<Obj?> editarVenda(Object? id, Object? body, Obj ator) => tx((c) async {
        final venda = await getVenda(id, c, true);
        if (venda == null) throw erro('Venda não encontrada.', 404);
        if (venda['status_venda'] != 'Concluída') throw erro('Somente vendas concluídas podem ser editadas.');
        final brutos = prop(body, 'itens');
        final novos = validarItens(brutos is List ? brutos : const []);
        final antigosItens = (venda['itens'] as List).cast<Obj>();
        await travarProdutos(c, [...novos.map((i) => prop(i, 'id_produto')), ...antigosItens.map((i) => i['id_produto'])]);
        final produtos = <Object?, Obj?>{};
        final quantidades = <Object?, double>{};
        // uma linha por produto + preço: cada item mantém o preço praticado na venda
        final linhas = <String, ({Object? idProduto, double preco, double qtd})>{};
        for (final it in novos) {
          final prod = produtos[idNum(prop(it, 'id_produto'))] ?? await getProductById(prop(it, 'id_produto'), c, true);
          if (prod == null) throw erro('Produto não cadastrado.', 404);
          produtos[prod['id_produto']] = prod;
          final q = validarQuantidade(prod, prop(it, 'quantidade'));
          final doProduto = antigosItens.where((i) => i['id_produto'] == prod['id_produto']).toList();
          Obj? anterior = doProduto.isEmpty ? null : doProduto.first;
          final idItem = prop(it, 'id_item_venda');
          if (!isUndef(idItem)) {
            final alvo = _num(idItem);
            anterior = doProduto.where((i) => i['id_item_venda'] == alvo).firstOrNull;
            if (anterior == null) throw erro('O item informado não pertence a esta venda.');
          } else if (doProduto.length > 1) {
            throw erro('"${toStr(prod['nome_produto'])}" aparece com preços diferentes nesta venda: informe qual item está sendo alterado.');
          }
          if (anterior == null && prod['status'] != 'Ativo') {
            throw erro('"${toStr(prod['nome_produto'])}" está inativo e não pode ser incluído na venda.');
          }
          final preco = anterior != null ? _num(anterior['valor_unitario']) : _num(prod['preco_venda']);
          final chave = '${toStr(prod['id_produto'])}|${numStr(preco)}';
          final l = linhas[chave] ?? (idProduto: prod['id_produto'], preco: preco, qtd: 0.0);
          linhas[chave] = (idProduto: l.idProduto, preco: l.preco, qtd: r3(l.qtd + q));
          quantidades[prod['id_produto']] = r3((quantidades[prod['id_produto']] ?? 0) + q);
        }
        if (quantidades.isEmpty) throw erro('A venda precisa ter ao menos um item. Para anulá-la, use o cancelamento.');
        final antigas = <Object?, double>{};
        for (final i in antigosItens) {
          antigas[i['id_produto']] = r3((antigas[i['id_produto']] ?? 0) + _num(i['quantidade']));
        }
        final ids = {...antigas.keys, ...quantidades.keys};
        for (final idp in ids) {
          if (!produtos.containsKey(idp)) produtos[idp] = await getProductById(idp, c, true);
          final diff = r3((quantidades[idp] ?? 0) - (antigas[idp] ?? 0));
          final p = produtos[idp]!;
          if (diff > 0 && _num(p['quantidade_estoque']) < diff) {
            throw erro(
              'Quantidade indisponível em estoque para "${toStr(p['nome_produto'])}"! Disponível para acréscimo: ${toStr(p['quantidade_estoque'])} ${toStr(p['unidade'])}.',
            );
          }
        }
        final itensNovos = <Obj>[];
        for (final l in linhas.values) {
          final p = produtos[l.idProduto]!;
          itensNovos.add({
            'id_produto': l.idProduto,
            'nome_produto': p['nome_produto'],
            'unidade': p['unidade'],
            'quantidade': l.qtd,
            'valor_unitario': l.preco,
            'subtotal': r2(l.qtd * l.preco),
          });
        }
        for (final idp in ids) {
          final diff = r3((quantidades[idp] ?? 0) - (antigas[idp] ?? 0));
          if (diff == 0) continue;
          final p = produtos[idp]!;
          await c.query(
            'UPDATE produto SET quantidade_estoque = ? WHERE id_produto = ?',
            [validarSaldo(p, r3(_num(p['quantidade_estoque']) - diff)), idp],
          );
          final ref = itensNovos.where((i) => i['id_produto'] == idp).firstOrNull ?? antigosItens.firstWhere((i) => i['id_produto'] == idp);
          await addMovimentacao(
            c,
            {
              'tipo_movimentacao': diff > 0 ? 'Saída' : 'Entrada',
              'quantidade': diff.abs(),
              'origem': 'ajuste',
              'observacao': 'Ajuste por edição da ${toStr(venda['codigo_venda'])}',
              'valor_unitario': ref['valor_unitario'],
            },
            p,
            ator,
          );
        }
        final subtotal = r2(itensNovos.fold<double>(0, (a, i) => a + (i['subtotal'] as double)));
        if (subtotal > maxTotal) throw erro('O valor total da venda é grande demais.');
        final percentual = venda['desconto_tipo'] == 'percentual';
        final desc = resolverDesconto(
          subtotal,
          {
            'desconto_tipo': venda['desconto_tipo'],
            'desconto': percentual ? venda['desconto_informado'] : jsMin(_num(venda['desconto']), subtotal),
          },
          ator,
          await getSettings(c),
        );
        final total = r2(subtotal - desc.valor);
        // Venda em dinheiro: o troco acompanha o novo total.
        Object? recebido = venda['valor_recebido'], troco = venda['troco'];
        if (venda['forma_pagamento'] == 'Dinheiro') {
          final vr = prop(body, 'valor_recebido');
          if (!isUndef(vr) && vr != null && vr != '') recebido = _num(vr);
          if (recebido != null) {
            final rec = _num(recebido);
            if (!rec.isFinite || rec < total) {
              throw erro(
                'O valor recebido (R\$ ${toFixed(rec, 2)}) não cobre o novo total da venda (R\$ ${toFixed(total, 2)}). Informe o valor recebido atualizado.',
              );
            }
            if (rec > maxTotal) throw erro('O valor recebido é grande demais.');
            recebido = r2(rec);
            troco = r2(r2(rec) - total);
          }
        }
        await c.query('DELETE FROM item_venda WHERE id_venda = ?', [venda['id_venda']]);
        await gravarItensVenda(c, venda['id_venda'], itensNovos);
        await c.query(
          'UPDATE venda SET valor_subtotal = ?, desconto = ?, desconto_informado = ?, valor_total = ?, valor_recebido = ?, troco = ?, editada_por = ?, data_edicao = ? WHERE id_venda = ?',
          [
            subtotal,
            desc.valor,
            percentual ? venda['desconto_informado'] : desc.valor,
            total,
            recebido,
            troco,
            ator['id_usuario'],
            dataHora(),
            venda['id_venda'],
          ],
        );
        return getVenda(venda['id_venda'], c);
      });

  Future<Obj> excluirVenda(Object? id, Obj ator) => tx((c) async {
        final venda = await getVenda(id, c, true);
        if (venda == null) throw erro('Venda não encontrada.', 404);
        if (venda['status_venda'] == 'Concluída') await estornarItensVenda(c, venda, ator, 'Estorno de estoque por exclusão');
        await c.query('DELETE FROM venda WHERE id_venda = ?', [venda['id_venda']]);
        return venda;
      });

  // ---------------------------------------------------------------- conferência de inventário (RF 06)
  Future<List<Obj>> listConferencias() async {
    final confs = await banco.linhas(
      'SELECT c.*, u.nome AS responsavel FROM conferencia c JOIN usuario u ON u.id_usuario = c.id_usuario ORDER BY c.id_conferencia DESC',
    );
    if (confs.isEmpty) return [];
    final itens = await banco.linhas(
      '''SELECT i.id_conferencia, i.id_produto, p.nome_produto, p.unidade, i.lote, i.quantidade_sistema, i.quantidade_fisica, i.divergencia
       FROM item_conferencia i JOIN produto p ON p.id_produto = i.id_produto
       WHERE i.id_conferencia IN (?) ORDER BY i.id_item_conferencia''',
      [for (final c in confs) c['id_conferencia']],
    );
    return [
      for (final c in confs)
        {
          'id_conferencia': c['id_conferencia'],
          'data_conferencia': hm(c['data_conferencia']),
          'responsavel': c['responsavel'],
          'id_usuario': c['id_usuario'],
          'observacao': or(c['observacao'], ''),
          'ajustou_estoque': _bool(c['ajustou_estoque']),
          'itens': [
            for (final i in itens)
              if (i['id_conferencia'] == c['id_conferencia']) {...(Map.of(i)..remove('id_conferencia')), 'lote': or(i['lote'], '')},
          ],
        },
    ];
  }

  Future<Obj> salvarConferencia(Object? body, Obj ator) => tx((c) async {
        final brutos = prop(body, 'itens');
        final itens = validarItens(brutos is List ? brutos : const []);
        if (itens.isEmpty) throw erro('Nenhum item foi conferido.');
        await travarProdutos(c, itens.map((i) => prop(i, 'id_produto')));
        final obs = validarTexto(prop(body, 'observacao'), 'A observação da conferência', min: 10, max: 1000);
        // Sem o campo, ajusta (padrão da tela). Enviado, só o booleano vale: "false", 0 etc. são recusados (como no bug 19).
        final aj = prop(body, 'ajustar');
        if (!isUndef(aj) && aj is! bool) throw erro('A opção de ajustar o estoque deve ser verdadeiro ou falso.');
        final ajustar = aj != false;
        final quando = dataHora();
        final r = await c.query(
          'INSERT INTO conferencia (data_conferencia, observacao, ajustou_estoque, id_usuario) VALUES (?, ?, ?, ?)',
          [quando, obs, ajustar, ator['id_usuario']],
        );
        final id = r.insertId;
        final vistos = <Object?>{};
        final proc = <Obj>[];
        for (final item in itens) {
          final prod = await getProductById(prop(item, 'id_produto'), c, true);
          if (prod == null) throw erro('Produto não cadastrado.', 404);
          final nome = toStr(prod['nome_produto']);
          if (vistos.contains(prod['id_produto'])) throw erro('O produto "$nome" foi informado mais de uma vez.');
          vistos.add(prod['id_produto']);
          final fisica = _num(prop(item, 'quantidade_fisica'));
          if (!fisica.isFinite || fisica < 0) throw erro('Contagem inválida para "$nome".');
          if (fisica > maxQuantidade) throw erro('A contagem de "$nome" é grande demais.');
          if (!aceitaFracao(prod['unidade']) && !isInteger(fisica)) {
            throw erro('"$nome" é contado em ${toStr(prod['unidade'])} e só aceita números inteiros.');
          }
          final sistema = _num(prod['quantidade_estoque']);
          // A tela informa o saldo que mostrava. Se mudou desde então (ex.: uma venda), a contagem não vale mais.
          final qs = prop(item, 'quantidade_sistema');
          if (!isUndef(qs) && _num(qs) != sistema) {
            throw erro(
              'O saldo de "$nome" mudou durante a conferência (era ${toStr(qs)}, agora ${numStr(sistema)}). Atualize a tela e conte de novo.',
              409,
            );
          }
          final div = r3(fisica - sistema);
          if (ajustar && div != 0) {
            await c.query('UPDATE produto SET quantidade_estoque = ? WHERE id_produto = ?', [r3(fisica), prod['id_produto']]);
            await addMovimentacao(
              c,
              {
                'tipo_movimentacao': div > 0 ? 'Entrada' : 'Saída',
                'quantidade': div.abs(),
                'origem': 'conferencia',
                'observacao': 'Ajuste da conferência #$id (sistema ${numStr(sistema)}, físico ${numStr(r3(fisica))})',
                'valor_unitario': prod['preco_custo'],
              },
              prod,
              ator,
            );
          }
          await c.query(
            'INSERT INTO item_conferencia (id_conferencia, id_produto, lote, quantidade_sistema, quantidade_fisica, divergencia) VALUES (?, ?, ?, ?, ?, ?)',
            [id, prod['id_produto'], prod['lote'], sistema, r3(fisica), div],
          );
          proc.add({
            'id_produto': prod['id_produto'],
            'nome_produto': prod['nome_produto'],
            'unidade': prod['unidade'],
            'lote': prod['lote'],
            'quantidade_sistema': sistema,
            'quantidade_fisica': r3(fisica),
            'divergencia': div,
          });
        }
        return {
          'id_conferencia': id.toDouble(),
          'data_conferencia': quando,
          'responsavel': ator['nome'],
          'id_usuario': ator['id_usuario'],
          'observacao': obs,
          'ajustou_estoque': ajustar,
          'itens': proc,
        };
      });

  Future<List<Obj>> listProdutosAtivos() => getProducts(null, null, 'Ativo');

  // ---------------------------------------------------------------- relatórios (RF 12, 13, 14)
  void validarPeriodo(Object? from, Object? to) {
    if (truthy(from) && !dataValida(from)) throw erro('A data inicial é inválida.');
    if (truthy(to) && !dataValida(to)) throw erro('A data final é inválida.');
    if (truthy(from) && truthy(to) && toStr(from).compareTo(toStr(to)) > 0) {
      throw erro('A data inicial não pode ser posterior à data final.');
    }
  }

  Obj _filtros(Object? from, Object? to, double? cat) => {'from': or(from, null), 'to': or(to, null), 'categoria': cat};

  Future<Obj> getRelatorioVendas({Object? from, Object? to, Object? categoria}) async {
    validarPeriodo(from, to);
    final cat = truthy(categoria) ? _num(categoria) : null;
    final vendas = await getVendas(from: from, to: to, status: 'Concluída');
    final prods = await banco.linhas('SELECT p.id_produto, p.id_categoria, c.nome_categoria FROM produto p JOIN categoria c ON c.id_categoria = p.id_categoria');
    final catDe = {for (final p in prods) p['id_produto']: p};
    final mapa = <Object?, Obj>{};
    final pagamentos = <Object?, Obj>{};
    final transacoes = <Obj>[];
    var bruto = 0.0, liquido = 0.0, descontos = 0.0;
    for (final v in vendas) {
      final vs = _num(v['valor_subtotal']);
      final razao = vs > 0 ? _num(v['valor_total']) / vs : 1.0;
      var sub = 0.0;
      final resumo = <String>[];
      for (final i in (v['itens'] as List).cast<Obj>()) {
        final p = catDe[i['id_produto']];
        if (truthy(cat) && (p == null || p['id_categoria'] != cat)) continue;
        sub += _num(i['subtotal']);
        resumo.add('${toStr(i['nome_produto'])} x${toStr(i['quantidade'])}');
        final nomeCat = p != null ? p['nome_categoria'] : '-';
        final m = mapa[i['id_produto']] ??
            {
              'id_produto': i['id_produto'],
              'nome_produto': i['nome_produto'],
              'categoria': nomeCat,
              'unidade': i['unidade'],
              'quantidade': 0.0,
              'total': 0.0,
            };
        m['quantidade'] = r3(_num(m['quantidade']) + _num(i['quantidade']));
        m['total'] = r2(_num(m['total']) + _num(i['subtotal']));
        mapa[i['id_produto']] = m;
      }
      if (resumo.isEmpty) continue;
      final liq = r2(sub * razao);
      bruto = r2(bruto + sub);
      liquido = r2(liquido + liq);
      descontos = r2(descontos + (sub - liq));
      final pg = pagamentos[v['forma_pagamento']] ?? {'forma': v['forma_pagamento'], 'total': 0.0, 'quantidade': 0.0};
      pg['total'] = r2(_num(pg['total']) + liq);
      pg['quantidade'] = _num(pg['quantidade']) + 1;
      pagamentos[v['forma_pagamento']] = pg;
      transacoes.add({
        'id_venda': v['id_venda'],
        'codigo_venda': v['codigo_venda'],
        'data_venda': v['data_venda'],
        'usuario_nome': v['usuario_nome'],
        'forma_pagamento': v['forma_pagamento'],
        'itens_resumo': resumo.join(', '),
        'bruto': r2(sub),
        'desconto': r2(sub - liq),
        'valor_total': liq,
      });
    }
    final itensVendidos = sortJs(
      [
        for (final i in mapa.values)
          {...i, 'valor_unitario': truthy(i['quantidade']) ? r2(_num(i['total']) / _num(i['quantidade'])) : 0.0},
      ],
      (a, b) => _num(b['total']) - _num(a['total']),
    );
    return {
      'filtros': _filtros(from, to, cat),
      'totalBruto': bruto,
      'totalDescontos': descontos,
      'totalGeral': liquido,
      'quantidadeTransacoes': transacoes.length.toDouble(),
      'ticketMedio': transacoes.isNotEmpty ? r2(liquido / transacoes.length) : 0.0,
      'porPagamento': pagamentos.values.toList(),
      'itensVendidos': itensVendidos,
      'transacoes': transacoes,
    };
  }

  Future<Obj> getRelatorioEstoque({Object? from, Object? to, Object? categoria}) async {
    validarPeriodo(from, to);
    final cat = truthy(categoria) ? _num(categoria) : null;
    final where = <String>[], params = <Object?>[];
    if (truthy(from)) {
      where.add('data_movimentacao >= ?');
      params.add('${toStr(from)} 00:00:00');
    }
    if (truthy(to)) {
      where.add('data_movimentacao <= ?');
      params.add('${toStr(to)} 23:59:59');
    }
    final movs = await banco.linhas(
      '''SELECT id_produto, tipo_movimentacao, SUM(quantidade) AS total FROM movimentacao_estoque
       ${where.isNotEmpty ? 'WHERE ${where.join(' AND ')}' : ''} GROUP BY id_produto, tipo_movimentacao''',
      params,
    );
    double soma(Object? idp, String tipo) =>
        r3((movs.where((m) => m['id_produto'] == idp && m['tipo_movimentacao'] == tipo).firstOrNull ?? {'total': 0.0})['total']);
    final prods = await banco.linhas(
      '''SELECT p.*, c.nome_categoria FROM produto p JOIN categoria c ON c.id_categoria = p.id_categoria
       WHERE p.status = 'Ativo'${truthy(cat) ? ' AND p.id_categoria = ?' : ''} ORDER BY p.id_produto''',
      truthy(cat) ? [cat] : [],
    );
    final linhas = [
      for (final p in prods)
        <String, Object?>{
          'id_produto': p['id_produto'],
          'codigo_barras': p['codigo_barras'],
          'nome_produto': p['nome_produto'],
          'unidade': p['unidade'],
          'categoria': p['nome_categoria'],
          'entradas': soma(p['id_produto'], 'Entrada'),
          'saidas': soma(p['id_produto'], 'Saída'),
          'saldo_atual': p['quantidade_estoque'],
          'estoque_minimo': p['estoque_minimo'],
          'valor_em_estoque': r2(_num(p['quantidade_estoque']) * _num(p['preco_custo'])),
          'situacao': _num(p['quantidade_estoque']) <= _num(p['estoque_minimo']) ? 'Crítico' : 'Regular',
        },
    ];
    return {
      'filtros': _filtros(from, to, cat),
      'totalProdutos': linhas.length.toDouble(),
      'totalCriticos': linhas.where((l) => l['situacao'] == 'Crítico').length.toDouble(),
      'valorTotalEstoque': r2(linhas.fold<double>(0, (a, l) => a + (l['valor_em_estoque'] as double))),
      'linhas': linhas,
    };
  }

  // Relatório de desperdício: perdas/sobras por produto e por motivo, valorizadas pelo custo.
  Future<Obj> getRelatorioPerdas({Object? from, Object? to, Object? categoria}) async {
    validarPeriodo(from, to);
    final cat = truthy(categoria) ? _num(categoria) : null;
    final where = ["m.origem = 'perda'"], params = <Object?>[];
    if (truthy(from)) {
      where.add('m.data_movimentacao >= ?');
      params.add('${toStr(from)} 00:00:00');
    }
    if (truthy(to)) {
      where.add('m.data_movimentacao <= ?');
      params.add('${toStr(to)} 23:59:59');
    }
    if (truthy(cat)) {
      where.add('p.id_categoria = ?');
      params.add(cat);
    }
    final rows = await banco.linhas(
      '''SELECT m.*, p.nome_produto AS produto_nome, p.codigo_barras, p.unidade, u.nome AS usuario_nome, c.nome_categoria AS categoria
       FROM movimentacao_estoque m JOIN produto p ON p.id_produto = m.id_produto
       JOIN categoria c ON c.id_categoria = p.id_categoria LEFT JOIN usuario u ON u.id_usuario = m.id_usuario
       WHERE ${where.join(' AND ')} ORDER BY m.data_movimentacao DESC, m.id_movimentacao DESC''',
      params,
    );
    final registros = [
      for (final m in rows) {...mapMov(m), 'categoria': m['categoria']},
    ];
    final produtos = <Object?, Obj>{};
    for (final r in registros) {
      final p = produtos[r['id_produto']] ??
          {
            'id_produto': r['id_produto'],
            'nome_produto': r['produto_nome'],
            'categoria': r['categoria'],
            'unidade': r['unidade'],
            'quantidade': 0.0,
            'valor_total': 0.0,
            'registros': 0.0,
          };
      p['quantidade'] = r3(_num(p['quantidade']) + _num(r['quantidade']));
      p['valor_total'] = r2(_num(p['valor_total']) + _num(r['valor_total']));
      p['registros'] = _num(p['registros']) + 1;
      produtos[r['id_produto']] = p;
    }
    final porMotivo = [
      for (final motivo in motivosPerda)
        () {
          final doMotivo = registros.where((r) => r['motivo_perda'] == motivo).toList();
          return <String, Object?>{
            'motivo': motivo,
            'registros': doMotivo.length.toDouble(),
            'valor_total': r2(doMotivo.fold<double>(0, (a, r) => a + (r['valor_total'] as double))),
          };
        }(),
    ].where((m) => truthy(m['registros'])).toList();
    return {
      'filtros': _filtros(from, to, cat),
      'totalRegistros': registros.length.toDouble(),
      'valorTotal': r2(registros.fold<double>(0, (a, r) => a + (r['valor_total'] as double))),
      'porProduto': sortJs(produtos.values.toList(), (a, b) => _num(b['valor_total']) - _num(a['valor_total'])),
      'porMotivo': porMotivo,
      'registros': registros,
    };
  }

  // ---------------------------------------------------------------- busca global (barra de pesquisa)
  // `permitido(perm)` informa o que o perfil do usuário pode ver; nada além disso é retornado.
  // A collation do banco (utf8mb4_0900_ai_ci) já ignora acentos e maiúsculas: "pao" acha "Pão".
  Future<Obj> buscaGlobal(Object? q, bool Function(String perm) permitido) async {
    final termo = txt(q);
    final out = <String, Object?>{'produtos': <Object?>[], 'requisicoes': <Object?>[], 'vendas': <Object?>[], 'usuarios': <Object?>[]};
    if (termo.length < 2) return out;
    final t = like(termo);
    const lim = 5;
    if (permitido('produtos:ver')) {
      out['produtos'] = await banco.linhas(
        '''SELECT p.id_produto, p.nome_produto, p.codigo_barras, p.unidade, p.quantidade_estoque, p.status, c.nome_categoria AS categoria
         FROM produto p JOIN categoria c ON c.id_categoria = p.id_categoria
         WHERE p.nome_produto LIKE ? OR p.codigo_barras LIKE ? OR p.lote LIKE ? OR p.descricao LIKE ?
         ORDER BY p.id_produto LIMIT ?''',
        [t, t, t, t, lim],
      );
    }
    if (permitido('requisicoes:ver')) {
      out['requisicoes'] = await banco.linhas(
        '''SELECT r.id_requisicao, r.codigo_pedido, r.produto_nome, f.nome AS fornecedor, r.situacao
         FROM requisicao r JOIN fornecedor f ON f.id_fornecedor = r.id_fornecedor
         WHERE r.codigo_pedido LIKE ? OR f.nome LIKE ? OR r.produto_nome LIKE ? OR r.situacao LIKE ?
         ORDER BY r.id_requisicao DESC LIMIT ?''',
        [t, t, t, t, lim],
      );
    }
    if (permitido('vendas:ver')) {
      out['vendas'] = [
        for (final v in await getVendas(q: termo, limite: lim))
          {
            'id_venda': v['id_venda'],
            'codigo_venda': v['codigo_venda'],
            'data_venda': v['data_venda'],
            'valor_total': v['valor_total'],
            'usuario_nome': v['usuario_nome'],
            'status_venda': v['status_venda'],
          },
      ];
    }
    if (permitido('usuarios:gerir')) {
      out['usuarios'] = await banco.linhas(
        '''SELECT u.id_usuario, u.nome, u.email, p.nome_perfil AS perfil, u.status
         FROM usuario u JOIN perfil p ON p.id_perfil = u.id_perfil
         WHERE u.nome LIKE ? OR u.email LIKE ? OR u.cargo LIKE ? ORDER BY u.id_usuario LIMIT ?''',
        [t, t, t, lim],
      );
    }
    return out;
  }

  Future<void> registrarRelatorio(String tipo, Object? idUsuario) async {
    await banco.query('INSERT INTO relatorio (tipo_relatorio, data_geracao, id_usuario) VALUES (?, ?, ?)', [sliceStr(tipo, 60), dataHora(), idUsuario]);
  }
}

// Math.random(): só precisa ser imprevisível o bastante para um lote provisório.
final _rnd = math.Random();
double _aleatorio() => _rnd.nextDouble();

/// Mensagem de um erro qualquer (o `e.message` do JS).
String mensagemDe(Object e) {
  if (e is HttpErro) return e.mensagem;
  try {
    final m = (e as dynamic).message;
    if (m is String) return m;
  } catch (_) {}
  return e.toString();
}
