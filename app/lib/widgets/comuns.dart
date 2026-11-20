// Componentes de interface: cada um reproduz uma classe do style.css do GestFast v1.
import 'dart:async';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/regras.dart';
import '../core/tema.dart';

// ---------------------------------------------------------------- toast (.toast)
enum TipoAviso { info, sucesso, erro }

class _Aviso {
  _Aviso(this.mensagem, this.tipo);
  final String mensagem;
  final TipoAviso tipo;
}

final _avisos = ValueNotifier<List<_Aviso>>(const []);

void avisar(String mensagem, {TipoAviso tipo = TipoAviso.info}) => _avisos.value = [..._avisos.value, _Aviso(mensagem, tipo)];

void avisarErro(Object e) => avisar(e is ApiException ? e.message : 'Não foi possível concluir a operação.', tipo: TipoAviso.erro);

Future<T?> tentar<T>(Future<T> Function() acao) async {
  try {
    return await acao();
  } catch (e) {
    avisarErro(e);
    return null;
  }
}

/// Toasts no canto inferior direito, como no v1, acima de tudo (inclusive dos diálogos).
class CamadaAvisos extends StatefulWidget {
  const CamadaAvisos({super.key, required this.child});
  final Widget child;
  @override
  State<CamadaAvisos> createState() => _CamadaAvisosState();
}

class _CamadaAvisosState extends State<CamadaAvisos> {
  final Map<_Aviso, Timer> _relogios = {};

  @override
  void initState() {
    super.initState();
    _avisos.addListener(_mudou);
    _mudou();
  }

  @override
  void dispose() {
    for (final t in _relogios.values) {
      t.cancel();
    }
    _avisos.removeListener(_mudou);
    _avisos.value = const [];
    super.dispose();
  }

  void _mudou() {
    for (final a in _avisos.value) {
      _relogios.putIfAbsent(a, () => Timer(Duration(milliseconds: a.tipo == TipoAviso.erro ? 6500 : 3800), () {
            _relogios.remove(a);
            _avisos.value = _avisos.value.where((x) => x != a).toList();
          }));
    }
  }

  @override
  Widget build(BuildContext context) => Stack(children: [
        widget.child,
        ValueListenableBuilder<List<_Aviso>>(
          valueListenable: _avisos,
          builder: (context, lista, _) {
            if (lista.isEmpty) return const SizedBox.shrink();
            return Positioned(
              right: 20,
              bottom: 20,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: (MediaQuery.sizeOf(context).width - 40).clamp(0, 520)),
                // Material: fora dele o texto não herda as fontes embutidas do tema.
                child: Material(type: MaterialType.transparency, child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                  for (final a in lista)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Semantics(
                        liveRegion: true,
                        container: true,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(6),
                            border: Border(left: BorderSide(width: 4, color: a.tipo == TipoAviso.sucesso ? Cores.sucesso : a.tipo == TipoAviso.erro ? Cores.perigo : Cores.primaria)),
                            boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 6, offset: Offset(0, 4))],
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(a.tipo == TipoAviso.sucesso ? '✅' : a.tipo == TipoAviso.erro ? '❌' : 'ℹ️', style: const TextStyle(fontSize: 13, decoration: TextDecoration.none)),
                            const SizedBox(width: 8),
                            Flexible(child: Text(a.mensagem, style: const TextStyle(color: Colors.white, fontSize: 13.1, fontWeight: FontWeight.w400, decoration: TextDecoration.none))),
                          ]),
                        ),
                      ),
                    ),
                ])),
              ),
            );
          },
        ),
      ]);
}

// ---------------------------------------------------------------- estrutura da tela
const espaco = SizedBox(height: 14);
const espacoCampo = SizedBox(height: 12);
bool telaEstreita(BuildContext c) => MediaQuery.sizeOf(c).width <= 900;

/// .main-content + .app-view
class Pagina extends StatelessWidget {
  const Pagina({super.key, this.cabecalho, required this.filhos});
  final Widget? cabecalho;
  final List<Widget> filhos;

  @override
  Widget build(BuildContext context) {
    final estreita = telaEstreita(context);
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: estreita ? 12 : 24, vertical: estreita ? 12 : 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (cabecalho != null) ...[cabecalho!, const SizedBox(height: 16)],
        for (var i = 0; i < filhos.length; i++) ...[if (i > 0) espaco, filhos[i]],
      ]),
    );
  }
}

/// Duas colunas com a mesma altura (grid do v1 com align-items: stretch).
/// Mede as duas e dá às duas a altura da maior; IntrinsicHeight não serve porque as tabelas usam LayoutBuilder.
class AlturaIgual extends MultiChildRenderObjectWidget {
  AlturaIgual({super.key, required Widget esquerda, required Widget direita, this.larguraEsquerda, this.fracaoEsquerda = .5, this.vao = 16}) : super(children: [esquerda, direita]);
  final double? larguraEsquerda;
  final double fracaoEsquerda, vao;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderAlturaIgual(larguraEsquerda, fracaoEsquerda, vao);

  @override
  void updateRenderObject(BuildContext context, RenderAlturaIgual renderObject) {
    renderObject
      ..larguraEsquerda = larguraEsquerda
      ..fracaoEsquerda = fracaoEsquerda
      ..vao = vao
      ..markNeedsLayout();
  }
}

class DadosColuna extends ContainerBoxParentData<RenderBox> {}

class RenderAlturaIgual extends RenderBox with ContainerRenderObjectMixin<RenderBox, DadosColuna>, RenderBoxContainerDefaultsMixin<RenderBox, DadosColuna> {
  RenderAlturaIgual(this.larguraEsquerda, this.fracaoEsquerda, this.vao);
  double? larguraEsquerda;
  double fracaoEsquerda, vao;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! DadosColuna) child.parentData = DadosColuna();
  }

  @override
  void performLayout() {
    final w = constraints.maxWidth;
    final le = larguraEsquerda ?? (w - vao) * fracaoEsquerda;
    final ld = w - vao - le;
    final a = firstChild!, b = lastChild!;
    a.layout(BoxConstraints.tightFor(width: le), parentUsesSize: true);
    b.layout(BoxConstraints.tightFor(width: ld), parentUsesSize: true);
    final h = math.max(a.size.height, b.size.height);
    a.layout(BoxConstraints.tightFor(width: le, height: h), parentUsesSize: true);
    b.layout(BoxConstraints.tightFor(width: ld, height: h), parentUsesSize: true);
    (a.parentData as DadosColuna).offset = Offset.zero;
    (b.parentData as DadosColuna).offset = Offset(le + vao, 0);
    size = constraints.constrain(Size(w, h));
  }

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => defaultHitTestChildren(result, position: position);
}

/// .figma-tab-header + .figma-tab-title-pill
class CabecalhoAba extends StatelessWidget {
  const CabecalhoAba(this.titulo, {super.key, this.acoes = const []});
  final String titulo;
  final List<Widget> acoes;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 8),
      decoration: BoxDecoration(
        color: Cores.cartao,
        border: Border.all(color: Cores.bordaCartao),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Text(titulo, style: TextStyle(fontSize: 16.8, fontWeight: FontWeight.w900, color: Cores.preto)),
    );
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [pill, if (acoes.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: acoes)],
    );
  }
}

/// .figma-card
class Cartao extends StatelessWidget {
  const Cartao({super.key, required this.child, this.claro = false});
  final Widget child;
  final bool claro;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: claro ? Cores.cartaoClaro : Cores.cartao,
        border: Border.all(color: Cores.bordaCartao, width: Cores.altoContraste ? 2 : 1),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1))],
      ),
      child: child,
    );
  }
}

/// .figma-card-header
class TituloCartao extends StatelessWidget {
  const TituloCartao(this.titulo, {super.key, this.direita});
  final String titulo;
  final Widget? direita;
  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Cores.bordaCartao))),
      child: Row(children: [
        Text(titulo, style: TextStyle(fontSize: 18.4, fontWeight: FontWeight.w900, color: Cores.preto)),
        const SizedBox(width: 12),
        if (direita != null) Expanded(child: Align(alignment: Alignment.centerRight, child: direita!)) else const Spacer(),
      ]),
    );
  }
}

class TituloH3 extends StatelessWidget {
  const TituloH3(this.titulo, {super.key});
  final String titulo;
  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(titulo, style: TextStyle(fontSize: 18.7, fontWeight: FontWeight.w700, color: Cores.preto)),
    );
  }
}

// ---------------------------------------------------------------- botões
enum TipoBotao { primario, secundario, sucesso, perigo }

/// .btn (.btn-primary, .btn-secondary...), .btn-sm e .btn-block
class Botao extends StatelessWidget {
  const Botao(this.texto, this.aoClicar, {super.key, this.tipo = TipoBotao.primario, this.pequeno = false, this.bloco = false, this.selecionado});
  final String texto;
  final VoidCallback? aoClicar;
  final TipoBotao tipo;
  final bool pequeno, bloco;

  /// Equivale à classe .active do v1 (botões de filtro). Só muda a semântica; o visual segue o do v1.
  final bool? selecionado;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final (fundo, frente, borda) = switch (tipo) {
      TipoBotao.primario => (Cores.primaria, Colors.white, null),
      TipoBotao.secundario => (Cores.secundario, Cores.texto, Cores.altoContraste ? Colors.black : const Color(0xFFD1D5DB)),
      TipoBotao.sucesso => (Cores.sucesso, Colors.white, null),
      TipoBotao.perigo => (Cores.perigo, Colors.white, null),
    };
    return Opacity(
      opacity: aoClicar == null ? .55 : 1,
      child: Semantics(
        button: true,
        enabled: aoClicar != null,
        selected: selecionado,
        label: texto,
        excludeSemantics: true,
        child: Material(
          color: fundo,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: borda == null ? BorderSide.none : BorderSide(color: borda, width: Cores.altoContraste ? 2 : 1)),
          child: InkWell(
            onTap: aoClicar,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: pequeno ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4) : const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(mainAxisSize: bloco ? MainAxisSize.max : MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                Flexible(child: Text(texto, textAlign: TextAlign.center, style: TextStyle(color: frente, fontSize: pequeno ? 12 : 13.6, fontWeight: FontWeight.w700))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

enum TipoAcao { aceitar, avancar, cancelar, info, lixeira }

/// .btn-icon (32x32, colorido)
class BotaoIcone extends StatelessWidget {
  const BotaoIcone(this.icone, this.dica, this.aoClicar, {super.key, this.tipo = TipoAcao.info});
  final IconData icone;
  final String dica;
  final VoidCallback? aoClicar;
  final TipoAcao tipo;

  @override
  Widget build(BuildContext context) {
    final (fundo, frente) = switch (tipo) {
      TipoAcao.aceitar => (Cores.sucesso, Colors.white),
      TipoAcao.avancar => (Cores.primaria, Colors.white),
      TipoAcao.cancelar => (Cores.perigo, Colors.white),
      TipoAcao.info => (const Color(0xFFE5E7EB), const Color(0xFF1F2429)),
      TipoAcao.lixeira => (const Color(0xFF7F1D1D), Colors.white),
    };
    return Padding(
      padding: const EdgeInsets.only(right: 4, bottom: 2),
      child: Tooltip(
        message: dica,
        child: Semantics(
          button: true,
          label: dica,
          excludeSemantics: true,
          child: Material(
            color: fundo,
            borderRadius: BorderRadius.circular(4),
            child: InkWell(onTap: aoClicar, borderRadius: BorderRadius.circular(4), child: SizedBox(width: 32, height: 32, child: Icon(icone, size: 19, color: frente))),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- selos (.badge-status-pill)
class Selo extends StatelessWidget {
  const Selo(this.texto, {super.key, this.fundo = Cores.infoClaro, this.cor = Cores.info});
  const Selo.sucesso(this.texto, {super.key}) : fundo = Cores.sucessoClaro, cor = Cores.sucessoEscuro;
  const Selo.alerta(this.texto, {super.key}) : fundo = Cores.alertaClaro, cor = Cores.alerta;
  const Selo.perigo(this.texto, {super.key}) : fundo = Cores.perigoClaro, cor = Cores.perigo;
  final String texto;
  final Color fundo, cor;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: fundo, borderRadius: BorderRadius.circular(99)),
        child: Text(texto, style: TextStyle(color: cor, fontSize: 11.5, fontWeight: FontWeight.w900)),
      );
}

Widget seloVenda(String s) => s == 'Concluída' ? Selo.sucesso(s) : Selo.perigo(s);
Widget seloAtivo(String s) => s == 'Ativo' ? Selo.sucesso(s) : Selo.perigo(s);

// ---------------------------------------------------------------- formulário
const rotuloEscuro = TextStyle(fontSize: 12, color: Color(0xFFCBD5E1), fontWeight: FontWeight.w500);
TextStyle _estiloRotulo(bool figma) => TextStyle(fontSize: figma ? 12.8 : 12.5, fontWeight: FontWeight.w700, color: figma ? Cores.preto : const Color(0xFF374151));

/// Campo com rótulo acima (.form-group / .figma-input-group) e, se pedido, contador de caracteres.
class Campo extends StatelessWidget {
  const Campo(this.controle, this.rotulo, {super.key, this.dica, this.numerico = false, this.senha = false, this.linhas = 1, this.max, this.largura, this.erro = false, this.aoMudar, this.aoEnviar, this.somenteLeitura = false, this.foco, this.autofoco = false, this.autofill, this.semRotulo = false, this.minContador, this.figma = false, this.escuro = false, this.ajuda});
  final TextEditingController controle;
  final String rotulo;
  final String? dica, ajuda;
  final bool numerico, senha, somenteLeitura, autofoco, erro, semRotulo, figma, escuro;
  final int linhas;
  final int? max, minContador;
  final double? largura;
  final ValueChanged<String>? aoMudar, aoEnviar;
  final FocusNode? foco;
  final Iterable<String>? autofill;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final tamanho = escuro ? 13.6 : (figma ? 14.1 : 13.6);
    OutlineInputBorder b(Color c, [double w = 1]) => OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: c, width: w));
    final corBorda = escuro ? const Color(0xFF4B5563) : Cores.bordaInput;
    final campo = Semantics(
      label: rotulo,
      child: TextField(
        key: ValueKey('campo:$rotulo'),
        controller: controle,
        focusNode: foco,
        autofocus: autofoco,
        obscureText: senha,
        readOnly: somenteLeitura,
        minLines: linhas > 1 ? linhas : null,
        maxLines: senha ? 1 : linhas,
        maxLength: max,
        maxLengthEnforcement: MaxLengthEnforcement.enforced,
        autofillHints: autofill,
        style: TextStyle(fontSize: tamanho, color: escuro ? Colors.white : Cores.texto),
        cursorColor: escuro ? Colors.white : Colors.black87,
        keyboardType: numerico ? const TextInputType.numberWithOptions(decimal: true) : (linhas > 1 ? TextInputType.multiline : null),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: escuro ? Cores.escuroCampo : (somenteLeitura ? const Color(0xFFF3F4F6) : Colors.white),
          hintText: dica,
          hintStyle: TextStyle(fontSize: tamanho, color: escuro ? const Color(0xFF9CA3AF) : const Color(0xFF757575)),
          counterText: '',
          contentPadding: escuro ? const EdgeInsets.symmetric(horizontal: 8, vertical: 10) : const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          border: b(corBorda),
          enabledBorder: erro ? b(Cores.perigo, 2) : b(corBorda),
          focusedBorder: erro ? b(Cores.perigo, 2) : b(Cores.foco, 2),
        ),
        onChanged: aoMudar,
        onSubmitted: aoEnviar,
      ),
    );
    final coluna = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (!semRotulo) ...[
        Text(rotulo, style: escuro ? rotuloEscuro : _estiloRotulo(figma)),
        const SizedBox(height: 3),
      ],
      campo,
      if (ajuda != null) Padding(padding: const EdgeInsets.only(top: 3), child: Text(ajuda!, style: TextStyle(fontSize: 11.8, color: Cores.fraco))),
      if (minContador != null) Contador(controle, min: minContador!, max: max ?? 5000),
    ]);
    return largura == null ? coluna : SizedBox(width: largura, child: coluna);
  }
}

/// .char-counter
class Contador extends StatelessWidget {
  const Contador(this.controle, {super.key, required this.min, required this.max});
  final TextEditingController controle;
  final int min, max;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<TextEditingValue>(
        valueListenable: controle,
        builder: (context, valor, _) {
          final n = valor.text.trim().length;
          final (cor, fundo) = n == 0
              ? (const Color(0xFF64748B), Colors.transparent)
              : n >= min
                  ? (Cores.sucesso, Cores.sucessoClaro)
                  : (Cores.perigo, Cores.perigoClaro);
          return Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: fundo, borderRadius: BorderRadius.circular(4)),
                child: Text('$n / $max caracteres (mínimo $min)', style: TextStyle(fontSize: 11.8, fontWeight: FontWeight.w700, color: cor)),
              ),
            ),
          );
        },
      );
}

/// Select do v1: caixa com borda e seta, rótulo acima.
class Escolha<T> extends StatelessWidget {
  const Escolha({super.key, required this.rotulo, required this.valor, required this.opcoes, required this.aoMudar, this.largura, this.semRotulo = false, this.figma = false, this.escuro = false});
  final String rotulo;
  final T? valor;
  final List<DropdownMenuItem<T>> opcoes;
  final ValueChanged<T?>? aoMudar;
  final double? largura;
  final bool semRotulo, figma, escuro;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final valido = opcoes.any((o) => o.value == valor) ? valor : null;
    final caixa = Semantics(
      label: rotulo,
      child: Container(
        height: escuro ? 34 : 36,
        padding: const EdgeInsets.only(left: 10, right: 4),
        decoration: BoxDecoration(
          color: escuro ? Cores.escuroCampo : Colors.white,
          border: Border.all(color: escuro ? const Color(0xFF4B5563) : Cores.bordaInput),
          borderRadius: BorderRadius.circular(4),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            key: ValueKey('escolha:$rotulo'),
            value: valido,
            isExpanded: true,
            isDense: true,
            dropdownColor: escuro ? Cores.escuroCampo : Colors.white,
            iconEnabledColor: escuro ? Colors.white : Colors.black87,
            iconSize: 20,
            style: TextStyle(fontSize: 13.6, color: escuro ? Colors.white : Cores.texto, fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily),
            items: opcoes,
            onChanged: aoMudar,
          ),
        ),
      ),
    );
    final coluna = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (!semRotulo) ...[Text(rotulo, style: escuro ? rotuloEscuro : _estiloRotulo(figma)), const SizedBox(height: 3)],
      caixa,
    ]);
    return largura == null ? coluna : SizedBox(width: largura, child: coluna);
  }
}

/// .checkbox-label
class Marcador extends StatelessWidget {
  const Marcador(this.texto, {super.key, required this.valor, required this.aoMudar});
  final String texto;
  final bool valor;
  final ValueChanged<bool> aoMudar;
  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return InkWell(
      onTap: () => aoMudar(!valor),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: 14, height: 14, child: Transform.scale(scale: .72, child: Checkbox(value: valor, side: const BorderSide(color: Color(0xFF767676), width: 1.4), onChanged: (v) => aoMudar(v == true)))),
        const SizedBox(width: 6),
        Flexible(child: Text(texto, style: TextStyle(fontSize: 13.6, color: Cores.texto))),
      ]),
    );
  }
}

/// .inline-field com data: "De [dd/mm/aaaa]"; valor em 'AAAA-MM-DD'.
class CampoData extends StatelessWidget {
  const CampoData({super.key, required this.rotulo, required this.valor, required this.aoMudar, this.primeira, this.emLinha = true, this.figma = false});
  final String rotulo, valor;
  final ValueChanged<String> aoMudar;
  final DateTime? primeira;
  final bool emLinha, figma;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final caixa = Semantics(
      button: true,
      label: rotulo,
      value: valor.isEmpty ? '' : dataBR(valor),
      excludeSemantics: true,
      child: InkWell(
        onTap: () async {
          final atual = lerDataISO(valor);
          final inicial = atual == null ? DateTime.now() : DateTime(atual.year, atual.month, atual.day);
          final min = primeira ?? DateTime(2000);
          final d = await showDatePicker(context: context, locale: const Locale('pt', 'BR'), initialDate: inicial.isBefore(min) ? min : inicial, firstDate: min, lastDate: DateTime(2100));
          if (d != null) aoMudar(dataISO(d));
        },
        child: Container(
          width: emLinha ? 140 : null,
          height: 36,
          padding: const EdgeInsets.only(left: 10, right: 6),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Cores.bordaInput), borderRadius: BorderRadius.circular(4)),
          child: Row(children: [
            Expanded(child: Text(valor.isEmpty ? 'dd/mm/aaaa' : dataBR(valor), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.6, color: Cores.texto))),
            if (valor.isNotEmpty) ...[
              InkWell(onTap: () => aoMudar(''), child: const Icon(Icons.close, size: 13, color: Color(0xFF6B7280))),
              const SizedBox(width: 3),
            ],
            const Icon(Icons.calendar_month_outlined, size: 15, color: Colors.black87),
          ]),
        ),
      ),
    );
    if (emLinha) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Text(rotulo, style: TextStyle(fontSize: 13.1, fontWeight: FontWeight.w700, color: Cores.texto)),
        const SizedBox(width: 6),
        caixa,
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(rotulo, style: _estiloRotulo(figma)),
      const SizedBox(height: 3),
      caixa,
    ]);
  }
}

/// .filter-toolbar
class BarraFiltros extends StatelessWidget {
  const BarraFiltros({super.key, required this.filhos, this.fim});
  final List<Widget> filhos;
  final Widget? fim;
  @override
  Widget build(BuildContext context) {
    final estreita = telaEstreita(context);
    final grupo = Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [...filhos, if (estreita && fim != null) fim!]);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: estreita || fim == null ? SizedBox(width: double.infinity, child: grupo) : Row(children: [Expanded(child: grupo), const SizedBox(width: 12), fim!]),
    );
  }
}

/// .toolbar-hint
class Dica extends StatelessWidget {
  const Dica(this.texto, {super.key});
  final String texto;
  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Text(texto, style: TextStyle(fontSize: 12.8, color: Cores.fraco, fontWeight: FontWeight.w600));
  }
}

// ---------------------------------------------------------------- tabela (.figma-styled-table)
class Coluna<T> {
  const Coluna(this.titulo, this.celula, {this.flex = 2});
  final String titulo;
  final Widget Function(T) celula;
  final int flex;
}

enum EstiloTabela { padrao, venda, relatorio }

/// Tabela do v1 em todas as telas. Em tela estreita, rola na horizontal (como .table-responsive).
class Tabela<T> extends StatelessWidget {
  const Tabela({super.key, required this.itens, required this.colunas, this.aoTocar, this.selecionado, this.apagado, this.critico, this.vazio = 'Nenhum registro encontrado.', this.larguraMinima = 720, this.estilo = EstiloTabela.padrao, this.alturaMaxima, this.dica, this.respiro = 14});
  final List<T> itens;
  final List<Coluna<T>> colunas;
  final void Function(T)? aoTocar;
  final bool Function(T)? selecionado, apagado, critico;
  final String Function(T)? dica;
  final String vazio;
  final double larguraMinima;
  final EstiloTabela estilo;
  final double? alturaMaxima;
  final double respiro;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final hc = Cores.altoContraste;
    final fundoTitulo = hc ? Colors.black : (estilo == EstiloTabela.venda ? const Color(0xFFF3F4F6) : Cores.cabecalhoTabela);
    final bordaTitulo = estilo == EstiloTabela.padrao ? const Color(0xFFD1D5DB) : Colors.black;
    Widget celulas(Widget Function(Coluna<T>) f, {required double vertical}) => Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          for (final col in colunas)
            Expanded(
              flex: col.flex,
              child: Padding(padding: EdgeInsets.symmetric(horizontal: respiro, vertical: vertical), child: Align(alignment: Alignment.centerLeft, child: f(col))),
            ),
        ]);
    final corpoTexto = TextStyle(fontSize: 14.7, color: Cores.texto, fontWeight: estilo == EstiloTabela.venda ? FontWeight.w500 : FontWeight.w400);
    final corpo = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (itens.isEmpty)
        Container(
          decoration: BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Cores.linhaTabela))),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Text(vazio, textAlign: TextAlign.center, style: TextStyle(fontSize: 14.4, color: Cores.fraco)),
        ),
      for (final item in itens)
        _Linha(
          conteudo: celulas((col) => DefaultTextStyle.merge(style: corpoTexto, child: col.celula(item)), vertical: 9),
          aoTocar: aoTocar == null ? null : () => aoTocar!(item),
          selecionada: selecionado?.call(item) == true,
          apagada: apagado?.call(item) == true,
          critica: critico?.call(item) == true,
          dica: dica?.call(item),
          corBorda: estilo == EstiloTabela.venda ? const Color(0xFFD1D5DB) : Cores.linhaTabela,
        ),
    ]);
    return LayoutBuilder(builder: (context, lim) {
      final estreita = lim.maxWidth < larguraMinima;
      final tabela = SizedBox(
        width: estreita ? larguraMinima : lim.maxWidth,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Container(
              decoration: BoxDecoration(color: fundoTitulo, border: Border(bottom: BorderSide(color: bordaTitulo, width: 2))),
              child: celulas((col) => Text(col.titulo, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15.2, color: hc ? Colors.white : Colors.black)), vertical: 10),
            ),
            if (alturaMaxima != null) Flexible(child: SingleChildScrollView(child: corpo)) else corpo,
          ]),
        ),
      );
      final limitada = alturaMaxima == null ? tabela : ConstrainedBox(constraints: BoxConstraints(maxHeight: alturaMaxima!), child: tabela);
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: estreita ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: limitada) : limitada,
      );
    });
  }
}

class _Linha extends StatefulWidget {
  const _Linha({required this.conteudo, this.aoTocar, required this.selecionada, required this.apagada, required this.critica, this.dica, required this.corBorda});
  final Widget conteudo;
  final VoidCallback? aoTocar;
  final bool selecionada, apagada, critica;
  final String? dica;
  final Color corBorda;
  @override
  State<_Linha> createState() => _LinhaState();
}

class _LinhaState extends State<_Linha> {
  bool _sobre = false;
  @override
  Widget build(BuildContext context) {
    final fundo = widget.selecionada ? const Color(0xFFEFF6FF) : (_sobre ? const Color(0xFFF9FAFB) : (widget.critica ? const Color(0xFFFFF1F2) : Colors.white));
    Widget linha = MouseRegion(
      onEnter: (_) => setState(() => _sobre = true),
      onExit: (_) => setState(() => _sobre = false),
      cursor: widget.aoTocar == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.aoTocar,
        child: Container(
          foregroundDecoration: widget.selecionada ? BoxDecoration(border: Border.all(color: Cores.primaria, width: 2)) : null,
          decoration: BoxDecoration(color: fundo, border: Border(bottom: BorderSide(color: widget.corBorda))),
          child: Opacity(opacity: widget.apagada ? .6 : 1, child: widget.conteudo),
        ),
      ),
    );
    if (widget.dica != null && widget.dica!.isNotEmpty) linha = Tooltip(message: widget.dica!, child: linha);
    return linha;
  }
}

/// Texto auxiliar pequeno (.muted)
class Pequeno extends StatelessWidget {
  const Pequeno(this.texto, {super.key, this.cor});
  final String texto;
  final Color? cor;
  @override
  Widget build(BuildContext context) => Text(texto, style: TextStyle(fontSize: 12.8, color: cor ?? const Color(0xFF6B7280)));
}

// ---------------------------------------------------------------- imagem do produto (GF.imgFor)
const _emojiCategoria = {1: '🍞', 2: '☕', 3: '🌾', 4: '🍰', 5: '🧀'};

class ImagemProduto extends StatelessWidget {
  const ImagemProduto({super.key, this.url, this.bytes, this.idCategoria, required this.tamanhoEmoji});
  final String? url;
  final Uint8List? bytes;
  final int? idCategoria;
  final double tamanhoEmoji;

  Widget _emoji() => ColoredBox(
        color: const Color(0xFFF3F4F6),
        child: Center(child: Text(_emojiCategoria[idCategoria] ?? '📦', style: TextStyle(fontSize: tamanhoEmoji))),
      );

  @override
  Widget build(BuildContext context) {
    if (bytes != null) return Image.memory(bytes!, fit: BoxFit.cover, width: double.infinity, height: double.infinity);
    if (url != null) return Image.network(url!, fit: BoxFit.cover, width: double.infinity, height: double.infinity, errorBuilder: (_, _, _) => _emoji());
    return _emoji();
  }
}

// ---------------------------------------------------------------- modal (.modal-box)
class Modal extends StatelessWidget {
  const Modal({super.key, required this.titulo, required this.filhos, this.acoes = const [], this.largo = false, this.acaoUnica});
  final String titulo;
  final List<Widget> filhos, acoes;
  final bool largo;
  final Widget? acaoUnica;

  @override
  Widget build(BuildContext context) {
    final tamanho = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      insetPadding: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: largo ? 720 : 500, maxHeight: tamanho.height * .92),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(titulo, style: const TextStyle(fontSize: 18.7, fontWeight: FontWeight.w700, color: Color(0xFF111827)))),
              Semantics(
                button: true,
                label: 'Fechar',
                excludeSemantics: true,
                child: InkWell(onTap: () => Navigator.pop(context), child: const Padding(padding: EdgeInsets.all(2), child: Icon(Icons.close, size: 18, color: Color(0xFF6B7280)))),
              ),
            ]),
            const SizedBox(height: 14),
            Flexible(child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: filhos))),
            if (acoes.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: acoes),
            ],
            if (acaoUnica != null) ...[const SizedBox(height: 14), acaoUnica!],
          ]),
        ),
      ),
    );
  }
}

/// .confirm-msg
class Mensagem extends StatelessWidget {
  const Mensagem(this.texto, {super.key});
  final String texto;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(texto, style: const TextStyle(fontSize: 14.7, height: 1.45, color: Color(0xFF111827))));
}

Future<bool> confirmar(BuildContext context, String mensagem, {String titulo = 'Confirmação', String ok = 'Confirmar', bool perigo = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => Modal(titulo: titulo, filhos: [Mensagem(mensagem)], acoes: [
      Botao('Cancelar', () => Navigator.pop(c, false), tipo: TipoBotao.secundario),
      Botao(ok, () => Navigator.pop(c, true), tipo: perigo ? TipoBotao.perigo : TipoBotao.primario),
    ]),
  );
  return r == true;
}
