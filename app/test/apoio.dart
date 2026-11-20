// Apoio aos testes: API simulada, sessão pronta e a tela dentro de um app mínimo.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestfast/core/api.dart';
import 'package:gestfast/core/sessao.dart';
import 'package:gestfast/widgets/comuns.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class CofreFalso implements CofreToken {
  String? valor;
  @override
  Future<void> apagar() async => valor = null;
  @override
  Future<void> gravar(String token) async => valor = token;
  @override
  Future<String?> ler() async => valor;
}

class Chamada {
  Chamada(this.metodo, this.caminho, this.corpo, this.cabecalhos);
  final String metodo, caminho;
  final Map<String, dynamic>? corpo;
  final Map<String, String> cabecalhos;
}

typedef Resposta = (int, Map<String, dynamic>);

/// API simulada: chave "METODO /caminho" -> resposta. Registra as chamadas feitas.
class ApiFalsa {
  ApiFalsa(this.rotas);
  final Map<String, Resposta Function(Chamada)> rotas;
  final List<Chamada> chamadas = [];

  http.Client get cliente => MockClient((req) async {
        final corpo = req.body.isEmpty ? null : jsonDecode(req.body) as Map<String, dynamic>;
        final c = Chamada(req.method, req.url.path, corpo, req.headers);
        chamadas.add(c);
        final rota = rotas['${req.method} ${req.url.path}'];
        final (status, dados) = rota == null ? (404, <String, dynamic>{'success': false, 'error': 'Rota não encontrada.'}) : rota(c);
        return http.Response.bytes(utf8.encode(jsonEncode(dados)), status, headers: {'content-type': 'application/json'});
      });

  Iterable<Chamada> de(String metodo, String caminho) => chamadas.where((c) => c.metodo == metodo && c.caminho == caminho);
}

Map<String, dynamic> usuarioJson({String perfil = 'Administrador'}) => {'id_usuario': 1, 'nome': 'Francisco', 'email': 'dono@x.com', 'cargo': '', 'perfil': perfil, 'id_perfil': 1, 'status': 'Ativo'};

const configJson = {'estabelecimento': 'Padaria', 'descontoMaximoPercent': 20, 'intervaloAtualizacaoSeg': 3, 'diasAlertaValidade': 3, 'simularCartaoNegado': false, 'simularFornecedorIndisponivel': false};

Map<String, dynamic> meJson({String perfil = 'Administrador', List<String> permissoes = const []}) => {'success': true, 'user': usuarioJson(perfil: perfil), 'permissoes': permissoes, 'settings': configJson, 'hoje': '2026-11-03'};

Map<String, dynamic> produtoJson(int id, String nome, {String unidade = 'UN', num estoque = 10, num venda = 5, String validade = ''}) => {
      'id_produto': id, 'codigo_barras': '789$id', 'nome_produto': nome, 'descricao': 'Descrição do produto', 'unidade': unidade, 'peso': '', 'preco_custo': 2, 'preco_venda': venda, 'preco_min': 1, 'preco_max': 50,
      'quantidade_estoque': estoque, 'estoque_minimo': 1, 'lote': 'L1', 'validade': validade, 'imagem': '', 'status': 'Ativo', 'id_categoria': 1,
    };

Map<String, Resposta Function(Chamada)> rotasBase({String perfil = 'Administrador', List<String> permissoes = const []}) => {
      'GET /api/auth/me': (_) => (200, meJson(perfil: perfil, permissoes: permissoes)),
      'GET /api/categories': (_) => (200, {'success': true, 'categories': [{'id_categoria': 1, 'nome_categoria': 'Pães'}]}),
      'GET /api/settings': (_) => (200, {'success': true, 'settings': configJson, 'hoje': '2026-11-03'}),
    };

/// Sessão ligada à API falsa. Com [logar], já carrega o perfil.
Future<Sessao> criarSessao(ApiFalsa api, {bool logar = true, CofreToken? cofre}) async {
  final s = Sessao(api: ApiClient(client: api.cliente, web: false), cofre: cofre ?? CofreFalso());
  s.api.baseUrl = 'http://servidor.local';
  s.servidor = s.api.baseUrl;
  s.iniciada = true;
  if (logar) await s.carregarPerfil();
  return s;
}

Future<void> abrirTela(WidgetTester t, Sessao s, Widget tela) async {
  t.view.physicalSize = const Size(1400, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [sessaoProvider.overrideWith((ref) => s)],
    child: MaterialApp(builder: (_, filho) => CamadaAvisos(child: filho!), home: Scaffold(body: tela)),
  ));
  await t.pumpAndSettle();
}

Finder campoRotulado(String rotulo) => find.byKey(ValueKey('campo:$rotulo'));
