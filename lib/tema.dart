import 'dart:convert';

import 'package:material_ui/material_ui.dart';

/// Aparencia do app, editavel pela pessoa (presets na tela ou JSON para quem quer
/// controlar tudo). Campos ausentes no JSON usam o padrao.
class Tema {
  final Color cor; // cor principal
  final String modo; // escuro | claro | sistema
  final Color? fundo; // fundo das telas (null = derivado da cor)
  final Color? cartao; // fundo dos cartoes
  final Color? destaque; // segunda cor do gradiente do logo/perfil
  final double raio; // arredondamento dos cartoes
  final double fonte; // escala do texto (0.8 a 1.4)
  final bool compacto; // listas mais densas

  const Tema({
    this.cor = const Color(0xFFB49AFF),
    this.modo = 'escuro',
    this.fundo,
    this.cartao,
    this.destaque,
    this.raio = 18,
    this.fonte = 1,
    this.compacto = false,
  });

  static const padrao = Tema(fundo: Color(0xFF100D17), cartao: Color(0xFF1A1622), destaque: Color(0xFF7D5AD1));

  static const presets = <String, Tema>{
    'Violeta': padrao,
    'Oceano': Tema(cor: Color(0xFF6EC6FF), fundo: Color(0xFF0B1320), cartao: Color(0xFF14202F), destaque: Color(0xFF2B7BD6)),
    'Floresta': Tema(cor: Color(0xFF7BD88F), fundo: Color(0xFF0D1510), cartao: Color(0xFF16221A), destaque: Color(0xFF2E9E57)),
    'Pôr do sol': Tema(cor: Color(0xFFFFA36C), fundo: Color(0xFF1A0F0B), cartao: Color(0xFF261813), destaque: Color(0xFFE0555B)),
    'Rosa': Tema(cor: Color(0xFFFF8AC6), fundo: Color(0xFF180D14), cartao: Color(0xFF24141E), destaque: Color(0xFFC2459A)),
    'Claro': Tema(cor: Color(0xFF6845C4), modo: 'claro'),
  };

  ThemeMode get themeMode => switch (modo) {
        'claro' => ThemeMode.light,
        'sistema' => ThemeMode.system,
        _ => ThemeMode.dark,
      };

  Color get segundaCor => destaque ?? Color.lerp(cor, Colors.black, 0.35)!;

  Tema copyWith({Color? cor, String? modo, double? raio, double? fonte, bool? compacto}) => Tema(
        cor: cor ?? this.cor,
        modo: modo ?? this.modo,
        fundo: cor == null ? fundo : null,
        cartao: cor == null ? cartao : null,
        destaque: cor == null ? destaque : null,
        raio: raio ?? this.raio,
        fonte: fonte ?? this.fonte,
        compacto: compacto ?? this.compacto,
      );

  Map<String, dynamic> toJson() => {
        'cor': hex(cor),
        'modo': modo,
        if (fundo != null) 'fundo': hex(fundo!),
        if (cartao != null) 'cartao': hex(cartao!),
        if (destaque != null) 'destaque': hex(destaque!),
        'raio': raio,
        'fonte': fonte,
        'compacto': compacto,
      };

  /// Le o JSON. Lanca FormatException com mensagem clara se algo estiver errado.
  factory Tema.fromJson(Map<String, dynamic> j) {
    Color? c(String k) {
      final v = j[k];
      if (v == null) return null;
      final cor = deHex('$v');
      if (cor == null) throw FormatException('"$k" precisa ser uma cor como "#B49AFF" (recebi "$v").');
      return cor;
    }

    double n(String k, double padrao, double min, double max) {
      final v = j[k];
      if (v == null) return padrao;
      if (v is! num) throw FormatException('"$k" precisa ser um número.');
      return v.toDouble().clamp(min, max);
    }

    final modo = '${j['modo'] ?? 'escuro'}';
    if (!['escuro', 'claro', 'sistema'].contains(modo)) {
      throw const FormatException('"modo" precisa ser "escuro", "claro" ou "sistema".');
    }
    return Tema(
      cor: c('cor') ?? const Color(0xFFB49AFF),
      modo: modo,
      fundo: c('fundo'),
      cartao: c('cartao'),
      destaque: c('destaque'),
      raio: n('raio', 18, 0, 40),
      fonte: n('fonte', 1, 0.8, 1.4),
      compacto: j['compacto'] == true,
    );
  }

  static Tema deTexto(String? s) {
    if (s == null || s.isEmpty) return padrao;
    try {
      return Tema.fromJson(Map<String, dynamic>.from(jsonDecode(s)));
    } catch (_) {
      return padrao;
    }
  }

  String paraTexto() => const JsonEncoder.withIndent('  ').convert(toJson());

  ThemeData construir(Brightness b) {
    final escuro = b == Brightness.dark;
    final fundoTela = escuro ? (fundo ?? Color.lerp(const Color(0xFF0E0E12), cor, 0.06)!) : const Color(0xFFF8F6FC);
    final fundoCartao = escuro ? (cartao ?? Color.lerp(fundoTela, cor, 0.08)!) : Colors.white;
    final principal = escuro ? cor : (modo == 'claro' ? cor : Color.lerp(cor, Colors.black, 0.35)!);
    final scheme = ColorScheme.fromSeed(seedColor: cor, brightness: b).copyWith(
      primary: principal,
      surface: fundoTela,
      error: const Color(0xFFFF8A98),
    );
    final raioMenor = (raio * 0.75).clamp(0, 30).toDouble();
    final base = ThemeData(
      colorScheme: scheme,
      brightness: b,
      scaffoldBackgroundColor: fundoTela,
      useMaterial3: true,
      visualDensity: compacto ? VisualDensity.compact : VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: fundoTela,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: fundoCartao,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(raio)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: escuro ? Color.lerp(fundoTela, fundoCartao, 0.5) : Colors.white,
        indicatorColor: Color.lerp(fundoCartao, cor, escuro ? 0.3 : 0.15),
        elevation: 0,
        labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: escuro ? Color.lerp(fundoCartao, Colors.white, 0.03) : const Color(0xFFF0EDF5),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(raioMenor), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(raioMenor),
          borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(raioMenor),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      listTileTheme: ListTileThemeData(
          iconColor: scheme.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(raioMenor))),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.4), thickness: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(raioMenor)),
      ),
      // barra de rolagem fina e arredondada que engrossa ao passar o mouse (computador)
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.hovered) || s.contains(WidgetState.dragged) ? 8 : 4),
        radius: const Radius.circular(8),
        thumbColor: WidgetStateProperty.resolveWith((s) => scheme.onSurface.withValues(
            alpha: s.contains(WidgetState.dragged) ? .5 : s.contains(WidgetState.hovered) ? .35 : .18)),
        trackColor: const WidgetStatePropertyAll(Colors.transparent),
        trackBorderColor: const WidgetStatePropertyAll(Colors.transparent),
        crossAxisMargin: 2,
        mainAxisMargin: 4,
        interactive: true,
      ),
      // telas entram com um deslize suave, iguais no celular e no computador
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
      }),
      popupMenuTheme: PopupMenuThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(raioMenor)),
        elevation: 6,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: scheme.inverseSurface, borderRadius: BorderRadius.circular(6)),
        textStyle: TextStyle(color: scheme.onInverseSurface, fontSize: 12.5, fontWeight: FontWeight.w600),
        waitDuration: const Duration(milliseconds: 400),
      ),
    );
    return base;
  }
}

String hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

Color? deHex(String s) {
  final m = RegExp(r'^#?([0-9a-fA-F]{6})([0-9a-fA-F]{2})?$').firstMatch(s.trim());
  if (m == null) return null;
  return Color(int.parse('FF${m[1]}', radix: 16));
}

/// Tema em uso. A tela de aparencia altera isto e o app redesenha na hora.
final temaAtual = ValueNotifier<Tema>(Tema.padrao);
