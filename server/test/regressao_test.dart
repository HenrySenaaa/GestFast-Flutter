// Testes de regressão (porte 1:1 de regressao.test.js): um para cada bug corrigido na migração
// para Flutter, mais o acesso por token. Rodam no banco gestfast_reg_test, recriado do zero.
import 'dart:convert';
import 'dart:io';

import 'package:gestfast_server/gestfast_server.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'apoio/ambiente.dart';

/// Dados com a falha de `listCategorias` ligável (o teste do Node trocava a função do módulo).
class DadosComFalha extends Dados {
  DadosComFalha({required super.banco, required super.relogio, required super.logger});
  String? falha;
  @override
  Future<List<Obj>> listCategorias([Executor? c]) {
    if (falha != null) throw Exception(falha);
    return super.listCategorias(c);
  }
}

late Ambiente amb;
late Directory tmp;
String get base => amb.base;
DadosComFalha get db => amb.dados as DadosComFalha;
Future<num> saldo(Object id) async => (await amb.dados.getProductById(id))!['quantidade_estoque'] as num;

Future<Cliente> logar(String email, String senha) async {
  final c = Cliente(base);
  final r = await c.post('/api/auth/login', {'email': email, 'senha': senha});
  expect(r.status, 200, reason: r.error);
  return c;
}

Future<Cliente> admin() => logar('proprietario@padarianovayork.com', 'admin123');
Future<Cliente> func() => logar('henry@padarianovayork.com', 'func123');
const novoProduto = {
  'descricao': 'Produto criado para teste de regressão',
  'id_categoria': 1,
  'unidade': 'UN',
  'preco_custo': 2,
  'preco_venda': 10,
  'preco_min': 5,
  'preco_max': 20,
  'estoque_minimo': 1,
};
Map<String, Object?> item(Object id, Object qtd) => {'id_produto': id, 'quantidade': qtd};

void main() {
  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('gestfast-reg-');
    Directory(p.join(tmp.path, 'web')).createSync();
    Directory(p.join(tmp.path, 'web-secreto')).createSync();
    File(p.join(tmp.path, 'web', 'index.html')).writeAsStringSync('<title>app</title>');
    File(p.join(tmp.path, 'web-secreto', 'x.txt')).writeAsStringSync('segredo');
    amb = await Ambiente.iniciar(
      nomeBanco: 'gestfast_reg_test',
      pasta: tmp,
      extra: {'GESTFAST_WEB_DIR': p.join(tmp.path, 'web'), 'CORS_ORIGINS': 'http://app.test'},
      criarDados: (b, r, l) => DadosComFalha(banco: b, relogio: r, logger: l),
    );
  });
  tearDownAll(() async => amb.encerrar());

  // ---------------------------------------------------------------- dados
  test('Bug 1: salvar produto não sobrescreve o saldo; estoque inicial entra no histórico', () async {
    final a = await admin();
    final criado = (await a.post('/api/products', {...novoProduto, 'nome_produto': 'Regressão Saldo', 'quantidade_estoque': 10}))['product'];
    final id = criado['id_produto'];
    final movs = ((await a.get('/api/movements?tipo=Entrada'))['movements'] as List).where((m) => m['id_produto'] == id).toList();
    expect(movs.length, 1);
    expect(movs[0]['quantidade'], 10);
    expect(movs[0]['valor_unitario'], 2);
    await (await func()).post('/api/sales', {
      'itens': [item(id, 3)],
    });
    // formulário aberto antes da venda reenvia o saldo antigo (10)
    final r = await a.put('/api/products/$id', {...novoProduto, 'nome_produto': 'Regressão Saldo', 'quantidade_estoque': 10});
    expect(r.status, 200);
    expect(await saldo(id), 7);
  });

  test('Bug 2: conferência recusa contagem feita sobre saldo desatualizado', () async {
    final f = await func();
    final lido = await saldo(11);
    await f.post('/api/sales', {
      'itens': [item(11, 2)],
    });
    final r = await f.post('/api/inventory', {
      'observacao': 'Conferência com saldo antigo na tela',
      'itens': [
        {'id_produto': 11, 'quantidade_fisica': lido, 'quantidade_sistema': lido},
      ],
    });
    expect(r.status, 409);
    expect(r.error, matches('Pão Doce'));
    expect(await saldo(11), lido - 2);
    final ok = await f.post('/api/inventory', {
      'observacao': 'Conferência com saldo atualizado',
      'itens': [
        {'id_produto': 11, 'quantidade_fisica': lido - 2, 'quantidade_sistema': lido - 2},
      ],
    });
    expect(ok.status, 201);
  });

  test('Bug 3: editar venda em dinheiro recalcula o troco e exige valor recebido suficiente', () async {
    final a = await admin();
    final v = (await a.post('/api/sales', {
      'itens': [item(8, 2)],
      'forma_pagamento': 'Dinheiro',
      'valor_recebido': 20,
    }))['sale'];
    expect(v['troco'], 8);
    final e1 = await a.put('/api/sales/${v['id_venda']}', {
      'itens': [item(8, 1)],
    });
    expect(e1['sale']['valor_total'], 6);
    expect(e1['sale']['troco'], 14);
    final e2 = await a.put('/api/sales/${v['id_venda']}', {
      'itens': [item(8, 5)],
    });
    expect(e2.status, 400);
    expect(e2.error, matches(RegExp('recebido', caseSensitive: false)));
    final e3 = await a.put('/api/sales/${v['id_venda']}', {
      'itens': [item(8, 5)],
      'valor_recebido': 50,
    });
    expect(e3['sale']['valor_recebido'], 50);
    expect(e3['sale']['troco'], 20);
  });

  test('Bug 4: editar venda preserva cada preço do mesmo produto', () async {
    final a = await admin();
    final v = (await a.post('/api/sales', {
      'itens': [
        {'id_produto': 12, 'quantidade': 1, 'valor_unitario': 0.3},
        {'id_produto': 12, 'quantidade': 1, 'valor_unitario': 0.5},
      ],
    }))['sale'];
    expect(v['valor_total'], 0.8);
    // sem dizer qual linha, a edição seria ambígua
    expect(
      (await a.put('/api/sales/${v['id_venda']}', {
        'itens': [item(12, 2)],
      }))
          .status,
      400,
    );
    final l1 = v['itens'][0], l2 = v['itens'][1];
    final e = await a.put('/api/sales/${v['id_venda']}', {
      'itens': [
        {'id_produto': 12, 'id_item_venda': l1['id_item_venda'], 'quantidade': 2},
        {'id_produto': 12, 'id_item_venda': l2['id_item_venda'], 'quantidade': 1},
      ],
    });
    expect(e.status, 200, reason: e.error);
    expect(e['sale']['valor_total'], 1.1);
    expect(((e['sale']['itens'] as List).map((i) => i['valor_unitario']).toList()..sort()), [0.3, 0.5]);
  });

  test('Bug 5: editar venda não inclui produto inativo', () async {
    final a = await admin();
    final pr = (await a.post('/api/products', {...novoProduto, 'nome_produto': 'Regressão Inativo', 'quantidade_estoque': 5}))['product'];
    await a.patch('/api/products/${pr['id_produto']}/status', {'status': 'Inativo'});
    final v = (await a.post('/api/sales', {
      'itens': [item(8, 1)],
    }))['sale'];
    final r = await a.put('/api/sales/${v['id_venda']}', {
      'itens': [item(8, 1), item(pr['id_produto'], 1)],
    });
    expect(r.status, 400);
    expect(r.error, matches(RegExp('inativo', caseSensitive: false)));
  });

  // ---------------------------------------------------------------- servidor e segurança
  test('Bug 6: endereço malformado não derruba o servidor', () async {
    for (final url in ['/%E0%A4%A', '/%00.png', '/api/%E0%A4%A', '/uploads/%E0%A4%A']) {
      final res = await requisicaoCrua(base, url);
      expect(res.status, 400, reason: url);
    }
    expect((await Cliente(base).get('/api/auth/me')).status, 401);
  });

  test('Bug 7: erro interno responde 500, sem expor detalhes, e fica no log', () async {
    final a = await admin();
    db.falha = 'SQL secreto: tabela xyz';
    try {
      final r = await a.get('/api/categories');
      expect(r.status, 500);
      expect(r.error, isNot(contains('secreto')));
    } finally {
      db.falha = null;
    }
    final logs = (await a.get('/api/logs'))['logs'] as List;
    expect(logs.any((l) => l['evento'] == 'falha_interna' && (l['erro'] as String).contains('secreto')), isTrue);
  });

  test('Bug 8: corpo e itens inválidos respondem 400 com mensagem clara', () async {
    final f = await func();
    expect((await f.post('/api/movements', null)).status, 400);
    expect((await f.post('/api/movements', [1, 2])).status, 400);
    for (final (url, corpo) in [
      (
        '/api/movements',
        {
          'tipo_movimentacao': 'Entrada',
          'observacao': 'Observação válida de teste',
          'itens': [null],
        },
      ),
      (
        '/api/sales',
        {
          'itens': [null],
        },
      ),
      (
        '/api/inventory',
        {
          'observacao': 'Observação válida de teste',
          'itens': ['x'],
        },
      ),
      (
        '/api/losses',
        {
          'motivo_perda': 'Vencido',
          'itens': [7],
        },
      ),
    ]) {
      final r = await f.post(url, corpo);
      expect(r.status, 400, reason: url);
      expect(r.error, isNot(matches(RegExp('Cannot read|undefined|null'))), reason: url);
    }
  });

  test('Bug 9: link de redefinição não fica nos logs', () async {
    final c = Cliente(base);
    await c.post('/api/auth/forgot', {'email': 'backoffice@padarianovayork.com'});
    final logs = (await (await admin()).get('/api/logs'))['logs'] as List;
    final ev = logs.where((l) => l['evento'] == 'redefinicao_senha_solicitada').toList();
    expect(ev.isNotEmpty, isTrue);
    final semEvento = [for (final l in ev) Map.of(l as Map)..remove('evento')];
    expect(jsonEncode(semEvento), isNot(matches(RegExp('reset|link|token', caseSensitive: false))));
  });

  test('Bug 10: senha de gerente tem limite de tentativas', () async {
    final f = await func();
    final v = (await f.post('/api/sales', {
      'itens': [item(8, 1)],
    }))['sale'];
    final corpo = {'motivo': 'Cancelamento para teste de limite', 'autorizador_email': 'backoffice@padarianovayork.com', 'autorizador_senha': 'errada'};
    for (var i = 0; i < 5; i++) {
      expect((await f.post('/api/sales/${v['id_venda']}/cancel', corpo)).status, 403);
    }
    final r = await f.post('/api/sales/${v['id_venda']}/cancel', {...corpo, 'autorizador_senha': 'backoffice123'});
    expect(r.status, 429);
  });

  test('Bug 11: trocar a senha encerra as outras sessões e mantém a atual', () async {
    final a = await admin();
    final c = await admin();
    final r = await a.post('/api/auth/change-password', {'senha_atual': 'admin123', 'nova_senha': 'admin123'});
    expect(r.status, 200);
    expect((await a.get('/api/auth/me')).status, 200);
    expect((await c.get('/api/auth/me')).status, 401);
  });

  test('Bug 12: login com e-mail inexistente também calcula o hash', () async {
    final original = amb.dados.verificarSenha;
    var chamadas = 0;
    amb.dados.verificarSenha = (s, h) {
      chamadas++;
      return original(s, h);
    };
    try {
      final r = await Cliente(base).post('/api/auth/login', {'email': 'ninguem-aqui@x.com', 'senha': 'qualquer'});
      expect(r.status, 401);
      expect(chamadas, 1);
    } finally {
      amb.dados.verificarSenha = original;
    }
  });

  test('Bug 13: arquivos estáticos não saem da pasta do app', () async {
    final res = await requisicaoCrua(base, '/..%2fweb-secreto%2fx.txt');
    expect(res.texto, isNot('segredo'));
    expect(res.status, 403);
    final raiz = await requisitar('GET', '$base/');
    expect(raiz.texto, matches('<title>app'));
  });

  // ---------------------------------------------------------------- validação e consistência
  test('Bug 14: datas impossíveis e filtros inválidos respondem 400', () async {
    final a = await admin();
    final r = await a.post('/api/products', {...novoProduto, 'nome_produto': 'Data Ruim', 'validade': '2030-02-31'});
    expect(r.status, 400);
    expect(r.error, matches(RegExp('validade', caseSensitive: false)));
    final q = await a.post('/api/requisitions', {'id_produto': 8, 'fornecedor': 'Laticínios ABC', 'quantidade_pedida': 1, 'previsao_entrega': '2030-02-31'});
    expect(q.status, 400);
    for (final url in ['/api/movements?from=abc', '/api/movements?to=2030-13-01', '/api/sales?from=abc', '/api/sales?to=2030-02-31']) {
      final x = await a.get(url);
      expect(x.status, 400, reason: url);
      expect(x.error, matches(RegExp('data', caseSensitive: false)), reason: url);
    }
  });

  test('Bug 15: quantidade que arredonda para zero é recusada com mensagem clara', () async {
    final a = await admin();
    final antes = await saldo(4);
    final r = await a.post('/api/movements', {
      'tipo_movimentacao': 'Entrada',
      'observacao': 'Observação válida de teste',
      'itens': [item(4, 0.0001)],
    });
    expect(r.status, 400);
    expect(r.error, matches('maior que zero'));
    expect(await saldo(4), antes);
    expect((await a.post('/api/requisitions', {'id_produto': 4, 'fornecedor': 'Laticínios ABC', 'quantidade_pedida': 0.0001})).status, 400);
  });

  test('Bug 16: produto inválido não deixa imagem órfã', () async {
    final a = await admin();
    final dir = Directory(amb.config.pastaUploads);
    int conta() => dir.existsSync() ? dir.listSync().length : 0;
    final antes = conta();
    const img = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';
    final r = await a.post('/api/products', {...novoProduto, 'nome_produto': 'Sem Preço', 'preco_venda': 0, 'imagem_data': img});
    expect(r.status, 400);
    expect(conta(), antes);
    final ok = await a.post('/api/products', {...novoProduto, 'nome_produto': 'Com Imagem', 'imagem_data': img});
    expect(ok['product']['imagem'], matches(RegExp(r'^uploads/prod-')));
    expect(conta(), antes + 1);
  });

  test('Bug 17: vendas simultâneas em ordem inversa não travam', () async {
    final a = await admin();
    final ps = <Object>[];
    for (final nome in ['Regressão A', 'Regressão B']) {
      ps.add((await a.post('/api/products', {...novoProduto, 'nome_produto': nome, 'quantidade_estoque': 500}))['product']['id_produto']);
    }
    Future<Resp> venda(List<Object> ordem) => a.post('/api/sales', {
          'itens': [for (final id in ordem) item(id, 1)],
        });
    final rs = await Future.wait(List.generate(30, (i) => venda(i.isOdd ? ps : ps.reversed.toList())));
    expect(rs.where((r) => r.status != 201).map((r) => r.error).toList(), isEmpty);
    expect(await saldo(ps[0]), 470);
    expect(await saldo(ps[1]), 470);
  });

  test('Bug 18: ajuste de conferência é sempre valorizado pelo custo', () async {
    final a = await admin();
    final s = await saldo(10);
    await a.post('/api/inventory', {
      'observacao': 'Conferência para testar o valor',
      'itens': [
        {'id_produto': 10, 'quantidade_fisica': s - 1},
      ],
    });
    final m = ((await a.get('/api/movements?tipo=Saída'))['movements'] as List).firstWhere((x) => x['id_produto'] == 10 && x['origem'] == 'conferencia');
    expect(m['valor_unitario'], 4.8);
  });

  test('Bug 19: simulações só aceitam verdadeiro ou falso', () async {
    final a = await admin();
    final r = await a.put('/api/settings', {'simularCartaoNegado': 'false'});
    expect(r.status, 400);
    expect((await a.get('/api/settings'))['settings']['simularCartaoNegado'], false);
  });

  test('Bug 20: limitador de tentativas limpa entradas antigas', () {
    var agora = 0;
    final l = Limitador(max: 2, bloqueioMs: 100, janelaMs: 1000, relogio: () => agora);
    l.falhou('a');
    expect(l.tamanho, 1);
    l.falhou('a');
    expect(() => l.checar('a'), throwsA(isA<HttpErro>().having((e) => e.status, 'status', 429)));
    agora = 101;
    expect(() => l.checar('a'), returnsNormally);
    agora = 5000;
    l.falhou('b');
    expect(l.tamanho, 1); // "a" expirou e foi limpo
  });

  test('Rota de produto ignora id e caminho de imagem enviados pelo cliente', () async {
    final a = await admin();
    final antes = (await a.get('/api/products/1'))['product']['nome_produto'];
    final r = await a.post('/api/products', {...novoProduto, 'nome_produto': 'Tentou Editar', 'id_produto': 1, 'imagem': '../../segredo'});
    expect(r.status, 201);
    expect(r['product']['id_produto'], isNot(1));
    expect(r['product']['imagem'], '');
    expect((await a.get('/api/products/1'))['product']['nome_produto'], antes);
  });

  // ---------------------------------------------------------------- acesso pelo app
  test('App: login por token (Bearer), sem cookie', () async {
    const headers = {'Content-Type': 'application/json', 'X-Client': 'app'};
    final res = await requisitar('POST', '$base/api/auth/login', corpo: {'email': 'henry@padarianovayork.com', 'senha': 'func123'}, headers: headers);
    final d = res.json;
    expect(res.status, 200);
    expect(d['token'], isNotNull);
    expect(res.headers['set-cookie'], isNull);
    final bearer = {'Authorization': 'Bearer ${d['token']}'};
    expect((await requisitar('GET', '$base/api/auth/me', headers: bearer)).status, 200);
    expect((await requisitar('POST', '$base/api/auth/logout', headers: {...bearer, 'Content-Type': 'application/json'}, bytes: utf8.encode('{}'))).status, 200);
    expect((await requisitar('GET', '$base/api/auth/me', headers: bearer)).status, 401);
    // navegador: continua com cookie e sem token no corpo
    final web = await requisitar(
      'POST',
      '$base/api/auth/login',
      corpo: {'email': 'henry@padarianovayork.com', 'senha': 'func123'},
      headers: {'Content-Type': 'application/json'},
    );
    expect(web.json['token'], isNull);
    expect(web.headers.value('set-cookie'), matches('HttpOnly'));
  });

  test('App: CORS só para origens configuradas', () async {
    final pre = await requisitar('OPTIONS', '$base/api/products', headers: {'Origin': 'http://app.test', 'Access-Control-Request-Method': 'GET'});
    expect(pre.status, 204);
    expect(pre.headers.value('access-control-allow-origin'), 'http://app.test');
    expect(pre.headers.value('access-control-allow-headers'), matches('Authorization'));
    final fora = await requisitar('GET', '$base/api/auth/me', headers: {'Origin': 'http://malicioso.test'});
    expect(fora.headers.value('access-control-allow-origin'), isNull);
  });

  // ---------------------------------------------------------------- fase 2 (Vigia)
  test('Fase 2 item 7: GET /api/logs respeita o teto de 1000 com limites inválidos', () async {
    for (var i = 0; i < 1100; i++) {
      amb.logger.log('INFO', 'teste_teto_logs', {'i': i.toDouble()});
    }
    final a = await admin();
    Future<int> qtd(String q) async {
      final r = await a.get('/api/logs$q');
      expect(r.status, 200);
      return (r['logs'] as List).length;
    }

    expect(await qtd('?limit=-1'), 200);
    expect(await qtd('?limit=-5000'), 200);
    expect(await qtd('?limit=abc'), 200);
    expect(await qtd('?limit=0'), 200);
    expect(await qtd('?limit=Infinity'), 200);
    expect(await qtd(''), 200);
    expect(await qtd('?limit=5000'), 1000);
    expect(await qtd('?limit=3'), 3);
    expect(await qtd('?limit=2.9'), 2);
  });

  test('Fase 2 item 10: falha simulada do fornecedor não vira falha_interna; falha_interna registra o usuário', () async {
    final a = await admin();
    final marca = DateTime.now().millisecondsSinceEpoch;
    expect((await a.put('/api/settings', {'simularFornecedorIndisponivel': true})).status, 200);
    try {
      final r = await a.post('/api/requisitions', {'id_produto': 4, 'fornecedor': 'Laticínios ABC', 'quantidade_pedida': 1, 'observacao': 'Pedido com fornecedor fora do ar'});
      expect(r.status, 503);
    } finally {
      expect((await a.put('/api/settings', {'simularFornecedorIndisponivel': false})).status, 200);
    }
    var logs = (await a.get('/api/logs?limit=50'))['logs'] as List;
    final externa = logs.firstWhere((l) => l['evento'] == 'falha_externa' && l['rota'] == '/api/requisitions', orElse: () => null);
    expect(externa, isNotNull, reason: 'falha do fornecedor deve ir ao log como falha_externa');
    expect(externa['nivel'], 'AVISO');
    expect(externa['status'], 503);
    expect(externa['usuario'], 'proprietario@padarianovayork.com');
    expect(logs.any((l) => l['evento'] == 'falha_interna' && l['rota'] == '/api/requisitions'), isFalse);

    db.falha = 'falha interna $marca';
    try {
      expect((await a.get('/api/categories')).status, 500);
    } finally {
      db.falha = null;
    }
    logs = (await a.get('/api/logs?limit=50'))['logs'] as List;
    final interna = logs.firstWhere((l) => l['evento'] == 'falha_interna' && (l['erro'] as String).contains('$marca'), orElse: () => null);
    expect(interna, isNotNull);
    expect(interna['nivel'], 'ERRO');
    expect(interna['usuario'], 'proprietario@padarianovayork.com');
  });

  // ---------------------------------------------------------------- fase 2 (Alicerce: banco)
  Future<num> alertas(Object id, [String status = 'Ativo']) async =>
      (await amb.dados.query('SELECT COUNT(*) AS n FROM alerta_estoque WHERE id_produto = ? AND status_alerta = ?', [id, status])).first['n'] as num;
  List<String> semErro(List<Resp> rs) => [
        for (final r in rs)
          if (r.status != 201) '${r.status} ${r.error}',
      ];

  test('Fase 2 item 1: vendas/entradas paralelas de produtos diferentes não dão deadlock e mantêm os alertas', () async {
    final a = await admin();
    Future<Object> cria(String nome, num qtd, num min) async =>
        (await a.post('/api/products', {...novoProduto, 'nome_produto': nome, 'quantidade_estoque': qtd, 'estoque_minimo': min}))['product']['id_produto'];
    Future<Resp> venda(Object id) => a.post('/api/sales', {
          'itens': [item(id, 1)],
        });
    Future<Resp> entrada(Object id) =>
        a.post('/api/movements', {'tipo_movimentacao': 'Entrada', 'observacao': 'Entrada paralela de teste', 'id_produto': id, 'quantidade': 1});

    // Cenário do Sonda: 60 vendas em paralelo, 30 só do produto A e 30 só do B.
    final aa = await cria('Paralelo A', 500, 1), bb = await cria('Paralelo B', 500, 1);
    expect(semErro(await Future.wait(List.generate(60, (i) => venda(i.isOdd ? aa : bb)))), isEmpty);
    expect(await saldo(aa), 470);
    expect(await saldo(bb), 470);

    // 30 vendas de C + 30 entradas de D.
    final cc = await cria('Paralelo C', 500, 1), dd = await cria('Paralelo D', 500, 1);
    expect(semErro(await Future.wait(List.generate(60, (i) => i.isOdd ? venda(cc) : entrada(dd)))), isEmpty);
    expect(await saldo(cc), 470);
    expect(await saldo(dd), 530);

    // Alertas: E e F cruzam o estoque mínimo AO MESMO TEMPO (40 -> 10, mínimo 20). Cada um fica com exatamente 1 alerta ativo.
    final ee = await cria('Paralelo E', 40, 20), ff = await cria('Paralelo F', 40, 20);
    expect(await alertas(ee), 0);
    expect(semErro(await Future.wait(List.generate(60, (i) => venda(i.isOdd ? ee : ff)))), isEmpty);
    expect(await saldo(ee), 10);
    expect(await alertas(ee), 1);
    expect(await alertas(ff), 1);
    expect(((await a.get('/api/alerts'))['alerts'] as List).any((x) => x['id_produto'] == ee), isTrue, reason: 'alerta aparece em /api/alerts');
    // Entrada que tira do mínimo resolve o alerta só do produto tocado.
    expect((await a.post('/api/movements', {'tipo_movimentacao': 'Entrada', 'observacao': 'Reposição de teste', 'id_produto': ee, 'quantidade': 100})).status, 201);
    expect(await alertas(ee), 0);
    expect(await alertas(ee, 'Resolvido'), 1);
    expect(await alertas(ff), 1);
    // Mudar o estoque mínimo pelo cadastro também atualiza o alerta.
    final pf = (await a.get('/api/products/$ff'))['product'] as Map<String, dynamic>;
    expect((await a.put('/api/products/$ff', {...pf, 'estoque_minimo': 5})).status, 200);
    expect(await alertas(ff), 0);
    // Produto cadastrado já abaixo do mínimo nasce com alerta.
    final gg = await cria('Paralelo G', 3, 5);
    expect(await alertas(gg), 1);
    // Alerta defasado (saldo mudado direto no banco) é corrigido pela sincronização completa da subida do servidor.
    await amb.dados.query('UPDATE produto SET quantidade_estoque = 0 WHERE id_produto = ?', [aa]);
    await amb.dados.query("UPDATE alerta_estoque SET status_alerta = 'Resolvido' WHERE id_produto = ?", [gg]);
    await amb.dados.sincronizarTodosAlertas();
    expect(await alertas(aa), 1);
    expect(await alertas(gg), 1);
    expect(await alertas(bb), 0);
  });

  test('Fase 2 item 4: valores acima do limite das colunas respondem 400, não 500', () async {
    final a = await admin();
    final pr = (await a.get('/api/products/1'))['product'] as Map<String, dynamic>;
    final forn = (await amb.dados.listFornecedores()).first;
    final vendaOk = (await a.post('/api/sales', {
      'forma_pagamento': 'Dinheiro',
      'valor_recebido': 100,
      'itens': [item(1, 1)],
    }))['sale'];
    final p1 = (await a.get('/api/products/1'))['product'];
    final casos = {
      'valor_recebido_venda': await a.post('/api/sales', {
        'forma_pagamento': 'Dinheiro',
        'valor_recebido': 1e12,
        'itens': [item(1, 1)],
      }),
      'valor_recebido_edicao': await a.put('/api/sales/${vendaOk['id_venda']}', {
        'valor_recebido': 1e12,
        'itens': [item(1, 1)],
      }),
      'preco_custo': await a.put('/api/products/1', {...pr, 'preco_custo': 1e12}),
      'preco_max': await a.put('/api/products/1', {...pr, 'preco_max': 1e12}),
      'estoque_minimo': await a.put('/api/products/1', {...pr, 'estoque_minimo': 1e13}),
      'quantidade_fisica': await a.post('/api/inventory', {
        'observacao': 'Conferência com valor enorme',
        'itens': [
          {'id_produto': 1, 'quantidade_fisica': 1e13},
        ],
      }),
      'valor_unitario': await a.post('/api/requisitions', {'fornecedor': forn, 'id_produto': 1, 'quantidade_pedida': 1, 'valor_unitario': 1e12}),
      'total_requisicao': await a.post('/api/requisitions', {'fornecedor': forn, 'id_produto': 1, 'quantidade_pedida': 999999, 'valor_unitario': 99999999}),
      'saldo_entrada': await a.post('/api/movements', {'tipo_movimentacao': 'Entrada', 'observacao': 'Entrada que estoura o saldo', 'id_produto': 1, 'quantidade': 999999999}),
    };
    for (final MapEntry(key: campo, value: r) in casos.entries) {
      expect(r.status, 400, reason: '$campo: ${r.status} ${r.error}');
      expect(r.error, matches(RegExp(r'grandes? demais')), reason: campo);
    }
    expect((await a.get('/api/products/1'))['product']['preco_custo'], pr['preco_custo']);
    expect(await saldo(1), p1['quantidade_estoque']);
    expect((await a.get('/api/sales/${vendaOk['id_venda']}'))['sale']['valor_recebido'], 100);
  });

  test('Fase 2 item 5: conferência só deixa de ajustar com o booleano false; texto é recusado', () async {
    final a = await admin();
    final s = await saldo(12);
    Future<Resp> conf(Object? ajustar) => a.post('/api/inventory', {
          'observacao': 'Conferência sem ajuste de estoque',
          'ajustar': ajustar,
          'itens': [
            {'id_produto': 12, 'quantidade_fisica': s - 7, 'quantidade_sistema': s},
          ],
        });
    for (final v in ['false', 0, 'true', null]) {
      final r = await conf(v);
      expect(r.status, 400, reason: 'ajustar=${jsonEncode(v)}');
      expect(await saldo(12), s);
    }
    final r = await conf(false);
    expect(r.status, 201);
    expect(r['conferencia']['ajustou_estoque'], false);
    expect(await saldo(12), s);
  });

  test('Fase 2 item 6: trocar a própria senha por PUT /api/users/:id encerra as outras sessões e mantém a atual', () async {
    final a = await admin();
    final outra = await admin();
    final eu = (await a.get('/api/auth/me'))['user']['id_usuario'];
    final r = await a.put('/api/users/$eu', {'senha': 'admin123'});
    expect(r.status, 200, reason: r.error);
    expect((await a.get('/api/auth/me')).status, 200);
    expect((await outra.get('/api/auth/me')).status, 401);
    // Senha de outro funcionário continua derrubando todas as sessões dele.
    final f = await func();
    final idf = (await f.get('/api/auth/me'))['user']['id_usuario'];
    expect((await a.put('/api/users/$idf', {'senha': 'func123'})).status, 200);
    expect((await f.get('/api/auth/me')).status, 401);
  });
}
