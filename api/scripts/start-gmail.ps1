$ErrorActionPreference = 'Stop'
$envFile = Join-Path $PSScriptRoot '..\.env'

if (-not (Test-Path $envFile)) {
  throw "Missing $envFile. Copy api/.env.example to api/.env and fill in the mailbox credentials and workspace UUID."
}

Get-Content $envFile | ForEach-Object {
  $line = $_.Trim()
  if ($line -and -not $line.StartsWith('#')) {
    $parts = $line -split '=', 2
    if ($parts.Count -ne 2) { throw "Invalid .env line (expected KEY=VALUE)." }
    $key = $parts[0].Trim()
    $value = $parts[1].Trim()
    if ($value.Length -ge 2 -and (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'")))) {
      $value = $value.Substring(1, $value.Length - 2)
    }
    [Environment]::SetEnvironmentVariable($key, $value, 'Process')
  }
}

$required = @('GMAIL_IMAP_ENABLED', 'GMAIL_ORG_ID', 'GMAIL_IMAP_USERNAME', 'GMAIL_IMAP_PASSWORD')
$missing = @($required | Where-Object { -not [Environment]::GetEnvironmentVariable($_, 'Process') })
if ($missing.Count -gt 0) { throw "Missing required .env values: $($missing -join ', ')" }
if ($env:GMAIL_IMAP_ENABLED -ne 'true') { throw 'Set GMAIL_IMAP_ENABLED=true in api/.env to enable polling.' }

Set-Location (Join-Path $PSScriptRoot '..')
mix phx.server
