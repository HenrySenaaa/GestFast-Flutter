// caminhos.dart - path.join / normalize / basename / extname do Node (v24, lib/path.js).
//
// A proteção dos arquivos estáticos ("o arquivo pedido está dentro da pasta do app?")
// depende de como o caminho é montado. Para dar exatamente o mesmo resultado do servidor
// Node, estas funções são uma tradução linha a linha das do Node, para Windows e POSIX.
import 'dart:io' show Platform;

const _barra = 0x2F, _contrabarra = 0x5C, _ponto = 0x2E, _doisPontos = 0x3A;

bool _sepWin(int c) => c == _barra || c == _contrabarra;
bool _sepPosix(int c) => c == _barra;
bool _raizDispositivo(int c) => (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

const _reservados = [
  'CON', 'PRN', 'AUX', 'NUL', //
  'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
  'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
  'COM\xb9', 'COM\xb2', 'COM\xb3',
  'LPT\xb9', 'LPT\xb2', 'LPT\xb3',
];

/// `slice` do JS (índices negativos contam do fim; nunca lança).
String _slice(String s, int ini, [int? fim]) {
  final n = s.length;
  var a = ini < 0 ? (n + ini).clamp(0, n) : ini.clamp(0, n);
  var b = fim == null ? n : (fim < 0 ? (n + fim).clamp(0, n) : fim.clamp(0, n));
  if (b < a) b = a;
  return s.substring(a, b);
}

bool _nomeReservado(String path, int indiceDoisPontos) =>
    _reservados.contains(_slice(path, 0, indiceDoisPontos).toUpperCase());

int _cc(String s, int i) => (i >= 0 && i < s.length) ? s.codeUnitAt(i) : -1; // NaN no JS

// Resolve . e .. num caminho.
String _normalizeString(String path, bool acimaDaRaiz, String sep, bool Function(int) ehSep) {
  var res = '';
  var ultimoSegmento = 0;
  var ultimaBarra = -1;
  var pontos = 0;
  var code = 0;
  for (var i = 0; i <= path.length; ++i) {
    if (i < path.length) {
      code = path.codeUnitAt(i);
    } else if (ehSep(code)) {
      break;
    } else {
      code = _barra;
    }

    if (ehSep(code)) {
      if (ultimaBarra == i - 1 || pontos == 1) {
        // nada
      } else if (pontos == 2) {
        if (res.length < 2 || ultimoSegmento != 2 || _cc(res, res.length - 1) != _ponto || _cc(res, res.length - 2) != _ponto) {
          if (res.length > 2) {
            final indice = res.length - ultimoSegmento - 1;
            if (indice == -1) {
              res = '';
              ultimoSegmento = 0;
            } else {
              res = _slice(res, 0, indice);
              ultimoSegmento = res.length - 1 - res.lastIndexOf(sep);
            }
            ultimaBarra = i;
            pontos = 0;
            continue;
          } else if (res.isNotEmpty) {
            res = '';
            ultimoSegmento = 0;
            ultimaBarra = i;
            pontos = 0;
            continue;
          }
        }
        if (acimaDaRaiz) {
          res += res.isNotEmpty ? '$sep..' : '..';
          ultimoSegmento = 2;
        }
      } else {
        if (res.isNotEmpty) {
          res += '$sep${_slice(path, ultimaBarra + 1, i)}';
        } else {
          res = _slice(path, ultimaBarra + 1, i);
        }
        ultimoSegmento = i - ultimaBarra - 1;
      }
      ultimaBarra = i;
      pontos = 0;
    } else if (code == _ponto && pontos != -1) {
      ++pontos;
    } else {
      pontos = -1;
    }
  }
  return res;
}

// ---------------------------------------------------------------- win32
String win32Normalize(String path) {
  final len = path.length;
  if (len == 0) return '.';
  var rootEnd = 0;
  String? device;
  var absoluto = false;
  final code = path.codeUnitAt(0);

  if (len == 1) return _sepPosix(code) ? r'\' : path;
  if (_sepWin(code)) {
    absoluto = true;
    if (_sepWin(path.codeUnitAt(1))) {
      var j = 2;
      var last = j;
      while (j < len && !_sepWin(path.codeUnitAt(j))) {
        j++;
      }
      if (j < len && j != last) {
        final firstPart = _slice(path, last, j);
        last = j;
        while (j < len && _sepWin(path.codeUnitAt(j))) {
          j++;
        }
        if (j < len && j != last) {
          last = j;
          while (j < len && !_sepWin(path.codeUnitAt(j))) {
            j++;
          }
          if (j == len || j != last) {
            if (firstPart == '.' || firstPart == '?') {
              device = '\\\\$firstPart';
              rootEnd = 4;
              final colonIndex = path.indexOf(':');
              final possivel = _slice(path, 4, colonIndex + 1);
              if (_nomeReservado(possivel, possivel.length - 1)) {
                device = '\\\\?\\$possivel';
                rootEnd = 4 + possivel.length;
              }
            } else if (j == len) {
              return '\\\\$firstPart\\${_slice(path, last)}\\';
            } else {
              device = '\\\\$firstPart\\${_slice(path, last, j)}';
              rootEnd = j;
            }
          }
        }
      }
    } else {
      rootEnd = 1;
    }
  } else {
    final colonIndex = path.indexOf(':');
    if (colonIndex > 0) {
      if (_raizDispositivo(code) && colonIndex == 1) {
        device = _slice(path, 0, 2);
        rootEnd = 2;
        if (len > 2 && _sepWin(path.codeUnitAt(2))) {
          absoluto = true;
          rootEnd = 3;
        }
      } else if (_nomeReservado(path, colonIndex)) {
        device = _slice(path, 0, colonIndex + 1);
        rootEnd = colonIndex + 1;
      }
    }
  }

  var tail = rootEnd < len ? _normalizeString(_slice(path, rootEnd), !absoluto, r'\', _sepWin) : '';
  if (tail.isEmpty && !absoluto) tail = '.';
  if (tail.isNotEmpty && _sepWin(path.codeUnitAt(len - 1))) tail += r'\';
  if (!absoluto && device == null && path.contains(':')) {
    // CVE-2024-36139
    if (tail.length >= 2 && _raizDispositivo(tail.codeUnitAt(0)) && tail.codeUnitAt(1) == _doisPontos) {
      return '.\\$tail';
    }
    var index = path.indexOf(':');
    do {
      if (index == len - 1 || _sepWin(path.codeUnitAt(index + 1))) return '.\\$tail';
    } while ((index = path.indexOf(':', index + 1)) != -1);
  }
  final colonIndex = path.indexOf(':');
  if (_nomeReservado(path, colonIndex)) return '.\\${device ?? ''}$tail';
  if (device == null) return absoluto ? '\\$tail' : tail;
  return absoluto ? '$device\\$tail' : '$device$tail';
}

String win32Join(List<String> args) {
  final partes = args.where((a) => a.isNotEmpty).toList();
  if (partes.isEmpty) return '.';
  final firstPart = partes.first;
  var joined = partes.join(r'\');
  var needsReplace = true;
  var slashCount = 0;
  if (_sepWin(firstPart.codeUnitAt(0))) {
    ++slashCount;
    final firstLen = firstPart.length;
    if (firstLen > 1 && _sepWin(firstPart.codeUnitAt(1))) {
      ++slashCount;
      if (firstLen > 2) {
        if (_sepWin(firstPart.codeUnitAt(2))) {
          ++slashCount;
        } else {
          needsReplace = false;
        }
      }
    }
  }
  if (needsReplace) {
    while (slashCount < joined.length && _sepWin(joined.codeUnitAt(slashCount))) {
      slashCount++;
    }
    if (slashCount >= 2) joined = '\\${_slice(joined, slashCount)}';
  }
  // Sem normalização quando há nomes de dispositivo reservados.
  final parts = <String>[];
  var part = '';
  for (var i = 0; i < joined.length; i++) {
    if (joined[i] == r'\') {
      if (part.isNotEmpty) parts.add(part);
      part = '';
      while (i + 1 < joined.length && joined[i + 1] == r'\') {
        i++;
      }
    } else {
      part += joined[i];
    }
  }
  if (part.isNotEmpty) parts.add(part);
  if (parts.any((p) {
    final ci = p.indexOf(':');
    return ci != -1 && _nomeReservado(p, ci);
  })) {
    return joined.replaceAll('/', r'\');
  }
  return win32Normalize(joined);
}

String win32Basename(String path) {
  var start = 0;
  var end = -1;
  var matchedSlash = true;
  if (path.length >= 2 && _raizDispositivo(path.codeUnitAt(0)) && path.codeUnitAt(1) == _doisPontos) start = 2;
  for (var i = path.length - 1; i >= start; --i) {
    if (_sepWin(path.codeUnitAt(i))) {
      if (!matchedSlash) {
        start = i + 1;
        break;
      }
    } else if (end == -1) {
      matchedSlash = false;
      end = i + 1;
    }
  }
  if (end == -1) return '';
  return _slice(path, start, end);
}

String _extname(String path, bool Function(int) ehSep, bool win) {
  var start = 0;
  var startDot = -1;
  var startPart = 0;
  var end = -1;
  var matchedSlash = true;
  var preDotState = 0;
  if (win && path.length >= 2 && path.codeUnitAt(1) == _doisPontos && _raizDispositivo(path.codeUnitAt(0))) {
    start = startPart = 2;
  }
  for (var i = path.length - 1; i >= start; --i) {
    final code = path.codeUnitAt(i);
    if (ehSep(code)) {
      if (!matchedSlash) {
        startPart = i + 1;
        break;
      }
      continue;
    }
    if (end == -1) {
      matchedSlash = false;
      end = i + 1;
    }
    if (code == _ponto) {
      if (startDot == -1) {
        startDot = i;
      } else if (preDotState != 1) {
        preDotState = 1;
      }
    } else if (startDot != -1) {
      preDotState = -1;
    }
  }
  if (startDot == -1 || end == -1 || preDotState == 0 || (preDotState == 1 && startDot == end - 1 && startDot == startPart + 1)) {
    return '';
  }
  return _slice(path, startDot, end);
}

String win32Extname(String path) => _extname(path, _sepWin, true);

// ---------------------------------------------------------------- posix
String posixNormalize(String path) {
  if (path.isEmpty) return '.';
  final absoluto = path.codeUnitAt(0) == _barra;
  final barraFinal = path.codeUnitAt(path.length - 1) == _barra;
  var p = _normalizeString(path, !absoluto, '/', _sepPosix);
  if (p.isEmpty) {
    if (absoluto) return '/';
    return barraFinal ? './' : '.';
  }
  if (barraFinal) p += '/';
  return absoluto ? '/$p' : p;
}

String posixJoin(List<String> args) {
  final partes = args.where((a) => a.isNotEmpty).toList();
  if (partes.isEmpty) return '.';
  return posixNormalize(partes.join('/'));
}

String posixBasename(String path) {
  var start = 0;
  var end = -1;
  var matchedSlash = true;
  for (var i = path.length - 1; i >= 0; --i) {
    if (path.codeUnitAt(i) == _barra) {
      if (!matchedSlash) {
        start = i + 1;
        break;
      }
    } else if (end == -1) {
      matchedSlash = false;
      end = i + 1;
    }
  }
  if (end == -1) return '';
  return _slice(path, start, end);
}

String posixExtname(String path) => _extname(path, _sepPosix, false);

// ---------------------------------------------------------------- da plataforma atual
/// Funções `path` do Node para a plataforma em que o servidor roda.
class CaminhosNode {
  const CaminhosNode({required this.windows});
  factory CaminhosNode.daPlataforma() => CaminhosNode(windows: Platform.isWindows);

  final bool windows;
  String get sep => windows ? r'\' : '/';
  String join(List<String> partes) => windows ? win32Join(partes) : posixJoin(partes);
  String normalize(String p) => windows ? win32Normalize(p) : posixNormalize(p);
  String basename(String p) => windows ? win32Basename(p) : posixBasename(p);
  String extname(String p) => windows ? win32Extname(p) : posixExtname(p);
}
