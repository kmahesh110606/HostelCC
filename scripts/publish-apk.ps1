param(
    [Parameter(Mandatory=$true)][string]$ApiUrl,
    [switch]$DebugBuild
)
$ErrorActionPreference='Stop'
$workspace=Split-Path $PSScriptRoot -Parent
$uri=[Uri]$ApiUrl
if (-not $uri.IsAbsoluteUri -or $uri.Scheme -notin @('http','https') -or -not $uri.AbsolutePath.TrimEnd('/').EndsWith('/api')) {
    throw 'ApiUrl must be an absolute HTTP(S) address ending in /api.'
}
if (-not $DebugBuild -and $uri.Scheme -ne 'https') { throw 'Release APKs require HTTPS.' }
Push-Location (Join-Path $workspace 'hostelCC-app')
try {
    $mode=if($DebugBuild){'debug'}else{'release'}
    & flutter build apk "--$mode" "--dart-define=API_BASE_URL=$ApiUrl"
    if($LASTEXITCODE -ne 0){throw 'Flutter build failed. The published APK was not changed.'}
    $destination=Join-Path $workspace 'HostelCC-web/public/downloads'
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    Copy-Item -LiteralPath "build/app/outputs/flutter-apk/app-$mode.apk" -Destination (Join-Path $destination 'HostelCC.apk')
    Write-Output "Published $mode APK. Rebuild the web Docker image to include it."
} finally { Pop-Location }
