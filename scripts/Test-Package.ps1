#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$version=([IO.File]::ReadAllText((Join-Path $root 'VERSION'))).Trim()
$dist=Join-Path $root 'dist'
foreach($line in [IO.File]::ReadAllLines((Join-Path $dist 'SHA256SUMS.txt'))){
 if(-not $line){continue}
 $parts=$line -split '  ',2
 if($parts.Count -ne 2 -or $parts[1] -notmatch '^[a-zA-Z0-9.-]+$'){throw 'Invalid checksum entry'}
 if((Get-FileHash (Join-Path $dist $parts[1]) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $parts[0]){throw 'Checksum mismatch'}
}
Write-Host 'Artifact checksums passed.'
$verify=Join-Path $env:TEMP ('sidepiece-verify-'+[guid]::NewGuid().ToString('N'))
try{
 Add-Type -AssemblyName System.IO.Compression.FileSystem
 [IO.Compression.ZipFile]::ExtractToDirectory((Join-Path $dist ('sidepiece-'+$version+'-windows-x64.zip')),$verify)
 foreach($file in Get-ChildItem $verify -Recurse -File){
  if($file.Name -match 'route\.key|\.log$|backup|test.*\.exe|installation\.json'){throw 'Unexpected runtime/test artifact'}
 }
 foreach($name in 'Setup.ps1','Gpu.ps1','Configure.ps1','UiSession.ps1'){
  if(-not (Test-Path (Join-Path $verify ('scripts\'+$name)))){throw ('Missing helper: '+$name)}
 }
 $actual=& (Join-Path $verify 'sidepiece.exe') --version
 if($LASTEXITCODE -or ($actual -join ' ') -notmatch [regex]::Escape($version)){throw 'Packaged binary version mismatch'}
 & (Join-Path $PSScriptRoot 'Test-Ui.ps1') -ConfigurePath (Join-Path $verify 'scripts\Configure.ps1')
 Write-Host 'Extracted package contents, version and UI lifecycle passed.'
}finally{if(Test-Path $verify){Remove-Item -LiteralPath $verify -Recurse -Force}}
