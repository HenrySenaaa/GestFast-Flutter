// executor.dart - Executa os passos de contrato num servidor e normaliza as respostas.
//
// O mesmo código roda contra o servidor Node e o Dart (harness.dart) e contra o Dart sozinho,
// comparando com a resposta gravada do Node (test/contrato_test.dart).
import 'dart:convert';
import 'dart:io';

import 'http_cru.dart';

/// Um passo: uma requisição HTTP feita por um "cliente" (sessão) com nome.
class Passo {
  const Passo(
    this.nome,
    this.metodo,
    this.alvo, {
    this.cliente,
    this.corpo = semCorpo,
    this.bruto,
    this.cabecalhos = const {},
    this.bearer = false,
    this.salvar = const {},
    this.acao,
  });

  final String nome;
  final String metodo;

  /// Caminho e query exatamente como vão na linha de pedido (aceita `${variavel}`).
  final String alvo;

  /// Sessão: o cookie (ou token, com [bearer]) é guardado por nome de cliente.
  final String? cliente;
  final Object? corpo;

  /// Corpo cru (bytes como texto latin1), para JSON inválido e corpos enormes.
  final String? bruto;
  final Map<String, String> cabecalhos;
  final bool bearer;

  /// variável -> caminho no JSON da resposta (ex.: `product.id_produto`).
  final Map<String, String> salvar;

  /// 'codigo': lê o último código de redefinição escrito no console do servidor.
  final String? acao;
}

const semCorpo = Object();

/// Estado de um servidor durante a execução: sessões, variáveis e console.
class Estado {
  Estado(this.host, this.porta, {this.lerConsole});
  final String host;
  final int porta;
  final Map<String, String> cookies = {};
  final Map<String, String> tokens = {};
  final Map<String, Object?> vars = {};

  /// Linhas escritas pelo servidor no console (para o código de redefinição de senha).
  final List<String> Function()? lerConsole;
}

Object? _substituir(Object? v, Map<String, Object?> vars) {
  if (v is String) {
    final inteira = RegExp(r'^\$\{(\w+)\}$').firstMatch(v);
    if (inteira != null && vars.containsKey(inteira[1])) return vars[inteira[1]];
    return v.replaceAllMapped(RegExp(r'\$\{(\w+)\}'), (m) => vars.containsKey(m[1]) ? _texto(vars[m[1]]) : m[0]!);
  }
  if (v is List) return [for (final e in v) _substituir(e, vars)];
  if (v is Map) return {for (final e in v.entries) e.key: _substituir(e.value, vars)};
  return v;
}

String _texto(Object? v) {
  if (v is double && v == v.truncateToDouble() && v.abs() < 1e15) return v.toInt().toString();
  return '$v';
}

Object? _caminho(Object? json, String caminho) {
  Object? atual = json;
  for (final parte in caminho.split('.')) {
    if (atual is Map) {
      atual = atual[parte];
    } else if (atual is List) {
      final i = int.tryParse(parte);
      atual = (i != null && i < atual.length) ? atual[i] : null;
    } else {
      return null;
    }
  }
  return atual;
}

/// Executa o passo e devolve a resposta já normalizada (pronta para comparar ou gravar).
Future<Map<String, Object?>> executar(Passo p, Estado e) async {
  if (p.acao == 'codigo') {
    // O código sai só no console (sem e-mail configurado), como no servidor Node.
    String? linha;
    for (var t = 0; t < 50 && linha == null; t++) {
      linha = e.lerConsole!().lastWhere((l) => l.contains('(código: '), orElse: () => '');
      if (linha.isEmpty) {
        linha = null;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    final codigo = RegExp(r'\(código: ([0-9a-f]+)\)').firstMatch(linha ?? '')?[1];
    p.salvar.forEach((k, _) => e.vars[k] = codigo);
    return {'console': _mascarar(linha ?? '<sem código>')};
  }
  final cab = <String, String>{...p.cabecalhos.map((k, v) => MapEntry(k, _substituir(v, e.vars) as String))};
  final cli = p.cliente;
  if (cli != null) {
    if (p.bearer) {
      if (e.tokens[cli] != null) cab['Authorization'] = 'Bearer ${e.tokens[cli]}';
    } else if ((e.cookies[cli] ?? '').isNotEmpty) {
      cab['Cookie'] = e.cookies[cli]!;
    }
  }
  List<int>? corpo;
  if (p.bruto != null) {
    corpo = latin1.encode(p.bruto!);
  } else if (!identical(p.corpo, semCorpo)) {
    cab.putIfAbsent('Content-Type', () => 'application/json');
    corpo = utf8.encode(jsonEncode(_substituir(p.corpo, e.vars)));
  }
  final alvo = _substituir(p.alvo, e.vars) as String;
  final r = await enviarCru(host: e.host, porta: e.porta, metodo: p.metodo, alvo: alvo, cabecalhos: cab, corpo: corpo);
  // sessão
  final sc = r.cabecalhos['set-cookie'];
  if (cli != null && sc != null && sc.isNotEmpty) {
    final par = sc.first.split(';').first;
    e.cookies[cli] = par.endsWith('=') ? '' : par;
  }
  final tipo = (r.cabecalho('content-type') ?? '').toLowerCase();
  Object? json;
  if (tipo.startsWith('application/json')) {
    try {
      json = jsonDecode(utf8.decode(r.corpo, allowMalformed: true));
    } catch (_) {}
  }
  if (cli != null && json is Map && json['token'] is String) e.tokens[cli] = json['token'] as String;
  p.salvar.forEach((nome, caminho) => e.vars[nome] = _caminho(json, caminho));
  return normalizar(r, json);
}

const _cabecalhosComparados = [
  'content-type',
  'cache-control',
  'content-disposition',
  'set-cookie',
  'access-control-allow-origin',
  'access-control-allow-headers',
  'access-control-allow-methods',
  'access-control-expose-headers',
  'access-control-max-age',
  'vary',
  'x-content-type-options',
  'x-frame-options',
  'referrer-policy',
  'content-security-policy',
];

final _hex64 = RegExp(r'[0-9a-f]{64}');

String _mascarar(String s) => s
    .replaceAll(_hex64, '<token>')
    .replaceAll(RegExp(r'http://localhost:\d+/'), 'http://localhost:<porta>/');

Object? _normalizarJson(Object? v, [String? chave, Map? pai]) {
  if (v is Map) {
    return {for (final e in v.entries) e.key as String: _normalizarJson(e.value, e.key as String, v)};
  }
  if (v is List) return [for (final x in v) _normalizarJson(x, chave, pai)];
  if (v is String) {
    if (chave == 'token' && _hex64.hasMatch(v)) return '<token>';
    // lote gerado ao acaso quando o produto é cadastrado sem lote
    if (RegExp(r'^L-\d{6}$').hasMatch(v)) return 'L-<aleatório>';
    // pilha de erro interno: muda de linguagem para linguagem
    if (chave == 'erro' && pai != null && pai['evento'] == 'falha_interna') return '<pilha do erro>';
    return v;
  }
  return v;
}

/// Resposta normalizada: status, cabeçalhos relevantes e corpo.
Map<String, Object?> normalizar(RespostaCrua r, Object? json) {
  final cab = <String, Object?>{};
  for (final k in _cabecalhosComparados) {
    final v = r.cabecalho(k);
    if (v != null) cab[k] = k == 'set-cookie' ? _mascarar(v) : v;
  }
  final tipo = (r.cabecalho('content-type') ?? '').toLowerCase();
  Object? corpo;
  if (json != null) {
    corpo = {'json': _normalizarJson(json)};
  } else if (tipo.contains('spreadsheetml')) {
    corpo = {'xlsx': _entradasZip(r.corpo)};
  } else if (tipo.startsWith('application/pdf') || tipo.startsWith('image/') || tipo.contains('octet-stream') || tipo.startsWith('font/') || tipo.contains('wasm')) {
    corpo = {'base64': base64Encode(r.corpo)};
  } else {
    corpo = {'texto': utf8.decode(r.corpo, allowMalformed: true)};
  }
  return {'status': r.status, if (r.erro != null) 'erro': r.erro, 'cabecalhos': cab, 'corpo': corpo};
}

/// Conteúdo descompactado de cada arquivo do .xlsx (os bytes comprimidos podem variar
/// com a versão do zlib, o conteúdo não).
Map<String, String> _entradasZip(List<int> b) {
  final out = <String, String>{};
  var i = 0;
  while (i + 30 <= b.length && b[i] == 0x50 && b[i + 1] == 0x4b && b[i + 2] == 3 && b[i + 3] == 4) {
    int u16(int o) => b[o] | (b[o + 1] << 8);
    int u32(int o) => u16(o) | (u16(o + 2) << 16);
    final metodo = u16(i + 8), comp = u32(i + 18), nomeLen = u16(i + 26), extra = u16(i + 28);
    final nome = utf8.decode(b.sublist(i + 30, i + 30 + nomeLen));
    final ini = i + 30 + nomeLen + extra;
    final dados = b.sublist(ini, ini + comp);
    out[nome] = utf8.decode(metodo == 8 ? ZLibDecoder(raw: true).convert(dados) : dados, allowMalformed: true);
    i = ini + comp;
  }
  return out;
}

/// Diferenças entre duas respostas normalizadas (vazio = iguais).
List<String> comparar(Object? a, Object? b, [String onde = '']) {
  if (a is Map && b is Map) {
    final out = <String>[];
    final ka = a.keys.toList(), kb = b.keys.toList();
    for (final k in {...ka, ...kb}) {
      if (!a.containsKey(k)) {
        out.add('$onde.$k: só no Dart = ${_curto(b[k])}');
      } else if (!b.containsKey(k)) {
        out.add('$onde.$k: só no Node = ${_curto(a[k])}');
      } else {
        out.addAll(comparar(a[k], b[k], '$onde.$k'));
      }
    }
    final comuns = ka.where(kb.contains).toList(), comunsB = kb.where(ka.contains).toList();
    if (out.isEmpty && comuns.join(',') != comunsB.join(',')) out.add('$onde: ordem das chaves difere (${comuns.join(',')} x ${comunsB.join(',')})');
    return out;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return ['$onde: ${a.length} itens no Node x ${b.length} no Dart'];
    return [for (var i = 0; i < a.length; i++) ...comparar(a[i], b[i], '$onde[$i]')];
  }
  // 10 e 10.0 são iguais para o Dart, mas no JSON aparecem diferentes: o tipo também conta.
  if (a is num && b is num) return (a == b && a.runtimeType == b.runtimeType) ? const [] : ['$onde: Node ${_curto(a)} x Dart ${_curto(b)}'];
  if (a == b) return const [];
  return ['$onde: Node ${_curto(a)} x Dart ${_curto(b)}'];
}

String _curto(Object? v) {
  final s = jsonEncode(v);
  return s.length > 300 ? '${s.substring(0, 300)}…' : s;
}
