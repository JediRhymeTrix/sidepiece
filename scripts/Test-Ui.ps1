#requires -Version 5.1
param([string]$ConfigurePath=(Join-Path $PSScriptRoot 'Configure.ps1'),[switch]$OwnerFixture,[string]$StatePath)
$ErrorActionPreference='Stop'
$ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
Add-Type -AssemblyName System.Windows.Forms
. (Join-Path $PSScriptRoot 'UiSession.ps1')
if($OwnerFixture){
 $owner=[Windows.Forms.Form]::new();$owner.Text='Sidepiece UI test owner'
 $owner.Add_Shown({
  $args='-NoProfile -STA -ExecutionPolicy Bypass -File "'+$ConfigurePath+'" -Install -SmokeTest -OwnerWindow '+$owner.Handle.ToInt64()+' -OwnerProcessId '+$PID
  $child=Start-Process $ps -ArgumentList $args -PassThru -NoNewWindow
  [IO.File]::WriteAllText($StatePath,[string]$child.Id);$child.Dispose()
 })
 try{[void]$owner.ShowDialog()}finally{$owner.Dispose()}
 exit
}
function Wait-Result($Process,[int]$Expected){
 $null=$Process.Handle
 if(-not $Process.WaitForExit(20000)){throw 'UI regression timed out'}
 if($Process.ExitCode -ne $Expected){throw ('Unexpected UI exit code: '+$Process.ExitCode+'; expected '+$Expected)}
}
$processes=[Collections.Generic.List[Diagnostics.Process]]::new()
$state=Join-Path $env:TEMP ('sidepiece-ui-'+[guid]::NewGuid().ToString('N')+'.pid')
$session=$null
try{
 $args='-NoProfile -STA -ExecutionPolicy Bypass -File "'+$ConfigurePath+'" -Install -SmokeTest'
 $p=Start-Process $ps -ArgumentList $args -PassThru -NoNewWindow;$processes.Add($p)
 Wait-Result $p 2
 # A held configuration lock must refuse a second process before any UI or mutation.
 $session=Open-SidepieceUiSession
 $nested=Open-SidepieceUiSession
 Close-SidepieceUiSession $nested
 $p=Start-Process $ps -ArgumentList $args -PassThru -NoNewWindow;$processes.Add($p)
 Wait-Result $p 1
 Close-SidepieceUiSession $session;$session=$null
 $ownerArgs='-NoProfile -STA -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -OwnerFixture -ConfigurePath "'+$ConfigurePath+'" -StatePath "'+$state+'"'
 $parent=Start-Process $ps -ArgumentList $ownerArgs -PassThru -NoNewWindow;$processes.Add($parent)
 $deadline=[DateTime]::UtcNow.AddSeconds(20)
 while(-not (Test-Path $state)){
  if($parent.HasExited -or [DateTime]::UtcNow -gt $deadline){throw 'UI owner fixture failed to start'}
  Start-Sleep -Milliseconds 100
 }
 $child=Get-Process -Id ([int][IO.File]::ReadAllText($state));$processes.Add($child)
 $null=$child.Handle
 do{
  if($child.HasExited -or [DateTime]::UtcNow -gt $deadline){throw 'Owned configurator never showed'}
  Start-Sleep -Milliseconds 100;$child.Refresh()
 }while(-not [SidepieceUi.Window]::HasVisibleConfiguration($child.Id))
 # Kill only our synthetic owner; the UI must cancel itself well before its 15s smoke timeout.
 $parent.Kill();[void]$parent.WaitForExit(5000)
 if(-not $child.WaitForExit(5000)){throw 'Configurator survived its installer owner'}
 if($child.ExitCode -ne 2){throw 'Owner loss did not return cancellation'}
 $session=Open-SidepieceUiSession
 Write-Host 'UI regressions passed: shown window, cancellation, duplicate refusal, parent-loss cancellation and lock release. No service/settings changes.'
}finally{
 Close-SidepieceUiSession $session
 foreach($p in $processes){try{if(-not $p.HasExited){$p.Kill();[void]$p.WaitForExit(5000)}}finally{$p.Dispose()}}
 if(Test-Path $state){Remove-Item -LiteralPath $state -Force}
}
