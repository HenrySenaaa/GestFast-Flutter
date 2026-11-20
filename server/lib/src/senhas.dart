// senhas.dart - Hash de senha (scrypt) e tokens de sessão (RNF 05).
//
// Formato gravado no banco (igual ao do servidor Node): `scrypt$<salt hex>$<hash hex>`,
// com os parâmetros padrão do `crypto.scryptSync` do Node (N=16384, r=8, p=1, 64 bytes).
// Os usuários já cadastrados continuam entrando com a mesma senha.
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'js.dart';

const _n = 16384, _r = 8, _p = 1;
final _aleatorio = Random.secure();

Uint8List _bytesAleatorios(int n) => Uint8List.fromList(List.generate(n, (_) => _aleatorio.nextInt(256)));

String _hex(List<int> b) {
  const d = '0123456789abcdef';
  final sb = StringBuffer();
  for (final x in b) {
    sb
      ..write(d[x >> 4])
      ..write(d[x & 15]);
  }
  return sb.toString();
}

/// `Buffer.from(texto, 'hex')` do Node: lê pares até o primeiro inválido.
Uint8List hexLeniente(String s) {
  final out = <int>[];
  for (var i = 0; i + 1 < s.length; i += 2) {
    final a = int.tryParse(s[i], radix: 16), b = int.tryParse(s[i + 1], radix: 16);
    if (a == null || b == null) break;
    out.add(a * 16 + b);
  }
  return Uint8List.fromList(out);
}

/// Token de sessão/redefinição: 32 bytes aleatórios em hex.
String novoToken() => _hex(_bytesAleatorios(32));

/// SHA-256 em hex de `String(t)` (o banco guarda só o hash do token).
String hashToken(Object? t) => sha256.convert(utf8.encode(toStr(t))).toString();

/// `scrypt$salt$hash` de uma senha nova (salt aleatório de 16 bytes).
Future<String> hashSenha(Object? senha) async {
  final salt = _bytesAleatorios(16);
  final h = await scryptAsync(utf8.encode(toStr(senha)), salt, 64);
  return 'scrypt\$${_hex(salt)}\$${_hex(h)}';
}

/// Confere a senha com o hash gravado. Qualquer formato inválido é "não confere".
Future<bool> verificarSenha(Object? senha, Object? gravado) async {
  try {
    final partes = toStr(gravado).split(r'$');
    if (partes.length < 3 || partes[0] != 'scrypt') return false;
    final esperado = hexLeniente(partes[2]);
    final h = await scryptAsync(utf8.encode(toStr(senha)), hexLeniente(partes[1]), esperado.length);
    // comparação em tempo constante
    var dif = 0;
    for (var i = 0; i < esperado.length; i++) {
      dif |= h[i] ^ esperado[i];
    }
    return dif == 0;
  } catch (_) {
    return false;
  }
}

/// scrypt fora da thread principal: o servidor continua atendendo enquanto calcula.
Future<Uint8List> scryptAsync(List<int> senha, List<int> salt, int tamanho) {
  final s = Uint8List.fromList(senha), sl = Uint8List.fromList(salt);
  return Isolate.run(() => scrypt(s, sl, tamanho));
}

// ------------------------------------------------------------------ scrypt (RFC 7914)

Uint8List _pbkdf2Sha256(List<int> senha, List<int> salt, int tamanho) {
  final hmac = Hmac(sha256, senha);
  final out = Uint8List(tamanho);
  var pos = 0;
  for (var bloco = 1; pos < tamanho; bloco++) {
    final s = Uint8List(salt.length + 4)
      ..setAll(0, salt)
      ..[salt.length] = (bloco >> 24) & 0xff
      ..[salt.length + 1] = (bloco >> 16) & 0xff
      ..[salt.length + 2] = (bloco >> 8) & 0xff
      ..[salt.length + 3] = bloco & 0xff;
    // com 1 iteração, T = U1
    final u = hmac.convert(s).bytes;
    final n = min(u.length, tamanho - pos);
    out.setRange(pos, pos + n, u);
    pos += n;
  }
  return out;
}

/// scrypt(N=16384, r=8, p=1), idêntico ao `crypto.scryptSync` do Node.
Uint8List scrypt(Uint8List senha, Uint8List salt, int tamanho) {
  if (tamanho == 0) return Uint8List(0);
  const tamBloco = 128 * _r;
  final b = _pbkdf2Sha256(senha, salt, _p * tamBloco);
  final x = Uint32List(32 * _r);
  final v = Uint32List(32 * _r * _n);
  final xy = Uint32List(64 * _r);
  final bd = ByteData.sublistView(b);
  for (var i = 0; i < _p; i++) {
    for (var k = 0; k < 32 * _r; k++) {
      x[k] = bd.getUint32(i * tamBloco + k * 4, Endian.little);
    }
    _roMix(x, v, xy);
    for (var k = 0; k < 32 * _r; k++) {
      bd.setUint32(i * tamBloco + k * 4, x[k], Endian.little);
    }
  }
  return _pbkdf2Sha256(senha, b, tamanho);
}

void _roMix(Uint32List x, Uint32List v, Uint32List y) {
  const w = 32 * _r;
  for (var i = 0; i < _n; i++) {
    v.setRange(i * w, i * w + w, x);
    _blockMix(x, y);
  }
  for (var i = 0; i < _n; i++) {
    final j = x[w - 16] & (_n - 1);
    final base = j * w;
    for (var k = 0; k < w; k++) {
      x[k] ^= v[base + k];
    }
    _blockMix(x, y);
  }
}

final _t = Uint32List(16);

void _blockMix(Uint32List b, Uint32List y) {
  // X = B[2r-1]
  for (var k = 0; k < 16; k++) {
    _t[k] = b[(2 * _r - 1) * 16 + k];
  }
  for (var i = 0; i < 2 * _r; i++) {
    for (var k = 0; k < 16; k++) {
      _t[k] ^= b[i * 16 + k];
    }
    _salsa20_8(_t);
    // pares em Y[0..r-1], ímpares em Y[r..2r-1]
    final dest = ((i & 1) == 0 ? (i >> 1) : _r + (i >> 1)) * 16;
    for (var k = 0; k < 16; k++) {
      y[dest + k] = _t[k];
    }
  }
  b.setRange(0, 32 * _r, y);
}

int _rotl(int a, int n) => ((a << n) | (a >> (32 - n))) & 0xffffffff;

final _s = Uint32List(16);

void _salsa20_8(Uint32List b) {
  var x0 = b[0], x1 = b[1], x2 = b[2], x3 = b[3], x4 = b[4], x5 = b[5], x6 = b[6], x7 = b[7];
  var x8 = b[8], x9 = b[9], x10 = b[10], x11 = b[11], x12 = b[12], x13 = b[13], x14 = b[14], x15 = b[15];
  for (var i = 0; i < 8; i += 2) {
    x4 ^= _rotl((x0 + x12) & 0xffffffff, 7);
    x8 ^= _rotl((x4 + x0) & 0xffffffff, 9);
    x12 ^= _rotl((x8 + x4) & 0xffffffff, 13);
    x0 ^= _rotl((x12 + x8) & 0xffffffff, 18);
    x9 ^= _rotl((x5 + x1) & 0xffffffff, 7);
    x13 ^= _rotl((x9 + x5) & 0xffffffff, 9);
    x1 ^= _rotl((x13 + x9) & 0xffffffff, 13);
    x5 ^= _rotl((x1 + x13) & 0xffffffff, 18);
    x14 ^= _rotl((x10 + x6) & 0xffffffff, 7);
    x2 ^= _rotl((x14 + x10) & 0xffffffff, 9);
    x6 ^= _rotl((x2 + x14) & 0xffffffff, 13);
    x10 ^= _rotl((x6 + x2) & 0xffffffff, 18);
    x3 ^= _rotl((x15 + x11) & 0xffffffff, 7);
    x7 ^= _rotl((x3 + x15) & 0xffffffff, 9);
    x11 ^= _rotl((x7 + x3) & 0xffffffff, 13);
    x15 ^= _rotl((x11 + x7) & 0xffffffff, 18);
    x1 ^= _rotl((x0 + x3) & 0xffffffff, 7);
    x2 ^= _rotl((x1 + x0) & 0xffffffff, 9);
    x3 ^= _rotl((x2 + x1) & 0xffffffff, 13);
    x0 ^= _rotl((x3 + x2) & 0xffffffff, 18);
    x6 ^= _rotl((x5 + x4) & 0xffffffff, 7);
    x7 ^= _rotl((x6 + x5) & 0xffffffff, 9);
    x4 ^= _rotl((x7 + x6) & 0xffffffff, 13);
    x5 ^= _rotl((x4 + x7) & 0xffffffff, 18);
    x11 ^= _rotl((x10 + x9) & 0xffffffff, 7);
    x8 ^= _rotl((x11 + x10) & 0xffffffff, 9);
    x9 ^= _rotl((x8 + x11) & 0xffffffff, 13);
    x10 ^= _rotl((x9 + x8) & 0xffffffff, 18);
    x12 ^= _rotl((x15 + x14) & 0xffffffff, 7);
    x13 ^= _rotl((x12 + x15) & 0xffffffff, 9);
    x14 ^= _rotl((x13 + x12) & 0xffffffff, 13);
    x15 ^= _rotl((x14 + x13) & 0xffffffff, 18);
  }
  _s
    ..[0] = x0
    ..[1] = x1
    ..[2] = x2
    ..[3] = x3
    ..[4] = x4
    ..[5] = x5
    ..[6] = x6
    ..[7] = x7
    ..[8] = x8
    ..[9] = x9
    ..[10] = x10
    ..[11] = x11
    ..[12] = x12
    ..[13] = x13
    ..[14] = x14
    ..[15] = x15;
  for (var k = 0; k < 16; k++) {
    b[k] = (b[k] + _s[k]) & 0xffffffff;
  }
}
