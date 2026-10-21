param([string]$Version = '0.10.0',[switch]$SkipBuild)
$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Version must have the form 0.10.0.' }
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $SkipBuild) { & (Join-Path $PSScriptRoot 'build.ps1') }
$dist = Join-Path $projectRoot 'dist'
$stage = Join-Path $dist ('LokiThrogPets-v' + $Version)
New-Item -ItemType Directory -Path $stage -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $projectRoot 'bin\LokiThrogPets.exe') -Destination $stage
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs\USER_GUIDE.zh-CN.md') -Destination (Join-Path $stage 'USER_GUIDE.zh-CN.md')
Copy-Item -LiteralPath (Join-Path $projectRoot 'NOTICE.md') -Destination $stage
Copy-Item -LiteralPath (Join-Path $projectRoot 'CHANGELOG.md') -Destination $stage
$exeHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $stage 'LokiThrogPets.exe')).Hash.ToLowerInvariant()
($exeHash + '  LokiThrogPets.exe') | Set-Content -LiteralPath (Join-Path $stage 'SHA256SUMS.txt') -Encoding ASCII
$archive = Join-Path $dist ('LokiThrogPets-v' + $Version + '-windows-x64.zip')
Compress-Archive -LiteralPath $stage -DestinationPath $archive -Force
$zipHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLowerInvariant()
($zipHash + '  ' + (Split-Path -Leaf $archive)) | Set-Content -LiteralPath (Join-Path $dist 'SHA256SUMS.txt') -Encoding ASCII
Write-Output ('Release archive: ' + $archive)
