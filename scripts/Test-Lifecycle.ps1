param([switch]$Scm)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$exe=Join-Path $root 'build\sidepiece.exe'
$fixture=Join-Path $env:TEMP ('sidepiece-fixture-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture -Force|Out-Null
Copy-Item -LiteralPath (Join-Path $root 'config\config.example.json') -Destination (Join-Path $fixture 'config.json')
$listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0);$listener.Start();$port=$listener.LocalEndpoint.Port;$listener.Stop()
$args=@('--data-dir',$fixture,'--fixture-root',$fixture,'--port',"$port")
& $exe @args --prepare;if($LASTEXITCODE){throw 'Fixture preparation failed'}
$process=$null;$service='GeForceSidepieceFixture'
try{
 if($Scm){
  if($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted'){throw 'SCM fixture testing is restricted to disposable GitHub-hosted runners.'}
  $command='"'+$exe+'" --service --data-dir "'+$fixture+'" --fixture-root "'+$fixture+'" --port '+$port+' --passive'
  & sc.exe create $service binPath= $command start= demand obj= 'NT AUTHORITY\LocalService'
  if($LASTEXITCODE){throw 'Fixture SCM create failed'}
  & icacls.exe $fixture /grant '*S-1-5-19:(OI)(CI)M'|Out-Null
  & icacls.exe $root /grant '*S-1-5-19:(OI)(CI)RX'|Out-Null
  Start-Service $service
 }else{$process=Start-Process -FilePath $exe -ArgumentList ('--data-dir "'+$fixture+'" --fixture-root "'+$fixture+'" --port '+$port+' --passive') -PassThru -NoNewWindow}
 Start-Sleep -Seconds 2
 & $exe @args --probe;if($LASTEXITCODE){throw 'Fixture health failed'}
 if($Scm){Stop-Service $service;(Get-Service $service).WaitForStatus('Stopped',[timespan]::FromSeconds(20))}
 else{& $exe @args --stop;if($LASTEXITCODE){throw 'Fixture stop failed'};if(-not $process.WaitForExit(20000)){throw 'Fixture failed to drain'}}
 Write-Host 'Isolated lifecycle fixture passed; real NVIDIA settings untouched.'
}finally{
 if($Scm-and $env:GITHUB_ACTIONS){$s=Get-Service $service -ErrorAction SilentlyContinue;if($s){if($s.Status-ne 'Stopped'){Stop-Service $service};& sc.exe delete $service|Out-Null}}
 if($process-and -not $process.HasExited){$process.Kill()}
 if(Test-Path -LiteralPath $fixture){Remove-Item -LiteralPath $fixture -Recurse -Force}
}
