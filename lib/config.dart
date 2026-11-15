import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Configuracoes do app.
///
/// - Preferencias comuns (site, filtros, intervalo...) ficam no SharedPreferences.
/// - Segredos (token do Moodle, chave da IA) ficam no FlutterSecureStorage, que no
///   Android usa o Keystore: o arquivo fica criptografado e so este app le.
/// - A SENHA do Moodle nunca e guardada: so e usada para gerar o token no login.
class Cfg {
  static const _seg = FlutterSecureStorage();
  static late SharedPreferences _p;

  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    await _p.reload(); // em segundo plano, pega o que a tela salvou
  }

  // ---- conta ----
  static String get site => _p.getString('site') ?? '';
  static Future<void> setSite(String v) => _p.setString('site', v.trim().replaceAll(RegExp(r'/+$'), ''));
  static String get usuarioNome => _p.getString('usuario_nome') ?? '';
  static Future<void> setUsuarioNome(String v) => _p.setString('usuario_nome', v);

  static Future<String?> token() => _seg.read(key: 'token');
  static Future<void> salvarToken(String t) => _seg.write(key: 'token', value: t);
  static Future<void> apagarToken() => _seg.delete(key: 'token');

  // ---- filtros de cursos ----
  static List<String> get ignorarCursos => _p.getStringList('ignorar') ?? const ['Biblioteca Virtual'];
  static Future<void> setIgnorarCursos(List<String> v) => _p.setStringList('ignorar', v);
  static List<String> get somenteCursos => _p.getStringList('somente') ?? const [];
  static Future<void> setSomenteCursos(List<String> v) => _p.setStringList('somente', v);
  static Set<String> get cursosIgnoradosIds => (_p.getStringList('cursos_ignorados_ids') ?? const []).toSet();
  static Future<void> setCursosIgnoradosIds(Set<String> v) => _p.setStringList('cursos_ignorados_ids', v.toList()..sort());
  static Set<String> get cursosSelecionadosIds => (_p.getStringList('cursos_selecionados_ids') ?? const []).toSet();
  static Future<void> setCursosSelecionadosIds(Set<String> v) => _p.setStringList('cursos_selecionados_ids', v.toList()..sort());
  static bool get somenteCursosIdsAtivo => _p.getBool('somente_cursos_ids_ativo') ?? false;
  static Future<void> setSomenteCursosIdsAtivo(bool v) => _p.setBool('somente_cursos_ids_ativo', v);

  // ---- sincronizacao ----
  static bool get autoSync => _p.getBool('auto_sync') ?? true;
  static Future<void> setAutoSync(bool v) => _p.setBool('auto_sync', v);
  static int get intervaloHoras => _p.getInt('intervalo_h') ?? 12;
  static Future<void> setIntervaloHoras(int v) => _p.setInt('intervalo_h', v);
  static bool get notificacoes => _p.getBool('notif') ?? true;
  static Future<void> setNotificacoes(bool v) => _p.setBool('notif', v);
  static bool get lembretePrazo => _p.getBool('lembrete') ?? true;
  static Future<void> setLembretePrazo(bool v) => _p.setBool('lembrete', v);
  static bool get baixarArquivos => _p.getBool('baixar') ?? true;
  static Future<void> setBaixarArquivos(bool v) => _p.setBool('baixar', v);
  static bool get soWifi => _p.getBool('so_wifi') ?? false;
  static Future<void> setSoWifi(bool v) => _p.setBool('so_wifi', v);
  static int get maxMb => _p.getInt('max_mb') ?? 100;
  static Future<void> setMaxMb(int v) => _p.setInt('max_mb', v);
  static bool get baixarLinks => _p.getBool('baixar_links') ?? true;
  static Future<void> setBaixarLinks(bool v) => _p.setBool('baixar_links', v);
  static bool get permissaoPedida => _p.getBool('perm_notif') ?? false;
  static Future<void> setPermissaoPedida(bool v) => _p.setBool('perm_notif', v);

  // ---- social ----
  static bool get socialNotificacoes => _p.getBool('social_notif') ?? true;
  static Future<void> setSocialNotificacoes(bool v) => _p.setBool('social_notif', v);
  static bool get socialUsado => _p.getBool('social_usado') ?? false;
  static Future<void> setSocialUsado(bool v) => _p.setBool('social_usado', v);
  static String get socialUltimaNotif => _p.getString('social_ultima_notif') ?? '';
  static Future<void> setSocialUltimaNotif(String v) => _p.setString('social_ultima_notif', v);
  static List<String> get socialEmojisRecentes => _p.getStringList('social_emojis') ?? const ['👍', '❤️', '😂', '😮', '😢', '🔥'];
  static Future<void> setSocialEmojisRecentes(List<String> v) => _p.setStringList('social_emojis', v.take(12).toList());
  static String get socialRascunhos => _p.getString('social_rascunhos') ?? '{}';
  static Future<void> setSocialRascunhos(String v) => _p.setString('social_rascunhos', v);

  // ---- atualizacoes do app ----
  static bool get verificarAtualizacoes => _p.getBool('upd_auto') ?? true;
  static Future<void> setVerificarAtualizacoes(bool v) => _p.setBool('upd_auto', v);
  static int get updUltimaVerificacao => _p.getInt('upd_ultima') ?? 0;
  static Future<void> setUpdUltimaVerificacao(int v) => _p.setInt('upd_ultima', v);
  /// Build ja avisado por notificacao (uma vez por build).
  static int get updNotificado => _p.getInt('upd_notif') ?? 0;
  static Future<void> setUpdNotificado(int v) => _p.setInt('upd_notif', v);
  /// "Depois": nao pergunta de novo sobre este build ate [updAdiadoAte] (segundos).
  static int get updAdiadoBuild => _p.getInt('upd_adiado') ?? 0;
  static int get updAdiadoAte => _p.getInt('upd_adiado_ate') ?? 0;
  static Future<void> adiarAtualizacao(int build, int ate) async {
    await _p.setInt('upd_adiado', build);
    await _p.setInt('upd_adiado_ate', ate);
  }

  // ---- calendario do celular (Google Agenda) ----
  static bool get calendario => _p.getBool('cal_on') ?? false;
  static Future<void> setCalendario(bool v) => _p.setBool('cal_on', v);
  static String get calendarioId => _p.getString('cal_id') ?? '';
  static Future<void> setCalendarioId(String v) => _p.setString('cal_id', v);
  static String get calendarioNome => _p.getString('cal_nome') ?? '';
  static Future<void> setCalendarioNome(String v) => _p.setString('cal_nome', v);
  static bool get calendarioSoProvas => _p.getBool('cal_provas') ?? false;
  static Future<void> setCalendarioSoProvas(bool v) => _p.setBool('cal_provas', v);
  /// chave do compromisso -> id do evento criado no calendario
  static Map<String, dynamic> get calendarioEventos => _json('cal_eventos');
  static Future<void> setCalendarioEventos(Map<String, dynamic> m) => _p.setString('cal_eventos', jsonEncode(m));

  // ---- perfil e aparencia ----
  static String get temaJson => _p.getString('tema') ?? '';
  static Future<void> setTemaJson(String v) => _p.setString('tema', v);
  static String get perfilFoto => _p.getString('perfil_foto') ?? '';
  static Future<void> setPerfilFoto(String v) => _p.setString('perfil_foto', v);
  static String get perfilApelido => _p.getString('perfil_apelido') ?? '';
  static Future<void> setPerfilApelido(String v) => _p.setString('perfil_apelido', v.trim());
  static String get perfilCurso => _p.getString('perfil_curso') ?? '';
  static Future<void> setPerfilCurso(String v) => _p.setString('perfil_curso', v.trim());
  static String get perfilBio => _p.getString('perfil_bio') ?? '';
  static Future<void> setPerfilBio(String v) => _p.setString('perfil_bio', v.trim());

  // ---- Q-Academico ----
  static String get qaUrl => _p.getString('qa_url') ?? '';
  static Future<void> setQaUrl(String v) => _p.setString('qa_url', v.trim());
  static String get qaLogin => _p.getString('qa_login') ?? '';
  static Future<void> setQaLogin(String v) => _p.setString('qa_login', v.trim());
  /// Senha do Q-Academico: so se a pessoa pedir para lembrar (Keystore do Android).
  static Future<String?> qaSenha() => _seg.read(key: 'qa_senha');
  static Future<void> setQaSenha(String? v) =>
      v == null || v.isEmpty ? _seg.delete(key: 'qa_senha') : _seg.write(key: 'qa_senha', value: v);
  /// Atualiza o Q-Academico junto com a sincronizacao do AVA (com o app aberto).
  static bool get qaAuto => _p.getBool('qa_auto') ?? true;
  static Future<void> setQaAuto(bool v) => _p.setBool('qa_auto', v);
  /// Faltar um dia de aula conta quantas faltas (quando o horario nao diz).
  static int get faltasPorDia => _p.getInt('faltas_dia') ?? 2;
  static Future<void> setFaltasPorDia(int v) => _p.setInt('faltas_dia', v);
  static int get frequenciaMinima => _p.getInt('freq_min') ?? 75;
  static Future<void> setFrequenciaMinima(int v) => _p.setInt('freq_min', v);

  // ---- semestre atual e categorias (ajustes manuais da pessoa) ----
  static bool get verTodas => _p.getBool('ver_todas') ?? false;
  static Future<void> setVerTodas(bool v) => _p.setBool('ver_todas', v);
  static Map<String, dynamic> _json(String k) {
    try {
      return Map<String, dynamic>.from(jsonDecode(_p.getString(k) ?? '{}'));
    } catch (_) {
      return {};
    }
  }

  /// id do curso -> true (semestre atual) / false (antigo). Sem entrada = automatico.
  static Map<String, dynamic> get atualManual => _json('atual_manual');
  static Future<void> setAtualManual(dynamic cursoId, bool? v) {
    final m = atualManual;
    v == null ? m.remove('$cursoId') : m['$cursoId'] = v;
    return _p.setString('atual_manual', jsonEncode(m));
  }

  /// "tarefa:12" / "quiz:3" / "evento:9" -> "prova" | "atividade". Sem entrada = automatico.
  static Map<String, dynamic> get categoriaManual => _json('cat_manual');
  static Future<void> setCategoriaManual(String chave, String? v) {
    final m = categoriaManual;
    v == null ? m.remove(chave) : m[chave] = v;
    return _p.setString('cat_manual', jsonEncode(m));
  }

  // ---- IA (opcional) ----
  // Cada provedor tem a sua propria configuracao e a sua propria pasta de conteudo.
  // Trocar de provedor nao apaga nada: o conteudo de cada um continua salvo.
  static String get iaAtiva => _p.getString('ia_ativa') ?? 'nenhum';
  static Future<void> setIaAtiva(String v) => _p.setString('ia_ativa', v);
  static String iaModelo(String slot) => _p.getString('ia_modelo_$slot') ?? '';
  static Future<void> setIaModelo(String slot, String v) => _p.setString('ia_modelo_$slot', v.trim());
  static String iaBaseUrl(String slot) => _p.getString('ia_base_$slot') ?? '';
  static Future<void> setIaBaseUrl(String slot, String v) => _p.setString('ia_base_$slot', v.trim());
  static Future<String?> iaChave(String slot) => _seg.read(key: 'ia_chave_$slot');
  static Future<void> setIaChave(String slot, String v) =>
      v.trim().isEmpty ? _seg.delete(key: 'ia_chave_$slot') : _seg.write(key: 'ia_chave_$slot', value: v.trim());
  static int get iaMaxContexto => _p.getInt('ia_ctx') ?? 120000;
  static Future<void> setIaMaxContexto(int v) => _p.setInt('ia_ctx', v);
  static bool get iaEnviarPdfs => _p.getBool('ia_pdfs') ?? true;
  static Future<void> setIaEnviarPdfs(bool v) => _p.setBool('ia_pdfs', v);

  static Future<void> sair() async {
    await apagarToken();
    await _p.remove('usuario_nome');
  }
}
