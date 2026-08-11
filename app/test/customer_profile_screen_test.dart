import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/data/repos.dart' show PeerBadges;
import 'package:jayalo_app/features/provider/customer_profile_screen.dart';
import 'package:jayalo_app/features/shared/customer_rep_card.dart';

/// Perfil del cliente (mockup aprobado 2026-08-11), montado con dobles: la
/// pantalla no toca Supabase — todo entra por los fetchers inyectables.
void main() {
  const cid = 'cliente-1';

  final repFull = <String, dynamic>{
    'avg_rating': 4.8,
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
    expect(find.text('4.8'), findsOneWidget);
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
        'rating': 4,
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
