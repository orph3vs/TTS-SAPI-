Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-TextFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    }

    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
    }

    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        return [System.Text.Encoding]::BigEndianUnicode.GetString($bytes, 2, $bytes.Length - 2)
    }

    $utf8Text = [System.Text.Encoding]::UTF8.GetString($bytes)
    if ($utf8Text.Contains([char]0xFFFD)) {
        return [System.Text.Encoding]::Default.GetString($bytes)
    }

    return $utf8Text
}

function New-Text {
    param(
        [Parameter(Mandatory = $true)]
        [int[]]$CodePoints
    )

    return (-join ($CodePoints | ForEach-Object { [char]$_ }))
}

function Get-PreferredVoice {
    $probeVoice = New-Object -ComObject SAPI.SpVoice
    try {
        $voices = @($probeVoice.GetVoices())
        $koreanVoice = $voices | Where-Object { $_.GetDescription() -match "Korean|Heami|ko-KR" } | Select-Object -First 1
        if ($null -ne $koreanVoice) {
            return $koreanVoice
        }

        return $voices | Select-Object -First 1
    }
    finally {
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($probeVoice)
    }
}

function Convert-IntegerToKoreanReading {
    param(
        [Parameter(Mandatory = $true)]
        [int]$Number
    )

    $digits = @(
        "",
        (New-Text @(0xC77C)),
        (New-Text @(0xC774)),
        (New-Text @(0xC0BC)),
        (New-Text @(0xC0AC)),
        (New-Text @(0xC624)),
        (New-Text @(0xC721)),
        (New-Text @(0xCE60)),
        (New-Text @(0xD314)),
        (New-Text @(0xAD6C))
    )

    if ($Number -eq 0) {
        return (New-Text @(0xC601))
    }

    if ($Number -lt 0) {
        return (New-Text @(0xB9C8, 0xC774, 0xB108, 0xC2A4)) + " " + (Convert-IntegerToKoreanReading -Number (-1 * $Number))
    }

    if ($Number -lt 10) {
        return $digits[$Number]
    }

    if ($Number -lt 100) {
        $tens = [math]::Floor($Number / 10)
        $ones = $Number % 10
        $text = if ($tens -eq 1) { New-Text @(0xC2ED) } else { $digits[$tens] + (New-Text @(0xC2ED)) }
        if ($ones -gt 0) {
            $text += $digits[$ones]
        }
        return $text
    }

    return [string]$Number
}

function Normalize-TextForSpeech {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $normalizedLines = foreach ($line in ($Text -split "`r?`n")) {
        $normalizedLine = [System.Text.RegularExpressions.Regex]::Replace(
            $line,
            '\uC81C(\d{1,2})(?=[\uAC00-\uD7A3])',
            {
                param($match)
                (New-Text @(0xC81C)) + (Convert-IntegerToKoreanReading -Number ([int]$match.Groups[1].Value))
            }
        )

        if ($normalizedLine -match '^(\s*)(\d{1,2})([.)])(\s+.*)$') {
            $prefix = $matches[1]
            $number = [int]$matches[2]
            $punctuation = $matches[3]
            $suffix = $matches[4]
            $prefix + (Convert-IntegerToKoreanReading -Number $number) + $punctuation + $suffix
            continue
        }

        $normalizedLine
    }

    return ($normalizedLines -join [Environment]::NewLine)
}

function Convert-TextToWave {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        $VoiceToken
    )

    $voice = $null
    $stream = $null
    $format = $null

    try {
        $voice = New-Object -ComObject SAPI.SpVoice
        if ($null -ne $VoiceToken) {
            $voice.Voice = $VoiceToken
        }

        $voice.Rate = 1
        $voice.Volume = 100

        # SAPI format type 6 = 8kHz / 16-bit / mono PCM WAV.
        $format = New-Object -ComObject SAPI.SpAudioFormat
        $format.Type = 6

        $stream = New-Object -ComObject SAPI.SpFileStream
        $stream.Format = $format
        $stream.Open($OutputPath, 3, $false)
        $voice.AudioOutputStream = $stream
        [void]$voice.Speak($Text)
    }
    finally {
        if ($null -ne $stream) {
            try {
                $stream.Close()
            }
            catch {
            }
            [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($stream)
        }

        if ($null -ne $voice) {
            [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($voice)
        }

        if ($null -ne $format) {
            [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($format)
        }
    }
}

$baseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptDir = Join-Path $baseDir "script"
$outputDir = Join-Path $baseDir "audio_data"

if (-not (Test-Path -LiteralPath $scriptDir -PathType Container)) {
    throw "Missing script directory: $scriptDir"
}

if (-not (Test-Path -LiteralPath $outputDir -PathType Container)) {
    [void](New-Item -ItemType Directory -Path $outputDir)
}

$textFiles = @(Get-ChildItem -LiteralPath $scriptDir -Filter *.txt -File | Sort-Object Name)
if ($textFiles.Count -eq 0) {
    Write-Host "No txt files found in the script directory."
    exit 0
}

$voiceToken = Get-PreferredVoice
$voiceDescription = if ($null -ne $voiceToken) { $voiceToken.GetDescription() } else { "Default voice" }

Write-Host "Selected voice: $voiceDescription"
Write-Host "Files to process: $($textFiles.Count)"
Write-Host ""

$index = 0
foreach ($file in $textFiles) {
    $index += 1
    $outputPath = Join-Path $outputDir ($file.BaseName + ".wav")
    $text = Read-TextFile -Path $file.FullName

    Write-Host ("[{0}/{1}] {2}" -f $index, $textFiles.Count, $file.Name)
    if ([string]::IsNullOrWhiteSpace($text)) {
        Write-Host "  Skipped: file is empty."
        continue
    }

    $normalizedText = Normalize-TextForSpeech -Text $text
    Convert-TextToWave -Text $normalizedText -OutputPath $outputPath -VoiceToken $voiceToken
}

Write-Host ""
Write-Host "Done: $outputDir"
