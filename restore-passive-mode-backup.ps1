param(
    [Parameter(Position = 0)]
    [string]$SpotifastPath = "."
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath $SpotifastPath).Path
$backupRoot = Join-Path $root ".passive-mode-backup"

if (-not (Test-Path -LiteralPath $backupRoot)) {
    Write-Error "Geen .passive-mode-backup map gevonden."
    exit 1
}

$latest = Get-ChildItem -LiteralPath $backupRoot -Directory |
    Sort-Object Name -Descending |
    Select-Object -First 1

if (-not $latest) {
    Write-Error "Geen backup gevonden."
    exit 1
}

Copy-Item -LiteralPath (Join-Path $latest.FullName "src\app.rs") `
    -Destination (Join-Path $root "src\app.rs") -Force
Copy-Item -LiteralPath (Join-Path $latest.FullName "src\settings.rs") `
    -Destination (Join-Path $root "src\settings.rs") -Force
Copy-Item -LiteralPath (Join-Path $latest.FullName "src\ui\settings.rs") `
    -Destination (Join-Path $root "src\ui\settings.rs") -Force

Write-Host "Hersteld vanaf: $($latest.FullName)" -ForegroundColor Green
