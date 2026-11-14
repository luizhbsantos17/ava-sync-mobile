import 'models.dart';

/// Contrato que a interface do Social usa. Implementações podem falar com
/// Supabase hospedado, Supabase self-hosted ou uma API própria.
abstract interface class SocialRepository {
  bool get configured;
  SocialAccount? get currentUser;
  Stream<SocialAccount?> get authChanges;
  Future<SocialAccount?> identity();

  Future<void> signIn({required String email, required String password});
  Future<void> signUp({required String email, required String password, required String username, required String displayName});
  Future<void> signOut();
  Future<List<SocialConversation>> conversations();
  Stream<List<SocialMessage>> messages(String conversationId);
  Future<SocialInvite> createGroup(String title);
  Future<List<SocialCourse>> teacherCourses();
  Future<SocialInvite> createCourseGroup({required String title, required SocialCourse course});
  Future<void> joinGroup(String inviteCode);
  Future<void> sendMessage(String conversationId, String text);
}
