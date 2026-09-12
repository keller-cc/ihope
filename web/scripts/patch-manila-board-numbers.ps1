# Erase ALL channel digits; paint exactly one foam-style 1..13 (bottom→top).
Add-Type -AssemblyName System.Drawing

$src = "C:\Users\micro\.cursor\projects\d-IHope\assets\manila-board-fused-semantic-v1.jpg"
$out = "d:\IHope\web\public\games\manila\board\board.jpg"

$srcBmp = [Drawing.Bitmap]::FromFile($src)
$bmp = New-Object Drawing.Bitmap $srcBmp.Width, $srcBmp.Height, ([Drawing.Imaging.PixelFormat]::Format24bppRgb)
$gc = [Drawing.Graphics]::FromImage($bmp)
$gc.DrawImage($srcBmp, 0, 0, $srcBmp.Width, $srcBmp.Height)
$gc.Dispose(); $srcBmp.Dispose()

$W = $bmp.Width; $H = $bmp.Height

# Local water-clone erase (no solid teal bar): for each pixel, copy from channel center ±jitter
function Soft-Erase([Drawing.Bitmap]$b, [int]$x0, [int]$x1, [int]$y0, [int]$y1, [double]$waterX) {
  $rand = New-Object Random 13
  for ($y = $y0; $y -lt $y1; $y++) {
    for ($x = $x0; $x -lt $x1; $x++) {
      $sx = [int]($b.Width * $waterX) + $rand.Next(-10, 11)
      $sy = $y + $rand.Next(-1, 2)
      if ($sx -lt 0) { $sx = 0 }
      if ($sx -ge $b.Width) { $sx = $b.Width - 1 }
      if ($sy -lt 0) { $sy = 0 }
      if ($sy -ge $b.Height) { $sy = $b.Height - 1 }
      # never sample from inside the erase band (avoid copying digits back)
      $bandL = $x0; $bandR = $x1
      if ($sx -ge $bandL -and $sx -lt $bandR) {
        $sx = [int]($b.Width * 0.50) + $rand.Next(-8, 9)
        if ($sx -ge $bandL -and $sx -lt $bandR) { $sx = [int]($b.Width * 0.40) }
      }
      $b.SetPixel($x, $y, $b.GetPixel($sx, $sy))
    }
  }
}

# Wipe AI digits near waves (left of crests) and old right column — full height incl. top ghost
Soft-Erase $bmp ([int]($W*0.40)) ([int]($W*0.57)) ([int]($H*0.06)) ([int]($H*0.88)) 0.50
Soft-Erase $bmp ([int]($W*0.57)) ([int]($W*0.74)) ([int]($H*0.06)) ([int]($H*0.88)) 0.50
# Extra pass on very top where ghost 13 lingered
Soft-Erase $bmp ([int]($W*0.45)) ([int]($W*0.74)) ([int]($H*0.04)) ([int]($H*0.14)) 0.50

function TrackYPct([int]$p) {
  $open = 78.0; $at5 = 54.0; $finish = 20.0
  if ($p -le 5) { return $open + ($p / 5.0) * ($at5 - $open) }
  return $at5 + (($p - 5) / 8.0) * ($finish - $at5)
}

$g = [Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAlias
$fontSize = [Math]::Max(17, [int]($H * 0.0155))
$font = New-Object Drawing.Font "Segoe UI", $fontSize, ([Drawing.FontStyle]::Bold)
$glow = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(110, 120, 180, 210))
$main = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(250, 255, 255, 255))
$sf = New-Object Drawing.StringFormat
$sf.Alignment = [Drawing.StringAlignment]::Center
$sf.LineAlignment = [Drawing.StringAlignment]::Center

$numX = [int]($W * 0.61)
for ($n = 1; $n -le 13; $n++) {
  $y = [int]($H * (TrackYPct $n) / 100.0)
  $t = [string]$n
  foreach ($ox in -1..1) {
    foreach ($oy in -1..1) {
      if ($ox -eq 0 -and $oy -eq 0) { continue }
      $g.DrawString($t, $font, $glow, ($numX + $ox), ($y + $oy), $sf)
    }
  }
  $g.DrawString($t, $font, $main, $numX, $y, $sf)
}

$main.Dispose(); $glow.Dispose(); $font.Dispose(); $sf.Dispose(); $g.Dispose()

$codec = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$ep = New-Object Drawing.Imaging.EncoderParameters(1)
$ep.Param[0] = New-Object Drawing.Imaging.EncoderParameter([Drawing.Imaging.Encoder]::Quality, 92L)
$bmp.Save($out, $codec, $ep)
$bmp.Dispose()
Write-Host "board digits fixed -> $out ($((Get-Item $out).Length))"
