import 'package:flutter/material.dart';

import '../../core/brand.dart';
import '../../data/repos.dart' show BusinessCardInfo;
import '../shared/brand_kit.dart';
import '../shared/network_image.dart';
import '../shared/product_list_card.dart';
import '../shell/floating_nav_bar.dart';
import 'catalog_articulos.dart';

/// Catálogo POR ARTÍCULOS (Task 6, 2026-09-07), camino nuevo que reemplaza a
/// `CatalogPortada` (Task 7 la borra): en vez de "recién publicados / tiendas
/// / por categoría" pinta cuatro secciones fijas — Proveedores, Productos,
/// Servicios, Paquetes — sobre los mismos 60 ítems ya cargados. `SeccionTitulo`,
/// `_Carrusel` y `_StoreCircle` se MUEVEN aquí desde `catalog_portada.dart`
/// (adaptados); pura: recibe datos y callbacks, no pide nada a la red.
/// [header] es la tira de chips: va dentro de la lista para desplazarse con
/// ella.
class CatalogSecciones extends StatelessWidget {
  const CatalogSecciones({
    super.key,
    required this.items,
    required this.negocios,
    required this.proveedores,
    required this.conteos,
    required this.onVerTodos,
    required this.onStore,
    this.header,
    this.controller,
  });

  final List<Map<String, dynamic>> items;
  final Map<String, BusinessCardInfo> negocios;

  /// Proveedores «con algún artículo» en [items] (ver `proveedoresDeItems`);
  /// el caller ya aplicó `kTopeProveedores` — aquí se vuelve a recortar por
  /// si acaso, nunca de más.
  final List<Proveedor> proveedores;
  final ({int productos, int servicios, int paquetes, int proveedores}) conteos;

  /// Avisa con `'producto' | 'servicio' | 'paquete' | 'proveedor'`: el caller
  /// decide a qué lista completa navegar.
  final ValueChanged<String> onVerTodos;
  final ValueChanged<String> onStore;
  final Widget? header;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final secciones = seccionesCatalogo(items);
    final rieleProveedores = proveedores.take(kTopeProveedores).toList();
    var i = 0;
    return ListView(
      controller: controller,
      padding: EdgeInsets.only(bottom: 12 + navBarReservedSpace(context)),
      children: [
        ?header,
        if (rieleProveedores.isNotEmpty) ...[
          SeccionTitulo(
            'Proveedores',
            n: conteos.proveedores,
            onMore: () => onVerTodos('proveedor'),
          ).cascadeIn(i++),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                for (final p in rieleProveedores) ...[
                  _StoreCircle(
                    name: p.name,
                    logoUrl: p.logoUrl,
                    linea: _lineaDe(p),
                    onTap: () => onStore(p.id),
                  ),
                  const SizedBox(width: 14),
                ],
              ],
            ),
          ).cascadeIn(i++),
        ],
        if (secciones.productos.isNotEmpty) ...[
          SeccionTitulo(
            'Productos',
            n: conteos.productos,
            onMore: () => onVerTodos('producto'),
          ).cascadeIn(i++),
          _Carrusel(
            items: secciones.productos,
            negocios: negocios,
          ).cascadeIn(i++),
        ],
        if (secciones.servicios.isNotEmpty) ...[
          SeccionTitulo(
            'Servicios',
            n: conteos.servicios,
            onMore: () => onVerTodos('servicio'),
          ).cascadeIn(i++),
          _Carrusel(
            items: secciones.servicios,
            negocios: negocios,
          ).cascadeIn(i++),
        ],
        if (secciones.paquetes.isNotEmpty) ...[
          SeccionTitulo(
            'Paquetes',
            n: conteos.paquetes,
            onMore: () => onVerTodos('paquete'),
          ).cascadeIn(i++),
          _Carrusel(
            items: secciones.paquetes,
            negocios: negocios,
          ).cascadeIn(i++),
        ],
      ],
    );
  }
}

/// Línea bajo el círculo/nombre de un proveedor: su «qué hace» si lo tiene,
/// si no y declara local «Tienda física» (autodeclarado, nunca el verde de
/// verificado), si no nada.
String? _lineaDe(Proveedor p) => p.queHace.isNotEmpty
    ? p.queHace
    : (p.hasPhysicalLocation ? 'Tienda física' : null);

/// Cabecera de sección: título 14 w600 en tinta de título, el conteo [n] en
/// gris 11.5 w500 justo detrás y, si hay [onMore], «Ver todos» en violeta a
/// la derecha.
class SeccionTitulo extends StatelessWidget {
  const SeccionTitulo(this.titulo, {super.key, this.n, this.onMore});
  final String titulo;
  final int? n;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Ritmo vertical (smoke PO 2026-09-06, «está todo muy pegado»): 24 de
    // aire sobre el título y 10 debajo, y la fila mide SIEMPRE 44 (la altura
    // del área táctil de «Ver todos»), así los títulos sin enlace respiran
    // igual que los que lo llevan.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 12, 10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      titulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: jayaloHead(context),
                      ),
                    ),
                  ),
                  if (n != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      '$n',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onMore != null)
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
                child: InkWell(
                  onTap: onMore,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 12,
                    ),
                    child: Text(
                      'Ver todos',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
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
}

/// Fila horizontal de [ProductCarouselCard]. `IntrinsicHeight` + `stretch`:
/// todas las tarjetas de la fila miden lo que mida la más alta, sin extent
/// fijo (crece con la fuente del sistema).
class _Carrusel extends StatelessWidget {
  const _Carrusel({required this.items, required this.negocios});
  final List<Map<String, dynamic>> items;
  final Map<String, BusinessCardInfo> negocios;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final it in items) ...[
            ProductCarouselCard(
              item: it,
              negocio: negocios[it['business_id']],
              showTypeTag: true,
              width: 150,
            ),
            const SizedBox(width: 10),
          ],
        ],
      ),
    ),
  );
}

/// Círculo de proveedor: logo `cover` o la inicial sobre lila, el nombre a
/// dos líneas y, si hay [linea] (qué hace o «Tienda física»), una tercera
/// línea de una sola línea de texto — teal si es «Tienda física», gris en
/// cualquier otro caso. Tocar abre la tienda del proveedor (lo decide el
/// caller).
class _StoreCircle extends StatelessWidget {
  const _StoreCircle({
    required this.name,
    required this.logoUrl,
    required this.onTap,
    this.linea,
  });
  final String name;
  final String? logoUrl;
  final VoidCallback onTap;
  final String? linea;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final teal =
        (dark ? JayaloStatus.requisitoDark : JayaloStatus.requisitoLight).ink;
    final inicial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.primaryContainer,
                boxShadow: const [
                  BoxShadow(
                    color: JayaloColors.warmShadow,
                    blurRadius: 14,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              alignment: Alignment.center,
              child: logoUrl == null
                  ? Text(
                      inicial,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: cs.onPrimaryContainer,
                      ),
                    )
                  : JayaloNetworkImage(
                      logoUrl!,
                      width: 54,
                      height: 54,
                      fit: BoxFit.cover,
                    ),
            ),
            const SizedBox(height: 5),
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10.5,
                height: 1.2,
                fontWeight: FontWeight.w500,
                color: cs.onSurface,
              ),
            ),
            if (linea != null) ...[
              const SizedBox(height: 2),
              Text(
                linea!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w500,
                  color: linea == 'Tienda física' ? teal : cs.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Tarjeta de proveedor (fila): logo/inicial 44, nombre 14 w600, «Verificado»
/// (verde `JayaloColors.success` + `Icons.verified`, SOLO si Jayalo lo
/// verificó), «qué hace» 12 gris si lo tiene, y una línea «Tienda física»
/// (teal, autodeclarado) · ciudad 11. Chevron a la derecha.
class ProveedorCard extends StatelessWidget {
  const ProveedorCard({super.key, required this.p, required this.onTap});
  final Proveedor p;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final success = dark ? JayaloColors.dSuccess : JayaloColors.success;
    final teal =
        (dark ? JayaloStatus.requisitoDark : JayaloStatus.requisitoLight).ink;
    final inicial = p.name.trim().isEmpty
        ? '?'
        : p.name.trim()[0].toUpperCase();
    final tieneCiudad = p.city != null && p.city!.isNotEmpty;
    final tieneTiendaOCiudad = p.hasPhysicalLocation || tieneCiudad;
    return JayaloCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.primaryContainer,
            ),
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
            child: p.logoUrl == null
                ? Text(
                    inicial,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: cs.onPrimaryContainer,
                    ),
                  )
                : JayaloNetworkImage(
                    p.logoUrl!,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: jayaloHead(context),
                  ),
                ),
                if (p.verificado) ...[
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified, size: 13, color: success),
                      const SizedBox(width: 3),
                      Text(
                        'Verificado',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: success,
                        ),
                      ),
                    ],
                  ),
                ],
                if (p.queHace.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    p.queHace,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
                if (tieneTiendaOCiudad) ...[
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                      children: [
                        if (p.hasPhysicalLocation)
                          TextSpan(
                            text: 'Tienda física',
                            style: TextStyle(
                              color: teal,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        if (p.hasPhysicalLocation && tieneCiudad)
                          const TextSpan(text: ' · '),
                        if (tieneCiudad) TextSpan(text: p.city),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right, size: 20, color: cs.onSurfaceVariant),
        ],
      ),
    );
  }
}

/// Píldoras de proveedores «que coinciden» con una búsqueda: logo 20 + nombre
/// 12 w600, bajo la etiqueta «Proveedores que coinciden:». Sin proveedores no
/// pinta nada (`SizedBox.shrink`) para no dejar un hueco con solo la
/// etiqueta.
class ProveedoresCoinciden extends StatelessWidget {
  const ProveedoresCoinciden({
    super.key,
    required this.proveedores,
    required this.onStore,
  });
  final List<Proveedor> proveedores;
  final ValueChanged<String> onStore;

  @override
  Widget build(BuildContext context) {
    if (proveedores.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Proveedores que coinciden:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in proveedores)
                _PildoraProveedor(p: p, onTap: () => onStore(p.id)),
            ],
          ),
        ],
      ),
    );
  }
}

class _PildoraProveedor extends StatelessWidget {
  const _PildoraProveedor({required this.p, required this.onTap});
  final Proveedor p;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final inicial = p.name.trim().isEmpty
        ? '?'
        : p.name.trim()[0].toUpperCase();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: JayaloColors.warmShadow,
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.primaryContainer,
              ),
              clipBehavior: Clip.antiAlias,
              alignment: Alignment.center,
              child: p.logoUrl == null
                  ? Text(
                      inicial,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: cs.onPrimaryContainer,
                      ),
                    )
                  : JayaloNetworkImage(
                      p.logoUrl!,
                      width: 20,
                      height: 20,
                      fit: BoxFit.cover,
                    ),
            ),
            const SizedBox(width: 6),
            Text(
              p.name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: jayaloHead(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
