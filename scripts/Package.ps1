#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$version=([IO.File]::ReadAllText((Join-Path $root 'VERSION'))).Trim()
if($version -notmatch '^\d+\.\d+\.\d+$'){throw 'Invalid version'}
if($env:GITHUB_REF_TYPE -eq 'tag' -and $env:GITHUB_REF_NAME -ne ('v'+$version)){throw 'Tag must match VERSION'}
$dist=Join-Path $root 'dist';New-Item -ItemType Directory -Path $dist -Force|Out-Null
$stage=Join-Path $dist ('stage-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage -Force|Out-Null
try{
 Copy-Item -LiteralPath (Join-Path $root 'build\sidepiece.exe') -Destination (Join-Path $stage 'sidepiece.exe')
 foreach($file in 'README.md','LICENSE','SECURITY.md','CONTRIBUTING.md','VERSION'){Copy-Item -LiteralPath (Join-Path $root $file) -Destination $stage}
 foreach($dir in 'config','docs','assets'){Copy-Item -LiteralPath (Join-Path $root $dir) -Destination $stage -Recurse}
 New-Item -ItemType Directory -Path (Join-Path $stage 'scripts')|Out-Null
 foreach($script in 'Setup.ps1','Gpu.ps1','Configure.ps1'){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $script) -Destination (Join-Path $stage 'scripts\'+$script)}
 $zip=Join-Path $dist ('sidepiece-'+$version+'-windows-x64.zip')
 Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -Force
 $sum=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()+'  '+[IO.Path]::GetFileName($zip)
 [IO.File]::WriteAllText((Join-Path $dist 'SHA256SUMS.txt'),$sum+"`n",[Text.UTF8Encoding]::new($false))
 Write-Host ('Packaged '+[IO.Path]::GetFileName($zip))
}finally{Remove-Item -LiteralPath $stage -Recurse -Force}
