import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/repos.dart';
import '../../domain/request_share_message.dart';
import '../client/my_requests_screen.dart' show timeAgo;
import 'recruit_share.dart';

/// "Reclutar" (SOLO admin): las solicitudes abiertas, marcando cuales no tienen
/// ni un proveedor al que les toque, para ofrecerselas por WhatsApp a alguien
/// que todavia no esta en Jayalo.
///
/// Espeja `/admin/requests?coverage=gap` de la web (desplegado 2026-09-14), pero
/// SOLO la parte de reclutar: aqui no se borra, no se marca completada y no se
/// reabre. Eso se queda en la web, que tiene pantalla grande.
///
/// `load`/`coverage`/`onShare` se inyectan para poder probar sin red (mismo
/// patron que `AddressScreen`).
class RecruitScreen extends StatefulWidget {
  // 🔴 NO `const`: `load ?? adminListRequests` no es una expresion constante,
  // asi que un constructor `const` no compila. Por eso la ruta la construye
  // como `RecruitScreen()`, sin `const` (a diferencia de las de al lado).
  // ignore: prefer_const_constructors_in_immutables
  RecruitScreen({
    super.key,
    Future<List<Map<String, dynamic>>> Function({int limit})? load,
    Future<Map<String, int>> Function(List<String>)? coverage,
    this.onShare,
    this.onOpen,
  })  : load = load ?? adminListRequests,
        coverage = coverage ?? adminRequestCoverage;

  final Future<List<Map<String, dynamic>>> Function({int limit}) load;
  final Future<Map<String, int>> Function(List<String>) coverage;

  /// La rellena la Task 5. Se inyecta para que el test no abra WhatsApp.
  final void Function(ShareableRequest)? onShare;

  /// Abrir el detalle de la solicitud. Se inyecta para que el test no necesite
  /// un GoRouter montado (`context.push` revienta bajo un `MaterialApp` pelado).
  final void Function(String id)? onOpen;

  @override
  State<RecruitScreen> createState() => _RecruitScreenState();
}

class _RecruitScreenState extends State<RecruitScreen> {
  bool _soloHuecos = true;
  bool _cargando = true;
  bool _error = false;
  List<Map<String, dynamic>> _filas = const [];

  /// id → proveedores fuertes. VACIO si el RPC fallo: en ese caso no se puede
  /// afirmar que algo sea un hueco, asi que no se pinta ningun chip y la vista
  /// cae a "Todas" (mentir con un "Sin proveedor" inventado seria peor que no
  /// decir nada).
  Map<String, int> _cobertura = const {};
  bool _coberturaOk = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  // El messenger se captura ANTES del await, y el aviso va detras de
  // `mounted`. `unawaited` es el idioma del repo (core/error_reporter.dart).
  void _compartir(ShareableRequest r) {
    final messenger = ScaffoldMessenger.of(context);
    unawaited(compartirSolicitud(
      r,
      aviso: (m) {
        if (!mounted) return;
        messenger.showSnackBar(SnackBar(content: Text(m)));
      },
    ));
  }

  /// Toda la fila lleva al detalle READ-ONLY de la solicitud — la misma
  /// pantalla que usa "De otros" en Tus solicitudes (`/client/other-request/`),
  /// que lee por id y se apoya en la RLS: el admin la ve toda. NO se usa
  /// `/provider/request/:id`: esa es la pantalla de OFERTAR, y además sella la
  /// solicitud como vista por el proveedor (`opened_requests`) — abrir para
  /// mirar no puede tocar datos.
  void _abrir(Map<String, dynamic> fila) {
    final id = fila['id'] as String?;
    if (id == null || id.isEmpty) return;
    final onOpen = widget.onOpen;
    if (onOpen != null) {
      onOpen(id);
      return;
    }
    context.push('/client/other-request/$id');
  }

  /// `silencioso: true` es el pull-to-refresh: NO pasa por `_cargando`, que
  /// reemplaza TODA la pantalla por un spinner centrado y tapa la lista que
  /// el `RefreshIndicator` ya está pintando arriba con su propio indicador
  /// nativo. Un fallo silencioso tampoco tumba lo que ya se ve — se queda con
  /// los datos viejos, igual que un fallo de `widget.coverage` de abajo.
  Future<void> _cargar({bool silencioso = false}) async {
    if (!silencioso) {
      setState(() {
        _cargando = true;
        _error = false;
      });
    }
    try {
      final filas = await widget.load();
      Map<String, int> cob = const {};
      var ok = false;
      try {
        cob = await widget.coverage([for (final f in filas) f['id'] as String]);
        ok = true;
      } catch (_) {
        // Un fallo de la cobertura NO tumba el listado.
      }
      if (!mounted) return;
      setState(() {
        _filas = filas;
        _cobertura = cob;
        _coberturaOk = ok;
        if (!ok) _soloHuecos = false;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      if (silencioso) return; // se queda con lo que ya había en pantalla.
      setState(() {
        _error = true;
        _cargando = false;
      });
    }
  }

  // 🔴 Un id que FALTA en `_cobertura` no es un hueco: el RPC solo devuelve
  // fila para las solicitudes que todavia existen, con `fuertes` en 0 cuando
  // de verdad no le toca a nadie. Si el id no aparece, la solicitud dejo de
  // existir entre listar y pedir cobertura — DESCONOCIDO, no cero. Por eso el
  // filtro exige una entrada explicita (`containsKey`) en vez de `?? 0 == 0`,
  // que habria pintado "Sin proveedor" sobre algo que ya no existe.
  List<Map<String, dynamic>> get _visibles => _soloHuecos
      ? [
          for (final f in _filas)
            if (_cobertura.containsKey(f['id']) && _cobertura[f['id']] == 0) f
        ]
      : _filas;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final visibles = _visibles;
    return Scaffold(
      appBar: AppBar(title: const Text('Reclutar')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('No se pudieron cargar las solicitudes'),
                      const SizedBox(height: 8),
                      FilledButton(
                          onPressed: _cargar, child: const Text('Reintentar')),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          if (_coberturaOk) ...[
                            // 🔴 Esta pastilla y el chip de `_Fila` dicen los
                            // dos, literal, "Sin proveedor" — y cuando el
                            // filtro esta activo TODA fila visible lleva ese
                            // chip, asi que ambos textos conviven en
                            // pantalla a la vez. Es un `Text` normal (como
                            // el resto de la pantalla) a proposito: un
                            // `RichText` aqui se saltaria el escalado de
                            // letra del sistema (`MediaQuery.textScalerOf`)
                            // y dejaria a `find.text()` ciego a un typo en
                            // el literal para siempre. La ambiguedad para
                            // los tests se resuelve ACOTANDO el finder del
                            // chip a su `ListTile` (ver
                            // `recruit_screen_test.dart`), no cambiando el
                            // tipo de widget.
                            _pastilla('Sin proveedor', _soloHuecos,
                                () => setState(() => _soloHuecos = true)),
                            const SizedBox(width: 8),
                          ],
                          _pastilla('Todas', !_soloHuecos,
                              () => setState(() => _soloHuecos = false)),
                          const Spacer(),
                          // 🔴 El texto dice lo que se esta VIENDO: en "Todas"
                          // no puede decir "sin proveedor".
                          Text(
                            _soloHuecos
                                ? '${visibles.length} sin proveedor'
                                : '${visibles.length} abiertas',
                            style: TextStyle(
                                fontSize: 12, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      // El RefreshIndicator envuelve TAMBIÉN el vacío — antes
                      // solo existía en la rama con filas, y "Sin proveedor"
                      // vacío es justo cuando más ganas hay de reintentar.
                      // `AlwaysScrollableScrollPhysics` en las dos ramas: sin
                      // ella el gesto de pull-to-refresh no arranca cuando el
                      // contenido no llena la pantalla (lista corta o vacía).
                      child: RefreshIndicator(
                        onRefresh: () => _cargar(silencioso: true),
                        child: visibles.isEmpty
                            ? LayoutBuilder(
                                builder: (context, constraints) => ListView(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  children: [
                                    ConstrainedBox(
                                      constraints: BoxConstraints(
                                          minHeight: constraints.maxHeight),
                                      child: Center(
                                        child: Padding(
                                          padding: const EdgeInsets.all(24),
                                          child: Text(
                                            _soloHuecos
                                                ? 'Ninguna solicitud abierta se quedó sin proveedor'
                                                : 'No hay solicitudes abiertas',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                                color: cs.onSurfaceVariant),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(),
                                itemCount: visibles.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (_, i) => _Fila(
                                  fila: visibles[i],
                                  fuertes: _coberturaOk &&
                                          _cobertura.containsKey(
                                              visibles[i]['id'])
                                      ? _cobertura[visibles[i]['id']]
                                      : null,
                                  onShare: widget.onShare ?? _compartir,
                                  onTap: () => _abrir(visibles[i]),
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _pastilla(String label, bool sel, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: sel ? cs.primary : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
                  color: sel ? Colors.white : cs.onSurfaceVariant)),
        ),
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila(
      {required this.fila,
      required this.fuertes,
      this.onShare,
      this.onTap});
  final Map<String, dynamic> fila;

  /// null = no se pudo saber (el RPC fallo o esta solicitud ya no aparece en
  /// la cobertura): no se pinta chip.
  final int? fuertes;
  final void Function(ShareableRequest)? onShare;

  /// Tocar la fila (fuera del boton de compartir) abre el detalle.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final titulo = (fila['title'] as String?)?.trim();
    final zona = (fila['zone'] as String?)?.trim();
    // `created_at` viaja en `kAdminListCols` desde siempre "para pintar la
    // fecha" (ver el comentario en repos.dart), pero la pantalla nunca la
    // usó. Para reclutar importa: una solicitud de hace 30 días no se ofrece
    // igual que una de hoy. `Wrap`, no `Row`: con zona larga + fecha + chip
    // en una sola línea fija, un teléfono angosto la desborda.
    final creadaEn = fila['created_at'] as String?;
    final creadaEnFecha = creadaEn == null ? null : DateTime.tryParse(creadaEn);
    final fecha = creadaEnFecha == null ? null : timeAgo(creadaEnFecha);
    return ListTile(
      // El `IconButton` de compartir se come su propio toque, asi que este
      // `onTap` no se dispara al compartir.
      onTap: onTap,
      title: Text(titulo == null || titulo.isEmpty ? 'Sin título' : titulo),
      subtitle: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (fecha != null)
            Text(fecha, style: TextStyle(color: cs.onSurfaceVariant)),
          if (zona != null && zona.isNotEmpty)
            Text(zona, style: TextStyle(color: cs.onSurfaceVariant)),
          if (fuertes != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: fuertes == 0
                    ? cs.errorContainer
                    : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                fuertes == 0 ? 'Sin proveedor' : '$fuertes proveedores',
                style: TextStyle(
                  fontSize: 11,
                  color: fuertes == 0 ? cs.onErrorContainer : cs.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.share_outlined),
        tooltip: 'Compartir por WhatsApp',
        onPressed: onShare == null
            ? null
            : () => onShare!(ShareableRequest.fromRow(fila)),
      ),
    );
  }
}
