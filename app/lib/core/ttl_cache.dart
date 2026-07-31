/// Caché en memoria de un solo valor con TTL, para amortiguar lecturas que la
/// app repetía en CADA entrada a pantalla.
///
/// Contexto (auditoría de rendimiento 2026-07-28): la app no cacheaba NADA de
/// datos — cada `initState` y cada `resumed` refetcheaba contra Supabase, y el
/// saldo del wallet era la query #1 de todo el backend. La web ya amortigua eso
/// con los `staleTime` de TanStack Query; esto es la pieza equivalente del lado
/// Flutter, con los MISMOS tiempos (ver `AppCaches`).
///
/// Es gemelo de `jayalo-main/src/lib/ttlCache.ts` (misma semántica get/has/
/// set/clear) más dos cosas que el cliente móvil sí necesita:
///
/// - **Coalescing**: dos pantallas que piden el saldo a la vez comparten UNA
///   petición en vuelo en vez de disparar dos.
/// - **Registro global**: `TtlCache.clearAll()` vacía todas las instancias, y
///   `repos.dart` lo engancha a `onAuthStateChange` para que al cerrar sesión
///   (o cambiar de cuenta) NUNCA sobreviva el dato del usuario anterior.
///
/// ⚠️ Igual que en la web: esto es best-effort de PRESENTACIÓN. El servidor
/// sigue siendo la autoridad — el costo y el débito de un desbloqueo se
/// calculan dentro de la RPC atómica, así que un saldo cacheado optimista como
/// mucho pinta un número viejo un rato, nunca deja pagar de menos.
library;

import 'dart:async';

class TtlCache<T> {
  TtlCache(this.ttl, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now {
    _registry.add(this);
  }

  /// Todas las instancias vivas, para poder vaciarlas de golpe en el signOut.
  /// Son singletons de scope global (`AppCaches`), así que no crecen sin fin.
  static final List<TtlCache<dynamic>> _registry = [];

  /// Vacía TODOS los cachés. Engancharlo a `onAuthStateChange` es lo que impide
  /// que el saldo o el rol de un usuario se le muestren al siguiente.
  static void clearAll() {
    for (final c in _registry) {
      c.clear();
    }
  }

  final Duration ttl;
  final DateTime Function() _clock;

  _Entry<T>? _entry;
  Future<T>? _inFlight;

  /// `true` si hay un valor vigente. Necesario para distinguir "no hay nada" de
  /// un `null`/`false` legítimamente cacheado (un wallet sin fila devuelve
  /// `null` y eso ES una respuesta).
  bool get has {
    final e = _entry;
    return e != null && _clock().isBefore(e.expires);
  }

  /// Valor vigente, o `null` si no hay o expiró. Ante un `T` nullable usar
  /// [has] para desambiguar.
  T? get value => has ? _entry!.value : null;

  /// `true` si hay un valor guardado AUNQUE haya expirado. Es lo que separa
  /// "nunca se cargó" (hay que ir a la red y esperar) de "está viejo" (se puede
  /// pintar ya y refrescar por detrás). Lo usa [readFresh].
  bool get hasStale => _entry != null;

  /// El último valor guardado, vencido o no. `null` solo si nunca hubo uno.
  T? get staleValue => _entry?.value;

  void set(T value) {
    _entry = _Entry(value, _clock().add(ttl));
  }

  void clear() {
    _entry = null;
    // Una petición en vuelo iniciada ANTES del clear ya no debe guardar su
    // resultado: quien la pidió recibe su respuesta, pero el caché queda vacío
    // para que la siguiente lectura vuelva a la fuente. Es el caso de un
    // desbloqueo que invalida el saldo mientras el header lo estaba pidiendo.
    _staleAfter = _inFlight;
  }

  Future<T>? _staleAfter;

  /// Lectura amortiguada: sirve el valor vigente, se cuelga de la petición en
  /// vuelo si ya hay una, o llama a [fetch] y guarda el resultado.
  ///
  /// Los ERRORES NO SE CACHEAN (igual que en la web): si [fetch] lanza, no
  /// queda entrada y la siguiente lectura reintenta.
  Future<T> read(Future<T> Function() fetch) {
    if (has) return Future.value(_entry!.value);
    final pending = _inFlight;
    if (pending != null) return pending;

    late final Future<T> f;
    f = fetch().then((v) {
      // Solo se guarda si nadie invalidó el caché mientras esta petición
      // estaba en vuelo.
      if (!identical(_staleAfter, f)) set(v);
      return v;
    });
    _inFlight = f;
    void releaseSlot() {
      if (identical(_inFlight, f)) _inFlight = null;
      if (identical(_staleAfter, f)) _staleAfter = null;
    }

    // El slot se libera en ÉXITO y en ERROR; sin esto, un fallo dejaría a todas
    // las lecturas siguientes colgadas del future roto. Va como rama aparte con
    // `onError` (no `catchError`, que exigiría fabricar un valor de tipo T que
    // no existe cuando T es no-nullable) para que el error tenga handler y no
    // se reporte como excepción no atrapada — el que llamó a `read` recibe el
    // error igual, por su propia rama.
    unawaited(
      f.then<void>((_) => releaseSlot(), onError: (Object _) => releaseSlot()),
    );
    return f;
  }

  /// Lectura STALE-WHILE-REVALIDATE: nunca hace esperar si ya se cargó alguna
  /// vez.
  ///
  /// - Valor vigente → se sirve, sin tocar la red.
  /// - Valor VENCIDO → se sirve igual, **de inmediato**, y se dispara un
  ///   refresco en segundo plano. Si lo que vuelve es distinto de lo que se
  ///   pintó, se llama [onChanged] para que la pantalla se entere.
  /// - Nada guardado → se va a la red y se espera (única vez que hay carga
  ///   visible).
  ///
  /// Ese "servir vencido" es justamente lo que quita el loader al volver a una
  /// pestaña: el `ShellRoute` destruye el `State` al cambiar de pestaña, así que
  /// cada regreso re-evalúa el `Future` de carga — con [read] eso era un
  /// round-trip completo cada vez, y a más de 400ms el `JayaloLoaderBlock`
  /// aparecía. Con esto la pantalla pinta al instante y la red corre detrás.
  ///
  /// [equals] decide si "cambió"; por defecto compara por identidad, que para
  /// listas recién deserializadas es SIEMPRE distinto. Quien cachee listas debe
  /// pasar una comparación real (ver `AppCaches` en `repos.dart`) o [onChanged]
  /// se disparará en cada revalidación y la pantalla recargará de más.
  ///
  /// El refresco de fondo es best-effort: si falla, se traga el error y la
  /// pantalla se queda con lo que ya tenía. No hay a quién avisarle — el
  /// usuario no pidió esta petición.
  Future<T> readFresh(
    Future<T> Function() fetch, {
    void Function()? onChanged,
    bool Function(T previous, T next)? equals,
  }) {
    if (has) return Future.value(_entry!.value);

    if (hasStale) {
      final previous = _entry!.value;
      // No se encadena con `_inFlight`: si ya hay una revalidación en vuelo,
      // `read` se cuelga de ella sola y no se duplica la petición.
      unawaited(
        read(fetch).then(
          (next) {
            final same = equals?.call(previous, next) ?? identical(previous, next);
            if (!same) onChanged?.call();
          },
          onError: (Object _) {},
        ),
      );
      return Future.value(previous);
    }

    return read(fetch);
  }
}

class _Entry<T> {
  const _Entry(this.value, this.expires);
  final T value;
  final DateTime expires;
}
