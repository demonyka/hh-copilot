/// Данные hh.ru-аккаунта пользователя (владелец резюме).
class HhAccount {
  const HhAccount({
    this.firstName = '',
    this.middleName = '',
    this.lastName = '',
    this.email = '',
    this.userId = 0,
  });

  final String firstName;
  final String middleName;
  final String lastName;
  final String email;
  final int userId;

  String get fullName =>
      [firstName, lastName].where((s) => s.trim().isNotEmpty).join(' ').trim();

  String get initials {
    final f = firstName.trim();
    final l = lastName.trim();
    final buf = StringBuffer();
    if (f.isNotEmpty) buf.write(f.substring(0, 1).toUpperCase());
    if (l.isNotEmpty) buf.write(l.substring(0, 1).toUpperCase());
    final res = buf.toString();
    return res.isEmpty ? '?' : res;
  }

  /// Признак того, что перед нами авторизованная сессия hh.ru,
  /// а не гостевая страница логина.
  bool get isAuthenticated => userId > 0 || email.trim().isNotEmpty;
}

/// Одно резюме пользователя на hh.ru.
class HhResume {
  const HhResume({
    required this.id,
    required this.hash,
    required this.title,
    required this.area,
    required this.salaryAmount,
    required this.salaryCurrency,
    required this.skills,
    required this.percent,
    required this.status,
  });

  final String id;
  final String hash;
  final String title;
  final String area;
  final int salaryAmount;
  final String salaryCurrency;
  final List<String> skills;

  /// Процент заполненности резюме (0..100), если известен.
  final int? percent;

  /// Внутренний статус публикации hh.ru (published/not_published/blocked/...).
  final String? status;

  bool get hasSalary => salaryAmount > 0;

  /// Человекочитаемая зарплата, например «150 000 ₽».
  String get salaryLabel {
    if (!hasSalary) return 'Зарплата не указана';
    return '${_formatThousands(salaryAmount)} ${_currencySymbol(salaryCurrency)}';
  }

  bool get isPublished => status == 'published';

  String get statusLabel {
    switch (status) {
      case 'published':
        return 'Опубликовано';
      case 'not_published':
        return 'Не опубликовано';
      case 'blocked':
        return 'Заблокировано';
      case 'deleted':
        return 'Удалено';
      default:
        return status == null || status!.isEmpty ? 'Черновик' : status!;
    }
  }

  static String _currencySymbol(String code) {
    switch (code.toUpperCase()) {
      case 'RUR':
      case 'RUB':
        return '₽';
      case 'USD':
        return r'$';
      case 'EUR':
        return '€';
      case 'KZT':
        return '₸';
      case 'BYR':
      case 'BYN':
        return 'Br';
      case 'UAH':
        return '₴';
      default:
        return code;
    }
  }

  static String _formatThousands(int value) {
    final digits = value.toString();
    final buf = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(' ');
      buf.write(digits[i]);
    }
    return buf.toString();
  }
}

/// Полный снимок профиля hh.ru: аккаунт + список резюме.
class HhProfile {
  const HhProfile({
    required this.account,
    required this.resumes,
    required this.latestResumeHash,
  });

  final HhAccount account;
  final List<HhResume> resumes;
  final String latestResumeHash;

  bool get isAuthenticated => account.isAuthenticated;
}
