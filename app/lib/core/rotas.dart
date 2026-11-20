// Rotas do app: login, telas protegidas e checagem de permissão.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/ajuda_tela.dart';
import '../features/configuracoes_tela.dart';
import '../features/estoque_tela.dart';
import '../features/funcionarios_tela.dart';
import '../features/historico_tela.dart';
import '../features/login_tela.dart';
import '../features/movimentos_tela.dart';
import '../features/painel_tela.dart';
import '../features/produtos_tela.dart';
import '../features/relatorios_tela.dart';
import '../features/requisicoes_tela.dart';
import '../features/vendas_tela.dart';
import '../widgets/casca.dart';
import '../widgets/comuns.dart';
import 'sessao.dart';

class Destino {
  const Destino(this.caminho, this.rotulo, this.rotuloBusca, this.emoji, this.perm, this.descricao, this.chaves);
  final String caminho, rotulo, rotuloBusca, emoji, descricao, chaves;
  final String? perm;
}

// Mesmos nomes do menu e da busca do v1.
const destinos = [
  Destino('/painel', 'Início', 'Início (Dashboard)', '🏠', 'dashboard:ver', 'Alertas, compras recentes e distribuição do estoque', 'inicio dashboard painel home alertas'),
  Destino('/estoque', 'Verificar Estoque', 'Verificar Estoque', '📦', 'estoque:conferir', 'Conferência física e divergências', 'estoque conferencia verificar inventario contagem'),
  Destino('/requisicoes', 'Requisição', 'Requisições de Compra', '📝', 'requisicoes:ver', 'Pedidos aos fornecedores', 'requisicao requisicoes pedido compra fornecedor'),
  Destino('/produtos', 'Cadastro de Produtos', 'Cadastro de Produtos', '🏷️', 'produtos:editar', 'Incluir, alterar e inativar produtos', 'cadastro produto cadastrar novo catalogo'),
  Destino('/saidas', 'Saída de Produtos', 'Saída de Produtos', '📤', 'movimentos:ver', 'Baixas, descartes e perdas', 'saida saidas baixa descarte perda'),
  Destino('/entradas', 'Entrada de Produtos', 'Entrada de Produtos', '📥', 'movimentos:ver', 'Recebimentos e reposição', 'entrada entradas recebimento reposicao'),
  Destino('/venda', 'Venda', 'Venda (Caixa)', '🛒', 'vendas:vender', 'Registrar vendas no balcão', 'venda vendas caixa pdv vender carrinho'),
  Destino('/historico', 'Histórico de Vendas', 'Histórico de Vendas', '🧾', 'vendas:ver', 'Consultar, editar e cancelar vendas', 'historico vendas cancelar editar consultar'),
  Destino('/relatorios', 'Relatórios', 'Relatórios', '📊', 'relatorios:ver', 'Faturamento e estoque, em PDF ou Excel', 'relatorio relatorios faturamento exportar pdf excel'),
  Destino('/funcionarios', 'Funcionários', 'Funcionários', '👥', 'usuarios:gerir', 'Acessos e perfis', 'funcionario funcionarios usuario acesso perfil login'),
  Destino('/configuracoes', 'Configuração', 'Configuração', '⚙️', null, 'Parâmetros, senha e acessibilidade', 'configuracao configuracoes config senha acessibilidade logs'),
  Destino('/ajuda', 'Ajuda', 'Ajuda', '❓', null, 'Sobre o sistema e perfis de acesso', 'ajuda sobre suporte'),
];

GoRouter criarRotas(Sessao sessao) {
  Page<void> pagina(GoRouterState s, Widget tela) => NoTransitionPage(key: ValueKey(s.uri.toString()), child: KeyedSubtree(key: ValueKey(s.uri.toString()), child: tela));
  Map<String, String> q(GoRouterState s) => s.uri.queryParameters;

  // Volta para a tela pedida antes do login (endereço digitado, página recarregada ou sessão expirada), como o #hash do v1.
  String destino() {
    final d = sessao.destinoPosLogin;
    sessao.destinoPosLogin = null;
    return d ?? '/painel';
  }

  return GoRouter(
    initialLocation: '/painel',
    refreshListenable: sessao,
    // Endereço desconhecido: o v1 abria o Início.
    onException: (_, _, router) => router.go('/painel'),
    redirect: (context, estado) {
      final local = estado.matchedLocation;
      final publica = local == '/login' || local == '/redefinir';
      final protegida = !publica && local != '/carregando';
      if (!sessao.iniciada) {
        if (local == '/redefinir') return null;
        if (protegida) sessao.destinoPosLogin = estado.uri.toString();
        return local == '/carregando' ? null : '/carregando';
      }
      if (local == '/carregando') return sessao.logado ? destino() : '/login';
      if (!sessao.logado) {
        if (publica) return null;
        if (sessao.lembrarDestino) sessao.destinoPosLogin = estado.uri.toString();
        return '/login';
      }
      if (publica) return destino();
      // Tela sem permissão (endereço digitado ou link antigo): volta ao início com o aviso do v1.
      for (final d in destinos) {
        if (d.caminho == local && d.perm != null && !sessao.pode(d.perm!)) {
          Future.microtask(() => avisar('Seu perfil não tem permissão para acessar esta área.', tipo: TipoAviso.erro));
          return '/painel';
        }
      }
      return null;
    },
    routes: [
      GoRoute(path: '/carregando', builder: (_, _) => const Scaffold(body: Center(child: CircularProgressIndicator()))),
      GoRoute(path: '/login', builder: (_, _) => const LoginTela()),
      GoRoute(path: '/redefinir', builder: (_, s) => LoginTela(codigoRedefinicao: q(s)['codigo'] ?? '', redefinir: true)),
      ShellRoute(
        builder: (_, _, filho) => Casca(filho: filho),
        routes: [
          GoRoute(path: '/painel', pageBuilder: (_, s) => pagina(s, const PainelTela())),
          GoRoute(path: '/estoque', pageBuilder: (_, s) => pagina(s, EstoqueTela(filtroInicial: q(s)['q'] ?? ''))),
          GoRoute(path: '/requisicoes', pageBuilder: (_, s) => pagina(s, RequisicoesTela(selecionarId: int.tryParse(q(s)['id'] ?? '')))),
          GoRoute(path: '/produtos', pageBuilder: (_, s) => pagina(s, ProdutosTela(abrirId: int.tryParse(q(s)['id'] ?? '')))),
          GoRoute(path: '/saidas', pageBuilder: (_, s) => pagina(s, const MovimentosTela(tipo: 'Saída'))),
          GoRoute(path: '/entradas', pageBuilder: (_, s) => pagina(s, const MovimentosTela(tipo: 'Entrada'))),
          GoRoute(path: '/venda', pageBuilder: (_, s) => pagina(s, const VendasTela())),
          GoRoute(path: '/historico', pageBuilder: (_, s) => pagina(s, HistoricoTela(vendaId: int.tryParse(q(s)['venda'] ?? ''), dia: q(s)['dia'], busca: q(s)['q']))),
          GoRoute(path: '/relatorios', pageBuilder: (_, s) => pagina(s, const RelatoriosTela())),
          GoRoute(path: '/funcionarios', pageBuilder: (_, s) => pagina(s, FuncionariosTela(buscaInicial: q(s)['q'] ?? ''))),
          GoRoute(path: '/configuracoes', pageBuilder: (_, s) => pagina(s, const ConfiguracoesTela())),
          GoRoute(path: '/ajuda', pageBuilder: (_, s) => pagina(s, const AjudaTela())),
        ],
      ),
    ],
  );
}
