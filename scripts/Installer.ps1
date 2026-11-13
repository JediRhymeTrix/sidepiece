#requires -Version 5.1
param(
 [ValidateSet('Install','Uninstall')][string]$Action='Install',
 [Parameter(Mandatory=$true)][string]$InstallRoot,
 [string]$DataRoot=(Join-Path $env:ProgramData 'GeForceSidepiece'),
 [string]$DeviceIds,
 [switch]$Silent
)
$ErrorActionPreference='Stop'
try{
 $serviceRoot=Join-Path $InstallRoot 'service'
 $backend=Join-Path $PSScriptRoot 'Setup.ps1'
 if($Action -eq 'Uninstall'){
  & $backend -Action Uninstall -InstallRoot $serviceRoot -DataRoot $DataRoot
 }elseif(Get-Service GeForceSidepiece -ErrorAction SilentlyContinue){
  & $backend -Action Update -InstallRoot $serviceRoot -DataRoot $DataRoot -BinaryPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'sidepiece.exe')
 }else{
  if($Silent -and -not $DeviceIds){throw 'Silent first installation requires /GPU=EXACT_METADATA_ID (comma-separated for multiple GPUs).'}
  if($DeviceIds -and $DeviceIds -notmatch '^[0-9A-F_,]+$'){throw 'Invalid explicit GPU IDs.'}
  $nv=Join-Path $env:ProgramData 'NVIDIA Corporation\NVIDIA App'
  if(-not (Test-Path (Join-Path $nv 'NvConfig\LocalizedConfig.json'))){throw 'NVIDIA App configuration not found. Install and open NVIDIA App first.'}
  $listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,80)
  try{$listener.Start()}catch{throw 'Port 80 is occupied. Stop/restore the existing bridge through its manager first; setup will not take it over.'}finally{$listener.Stop()}
  if(Test-Path -LiteralPath $DataRoot){throw 'Existing recovery data found. Refusing to adopt or overwrite it. Review/archive it first.'}
  $options=@{Install=$true;InstallRoot=$serviceRoot;DataRoot=$DataRoot}
  if($DeviceIds){$options.SilentDeviceIds=$DeviceIds}
  & (Join-Path $PSScriptRoot 'Configure.ps1') @options
  if($LASTEXITCODE -or -not (Get-Service GeForceSidepiece -ErrorAction SilentlyContinue)){throw 'GPU selection cancelled or service installation failed.'}
 }
 exit 0
}catch{
 if(-not $Silent){Add-Type -AssemblyName System.Windows.Forms;[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'GeForce Sidepiece - setup refused','OK','Error')}
 Write-Error $_ -ErrorAction Continue
 exit 1
}
