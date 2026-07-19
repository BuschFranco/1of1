# Compone UNA captura de marketing para Play Store a partir de una captura
# cruda del celu (tomada con adb): fondo de marca + headline en Jost +
# la captura real con esquinas redondeadas y una sombra sutil.
#
# Uso:
#   .\generate-screenshot.ps1 -RawScreenshot ".\raw\mapa.png" -Headline "ENCONTRA TU CANCHA" -Subtitle "Canchas cerca tuyo, con toda la info" -OutName "01-mapa"
param(
    [Parameter(Mandatory=$true)] [string]$RawScreenshot,
    [Parameter(Mandatory=$true)] [string]$Headline,
    [Parameter(Mandatory=$true)] [string]$Subtitle,
    [Parameter(Mandatory=$true)] [string]$OutName
)

Add-Type -AssemblyName System.Drawing

$root = "D:\dev\1of1\app"
$outDir = "D:\dev\1of1\docs\play-store\assets\screenshots"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

# Lienzo final: 1080x1920 (retrato, formato estándar de Play Store).
$W = 1080; $H = 1920

$fonts = New-Object System.Drawing.Text.PrivateFontCollection
$fonts.AddFontFile("$root\assets\fonts\jost\Jost-900-Black.otf")
$fonts.AddFontFile("$root\assets\fonts\jost\Jost-600-Semi.otf")
$familyBlack = $fonts.Families[0]
$familySemi = $fonts.Families[1]

$bmp = New-Object System.Drawing.Bitmap $W, $H
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

$bg = [System.Drawing.ColorTranslator]::FromHtml("#0A0A0A")
$g.Clear($bg)

$accent = [System.Drawing.ColorTranslator]::FromHtml("#FF6B1A")
$glowPath = New-Object System.Drawing.Drawing2D.GraphicsPath
$glowPath.AddEllipse((-$W * 0.3), (-$H * 0.12), ($W * 1.6), ($H * 0.55))
$glowBrush = New-Object System.Drawing.Drawing2D.PathGradientBrush $glowPath
$glowBrush.CenterColor = [System.Drawing.Color]::FromArgb(50, $accent.R, $accent.G, $accent.B)
$glowBrush.SurroundColors = @([System.Drawing.Color]::FromArgb(0, $accent.R, $accent.G, $accent.B))
$g.FillPath($glowBrush, $glowPath)

# Headline (auto-fit de ancho, hasta 2 líneas si hace falta lo maneja el caller
# pasando \n en $Headline).
$marginX = $W * 0.07
$textAreaW = $W - 2 * $marginX
$headlineSize = 62
$fontHeadline = New-Object System.Drawing.Font $familyBlack, $headlineSize, ([System.Drawing.FontStyle]::Bold)
do {
    $fontHeadline = New-Object System.Drawing.Font $familyBlack, $headlineSize, ([System.Drawing.FontStyle]::Bold)
    $measured = $g.MeasureString($Headline, $fontHeadline, [int]$textAreaW)
    if ($measured.Height -le ($H * 0.16)) { break }
    $headlineSize -= 2
} while ($headlineSize -gt 28)

$brushWhite = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
$rectHeadline = New-Object System.Drawing.RectangleF $marginX, ($H * 0.06), $textAreaW, ($H * 0.16)
$g.DrawString($Headline, $fontHeadline, $brushWhite, $rectHeadline)

$fontSub = New-Object System.Drawing.Font $familySemi, 30, ([System.Drawing.FontStyle]::Regular)
$brushGray = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(190, 255, 255, 255))
$rectSub = New-Object System.Drawing.RectangleF $marginX, ($H * 0.145), $textAreaW, ($H * 0.06)
$g.DrawString($Subtitle, $fontSub, $brushGray, $rectSub)

# Captura real, con esquinas redondeadas, ocupando el resto del lienzo.
$raw = [System.Drawing.Image]::FromFile($RawScreenshot)
$shotTop = $H * 0.24
$shotW = $W * 0.86
$shotH = $shotW * ($raw.Height / $raw.Width)
if ($shotTop + $shotH -gt $H * 0.98) {
    $shotH = ($H * 0.98) - $shotTop
    $shotW = $shotH * ($raw.Width / $raw.Height)
}
$shotX = ($W - $shotW) / 2

$radius = 36
$path = New-Object System.Drawing.Drawing2D.GraphicsPath
$d = $radius * 2
$rect = New-Object System.Drawing.RectangleF $shotX, $shotTop, $shotW, $shotH
$path.AddArc($rect.X, $rect.Y, $d, $d, 180, 90)
$path.AddArc(($rect.X + $rect.Width - $d), $rect.Y, $d, $d, 270, 90)
$path.AddArc(($rect.X + $rect.Width - $d), ($rect.Y + $rect.Height - $d), $d, $d, 0, 90)
$path.AddArc($rect.X, ($rect.Y + $rect.Height - $d), $d, $d, 90, 90)
$path.CloseFigure()

$g.SetClip($path)
$g.DrawImage($raw, $shotX, $shotTop, $shotW, $shotH)
$g.ResetClip()

$borderPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(60, 255, 255, 255)), 2
$g.DrawPath($borderPen, $path)

$bmp.Save("$outDir\$OutName.png", [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose(); $raw.Dispose()
Write-Output "OK: $outDir\$OutName.png"
