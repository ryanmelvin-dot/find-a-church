# Geocode church addresses into public/assets/churches-geo.json
#
# The map view plots every church at once, which requires latitude/longitude.
# Airtable only stores street addresses, so this script converts them using
# the free US Census Bureau batch geocoder (no API key, ~10k addresses per
# request), with a Nominatim (OpenStreetMap) fallback for addresses the
# Census service can't match.
#
# Run it whenever churches are added or addresses change in Airtable:
#   powershell -ExecutionPolicy Bypass -File tools\geocode-churches.ps1
#
# It is incremental: churches already present in churches-geo.json are
# skipped. Use -Force to re-geocode everything from scratch.

param([switch]$Force)

$ErrorActionPreference = "Stop"

$root    = Split-Path -Parent $PSScriptRoot
$geoPath = Join-Path $root "public\assets\churches-geo.json"
$envFile = Join-Path $root ".env"

# ── Read .env ───────────────────────────────────────────────────────────────
$envVars = @{}
foreach ($line in Get-Content $envFile) {
  if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
    $envVars[$Matches[1]] = $Matches[2].Trim()
  }
}
$BASE_ID = $envVars["AIRTABLE_BASE_ID"]
$TOKEN   = $envVars["AIRTABLE_TOKEN"]
$TABLE   = if ($envVars["CHURCHES_TABLE"]) { $envVars["CHURCHES_TABLE"] } else { "Churches" }

# ── Fetch all churches from Airtable ────────────────────────────────────────
$records = @()
$offset  = $null
do {
  $url = "https://api.airtable.com/v0/$BASE_ID/$([uri]::EscapeDataString($TABLE))"
  if ($offset) { $url += "?offset=$([uri]::EscapeDataString($offset))" }
  $resp = Invoke-RestMethod -Uri $url -Headers @{ Authorization = "Bearer $TOKEN" }
  $records += $resp.records
  $offset = $resp.offset
} while ($offset)
Write-Host "Fetched $($records.Count) church records from Airtable."

$churches = foreach ($r in $records) {
  $f = $r.fields
  $gcfa = "$($f.'GCFA ID')".Trim()
  if (-not $gcfa) { continue }
  [pscustomobject]@{
    Gcfa   = $gcfa
    Street = "$($f.'Physical Address (Street)')".Trim()
    City   = "$($f.'Physical Address (City)')".Trim()
    State  = "$($f.'Physical Address (State/Province)')".Trim()
    Zip    = "$($f.'Physical Address (ZIP/Postal Code)')".Trim()
  }
}

# ── Load existing coordinates (incremental mode) ────────────────────────────
$geo = @{}
if ((Test-Path $geoPath) -and -not $Force) {
  $existing = Get-Content $geoPath -Raw | ConvertFrom-Json
  foreach ($p in $existing.PSObject.Properties) { $geo[$p.Name] = @($p.Value) }
  Write-Host "Loaded $($geo.Count) existing coordinates (incremental — use -Force to redo all)."
}

$todo = @($churches | Where-Object { -not $geo.ContainsKey($_.Gcfa) -and $_.Street -and $_.City })
Write-Host "To geocode: $($todo.Count) addresses."

if ($todo.Count -gt 0) {
  # ── Pass 1: US Census batch geocoder ──────────────────────────────────────
  $batchCsv  = Join-Path $env:TEMP "church-batch.csv"
  $resultCsv = Join-Path $env:TEMP "church-batch-result.csv"
  $q = '"'
  $lines = foreach ($c in $todo) {
    $cells = @($c.Gcfa, $c.Street, $c.City, $c.State, $c.Zip) |
      ForEach-Object { $q + ($_ -replace '"', '""') + $q }
    $cells -join ","
  }
  [IO.File]::WriteAllLines($batchCsv, $lines)

  Write-Host "Submitting batch to US Census geocoder (can take a minute)..."
  & curl.exe -s --max-time 300 `
    -F "addressFile=@$batchCsv" `
    -F "benchmark=Public_AR_Current" `
    -o $resultCsv `
    "https://geocoding.geo.census.gov/geocoder/locations/addressbatch"

  $matched = 0
  $misses  = @{}
  foreach ($c in $todo) { $misses[$c.Gcfa] = $c }
  if (Test-Path $resultCsv) {
    $rows = Import-Csv $resultCsv -Header ID, Input, Status, MatchType, MatchedAddr, Coords, Tiger, Side
    foreach ($row in $rows) {
      if ($row.Status -eq "Match" -and $row.Coords) {
        $lonLat = $row.Coords -split ","
        $geo[$row.ID] = @([Math]::Round([double]$lonLat[1], 5), [Math]::Round([double]$lonLat[0], 5))
        $misses.Remove($row.ID)
        $matched++
      }
    }
  }
  Write-Host "Census matched $matched of $($todo.Count)."

  # ── Pass 2: Nominatim fallback for the misses (1 request/second) ──────────
  if ($misses.Count -gt 0) {
    Write-Host "Trying Nominatim for $($misses.Count) unmatched addresses (~$([Math]::Ceiling($misses.Count * 1.2 / 60)) min)..."
    $ua = @{ "User-Agent" = "INUMC-FindAChurch/1.0 (in.comm@inumc.org)" }
    $nomMatched = 0
    foreach ($c in @($misses.Values)) {
      Start-Sleep -Milliseconds 1100
      try {
        $url = "https://nominatim.openstreetmap.org/search?format=json&limit=1&countrycodes=us" +
               "&street=$([uri]::EscapeDataString($c.Street))" +
               "&city=$([uri]::EscapeDataString($c.City))" +
               "&state=$([uri]::EscapeDataString($c.State))" +
               "&postalcode=$([uri]::EscapeDataString($c.Zip))"
        $hit = @(Invoke-RestMethod -Uri $url -Headers $ua)
        if (-not $hit) {
          # Retry without street — city-level pin beats no pin
          Start-Sleep -Milliseconds 1100
          $url = "https://nominatim.openstreetmap.org/search?format=json&limit=1&countrycodes=us" +
                 "&city=$([uri]::EscapeDataString($c.City))" +
                 "&state=$([uri]::EscapeDataString($c.State))" +
                 "&postalcode=$([uri]::EscapeDataString($c.Zip))"
          $hit = @(Invoke-RestMethod -Uri $url -Headers $ua)
        }
        if ($hit) {
          $geo[$c.Gcfa] = @([Math]::Round([double]$hit[0].lat, 5), [Math]::Round([double]$hit[0].lon, 5))
          $nomMatched++
        }
      } catch {
        Write-Host "  Nominatim error for GCFA $($c.Gcfa): $($_.Exception.Message)"
      }
    }
    Write-Host "Nominatim matched $nomMatched more."
  }
}

# ── Write churches-geo.json ─────────────────────────────────────────────────
$ordered = [ordered]@{}
foreach ($k in ($geo.Keys | Sort-Object)) { $ordered[$k] = $geo[$k] }
$json = $ordered | ConvertTo-Json -Compress -Depth 3
[IO.File]::WriteAllText($geoPath, $json)

$total   = ($churches | Measure-Object).Count
$covered = ($churches | Where-Object { $geo.ContainsKey($_.Gcfa) } | Measure-Object).Count
Write-Host "Done. $covered of $total churches have coordinates -> $geoPath"
