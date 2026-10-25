# Draws the application icon (launcher/icon.ico, used by gow-launcher.exe and the installer): a white omega on a crimson
# rounded square with a darker diagonal blade, the same drawing as the launcher's runtime icon (launcher/src/main.cpp).
# The .ico is committed; run this again only to change the design:
#   powershell -ExecutionPolicy Bypass -File tools\make_icon.ps1
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$out = Join-Path $PSScriptRoot '..\launcher\icon.ico'

function Draw-Icon([int]$side) {
    $bmp = New-Object System.Drawing.Bitmap $side, $side, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAlias'; $g.Clear([System.Drawing.Color]::Transparent)
    $s = $side / 256.0
    $m = 8 * $s; $w = 240 * $s; $r = 52 * $s
    $box = New-Object System.Drawing.Drawing2D.GraphicsPath
    $box.AddArc($m, $m, 2 * $r, 2 * $r, 180, 90); $box.AddArc($m + $w - 2 * $r, $m, 2 * $r, 2 * $r, 270, 90)
    $box.AddArc($m + $w - 2 * $r, $m + $w - 2 * $r, 2 * $r, 2 * $r, 0, 90); $box.AddArc($m, $m + $w - 2 * $r, 2 * $r, 2 * $r, 90, 90)
    $box.CloseFigure()
    $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.PointF 0, $m),
        (New-Object System.Drawing.PointF 0, ($m + $w)), ([System.Drawing.Color]::FromArgb(224, 53, 42)), ([System.Drawing.Color]::FromArgb(122, 22, 16))
    $g.FillPath($grad, $box)
    $g.SetClip($box)
    $blade = [System.Drawing.PointF[]]@((New-Object System.Drawing.PointF (150 * $s), $m), (New-Object System.Drawing.PointF (205 * $s), $m),
        (New-Object System.Drawing.PointF (110 * $s), ($m + $w)), (New-Object System.Drawing.PointF (55 * $s), ($m + $w)))
    $g.FillPolygon((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(55, 0, 0, 0))), $blade)
    $g.ResetClip()
    $omega = New-Object System.Drawing.Drawing2D.GraphicsPath
    $family = New-Object System.Drawing.FontFamily 'Segoe UI Black'
    $omega.AddString([string][char]0x03A9, $family, 0, [single](170 * $s), (New-Object System.Drawing.PointF 0, 0), [System.Drawing.StringFormat]::GenericTypographic)
    $b = $omega.GetBounds()
    $t = New-Object System.Drawing.Drawing2D.Matrix
    $t.Translate([single](128 * $s - ($b.X + $b.Width / 2)), [single](130 * $s - ($b.Y + $b.Height / 2)))
    $omega.Transform($t)
    if ($side -ge 48) {
        $shadow = $omega.Clone(); $st = New-Object System.Drawing.Drawing2D.Matrix; $st.Translate(0, [single](5 * $s)); $shadow.Transform($st)
        $g.FillPath((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(90, 0, 0, 0))), $shadow)
    }
    $g.FillPath([System.Drawing.Brushes]::White, $omega)
    $g.Dispose()
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    return , $ms.ToArray()
}

# .ico with PNG images (Windows Vista and later read PNG entries at every size)
$sizes = 16, 24, 32, 48, 64, 128, 256
$images = foreach ($z in $sizes) { , (Draw-Icon $z) }
$fs = [System.IO.File]::Create((Resolve-Path (Split-Path $out)).Path + '\icon.ico')
$bw = New-Object System.IO.BinaryWriter $fs
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $z = $sizes[$i]; $len = $images[$i].Length
    $bw.Write([byte]($z % 256)); $bw.Write([byte]($z % 256)); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32); $bw.Write([uint32]$len); $bw.Write([uint32]$offset)
    $offset += $len
}
foreach ($img in $images) { $bw.Write($img) }
$bw.Close()
Write-Host "OK: $out"
