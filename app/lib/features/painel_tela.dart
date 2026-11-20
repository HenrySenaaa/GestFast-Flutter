// Painel inicial do v1: banner de sincronização, Alertas, Validade, Compras e Distribuição de Estoque.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/regras.dart';
import '../core/sessao.dart';
import '../core/tema.dart';
import '../models/modelos.dart';
import '../widgets/comuns.dart';
import 'dialogos_estoque.dart';

class PainelTela extends ConsumerStatefulWidget {
  const PainelTela({super.key});
  @override
  ConsumerState<PainelTela> createState() => _PainelTelaState();
}

class _PainelTelaState extends ConsumerState<PainelTela> with WidgetsBindingObserver {
  Json? _dados;
  bool _erro = false, _carregando = false, _visivel = true;
  String _ultima = 'Última checagem: agora', _intervalo = 'atualização periódica a cada 3s';
  Timer? _relogio;

  Sessao get _s => ref.read(sessaoProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _iniciar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _relogio?.cancel();
    super.dispose();
  }

  // App em segundo plano não consulta o servidor (no v1: document.hidden).
  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    _visivel = estado == AppLifecycleState.resumed;
    if (_visivel) _atualizar();
  }

  int get _segundos => math.max(2, _s.config?.intervaloSeg ?? 3);

  Future<void> _iniciar() async {
    await _s.sincronizar();
    await _atualizar();
    if (!mounted) return;
    _relogio = Timer.periodic(Duration(seconds: _segundos), (_) {
      if (_visivel) _atualizar();
    });
  }

  Future<void> _atualizar({bool manual = false}) async {
    if (_carregando) return;
    _carregando = true;
    try {
      final r = await _s.api.get('/api/dashboard');
      if (!mounted) return;
      final a = DateTime.now();
      String p(int n) => n.toString().padLeft(2, '0');
      final lat = r['latencyMs'] ?? 10;
      setState(() {
        _dados = Json.from(r['data'] as Map);
        _erro = false;
        _ultima = 'Última sincronização: ${p(a.hour)}:${p(a.minute)}:${p(a.second)} (Latência do banco: ${lat}ms)';
        _intervalo = 'Atualização periódica a cada ${_segundos}s (Tempo de resposta do banco: ~${lat}ms)';
      });
      if (manual) avisar('Dashboard sincronizado em tempo real.');
    } catch (_) {
      if (mounted) setState(() => _erro = true);
    } finally {
      _carregando = false;
    }
  }

  Widget _banner() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFCBD5E1)), borderRadius: BorderRadius.circular(8)),
        child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 6, spacing: 12, children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const _PontoVivo(),
              const SizedBox(width: 8),
              Flexible(
                child: Text.rich(TextSpan(style: const TextStyle(fontSize: 12.8, color: Color(0xFF111827)), children: [
                  const TextSpan(text: 'Sincronização em Tempo Real Ativa', style: TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: ' • $_intervalo'),
                ])),
              ),
            ]),
          ),
          Row(mainAxisSize: MainAxisSize.min, children: [
            ConstrainedBox(constraints: const BoxConstraints(maxWidth: 320), child: Text(_ultima, style: const TextStyle(fontSize: 12.8, color: Color(0xFF64748B)))),
            const SizedBox(width: 10),
            Semantics(
              button: true,
              label: 'Sincronizar',
              excludeSemantics: true,
              child: Tooltip(
                message: 'Forçar sincronização imediata',
                child: InkWell(
                  onTap: () => _atualizar(manual: true),
                  borderRadius: BorderRadius.circular(99),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(color: const Color(0xFFF1F5F9), border: Border.all(color: const Color(0xFFCBD5E1)), borderRadius: BorderRadius.circular(99)),
                    child: const Text('🔄 Sincronizar', style: TextStyle(fontSize: 11.8, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                  ),
                ),
              ),
            ),
          ]),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessaoProvider);
    final d = _dados;
    return Pagina(filhos: [
      _banner(),
      if (_erro)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: Cores.perigoClaro, borderRadius: BorderRadius.circular(8)),
          child: const Text('Não foi possível carregar os gráficos no momento. Tente atualizar a página.', style: TextStyle(color: Cores.perigo, fontWeight: FontWeight.w700, fontSize: 14)),
        ),
      if (d != null) _conteudo(d, s),
    ]);
  }

  Widget _conteudo(Json d, Sessao s) {
    final v = Json.from(d['validades'] as Map);
    final itensValidade = listaJson(v['itens']);
    final vencidos = (v['vencidos'] as num?)?.toInt() ?? 0;
    final podePedir = s.pode('requisicoes:criar');
    final podePerda = s.pode('movimentos:registrar');

    final alertas = Cartao(
      claro: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const TituloCartao('Alertas'),
        _Lista(
          vazio: const _Linha('Todos os itens com estoque regular', 'OK'),
          linhas: [
            for (final a in listaJson(d['alertas']))
              _Linha(
                '${a['nome_produto']}',
                quantidade(a['quantidade_estoque']),
                dica: '${a['mensagem']} (mínimo ${quantidade(a['estoque_minimo'])} ${a['unidade']})${podePedir ? ' - clique para criar uma requisição' : ''}',
                aoTocar: podePedir
                    ? () async {
                        if (await abrirNovaRequisicao(context, s, idProduto: (a['id_produto'] as num).toInt()) != null) _atualizar();
                      }
                    : null,
              ),
          ],
        ),
      ]),
    );
    final validade = Cartao(
      claro: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TituloCartao('Validade', direita: itensValidade.isEmpty ? null : Dica('$vencidos vencido(s) • ${itensValidade.length - vencidos} vencendo em até ${v['dias']} dia(s)')),
        _Lista(
          vazio: const _Linha('Nenhum produto vencido ou perto de vencer', 'OK'),
          linhas: [
            for (final i in itensValidade)
              _Linha(
                '${i['nome_produto']}',
                numero(i['dias_restantes']) < 0
                    ? 'Vencido (${dataBR('${i['validade']}')})'
                    : numero(i['dias_restantes']) == 0
                        ? 'Vence hoje'
                        : '${numero(i['dias_restantes']).toInt()} dia(s)',
                cor: numero(i['dias_restantes']) < 0 ? Cores.perigo : Cores.alerta,
                dica: 'Lote ${i['lote'] == '' ? '-' : i['lote']} • validade ${dataBR('${i['validade']}')} • ${quantidade(i['quantidade_estoque'])} ${i['unidade']} (${dinheiro(i['valor_em_risco'])} no custo)${podePerda ? ' - clique para dar baixa como perda' : ''}',
                aoTocar: podePerda
                    ? () async {
                        if (await abrirPerda(context, s, idProduto: (i['id_produto'] as num).toInt(), quantidadePreset: numero(i['quantidade_estoque']))) _atualizar();
                      }
                    : null,
              ),
          ],
        ),
      ]),
    );
    final compras = Cartao(
      claro: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TituloCartao('Compras',
            direita: podePedir
                ? Botao('+ Nova Requisição', () async {
                    if (await abrirNovaRequisicao(context, s) != null) _atualizar();
                  }, pequeno: true)
                : null),
        _Lista(
          vazio: const _Linha('Nenhuma compra recente', ''),
          linhas: [
            for (final c in listaJson(d['ultimasCompras']))
              _Linha('${c['produto_nome']}', 'x${quantidade(c['quantidade_pedida'])}', dica: '${c['codigo_pedido']} • ${c['fornecedor']} • ${c['situacao']}', aoTocar: () => context.go('/requisicoes?id=${c['id_requisicao']}')),
          ],
        ),
      ]),
    );
    final grafico = _CartaoGrafico(dist: listaJson(d['distribuicaoEstoque']), s: s);
    final esquerda = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [alertas, const SizedBox(height: 16), validade, const SizedBox(height: 16), compras]);

    return LayoutBuilder(builder: (context, lim) {
      if (MediaQuery.sizeOf(context).width <= 1100) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [esquerda, const SizedBox(height: 16), grafico]);
      }
      return AlturaIgual(esquerda: esquerda, direita: grafico);
    });
  }
}

class _PontoVivo extends StatefulWidget {
  const _PontoVivo();
  @override
  State<_PontoVivo> createState() => _PontoVivoState();
}

class _PontoVivoState extends State<_PontoVivo> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(seconds: 2));

  @override
  void initState() {
    super.initState();
    _a.repeat();
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _a,
        builder: (_, _) {
          final t = _a.value;
          final abre = t < .7 ? t / .7 : 1.0;
          return Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: Cores.sucesso,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Cores.sucesso.withValues(alpha: .7 * (1 - abre)), spreadRadius: 6 * abre)],
            ),
          );
        },
      );
}

class _Linha {
  const _Linha(this.titulo, this.valor, {this.dica, this.aoTocar, this.cor});
  final String titulo, valor;
  final String? dica;
  final VoidCallback? aoTocar;
  final Color? cor;
}

class _Lista extends StatelessWidget {
  const _Lista({required this.linhas, required this.vazio});
  final List<_Linha> linhas;
  final _Linha vazio;
  @override
  Widget build(BuildContext context) {
    final itens = linhas.isEmpty ? [vazio] : linhas;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < itens.length; i++) ...[if (i > 0) const SizedBox(height: 8), _LinhaDado(itens[i])],
    ]);
  }
}

/// .figma-data-row
class _LinhaDado extends StatefulWidget {
  const _LinhaDado(this.l);
  final _Linha l;
  @override
  State<_LinhaDado> createState() => _LinhaDadoState();
}

class _LinhaDadoState extends State<_LinhaDado> {
  bool _sobre = false;
  @override
  Widget build(BuildContext context) {
    final l = widget.l;
    Widget linha = MouseRegion(
      cursor: l.aoTocar == null ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _sobre = true),
      onExit: (_) => setState(() => _sobre = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: l.aoTocar,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: _sobre && l.aoTocar != null ? const Color(0xFFEEF2FF) : Colors.white, borderRadius: BorderRadius.circular(4)),
          child: Row(children: [
            Expanded(child: Text(l.titulo, style: TextStyle(fontSize: 15.2, color: Cores.texto))),
            const SizedBox(width: 8),
            Text(l.valor, style: TextStyle(fontSize: 15.2, fontWeight: FontWeight.w900, color: l.cor ?? const Color(0xFF111827))),
          ]),
        ),
      ),
    );
    if (l.dica != null) linha = Tooltip(message: l.dica!, child: linha);
    return linha;
  }
}

class _CartaoGrafico extends StatelessWidget {
  const _CartaoGrafico({required this.dist, required this.s});
  final List<Json> dist;
  final Sessao s;

  @override
  Widget build(BuildContext context) {
    Widget atalho(String t, VoidCallback f) => Semantics(
          button: true,
          label: t,
          excludeSemantics: true,
          child: InkWell(
            onTap: f,
            borderRadius: BorderRadius.circular(99),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFD4D4D8)), borderRadius: BorderRadius.circular(99)),
              child: Text(t, style: const TextStyle(fontSize: 12.8, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
            ),
          ),
        );
    return Cartao(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        TituloCartao(
          'Distribuição de Estoque',
          direita: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: Cores.sucesso, borderRadius: BorderRadius.circular(99)),
            child: const Text('Ao Vivo', style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
          ),
        ),
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(width: 220, height: 220, child: Semantics(label: 'Gráfico de distribuição do estoque por categoria', child: CustomPaint(painter: _Pizza(dist.map((e) => numero(e['quantidade'])).toList())))),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Column(children: [
                  for (var i = 0; i < dist.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(children: [
                        Container(width: 12, height: 12, decoration: BoxDecoration(color: Cores.grafico[i % Cores.grafico.length], borderRadius: BorderRadius.circular(2))),
                        const SizedBox(width: 6),
                        Expanded(child: Text('${dist[i]['categoria']}', style: const TextStyle(fontSize: 14.1, fontWeight: FontWeight.w500, color: Color(0xFF111827)))),
                        Text('${dist[i]['porcentagem']}%', style: const TextStyle(fontSize: 14.1, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
                      ]),
                    ),
                ]),
              ),
            ]),
        ),
        Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
          atalho('📦 Abrir Estoque', () => context.go('/estoque')),
          if (s.pode('vendas:vender')) atalho('🛒 Abrir Caixa', () => context.go('/venda')),
          atalho('📝 Requisições', () => context.go('/requisicoes')),
        ]),
      ]),
    );
  }
}

class _Pizza extends CustomPainter {
  _Pizza(this.valores);
  final List<double> valores;

  @override
  void paint(Canvas canvas, Size size) {
    final total = valores.fold(0.0, (a, b) => a + b);
    if (total <= 0) return;
    // Mesma geometria do canvas do v1: centro em 110, raio 95.
    final r = Rect.fromCircle(center: const Offset(110, 110), radius: 95);
    var inicio = -math.pi / 2;
    for (var i = 0; i < valores.length; i++) {
      final fatia = valores[i] / total * 2 * math.pi;
      canvas.drawArc(r, inicio, fatia, true, Paint()..color = Cores.grafico[i % Cores.grafico.length]);
      canvas.drawArc(r, inicio, fatia, true, Paint()
        ..color = const Color(0xFFDEDEDE)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5);
      inicio += fatia;
    }
  }

  @override
  bool shouldRepaint(_Pizza antigo) => antigo.valores != valores;
}
