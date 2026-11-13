#requires -Version 5.1
[CmdletBinding()]
param(
 [switch]$Install,
 [string]$InstallRoot,
 [string]$DataRoot=(Join-Path $env:ProgramData 'GeForceSidepiece'),
 [string]$BinaryPath,
 [string]$SilentDeviceIds,
 [switch]$SmokeTest,
 [long]$OwnerWindow,
 [int]$OwnerProcessId
)
$ErrorActionPreference='Stop'
if(-not $InstallRoot){$InstallRoot=Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'service'}
if(-not $BinaryPath){$BinaryPath=Join-Path (Split-Path $PSScriptRoot -Parent) 'sidepiece.exe'}
. (Join-Path $PSScriptRoot 'Gpu.ps1')
$setup=Join-Path $PSScriptRoot 'Setup.ps1'
if($SmokeTest -and (-not $Install -or $SilentDeviceIds)){throw 'Smoke test requires -Install without silent IDs and never installs anything.'}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
if(-not $SmokeTest -and -not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
 # Only fixed installed/default arguments are forwarded; user-supplied paths require an elevated shell.
 if($PSBoundParameters.Count){throw 'Run this command elevated when supplying custom arguments.'}
 Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -Verb RunAs -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -File "'+$PSCommandPath+'"')
 exit
}
. (Join-Path $PSScriptRoot 'UiSession.ps1')
$session=Open-SidepieceUiSession $OwnerWindow $OwnerProcessId
$parentTimer=$null;$smokeTimer=$null
try{
if($SilentDeviceIds){
 if(-not $Install){throw 'Silent GPU IDs are install-only.'}
 $ids=@($SilentDeviceIds.Split(','))
 & $setup -Action Install -InstallRoot $InstallRoot -DataRoot $DataRoot -BinaryPath $BinaryPath -DeviceId $ids
 exit 0
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$form=[Windows.Forms.Form]::new();$form.Text='GeForce Sidepiece - Configuration';$form.Size=[Drawing.Size]::new(880,700);$form.MinimumSize=$form.Size;$form.StartPosition='CenterScreen'
if($session.Parent){
 $parentTimer=[Windows.Forms.Timer]::new();$parentTimer.Interval=250
 $parentTimer.Add_Tick({if($session.Parent.HasExited){$form.Close()}})
 $parentTimer.Start()
}
$note=[Windows.Forms.Label]::new();$note.SetBounds(16,12,830,64);$note.Text="Select only your external DESKTOP GPU. A model name cannot prove eGPU topology.`r`nIDs are derived from PCI data with suffix _1; verify/edit the suffix if your metadata differs.`r`nNo permanent GUI runs. Stop restores NVIDIA URLs; disabling overrides does not stop the bridge."
$form.Controls.Add($note)
$tabs=[Windows.Forms.TabControl]::new();$tabs.SetBounds(16,80,830,470);$tabs.Anchor='Top,Bottom,Left,Right';$form.Controls.Add($tabs)
$basic=[Windows.Forms.TabPage]::new();$basic.Text='GPUs and behavior';[void]$tabs.TabPages.Add($basic)
$advanced=[Windows.Forms.TabPage]::new();$advanced.Text='Advanced JSON (full configuration)';[void]$tabs.TabPages.Add($advanced)
$list=[Windows.Forms.ListView]::new();$list.SetBounds(10,10,795,160);$list.View='Details';$list.FullRowSelect=$true
[void]$list.Columns.Add('Detected NVIDIA GPU',270);[void]$list.Columns.Add('Suggested metadata ID',300);[void]$list.Columns.Add('Device state',190);$basic.Controls.Add($list)
$allowButton=[Windows.Forms.Button]::new();$allowButton.Text='Allow selected GPU';$allowButton.SetBounds(10,175,180,30);$basic.Controls.Add($allowButton)
$denyButton=[Windows.Forms.Button]::new();$denyButton.Text='Deny selected GPU';$denyButton.SetBounds(200,175,180,30);$basic.Controls.Add($denyButton)
$label=[Windows.Forms.Label]::new();$label.Text='Allowed desktop eGPU IDs (one per line; editable):';$label.SetBounds(10,215,390,22);$basic.Controls.Add($label)
$allow=[Windows.Forms.TextBox]::new();$allow.Multiline=$true;$allow.ScrollBars='Vertical';$allow.SetBounds(10,240,390,125);$basic.Controls.Add($allow)
$label=[Windows.Forms.Label]::new();$label.Text='Denied GPU IDs (deny wins; one per line):';$label.SetBounds(410,215,390,22);$basic.Controls.Add($label)
$deny=[Windows.Forms.TextBox]::new();$deny.Multiline=$true;$deny.ScrollBars='Vertical';$deny.SetBounds(410,240,390,125);$basic.Controls.Add($deny)
$enabled=[Windows.Forms.CheckBox]::new();$enabled.Text='Enable configured metadata overrides';$enabled.SetBounds(10,375,500,25);$basic.Controls.Add($enabled)
$raw=[Windows.Forms.TextBox]::new();$raw.Multiline=$true;$raw.AcceptsReturn=$true;$raw.AcceptsTab=$true;$raw.ScrollBars='Both';$raw.WordWrap=$false;$raw.Dock='Fill';$raw.Font=[Drawing.Font]::new('Consolas',10);$advanced.Controls.Add($raw)
$status=[Windows.Forms.Label]::new();$status.SetBounds(16,555,830,38);$status.Anchor='Bottom,Left,Right';$form.Controls.Add($status)
function Read-Ids($Box){@($Box.Lines|ForEach-Object {$_.Trim().ToUpperInvariant()}|Where-Object {$_})}
function Refresh-Status {
 $svc=Get-Service GeForceSidepiece -ErrorAction SilentlyContinue
 $status.Text=if($svc){'Service: '+$svc.Status+' | Settings: '+$DataRoot}else{'Not installed. No GPU is automatically selected.'}
}
$script:loadedHash=$null;$script:syncing=$false;$script:done=$false
function Load-Configuration {
 $path=if($Install){Join-Path (Split-Path $PSScriptRoot -Parent) 'config\config.example.json'}else{Join-Path $DataRoot 'config.json'}
 $text=[IO.File]::ReadAllText($path)
 if(-not $Install){$script:loadedHash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}
 $script:syncing=$true
 try{$raw.Text=$text;$c=$text|ConvertFrom-Json;$allow.Text=@($c.whitelistDeviceIds)-join "`r`n";$deny.Text=@($c.blacklistDeviceIds)-join "`r`n";$enabled.Checked=$c.enabled -eq $true}finally{$script:syncing=$false}
 Refresh-Status
}
function Sync-Basic {
 if($script:syncing){return}
 $c=$raw.Text|ConvertFrom-Json
 foreach($key in 'whitelistDeviceIds','blacklistDeviceIds','enabled'){if(-not $c.PSObject.Properties[$key]){$c|Add-Member NoteProperty $key $null}}
 $c.whitelistDeviceIds=@(Read-Ids $allow);$c.blacklistDeviceIds=@(Read-Ids $deny);$c.enabled=$enabled.Checked
 $script:syncing=$true
 try{$raw.Text=$c|ConvertTo-Json -Depth 64}finally{$script:syncing=$false}
}
function Show-Failure($e){
 if($session.Parent -and $session.Parent.HasExited){$form.Close();return}
 [void][Windows.Forms.MessageBox]::Show($form,$e.Exception.Message,'Sidepiece - operation refused','OK','Error')
}
$allowButton.Add_Click({if($list.SelectedItems.Count){$allow.AppendText($(if($allow.Text){"`r`n"}else{''})+$list.SelectedItems[0].SubItems[1].Text)}})
$denyButton.Add_Click({if($list.SelectedItems.Count){$deny.AppendText($(if($deny.Text){"`r`n"}else{''})+$list.SelectedItems[0].SubItems[1].Text)}})
$tabs.Add_Selecting({param($sender,$e)
 try{
  if($e.TabPage -eq $advanced){Sync-Basic}
  else{
   $c=$raw.Text|ConvertFrom-Json;$script:syncing=$true
   try{$allow.Text=@($c.whitelistDeviceIds)-join "`r`n";$deny.Text=@($c.blacklistDeviceIds)-join "`r`n";$enabled.Checked=$c.enabled -eq $true}finally{$script:syncing=$false}
  }
 }catch{$e.Cancel=$true;Show-Failure $_}
})
$save=[Windows.Forms.Button]::new();$save.Text=if($Install){'Install and verify'}else{'Validate and save'};$save.SetBounds(16,600,180,35);$save.Anchor='Bottom,Left';$form.Controls.Add($save)
$save.Add_Click({
 try{
  if($SmokeTest){throw 'Smoke test cannot save or install.'}
  if($session.Parent -and $session.Parent.HasExited){$form.Close();return}
  if($tabs.SelectedTab -eq $basic){Sync-Basic}
  $save.Enabled=$false;$form.UseWaitCursor=$true
  if($Install){
   $c=$raw.Text|ConvertFrom-Json
   if(-not @($c.whitelistDeviceIds).Count){throw 'Select at least one external desktop GPU explicitly.'}
   if([Windows.Forms.MessageBox]::Show($form,('Install for these explicitly selected desktop GPU IDs?'+"`r`n"+(@($c.whitelistDeviceIds)-join "`r`n")),'Confirm desktop eGPU selection','YesNo','Warning') -ne 'Yes'){return}
   if($session.Parent -and $session.Parent.HasExited){$form.Close();return}
   # Finish or unwind transactions rather than interrupting them on parent loss.
   if($parentTimer){$parentTimer.Stop()}
   $validation=Join-Path $env:TEMP ('sidepiece-config-'+[guid]::NewGuid().ToString('N'))
   try{
    New-Item -ItemType Directory -Path $validation|Out-Null
    [IO.File]::WriteAllText((Join-Path $validation 'config.json'),$raw.Text,[Text.UTF8Encoding]::new($false))
    & $BinaryPath --data-dir $validation --prepare
    if($LASTEXITCODE){throw 'Invalid configuration; no service was installed.'}
   }finally{if(Test-Path $validation){Remove-Item -LiteralPath $validation -Recurse -Force}}
   & $setup -Action Install -InstallRoot $InstallRoot -DataRoot $DataRoot -BinaryPath $BinaryPath -DeviceId @($c.whitelistDeviceIds) -DeniedDeviceId @($c.blacklistDeviceIds)
   try{& $setup -Action Configure -InstallRoot $InstallRoot -DataRoot $DataRoot -ConfigText $raw.Text -ExpectedConfigHash (Get-FileHash (Join-Path $DataRoot 'config.json') -Algorithm SHA256).Hash}catch{& $setup -Action Uninstall -InstallRoot $InstallRoot -DataRoot $DataRoot;throw}
   $script:done=$true
   if(-not $session.Parent -or -not $session.Parent.HasExited){[void][Windows.Forms.MessageBox]::Show($form,'Installed and healthy. Reopen NVIDIA App.','GeForce Sidepiece','OK','Information')}
   $form.Close()
  }else{
   & $setup -Action Configure -InstallRoot $InstallRoot -DataRoot $DataRoot -ConfigText $raw.Text -ExpectedConfigHash $script:loadedHash
   Load-Configuration
   [void][Windows.Forms.MessageBox]::Show($form,'Validated and saved. Custom rules and service state preserved.','GeForce Sidepiece','OK','Information')
  }
 }catch{Show-Failure $_}finally{$save.Enabled=$true;$form.UseWaitCursor=$false;if($parentTimer){$parentTimer.Start()}}
})
$reload=[Windows.Forms.Button]::new();$reload.Text='Reload / discard edits';$reload.SetBounds(205,600,170,35);$reload.Anchor='Bottom,Left';$reload.Add_Click({try{Load-Configuration}catch{Show-Failure $_}});$form.Controls.Add($reload)
if(-not $Install){
 $start=[Windows.Forms.Button]::new();$start.Text='Start service';$start.SetBounds(385,600,140,35);$start.Anchor='Bottom,Left';$start.Add_Click({try{& $setup -Action Start -InstallRoot $InstallRoot -DataRoot $DataRoot;Refresh-Status}catch{Show-Failure $_}});$form.Controls.Add($start)
 $stop=[Windows.Forms.Button]::new();$stop.Text='Stop and restore';$stop.SetBounds(535,600,160,35);$stop.Anchor='Bottom,Left';$stop.Add_Click({try{& $setup -Action Stop -InstallRoot $InstallRoot -DataRoot $DataRoot;Refresh-Status}catch{Show-Failure $_}});$form.Controls.Add($stop)
}
try{
 $inventory=if($SmokeTest){@([pscustomobject]@{Name='Synthetic disabled GPU';DeviceId='ABCD_10DE_1234_5678_1';Status='Error';ProblemCode=22})}else{@(Get-SidepieceGpus)}
 foreach($gpu in $inventory){
  $item=[Windows.Forms.ListViewItem]::new([string]$gpu.Name);[void]$item.SubItems.Add($gpu.DeviceId);[void]$item.SubItems.Add(([string]$gpu.Status+' (code '+$gpu.ProblemCode+')'));[void]$list.Items.Add($item)
 }
 Load-Configuration
 if($SmokeTest){
  if(-not $Install){throw 'UI smoke mode requires -Install and never installs anything.'}
  $custom=$raw.Text|ConvertFrom-Json
  $custom.rules+=@{endpoint='customMetadata';method='GET';overrides=@(@{field='mode';from='old';to='new'})}
  $raw.Text=$custom|ConvertTo-Json -Depth 64
  $allow.Text='ABCD_10DE_1234_5678_1';$deny.Text='FFFF_10DE_0000_0000_1';$enabled.Checked=$true
  Sync-Basic
  $c=$raw.Text|ConvertFrom-Json
  if($c.whitelistDeviceIds[0] -ne 'ABCD_10DE_1234_5678_1' -or $c.blacklistDeviceIds[0] -ne 'FFFF_10DE_0000_0000_1' -or $c.rules.Count -ne 3 -or $c.rules[2].overrides[0].to -ne 'new' -or $list.Items.Count -ne 1){throw 'UI synchronization/custom-rule preservation failed'}
  $tabs.SelectedTab=$advanced;$tabs.SelectedTab=$basic
  $save.Enabled=$false;$reload.Enabled=$false
  $script:shownVerified=$false
  $smokeTimer=[Windows.Forms.Timer]::new();$smokeTimer.Interval=if($session.Parent){15000}else{600}
  $smokeTimer.Add_Tick({
   $script:shownVerified=$form.Visible -and [SidepieceUi.Window]::IsWindowVisible($form.Handle)
   $smokeTimer.Stop();$form.Close()
  })
  $form.Add_Shown({$script:shownVerified=$form.Visible -and [SidepieceUi.Window]::IsWindowVisible($form.Handle);$smokeTimer.Start()})
 }
 if($session.Parent -and $session.Parent.HasExited){exit 2}
 if($session.Owner){[void]$form.ShowDialog($session.Owner)}else{[void]$form.ShowDialog()}
 if($SmokeTest){
  if(-not $script:shownVerified){throw 'Configurator window was not visibly shown.'}
  Write-Host 'Shown WinForms window and basic/advanced synchronization passed; no service changes.'
 }
 if($Install -and -not $script:done){exit 2}
}finally{$form.Dispose()}
}finally{
 if($parentTimer){$parentTimer.Dispose()};if($smokeTimer){$smokeTimer.Dispose()}
 Close-SidepieceUiSession $session
}
