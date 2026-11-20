import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/rotas.dart';
import 'core/sessao.dart';
import 'core/tema.dart';
import 'widgets/comuns.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');
  final sessao = Sessao();
  runApp(ProviderScope(
    overrides: [sessaoProvider.overrideWith((ref) => sessao)],
    child: GestFastApp(sessao: sessao),
  ));
  await sessao.iniciar();
}

class GestFastApp extends StatefulWidget {
  const GestFastApp({super.key, required this.sessao});
  final Sessao sessao;
  @override
  State<GestFastApp> createState() => _GestFastAppState();
}

class _GestFastAppState extends State<GestFastApp> {
  late final GoRouter _rotas = criarRotas(widget.sessao);

  @override
  void dispose() {
    _rotas.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.sessao,
        builder: (context, _) => MaterialApp.router(
          title: 'GestFast',
          debugShowCheckedModeBanner: false,
          theme: temaGestFast(altoContraste: widget.sessao.altoContraste),
          locale: const Locale('pt', 'BR'),
          supportedLocales: const [Locale('pt', 'BR')],
          localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
          routerConfig: _rotas,
          builder: (context, filho) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(widget.sessao.zoom)),
            child: CamadaAvisos(child: filho ?? const SizedBox.shrink()),
          ),
        ),
      );
}
