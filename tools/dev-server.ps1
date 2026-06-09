# Local development server for the Find a Church site.
#
# This machine doesn't need Node or the Netlify CLI to preview the site:
# this script serves the static files in public/ and emulates the
# /.netlify/functions/churches endpoint by calling Airtable directly,
# using the same environment variables from .env.
#
# Usage:  powershell -ExecutionPolicy Bypass -File tools\dev-server.ps1
# Then open http://localhost:8888
#
# NOTE: This is a development convenience only. The deployed site uses
# netlify/functions/churches.mjs — keep the two in sync if behavior changes.

$ErrorActionPreference = "Stop"

$root      = Split-Path -Parent $PSScriptRoot
$publicDir = Join-Path $root "public"
$envFile   = Join-Path $root ".env"
$port      = 8888

# ── Parse .env ──────────────────────────────────────────────────────────────
$envVars = @{}
if (Test-Path $envFile) {
  foreach ($line in Get-Content $envFile) {
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
      $envVars[$Matches[1]] = $Matches[2].Trim()
    }
  }
}

$BASE_ID        = $envVars["AIRTABLE_BASE_ID"]
$TOKEN          = $envVars["AIRTABLE_TOKEN"]
$CHURCHES_TABLE = if ($envVars["CHURCHES_TABLE"]) { $envVars["CHURCHES_TABLE"] } else { "Churches" }
$SERVICES_TABLE = if ($envVars["SERVICES_TABLE"]) { $envVars["SERVICES_TABLE"] } else { "Services" }

# ── Airtable fetch with pagination (mirrors churches.mjs) ──────────────────
function Get-AirtableTable([string]$tableName) {
  $records = @()
  $offset  = $null
  do {
    $url = "https://api.airtable.com/v0/$BASE_ID/$([uri]::EscapeDataString($tableName))"
    if ($offset) { $url += "?offset=$([uri]::EscapeDataString($offset))" }
    $resp = Invoke-RestMethod -Uri $url -Headers @{ Authorization = "Bearer $TOKEN" }
    $records += $resp.records
    $offset = $resp.offset
  } while ($offset)
  return $records
}

# In-memory cache, mirrors the 5-minute CDN cache in production
$script:cachedPayload = $null
$script:cachedAt      = [datetime]::MinValue

function Get-ChurchesPayload([bool]$debug) {
  if ($script:cachedPayload -and ((Get-Date) - $script:cachedAt).TotalSeconds -lt 300) {
    $payload = $script:cachedPayload
  } else {
    $churches = Get-AirtableTable $CHURCHES_TABLE
    $services = Get-AirtableTable $SERVICES_TABLE
    Write-Host "Fetched $($churches.Count) church and $($services.Count) service records from Airtable."
    $payload = @{ churches = $churches; services = $services }
    $script:cachedPayload = $payload
    $script:cachedAt      = Get-Date
  }
  if ($debug) {
    $payload = @{
      churches = $payload.churches
      services = $payload.services
      _debug   = @{
        churchCount   = $payload.churches.Count
        serviceCount  = $payload.services.Count
        churchFields  = @(if ($payload.churches.Count)  { $payload.churches[0].fields.PSObject.Properties.Name }  else { @() })
        serviceFields = @(if ($payload.services.Count) { $payload.services[0].fields.PSObject.Properties.Name } else { @() })
      }
    }
  }
  return $payload | ConvertTo-Json -Depth 20 -Compress
}

# ── MIME types ──────────────────────────────────────────────────────────────
$mime = @{
  ".html" = "text/html; charset=utf-8"
  ".css"  = "text/css; charset=utf-8"
  ".js"   = "application/javascript; charset=utf-8"
  ".mjs"  = "application/javascript; charset=utf-8"
  ".json" = "application/json; charset=utf-8"
  ".png"  = "image/png"
  ".jpg"  = "image/jpeg"
  ".svg"  = "image/svg+xml"
  ".ico"  = "image/x-icon"
}

# ── HTTP server ─────────────────────────────────────────────────────────────
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
$listener.Start()
Write-Host "Find a Church dev server running at http://localhost:$port  (Ctrl+C to stop)"

try {
  while ($listener.IsListening) {
    $ctx  = $listener.GetContext()
    $req  = $ctx.Request
    $res  = $ctx.Response
    $path = $req.Url.AbsolutePath

    try {
      if ($path -eq "/.netlify/functions/churches") {
        $debug = $req.QueryString["debug"] -eq "1"
        $json  = Get-ChurchesPayload $debug
        $bytes = [Text.Encoding]::UTF8.GetBytes($json)
        $res.ContentType = "application/json; charset=utf-8"
        $res.OutputStream.Write($bytes, 0, $bytes.Length)
      } else {
        if ($path -eq "/") { $path = "/index.html" }
        $file = Join-Path $publicDir ($path.TrimStart("/") -replace "/", "\")
        $full = [IO.Path]::GetFullPath($file)
        if ($full.StartsWith($publicDir, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path $full -PathType Leaf)) {
          $ext = [IO.Path]::GetExtension($full).ToLower()
          $res.ContentType = if ($mime[$ext]) { $mime[$ext] } else { "application/octet-stream" }
          $bytes = [IO.File]::ReadAllBytes($full)
          $res.OutputStream.Write($bytes, 0, $bytes.Length)
        } else {
          $res.StatusCode = 404
          $bytes = [Text.Encoding]::UTF8.GetBytes("Not found")
          $res.OutputStream.Write($bytes, 0, $bytes.Length)
        }
      }
      Write-Host "$($req.HttpMethod) $($req.Url.PathAndQuery) -> $($res.StatusCode)"
    } catch {
      Write-Host "ERROR handling $($req.Url.PathAndQuery): $($_.Exception.Message)"
      try {
        $res.StatusCode = 502
        $bytes = [Text.Encoding]::UTF8.GetBytes('{"error":"Failed to fetch data from Airtable."}')
        $res.OutputStream.Write($bytes, 0, $bytes.Length)
      } catch {}
    } finally {
      $res.OutputStream.Close()
    }
  }
} finally {
  $listener.Stop()
}
