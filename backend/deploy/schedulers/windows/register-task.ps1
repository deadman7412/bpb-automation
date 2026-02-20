param(
  [string]$TaskName = "BPB-Autoscan",
  [int]$IntervalHours = 6
)

$action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c C:\bpb-automation\backend\deploy\schedulers\windows\run-once.cmd scheduled >> C:\bpb-automation\logs\cron.log 2>&1"
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
  -RepetitionInterval (New-TimeSpan -Hours $IntervalHours) `
  -RepetitionDuration ([TimeSpan]::MaxValue)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -StartWhenAvailable

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Force
Write-Host "Registered task: $TaskName (every $IntervalHours hours)"
