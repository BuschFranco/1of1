# Genera el ícono de la ficha de Play Store: 512x512, fondo #0A0A0A + el
# wordmark de marca (assets/branding/icon_foreground.png, transparente),
# auto-recortado a su contenido real (el PNG fuente trae mucho margen vacío)
# y centrado con un padding prolijo.
Add-Type -AssemblyName System.Drawing

$root = "D:\dev\1of1\app"
$out = "D:\dev\1of1\docs\play-store\assets"
$size = 512

function Get-OpaqueBounds($bitmap) {
    $minX = $bitmap.Width; $minY = $bitmap.Height; $maxX = 0; $maxY = 0
    $step = 2 # muestreo cada 2px para velocidad, suficiente precisión para bounds
    for ($y = 0; $y -lt $bitmap.Height; $y += $step) {
        for ($x = 0; $x -lt $bitmap.Width; $x += $step) {
            if ($bitmap.GetPixel($x, $y).A -gt 10) {
                if ($x -lt $minX) { $minX = $x }
                if ($y -lt $minY) { $minY = $y }
                if ($x -gt $maxX) { $maxX = $x }
                if ($y -gt $maxY) { $maxY = $y }
            }
        }
    }
    return @{ X = $minX; Y = $minY; W = ($maxX - $minX); H = ($maxY - $minY) }
}

$logoFull = New-Object System.Drawing.Bitmap "$root\assets\branding\icon_foreground.png"
$bounds = Get-OpaqueBounds $logoFull
Write-Output "Contenido real detectado: $($bounds.W)x$($bounds.H) en ($($bounds.X),$($bounds.Y))"

$cropRect = New-Object System.Drawing.Rectangle $bounds.X, $bounds.Y, $bounds.W, $bounds.H
$logoCropped = $logoFull.Clone($cropRect, $logoFull.PixelFormat)

$bmp = New-Object System.Drawing.Bitmap $size, $size
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

$bg = [System.Drawing.ColorTranslator]::FromHtml("#0A0A0A")
$g.Clear($bg)

$padding = 0.09
$targetSize = $size * (1 - 2 * $padding)
$scale = [Math]::Min($targetSize / $logoCropped.Width, $targetSize / $logoCropped.Height)
$drawW = $logoCropped.Width * $scale
$drawH = $logoCropped.Height * $scale
$x = ($size - $drawW) / 2
$y = ($size - $drawH) / 2
$g.DrawImage($logoCropped, $x, $y, $drawW, $drawH)

$bmp.Save("$out\icon-512.png", [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose(); $logoCropped.Dispose(); $logoFull.Dispose()
Write-Output "OK: $out\icon-512.png"
