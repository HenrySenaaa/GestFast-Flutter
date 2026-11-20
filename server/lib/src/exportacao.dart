// exportacao.dart - Exportação de relatórios em XLSX e PDF (RF 14), sem dependências externas.
// Tradução direta do lib/export.js do servidor Node: os arquivos saem com o mesmo conteúdo.
import 'dart:convert';
import 'dart:io' show ZLibEncoder;
import 'dart:typed_data';

import 'js.dart';
import 'largura_nfd.dart';

/// Uma linha de tabela; [negrito] corresponde ao `__bold` do Node.
class Linha {
  Linha(this.celulas, {this.negrito = false});
  final List<Object?> celulas;
  final bool negrito;
  Object? operator [](int i) => i < celulas.length ? celulas[i] : undefined;
}

class ColunaPlanilha {
  const ColunaPlanilha(this.label, this.width, [this.fmt]);
  final String label;
  final num width;
  final String? fmt;
}

class Planilha {
  Planilha({required this.name, this.title, this.subtitle, required this.columns, required this.rows});
  final String? name;
  final String? title;
  final String? subtitle;
  final List<ColunaPlanilha> columns;
  final List<Linha> rows;
}

class ColunaPdf {
  const ColunaPdf(this.label, this.w, [this.align]);
  final String label;
  final num w;
  final String? align;
}

class SecaoPdf {
  SecaoPdf({this.heading, required this.columns, required this.rows});
  final String? heading;
  final List<ColunaPdf> columns;
  final List<Linha> rows;
}

// ---------------------------------------------------------------- ZIP / XLSX
final Uint32List _crcTabela = () {
  final t = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
    }
    t[n] = c;
  }
  return t;
}();

int _crc32(List<int> buf) {
  var c = 0xffffffff;
  for (final b in buf) {
    c = _crcTabela[(c ^ b) & 0xff] ^ (c >> 8);
  }
  return (c ^ 0xffffffff) & 0xffffffff;
}

Uint8List _zip(List<(String, String)> arquivos) {
  final saida = BytesBuilder(copy: false);
  final centrais = BytesBuilder(copy: false);
  var offset = 0;
  for (final (nomeTxt, dadosTxt) in arquivos) {
    final nome = utf8.encode(nomeTxt);
    final dados = utf8.encode(dadosTxt);
    final comp = ZLibEncoder(raw: true, level: 6).convert(dados);
    final crc = _crc32(dados);
    final lh = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 0x0800, Endian.little)
      ..setUint16(8, 8, Endian.little)
      ..setUint16(10, 0, Endian.little)
      ..setUint16(12, 0x21, Endian.little)
      ..setUint32(14, crc, Endian.little)
      ..setUint32(18, comp.length, Endian.little)
      ..setUint32(22, dados.length, Endian.little)
      ..setUint16(26, nome.length, Endian.little)
      ..setUint16(28, 0, Endian.little);
    saida
      ..add(lh.buffer.asUint8List())
      ..add(nome)
      ..add(comp);
    final ch = ByteData(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 20, Endian.little)
      ..setUint16(8, 0x0800, Endian.little)
      ..setUint16(10, 8, Endian.little)
      ..setUint16(12, 0, Endian.little)
      ..setUint16(14, 0x21, Endian.little)
      ..setUint32(16, crc, Endian.little)
      ..setUint32(20, comp.length, Endian.little)
      ..setUint32(24, dados.length, Endian.little)
      ..setUint16(28, nome.length, Endian.little)
      ..setUint32(42, offset, Endian.little);
    centrais
      ..add(ch.buffer.asUint8List())
      ..add(nome);
    offset += 30 + nome.length + comp.length;
  }
  final cd = centrais.takeBytes();
  final fim = ByteData(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, arquivos.length, Endian.little)
    ..setUint16(10, arquivos.length, Endian.little)
    ..setUint32(12, cd.length, Endian.little)
    ..setUint32(16, offset, Endian.little);
  saida
    ..add(cd)
    ..add(fim.buffer.asUint8List());
  return saida.takeBytes();
}

final _xmlEspecial = RegExp(r'''[<>&"']''');
final _xmlControle = RegExp('[\u0000-\u0008\u000b\u000c\u000e-\u001f]');

String _xmlEsc(Object? s) => toStr(s)
    .replaceAllMapped(_xmlEspecial, (m) => const {'<': '&lt;', '>': '&gt;', '&': '&amp;', '"': '&quot;', "'": '&apos;'}[m[0]]!)
    .replaceAll(_xmlControle, '');

String _colLetra(int i) {
  var s = '';
  for (i++; i > 0; i = (i - 1) ~/ 26) {
    s = String.fromCharCode(65 + ((i - 1) % 26)) + s;
  }
  return s;
}

// estilos: 0 padrão, 1 cabeçalho, 2 moeda, 3 inteiro, 4 decimal, 5 título, 6 negrito
const _estiloFmt = {'money': 2, 'int': 3, 'dec': 4};

String _cel(int c, int ri, Object? v, int s) {
  if (v is num && v.isFinite) return '<c r="${_colLetra(c)}$ri" s="$s"><v>${numStr(v)}</v></c>';
  final est = (s == 2 || s == 3 || s == 4) ? 0 : s;
  return '<c r="${_colLetra(c)}$ri" s="$est" t="inlineStr"><is><t xml:space="preserve">${_xmlEsc(isNullish(v) ? '' : v)}</t></is></c>';
}

String _sheetXml(Planilha sheet) {
  var r = 1;
  final linhas = <String>[];
  if (truthy(sheet.title)) {
    linhas.add('<row r="$r">${_cel(0, r, sheet.title, 5)}</row>');
    r++;
  }
  if (truthy(sheet.subtitle)) {
    linhas.add('<row r="$r">${_cel(0, r, sheet.subtitle, 0)}</row>');
    r++;
  }
  if (truthy(sheet.title) || truthy(sheet.subtitle)) r++;
  final hdr = r;
  final cols = sheet.columns;
  linhas.add('<row r="$r">${[for (var i = 0; i < cols.length; i++) _cel(i, r, cols[i].label, 1)].join()}</row>');
  r++;
  for (final row in sheet.rows) {
    linhas.add('<row r="$r">${[
      for (var i = 0; i < cols.length; i++) _cel(i, r, row[i], row.negrito ? 6 : (_estiloFmt[cols[i].fmt] ?? 0)),
    ].join()}</row>');
    r++;
  }
  final colsXml = [
    for (var i = 0; i < cols.length; i++)
      '<col min="${i + 1}" max="${i + 1}" width="${numStr(cols[i].width == 0 ? 16 : cols[i].width)}" customWidth="1"/>',
  ].join();
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0"><pane ySplit="$hdr" topLeftCell="A${hdr + 1}" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols>$colsXml</cols><sheetData>${linhas.join()}</sheetData></worksheet>';
}

final _nomeInvalido = RegExp(r'[\\/?*[\]:]');

Uint8List gerarXlsx(List<Planilha> sheets) {
  final nomes = [
    for (var i = 0; i < sheets.length; i++)
      _xmlEsc(sliceStr((truthy(sheets[i].name) ? sheets[i].name! : 'Planilha${i + 1}').replaceAll(_nomeInvalido, ' '), 31)),
  ];
  final n = sheets.length;
  final arquivos = <(String, String)>[
    (
      '[Content_Types].xml',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>${[for (var i = 0; i < n; i++) '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}</Types>',
    ),
    (
      '_rels/.rels',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
    ),
    (
      'xl/workbook.xml',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>${[for (var i = 0; i < n; i++) '<sheet name="${nomes[i]}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}</sheets></workbook>',
    ),
    (
      'xl/_rels/workbook.xml.rels',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${[for (var i = 0; i < n; i++) '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>'].join()}<Relationship Id="rId${n + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>',
    ),
    (
      'xl/styles.xml',
      r'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="2"><numFmt numFmtId="164" formatCode="&quot;R$&quot;\ #,##0.00"/><numFmt numFmtId="165" formatCode="#,##0.###"/></numFmts><fonts count="4"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font><font><b/><sz val="14"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF1F2429"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="7"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/><xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="1" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>',
    ),
    for (var i = 0; i < n; i++) ('xl/worksheets/sheet${i + 1}.xml', _sheetXml(sheets[i])),
  ];
  return _zip(arquivos);
}

// ---------------------------------------------------------------- PDF
const _helv = [
  278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278, 556, 556, 556, 556, 556, 556, 556, //
  556, 556, 556, 278, 278, 584, 584, 584, 556, 1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833,
  722, 778, 667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556, 333, 556, 556, 500, 556,
  556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556, 556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334,
  260, 334, 584,
];

/// Largura de um caractere depois do NFD sem acentos (ver largura_nfd.dart).
int _larguraCodigo(int cp) {
  var lo = 0, hi = faixasNfd.length ~/ 3 - 1;
  while (lo <= hi) {
    final m = (lo + hi) >> 1;
    if (cp < faixasNfd[m * 3]) {
      hi = m - 1;
    } else if (cp > faixasNfd[m * 3 + 1]) {
      lo = m + 1;
    } else {
      return faixasNfd[m * 3 + 2];
    }
  }
  return (cp >= 32 && cp <= 126) ? _helv[cp - 32] : 556;
}

double _largura(Object? texto, num size, bool bold) {
  var w = 0;
  for (final cp in toStr(texto).runes) {
    w += _larguraCodigo(cp);
  }
  return (w / 1000) * size * (bold ? 1.07 : 1);
}

String _cortar(Object? texto, num max, num size, bool bold) {
  var t = isNullish(texto) ? '' : toStr(texto);
  if (_largura(t, size, bold) <= max) return t;
  while (t.length > 1 && _largura('$t...', size, bold) > max) {
    t = t.substring(0, t.length - 1);
  }
  return '$t...';
}

String _pdfStr(Object? s) {
  final sb = StringBuffer();
  for (final u in toStr(s).codeUnits) {
    final b = u > 0xff ? 0x3f : u; // '?' para fora do latin1
    if (b == 0x28 || b == 0x29 || b == 0x5c) {
      sb
        ..write(r'\')
        ..writeCharCode(b);
    } else if (b < 32 || b > 126) {
      sb.write('\\${b.toRadixString(8).padLeft(3, '0')}');
    } else {
      sb.writeCharCode(b);
    }
  }
  return sb.toString();
}

String _f2(num x) => toFixed(x.toDouble(), 2);

Uint8List gerarPdf({
  required String title,
  required Object? subtitle,
  required List<SecaoPdf> sections,
  String footer = 'GestFast',
  bool landscape = false,
}) {
  final pw = landscape ? 842 : 595, ph = landscape ? 595 : 842;
  const m = 36;
  final paginas = <String>[];
  var ops = <String>[];
  double y = 0;
  void nova() {
    if (ops.isNotEmpty) paginas.add(ops.join('\n'));
    ops = [];
    y = (ph - m).toDouble();
  }

  void txt(num x, num yy, Object? s, [num size = 9, bool bold = false, String cor = '0 0 0']) =>
      ops.add('BT $cor rg /${bold ? 'F2' : 'F1'} ${numStr(size)} Tf ${_f2(x)} ${_f2(yy)} Td (${_pdfStr(s)}) Tj ET');
  void rect(num x, num yy, num w, num h, String cor) => ops.add('$cor rg ${_f2(x)} ${_f2(yy)} ${_f2(w)} ${_f2(h)} re f');

  nova();
  rect(0, ph - 56, pw, 56, '0.122 0.141 0.161');
  txt(m, ph - 28, 'GEST', 18, true, '1 1 1');
  txt(m + 46, ph - 28, 'FAST#', 18, true, '0.976 0.451 0.086');
  txt(m, ph - 46, title, 11, false, '0.9 0.9 0.9');
  y = (ph - 56 - 22).toDouble();
  if (truthy(subtitle)) {
    for (final l in (subtitle is List ? subtitle : [subtitle])) {
      txt(m, y, _cortar(l, pw - 2 * m, 9, false), 9, false, '0.3 0.3 0.3');
      y -= 13;
    }
  }
  y -= 6;
  for (final sec in sections) {
    final usable = pw - 2 * m;
    final soma = sec.columns.fold<num>(0, (a, c) => a + (c.w == 0 ? 1 : c.w));
    final larguras = [for (final c in sec.columns) usable * (c.w == 0 ? 1 : c.w) / soma];
    void cabecalho() {
      rect(m, y - 4, usable, 16, '0.122 0.141 0.161');
      num x = m;
      for (var i = 0; i < sec.columns.length; i++) {
        final c = sec.columns[i];
        final t = _cortar(c.label, larguras[i] - 8, 8, true);
        txt(c.align == 'right' ? x + larguras[i] - 4 - _largura(t, 8, true) : x + 4, y, t, 8, true, '1 1 1');
        x += larguras[i];
      }
      y -= 18;
    }

    if (y < 90) nova();
    if (truthy(sec.heading)) {
      txt(m, y, sec.heading, 11, true);
      y -= 16;
    }
    cabecalho();
    for (var ri = 0; ri < sec.rows.length; ri++) {
      final row = sec.rows[ri];
      if (y < m + 30) {
        nova();
        y = (ph - m).toDouble();
        cabecalho();
      }
      if (ri % 2 == 0) rect(m, y - 4, usable, 14, '0.955 0.955 0.965');
      num x = m;
      for (var i = 0; i < sec.columns.length; i++) {
        final c = sec.columns[i];
        final bold = row.negrito;
        final v = row[i];
        final t = _cortar(isNullish(v) ? '' : v, larguras[i] - 8, 8, bold);
        txt(c.align == 'right' ? x + larguras[i] - 4 - _largura(t, 8, bold) : x + 4, y, t, 8, bold);
        x += larguras[i];
      }
      y -= 14;
    }
    if (sec.rows.isEmpty) {
      txt(m + 4, y, 'Nenhum registro.', 8);
      y -= 14;
    }
    y -= 14;
  }
  paginas.add(ops.join('\n'));
  final total = paginas.length;
  final conteudos = [
    for (var i = 0; i < total; i++)
      '${paginas[i]}\nBT 0.4 0.4 0.4 rg /F1 8 Tf $m 20 Td (${_pdfStr(footer)}) Tj ET\nBT 0.4 0.4 0.4 rg /F1 8 Tf ${pw - m - 60} 20 Td (${_pdfStr('Página ${i + 1} de $total')}) Tj ET',
  ];

  final objs = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [${[for (var i = 0; i < total; i++) '${5 + i * 2} 0 R'].join(' ')}] /Count $total >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>',
  ];
  for (var i = 0; i < total; i++) {
    final c = conteudos[i];
    objs
      ..add(
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $pw $ph] /Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents ${6 + i * 2} 0 R >>',
      )
      ..add('<< /Length ${c.length} >>\nstream\n$c\nendstream');
  }
  final out = StringBuffer('%PDF-1.4\n');
  final offs = <int>[];
  for (var i = 0; i < objs.length; i++) {
    offs.add(out.length);
    out.write('${i + 1} 0 obj\n${objs[i]}\nendobj\n');
  }
  final xref = out.length;
  out.write(
    'xref\n0 ${objs.length + 1}\n0000000000 65535 f \n${offs.map((o) => '${o.toString().padLeft(10, '0')} 00000 n \n').join()}trailer\n<< /Size ${objs.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF',
  );
  return latin1.encode(out.toString());
}
