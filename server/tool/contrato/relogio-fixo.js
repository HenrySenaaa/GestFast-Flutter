// relogio-fixo.js - Pré-carregado no servidor Node de referência (node -r) pelo harness de contrato.
// Congela Date no instante GESTFAST_AGORA_MS, o mesmo relógio fixo usado no servidor Dart.
const T = Number(process.env.GESTFAST_AGORA_MS);
if (!Number.isFinite(T)) throw new Error('GESTFAST_AGORA_MS não definido');
const Real = Date;
class DataFixa extends Real {
  constructor(...a) {
    if (a.length === 0) super(T);
    else super(...a);
  }
  static now() {
    return T;
  }
}
global.Date = DataFixa;
