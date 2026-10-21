param([switch]$SkipBuild)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $SkipBuild) { & (Join-Path $PSScriptRoot 'build.ps1') }
$executable = Join-Path $projectRoot 'bin\LokiThrogPets.exe'
$testRoot = Join-Path $projectRoot 'artifacts\test'
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$runFolder = Join-Path $testRoot ([guid]::NewGuid().ToString('N'))
$process = Start-Process -FilePath $executable -ArgumentList @('--self-test',('"' + $runFolder + '"')) -WindowStyle Hidden -PassThru
if (-not $process.WaitForExit(180000)) { Stop-Process -Id $process.Id; throw 'The isolated self-test process timed out.' }
$log = Join-Path $runFolder 'self-test.txt'
if (-not (Test-Path -LiteralPath $log)) { throw 'The engine did not create a passing self-test log. See bin\error.log if present.' }
$report = Get-Content -LiteralPath $log -Raw
if (-not $report.StartsWith('PASS')) { throw $report }
Write-Output $report
