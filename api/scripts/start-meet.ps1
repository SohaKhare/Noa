$ErrorActionPreference = 'Stop'

# Read only the Attendee key; do not enable Gmail or export unrelated credentials.
if (-not $env:ATTENDEE_API_KEY) {
  $candidates = @((Join-Path $PSScriptRoot '..\.env'), (Join-Path $PSScriptRoot '..\..\.env'))
  foreach ($file in $candidates) {
    if (Test-Path $file) {
      $entry = Get-Content $file | Where-Object { $_ -match '^\s*ATTENDEE_API_KEY\s*=' } | Select-Object -Last 1
      if ($entry) {
        $value = ($entry -split '=', 2)[1].Trim().Trim('"').Trim("'")
        if ($value) { $env:ATTENDEE_API_KEY = $value; break }
      }
    }
  }
}
if (-not $env:ATTENDEE_API_KEY) { throw 'Set ATTENDEE_API_KEY in the process, api/.env or root .env.' }

Set-Location (Join-Path $PSScriptRoot '..')
mix phx.server
