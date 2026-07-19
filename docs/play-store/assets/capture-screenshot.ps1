# Todo en uno: toma una captura del celu conectado por adb y la compone como
# imagen de marketing para Play Store (headline + subtítulo + tu pantalla real).
# Corré esto con la app ABIERTA en la pantalla que querés capturar.
#
# Uso:
#   .\capture-screenshot.ps1 -Headline "ENCONTRA TU CANCHA" -Subtitle "Canchas cerca tuyo, con toda la info" -OutName "01-mapa"
param(
    [Parameter(Mandatory=$true)] [string]$Headline,
    [Parameter(Mandatory=$true)] [string]$Subtitle,
    [Parameter(Mandatory=$true)] [string]$OutName
)

$adb = "C:\Android\platform-tools\adb.exe"
$rawDir = "D:\dev\1of1\docs\play-store\assets\screenshots\raw"
New-Item -ItemType Directory -Force -Path $rawDir | Out-Null
$rawPath = "$rawDir\$OutName-raw.png"

& $adb exec-out screencap -p > $rawPath
if ((Get-Item $rawPath).Length -lt 1000) {
    Write-Error "La captura salió vacía. ¿Está el celu conectado (adb devices)?"
    exit 1
}
Write-Output "Captura cruda OK: $rawPath"

& powershell -ExecutionPolicy Bypass -File "D:\dev\1of1\docs\play-store\assets\generate-screenshot.ps1" `
    -RawScreenshot $rawPath -Headline $Headline -Subtitle $Subtitle -OutName $OutName
