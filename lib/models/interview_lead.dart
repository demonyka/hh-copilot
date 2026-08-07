/// Обнаруженное приглашение на собеседование (для раздела «Собеседования»).
class InterviewLead {
  const InterviewLead({
    required this.chatId,
    required this.vacancy,
    required this.company,
    required this.message,
    required this.kind,
    required this.summary,
    required this.detectedAt,
    this.messageAt,
  });

  final int chatId;
  final String vacancy;
  final String company;
  final String message;
  final String kind;
  final String summary;
  final DateTime detectedAt;
  final DateTime? messageAt;

  String get chatUrl => 'https://hh.ru/chat/$chatId';

  Map<String, dynamic> toJson() => {
        'chatId': chatId,
        'vacancy': vacancy,
        'company': company,
        'message': message,
        'kind': kind,
        'summary': summary,
        'detectedAt': detectedAt.toIso8601String(),
        'messageAt': messageAt?.toIso8601String(),
      };

  factory InterviewLead.fromJson(Map<String, dynamic> j) {
    return InterviewLead(
      chatId: (j['chatId'] as num?)?.toInt() ?? 0,
      vacancy: (j['vacancy'] ?? '') as String,
      company: (j['company'] ?? '') as String,
      message: (j['message'] ?? '') as String,
      kind: (j['kind'] ?? '') as String,
      summary: (j['summary'] ?? '') as String,
      detectedAt:
          DateTime.tryParse((j['detectedAt'] ?? '') as String) ?? DateTime(2000),
      messageAt: j['messageAt'] == null
          ? null
          : DateTime.tryParse(j['messageAt'] as String),
    );
  }
}
