// Testes de API baseados nos cenários BDD do Apêndice F do relatório (porte 1:1 de api.test.js).
// Rodam num banco MySQL separado (gestfast_api_test), recriado do zero a cada execução.
import 'package:mysql_dart/mysql_dart.dart';
import 'package:test/test.dart';

import 'apoio/ambiente.dart';

late Ambiente amb;
String get base => amb.base;
Future<num> saldo(Object id) async => (await amb.dados.getProductById(id))!['quantidade_estoque'] as num;

Future<Cliente> logar(String email, String senha) async {
  final c = Cliente(base);
  final r = await c.post('/api/auth/login', {'email': email, 'senha': senha});
  expect(r.status, 200, reason: r.error);
  return c;
}

Future<Cliente> admin() => logar('proprietario@padarianovayork.com', 'admin123');
Future<Cliente> func() => logar('henry@padarianovayork.com', 'func123');
Future<Cliente> back() => logar('backoffice@padarianovayork.com', 'backoffice123');

void main() {
  setUpAll(() async => amb = await Ambiente.iniciar(nomeBanco: 'gestfast_api_test'));
  tearDownAll(() async => amb.encerrar());

  test('Cenário 5/6: login válido e credenciais inválidas', () async {
    final c = Cliente(base);
    var r = await c.post('/api/auth/login', {'email': 'nao@existe.com', 'senha': 'x'});
    expect(r.status, 401);
    expect(r.error, 'E-mail ou senha incorretos');
    r = await c.post('/api/auth/login', {'email': 'proprietario@padarianovayork.com', 'senha': 'admin123'});
    expect(r.status, 200);
    expect(r['message'], 'Login realizado com sucesso');
    expect((await c.get('/api/auth/me'))['user']['perfil'], 'Administrador');
    await c.post('/api/auth/logout');
    expect((await c.get('/api/auth/me')).status, 401);
  });

  test('API exige autenticação e respeita perfis', () async {
    expect((await Cliente(base).get('/api/products')).status, 401);
    final f = await func();
    expect((await f.get('/api/users')).status, 403);
    expect((await f.get('/api/reports/sales')).status, 403);
    expect((await f.post('/api/products', {'nome_produto': 'X'})).status, 403);
    final b = await back();
    expect((await b.post('/api/sales', {'itens': []})).status, 403);
  });

  test('Senhas são armazenadas com hash (RNF 05)', () async {
    final usuarios = await amb.dados.query('SELECT senha FROM usuario');
    expect(usuarios.length >= 3 && usuarios.every((u) => (u['senha'] as String).startsWith(r'scrypt$')), isTrue);
  });

  test('Cenários 10-18: manter funcionários', () async {
    final a = await admin();
    var r = await a.post('/api/users', {'nome': 'Maria Silva', 'email': 'maria@padaria.com', 'senha': 'senha123', 'id_perfil': 3});
    expect(r.status, 201);
    final id = r['user']['id_usuario'];
    expect(
      (await a.post('/api/users', {'nome': 'Outra', 'email': 'MARIA@padaria.com', 'senha': 'senha123', 'id_perfil': 3})).error,
      'O login informado já está em uso. Informe outro identificador.',
    );
    expect((await a.post('/api/users', {'nome': '', 'email': 'x', 'senha': '1', 'id_perfil': 9})).status, 400);
    expect((await a.put('/api/users/$id', {'cargo': 'Padeira'}))['user']['cargo'], 'Padeira');
    expect((await a.put('/api/users/$id', {'id_perfil': 2}))['user']['perfil'], 'BackOffice');
    expect(((await a.get('/api/users?id_perfil=2'))['users'] as List).any((u) => u['id_usuario'] == id), isTrue);
    expect(((await a.get('/api/users?q=maria'))['users'] as List).length, 1);
    final m = await logar('maria@padaria.com', 'senha123');
    expect((await a.patch('/api/users/$id/status', {'status': 'Inativo'})).status, 200);
    expect((await m.get('/api/products')).status, 401);
    final c = Cliente(base);
    final bloq = await c.post('/api/auth/login', {'email': 'maria@padaria.com', 'senha': 'senha123'});
    expect(bloq.error, 'Sua conta está inativa. Entre em contato com o administrador');
    expect((await a.patch('/api/users/1/status', {'status': 'Inativo'})).status, 400); // não desativa a si/único admin
  });

  test('Cenários 19-27: manter produtos (validações, filtro, inativar)', () async {
    final a = await admin();
    final ok = {
      'nome_produto': 'Broa de Milho',
      'descricao': 'Broa de milho caseira assada na hora',
      'id_categoria': 1,
      'unidade': 'UN',
      'preco_custo': 1,
      'preco_venda': 4,
      'preco_min': 3,
      'preco_max': 6,
      'estoque_minimo': 5,
      'quantidade_estoque': 20,
    };
    var r = await a.post('/api/products', ok);
    expect(r.status, 201);
    final id = r['product']['id_produto'];
    expect((await a.post('/api/products', {...ok, 'preco_venda': 0})).error, 'O preço de venda deve ser maior que zero.');
    expect((await a.post('/api/products', {...ok, 'nome_produto': ''})).status, 400);
    expect((await a.post('/api/products', {...ok, 'codigo_barras': '78910001'})).status, 400);
    expect((await a.post('/api/products', {...ok, 'estoque_minimo': 2.5})).status, 400);
    expect(((await a.get('/api/products?category=1'))['products'] as List).every((p) => p['id_categoria'] == 1), isTrue);
    expect((await a.put('/api/products/$id', {...ok, 'preco_venda': 5}))['product']['preco_venda'], 5);
    expect((await a.put('/api/products/$id', {...ok, 'estoque_minimo': 0}))['product']['estoque_minimo'], 0);
    expect((await a.del('/api/products/$id')).status, 200);
    expect(((await a.get('/api/products'))['products'] as List).any((p) => p['id_produto'] == id), isFalse);
    expect(((await a.get('/api/products?status=Inativo'))['products'] as List).any((p) => p['id_produto'] == id), isTrue);
    expect((await a.patch('/api/products/$id/status', {'status': 'Ativo'})).status, 200);
    const img = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';
    final pi = await a.put('/api/products/$id', {...ok, 'imagem_data': img});
    expect(pi['product']['imagem'], matches(RegExp(r'^uploads/prod-')));
    final f = await requisitar('GET', '$base/${pi['product']['imagem']}');
    expect(f.status, 200);
    expect((await a.put('/api/products/$id', {...ok, 'imagem_data': 'data:text/html;base64,AAAA'})).status, 400);
  });

  test('Cenário 7: venda com baixa automática, quantidade inteira e preço dentro da faixa', () async {
    final f = await func();
    final antes = await saldo(8);
    final r = await f.post('/api/sales', {
      'itens': [
        {'id_produto': 8, 'quantidade': 3},
      ],
      'forma_pagamento': 'PIX',
    });
    expect(r.status, 201);
    expect(r['message'], 'Venda realizada com sucesso');
    expect(await saldo(8), antes - 3);
    expect(r['sale']['valor_total'], 18);
    // bug "quant" quebrado: 1,3 em UN deve ser recusado; em KG é aceito
    expect(
      (await f.post('/api/sales', {
        'itens': [
          {'id_produto': 1, 'quantidade': 1.3},
        ],
      }))
          .error,
      matches('só aceita quantidades inteiras'),
    );
    expect(
      (await f.post('/api/sales', {
        'itens': [
          {'id_produto': 4, 'quantidade': 1.3},
        ],
      }))
          .status,
      201,
    );
    expect(
      (await f.post('/api/sales', {
        'itens': [
          {'id_produto': 8, 'quantidade': 1, 'valor_unitario': 1},
        ],
      }))
          .status,
      400,
    );
    expect((await f.post('/api/sales', {'itens': []})).status, 400);
  });

  test('Exceções de venda: estoque insuficiente, produto inexistente, cartão negado, desconto acima do limite', () async {
    final f = await func();
    expect(
      (await f.post('/api/sales', {
        'itens': [
          {'id_produto': 3, 'quantidade': 500},
        ],
      }))
          .error,
      matches('Quantidade indisponível em estoque'),
    );
    expect(
      (await f.post('/api/sales', {
        'itens': [
          {'id_produto': 9999, 'quantidade': 1},
        ],
      }))
          .error,
      'Produto não cadastrado.',
    );
    expect(
      (await f.post('/api/sales', {
        'itens': [
          {'id_produto': 8, 'quantidade': 10},
        ],
        'desconto': 50,
        'desconto_tipo': 'percentual',
      }))
          .error,
      matches('limite permitido'),
    );
    final a = await admin();
    await a.put('/api/settings', {'simularCartaoNegado': true});
    final estoque = await saldo(8);
    final neg = await f.post('/api/sales', {
      'itens': [
        {'id_produto': 8, 'quantidade': 1},
      ],
      'forma_pagamento': 'Cartão Crédito',
    });
    expect(neg.error, 'Transação Negada pela Operadora');
    expect(await saldo(8), estoque); // nada gravado
    await a.put('/api/settings', {'simularCartaoNegado': false});
  });

  test('Cancelar/editar/excluir venda (cenários 8 e 9, RF 09)', () async {
    final f = await func();
    final v = (await f.post('/api/sales', {
      'itens': [
        {'id_produto': 8, 'quantidade': 2},
      ],
    }))['sale'];
    final est = await saldo(8);
    // edição recalcula total e ajusta estoque
    var r = await f.put('/api/sales/${v['id_venda']}', {
      'itens': [
        {'id_produto': 8, 'quantidade': 5},
      ],
    });
    expect(r['sale']['valor_total'], 30);
    expect(await saldo(8), est - 3);
    // cancelamento exige senha de gerente
    expect(
      (await f.post('/api/sales/${v['id_venda']}/cancel', {
        'motivo': 'Cliente desistiu da compra',
        'autorizador_email': 'henry@padarianovayork.com',
        'autorizador_senha': 'func123',
      }))
          .status,
      403,
    );
    r = await f.post('/api/sales/${v['id_venda']}/cancel', {
      'motivo': 'Cliente desistiu da compra',
      'autorizador_email': 'proprietario@padarianovayork.com',
      'autorizador_senha': 'admin123',
    });
    expect(r['sale']['status_venda'], 'Cancelada');
    expect(await saldo(8), est + 2);
    expect(
      (await f.post('/api/sales/${v['id_venda']}/cancel', {
        'motivo': 'Cliente desistiu da compra',
        'autorizador_email': 'proprietario@padarianovayork.com',
        'autorizador_senha': 'admin123',
      }))
          .status,
      400,
    );
    // exclusão: só administrador
    expect((await f.del('/api/sales/${v['id_venda']}', {})).status, 403);
    final a = await admin();
    expect(
      (await a.del('/api/sales/${v['id_venda']}', {'autorizador_email': 'proprietario@padarianovayork.com', 'autorizador_senha': 'admin123'}))['message'],
      'Venda excluída com sucesso',
    );
    expect((await a.get('/api/sales/${v['id_venda']}')).status, 404);
  });

  test('Cenários 1-2: requisição ao fornecedor, recebimento parcial/total e cancelamento com justificativa', () async {
    final f = await func();
    final baseReq = {'id_produto': 6, 'quantidade_pedida': 10, 'fornecedor': 'Moinho Paulista de Trigo', 'valor_unitario': 4.1};
    var r = await f.post('/api/requisitions', baseReq);
    expect(r.status, 201);
    expect(r['message'], 'Pedido realizado com sucesso');
    final id = r['requisicao']['id_requisicao'];
    expect((await f.post('/api/requisitions', {...baseReq, 'fornecedor': 'Inventado'})).status, 400);
    final est = await saldo(6);
    r = await f.patch('/api/requisitions/$id/status', {'situacao': 'Finalizado', 'quantidade_recebida': 4});
    expect(r['requisicao']['situacao'], 'Em Aberto');
    expect(await saldo(6), est + 4);
    expect((await f.patch('/api/requisitions/$id/status', {'situacao': 'Finalizado', 'quantidade_recebida': 99})).status, 400);
    r = await f.patch('/api/requisitions/$id/status', {'situacao': 'Finalizado'});
    expect(r['requisicao']['situacao'], 'Finalizado');
    expect(await saldo(6), est + 10);
    // funcionário não avança status (financeiro/backoffice)
    final r2 = (await f.post('/api/requisitions', baseReq))['requisicao']['id_requisicao'];
    expect((await f.patch('/api/requisitions/$r2/status', {'situacao': 'Cotado'})).status, 403);
    final b = await back();
    expect((await b.patch('/api/requisitions/$r2/status', {'situacao': 'Cotado'}))['requisicao']['situacao'], 'Cotado');
    expect((await b.patch('/api/requisitions/$r2/status', {'situacao': 'AF Gerada'}))['requisicao']['situacao'], 'AF Gerada');
    // cancelamento
    expect((await f.patch('/api/requisitions/$r2/status', {'situacao': 'Cancelado', 'justificativa': 'curto'})).status, 400);
    final a = await admin();
    await a.put('/api/settings', {'simularFornecedorIndisponivel': true});
    expect(
      (await f.patch('/api/requisitions/$r2/status', {'situacao': 'Cancelado', 'justificativa': 'Pedido duplicado no sistema'})).error,
      matches('Falha de comunicação com o sistema do fornecedor'),
    );
    await a.put('/api/settings', {'simularFornecedorIndisponivel': false});
    r = await f.patch('/api/requisitions/$r2/status', {'situacao': 'Cancelado', 'justificativa': 'Pedido duplicado no sistema'});
    expect(r['message'], 'Solicitação de cancelamento encaminhada com sucesso');
    expect((await f.patch('/api/requisitions/$r2/status', {'situacao': 'Finalizado'})).status, 400);
  });

  test('RF 04: movimentação individual e em lote, com atomicidade', () async {
    final f = await func();
    final e1 = await saldo(5);
    var r = await f.post('/api/movements', {
      'tipo_movimentacao': 'Entrada',
      'observacao': 'Recebimento de caixa de insumos',
      'itens': [
        {'id_produto': 5, 'quantidade': 10},
        {'id_produto': 6, 'quantidade': 5},
      ],
    });
    expect(r.status, 201);
    expect((r['movements'] as List).length, 2);
    expect(await saldo(5), e1 + 10);
    r = await f.post('/api/movements', {
      'tipo_movimentacao': 'Saída',
      'observacao': 'Descarte por validade vencida',
      'itens': [
        {'id_produto': 5, 'quantidade': 1},
        {'id_produto': 6, 'quantidade': 9999},
      ],
    });
    expect(r.status, 400);
    expect(await saldo(5), e1 + 10); // rollback do lote
    expect((await f.post('/api/movements', {'tipo_movimentacao': 'Saída', 'observacao': 'curto', 'id_produto': 5, 'quantidade': 1})).status, 400);
    expect(((await f.get('/api/movements?tipo=Entrada'))['movements'] as List).every((m) => m['tipo_movimentacao'] == 'Entrada'), isTrue);
  });

  test('RF 06: conferência de estoque ajusta saldos e registra divergência', () async {
    final f = await func();
    final antes = await saldo(12);
    final r = await f.post('/api/inventory', {
      'observacao': 'Conferência quinzenal do estoque',
      'itens': [
        {'id_produto': 12, 'quantidade_fisica': antes - 7},
      ],
    });
    expect(r.status, 201);
    expect(r['conferencia']['itens'][0]['divergencia'], -7);
    expect(await saldo(12), antes - 7);
    expect(
      (await f.post('/api/inventory', {
        'observacao': 'Conferência quinzenal do estoque',
        'itens': [
          {'id_produto': 1, 'quantidade_fisica': 2.5},
        ],
      }))
          .status,
      400,
    );
    expect(((await f.get('/api/inventory'))['conferencias'] as List).length >= 2, isTrue);
  });

  test('Cenário 3: alerta de estoque crítico no dashboard', () async {
    final f = await func();
    final d = (await f.get('/api/dashboard'))['data'];
    expect(
      (d['alertas'] as List).any(
        (a) => a['mensagem'] == 'Atenção: Farinha de Trigo Especial 1kg atingiu o estoque mínimo' || (a['mensagem'] as String).startsWith('Atenção: '),
      ),
      isTrue,
    );
    expect((d['alertas'] as List).length, d['metricas']['alertasCriticosCount']);
  });

  test('Cenário 4 / RF 12-14: relatórios com filtros e exportação PDF e XLSX', () async {
    final b = await back();
    final hoje = amb.dados.dataISO();
    var r = await b.get('/api/reports/sales?from=$hoje&to=$hoje');
    expect(r['report']['quantidadeTransacoes'] > 0, isTrue);
    final soma = (r['report']['itensVendidos'] as List).fold<num>(0, (a, i) => a + i['total']);
    expect((soma - r['report']['totalBruto']).abs() < 0.01, isTrue);
    expect(((await b.get('/api/reports/sales?from=2000-01-01&to=2000-01-02'))['report']['itensVendidos'] as List).length, 0);
    expect((await b.get('/api/reports/sales?from=2026-12-01&to=2026-01-01')).status, 400);
    final cat = (await b.get('/api/reports/sales?categoria=2'))['report'];
    expect((cat['itensVendidos'] as List).every((i) => i['categoria'] == 'Bebidas & Cafés'), isTrue);
    final pdf = await requisitar('GET', '$base/api/reports/sales?format=pdf&from=$hoje&to=$hoje', headers: {'cookie': b.cookie});
    expect(pdf.headers.value('content-type'), 'application/pdf');
    expect(String.fromCharCodes(pdf.bytes.sublist(0, 5)), '%PDF-');
    final xlsx = await requisitar('GET', '$base/api/reports/stock?format=xlsx', headers: {'cookie': b.cookie});
    expect(xlsx.headers.value('content-disposition'), matches(r'\.xlsx'));
    expect(String.fromCharCodes(xlsx.bytes.sublist(0, 2)), 'PK');
    final st = (await b.get('/api/reports/stock'))['report'];
    expect((st['linhas'] as List).every((l) => l['situacao'] == (l['saldo_atual'] <= l['estoque_minimo'] ? 'Crítico' : 'Regular')), isTrue);
    expect((await b.get('/api/reports/stock?format=doc')).status, 400);
  });

  test('Persistência no MySQL e logs (RNF 06)', () async {
    // Uma conexão nova (fora do pool do sistema) enxerga as mesmas vendas gravadas pela API.
    final conn = await MySQLConnection.createConnection(
      host: envTeste['host']!,
      port: int.parse(envTeste['port']!),
      userName: envTeste['user']!,
      password: envTeste['password']!,
      databaseName: 'gestfast_api_test',
      secure: false,
      allowPublicKeyRetrieval: true,
    );
    await conn.connect();
    final n = int.parse((await conn.execute('SELECT COUNT(*) AS n FROM venda')).rows.first.colAt(0) as String);
    await conn.close();
    expect(n, (await amb.dados.getVendas()).length);
    expect(n > 6, isTrue); // as 6 de exemplo + as criadas nos testes
    final a = await admin();
    final logs = (await a.get('/api/logs'))['logs'] as List;
    expect(
      logs.any((l) => l['evento'] == 'login') && logs.any((l) => l['evento'] == 'login_falhou') && logs.any((l) => l['evento'] == 'operacao'),
      isTrue,
    );
    expect((await (await func()).get('/api/logs')).status, 403);
  });

  test('Recuperação de senha por link (fluxo de exceção IV)', () async {
    final c = Cliente(base);
    expect((await c.post('/api/auth/forgot', {'email': 'ninguem@x.com'})).status, 200);
    final r = await amb.dados.createResetToken('henry@padarianovayork.com');
    expect((await c.post('/api/auth/reset', {'token': 'invalido', 'senha': 'novasenha1'})).status, 400);
    expect((await c.post('/api/auth/reset', {'token': r!.token, 'senha': 'novasenha1'})).status, 200);
    expect((await c.post('/api/auth/reset', {'token': r.token, 'senha': 'outrasenha1'})).status, 400); // token de uso único
    await logar('henry@padarianovayork.com', 'novasenha1');
  });

  test('Busca global: encontra conteúdo e respeita o perfil', () async {
    final a = await admin();
    var r = (await a.get('/api/search?q=pao'))['results']; // sem acento
    expect((r['produtos'] as List).any((p) => p['nome_produto'] == 'Pão Francês'), isTrue);
    expect(((await a.get('/api/search?q=REQ-9661'))['results']['requisicoes'] as List).isNotEmpty, isTrue);
    expect(((await a.get('/api/search?q=VENDA-100'))['results']['vendas'] as List).isNotEmpty, isTrue);
    expect(((await a.get('/api/search?q=henry'))['results']['usuarios'] as List).isNotEmpty, isTrue);
    expect(((await a.get('/api/search?q=p'))['results']['produtos'] as List).length, 0); // mínimo de 2 letras
    final f = await logar('henry@padarianovayork.com', 'novasenha1'); // senha trocada no teste de recuperação
    r = (await f.get('/api/search?q=henry'))['results'];
    expect((r['usuarios'] as List).length, 0); // funcionário não vê a lista de usuários
    expect((await Cliente(base).get('/api/search?q=pao')).status, 401);
  });

  test('Etapa 2: alerta de validade no painel e na API', () async {
    final a = await admin();
    final r = await a.get('/api/expiring');
    expect(r['dias'], 3);
    final itens = r['itens'] as List;
    final doce = itens.firstWhere((i) => i['nome_produto'] == 'Pão Doce Tradicional');
    expect(doce['situacao'], 'Vencido');
    expect(doce['dias_restantes'], -1);
    expect(itens.firstWhere((i) => i['nome_produto'] == 'Pão Francês')['dias_restantes'], 1);
    expect(itens.any((i) => i['nome_produto'] == 'Queijo Mussarela Fatiado'), isFalse); // vence em 7 dias
    expect(itens.every((i) => i['quantidade_estoque'] > 0 && i['dias_restantes'] <= 3), isTrue);
    final d = (await a.get('/api/dashboard'))['data'];
    expect(d['metricas']['produtosVencidosCount'], r['vencidos']);
    expect(d['metricas']['produtosVencendoCount'], itens.length);
    expect((await a.put('/api/settings', {'diasAlertaValidade': 99})).status, 400);
    await a.put('/api/settings', {'diasAlertaValidade': 10});
    expect(((await a.get('/api/expiring'))['itens'] as List).any((i) => i['nome_produto'] == 'Queijo Mussarela Fatiado'), isTrue);
    await a.put('/api/settings', {'diasAlertaValidade': 3});
  });

  test('Etapa 2: registro de perdas e sobras com baixa no estoque', () async {
    final a = await admin();
    final antes = await saldo(11);
    var r = await a.post('/api/losses', {
      'motivo_perda': 'Vencido',
      'itens': [
        {'id_produto': 11, 'quantidade': 5},
      ],
    });
    expect(r.status, 201, reason: r.error);
    expect(await saldo(11), antes - 5);
    final m = r['movements'][0];
    expect(m['origem'], 'perda');
    expect(m['motivo_perda'], 'Vencido');
    expect(m['valor_unitario'], 1.10);
    expect(m['valor_total'], 5.5); // valor de custo
    expect(
      (await a.post('/api/losses', {
        'motivo_perda': 'Roubo',
        'itens': [
          {'id_produto': 11, 'quantidade': 1},
        ],
      }))
          .status,
      400,
    );
    expect(
      (await a.post('/api/losses', {
        'motivo_perda': 'Outro',
        'itens': [
          {'id_produto': 11, 'quantidade': 1},
        ],
      }))
          .status,
      400,
    ); // "Outro" exige observação
    r = await a.post('/api/losses', {
      'motivo_perda': 'Quebra/Avaria',
      'itens': [
        {'id_produto': 9, 'quantidade': 1},
        {'id_produto': 11, 'quantidade': 99999},
      ],
    });
    expect(r.status, 400);
    expect(await saldo(11), antes - 5); // rollback do lote
    expect(
      (await a.post('/api/losses', {
        'motivo_perda': 'Sobra do dia',
        'itens': [
          {'id_produto': 4, 'quantidade': 1.5},
        ],
      }))
          .status,
      201,
    ); // KG aceita fração
    final saidas = (await a.get('/api/movements?tipo=Saída'))['movements'] as List;
    expect(saidas.any((s) => s['origem'] == 'perda' && s['motivo_perda'] == 'Sobra do dia'), isTrue);
  });

  test('Etapa 2: relatório de desperdício com exportação', () async {
    final b = await back();
    final r = (await b.get('/api/reports/losses'))['report'];
    expect(r['totalRegistros'] >= 3, isTrue);
    expect(((r['porProduto'] as List).fold<num>(0, (s, p) => s + p['valor_total']) - r['valorTotal']).abs() < 0.01, isTrue);
    expect(((r['porMotivo'] as List).fold<num>(0, (s, p) => s + p['valor_total']) - r['valorTotal']).abs() < 0.01, isTrue);
    expect((r['registros'] as List).every((x) => x['origem'] == 'perda'), isTrue);
    expect(((await b.get('/api/reports/losses?categoria=2'))['report']['registros'] as List).every((x) => x['categoria'] == 'Bebidas & Cafés'), isTrue);
    final pdf = await requisitar('GET', '$base/api/reports/losses?format=pdf', headers: {'cookie': b.cookie});
    expect(String.fromCharCodes(pdf.bytes.sublist(0, 5)), '%PDF-');
    final xlsx = await requisitar('GET', '$base/api/reports/losses?format=xlsx', headers: {'cookie': b.cookie});
    expect(String.fromCharCodes(xlsx.bytes.sublist(0, 2)), 'PK');
    final f = await logar('henry@padarianovayork.com', 'novasenha1');
    expect((await f.get('/api/reports/losses')).status, 403);
  });

}
