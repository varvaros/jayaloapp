# jayalo_app

App Android de **Jayalo** (Flutter). El marketplace conecta clientes que publican
una solicitud con proveedores que ofertan; el proveedor paga créditos para
desbloquear el contacto del cliente.

Esta app es un cliente del mismo backend que la web (`jayalo-main`): Supabase
(Postgres + Auth + Realtime + Storage) y las server functions de jayalo.com. No
tiene backend propio.

## Puesta en marcha

```bash
flutter pub get
flutter run
```

Para un build de release hace falta `android/key.properties` con el keystore de
subida (ver `docs/build-release.md`). Sin él el build **falla a propósito**: antes
caía a las claves de debug en silencio y producía un artefacto que Play rechaza.
Para correr en local sin keystore: `flutter run --release -PallowDebugSigning=true`.

## Dónde está cada cosa

| Carpeta | Qué hay |
| --- | --- |
| `lib/core/` | Router, sesión/rol, tema y movimiento, cachés TTL, config |
| `lib/data/repos.dart` | Todo el acceso a Supabase, en una sola puerta |
| `lib/domain/` | Lógica pura y testeable: precios, catálogo, anti-elusión, chat |
| `lib/features/` | Pantallas por rol: `client/`, `provider/`, `chat/`, `onboarding/` |
| `lib/push/` | FCM, notificaciones locales de chat y ruteo del tap |
| `test/` | Tests, incluidos los de regresión de los bugs caros |

## Reglas que no se negocian

- **El costo se calcula en la BD.** Las RPCs de cobro ignoran el `_cost` que manda
  el cliente. Lo de `lib/domain/pricing.dart` sirve solo para PINTAR el precio.
- **Paridad exacta con la web** en toda regla de negocio (tramos de precio,
  cascada, tope de 3 finalistas, costos de empleos). Si cambia una, cambian las dos.
- **Nada de datos de contacto** en texto libre antes de que se pague el desbloqueo:
  lo vigila el trigger `enforce_no_contact_info` (JY422) y lo adelanta
  `domain/contact_info.dart`.

## Verificación

```bash
flutter analyze && flutter test
```
