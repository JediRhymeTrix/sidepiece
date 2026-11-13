#requires -Version 5.1
param([switch]$InstallCompiler)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$compiler=Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'
if($InstallCompiler){
 $compiler=Join-Path $env:TEMP 'sidepiece-inno-6.4.3\ISCC.exe'
 $download=Join-Path $env:TEMP ('innosetup-'+[guid]::NewGuid().ToString('N')+'.exe')
 try{
  Invoke-WebRequest 'https://github.com/jrsoftware/issrc/releases/download/is-6_4_3/innosetup-6.4.3.exe' -OutFile $download
  if((Get-FileHash $download -Algorithm SHA256).Hash -ne 'F3C42116542C4CC57263C5BA6C4FEABFC49FE771F2F98A79D2F7628B8762723B'){throw 'Inno compiler checksum mismatch'}
  if((Get-AuthenticodeSignature $download).Status -ne 'Valid'){throw 'Inno compiler signature invalid'}
  $p=Start-Process $download -ArgumentList ('/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /DIR="'+(Split-Path $compiler -Parent)+'"') -Wait -PassThru
  try{if($p.ExitCode){throw 'Inno compiler installation failed'}}finally{$p.Dispose()}
 }finally{if(Test-Path $download){Remove-Item -LiteralPath $download -Force}}
}
if(-not (Test-Path $compiler)){throw 'Install Inno Setup 6.4.3, or use -InstallCompiler on a disposable build runner.'}
if(-not $InstallCompiler -and (Get-Item $compiler).VersionInfo.ProductVersion -notlike '6.4.3*'){throw 'Install Inno Setup 6.4.3; the local compiler has a different product version.'}
$version=([IO.File]::ReadAllText((Join-Path $root 'VERSION'))).Trim()
if($version -notmatch '^\d+\.\d+\.\d+$'){throw 'Invalid version'}
$payload=Join-Path $root 'build\installer-payload'
if(Test-Path $payload){Remove-Item -LiteralPath $payload -Recurse -Force}
New-Item -ItemType Directory -Path $payload|Out-Null
Copy-Item -LiteralPath (Join-Path $root 'build\sidepiece.exe') -Destination $payload
foreach($file in 'LICENSE','README.md','SECURITY.md','VERSION'){Copy-Item -LiteralPath (Join-Path $root $file) -Destination $payload}
Copy-Item -LiteralPath (Join-Path $root 'config') -Destination $payload -Recurse
New-Item -ItemType Directory -Path (Join-Path $payload 'scripts')|Out-Null
foreach($file in 'Setup.ps1','Gpu.ps1','Configure.ps1','Installer.ps1'){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination (Join-Path $payload 'scripts')}
& $compiler ('/DProductVersion='+$version) (Join-Path $root 'installer\sidepiece.iss')
if($LASTEXITCODE){throw 'Installer compilation failed'}
if($env:GITHUB_ACTIONS -eq 'true' -and $env:RUNNER_ENVIRONMENT -eq 'github-hosted'){
 & $compiler ('/DProductVersion='+$version) '/DInstallerFailureTest' ('/O'+(Join-Path $root 'build')) '/FFailureFixture' (Join-Path $root 'installer\sidepiece.iss')
 if($LASTEXITCODE){throw 'Failure-fixture compilation failed'}
}
$dist=Join-Path $root 'dist'
$lines=foreach($file in @((Join-Path $dist ('sidepiece-'+$version+'-windows-x64.zip')),(Join-Path $dist ('Sidepiece-Setup-'+$version+'-windows-x64.exe')))){
 (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()+'  '+[IO.Path]::GetFileName($file)
}
[IO.File]::WriteAllText((Join-Path $dist 'SHA256SUMS.txt'),($lines -join "`n")+"`n",[Text.UTF8Encoding]::new($false))
