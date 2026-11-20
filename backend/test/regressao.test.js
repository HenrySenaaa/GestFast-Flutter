// Testes de regressão: um para cada bug corrigido na migração para Flutter, mais o acesso por token.
// Rodam no banco gestfast_test, recriado do zero. O banco "gestfast" não é tocado.
const os = require('os');
const path = require('path');
const fs = require('fs');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'gestfast-reg-'));
process.env.DB_NAME = process.env.DB_TEST_NAME || 'gestfast_test';
process.env.GESTFAST_UPLOAD_DIR = path.join(tmp, 'uploads');
process.env.GESTFAST_LOG_DIR = path.join(tmp, 'logs');
process.env.GESTFAST_WEB_DIR = path.join(tmp, 'web');
process.env.GESTFAST_QUIET = '1';
process.env.CORS_ORIGINS = 'http://app.test';
fs.mkdirSync(path.join(tmp, 'web'));
fs.mkdirSync(path.join(tmp, 'web-secreto'));
fs.writeFileSync(path.join(tmp, 'web', 'index.html'), '<title>app</title>');
fs.writeFileSync(path.join(tmp, 'web-secreto', 'x.txt'), 'segredo');

const test = require('node:test');
const assert = require('node:assert/strict');
const { recriarBancoDeTeste } = require('./setup-db');
const server = require('../server');
const db = require('../db');
const auth = require('../lib/auth');
const saldo = async id => (await db.getProductById(id)).quantidade_estoque;

let base;
test.before(async () => {
  await recriarBancoDeTeste(process.env.DB_NAME);
  await new Promise(r => server.listen(0, r));
  base = `http://localhost:${server.address().port}`;
});
test.after(async () => { server.close(); await db.end(); });

function cliente() {
  let cookie = '';
  const call = async (method, url, body) => {
    const res = await fetch(base + url, { method, headers: { 'Content-Type': 'application/json', ...(cookie ? { cookie } : {}) }, body: body === undefined ? undefined : JSON.stringify(body) });
    const sc = res.headers.get('set-cookie');
    if (sc) cookie = sc.split(';')[0].endsWith('=') ? '' : sc.split(';')[0];
    const texto = await res.text();
    let json = {};
    try { json = JSON.parse(texto); } catch (e) { json = { texto }; }
    return { status: res.status, ...json };
  };
  return { get: u => call('GET', u), post: (u, b) => call('POST', u, b === undefined ? {} : b), put: (u, b) => call('PUT', u, b), patch: (u, b) => call('PATCH', u, b), del: (u, b) => call('DELETE', u, b === undefined ? {} : b) };
}
async function logar(email, senha) { const c = cliente(); const r = await c.post('/api/auth/login', { email, senha }); assert.equal(r.status, 200, r.error); return c; }
const admin = () => logar('proprietario@padarianovayork.com', 'admin123');
const func = () => logar('henry@padarianovayork.com', 'func123');
const novoProduto = { descricao: 'Produto criado para teste de regressão', id_categoria: 1, unidade: 'UN', preco_custo: 2, preco_venda: 10, preco_min: 5, preco_max: 20, estoque_minimo: 1 };

// ---------------------------------------------------------------- dados
test('Bug 1: salvar produto não sobrescreve o saldo; estoque inicial entra no histórico', async () => {
  const a = await admin();
  const criado = (await a.post('/api/products', { ...novoProduto, nome_produto: 'Regressão Saldo', quantidade_estoque: 10 })).product;
  const id = criado.id_produto;
  const movs = (await a.get('/api/movements?tipo=Entrada')).movements.filter(m => m.id_produto === id);
  assert.equal(movs.length, 1);
  assert.equal(movs[0].quantidade, 10);
  assert.equal(movs[0].valor_unitario, 2);
  await (await func()).post('/api/sales', { itens: [{ id_produto: id, quantidade: 3 }] });
  // formulário aberto antes da venda reenvia o saldo antigo (10)
  const r = await a.put(`/api/products/${id}`, { ...novoProduto, nome_produto: 'Regressão Saldo', quantidade_estoque: 10 });
  assert.equal(r.status, 200);
  assert.equal(await saldo(id), 7);
});

test('Bug 2: conferência recusa contagem feita sobre saldo desatualizado', async () => {
  const f = await func();
  const lido = await saldo(11);
  await f.post('/api/sales', { itens: [{ id_produto: 11, quantidade: 2 }] });
  const r = await f.post('/api/inventory', { observacao: 'Conferência com saldo antigo na tela', itens: [{ id_produto: 11, quantidade_fisica: lido, quantidade_sistema: lido }] });
  assert.equal(r.status, 409);
  assert.match(r.error, /Pão Doce/);
  assert.equal(await saldo(11), lido - 2);
  const ok = await f.post('/api/inventory', { observacao: 'Conferência com saldo atualizado', itens: [{ id_produto: 11, quantidade_fisica: lido - 2, quantidade_sistema: lido - 2 }] });
  assert.equal(ok.status, 201);
});

test('Bug 3: editar venda em dinheiro recalcula o troco e exige valor recebido suficiente', async () => {
  const a = await admin();
  const v = (await a.post('/api/sales', { itens: [{ id_produto: 8, quantidade: 2 }], forma_pagamento: 'Dinheiro', valor_recebido: 20 })).sale;
  assert.equal(v.troco, 8);
  const e1 = await a.put(`/api/sales/${v.id_venda}`, { itens: [{ id_produto: 8, quantidade: 1 }] });
  assert.equal(e1.sale.valor_total, 6);
  assert.equal(e1.sale.troco, 14);
  const e2 = await a.put(`/api/sales/${v.id_venda}`, { itens: [{ id_produto: 8, quantidade: 5 }] });
  assert.equal(e2.status, 400);
  assert.match(e2.error, /recebido/i);
  const e3 = await a.put(`/api/sales/${v.id_venda}`, { itens: [{ id_produto: 8, quantidade: 5 }], valor_recebido: 50 });
  assert.equal(e3.sale.valor_recebido, 50);
  assert.equal(e3.sale.troco, 20);
});

test('Bug 4: editar venda preserva cada preço do mesmo produto', async () => {
  const a = await admin();
  const v = (await a.post('/api/sales', { itens: [{ id_produto: 12, quantidade: 1, valor_unitario: 0.3 }, { id_produto: 12, quantidade: 1, valor_unitario: 0.5 }] })).sale;
  assert.equal(v.valor_total, 0.8);
  // sem dizer qual linha, a edição seria ambígua
  assert.equal((await a.put(`/api/sales/${v.id_venda}`, { itens: [{ id_produto: 12, quantidade: 2 }] })).status, 400);
  const [l1, l2] = v.itens;
  const e = await a.put(`/api/sales/${v.id_venda}`, { itens: [{ id_produto: 12, id_item_venda: l1.id_item_venda, quantidade: 2 }, { id_produto: 12, id_item_venda: l2.id_item_venda, quantidade: 1 }] });
  assert.equal(e.status, 200, e.error);
  assert.equal(e.sale.valor_total, 1.1);
  assert.deepEqual(e.sale.itens.map(i => i.valor_unitario).sort(), [0.3, 0.5]);
});

test('Bug 5: editar venda não inclui produto inativo', async () => {
  const a = await admin();
  const p = (await a.post('/api/products', { ...novoProduto, nome_produto: 'Regressão Inativo', quantidade_estoque: 5 })).product;
  await a.patch(`/api/products/${p.id_produto}/status`, { status: 'Inativo' });
  const v = (await a.post('/api/sales', { itens: [{ id_produto: 8, quantidade: 1 }] })).sale;
  const r = await a.put(`/api/sales/${v.id_venda}`, { itens: [{ id_produto: 8, quantidade: 1 }, { id_produto: p.id_produto, quantidade: 1 }] });
  assert.equal(r.status, 400);
  assert.match(r.error, /inativo/i);
});

// ---------------------------------------------------------------- servidor e segurança
test('Bug 6: endereço malformado não derruba o servidor', async () => {
  for (const url of ['/%E0%A4%A', '/%00.png', '/api/%E0%A4%A', '/uploads/%E0%A4%A']) {
    const res = await fetch(base + url);
    assert.equal(res.status, 400, url);
  }
  assert.equal((await cliente().get('/api/auth/me')).status, 401);
});

test('Bug 7: erro interno responde 500, sem expor detalhes, e fica no log', async () => {
  const a = await admin();
  const original = db.listCategorias;
  db.listCategorias = async () => { throw new Error('SQL secreto: tabela xyz'); };
  try {
    const r = await a.get('/api/categories');
    assert.equal(r.status, 500);
    assert.doesNotMatch(r.error, /secreto/);
  } finally { db.listCategorias = original; }
  const logs = (await a.get('/api/logs')).logs;
  assert.ok(logs.some(l => l.evento === 'falha_interna' && /secreto/.test(l.erro)));
});

test('Bug 8: corpo e itens inválidos respondem 400 com mensagem clara', async () => {
  const f = await func();
  assert.equal((await f.post('/api/movements', null)).status, 400);
  assert.equal((await f.post('/api/movements', [1, 2])).status, 400);
  for (const [url, corpo] of [
    ['/api/movements', { tipo_movimentacao: 'Entrada', observacao: 'Observação válida de teste', itens: [null] }],
    ['/api/sales', { itens: [null] }],
    ['/api/inventory', { observacao: 'Observação válida de teste', itens: ['x'] }],
    ['/api/losses', { motivo_perda: 'Vencido', itens: [7] }]
  ]) {
    const r = await f.post(url, corpo);
    assert.equal(r.status, 400, url);
    assert.doesNotMatch(r.error, /Cannot read|undefined|null/, url);
  }
});

test('Bug 9: link de redefinição não fica nos logs', async () => {
  const c = cliente();
  await c.post('/api/auth/forgot', { email: 'backoffice@padarianovayork.com' });
  const logs = (await (await admin()).get('/api/logs')).logs;
  const ev = logs.filter(l => l.evento === 'redefinicao_senha_solicitada');
  assert.ok(ev.length >= 1);
  assert.doesNotMatch(JSON.stringify(ev.map(({ evento, ...resto }) => resto)), /reset|link|token/i);
});

test('Bug 10: senha de gerente tem limite de tentativas', async () => {
  const f = await func();
  const v = (await f.post('/api/sales', { itens: [{ id_produto: 8, quantidade: 1 }] })).sale;
  const corpo = { motivo: 'Cancelamento para teste de limite', autorizador_email: 'backoffice@padarianovayork.com', autorizador_senha: 'errada' };
  for (let i = 0; i < 5; i++) assert.equal((await f.post(`/api/sales/${v.id_venda}/cancel`, corpo)).status, 403);
  const r = await f.post(`/api/sales/${v.id_venda}/cancel`, { ...corpo, autorizador_senha: 'backoffice123' });
  assert.equal(r.status, 429);
});

test('Bug 11: trocar a senha encerra as outras sessões e mantém a atual', async () => {
  const a = await admin();
  const c = await admin();
  const r = await a.post('/api/auth/change-password', { senha_atual: 'admin123', nova_senha: 'admin123' });
  assert.equal(r.status, 200);
  assert.equal((await a.get('/api/auth/me')).status, 200);
  assert.equal((await c.get('/api/auth/me')).status, 401);
});

test('Bug 12: login com e-mail inexistente também calcula o hash', async () => {
  const original = auth.verifyPassword;
  let chamadas = 0;
  auth.verifyPassword = (...x) => { chamadas++; return original(...x); };
  try {
    const r = await cliente().post('/api/auth/login', { email: 'ninguem-aqui@x.com', senha: 'qualquer' });
    assert.equal(r.status, 401);
    assert.equal(chamadas, 1);
  } finally { auth.verifyPassword = original; }
});

test('Bug 13: arquivos estáticos não saem da pasta do app', async () => {
  const res = await fetch(`${base}/..%2fweb-secreto%2fx.txt`);
  assert.notEqual(await res.text(), 'segredo');
  assert.equal(res.status, 403);
  const raiz = await fetch(`${base}/`);
  assert.match(await raiz.text(), /<title>app/);
});

// ---------------------------------------------------------------- validação e consistência
test('Bug 14: datas impossíveis e filtros inválidos respondem 400', async () => {
  const a = await admin();
  const r = await a.post('/api/products', { ...novoProduto, nome_produto: 'Data Ruim', validade: '2030-02-31' });
  assert.equal(r.status, 400);
  assert.match(r.error, /validade/i);
  const q = await a.post('/api/requisitions', { id_produto: 8, fornecedor: 'Laticínios ABC', quantidade_pedida: 1, previsao_entrega: '2030-02-31' });
  assert.equal(q.status, 400);
  for (const url of ['/api/movements?from=abc', '/api/movements?to=2030-13-01', '/api/sales?from=abc', '/api/sales?to=2030-02-31']) {
    const x = await a.get(url);
    assert.equal(x.status, 400, url);
    assert.match(x.error, /data/i, url);
  }
});

test('Bug 15: quantidade que arredonda para zero é recusada com mensagem clara', async () => {
  const a = await admin();
  const antes = await saldo(4);
  const r = await a.post('/api/movements', { tipo_movimentacao: 'Entrada', observacao: 'Observação válida de teste', itens: [{ id_produto: 4, quantidade: 0.0001 }] });
  assert.equal(r.status, 400);
  assert.match(r.error, /maior que zero/);
  assert.equal(await saldo(4), antes);
  assert.equal((await a.post('/api/requisitions', { id_produto: 4, fornecedor: 'Laticínios ABC', quantidade_pedida: 0.0001 })).status, 400);
});

test('Bug 16: produto inválido não deixa imagem órfã', async () => {
  const a = await admin();
  const dir = process.env.GESTFAST_UPLOAD_DIR;
  const conta = () => (fs.existsSync(dir) ? fs.readdirSync(dir).length : 0);
  const antes = conta();
  const img = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';
  const r = await a.post('/api/products', { ...novoProduto, nome_produto: 'Sem Preço', preco_venda: 0, imagem_data: img });
  assert.equal(r.status, 400);
  assert.equal(conta(), antes);
  const ok = await a.post('/api/products', { ...novoProduto, nome_produto: 'Com Imagem', imagem_data: img });
  assert.match(ok.product.imagem, /^uploads\/prod-/);
  assert.equal(conta(), antes + 1);
});

test('Bug 17: vendas simultâneas em ordem inversa não travam', async () => {
  const a = await admin();
  const ps = [];
  for (const nome of ['Regressão A', 'Regressão B']) ps.push((await a.post('/api/products', { ...novoProduto, nome_produto: nome, quantidade_estoque: 500 })).product.id_produto);
  const venda = ordem => a.post('/api/sales', { itens: ordem.map(id => ({ id_produto: id, quantidade: 1 })) });
  const rs = await Promise.all(Array.from({ length: 30 }, (_, i) => venda(i % 2 ? ps : [...ps].reverse())));
  assert.deepEqual(rs.filter(r => r.status !== 201).map(r => r.error), []);
  assert.equal(await saldo(ps[0]), 470);
  assert.equal(await saldo(ps[1]), 470);
});

test('Bug 18: ajuste de conferência é sempre valorizado pelo custo', async () => {
  const a = await admin();
  const s = await saldo(10);
  await a.post('/api/inventory', { observacao: 'Conferência para testar o valor', itens: [{ id_produto: 10, quantidade_fisica: s - 1 }] });
  const m = (await a.get('/api/movements?tipo=Saída')).movements.find(x => x.id_produto === 10 && x.origem === 'conferencia');
  assert.equal(m.valor_unitario, 4.8);
});

test('Bug 19: simulações só aceitam verdadeiro ou falso', async () => {
  const a = await admin();
  const r = await a.put('/api/settings', { simularCartaoNegado: 'false' });
  assert.equal(r.status, 400);
  assert.equal((await a.get('/api/settings')).settings.simularCartaoNegado, false);
});

test('Bug 20: limitador de tentativas limpa entradas antigas', () => {
  const { criarLimitador } = require('../lib/limiter');
  let agora = 0;
  const l = criarLimitador({ max: 2, bloqueioMs: 100, janelaMs: 1000, relogio: () => agora });
  l.falhou('a');
  assert.equal(l.tamanho(), 1);
  l.falhou('a');
  assert.throws(() => l.checar('a'), e => e.status === 429);
  agora = 101;
  assert.doesNotThrow(() => l.checar('a'));
  agora = 5000;
  l.falhou('b');
  assert.equal(l.tamanho(), 1); // "a" expirou e foi limpo
});

test('Rota de produto ignora id e caminho de imagem enviados pelo cliente', async () => {
  const a = await admin();
  const antes = (await a.get('/api/products/1')).product.nome_produto;
  const r = await a.post('/api/products', { ...novoProduto, nome_produto: 'Tentou Editar', id_produto: 1, imagem: '../../segredo' });
  assert.equal(r.status, 201);
  assert.notEqual(r.product.id_produto, 1);
  assert.equal(r.product.imagem, '');
  assert.equal((await a.get('/api/products/1')).product.nome_produto, antes);
});

// ---------------------------------------------------------------- acesso pelo app
test('App: login por token (Bearer), sem cookie', async () => {
  const headers = { 'Content-Type': 'application/json', 'X-Client': 'app' };
  const res = await fetch(`${base}/api/auth/login`, { method: 'POST', headers, body: JSON.stringify({ email: 'henry@padarianovayork.com', senha: 'func123' }) });
  const d = await res.json();
  assert.equal(res.status, 200);
  assert.ok(d.token);
  assert.equal(res.headers.get('set-cookie'), null);
  const bearer = { Authorization: `Bearer ${d.token}` };
  assert.equal((await fetch(`${base}/api/auth/me`, { headers: bearer })).status, 200);
  assert.equal((await fetch(`${base}/api/auth/logout`, { method: 'POST', headers: { ...bearer, 'Content-Type': 'application/json' }, body: '{}' })).status, 200);
  assert.equal((await fetch(`${base}/api/auth/me`, { headers: bearer })).status, 401);
  // navegador: continua com cookie e sem token no corpo
  const web = await fetch(`${base}/api/auth/login`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email: 'henry@padarianovayork.com', senha: 'func123' }) });
  assert.equal((await web.json()).token, undefined);
  assert.match(web.headers.get('set-cookie'), /HttpOnly/);
});

test('App: CORS só para origens configuradas', async () => {
  const pre = await fetch(`${base}/api/products`, { method: 'OPTIONS', headers: { Origin: 'http://app.test', 'Access-Control-Request-Method': 'GET' } });
  assert.equal(pre.status, 204);
  assert.equal(pre.headers.get('access-control-allow-origin'), 'http://app.test');
  assert.match(pre.headers.get('access-control-allow-headers'), /Authorization/);
  const fora = await fetch(`${base}/api/auth/me`, { headers: { Origin: 'http://malicioso.test' } });
  assert.equal(fora.headers.get('access-control-allow-origin'), null);
});

// ---------------------------------------------------------------- fase 2 (Vigia)
test('Fase 2 item 7: GET /api/logs respeita o teto de 1000 com limites inválidos', async () => {
  const logger = require('../lib/logger');
  for (let i = 0; i < 1100; i++) logger.log('INFO', 'teste_teto_logs', { i });
  const a = await admin();
  const qtd = async q => { const r = await a.get('/api/logs' + q); assert.equal(r.status, 200); return r.logs.length; };
  assert.equal(await qtd('?limit=-1'), 200);
  assert.equal(await qtd('?limit=-5000'), 200);
  assert.equal(await qtd('?limit=abc'), 200);
  assert.equal(await qtd('?limit=0'), 200);
  assert.equal(await qtd('?limit=Infinity'), 200);
  assert.equal(await qtd(''), 200);
  assert.equal(await qtd('?limit=5000'), 1000);
  assert.equal(await qtd('?limit=3'), 3);
  assert.equal(await qtd('?limit=2.9'), 2);
});

test('Fase 2 item 10: falha simulada do fornecedor não vira falha_interna; falha_interna registra o usuário', async () => {
  const a = await admin();
  const marca = Date.now();
  assert.equal((await a.put('/api/settings', { simularFornecedorIndisponivel: true })).status, 200);
  try {
    const r = await a.post('/api/requisitions', { id_produto: 4, fornecedor: 'Laticínios ABC', quantidade_pedida: 1, observacao: 'Pedido com fornecedor fora do ar' });
    assert.equal(r.status, 503);
  } finally {
    assert.equal((await a.put('/api/settings', { simularFornecedorIndisponivel: false })).status, 200);
  }
  let logs = (await a.get('/api/logs?limit=50')).logs;
  const externa = logs.find(l => l.evento === 'falha_externa' && l.rota === '/api/requisitions');
  assert.ok(externa, 'falha do fornecedor deve ir ao log como falha_externa');
  assert.equal(externa.nivel, 'AVISO');
  assert.equal(externa.status, 503);
  assert.equal(externa.usuario, 'proprietario@padarianovayork.com');
  assert.ok(!logs.some(l => l.evento === 'falha_interna' && l.rota === '/api/requisitions'));

  const original = db.listCategorias;
  db.listCategorias = async () => { throw new Error(`falha interna ${marca}`); };
  try {
    assert.equal((await a.get('/api/categories')).status, 500);
  } finally { db.listCategorias = original; }
  logs = (await a.get('/api/logs?limit=50')).logs;
  const interna = logs.find(l => l.evento === 'falha_interna' && l.erro.includes(String(marca)));
  assert.ok(interna);
  assert.equal(interna.nivel, 'ERRO');
  assert.equal(interna.usuario, 'proprietario@padarianovayork.com');
});

// ---------------------------------------------------------------- fase 2 (Alicerce: banco)
const alertas = async (id, status = 'Ativo') =>
  Number((await db.query('SELECT COUNT(*) AS n FROM alerta_estoque WHERE id_produto = ? AND status_alerta = ?', [id, status]))[0].n);
const semErro = rs => rs.filter(r => r.status !== 201).map(r => `${r.status} ${r.error}`);

test('Fase 2 item 1: vendas/entradas paralelas de produtos diferentes não dão deadlock e mantêm os alertas', async () => {
  const a = await admin();
  const cria = async (nome, qtd, min) =>
    (await a.post('/api/products', { ...novoProduto, nome_produto: nome, quantidade_estoque: qtd, estoque_minimo: min })).product.id_produto;
  const venda = id => a.post('/api/sales', { itens: [{ id_produto: id, quantidade: 1 }] });
  const entrada = id => a.post('/api/movements', { tipo_movimentacao: 'Entrada', observacao: 'Entrada paralela de teste', id_produto: id, quantidade: 1 });

  // Cenário do Sonda: 60 vendas em paralelo, 30 só do produto A e 30 só do B.
  const A = await cria('Paralelo A', 500, 1), B = await cria('Paralelo B', 500, 1);
  assert.deepEqual(semErro(await Promise.all(Array.from({ length: 60 }, (_, i) => venda(i % 2 ? A : B)))), []);
  assert.equal(await saldo(A), 470);
  assert.equal(await saldo(B), 470);

  // 30 vendas de C + 30 entradas de D.
  const C = await cria('Paralelo C', 500, 1), D = await cria('Paralelo D', 500, 1);
  assert.deepEqual(semErro(await Promise.all(Array.from({ length: 60 }, (_, i) => (i % 2 ? venda(C) : entrada(D))))), []);
  assert.equal(await saldo(C), 470);
  assert.equal(await saldo(D), 530);

  // Alertas: E e F cruzam o estoque mínimo AO MESMO TEMPO (40 -> 10, mínimo 20). Cada um fica com exatamente 1 alerta ativo.
  const E = await cria('Paralelo E', 40, 20), F = await cria('Paralelo F', 40, 20);
  assert.equal(await alertas(E), 0);
  assert.deepEqual(semErro(await Promise.all(Array.from({ length: 60 }, (_, i) => venda(i % 2 ? E : F)))), []);
  assert.equal(await saldo(E), 10);
  assert.equal(await alertas(E), 1);
  assert.equal(await alertas(F), 1);
  assert.ok((await a.get('/api/alerts')).alerts.some(x => x.id_produto === E), 'alerta aparece em /api/alerts');
  // Entrada que tira do mínimo resolve o alerta só do produto tocado.
  assert.equal((await a.post('/api/movements', { tipo_movimentacao: 'Entrada', observacao: 'Reposição de teste', id_produto: E, quantidade: 100 })).status, 201);
  assert.equal(await alertas(E), 0);
  assert.equal(await alertas(E, 'Resolvido'), 1);
  assert.equal(await alertas(F), 1);
  // Mudar o estoque mínimo pelo cadastro também atualiza o alerta.
  const pf = (await a.get(`/api/products/${F}`)).product;
  assert.equal((await a.put(`/api/products/${F}`, { ...pf, estoque_minimo: 5 })).status, 200);
  assert.equal(await alertas(F), 0);
  // Produto cadastrado já abaixo do mínimo nasce com alerta.
  const G = await cria('Paralelo G', 3, 5);
  assert.equal(await alertas(G), 1);
  // Alerta defasado (saldo mudado direto no banco) é corrigido pela sincronização completa da subida do servidor.
  await db.query('UPDATE produto SET quantidade_estoque = 0 WHERE id_produto = ?', [A]);
  await db.query("UPDATE alerta_estoque SET status_alerta = 'Resolvido' WHERE id_produto = ?", [G]);
  await db.sincronizarTodosAlertas();
  assert.equal(await alertas(A), 1);
  assert.equal(await alertas(G), 1);
  assert.equal(await alertas(B), 0);
});

test('Fase 2 item 4: valores acima do limite das colunas respondem 400, não 500', async () => {
  const a = await admin();
  const p = (await a.get('/api/products/1')).product;
  const [forn] = await db.listFornecedores();
  const vendaOk = (await a.post('/api/sales', { forma_pagamento: 'Dinheiro', valor_recebido: 100, itens: [{ id_produto: 1, quantidade: 1 }] })).sale;
  const p1 = (await a.get('/api/products/1')).product;
  const casos = {
    valor_recebido_venda: await a.post('/api/sales', { forma_pagamento: 'Dinheiro', valor_recebido: 1e12, itens: [{ id_produto: 1, quantidade: 1 }] }),
    valor_recebido_edicao: await a.put(`/api/sales/${vendaOk.id_venda}`, { valor_recebido: 1e12, itens: [{ id_produto: 1, quantidade: 1 }] }),
    preco_custo: await a.put('/api/products/1', { ...p, preco_custo: 1e12 }),
    preco_max: await a.put('/api/products/1', { ...p, preco_max: 1e12 }),
    estoque_minimo: await a.put('/api/products/1', { ...p, estoque_minimo: 1e13 }),
    quantidade_fisica: await a.post('/api/inventory', { observacao: 'Conferência com valor enorme', itens: [{ id_produto: 1, quantidade_fisica: 1e13 }] }),
    valor_unitario: await a.post('/api/requisitions', { fornecedor: forn, id_produto: 1, quantidade_pedida: 1, valor_unitario: 1e12 }),
    total_requisicao: await a.post('/api/requisitions', { fornecedor: forn, id_produto: 1, quantidade_pedida: 999999, valor_unitario: 99999999 }),
    saldo_entrada: await a.post('/api/movements', { tipo_movimentacao: 'Entrada', observacao: 'Entrada que estoura o saldo', id_produto: 1, quantidade: 999999999 })
  };
  for (const [campo, r] of Object.entries(casos)) {
    assert.equal(r.status, 400, `${campo}: ${r.status} ${r.error}`);
    assert.match(r.error, /grandes? demais/, campo);
  }
  assert.equal((await a.get('/api/products/1')).product.preco_custo, p.preco_custo);
  assert.equal(await saldo(1), p1.quantidade_estoque);
  assert.equal((await a.get(`/api/sales/${vendaOk.id_venda}`)).sale.valor_recebido, 100);
});

test('Fase 2 item 5: conferência só deixa de ajustar com o booleano false; texto é recusado', async () => {
  const a = await admin();
  const s = await saldo(12);
  const conf = ajustar => a.post('/api/inventory', { observacao: 'Conferência sem ajuste de estoque', ajustar, itens: [{ id_produto: 12, quantidade_fisica: s - 7, quantidade_sistema: s }] });
  for (const v of ['false', 0, 'true', null]) {
    const r = await conf(v);
    assert.equal(r.status, 400, `ajustar=${JSON.stringify(v)}`);
    assert.equal(await saldo(12), s);
  }
  const r = await conf(false);
  assert.equal(r.status, 201);
  assert.equal(r.conferencia.ajustou_estoque, false);
  assert.equal(await saldo(12), s);
});

test('Fase 2 item 6: trocar a própria senha por PUT /api/users/:id encerra as outras sessões e mantém a atual', async () => {
  const a = await admin();
  const outra = await admin();
  const eu = (await a.get('/api/auth/me')).user.id_usuario;
  const r = await a.put(`/api/users/${eu}`, { senha: 'admin123' });
  assert.equal(r.status, 200, r.error);
  assert.equal((await a.get('/api/auth/me')).status, 200);
  assert.equal((await outra.get('/api/auth/me')).status, 401);
  // Senha de outro funcionário continua derrubando todas as sessões dele.
  const f = await func();
  const idf = (await f.get('/api/auth/me')).user.id_usuario;
  assert.equal((await a.put(`/api/users/${idf}`, { senha: 'func123' })).status, 200);
  assert.equal((await f.get('/api/auth/me')).status, 401);
});
