param([string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $projectRoot 'bin' }
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
if (-not (Test-Path -LiteralPath $compiler)) { throw 'The .NET Framework C# compiler is required on Windows.' }
$pngFiles = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'assets') -Filter '*.png')
$wavFiles = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'sounds') -Filter '*.wav')
if ($pngFiles.Count -ne 454 -or $wavFiles.Count -ne 14) { throw 'Expected 454 PNG resources and 14 WAV resources.' }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
$compileArgs = @('/nologo','/target:winexe','/optimize+','/platform:anycpu','/codepage:65001','/reference:System.Drawing.dll','/reference:System.Windows.Forms.dll',('/out:' + (Join-Path $OutputDirectory 'LokiThrogPets.exe')))
foreach ($file in $pngFiles) { $compileArgs += ('/resource:' + $file.FullName + ',sprite.' + $file.BaseName) }
foreach ($file in $wavFiles) { $compileArgs += ('/resource:' + $file.FullName + ',sound.' + $file.BaseName) }
Get-ChildItem -LiteralPath (Join-Path $projectRoot 'src') -Filter '*.cs' | ForEach-Object { $compileArgs += $_.FullName }
$responseFile = Join-Path $OutputDirectory 'build-arguments.rsp'
try {
    $compileArgs | ForEach-Object { '"' + $_ + '"' } | Set-Content -LiteralPath $responseFile -Encoding UTF8
    & $compiler ('@' + $responseFile)
    if ($LASTEXITCODE -ne 0) { throw 'Compilation failed.' }
    Write-Output ('Built: ' + (Join-Path $OutputDirectory 'LokiThrogPets.exe'))
} finally {
    if (Test-Path -LiteralPath $responseFile) { Remove-Item -LiteralPath $responseFile }
}
