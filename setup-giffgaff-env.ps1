<#
.SYNOPSIS
  giffgaff eSIM 环境一键配置脚本（交互式向导版）
.DESCRIPTION
  在 MuMu 5 模拟器中自动搭建 giffgaff eSIM 环境：
  Root -> Kitsune Mask -> Zygisk -> LSPosed -> HookEuicc -> giffgaff 登录页
  支持全自动下载工具包、交互式选择实例，也支持 AI Agent 非交互调用。
#>
param(
  [string]$ToolDir = "",
  [int]$VmIndex = -1,
  [string]$MuMuDir = "",
  [switch]$NonInteractive,
  [switch]$SkipDownload,
  [switch]$NoAcceptGiffgaffTerms
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# 修复中文显示
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# ========== URL 配置 ==========
$Urls = @{
  MuMuDownload  = "https://www.mumuplayer.com/download/"
  LSPosed       = "https://github.com/LSPosed/LSPosed/releases/download/v1.9.2/LSPosed-v1.9.2-7024-zygisk-release.zip"
  HookEuiccAPI  = "https://api.github.com/repos/Unicorn369/HookEuicc/releases/latest"
  HookEuiccPage = "https://github.com/Unicorn369/HookEuicc/releases"
  Via           = "https://res.viayoo.com/v1/via-release.apk"
  Giffgaff      = "https://mi9.com/package/com.giffgaffmobile.controller/download/"
  GiffgaffAlt   = "https://my-giffgaff.en.uptodown.com/android/download"
  KitsuneMask   = "https://sourceforge.net/projects/magisk/files/Magisk%20Delta%20(Kitsune%20Mask)/Magisk%20Delta%20Kitsune%2027.001%20Canary.apk/download"
  KitsuneMaskAlt = "https://sourceforge.net/projects/magisk/files/Magisk%20Delta%20(Kitsune%20Mask)/"
}

# ========== 日志 ==========
$ScriptRoot = $PSScriptRoot
if (-not $ScriptRoot) { $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
$LogDir = Join-Path $ScriptRoot "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = Join-Path $LogDir ("setup-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))

function Write-Step {
  param([string]$Message)
  $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Message
  Write-Host $line
  Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
}

function Write-WarnLine {
  param([string]$Message)
  Write-Host "  [!] $Message" -ForegroundColor Yellow
  Add-Content -LiteralPath $LogFile -Value "[WARN] $Message" -Encoding UTF8
}

function Write-OK {
  param([string]$Message)
  Write-Host "  [OK] $Message" -ForegroundColor Green
  Add-Content -LiteralPath $LogFile -Value "[OK] $Message" -Encoding UTF8
}

function Fail {
  param([string]$Message)
  Write-Host ""
  Write-Host "  [X] $Message" -ForegroundColor Red
  Add-Content -LiteralPath $LogFile -Value "[FAIL] $Message" -Encoding UTF8
  Write-Host ""
  Write-Host "  日志文件: $LogFile" -ForegroundColor Cyan
  if (-not $NonInteractive) { Read-Host "按回车键退出" }
  exit 1
}

# ========== 通用命令执行 ==========
function Invoke-Cmd {
  param(
    [string]$FilePath,
    [string[]]$Arguments,
    [switch]$AllowFailure
  )
  $argText = $Arguments -join " "
  Add-Content -LiteralPath $LogFile -Value "`n> $FilePath $argText" -Encoding UTF8
  $oldEAP = $ErrorActionPreference
  if ($AllowFailure) { $ErrorActionPreference = "Continue" }
  try {
    $output = & $FilePath @Arguments 2>&1
    $code = $LASTEXITCODE
  } catch {
    if (-not $AllowFailure) { throw }
    $output = $_.Exception.Message
    $code = 1
  } finally {
    $ErrorActionPreference = $oldEAP
  }
  $outputText = ($output | Out-String)
  if ($output) { Add-Content -LiteralPath $LogFile -Value $outputText -Encoding UTF8 }
  if ($code -ne 0 -and $outputText -match "file pushed|files pushed|pushed") { $code = 0 }
  if ($code -ne 0 -and -not $AllowFailure) {
    throw "Command failed: $FilePath $argText`n$outputText"
  }
  return $outputText
}

# ========== 文件查找 ==========
function Find-FirstFile {
  param([string[]]$Patterns, [string]$Dir)
  foreach ($pattern in $Patterns) {
    $file = Get-ChildItem -LiteralPath $Dir -File -Filter $pattern -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending |
      Select-Object -First 1
    if ($file) { return $file.FullName }
  }
  return $null
}

# ========== MuMu 检测 ==========
function Find-MuMuDir {
  if ($MuMuDir -and (Test-Path -LiteralPath (Join-Path $MuMuDir "mumu-cli.exe"))) { return $MuMuDir }
  $candidates = @(
    "D:\Program Files\Netease\MuMuPlayer\nx_main",
    "C:\Program Files\Netease\MuMuPlayer\nx_main",
    "C:\Program Files (x86)\Netease\MuMuPlayer\nx_main",
    "$env:LOCALAPPDATA\Netease\MuMuPlayer\nx_main",
    "D:\Netease\MuMuPlayer\nx_main",
    "C:\Netease\MuMuPlayer\nx_main"
  )
  foreach ($dir in $candidates) {
    if (Test-Path -LiteralPath (Join-Path $dir "mumu-cli.exe")) { return $dir }
  }
  # 深度搜索（仅扫描 Program Files 级别，避免全盘扫描过慢）
  $searchRoots = @("C:\Program Files", "C:\Program Files (x86)", "D:\Program Files", "D:\")
  foreach ($root in $searchRoots) {
    if (-not (Test-Path $root)) { continue }
    $found = Get-ChildItem -Path $root -Recurse -Filter "mumu-cli.exe" -ErrorAction SilentlyContinue -Depth 5 |
      Where-Object { $_.FullName -like "*MuMuPlayer*nx_main*" } |
      Select-Object -First 1
    if ($found) { return $found.DirectoryName }
  }
  return $null
}

function ConvertFrom-MuMuJson {
  param([string]$Text)
  $start = $Text.IndexOf("{")
  if ($start -lt 0) { return $null }
  return $Text.Substring($start) | ConvertFrom-Json
}

function Get-AllVmIndices {
  $indices = @()
  for ($i = 0; $i -lt 10; $i++) {
    try {
      $out = Invoke-Cmd $script:MuMuCli @("info", "--vmindex", "$i") -AllowFailure
      $info = ConvertFrom-MuMuJson $out
      if ($info -and $info.error_code -eq 0) {
        $indices += [pscustomobject]@{
          Index = $i
          Name = $info.name
          IsMain = $info.is_main
          IsRunning = $info.is_android_started
          DiskSize = if ($info.disk_size_bytes) { "{0:N0} MB" -f ($info.disk_size_bytes / 1MB) } else { "N/A" }
        }
      }
    } catch { break }
  }
  return $indices
}

# ========== ADB ==========
function Wait-AndroidStarted {
  param([int]$TimeoutSec = 120)
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  while ((Get-Date) -lt $deadline) {
    try {
      $info = Get-MuMuInfo
      if ($info -and $info.is_android_started -eq $true -and $info.adb_port -and $info.player_state -eq "start_finished") {
        $script:AdbSerial = "{0}:{1}" -f $info.adb_host_ip, $info.adb_port
        Write-Step "Android 已启动, ADB: $script:AdbSerial"
        return $info
      }
    } catch {
      Add-Content -LiteralPath $LogFile -Value "[wait] $($_.Exception.Message)" -Encoding UTF8
    }
    Start-Sleep -Seconds 3
  }
  Fail "等待 MuMu Android 启动超时。"
}

function Get-MuMuInfo {
  $out = Invoke-Cmd $script:MuMuCli @("info", "--vmindex", "$VmIndex")
  return ConvertFrom-MuMuJson $out
}

function Adb {
  param([string[]]$Arguments, [switch]$AllowFailure)
  return Invoke-Cmd -FilePath $script:AdbExe -Arguments (@("-s", $script:AdbSerial) + $Arguments) -AllowFailure:$AllowFailure
}

function Adb-Push {
  param([string]$Source, [string]$Destination)
  $out = Invoke-Cmd -FilePath $script:AdbExe -Arguments @("-s", $script:AdbSerial, "push", $Source, $Destination) -AllowFailure
  if ($out -notmatch "file pushed|files pushed|pushed") {
    Fail "ADB push 失败: $Source -> $Destination`n$out"
  }
}

function Ensure-Adb {
  Invoke-Cmd -FilePath $script:AdbExe -Arguments @("start-server") -AllowFailure | Out-Null
  Invoke-Cmd -FilePath $script:AdbExe -Arguments @("connect", $script:AdbSerial) -AllowFailure | Out-Null
  Start-Sleep -Seconds 2
  Invoke-Cmd -FilePath $script:AdbExe -Arguments @("-s", $script:AdbSerial, "root") -AllowFailure | Out-Null
  Start-Sleep -Seconds 2
  Invoke-Cmd -FilePath $script:AdbExe -Arguments @("connect", $script:AdbSerial) -AllowFailure | Out-Null
  $deadline = (Get-Date).AddSeconds(45)
  while ((Get-Date) -lt $deadline) {
    $boot = (Adb -Arguments @("shell", "getprop", "sys.boot_completed") -AllowFailure).Trim()
    if ($boot -match "1") {
      $id = (Adb -Arguments @("shell", "id") -AllowFailure).Trim()
      if ($id -match "uid=0") { return }
      Invoke-Cmd -FilePath $script:AdbExe -Arguments @("-s", $script:AdbSerial, "root") -AllowFailure | Out-Null
    }
    Start-Sleep -Seconds 3
  }
  Fail "ADB 已连接，但 Android 启动/root 状态未就绪。"
}

# ========== UI 自动化 ==========
function Launch-App {
  param([string]$Package)
  $resolved = Adb @("shell", "cmd", "package", "resolve-activity", "--brief", $Package) -AllowFailure
  $activity = ($resolved -split "`r?`n" | Where-Object { $_ -match "^[A-Za-z0-9_.]+/[A-Za-z0-9_.$]+" } | Select-Object -Last 1)
  if ($activity) {
    Adb @("shell", "am", "start", "-n", $activity.Trim()) -AllowFailure | Out-Null
  } else {
    Adb @("shell", "monkey", "-p", $Package, "-c", "android.intent.category.LAUNCHER", "1") -AllowFailure | Out-Null
  }
  Start-Sleep -Seconds 2
}

function Get-UiXml {
  Adb @("shell", "uiautomator", "dump", "/sdcard/window.xml") -AllowFailure | Out-Null
  $raw = Adb @("shell", "cat", "/sdcard/window.xml") -AllowFailure
  try {
    return [xml]$raw
  } catch {
    Add-Content -LiteralPath $LogFile -Value $raw -Encoding UTF8
    throw "无法解析 Android UI XML。"
  }
}

function Get-Attr {
  param($Node, [string]$Name)
  return $Node.GetAttribute($Name)
}

function Get-CenterFromBounds {
  param([string]$Bounds)
  if ($Bounds -notmatch "\[(\d+),(\d+)\]\[(\d+),(\d+)\]") {
    throw "无法解析 bounds: $Bounds"
  }
  $x = [int](([int]$Matches[1] + [int]$Matches[3]) / 2)
  $y = [int](([int]$Matches[2] + [int]$Matches[4]) / 2)
  return @($x, $y)
}

function Tap-Point {
  param([int]$X, [int]$Y)
  Adb @("shell", "input", "tap", "$X", "$Y") -AllowFailure | Out-Null
  Start-Sleep -Milliseconds 700
}

function Find-UiNode {
  param(
    [xml]$Xml,
    [string]$Pattern,
    [switch]$IncludeContentDesc,
    [switch]$OnlyEnabled
  )
  foreach ($node in $Xml.SelectNodes("//*")) {
    if ($OnlyEnabled -and (Get-Attr $node "enabled") -eq "false") { continue }
    $text = Get-Attr $node "text"
    $desc = Get-Attr $node "content-desc"
    $rid = Get-Attr $node "resource-id"
    $hay = if ($IncludeContentDesc) { "$text $desc $rid" } else { "$text $rid" }
    if ($hay -match $Pattern -and (Get-Attr $node "bounds")) { return $node }
  }
  return $null
}

function Tap-Ui {
  param(
    [string]$Pattern,
    [string]$Label,
    [int]$TimeoutSec = 12,
    [switch]$IncludeContentDesc
  )
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  while ((Get-Date) -lt $deadline) {
    $xml = Get-UiXml
    $node = Find-UiNode $xml $Pattern -IncludeContentDesc:$IncludeContentDesc -OnlyEnabled
    if ($node) {
      $center = Get-CenterFromBounds (Get-Attr $node "bounds")
      Write-Step "  点击: $Label"
      Tap-Point $center[0] $center[1]
      return $true
    }
    Start-Sleep -Seconds 1
  }
  Write-WarnLine "未找到 UI 元素: $Label"
  return $false
}

function Ui-Contains {
  param([string]$Pattern)
  $xml = Get-UiXml
  foreach ($node in $xml.SelectNodes("//*")) {
    $hay = "{0} {1} {2}" -f (Get-Attr $node "text"), (Get-Attr $node "content-desc"), (Get-Attr $node "resource-id")
    if ($hay -match $Pattern) { return $true }
  }
  return $false
}

function Test-MagiskBinary {
  $out = Adb -Arguments @("shell", "command -v magisk >/dev/null 2>&1 && echo yes || echo no") -AllowFailure
  return ($out -match "yes")
}

function Scroll-Down {
  Adb @("shell", "input", "swipe", "450", "1300", "450", "350", "700") -AllowFailure | Out-Null
  Start-Sleep -Milliseconds 900
}

function Get-RowSwitchInfo {
  param([xml]$Xml, [string]$TextPattern, [string]$Label)
  $xml = $Xml
  $node = Find-UiNode $xml $TextPattern -IncludeContentDesc
  if (-not $node) {
    Write-WarnLine "未找到行: $Label"
    return $null
  }
  $rowBounds = Get-Attr $node "bounds"
  if ($rowBounds -notmatch "\[(\d+),(\d+)\]\[(\d+),(\d+)\]") {
    Write-WarnLine "无法解析行 bounds: $Label"
    return $null
  }
  $rowLeft = [int]$Matches[1]
  $rowTop = [int]$Matches[2]
  $rowRight = [int]$Matches[3]
  $rowBottom = [int]$Matches[4]
  $rowCenterY = [int](($rowTop + $rowBottom) / 2)
  $rowMidX = [int](($rowLeft + $rowRight) / 2)
  $switchNode = $null
  $fallbackSwitchNode = $null
  foreach ($candidate in $xml.SelectNodes("//*")) {
    $class = Get-Attr $candidate "class"
    $checkable = Get-Attr $candidate "checkable"
    $enabled = Get-Attr $candidate "enabled"
    $bounds = Get-Attr $candidate "bounds"
    if (-not $bounds) { continue }
    if ($bounds -notmatch "\[(\d+),(\d+)\]\[(\d+),(\d+)\]") { continue }
    $left = [int]$Matches[1]
    $top = [int]$Matches[2]
    $right = [int]$Matches[3]
    $bottom = [int]$Matches[4]
    $centerY = [int](($top + $bottom) / 2)
    $sameRow = $centerY -ge ($rowTop - 24) -and $centerY -le ($rowBottom + 24)
    $isSwitch = $class -match "Switch|CheckBox" -or $checkable -eq "true"
    $isRightSide = $left -gt $rowMidX
    if ($sameRow -and $isSwitch -and $enabled -ne "false") {
      if ($isRightSide) { $switchNode = $candidate; break }
      if (-not $fallbackSwitchNode) { $fallbackSwitchNode = $candidate }
    }
  }
  if (-not $switchNode) { $switchNode = $fallbackSwitchNode }
  return [pscustomobject]@{
    RowRight = $rowRight
    RowCenterY = $rowCenterY
    SwitchNode = $switchNode
  }
}

function Set-RowSwitch {
  param([string]$TextPattern, [string]$Label, [bool]$Enabled = $true)
  $xml = Get-UiXml
  $info = Get-RowSwitchInfo $xml $TextPattern $Label
  if (-not $info) { return $false }
  if ($info.SwitchNode) {
    $checked = (Get-Attr $info.SwitchNode "checked") -eq "true"
    if ($checked -eq $Enabled) {
      $stateText = if ($Enabled) { "已开启" } else { "已关闭" }
      Write-Step "  $Label $stateText"
      return $true
    }
  }
  Write-Step "  切换: $Label"
  if ($info.SwitchNode) {
    $switchCenter = Get-CenterFromBounds (Get-Attr $info.SwitchNode "bounds")
    Tap-Point $switchCenter[0] $switchCenter[1]
  } else {
    $fallbackX = [int]($info.RowRight - 60)
    Tap-Point $fallbackX $info.RowCenterY
  }
  return $true
}

function Grant-RootIfPrompt {
  $xml = Get-UiXml
  if ($xml.OuterXml -match "superuser|\u8D85\u7D1A\u4F7F\u7528\u8005|\u8D85\u7EA7\u4F7F\u7528\u8005|\u5141\u8A31|\u5141\u8BB8") {
    Tap-Ui "remember_forever|\u6C38\u9060\u8A18\u4F4F|\u6C38\u8FDC\u8BB0\u4F4F" "记住root授权" -IncludeContentDesc | Out-Null
    Tap-Ui "allow|\u5141\u8A31|\u5141\u8BB8" "允许root授权" -IncludeContentDesc | Out-Null
    Start-Sleep -Seconds 1
  }
}

function Install-Apk {
  param([string]$Path, [string]$Label)
  if (-not (Test-Path -LiteralPath $Path)) { Fail "$Label 文件未找到: $Path" }
  Write-Step "  安装 $Label ..."
  $out = Adb @("install", "-r", $Path) -AllowFailure
  if ($out -notmatch "Success") { throw "$Label 安装失败: $out" }
  Write-OK "$Label 安装成功"
}

# ========== 交互式向导 ==========
function Show-Banner {
  Write-Host ""
  Write-Host "  ============================================" -ForegroundColor Cyan
  Write-Host "    giffgaff eSIM 环境一键配置工具 v2.0" -ForegroundColor Cyan
  Write-Host "    MuMu 5 + Kitsune Mask + LSPosed + HookEuicc" -ForegroundColor Cyan
  Write-Host "  ============================================" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "  本脚本将自动完成以下步骤:" -ForegroundColor White
  Write-Host "    1. 启动 MuMu 模拟器并开启 Root"
  Write-Host "    2. 安装 Kitsune Mask (Magisk) 并开启 Zygisk"
  Write-Host "    3. 安装 LSPosed 框架"
  Write-Host "    4. 配置 HookEuicc 模块 (Hook 电话服务和 giffgaff)"
  Write-Host "    5. 打开 giffgaff 到登录页"
  Write-Host ""
  Write-Host "  之后你需要手动完成: 登录/验证码/选套餐/付款/购买 eSIM" -ForegroundColor Yellow
  Write-Host ""
}

function Select-MuMuDir {
  Write-Step "检测 MuMu Player 安装位置..."
  $dir = Find-MuMuDir
  if ($dir) {
    Write-OK "MuMu 安装目录: $dir"
    return $dir
  }
  Write-WarnLine "未自动找到 MuMu Player"
  if ($NonInteractive) {
    Start-Process $Urls.MuMuDownload
    Fail "未找到 MuMu Player，已打开下载页面，请安装后重试。也可用 -MuMuDir 参数指定路径。"
  }
  Write-Host ""
  Write-Host "  请选择:" -ForegroundColor Yellow
  Write-Host "    1. 手动输入 MuMu 安装路径"
  Write-Host "    2. 打开 MuMu 下载页面"
  Write-Host "    3. 退出"
  $choice = Read-Host "请输入选项 (1/2/3)"
  switch ($choice) {
    "1" {
      $input = Read-Host "请输入 MuMu 安装路径 (包含 mumu-cli.exe 的目录)"
      if ($input -and (Test-Path -LiteralPath (Join-Path $input "mumu-cli.exe"))) {
        Write-OK "MuMu 安装目录: $input"
        return $input
      }
      Fail "路径无效或找不到 mumu-cli.exe: $input"
    }
    "2" {
      Start-Process $Urls.MuMuDownload
      Fail "已打开 MuMu 下载页面，请安装后重新运行本脚本。"
    }
    default { exit 0 }
  }
}

function Select-VmIndex {
  Write-Step "扫描可用的 MuMu 实例..."
  $vms = Get-AllVmIndices
  if ($vms.Count -eq 0) {
    Fail "未找到任何 MuMu 实例。请先在 MuMu Player 中创建一个新实例。"
  }
  if ($NonInteractive -and $VmIndex -ge 0) {
    $vm = $vms | Where-Object { $_.Index -eq $VmIndex }
    if (-not $vm) { Fail "指定的实例 VM $VmIndex 不存在。" }
    Write-Step "使用指定实例: VM $VmIndex ($($vm.Name))"
    return $VmIndex
  }
  Write-Host ""
  Write-Host "  可用的 MuMu 实例:" -ForegroundColor Cyan
  Write-Host ""
  foreach ($vm in $vms) {
    $mainTag = if ($vm.IsMain) { " [主实例]" } else { "" }
    $runTag = if ($vm.IsRunning) { " [运行中]" } else { "" }
    $recTag = if (-not $vm.IsMain) { " <- 推荐" } else { " (不建议在主实例操作)" }
    Write-Host ("    [{0}] {1}{2}{3}{4}  ({5})" -f $vm.Index, $vm.Name, $mainTag, $runTag, $recTag, $vm.DiskSize)
  }
  Write-Host ""
  Write-Host "  [!] 建议使用非主实例 (新建干净实例)，避免影响你的主环境" -ForegroundColor Yellow
  Write-Host ""
  $choice = Read-Host "请输入要使用的实例编号 (0-$($vms.Count - 1))"
  $idx = -1
  if ([int]::TryParse($choice, [ref]$idx) -and $vms | Where-Object { $_.Index -eq $idx }) {
    $vm = $vms | Where-Object { $_.Index -eq $idx }
    Write-OK "选择实例: VM $idx ($($vm.Name))"
    if ($vm.IsMain) {
      Write-WarnLine "你选择了主实例，脚本将修改其 root 和系统盘设置。建议改用非主实例。"
      $confirm = Read-Host "确认在主实例上操作? (y/N)"
      if ($confirm -ne "y" -and $confirm -ne "Y") { exit 0 }
    }
    return $idx
  }
  Fail "无效的实例编号: $choice"
}

function Select-ToolDir {
  if ($ToolDir -and (Test-Path $ToolDir)) {
    Write-OK "工具包目录: $ToolDir"
    return $ToolDir
  }
  $default = Join-Path $ScriptRoot "tools"
  if ($NonInteractive) {
    $ToolDir = $default
  } else {
    Write-Host ""
    Write-Host "  工具包目录 (存放 APK 和 ZIP 文件)" -ForegroundColor Cyan
    Write-Host "    默认: $default"
    $input = Read-Host "回车使用默认，或输入自定义路径"
    if ($input) {
      if (Test-Path $input) {
        $ToolDir = $input
      } else {
        Write-WarnLine "路径不存在，使用默认目录"
        $ToolDir = $default
      }
    } else {
      $ToolDir = $default
    }
  }
  New-Item -ItemType Directory -Force -Path $ToolDir | Out-Null
  Write-OK "工具包目录: $ToolDir"
  return $ToolDir
}

function Download-File {
  param([string]$Url, [string]$Path, [string]$Label)
  if (Test-Path -LiteralPath $Path) {
    Write-OK "$Label 已存在"
    return $true
  }
  if ($SkipDownload) {
    Write-WarnLine "$Label 缺失且 -SkipDownload 已启用"
    return $false
  }
  Write-Step "  下载 $Label ..."
  try {
    Invoke-WebRequest -Uri $Url -OutFile $Path -UseBasicParsing -TimeoutSec 180 -MaximumRedirection 10
    if (Test-Path -LiteralPath $Path) {
      Write-OK "$Label 下载完成"
      return $true
    }
  } catch {
    Write-WarnLine "$Label 下载失败: $($_.Exception.Message)"
  }
  return $false
}

function Download-HookEuicc {
  param([string]$Dir)
  $existing = Find-FirstFile @("HookEuicc*.apk", "*HookEuicc*.apk") $Dir
  if ($existing) { Write-OK "HookEuicc 已存在: $(Split-Path $existing -Leaf)"; return $true }
  if ($SkipDownload) { return $false }
  Write-Step "  从 GitHub 获取 HookEuicc 最新版本..."
  try {
    $release = Invoke-RestMethod -Uri $Urls.HookEuiccAPI -Headers @{"User-Agent"="PowerShell"} -TimeoutSec 30
    $asset = $release.assets | Where-Object { $_.name -like "*.apk" } | Select-Object -First 1
    if ($asset) {
      $dest = Join-Path $Dir ("HookEuicc-" + $asset.name)
      $downloaded = Download-File $asset.browser_download_url $dest "HookEuicc"
      if ($downloaded) { return $true }
    }
  } catch {
    Write-WarnLine "GitHub API 获取失败: $($_.Exception.Message)"
  }
  Write-WarnLine "HookEuicc 自动下载失败，请手动下载:"
  Write-Host "    下载页面: $($Urls.HookEuiccPage)" -ForegroundColor Cyan
  Write-Host "    放到目录: $Dir" -ForegroundColor Cyan
  return $false
}

function Wait-ForManualFile {
  param([string[]]$Patterns, [string]$Dir, [string]$Label, [string[]]$Links)
  $existing = Find-FirstFile $Patterns $Dir
  if ($existing) { Write-OK "$Label 已存在: $(Split-Path $existing -Leaf)"; return $true }
  if ($NonInteractive) {
    Write-WarnLine "$Label 缺失"
    foreach ($link in $Links) { Write-Host "    下载链接: $link" -ForegroundColor Cyan }
    return $false
  }
  Write-Host ""
  Write-Host "  [!] 缺少 $Label" -ForegroundColor Yellow
  Write-Host "  请从以下链接下载:" -ForegroundColor Yellow
  foreach ($link in $Links) {
    Write-Host "    -> $link" -ForegroundColor Cyan
  }
  Write-Host "  下载后放入: $Dir" -ForegroundColor Yellow
  Write-Host ""
  Start-Process $Links[0]
  Write-Host "  已在浏览器打开第一个链接。" -ForegroundColor Green
  $deadline = (Get-Date).AddMinutes(30)
  while ((Get-Date) -lt $deadline) {
    $existing = Find-FirstFile $Patterns $Dir
    if ($existing) { Write-OK "$Label 已就位: $(Split-Path $existing -Leaf)"; return $true }
    Write-Host -NoNewline "`r  等待文件放入 $Dir ... (Ctrl+C 取消)    "
    Start-Sleep -Seconds 3
  }
  Write-WarnLine "等待超时，未检测到 $Label"
  return $false
}

function Prepare-Tools {
  param([string]$Dir)
  Write-Step "准备工具包..."
  Write-Host ""
  Write-Host "  ---- 工具包下载/检查 ----" -ForegroundColor Cyan

  # 自动下载: LSPosed, Via, HookEuicc
  Download-File $Urls.LSPosed (Join-Path $Dir "LSPosed-v1.9.2-7024-zygisk-release.zip") "LSPosed" | Out-Null
  Download-File $Urls.Via (Join-Path $Dir "via-release.apk") "Via 浏览器" | Out-Null
  Download-HookEuicc -Dir $Dir | Out-Null

  # 引导手动下载: giffgaff, Kitsune Mask
  Wait-ForManualFile @("giffgaff*.apk", "*giffgaff*.apk") $Dir "giffgaff APK" @($Urls.Giffgaff, $Urls.GiffgaffAlt) | Out-Null
  Wait-ForManualFile @("Kitsune*.apk", "*Mask*.apk", "*magisk*.apk", "*Kitsune*.apk") $Dir "Kitsune Mask APK" @($Urls.KitsuneMask, $Urls.KitsuneMaskAlt) | Out-Null

  # 汇总检查
  $script:Files = @{
    LSPosed   = Find-FirstFile @("LSPosed-v1.9.2-7024-zygisk-release.zip") $Dir
    Via       = Find-FirstFile @("via-release.apk", "Via*.apk", "via*.apk") $Dir
    Hook      = Find-FirstFile @("HookEuicc*.apk", "*HookEuicc*.apk") $Dir
    Giffgaff  = Find-FirstFile @("giffgaff*.apk", "*giffgaff*.apk") $Dir
    Kitsune   = Find-FirstFile @("Kitsune*.apk", "*Mask*.apk", "*magisk*.apk", "*Kitsune*.apk") $Dir
  }

  Write-Host ""
  Write-Host "  ---- 工具包清单 ----" -ForegroundColor Cyan
  $labels = @{
    LSPosed  = "LSPosed 框架"
    Via      = "Via 浏览器"
    Hook     = "HookEuicc"
    Giffgaff = "giffgaff App"
    Kitsune  = "Kitsune Mask"
  }
  $missing = @()
  foreach ($key in @("LSPosed","Via","Hook","Giffgaff","Kitsune")) {
    $path = $Files[$key]
    if ($path) {
      $size = [math]::Round((Get-Item $path).Length / 1KB)
      Write-Host ("    [{0}] {1} ({2} KB)" -f "x", $labels[$key], $size) -ForegroundColor Green
    } else {
      Write-Host ("    [{0}] {1}" -f " ", $labels[$key]) -ForegroundColor Red
      $missing += $labels[$key]
    }
  }
  Write-Host ""
  if ($missing.Count -gt 0) {
    Fail "工具包不完整，缺少: $($missing -join ', ')。请将文件放入: $Dir"
  }
  Write-OK "工具包齐全"
}

function Show-Summary {
  param([string]$MuMuPath, [int]$VM, [string]$TDir)
  Write-Host ""
  Write-Host "  ============================================" -ForegroundColor Cyan
  Write-Host "  配置摘要" -ForegroundColor Cyan
  Write-Host "  ============================================" -ForegroundColor Cyan
  Write-Host "    MuMu 目录:  $MuMuPath"
  Write-Host "    实例编号:    VM $VM"
  Write-Host "    工具包目录:  $TDir"
  Write-Host "    日志文件:    $LogFile"
  Write-Host "  ============================================" -ForegroundColor Cyan
  Write-Host ""
  if (-not $NonInteractive) {
    $confirm = Read-Host "确认开始配置? (Y/n)"
    if ($confirm -eq "n" -or $confirm -eq "N") {
      Write-Host "已取消。" -ForegroundColor Yellow
      exit 0
    }
  }
}

# ========== 核心配置步骤 ==========
function Configure-MagiskAndZygisk {
  Write-Step "打开 Kitsune Mask..."
  Launch-App "io.github.huskydg.magisk"
  Grant-RootIfPrompt
  if (-not (Test-MagiskBinary)) {
    Tap-Ui "\u5B89\u88DD|\u5B89\u88C5|home_magisk_button" "Magisk 安装按钮" -IncludeContentDesc | Out-Null
    Start-Sleep -Seconds 1
    if (Ui-Contains "\u76F4\u63A5\u5B89\u88DD|\u76F4\u63A5\u5B89\u88C5") {
      if (-not (Tap-Ui "\u76F4\u63A5\u5B89\u88DD.*system|\u76F4\u63A5\u5B89\u88C5.*system" "直接安装到系统" -IncludeContentDesc)) {
        Tap-Ui "\u76F4\u63A5\u5B89\u88DD|\u76F4\u63A5\u5B89\u88C5" "直接安装" -IncludeContentDesc | Out-Null
      }
    } else {
      Fail "Kitsune 直接安装选项未出现。请检查 root 和系统盘可写设置。"
    }
    Tap-Ui "\u958B\u59CB\u57F7\u884C|\u5F00\u59CB\u6267\u884C" "开始安装" -IncludeContentDesc | Out-Null
    $deadline = (Get-Date).AddSeconds(90)
    while ((Get-Date) -lt $deadline) {
      if (Ui-Contains "All done|\u5B8C\u6210") { Write-Step "  Magisk 安装完成"; break }
      Start-Sleep -Seconds 2
    }
    Invoke-Cmd $script:MuMuCli @("control", "--vmindex", "$VmIndex", "restart") | Out-Null
    Wait-AndroidStarted | Out-Null
    Ensure-Adb
    Launch-App "io.github.huskydg.magisk"
    Grant-RootIfPrompt
  } else {
    Write-Step "  Magisk 已安装，跳过"
  }
  Write-Step "开启 Zygisk..."
  Tap-Ui "action_settings|\u8A2D\u5B9A|\u8BBE\u7F6E" "Kitsune 设置" -IncludeContentDesc | Out-Null
  for ($i = 0; $i -lt 6; $i++) {
    if (Ui-Contains "Zygisk") { break }
    Scroll-Down
  }
  if (-not (Set-RowSwitch "Zygisk" "Zygisk" $true)) {
    Fail "在 Kitsune 设置中找不到 Zygisk 开关。"
  }
  Invoke-Cmd $script:MuMuCli @("control", "--vmindex", "$VmIndex", "restart") | Out-Null
  Wait-AndroidStarted | Out-Null
  Ensure-Adb
}

function Install-LSPosedModule {
  Write-Step "安装 LSPosed 模块..."
  Adb-Push $Files.LSPosed "/sdcard/Download/LSPosed-v1.9.2-7024-zygisk-release.zip"
  $out = Adb -Arguments @("shell", "magisk", "--install-module", "/sdcard/Download/LSPosed-v1.9.2-7024-zygisk-release.zip") -AllowFailure
  if ($out -notmatch "Welcome to LSPosed|Done") {
    Fail "LSPosed 命令行安装未完成。`n$out"
  }
  Write-OK "LSPosed 模块安装完成"
  Invoke-Cmd $script:MuMuCli @("control", "--vmindex", "$VmIndex", "restart") | Out-Null
  Wait-AndroidStarted | Out-Null
  Ensure-Adb
}

function Configure-HookEuiccScope {
  Write-Step "打开 LSPosed 管理器..."
  Adb @("shell", "am", "start", "-a", "android.intent.action.MAIN", "-c", "org.lsposed.manager.LAUNCH_MANAGER", "-n", "com.android.shell/.BugreportWarningActivity") -AllowFailure | Out-Null
  Start-Sleep -Seconds 3
  if (Ui-Contains "\u6B61\u8FCE\u4F7F\u7528 LSPosed|\u6B22\u8FCE\u4F7F\u7528 LSPosed") {
    Tap-Ui "\u78BA\u5B9A|\u786E\u5B9A|OK" "关闭 LSPosed 欢迎弹窗" -IncludeContentDesc | Out-Null
  }
  if (-not (Ui-Contains "\u5DF2\u555F\u7528|\u5DF2\u542F\u7528|1\.9\.2.*Zygisk")) {
    Write-WarnLine "LSPosed 启用状态未确认，继续执行"
  }
  Tap-Ui "\u6A21\u7D44|\u6A21\u5757" "LSPosed 模块标签页" -IncludeContentDesc | Out-Null
  Tap-Ui "HookEuicc" "HookEuicc 模块详情" -IncludeContentDesc | Out-Null
  if (Ui-Contains "\u555F\u7528\u6A21\u7D44|\u542F\u7528\u6A21\u5757") {
    Set-RowSwitch "\u555F\u7528\u6A21\u7D44|\u542F\u7528\u6A21\u5757" "HookEuicc 模块开关" $true | Out-Null
  }
  Set-RowSwitch "com\.android\.phone" "电话服务作用域" $true | Out-Null
  Set-RowSwitch "com\.giffgaffmobile\.controller|giffgaff" "giffgaff 作用域" $true | Out-Null
  Invoke-Cmd $script:MuMuCli @("control", "--vmindex", "$VmIndex", "restart") | Out-Null
  Wait-AndroidStarted | Out-Null
  Ensure-Adb
}

function Enable-HookEuiccAppSwitch {
  Write-Step "打开 HookEuicc App..."
  Launch-App "cn.unicorn369.HookEuicc"
  if (Ui-Contains "LSPosed is not activated") {
    Fail "HookEuicc 提示 LSPosed 未激活。请重启 MuMu 后重新运行脚本。"
  }
  Set-RowSwitch "Hook Euicc" "HookEuicc 主开关" $true | Out-Null
}

function Open-GiffgaffToLogin {
  Write-Step "打开 giffgaff..."
  Launch-App "com.giffgaffmobile.controller"
  if (Ui-Contains "This app version is a little dated") {
    Tap-Ui "UPDATE IN 60 SECONDS" "跳过 giffgaff 更新提示" -IncludeContentDesc | Out-Null
  }
  Start-Sleep -Seconds 2
  if (-not $NoAcceptGiffgaffTerms -and (Ui-Contains "I accept the Terms and Conditions")) {
    Write-Step "  接受 giffgaff 条款并打开登录页..."
    Tap-Ui "I Accept terms and conditions|I accept the Terms" "接受条款" -IncludeContentDesc | Out-Null
    Tap-Ui "Continue|To Login" "继续到登录页" -IncludeContentDesc | Out-Null
  }
}

# ========== 主流程 ==========
try {
  Show-Banner

  # 1. 检测 MuMu
  $resolvedMuMuDir = Select-MuMuDir
  $script:MuMuCli = Join-Path $resolvedMuMuDir "mumu-cli.exe"
  $script:AdbExe = Join-Path $resolvedMuMuDir "adb.exe"
  if (-not (Test-Path -LiteralPath $script:AdbExe)) {
    Fail "找到 mumu-cli 但缺少 adb.exe: $resolvedMuMuDir"
  }
  Invoke-Cmd $script:MuMuCli @("version") | Out-Null

  # 2. 选择实例
  if ($VmIndex -ge 0) {
    Write-Step "使用指定实例: VM $VmIndex"
  } else {
    $VmIndex = Select-VmIndex
  }

  # 3. 准备工具包
  $resolvedToolDir = Select-ToolDir
  Prepare-Tools $resolvedToolDir

  # 4. 确认配置
  Show-Summary $resolvedMuMuDir $VmIndex $resolvedToolDir

  # 5. 启动 MuMu
  Write-Step "启动 MuMu VM $VmIndex ..."
  Invoke-Cmd $script:MuMuCli @("control", "--vmindex", "$VmIndex", "launch") -AllowFailure | Out-Null
  Wait-AndroidStarted | Out-Null

  # 6. 开启 root 和系统盘可写
  Write-Step "开启 Root 权限和系统盘可写..."
  Invoke-Cmd $script:MuMuCli @("setting", "--vmindex", "$VmIndex", "--key", "root_permission", "--value", "true") | Out-Null
  Invoke-Cmd $script:MuMuCli @("setting", "--vmindex", "$VmIndex", "--key", "system_disk_readonly", "--value", "false") | Out-Null
  Invoke-Cmd $script:MuMuCli @("control", "--vmindex", "$VmIndex", "restart") | Out-Null
  Wait-AndroidStarted | Out-Null
  Ensure-Adb

  # 7. 安装 APK
  Write-Step "安装 APK..."
  Install-Apk $Files.Via "Via 浏览器"
  Install-Apk $Files.Giffgaff "giffgaff"
  Install-Apk $Files.Kitsune "Kitsune Mask"
  Install-Apk $Files.Hook "HookEuicc"

  # 8. 配置 Magisk + Zygisk
  Write-Step "配置 Magisk 和 Zygisk..."
  Configure-MagiskAndZygisk

  # 9. 安装 LSPosed
  Write-Step "安装 LSPosed..."
  Install-LSPosedModule

  # 10. 配置 HookEuicc
  Write-Step "配置 HookEuicc 作用域..."
  Configure-HookEuiccScope

  # 11. 开启 HookEuicc
  Write-Step "开启 HookEuicc..."
  Enable-HookEuiccAppSwitch

  # 12. 打开 giffgaff
  Write-Step "打开 giffgaff..."
  Open-GiffgaffToLogin

  # 完成
  Write-Host ""
  Write-Host "  ============================================" -ForegroundColor Green
  Write-Host "  配置完成!" -ForegroundColor Green
  Write-Host "  ============================================" -ForegroundColor Green
  Write-Host ""
  Write-Host "  giffgaff 已打开到登录页。接下来请手动完成:" -ForegroundColor White
  Write-Host "    1. 输入 giffgaff 账号密码"
  Write-Host "    2. 输入邮箱/短信验证码"
  Write-Host "    3. 选择套餐或 eSIM"
  Write-Host "    4. 填写地址并付款"
  Write-Host "    5. 确认购买/提交"
  Write-Host ""
  Write-Host "  日志文件: $LogFile" -ForegroundColor Cyan
  Write-Host ""

} catch {
  Fail $_.Exception.Message
}
