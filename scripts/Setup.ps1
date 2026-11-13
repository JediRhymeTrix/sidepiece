#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param(
 [ValidateSet('Install','Update','Uninstall','Status','ListGpus','Configure','Start','Stop')][string]$Action='Install',
 [string[]]$DeviceId=@(),
 [string[]]$DeniedDeviceId=@(),
 [string]$ConfigText,
 [string]$ExpectedConfigHash,
 [string]$BinaryPath,
 [string]$InstallRoot=(Join-Path $env:ProgramFiles 'GeForce Sidepiece'),
 [string]$DataRoot=(Join-Path $env:ProgramData 'GeForceSidepiece')
)
$ErrorActionPreference='Stop'
if(-not $BinaryPath){$BinaryPath=Join-Path (Split-Path $PSScriptRoot -Parent) 'sidepiece.exe'}
$name='GeForceSidepiece'
function Assert-Admin {
 $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
 if(-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Run setup in an elevated PowerShell window.'}
}
function Native($File,$Arguments){
 # ProcessStartInfo avoids Windows PowerShell 5.1 stripping embedded SCM ImagePath quotes.
 $quoted=foreach($arg in $Arguments){'"'+([string]$arg -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"'}
 $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$File;$info.Arguments=$quoted -join ' ';$info.UseShellExecute=$false
 $p=[Diagnostics.Process]::Start($info)
 try{if(-not $p.WaitForExit(30000)){throw ('Operation timed out: '+[IO.Path]::GetFileName($File))};if($p.ExitCode){throw ('Operation failed: '+[IO.Path]::GetFileName($File))}}finally{$p.Dispose()}
}
function Secure-Directory($Path,$ServiceAccess){
 New-Item -ItemType Directory -Path $Path -Force|Out-Null
 $acl=Get-Acl -LiteralPath $Path
 $acl.SetAccessRuleProtection($true,$false)
 foreach($sid in 'S-1-5-18','S-1-5-32-544'){
  $rule=[Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),[Security.AccessControl.FileSystemRights]::FullControl,'ContainerInherit,ObjectInherit','None','Allow');$acl.AddAccessRule($rule)
 }
 $rule=[Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.NTAccount]::new('NT SERVICE\'+$name),[Security.AccessControl.FileSystemRights]$ServiceAccess,'ContainerInherit,ObjectInherit','None','Allow');$acl.AddAccessRule($rule)
 Set-Acl -LiteralPath $Path -AclObject $acl
}
function Remove-ServiceGrant($Path,$Sid){
 $acl=Get-Acl -LiteralPath $Path
 foreach($rule in @($acl.Access)){
  if(-not $rule.IsInherited -and $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -eq $Sid){[void]$acl.RemoveAccessRuleSpecific($rule)}
 }
 Set-Acl -LiteralPath $Path -AclObject $acl
}
function Stop-Owned {
 $s=Get-Service -Name $name -ErrorAction SilentlyContinue
 if($s -and $s.Status-ne 'Stopped'){$s.Stop();$s.WaitForStatus('Stopped',[timespan]::FromSeconds(80))}
}
function Wait-Healthy($Exe){
 $deadline=(Get-Date).AddSeconds(20)
 do{
  Start-Sleep -Milliseconds 500
  $output=& $Exe --data-dir $DataRoot --probe 2>$null
  if($LASTEXITCODE -eq 0){
   $health=$output|ConvertFrom-Json
   $svc=Get-CimInstance Win32_Service -Filter ("Name='"+$name+"'")
   if($health.ok -eq $true -and $health.product -eq 'GeForce Sidepiece' -and $health.pid -eq $svc.ProcessId -and $svc.State -eq 'Running'){return}
  }
 }while((Get-Date)-lt $deadline)
 throw 'Service did not become healthy; installation rolled back.'
}
if($Action-eq 'ListGpus'){
 . (Join-Path $PSScriptRoot 'Gpu.ps1')
 Get-SidepieceGpus | Select-Object Name,DeviceId,Status,ProblemCode
 Write-Host 'Select the external desktop GPU explicitly. Detection does not infer Thunderbolt/OCuLink topology.'
 exit
}
if($Action-eq 'Status'){Get-Service -Name $name -ErrorAction SilentlyContinue;exit}
Assert-Admin
if(-not $PSCmdlet.ShouldProcess($name,$Action)){return}
foreach($path in @($InstallRoot,$DataRoot)){
 if(-not [IO.Path]::IsPathRooted($path) -or $path.Contains('"') -or $path.Contains('..') -or $path.EndsWith('\')){throw 'Installation paths must be absolute, without quotes, traversal or a trailing slash.'}
 $parent=$path
 while($parent){if((Test-Path -LiteralPath $parent) -and ((Get-Item -LiteralPath $parent -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Reparse-point installation paths are not supported.'};$parent=Split-Path $parent -Parent}
}
$manifest=Join-Path $DataRoot 'installation.json'
$existing=Get-Service -Name $name -ErrorAction SilentlyContinue
if($existing){
 if(-not (Test-Path -LiteralPath $manifest)){throw 'Existing service is not owned by this installer.'}
 $saved=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json
 $expected='"'+(Join-Path $InstallRoot 'sidepiece.exe')+'" --service --data-dir "'+$DataRoot+'"'
 $image=(Get-ItemProperty -LiteralPath ('HKLM:\SYSTEM\CurrentControlSet\Services\'+$name)).ImagePath
 $sid=([Security.Principal.NTAccount]::new('NT SERVICE\'+$name)).Translate([Security.Principal.SecurityIdentifier]).Value
 if($saved.serviceName -ne $name -or $saved.installRoot -ne $InstallRoot -or $saved.dataRoot -ne $DataRoot -or $saved.serviceSid -ne $sid -or $image -ne $expected){throw 'Installation ownership mismatch.'}
}
if($Action -in 'Configure','Start','Stop'){
 if(-not $existing){throw 'No owned standalone installation found.'}
 $exe=Join-Path $InstallRoot 'sidepiece.exe'
 if($Action -eq 'Stop'){Stop-Owned;return}
 if($Action -eq 'Start'){Start-Service $name;Wait-Healthy $exe;return}
 if(-not $ConfigText -or [Text.Encoding]::UTF8.GetByteCount($ConfigText) -gt 65536){throw 'Configuration must contain 1-65536 UTF-8 bytes.'}
 $path=Join-Path $DataRoot 'config.json'
 if(-not $ExpectedConfigHash -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $ExpectedConfigHash){throw 'Configuration changed; reload before saving.'}
 $stage=Join-Path $DataRoot ('validate-'+[guid]::NewGuid().ToString('N'))
 $candidate=Join-Path $DataRoot ('config-'+[guid]::NewGuid().ToString('N')+'.tmp')
 try{
  New-Item -ItemType Directory -Path $stage|Out-Null
  [IO.File]::WriteAllText((Join-Path $stage 'config.json'),$ConfigText,[Text.UTF8Encoding]::new($false))
  Native $exe @('--data-dir',$stage,'--prepare')
  [IO.File]::WriteAllText($candidate,$ConfigText,[Text.UTF8Encoding]::new($false))
  if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $ExpectedConfigHash){throw 'Configuration changed during validation; reload before saving.'}
  [IO.File]::Replace($candidate,$path,(Join-Path $DataRoot 'config.previous.json'))
  Write-Host 'Configuration validated and saved. Service running/stopped state was preserved.'
 }finally{if(Test-Path -LiteralPath $candidate){Remove-Item -LiteralPath $candidate -Force};if(Test-Path -LiteralPath $stage){Remove-Item -LiteralPath $stage -Recurse -Force}}
 return
}
if($Action-eq 'Uninstall'){
 if(-not (Test-Path -LiteralPath $manifest)){throw 'Owned installation manifest not found; refusing uninstall.'}
 $saved=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json
 if($saved.serviceName-ne $name-or $saved.installRoot-ne $InstallRoot){throw 'Installation ownership mismatch.'}
 Stop-Owned
 $exe=Join-Path $InstallRoot 'sidepiece.exe'
 Native $exe @('--data-dir',$DataRoot,'--restore')
 Native sc.exe @('delete',$name)
 foreach($entry in $saved.nvidiaAcls){Remove-ServiceGrant $entry.path $saved.serviceSid}
 Write-Host 'Service removed; NVIDIA URLs restored. Binaries, settings and backups retained for recovery.'
 return
}
if(-not (Test-Path -LiteralPath $BinaryPath)){throw 'Extract the release ZIP first, or supply -BinaryPath.'}
$BinaryPath=(Resolve-Path -LiteralPath $BinaryPath).Path
$existing=Get-Service -Name $name -ErrorAction SilentlyContinue
if($Action-eq 'Update'-and -not $existing){throw 'No standalone installation to update.'}
if($existing -and $Action -eq 'Install'){throw 'Already installed; use -Action Update.'}
if(-not $existing -and ((Test-Path -LiteralPath $InstallRoot) -or (Test-Path -LiteralPath $DataRoot))){throw 'Choose unused installation/data directories; existing files are never overwritten by a new install.'}
$nv=Join-Path $env:ProgramData 'NVIDIA Corporation\NVIDIA App'
$nvFiles=@((Join-Path $nv 'NvConfig\LocalizedConfig.json'),(Join-Path $nv 'UpdateFramework\profile-catalog\component_profiles.json'))
foreach($file in $nvFiles){if(-not (Test-Path -LiteralPath $file)){throw 'NVIDIA App configuration not found.'}}
if(-not $existing){
 $listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,80)
 try{$listener.Start()}catch{throw 'Loopback port 80 is occupied. Stop/restore any existing bridge through its manager first.'}finally{$listener.Stop()}
 if(-not $DeviceId.Count){throw 'Supply -DeviceId with the exact desktop eGPU ID. Run -Action ListGpus; see docs/configuration.md for conversion.'}
 foreach($id in @($DeviceId)+@($DeniedDeviceId)){if($id.Length -gt 40 -or $id-cnotmatch '^[0-9A-F]{4}_[0-9A-F]{4}_[0-9A-F]{4}_[0-9A-F]{4}_[0-9]+$'){throw 'Device IDs must use exact uppercase NVIDIA metadata format.'}}
 $local=Get-Content -LiteralPath $nvFiles[0] -Raw|ConvertFrom-Json
 if($local.localizedConfig.gfwsl.server-ne 'https://gfwsl.geforce.com/'){throw 'Unknown or already redirected NVIDIA endpoint; restore its owner first.'}
}
$created=$false;$oldBinary=$null;$aclState=@();$oldConfig=$null
try{
 if(-not $existing){
  New-Item -ItemType Directory -Path $InstallRoot,$DataRoot -Force|Out-Null
  Native sc.exe @('create',$name,'binPath=',('"'+(Join-Path $InstallRoot 'sidepiece.exe')+'" --service --data-dir "'+$DataRoot+'"'),'start=','auto','obj=','NT AUTHORITY\LocalService','DisplayName=','GeForce Sidepiece')
  $created=$true
  Native sc.exe @('sidtype',$name,'unrestricted')
  Native sc.exe @('description',$name,'Unofficial NVIDIA App desktop eGPU driver-discovery compatibility bridge.')
  Secure-Directory $InstallRoot 'ReadAndExecute'
  Secure-Directory $DataRoot 'Modify'
  $serviceSid=([Security.Principal.NTAccount]::new('NT SERVICE\'+$name)).Translate([Security.Principal.SecurityIdentifier]).Value
  foreach($parent in @($nvFiles|ForEach-Object {Split-Path $_ -Parent}|Select-Object -Unique)){
   $acl=Get-Acl -LiteralPath $parent;$aclState+=@{path=$parent}
   $rule=[Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($serviceSid),'Modify','ContainerInherit,ObjectInherit','None','Allow');$acl.AddAccessRule($rule);Set-Acl -LiteralPath $parent -AclObject $acl
  }
  $template=Join-Path (Split-Path $PSScriptRoot -Parent) 'config\config.example.json'
  $config=Get-Content -LiteralPath $template -Raw|ConvertFrom-Json;$config.whitelistDeviceIds=@($DeviceId);$config.blacklistDeviceIds=@($DeniedDeviceId)
  [IO.File]::WriteAllText((Join-Path $DataRoot 'config.json'),($config|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
 }else{
  Stop-Owned
  $oldBinary=Join-Path $DataRoot 'sidepiece.previous.exe'
  Copy-Item -LiteralPath (Join-Path $InstallRoot 'sidepiece.exe') -Destination $oldBinary -Force
  $oldConfig=[IO.File]::ReadAllText((Join-Path $DataRoot 'config.json'))
 }
 $dest=Join-Path $InstallRoot 'sidepiece.exe'
 Copy-Item -LiteralPath $BinaryPath -Destination $dest -Force
 Native $dest @('--data-dir',$DataRoot,'--prepare')
 Native $dest @('--data-dir',$DataRoot,'--validate')
 Start-Service -Name $name
 Wait-Healthy $dest
 if($created){$state=@{serviceName=$name;installRoot=$InstallRoot;dataRoot=$DataRoot;serviceSid=$serviceSid;nvidiaAcls=$aclState};[IO.File]::WriteAllText($manifest,($state|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))}
 Write-Host 'GeForce Sidepiece is installed and healthy. Reopen NVIDIA App if it cached old endpoints.'
}catch{
 $failure=$_.Exception.Message
 try{Stop-Owned}catch{Write-Warning 'Service could not stop safely; retained files/permissions for recovery.';throw}
 if($created){
  if(Test-Path -LiteralPath (Join-Path $DataRoot 'route.key')){Native (Join-Path $InstallRoot 'sidepiece.exe') @('--data-dir',$DataRoot,'--restore')}
  Native sc.exe @('delete',$name)
  foreach($entry in $aclState){Remove-ServiceGrant $entry.path $serviceSid}
 }elseif($oldBinary){Copy-Item -LiteralPath $oldBinary -Destination (Join-Path $InstallRoot 'sidepiece.exe') -Force;if($null-ne $oldConfig){[IO.File]::WriteAllText((Join-Path $DataRoot 'config.json'),$oldConfig,[Text.UTF8Encoding]::new($false))};Start-Service $name}
 throw $failure
}
