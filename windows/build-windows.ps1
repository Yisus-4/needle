param(
    [switch]$FrameworkDependent
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$TestsProj = Join-Path $Root "Needle.Core.Tests\Needle.Core.Tests.csproj"
$AppProj = Join-Path $Root "Needle.Screensaver\Needle.Screensaver.csproj"
$PublishDir = Join-Path $Root "dist\publish"
$OutExe = Join-Path $Root "dist\Needle.exe"
$OutScr = Join-Path $Root "dist\Needle.scr"

Write-Host "Running Needle.Core.Tests..." -ForegroundColor Cyan
dotnet test $TestsProj -c Release --nologo
if ($LASTEXITCODE -ne 0) {
    throw "dotnet test failed with exit code $LASTEXITCODE"
}

Write-Host "Publishing Needle for Windows..." -ForegroundColor Cyan
if (Test-Path $PublishDir) { Remove-Item -Recurse -Force $PublishDir }

$SelfContained = if ($FrameworkDependent) { "false" } else { "true" }

dotnet publish $AppProj `
    -c Release `
    -r win-x64 `
    -p:SelfContained=$SelfContained `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:EnableCompressionInSingleFile=true `
    -p:DebugType=None `
    -p:DebugSymbols=false `
    -o $PublishDir
if ($LASTEXITCODE -ne 0) {
    throw "dotnet publish failed with exit code $LASTEXITCODE"
}

$ExePath = Join-Path $PublishDir "Needle.exe"
if (-not (Test-Path $ExePath)) {
    throw "Expected output executable not found: $ExePath"
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutExe) | Out-Null
Copy-Item -Force $ExePath $OutExe
Copy-Item -Force $ExePath $OutScr

Write-Host ""
Write-Host "Built:" -ForegroundColor Green
Write-Host "  - $OutExe  (Recomendado: abre en bandeja del sistema, Ctrl+Alt+L para bloquear con letras + Vista previa en 1 clic)" -ForegroundColor Cyan
Write-Host "  - $OutScr  (Opcional: clic derecho -> Instalar como salvapantallas clasico de Windows)" -ForegroundColor Gray
