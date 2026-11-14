class SocialAccount {
  final String id;
  final String? email;
  const SocialAccount({required this.id, this.email});
}

class SocialCourse {
  final int id;
  final String name;
  const SocialCourse({required this.id, required this.name});
}

class SocialConversation {
  final String id;
  final String title;
  final String lastMessage;
  final DateTime createdAt;
  final bool isGroup;
  final bool isCourseGroup;
  final String? courseName;

  const SocialConversation({required this.id, required this.title, required this.lastMessage, required this.createdAt, this.isGroup = true, this.isCourseGroup = false, this.courseName});
}

class SocialMessage {
  final String id;
  final String conversationId;
  final String senderId;
  final String senderName;
  final String text;
  final DateTime createdAt;

  const SocialMessage({required this.id, required this.conversationId, required this.senderId, required this.senderName, required this.text, required this.createdAt});
}

class SocialInvite {
  final String conversationId;
  final String token;
  final String conversationKey;
  final int? membersCount;

  const SocialInvite({required this.conversationId, required this.token, required this.conversationKey, this.membersCount});
}
