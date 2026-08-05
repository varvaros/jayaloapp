# Reseteo de usuarios en producción — 2026-08-03

Autorizado por el PO para volver a correr el ciclo completo de pruebas (registro → confirmación →
crear solicitud → ofertar → chat). El PO confirmó que **las 21 cuentas eran testers suyos**, ninguna
de un tercero que llegara solo a jayalo.com.

Proyecto: `mfaiklvobnvgusbcssbx` (producción, la que sirve jayalo.com).

## Comprobaciones previas

- **Dinero real: no hay.** 4 órdenes capturadas por **USD 0.04** en total (el paquete "test" de
  2 pts / USD 0.01) y 1 orden en `created` sin capturar.
- **Ninguna tabla tiene FK contra `auth.users`** — verificado. Borrar las cuentas NO arrastra nada,
  así que los datos hubo que borrarlos explícitamente o habrían quedado huérfanos.
- **El auto-admin sigue vivo**: `handle_new_user` otorga rol `admin` al registrarse
  `varvaros.com@gmail.com`. Por eso se pudo borrar también el único admin sin dejar el panel
  inaccesible: se recupera al re-registrar ese correo.

## Cuentas borradas (21)

| correo | alta | último acceso | tipo | solicitudes | negocios |
|---|---|---|---|---|---|
| qaconsumerjayalotest3@gmail.com | 07-09 | 07-09 | provider | 1 | 1 |
| qafixverify4@gmail.com | 07-10 | 07-10 | provider | 0 | 1 |
| mentekruel@gmail.com | 07-11 | 07-28 | provider | 0 | 1 |
| qa-cliente@example.com | 07-13 | 07-22 | consumer | 0 | 0 |
| qa-proveedor@example.com | 07-13 | 07-17 | provider | 0 | 1 |
| qa-admin@example.com | 07-14 | 07-17 | consumer | 0 | 0 |
| varvaros.com@gmail.com | 07-14 | 08-01 | provider | 0 | 1 | ← **era el único admin** |
| amaury@elcorito.com | 07-15 | 08-03 | provider | 4 | 1 |
| ohuaord@gmail.com | 07-15 | 08-03 | consumer | 21 | 0 | ← cuenta del PO |
| dondepuntodo@gmail.com | 07-17 | 07-28 | provider | 0 | 1 |
| donderd.com@gmail.com | 07-17 | 07-17 | consumer | 0 | 0 |
| ac@elcorito.com | 07-18 | 07-28 | consumer | 0 | 0 |
| orlandoferreras@gmail.com | 07-20 | 07-31 | consumer | 11 | 0 |
| lovable@elcorito.com | 07-21 | 07-26 | consumer | 2 | 0 |
| thelobosama@gmail.com | 07-21 | 07-28 | provider | 0 | 1 |
| mrferreras@gmail.com | 07-22 | 07-24 | consumer | 2 | 0 |
| arianigilromano@gmail.com | 07-24 | 07-24 | consumer | 1 | 0 |
| dev@elcorito.com | 07-26 | 07-28 | provider | 0 | 1 |
| accr.advertise@gmail.com | 07-26 | 07-26 | consumer | 1 | 0 |
| marcasdord@gmail.com | 07-27 | 07-27 | (sin perfil) | 0 | 0 |
| georginaascanio@gmail.com | 07-27 | 08-01 | consumer | 1 | 0 |

## Datos borrados

44 solicitudes · 36 ofertas · 26 conversaciones · 167 mensajes · 505 notificaciones · 9 negocios ·
10 productos · 9 wallets · 1 reseña · 62 ficheros de storage (10 MB, casi todo `business-logos`).

También se vaciaron `page_events`, `error_events` y `api_rate_limits`. Esta última a propósito: los
contadores de rate limit viejos (OTP, IA) habrían bloqueado las pruebas nuevas.

## Lo que NO se tocó

`rubros` (502) · `app_settings` · `credit_packages` · `paypal_settings` · `email_template_overrides`
· `categories` · `countries` · `zones` — es catálogo y configuración, no datos de usuario.

**`admin_audit_log` (7 filas) se conservó** a propósito: es una pista de auditoría y borrarla no
formaba parte de lo pedido. Sus filas apuntan ahora a un `admin_id` que ya no existe.

## Residuo conocido: los ficheros de storage

Supabase **bloquea el borrado directo de `storage.objects`** (guard `storage.protect_delete`, que
exige pasar por la Storage API). Así que los **62 ficheros (10 MB, casi todo `business-logos`)
siguen en el bucket**, huérfanos: ninguna fila de la base los referencia y sus rutas van por UUID,
así que no pueden colisionar con nada nuevo. Se dejan a propósito en vez de forzar el borrado. Si
molestan, se limpian con la Storage API y la service_role key.

## Verificación posterior

`auth.users`, `auth.identities`, `auth.sessions`, `profiles`, `customer_requests`,
`provider_offers`, `conversations`, `notifications`, `provider_businesses`, `device_tokens` y
`user_roles` → **todo a 0**.
Catálogo intacto: `rubros` 502 · `app_settings` 10 · `credit_packages` 5 · `paypal_settings` 1 ·
`admin_audit_log` 7.

## Deuda que deja este reseteo

- **El paquete "test" de `credit_packages`** (2 pts / USD 0.01, `sort_order` 0) sigue activo. Es
  bloqueante del launch-checklist: hay que desactivarlo antes de abrir al público.
- **jayalo.com sigue con registro abierto** durante las pruebas, así que pueden entrar desconocidos
  y mezclarse con los datos de prueba. Si vuelve a hacer falta un reseteo, conviene montar una rama
  de Supabase en vez de repetir esto sobre producción.
