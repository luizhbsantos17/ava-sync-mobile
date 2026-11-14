import 'http_repository.dart';
import 'moodle_social_repository.dart';
import 'repository.dart';

/// Escolhe a implementação do backend sem acoplar a UI ao fornecedor.
/// O Supabase self-hosted usa o mesmo protocolo e pede apenas outra URL/chave.
class SocialBackend {
  static const url = String.fromEnvironment('SOCIAL_SUPABASE_URL', defaultValue: 'https://zfyxjqdiffuuofwrgvat.supabase.co');
  static const publishableKey = String.fromEnvironment('SOCIAL_SUPABASE_KEY', defaultValue: 'sb_publishable_Z2Dd3ItPRVW7DRq3vo8jlg_ftshQWRi');
  static const backend = String.fromEnvironment('SOCIAL_BACKEND', defaultValue: 'supabase');
  static const serverUrl = String.fromEnvironment('SOCIAL_SERVER_URL');
  static const tlsCertificateBase64 = String.fromEnvironment('SOCIAL_TLS_CERT_BASE64');
  static SocialRepository? _repository;
  static String? initializationError;

  static bool get configured => backend == 'pc' ? serverUrl.isNotEmpty : backend == 'supabase' && url.isNotEmpty && publishableKey.isNotEmpty;
  static bool get configurationStarted => serverUrl.isNotEmpty || url.isNotEmpty || publishableKey.isNotEmpty;
  static SocialRepository? get repository => _repository;

  static Future<void> initialize() async {
    if (!configured) return;
    try {
      if (backend == 'pc') {
        final repository = HttpSocialRepository(serverUrl, tlsCertificateBase64: tlsCertificateBase64);
        await repository.restoreSession();
        _repository = repository;
      } else if (backend == 'supabase') {
        _repository = MoodleSocialRepository();
      } else {
        initializationError = 'Backend social desconhecido: $backend';
      }
    } catch (e) {
      initializationError = '$e';
    }
  }
}
