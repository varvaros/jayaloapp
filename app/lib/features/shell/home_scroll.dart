import 'package:flutter/widgets.dart';

/// Controlador compartido de la lista del home (cliente o proveedor; solo una
/// vive a la vez). El shell lo usa para que el ATRÁS suba al tope antes de
/// preguntar si cerrar la app.
final ScrollController homeScrollController = ScrollController();
