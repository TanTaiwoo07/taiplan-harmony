param(
  [string]$DevEcoHome = 'D:\Program Files\Huawei\DevEco Studio',
  [string]$Device = '127.0.0.1:5555',
  [switch]$Build
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$protectedRoot = 'C:\Users\Lenovo\Documents\Codex\2026-10-09\1-0-github-2-0\outputs\taiplan-harmony'
if ([IO.Path]::GetFullPath($projectRoot).TrimEnd('\') -ieq $protectedRoot) { throw 'Protected original project: use the desktop copy.' }
Set-Location -LiteralPath $projectRoot
$hdc = Join-Path $DevEcoHome 'sdk\default\openharmony\toolchains\hdc.exe'
$hap = Join-Path $projectRoot 'entry\build\default\outputs\default\entry-default-unsigned.hap'
if ($Build) {
  $env:DEVECO_SDK_HOME = Join-Path $DevEcoHome 'sdk'
  $env:JAVA_HOME = Join-Path $DevEcoHome 'jbr'
  $env:Path = (Join-Path $DevEcoHome 'tools\node') + ';' + $env:Path
  if (!(Test-Path -LiteralPath (Join-Path $projectRoot 'oh_modules'))) {
    & (Join-Path $DevEcoHome 'tools\ohpm\bin\ohpm.bat') install
    if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed.' }
  }
  & (Join-Path $DevEcoHome 'tools\hvigor\bin\hvigorw.bat') --mode module -p product=default -p module=entry@default assembleHap --no-daemon
  if ($LASTEXITCODE -ne 0) { throw 'Build failed.' }
}
if (!(Test-Path -LiteralPath $hap)) { throw 'No HAP found. Run with -Build, or open this project in DevEco Studio.' }
$hapTime = (Get-Item -LiteralPath $hap).LastWriteTimeUtc
$sourcePaths = @('entry\src', 'AppScope', 'hvigor', 'build-profile.json5', 'oh-package.json5', 'entry\build-profile.json5', 'entry\oh-package.json5')
foreach ($sourcePath in $sourcePaths) {
  $absolute = Join-Path $projectRoot $sourcePath
  if (Test-Path -LiteralPath $absolute) {
    $newer = Get-ChildItem -LiteralPath $absolute -Recurse -File | Where-Object { $_.LastWriteTimeUtc -gt $hapTime } | Select-Object -First 1
    if ($newer) { throw 'Source is newer than the HAP. Run tools/run-emulator.ps1 -Build before installing.' }
  }
}
$targets = & $hdc list targets
if ($targets -notcontains $Device) { throw "Start the API 26 emulator in DevEco Device Manager. Target missing: $Device" }
$result = & $hdc -t $Device install -r $hap
Write-Output $result
if ($LASTEXITCODE -ne 0 -or (($result -join ' ') -notmatch 'install bundle successfully')) { throw 'Install failed. Existing application data was not uninstalled.' }
$result = & $hdc -t $Device shell aa start -a EntryAbility -b com.taiwoo.taiplan
Write-Output $result
if ($LASTEXITCODE -ne 0 -or (($result -join ' ') -notmatch 'start ability successfully')) { throw 'App launch failed.' }
Write-Output 'TaiPlan is open in the native emulator. There is no localhost URL.'
