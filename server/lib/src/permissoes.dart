// permissoes.dart - Perfis de acesso (RF 02 / RF 03).

const _a = 'Administrador', _b = 'BackOffice', _f = 'Funcionario';
const _todos = [_a, _b, _f];

/// Permissão -> perfis. A ordem das chaves é a da lista devolvida ao app.
const Map<String, List<String>> permissoes = {
  'dashboard:ver': _todos,
  'produtos:ver': _todos,
  'produtos:editar': [_a, _b],
  'estoque:conferir': _todos,
  'movimentos:ver': _todos,
  'movimentos:registrar': _todos,
  'requisicoes:ver': _todos,
  'requisicoes:criar': _todos,
  'requisicoes:cancelar': _todos,
  'requisicoes:receber': _todos,
  'requisicoes:avancar': [_a, _b],
  'vendas:vender': [_a, _f],
  'vendas:ver': _todos,
  'vendas:editar': [_a, _f],
  'vendas:cancelar': [_a, _f],
  'vendas:excluir': [_a],
  'relatorios:ver': [_a, _b],
  'usuarios:gerir': [_a],
  'config:gerir': [_a],
  'logs:ver': [_a],
};

bool pode(Object? perfil, String perm) => (permissoes[perm] ?? const []).contains(perfil);

List<String> permissoesDe(Object? perfil) => [for (final p in permissoes.keys) if (pode(perfil, p)) p];
