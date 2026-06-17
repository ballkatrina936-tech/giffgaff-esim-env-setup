param(
  [string]$ToolDir = (Join-Path $PSScriptRoot "tools"),
  [int]$VmIndex = -1,
  [string]$MuMuDir = "",
  [switch]$SkipDownload,
  [switch]$NoAcceptGiffgaffTerms
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$Urls = @{
  MuMuDownload = "https://www.mumuplayer.com/download/"
  LSPosed      = "https://github.com/LSPosed/LSPosed/releases/download/v1.9.2/LSPosed-v1.9.2-7024-zygisk-release.zip"
  HookEuicc    = "https://github.com/Unicorn369/HookEuicc"
  Via          = "https://res.viayoo.com/v1/via-release.apk"
  Giffgaff     = "https://mi9.com/package/com.giffgaffmobile.controller/download/"
  KitsuneMask  = "https://mega.nz/file/DEUVTRBA#lGEogAthS3kt2YuCmi0kszwPuFV4KI0o3-hApgdBxEw"
}

$LogDir = Join-Path $PSScriptRoot "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
New-Item -ItemType Directory -Force -Path $ToolDir | Out-Null
$LogFile = Join-Path $LogDir ("setup-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))

function Write-Step {
  param([string]$Message)
  $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Message
  Write-Host $line
  Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
}

function Write-WarnLine {
  param([string]$Message)
  Write-Host "[WARN] $Message" -ForegroundColor Yellow
  Add-Content -LiteralPath $LogFile -Value "[WARN] $Message" -Encoding UTF8
}

function Fail {
  param([string]$Message)
  Write-Host ""
  Write-Host "[FAIL] $Message" -ForegroundColor Red
  Add-Content -LiteralPath $LogFile -Value "[FAIL] $Message" -Encoding UTF8
  Write-Host "Log file: $LogFile"
  exit 1
}

function Invoke-Cmd {
  param(
    [string]$FilePath,
    [string[]]$Arguments,
    [switch]$AllowFailure
  )
  $argText = $Arguments -join " "
  Add-Content -LiteralPath $LogFile -Value "`n> $FilePath $argText" -Encoding UTF8
  $oldErrorActionPreference = $ErrorActionPreference
  if ($AllowFailure) { $ErrorActionPreference = "Continue" }
  try {
    $output = & $FilePath @Arguments 2>&1
    $code = $LASTEXITCODE
  } catch {
    if (-not $AllowFailure) { throw }
    $output = $_.Exception.Message
    $code = 1
  } finally {
    $ErrorActionPreference = $oldErrorActionPreference
  }
  $outputText = ($output | Out-String)
  if ($output) { Add-Content -LiteralPath $LogFile -Value $outputText -Encoding UTF8 }
  if ($code -ne 0 -and $outputText -match "file pushed|files pushed|pushed") {
    $code = 0
  }
  if ($code -ne 0 -and -not $AllowFailure) {
    throw "Command failed: $FilePath $argText`n$outputText"
  }
  return $outputText
}

function Download-IfMissing {
  param([string]$Url, [string]$Path, [string]$Label)
  if (Test-Path -LiteralPath $Path) {
    Write-Step "$Label exists: $Path"
    return
  }
  if ($SkipDownload) {
    Write-WarnLine "$Label is missing and -SkipDownload was used: $Path"
    return
  }
  Write-Step "Downloading $Label ..."
  try {
    Invoke-WebRequest -Uri $Url -OutFile $Path -UseBasicParsing -TimeoutSec 120
    Write-Step "$Label downloaded: $Path"
  } catch {
    Write-WarnLine "$Label download failed: $($_.Exception.Message)"
  }
}

function Find-FirstFile {
  param([string[]]$Patterns)
  foreach ($pattern in $Patterns) {
    $file = Get-ChildItem -LiteralPath $ToolDir -File -Filter $pattern -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending |
      Select-Object -First 1
    if ($file) { return $file.FullName }
  }
  return $null
}

function Find-MuMuDir {
  if ($MuMuDir -and (Test-Path -LiteralPath (Join-Path $MuMuDir "mumu-cli.exe"))) { return $MuMuDir }
  $candidates = @(
    "D:\Program Files\Netease\MuMuPlayer\nx_main",
    "C:\Program Files\Netease\MuMuPlayer\nx_main",
    "C:\Program Files (x86)\Netease\MuMuPlayer\nx_main",
    "$env:LOCALAPPDATA\Netease\MuMuPlayer\nx_main"
  )
  foreach ($dir in $candidates) {
    if (Test-Path -LiteralPath (Join-Path $dir "mumu-cli.exe")) { return $dir }
  }
  $roots = @("C:\")
  if (Test-Path "D:\") { $roots += "D:\" }
  $found = Get-ChildItem -Path $roots -Recurse -Filter "mumu-cli.exe" -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -like "*MuMuPlayer*nx_main*" } |
    Select-Object -First 1
  if ($found) { return $found.DirectoryName }
  return $null
}

function ConvertFrom-MuMuJson {
  param([string]$Text)
  $start = $Text.IndexOf("{")
  if ($start -lt 0) { return $null }
  return $Text.Substring($start) | ConvertFrom-Json
}

function Get-MuMuInfo {
  $out = Invoke-Cmd $script:MuMuCli @("info", "--vmindex", "$VmIndex")
  return ConvertFrom-MuMuJson $out
}

function Wait-AndroidStarted {
  param([int]$TimeoutSec = 120)
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  while ((Get-Date) -lt $deadline) {
    try {
      $info = Get-MuMuInfo
      if ($info -and $info.is_android_started -eq $true -and $info.adb_port -and $info.player_state -eq "start_finished") {
        $script:AdbSerial = "{0}:{1}" -f $info.adb_host_ip, $info.adb_port
        Write-Step "Android started. ADB serial: $script:AdbSerial"
        return $info
      }
    } catch {
      Add-Content -LiteralPath $LogFile -Value "[wait] $($_.Exception.Message)" -Encoding UTF8
    }
    Start-Sleep -Seconds 3
  }
  Fail "Timed out while waiting for MuMu Android to start."
}

function Adb {
  param([string[]]$Arguments, [switch]$AllowFailure)
  return Invoke-Cmd -FilePath $script:AdbExe -Arguments (@("-s", $script:AdbSerial) + $Arguments) -AllowFailure:$AllowFailure
}

function Adb-Push {
  param([string]$Source, [string]$Destination)
  $out = Invoke-Cmd -FilePath $script:AdbExe -Arguments @("-s", $script:AdbSerial, "push", $Source, $Destination) -AllowFailure
  if ($out -notmatch "file pushed|files pushed|pushed") {
    Fail "ADB push failed: $Source -> $Destination`n$out"
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
  Fail "ADB connected, but Android boot/root state is not ready."
}

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
    throw "Could not parse Android UI XML."
  }
}

function Get-Attr {
  param($Node, [string]$Name)
  return $Node.GetAttribute($Name)
}

function Get-CenterFromBounds {
  param([string]$Bounds)
  if ($Bounds -notmatch "\[(\d+),(\d+)\]\[(\d+),(\d+)\]") {
    throw "Could not parse bounds: $Bounds"
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
      Write-Step "Tap: $Label"
      Tap-Point $center[0] $center[1]
      return $true
    }
    Start-Sleep -Seconds 1
  }
  Write-WarnLine "Could not find UI item: $Label"
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

function Tap-RowSwitchByText {
  param([string]$TextPattern, [string]$Label)
  $xml = Get-UiXml
  $node = Find-UiNode $xml $TextPattern -IncludeContentDesc
  if (-not $node) {
    Write-WarnLine "Could not find row: $Label"
    return $false
  }

  $rowBounds = Get-Attr $node "bounds"
  if ($rowBounds -notmatch "\[(\d+),(\d+)\]\[(\d+),(\d+)\]") {
    Write-WarnLine "Could not parse row bounds: $Label"
    return $false
  }

  $rowLeft = [int]$Matches[1]
  $rowTop = [int]$Matches[2]
  $rowRight = [int]$Matches[3]
  $rowBottom = [int]$Matches[4]
  $rowCenterY = [int](($rowTop + $rowBottom) / 2)
  $rowMidX = [int](($rowLeft + $rowRight) / 2)

  $switchNode = $null
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

    $sameRow = $centerY -ge $rowTop -and $centerY -le $rowBottom
    $isSwitch = $class -match "Switch|CheckBox" -or $checkable -eq "true"
    $isRightSide = $left -gt $rowMidX

    if ($sameRow -and $isSwitch -and $isRightSide -and $enabled -ne "false") {
      $switchNode = $candidate
      break
    }
  }

  Write-Step "Toggle: $Label"
  if ($switchNode) {
    $switchCenter = Get-CenterFromBounds (Get-Attr $switchNode "bounds")
    Tap-Point $switchCenter[0] $switchCenter[1]
  } else {
    $fallbackX = [int]($rowRight - 60)
    Tap-Point $fallbackX $rowCenterY
  }
  return $true
}

function Grant-RootIfPrompt {
  $xml = Get-UiXml
  if ($xml.OuterXml -match "superuser|\u8D85\u7D1A\u4F7F\u7528\u8005|\u8D85\u7EA7\u4F7F\u7528\u8005|\u5141\u8A31|\u5141\u8BB8") {
    Tap-Ui "remember_forever|\u6C38\u9060\u8A18\u4F4F|\u6C38\u8FDC\u8BB0\u4F4F" "Remember root grant" -IncludeContentDesc | Out-Null
    Tap-Ui "allow|\u5141\u8A31|\u5141\u8BB8" "Allow root grant" -IncludeContentDesc | Out-Null
    Start-Sleep -Seconds 1
  }
}

function Install-Apk {
  param([string]$Path, [string]$Label)
  if (-not (Test-Path -LiteralPath $Path)) { Fail "$Label file not found: $Path" }
  Write-Step "Installing $Label ..."
  $out = Adb @("install", "-r", $Path) -AllowFailure
  if ($out -notmatch "Success") { throw "$Label install failed: $out" }
}

function Ensure-RequiredFiles {
  Download-IfMissing $Urls.LSPosed (Join-Path $ToolDir "LSPosed-v1.9.2-7024-zygisk-release.zip") "LSPosed"
  Download-IfMissing $Urls.Via (Join-Path $ToolDir "via-release.apk") "Via"

  $script:Files = @{
    LSPosed  = Find-FirstFile @("LSPosed-v1.9.2-7024-zygisk-release.zip")
    Via      = Find-FirstFile @("via-release.apk", "Via*.apk", "via*.apk")
    Hook     = Find-FirstFile @("HookEuicc*.apk", "*HookEuicc*.apk")
    Giffgaff = Find-FirstFile @("giffgaff*.apk", "*giffgaff*.apk")
    Kitsune  = Find-FirstFile @("Kitsune*.apk", "*Mask*.apk", "*magisk*.apk")
  }

  $missing = @()
  if (-not $Files.Hook)     { $missing += "HookEuicc APK: $($Urls.HookEuicc)" }
  if (-not $Files.Giffgaff) { $missing += "giffgaff APK: $($Urls.Giffgaff)" }
  if (-not $Files.Kitsune)  { $missing += "Kitsune Mask APK: $($Urls.KitsuneMask)" }
  if (-not $Files.LSPosed)  { $missing += "LSPosed ZIP: $($Urls.LSPosed)" }
  if (-not $Files.Via)      { $missing += "Via APK: $($Urls.Via)" }

  if ($missing.Count -gt 0) {
    Write-Host ""
    Write-Host "Missing files. Download them into: $ToolDir" -ForegroundColor Yellow
    foreach ($m in $missing) { Write-Host "- $m" }
    Fail "Tool package is incomplete."
  }
}

function Configure-MagiskAndZygisk {
  Write-Step "Opening Kitsune Mask ..."
  Launch-App "io.github.huskydg.magisk"
  Grant-RootIfPrompt

  if (-not (Test-MagiskBinary)) {
    Tap-Ui "\u5B89\u88DD|\u5B89\u88C5|home_magisk_button" "Magisk install button" -IncludeContentDesc | Out-Null
    Start-Sleep -Seconds 1

    if (Ui-Contains "\u76F4\u63A5\u5B89\u88DD|\u76F4\u63A5\u5B89\u88C5") {
      if (-not (Tap-Ui "\u76F4\u63A5\u5B89\u88DD.*system|\u76F4\u63A5\u5B89\u88C5.*system" "Direct install to system" -IncludeContentDesc)) {
        Tap-Ui "\u76F4\u63A5\u5B89\u88DD|\u76F4\u63A5\u5B89\u88C5" "Direct install" -IncludeContentDesc | Out-Null
      }
    } else {
      Fail "Kitsune direct install option did not appear. Check root and writable system disk settings."
    }

    Tap-Ui "\u958B\u59CB\u57F7\u884C|\u5F00\u59CB\u6267\u884C" "Start Magisk install" -IncludeContentDesc | Out-Null
    $deadline = (Get-Date).AddSeconds(90)
    while ((Get-Date) -lt $deadline) {
      if (Ui-Contains "All done|\u5B8C\u6210") {
        Write-Step "Magisk install finished."
        break
      }
      Start-Sleep -Seconds 2
    }
    Invoke-Cmd $script:MuMuCli @("control", "--vmindex", "$VmIndex", "restart") | Out-Null
    Wait-AndroidStarted | Out-Null
    Ensure-Adb
    Launch-App "io.github.huskydg.magisk"
    Grant-RootIfPrompt
  } else {
    Write-Step "Magisk binary is installed. Skipping install."
  }

  if (-not (Ui-Contains "Zygisk.*\u662F")) {
    Write-Step "Enabling Zygisk ..."
    Tap-Ui "action_settings|\u8A2D\u5B9A|\u8BBE\u7F6E" "Kitsune settings" -IncludeContentDesc | Out-Null
    for ($i = 0; $i -lt 6; $i++) {
      if (Ui-Contains "Zygisk") { break }
      Scroll-Down
    }
    Tap-RowSwitchByText "Zygisk" "Zygisk" | Out-Null
    Invoke-Cmd $script:MuMuCli @("control", "--vmindex", "$VmIndex", "restart") | Out-Null
    Wait-AndroidStarted | Out-Null
    Ensure-Adb
  } else {
    Write-Step "Zygisk is already enabled."
  }
}

function Install-LSPosedModule {
  Write-Step "Installing LSPosed module ..."
  Adb-Push $Files.LSPosed "/sdcard/Download/LSPosed-v1.9.2-7024-zygisk-release.zip"
  $out = Adb -Arguments @("shell", "magisk", "--install-module", "/sdcard/Download/LSPosed-v1.9.2-7024-zygisk-release.zip") -AllowFailure
  if ($out -notmatch "Welcome to LSPosed|Done") {
    Fail "LSPosed command-line install did not finish successfully.`n$out"
  }
  Write-Step "LSPosed module install finished."
  Invoke-Cmd $script:MuMuCli @("control", "--vmindex", "$VmIndex", "restart") | Out-Null
  Wait-AndroidStarted | Out-Null
  Ensure-Adb
}

function Open-LSPosedManager {
  Write-Step "Opening LSPosed manager ..."
  Adb @("shell", "am", "start", "-a", "android.intent.action.MAIN", "-c", "org.lsposed.manager.LAUNCH_MANAGER", "-n", "com.android.shell/.BugreportWarningActivity") -AllowFailure | Out-Null
  Start-Sleep -Seconds 3
  if (Ui-Contains "\u6B61\u8FCE\u4F7F\u7528 LSPosed|\u6B22\u8FCE\u4F7F\u7528 LSPosed") {
    Tap-Ui "\u78BA\u5B9A|\u786E\u5B9A|OK" "Close LSPosed welcome dialog" -IncludeContentDesc | Out-Null
  }
  if (-not (Ui-Contains "\u5DF2\u555F\u7528|\u5DF2\u542F\u7528|1\.9\.2.*Zygisk")) {
    Write-WarnLine "LSPosed enabled status was not recognized. Continuing anyway."
  }
}

function Configure-HookEuiccScope {
  Open-LSPosedManager
  Tap-Ui "\u6A21\u7D44|\u6A21\u5757" "LSPosed modules tab" -IncludeContentDesc | Out-Null
  Tap-Ui "HookEuicc" "HookEuicc module details" -IncludeContentDesc | Out-Null
  if (Ui-Contains "\u555F\u7528\u6A21\u7D44|\u542F\u7528\u6A21\u5757") {
    Tap-RowSwitchByText "\u555F\u7528\u6A21\u7D44|\u542F\u7528\u6A21\u5757" "HookEuicc module switch" | Out-Null
  }
  $xml = Get-UiXml
  if ($xml.OuterXml -notmatch 'com\.android\.phone(.|\n)*checked="true"') {
    Tap-RowSwitchByText "com\.android\.phone" "Phone service scope" | Out-Null
  }
  $xml = Get-UiXml
  if ($xml.OuterXml -notmatch 'com\.giffgaffmobile\.controller(.|\n)*checked="true"') {
    Tap-RowSwitchByText "com\.giffgaffmobile\.controller|giffgaff" "giffgaff scope" | Out-Null
  }
  Invoke-Cmd $script:MuMuCli @("control", "--vmindex", "$VmIndex", "restart") | Out-Null
  Wait-AndroidStarted | Out-Null
  Ensure-Adb
}

function Enable-HookEuiccAppSwitch {
  Write-Step "Opening HookEuicc app ..."
  Launch-App "cn.unicorn369.HookEuicc"
  if (Ui-Contains "LSPosed is not activated") {
    Fail "HookEuicc still says LSPosed is not activated. Reboot MuMu and rerun the script."
  }
  $xml = Get-UiXml
  if ($xml.OuterXml -match 'Hook Euicc(.|\n)*checked="true"') {
    Write-Step "HookEuicc main switch is already enabled."
    return
  }
  Tap-RowSwitchByText "Hook Euicc" "HookEuicc main switch" | Out-Null
}

function Open-GiffgaffToLogin {
  Write-Step "Opening giffgaff ..."
  Launch-App "com.giffgaffmobile.controller"
  if (Ui-Contains "This app version is a little dated") {
    Tap-Ui "UPDATE IN 60 SECONDS" "Delay giffgaff update prompt" -IncludeContentDesc | Out-Null
  }
  Start-Sleep -Seconds 2
  if (-not $NoAcceptGiffgaffTerms -and (Ui-Contains "I accept the Terms and Conditions")) {
    Write-Step "Accepting giffgaff terms and opening login page ..."
    Tap-Ui "I Accept terms and conditions|I accept the Terms" "Accept terms checkbox" -IncludeContentDesc | Out-Null
    Tap-Ui "Continue|To Login" "Continue to login" -IncludeContentDesc | Out-Null
  }
  Write-Step "giffgaff is open. Enter account, password, verification codes, payment, and final purchase manually."
}

try {
  Write-Step "Starting giffgaff eSIM environment setup."
  Write-Step "ToolDir: $ToolDir"
  if ($VmIndex -lt 0) {
    Fail "Please create a clean MuMu instance and pass -VmIndex explicitly, for example: -VmIndex 1. This avoids modifying your main MuMu instance."
  }
  Ensure-RequiredFiles

  $resolvedMuMuDir = Find-MuMuDir
  if (-not $resolvedMuMuDir) {
    Start-Process $Urls.MuMuDownload
    Fail "MuMu 5 was not found. The download page has been opened. Install MuMu and rerun this script."
  }

  $script:MuMuCli = Join-Path $resolvedMuMuDir "mumu-cli.exe"
  $script:AdbExe = Join-Path $resolvedMuMuDir "adb.exe"
  if (-not (Test-Path -LiteralPath $script:AdbExe)) { Fail "mumu-cli was found, but adb.exe was not found: $resolvedMuMuDir" }

  Write-Step "MuMu directory: $resolvedMuMuDir"
  Invoke-Cmd $script:MuMuCli @("version") | Out-Null

  Write-Step "Launching MuMu VM $VmIndex ..."
  Invoke-Cmd $script:MuMuCli @("control", "--vmindex", "$VmIndex", "launch") -AllowFailure | Out-Null
  Wait-AndroidStarted | Out-Null

  Write-Step "Enabling root and writable system disk ..."
  Invoke-Cmd $script:MuMuCli @("setting", "--vmindex", "$VmIndex", "--key", "root_permission", "--value", "true") | Out-Null
  Invoke-Cmd $script:MuMuCli @("setting", "--vmindex", "$VmIndex", "--key", "system_disk_readonly", "--value", "false") | Out-Null
  Invoke-Cmd $script:MuMuCli @("control", "--vmindex", "$VmIndex", "restart") | Out-Null
  Wait-AndroidStarted | Out-Null
  Ensure-Adb

  Install-Apk $Files.Via "Via"
  Install-Apk $Files.Giffgaff "giffgaff"
  Install-Apk $Files.Kitsune "Kitsune Mask"
  Install-Apk $Files.Hook "HookEuicc"

  Configure-MagiskAndZygisk
  Install-LSPosedModule
  Configure-HookEuiccScope
  Enable-HookEuiccAppSwitch
  Open-GiffgaffToLogin

  Write-Host ""
  Write-Host "Done. The environment should now be at the giffgaff login page." -ForegroundColor Green
  Write-Host "Manually enter account/password/codes and confirm any purchase or submission yourself."
  Write-Host "Log file: $LogFile"
} catch {
  Fail $_.Exception.Message
}
