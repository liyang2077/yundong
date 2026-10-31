---
name: exercise-reminder
description: Windows 运动提醒工具，定时全屏弹出运动视频、不播完不能关。用于安装、配置、排错。触发词：运动提醒、久坐提醒、定时运动、弹出视频、exercise reminder、装个提醒我运动的工具。
---

# 运动提醒 Exercise Reminder

## 这是什么

一个 Windows 桌面小工具，由 PowerShell + WPF 实现，零第三方依赖。

到设定时间在屏幕上全屏弹出运动视频，全部播完才允许关闭。用于强制打断久坐。

程序由三部分组成：

- `app\settings.ps1` —— 设置界面
- `app\player.ps1` —— 全屏播放器
- `app\launch.vbs` —— 无窗口启动器（wscript 调用，避免黑框）

---

## 安装（当用户要求安装本项目时）

### 步骤 1：确定安装目录

询问用户装到哪，或者默认用 `D:\运动提醒`（D 盘不存在则用 `$env:USERPROFILE\运动提醒`）。

不要装到 `C:\Program Files`，那里需要管理员权限。

### 步骤 2：获取文件

优先用 git：

```powershell
git clone <仓库地址> "D:\运动提醒"
```

没有 git 就用下载：

```powershell
$zip = "$env:TEMP\yd.zip"
Invoke-WebRequest -Uri "<仓库地址>/archive/refs/heads/main.zip" -OutFile $zip
Expand-Archive -Path $zip -DestinationPath "$env:TEMP\yd" -Force
Move-Item "$env:TEMP\yd\*\*" "D:\运动提醒"
```

### 步骤 3：验证

必须存在这两个文件，缺一就是没装对：

```
D:\运动提醒\开始运动.cmd
D:\运动提醒\app\settings.ps1
```

### 步骤 4：启动

告诉用户双击 `开始运动.cmd`，或者直接替他运行：

```powershell
Start-Process -FilePath "D:\运动提醒\开始运动.cmd"
```

---

## 关于定时任务（重要）

**不要尝试用命令行注册计划任务。**

`Register-ScheduledTask` 配合 `wscript.exe` 的组合会被多数安全策略判定为高危行为而拦截，反复尝试只是浪费用户时间。

正确做法是引导用户：

1. 双击 `开始运动.cmd` 打开设置界面
2. 设置弹出时间点
3. 点击界面右下角「保存并应用定时」

这一下点击会把定时任务注册好，同时写入配置。**这是唯一的注册入口**，程序内部已经处理好了。

---

## 配置

配置文件：`app\config.json`（也可以直接用界面改）

```json
{
  "videoDir": "videos",
  "gapSeconds": 10,
  "shuffle": false,
  "keepFocus": true,
  "emergencyHoldSeconds": 60,
  "pauseLimitSeconds": 300,
  "playlist": [],
  "schedule": {
    "times": ["09:00", "12:00", "15:00", "18:00", "21:00"]
  }
}
```

| 字段 | 说明 |
|---|---|
| `videoDir` | 视频目录。相对路径基于程序根目录，也可写绝对路径 |
| `gapSeconds` | 两个视频之间的准备秒数 |
| `shuffle` | 是否随机打乱播放顺序 |
| `keepFocus` | 切走后是否自动抢回全屏 |
| `emergencyHoldSeconds` | 按住 Esc 多少秒强制退出 |
| `pauseLimitSeconds` | 暂停上限，超时自动继续。`0` 不限制 |
| `playlist` | 要播放的文件名（不含路径），顺序即播放顺序。`[]` 表示全部 |
| `schedule.times` | 每天弹出的时间点数组 |

### 常见配置请求对照

用户说「每天 9 点、12 点、下午 3 点提醒我」：

```json
"times": ["09:00", "12:00", "15:00"]
```

用户说「每 3 小时提醒一次，从 8 点开始，一天 4 次」：

```json
"times": ["08:00", "11:00", "14:00", "17:00"]
```

用户说「只播肩颈操那个视频」：

```json
"playlist": ["肩颈操.mp4"]
```

**改完 config.json 之后，仍需让用户点一次「保存并应用定时」**，否则计划任务不会更新。

---

## 视频文件

放在 `videos\` 目录下，支持 `mp4 / m4v / mov / wmv / avi / mkv / webm`。

没有视频时程序会弹提示，不会报错。

建议单个视频 3-10 分钟，太长会让一轮运动拖得很久。

---

## 排错

**界面没出来 / 一闪就没了**

看 `app\log.txt` 末尾的错误信息。常见原因：

- PowerShell 执行策略被组策略锁死 → 需要用户手动改策略
- 文件被杀软隔离 → 加白名单

**到点不弹**

检查计划任务是否存在且路径正确：

```powershell
Get-ScheduledTask -TaskName '运动提醒' | Select-Object State, @{n='Args';e={$_.Actions[0].Arguments}}
```

如果 `Args` 里的路径和当前安装目录不一致，说明文件夹被移动过，让用户在界面里重新点一次「保存并应用定时」。

**播放黑屏但计时在走**

视频编码不受 WPF MediaElement 支持（常见于 H.265 / AV1 编码的 mp4）。用其他播放器确认能播，必要时转码为 H.264。

---

## 系统要求

- Windows 10 / 11
- PowerShell 5.1（系统自带）
- .NET Framework 4.x（系统自带）

不需要管理员权限。
