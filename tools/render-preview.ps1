Add-Type -AssemblyName System.Drawing

$OutputDir = Join-Path (Get-Location) "screenshots"
if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

$Background = [System.Drawing.Color]::FromArgb(45, 45, 48)
$White = [System.Drawing.Color]::White
$BlackBorder = [System.Drawing.Color]::FromArgb(190, 0, 0, 0)
$MatchGreen = [System.Drawing.Color]::FromArgb(52, 143, 80)
$MismatchRed = [System.Drawing.Color]::FromArgb(181, 61, 55)
$ResponseBar = [System.Drawing.Color]::FromArgb(210, 33, 33, 36)

$Palette = @(
    [System.Drawing.Color]::FromArgb(244, 67, 54),
    [System.Drawing.Color]::FromArgb(33, 150, 243),
    [System.Drawing.Color]::FromArgb(76, 175, 80),
    [System.Drawing.Color]::FromArgb(255, 235, 59),
    [System.Drawing.Color]::FromArgb(156, 39, 176),
    [System.Drawing.Color]::FromArgb(255, 0, 255),
    [System.Drawing.Color]::FromArgb(255, 152, 0),
    [System.Drawing.Color]::FromArgb(0, 188, 212),
    [System.Drawing.Color]::White
)

$Slots = @(
    @{ X = -0.82; Y = -0.58 },
    @{ X = 0.0; Y = -0.72 },
    @{ X = 0.82; Y = -0.58 },
    @{ X = -0.82; Y = 0.0 },
    @{ X = 0.82; Y = 0.0 },
    @{ X = -0.82; Y = 0.58 },
    @{ X = 0.0; Y = 0.72 },
    @{ X = 0.82; Y = 0.58 }
)

function New-Geometry {
    param([float]$Width, [float]$Height)

    $fixationX = $Width * 0.5
    $fixationY = $Height * 0.5
    $sideMargin = $Width * 0.045
    $centralGap = $Width * 0.105
    $verticalTop = $Height * 0.20
    $verticalBottom = $Height * 0.74
    $squareSide = [Math]::Min($Width * 0.068, $Height * 0.058)

    $leftHemifield = [System.Drawing.RectangleF]::FromLTRB($sideMargin, $verticalTop, $fixationX - $centralGap, $verticalBottom)
    $rightHemifield = [System.Drawing.RectangleF]::FromLTRB($fixationX + $centralGap, $verticalTop, $Width - $sideMargin, $verticalBottom)

    [pscustomobject]@{
        Width = $Width
        Height = $Height
        FixationX = $fixationX
        FixationY = $fixationY
        SquareSide = $squareSide
        LeftField = Get-CenteredBox -Bounds $leftHemifield -WidthScale 0.96 -HeightScale 0.72
        RightField = Get-CenteredBox -Bounds $rightHemifield -WidthScale 0.96 -HeightScale 0.72
    }
}

function Get-CenteredBox {
    param(
        [System.Drawing.RectangleF]$Bounds,
        [float]$WidthScale,
        [float]$HeightScale
    )

    $boxWidth = $Bounds.Width * $WidthScale
    $boxHeight = $Bounds.Height * $HeightScale
    $left = $Bounds.X + ($Bounds.Width * 0.5) - ($boxWidth * 0.5)
    $top = $Bounds.Y + ($Bounds.Height * 0.5) - ($boxHeight * 0.5)
    [System.Drawing.RectangleF]::new($left, $top, $boxWidth, $boxHeight)
}

function Draw-CenteredText {
    param(
        [System.Drawing.Graphics]$Graphics,
        [string]$Text,
        [float]$X,
        [float]$Y,
        [float]$Size,
        [System.Drawing.Color]$Color
    )

    $font = New-Object System.Drawing.Font("Arial", $Size, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $brush = New-Object System.Drawing.SolidBrush($Color)
    $format = New-Object System.Drawing.StringFormat
    $format.Alignment = [System.Drawing.StringAlignment]::Center
    $format.LineAlignment = [System.Drawing.StringAlignment]::Center
    $rect = [System.Drawing.RectangleF]::new($X - 400, $Y - 200, 800, 400)
    $Graphics.DrawString($Text, $font, $brush, $rect, $format)
    $format.Dispose()
    $brush.Dispose()
    $font.Dispose()
}

function Get-StimulusRect {
    param(
        [pscustomobject]$Geometry,
        [string]$Hemifield,
        [float]$SlotX,
        [float]$SlotY
    )

    $field = if ($Hemifield -eq "left") { $Geometry.LeftField } else { $Geometry.RightField }
    $horizontalRadius = [Math]::Max(($field.Width - $Geometry.SquareSide) * 0.5, 0)
    $verticalRadius = [Math]::Max(($field.Height - $Geometry.SquareSide) * 0.42, 0)
    $halfSide = $Geometry.SquareSide * 0.5

    $centerX = $field.X + ($field.Width * 0.5) + ($SlotX * $horizontalRadius)
    $centerY = $field.Y + ($field.Height * 0.5) + ($SlotY * $verticalRadius)
    $left = [Math]::Min([Math]::Max($centerX - $halfSide, $field.Left), $field.Right - $Geometry.SquareSide)
    $top = [Math]::Min([Math]::Max($centerY - $halfSide, $field.Top), $field.Bottom - $Geometry.SquareSide)

    [System.Drawing.RectangleF]::new($left, $top, $Geometry.SquareSide, $Geometry.SquareSide)
}

function Draw-Stimuli {
    param(
        [System.Drawing.Graphics]$Graphics,
        [pscustomobject]$Geometry,
        [string[]]$Hemifields,
        [int]$SetSize,
        [bool]$Mismatch
    )

    $borderPen = New-Object System.Drawing.Pen($BlackBorder, [Math]::Max($Geometry.SquareSide * 0.045, 1))
    foreach ($hemifield in $Hemifields) {
        for ($i = 0; $i -lt $SetSize; $i++) {
            $color = $Palette[$i]
            if ($Mismatch -and $hemifield -eq "right" -and $i -eq 2) {
                $color = $Palette[7]
            }
            $brush = New-Object System.Drawing.SolidBrush($color)
            $slot = $Slots[$i]
            $rect = Get-StimulusRect -Geometry $Geometry -Hemifield $hemifield -SlotX $slot.X -SlotY $slot.Y
            $Graphics.FillRectangle($brush, $rect)
            $Graphics.DrawRectangle($borderPen, $rect.X, $rect.Y, $rect.Width, $rect.Height)
            $brush.Dispose()
        }
    }
    $borderPen.Dispose()
}

function Draw-ResponseButtons {
    param(
        [System.Drawing.Graphics]$Graphics,
        [int]$Width,
        [int]$Height
    )

    $barHeight = [Math]::Max([int]($Height * 0.094), 76)
    $barY = $Height - $barHeight
    $barBrush = New-Object System.Drawing.SolidBrush($ResponseBar)
    $Graphics.FillRectangle($barBrush, 0, $barY, $Width, $barHeight)
    $barBrush.Dispose()

    $buttonMargin = [int]($Width * 0.058)
    $gap = [int]($Width * 0.04)
    $buttonWidth = [int](($Width - ($buttonMargin * 2) - $gap) / 2)
    $buttonHeight = [int]($barHeight * 0.66)
    $buttonY = $barY + [int](($barHeight - $buttonHeight) / 2)
    $matchRect = [System.Drawing.Rectangle]::new($buttonMargin, $buttonY, $buttonWidth, $buttonHeight)
    $mismatchRect = [System.Drawing.Rectangle]::new($buttonMargin + $buttonWidth + $gap, $buttonY, $buttonWidth, $buttonHeight)

    $matchBrush = New-Object System.Drawing.SolidBrush($MatchGreen)
    $mismatchBrush = New-Object System.Drawing.SolidBrush($MismatchRed)
    $Graphics.FillRectangle($matchBrush, $matchRect)
    $Graphics.FillRectangle($mismatchBrush, $mismatchRect)
    $matchBrush.Dispose()
    $mismatchBrush.Dispose()

    Draw-CenteredText -Graphics $Graphics -Text "Match" -X ($matchRect.X + $matchRect.Width / 2) -Y ($matchRect.Y + $matchRect.Height / 2) -Size ([Math]::Max($Width * 0.044, 16)) -Color $White
    Draw-CenteredText -Graphics $Graphics -Text "Mismatch" -X ($mismatchRect.X + $mismatchRect.Width / 2) -Y ($mismatchRect.Y + $mismatchRect.Height / 2) -Size ([Math]::Max($Width * 0.044, 16)) -Color $White
}

function Render-Preview {
    param(
        [string]$Name,
        [int]$Width,
        [int]$Height,
        [string]$Phase,
        [int]$SetSize,
        [bool]$Mismatch = $false
    )

    $bitmap = New-Object System.Drawing.Bitmap($Width, $Height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $graphics.Clear($Background)

    $geometry = New-Geometry -Width $Width -Height $Height
    $fixationSize = [Math]::Min($Width, $Height) * 0.055
    $cueSize = [Math]::Min($Width, $Height) * 0.08

    switch ($Phase) {
        "fixation" {
            Draw-CenteredText -Graphics $graphics -Text "+" -X $geometry.FixationX -Y $geometry.FixationY -Size $fixationSize -Color $White
        }
        "cue-right" {
            Draw-CenteredText -Graphics $graphics -Text ">" -X $geometry.FixationX -Y $geometry.FixationY -Size $cueSize -Color $White
        }
        "encoding" {
            Draw-CenteredText -Graphics $graphics -Text "+" -X $geometry.FixationX -Y $geometry.FixationY -Size $fixationSize -Color $White
            Draw-Stimuli -Graphics $graphics -Geometry $geometry -Hemifields @("left", "right") -SetSize $SetSize -Mismatch $false
        }
        "maintenance" {
            Draw-CenteredText -Graphics $graphics -Text "+" -X $geometry.FixationX -Y $geometry.FixationY -Size $fixationSize -Color $White
        }
        "retrieval" {
            Draw-CenteredText -Graphics $graphics -Text "+" -X $geometry.FixationX -Y $geometry.FixationY -Size $fixationSize -Color $White
            Draw-Stimuli -Graphics $graphics -Geometry $geometry -Hemifields @("left", "right") -SetSize $SetSize -Mismatch $Mismatch
            Draw-ResponseButtons -Graphics $graphics -Width $Width -Height $Height
        }
    }

    $path = Join-Path $OutputDir $Name
    $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bitmap.Dispose()
    Write-Output $path
}

Render-Preview -Name "01-phone-fixation.png" -Width 411 -Height 915 -Phase "fixation" -SetSize 6
Render-Preview -Name "02-phone-cue-right.png" -Width 411 -Height 915 -Phase "cue-right" -SetSize 6
Render-Preview -Name "03-phone-encoding-set6.png" -Width 411 -Height 915 -Phase "encoding" -SetSize 6
Render-Preview -Name "04-phone-maintenance.png" -Width 411 -Height 915 -Phase "maintenance" -SetSize 6
Render-Preview -Name "05-phone-retrieval-mismatch-set6.png" -Width 411 -Height 915 -Phase "retrieval" -SetSize 6 -Mismatch $true
Render-Preview -Name "06-landscape-encoding-set8.png" -Width 1280 -Height 800 -Phase "encoding" -SetSize 8
Render-Preview -Name "07-tablet-retrieval-match-set8.png" -Width 800 -Height 1280 -Phase "retrieval" -SetSize 8
