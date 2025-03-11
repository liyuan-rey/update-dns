# 定义脚本路径
$scriptPath = Join-Path -Path [Environment]::GetFolderPath("UserProfile") -ChildPath "update-dns.ps1"

# 创建计划任务动作
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File $scriptPath"

# 创建计划任务触发器
$trigger = New-ScheduledTaskTrigger -AtStartup
$hourlyTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours 1)

# 创建计划任务设置
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

# 注册计划任务
Register-ScheduledTask -TaskName "CloudflareDNSUpdate" -Action $action -Trigger $trigger, $hourlyTrigger -Settings $settings -User "SYSTEM"