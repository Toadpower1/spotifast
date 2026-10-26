param(
    [Parameter(Position = 0)]
    [string]$SpotifastPath = "."
)

$ErrorActionPreference = "Stop"

function Fail([string]$Message) {
    Write-Host ""
    Write-Host "Passive Mode is NIET geinstalleerd." -ForegroundColor Red
    Write-Host $Message -ForegroundColor Red
    exit 1
}

function Replace-Once {
    param(
        [string]$Text,
        [string]$Pattern,
        [scriptblock]$Replacement,
        [string]$Description
    )

    $regex = [regex]::new(
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::Multiline
    )

    $matches = $regex.Matches($Text)
    if ($matches.Count -ne 1) {
        throw "Kon '$Description' niet veilig vinden (gevonden: $($matches.Count))."
    }

    return $regex.Replace(
        $Text,
        [System.Text.RegularExpressions.MatchEvaluator]{
            param($m)
            & $Replacement $m
        },
        1
    )
}

try {
    $root = (Resolve-Path -LiteralPath $SpotifastPath).Path
} catch {
    Fail "Map bestaat niet: $SpotifastPath"
}

$cargoPath = Join-Path $root "Cargo.toml"
$appPath = Join-Path $root "src\app.rs"
$settingsPath = Join-Path $root "src\settings.rs"
$uiSettingsPath = Join-Path $root "src\ui\settings.rs"

foreach ($path in @($cargoPath, $appPath, $settingsPath, $uiSettingsPath)) {
    if (-not (Test-Path -LiteralPath $path)) {
        Fail "Dit lijkt geen volledige Spotifast-broncode-map te zijn. Ontbreekt: $path"
    }
}

$cargo = [System.IO.File]::ReadAllText($cargoPath)

if ($cargo -notmatch '(?m)^version\s*=\s*"0\.14\.2"\s*$') {
    $version = if ($cargo -match '(?m)^version\s*=\s*"([^"]+)"\s*$') {
        $Matches[1]
    } else {
        "onbekend"
    }

    Fail "Deze installer is bewust gemaakt voor Spotifast 0.14.2. Gevonden versie: $version. Er is niets aangepast."
}

$app = [System.IO.File]::ReadAllText($appPath)
$settings = [System.IO.File]::ReadAllText($settingsPath)
$uiSettings = [System.IO.File]::ReadAllText($uiSettingsPath)

# ---------------------------------------------------------------------------
# 1. src/settings.rs
# ---------------------------------------------------------------------------

if ($settings -notmatch '\bpub\s+passive_mode\s*:\s*bool\s*,') {
    $settings = Replace-Once `
        -Text $settings `
        -Pattern '(?m)^(\s*pub\s+gapless\s*:\s*bool\s*,\s*\r?\n)' `
        -Description "Settings.gapless veld" `
        -Replacement {
            param($m)
            $m.Groups[1].Value +
            "    /// Automatically open the playing track's album page when the track changes.`r`n" +
            "    #[serde(default)]`r`n" +
            "    pub passive_mode: bool,`r`n"
        }
}

if ($settings -notmatch '(?m)^\s*passive_mode\s*:\s*false\s*,') {
    $settings = Replace-Once `
        -Text $settings `
        -Pattern '(?m)^(\s*gapless\s*:\s*true\s*,\s*\r?\n)' `
        -Description "Settings::default gapless waarde" `
        -Replacement {
            param($m)
            $m.Groups[1].Value +
            "            passive_mode: false,`r`n"
        }
}

# ---------------------------------------------------------------------------
# 2. src/ui/settings.rs
#    Add the row as the LAST playback row, so existing numeric row indices
#    do not shift when Spotifast changes other playback settings.
# ---------------------------------------------------------------------------

if ($uiSettings -notmatch 'let\s+passive_mode\s*=\s*gettext\(locale,\s*"Passive mode"\)') {
    $uiSettings = Replace-Once `
        -Text $uiSettings `
        -Pattern '(?m)^(\s*let\s+gapless\s*=\s*gettext\(locale,\s*"Gapless playback"\);\s*\r?\n)' `
        -Description "Gapless playback label in Settings UI" `
        -Replacement {
            param($m)
            $m.Groups[1].Value +
            '    let passive_mode = gettext(locale, "Passive mode");' + "`r`n"
        }
}

if ($uiSettings -notmatch 'Automatically open the album page when the playing track changes\.') {
    $pattern = '(?s)(let\s+playback_rows\s*=\s*\[.*?)(\r?\n\s*\];\s*\r?\n\s*if\s+section_matches\(&needle,\s*&playback,\s*&playback_rows\))'
    $regex = [regex]::new($pattern)
    $matches = $regex.Matches($uiSettings)

    if ($matches.Count -ne 1) {
        throw "Kon het einde van playback_rows niet veilig vinden (gevonden: $($matches.Count))."
    }

    $uiSettings = $regex.Replace(
        $uiSettings,
        [System.Text.RegularExpressions.MatchEvaluator]{
            param($m)
            $m.Groups[1].Value +
            "`r`n        RowText::new(" +
            "`r`n            passive_mode.clone()," +
            "`r`n            gettext(" +
            "`r`n                locale," +
            "`r`n                `"Automatically open the album page when the playing track changes.`"," +
            "`r`n            )," +
            "`r`n        )," +
            $m.Groups[2].Value
        },
        1
    )
}

if ($uiSettings -notmatch 'let\s+passive_row\s*=\s*&playback_rows\[playback_rows\.len\(\)\s*-\s*1\]') {
    $uiSettings = Replace-Once `
        -Text $uiSettings `
        -Pattern '(?m)^(\s*section\(ui,\s*&palette,\s*&playback,\s*\|ui\|\s*\{\s*\r?\n)' `
        -Description "Playback Settings section" `
        -Replacement {
            param($m)
            $m.Groups[1].Value +
            "        // Custom Passive Mode: keep this row at the end of playback_rows.`r`n" +
            "        let passive_row = &playback_rows[playback_rows.len() - 1];`r`n" +
            "        filtered_row(ui, &palette, &needle, &playback, passive_row, |ui| {`r`n" +
            "            if widgets::switch(`r`n" +
            "                ui,`r`n" +
            "                &palette,`r`n" +
            "                &passive_mode,`r`n" +
            "                &mut app.settings.passive_mode,`r`n" +
            "            )`r`n" +
            "            .changed()`r`n" +
            "            {`r`n" +
            "                changed = true;`r`n" +
            "            }`r`n" +
            "        });`r`n"
        }
}

# ---------------------------------------------------------------------------
# 3. src/app.rs
# ---------------------------------------------------------------------------

# Main trigger: when Spotifast confirms that a different track is playing.
if ($app -notmatch 'Custom Passive Mode: open the album on a confirmed track change') {
    $functionStart = $app.IndexOf("fn on_now_playing_changed(&mut self)")
    if ($functionStart -lt 0) {
        throw "Kon on_now_playing_changed() niet vinden."
    }

    $prefix = $app.Substring(0, $functionStart)
    $tail = $app.Substring($functionStart)

    $earlyReturnPattern = '(?m)^(\s*if\s+same_uri\s*&&\s*!new_occurrence\s*\{\s*\r?\n\s*return;\s*\r?\n\s*\}\s*\r?\n)'
    $regex = [regex]::new($earlyReturnPattern)
    $matches = $regex.Matches($tail)

    if ($matches.Count -lt 1) {
        throw "Kon de track-change guard in on_now_playing_changed() niet vinden."
    }

    $tail = $regex.Replace(
        $tail,
        [System.Text.RegularExpressions.MatchEvaluator]{
            param($m)
            $m.Groups[1].Value +
            "`r`n" +
            "        // Custom Passive Mode: open the album on a confirmed track change.`r`n" +
            "        if self.settings.passive_mode && !same_uri {`r`n" +
            "            if let Some(album_id) = now.album_id.clone() {`r`n" +
            "                self.actions.push(Action::Open(Page::Album(album_id)));`r`n" +
            "            }`r`n" +
            "        }`r`n"
        },
        1
    )

    $app = $prefix + $tail
}

# Reliability fallback:
# Local playback can announce the new track before its album id has reached
# the track cache. When the Track API response arrives, open the album if this
# is still the current track and the first trigger had no album id.
if ($app -notmatch 'Custom Passive Mode fallback: metadata arrived after the track change') {
    $trackArm = $app.IndexOf("ApiResponse::Track { id, result } => {")
    if ($trackArm -lt 0) {
        throw "Kon ApiResponse::Track niet vinden voor de Passive Mode metadata-fallback."
    }

    $okTrack = $app.IndexOf("Ok(track) => {", $trackArm)
    if ($okTrack -lt 0 -or ($okTrack - $trackArm) -gt 2500) {
        throw "Kon Ok(track) in ApiResponse::Track niet veilig vinden."
    }

    $insertAt = $okTrack + "Ok(track) => {".Length

    $fallback = @"

                        // Custom Passive Mode fallback: metadata arrived after the track change.
                        let passive_album = if self.settings.passive_mode
                            && self.now_playing_live().is_some_and(|now| {
                                now.uri == track.uri && now.album_id.is_none()
                            })
                        {
                            track.album.as_ref().map(|album| album.id.clone())
                        } else {
                            None
                        };
                        if let Some(album_id) = passive_album {
                            self.actions.push(Action::Open(Page::Album(album_id)));
                        }
"@

    $app = $app.Insert($insertAt, $fallback)
}

# ---------------------------------------------------------------------------
# Validate our own additions before touching the user's checkout.
# ---------------------------------------------------------------------------

$checks = @(
    @{ Text = $settings; Pattern = '\bpub\s+passive_mode\s*:\s*bool\s*,'; Name = "Settings field" },
    @{ Text = $settings; Pattern = '(?m)^\s*passive_mode\s*:\s*false\s*,'; Name = "Default value" },
    @{ Text = $uiSettings; Pattern = 'Passive mode'; Name = "Settings UI label" },
    @{ Text = $uiSettings; Pattern = 'app\.settings\.passive_mode'; Name = "Settings UI switch" },
    @{ Text = $app; Pattern = 'Custom Passive Mode: open the album'; Name = "Track-change trigger" },
    @{ Text = $app; Pattern = 'Custom Passive Mode fallback'; Name = "Metadata fallback" }
)

foreach ($check in $checks) {
    if ($check.Text -notmatch $check.Pattern) {
        throw "Interne controle mislukt: $($check.Name)"
    }
}

# ---------------------------------------------------------------------------
# Backup and write. No source file is changed before all transformations passed.
# ---------------------------------------------------------------------------

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupDir = Join-Path $root ".passive-mode-backup\$stamp"
New-Item -ItemType Directory -Force -Path (Join-Path $backupDir "src\ui") | Out-Null

Copy-Item -LiteralPath $appPath -Destination (Join-Path $backupDir "src\app.rs")
Copy-Item -LiteralPath $settingsPath -Destination (Join-Path $backupDir "src\settings.rs")
Copy-Item -LiteralPath $uiSettingsPath -Destination (Join-Path $backupDir "src\ui\settings.rs")

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($appPath, $app, $utf8NoBom)
[System.IO.File]::WriteAllText($settingsPath, $settings, $utf8NoBom)
[System.IO.File]::WriteAllText($uiSettingsPath, $uiSettings, $utf8NoBom)

Write-Host ""
Write-Host "Passive Mode voor Spotifast 0.14.2 is toegevoegd." -ForegroundColor Green
Write-Host "Backup: $backupDir"
Write-Host ""
Write-Host "Test nu vanuit deze map:" -ForegroundColor Cyan
Write-Host "  cargo check --no-default-features"
Write-Host ""
Write-Host "Als dat slaagt:" -ForegroundColor Cyan
Write-Host "  cargo run --no-default-features"
Write-Host ""
Write-Host "De schakelaar staat in Settings > Playback on this computer > Passive mode."
