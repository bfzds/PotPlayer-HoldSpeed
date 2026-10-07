# 注册中转计划任务 "PotPlayerHoldSpeed"
# 用途: 供 zTasker 的引导脚本通过 schtasks /Run 拉起, 由系统服务在 zTasker 进程树之外启动常驻脚本
# 以当前用户身份运行即可, 无需管理员; 重复执行会覆盖旧注册
#
# 用法: powershell -ExecutionPolicy Bypass -File .\register-scheduled-task.ps1

$ErrorActionPreference = "Stop"

# ---- 定位 AutoHotkey v2 解释器 ----
$ahkCandidates = @(
    (Join-Path $env:ProgramFiles "AutoHotkey\v2\AutoHotkey64.exe"),
    (Join-Path ${env:ProgramFiles(x86)} "AutoHotkey\v2\AutoHotkey64.exe")
)
$ahkExe = $ahkCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $ahkExe) {
    Write-Host "未找到 AutoHotkey v2 (AutoHotkey64.exe), 请先安装或手动修改本脚本中的路径。" -ForegroundColor Red
    exit 1
}

# ---- 定位脚本目录 (脚本需位于纯英文路径) ----
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ahkScript = Join-Path $scriptDir "PotPlayer-HoldSpeed.ahk"
if (-not (Test-Path $ahkScript)) {
    Write-Host "未找到 $ahkScript" -ForegroundColor Red
    exit 1
}

$action  = New-ScheduledTaskAction -Execute $ahkExe -Argument "`"$ahkScript`""
$trigger = New-ScheduledTaskTrigger -Once -At "2020-01-01T00:00:00"   # 不会自动触发的占位时间, 只供手动 /Run

# 关键: 覆盖任务计划程序的默认电源/时限策略。
# 默认值(禁止电池启动、切换电池即终止、72小时执行时限)是为一次性维护作业设计的,
# 对常驻脚本是致命的: 笔记本切到电池供电的瞬间, 常驻脚本会被任务计划程序直接终止, 不留任何日志。
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName "PotPlayerHoldSpeed" -Action $action -Trigger $trigger -Settings $settings `
    -Description "PotPlayer hold-speed broker (started via schtasks /Run by zTasker)" -Force |
    Select-Object TaskName, State

Write-Host ""
Write-Host "注册完成。下一步在 zTasker 中新建任务:" -ForegroundColor Green
Write-Host "  触发: 窗口事件 - 创建(从无到有), 类名 PotPlayer64"
Write-Host "  动作: 运行AHK脚本(V2, 内联), 内容:"
Write-Host '    RunWait(A_ComSpec '' /c schtasks /Run /TN "PotPlayerHoldSpeed"'', , "Hide")'
