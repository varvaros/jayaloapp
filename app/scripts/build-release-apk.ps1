<#
.SYNOPSIS
    Build de release de Jayalo con ofuscacion de Dart + simbolos archivados.

.DESCRIPTION
    Compila un APK (o AAB con -Bundle) de release aplicando:
      --obfuscate            ofusca los simbolos Dart en libapp.so
      --split-debug-info     extrae los simbolos a symbols/<version> para poder
                             des-ofuscar despues los stack traces del
                             error-tracking (capa #12).

    R8 + shrinkResources se aplican solos: estan configurados en
    android/app/build.gradle.kts para el buildType release.

    IMPORTANTE: guarda la carpeta symbols/<version> de CADA release publicado.
    Sin ella no se pueden leer los crashes ofuscados de esa version. Estan
    fuera de git (ver .gitignore: app.*.symbols) — archivarlas aparte.

.PARAMETER Bundle
    Genera un App Bundle (.aab) para Play Store en vez de APK.

.EXAMPLE
    ./scripts/build-release-apk.ps1
    ./scripts/build-release-apk.ps1 -Bundle
#>
param(
    [switch]$Bundle
)

$ErrorActionPreference = "Stop"

# Raiz del proyecto Flutter (un nivel arriba de scripts/).
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

# Version desde pubspec.yaml (ej. "1.0.0+1" -> "1.0.0+1").
$versionLine = Select-String -Path "pubspec.yaml" -Pattern '^version:\s*(.+)$' | Select-Object -First 1
$version = if ($versionLine) { $versionLine.Matches[0].Groups[1].Value.Trim() } else { "unknown" }
$symbolsDir = Join-Path $projectRoot "symbols/$version"

Write-Host "==> Version:        $version"
Write-Host "==> Simbolos ->     $symbolsDir"

if (-not (Test-Path "android/key.properties")) {
    Write-Warning "android/key.properties NO existe: se firmara con DEBUG keys (no publicable)."
    Write-Warning "Ver docs/build-release.md para generar el keystore de subida."
}

$target = if ($Bundle) { "appbundle" } else { "apk" }

Write-Host "==> flutter build $target --release --obfuscate --split-debug-info=$symbolsDir"
& flutter build $target --release --obfuscate --split-debug-info="$symbolsDir"
if ($LASTEXITCODE -ne 0) { throw "flutter build fallo (exit $LASTEXITCODE)" }

Write-Host ""
Write-Host "OK. Artefacto en build/app/outputs/" -ForegroundColor Green
Write-Host "RECUERDA archivar $symbolsDir para des-ofuscar crashes de esta version." -ForegroundColor Yellow
