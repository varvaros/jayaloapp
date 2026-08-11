import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/repos.dart' show isAdmin;
import '../features/auth/login_screen.dart';
import '../features/chat/chat_screen.dart';
import '../features/chat/conversations_screen.dart';
import '../features/client/catalog_screen.dart';
import '../features/client/create_request_screen.dart';
import '../features/client/my_requests_screen.dart';
import '../features/client/other_request_screen.dart';
import '../features/client/package_detail_screen.dart';
import '../features/client/product_detail_screen.dart';
import '../features/client/provider_store_screen.dart';
import '../features/admin/quick_register_screen.dart';
import '../features/client/reputation_screen.dart';
import '../features/client/request_status_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/onboarding/choose_role_screen.dart';
import '../features/onboarding/consumer_onboarding_screen.dart';
import '../features/onboarding/gate_screen.dart';
import '../features/onboarding/provider_onboarding_screen.dart';
import '../features/provider/credit_shop_screen.dart';
import '../features/provider/customer_profile_screen.dart';
import '../features/provider/inbox_screen.dart';
import '../features/provider/add_store_item_screen.dart';
import '../features/provider/my_business_screen.dart';
import '../features/provider/package_editor_screen.dart';
import '../features/provider/my_offers_screen.dart';
import '../features/provider/product_interest_detail_screen.dart';
import '../features/provider/request_detail_screen.dart';
import '../features/provider/stats_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/settings/address_screen.dart';
import '../features/settings/quick_replies_editor_screen.dart';
import '../features/shared/profile_avatar_button.dart';
import '../features/shell/back_guard.dart';
import '../features/shell/home_shell.dart';
import 'motion.dart';
import 'session_state.dart';

/// Navigator RAÍZ. Las rutas full-screen que deben cubrir TODO (tienda del
/// proveedor, chat) viven como rutas TOP-LEVEL, hermanas del ShellRoute — así
/// se apilan en este navigator por naturaleza, por encima de la barra
/// flotante. GOTCHA (QA 2026-07-21, "no abre el chat / la tienda"): NO
/// declararlas DENTRO del ShellRoute con `parentNavigatorKey: _rootNavigatorKey`
/// — go_router lo PROHÍBE con un assert ("sub-route's parent navigator key must
/// either be null or has the same navigator key as parent's key") que en
/// release se elimina, y el push simplemente no monta la página: falla en
/// silencio.
final _rootNavigatorKey = GlobalKey<NavigatorState>();

GoRouter buildRouter() => GoRouter(
      initialLocation: '/gate',
      navigatorKey: _rootNavigatorKey,
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
                                    child: BackGuard(
                                        child: CreateRequestScreen(
                                            seedFrom: state.uri
                                                .queryParameters['seedFrom'])),
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
            GoRoute(
                path: '/client/other-request/:id',
                builder: (_, s) => BackGuard(
                    child: OtherRequestScreen(
                        requestId: s.pathParameters['id']!))),
            // Task 6 (2026-07-18): solo el listado. El cableado de la
            // pestaña en la barra flotante es una tarea posterior — hoy se
            // llega navegando a esta ruta directamente (mismo patrón que
            // `/provider/business`).
            GoRoute(
                path: '/catalog',
                // `?focus=1` (desde el buscador de Mis solicitudes) abre el
                // catálogo con el buscador enfocado.
                builder: (_, s) => BackGuard(
                    child: CatalogScreen(
                        autofocusSearch:
                            s.uri.queryParameters['focus'] == '1'))),
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
                        requestId: s.pathParameters['id']!,
                        // `?edit=<offerId>`: entra en modo edición de una oferta
                        // PENDIENTE propia (desde "Mis ofertas").
                        editOfferId: s.uri.queryParameters['edit']))),
            // Interés de producto (alguien tocó "Me interesa" en el catálogo).
            // Era una hoja dentro del inbox; el PO la pidió como pantalla,
            // igual que el detalle de solicitud (2026-08-01). El `extra` trae
            // la fila que el inbox ya tiene cargada, para pintar sin esperar.
            GoRoute(
                path: '/provider/interest/:id',
                builder: (_, s) => BackGuard(
                    child: ProductInterestDetailScreen(
                        interestId: s.pathParameters['id']!,
                        initial: s.extra as Map<String, dynamic>?))),
            // Perfil del cliente visto por el proveedor (mockup aprobado
            // 2026-08-11): anónimo hasta el desbloqueo, identidad real
            // después — quién está desbloqueado lo decide la RPC, no la ruta.
            GoRoute(
                path: '/provider/customer/:id',
                builder: (_, s) => BackGuard(
                    child: CustomerProfileScreen(
                        customerId: s.pathParameters['id']!))),
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
            // Alta rápida del agregador de "Mi negocio" (PO 2026-08-05).
            // `kind` y `bid` viajan por query: la pantalla de origen ya tiene
            // el negocio cargado y así no se repite el fetch. `extra` (Task 6,
            // 2026-08-09) trae la fila completa cuando se abre para EDITAR
            // (tocar una tarjeta propia) — no cabe en query params.
            GoRoute(
                path: '/provider/business/add',
                builder: (_, s) => BackGuard(
                    child: AddStoreItemScreen(
                        kind: s.uri.queryParameters['kind'] ?? 'producto',
                        businessId: s.uri.queryParameters['bid'] ?? '',
                        initial: s.extra as Map<String, dynamic>?))),
            // Editor de paquetes/planes de "Mi negocio" (Task 7, 2026-08-09).
            // Mismo patrón que `/provider/business/add`: `bid` por query,
            // `extra` con la fila completa al EDITAR un paquete propio.
            GoRoute(
                path: '/provider/business/package',
                builder: (_, s) => BackGuard(
                    child: PackageEditorScreen(
                        businessId: s.uri.queryParameters['bid'] ?? '',
                        initial: s.extra as Map<String, dynamic>?))),
            // Tienda de créditos IN-APP. Sustituye al link-out al wallet web
            // (ADR-0031): Play prohíbe llevar al usuario a otro método de pago.
            GoRoute(
                path: '/tienda-creditos',
                builder: (_, _) => const BackGuard(child: CreditShopScreen())),
            GoRoute(
                path: '/settings',
                builder: (_, _) => const BackGuard(child: SettingsScreen())),
            GoRoute(
                path: '/settings/quick-replies',
                builder: (_, _) =>
                    const BackGuard(child: QuickRepliesEditorScreen())),
            GoRoute(
                path: '/settings/address',
                builder: (_, _) => const BackGuard(child: AddressScreen())),
            GoRoute(
                path: '/admin/quick-register',
                // El ítem del menú ya está gateado por `isAdmin()`
                // (profile_avatar_button), pero la RUTA no lo estaba: cualquiera
                // podía llegar por navegación directa y ver el formulario. La
                // barrera real es server-side — la edge function
                // `admin-invite-provider` responde 403 a quien no sea admin — así
                // que esto es defensa en profundidad, no el único candado.
                // `isAdmin()` va cacheado (AppCaches.isAdmin), no pega a la BD
                // en cada navegación.
                redirect: (_, _) async => await isAdmin() ? null : '/gate',
                builder: (_, _) =>
                    const BackGuard(child: AdminQuickRegisterScreen())),
            GoRoute(
                path: '/messages',
                builder: (_, _) => const BackGuard(child: ConversationsScreen())),
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
        // ─── Rutas FULL-SCREEN sobre el shell (navigator raíz) ───
        // Declaradas FUERA del ShellRoute a propósito: cubren toda la pantalla
        // (incluida la barra flotante) al apilarse con push. Ver el gotcha
        // documentado junto a `_rootNavigatorKey`.
        //
        // Tienda de un proveedor (desde una oferta o el catálogo): identidad
        // real (PO 2026-07-28). Entra como VENTANA deslizando DESDE LA
        // DERECHA (pedido PO 2026-07-22).
        GoRoute(
            path: '/store/:bid',
            pageBuilder: (context, s) => CustomTransitionPage(
                  key: s.pageKey,
                  transitionDuration: JayaloMotion.reduced(context)
                      ? Duration.zero
                      : JayaloMotion.page,
                  reverseTransitionDuration: JayaloMotion.reduced(context)
                      ? Duration.zero
                      : JayaloMotion.page,
                  transitionsBuilder: (context, animation, _, child) =>
                      SlideTransition(
                    position: Tween<Offset>(
                            begin: const Offset(1, 0), end: Offset.zero)
                        .animate(CurvedAnimation(
                            parent: animation,
                            curve: JayaloMotion.enter,
                            reverseCurve: JayaloMotion.exit)),
                    child: child,
                  ),
                  child: BackGuard(
                      child: ProviderStoreScreen(
                          businessId: s.pathParameters['bid']!)),
                )),
        // Detalle de producto ABIERTO DESDE LA TIENDA (`/store/:bid`): como la
        // tienda vive en el navigator raíz, empujar la ruta del shell
        // `/catalog/:id` desde ella montaba el detalle DEBAJO de la tienda y
        // se veía vacío (QA PO 2026-07-21). Esta variante top-level apila el
        // mismo ProductDetailScreen ENCIMA de la tienda. `ProductListCard`
        // decide cuál de las dos rutas usar según dónde está.
        GoRoute(
            path: '/product/:id',
            pageBuilder: (context, s) => CustomTransitionPage(
                  key: s.pageKey,
                  transitionDuration: JayaloMotion.reduced(context)
                      ? Duration.zero
                      : JayaloMotion.page,
                  reverseTransitionDuration: JayaloMotion.reduced(context)
                      ? Duration.zero
                      : JayaloMotion.page,
                  transitionsBuilder: (context, animation, _, child) =>
                      SlideTransition(
                    position: Tween<Offset>(
                            begin: const Offset(1, 0), end: Offset.zero)
                        .animate(CurvedAnimation(
                            parent: animation,
                            curve: JayaloMotion.enter,
                            reverseCurve: JayaloMotion.exit)),
                    child: child,
                  ),
                  child: BackGuard(
                      child: ProductDetailScreen(
                          productId: s.pathParameters['id']!)),
                )),
        // Detalle de PAQUETE, abierto desde la tienda (`/store/:bid`) —
        // pedido PO 2026-08-09: "El paquete no abre nada". Misma razón que
        // `/product/:id`: la tienda vive en el navigator raíz, así que esta
        // ruta también va top-level (nunca dentro del ShellRoute) para
        // apilarse ENCIMA de ella en vez de quedar oculta debajo.
        GoRoute(
            path: '/package/:id',
            pageBuilder: (context, s) => CustomTransitionPage(
                  key: s.pageKey,
                  transitionDuration: JayaloMotion.reduced(context)
                      ? Duration.zero
                      : JayaloMotion.page,
                  reverseTransitionDuration: JayaloMotion.reduced(context)
                      ? Duration.zero
                      : JayaloMotion.page,
                  transitionsBuilder: (context, animation, _, child) =>
                      SlideTransition(
                    position: Tween<Offset>(
                            begin: const Offset(1, 0), end: Offset.zero)
                        .animate(CurvedAnimation(
                            parent: animation,
                            curve: JayaloMotion.enter,
                            reverseCurve: JayaloMotion.exit)),
                    child: child,
                  ),
                  child: BackGuard(
                      child: PackageDetailScreen(
                          packageId: s.pathParameters['id']!)),
                )),
        // Chat: Scaffold de PRIMER NIVEL para que el composer reciba el inset
        // real del sistema (anidado bajo el Scaffold del shell con su
        // bottomNavigationBar, el inset quedaba recortado y el campo de
        // escribir se pegaba al borde inferior — QA 2026-07-21).
        GoRoute(
            path: '/messages/:id',
            pageBuilder: (context, s) {
              // Task I-2: peer_name/avatar llegan por `extra` desde la
              // lista de conversaciones (evita el RPC agregado). Si no
              // vienen (deep-link/push futuro), quedan null y ChatScreen
              // cae al fallback con `conversationsList()`.
              final x = s.extra;
              final m = x is Map ? x : null;
              return CustomTransitionPage(
                key: s.pageKey,
                transitionDuration: JayaloMotion.reduced(context)
                    ? Duration.zero
                    : JayaloMotion.page,
                reverseTransitionDuration: JayaloMotion.reduced(context)
                    ? Duration.zero
                    : JayaloMotion.page,
                transitionsBuilder: (context, animation, _, child) =>
                    SlideTransition(
                  position: Tween<Offset>(
                          begin: const Offset(1, 0), end: Offset.zero)
                      .animate(CurvedAnimation(
                          parent: animation,
                          curve: JayaloMotion.enter,
                          reverseCurve: JayaloMotion.exit)),
                  child: child,
                ),
                // BackGuard maneja el atrás del sistema → `go('/messages')`
                // (vuelve a la lista). Funciona porque el predictive-back está
                // DESACTIVADO en el manifest (enableOnBackInvokedCallback=false):
                // en el camino legacy el PopScope de BackGuard se dispara aunque
                // sea un route directo del navigator raíz. Con predictive-back
                // activo (default de targetSdk 36) esto minimizaba (bug PO
                // 2026-07-23) — ver AndroidManifest.xml.
                child: BackGuard(
                    child: ChatScreen(
                        conversationId: s.pathParameters['id']!,
                        peerName: m?['peer_name'] as String?,
                        peerAvatarUrl: m?['peer_avatar_url'] as String?)),
              );
            }),
      ],
    );

/// Sustituye a `openProviderWallet` (ADR-0031). El pago ocurre DENTRO de la
/// app: Play prohíbe llevar al usuario a otro método de pago.
Future<void> openCreditShop(BuildContext context) =>
    context.push('/tienda-creditos');

class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier() {
    Supabase.instance.client.auth.onAuthStateChange.listen((_) => notifyListeners());
  }
}
