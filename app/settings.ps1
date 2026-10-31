# ============================================================
#  运动提醒 - 设置界面
#  配置定时、休息时间、选择视频、调整播放顺序
# ============================================================

$ErrorActionPreference = 'Stop'

$AppDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProgRoot = Split-Path -Parent $AppDir
$CfgPath  = Join-Path $AppDir 'config.json'
$LogPath  = Join-Path $AppDir 'log.txt'

function Write-Log([string]$msg) {
    try {
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  [设置] $msg" |
            Out-File -FilePath $LogPath -Append -Encoding utf8
    } catch { }
}

trap {
    $m = ($_ | Out-String)
    Write-Log "[FATAL] $m"
    try {
        [System.Windows.MessageBox]::Show("设置界面出错：`n`n$($_.Exception.Message)`n`n详见 log.txt", '运动提醒', 'OK', 'Error') | Out-Null
    } catch { }
    exit 1
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# ---------------- 配置 ----------------
if (-not (Test-Path -LiteralPath $CfgPath)) {
    [System.Windows.MessageBox]::Show("找不到 config.json，请确认程序文件完整。", '运动提醒', 'OK', 'Error') | Out-Null
    exit 1
}

$Cfg = Get-Content -LiteralPath $CfgPath -Raw -Encoding UTF8 | ConvertFrom-Json

$script:VideoDirRaw = [string]$Cfg.videoDir
if ([string]::IsNullOrWhiteSpace($script:VideoDirRaw)) { $script:VideoDirRaw = 'videos' }
if ([System.IO.Path]::IsPathRooted($script:VideoDirRaw)) {
    $script:VideoDir = [System.IO.Path]::GetFullPath($script:VideoDirRaw)
} else {
    $script:VideoDir = [System.IO.Path]::GetFullPath((Join-Path $ProgRoot $script:VideoDirRaw))
}

$script:KeepFocus = if ($null -ne $Cfg.keepFocus) { [bool]$Cfg.keepFocus } else { $true }
$script:HoldSec   = if ($null -ne $Cfg.emergencyHoldSeconds) { [int]$Cfg.emergencyHoldSeconds } else { 60 }
$script:PauseLimit = if ($null -ne $Cfg.pauseLimitSeconds) { [int]$Cfg.pauseLimitSeconds } else { 300 }
$script:Exts      = @('.mp4', '.m4v', '.mov', '.wmv', '.avi', '.mkv', '.webm')

$script:GapSec = if ($null -ne $Cfg.gapSeconds) { [int]$Cfg.gapSeconds } else { 10 }

$script:Times = @()
if ($Cfg.schedule) {
    if ($Cfg.schedule.times) {
        $script:Times = @($Cfg.schedule.times | ForEach-Object { [string]$_ })
    } elseif ($Cfg.schedule.firstTime) {
        $t0 = [DateTime]::ParseExact([string]$Cfg.schedule.firstTime, 'HH:mm', [Globalization.CultureInfo]::InvariantCulture)
        $iv = if ($Cfg.schedule.intervalMinutes) { [int]$Cfg.schedule.intervalMinutes } else { 180 }
        $n  = if ($Cfg.schedule.repeatCount) { [int]$Cfg.schedule.repeatCount } else { 5 }
        for ($i = 0; $i -lt $n; $i++) { $script:Times += $t0.AddMinutes($i * $iv).ToString('HH:mm') }
    }
}
if ($script:Times.Count -eq 0) {
    $script:Times = @('09:00', '12:00', '15:00', '18:00', '21:00')
}

# ---------------- 界面 ----------------
$Xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="运动提醒 设置"
        WindowStyle="None" ResizeMode="NoResize"
        Width="980" Height="700"
        WindowStartupLocation="CenterScreen"
        Background="#FF1A1A1A"
        FontFamily="Microsoft YaHei UI">
  <Window.Resources>
    <Style x:Key="FlatBtn" TargetType="Button">
      <Setter Property="Foreground" Value="#FFE0E0E0"/>
      <Setter Property="Background" Value="#FF2C2C2C"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Background="{TemplateBinding Background}" CornerRadius="6">
              <Grid>
                <Border x:Name="hl" Background="#00FFFFFF" CornerRadius="6"/>
                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Grid>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="hl" Property="Background" Value="#1FFFFFFF"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="hl" Property="Background" Value="#38FFFFFF"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="hl" Property="Background" Value="#B3000000"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="InputBox" TargetType="TextBox">
      <Setter Property="Background" Value="#FF101010"/>
      <Setter Property="Foreground" Value="#FFE8E8E8"/>
      <Setter Property="BorderBrush" Value="#33FFFFFF"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="8,5"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
      <Setter Property="CaretBrush" Value="#FF5DCAA5"/>
    </Style>
  </Window.Resources>

  <Border BorderBrush="#33FFFFFF" BorderThickness="1">
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="46"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="82"/>
      </Grid.RowDefinitions>

      <Grid x:Name="TitleBar" Grid.Row="0" Background="#FF212121">
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="18,0,0,0">
          <TextBlock Text="运动提醒" FontSize="14" FontWeight="500" Foreground="#FFF0F0F0"/>
          <TextBlock Text="设置" FontSize="12" Foreground="#FF7A7A7A" Margin="8,1,0,0"/>
        </StackPanel>
        <Button x:Name="CloseBtn" Content="×" Width="44" Height="46" HorizontalAlignment="Right"
                Style="{StaticResource FlatBtn}" Background="Transparent" Foreground="#FF9A9A9A" FontSize="16"/>
      </Grid>

      <Grid Grid.Row="1" Margin="20,18,20,0">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="330"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <StackPanel Grid.Column="0" Margin="0,0,22,0">
          <TextBlock Text="定时" Foreground="#FF7A7A7A" FontSize="12" Margin="0,0,0,12"/>

          <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
            <TextBox x:Name="StartBox" Width="62" Style="{StaticResource InputBox}"/>
            <TextBlock Text="起，每" Margin="6,0,6,0" Foreground="#FF9A9A9A" FontSize="12" VerticalAlignment="Center"/>
            <TextBox x:Name="StepBox" Width="44" Style="{StaticResource InputBox}"/>
            <TextBlock Text="小时，共" Margin="6,0,6,0" Foreground="#FF9A9A9A" FontSize="12" VerticalAlignment="Center"/>
            <TextBox x:Name="NumBox" Width="44" Style="{StaticResource InputBox}"/>
            <TextBlock Text="次" Margin="6,0,0,0" Foreground="#FF9A9A9A" FontSize="12" VerticalAlignment="Center"/>
          </StackPanel>

          <Button x:Name="GenBtn" Content="生成时间点" Width="104" Height="30" HorizontalAlignment="Left"
                  Style="{StaticResource FlatBtn}" Margin="0,0,0,12"/>

          <TextBlock Text="弹出时间 · 一行一个，可直接改" Foreground="#FF6E6E6E" FontSize="11" Margin="0,0,0,6"/>

          <TextBox x:Name="TimesArea" Height="132" Style="{StaticResource InputBox}"
                   AcceptsReturn="True" VerticalScrollBarVisibility="Auto"
                   VerticalContentAlignment="Top" HorizontalContentAlignment="Left"/>

          <TextBlock x:Name="TimesInfo" Foreground="#FF5E5E5E" FontSize="11" Margin="0,7,0,0"/>

          <TextBlock Text="播放" Foreground="#FF7A7A7A" FontSize="12" Margin="0,24,0,12"/>

          <StackPanel Orientation="Horizontal" Margin="0,0,0,9">
            <TextBlock Text="视频间休息" Width="74" Foreground="#FFCFCFCF" FontSize="13" VerticalAlignment="Center"/>
            <TextBox x:Name="GapBox" Width="74" Style="{StaticResource InputBox}"/>
            <TextBlock Text="秒" Margin="8,0,0,0" Foreground="#FF7A7A7A" FontSize="12" VerticalAlignment="Center"/>
          </StackPanel>

          <StackPanel Orientation="Horizontal" Margin="0,0,0,9">
            <TextBlock Text="紧急退出" Width="74" Foreground="#FFCFCFCF" FontSize="13" VerticalAlignment="Center"/>
            <TextBox x:Name="HoldBox" Width="74" Style="{StaticResource InputBox}"/>
            <TextBlock Text="秒" Margin="8,0,0,0" Foreground="#FF7A7A7A" FontSize="12" VerticalAlignment="Center"/>
          </StackPanel>
          <TextBlock Text="按住 Esc 满这个秒数才强制退出" Foreground="#FF5E5E5E" FontSize="11" Margin="74,0,0,0"/>

          <StackPanel Orientation="Horizontal" Margin="0,14,0,9">
            <TextBlock Text="暂停上限" Width="74" Foreground="#FFCFCFCF" FontSize="13" VerticalAlignment="Center"/>
            <TextBox x:Name="PauseBox" Width="74" Style="{StaticResource InputBox}"/>
            <TextBlock Text="秒" Margin="8,0,0,0" Foreground="#FF7A7A7A" FontSize="12" VerticalAlignment="Center"/>
          </StackPanel>
          <TextBlock Text="暂停超时自动继续，填 0 表示不限制" Foreground="#FF5E5E5E" FontSize="11" Margin="74,0,0,0"/>
        </StackPanel>

        <Grid Grid.Column="1">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>

          <Grid Grid.Row="0" Margin="0,0,0,12">
            <TextBlock Text="视频列表" Foreground="#FF7A7A7A" FontSize="12" VerticalAlignment="Center"/>
            <TextBlock Text="勾选要播放的 · 按住拖动调顺序" Foreground="#FF565656" FontSize="11"
                       HorizontalAlignment="Right" VerticalAlignment="Center"/>
          </Grid>

          <Border Grid.Row="1" Background="#FF141414" CornerRadius="8" Padding="8">
            <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
              <StackPanel x:Name="ListPanel"/>
            </ScrollViewer>
          </Border>

          <Grid Grid.Row="2" Margin="0,10,0,0">
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Left">
              <Button x:Name="AllBtn" Content="全选" Width="72" Height="30" Style="{StaticResource FlatBtn}"/>
              <Button x:Name="NoneBtn" Content="全不选" Width="84" Height="30" Margin="8,0,0,0" Style="{StaticResource FlatBtn}"/>
            </StackPanel>
            <TextBlock x:Name="SummaryText" HorizontalAlignment="Right" VerticalAlignment="Center"
                       Foreground="#FF8A8A8A" FontSize="12"/>
          </Grid>
        </Grid>
      </Grid>

      <Grid Grid.Row="2" Margin="20,0,20,0">
        <TextBlock x:Name="StatusText" VerticalAlignment="Center" HorizontalAlignment="Left"
                   Foreground="#FF6E6E6E" FontSize="12"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
          <Button x:Name="SaveBtn" Content="保存并应用定时" Width="152" Height="42" Style="{StaticResource FlatBtn}"/>
          <Button x:Name="StartBtn" Content="开始运动" Width="134" Height="42" Margin="12,0,0,0"
                  Style="{StaticResource FlatBtn}" Background="#FF1D9E75" Foreground="White" FontSize="15"/>
        </StackPanel>
      </Grid>
    </Grid>
  </Border>
</Window>
'@

$Win = [Windows.Markup.XamlReader]::Parse($Xaml)

function Get-Ctrl([string]$Name) {
    $c = $null
    try { $c = $Win.FindName($Name) } catch { }
    if (-not $c) { try { if ($Win.Content) { $c = $Win.Content.FindName($Name) } } catch { } }
    return $c
}

$TitleBar    = Get-Ctrl 'TitleBar'
$CloseBtn    = Get-Ctrl 'CloseBtn'
$StartBox    = Get-Ctrl 'StartBox'
$StepBox     = Get-Ctrl 'StepBox'
$NumBox      = Get-Ctrl 'NumBox'
$GenBtn      = Get-Ctrl 'GenBtn'
$TimesArea   = Get-Ctrl 'TimesArea'
$TimesInfo   = Get-Ctrl 'TimesInfo'
$GapBox      = Get-Ctrl 'GapBox'
$HoldBox     = Get-Ctrl 'HoldBox'
$PauseBox    = Get-Ctrl 'PauseBox'
$ListPanel   = Get-Ctrl 'ListPanel'
$AllBtn      = Get-Ctrl 'AllBtn'
$NoneBtn     = Get-Ctrl 'NoneBtn'
$SummaryText = Get-Ctrl 'SummaryText'
$StatusText  = Get-Ctrl 'StatusText'
$SaveBtn     = Get-Ctrl 'SaveBtn'
$StartBtn    = Get-Ctrl 'StartBtn'

if (-not $ListPanel -or -not $StartBtn) {
    Write-Log '控件加载失败'
    [System.Windows.MessageBox]::Show("界面控件加载失败，详见 log.txt", '运动提醒', 'OK', 'Error') | Out-Null
    exit 1
}

# ---------------- 颜色 ----------------
function New-Brush([string]$hex) {
    $color = [Windows.Media.ColorConverter]::ConvertFromString($hex)
    return New-Object Windows.Media.SolidColorBrush -ArgumentList $color
}

$script:BrushText  = New-Brush '#FFE8E8E8'
$script:BrushMuted = New-Brush '#FF8A8A8A'
$script:BrushRow   = New-Brush '#FF1E1E1E'
$script:BrushRowOver = New-Brush '#FF2A2A2A'
$script:BrushOk    = New-Brush '#FF5DCAA5'
$script:BrushWarn  = New-Brush '#FFE07A5F'

# ---------------- 数据 ----------------
$script:Items    = @()
$script:Shell    = New-Object -ComObject Shell.Application
$script:CachedDir = ''
$script:CachedFolder = $null
$script:dragFrom = -1
$script:dragY    = 0.0

function Format-Duration($ts) {
    if ($null -eq $ts) { return '--:--' }
    if ($ts.TotalHours -ge 1) { return $ts.ToString('h\:mm\:ss') }
    return $ts.ToString('mm\:ss')
}

function Get-VideoDuration([string]$fullPath) {
    try {
        $dir  = [System.IO.Path]::GetDirectoryName($fullPath)
        $leaf = [System.IO.Path]::GetFileName($fullPath)
        if ($script:CachedDir -ne $dir) {
            $script:CachedDir    = $dir
            $script:CachedFolder = $script:Shell.Namespace($dir)
        }
        $folder = $script:CachedFolder
        if (-not $folder) { return $null }
        $item = $folder.ParseName($leaf)
        if (-not $item) { return $null }
        $raw = $item.ExtendedProperty('System.Media.Duration')
        if ($null -eq $raw) { return $null }
        $t = [int64]$raw
        if ($t -le 0) { return $null }
        return [TimeSpan]::FromTicks($t)
    } catch {
        return $null
    }
}

function Load-Videos {
    $script:Items = @()
    $files = @()
    if (Test-Path -LiteralPath $script:VideoDir) {
        $files = @(
            Get-ChildItem -LiteralPath $script:VideoDir -File -ErrorAction SilentlyContinue |
                Where-Object { $script:Exts -contains $_.Extension.ToLower() } |
                Sort-Object Name
        )
    }

    $saved = @()
    if ($null -ne $Cfg.playlist) { $saved = @($Cfg.playlist | ForEach-Object { [string]$_ }) }

    foreach ($f in $files) {
        $ts = Get-VideoDuration $f.FullName
        $ticks = [int64]0
        if ($null -ne $ts) { $ticks = [int64]$ts.Ticks }
        $chk = $true
        if ($saved.Count -gt 0) { $chk = ($saved -contains $f.Name) }
        $script:Items += [pscustomobject]@{
            Name         = $f.Name
            FullPath     = $f.FullName
            Checked      = $chk
            DurationText = (Format-Duration $ts)
            Ticks        = $ticks
        }
    }

    if ($saved.Count -gt 0 -and $script:Items.Count -gt 0) {
        $ordered = @()
        foreach ($n in $saved) {
            $hit = @($script:Items | Where-Object { $_.Name -eq $n })
            if ($hit.Count -gt 0 -and ($ordered -notcontains $hit[0])) { $ordered += $hit[0] }
        }
        foreach ($x in $script:Items) {
            if ($ordered -notcontains $x) { $ordered += $x }
        }
        $script:Items = $ordered
    }
}

function Update-Summary {
    $sel = @($script:Items | Where-Object { $_.Checked })
    $ticks = [int64]0
    foreach ($s in $sel) { $ticks += [int64]$s.Ticks }
    $ts = [TimeSpan]::FromTicks($ticks)
    $SummaryText.Text = "已选 $($sel.Count) / $($script:Items.Count) 个 · 合计 $(Format-Duration $ts)"
}

function Parse-Times {
    $result = @()
    $text = [string]$TimesArea.Text
    foreach ($ln in ($text -split "`r?`n")) {
        $s = $ln.Trim()
        if ($s -eq '') { continue }
        if ($s -notmatch '^\d{1,2}:\d{2}$') {
            throw "时间格式不对：$s（应该像 09:00）"
        }
        $p  = $s -split ':'
        $h  = [int]$p[0]
        $mi = [int]$p[1]
        if ($h -lt 0 -or $h -gt 23 -or $mi -lt 0 -or $mi -gt 59) {
            throw "时间超出范围：$s"
        }
        $result += ('{0:D2}:{1:D2}' -f $h, $mi)
    }
    if ($result.Count -eq 0) { throw '至少填一个时间点' }
    return @($result | Sort-Object -Unique)
}

function Update-TimesInfo {
    try {
        $t = @(Parse-Times)
        if ($t.Count -eq 1) {
            $TimesInfo.Text = "共 1 个时间点：$($t[0])"
        } else {
            $TimesInfo.Text = "共 $($t.Count) 个时间点：$($t[0]) 到 $($t[-1])"
        }
        $TimesInfo.Foreground = $script:BrushMuted
    } catch {
        $TimesInfo.Text = $_.Exception.Message
        $TimesInfo.Foreground = $script:BrushWarn
    }
}

function Generate-Times {
    if ($StartBox.Text.Trim() -notmatch '^\d{1,2}:\d{2}$') { throw '起始时间格式不对，应该像 09:00' }
    $p  = $StartBox.Text.Trim() -split ':'
    $h  = [int]$p[0]
    $mi = [int]$p[1]
    if ($h -gt 23 -or $mi -gt 59) { throw '起始时间超出范围' }

    $step = [int]$StepBox.Text
    $n    = [int]$NumBox.Text
    if ($step -lt 1)  { throw '间隔至少 1 小时' }
    if ($step -gt 24) { throw '间隔不能超过 24 小时' }
    if ($n -lt 1)     { throw '次数至少 1' }
    if ($n -gt 48)    { throw '次数最多 48 个' }

    $arr  = @()
    $base = $h * 60 + $mi
    for ($i = 0; $i -lt $n; $i++) {
        $tot = ($base + $i * $step * 60) % 1440
        $hh  = [int][math]::Floor($tot / 60)
        $mm  = [int]($tot % 60)
        $arr += ('{0:D2}:{1:D2}' -f $hh, $mm)
    }
    $TimesArea.Text = ($arr -join "`r`n")
    Update-TimesInfo
}

function Rebuild-List {
    $ListPanel.Children.Clear()

    if ($script:Items.Count -eq 0) {
        $empty = New-Object Windows.Controls.TextBlock
        $empty.Text = "videos 文件夹里还没有视频`n`n把抖音下载的 mp4 丢进：`n$($script:VideoDir)"
        $empty.Foreground = $script:BrushMuted
        $empty.FontSize = 12
        $empty.Margin = New-Object Windows.Thickness -ArgumentList 14, 20, 14, 20
        $empty.LineHeight = 22
        $ListPanel.Children.Add($empty) | Out-Null
        Update-Summary
        return
    }

    for ($i = 0; $i -lt $script:Items.Count; $i++) {
        $row = New-Row $i
        $ListPanel.Children.Add($row) | Out-Null
    }
    Update-Summary
}

function New-Row([int]$Index) {
    $it = $script:Items[$Index]

    $border = New-Object Windows.Controls.Border
    $border.CornerRadius = New-Object Windows.CornerRadius -ArgumentList 6
    $border.Padding      = New-Object Windows.Thickness -ArgumentList 10, 0, 10, 0
    $border.Height       = 40
    $border.Margin       = New-Object Windows.Thickness -ArgumentList 0, 2, 0, 2
    $border.Background   = $script:BrushRow
    $border.Tag          = $Index
    $border.AllowDrop    = $true
    $border.Cursor       = [Windows.Input.Cursors]::Hand

    $dock = New-Object Windows.Controls.DockPanel
    $dock.LastChildFill = $true

    $cb = New-Object Windows.Controls.CheckBox
    $cb.Width = 28
    $cb.VerticalAlignment = 'Center'
    $cb.IsChecked = [bool]$it.Checked
    $cb.Tag = $Index
    $cb.Cursor = [Windows.Input.Cursors]::Hand
    [Windows.Controls.DockPanel]::SetDock($cb, [Windows.Controls.Dock]::Left)
    $dock.Children.Add($cb) | Out-Null

    $dur = New-Object Windows.Controls.TextBlock
    $dur.Text = [string]$it.DurationText
    $dur.Width = 66
    $dur.FontSize = 12
    $dur.Foreground = $script:BrushMuted
    $dur.VerticalAlignment = 'Center'
    $dur.TextAlignment = 'Right'
    [Windows.Controls.DockPanel]::SetDock($dur, [Windows.Controls.Dock]::Right)
    $dock.Children.Add($dur) | Out-Null

    $nm = New-Object Windows.Controls.TextBlock
    $nm.Text = [string]$it.Name
    $nm.FontSize = 13
    $nm.Foreground = $script:BrushText
    $nm.VerticalAlignment = 'Center'
    $nm.Margin = New-Object Windows.Thickness -ArgumentList 8, 0, 8, 0
    $nm.TextTrimming = 'CharacterEllipsis'
    $dock.Children.Add($nm) | Out-Null

    $border.Child = $dock

    $cb.Add_Click({
        param($s, $e)
        $idx = [int]$s.Tag
        $script:Items[$idx].Checked = [bool]$s.IsChecked
        Update-Summary
    })

    $border.Add_MouseEnter({
        param($s, $e)
        $s.Background = $script:BrushRowOver
    })
    $border.Add_MouseLeave({
        param($s, $e)
        $s.Background = $script:BrushRow
    })

    $border.Add_PreviewMouseLeftButtonDown({
        param($s, $e)
        $script:dragFrom = [int]$s.Tag
        $script:dragY = $e.GetPosition($ListPanel).Y
    })

    $border.Add_PreviewMouseMove({
        param($s, $e)
        if ($e.LeftButton -ne [Windows.Input.MouseButtonState]::Pressed) { return }
        if ($script:dragFrom -lt 0) { return }
        if ($script:dragFrom -ne [int]$s.Tag) { return }
        $y = $e.GetPosition($ListPanel).Y
        if ([math]::Abs($y - $script:dragY) -gt 12) {
            [Windows.DragDrop]::DoDragDrop($s, $s, [Windows.DragDropEffects]::Move)
            $script:dragFrom = -1
        }
    })

    $border.Add_DragOver({
        param($s, $e)
        $e.Effects = [Windows.DragDropEffects]::Move
        $e.Handled = $true
    })

    $border.Add_Drop({
        param($s, $e)
        $from = $script:dragFrom
        $to   = [int]$s.Tag
        $script:dragFrom = -1
        if ($from -ge 0 -and $from -ne $to) { Move-Row $from $to }
        $e.Handled = $true
    })

    return $border
}

function Move-Row([int]$From, [int]$To) {
    if ($From -lt 0 -or $From -ge $script:Items.Count) { return }
    $list = New-Object System.Collections.ArrayList
    foreach ($x in $script:Items) { [void]$list.Add($x) }

    $obj = $list[$From]
    $list.RemoveAt($From)
    if ($To -gt $From) { $To = $To - 1 }
    if ($To -lt 0) { $To = 0 }
    if ($To -gt $list.Count) { $To = $list.Count }
    $list.Insert($To, $obj)

    $script:Items = @($list.ToArray())
    Rebuild-List
}

# ---------------- 配置写回 ----------------
function Save-Config {
    $times = @(Parse-Times)
    $gap = [int]$GapBox.Text
    $hold = [int]$HoldBox.Text
    $pause = [int]$PauseBox.Text
    if ($gap -lt 0)   { throw '休息时间不能是负数' }
    if ($hold -lt 1)  { throw '紧急退出秒数必须大于 0' }
    if ($pause -lt 0) { throw '暂停上限不能是负数' }

    $selNames = @($script:Items | Where-Object { $_.Checked } | ForEach-Object { [string]$_.Name })

    $cfg = [ordered]@{
        videoDir             = $script:VideoDirRaw
        gapSeconds           = $gap
        shuffle              = $false
        keepFocus            = $script:KeepFocus
        emergencyHoldSeconds = $hold
        pauseLimitSeconds    = $pause
        playlist             = $selNames
        schedule             = [ordered]@{
            times = $times
        }
    }

    ($cfg | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $CfgPath -Encoding UTF8
    Write-Log "已保存 list=$($selNames.Count) gap=$gap hold=$hold times=$($times -join ',')"
}

function Apply-Task {
    $times = @(Parse-Times)
    if ($times.Count -eq 0) { throw '没有可用的时间点' }

    $Action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument ('"' + (Join-Path $AppDir 'launch.vbs') + '" player.ps1')

    $triggers = @()
    foreach ($t in $times) {
        $dt = [DateTime]::ParseExact($t, 'HH:mm', [Globalization.CultureInfo]::InvariantCulture)
        $triggers += New-ScheduledTaskTrigger -Daily -At $dt
    }

    $Settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -ExecutionTimeLimit (New-TimeSpan -Hours 4) `
        -MultipleInstances IgnoreNew

    $Principal = New-ScheduledTaskPrincipal `
        -UserId ("$env:USERDOMAIN\$env:USERNAME") `
        -LogonType Interactive `
        -RunLevel Limited

    # 清理旧版本留下的英文任务名，避免出现两个任务
    try {
        $oldTask = Get-ScheduledTask -TaskName 'ExerciseReminder' -ErrorAction SilentlyContinue
        if ($oldTask) {
            Unregister-ScheduledTask -TaskName 'ExerciseReminder' -Confirm:$false -ErrorAction SilentlyContinue
            Write-Log '已清理旧任务 ExerciseReminder'
        }
    } catch { }

    Register-ScheduledTask -TaskName '运动提醒' -Action $Action -Trigger $triggers `
        -Settings $Settings -Principal $Principal -Force | Out-Null
}

# ---------------- 初始化 ----------------
$StartBox.Text   = if ($script:Times.Count -gt 0) { $script:Times[0] } else { '09:00' }
$StepBox.Text    = '3'
$NumBox.Text     = [string]$script:Times.Count
$TimesArea.Text  = ($script:Times -join "`r`n")
$GapBox.Text      = [string]$script:GapSec
$HoldBox.Text     = [string]$script:HoldSec
$PauseBox.Text    = [string]$script:PauseLimit

$script:Loading = $false
Load-Videos
Rebuild-List
Update-TimesInfo

# ---------------- 事件 ----------------
$TimesArea.Add_TextChanged({ if (-not $script:Loading) { Update-TimesInfo } })

$GenBtn.Add_Click({
    try {
        Generate-Times
        $StatusText.Text = '已生成时间点'
        $StatusText.Foreground = $script:BrushMuted
    } catch {
        $StatusText.Text = $_.Exception.Message
        $StatusText.Foreground = $script:BrushWarn
    }
})

$AllBtn.Add_Click({
    foreach ($it in $script:Items) { $it.Checked = $true }
    Rebuild-List
})
$NoneBtn.Add_Click({
    foreach ($it in $script:Items) { $it.Checked = $false }
    Rebuild-List
})

$TitleBar.Add_MouseLeftButtonDown({ $Win.DragMove() })
$CloseBtn.Add_Click({ $Win.Close() })

$SaveBtn.Add_Click({
    try {
        Save-Config
    } catch {
        $StatusText.Text = "保存失败：" + $_.Exception.Message
        $StatusText.Foreground = $script:BrushWarn
        Write-Log "保存失败: $($_.Exception.Message)"
        return
    }
    try {
        Apply-Task
        $StatusText.Text = '保存成功'
        $StatusText.Foreground = $script:BrushOk
        Write-Log '定时任务已更新'
    } catch {
        $StatusText.Text = "设置已保存，但定时注册失败：" + $_.Exception.Message
        $StatusText.Foreground = $script:BrushWarn
        Write-Log "注册任务失败: $($_.Exception.Message)"
    }
})

$StartBtn.Add_Click({
    try {
        $sel = @($script:Items | Where-Object { $_.Checked })
        if ($sel.Count -eq 0) {
            $StatusText.Text = "至少选一个视频"
            $StatusText.Foreground = $script:BrushWarn
            return
        }
        Save-Config
        $vbs = Join-Path $AppDir 'launch.vbs'
        Start-Process -FilePath 'wscript.exe' -ArgumentList ('"' + $vbs + '" player.ps1')
        $Win.Close()
    } catch {
        $StatusText.Text = "启动失败：" + $_.Exception.Message
        $StatusText.Foreground = $script:BrushWarn
        Write-Log "启动失败: $($_.Exception.Message)"
    }
})

$Win.ShowDialog() | Out-Null
Write-Log '设置界面关闭'
