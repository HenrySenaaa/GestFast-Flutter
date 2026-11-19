// limitador.dart - Limite de tentativas (login e senha de gerente), com limpeza de entradas antigas.
import 'erros.dart';

class _Entrada {
  _Entrada(this.ultima);
  int n = 0;
  int ate = 0;
  int ultima;
}

class Limitador {
  Limitador({this.max = 5, this.bloqueioMs = 60000, this.janelaMs = 15 * 60000, int Function()? relogio})
      : _relogio = relogio ?? (() => DateTime.now().millisecondsSinceEpoch);

  final int max, bloqueioMs, janelaMs;
  final int Function() _relogio;
  final _entradas = <String, _Entrada>{};

  void _limpar(int agora) =>
      _entradas.removeWhere((_, t) => t.ate <= agora && t.ultima + janelaMs <= agora);

  /// Lança 429 enquanto a chave estiver bloqueada.
  void checar(String chave) {
    final t = _entradas[chave];
    final agora = _relogio();
    if (t != null && t.ate > agora) {
      throw HttpErro(429, 'Muitas tentativas. Aguarde ${((t.ate - agora) / 1000).ceil()}s para tentar novamente.');
    }
  }

  void falhou(String chave) {
    final agora = _relogio();
    _limpar(agora);
    final t = _entradas[chave] ?? _Entrada(agora);
    t.n++;
    t.ultima = agora;
    if (t.n >= max) {
      t.ate = agora + bloqueioMs;
      t.n = 0;
    }
    _entradas[chave] = t;
  }

  void sucesso(String chave) => _entradas.remove(chave);

  int get tamanho => _entradas.length;
}
