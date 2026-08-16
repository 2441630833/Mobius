# Sync Mobius branding from static/images/logo.png
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$VsCodeDir = Join-Path $Root "vscode"
$LogoSrc = Join-Path $Root "static\images\logo.png"
$HashFile = Join-Path $Root ".cache\logo-hash.txt"

if (-not (Test-Path $LogoSrc)) {
    Write-Host "Missing brand logo: $LogoSrc" -ForegroundColor Yellow
    exit 0
}

$currentHash = (Get-FileHash $LogoSrc -Algorithm SHA256).Hash
$cachedHash = $null
if (Test-Path $HashFile) {
    $cachedHash = (Get-Content $HashFile -Raw).Trim()
}
$win32Dir = Join-Path $VsCodeDir "resources\win32"
$innoBmpNames = @(
    "inno-small-100.bmp", "inno-small-125.bmp", "inno-small-150.bmp", "inno-small-175.bmp",
    "inno-small-200.bmp", "inno-small-225.bmp", "inno-small-250.bmp",
    "inno-big-100.bmp", "inno-big-125.bmp", "inno-big-150.bmp", "inno-big-175.bmp",
    "inno-big-200.bmp", "inno-big-225.bmp", "inno-big-250.bmp"
)
$missingInnoBmps = $innoBmpNames | Where-Object { -not (Test-Path (Join-Path $win32Dir $_)) }
if ($cachedHash -eq $currentHash -and $missingInnoBmps.Count -eq 0) {
    return
}

Add-Type -AssemblyName System.Drawing

function Save-FittedPng {
    param(
        [string]$SourcePath,
        [string]$DestPath,
        [int]$Size
    )

    $src = [System.Drawing.Image]::FromFile($SourcePath)
    try {
        $bmp = New-Object System.Drawing.Bitmap $Size, $Size
        $graphics = [System.Drawing.Graphics]::FromImage($bmp)
        try {
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
            $graphics.Clear([System.Drawing.Color]::Transparent)

            $ratio = [Math]::Min($Size / $src.Width, $Size / $src.Height)
            $width = [int][Math]::Round($src.Width * $ratio)
            $height = [int][Math]::Round($src.Height * $ratio)
            $x = [int][Math]::Round(($Size - $width) / 2)
            $y = [int][Math]::Round(($Size - $height) / 2)
            $graphics.DrawImage($src, $x, $y, $width, $height)
        } finally {
            $graphics.Dispose()
        }

        $dir = Split-Path -Parent $DestPath
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
        $bmp.Save($DestPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
    } finally {
        $src.Dispose()
    }
}

function Save-FittedBmp {
    param(
        [string]$SourcePath,
        [string]$DestPath,
        [int]$Width,
        [int]$Height,
        [double]$FillRatio = 1.0
    )

    $src = [System.Drawing.Image]::FromFile($SourcePath)
    try {
        # Prefer 32-bpp PNG so Inno Setup can honor alpha (true transparency).
        # Fall back path also writes .bmp without alpha if extension is .bmp.
        $usePng = [IO.Path]::GetExtension($DestPath).Equals(".png", [StringComparison]::OrdinalIgnoreCase)
        $pixelFormat = if ($usePng) {
            [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
        } else {
            [System.Drawing.Imaging.PixelFormat]::Format24bppRgb
        }
        $bmp = New-Object System.Drawing.Bitmap $Width, $Height, $pixelFormat
        $graphics = [System.Drawing.Graphics]::FromImage($bmp)
        try {
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
            $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
            if ($usePng) {
                $graphics.Clear([System.Drawing.Color]::Transparent)
            } else {
                # 24-bit BMP has no alpha; white matches the wizard chrome.
                $graphics.Clear([System.Drawing.Color]::White)
            }

            $maxW = [Math]::Max(1, [int][Math]::Round($Width * $FillRatio))
            $maxH = [Math]::Max(1, [int][Math]::Round($Height * $FillRatio))
            $ratio = [Math]::Min($maxW / $src.Width, $maxH / $src.Height)
            $drawW = [int][Math]::Round($src.Width * $ratio)
            $drawH = [int][Math]::Round($src.Height * $ratio)
            $x = [int][Math]::Round(($Width - $drawW) / 2)
            $y = [int][Math]::Round(($Height - $drawH) / 2)
            $graphics.DrawImage($src, $x, $y, $drawW, $drawH)
        } finally {
            $graphics.Dispose()
        }

        $dir = Split-Path -Parent $DestPath
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
        if ($usePng) {
            $bmp.Save($DestPath, [System.Drawing.Imaging.ImageFormat]::Png)
        } else {
            $bmp.Save($DestPath, [System.Drawing.Imaging.ImageFormat]::Bmp)
        }
        $bmp.Dispose()
    } finally {
        $src.Dispose()
    }
}

function Export-IcoFramesToPng {
    param(
        [string]$IcoPath,
        [string]$TempDir,
        [string]$Prefix
    )

    $bytes = [System.IO.File]::ReadAllBytes($IcoPath)
    $count = [BitConverter]::ToUInt16($bytes, 4)
    $paths = New-Object System.Collections.Generic.List[string]

    for ($i = 0; $i -lt $count; $i++) {
        $entryOff = 6 + (16 * $i)
        $width = $bytes[$entryOff]
        $height = $bytes[$entryOff + 1]
        if ($width -eq 0) { $width = 256 }
        if ($height -eq 0) { $height = 256 }

        $pngPath = Join-Path $TempDir "$Prefix-$width.png"
        $icon = New-Object System.Drawing.Icon($IcoPath, $width, $height)
        try {
            $bitmap = $icon.ToBitmap()
            try {
                $bitmap.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)
            } finally {
                $bitmap.Dispose()
            }
        } finally {
            $icon.Dispose()
        }
        $paths.Add($pngPath)
    }

    return $paths
}

function Get-DocumentPaperColor {
    param([System.Drawing.Bitmap]$Bitmap)

    $width = $Bitmap.Width
    $height = $Bitmap.Height
    $samplePoints = @(
        @([Math]::Max(0, [int]($width * 0.20)), [Math]::Max(0, [int]($height * 0.62))),
        @([Math]::Max(0, [int]($width * 0.28)), [Math]::Max(0, [int]($height * 0.72))),
        @([Math]::Max(0, [int]($width * 0.15)), [Math]::Max(0, [int]($height * 0.55)))
    )

    $bestColor = $Bitmap.GetPixel($samplePoints[0][0], $samplePoints[0][1])
    $bestLuminance = -1
    foreach ($point in $samplePoints) {
        $color = $Bitmap.GetPixel($point[0], $point[1])
        $luminance = ($color.R * 0.299) + ($color.G * 0.587) + ($color.B * 0.114)
        if ($luminance -gt $bestLuminance) {
            $bestLuminance = $luminance
            $bestColor = $color
        }
    }
    return $bestColor
}

function Clear-CornerBadgeArea {
    param([System.Drawing.Bitmap]$Bitmap)

    $width = $Bitmap.Width
    $height = $Bitmap.Height
    $minSide = [Math]::Min($width, $height)
    # Match the original VS Code badge inset -- document art does not fill the canvas edge.
    $clearSize = [int][Math]::Round($minSide * 0.32)
    $marginRight = [int][Math]::Round($minSide * 0.09)
    $marginBottom = [int][Math]::Round($minSide * 0.05)
    $shiftLeft = [int][Math]::Round($minSide * 0.06)
    $shiftDown = [int][Math]::Round($minSide * 0.02)
    $clearX = $width - $clearSize - $marginRight - $shiftLeft
    $clearY = [Math]::Min($height - $clearSize, $height - $clearSize - $marginBottom + $shiftDown)

    $sampleX = [Math]::Max(0, $clearX - [int]($minSide * 0.05))
    $sampleY = [Math]::Min($height - 1, $clearY + [int]($clearSize / 2))
    $leftColor = $Bitmap.GetPixel($sampleX, $sampleY)

    $sampleX2 = [Math]::Min($width - 1, $clearX + [int]($clearSize / 2))
    $sampleY2 = [Math]::Max(0, $clearY - [int]($minSide * 0.03))
    $topColor = $Bitmap.GetPixel($sampleX2, $sampleY2)

    $paperColor = Get-DocumentPaperColor -Bitmap $Bitmap
    $fillColor = [System.Drawing.Color]::FromArgb(
        [int][Math]::Round(($leftColor.R + $topColor.R + $paperColor.R) / 3),
        [int][Math]::Round(($leftColor.G + $topColor.G + $paperColor.G) / 3),
        [int][Math]::Round(($leftColor.B + $topColor.B + $paperColor.B) / 3)
    )

    $graphics = [System.Drawing.Graphics]::FromImage($Bitmap)
    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $brush = New-Object System.Drawing.SolidBrush $fillColor
        try {
            $graphics.FillEllipse($brush, $clearX, $clearY, $clearSize, $clearSize)
        } finally {
            $brush.Dispose()
        }
    } finally {
        $graphics.Dispose()
    }

    return @{
        X = $clearX
        Y = $clearY
        Size = $clearSize
    }
}

function Add-CornerBadgeToBitmap {
    param(
        [System.Drawing.Bitmap]$Bitmap,
        [System.Drawing.Image]$Logo
    )

    $badgeArea = Clear-CornerBadgeArea -Bitmap $Bitmap
    $badge = [int][Math]::Round($badgeArea.Size * 0.82)
    $x = $badgeArea.X + [int][Math]::Round(($badgeArea.Size - $badge) / 2)
    $y = $badgeArea.Y + [int][Math]::Round(($badgeArea.Size - $badge) / 2)

    $graphics = [System.Drawing.Graphics]::FromImage($Bitmap)
    try {
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality

        $ratio = [Math]::Min($badge / $Logo.Width, $badge / $Logo.Height)
        $logoWidth = [int][Math]::Round($Logo.Width * $ratio)
        $logoHeight = [int][Math]::Round($Logo.Height * $ratio)
        $logoX = $x + [int][Math]::Round(($badge - $logoWidth) / 2)
        $logoY = $y + [int][Math]::Round(($badge - $logoHeight) / 2)
        $graphics.DrawImage($Logo, $logoX, $logoY, $logoWidth, $logoHeight)
    } finally {
        $graphics.Dispose()
    }
}

function Update-IcoCornerBadge {
    param(
        [string]$SourceIco,
        [string]$DestIco,
        [string]$LogoPath,
        [string]$WorkDir
    )

    $prefix = [IO.Path]::GetFileNameWithoutExtension($DestIco)
    $framePaths = Export-IcoFramesToPng -IcoPath $SourceIco -TempDir $WorkDir -Prefix $prefix
    $logo = [System.Drawing.Image]::FromFile($LogoPath)
    $processed = New-Object System.Collections.Generic.List[string]
    try {
        foreach ($framePath in $framePaths) {
            $frame = [System.Drawing.Bitmap]::FromFile($framePath)
            try {
                $composited = New-Object System.Drawing.Bitmap $frame.Width, $frame.Height
                $copyGraphics = [System.Drawing.Graphics]::FromImage($composited)
                try {
                    $copyGraphics.DrawImage($frame, 0, 0, $frame.Width, $frame.Height)
                } finally {
                    $copyGraphics.Dispose()
                }
                Add-CornerBadgeToBitmap -Bitmap $composited -Logo $logo
                $outPath = "$framePath.badge.png"
                $composited.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
                $composited.Dispose()
                $processed.Add($outPath)
            } finally {
                $frame.Dispose()
            }
        }
        Save-PngAsIco -PngPaths $processed.ToArray() -OutputPath $DestIco
    } finally {
        $logo.Dispose()
    }
}

function Save-PngAsIco {
    param(
        [string[]]$PngPaths,
        [string]$OutputPath
    )

    $entries = New-Object System.Collections.Generic.List[object]
    $dataOffset = 6 + (16 * $PngPaths.Count)

    foreach ($pngPath in $PngPaths) {
        $pngBytes = [System.IO.File]::ReadAllBytes($pngPath)
        $image = [System.Drawing.Image]::FromFile($pngPath)
        try {
            $width = if ($image.Width -ge 256) { 0 } else { [byte]$image.Width }
            $height = if ($image.Height -ge 256) { 0 } else { [byte]$image.Height }
            $entries.Add([PSCustomObject]@{
                Width = $width
                Height = $height
                Bytes = $pngBytes
                Offset = $dataOffset
            })
            $dataOffset += $pngBytes.Length
        } finally {
            $image.Dispose()
        }
    }

    $stream = New-Object System.IO.MemoryStream
    $writer = New-Object System.IO.BinaryWriter($stream)
    try {
        $writer.Write([UInt16]0)
        $writer.Write([UInt16]1)
        $writer.Write([UInt16]$entries.Count)

        foreach ($entry in $entries) {
            $writer.Write([byte]$entry.Width)
            $writer.Write([byte]$entry.Height)
            $writer.Write([byte]0)
            $writer.Write([byte]0)
            $writer.Write([UInt16]1)
            $writer.Write([UInt16]32)
            $writer.Write([UInt32]$entry.Bytes.Length)
            $writer.Write([UInt32]$entry.Offset)
        }

        foreach ($entry in $entries) {
            $writer.Write($entry.Bytes)
        }

        [System.IO.File]::WriteAllBytes($OutputPath, $stream.ToArray())
    } finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

Write-Host "Syncing brand assets from static/images/logo.png..." -ForegroundColor Cyan

$targets = @(
    @{ Path = Join-Path $VsCodeDir "src\vs\workbench\browser\media\logo.png"; Size = 0 }
    @{ Path = Join-Path $VsCodeDir "resources\win32\code_150x150.png"; Size = 150 }
    @{ Path = Join-Path $VsCodeDir "resources\win32\code_70x70.png"; Size = 70 }
    @{ Path = Join-Path $VsCodeDir "resources\linux\code.png"; Size = 512 }
    @{ Path = Join-Path $VsCodeDir "resources\server\code-512.png"; Size = 512 }
    @{ Path = Join-Path $VsCodeDir "resources\server\code-192.png"; Size = 192 }
)

Copy-Item -Force $LogoSrc $targets[0].Path
for ($i = 1; $i -lt $targets.Count; $i++) {
    Save-FittedPng -SourcePath $LogoSrc -DestPath $targets[$i].Path -Size $targets[$i].Size
}

# Inno Setup wizard images (header small logo + welcome/finish sidebar).
# Use 24-bit BMP -- most compatible with Inno Setup at runtime (PNG alpha can fail with "Bitmap image is not valid").
$innoSmall = @(
    @{ Name = "inno-small-100.bmp"; W = 55; H = 55 }
    @{ Name = "inno-small-125.bmp"; W = 64; H = 68 }
    @{ Name = "inno-small-150.bmp"; W = 83; H = 80 }
    @{ Name = "inno-small-175.bmp"; W = 92; H = 97 }
    @{ Name = "inno-small-200.bmp"; W = 110; H = 106 }
    @{ Name = "inno-small-225.bmp"; W = 119; H = 123 }
    @{ Name = "inno-small-250.bmp"; W = 138; H = 140 }
)
$innoBig = @(
    @{ Name = "inno-big-100.bmp"; W = 164; H = 314 }
    @{ Name = "inno-big-125.bmp"; W = 192; H = 386 }
    @{ Name = "inno-big-150.bmp"; W = 246; H = 459 }
    @{ Name = "inno-big-175.bmp"; W = 273; H = 556 }
    @{ Name = "inno-big-200.bmp"; W = 328; H = 604 }
    @{ Name = "inno-big-225.bmp"; W = 355; H = 700 }
    @{ Name = "inno-big-250.bmp"; W = 410; H = 797 }
)
Write-Host "Updating Inno Setup wizard images (24-bit BMP)..." -ForegroundColor Cyan
foreach ($item in $innoSmall) {
    Save-FittedBmp -SourcePath $LogoSrc -DestPath (Join-Path $win32Dir $item.Name) -Width $item.W -Height $item.H
}
foreach ($item in $innoBig) {
    # Tall sidebar: keep logo centered with comfortable margin
    Save-FittedBmp -SourcePath $LogoSrc -DestPath (Join-Path $win32Dir $item.Name) -Width $item.W -Height $item.H -FillRatio 0.72
}
Write-Host "  inno-small/big BMPs: $($innoSmall.Count + $innoBig.Count)" -ForegroundColor DarkGray
# Remove legacy PNG wizard images so packaging cannot pick up stale assets
Get-ChildItem -Path $win32Dir -Filter "inno-*.png" -File -ErrorAction SilentlyContinue | Remove-Item -Force

$tempDir = Join-Path $env:TEMP "mobius-icons"
if (Test-Path $tempDir) {
    Remove-Item -Recurse -Force $tempDir
}
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

$icoSizes = @(16, 24, 32, 48, 64, 128, 256)
$icoInputs = @()
foreach ($size in $icoSizes) {
    $pngPath = Join-Path $tempDir "logo-$size.png"
    Save-FittedPng -SourcePath $LogoSrc -DestPath $pngPath -Size $size
    $icoInputs += $pngPath
}

$icoDest = Join-Path $VsCodeDir "resources\win32\code.ico"
Save-PngAsIco -PngPaths $icoInputs -OutputPath $icoDest

$faviconInputs = @(16, 32, 48) | ForEach-Object { Join-Path $tempDir "logo-$_.png" }
$faviconDest = Join-Path $VsCodeDir "resources\server\favicon.ico"
Save-PngAsIco -PngPaths $faviconInputs -OutputPath $faviconDest

$originalsDir = Join-Path $Root "scripts\brand-assets\originals\win32"
if (-not (Test-Path $originalsDir)) {
    New-Item -ItemType Directory -Force -Path $originalsDir | Out-Null
    Copy-Item -Force (Join-Path $VsCodeDir "resources\win32\*.ico") $originalsDir
}

$fileTypeWorkDir = Join-Path $tempDir "file-types"
New-Item -ItemType Directory -Force -Path $fileTypeWorkDir | Out-Null
Write-Host "Updating file-type corner badges (keeping document icons)..." -ForegroundColor Cyan
$fileTypeCount = 0
Get-ChildItem -Path $originalsDir -Filter "*.ico" -File | ForEach-Object {
    if ($_.Name -eq "code.ico") {
        return
    }
    $dest = Join-Path $VsCodeDir "resources\win32\$($_.Name)"
    Update-IcoCornerBadge -SourceIco $_.FullName -DestIco $dest -LogoPath $LogoSrc -WorkDir $fileTypeWorkDir
    $fileTypeCount++
}
Write-Host "  win32 file-type icons: $fileTypeCount" -ForegroundColor DarkGray

$outLogo = Join-Path $VsCodeDir "out\vs\workbench\browser\media\logo.png"
if (Test-Path (Split-Path -Parent $outLogo)) {
    Copy-Item -Force $LogoSrc $outLogo
}

Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue

$cacheDir = Split-Path -Parent $HashFile
if (-not (Test-Path $cacheDir)) {
    New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
}
Set-Content -Path $HashFile -Value $currentHash -NoNewline

$electronDir = Join-Path $VsCodeDir ".build\electron"
$productExe = Join-Path $electronDir "Mobius.exe"
$codeIco = Join-Path $VsCodeDir "resources\win32\code.ico"
if ((Test-Path $productExe) -and (Test-Path $codeIco)) {
    # Patch icon in place -- do NOT delete .build/electron (forces a GitHub
    # re-download that often times out).
    Write-Host "Updating Electron exe icon in place..." -ForegroundColor Yellow
    Push-Location $VsCodeDir
    try {
        node -e "require('rcedit')(process.argv[1], { icon: process.argv[2] }, err => { if (err) { console.error(err); process.exit(1) } })" $productExe $codeIco
        Write-Host "  icon updated: Mobius.exe" -ForegroundColor DarkGray
    } catch {
        Write-Host "[WARN] Could not update Electron icon: $_" -ForegroundColor Yellow
    } finally {
        Pop-Location
    }
} elseif (Test-Path $electronDir) {
    Write-Host "Electron tree present but Mobius.exe missing; leave cache for ensure-electron.ps1" -ForegroundColor DarkGray
}

Write-Host "Brand assets synced." -ForegroundColor Green
