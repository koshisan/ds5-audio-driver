# deploy-audio.ps1 — Build, sign, deploy ds5-audio-driver
$ErrorActionPreference = "Stop"

$projDir = "C:\Users\koshi\source\repos\ds5-audio-driver"
$pkgDir = "$projDir\x64\Release\package"
$hwid = "ROOT\DualSenseAudio"
$certName = "DS5Virtual Test"
$signtool = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe"
$inf2cat = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x86\inf2cat.exe"
$devcon = "C:\Program Files (x86)\Windows Kits\10\Tools\10.0.26100.0\x64\devcon.exe"
$msbuild = "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe"

Write-Host "`n=== DS5 Audio Driver Deploy ===" -ForegroundColor Cyan

# 1. Remove existing device
Write-Host "`n[1/6] Removing existing device..." -ForegroundColor Yellow
& $devcon remove $hwid 2>$null
& pnputil /delete-driver oem*.inf /uninstall /force 2>$null

# 2. Build
Write-Host "`n[2/6] Building..." -ForegroundColor Yellow
$env:WDKBuildFolder = "10.0.26100.0"
& $msbuild "$projDir\VirtualAudioDriver.sln" /p:Configuration=Release /p:Platform=x64 /p:SpectreMitigation=false /p:WindowsTargetPlatformVersion=10.0.26100.0 /p:KMDF_VERSION_MAJOR=1 /p:KMDF_VERSION_MINOR=33 /t:Rebuild /v:minimal
if ($LASTEXITCODE -ne 0) { Write-Host "BUILD FAILED" -ForegroundColor Red; exit 1 }

# 3. Check .sys exists
if (-not (Test-Path "$pkgDir\VirtualAudioDriver.sys")) {
    Write-Host "ERROR: .sys not found in $pkgDir" -ForegroundColor Red; exit 1
}
Write-Host "  .sys found: $((Get-Item "$pkgDir\VirtualAudioDriver.sys").Length) bytes" -ForegroundColor Green

# 4. Sign .sys
Write-Host "`n[3/6] Signing .sys..." -ForegroundColor Yellow
& $signtool sign /v /fd sha256 /s My /n $certName /t http://timestamp.digicert.com "$pkgDir\VirtualAudioDriver.sys"
if ($LASTEXITCODE -ne 0) { Write-Host "SIGN FAILED" -ForegroundColor Red; exit 1 }

# 5. Create + sign catalog
Write-Host "`n[4/6] Creating catalog..." -ForegroundColor Yellow
& $inf2cat /os:10_x64 /driver:$pkgDir 2>$null
if (Test-Path "$pkgDir\virtualaudiodriver.cat") {
    Write-Host "`n[5/6] Signing catalog..." -ForegroundColor Yellow
    & $signtool sign /v /fd sha256 /s My /n $certName /t http://timestamp.digicert.com "$pkgDir\virtualaudiodriver.cat"
} else {
    Write-Host "  Catalog not created (inf2cat issue) - skipping" -ForegroundColor DarkYellow
}

# 6. Install
Write-Host "`n[6/6] Installing driver..." -ForegroundColor Yellow
& $devcon install "$pkgDir\VirtualAudioDriver.inf" $hwid

Write-Host "`n=== Done! ===" -ForegroundColor Green
Get-PnpDevice -FriendlyName "*DualSense*" 2>$null | Format-Table Status, Class, FriendlyName -AutoSize
