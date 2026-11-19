// gateways.dart - Integrações externas simuladas (operadora de cartão e API do fornecedor).
import 'erros.dart';
import 'js.dart';

class Autorizacao {
  Autorizacao(this.nsu);
  final String nsu;
}

Autorizacao autorizarPagamento(Object? forma, Map<String, Object?> cfg) {
  if (toStr(forma).startsWith('Cartão') && cfg['simularCartaoNegado'] == true) {
    throw HttpErro(402, 'Transação Negada pela Operadora');
  }
  final ms = DateTime.now().millisecondsSinceEpoch.toString();
  return Autorizacao(ms.substring(ms.length - 8));
}

void comunicarFornecedor(Map<String, Object?> cfg) {
  if (cfg['simularFornecedorIndisponivel'] == true) {
    throw HttpErro(503, 'Falha de comunicação com o sistema do fornecedor, tente novamente mais tarde.');
  }
}
