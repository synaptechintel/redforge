# RedForge - Ensure Windows build icons exist
# Generates minimal valid placeholder PNG/ICO icons so Tauri can complete Windows builds.
# Replace these files later with branded production icons.

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$IconDir = Join-Path $Root 'src-tauri\icons'
New-Item -ItemType Directory -Force -Path $IconDir | Out-Null

Add-Type -AssemblyName System.Drawing

function New-RedForgePngIcon {
    param(
        [int]$Size,
        [string]$Path
    )

    if (Test-Path $Path) { return }

    $bitmap = New-Object System.Drawing.Bitmap $Size, $Size
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

    $bg = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(24, 24, 27))
    $red = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(220, 38, 38))
    $white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(245, 245, 245))

    $graphics.FillRectangle($bg, 0, 0, $Size, $Size)
    $pad = [Math]::Max(2, [int]($Size * 0.14))
    $graphics.FillEllipse($red, $pad, $pad, $Size - ($pad * 2), $Size - ($pad * 2))

    $fontSize = [Math]::Max(8, [int]($Size * 0.42))
    $font = New-Object System.Drawing.Font('Arial', $fontSize, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $format = New-Object System.Drawing.StringFormat
    $format.Alignment = [System.Drawing.StringAlignment]::Center
    $format.LineAlignment = [System.Drawing.StringAlignment]::Center
    $rect = New-Object System.Drawing.RectangleF(0, 0, $Size, $Size)
    $graphics.DrawString('R', $font, $white, $rect, $format)

    $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)

    $graphics.Dispose()
    $bitmap.Dispose()
}

function New-RedForgeIcoIcon {
    param([string]$Path)
    if (Test-Path $Path) { return }

    $bitmap = New-Object System.Drawing.Bitmap 256, 256
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([System.Drawing.Color]::FromArgb(24, 24, 27))
    $red = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(220, 38, 38))
    $white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(245, 245, 245))
    $graphics.FillEllipse($red, 32, 32, 192, 192)
    $font = New-Object System.Drawing.Font('Arial', 118, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $format = New-Object System.Drawing.StringFormat
    $format.Alignment = [System.Drawing.StringAlignment]::Center
    $format.LineAlignment = [System.Drawing.StringAlignment]::Center
    $rect = New-Object System.Drawing.RectangleF(0, 0, 256, 256)
    $graphics.DrawString('R', $font, $white, $rect, $format)

    $iconHandle = $bitmap.GetHicon()
    $icon = [System.Drawing.Icon]::FromHandle($iconHandle)
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Create)
    $icon.Save($stream)
    $stream.Close()

    $graphics.Dispose()
    $bitmap.Dispose()
    $icon.Dispose()
}

New-RedForgePngIcon -Size 32 -Path (Join-Path $IconDir '32x32.png')
New-RedForgePngIcon -Size 128 -Path (Join-Path $IconDir '128x128.png')
New-RedForgePngIcon -Size 256 -Path (Join-Path $IconDir '128x128@2x.png')
New-RedForgeIcoIcon -Path (Join-Path $IconDir 'icon.ico')

# The Windows build only uses .ico/.png. Keep an icon.icns placeholder path present so config validation does not fail.
$icnsPath = Join-Path $IconDir 'icon.icns'
if (-not (Test-Path $icnsPath)) {
    Copy-Item (Join-Path $IconDir '128x128.png') $icnsPath -Force
}

Write-Host "RedForge icons ready in $IconDir" -ForegroundColor Green
