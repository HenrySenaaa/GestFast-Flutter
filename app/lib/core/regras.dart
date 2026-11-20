// Formatação pt-BR e regras de negócio usadas nas telas. O servidor valida de novo tudo o que importa.
import 'package:intl/intl.dart';

final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _num2 = NumberFormat('#,##0.00', 'pt_BR');
final _qtd = NumberFormat('#,##0.###', 'pt_BR');

double numero(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.replaceAll(',', '.')) ?? 0;
  return 0;
}

String dinheiro(dynamic n) => _moeda.format(numero(n)).replaceAll(' ', ' ');
String num2(dynamic n) => _num2.format(numero(n));
String quantidade(dynamic n) => _qtd.format(numero(n));

double r2(num n) => ((n + 2.220446049250313e-16) * 100).round() / 100;
double r3(num n) => ((n + 2.220446049250313e-16) * 1000).round() / 1000;

/// Texto digitado para número: aceita vírgula ou ponto. Devolve null se não for número.
double? lerNumero(String texto) {
  final t = texto.trim().replaceAll(' ', '');
  if (t.isEmpty) return null;
  // "1.234,56" -> ponto é separador de milhar quando também há vírgula.
  final normal = t.contains(',') ? t.replaceAll('.', '').replaceAll(',', '.') : t;
  final v = double.tryParse(normal);
  return v != null && v.isFinite ? v : null;
}

/// 'AAAA-MM-DD' ou 'AAAA-MM-DD HH:MM' -> 'DD/MM/AAAA' (mantém a hora).
String dataBR(String? s) {
  if (s == null || s.isEmpty) return '-';
  final partes = s.split(' ');
  final d = partes[0].split('-');
  if (d.length != 3) return s;
  final hora = partes.length > 1 ? ' ${partes[1]}' : '';
  return '${d[2]}/${d[1]}/${d[0]}$hora';
}

String dataISO(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? lerDataISO(String? s) {
  if (s == null || s.length < 10) return null;
  final p = s.substring(0, 10).split('-');
  if (p.length != 3) return null;
  final a = int.tryParse(p[0]), m = int.tryParse(p[1]), d = int.tryParse(p[2]);
  if (a == null || m == null || d == null) return null;
  return DateTime.utc(a, m, d);
}

/// Data 'AAAA-MM-DD' como meia-noite LOCAL (para calendários). Não use lerDataISO(...).toLocal():
/// em UTC-3 a meia-noite UTC vira 21h do dia anterior e o calendário ofereceria ontem.
DateTime? dataLocal(String? s) {
  final d = lerDataISO(s);
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

/// Soma dias a uma data 'AAAA-MM-DD' (a referência é a data do servidor, não a do aparelho).
String somarDias(String iso, int dias) {
  final d = lerDataISO(iso) ?? DateTime.now().toUtc();
  return dataISO(d.add(Duration(days: dias)));
}

/// KG e Lt aceitam fração; UN, Pacote, DZ e Fatia só aceitam inteiros.
bool aceitaFracao(String? unidade) => const ['kg', 'lt', 'l'].contains((unidade ?? '').toLowerCase());

/// Mensagem de erro da quantidade, ou null se estiver certa.
String? erroQuantidade(String? unidade, double? q, {String nome = 'Este produto', bool aceitaZero = false}) {
  if (q == null || q < 0 || (!aceitaZero && r3(q) <= 0)) {
    return aceitaZero ? 'Informe zero ou mais.' : 'Informe uma quantidade maior que zero.';
  }
  if (!aceitaFracao(unidade) && q != q.roundToDouble()) {
    return '$nome é controlado em ${unidade ?? 'UN'} e só aceita quantidades inteiras.';
  }
  return null;
}

class SituacaoValidade {
  const SituacaoValidade(this.dias, this.alerta);
  final int dias;
  final bool alerta;
  bool get vencido => dias < 0;
  String get texto => dias < 0
      ? 'Vencido há ${-dias} dia(s)'
      : dias == 0
          ? 'Vence hoje'
          : 'Vence em $dias dia(s)';
}

SituacaoValidade? situacaoValidade(String? validade, String? hoje, int limiteDias) {
  final v = lerDataISO(validade);
  final h = lerDataISO(hoje);
  if (v == null || h == null) return null;
  final dias = v.difference(h).inDays;
  return SituacaoValidade(dias, dias <= limiteDias);
}

const unidades = ['UN', 'KG', 'Pacote', 'DZ', 'Fatia', 'Lt'];
const formasPagamento = ['Dinheiro', 'Cartão Débito', 'Cartão Crédito', 'PIX'];
const motivosPerda = ['Vencido', 'Quebra/Avaria', 'Sobra do dia', 'Outro'];
const situacoesAbertas = ['Em Aberto', 'Cotado', 'AF Gerada'];

String nomePerfil(String? p) => p == 'Funcionario' ? 'Funcionário' : (p ?? '-');
String semAcento(String s) {
  const de = 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ';
  const para = 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC';
  final b = StringBuffer();
  for (final c in s.split('')) {
    final i = de.indexOf(c);
    b.write(i >= 0 ? para[i] : c);
  }
  return b.toString().toLowerCase();
}

/// Endereço do servidor: HTTPS em qualquer lugar; HTTP só na rede local (senha não trafega aberta na internet).
/// Devolve o endereço normalizado (sem barra no fim) ou lança FormatException com a mensagem.
String validarServidor(String texto) {
  var t = texto.trim();
  if (t.isEmpty) throw const FormatException('Informe o endereço do servidor.');
  if (!t.contains('://')) t = 'http://$t';
  final u = Uri.tryParse(t);
  if (u == null || u.host.isEmpty || !(u.scheme == 'http' || u.scheme == 'https')) {
    throw const FormatException('Endereço inválido. Exemplo: http://192.168.0.10:3000');
  }
  if (u.scheme == 'http' && !hostLocal(u.host)) {
    throw const FormatException('Fora da rede local, o servidor precisa usar https://.');
  }
  final porta = u.hasPort ? ':${u.port}' : '';
  final host = u.host.contains(':') ? '[${u.host}]' : u.host;
  return '${u.scheme}://$host$porta';
}

bool hostLocal(String host) {
  final h = host.toLowerCase();
  if (h == 'localhost' || h == '::1' || h.endsWith('.local')) return true;
  final p = h.split('.').map(int.tryParse).toList();
  if (p.length != 4 || p.any((x) => x == null || x < 0 || x > 255)) return false;
  final a = p[0]!, b = p[1]!;
  return a == 127 || a == 10 || (a == 192 && b == 168) || (a == 172 && b >= 16 && b <= 31) || (a == 169 && b == 254);
}
