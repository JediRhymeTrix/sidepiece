#requires -Version 5.1
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted'){throw 'Compiled installer tests require disposable GitHub-hosted Windows.'}
$root=Split-Path $PSScriptRoot -Parent
$version=(Get-Content (Join-Path $root 'VERSION') -Raw).Trim()
$installer=Join-Path $root ('dist\Sidepiece-Setup-'+$version+'-windows-x64.exe')
$install=Join-Path $env:ProgramFiles 'GeForce Sidepiece'
$data=Join-Path $env:ProgramData 'GeForceSidepiece'
$nv=Join-Path $env:ProgramData 'NVIDIA Corporation\NVIDIA App'
if((Test-Path $install) -or (Test-Path $data) -or (Test-Path $nv) -or (Get-Service GeForceSidepiece -ErrorAction SilentlyContinue)){throw 'Runner is not clean.'}
foreach($name in 'W3SVC','WAS'){$s=Get-Service $name -ErrorAction SilentlyContinue;if($s -and $s.Status -ne 'Stopped'){Stop-Service $name -Force}}
function Run-Installer($File,$Arguments,[switch]$ExpectFailure){
 $p=Start-Process -FilePath $File -ArgumentList $Arguments -PassThru
 try{if(-not $p.WaitForExit(180000)){$p.Kill();throw 'Installer test timeout'};if($ExpectFailure){if($p.ExitCode -eq 0){throw 'Expected refusal, got success'}}elseif($p.ExitCode){throw ('Installer failed: '+$p.ExitCode)}}finally{$p.Dispose()}
}
$loc=Join-Path $nv 'NvConfig\LocalizedConfig.json';$profiles=Join-Path $nv 'UpdateFramework\profile-catalog\component_profiles.json'
$utf8=[Text.UTF8Encoding]::new($false)
$localText='{"localizedConfig":{"gfwsl":{"server":"https://gfwsl.geforce.com/"}},"other":"preserve"}'
$profileText='[{"componentName":"grd","updateCheckerProfiles":[{"otaBaseUrl":"https://gfwsl.geforce.com/"}]},{"componentName":"crd","updateCheckerProfiles":[{"otaBaseUrl":"https://gfwsl.geforce.com/"}]}]'
try{
 New-Item -ItemType Directory -Path (Split-Path $loc),(Split-Path $profiles) -Force|Out-Null
 [IO.File]::WriteAllText($loc,$localText,$utf8);[IO.File]::WriteAllText($profiles,$profileText,$utf8)
 Run-Installer $installer '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' -ExpectFailure
 if(Get-Service GeForceSidepiece -ErrorAction SilentlyContinue){throw 'No-selection install created service'}
 Run-Installer (Join-Path $root 'build\FailureFixture.exe') '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /GPU=ABCD_10DE_1234_5678_1' -ExpectFailure
 if(Get-Service GeForceSidepiece -ErrorAction SilentlyContinue){throw 'Interrupted setup left active service'}
 if([IO.File]::ReadAllText($loc) -cne $localText -or [IO.File]::ReadAllText($profiles) -cne $profileText){throw 'Interrupted setup failed restoration'}
 if(-not (Test-Path (Join-Path $install 'service\Recover.ps1')) -or -not (Test-Path (Join-Path $data 'route.key'))){throw 'Interrupted setup lost recovery files'}
 foreach($p in @($install,$data)){if(Test-Path $p){Remove-Item -LiteralPath $p -Recurse -Force}}
 Run-Installer $installer '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /GPU=ABCD_10DE_1234_5678_1'
 if((Get-Service GeForceSidepiece).Status -ne 'Running'){throw 'Installed service not running'}
 $backend=Join-Path $install 'payload\scripts\Setup.ps1';$service=Join-Path $install 'service'
 $recovery=Join-Path $service 'Recover.ps1'
 if(-not (Test-Path $recovery)){throw 'Protected recovery helper missing'}
 $shortcut=Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Configure GeForce Sidepiece.lnk'
 $link=(New-Object -ComObject WScript.Shell).CreateShortcut($shortcut)
 if($link.Arguments -notlike '*payload\scripts\Configure.ps1*' -or $link.Arguments -notlike '*-STA*'){throw 'Installed shortcut target invalid'}
 $config=Join-Path $data 'config.json'
 $before=[IO.File]::ReadAllText($config);$hash=(Get-FileHash $config -Algorithm SHA256).Hash
 $rejected=$false
 try{& $backend -Action Configure -InstallRoot $service -DataRoot $data -ConfigText '{"rules":false}' -ExpectedConfigHash $hash}catch{$rejected=$true}
 if(-not $rejected -or [IO.File]::ReadAllText($config) -cne $before){throw 'Invalid config not refused/preserved'}
 $c=$before|ConvertFrom-Json;$c.blacklistDeviceIds=@('FFFF_10DE_0000_0000_1');$c.rules+=@{endpoint='customMetadata';method='GET';overrides=@(@{field='mode';from='old';to='new'})}
 $custom=$c|ConvertTo-Json -Depth 64
 $lock=[IO.File]::Open($config,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
 try{
  $rejected=$false
  try{& $backend -Action Configure -InstallRoot $service -DataRoot $data -ConfigText $custom -ExpectedConfigHash $hash}catch{$rejected=$true}
  if(-not $rejected -or [IO.File]::ReadAllText($config) -cne $before){throw 'Blocked save changed configuration'}
 }finally{$lock.Dispose()}
 & $backend -Action Configure -InstallRoot $service -DataRoot $data -ConfigText $custom -ExpectedConfigHash $hash
 $rejected=$false
 try{& $backend -Action Configure -InstallRoot $service -DataRoot $data -ConfigText $before -ExpectedConfigHash $hash}catch{$rejected=$true}
 if(-not $rejected -or [IO.File]::ReadAllText($config) -cne $custom){throw 'Stale save clobbered custom config'}
 & $backend -Action Stop -InstallRoot $service -DataRoot $data
 $hash=(Get-FileHash $config -Algorithm SHA256).Hash
 & $backend -Action Configure -InstallRoot $service -DataRoot $data -ConfigText $custom -ExpectedConfigHash $hash
 if((Get-Service GeForceSidepiece).Status -ne 'Stopped'){throw 'Saving started a stopped service'}
 Run-Installer $installer '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART'
 if((Get-Service GeForceSidepiece).Status -ne 'Stopped'){throw 'Upgrade started stopped service'}
 & $backend -Action Start -InstallRoot $service -DataRoot $data
 $exe=Join-Path $service 'sidepiece.exe';$binaryHash=(Get-FileHash $exe -Algorithm SHA256).Hash
 $bad=Join-Path $env:TEMP ('sidepiece-bad-'+[guid]::NewGuid().ToString('N')+'.exe')
 try{
  [IO.File]::WriteAllText($bad,'not an executable')
  $rejected=$false
  try{& $backend -Action Update -InstallRoot $service -DataRoot $data -BinaryPath $bad}catch{$rejected=$true}
  if(-not $rejected -or (Get-FileHash $exe -Algorithm SHA256).Hash -ne $binaryHash -or (Get-Service GeForceSidepiece).Status -ne 'Running'){throw 'Failed update did not roll back'}
 }finally{Remove-Item -LiteralPath $bad -Force}
 Run-Installer $installer '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART'
 if([IO.File]::ReadAllText($config) -cne $custom){throw 'Installer upgrade lost custom rules'}
 # Crash recovery: retain the same key; never overwrite whole NVIDIA files from backups.
 $pidValue=(Get-CimInstance Win32_Service -Filter "Name='GeForceSidepiece'").ProcessId
 Stop-Process -Id $pidValue -Force
 (Get-Service GeForceSidepiece).WaitForStatus('Stopped',[timespan]::FromSeconds(20))
 & $exe --data-dir $data --restore
 if($LASTEXITCODE -or [IO.File]::ReadAllText($loc) -cne $localText){throw 'Crash restore failed'}
 & $backend -Action Start -InstallRoot $service -DataRoot $data
 & $backend -Action Stop -InstallRoot $service -DataRoot $data
 [IO.File]::WriteAllText($loc,$localText.Replace('https://gfwsl.geforce.com/','https://example.invalid/'),$utf8)
 $uninstall=Join-Path $install 'unins000.exe'
 try{
  Run-Installer $uninstall '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' -ExpectFailure
  if(-not (Test-Path $backend) -or -not (Get-Service GeForceSidepiece -ErrorAction SilentlyContinue)){throw 'Failed restore removed recovery tools/service'}
 }finally{[IO.File]::WriteAllText($loc,$localText,$utf8)}
 & $backend -Action Start -InstallRoot $service -DataRoot $data
 $manifest=Join-Path $data 'installation.json';$owned=[IO.File]::ReadAllText($manifest)
 try{
  $foreign=$owned|ConvertFrom-Json;$foreign.installRoot='C:\ForeignInstallation'
  [IO.File]::WriteAllText($manifest,($foreign|ConvertTo-Json -Depth 8),$utf8)
  Run-Installer $uninstall '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' -ExpectFailure
  if(-not (Test-Path $backend) -or -not (Test-Path $uninstall) -or (Get-Service GeForceSidepiece).Status -ne 'Running'){throw 'Refused uninstall removed files or stopped foreign service'}
 }finally{[IO.File]::WriteAllText($manifest,$owned,$utf8)}
 Run-Installer $uninstall '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART'
 if(Get-Service GeForceSidepiece -ErrorAction SilentlyContinue){throw 'Service survived uninstall'}
 & $recovery -Action Uninstall -InstallRoot $service -DataRoot $data
 if(-not (Test-Path $recovery)){throw 'Uninstall removed standalone recovery helper'}
 if([IO.File]::ReadAllText($loc) -cne $localText -or [IO.File]::ReadAllText($profiles) -cne $profileText){throw 'Uninstall did not restore exact NVIDIA fixture bytes'}
 if(-not (Test-Path (Join-Path $data 'route.key'))){throw 'Uninstall deleted recovery data'}
 Run-Installer $installer '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /GPU=ABCD_10DE_1234_5678_1' -ExpectFailure
 Write-Host 'Compiled EXE passed: no-selection refusal, install/health, invalid/stale config refusal, custom-rule save, stopped-state preservation, upgrade, uninstall/restore and retained-data refusal.'
}finally{
 $s=Get-Service GeForceSidepiece -ErrorAction SilentlyContinue
 if($s){if($s.Status -ne 'Stopped'){Stop-Service GeForceSidepiece -ErrorAction Continue};& sc.exe delete GeForceSidepiece|Out-Null}
 foreach($p in @($install,$data,$nv)){if(Test-Path $p){Remove-Item -LiteralPath $p -Recurse -Force}}
}
