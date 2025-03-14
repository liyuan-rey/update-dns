try {
    # 定义脚本路径
    $scriptPath = Join-Path -Path ([System.Environment]::GetFolderPath("UserProfile")) -ChildPath "update-dns.ps1"

    # 复制当前目录的脚本到 scriptPath
    Copy-Item -Path "$PSScriptRoot\update-dns.ps1" -Destination $scriptPath -Force
    Copy-Item -Path "$PSScriptRoot\.env" -Destination $scriptPath -Force

    # 定义计划任务名称和文件夹
    $taskName = "CloudflareDNSUpdate"
    $taskFolder = "\MyTasks\"

    # 创建计划任务动作
    $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File $scriptPath"

    # 创建计划任务触发器
    # 一次性触发器，开机时运行
    $trigger = New-ScheduledTaskTrigger -AtStartup
    # 每天 00:00 触发
    $dailyTrigger = New-ScheduledTaskTrigger -Daily -At "00:00"
    # 每 2 小时运行一次
    $hourlyTrigger = New-ScheduledTaskTrigger -Once -At "00:00" -RepetitionInterval (New-TimeSpan -Hours 2) -RepetitionDuration (New-TimeSpan -Days 1)

    # 创建计划任务设置
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

    # 注册计划任务到独立文件夹
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger, $dailyTrigger, $hourlyTrigger -Settings $settings -User "SYSTEM" -TaskPath $taskFolder -Force
} catch {
    Write-Error "发生错误: $_"
    exit 1
}
