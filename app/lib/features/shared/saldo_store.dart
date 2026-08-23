/// Saldo de créditos compartido por todas las cabeceras.
///
/// Un solo número para toda la app: si «Solicitudes» dijera 38 y «Mis ofertas»
/// 36, el proveedor no sabría cuál creer. Se apoya en `walletBalance()`, que ya
/// cachea 60 s, así que pintar el contador en cuatro pantallas NO son cuatro
/// consultas.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/repos.dart'
    show onWalletBalanceChanged, supa, walletBalance;

class SaldoStore extends ChangeNotifier {
  SaldoStore() {
    // Un desbloqueo cobra créditos y la capa de datos avisa por aquí: el
    // contador tiene que bajar en el acto, sin esperar a que la pantalla se
    // vuelva a montar.
    onWalletBalanceChanged = (nuevo) {
      if (nuevo == null) {
        unawaited(refresh());
      } else {
        set(nuevo);
      }
    };
    // Al cerrar sesión el número del usuario anterior no puede quedarse
    // pintado en la pantalla de login ni en el siguiente arranque.
    //
    // Dentro de un try: en widget-tests no hay Supabase montado y sin esto el
    // singleton reventaría al crearse, tumbando cualquier pantalla que solo
    // quería pintar el contador.
    try {
      supa.auth.onAuthStateChange.listen((e) {
        if (e.event == AuthChangeEvent.signedOut) {
          saldo = null;
          notifyListeners();
        }
      });
    } catch (_) {
      // Sin sesión que vigilar; el contador funciona igual.
    }
  }

  /// `null` = todavía no se sabe. El contador no se pinta hasta tener número:
  /// un «0» falso en la cabecera es peor que no enseñar nada.
  int? saldo;

  Future<void> refresh() async {
    try {
      final n = await walletBalance();
      if (n != saldo) {
        saldo = n;
        notifyListeners();
      }
    } catch (_) {
      // Best-effort: el contador nunca rompe la pantalla que lo hospeda.
    }
  }

  void set(int nuevo) {
    if (nuevo == saldo) return;
    saldo = nuevo;
    notifyListeners();
  }
}

final saldoStore = SaldoStore();
