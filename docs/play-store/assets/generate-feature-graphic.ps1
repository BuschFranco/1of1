# Genera el Feature Graphic de Play Store: 1024x500. Fondo #0A0A0A con
# resplandor naranja de marca, logo a la izquierda y tagline en Jost (tipografía
# real de la app) a la derecha.
Add-Type -AssemblyName System.Drawing

$root = "D:\dev\1of1\app"
$out = "D:\dev\1of1\docs\play-store\assets"
$W = 1024; $H = 500

# ── Cargar Jost como fuente privada (no requiere instalarla en el sistema) ──
$fonts = New-Object System.Drawing.Text.PrivateFontCollection
$fonts.AddFontFile("$root\assets\fonts\jost\Jost-900-Black.otf")
$fonts.AddFontFile("$root\assets\fonts\jost\Jost-600-Semi.otf")
$familyBlack = $fonts.Families[0]
$familySemi = $fonts.Families[1]

function Get-OpaqueBounds($bitmap) {
    $minX = $bitmap.Width; $minY = $bitmap.Height; $maxX = 0; $maxY = 0
    $step = 2
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
    return New-Object System.Drawing.Rectangle $minX, $minY, ($maxX - $minX), ($maxY - $minY)
}

$bmp = New-Object System.Drawing.Bitmap $W, $H
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic

# Fondo sólido de marca.
$bg = [System.Drawing.ColorTranslator]::FromHtml("#0A0A0A")
$g.Clear($bg)

# Resplandor radial naranja sutil en la esquina superior derecha (profundidad).
$accent = [System.Drawing.ColorTranslator]::FromHtml("#FF6B1A")
$glowPath = New-Object System.Drawing.Drawing2D.GraphicsPath
$glowPath.AddEllipse(($W * 0.55), (-$H * 0.7), ($W * 1.3), ($H * 2.4))
$glowBrush = New-Object System.Drawing.Drawing2D.PathGradientBrush $glowPath
$glowBrush.CenterColor = [System.Drawing.Color]::FromArgb(55, $accent.R, $accent.G, $accent.B)
$glowBrush.SurroundColors = @([System.Drawing.Color]::FromArgb(0, $accent.R, $accent.G, $accent.B))
$g.FillPath($glowBrush, $glowPath)

# Logo recortado a su contenido real, a la izquierda.
$logoFull = New-Object System.Drawing.Bitmap "$root\assets\branding\icon_foreground.png"
$bounds = Get-OpaqueBounds $logoFull
$logo = $logoFull.Clone($bounds, $logoFull.PixelFormat)
$logoTargetH = $H * 0.40
$scale = $logoTargetH / $logo.Height
$logoW = $logo.Width * $scale
$logoH = $logo.Height * $scale
$logoX = $W * 0.05
$logoY = $H * 0.14
$g.DrawImage($logo, $logoX, $logoY, $logoW, $logoH)

# Divisor sutil vertical entre logo y texto.
$linePen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(40, 255, 255, 255)), 2
$lineX = $W * 0.50
$g.DrawLine($linePen, $lineX, $H * 0.18, $lineX, $H * 0.82)

# ── Texto: tagline corto (auto-fit) + subtítulo ──
$textX = $W * 0.545
$textAreaW = $W - $textX - ($W * 0.035)

$brushWhite = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
$brushAccent = New-Object System.Drawing.SolidBrush $accent
$fmt = New-Object System.Drawing.StringFormat
$fmt.Alignment = [System.Drawing.StringAlignment]::Near

# Auto-fit: bajamos el tamaño hasta que ambas líneas entren en textAreaW.
# Tildes por código Unicode explícito (evita mojibake por encoding del .ps1).
$aAcute = [char]0x00E1 # 'á' minúscula (para "básquet")
$line1 = "TU CANCHA," # keyword-first: se lee de un vistazo
$line2 = "TU PARTIDO."
$headlineSize = 56
do {
    $fontHeadline = New-Object System.Drawing.Font $familyBlack, $headlineSize, ([System.Drawing.FontStyle]::Bold)
    $w1 = $g.MeasureString($line1, $fontHeadline).Width
    $w2 = $g.MeasureString($line2, $fontHeadline).Width
    $maxW = [Math]::Max($w1, $w2)
    if ($maxW -le $textAreaW) { break }
    $headlineSize -= 2
} while ($headlineSize -gt 20)

$lineGap = $headlineSize * 1.22
$y1 = $H * 0.24
$g.DrawString($line1, $fontHeadline, $brushWhite, $textX, $y1, $fmt)
$y2 = $y1 + $lineGap
$g.DrawString($line2, $fontHeadline, $brushAccent, $textX, $y2, $fmt)

# Subtítulo, con separación clara respecto del headline.
$fontSub = New-Object System.Drawing.Font $familySemi, 21, ([System.Drawing.FontStyle]::Regular)
$brushGray = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(190, 255, 255, 255))
$sub = "Partidos, ranking y clanes de b${aAcute}squet callejero"
$ySub = $y2 + $lineGap * 1.35
$rectSub = New-Object System.Drawing.RectangleF $textX, $ySub, $textAreaW, ($H * 0.22)
$g.DrawString($sub, $fontSub, $brushGray, $rectSub)

$bmp.Save("$out\feature-graphic-1024x500.png", [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose(); $logo.Dispose(); $logoFull.Dispose()
Write-Output "OK: $out\feature-graphic-1024x500.png (headline size: $headlineSize)"
