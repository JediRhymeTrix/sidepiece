#requires -Version 5.1
function ConvertTo-MetadataId([string]$HardwareId,[string]$InstanceSuffix='1') {
 if($InstanceSuffix -notmatch '^[0-9]{1,20}$'){throw 'Instance suffix must be 1-20 decimal digits.'}
 if($HardwareId -notmatch '(?i)^PCI\\VEN_10DE&DEV_([0-9A-F]{4})&SUBSYS_([0-9A-F]{4})([0-9A-F]{4})(?:&|\\|$)'){return $null}
 $id=('{0}_10DE_{1}_{2}_{3}' -f $Matches[1],$Matches[2],$Matches[3],$InstanceSuffix).ToUpperInvariant()
 if($id.Length -gt 40){throw 'Metadata ID exceeds 40 characters.'}
 return $id
}
function Get-SidepieceGpus {
 # Win32_PnPEntity includes disabled display devices that VideoController may omit.
 Get-CimInstance Win32_PnPEntity -Filter "PNPClass='Display'" | ForEach-Object {
  $id=ConvertTo-MetadataId $_.PNPDeviceID
  if($id){[pscustomobject]@{Name=$_.Name;DeviceId=$id;HardwareId=$_.PNPDeviceID;Status=$_.Status;ProblemCode=$_.ConfigManagerErrorCode}}
 }
}
