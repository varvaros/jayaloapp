import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/data/repos.dart' show PeerBadges;
import 'package:jayalo_app/features/provider/customer_profile_screen.dart';
import 'package:jayalo_app/features/shared/customer_rep_card.dart';

/// Perfil del cliente (mockup aprobado 2026-08-11), montado con dobles: la
/// pantalla no toca Supabase — todo entra por los fetchers inyectables.
void main() {
  const cid = 'cliente-1';

  // La escala es 1-10 (`customer_reviews.rating`, CHECK 1..10). El fixture valía
  // 4.8 cuando la app escribía 1-5 por error; con esa escala un 4.8 era un cliente
  // excelente y ahora sería mediocre, así que se sube para que represente lo mismo.
  final repFull = <String, dynamic>{
    'avg_rating': 8.6,
    'reviews_count': 6,
    'completed_purchases': 2,
    'requests_count': 4,
    'median_response_minutes': 720.0,
    'response_samples': 5,
  };

  Widget screen({
    bool unlocked = false,
    String? firstName,
    String? lastName,
    String? avatarUrl,
    Map<String, dynamic>? rep,
    List<Map<String, dynamic>> reviews = const [],
    PeerBadges? badges,
  }) =>
      MaterialApp(
        home: CustomerProfileScreen(
          customerId: cid,
          fetchProfile: (_,
                  {String? requestId, String? offerId, String? interestId}) async =>
              (
            unlocked: unlocked,
            firstName: firstName,
            lastName: lastName,
            avatarUrl: avatarUrl,
          ),
          fetchReputation: ([_]) async => rep,
          fetchReviews: (_, {int limit = 5}) async => reviews,
          fetchBadges: (_) async =>
              badges == null ? {} : {cid: badges},
        ),
      );

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(); // resuelve los futures de _load
    await tester.pump(); // pinta el estado cargado
  }

  testWidgets('anónimo: alias, aviso de anonimato y tiles con los agregados',
      (tester) async {
    await tester.pumpWidget(screen(rep: repFull));
    await settle(tester);
    expect(find.text(CustomerRepCard.aliasFor(cid)), findsOneWidget);
    expect(find.text('Nombre y foto al desbloquear el contacto'),
        findsOneWidget);
    expect(find.textContaining('Este perfil es anónimo'), findsOneWidget);
    expect(find.text('~12 h'), findsOneWidget); // 720 min → destacada
    expect(find.text('8.6/10'), findsOneWidget);
    expect(find.text('Solicitudes publicadas'), findsOneWidget);
    expect(find.text('Compras cerradas'), findsOneWidget);
  });

  testWidgets('desbloqueado: nombre real, sin aviso de anonimato',
      (tester) async {
    await tester.pumpWidget(screen(
      unlocked: true,
      firstName: 'Amaury',
      lastName: 'Rodríguez',
      rep: repFull,
    ));
    await settle(tester);
    expect(find.text('Amaury Rodríguez'), findsOneWidget);
    expect(find.text('Contacto desbloqueado'), findsOneWidget);
    expect(find.textContaining('Este perfil es anónimo'), findsNothing);
  });

  testWidgets('reseñas de otros proveedores: comentario + negocio',
      (tester) async {
    await tester.pumpWidget(screen(rep: repFull, reviews: [
      {
        'rating': 8,
        'comment': 'Pagó al momento y respondió rápido.',
        'business_name': 'Ferretería El Sol',
        'created_at':
            DateTime.now().subtract(const Duration(days: 3)).toIso8601String(),
      },
    ]));
    await settle(tester);
    expect(find.text('LO QUE DICEN LOS PROVEEDORES'), findsOneWidget);
    expect(
        find.text('Pagó al momento y respondió rápido.'), findsOneWidget);
    expect(find.textContaining('Ferretería El Sol'), findsOneWidget);
    // La nota se escribe: sin el número, un 6, un 8 y un 10 pintan las mismas
    // estrellas y el bug de escala vuelve a ser invisible.
    expect(find.text('8 / 10'), findsOneWidget);
  });

  testWidgets('sin reseñas la sección no aparece', (tester) async {
    await tester.pumpWidget(screen(rep: repFull));
    await settle(tester);
    expect(find.text('LO QUE DICEN LOS PROVEEDORES'), findsNothing);
  });

  testWidgets('sin muestras suficientes el tiempo de respuesta dice —',
      (tester) async {
    await tester.pumpWidget(screen(rep: {
      ...repFull,
      'median_response_minutes': 30.0,
      'response_samples': 1, // < 3 muestras: no se afirma nada
    }));
    await settle(tester);
    expect(find.text('—'), findsWidgets);
    expect(find.text('~30 min'), findsNothing);
  });
}
