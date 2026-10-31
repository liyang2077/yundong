# ============================================================
#  运动提醒播放器 (Exercise Reminder)
#  全屏播放指定目录下所有视频，全部播完才允许关闭
#  紧急退出：按住 Esc 键 3 秒
# ============================================================

$ErrorActionPreference = 'Stop'

$AppDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProgRoot = Split-Path -Parent $AppDir
$script:BootLog = Join-Path $AppDir 'log.txt'

trap {
    $msg = ($_ | Out-String)
    try {
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  [FATAL] $msg" |
            Out-File -FilePath $script:BootLog -Append -Encoding utf8
    } catch { }
    try {
        [System.Windows.MessageBox]::Show(
            "程序出错：`n`n$($_.Exception.Message)`n`n详细信息已写入 log.txt",
            '运动提醒', 'OK', 'Error') | Out-Null
    } catch { }
    exit 1
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$CfgPath = Join-Path $AppDir 'config.json'
$LogPath = Join-Path $AppDir 'log.txt'

function Write-Log([string]$msg) {
    try {
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $msg" |
            Out-File -FilePath $LogPath -Append -Encoding utf8
    } catch { }
}

# ---------------- 读取配置 ----------------
if (-not (Test-Path -LiteralPath $CfgPath)) {
    Write-Log 'config.json 不存在，退出'
    exit 1
}

$Cfg = Get-Content -LiteralPath $CfgPath -Raw -Encoding UTF8 | ConvertFrom-Json

# 视频目录：相对路径（如 "videos"）相对本程序所在文件夹，绝对路径原样使用
# 这样整个文件夹挪到任何盘、任何位置都能照常工作
$RawDir = [string]$Cfg.videoDir
if ([string]::IsNullOrWhiteSpace($RawDir)) { $RawDir = 'videos' }
if ([System.IO.Path]::IsPathRooted($RawDir)) {
    $script:VideoDir = [System.IO.Path]::GetFullPath($RawDir)
} else {
    $script:VideoDir = [System.IO.Path]::GetFullPath((Join-Path $ProgRoot $RawDir))
}

$script:GapSec    = if ($null -ne $Cfg.gapSeconds) { [int]$Cfg.gapSeconds } else { 10 }
$script:Shuffle   = [bool]$Cfg.shuffle
$script:KeepFocus = if ($null -ne $Cfg.keepFocus) { [bool]$Cfg.keepFocus } else { $true }
$script:HoldSec   = if ($null -ne $Cfg.emergencyHoldSeconds) { [int]$Cfg.emergencyHoldSeconds } else { 60 }
$script:PauseLimit = if ($null -ne $Cfg.pauseLimitSeconds) { [int]$Cfg.pauseLimitSeconds } else { 300 }

# ---------------- 扫描视频 ----------------
$Exts = @('.mp4', '.m4v', '.mov', '.wmv', '.avi', '.mkv', '.webm')

$AllFiles = @()
if (Test-Path -LiteralPath $script:VideoDir) {
    $AllFiles = @(
        Get-ChildItem -LiteralPath $script:VideoDir -File -ErrorAction SilentlyContinue |
            Where-Object { $Exts -contains $_.Extension.ToLower() } |
            Sort-Object Name
    )
}

# 播放清单：playlist 里存的是文件名，留空表示播放全部
$Playlist = @()
if ($null -ne $Cfg.playlist) { $Playlist = @($Cfg.playlist | Where-Object { $_ }) }

$script:Files = @()
if ($Playlist.Count -gt 0) {
    foreach ($n in $Playlist) {
        $hit = @($AllFiles | Where-Object { $_.Name -eq [string]$n })
        if ($hit.Count -gt 0) { $script:Files += $hit[0] }
    }
    if ($script:Files.Count -eq 0) { $script:Files = $AllFiles }
} else {
    $script:Files = $AllFiles
}

if ($script:Shuffle -and $script:Files.Count -gt 1) {
    $script:Files = @($script:Files | Sort-Object { Get-Random })
}

if ($script:Files.Count -eq 0) {
    Write-Log '视频目录为空'
    [System.Windows.MessageBox]::Show(
        "视频目录里还没有视频。`n`n请把抖音下载的运动视频放进这个目录：`n$($script:VideoDir)`n`n放好以后再来触发一次。",
        '运动提醒', 'OK', 'Information') | Out-Null
    exit 0
}

Write-Log "开始，共 $($script:Files.Count) 个视频"

# ---------------- 界面 ----------------
$Xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="运动时间"
        WindowStyle="None"
        WindowState="Maximized"
        ResizeMode="NoResize"
        MaxWidth="100000"
        MaxHeight="100000"
        Topmost="True"
        ShowInTaskbar="False"
        Background="Black"
        FontFamily="Microsoft YaHei UI">
  <Grid>
    <MediaElement x:Name="Player" LoadedBehavior="Manual" UnloadedBehavior="Manual" Stretch="Uniform"/>

    <Border x:Name="InfoBar" VerticalAlignment="Bottom" HorizontalAlignment="Center"
            Margin="0,0,0,32" Background="#B3000000" CornerRadius="10" Padding="20,9">
      <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
        <TextBlock x:Name="InfoText" Foreground="#D9FFFFFF" FontSize="15" VerticalAlignment="Center"/>
        <Button x:Name="PauseBtn" Content="暂停" Width="66" Height="30" Margin="18,0,0,0"
                Focusable="False" Cursor="Hand" Background="#2EFFFFFF" Foreground="#F2FFFFFF"
                BorderThickness="0" FontSize="13">
          <Button.Template>
            <ControlTemplate TargetType="Button">
              <Border Background="{TemplateBinding Background}" CornerRadius="6">
                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
            </ControlTemplate>
          </Button.Template>
        </Button>
      </StackPanel>
    </Border>

    <Border x:Name="GapPanel" Background="#F0000000" Visibility="Collapsed">
      <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
        <TextBlock Text="下一个" Foreground="#8CFFFFFF" FontSize="17" HorizontalAlignment="Center"/>
        <TextBlock x:Name="GapTitle" Foreground="#FFFFFFFF" FontSize="30" HorizontalAlignment="Center" Margin="0,10,0,0"/>
        <TextBlock x:Name="GapCount" Foreground="#FF5DCAA5" FontSize="76" HorizontalAlignment="Center" Margin="0,16,0,0"/>
        <TextBlock Text="站好位置，准备开始" Foreground="#8CFFFFFF" FontSize="15" HorizontalAlignment="Center" Margin="0,10,0,0"/>
      </StackPanel>
    </Border>

    <Border x:Name="DonePanel" Background="#FF000000" Visibility="Collapsed">
      <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
        <TextBlock Text="全部完成" Foreground="#FF5DCAA5" FontSize="46" HorizontalAlignment="Center"/>
        <TextBlock x:Name="DoneDetail" Foreground="#99FFFFFF" FontSize="16" HorizontalAlignment="Center" Margin="0,16,0,0"/>
        <Button x:Name="CloseBtn" Content="关闭" Width="170" Height="48" Margin="0,40,0,0"
                FontSize="16" Background="#FF1D9E75" Foreground="White" BorderThickness="0"/>
        <TextBlock Text="下一轮 3 小时后" Foreground="#59FFFFFF" FontSize="13"
                   HorizontalAlignment="Center" Margin="0,22,0,0"/>
      </StackPanel>
    </Border>

    <TextBlock x:Name="HintText" Text="空格 暂停 · 按住 Esc 60 秒强制退出"
               Foreground="#33FFFFFF" FontSize="12" HorizontalAlignment="Right"
               VerticalAlignment="Bottom" Margin="0,0,18,8"/>
  </Grid>
</Window>
'@

$Win = [Windows.Markup.XamlReader]::Parse($Xaml)

function Get-Ctrl([string]$Name) {
    $c = $null
    try { $c = $Win.FindName($Name) } catch { }
    if (-not $c) {
        try { if ($Win.Content) { $c = $Win.Content.FindName($Name) } } catch { }
    }
    return $c
}

$Player     = Get-Ctrl 'Player'
$InfoBar    = Get-Ctrl 'InfoBar'
$InfoText   = Get-Ctrl 'InfoText'
$PauseBtn   = Get-Ctrl 'PauseBtn'
$GapPanel   = Get-Ctrl 'GapPanel'
$GapTitle   = Get-Ctrl 'GapTitle'
$GapCount   = Get-Ctrl 'GapCount'
$DonePanel  = Get-Ctrl 'DonePanel'
$DoneDetail = Get-Ctrl 'DoneDetail'
$CloseBtn   = Get-Ctrl 'CloseBtn'
$HintText   = Get-Ctrl 'HintText'

if (-not $Player -or -not $DonePanel -or -not $CloseBtn) {
    Write-Log '界面控件加载失败'
    [System.Windows.MessageBox]::Show(
        "界面加载失败（控件未找到）。`n`n请把 $LogPath 的内容发给小布。",
        '运动提醒', 'OK', 'Error') | Out-Null
    exit 1
}

$script:HintNormalBrush = $HintText.Foreground
$HintText.Text = "按住 Esc $($script:HoldSec) 秒可强制退出"

# ---------------- 状态 ----------------
$script:state       = 'idle'
$script:idx         = 0
$script:ended       = $false
$script:failed      = $false
$script:allDone     = $false
$script:gapEnd      = $null
$script:lastPos     = 0.0
$script:stuck       = 0
$script:totalSec    = 0.0
$script:escDown     = $null
$script:lostFocusAt = $null
$script:paused      = $false
$script:pauseStart  = $null

# ---------------- 逻辑 ----------------
function Update-Info {
    $n     = $script:idx + 1
    $total = $script:Files.Count
    $name  = $script:Files[$script:idx].BaseName

    if ($script:paused) {
        $tail = '已暂停 · 按空格继续'
        if ($script:PauseLimit -gt 0 -and $null -ne $script:pauseStart) {
            $left = [int]($script:PauseLimit - ((Get-Date) - $script:pauseStart).TotalSeconds)
            if ($left -lt 0) { $left = 0 }
            $tail = "已暂停 · 还剩 $left 秒自动继续"
        }
        $InfoText.Text = "第 $n / $total 个 · $name · $tail"
    } else {
        $ts = [TimeSpan]::FromSeconds([int]$script:totalSec)
        $InfoText.Text = "第 $n / $total 个 · $name · 已运动 $($ts.ToString('mm\:ss')) · 全部播完才能关闭"
    }
}

function Toggle-Pause {
    if ($script:allDone) { return }
    if ($script:state -ne 'playing') { return }

    if ($script:paused) {
        try { $Player.Play() } catch { }
        $script:paused = $false
        $script:pauseStart = $null
        $PauseBtn.Content = '暂停'
        Write-Log '继续播放'
    } else {
        try { $Player.Pause() } catch { }
        $script:paused = $true
        $script:pauseStart = Get-Date
        $PauseBtn.Content = '继续'
        Write-Log '暂停'
    }
    Update-Info
}

function Restore-Hint {
    $HintText.Text = "空格 暂停 · 按住 Esc $($script:HoldSec) 秒强制退出"
    $HintText.Foreground = $script:HintNormalBrush
    $HintText.Opacity = 1.0
}

function Start-Current {
    if ($script:idx -ge $script:Files.Count) { Show-Done; return }

    $GapPanel.Visibility  = 'Collapsed'
    $DonePanel.Visibility = 'Collapsed'
    $InfoBar.Visibility   = 'Visible'

    $f = $script:Files[$script:idx]
    $script:ended      = $false
    $script:failed     = $false
    $script:lastPos    = 0.0
    $script:stuck      = 0
    $script:paused     = $false
    $script:pauseStart = $null
    $script:state      = 'playing'
    $PauseBtn.Content  = '暂停'

    try {
        $Player.Source = New-Object System.Uri($f.FullName)
        $Player.Play()
        Write-Log "播放: $($f.Name)"
    } catch {
        Write-Log "播放异常 $($f.Name): $($_.Exception.Message)"
        Next-Video
        return
    }
    Update-Info
}

function Next-Video {
    $script:idx++
    if ($script:idx -ge $script:Files.Count) { Show-Done } else { Start-Gap }
}

function Start-Gap {
    if ($script:idx -ge $script:Files.Count) { Show-Done; return }

    $script:state = 'gap'
    try { $Player.Stop() } catch { }

    $GapTitle.Text = $script:Files[$script:idx].BaseName
    $GapCount.Text = [string]$script:GapSec
    $script:gapEnd = (Get-Date).AddSeconds($script:GapSec)
    $GapPanel.Visibility = 'Visible'
}

function Show-Done {
    $script:state   = 'done'
    $script:allDone = $true

    try { $Player.Stop() } catch { }

    $ts = [TimeSpan]::FromSeconds([int]$script:totalSec)
    $DoneDetail.Text     = "本次完成 $($script:Files.Count) 个视频，共运动 $($ts.ToString('mm\:ss'))"
    $InfoBar.Visibility  = 'Collapsed'
    $GapPanel.Visibility = 'Collapsed'
    $HintText.Visibility = 'Collapsed'
    $DonePanel.Visibility = 'Visible'
    $CloseBtn.Focus() | Out-Null

    Write-Log "全部完成，用时 $($ts.ToString('mm\:ss'))"
}

# ---------------- 事件 ----------------
$Player.Add_MediaEnded({ $script:ended = $true })
$Player.Add_MediaFailed({ $script:failed = $true })
$CloseBtn.Add_Click({ $Win.Close() })
$PauseBtn.Add_Click({ Toggle-Pause })

$Win.Add_Closing({
    param($s, $e)
    if (-not $script:allDone) {
        $e.Cancel = $true
        Write-Log '拦截了一次关闭尝试'
    }
})

$Win.Add_PreviewKeyDown({
    param($s, $e)
    if ($e.Key -eq [Windows.Input.Key]::Escape) {
        if ($null -eq $script:escDown) { $script:escDown = Get-Date }
        return
    }
    if ($null -ne $script:escDown) {
        $script:escDown = $null
        if (-not $script:allDone) { Restore-Hint }
    }
    if ($e.Key -eq [Windows.Input.Key]::Space -and -not $script:allDone) {
        Toggle-Pause
        $e.Handled = $true
    }
})
$Win.Add_PreviewKeyUp({
    param($s, $e)
    if ($e.Key -eq [Windows.Input.Key]::Escape) {
        $script:escDown = $null
        if (-not $script:allDone) { Restore-Hint }
    }
})

$Win.Add_Deactivated({ $script:lostFocusAt = Get-Date })
$Win.Add_Activated({ $script:lostFocusAt = $null })

# ---------------- 主循环 ----------------
function Invoke-Tick {

    if ($script:state -eq 'idle') {
        Start-Current
        return
    }

    if ($null -ne $script:escDown -and -not $script:allDone) {
        $held = ((Get-Date) - $script:escDown).TotalSeconds
        if ($held -ge $script:HoldSec) {
            Write-Log '紧急退出'
            $script:allDone = $true
            $Win.Close()
            return
        }
        $HintText.Text = "强制退出 $([int]$held) / $($script:HoldSec) 秒 · 松开可取消"
        $HintText.Foreground = [Windows.Media.Brushes]::White
    }

    if ($script:KeepFocus -and -not $script:allDone -and $null -ne $script:lostFocusAt) {
        if (((Get-Date) - $script:lostFocusAt).TotalSeconds -gt 1.5) {
            try {
                $Win.WindowState = 'Maximized'
                $Win.Topmost = $false
                $Win.Topmost = $true
                $Win.Activate() | Out-Null
                $Win.Focus() | Out-Null
            } catch { }
            $script:lostFocusAt = $null
        }
    }

    switch ($script:state) {

        'playing' {
            if ($script:paused) {
                if ($script:PauseLimit -gt 0 -and $null -ne $script:pauseStart) {
                    if (((Get-Date) - $script:pauseStart).TotalSeconds -ge $script:PauseLimit) {
                        Write-Log '暂停超时，自动继续'
                        Toggle-Pause
                        return
                    }
                }
                Update-Info
                return
            }

            if ($script:failed) {
                Write-Log "媒体失败，跳过第 $($script:idx + 1) 个"
                $script:failed = $false
                Next-Video
                return
            }

            if ($script:ended) {
                $script:ended = $false
                Next-Video
                return
            }

            try {
                $pos = $Player.Position.TotalSeconds
                $dur = 0.0
                if ($Player.NaturalDuration.HasTimeSpan) {
                    $dur = $Player.NaturalDuration.TimeSpan.TotalSeconds
                }

                if ($dur -gt 0 -and $pos -ge ($dur - 0.20)) {
                    $script:ended = $false
                    Next-Video
                    return
                }

                $diff = $pos - $script:lastPos
                if ($diff -gt 0.02) {
                    $script:totalSec += $diff
                    $script:stuck = 0
                } elseif ($diff -lt -0.50) {
                    $script:stuck = 0
                } else {
                    $script:stuck++
                }
                $script:lastPos = $pos

                if ($script:stuck -ge 240) {
                    Write-Log "播放卡住，跳过第 $($script:idx + 1) 个"
                    $script:stuck = 0
                    Next-Video
                    return
                }

                Update-Info
            } catch { }
        }

        'gap' {
            if ((Get-Date) -ge $script:gapEnd) {
                Start-Current
            } else {
                $left = [math]::Ceiling(($script:gapEnd - (Get-Date)).TotalSeconds)
                if ($left -lt 1) { $left = 1 }
                $GapCount.Text = [string]$left
            }
        }
    }
}

$Timer = New-Object Windows.Threading.DispatcherTimer
$Timer.Interval = [TimeSpan]::FromMilliseconds(250)
$Timer.Add_Tick({ Invoke-Tick })
$Timer.Start()

$Win.Add_ContentRendered({
    $Win.Activate() | Out-Null
    $Win.Focus() | Out-Null
    Start-Current
})

$Win.ShowDialog() | Out-Null

Write-Log '退出'
