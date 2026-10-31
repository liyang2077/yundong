# ============================================================
#  运动提醒 - 安装脚本
#  把当前目录的程序复制到指定位置
#  例：powershell -ExecutionPolicy Bypass -File install.ps1 -TargetDir "D:\运动提醒"
# ============================================================

param(
    [string]$TargetDir = "$env:USERPROFILE\运动提醒",
    [switch]$Open
)

$ErrorActionPreference = 'Stop'
$Source = Split-Path -Parent $MyInvocation.MyCommand.Path

function Say([string]$msg, [string]$color = 'Gray') {
    Write-Host "  $msg" -ForegroundColor $color
}

Write-Host ""
Write-Host "  运动提醒 - 安装" -ForegroundColor Cyan
Write-Host "  ----------------------------------------"

if (-not (Test-Path -LiteralPath (Join-Path $Source 'app\settings.ps1'))) {
    Write-Host "  [X] 当前目录不完整，缺少 app\settings.ps1" -ForegroundColor Red
    exit 1
}

if ([System.IO.Path]::GetFullPath($Source) -eq [System.IO.Path]::GetFullPath($TargetDir)) {
    Say "源目录和目标目录相同，无需复制" 'Yellow'
} else {
    if (-not (Test-Path -LiteralPath $TargetDir)) {
        New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
    }

    $appDir = Join-Path $TargetDir 'app'
    if (-not (Test-Path -LiteralPath $appDir)) {
        New-Item -ItemType Directory -Path $appDir -Force | Out-Null
    }

    $cmdFile = Get-ChildItem -LiteralPath $Source -File |
               Where-Object { $_.Extension -eq '.cmd' } |
               Select-Object -First 1
    if (-not $cmdFile) {
        Write-Host "  [X] 找不到启动文件（.cmd）" -ForegroundColor Red
        exit 1
    }
    Copy-Item -LiteralPath $cmdFile.FullName -Destination $TargetDir -Force

    foreach ($n in @('说明.md', 'README.md', 'SKILL.md')) {
        $p = Join-Path $Source $n
        if (Test-Path -LiteralPath $p) {
            Copy-Item -LiteralPath $p -Destination $TargetDir -Force
        }
    }

    foreach ($n in @('settings.ps1', 'player.ps1', 'launch.vbs')) {
        Copy-Item -LiteralPath (Join-Path $Source "app\$n") -Destination $appDir -Force
    }

    $cfgDst = Join-Path $appDir 'config.json'
    if (-not (Test-Path -LiteralPath $cfgDst)) {
        Copy-Item -LiteralPath (Join-Path $Source 'app\config.json') -Destination $cfgDst -Force
        Say "已写入默认配置" 'Green'
    } else {
        Say "目标位置已有配置，保留不动" 'Yellow'
    }

    Say "已安装到 $TargetDir" 'Green'
}

$videos = Join-Path $TargetDir 'videos'
if (-not (Test-Path -LiteralPath $videos)) {
    New-Item -ItemType Directory -Path $videos -Force | Out-Null
    Say "已创建 videos 文件夹" 'Green'
}

$vids = @(Get-ChildItem -LiteralPath $videos -File -ErrorAction SilentlyContinue |
          Where-Object { @('.mp4','.m4v','.mov','.wmv','.avi','.mkv','.webm') -contains $_.Extension.ToLower() })
if ($vids.Count -eq 0) {
    Say "videos 里还没有视频，记得放几个 mp4 进去" 'Yellow'
} else {
    Say "发现 $($vids.Count) 个视频" 'Green'
}

$entry = Get-ChildItem -LiteralPath $TargetDir -File | Where-Object { $_.Extension -eq '.cmd' } | Select-Object -First 1

Write-Host ""
Write-Host "  接下来" -ForegroundColor Cyan
Write-Host "  1. 把运动视频（mp4）放进 $videos" -ForegroundColor Gray
Write-Host "  2. 双击 $($entry.Name)" -ForegroundColor Gray
Write-Host "  3. 设好时间点，点「保存并应用定时」" -ForegroundColor Gray
Write-Host ""
Write-Host "  定时任务需要在界面里点那一下才会注册，脚本不代劳。" -ForegroundColor DarkGray
Write-Host ""

if ($Open) {
    Start-Process -FilePath $entry.FullName
    Say "已打开设置界面" 'Green'
}
