#Requires AutoHotkey v2.0
#SingleInstance Off          ; 自己管理实例：跟随模式下重复触发 = 静默接管
DetectHiddenWindows true

; ======================================================================
;  PotPlayer 长按倍速 / 松开恢复（仿 B 站：长按 → 倍速播放，松开回原速）
;
;  - 仅在 PotPlayer 位于前台时生效，其他程序不受影响
;  - 短按 → 仍是 PotPlayer 原生"快进 5 秒"，长按超过 0.3 秒才触发倍速
;  - 原理：模拟 PotPlayer 默认热键 c（每按一次 +0.1x）与 z（速度重置）
;    无需在 PotPlayer 里修改任何设置
;
;  启动链路（方案B 跟随 PotPlayer 进程）：
;    zTasker（PotPlayer64 窗口创建触发）
;      → 内联引导脚本执行 schtasks /Run
;      → 计划任务 "PotPlayerHoldSpeed" 由系统服务启动本脚本
;      → 本脚本常驻；PotPlayer 退出约 30 秒后自动停用
;
;  每次动作都会写入同目录 PotPlayer-HoldSpeed.log，便于排查
; ======================================================================

; --------------------- 可自行修改的配置 ------------------------------
potWin     := "ahk_class PotPlayer64 ahk_exe PotPlayerMini64.exe"  ; PotPlayer 64 位主窗口
holdTime   := 0.3      ; 按住超过多少秒算"长按"
holdSpeed  := 3.0      ; 长按目标倍速
restSpeed  := 1.5      ; 松开后的速度
speedStep  := 0.1      ; PotPlayer 每按一次 c 的速度变化量(选项→播放→"速度调整单位", 默认0.1)
speedKey   := "c"      ; PotPlayer "加快播放速度" 热键（默认 c）
resetKey   := "z"      ; PotPlayer "重置播放速度" 热键（默认 z）
useControlSend := false  ; 若中文输入法截获按键导致倍速无效，改为 true
followPotPlayer := true  ; PotPlayer 进程退出约 30 秒后本脚本自动停用
; ----------------------------------------------------------------------

logFile := A_ScriptDir "\PotPlayer-HoldSpeed.log"
Log(msg) {
    FileAppend("[" FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") "] " msg "`n", logFile, "UTF-8")
}

; --- 启动逻辑 ---
takeover := followPotPlayer || (A_Args.Length && A_Args[1] = "/follow")
wasRunning := false
oldHwnd := WinExist(A_ScriptFullPath " ahk_class AutoHotkey")
if oldHwnd && oldHwnd != A_ScriptHwnd {     ; 排除自身隐藏主窗口
    wasRunning := true
    Log("检测到旧实例, 接管模式: 关闭旧实例后继续")
    WinClose(oldHwnd)
    if !takeover {
        Log("开关模式: 已停用")
        TrayTip("已停用", "PotPlayer 长按倍速")
        ExitApp()
    }
    Sleep(400)
    oldHwnd := WinExist(A_ScriptFullPath " ahk_class AutoHotkey")
    if oldHwnd && oldHwnd != A_ScriptHwnd {
        Log("旧实例未正常退出, 放弃本次启动")
        TrayTip("旧实例未正常退出, 已放弃本次启动", "PotPlayer 长按倍速")
        ExitApp()
    }
}
if !wasRunning {
    Log("脚本启动 (等待 PotPlayer 触发/前台)")
    TrayTip("已启用：PotPlayer 前台长按 → " holdSpeed " 倍速，松开 " restSpeed " 倍速", "PotPlayer 长按倍速")
}
Log("运行模式: " (useControlSend ? "ControlSend" : "Send") ", 长按=" holdSpeed "x, 松开=" restSpeed "x")

if followPotPlayer {
    WatchPotPlayer()
    SetTimer WatchPotPlayer, 5000
}

; 长按: 先 z 重置到 1.0 再连按 c 升到 holdSpeed; 松开: 先 z 再升到 restSpeed
; (先重置再补步, 保证从任何当前速度出发都能精确到达目标)
toHoldKeys := ""
toRestKeys := ""
Loop Round((holdSpeed - 1.0) / speedStep)
    toHoldKeys .= speedKey
Loop Round((restSpeed - 1.0) / speedStep)
    toRestKeys .= speedKey
toHoldKeys := resetKey toHoldKeys
toRestKeys := resetKey toRestKeys

DoSend(keys) {
    if useControlSend
        ControlSend(keys, , potWin)
    else
        Send(keys)
}

#HotIf WinActive(potWin)

Right:: {  ; 想改触发键（如 Tab、鼠标侧键 XButton2）：改这里和下面两处 KeyWait("Right", ...)
    if !KeyWait("Right", "T" holdTime) {    ; 一直按住超过 holdTime 仍未松开 → 长按
        Log("长按触发: 调整到 " holdSpeed "x")
        DoSend(toHoldKeys)
        ToolTip("▶▶▶ " holdSpeed "x   （松开恢复 " restSpeed "x）")
        SetTimer(() => ToolTip(), -1500)
        KeyWait("Right")                    ; 等待松开
        ToolTip()
        Log("松开: 恢复 " restSpeed "x")
        if WinActive(potWin)
            DoSend(toRestKeys)
        else
            ControlSend(toRestKeys, , potWin) ; 长按期间焦点被切走，也尽量把速度恢复掉
    } else {
        if WinActive(potWin)
            Send("{Right}")                 ; 短按：触发 PotPlayer 原生快进 5 秒
    }
}

#HotIf

; 进程跟随：PotPlayer 退出约 30 秒后自动停用脚本
WatchPotPlayer() {
    static lastSeen := 0
    if ProcessExist("PotPlayerMini64.exe")
        lastSeen := A_TickCount
    else if lastSeen && A_TickCount - lastSeen > 30000 {
        Log("PotPlayer 已退出超过30秒, 脚本自动停用")
        ExitApp()
    }
}
