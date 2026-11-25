param(
    [switch]$FrameworkDependent
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$TestsProj = Join-Path $Root "Needle.Core.Tests\Needle.Core.Tests.csproj"
$AppProj = Join-Path $Root "Needle.Screensaver\Needle.Screensaver.csproj"
$PublishDir = Join-Path $Root "dist\publish"
$OutScr = Join-Path $Root "dist\Needle.scr"

Write-Host "Running Needle.Core.Tests..." -ForegroundColor Cyan
dotnet test $TestsProj -c Release --nologo
if ($LASTEXITCODE -ne 0) {
    throw "dotnet test failed with exit code $LASTEXITCODE"
}

Write-Host "Publishing Needle.Screensaver..." -ForegroundColor Cyan
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

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutScr) | Out-Null
Copy-Item -Force $ExePath $OutScr

Write-Host ""
Write-Host "Built: $OutScr" -ForegroundColor Green
Write-Host "Install: Right-click Needle.scr -> Install (and check 'On resume, display logon screen')." -ForegroundColor Gray
