# PotPlayer-HoldSpeed

仿 B 站的 PotPlayer 长按倍速播放：**长按 `→` 倍速播放，松开恢复**，短按仍是原生的快进 5 秒。
基于 AutoHotkey v2，配合 zTasker 实现跟随 PotPlayer 进程自动启停，全程无需手动管理。

## 功能

| 操作 | 行为 |
|---|---|
| 短按 `→` | PotPlayer 原生快进 5 秒（不受影响） |
| 长按 `→` ≥ 0.3 秒 | 切换到 **3.0 倍速**，屏幕角标 `▶▶▶ 3.0x` 提示 |
| 松开 `→` | 恢复到 **1.5 倍速**（可配置） |
| PotPlayer 不在前台 | `→` 键完全不受影响，其他程序正常使用 |
| 退出 PotPlayer | 约 30 秒后脚本自动停用，无常驻残留 |
| 重新打开 PotPlayer | 数秒内脚本被自动拉起，无需任何手动操作 |

## 运行链路

```
PotPlayer 启动(窗口创建)
  → zTasker [窗口"创建(从无到有)"触发, 类名 PotPlayer64]
  → 内联引导脚本: schtasks /Run
  → Windows 计划任务 "PotPlayerHoldSpeed"（系统服务启动, 独立于 zTasker 进程树）
  → PotPlayer-HoldSpeed.ahk 常驻
  → PotPlayer 退出约 30 秒后脚本自动停用
```

### 为什么需要计划任务中转？

zTasker 的任务执行器会在**任务结束时回收它启动的子进程**——无论是"运行程序"、"运行 .ahk 文件"还是"运行快捷方式"，被拉起的脚本都会在任务完成瞬间被杀掉，活不过 1 秒（任务日志甚至显示"运行成功"）。
解决方案：zTasker 只执行一行引导代码，由它去触发 Windows 计划任务，**由任务计划程序服务在 zTasker 进程树之外启动**真正需要常驻的脚本。

### 为什么脚本要放在纯英文路径？

AutoHotkey 的 UX 启动器（文件关联链路）对中文用户名路径（如 `C:\Users\<中文名>\...`）兼容性差，
实测会出现"启动成功但进程静默消失"。建议整个项目放在 `C:\AHK` 这类纯 ASCII 路径下。

## 兼容性

Windows 10 与 Windows 11 均可使用（作者在 Win11 25H2 实测；链路中用到的 AutoHotkey v2、zTasker、任务计划程序、PotPlayer 64 位在 Win10 上行为一致）。

## 安装

### 前置依赖

- [AutoHotkey v2.0+](https://www.autohotkey.com/)（只需安装，无需额外配置）
- PotPlayer 64 位（主程序 `PotPlayerMini64.exe`，无需修改任何 PotPlayer 设置）
- [zTasker](https://www.everauto.net/)（负责"PotPlayer 启动"这个触发器）

### 三步安装

**1. 放置脚本**：把整个目录放到纯英文路径（如 `C:\AHK`）。

**2. 注册中转计划任务**（当前用户身份，无需管理员）：

```powershell
powershell -ExecutionPolicy Bypass -File .\register-scheduled-task.ps1
```

注册脚本已内置三处关键覆盖：**允许电池供电时启动、切换电池不终止任务、取消 72 小时执行时限**——任务计划程序的默认电池策略是为一次性维护作业设计的，笔记本切到电池供电的瞬间会终止常驻脚本（表现为脚本无声消失、日志无任何退出记录），不覆盖必踩。

**3. zTasker 新建任务**：

- 触发方式：窗口事件 → **创建（从无到有）**，窗口类名填 `PotPlayer64`，轮询间隔默认 2 秒
- 任务动作：**运行 AHK 脚本**，版本选 **V2**，模式选 **内联脚本**，内容只放一行：

```autohotkey
RunWait(A_ComSpec ' /c schtasks /Run /TN "PotPlayerHoldSpeed"', , "Hide")
```

打开 PotPlayer，托盘出现 H 图标并弹出"已启用"气泡即完成。

## 配置

脚本开头可自行修改：

| 变量 | 默认 | 说明 |
|---|---|---|
| `holdSpeed` | `3.0` | 长按目标倍速 |
| `restSpeed` | `1.5` | 松开后的速度 |
| `speedStep` | `0.1` | PotPlayer 每按一次 `c` 的速度变化量（若在 PotPlayer 选项→播放→"速度调整单位"改过，需同步修改） |
| `speedKey` / `resetKey` | `c` / `z` | PotPlayer 默认的加速/重置热键 |
| `holdTime` | `0.3` | 长按判定时间（秒） |
| `useControlSend` | `false` | 若中文输入法截获按键导致变速无效，改为 `true` |
| `followPotPlayer` | `true` | PotPlayer 进程退出 30 秒后脚本自动停用；改为 `false` 则变成"再运行一次=关闭"的开关模式 |

## 设计细节

- **先重置再补步**：变速时先按 `z` 重置到 1.0，再按 `(目标-1)/步长` 次补按 `c`。
  松开后基准是 1.5 而不是 1.0，如果只按差值补步，速度会随使用次数累计漂移；
  每次从 1.0 出发则从任何当前速度都能精确到达目标。
- **实例自匹配**：脚本用 `A_ScriptHwnd` 排除自己的隐藏主窗口再做"旧实例检测"，
  否则接管逻辑会把自己误当旧实例关掉。
- **接管模式**：`followPotPlayer := true` 时重复触发 = 静默替换旧实例；
  改为 `false` 后变成开关模式（适合做 zTasker 热键一键启停）。
- **动作日志**：每次启动/接管/长按/恢复都写入同目录 `PotPlayer-HoldSpeed.log`，排查问题先看它。

## 故障排查

| 现象 | 处理 |
|---|---|
| 有 `▶▶▶` 角标但速度不变 | 中文输入法截获了按键：看视频时切英文输入法，或 `useControlSend := true` |
| 变速数值不对 | 确认 PotPlayer "速度调整单位" 是否为 0.1，并同步 `speedStep` |
| 打开 PotPlayer 后脚本没被拉起 | 依次检查：zTasker 是否在运行并加载了任务 → 手动执行 `schtasks /Run /TN "PotPlayerHoldSpeed"` 是否拉起脚本 → 查看 `PotPlayer-HoldSpeed.log` |
| 长按无任何反应 | 确认脚本在运行（托盘 H 图标）且 PotPlayer 是前台窗口 |
| 笔记本上脚本无声消失 / 电池供电时不启动 | 任务计划程序的默认电池策略所致，重跑 `register-scheduled-task.ps1` 即可（已内置覆盖） |

## 参考 / 致谢

- 长按倍速方案原型：[小众软件论坛 - PotPlayer长按倍速播放](https://meta.appinn.net/t/topic/36469)
- [小众软件 - PotPlayer：长按右箭头键实现三倍速播放[AHK]](https://www.appinn.com/potplayer-fast-forward-ahk)
- [Tzhanq/speed - GitHub](https://github.com/Tzhanq/speed)

## License

[MIT](LICENSE)
