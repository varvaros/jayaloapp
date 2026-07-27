import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/shared/onboarding_copy.dart';

void main() {
  test('todas las claves nuevas de onboarding existen y no van vacías', () {
    // Claves de las guías YA cableadas en pantallas (una pantalla que hace
    // `onboardingCopy['clave']!` revienta al build si falta). Se van sumando
    // por task: Task 6 (`client.catalog.v1`) y Task 7 (`chat.quick_replies.v1`,
    // `chat.report.v1`, en el composer/⋮ del chat) ya aterrizaron y suman las
    // suyas, para que la suite quede verde en cada frontera de task.
    const keys = [
      'client.plus.v1',
      'client.my_requests.v1',
      'client.others_requests.v1',
      'client.request_kind.v1',
      'client.request_photo.v1',
      'client.request_wholesale.v1',
      'client.catalog.v1',
      'chat.quick_replies.v1',
      'chat.report.v1',
    ];
    for (final k in keys) {
      expect(onboardingCopy.containsKey(k), isTrue, reason: 'falta $k');
      expect(onboardingCopy[k]!, isNotEmpty, reason: '$k sin pasos');
      expect(onboardingCopy[k]!.first.message.trim(), isNotEmpty,
          reason: '$k con mensaje vacío');
    }
  });
}
