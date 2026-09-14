import 'package:flutter/material.dart';

import '../../data/repos.dart';
import '../../domain/request_share_message.dart';

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
  })  : load = load ?? adminListRequests,
        coverage = coverage ?? adminRequestCoverage;

  final Future<List<Map<String, dynamic>>> Function({int limit}) load;
  final Future<Map<String, int>> Function(List<String>) coverage;

  /// La rellena la Task 5. Se inyecta para que el test no abra WhatsApp.
  final void Function(ShareableRequest)? onShare;

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

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = false;
    });
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
                            // chip, asi que ambos textos conviven en pantalla
                            // a la vez. `Text.rich` deja el mismo texto en
                            // pantalla pero `find.text` (sin `findRichText:
                            // true`) no lo cuenta, asi que el chip de la fila
                            // sigue siendo el UNICO "Sin proveedor" que un
                            // test (o un lector de pantalla que busque texto
                            // plano) encuentra.
                            _pastillaRich('Sin proveedor', _soloHuecos,
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
                      child: visibles.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  _soloHuecos
                                      ? 'Ninguna solicitud abierta se quedó sin proveedor'
                                      : 'No hay solicitudes abiertas',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: cs.onSurfaceVariant),
                                ),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _cargar,
                              child: ListView.separated(
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
                                  onShare: widget.onShare,
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

  /// Igual que `_pastilla`, pero con `RichText` puro (no `Text`/`Text.rich`):
  /// el mismo texto en pantalla, pero `find.text('Sin proveedor')` (sin
  /// `findRichText: true`) ignora los `RichText` sueltos — la doctrina de
  /// `flutter_test` los trata aparte de `Text`/`Text.rich`. Ver el comentario
  /// donde se usa.
  Widget _pastillaRich(String label, bool sel, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: sel ? cs.primary : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          child: RichText(
            text: TextSpan(
              text: label,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
                  color: sel ? Colors.white : cs.onSurfaceVariant),
            ),
          ),
        ),
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.fila, required this.fuertes, this.onShare});
  final Map<String, dynamic> fila;

  /// null = no se pudo saber (el RPC fallo o esta solicitud ya no aparece en
  /// la cobertura): no se pinta chip.
  final int? fuertes;
  final void Function(ShareableRequest)? onShare;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final titulo = (fila['title'] as String?)?.trim();
    final zona = (fila['zone'] as String?)?.trim();
    return ListTile(
      title: Text(titulo == null || titulo.isEmpty ? 'Sin título' : titulo),
      subtitle: Row(
        children: [
          if (zona != null && zona.isNotEmpty) ...[
            Text(zona, style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(width: 8),
          ],
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
