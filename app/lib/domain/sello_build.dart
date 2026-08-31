/// De qué rama y qué commit salió el binario que está corriendo.
///
/// Nace del APK 1.0.4+87 (2026-08-30): se compiló desde una rama hermana y le
/// quitó al teléfono 26 commits de trabajo. Mirando el aparato no había forma
/// de saberlo —solo haciendo arqueología de git— y por eso tardó en verse. El
/// sello convierte «creo que es esta rama» en un dato que se lee en Ajustes.
///
/// Lo hornea Gradle en el manifest y lo sirve un `MethodChannel`; aquí solo se
/// interpreta. La parte interpretable vive separada del canal a propósito, para
/// poder probarla sin plataforma debajo.
class SelloBuild {
  const SelloBuild({
    required this.rama,
    required this.sha,
    required this.sucio,
  });

  final String rama;
  final String sha;

  /// El árbol tenía cambios sin commitear al compilar. Es lo más importante que
  /// puede decir el sello: el código que corre **no está en ningún commit**, así
  /// que no se puede reconstruir ni saber qué lleva.
  final bool sucio;

  /// Lo que se muestra cuando no hay sello (build viejo, o compilado fuera de un
  /// repo git). No se inventa nada: se dice que no se sabe.
  static const desconocido = SelloBuild(
    rama: 'desconocida',
    sha: 'desconocido',
    sucio: false,
  );

  bool get conocido => sha != 'desconocido' && sha.isNotEmpty;

  /// Tolera que falte cualquier clave y que lleguen vacías: un mapa a medias
  /// vale más que una excepción en Ajustes.
  factory SelloBuild.desdeMapa(Map<Object?, Object?>? m) {
    String leer(String k, String siVacio) {
      final v = (m?[k] as String?)?.trim() ?? '';
      return v.isEmpty ? siVacio : v;
    }

    return SelloBuild(
      rama: leer('rama', 'desconocida'),
      sha: leer('sha', 'desconocido'),
      sucio: leer('sucio', '0') == '1',
    );
  }

  /// Una línea para Ajustes. El aviso de «sin commitear» va al final y en
  /// palabras, no con un símbolo: quien mire esto puede no saber qué significa
  /// una marca rara al lado de un hash.
  String get linea {
    if (!conocido) return 'origen desconocido';
    return sucio ? '$rama · $sha · con cambios sin commitear' : '$rama · $sha';
  }
}

/// Título PÚBLICO de la fila de versión: «Jayalo v1.0.4 (98)» — el producto y
/// su versión, sin interioridades (decisión PO 2026-08-31: la rama y el sha no
/// son para el usuario). `version` llega como la compone Ajustes
/// («1.0.4+98») o como 'desconocida'/null si PackageInfo falló.
String tituloVersionPublica(String? version) {
  if (version == null || version.isEmpty || version == 'desconocida') {
    return 'Jayalo';
  }
  final i = version.indexOf('+');
  if (i <= 0 || i == version.length - 1) return 'Jayalo v$version';
  final nombre = version.substring(0, i);
  final build = version.substring(i + 1);
  return 'Jayalo v$nombre ($build)';
}

/// Subtítulo de la fila de versión. El sello (rama · sha) queda OCULTO por
/// defecto y se revela con el gesto clásico de Android (5 toques en la fila):
/// sigue al alcance de un brazo cuando algo no cuadra —la razón por la que
/// existe, el APK +87— sin enseñarle interioridades a todo el mundo.
/// EXCEPCIÓN deliberada: un árbol SUCIO se enseña siempre, revelado o no — es
/// lo más grave que puede decir el sello (código que no está en ningún commit)
/// y un build legítimo de release jamás debería estarlo.
String? subtituloVersion(SelloBuild sello, {required bool revelado}) {
  if (revelado || sello.sucio) return sello.linea;
  return null;
}
