// js.dart - Semântica de JavaScript que o backend original (Node.js) usava.
//
// O servidor em Dart precisa responder exatamente como o Node: mesmas conversões
// (`Number(x)`, `String(x)`, `x || y`), mesmo arredondamento (`Math.round`), mesmos
// números no JSON (`10`, não `10.0`) e mesma ordenação estável. Este arquivo reúne
// essas regras para que o resto do código possa ser uma tradução direta.
//
// Modelo de valores (igual ao do JSON.parse do Node):
//   undefined -> [undefined]   null -> null   boolean -> bool   número -> double
//   texto -> String   array -> List<Object?>   objeto -> Map<String, Object?>
import 'dart:convert';
import 'dart:math' as math;

/// O `undefined` do JavaScript (chave ausente). Diferente de `null`.
final class Undefined {
  const Undefined._();
  @override
  String toString() => 'undefined';
}

const Object undefined = Undefined._();

bool isUndef(Object? v) => v is Undefined;
bool isNullish(Object? v) => v == null || v is Undefined;

/// `obj.chave` do JavaScript: `undefined` quando a chave não existe ou `obj` não é objeto.
Object? prop(Object? obj, String chave) {
  if (obj is Map && obj.containsKey(chave)) return obj[chave];
  return undefined;
}

/// Valor "verdadeiro" do JavaScript (`if (v)`).
bool truthy(Object? v) {
  if (v == null || v is Undefined) return false;
  if (v is bool) return v;
  if (v is num) return !(v == 0 || v.isNaN);
  if (v is String) return v.isNotEmpty;
  return true;
}

/// `a || b`
Object? or(Object? a, Object? b) => truthy(a) ? a : b;

// ---------------------------------------------------------------------------- números

const double epsilon = 2.220446049250313e-16; // Number.EPSILON

/// Espaços que o `trim()` e o `Number()` do JavaScript removem.
bool _ehEspacoJs(int c) =>
    c == 0x09 ||
    c == 0x0A ||
    c == 0x0B ||
    c == 0x0C ||
    c == 0x0D ||
    c == 0x20 ||
    c == 0xA0 ||
    c == 0x1680 ||
    (c >= 0x2000 && c <= 0x200A) ||
    c == 0x2028 ||
    c == 0x2029 ||
    c == 0x202F ||
    c == 0x205F ||
    c == 0x3000 ||
    c == 0xFEFF;

/// `String.prototype.trim()`
String jsTrim(String s) {
  var i = 0, f = s.length;
  while (i < f && _ehEspacoJs(s.codeUnitAt(i))) {
    i++;
  }
  while (f > i && _ehEspacoJs(s.codeUnitAt(f - 1))) {
    f--;
  }
  return (i == 0 && f == s.length) ? s : s.substring(i, f);
}

final _decimalJs = RegExp(r'^[+-]?(?:\d+\.?\d*(?:[eE][+-]?\d+)?|\.\d+(?:[eE][+-]?\d+)?)$');
final _radixJs = RegExp(r'^0([xXoObB])([0-9a-zA-Z]+)$');

/// `Number(texto)` (StringToNumber da especificação).
double numeroDeTexto(String texto) {
  final s = jsTrim(texto);
  if (s.isEmpty) return 0;
  if (s == 'Infinity' || s == '+Infinity') return double.infinity;
  if (s == '-Infinity') return double.negativeInfinity;
  final r = _radixJs.firstMatch(s);
  if (r != null) {
    final base = switch (r.group(1)!.toLowerCase()) {
      'x' => 16,
      'o' => 8,
      _ => 2,
    };
    final digitos = r.group(2)!;
    final valido = switch (base) {
      16 => RegExp(r'^[0-9a-fA-F]+$'),
      8 => RegExp(r'^[0-7]+$'),
      _ => RegExp(r'^[01]+$'),
    };
    if (!valido.hasMatch(digitos)) return double.nan;
    return BigInt.parse(digitos, radix: base).toDouble();
  }
  if (!_decimalJs.hasMatch(s)) return double.nan;
  return double.parse(s);
}

/// `Number(v)`
double toNumber(Object? v) {
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v == null) return 0;
  if (v is Undefined) return double.nan;
  if (v is bool) return v ? 1 : 0;
  if (v is String) return numeroDeTexto(v);
  if (v is List) return numeroDeTexto(toStr(v));
  return double.nan; // objeto: "[object Object]"
}

bool isFinite(double n) => n.isFinite;

/// `Number.isInteger(n)`
bool isInteger(double n) => n.isFinite && n == n.truncateToDouble();

/// `Math.round(n)` (meio arredonda para +infinito, diferente do `round()` do Dart).
double jsRound(double n) {
  if (!n.isFinite || n == 0) return n;
  final f = n.floorToDouble();
  final r = (n - f >= 0.5) ? f + 1 : f;
  // Math.round(-0.4) é -0; só importa para o sinal, que o JSON não mostra.
  return r;
}

/// `Math.trunc(n)`
double jsTrunc(double n) => n.isFinite ? n.truncateToDouble() : n;

/// Arredonda para 2 casas como o db.js: `Math.round((n + EPSILON) * 100) / 100`.
double r2(Object? n) => jsRound((toNumber(n) + epsilon) * 100) / 100;

/// Arredonda para 3 casas como o db.js.
double r3(Object? n) => jsRound((toNumber(n) + epsilon) * 1000) / 1000;

/// `String(n)` para número (formato do JavaScript: `10`, `0.1`, `1e+21`, `1e-7`).
String numStr(num valor) {
  final n = valor.toDouble();
  if (n.isNaN) return 'NaN';
  if (n == double.infinity) return 'Infinity';
  if (n == double.negativeInfinity) return '-Infinity';
  if (n == 0) return '0';
  if (n == n.truncateToDouble() && n.abs() < 1e21) {
    // inteiro: sem ".0"
    final s = n.toString();
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }
  // O Dart já usa a menor representação exata, no mesmo formato do JS
  // (inclusive "1e+21" e "1e-7").
  return n.toString();
}

/// `n.toFixed(casas)`
String toFixed(double n, int casas) {
  if (n.isNaN) return 'NaN';
  if (n.abs() >= 1e21 || !n.isFinite) return numStr(n);
  if (n == 0) n = 0; // -0 vira "0.00", como no JS
  final s = n.toStringAsFixed(casas);
  return s;
}

// ---------------------------------------------------------------------------- textos

/// `String(v)`
String toStr(Object? v) {
  if (v is String) return v;
  if (v == null) return 'null';
  if (v is Undefined) return 'undefined';
  if (v is bool) return v ? 'true' : 'false';
  if (v is num) return numStr(v);
  if (v is List) return v.map((e) => isNullish(e) ? '' : toStr(e)).join(',');
  return '[object Object]';
}

/// `txt(v)` do db.js: vazio para null/undefined, senão `String(v).trim()`.
String txt(Object? v) => isNullish(v) ? '' : jsTrim(toStr(v));

/// `s.slice(0, n)` (unidades UTF-16, igual ao JS).
String sliceStr(String s, int fim) => s.length <= fim ? s : s.substring(0, fim);

/// `toLowerCase()` do JavaScript (mapeamento Unicode completo, sem localidade).
String jsLower(String s) => s.toLowerCase();

// ---------------------------------------------------------------------------- JSON

/// `JSON.parse(texto)`, com os números como double (como no JS).
Object? jsonParse(String texto) => _normalizar(jsonDecode(texto));

Object? _normalizar(Object? v) {
  if (v is int) return v.toDouble();
  if (v is List) return [for (final e in v) _normalizar(e)];
  if (v is Map) {
    return <String, Object?>{for (final e in v.entries) e.key as String: _normalizar(e.value)};
  }
  return v;
}

/// `JSON.stringify(v)` (sem espaços), no formato exato do Node.
String jsonStringify(Object? v) {
  final sb = StringBuffer();
  _escrever(sb, v);
  return sb.toString();
}

void _escrever(StringBuffer sb, Object? v) {
  if (v == null || v is Undefined) {
    sb.write('null');
  } else if (v is bool) {
    sb.write(v ? 'true' : 'false');
  } else if (v is num) {
    sb.write(v.isFinite ? numStr(v) : 'null');
  } else if (v is String) {
    escreverTextoJson(sb, v);
  } else if (v is List) {
    sb.write('[');
    for (var i = 0; i < v.length; i++) {
      if (i > 0) sb.write(',');
      _escrever(sb, v[i]);
    }
    sb.write(']');
  } else if (v is Map) {
    sb.write('{');
    var primeiro = true;
    for (final e in v.entries) {
      if (e.value is Undefined) continue;
      if (!primeiro) sb.write(',');
      primeiro = false;
      escreverTextoJson(sb, e.key.toString());
      sb.write(':');
      _escrever(sb, e.value);
    }
    sb.write('}');
  } else {
    throw ArgumentError('valor sem representação JSON: ${v.runtimeType}');
  }
}

/// Texto entre aspas como o `JSON.stringify` do Node (inclusive surrogates soltos).
void escreverTextoJson(StringBuffer sb, String s) {
  sb.write('"');
  final n = s.length;
  for (var i = 0; i < n; i++) {
    final c = s.codeUnitAt(i);
    if (c == 0x22) {
      sb.write(r'\"');
    } else if (c == 0x5C) {
      sb.write(r'\\');
    } else if (c < 0x20) {
      switch (c) {
        case 0x08:
          sb.write(r'\b');
        case 0x09:
          sb.write(r'\t');
        case 0x0A:
          sb.write(r'\n');
        case 0x0C:
          sb.write(r'\f');
        case 0x0D:
          sb.write(r'\r');
        default:
          sb.write('\\u${c.toRadixString(16).padLeft(4, '0')}');
      }
    } else if (c >= 0xD800 && c <= 0xDBFF) {
      if (i + 1 < n) {
        final d = s.codeUnitAt(i + 1);
        if (d >= 0xDC00 && d <= 0xDFFF) {
          sb.writeCharCode(c);
          sb.writeCharCode(d);
          i++;
          continue;
        }
      }
      sb.write('\\u${c.toRadixString(16)}');
    } else if (c >= 0xDC00 && c <= 0xDFFF) {
      sb.write('\\u${c.toRadixString(16)}');
    } else {
      sb.writeCharCode(c);
    }
  }
  sb.write('"');
}

// ---------------------------------------------------------------------------- listas

/// `Array.prototype.sort(cmp)` do V8: estável (o `List.sort` do Dart não é).
/// Um resultado negativo põe `a` antes de `b`; zero, positivo ou NaN mantêm a ordem.
List<T> sortJs<T>(List<T> lista, num Function(T a, T b) cmp) {
  if (lista.length < 2) return lista;
  final aux = List<T>.of(lista);
  _mergeSort(lista, aux, 0, lista.length, cmp);
  return lista;
}

void _mergeSort<T>(List<T> a, List<T> aux, int ini, int fim, num Function(T, T) cmp) {
  if (fim - ini < 2) return;
  final meio = (ini + fim) >> 1;
  _mergeSort(a, aux, ini, meio, cmp);
  _mergeSort(a, aux, meio, fim, cmp);
  for (var k = ini; k < fim; k++) {
    aux[k] = a[k];
  }
  var i = ini, j = meio;
  for (var k = ini; k < fim; k++) {
    if (i >= meio) {
      a[k] = aux[j++];
    } else if (j >= fim) {
      a[k] = aux[i++];
    } else if (cmp(aux[j], aux[i]) < 0) {
      a[k] = aux[j++];
    } else {
      a[k] = aux[i++];
    }
  }
}

/// `Math.min` para dois números (NaN contamina, como no JS).
double jsMin(double a, double b) => (a.isNaN || b.isNaN) ? double.nan : math.min(a, b);
