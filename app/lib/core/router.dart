import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../features/auth/login_screen.dart';
import '../features/chat/chat_screen.dart';
import '../features/chat/conversations_screen.dart';
import '../features/client/catalog_screen.dart';
import '../features/client/create_request_screen.dart';
import '../features/client/my_requests_screen.dart';
import '../features/client/product_detail_screen.dart';
import '../features/client/reputation_screen.dart';
import '../features/client/request_status_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/onboarding/choose_role_screen.dart';
import '../features/onboarding/consumer_onboarding_screen.dart';
import '../features/onboarding/gate_screen.dart';
import '../features/onboarding/provider_onboarding_screen.dart';
import '../features/provider/inbox_screen.dart';
import '../features/provider/my_business_screen.dart';
import '../features/provider/my_offers_screen.dart';
import '../features/provider/request_detail_screen.dart';
import '../features/provider/stats_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shared/profile_avatar_button.dart';
import '../features/shell/back_guard.dart';
import '../features/shell/home_shell.dart';
import 'motion.dart';
import 'session_state.dart';

GoRouter buildRouter() => GoRouter(
      initialLocation: '/gate',
      refreshListenable: Listenable.merge([_AuthNotifier(), roleStore]),
      redirect: (context, state) {
        final loggedIn = Supabase.instance.client.auth.currentSession != null;
        // Al cerrar sesión, el rol cacheado deja de valer.
        if (!loggedIn && roleStore.value != RoleState.unknown) {
          roleStore.invalidate();
          // El avatar no debe arrastrar la foto/nombre del usuario anterior
          // al siguiente login (mismo teléfono, otra cuenta).
          profileStore.clear();
        }
        return redirectTarget(
            loggedIn: loggedIn,
            role: roleStore.value,
            location: state.matchedLocation);
      },
      routes: [
        GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
        GoRoute(path: '/gate', builder: (_, _) => const GateScreen()),
        GoRoute(path: '/onboarding', builder: (_, _) => const ChooseRoleScreen()),
        GoRoute(
            path: '/onboarding/consumer',
            builder: (_, _) => const ConsumerOnboardingScreen()),
        GoRoute(
            path: '/onboarding/provider',
            builder: (_, _) => const ProviderOnboardingScreen()),
        ShellRoute(
          builder: (_, _, child) => HomeShell(child: child),
          // BackGuard va DENTRO de cada ruta (no en HomeShell) para que el
          // PopScope se registre en el navigator anidado; ver back_guard.dart.
          routes: [
            GoRoute(
                path: '/client',
                builder: (_, _) => const BackGuard(child: MyRequestsScreen())),
            // La ventana de crear solicitud se presenta como MODAL (PO
            // 2026-07-19, revisión visual en device): una ventana por encima
            // de las demás, con esquinas superiores redondeadas, que sube
            // desde abajo con ease-in-out (arranca suave y FRENA antes de
            // llegar a su tope — easeInOutCubic, `emphasized`). `opaque:
            // false` deja viva la pantalla de abajo. Para que de verdad se
            // apile (y esta transición corra), se navega con `push`, no `go`
            // — ver `home_shell.dart`.
            //
            // 2ª pasada del mismo día, verificada con screenshots por adb: a
            // pantalla COMPLETA el modal era invisible como modal — las
            // esquinas quedaban en el borde físico (bajo el status bar) y,
            // con la pantalla de atrás compartiendo el mismo fondo, ni el
            // recorte ni la subida se percibían ("no sube suave con bordes
            // redondeados", PO). Lo que vende la ventana es el HUECO
            // superior: la tarjeta arranca debajo del status bar y en esa
            // franja queda visible la pantalla anterior atenuada por el
            // scrim. `removePadding(removeTop)` evita que el AppBar interno
            // vuelva a reservar un status bar bajo el que ya no está.
            GoRoute(
                path: '/client/create',
                pageBuilder: (context, state) => CustomTransitionPage(
                      key: state.pageKey,
                      opaque: false,
                      barrierColor: Colors.black45,
                      // 3ª pasada PO: 600ms (modalRise) con la curva
                      // enfatizada — frenada MUY visible al llegar al tope.
                      // El cierre se queda en page (300ms): al salir no debe
                      // arrastrar.
                      transitionDuration: JayaloMotion.reduced(context)
                          ? Duration.zero
                          : JayaloMotion.modalRise,
                      reverseTransitionDuration:
                          JayaloMotion.reduced(context)
                              ? Duration.zero
                              : JayaloMotion.page,
                      transitionsBuilder: (context, animation, _, child) =>
                          SlideTransition(
                        position: Tween<Offset>(
                                begin: const Offset(0, 1), end: Offset.zero)
                            .animate(CurvedAnimation(
                                parent: animation,
                                curve: JayaloMotion.rise,
                                reverseCurve: JayaloMotion.emphasized)),
                        child: child,
                      ),
                      child: Builder(
                          builder: (context) => Padding(
                                padding: EdgeInsets.only(
                                    top: MediaQuery.paddingOf(context).top +
                                        12),
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(24)),
                                  child: MediaQuery.removePadding(
                                    context: context,
                                    removeTop: true,
                                    child: const BackGuard(
                                        child: CreateRequestScreen()),
                                  ),
                                ),
                              )))),
            GoRoute(
                path: '/client/reputation',
                builder: (_, _) => const BackGuard(child: ReputationScreen())),
            GoRoute(
                path: '/client/request/:id',
                builder: (_, s) => BackGuard(
                    child:
                        RequestStatusScreen(requestId: s.pathParameters['id']!))),
            // Task 6 (2026-07-18): solo el listado. El cableado de la
            // pestaña en la barra flotante es una tarea posterior — hoy se
            // llega navegando a esta ruta directamente (mismo patrón que
            // `/provider/business`).
            GoRoute(
                path: '/catalog',
                builder: (_, _) => const BackGuard(child: CatalogScreen())),
            // Task 7 (2026-07-19): detalle del producto/servicio + "Me
            // interesa". Modelo `/client/request/:id`: fetch propio por id,
            // AppBar sin campana/avatar (pantalla de detalle, no pestaña raíz).
            GoRoute(
                path: '/catalog/:id',
                builder: (_, s) => BackGuard(
                    child: ProductDetailScreen(
                        productId: s.pathParameters['id']!))),
            GoRoute(
                path: '/provider',
                builder: (_, _) => const BackGuard(child: ProviderInboxScreen())),
            GoRoute(
                path: '/provider/request/:id',
                builder: (_, s) => BackGuard(
                    child: ProviderRequestDetailScreen(
                        requestId: s.pathParameters['id']!))),
            GoRoute(
                path: '/provider/offers',
                builder: (_, _) => const BackGuard(child: MyOffersScreen())),
            GoRoute(
                path: '/provider/stats',
                builder: (_, _) => const BackGuard(child: StatsScreen())),
            // Task 4 (2026-07-18): la pantalla ya existe; el cableado de la
            // pestaña en la barra flotante es una tarea posterior — hoy se
            // llega navegando a esta ruta directamente.
            GoRoute(
                path: '/provider/business',
                builder: (_, _) =>
                    const BackGuard(child: MyBusinessScreen())),
            GoRoute(
                path: '/settings',
                builder: (_, _) => const BackGuard(child: SettingsScreen())),
            GoRoute(
                path: '/messages',
                builder: (_, _) => const BackGuard(child: ConversationsScreen())),
            GoRoute(
                path: '/messages/:id',
                builder: (_, s) {
                  // Task I-2: peer_name/avatar llegan por `extra` desde la
                  // lista de conversaciones (evita el RPC agregado). Si no
                  // vienen (deep-link/push futuro), quedan null y ChatScreen
                  // cae al fallback con `conversationsList()`.
                  final x = s.extra;
                  final m = x is Map ? x : null;
                  return BackGuard(
                      child: ChatScreen(
                          conversationId: s.pathParameters['id']!,
                          peerName: m?['peer_name'] as String?,
                          peerAvatarUrl: m?['peer_avatar_url'] as String?));
                }),
            // Una de las 4 excepciones pedidas por el PO (2026-07-19, 4ª
            // pasada) que SÍ conserva animación tras retirar el deslizado
            // general de sección: fade + leve deslizado desde la derecha,
            // 300ms — corto, sin el frenado de 2s que se quitó del resto.
            GoRoute(
                path: '/notifications',
                pageBuilder: (context, state) => CustomTransitionPage(
                      key: state.pageKey,
                      transitionDuration: JayaloMotion.reduced(context)
                          ? Duration.zero
                          : JayaloMotion.page,
                      reverseTransitionDuration: JayaloMotion.reduced(context)
                          ? Duration.zero
                          : JayaloMotion.page,
                      transitionsBuilder: (context, animation, _, child) {
                        final curved = CurvedAnimation(
                            parent: animation,
                            curve: JayaloMotion.enter,
                            reverseCurve: JayaloMotion.exit);
                        return FadeTransition(
                          opacity: curved,
                          child: SlideTransition(
                            position: Tween<Offset>(
                                    begin: const Offset(.06, 0),
                                    end: Offset.zero)
                                .animate(curved),
                            child: child,
                          ),
                        );
                      },
                      child: const BackGuard(child: NotificationsScreen()),
                    )),
          ],
        ),
      ],
    );

class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier() {
    Supabase.instance.client.auth.onAuthStateChange.listen((_) => notifyListeners());
  }
}
