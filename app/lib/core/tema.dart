// Cores e medidas do style.css do GestFast v1. Alto contraste igual ao html.hc do v1: fundo branco e texto preto.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class Cores {
  /// Definido pelo tema. Os widgets dependem de Theme.of, então redesenham quando muda.
  static bool altoContraste = false;
  static bool get _hc => altoContraste;

  static Color get pagina => _hc ? Colors.white : const Color(0xFFDEDEDE);
  static Color get linhaLayout => _hc ? Colors.black : const Color(0xFFCFCFCF);
  static Color get cartao => _hc ? Colors.white : const Color(0xFFEDEDED);
  static Color get cartaoClaro => _hc ? Colors.white : const Color(0xFFF3F3F3);
  static Color get bordaCartao => _hc ? Colors.black : const Color(0xFFD4D4D8);
  static Color get bordaInput => _hc ? Colors.black : const Color(0xFFD1D5DB);
  static Color get bordaBusca => const Color(0xFF5B8DB8);
  static Color get texto => _hc ? Colors.black : const Color(0xFF1F2429);
  static Color get preto => Colors.black;
  static Color get fraco => _hc ? const Color(0xFF1F2937) : const Color(0xFF52525B);
  static Color get cabecalhoTabela => _hc ? Colors.black : const Color(0xFFE9E9E9);
  static Color get textoCabecalhoTabela => _hc ? Colors.white : Colors.black;
  static Color get linhaTabela => _hc ? Colors.black : const Color(0xFFE5E7EB);
  static Color get menuAtivo => _hc ? Colors.black : const Color(0xFFCFCFCF);
  static Color get textoMenuAtivo => _hc ? Colors.white : Colors.black;
  static Color get menuHover => _hc ? Colors.black : const Color(0xFFD4D4D4);
  static Color get secundario => _hc ? Colors.white : const Color(0xFFE5E7EB);

  static const escuro = Color(0xFF1F2429);
  static const escuroCampo = Color(0xFF2D343C);
  static const escuroBorda = Color(0xFF3F444E);
  static const primaria = Color(0xFF2563EB);
  static const sucesso = Color(0xFF16A34A);
  static const sucessoClaro = Color(0xFFDCFCE7);
  static const sucessoEscuro = Color(0xFF166534);
  static const perigo = Color(0xFFDC2626);
  static const perigoClaro = Color(0xFFFEE2E2);
  static const alerta = Color(0xFFD97706);
  static const alertaClaro = Color(0xFFFEF3C7);
  static const infoClaro = Color(0xFFE0E7FF);
  static const info = Color(0xFF3730A3);
  static const foco = Color(0xFFF97316);
  static const grafico = [Color(0xFF2563EB), Color(0xFFF97316), Color(0xFF374151), Color(0xFF10B981), Color(0xFF8B5CF6)];
}

ThemeData temaGestFast({required bool altoContraste}) {
  Cores.altoContraste = altoContraste;
  final esquema = ColorScheme.fromSeed(seedColor: Cores.primaria, primary: Cores.primaria, surface: Colors.white, onSurface: Cores.texto, error: Cores.perigo);
  return ThemeData(
    useMaterial3: true,
    colorScheme: esquema,
    // O Material espaça as letras por padrão; o CSS do v1 não.
    textTheme: const TextTheme(
      bodyLarge: TextStyle(letterSpacing: 0),
      bodyMedium: TextStyle(letterSpacing: 0),
      bodySmall: TextStyle(letterSpacing: 0),
      titleMedium: TextStyle(letterSpacing: 0),
      titleSmall: TextStyle(letterSpacing: 0),
      labelLarge: TextStyle(letterSpacing: 0),
    ),
    // Como o CSS do v1: fonte do sistema (Segoe UI no Windows, Roboto no Android...). Na web, a Roboto embutida.
    fontFamily: kIsWeb ? 'Roboto' : null,
    fontFamilyFallback: kIsWeb ? const ['GestSimbolos', 'GestMath', 'GestEmoji'] : null,
    scaffoldBackgroundColor: Cores.pagina,
    canvasColor: Colors.white,
    dialogTheme: const DialogThemeData(barrierColor: Color(0x8C000000)),
    splashFactory: NoSplash.splashFactory,
    hoverColor: Colors.transparent,
    highlightColor: Colors.transparent,
    visualDensity: VisualDensity.compact,
    tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 500)),
    textSelectionTheme: const TextSelectionThemeData(cursorColor: Colors.black87),
    checkboxTheme: CheckboxThemeData(
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
    ),
  );
}
