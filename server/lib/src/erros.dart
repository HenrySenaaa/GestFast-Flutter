// erros.dart - Erros de regra com código HTTP (a mensagem vai para o cliente).

class HttpErro implements Exception {
  HttpErro(this.status, this.mensagem);
  final int status;
  final String mensagem;
  @override
  String toString() => 'HttpErro($status): $mensagem';
}

/// `erro(msg, status = 400)` do backend original.
HttpErro erro(String msg, [int status = 400]) => HttpErro(status, msg);
