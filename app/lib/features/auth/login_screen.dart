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
import '../../data/repos.dart' as repos show fetchWelcomeCredits;
import '../shared/brand_kit.dart' show JayaloCard;
import '../shared/jayalo_loader.dart';
import 'intro_copy.dart';
import 'intro_reveal.dart';
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

/// Primera apertura de la app: el guion del PO en láminas, que termina en los
/// accesos de siempre.
///
/// Las láminas viven aquí dentro y no en rutas nuevas por un motivo duro:
/// `redirectTarget()` empieza con `if (!loggedIn) return onLogin ? null :
/// '/login';` — sin sesión, toda ruta que no sea `/login` rebota. Metiendo el
/// carrusel dentro de `/login` no se toca el router.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.fetchWelcomeCredits = repos.fetchWelcomeCredits,
  });

  /// Inyectable para los tests: cuántos créditos regala el alta de proveedor.
  final Future<int> Function() fetchWelcomeCredits;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;

  final _pages = PageController();

  /// La elección de rol YA GUARDADA. `null` = todavía no eligió, y entonces
  /// solo existe la lámina de la pregunta (ver [_steps]).
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

  /// La reacción avanza sola tras `introRead`; el «Siguiente» fantasma
  /// aparece a `introHint`. Se cancelan al cambiar de lámina, al retroceder y
  /// en dispose (si no, los tests de widgets mueren por temporizadores vivos).
  Timer? _readTimer;
  Timer? _hintTimer;
  bool _hintVisible = false;

  void _armReaction(int i) {
    _disarmReaction();
    if (_steps[i] != IntroStep.react) return;
    _hintTimer = Timer(JayaloMotion.introHint, () {
      if (mounted) setState(() => _hintVisible = true);
    });
    // Tiempo de LECTURA, no animación: con «reducir animaciones» también avanza.
    _readTimer = Timer(JayaloMotion.introRead, () {
      if (!mounted || _page != i || _busy) return;
      unawaited(_goToPage(i + 1));
    });
  }

  void _disarmReaction() {
    _readTimer?.cancel();
    _hintTimer?.cancel();
    _readTimer = null;
    _hintTimer = null;
    if (_hintVisible) _hintVisible = false;
  }

  /// Créditos de bienvenida según el servidor; `null` mientras no llega.
  int? _welcomeCredits;

  /// EL viaje al servidor por el bono: uno solo por montaje de la pantalla.
  ///
  /// `late final` a propósito — el futuro NACE en el primer acceso, que está
  /// dentro de [_restore] y solo en modo intro: el login clásico (el 99 % de
  /// las aperturas) no pide el bono nunca. Las dos ramas de [_restore] —la
  /// suscripción en paralelo y la espera con rol guardado— comparten ESTE
  /// futuro, así que la RPC se hace una vez y no dos.
  late final Future<int> _creditsFuture = widget.fetchWelcomeCredits();

  /// Los créditos CONGELADOS al elegir rol. Que el valor llegue después no
  /// cambia el número de láminas: si no, la lámina de accesos se movería bajo
  /// el dedo del usuario.
  int _credits = 0;

  /// La secuencia de láminas. Pura y derivada: la pantalla no la guarda, la
  /// lee — así el largo del carrusel y el copy nunca se desincronizan.
  List<IntroStep> get _steps =>
      introSteps(role: _introRole, skipped: _skipped, credits: _credits);

  /// Qué hace Jayi en cada lámina. Es UN SOLO widget, montado fuera del
  /// carrusel: aquí solo se decide su pose, y la escena anima el cambio.
  JayiPose _poseFor(int i) => switch (_steps[i.clamp(0, _steps.length - 1)]) {
    IntroStep.ask || IntroStep.neutralClose => JayiPose.open,
    IntroStep.react => JayiPose.thumbsUp,
    IntroStep.consumerFree => JayiPose.free,
    IntroStep.providerOffers => JayiPose.priceTag,
    IntroStep.providerCoin => JayiPose.coin,
  };

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  @override
  void dispose() {
    _disarmReaction();
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
    // Los créditos se piden en paralelo con el rol: no bloquean la lámina 0.
    // Aquí es donde nace `_creditsFuture`, y es el ÚNICO viaje: abajo se
    // espera a este mismo futuro, nunca se lanza otro.
    unawaited(
      _creditsFuture.then((n) {
        if (mounted) setState(() => _welcomeCredits = n);
      }),
    );
    final role = await IntroRoleStore().read();
    if (!mounted) return;
    if (role == null) {
      setState(() => _introSeen = false);
      return;
    }
    // Con rol ya guardado se aterriza en los accesos, y para eso hay que saber
    // cuántas láminas hay: sin el bono no se sabe si el proveedor tiene 3 o 4,
    // y aterrizar en la lámina equivocada movería el carrusel bajo el dedo del
    // usuario. Por eso aquí SÍ se espera — pero al MISMO futuro que ya está en
    // vuelo desde arriba, y la espera está acotada por el timeout del repo
    // (`fetchWelcomeCredits` corta a los 3 s y devuelve 0).
    final credits = _welcomeCredits ?? await _creditsFuture;
    if (!mounted) return;
    setState(() {
      _introSeen = false;
      _introRole = role;
      _credits = credits;
      // Los puntos y el «Saltar» ya nacen en su sitio, sin parpadeo.
      _page = _steps.length - 1;
    });
    // Volver con lado ya elegido aterriza en los accesos, que es el final del
    // carrusel: para el usuario el intro ya está visto.
    _markSeenIfDone();
    unawaited(
      _afterLayout(() async {
        if (_pages.hasClients) _pages.jumpToPage(_steps.length - 1);
      }),
    );
  }

  /// ¿La lámina `i` es la de los accesos, o sea el FINAL del carrusel?
  ///
  /// No vale `i == _steps.length - 1` a secas: mientras no se elige lado ni se
  /// salta, el carrusel mide UNA lámina y esa única lámina es la de la
  /// pregunta — marcar ahí daría el intro por visto a quien no ha visto nada.
  /// El criterio vive en `intro_copy.dart` y lo comparten [_buildSlide] y
  /// [_markSeenIfDone].
  bool _isAccessSlide(int i) => introStepIsAccess(_steps, i);

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
      setState(() {
        _introRole = role;
        // CONGELADOS aquí: si `_steps` leyera `_welcomeCredits`, un bono que
        // llega tarde añadiría una lámina bajo el dedo del usuario y movería
        // la de accesos de sitio.
        _credits = _welcomeCredits ?? 0;
      });
      await _afterLayout(() => _goToPage(1));
    } finally {
      _choosing = false;
    }
  }

  void _skip() {
    setState(() => _skipped = true);
    // Última lámina SIEMPRE, sea cual sea el largo del carrusel: sin rol son
    // 2 (cierre neutro); con rol ya elegido son 3 o 4 — p.ej. volver a la
    // lámina 0 con «Soy un proveedor» ya guardado y tocar «Saltar» debe caer
    // en los accesos, no quedarse en una lámina de contenido. Hardcodear el 1
    // aquí fue el bug.
    unawaited(_afterLayout(() => _goToPage(_steps.length - 1)));
  }

  /// El chevrón de la fila superior (y el atrás de Android): una lámina atrás.
  ///
  /// Misma guarda de reentrada que [_chooseRole]: un back machacado en mitad
  /// de una transición no debe lanzar una segunda `animateToPage` en paralelo
  /// con la que ya está en vuelo. Y con el login en vuelo el carrusel está
  /// congelado (mismo motivo que la física del `PageView`): retroceder aquí
  /// dejaría reelegir rol mientras `_go()` sigue autenticando.
  void _back() {
    if (_choosing || _busy || _page == 0) return;
    _disarmReaction();
    _choosing = true;
    unawaited(_goToPage(_page - 1).whenComplete(() => _choosing = false));
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
    _back();
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
                      // UN SOLO Jayi, fuera del carrusel: nunca se remonta, solo
                      // cambia de pose (y la escena anima ese cambio). Dentro del
                      // `PageView` cada lámina montaba el suyo, así que Jayi se
                      // deslizaba con el texto en vez de reaccionar.
                      Padding(
                        padding: const EdgeInsets.only(top: 18, bottom: 6),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 210),
                            child: JayiScene(pose: _poseFor(_page)),
                          ),
                        ),
                      ),
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
                          itemCount: _steps.length,
                          onPageChanged: (i) {
                            setState(() {
                              _page = i;
                              _disarmReaction();
                            });
                            _markSeenIfDone();
                            _armReaction(i);
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
                      _Dots(
                        active: _page,
                        count: _steps.length == 1 ? 3 : _steps.length,
                      ),
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
  /// ve igual: es la de la pregunta, no la de acceso.
  ///
  /// Y tampoco en la REACCIÓN: esa lámina dura lo que dura leerla, y ofrecer
  /// saltar justo cuando Jayi acaba de responder al usuario suena a que la
  /// app quiere terminar la conversación que ella misma empezó.
  bool get _showSkip {
    if (_steps.length == 1) return true;
    final i = _page.clamp(0, _steps.length - 1);
    return i != _steps.length - 1 && _steps[i] != IntroStep.react;
  }

  /// Ancho de las celdas laterales de la fila superior. Fijas y iguales para
  /// que el imagotipo quede CENTRADO pase lo que pase con los dos extremos
  /// (uno aparece al avanzar, el otro desaparece al llegar al final).
  static const _topSide = 104.0;

  /// Chevrón atrás, marca centrada y «Saltar», como el `.top` de la maqueta.
  /// El imagotipo vive aquí desde que se retiró la portada, que era quien lo
  /// pintaba — y va PEQUEÑO: en el intro la marca sitúa, no protagoniza.
  ///
  /// El alto se reserva SIEMPRE para que nada salte al llegar.
  Widget _topRow(BuildContext context) {
    final skip = _showSkip;
    final back = _page > 0;
    final d = JayaloMotion.reduced(context) ? Duration.zero : JayaloMotion.fast;
    return SizedBox(
      height: 48,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            SizedBox(
              width: _topSide,
              child: Align(
                alignment: Alignment.centerLeft,
                child: AnimatedOpacity(
                  opacity: back ? 1 : 0,
                  duration: d,
                  curve: JayaloMotion.enter,
                  // Invisible es invisible también para TalkBack: sin el
                  // `ExcludeSemantics` el lector cantaba «Atrás» en la lámina 0,
                  // donde el chevrón no está.
                  child: ExcludeSemantics(
                    excluding: !back,
                    child: IgnorePointer(
                      ignoring: !back,
                      child: IconButton(
                        key: const Key('intro-back'),
                        onPressed: _back,
                        icon: const Icon(Icons.chevron_left_rounded),
                        color: JayaloColors.foreground.withValues(alpha: .75),
                        tooltip: 'Atrás',
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Expanded(child: Center(child: _Wordmark())),
            SizedBox(
              width: _topSide,
              child: Align(
                alignment: Alignment.centerRight,
                child: AnimatedOpacity(
                  opacity: skip ? 1 : 0,
                  duration: d,
                  curve: JayaloMotion.enter,
                  // Igual que el chevrón: apagado a la vista, apagado también
                  // para el lector de pantalla.
                  child: ExcludeSemantics(
                    excluding: !skip,
                    child: IgnorePointer(
                      ignoring: !skip,
                      child: TextButton(
                        onPressed: _skip,
                        child: Text(
                          'Saltar',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: JayaloColors.foreground.withValues(
                              alpha: .75,
                            ),
                          ),
                        ),
                      ),
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
    final step = _steps[i];
    final slide = introSlideFor(step, role: _introRole, credits: _credits);
    final Widget action = switch (step) {
      IntroStep.ask => _roleCards(context),
      _ when _isAccessSlide(i) => _accessStack(context),
      IntroStep.react => AnimatedOpacity(
        key: const Key('intro-ghost-next'),
        opacity: _hintVisible ? 1 : 0,
        duration: JayaloMotion.reduced(context)
            ? Duration.zero
            : JayaloMotion.base,
        curve: JayaloMotion.enter,
        child: IgnorePointer(
          ignoring: !_hintVisible,
          child: TextButton(
            onPressed: () => _goToPage(i + 1),
            style: TextButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              foregroundColor: JayaloColors.primary,
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text('Siguiente'),
          ),
        ),
      ),
      _ => FilledButton(
        style: _pill,
        onPressed: () => _goToPage(i + 1),
        child: const Text('Siguiente'),
      ),
    };
    // Copy arriba y la acción abajo, con el hueco repartido entre las dos — el
    // `spacer / benefit / sub / spacer / actions` de la maqueta. Jayi ya no
    // vive aquí: está fuera del carrusel, sobre esta columna. Desplazable
    // porque con la fuente del sistema en gigante los titulares crecen.
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _SlideCopy(
                slide,
                wordByWord: step == IntroStep.ask,
                question: step == IntroStep.ask,
              ),
              Padding(padding: const EdgeInsets.only(top: 22), child: action),
            ],
          ),
        ),
      ),
    );
  }

  /// Los dos recuadros de la pregunta: tarjeta blanca sin borde, sombra suave,
  /// ícono lineal SIN fondo. NO son botones a propósito — se leen como una
  /// elección entre pares.
  ///
  /// Entran ESCALONADOS y después de que Jayi aterriza: primero se ve quién
  /// pregunta, después las dos respuestas.
  Widget _roleCards(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: IntroReveal(
            delay: _cardDelay1,
            dy: 14,
            child: _RoleCard(
              icon: Icons.search_rounded,
              title: kIntroConsumerCard.title,
              sub: kIntroConsumerCard.sub,
              onTap: () => _chooseRole(IntroRole.consumer),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: IntroReveal(
            delay: _cardDelay2,
            dy: 14,
            child: _RoleCard(
              icon: Icons.storefront_outlined,
              title: kIntroProviderCard.title,
              sub: kIntroProviderCard.sub,
              onTap: () => _chooseRole(IntroRole.provider),
            ),
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
              children: [
                const Spacer(),
                // Sin escalonado: el login clásico pinta sus botones AL
                // INSTANTE, como siempre. Los retardos son del guion del
                // intro (el CTA no debe llegar antes que el texto que lo
                // justifica) y aquí no hay guion que respetar.
                _accessStack(context, reveal: false),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  /// La pila de acceso de siempre. Google REGISTRA; el correo solo inicia
  /// sesión — por eso uno va en pill y el otro en enlace discreto.
  ///
  /// Con [reveal] los tres entran escalonados DESPUÉS de que la lámina termina
  /// de deslizar: el botón que cierra el intro no debe llegar antes que el
  /// texto que lo justifica. El login CLÁSICO la llama con `reveal: false` y
  /// los pinta al instante — esa pantalla no cambia con el intro.
  Widget _accessStack(BuildContext context, {bool reveal = true}) {
    Widget entra(Duration delay, Widget child) =>
        reveal ? IntroReveal(delay: delay, dy: 14, child: child) : child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        entra(
          _accessDelay1,
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
        ),
        const SizedBox(height: 12),
        // El registro es NATIVO desde el onboarding (spec 2026-07-16):
        // mandar a jayalo.com sería mentirle al usuario nuevo.
        entra(
          _accessDelay2,
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
        ),
        // Puerta para las cuentas creadas en jayalo.com con correo y
        // contraseña: sin esto quedaban fuera de la app si su correo
        // no era de Google (2026-08-10).
        entra(
          _accessDelay3,
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
        ),
      ],
    );
  }
}

// ── Retardos de las revelaciones del intro ───────────────────────────────
//
// Son los ÚNICOS `Duration(milliseconds:)` de esta pantalla, y existen porque
// no son duraciones sino COMPASES: el instante en que cada pieza entra
// respecto de otra que ya se está moviendo. Las duraciones y las curvas siguen
// saliendo enteras de `JayaloMotion`.

/// El primer recuadro, SOLAPADO con el final del aterrizaje de Jayi
/// (`JayaloMotion.introLand`, 720 ms): a los 560 ms el salto y su aplastado ya
/// pasaron y solo queda el último asentamiento, así que los recuadros empiezan
/// a subir mientras Jayi termina de posarse. Es lo que hace la maqueta
/// aprobada: esperar los 720 ms enteros dejaba un hueco muerto.
const _cardDelay1 = Duration(milliseconds: 560);

/// El segundo, 80 ms detrás del primero: se leen como dos, no como un bloque.
const _cardDelay2 = Duration(milliseconds: 640);

/// El grito de la reacción, tras el cambio de pose de Jayi: primero el pulgar,
/// después la palabra.
const _shoutDelay = Duration(milliseconds: 110);

/// Y la frase que lo explica, cuando el grito ya rebotó
/// (`JayaloMotion.introGesture`, 560 ms).
const _shoutSubDelay = Duration(milliseconds: 520);

/// El acceso principal, tras el deslizamiento de la lámina
/// (`JayaloMotion.page`, con un 10 % de margen para no pisar el frenado).
/// `final` y no `const` porque multiplicar una `Duration` no es constante.
final _accessDelay1 = JayaloMotion.page * 1.1;

/// El texto de apoyo y el enlace, 90 y 170 ms detrás de él.
final _accessDelay2 = _accessDelay1 + const Duration(milliseconds: 90);
final _accessDelay3 = _accessDelay1 + const Duration(milliseconds: 170);

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

/// El copy de una lámina: grito, titular y apoyo. Todo lo que se pinta aquí
/// sale de `intro_copy.dart` — ninguna frase se re-escribe en la pantalla.
///
/// El realce va en violeta partiendo el titular por `highlight`; y si el
/// titular trae `{n}` con un `counter`, ahí entra el contador de créditos.
class _SlideCopy extends StatelessWidget {
  const _SlideCopy(
    this.slide, {
    this.wordByWord = false,
    this.question = false,
  });
  final IntroSlide slide;

  /// El titular de la PREGUNTA entra palabra a palabra: es lo primero que se
  /// lee de la app y se quiere ver escribirse.
  final bool wordByWord;

  /// Esta lámina es la de la pregunta (`IntroStep.ask`), donde el apoyo no es
  /// apoyo sino LA pregunta y se pinta en violeta y grande. Es una bandera
  /// explícita y no una comparación de `slide` con `introSlideFor(ask)`: esa
  /// comparación dependía de la identidad de una instancia const y se rompería
  /// en silencio en cuanto el copy dejara de serlo.
  final bool question;

  // Pesos 400-700: el 700 es solo del grito, que es un gesto de personaje.
  static const _head = TextStyle(
    fontSize: 22,
    height: 1.28,
    fontWeight: FontWeight.w600,
    color: JayaloColors.head,
  );

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    if (slide.shout != null) {
      children.add(
        IntroReveal(
          delay: _shoutDelay,
          duration: JayaloMotion.introGesture,
          curve: JayaloMotion.bounce,
          scaleFrom: .72,
          dy: 6,
          child: Text(
            slide.shout!,
            textAlign: TextAlign.left,
            style: const TextStyle(
              fontSize: 38,
              height: 1,
              fontWeight: FontWeight.w700,
              color: JayaloColors.primary,
            ),
          ),
        ),
      );
      children.add(const SizedBox(height: 10));
    }
    if (slide.headline.isNotEmpty) {
      children.add(
        wordByWord
            ? IntroWords(text: slide.headline, style: _head)
            : IntroReveal(child: _headline(slide)),
      );
    }
    if (slide.sub.isNotEmpty) {
      children.add(const SizedBox(height: 10));
      children.add(
        IntroReveal(
          // Tras el grito, cuando ya rebotó; en la pregunta, cuando el titular
          // terminó de escribirse; en el resto, junto con el titular.
          delay: slide.shout != null
              ? _shoutSubDelay
              : (question ? JayaloMotion.intro * 1.4 : Duration.zero),
          child: Text(
            slide.sub,
            textAlign: TextAlign.center,
            style: question
                // «¿Tú qué eres?» no es un apoyo: es LA pregunta.
                ? const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w500,
                    color: JayaloColors.primary,
                  )
                : TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    fontWeight: FontWeight.w400,
                    color: JayaloColors.foreground.withValues(alpha: .9),
                  ),
          ),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: slide.shout != null
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: children,
    );
  }

  /// El titular con el realce en violeta; si trae `{n}` y `counter`, ahí va el
  /// contador (la moneda).
  Widget _headline(IntroSlide s) {
    if (s.counter != null && s.headline.contains('{n}')) {
      final parts = s.headline.split('{n}');
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(text: parts[0]),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: IntroCounter(
                to: s.counter!,
                style: _head.copyWith(
                  color: JayaloColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextSpan(text: parts[1]),
          ],
        ),
        textAlign: TextAlign.center,
        style: _head,
      );
    }
    final h = s.highlight;
    final i = h == null ? -1 : s.headline.indexOf(h);
    final span = i < 0
        ? TextSpan(text: s.headline)
        : TextSpan(
            children: [
              TextSpan(text: s.headline.substring(0, i)),
              TextSpan(
                text: h,
                style: const TextStyle(color: JayaloColors.primary),
              ),
              TextSpan(text: s.headline.substring(i + h!.length)),
            ],
          );
    return Text.rich(span, textAlign: TextAlign.center, style: _head);
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
      key: const Key('intro-dots'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final on = i == active;
        // El punto que NACE (el bono del proveedor añade una lámina) crece
        // desde cero en vez de aparecer de golpe: la `ValueKey` es lo que hace
        // que los que ya estaban conserven su estado y no vuelvan a nacer.
        return TweenAnimationBuilder<double>(
          key: ValueKey(i),
          tween: Tween<double>(begin: 0, end: 1),
          duration: reduced ? Duration.zero : JayaloMotion.page,
          curve: JayaloMotion.bounce,
          builder: (_, s, child) => Transform.scale(scale: s, child: child),
          child: AnimatedContainer(
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
