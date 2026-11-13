#requires -Version 5.1
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted'){throw 'Installer fixtures require a disposable GitHub-hosted runner.'}
$root=Split-Path $PSScriptRoot -Parent
$nv=Join-Path $env:ProgramData 'NVIDIA Corporation\NVIDIA App'
$install=Join-Path $env:ProgramFiles ('SidepieceFixture-'+[guid]::NewGuid().ToString('N'))
$data=Join-Path $env:ProgramData ('SidepieceFixture-'+[guid]::NewGuid().ToString('N'))
if((Test-Path -LiteralPath $nv) -or (Get-Service GeForceSidepiece -ErrorAction SilentlyContinue)){throw 'Refusing existing NVIDIA settings or service; runner must be clean.'}
# Hosted Windows images may have IIS bound to HTTP port 80. Never do this on user machines.
foreach($webService in 'W3SVC','WAS'){
 $web=Get-Service $webService -ErrorAction SilentlyContinue
 if($web -and $web.Status -ne 'Stopped'){Stop-Service $webService -Force}
}
$setup=Join-Path $PSScriptRoot 'Setup.ps1'
$binary=Join-Path $root 'build\sidepiece.exe'
$loc=Join-Path $nv 'NvConfig\LocalizedConfig.json'
$profiles=Join-Path $nv 'UpdateFramework\profile-catalog\component_profiles.json'
$utf8=[Text.UTF8Encoding]::new($false)
$localText='{"localizedConfig":{"gfwsl":{"server":"https://gfwsl.geforce.com/"}},"unrelated":"retained"}'
$profileText='[{"componentName":"grd","updateCheckerProfiles":[{"otaBaseUrl":"https://gfwsl.geforce.com/"}]},{"componentName":"crd","updateCheckerProfiles":[{"otaBaseUrl":"https://gfwsl.geforce.com/"}]}]'
try{
 New-Item -ItemType Directory -Path (Split-Path $loc -Parent),(Split-Path $profiles -Parent) -Force|Out-Null
 [IO.File]::WriteAllText($loc,$localText,$utf8);[IO.File]::WriteAllText($profiles,$profileText,$utf8)
 & $setup -BinaryPath $binary -InstallRoot $install -DataRoot $data -DeviceId 'ABCD_10DE_1234_5678_1'
 if((Get-Service GeForceSidepiece).Status -ne 'Running'){throw 'Install not running'}
 if([IO.File]::ReadAllText($loc) -eq $localText){throw 'Fixture URLs not redirected'}
 $exe=Join-Path $install 'sidepiece.exe'
 & $exe --data-dir $data --probe;if($LASTEXITCODE){throw 'Installed host probe failed'}
 Stop-Service GeForceSidepiece
 (Get-Service GeForceSidepiece).WaitForStatus('Stopped',[timespan]::FromSeconds(80))
 if([IO.File]::ReadAllText($loc) -cne $localText -or [IO.File]::ReadAllText($profiles) -cne $profileText){throw 'Stop did not restore exact fixture bytes'}
 $config=Join-Path $data 'config.json'
 $c=Get-Content -LiteralPath $config -Raw|ConvertFrom-Json;$c.blacklistDeviceIds=@('FFFF_10DE_0000_0000_1')
 [IO.File]::WriteAllText($config,($c|ConvertTo-Json -Depth 12),$utf8)
 $before=[IO.File]::ReadAllText($config)
 Start-Service GeForceSidepiece
 & $setup -Action Update -BinaryPath $binary -InstallRoot $install -DataRoot $data
 if([IO.File]::ReadAllText($config) -cne $before){throw 'Update lost custom configuration'}
 & $setup -Action Uninstall -InstallRoot $install -DataRoot $data
 if([IO.File]::ReadAllText($loc) -cne $localText -or [IO.File]::ReadAllText($profiles) -cne $profileText){throw 'Uninstall did not restore exact fixture bytes'}
 if(-not (Test-Path -LiteralPath $config)){throw 'Uninstall removed retained configuration'}
 Write-Host 'Installer fixture passed: LocalService install, probe, stop/restore, restart, update/preserve, uninstall/restore.'
}finally{
 $s=Get-Service GeForceSidepiece -ErrorAction SilentlyContinue
 if($s){if($s.Status -ne 'Stopped'){Stop-Service GeForceSidepiece -ErrorAction Continue}; & sc.exe delete GeForceSidepiece|Out-Null}
 foreach($p in @($nv,$install,$data)){if(Test-Path -LiteralPath $p){Remove-Item -LiteralPath $p -Recurse -Force}}
}
