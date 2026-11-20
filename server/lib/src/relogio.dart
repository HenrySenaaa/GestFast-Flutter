// relogio.dart - Data e hora locais no fuso configurado (TZ, padrão America/Sao_Paulo).
//
// O Node usava a variável TZ do processo para todas as datas "locais" (data das vendas,
// "hoje", validade). Aqui o fuso vem da base IANA embutida no pacote timezone, então o
// resultado não depende do fuso do Windows. Fuso desconhecido cai em UTC, como no Node.
import 'package:timezone/data/latest_all.dart' as tzdados;
import 'package:timezone/timezone.dart' as tz;

String _p2(int n) => n.toString().padLeft(2, '0');

class Relogio {
  Relogio(String nomeFuso, {int Function()? agora}) : _agora = agora ?? (() => DateTime.now().millisecondsSinceEpoch) {
    if (!_iniciado) {
      tzdados.initializeTimeZones();
      _iniciado = true;
    }
    final nome = nomeFuso.startsWith(':') ? nomeFuso.substring(1) : nomeFuso;
    tz.Location f;
    try {
      f = (nome == 'UTC' || nome == 'GMT') ? tz.UTC : tz.getLocation(nome);
    } catch (_) {
      f = tz.UTC;
    }
    fuso = f;
  }

  static bool _iniciado = false;
  late final tz.Location fuso;
  final int Function() _agora;

  /// `Date.now()`
  int agoraMs() => _agora();

  tz.TZDateTime _local(int ms) => tz.TZDateTime.fromMillisecondsSinceEpoch(fuso, ms);

  /// AAAA-MM-DD local (`dataISO` do db.js).
  String dataISO([int? ms]) {
    final d = _local(ms ?? agoraMs());
    return '${d.year}-${_p2(d.month)}-${_p2(d.day)}';
  }

  /// AAAA-MM-DD HH:MM local (`dataHora` do db.js).
  String dataHora([int? ms]) {
    final d = _local(ms ?? agoraMs());
    return '${d.year}-${_p2(d.month)}-${_p2(d.day)} ${_p2(d.hour)}:${_p2(d.minute)}';
  }

  /// `deslocar(dias, minutos)`: agora + dias/minutos, em milissegundos.
  int deslocar(num dias, [num minutos = 0]) => (agoraMs() + dias * 86400000 + minutos * 60000).toInt();

  /// `new Date().toISOString()` (sempre UTC, com milissegundos).
  String isoUtc([int? ms]) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms ?? agoraMs(), isUtc: true);
    return '${d.year.toString().padLeft(4, '0')}-${_p2(d.month)}-${_p2(d.day)}T${_p2(d.hour)}:${_p2(d.minute)}:${_p2(d.second)}.${d.millisecond.toString().padLeft(3, '0')}Z';
  }
}
