// cenarios.dart - Sequência de requisições do teste de contrato (Node x Dart).
//
// Cobre todas as rotas, os três perfis e os casos válidos e inválidos. A ordem importa:
// os passos compartilham o banco (ids, saldos) e as sessões dos clientes.
import 'executor.dart';

const _png = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';
const _obs = 'Observação válida para o teste de contrato';
const _admin = {'email': 'proprietario@padarianovayork.com', 'senha': 'admin123'};
const _back = {'email': 'backoffice@padarianovayork.com', 'senha': 'backoffice123'};
const _func = {'email': 'henry@padarianovayork.com', 'senha': 'func123'};
const _produto = {
  'nome_produto': 'Broa de Contrato',
  'descricao': 'Broa de milho usada no teste de contrato',
  'id_categoria': 1,
  'unidade': 'UN',
  'preco_custo': 1.25,
  'preco_venda': 4.5,
  'preco_min': 3,
  'preco_max': 6,
  'estoque_minimo': 5,
  'quantidade_estoque': 40,
  'lote': 'LT-CONTRATO',
  'peso': '80g',
};

Map<String, Object?> _item(Object id, Object qtd, [Object? preco]) => {'id_produto': id, 'quantidade': qtd, 'valor_unitario': ?preco};

List<Passo> cenarios() {
  final l = <Passo>[];
  void get(String nome, String alvo, {String? c, Map<String, String> h = const {}, bool bearer = false, Map<String, String> salvar = const {}}) =>
      l.add(Passo(nome, 'GET', alvo, cliente: c, cabecalhos: h, bearer: bearer, salvar: salvar));
  void req(String nome, String metodo, String alvo, Object? corpo,
          {String? c, Map<String, String> h = const {}, bool bearer = false, Map<String, String> salvar = const {}}) =>
      l.add(Passo(nome, metodo, alvo, cliente: c, corpo: corpo, cabecalhos: h, bearer: bearer, salvar: salvar));
  void post(String nome, String alvo, Object? corpo, {String? c, Map<String, String> h = const {}, bool bearer = false, Map<String, String> salvar = const {}}) =>
      req(nome, 'POST', alvo, corpo, c: c, h: h, bearer: bearer, salvar: salvar);
  void bruto(String nome, String metodo, String alvo, String corpo, {String? c}) =>
      l.add(Passo(nome, metodo, alvo, cliente: c, bruto: corpo, cabecalhos: const {'Content-Type': 'application/json'}));

  // ================================================================ autenticação
  get('me sem sessão', '/api/auth/me');
  bruto('login com JSON inválido', 'POST', '/api/auth/login', '{"email": ');
  bruto('login com corpo null', 'POST', '/api/auth/login', 'null');
  bruto('login com corpo lista', 'POST', '/api/auth/login', '[1,2]');
  bruto('login com corpo texto', 'POST', '/api/auth/login', '"x"');
  bruto('login com corpo número', 'POST', '/api/auth/login', '1');
  bruto('login com corpo vazio', 'POST', '/api/auth/login', '');
  bruto('login com espaço no corpo', 'POST', '/api/auth/login', ' ');
  post('login sem e-mail', '/api/auth/login', {'senha': 'x'});
  post('login sem senha', '/api/auth/login', {'email': 'a@b.com'});
  post('login senha zero', '/api/auth/login', {'email': 'a@b.com', 'senha': 0});
  post('login e-mail inexistente', '/api/auth/login', {'email': 'nao@existe.com', 'senha': 'x'});
  post('login senha errada', '/api/auth/login', {'email': 'proprietario@padarianovayork.com', 'senha': 'errada'});
  post('login senha numérica', '/api/auth/login', {'email': 'proprietario@padarianovayork.com', 'senha': 123});
  post('login e-mail objeto', '/api/auth/login', {
    'email': {'a': 1},
    'senha': 'x',
  });
  post('login e-mail com maiúsculas e espaços', '/api/auth/login', {'email': '  PROPRIETARIO@padarianovayork.com ', 'senha': 'admin123'}, c: 'admin2');
  post('login admin', '/api/auth/login', _admin, c: 'admin');
  post('login backoffice', '/api/auth/login', _back, c: 'back');
  post('login funcionário', '/api/auth/login', _func, c: 'func');
  post('login lembrar=true', '/api/auth/login', {..._func, 'lembrar': true}, c: 'func2');
  post('login lembrar="false" (texto conta como verdadeiro)', '/api/auth/login', {..._func, 'lembrar': 'false'}, c: 'func3');
  post('login pelo app (X-Client)', '/api/auth/login', _back, c: 'app', h: const {'X-Client': 'app'});
  post('login pelo app (X-Client em maiúsculas)', '/api/auth/login', _func, c: 'app2', h: const {'X-Client': 'APP'});
  get('me admin (cookie)', '/api/auth/me', c: 'admin');
  get('me funcionário', '/api/auth/me', c: 'func');
  get('me app (Bearer)', '/api/auth/me', c: 'app', bearer: true);
  get('me com bearer em minúsculas', '/api/auth/me', h: const {'Authorization': 'bearer token-que-nao-existe'});
  get('me com bearer inválido', '/api/auth/me', h: const {'Authorization': 'Bearer abc'});
  get('me com bearer mal formado', '/api/auth/me', h: const {'Authorization': 'Bearer a b'});
  get('me com cookie inválido', '/api/auth/me', h: const {'Cookie': 'gf_session=xyz; outro=%E0%A4%A'});
  post('logout sem sessão', '/api/auth/logout', <String, Object?>{});
  post('logout admin2', '/api/auth/logout', <String, Object?>{}, c: 'admin2');
  get('me admin2 depois do logout', '/api/auth/me', c: 'admin2');
  post('logout app (Bearer)', '/api/auth/logout', <String, Object?>{}, c: 'app2', bearer: true);
  get('me app2 depois do logout', '/api/auth/me', c: 'app2', bearer: true);

  // bloqueio após 5 falhas (relógio parado: o tempo restante é o mesmo nos dois)
  for (var i = 1; i <= 5; i++) {
    post('falha de login $i', '/api/auth/login', {'email': 'backoffice@padarianovayork.com', 'senha': 'errada$i'});
  }
  post('login bloqueado (429)', '/api/auth/login', _back);
  post('login de outro e-mail não é bloqueado', '/api/auth/login', _admin, c: 'admin3');

  // recuperação de senha
  post('forgot e-mail desconhecido', '/api/auth/forgot', {'email': 'ninguem@x.com'});
  post('forgot sem e-mail', '/api/auth/forgot', <String, Object?>{});
  post('forgot e-mail objeto', '/api/auth/forgot', {
    'email': ['henry@padarianovayork.com'],
  });
  l.add(const Passo('código escrito no console', 'GET', '', acao: 'codigo', salvar: {'codigo': ''}));
  post('reset com token inválido', '/api/auth/reset', {'token': 'invalido', 'senha': 'novasenha1'});
  post('reset sem token', '/api/auth/reset', {'senha': 'novasenha1'});
  post('reset com senha curta', '/api/auth/reset', {'token': r'${codigo}', 'senha': '123'});
  post('reset válido', '/api/auth/reset', {'token': r'${codigo}', 'senha': 'func123'});
  post('reset reutilizado', '/api/auth/reset', {'token': r'${codigo}', 'senha': 'func123'});
  get('sessão do funcionário caiu com o reset', '/api/auth/me', c: 'func');
  post('login funcionário de novo', '/api/auth/login', _func, c: 'func');

  // troca de senha
  post('change-password sem sessão', '/api/auth/change-password', {'senha_atual': 'x', 'nova_senha': 'yyyyyy'});
  post('change-password senha atual errada', '/api/auth/change-password', {'senha_atual': 'x', 'nova_senha': 'yyyyyy'}, c: 'admin');
  post('change-password nova curta', '/api/auth/change-password', {'senha_atual': 'admin123', 'nova_senha': 'y'}, c: 'admin');
  post('change-password nova longa', '/api/auth/change-password', {'senha_atual': 'admin123', 'nova_senha': 'y' * 101}, c: 'admin');
  post('change-password válido', '/api/auth/change-password', {'senha_atual': 'admin123', 'nova_senha': 'admin123'}, c: 'admin');
  get('a sessão atual continua', '/api/auth/me', c: 'admin');
  get('a outra sessão do admin caiu', '/api/auth/me', c: 'admin3');

  // ================================================================ rotas e roteador
  get('rota inexistente', '/api/nada');
  get('rota inexistente com sessão', '/api/nada', c: 'admin');
  req('método não permitido', 'PATCH', '/api/products', <String, Object?>{}, c: 'admin');
  req('método não permitido sem sessão', 'DELETE', '/api/categories', <String, Object?>{});
  get('barra no fim da rota', '/api/categories/', c: 'admin');
  get('rota com maiúsculas não existe', '/api/Categories', c: 'admin');
  get('OPTIONS sem origem permitida', '/api/products', h: const {'Origin': 'http://malicioso.test'});
  l.add(const Passo('preflight CORS', 'OPTIONS', '/api/products', cabecalhos: {'Origin': 'http://app.test', 'Access-Control-Request-Method': 'GET'}));
  l.add(const Passo('OPTIONS sem CORS cai no 405', 'OPTIONS', '/api/products'));
  get('CORS numa resposta comum', '/api/auth/me', h: const {'Origin': 'http://app.test'});
  get('CORS com origem de fora', '/api/auth/me', h: const {'Origin': 'http://malicioso.test'});
  get('CORS em erro 404', '/api/xyz', h: const {'Origin': 'http://app.test'});
  get('perm negada antes do corpo', '/api/users', c: 'func');
  bruto('JSON inválido com sessão', 'POST', '/api/movements', '{x', c: 'func');
  bruto('JSON inválido sem sessão (401 vem antes)', 'POST', '/api/movements', '{x');
  bruto('JSON inválido sem permissão (403 vem antes)', 'POST', '/api/users', '{x', c: 'func');
  bruto('UTF-8 inválido no corpo', 'POST', '/api/movements', '{"tipo_movimentacao":"Entrada","observacao":"\xff\xfe inválido aqui","id_produto":5,"quantidade":1}', c: 'func');

  // ================================================================ busca global
  get('busca sem termo', '/api/search', c: 'admin');
  get('busca de 1 letra', '/api/search?q=p', c: 'admin');
  get('busca sem acento acha Pão', '/api/search?q=pao', c: 'admin');
  get('busca requisição', '/api/search?q=REQ-9661', c: 'admin');
  get('busca venda', '/api/search?q=VENDA-100', c: 'admin');
  get('busca usuário', '/api/search?q=henry', c: 'admin');
  get('busca com curinga escapado', '/api/search?q=%25%25', c: 'admin');
  get('busca com sublinhado', '/api/search?q=__', c: 'admin');
  get('busca com + vira espaço', '/api/search?q=p%C3%A3o+de', c: 'admin');
  get('busca repetida (vale a última)', '/api/search?q=xx&q=pao', c: 'admin');
  get('busca do funcionário não vê usuários', '/api/search?q=henry', c: 'func');
  get('busca do backoffice', '/api/search?q=caf', c: 'back');
  get('busca sem sessão', '/api/search?q=pao');

  // ================================================================ dados de apoio
  get('dashboard admin', '/api/dashboard', c: 'admin');
  get('dashboard funcionário', '/api/dashboard', c: 'func');
  get('alertas', '/api/alerts', c: 'back');
  get('categorias', '/api/categories', c: 'func');
  get('fornecedores', '/api/suppliers', c: 'func');
  get('perfis (admin)', '/api/profiles', c: 'admin');
  get('perfis (backoffice: 403)', '/api/profiles', c: 'back');
  get('configurações', '/api/settings', c: 'func');
  req('configurações: funcionário não altera', 'PUT', '/api/settings', {'estabelecimento': 'Outro nome'}, c: 'func');
  req('configurações: nome curto', 'PUT', '/api/settings', {'estabelecimento': 'ab'}, c: 'admin');
  req('configurações: nome null', 'PUT', '/api/settings', {'estabelecimento': null}, c: 'admin');
  req('configurações: desconto 101', 'PUT', '/api/settings', {'descontoMaximoPercent': 101}, c: 'admin');
  req('configurações: desconto texto', 'PUT', '/api/settings', {'descontoMaximoPercent': 'abc'}, c: 'admin');
  req('configurações: intervalo 1', 'PUT', '/api/settings', {'intervaloAtualizacaoSeg': 1}, c: 'admin');
  req('configurações: dias 2.5', 'PUT', '/api/settings', {'diasAlertaValidade': 2.5}, c: 'admin');
  req('configurações: simulação "false"', 'PUT', '/api/settings', {'simularCartaoNegado': 'false'}, c: 'admin');
  req('configurações: simulação 1', 'PUT', '/api/settings', {'simularFornecedorIndisponivel': 1}, c: 'admin');
  req('configurações: tudo válido com frações', 'PUT', '/api/settings', {
    'estabelecimento': '  Padaria Nova York - Contrato  ',
    'descontoMaximoPercent': 33.335,
    'intervaloAtualizacaoSeg': 2.5,
    'diasAlertaValidade': '4',
  }, c: 'admin');
  get('configurações depois (frações arredondadas pelo banco)', '/api/settings', c: 'admin');
  req('configurações: volta o padrão', 'PUT', '/api/settings', {'descontoMaximoPercent': 20, 'intervaloAtualizacaoSeg': 3, 'diasAlertaValidade': 3}, c: 'admin');
  req('configurações: corpo vazio', 'PUT', '/api/settings', <String, Object?>{}, c: 'admin');

  // ================================================================ funcionários
  get('usuários (admin)', '/api/users', c: 'admin');
  get('usuários (backoffice: 403)', '/api/users', c: 'back');
  get('usuários por perfil', '/api/users?id_perfil=3', c: 'admin');
  get('usuários por perfil inválido', '/api/users?id_perfil=abc', c: 'admin');
  get('usuários por situação', '/api/users?status=Ativo&q=padaria', c: 'admin');
  post('cria usuário', '/api/users', {'nome': ' Maria Silva ', 'email': ' Maria@Padaria.com ', 'senha': 'senha123', 'id_perfil': '3', 'cargo': 'C' * 120},
      c: 'admin', salvar: const {'maria': 'user.id_usuario'});
  post('cria usuário duplicado', '/api/users', {'nome': 'Outra', 'email': 'MARIA@padaria.com', 'senha': 'senha123', 'id_perfil': 3}, c: 'admin');
  post('cria usuário nome curto', '/api/users', {'nome': 'M', 'email': 'm@x.com', 'senha': 'senha123', 'id_perfil': 3}, c: 'admin');
  post('cria usuário e-mail inválido', '/api/users', {'nome': 'Mario', 'email': 'mario@x', 'senha': 'senha123', 'id_perfil': 3}, c: 'admin');
  post('cria usuário senha curta', '/api/users', {'nome': 'Mario', 'email': 'mario@x.com', 'senha': '123', 'id_perfil': 3}, c: 'admin');
  post('cria usuário perfil inválido', '/api/users', {'nome': 'Mario', 'email': 'mario@x.com', 'senha': 'senha123', 'id_perfil': 9}, c: 'admin');
  post('cria usuário perfil fracionado', '/api/users', {'nome': 'Mario', 'email': 'mario@x.com', 'senha': 'senha123', 'id_perfil': 1.5}, c: 'admin');
  post('cria usuário sem nada', '/api/users', <String, Object?>{}, c: 'admin');
  req('altera cargo', 'PUT', r'/api/users/${maria}', {'cargo': 'Padeira'}, c: 'admin');
  req('altera perfil', 'PUT', r'/api/users/${maria}', {'id_perfil': 2}, c: 'admin');
  req('altera e-mail para um em uso', 'PUT', r'/api/users/${maria}', {'email': 'henry@padarianovayork.com'}, c: 'admin');
  req('altera e-mail inválido', 'PUT', r'/api/users/${maria}', {'email': 'x'}, c: 'admin');
  req('altera nome vazio', 'PUT', r'/api/users/${maria}', {'nome': ''}, c: 'admin');
  req('altera senha curta', 'PUT', r'/api/users/${maria}', {'senha': '1'}, c: 'admin');
  req('altera usuário inexistente', 'PUT', '/api/users/999', {'cargo': 'x'}, c: 'admin');
  req('altera usuário com id texto', 'PUT', '/api/users/abc', {'cargo': 'x'}, c: 'admin');
  req('tira o perfil do único admin', 'PUT', '/api/users/1', {'id_perfil': 2}, c: 'admin');
  post('login da Maria', '/api/auth/login', {'email': 'maria@padaria.com', 'senha': 'senha123'}, c: 'maria');
  req('troca a senha da Maria (derruba as sessões dela)', 'PUT', r'/api/users/${maria}', {'senha': 'senha456'}, c: 'admin');
  get('sessão da Maria caiu', '/api/auth/me', c: 'maria');
  post('login da Maria com a nova senha', '/api/auth/login', {'email': 'maria@padaria.com', 'senha': 'senha456'}, c: 'maria');
  req('situação inválida', 'PATCH', r'/api/users/${maria}/status', {'status': 'Bloqueado'}, c: 'admin');
  req('admin não desativa a si mesmo', 'PATCH', '/api/users/1/status', {'status': 'Inativo'}, c: 'admin');
  req('desativa a Maria', 'PATCH', r'/api/users/${maria}/status', {'status': 'Inativo'}, c: 'admin');
  get('sessão da Maria caiu (inativa)', '/api/products', c: 'maria');
  post('Maria inativa não entra', '/api/auth/login', {'email': 'maria@padaria.com', 'senha': 'senha456'}, c: 'maria');
  req('reativa a Maria', 'PATCH', r'/api/users/${maria}/status', {'status': 'Ativo'}, c: 'admin');
  req('situação de usuário inexistente', 'PATCH', '/api/users/999/status', {'status': 'Ativo'}, c: 'admin');
  req('situação sem corpo', 'PATCH', r'/api/users/${maria}/status', <String, Object?>{}, c: 'admin');

  // ================================================================ produtos
  get('produtos ativos', '/api/products', c: 'func');
  get('produtos inativos', '/api/products?status=Inativo', c: 'func');
  get('produtos todos', '/api/products?status=todos', c: 'func');
  get('produtos situação desconhecida', '/api/products?status=xyz', c: 'func');
  get('produtos por categoria', '/api/products?category=2', c: 'func');
  get('produtos por categoria inválida', '/api/products?category=abc', c: 'func');
  get('produtos busca', '/api/products?q=p%C3%A3o', c: 'func');
  get('produto 1', '/api/products/1', c: 'func');
  get('produto inexistente', '/api/products/999', c: 'func');
  get('produto id texto', '/api/products/abc', c: 'func');
  get('produto id fracionado', '/api/products/1.5', c: 'func');
  get('produto id hexadecimal', '/api/products/0x2', c: 'func');
  get('produto id com espaço', '/api/products/%201', c: 'func');
  get('produto id 1e0', '/api/products/1e0', c: 'func');
  post('funcionário não cadastra produto', '/api/products', _produto, c: 'func');
  post('cadastra produto', '/api/products', _produto, c: 'back', salvar: const {'prod': 'product.id_produto'});
  post('cadastra produto sem código, sem lote, sem custo', '/api/products', {
    ..._produto,
    'nome_produto': 'Sem Código',
    'lote': '',
    'preco_custo': '',
    'preco_min': '',
    'preco_max': '',
    'estoque_minimo': '',
    'quantidade_estoque': '',
  }, c: 'admin', salvar: const {'prod2': 'product.id_produto'});
  post('cadastra produto em KG com fração', '/api/products', {
    ..._produto,
    'nome_produto': 'Granel Contrato',
    'unidade': 'kg',
    'quantidade_estoque': 12.3456,
    'estoque_minimo': 0.5,
    'codigo_barras': ' 99887766 ',
    'validade': '2030-01-31',
  }, c: 'admin', salvar: const {'prodkg': 'product.id_produto'});
  post('cadastra produto com imagem', '/api/products', {..._produto, 'nome_produto': 'Com Imagem', 'imagem_data': _png}, c: 'admin', salvar: const {'prodimg': 'product.id_produto', 'imagem': 'product.imagem'});
  get('imagem enviada', r'/${imagem}');
  get('imagem enviada com CORS', r'/${imagem}', h: const {'Origin': 'http://app.test'});
  post('imagem com tipo inválido', '/api/products', {..._produto, 'imagem_data': 'data:text/html;base64,AAAA'}, c: 'admin');
  post('imagem em lista vira texto', '/api/products', {
    ..._produto,
    'nome_produto': 'Imagem em Lista',
    'imagem_data': [_png],
  }, c: 'admin');
  post('imagem com base64 estranho', '/api/products', {..._produto, 'nome_produto': 'Base64 Estranho', 'imagem_data': 'data:image/gif;base64,R0lG=ODlh'}, c: 'admin');
  post('imagem grande demais', '/api/products', {..._produto, 'imagem_data': 'data:image/png;base64,${'A' * 2900000}'}, c: 'admin');
  post('id e caminho da imagem vindos do cliente são ignorados', '/api/products', {..._produto, 'nome_produto': 'Tentou Editar', 'id_produto': 1, 'imagem': '../../segredo'}, c: 'admin');
  for (final (nome, extra) in <(String, Map<String, Object?>)>[
    ('preço de venda zero', {'preco_venda': 0}),
    ('preço de venda texto', {'preco_venda': 'abc'}),
    ('preço de venda enorme', {'preco_venda': 1e9}),
    ('preço de custo negativo', {'preco_custo': -1}),
    ('preço de custo enorme', {'preco_custo': 1e9}),
    ('mínimo acima da venda', {'preco_min': 5}),
    ('máximo abaixo da venda', {'preco_max': 4}),
    ('máximo zero', {'preco_max': 0}),
    ('mínimo e máximo enormes', {'preco_min': 1, 'preco_max': 1e9}),
    ('estoque mínimo negativo', {'estoque_minimo': -1}),
    ('estoque mínimo fracionado em UN', {'estoque_minimo': 2.5}),
    ('estoque mínimo enorme', {'estoque_minimo': 1e10}),
    ('estoque negativo', {'quantidade_estoque': -1}),
    ('estoque fracionado em UN', {'quantidade_estoque': 1.5}),
    ('estoque enorme', {'quantidade_estoque': 1e10}),
    ('categoria inválida', {'id_categoria': 99}),
    ('categoria texto', {'id_categoria': 'x'}),
    ('descrição curta', {'descricao': 'curta'}),
    ('descrição longa', {'descricao': 'x' * 5001}),
    ('validade impossível', {'validade': '2030-02-31'}),
    ('validade em formato errado', {'validade': '31/01/2030'}),
    ('validade com ano 0099', {'validade': '0099-01-01'}),
    ('código já usado', {'codigo_barras': '78910001'}),
    ('nome curto', {'nome_produto': 'X'}),
    ('nome ausente', {'nome_produto': null}),
    ('unidade com espaço vira UN', {'unidade': '  ', 'quantidade_estoque': 2.5}),
  ]) {
    post('produto inválido: $nome', '/api/products', {..._produto, ...extra}, c: 'admin');
  }
  req('altera produto', 'PUT', r'/api/products/${prod}', {..._produto, 'nome_produto': 'Broa Alterada', 'preco_venda': 5, 'quantidade_estoque': 999, 'lote': ''}, c: 'back');
  req('altera produto trocando o código', 'PUT', r'/api/products/${prod}', {..._produto, 'codigo_barras': '55555'}, c: 'back');
  req('altera produto inexistente', 'PUT', '/api/products/999', _produto, c: 'back');
  req('altera produto com id texto', 'PUT', '/api/products/abc', _produto, c: 'back');
  req('altera produto com imagem', 'PUT', r'/api/products/${prod}', {..._produto, 'imagem_data': _png}, c: 'back');
  req('inativa produto', 'DELETE', r'/api/products/${prod2}', <String, Object?>{}, c: 'back');
  req('inativa de novo', 'DELETE', r'/api/products/${prod2}', <String, Object?>{}, c: 'back');
  req('inativa produto inexistente', 'DELETE', '/api/products/999', <String, Object?>{}, c: 'back');
  req('reativa produto', 'PATCH', r'/api/products/${prod2}/status', {'status': 'Ativo'}, c: 'back');
  req('reativa de novo', 'PATCH', r'/api/products/${prod2}/status', {'status': 'Ativo'}, c: 'back');
  req('situação de produto inválida', 'PATCH', r'/api/products/${prod2}/status', {'status': 'x'}, c: 'back');
  req('situação: funcionário não altera', 'PATCH', r'/api/products/${prod2}/status', {'status': 'Inativo'}, c: 'func');
  get('produtos depois dos cadastros', '/api/products?status=todos', c: 'admin');
  get('validade (padrão 3 dias)', '/api/expiring', c: 'func');

  // ================================================================ movimentações
  get('movimentações', '/api/movements', c: 'func');
  get('movimentações de entrada', '/api/movements?tipo=Entrada', c: 'func');
  get('movimentações com período', '/api/movements?from=2000-01-01&to=2099-12-31', c: 'func');
  get('movimentações data inválida', '/api/movements?from=abc', c: 'func');
  get('movimentações mês 13', '/api/movements?to=2030-13-01', c: 'func');
  get('movimentações período invertido', '/api/movements?from=2030-01-02&to=2030-01-01', c: 'func');
  post('entrada individual', '/api/movements', {'tipo_movimentacao': 'Entrada', 'observacao': _obs, 'id_produto': 5, 'quantidade': '10'}, c: 'func');
  post('entrada em lote com produto repetido', '/api/movements', {
    'tipo_movimentacao': 'Entrada',
    'observacao': _obs,
    'itens': [_item(5, 1), _item(6, 2), _item(5, 3), _item(4, 0.25)],
  }, c: 'func');
  post('saída maior que o saldo (lote desfeito)', '/api/movements', {
    'tipo_movimentacao': 'Saída',
    'observacao': _obs,
    'itens': [_item(5, 1), _item(6, 99999)],
  }, c: 'func');
  post('saída válida', '/api/movements', {
    'tipo_movimentacao': 'Saída',
    'observacao': _obs,
    'itens': [_item(4, 1.5)],
  }, c: 'func');
  post('movimentação tipo inválido', '/api/movements', {'tipo_movimentacao': 'Ajuste', 'observacao': _obs, 'id_produto': 5, 'quantidade': 1}, c: 'func');
  post('movimentação sem observação', '/api/movements', {'tipo_movimentacao': 'Entrada', 'id_produto': 5, 'quantidade': 1}, c: 'func');
  post('movimentação observação curta', '/api/movements', {'tipo_movimentacao': 'Entrada', 'observacao': 'curto', 'id_produto': 5, 'quantidade': 1}, c: 'func');
  post('movimentação quantidade 0.0001', '/api/movements', {'tipo_movimentacao': 'Entrada', 'observacao': _obs, 'id_produto': 4, 'quantidade': 0.0001}, c: 'func');
  post('movimentação fracionada em UN', '/api/movements', {'tipo_movimentacao': 'Entrada', 'observacao': _obs, 'id_produto': 5, 'quantidade': 1.5}, c: 'func');
  post('movimentação enorme', '/api/movements', {'tipo_movimentacao': 'Entrada', 'observacao': _obs, 'id_produto': 5, 'quantidade': 1e10}, c: 'func');
  post('movimentação estoura o saldo', '/api/movements', {'tipo_movimentacao': 'Entrada', 'observacao': _obs, 'id_produto': 5, 'quantidade': 999999999}, c: 'func');
  post('movimentação produto inexistente', '/api/movements', {'tipo_movimentacao': 'Entrada', 'observacao': _obs, 'id_produto': 999, 'quantidade': 1}, c: 'func');
  post('movimentação sem produto', '/api/movements', {'tipo_movimentacao': 'Entrada', 'observacao': _obs}, c: 'func');
  post('movimentação itens vazios', '/api/movements', {'tipo_movimentacao': 'Entrada', 'observacao': _obs, 'itens': []}, c: 'func');
  post('movimentação itens nulos', '/api/movements', {
    'tipo_movimentacao': 'Entrada',
    'observacao': _obs,
    'itens': [null],
  }, c: 'func');
  post('movimentação itens lista', '/api/movements', {
    'tipo_movimentacao': 'Entrada',
    'observacao': _obs,
    'itens': [
      [5, 1],
    ],
  }, c: 'func');

  // ================================================================ perdas
  post('perda vencido', '/api/losses', {
    'motivo_perda': 'Vencido',
    'itens': [_item(11, 5)],
  }, c: 'admin');
  post('perda em lote', '/api/losses', {
    'motivo_perda': 'Quebra/Avaria',
    'observacao': 'Caixa caiu no chão do estoque',
    'itens': [_item(9, 1), _item(4, 0.5)],
  }, c: 'func');
  post('perda motivo inválido', '/api/losses', {
    'motivo_perda': 'Roubo',
    'itens': [_item(11, 1)],
  }, c: 'admin');
  post('perda "Outro" sem observação', '/api/losses', {
    'motivo_perda': 'Outro',
    'itens': [_item(11, 1)],
  }, c: 'admin');
  post('perda "Outro" com observação', '/api/losses', {
    'motivo_perda': 'Outro',
    'observacao': 'Cliente devolveu produto aberto',
    'itens': [_item(11, 1)],
  }, c: 'admin');
  post('perda maior que o saldo', '/api/losses', {
    'motivo_perda': 'Sobra do dia',
    'itens': [_item(11, 99999)],
  }, c: 'admin');
  post('perda itens inválidos', '/api/losses', {
    'motivo_perda': 'Vencido',
    'itens': [7],
  }, c: 'admin');
  post('perda: backoffice também registra', '/api/losses', {
    'motivo_perda': 'Sobra do dia',
    'itens': [_item(4, 1)],
  }, c: 'back');

  // ================================================================ requisições
  get('requisições', '/api/requisitions', c: 'func');
  get('requisição 1', '/api/requisitions/1', c: 'func');
  get('requisição inexistente', '/api/requisitions/999', c: 'func');
  post('requisição válida', '/api/requisitions', {'id_produto': 6, 'quantidade_pedida': 10, 'fornecedor': 'Moinho Paulista de Trigo', 'valor_unitario': 4.1, 'observacao': _obs},
      c: 'func', salvar: const {'req': 'requisicao.id_requisicao'});
  post('requisição de item não cadastrado', '/api/requisitions', {
    'produto_nome': '  Copos 300ml  ',
    'unidade': 'Pacote',
    'quantidade_pedida': '5',
    'fornecedor': 'Distribuidora de Embalagens São Caetano',
    'valor_unitario': '',
    'endereco_entrega': 'Depósito dos fundos',
  }, c: 'func', salvar: const {'req2': 'requisicao.id_requisicao'});
  post('requisição sem valor usa o custo', '/api/requisitions', {'id_produto': 7, 'quantidade_pedida': 2.5, 'fornecedor': 'Laticínios ABC'}, c: 'back', salvar: const {'req3': 'requisicao.id_requisicao'});
  post('requisição fornecedor inventado', '/api/requisitions', {'id_produto': 6, 'quantidade_pedida': 10, 'fornecedor': 'Inventado'}, c: 'func');
  post('requisição sem fornecedor', '/api/requisitions', {'id_produto': 6, 'quantidade_pedida': 10}, c: 'func');
  post('requisição produto inexistente', '/api/requisitions', {'id_produto': 999, 'quantidade_pedida': 1, 'fornecedor': 'Laticínios ABC'}, c: 'func');
  post('requisição sem nome de produto', '/api/requisitions', {'quantidade_pedida': 1, 'fornecedor': 'Laticínios ABC'}, c: 'func');
  post('requisição quantidade zero', '/api/requisitions', {'id_produto': 6, 'quantidade_pedida': 0, 'fornecedor': 'Laticínios ABC'}, c: 'func');
  post('requisição quantidade fracionada em pacote', '/api/requisitions', {'id_produto': 6, 'quantidade_pedida': 1.5, 'fornecedor': 'Laticínios ABC'}, c: 'func');
  post('requisição quantidade enorme', '/api/requisitions', {'id_produto': 6, 'quantidade_pedida': 1e10, 'fornecedor': 'Laticínios ABC'}, c: 'func');
  post('requisição preço negativo', '/api/requisitions', {'id_produto': 6, 'quantidade_pedida': 1, 'fornecedor': 'Laticínios ABC', 'valor_unitario': -1}, c: 'func');
  post('requisição preço null vira zero', '/api/requisitions', {'id_produto': 6, 'quantidade_pedida': 1, 'fornecedor': 'Laticínios ABC', 'valor_unitario': null}, c: 'func');
  post('requisição total enorme', '/api/requisitions', {'id_produto': 6, 'quantidade_pedida': 999999, 'fornecedor': 'Laticínios ABC', 'valor_unitario': 99999999}, c: 'func');
  post('requisição previsão no passado', '/api/requisitions', {'id_produto': 6, 'quantidade_pedida': 1, 'fornecedor': 'Laticínios ABC', 'previsao_entrega': '2001-01-01'}, c: 'func');
  post('requisição previsão impossível', '/api/requisitions', {'id_produto': 6, 'quantidade_pedida': 1, 'fornecedor': 'Laticínios ABC', 'previsao_entrega': '2030-02-31'}, c: 'func');
  post('requisição observação curta', '/api/requisitions', {'id_produto': 6, 'quantidade_pedida': 1, 'fornecedor': 'Laticínios ABC', 'observacao': 'curta'}, c: 'func');
  req('funcionário não cota', 'PATCH', r'/api/requisitions/${req}/status', {'situacao': 'Cotado'}, c: 'func');
  req('funcionário: situação inválida (403 antes)', 'PATCH', r'/api/requisitions/${req}/status', {'situacao': 'xyz'}, c: 'func');
  req('admin: situação inválida', 'PATCH', r'/api/requisitions/${req}/status', {'situacao': 'xyz'}, c: 'admin');
  req('cota', 'PATCH', r'/api/requisitions/${req}/status', {'situacao': 'Cotado'}, c: 'back');
  req('cota de novo', 'PATCH', r'/api/requisitions/${req}/status', {'situacao': 'Cotado'}, c: 'back');
  req('gera AF', 'PATCH', r'/api/requisitions/${req}/status', {'situacao': 'AF Gerada'}, c: 'back');
  req('gera AF de novo', 'PATCH', r'/api/requisitions/${req}/status', {'situacao': 'AF Gerada'}, c: 'back');
  req('recebe parcial', 'PATCH', r'/api/requisitions/${req}/status', {'situacao': 'Finalizado', 'quantidade_recebida': 4}, c: 'func');
  req('recebe acima do saldo', 'PATCH', r'/api/requisitions/${req}/status', {'situacao': 'Finalizado', 'quantidade_recebida': 99}, c: 'func');
  req('recebe fração em pacote', 'PATCH', r'/api/requisitions/${req}/status', {'situacao': 'Finalizado', 'quantidade_recebida': 1.5}, c: 'func');
  req('recebe zero', 'PATCH', r'/api/requisitions/${req}/status', {'situacao': 'Finalizado', 'quantidade_recebida': 0}, c: 'func');
  req('recebe null', 'PATCH', r'/api/requisitions/${req}/status', {'situacao': 'Finalizado', 'quantidade_recebida': null}, c: 'func');
  req('recebe o restante', 'PATCH', r'/api/requisitions/${req}/status', {'situacao': 'Finalizado', 'quantidade_recebida': ''}, c: 'func');
  req('requisição finalizada não muda', 'PATCH', r'/api/requisitions/${req}/status', {'situacao': 'Cancelado', 'justificativa': 'Pedido duplicado no sistema'}, c: 'func');
  req('recebe item não cadastrado (sem estoque)', 'PATCH', r'/api/requisitions/${req2}/status', {'situacao': 'Finalizado'}, c: 'func');
  req('recebe parcial em KG', 'PATCH', r'/api/requisitions/${req3}/status', {'situacao': 'Finalizado', 'quantidade_recebida': 1.25}, c: 'func');
  req('cancela sem justificativa', 'PATCH', r'/api/requisitions/${req3}/status', {'situacao': 'Cancelado'}, c: 'func');
  req('cancela justificativa curta', 'PATCH', r'/api/requisitions/${req3}/status', {'situacao': 'Cancelado', 'justificativa': 'curto'}, c: 'func');
  req('liga o fornecedor fora do ar', 'PUT', '/api/settings', {'simularFornecedorIndisponivel': true}, c: 'admin');
  req('cancela com fornecedor fora do ar (503)', 'PATCH', r'/api/requisitions/${req3}/status', {'situacao': 'Cancelado', 'justificativa': 'Pedido duplicado no sistema'}, c: 'func');
  post('nova requisição com fornecedor fora do ar (503)', '/api/requisitions', {'id_produto': 4, 'fornecedor': 'Laticínios ABC', 'quantidade_pedida': 1}, c: 'admin');
  req('desliga o fornecedor fora do ar', 'PUT', '/api/settings', {'simularFornecedorIndisponivel': false}, c: 'admin');
  req('cancela', 'PATCH', r'/api/requisitions/${req3}/status', {'situacao': 'Cancelado', 'justificativa': 'Pedido duplicado no sistema'}, c: 'func');
  req('situação de requisição inexistente', 'PATCH', '/api/requisitions/999/status', {'situacao': 'Cotado'}, c: 'admin');
  get('requisições depois', '/api/requisitions', c: 'admin');

  // ================================================================ vendas
  get('vendas', '/api/sales', c: 'back');
  get('venda 1', '/api/sales/1', c: 'back');
  get('venda inexistente', '/api/sales/999', c: 'back');
  get('vendas com filtros', '/api/sales?status=Conclu%C3%ADda&q=caf', c: 'back');
  get('vendas data inválida', '/api/sales?to=2030-02-31', c: 'back');
  post('backoffice não vende', '/api/sales', {
    'itens': [_item(8, 1)],
  }, c: 'back');
  post('venda PIX', '/api/sales', {
    'itens': [_item(8, 3)],
    'forma_pagamento': 'PIX',
  }, c: 'func', salvar: const {'v1': 'sale.id_venda'});
  post('venda em dinheiro com troco', '/api/sales', {
    'itens': [_item(8, 2), _item(4, 1.3)],
    'forma_pagamento': 'Dinheiro',
    'valor_recebido': '50',
  }, c: 'func', salvar: const {'v2': 'sale.id_venda'});
  post('venda no cartão (NSU)', '/api/sales', {
    'itens': [_item(10, 1)],
    'forma_pagamento': 'Cartão Débito',
  }, c: 'func', salvar: const {'v3': 'sale.id_venda'});
  post('venda com dois preços do mesmo produto', '/api/sales', {
    'itens': [_item(12, 1, 0.3), _item(12, 1, 0.5), _item(12, 2, '0.3')],
  }, c: 'admin', salvar: const {'v4': 'sale.id_venda', 'item1': 'sale.itens.0.id_item_venda', 'item2': 'sale.itens.1.id_item_venda'});
  post('venda com desconto em valor', '/api/sales', {
    'itens': [_item(8, 1)],
    'desconto': 1.2,
    'desconto_tipo': 'valor',
  }, c: 'func');
  post('venda com desconto percentual', '/api/sales', {
    'itens': [_item(8, 3)],
    'desconto': '10',
    'desconto_tipo': 'percentual',
  }, c: 'func', salvar: const {'v5': 'sale.id_venda'});
  post('desconto acima do limite (funcionário)', '/api/sales', {
    'itens': [_item(8, 10)],
    'desconto': 50,
    'desconto_tipo': 'percentual',
  }, c: 'func');
  post('desconto acima do limite (admin pode)', '/api/sales', {
    'itens': [_item(8, 1)],
    'desconto': 50,
    'desconto_tipo': 'percentual',
  }, c: 'admin');
  post('desconto percentual acima de 100', '/api/sales', {
    'itens': [_item(8, 1)],
    'desconto': 101,
    'desconto_tipo': 'percentual',
  }, c: 'admin');
  post('desconto maior que o subtotal', '/api/sales', {
    'itens': [_item(8, 1)],
    'desconto': 100,
  }, c: 'admin');
  post('desconto negativo', '/api/sales', {
    'itens': [_item(8, 1)],
    'desconto': -1,
  }, c: 'admin');
  post('recebido menor que o total', '/api/sales', {
    'itens': [_item(8, 2)],
    'forma_pagamento': 'Dinheiro',
    'valor_recebido': 1,
  }, c: 'func');
  post('recebido enorme', '/api/sales', {
    'itens': [_item(8, 1)],
    'forma_pagamento': 'Dinheiro',
    'valor_recebido': 1e12,
  }, c: 'func');
  post('recebido no PIX é ignorado', '/api/sales', {
    'itens': [_item(8, 1)],
    'forma_pagamento': 'PIX',
    'valor_recebido': 1,
  }, c: 'func');
  post('forma de pagamento inválida', '/api/sales', {
    'itens': [_item(8, 1)],
    'forma_pagamento': 'Cheque',
  }, c: 'func');
  post('quantidade fracionada em UN', '/api/sales', {
    'itens': [_item(1, 1.3)],
  }, c: 'func');
  post('preço fora da faixa', '/api/sales', {
    'itens': [_item(8, 1, 1)],
  }, c: 'func');
  post('preço texto', '/api/sales', {
    'itens': [_item(8, 1, 'abc')],
  }, c: 'func');
  post('estoque insuficiente', '/api/sales', {
    'itens': [_item(3, 500)],
  }, c: 'func');
  post('produto inexistente', '/api/sales', {
    'itens': [_item(9999, 1)],
  }, c: 'func');
  post('produto inativo', '/api/sales', {
    'itens': [_item(r'${prod2}', 1)],
  }, c: 'func');
  post('sem itens', '/api/sales', {'itens': []}, c: 'func');
  post('itens não é lista', '/api/sales', {'itens': 'x'}, c: 'func');
  post('itens nulos', '/api/sales', {
    'itens': [null],
  }, c: 'func');
  req('liga o cartão negado', 'PUT', '/api/settings', {'simularCartaoNegado': true}, c: 'admin');
  post('cartão negado (402) não grava nada', '/api/sales', {
    'itens': [_item(8, 1)],
    'forma_pagamento': 'Cartão Crédito',
  }, c: 'func');
  post('dinheiro passa com o cartão negado', '/api/sales', {
    'itens': [_item(8, 1)],
  }, c: 'func');
  req('desliga o cartão negado', 'PUT', '/api/settings', {'simularCartaoNegado': false}, c: 'admin');
  req('edita venda (aumenta)', 'PUT', r'/api/sales/${v1}', {
    'itens': [_item(8, 5)],
  }, c: 'func');
  req('edita venda (diminui e troca produto)', 'PUT', r'/api/sales/${v1}', {
    'itens': [_item(8, 1), _item(10, 2)],
  }, c: 'func');
  req('edita venda em dinheiro (troco acompanha)', 'PUT', r'/api/sales/${v2}', {
    'itens': [_item(8, 1)],
  }, c: 'func');
  req('edita venda em dinheiro (recebido não cobre)', 'PUT', r'/api/sales/${v2}', {
    'itens': [_item(8, 20)],
  }, c: 'func');
  req('edita venda em dinheiro com novo recebido', 'PUT', r'/api/sales/${v2}', {
    'itens': [_item(8, 20)],
    'valor_recebido': 200,
  }, c: 'func');
  req('edita venda ambígua', 'PUT', r'/api/sales/${v4}', {
    'itens': [_item(12, 2)],
  }, c: 'admin');
  req('edita venda com item de outra venda', 'PUT', r'/api/sales/${v4}', {
    'itens': [
      {'id_produto': 12, 'id_item_venda': 1, 'quantidade': 1},
    ],
  }, c: 'admin');
  req('edita venda escolhendo o item', 'PUT', r'/api/sales/${v4}', {
    'itens': [
      {'id_produto': 12, 'id_item_venda': r'${item1}', 'quantidade': 2},
      {'id_produto': 12, 'id_item_venda': r'${item2}', 'quantidade': 1},
    ],
  }, c: 'admin');
  req('edita venda incluindo inativo', 'PUT', r'/api/sales/${v1}', {
    'itens': [_item(8, 1), _item(r'${prod2}', 1)],
  }, c: 'admin');
  req('edita venda sem itens', 'PUT', r'/api/sales/${v1}', {'itens': []}, c: 'func');
  req('edita venda quantidade negativa', 'PUT', r'/api/sales/${v1}', {
    'itens': [_item(8, -1)],
  }, c: 'func');
  req('edita venda com desconto percentual', 'PUT', r'/api/sales/${v5}', {
    'itens': [_item(8, 6)],
  }, c: 'func');
  req('edita venda acima do estoque', 'PUT', r'/api/sales/${v1}', {
    'itens': [_item(3, 500)],
  }, c: 'func');
  req('edita venda inexistente', 'PUT', '/api/sales/999', {
    'itens': [_item(8, 1)],
  }, c: 'func');
  req('backoffice não edita venda', 'PUT', r'/api/sales/${v1}', {
    'itens': [_item(8, 1)],
  }, c: 'back');
  post('cancela sem autorizador', r'/api/sales/${v3}/cancel', {'motivo': 'Cliente desistiu da compra'}, c: 'func');
  post('cancela com senha de funcionário', r'/api/sales/${v3}/cancel', {
    'motivo': 'Cliente desistiu da compra',
    'autorizador_email': 'henry@padarianovayork.com',
    'autorizador_senha': 'func123',
  }, c: 'func');
  post('cancela motivo curto', r'/api/sales/${v3}/cancel', {
    'motivo': 'curto',
    'autorizador_email': 'BACKOFFICE@padarianovayork.com',
    'autorizador_senha': 'backoffice123',
  }, c: 'func');
  post('cancela autorizado pelo backoffice', r'/api/sales/${v3}/cancel', {
    'motivo': 'Cliente desistiu da compra',
    'autorizador_email': 'backoffice@padarianovayork.com',
    'autorizador_senha': 'backoffice123',
  }, c: 'func');
  post('cancela de novo', r'/api/sales/${v3}/cancel', {
    'motivo': 'Cliente desistiu da compra',
    'autorizador_email': 'proprietario@padarianovayork.com',
    'autorizador_senha': 'admin123',
  }, c: 'func');
  req('edita venda cancelada', 'PUT', r'/api/sales/${v3}', {
    'itens': [_item(10, 1)],
  }, c: 'func');
  post('cancela venda inexistente', '/api/sales/999/cancel', {
    'motivo': 'Cliente desistiu da compra',
    'autorizador_email': 'proprietario@padarianovayork.com',
    'autorizador_senha': 'admin123',
  }, c: 'admin');
  for (var i = 1; i <= 5; i++) {
    post('senha de gerente errada $i', r'/api/sales/${v5}/cancel', {
      'motivo': 'Cancelamento para teste de limite',
      'autorizador_email': 'admin@limite.com',
      'autorizador_senha': 'errada',
    }, c: 'func');
  }
  post('senha de gerente bloqueada (429)', r'/api/sales/${v5}/cancel', {
    'motivo': 'Cancelamento para teste de limite',
    'autorizador_email': 'ADMIN@limite.com',
    'autorizador_senha': 'errada',
  }, c: 'func');
  req('funcionário não exclui venda', 'DELETE', r'/api/sales/${v1}', <String, Object?>{}, c: 'func');
  req('exclui venda com senha de backoffice', 'DELETE', r'/api/sales/${v1}', {'autorizador_email': 'backoffice@padarianovayork.com', 'autorizador_senha': 'backoffice123'}, c: 'admin');
  req('exclui venda', 'DELETE', r'/api/sales/${v1}', {'autorizador_email': 'proprietario@padarianovayork.com', 'autorizador_senha': 'admin123'}, c: 'admin');
  req('exclui venda cancelada (sem estorno)', 'DELETE', r'/api/sales/${v3}', {'autorizador_email': 'proprietario@padarianovayork.com', 'autorizador_senha': 'admin123'}, c: 'admin');
  req('exclui venda inexistente', 'DELETE', '/api/sales/999', {'autorizador_email': 'proprietario@padarianovayork.com', 'autorizador_senha': 'admin123'}, c: 'admin');
  get('venda excluída', r'/api/sales/${v1}', c: 'admin');
  get('vendas depois', '/api/sales', c: 'admin');

  // ================================================================ conferência
  get('conferências', '/api/inventory', c: 'func');
  post('conferência ajusta o estoque', '/api/inventory', {
    'observacao': 'Conferência quinzenal do estoque',
    'itens': [
      {'id_produto': 12, 'quantidade_fisica': 150},
      {'id_produto': 4, 'quantidade_fisica': '60.5'},
    ],
  }, c: 'func');
  post('conferência sem ajuste', '/api/inventory', {
    'observacao': 'Conferência sem ajuste de estoque',
    'ajustar': false,
    'itens': [
      {'id_produto': 10, 'quantidade_fisica': 1},
    ],
  }, c: 'func');
  post('conferência ajustar "false"', '/api/inventory', {
    'observacao': 'Conferência sem ajuste de estoque',
    'ajustar': 'false',
    'itens': [
      {'id_produto': 10, 'quantidade_fisica': 1},
    ],
  }, c: 'func');
  post('conferência ajustar null', '/api/inventory', {
    'observacao': 'Conferência sem ajuste de estoque',
    'ajustar': null,
    'itens': [
      {'id_produto': 10, 'quantidade_fisica': 1},
    ],
  }, c: 'func');
  post('conferência saldo mudou (409)', '/api/inventory', {
    'observacao': 'Conferência com saldo antigo na tela',
    'itens': [
      {'id_produto': 11, 'quantidade_fisica': 1, 'quantidade_sistema': '1'},
    ],
  }, c: 'func');
  post('conferência produto repetido', '/api/inventory', {
    'observacao': 'Conferência com produto repetido',
    'itens': [
      {'id_produto': 5, 'quantidade_fisica': 1},
      {'id_produto': 5, 'quantidade_fisica': 2},
    ],
  }, c: 'func');
  post('conferência contagem negativa', '/api/inventory', {
    'observacao': 'Conferência com contagem errada',
    'itens': [
      {'id_produto': 5, 'quantidade_fisica': -1},
    ],
  }, c: 'func');
  post('conferência fração em UN', '/api/inventory', {
    'observacao': 'Conferência com contagem errada',
    'itens': [
      {'id_produto': 1, 'quantidade_fisica': 2.5},
    ],
  }, c: 'func');
  post('conferência enorme', '/api/inventory', {
    'observacao': 'Conferência com valor enorme',
    'itens': [
      {'id_produto': 1, 'quantidade_fisica': 1e13},
    ],
  }, c: 'func');
  post('conferência observação longa', '/api/inventory', {
    'observacao': 'x' * 1001,
    'itens': [
      {'id_produto': 1, 'quantidade_fisica': 1},
    ],
  }, c: 'func');
  post('conferência sem itens', '/api/inventory', {'observacao': 'Conferência vazia de teste'}, c: 'func');
  post('conferência item texto', '/api/inventory', {
    'observacao': 'Conferência com item texto',
    'itens': ['x'],
  }, c: 'func');
  post('conferência produto inexistente', '/api/inventory', {
    'observacao': 'Conferência com produto inexistente',
    'itens': [
      {'id_produto': 999, 'quantidade_fisica': 1},
    ],
  }, c: 'func');
  get('conferências depois', '/api/inventory', c: 'admin');

  // ================================================================ painel e alertas depois das operações
  get('dashboard depois', '/api/dashboard', c: 'admin');
  get('alertas depois', '/api/alerts', c: 'admin');
  get('validade depois', '/api/expiring', c: 'admin');
  get('movimentações depois', '/api/movements', c: 'admin');

  // ================================================================ relatórios
  get('relatórios: funcionário não vê', '/api/reports/sales', c: 'func');
  get('relatório de vendas', '/api/reports/sales', c: 'back');
  get('relatório de vendas por categoria', '/api/reports/sales?categoria=2', c: 'back');
  get('relatório de vendas categoria texto', '/api/reports/sales?categoria=abc', c: 'back');
  get('relatório de vendas período vazio', '/api/reports/sales?from=2000-01-01&to=2000-01-02', c: 'back');
  get('relatório de vendas período invertido', '/api/reports/sales?from=2026-12-01&to=2026-01-01', c: 'back');
  get('relatório de vendas PDF', '/api/reports/sales?format=pdf', c: 'back');
  get('relatório de vendas PDF por categoria', '/api/reports/sales?format=PDF&categoria=2&from=2000-01-01', c: 'back');
  get('relatório de vendas PDF categoria inexistente', '/api/reports/sales?format=pdf&categoria=99&to=2099-01-01', c: 'back');
  get('relatório de vendas XLSX', '/api/reports/sales?format=xlsx', c: 'admin');
  get('relatório de estoque', '/api/reports/stock', c: 'admin');
  get('relatório de estoque por categoria', '/api/reports/stock?categoria=3&from=2000-01-01', c: 'admin');
  get('relatório de estoque PDF', '/api/reports/stock?format=pdf', c: 'admin');
  get('relatório de estoque XLSX', '/api/reports/stock?format=Xlsx', c: 'admin');
  get('relatório de estoque formato inválido', '/api/reports/stock?format=doc', c: 'admin');
  get('relatório de perdas', '/api/reports/losses', c: 'back');
  get('relatório de perdas por categoria', '/api/reports/losses?categoria=1', c: 'back');
  get('relatório de perdas PDF', '/api/reports/losses?format=pdf', c: 'back');
  get('relatório de perdas XLSX', '/api/reports/losses?format=xlsx', c: 'back');
  get('relatório de perdas vazio em PDF', '/api/reports/losses?format=pdf&from=2000-01-01&to=2000-01-02', c: 'back');

  // ================================================================ logs
  get('logs: funcionário não vê', '/api/logs', c: 'func');
  get('logs', '/api/logs', c: 'admin');
  get('logs limite 3', '/api/logs?limit=3', c: 'admin');
  get('logs limite 2.9', '/api/logs?limit=2.9', c: 'admin');
  get('logs limite inválido', '/api/logs?limit=abc', c: 'admin');
  get('logs limite 5000', '/api/logs?limit=5000', c: 'admin');

  // ================================================================ arquivos estáticos e endereços
  get('raiz (index.html)', '/');
  get('index.html', '/index.html');
  get('arquivo JS', '/main.dart.js');
  get('fonte', '/assets/fonte.ttf');
  get('wasm', '/canvaskit.wasm');
  get('extensão desconhecida', '/arquivo.xyz');
  get('extensão em maiúsculas', '/IMAGEM.PNG');
  get('rota do app sem extensão (SPA)', '/produtos/editar');
  get('arquivo inexistente com extensão', '/nao-existe.js');
  get('pasta sem extensão', '/assets');
  get('pasta com ponto', '/pasta.d');
  get('fuga com %2f', '/..%2fweb-secreto%2fx.txt');
  get('fuga com contrabarra codificada', '/..%5cweb-secreto%5cx.txt');
  get('fuga com contrabarra', r'/..\web-secreto\x.txt');
  get('fuga com %2e%2e', '/%2e%2e/web-secreto/x.txt');
  get('fuga com ../', '/../web-secreto/x.txt');
  get('fuga para outra unidade', '/C:/Windows/win.ini');
  get('fuga por dispositivo', '/CON:x');
  get('dois pontos no nome', '/a:b.txt');
  get('byte nulo', '/%00.png');
  get('UTF-8 inválido', '/%E0%A4%A');
  get('UTF-8 inválido na API', '/api/%E0%A4%A');
  get('UTF-8 inválido em uploads', '/uploads/%E0%A4%A');
  get('surrogate codificado', '/%ED%A0%80');
  get('acento codificado', '/p%C3%A1gina');
  get('uploads inexistente', '/uploads/nada.png');
  get('uploads sem nome', '/uploads/');
  get('uploads com fuga', '/uploads/..%2f..%2fweb%2findex.html');
  get('query na raiz', '/?x=1');
  l.add(const Passo('HEAD na raiz', 'HEAD', '/'));
  l.add(const Passo('POST num arquivo estático', 'POST', '/index.html', corpo: {'a': 1}));
  get('barra dupla', '//index.html');
  get('API com barra dupla', '//api/categories', c: 'admin');
  get('API com ponto-ponto', '/api/../api/categories', c: 'admin');
  get('API com %2F no id', '/api/products/1%2Fstatus', c: 'admin');

  // ================================================================ corpo grande demais
  bruto('corpo acima de 4 MB', 'POST', '/api/movements', '{"x":"${'a' * (4 * 1024 * 1024)}"}', c: 'func');
  get('o servidor continua de pé', '/api/auth/me', c: 'func');

  // ================================================================ logout final
  post('logout admin', '/api/auth/logout', <String, Object?>{}, c: 'admin');
  get('me depois do logout', '/api/auth/me', c: 'admin');
  return l;
}
