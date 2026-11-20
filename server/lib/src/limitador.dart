// limitador.dart - Limite de tentativas (login e senha de gerente), com limpeza de entradas antigas.
import 'erros.dart';

class _Entrada {
  _Entrada(this.ultima);
  int n = 0;
  int ate = 0;

  /// Tentativas em andamento (a senha ainda está sendo conferida).
  int pendentes = 0;
  int ultima;
}

class Limitador {
  Limitador({this.max = 5, this.bloqueioMs = 60000, this.janelaMs = 15 * 60000, int Function()? relogio})
      : _relogio = relogio ?? (() => DateTime.now().millisecondsSinceEpoch);

  final int max, bloqueioMs, janelaMs;
  final int Function() _relogio;
  final _entradas = <String, _Entrada>{};

  void _limpar(int agora) =>
      _entradas.removeWhere((_, t) => t.pendentes == 0 && t.ate <= agora && t.ultima + janelaMs <= agora);

  /// Lança 429 enquanto a chave estiver bloqueada.
  void checar(String chave) {
    final t = _entradas[chave];
    final agora = _relogio();
    if (t != null && t.ate > agora) {
      throw HttpErro(429, 'Muitas tentativas. Aguarde ${((t.ate - agora) / 1000).ceil()}s para tentar novamente.');
    }
  }

  /// [checar] e reserva a tentativa: com [max] tentativas já em andamento na mesma chave,
  /// as seguintes recebem 429. Sem a reserva, requisições paralelas passavam todas pelo
  /// [checar] antes da primeira falha ser contada. Chame [encerrar] ao fim, com ou sem erro.
  void iniciar(String chave) {
    checar(chave);
    final agora = _relogio();
    final t = _entradas[chave] ?? _Entrada(agora);
    if (t.n + t.pendentes >= max) {
      throw HttpErro(429, 'Muitas tentativas. Aguarde alguns segundos para tentar novamente.');
    }
    t.pendentes++;
    _entradas[chave] = t;
  }

  /// Libera a reserva feita por [iniciar].
  void encerrar(String chave) {
    final t = _entradas[chave];
    if (t != null && t.pendentes > 0) t.pendentes--;
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

  void sucesso(String chave) {
    final t = _entradas[chave];
    if (t == null) return;
    if (t.pendentes > 0) {
      // Outras tentativas paralelas ainda estão em andamento: zera as falhas e mantém a reserva delas.
      t
        ..n = 0
        ..ate = 0;
    } else {
      _entradas.remove(chave);
    }
  }

  int get tamanho => _entradas.length;
}
