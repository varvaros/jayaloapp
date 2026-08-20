import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/brand.dart';
import '../../core/config.dart';
import '../../core/motion.dart';
import '../../core/turnstile.dart';
import '../shared/brand_kit.dart' show JayaloCard;
import '../shared/jayalo_loader.dart';
import 'intro_copy.dart';
import 'intro_role_store.dart';
import 'intro_seen_store.dart';
import 'jayalo_imagotipo.dart';
import 'jayi_scene.dart';
import 'portada_jayi.dart';

/// El usuario cerró el selector de cuenta de Google. No es un fallo: no hay que
/// enseñarle ningún error.
class SignInCancelled implements Exception {
  const SignInCancelled();
}

Future<void> signInWithGoogleNative(BuildContext context) async {
  final google = GoogleSignIn(serverClientId: AppConfig.googleWebClientId);
  final account = await google.signIn();
  if (account == null) throw const SignInCancelled();
  final auth = await account.authentication;
  final idToken = auth.idToken;
  if (idToken == null) throw Exception('Google no devolvió idToken');

  final supa = Supabase.instance.client.auth;
  try {
    await supa.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: auth.accessToken,
    );
  } on AuthException catch (e) {
    // CAPTCHA global de Supabase (ADR-0028): reintento con token Turnstile.
    if (!e.message.toLowerCase().contains('captcha')) rethrow;
    if (!context.mounted) rethrow;
    final captcha = await getTurnstileToken(context);
    await supa.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: auth.accessToken,
      captchaToken: captcha,
    );
  }
}

/// Entra con correo y contraseña (las cuentas creadas en jayalo.com).
///
/// La app SOLO tenía Google, así que quien se registraba en la web con un
/// correo que no fuera de Google se quedaba fuera (2026-08-10). El registro
/// sigue siendo nativo por Google: esto es únicamente una puerta de entrada
/// para cuentas que ya existen.
///
/// Mismo reintento con Turnstile que el login de Google: el CAPTCHA global de
/// Supabase (ADR-0028) también aplica a esta vía.
Future<void> signInWithPasswordNative(
  BuildContext context,
  String email,
  String password,
) async {
  final supa = Supabase.instance.client.auth;
  try {
    await supa.signInWithPassword(email: email, password: password);
  } on AuthException catch (e) {
    if (!e.message.toLowerCase().contains('captcha')) rethrow;
    if (!context.mounted) rethrow;
    final captcha = await getTurnstileToken(context);
    await supa.signInWithPassword(
      email: email,
      password: password,
      captchaToken: captcha,
    );
  }
}

/// Traduce un fallo de [signInWithPasswordNative] a algo accionable. Pura y
/// pública para fijarla en un test: el mensaje crudo de Supabase llega en
/// inglés ("Invalid login credentials") y no le dice al usuario qué hacer.
String passwordLoginError(Object e) {
  final m = e is AuthException ? e.message.toLowerCase() : '';
  if (m.contains('invalid login credentials') ||
      m.contains('invalid_credentials')) {
    return 'Correo o contraseña incorrectos.';
  }
  if (m.contains('email not confirmed')) {
    return 'Confirma tu correo desde el enlace que te enviamos y vuelve a entrar.';
  }
  if (m.contains('too many') || m.contains('rate limit')) {
    return 'Demasiados intentos. Espera unos minutos e inténtalo de nuevo.';
  }
  return 'No pudimos entrar. Revisa tu conexión e inténtalo de nuevo.';
}

/// Primera apertura de la app: carrusel de TRES láminas que termina en los
/// accesos de siempre.
///
/// Las láminas viven aquí dentro y no en rutas nuevas por un motivo duro:
/// `redirectTarget()` empieza con `if (!loggedIn) return onLogin ? null :
/// '/login';` — sin sesión, toda ruta que no sea `/login` rebota. Metiendo el
/// carrusel dentro de `/login` no se toca el router.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;

  final _pages = PageController();

  /// La elección de rol YA GUARDADA. `null` = todavía no eligió, y entonces las
  /// láminas 2 y 3 no existen (ver [_pageCount]).
  IntroRole? _introRole;

  /// Tocó «Saltar» sin elegir lado. No guarda nada — tras autenticar cae en
  /// `ChooseRoleScreen`, que es la red de seguridad prevista — pero sí abre el
  /// carrusel para poder enseñarle la lámina de cierre.
  bool _skipped = false;

  int _page = 0;

  /// ¿Este teléfono ya vio el intro? `null` mientras se lee del disco: en ese
  /// primer frame no se pinta NI el carrusel ni la portada, porque acertar por
  /// defecto es imposible y equivocarse se ve como un parpadeo entre dos
  /// pantallas muy distintas. La lectura es de `SharedPreferences`, o sea un
  /// puñado de microsegundos sobre un mapa ya cargado en memoria.
  bool? _introSeen;

  /// Ya se escribió la marca en esta sesión de pantalla. `_introSeen` NO sirve
  /// de guarda: sigue valiendo `false` (estamos en modo intro) después de
  /// marcar, y sin esto cada deslizamiento hasta los accesos repetiría la
  /// escritura en disco.
  bool _seenMarked = false;

  /// Hay una elección en vuelo (guardando o avanzando la lámina). Ver la guarda
  /// de reentrada de [_chooseRole].
  bool _choosing = false;

  /// Sin rol elegido el carrusel es de UNA lámina: así no se puede deslizar a
  /// una lámina que todavía no sabe de qué lado está el usuario. En cuanto se
  /// «Salta» sin elegir, se abre una segunda (y última) lámina de cierre
  /// NEUTRO — no las 3 del camino con rol, porque no hay rol con el que
  /// pintar contenido dedicado para una lámina intermedia.
  int get _pageCount {
    if (_introRole != null) return 3;
    return _skipped ? 2 : 1;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// Decide en qué modo abre el login y, si toca el carrusel, en qué lámina.
  ///
  /// **Modo clásico** (marca `IntroSeenStore` puesta): la Portada Jayi de
  /// siempre. El intro es de UNA VEZ POR TELÉFONO (PO 2026-08-20), así que
  /// quien cierra sesión y vuelve —o el segundo usuario del mismo aparato— ya
  /// no lo ve. Elegir lado pasa a ser trabajo de `ChooseRoleScreen`, que sigue
  /// intacto detrás de `/onboarding`.
  ///
  /// **Modo intro**: además se restaura la elección PENDIENTE de consumir, que
  /// sobrevive a matar la app — quien eligió lado y se fue antes de
  /// autenticarse vuelve directo a la lámina de acceso. Esa sí es memoria
  /// efímera: el alta la consume y la borra (`IntroRoleStore.clear()`), porque
  /// su clave no lleva uid y si no el siguiente que se registrara en el mismo
  /// teléfono heredaría la elección del anterior.
  Future<void> _restore() async {
    final seen = await IntroSeenStore().read();
    if (!mounted) return;
    if (seen) {
      setState(() => _introSeen = true);
      return;
    }
    final role = await IntroRoleStore().read();
    if (!mounted) return;
    setState(() {
      _introSeen = false;
      if (role == null) return;
      _introRole = role;
      _page = 2; // los puntos y el «Saltar» ya nacen en su sitio, sin parpadeo
    });
    if (role == null) return;
    // Volver con lado ya elegido aterriza en los accesos, que es el final del
    // carrusel: para el usuario el intro ya está visto.
    _markSeenIfDone();
    unawaited(
      _afterLayout(() async {
        if (_pages.hasClients) _pages.jumpToPage(2);
      }),
    );
  }

  /// ¿La lámina `i` es la de los accesos, o sea el FINAL del carrusel?
  ///
  /// No vale `i == _pageCount - 1`: mientras no se elige lado ni se salta, el
  /// carrusel mide UNA lámina y esa única lámina es la de los recuadros de rol
  /// — marcar ahí daría el intro por visto a quien no ha visto nada. Ver
  /// [_buildSlide], que reparte las acciones con este mismo criterio.
  bool _isAccessSlide(int i) => _introRole == null ? i >= 1 : i >= 2;

  /// Deja la marca de «visto» en cuanto el usuario alcanza los accesos, por
  /// cualquiera de los tres caminos (elegir lado y avanzar, «Saltar», o volver
  /// con lado ya elegido). No se retira nunca: deslizar hacia atrás a mirar
  /// otra lámina no deshace el haberlo visto.
  void _markSeenIfDone() {
    if (_seenMarked || _introSeen != false) return; // ya marcado, o sin leer
    if (!_isAccessSlide(_page)) return;
    _seenMarked = true;
    unawaited(IntroSeenStore().markSeen());
  }

  /// Mueve el carrusel DESPUÉS del frame en el que ya hay 3 páginas: pedirle a
  /// `PageController` la página 1 mientras el viewport todavía mide una sola
  /// deja la posición fuera de rango. El futuro que devuelve se cierra cuando
  /// termina la transición, para poder esperarla.
  Future<void> _afterLayout(Future<void> Function() fn) {
    final done = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        done.complete();
        return;
      }
      fn().whenComplete(done.complete);
    });
    return done.future;
  }

  Future<void> _goToPage(int i) async {
    if (!_pages.hasClients) return;
    if (JayaloMotion.reduced(context)) {
      _pages.jumpToPage(i);
      return;
    }
    return _pages.animateToPage(
      i,
      duration: JayaloMotion.page,
      curve: JayaloMotion.emphasized,
    );
  }

  /// Los recuadros NO navegan: guardan el lado elegido y avanzan la lámina.
  ///
  /// Guarda de reentrada hasta que la lámina termina de entrar: tocar los dos
  /// recuadros seguidos lanzaría dos `save()` en paralelo y en disco quedaría
  /// el que resolviera último, que no tiene por qué ser el que tocó el usuario.
  /// Y durante la transición el recuadro de al lado sigue en pantalla y se
  /// puede tocar.
  Future<void> _chooseRole(IntroRole role) async {
    if (_choosing) return;
    _choosing = true;
    try {
      await IntroRoleStore().save(role);
      if (!mounted) return;
      setState(() => _introRole = role);
      await _afterLayout(() => _goToPage(1));
    } finally {
      _choosing = false;
    }
  }

  void _skip() {
    setState(() => _skipped = true);
    // Última lámina SIEMPRE, sea cual sea el largo del carrusel: sin rol son
    // 2 (cierre neutro, índice 1); con rol ya elegido son 3 (índice 2) — p.ej.
    // volver deslizando a la lámina 0 con «Vendo algo» ya guardado y tocar
    // «Saltar» debe caer en los accesos, no quedarse en la lámina de
    // contenido del rol (índice 1). Hardcodear el 1 aquí fue el bug.
    unawaited(_afterLayout(() => _goToPage(_pageCount - 1)));
  }

  Future<void> _openPasswordSheet() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: const _PasswordLoginSheet(),
    ),
  );

  Future<void> _go() async {
    setState(() => _busy = true);
    try {
      await signInWithGoogleNative(context);
    } on SignInCancelled {
      // Sin ruido: cerrar el selector de cuenta es una decisión del usuario.
    } catch (e) {
      // Nada de `$e` crudo: esta es la ÚNICA puerta de entrada de la app, y el
      // usuario leía cosas como `PlatformException(sign_in_failed, ...
      // ApiException: 10...)`, que no le dicen qué hacer. El detalle va al log
      // de desarrollo; a la pantalla va un mensaje accionable.
      if (kDebugMode) debugPrint('[login] $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No pudimos iniciar sesión. Revisa tu conexión e inténtalo de nuevo.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Pill violeta FIJO (la portada no tiene modo oscuro): el botón de Google y
  /// el «Siguiente» del carrusel son el mismo botón.
  static ButtonStyle get _pill => FilledButton.styleFrom(
    minimumSize: const Size.fromHeight(54),
    backgroundColor: JayaloColors.primary,
    foregroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(999)),
    ),
    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
  );

  /// Atrás de Android dentro del carrusel: en vez de salir de la app (o de
  /// `/login`, que sin sesión rebota otra vez aquí — ver el doc de la
  /// clase), retrocede una lámina. Solo en la lámina 0 se deja pasar el pop
  /// de verdad.
  void _handleBackPop(bool didPop, Object? result) {
    if (didPop) return;
    // Misma guarda de reentrada que [_chooseRole]: un back machacado en
    // mitad de una transición no debe lanzar una segunda `animateToPage` en
    // paralelo con la que ya está en vuelo.
    if (_choosing) return;
    // Con el login en vuelo el carrusel está congelado (mismo motivo que la
    // física del `PageView`, ver el comentario en `build`): retroceder aquí
    // dejaría reelegir rol mientras `_go()` sigue autenticando.
    if (_busy) return;
    _choosing = true;
    unawaited(_goToPage(_page - 1).whenComplete(() => _choosing = false));
  }

  @override
  Widget build(BuildContext context) {
    // La portada es arena clara: los iconos de la status bar tienen que ser
    // oscuros o desaparecen (ningún otro sitio de la app fija la barra).
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      // Tres estados, no dos. Mientras `_introSeen` es null todavía se está
      // leyendo la marca del disco: se pinta la arena pelada, porque elegir
      // por defecto y corregir un frame después se ve como un parpadeo entre
      // dos pantallas que no se parecen en nada.
      child: _introSeen == null
          // Modo CLÁSICO: este teléfono ya vio el intro y no vuelve a verlo.
          // Nada de PopScope ahí — sin carrusel no hay lámina a la que
          // retroceder, y retener el atrás encerraría al usuario en el login.
          ? const Scaffold(
              backgroundColor: JayaloColors.background,
              body: SizedBox.expand(),
            )
          : _introSeen!
          ? _classicLogin(context)
          : PopScope<Object?>(
        // Solo la lámina 0 deja salir de verdad (cerrar la app / volver a
        // donde sea que llevó a `/login`). En cualquier otra, el atrás de
        // Android retrocede una lámina en vez de sacar al usuario del
        // onboarding (I-2: desde las láminas 2-3 se salía de la app entera).
        canPop: _page == 0,
        onPopInvokedWithResult: _handleBackPop,
        child: Scaffold(
          // Arena FIJA de marca (no `cs.background`: el intro no tiene modo
          // oscuro). El CTA mantiene el violeta FIJO por la misma razón.
          //
          // Lienzo LIMPIO, como la maqueta de onboarding: la ilustración es la
          // escena de cada lámina, no un fondo. La «Portada Jayi» (render 3D a
          // pantalla completa + patrón de isotipos) vivía aquí y se retiró: su
          // render era el mismo en las tres láminas y su claim fijo («Todo
          // comienza con una idea») dejaba DOS titulares apilados compitiendo
          // con el de la lámina.
          backgroundColor: JayaloColors.background,
          body: SafeArea(
            child: Column(
              children: [
                _topRow(context),
                Expanded(
                  child: PageView.builder(
                    controller: _pages,
                    // Con el login en vuelo el carrusel se congela: si no,
                    // se puede deslizar de vuelta a los recuadros y
                    // reescribir la elección MIENTRAS se autentica, y el
                    // alta consumiría un rol distinto del que se ve.
                    physics: _busy
                        ? const NeverScrollableScrollPhysics()
                        : null,
                    itemCount: _pageCount,
                    onPageChanged: (i) {
                      setState(() => _page = i);
                      _markSeenIfDone();
                    },
                    itemBuilder: _buildSlide,
                  ),
                ),
                const SizedBox(height: 14),
                // Con 1 sola lámina (todavía sin elegir ni saltar)
                // se siguen pintando los 3 puntos de siempre: esa
                // lámina es la de elección, y de ahí se puede llegar
                // tanto al camino de 3 (con rol) como al de 2 (sin
                // rol) — pintar 1 solo punto ahí sugeriría un
                // carrusel de una sola lámina que no existe. Fuera de
                // ese caso transitorio, el conteo real evita el punto
                // del medio encendido de tres cuando en realidad solo
                // hay 2 (el bug que reportó el coordinador).
                _Dots(active: _page, count: _pageCount == 1 ? 3 : _pageCount),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// «Saltar» arriba a la derecha en toda lámina salvo la última (la de los
  /// accesos): ahí ya no hay nada que saltar. Con una sola lámina (todavía
  /// sin elegir ni saltar) esa última lámina es la única que hay, así que se
  /// ve igual: es la que tiene los recuadros de rol, no la de acceso.
  bool get _showSkip => _pageCount == 1 || _page != _pageCount - 1;

  /// Marca a la izquierda y «Saltar» a la derecha, como el `.top` de la
  /// maqueta. El imagotipo vive aquí desde que se retiró la portada, que era
  /// quien lo pintaba — y va PEQUEÑO: en el intro la marca sitúa, no protagoniza.
  ///
  /// El alto se reserva SIEMPRE para que nada salte al llegar.
  Widget _topRow(BuildContext context) {
    final visible = _showSkip;
    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            const _Wordmark(),
            const Spacer(),
            AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: JayaloMotion.reduced(context)
                  ? Duration.zero
                  : JayaloMotion.fast,
              curve: JayaloMotion.enter,
              child: IgnorePointer(
                ignoring: !visible,
                child: TextButton(
                  onPressed: _skip,
                  child: Text(
                    'Saltar',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: JayaloColors.foreground.withValues(alpha: .75),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlide(BuildContext context, int i) {
    final IntroSlide slide;
    final Widget action;
    if (_introRole == null) {
      // Saltó sin elegir lado: 2 láminas, ambas con el copy común — no hay
      // rol con el que pintar contenido dedicado para ninguna de las dos.
      // Lámina 0 = elegir; lámina 1 (última) = cierre neutro con los accesos.
      slide = kIntroCommon;
      action = i == 0 ? _roleCards(context) : _accessStack(context);
    } else {
      slide = i == 0 ? kIntroCommon : kIntroSlides[_introRole]![i - 1];
      action = switch (i) {
        0 => _roleCards(context),
        1 => FilledButton(
          style: _pill,
          onPressed: () => _goToPage(2),
          child: const Text('Siguiente'),
        ),
        _ => _accessStack(context),
      };
    }
    // Escena + copy arriba y la acción abajo, con el hueco repartido entre las
    // dos — el `spacer / scene / benefit / sub / spacer / actions` de la
    // maqueta. Desplazable porque con la fuente del sistema en gigante los
    // titulares crecen y no deben desbordar sobre la escena.
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Hueco de arriba: `spaceBetween` reparte el sobrante entre este
              // hijo vacío y la acción, así que la escena queda a media altura
              // en vez de pegada bajo la marca.
              const SizedBox.shrink(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: JayiScene(kind: _sceneFor(i)),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _SlideCopy(slide),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 22),
                child: action,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Qué hace Jayi en cada lámina. La 0 es siempre la común (bracitos abiertos
  /// entre las dos partes); las demás dependen del lado elegido. Sin rol, la
  /// lámina de cierre repite la común: su copy también es el común, y no hay
  /// lado con el que pintar una escena dedicada.
  JayiSceneKind _sceneFor(int i) {
    if (i == 0 || _introRole == null) return JayiSceneKind.common;
    return switch ((_introRole!, i)) {
      (IntroRole.consumer, 1) => JayiSceneKind.consumerOffers,
      (IntroRole.consumer, _) => JayiSceneKind.consumerLock,
      (IntroRole.provider, 1) => JayiSceneKind.providerTray,
      (IntroRole.provider, _) => JayiSceneKind.providerCoin,
    };
  }

  /// Los dos recuadros de la lámina común: tarjeta blanca sin borde, sombra
  /// suave, ícono lineal. NO son botones a propósito — se leen como una
  /// elección entre pares.
  Widget _roleCards(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _RoleCard(
            icon: Icons.shopping_bag_outlined,
            title: 'Busco algo',
            sub: 'Quiero pedir',
            onTap: () => _chooseRole(IntroRole.consumer),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _RoleCard(
            icon: Icons.storefront_outlined,
            title: 'Vendo algo',
            sub: 'Quiero ofertar',
            onTap: () => _chooseRole(IntroRole.provider),
          ),
        ),
      ],
    ),
  );

  /// El login de SIEMPRE, el que había antes del intro (`451d1ab`): la
  /// «Portada Jayi» a pantalla completa —el render 3D de Jayi sobre el pattern
  /// de isotipos— con los accesos abajo.
  ///
  /// Es la pantalla que ve el 99 % de las aperturas, porque el carrusel es de
  /// una sola vez por teléfono. `bottomReserve` deja libre la banda de los
  /// botones para que la composición no se los coma, igual que antes.
  Widget _classicLogin(BuildContext context) => Scaffold(
    // Arena FIJA de marca (no `cs.background`: la portada no tiene modo
    // oscuro). El CTA mantiene el violeta FIJO por la misma razón.
    backgroundColor: JayaloColors.background,
    body: Stack(
      children: [
        const Positioned.fill(child: PortadaJayi(bottomReserve: 170)),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 14, 28, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [const Spacer(), _accessStack(context)],
            ),
          ),
        ),
      ],
    ),
  );

  /// La pila de acceso de siempre. Google REGISTRA; el correo solo inicia
  /// sesión — por eso uno va en pill y el otro en enlace discreto.
  Widget _accessStack(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _busy ? null : _go,
          style: _pill,
          icon: _busy
              ? const JayaloSpinner(size: 18, color: Colors.white)
              : const Icon(Icons.g_mobiledata, size: 26),
          label: const Text('Continuar con Google'),
        ),
      ),
      const SizedBox(height: 12),
      // El registro es NATIVO desde el onboarding (spec 2026-07-16):
      // mandar a jayalo.com sería mentirle al usuario nuevo.
      Text(
        '¿Primera vez? Entra con Google y creamos tu cuenta al momento.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          height: 1.4,
          fontWeight: FontWeight.w400,
          // Sobre la arena de la portada, tinta (antes blanco
          // sobre el mar de FONDO PLAYA).
          color: JayaloColors.foreground.withValues(alpha: .8),
        ),
      ),
      // Puerta para las cuentas creadas en jayalo.com con correo y
      // contraseña: sin esto quedaban fuera de la app si su correo
      // no era de Google (2026-08-10).
      TextButton(
        onPressed: _busy ? null : _openPasswordSheet,
        child: Text(
          'Entrar con correo y contraseña',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            // Violeta de acción sobre la arena (antes blanco).
            color: JayaloColors.primary,
          ),
        ),
      ),
    ],
  );
}

/// El imagotipo pequeño de la fila superior. Ancho fijo y alto derivado de la
/// proporción real del logo, para que no se deforme nunca.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  static const _w = 84.0;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: _w,
    height: _w * kImagotipoSize.height / kImagotipoSize.width,
    child: const CustomPaint(painter: _WordmarkPainter()),
  );
}

class _WordmarkPainter extends CustomPainter {
  const _WordmarkPainter();

  @override
  void paint(Canvas canvas, Size size) =>
      paintImagotipo(canvas, Offset.zero & size);

  @override
  bool shouldRepaint(covariant _WordmarkPainter old) => false;
}

/// Titular + apoyo de una lámina. El realce va en violeta partiendo el titular
/// por `highlight`.
class _SlideCopy extends StatelessWidget {
  const _SlideCopy(this.slide);
  final IntroSlide slide;

  @override
  Widget build(BuildContext context) {
    final i = slide.headline.indexOf(slide.highlight);
    final head = i < 0
        ? TextSpan(text: slide.headline)
        : TextSpan(
            children: [
              TextSpan(text: slide.headline.substring(0, i)),
              TextSpan(
                text: slide.highlight,
                style: const TextStyle(color: JayaloColors.primary),
              ),
              TextSpan(
                text: slide.headline.substring(i + slide.highlight.length),
              ),
            ],
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          head,
          textAlign: TextAlign.center,
          // Pesos 400-600, nunca bold: la doctrina tipográfica de la app.
          style: const TextStyle(
            fontSize: 19,
            height: 1.3,
            fontWeight: FontWeight.w600,
            color: JayaloColors.head,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          slide.sub,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.5,
            fontWeight: FontWeight.w400,
            color: JayaloColors.foreground.withValues(alpha: .9),
          ),
        ),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.sub,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Colores FIJOS del tema claro: estos recuadros viven sobre la portada de
    // arena, que no tiene modo oscuro.
    return JayaloCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      tint: JayaloColors.card,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 26, color: JayaloColors.primary),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: JayaloColors.head,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            sub,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11.5,
              height: 1.3,
              fontWeight: FontWeight.w400,
              color: JayaloColors.mutedFg,
            ),
          ),
        ],
      ),
    );
  }
}

/// Los puntos del carrusel, con el activo alargado. `count` es el número real
/// de láminas — antes estaba fijo en 3 y con el camino de «Saltar sin rol»
/// (2 láminas) se veía el punto del medio encendido de tres, como si faltara
/// una lámina.
class _Dots extends StatelessWidget {
  const _Dots({required this.active, required this.count});
  final int active;
  final int count;

  @override
  Widget build(BuildContext context) {
    final reduced = JayaloMotion.reduced(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final on = i == active;
        return AnimatedContainer(
          duration: reduced ? Duration.zero : JayaloMotion.base,
          curve: JayaloMotion.emphasized,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: on ? 22 : 7,
          height: 7,
          decoration: BoxDecoration(
            color: on
                ? JayaloColors.primary
                : JayaloColors.foreground.withValues(alpha: .22),
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }
}

/// Hoja de "entrar con correo y contraseña". SOLO inicia sesión: crear cuenta
/// sigue siendo Google + onboarding nativo, así que aquí no hay registro ni
/// se promete uno. Al entrar, el router redirige solo (misma sesión de
/// Supabase que con Google).
class _PasswordLoginSheet extends StatefulWidget {
  const _PasswordLoginSheet();

  @override
  State<_PasswordLoginSheet> createState() => _PasswordLoginSheetState();
}

class _PasswordLoginSheetState extends State<_PasswordLoginSheet> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _email.text.trim().contains('@') && _password.text.isNotEmpty;

  Future<void> _submit() async {
    if (!_canSubmit || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await signInWithPasswordNative(
        context,
        _email.text.trim(),
        _password.text,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (kDebugMode) debugPrint('[login-password] $e');
      if (mounted) {
        setState(() {
          _busy = false;
          _error = passwordLoginError(e);
        });
      }
    }
  }

  InputDecoration _field(String label, {Widget? suffix}) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: const Color(0xFFF3F1FA),
    suffixIcon: suffix,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Entra con tu correo',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: jayaloHead(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Para las cuentas creadas en jayalo.com. Si entraste con Google, '
            'usa el botón de Google.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            decoration: _field('Correo electrónico'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _password,
            obscureText: _hide,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
            decoration: _field(
              'Contraseña',
              suffix: IconButton(
                icon: Icon(
                  _hide
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () => setState(() => _hide = !_hide),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: (_canSubmit && !_busy) ? _submit : null,
            child: _busy
                ? const JayaloSpinner(size: 18, color: Colors.white)
                : const Text('Entrar'),
          ),
          const SizedBox(height: 10),
          Text(
            '¿Olvidaste tu contraseña? Recupérala en jayalo.com.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
