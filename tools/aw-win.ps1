# Unreal Agency — ActivityWatch sync for Windows.
# Install (PowerShell): $t='YOUR_TOKEN'; irm https://unrealagency.ai/tools/aw-win.ps1 | iex
if (-not $t) { Write-Host "Missing token: set `$t first"; return }
$dir = Join-Path $env:USERPROFILE ".unreal"; New-Item -ItemType Directory -Force -Path $dir | Out-Null
$sync = @"
`$ErrorActionPreference = 'SilentlyContinue'
`$token = '$t'
`$url = 'https://ljhpdqttcxwgufcejfor.supabase.co/rest/v1/rpc/aw_ingest'
`$key = 'sb_publishable_Nu7S4SnvuTFRg1ODn4VVrA_hCH5X1wY'
`$aw = 'http://localhost:5600/api/0'
`$stamp = Join-Path '$dir' 'last-sync'
`$mins = if (Test-Path `$stamp) { 30 } else { 1440 }
`$start = (Get-Date).ToUniversalTime().AddMinutes(-`$mins).ToString('yyyy-MM-ddTHH:mm:ssZ')
`$buckets = (Invoke-RestMethod "`$aw/buckets/" -TimeoutSec 10).PSObject.Properties.Name | Where-Object { `$_ -match '^aw-watcher-(window|afk|web)' }
if (-not `$buckets) { return }
`$ok = `$true
foreach (`$b in `$buckets) {
  `$ev = Invoke-WebRequest "`$aw/buckets/`$b/events?start=`$start&limit=5000" -UseBasicParsing -TimeoutSec 20
  if (-not `$ev) { continue }
  `$body = '{"p_token":"' + `$token + '","p_device":"' + `$env:COMPUTERNAME + '","p_bucket":"' + `$b + '","p_events":' + `$ev.Content + '}'
  try { Invoke-RestMethod -Method Post -Uri `$url -Headers @{ apikey = `$key; Authorization = "Bearer `$key" } -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes(`$body)) -TimeoutSec 30 | Out-Null } catch { `$ok = `$false }
}
if (`$ok) { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() | Out-File `$stamp }
"@
$file = Join-Path $dir "aw-sync.ps1"; Set-Content -Path $file -Value $sync -Encoding UTF8
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$file`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 10)
Register-ScheduledTask -TaskName "UnrealAwSync" -Action $action -Trigger $trigger -Force | Out-Null
powershell -NoProfile -ExecutionPolicy Bypass -File $file
Write-Host "Unreal tracking installed. It syncs every 10 minutes while ActivityWatch is running."
