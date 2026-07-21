# Paridad del formulario de ofertar (app ↔ web) — Plan de implementación

> **Para workers agénticos:** SUB-SKILL REQUERIDA: usar superpowers:subagent-driven-development o superpowers:executing-plans para implementar tarea por tarea. Los pasos usan checkbox (`- [ ]`).

**Goal:** Que el formulario de ofertar de la app (`request_detail_screen.dart`) tenga las mismas opciones que la web (`RequestRespondSection.tsx`), y que el mensaje al cliente NO sea un campo de texto libre sino auto-armado desde los datos de la oferta (decisión PO 2026-07-20).

**Architecture:** El form se ramifica por `req['kind']` (producto vs servicio), igual que la web. La lógica de "qué texto de mensaje se guarda" se extrae a una función pura testeable. `makeOffer` (repo) se amplía para insertar las columnas nuevas — que YA existen en `provider_offers` (verificado en prod: `offers_shipping, shipping_price, offers_installation, installation_price, requires_evaluation, evaluation_price, hourly_rate, estimated_hours, availability_note, estimated_duration, pricing_mode`).

**Tech Stack:** Flutter 3.44.6, Dart 3.12, Supabase (PostgREST insert), `flutter_test`.

## Global Constraints

- Ofertar es GRATIS — no tocar esa doctrina. El costo se muestra pero no se cobra al ofertar. [[jayalo-modelo-creditos-ofertar-gratis]]
- El costo real lo calcula la RPC server-side; `pointsForOffer` (TS/Dart) es SOLO para mostrar. No confiar en `_cost` del cliente.
- `flutter analyze` debe quedar en 0 y `flutter test` en verde (baseline 359).
- Toda duración/curva de animación sale de `JayaloMotion` (no `Duration(...)` sueltos).
- Diseño reversible: un commit por bloque, decir qué sha revierte. [[po-feedback-disenos-reversibles]]
- `enforce_business_can_offer` (cédula) sigue bloqueando informal/técnico sin docs — YA se surface el error real (fix aplicado 2026-07-20), este plan NO lo cambia.

---

## Alcance de ESTE plan (Fase 1: núcleo económico + mensaje)

Cubre lo que es autocontenido y de alto valor, sin subsistemas nuevos de datos:

- Ramas por kind: **servicio** (fijo/rango/**por hora**/**requiere evaluación** + disponibilidad + duración) y **producto** (fijo/rango + **envío**/**instalación**/**evaluación** con costo opcional).
- **Quitar** el campo libre "Mensaje al cliente"; auto-armar `message` desde los datos.
- Ampliar `makeOffer` con las columnas nuevas.

### Diferido a planes separados (necesitan capa de datos NUEVA en la app — hoy NO existe nada):

- **P2 — Detalles de producto** (marca/color/garantía/entrega) + el sistema `activeDetails` que decide qué campo aplica por categoría. Requiere traer la config de detalles por categoría a la app.
- **P3 — Paquetes**: cargar `provider_packages` del proveedor + UI de selección + `package_snapshot` + prefill de precio/mensaje.
- **P4 — Publicar en tienda** (`addToStore`): expone la server fn `publishOfferToCatalog` a la app.
- **P5 — Expiración de oferta** (`expires_at` / `expiryHours`): selector de vigencia.

Cada uno se planifica por separado cuando toque (scope-check de writing-plans).

---

## Estructura de archivos (Fase 1)

- Crear: `lib/domain/offer_message.dart` — función pura `composeOfferMessage(...)`.
- Crear: `test/offer_message_test.dart` — tests de la función pura.
- Modificar: `lib/data/repos.dart` — ampliar `makeOffer(...)` (firma + insert).
- Modificar: `lib/features/provider/request_detail_screen.dart` — form ramificado por kind, campos nuevos, quitar mensaje libre, wire de compose.
- Modificar: `test/` — nuevo `test/provider_offer_form_test.dart` (widget) para presencia/validación por kind.

---

### Task 1: Función pura `composeOfferMessage`

**Files:**
- Create: `lib/domain/offer_message.dart`
- Test: `test/offer_message_test.dart`

**Interfaces:**
- Produces: `String composeOfferMessage({required bool isService, bool offersShipping, double? shippingPrice, bool offersInstallation, double? installationPrice, bool requiresEvaluation, double? evaluationPrice, String availabilityNote, String estimatedDuration})`

- [ ] **Step 1: Escribir el test que falla**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/offer_message.dart';

void main() {
  test('producto: envío con costo, instalación gratis, sin evaluación', () {
    final m = composeOfferMessage(
      isService: false,
      offersShipping: true, shippingPrice: 300,
      offersInstallation: true, installationPrice: 0,
    );
    expect(m, 'Envío: RD\$300 · Instalación incluida');
  });

  test('producto sin extras => mensaje vacío (columna default \'\')', () {
    expect(composeOfferMessage(isService: false), '');
  });

  test('servicio: disponibilidad + duración + evaluación', () {
    final m = composeOfferMessage(
      isService: true,
      availabilityNote: 'Lun a Vie',
      estimatedDuration: '2 días',
      requiresEvaluation: true,
    );
    expect(m, 'Disponibilidad: Lun a Vie · Duración: 2 días · Requiere evaluación en sitio');
  });
}
```

- [ ] **Step 2: Correr y verificar que falla**

Run: `flutter test test/offer_message_test.dart`
Expected: FAIL (`offer_message.dart` no existe).

- [ ] **Step 3: Implementar la función mínima**

```dart
import '../core/format.dart' show fmtRD; // fmtRD ya existe (usado en chat/status)

/// El mensaje al cliente ya NO es texto libre (decisión PO 2026-07-20: se quita
/// la caja para no invitar a filtrar teléfono y saltarse el desbloqueo pagado).
/// Se arma desde los datos estructurados de la oferta. Puede quedar vacío — la
/// columna `provider_offers.message` es NOT NULL con default ''.
String composeOfferMessage({
  required bool isService,
  bool offersShipping = false,
  double? shippingPrice,
  bool offersInstallation = false,
  double? installationPrice,
  bool requiresEvaluation = false,
  double? evaluationPrice,
  String availabilityNote = '',
  String estimatedDuration = '',
}) {
  final parts = <String>[];
  if (!isService) {
    if (offersShipping) {
      parts.add((shippingPrice != null && shippingPrice > 0)
          ? 'Envío: ${fmtRD(shippingPrice)}'
          : 'Envío gratis');
    }
    if (offersInstallation) {
      parts.add((installationPrice != null && installationPrice > 0)
          ? 'Instalación: ${fmtRD(installationPrice)}'
          : 'Instalación incluida');
    }
    if (requiresEvaluation) {
      parts.add((evaluationPrice != null && evaluationPrice > 0)
          ? 'Evaluación: ${fmtRD(evaluationPrice)}'
          : 'Requiere evaluación en sitio');
    }
  } else {
    if (availabilityNote.trim().isNotEmpty) {
      parts.add('Disponibilidad: ${availabilityNote.trim()}');
    }
    if (estimatedDuration.trim().isNotEmpty) {
      parts.add('Duración: ${estimatedDuration.trim()}');
    }
    if (requiresEvaluation) parts.add('Requiere evaluación en sitio');
  }
  return parts.join(' · ');
}
```

> NOTA para el implementador: verificar el nombre/ubicación real de `fmtRD` (grep `String fmtRD`). Si vive en otro archivo, ajustar el import. Si su formato incluye separador de miles, ajustar los `expect` del test a la salida real de `fmtRD` (el contrato es "usa fmtRD", no un string fijo).

- [ ] **Step 4: Correr y verificar que pasa** — `flutter test test/offer_message_test.dart`

- [ ] **Step 5: Commit** — `feat(app): composeOfferMessage (mensaje de oferta auto-armado)`

---

### Task 2: Ampliar `makeOffer` con las columnas nuevas

**Files:**
- Modify: `lib/data/repos.dart:217-244` (`makeOffer`)

**Interfaces:**
- Consumes: nada nuevo.
- Produces: `makeOffer({required Map request, required String businessId, double? price, double? priceMin, double? priceMax, required String message, List<String> imageUrls, String pricingMode, bool offersShipping, double? shippingPrice, bool offersInstallation, double? installationPrice, bool requiresEvaluation, double? evaluationPrice, double? hourlyRate, double? estimatedHours, String availabilityNote, String estimatedDuration})`

- [ ] **Step 1: Reemplazar la firma + el insert**

```dart
Future<void> makeOffer({
  required Map<String, dynamic> request,
  required String businessId,
  double? price,
  double? priceMin,
  double? priceMax,
  required String message,
  List<String> imageUrls = const [],
  String pricingMode = 'fixed',
  bool offersShipping = false,
  double? shippingPrice,
  bool offersInstallation = false,
  double? installationPrice,
  bool requiresEvaluation = false,
  double? evaluationPrice,
  double? hourlyRate,
  double? estimatedHours,
  String availabilityNote = '',
  String estimatedDuration = '',
}) async {
  final uid = supa.auth.currentUser!.id;
  await supa.from('provider_offers').insert({
    'user_id': uid,
    'business_id': businessId,
    'request_id': request['id'],
    'request_title': request['title'],
    'price': price,
    'price_min': priceMin,
    'price_max': priceMax,
    'message': message,
    'status': 'pending',
    'image_urls': imageUrls,
    'offers_shipping': offersShipping,
    'shipping_price': offersShipping && (shippingPrice ?? 0) > 0 ? shippingPrice : null,
    'offers_installation': offersInstallation,
    'installation_price': offersInstallation && (installationPrice ?? 0) > 0 ? installationPrice : null,
    'requires_evaluation': requiresEvaluation,
    'evaluation_price': requiresEvaluation && (evaluationPrice ?? 0) > 0 ? evaluationPrice : null,
    'pricing_mode': pricingMode,
    'hourly_rate': pricingMode == 'hourly' ? hourlyRate : null,
    'estimated_hours': pricingMode == 'hourly' ? estimatedHours : null,
    'availability_note': availabilityNote,
    'estimated_duration': estimatedDuration,
  });
}
```

- [ ] **Step 2: `flutter analyze lib/data/repos.dart`** → 0 issues (los call sites se ajustan en Task 3; hasta entonces el default de `pricingMode` mantiene compatibilidad).

- [ ] **Step 3: Commit** — `feat(app): makeOffer acepta envío/instalación/evaluación/hora/servicio`

---

### Task 3: Form ramificado por kind + quitar mensaje libre

**Files:**
- Modify: `lib/features/provider/request_detail_screen.dart`
- Test: `test/provider_offer_form_test.dart` (create)

**Interfaces:**
- Consumes: `composeOfferMessage` (Task 1), `makeOffer` (Task 2).

- [ ] **Step 1: Estado nuevo** en `_ProviderRequestDetailScreenState`: reemplazar `_msg` por controllers/flags:
  `String _pricingMode = 'fixed';` (servicio: fixed|range|hourly|needs_evaluation; producto usa _fixed/rango),
  `final _hourly = TextEditingController(); final _hours = TextEditingController();`
  `final _availability = TextEditingController(); final _duration = TextEditingController();`
  `bool _offersShipping=false; final _shipping=TextEditingController();`
  `bool _offersInstallation=false; final _installation=TextEditingController();`
  `bool _requiresEvaluation=false; final _evaluation=TextEditingController();`
  Recordar `dispose()` de cada controller.

- [ ] **Step 2: Render** — calcular `final isService = req['kind'] == 'servicio';`. Reemplazar el bloque `else ...[ Text('Tu oferta') ... ]` (líneas ~266-367) por:
  - **Servicio**: segmentado de 4 modos (Precio fijo / Rango / Por hora / Requiere evaluación); campos según modo (por hora → tarifa + horas; needs_evaluation → sin precio); + `TextField` disponibilidad + `TextField` duración estimada.
  - **Producto**: el segmentado fijo/rango actual + los 3 toggles (Ofrezco envío / Ofrezco instalación / Requiere evaluación) cada uno con su costo opcional y etiqueta "Gratis" cuando el costo es 0 (copiar textos exactos de la web `RequestRespondSection.tsx:1872-1975`).
  - **QUITAR** el `TextField _msg` "Mensaje al cliente" (líneas 301-304) y su validación obligatoria (líneas 72-74).
  Fotos, costo estimado y botón "Enviar oferta (gratis)" quedan igual.

- [ ] **Step 3: `_submit()`** — recomponer:
  - Validación: fijo → precio>0; rango → min/max válidos; hourly → tarifa>0 y horas>0; needs_evaluation → sin validación de precio. (Quitar el gate del mensaje.)
  - `final message = composeOfferMessage(isService: isService, offersShipping: _offersShipping, shippingPrice: double.tryParse(_shipping.text), offersInstallation: _offersInstallation, installationPrice: double.tryParse(_installation.text), requiresEvaluation: _requiresEvaluation, evaluationPrice: double.tryParse(_evaluation.text), availabilityNote: _availability.text, estimatedDuration: _duration.text);`
  - Determinar `pricingMode` y llamar `makeOffer(...)` con todos los campos. Producto: `pricingMode = _fixed ? 'fixed' : 'range'`; servicio: `_pricingMode`.
  - Mantener el `try/catch` con `_showSubmitError(e)` (fix de cédula ya aplicado).

- [ ] **Step 4: Widget test** `test/provider_offer_form_test.dart`: montar la pantalla con un `req` de kind 'producto' y otro 'servicio' (inyectando `_req` vía un request mock si hace falta; si el fetch es interno, testear el sub-árbol de la oferta con un helper), y verificar:
  - producto → aparece "Ofrezco envío" y NO aparece "Mensaje al cliente".
  - servicio → aparece el modo "Por hora".
  (Si montar la pantalla completa es inviable por el fetch en `initState`, extraer el bloque de la oferta a un widget `_OfferForm` puro que reciba `isService`/`kind` y testear ese widget — es además mejor diseño.)

- [ ] **Step 5: `flutter analyze` (0) + `flutter test` (verde)**

- [ ] **Step 6: Commit** — `feat(app): form de ofertar con paridad de opciones web + mensaje auto-armado`

---

## Self-review (hecho)

- Cobertura: Fase 1 cubre kind-split, modos de servicio, toggles de producto, quitar mensaje libre, auto-compose, insert. Detalles de producto / paquetes / tienda / expiración → planes P2–P5 explícitos.
- Sin placeholders en los pasos de código (compose + makeOffer con código real).
- Consistencia de tipos: `composeOfferMessage` y `makeOffer` usan los mismos nombres/tipos en Task 1/2/3.
- Riesgo señalado: `fmtRD` (verificar ubicación) y el montaje del widget test (fallback: extraer `_OfferForm`).
