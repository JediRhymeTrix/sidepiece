#requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Gpu.ps1')
if((ConvertTo-MetadataId 'PCI\VEN_10DE&DEV_ABCD&SUBSYS_12345678&REV_A1') -cne 'ABCD_10DE_1234_5678_1'){throw 'PCI ID conversion failed'}
if((ConvertTo-MetadataId 'pci\ven_10de&dev_abcd&subsys_12345678&rev_a1' '2') -cne 'ABCD_10DE_1234_5678_2'){throw 'Suffix/case conversion failed'}
foreach($bad in 'PCI\VEN_8086&DEV_ABCD&SUBSYS_12345678','PCI\VEN_10DE&DEV_ABCD','PCI\VEN_10DE&DEV_ABCD&SUBSYS_123456789'){if(ConvertTo-MetadataId $bad){throw 'Malformed/non-NVIDIA ID accepted'}}
$rejected=$false;try{ConvertTo-MetadataId 'PCI\VEN_10DE&DEV_ABCD&SUBSYS_12345678' 'bad'}catch{$rejected=$true};if(-not $rejected){throw 'Bad suffix accepted'}
function Get-CimInstance {
 param($ClassName,$Filter)
 if($ClassName -ne 'Win32_PnPEntity' -or $Filter -ne "PNPClass='Display'"){throw 'Inventory no longer uses PnP display entities'}
 [pscustomobject]@{Name='Synthetic disabled NVIDIA';PNPDeviceID='PCI\VEN_10DE&DEV_ABCD&SUBSYS_12345678';Status='Error';ConfigManagerErrorCode=22}
}
$gpus=@(Get-SidepieceGpus)
if($gpus.Count -ne 1 -or $gpus[0].ProblemCode -ne 22 -or $gpus[0].DeviceId -ne 'ABCD_10DE_1234_5678_1'){throw 'Disabled GPU omitted'}
Write-Host 'GPU conversion and disabled-device inventory checks passed.'
