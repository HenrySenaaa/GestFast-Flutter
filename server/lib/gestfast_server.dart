/// Servidor HTTP/JSON do GestFast ERP.
library;

export 'src/banco.dart' show Banco, Executor, Registro, Resultado, Transacao;
export 'src/config.dart' show Config, lerDotenv, pastaDoServidor;
export 'src/dados.dart' show Dados, Obj, mensagemDe;
export 'src/erros.dart' show HttpErro, erro;
export 'src/limitador.dart' show Limitador;
export 'src/logger.dart' show Logger;
export 'src/relogio.dart' show Relogio;
export 'src/servidor.dart' show Servidor;
