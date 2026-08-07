import 'package:flutter_test/flutter_test.dart';
import 'package:hh_copilot/services/hh_profile_parser.dart';

void main() {
  // Собираем JSON как его отдаёт hh.ru: встроенный в HTML и с экранированными
  // кавычками (&#34;). Парсер обязан развернуть энтити и достать данные.
  const rawJson =
      '{"redirectConfig":{"strictMode":true},'
      '"account":{"firstName":"Иван","middleName":"Сергеевич","lastName":"Петров","email":"ivan@example.com"},'
      '"userNotifications":[{"userId":12345}],'
      '"latestResumeHash":"abc123def456abc123def456abc123",'
      '"applicantResumes":[{'
      '"_attributes":{"id":"77","hash":"abcdef0123","percent":85,"status":"published"},'
      '"title":[{"string":"Flutter-разработчик"}],'
      '"area":[{"title":"Москва"}],'
      '"salary":[{"amount":250000,"currency":"RUR"}],'
      '"keySkills":[{"string":"Dart"},{"string":"Flutter"}]'
      '}]}';

  String asHhPage(String json) {
    final escaped = json.replaceAll('"', '&#34;');
    return '<!DOCTYPE html><html><body>'
        '<template id="hh-page-data">$escaped</template>'
        '</body></html>';
  }

  group('HhProfileParser', () {
    test('парсит аккаунт и резюме из экранированной страницы hh.ru', () {
      final profile = HhProfileParser.parse(asHhPage(rawJson));

      expect(profile, isNotNull);
      expect(profile!.isAuthenticated, isTrue);

      expect(profile.account.firstName, 'Иван');
      expect(profile.account.lastName, 'Петров');
      expect(profile.account.email, 'ivan@example.com');
      expect(profile.account.userId, 12345);
      expect(profile.account.fullName, 'Иван Петров');
      expect(profile.account.initials, 'ИП');

      expect(profile.latestResumeHash, 'abc123def456abc123def456abc123');

      expect(profile.resumes, hasLength(1));
      final r = profile.resumes.single;
      expect(r.id, '77');
      expect(r.hash, 'abcdef0123');
      expect(r.title, 'Flutter-разработчик');
      expect(r.area, 'Москва');
      expect(r.salaryAmount, 250000);
      expect(r.salaryCurrency, 'RUR');
      expect(r.salaryLabel, '250 000 ₽');
      expect(r.percent, 85);
      expect(r.status, 'published');
      expect(r.isPublished, isTrue);
      expect(r.skills, ['Dart', 'Flutter']);
    });

    test('возвращает null для гостевой страницы без аккаунта', () {
      const guest = '<html><body><h1>Вход на hh.ru</h1></body></html>';
      expect(HhProfileParser.parse(guest), isNull);
    });

    test('htmlUnescape разворачивает числовые и именованные энтити', () {
      expect(HhProfileParser.htmlUnescape('a &#34;b&#34; c'), 'a "b" c');
      expect(HhProfileParser.htmlUnescape('&#x41;&amp;&lt;&gt;'), 'A&<>');
      expect(HhProfileParser.htmlUnescape('&laquo;тест&raquo;'), '«тест»');
    });

    test('зарплата не указана, когда salary пуст', () {
      const noSalary =
          '{"redirectConfig":{},'
          '"account":{"firstName":"Анна","lastName":"Смирнова","email":"a@b.ru"},'
          '"userNotifications":[{"userId":999}],'
          '"latestResumeHash":"deadbeefdeadbeefdeadbeefdeadbeef",'
          '"applicantResumes":[{'
          '"_attributes":{"id":"1","hash":"h1"},'
          '"title":[{"string":"Тестировщик"}],'
          '"area":[{"title":"Казань"}],'
          '"salary":[],'
          '"keySkills":[]'
          '}]}';
      final profile = HhProfileParser.parse(asHhPage(noSalary));
      expect(profile, isNotNull);
      final r = profile!.resumes.single;
      expect(r.hasSalary, isFalse);
      expect(r.salaryLabel, 'Зарплата не указана');
      expect(r.statusLabel, 'Черновик');
    });
  });
}
