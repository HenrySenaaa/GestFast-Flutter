// url.dart - decodeURIComponent e URLSearchParams com as regras do JavaScript.
import 'dart:convert';

/// Erro do `decodeURIComponent` (URIError no JS).
class ErroUri implements Exception {
  const ErroUri();
}

int _hex(int c) {
  if (c >= 0x30 && c <= 0x39) return c - 0x30;
  if (c >= 0x41 && c <= 0x46) return c - 0x37;
  if (c >= 0x61 && c <= 0x66) return c - 0x57;
  return -1;
}

int _byteEm(String s, int k) {
  if (k + 2 >= s.length || s.codeUnitAt(k) != 0x25) throw const ErroUri();
  final a = _hex(s.codeUnitAt(k + 1)), b = _hex(s.codeUnitAt(k + 2));
  if (a < 0 || b < 0) throw const ErroUri();
  return a * 16 + b;
}

/// `decodeURIComponent(s)`: lança [ErroUri] para `%` malformado ou UTF-8 inválido.
String decodeURIComponent(String s) {
  final sb = StringBuffer();
  final n = s.length;
  for (var k = 0; k < n; k++) {
    final c = s.codeUnitAt(k);
    if (c != 0x25) {
      sb.writeCharCode(c);
      continue;
    }
    if (k + 2 >= n) throw const ErroUri();
    final b = _byteEm(s, k);
    k += 2;
    if (b < 0x80) {
      sb.writeCharCode(b);
      continue;
    }
    int qtd;
    if ((b & 0xE0) == 0xC0) {
      qtd = 2;
    } else if ((b & 0xF0) == 0xE0) {
      qtd = 3;
    } else if ((b & 0xF8) == 0xF0) {
      qtd = 4;
    } else {
      throw const ErroUri();
    }
    final octetos = [b];
    if (k + 3 * (qtd - 1) >= n) throw const ErroUri();
    for (var j = 1; j < qtd; j++) {
      k++;
      final x = _byteEm(s, k);
      if ((x & 0xC0) != 0x80) throw const ErroUri();
      k += 2;
      octetos.add(x);
    }
    // UTF-8 válido: sem forma longa, sem surrogate, até U+10FFFF.
    int cp;
    if (qtd == 2) {
      cp = ((b & 0x1F) << 6) | (octetos[1] & 0x3F);
      if (cp < 0x80) throw const ErroUri();
    } else if (qtd == 3) {
      cp = ((b & 0x0F) << 12) | ((octetos[1] & 0x3F) << 6) | (octetos[2] & 0x3F);
      if (cp < 0x800 || (cp >= 0xD800 && cp <= 0xDFFF)) throw const ErroUri();
    } else {
      cp = ((b & 0x07) << 18) | ((octetos[1] & 0x3F) << 12) | ((octetos[2] & 0x3F) << 6) | (octetos[3] & 0x3F);
      if (cp < 0x10000 || cp > 0x10FFFF) throw const ErroUri();
    }
    sb.writeCharCode(cp);
  }
  return sb.toString();
}

/// Decodificação percentual tolerante (WHATWG): `%` inválido fica como está.
List<int> _percentDecodeBytes(List<int> entrada) {
  final out = <int>[];
  for (var i = 0; i < entrada.length; i++) {
    final c = entrada[i];
    if (c == 0x25 && i + 2 < entrada.length) {
      final a = _hex(entrada[i + 1]), b = _hex(entrada[i + 2]);
      if (a >= 0 && b >= 0) {
        out.add(a * 16 + b);
        i += 2;
        continue;
      }
    }
    out.add(c);
  }
  return out;
}

/// `Object.fromEntries(new URLSearchParams(query))`: a última ocorrência de cada chave vale.
Map<String, String> lerQuery(String query) {
  final out = <String, String>{};
  if (query.isEmpty) return out;
  final bytes = utf8.encode(query);
  var ini = 0;
  for (var i = 0; i <= bytes.length; i++) {
    if (i < bytes.length && bytes[i] != 0x26) continue;
    final seq = bytes.sublist(ini, i);
    ini = i + 1;
    if (seq.isEmpty) continue;
    final eq = seq.indexOf(0x3D);
    List<int> nome, valor;
    if (eq >= 0) {
      nome = seq.sublist(0, eq);
      valor = seq.sublist(eq + 1);
    } else {
      nome = seq;
      valor = const [];
    }
    String dec(List<int> b) =>
        utf8.decode(_percentDecodeBytes([for (final x in b) x == 0x2B ? 0x20 : x]), allowMalformed: true);
    out[dec(nome)] = dec(valor);
  }
  return out;
}
