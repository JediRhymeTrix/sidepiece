#ifndef ProductVersion
  #error ProductVersion required
#endif
[Setup]
AppId={{87258112-18CA-4D9C-884E-4E739164930B}
AppName=GeForce Sidepiece
AppVersion={#ProductVersion}
AppPublisher=JediRhymeTrix
AppPublisherURL=https://github.com/JediRhymeTrix/sidepiece
DefaultDirName={autopf}\GeForce Sidepiece
DisableDirPage=yes
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
LicenseFile=..\LICENSE
OutputDir=..\dist
OutputBaseFilename=Sidepiece-Setup-{#ProductVersion}-windows-x64
Compression=lzma2
SolidCompression=yes
CloseApplications=no
RestartApplications=no
UninstallDisplayName=GeForce Sidepiece
SetupLogging=yes
SetupMutex=Global\GeForceSidepiece.Setup
[Files]
Source: "..\build\installer-payload\*"; DestDir: "{tmp}\sidepiece-payload"; Flags: dontcopy recursesubdirs
Source: "..\build\installer-payload\*"; DestDir: "{app}\payload"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{commonprograms}\Configure GeForce Sidepiece"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -STA -ExecutionPolicy Bypass -File ""{app}\payload\scripts\Configure.ps1"""; WorkingDir: "{app}"
[Code]
var
  BackendAttempted, HadService, SetupCompleted: Boolean;
function GetCurrentProcessId: LongWord;
  external 'GetCurrentProcessId@kernel32.dll stdcall';
function BackendParams(Base, Action: String): String;
begin
  Result := '-NoProfile -STA -ExecutionPolicy Bypass -File "' + Base + '\scripts\Installer.ps1" -Action ' + Action + ' -InstallRoot "' + ExpandConstant('{app}') + '"';
end;
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  Code, ShowMode: Integer;
  Args, Gpus: String;
begin
  Result := '';
  ExtractTemporaryFiles('{tmp}\sidepiece-payload\*');
  Args := BackendParams(ExpandConstant('{tmp}\sidepiece-payload'), 'Install');
  Gpus := ExpandConstant('{param:GPU|}');
  if Gpus <> '' then begin
    if (Pos('"', Gpus) > 0) or (Pos(' ', Gpus) > 0) then begin
      Result := 'Invalid GPU parameter.';
      Exit;
    end;
    Args := Args + ' -DeviceIds "' + Gpus + '"';
  end;
  ShowMode := SW_SHOWNORMAL;
  if WizardSilent then begin
    Args := Args + ' -Silent';
    ShowMode := SW_HIDE;
  end else
    Args := Args + ' -OwnerWindow ' + IntToStr(WizardForm.Handle) + ' -OwnerProcessId ' + IntToStr(GetCurrentProcessId);
  if not BackendAttempted then
    HadService := RegKeyExists(HKLM, 'SYSTEM\CurrentControlSet\Services\GeForceSidepiece');
  BackendAttempted := True;
  if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Args, '', ShowMode, ewWaitUntilTerminated, Code) then
    Result := 'Unable to launch Windows PowerShell setup.'
  else if Code <> 0 then
    Result := 'Service setup was cancelled or refused. Check NVIDIA App, existing bridges, port 80 and retained recovery data. No successful installation is claimed.';
end;
procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssDone then SetupCompleted := True;
#ifdef InstallerFailureTest
  if CurStep = ssInstall then RaiseException('Injected test failure after backend activation.');
#endif
end;
procedure DeinitializeSetup;
var
  Code: Integer;
  Args, Recovery: String;
begin
  if not BackendAttempted or HadService or SetupCompleted then Exit;
  if not RegKeyExists(HKLM, 'SYSTEM\CurrentControlSet\Services\GeForceSidepiece') then Exit;
  Code := -1;
  Recovery := ExpandConstant('{app}\service\Recover.ps1');
  if not FileExists(Recovery) then Exit;
  Args := '-NoProfile -ExecutionPolicy Bypass -File "' + Recovery + '" -Action Uninstall -InstallRoot "' + ExpandConstant('{app}\service') + '"';
  if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Args, '', SW_HIDE, ewWaitUntilTerminated, Code) then
    Log('Recovery helper could not launch; retain service files and use Recover.ps1 -Action Uninstall.');
  if Code <> 0 then
    Log('Automatic restoration failed; retain route.key and use the protected service recovery helper.');
end;
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Code, ShowMode: Integer;
  Args: String;
begin
  if CurUninstallStep <> usUninstall then Exit;
  Args := BackendParams(ExpandConstant('{app}\payload'), 'Uninstall');
  ShowMode := SW_SHOWNORMAL;
  if UninstallSilent then begin
    Args := Args + ' -Silent';
    ShowMode := SW_HIDE;
  end else
    Args := Args + ' -OwnerWindow ' + IntToStr(UninstallProgressForm.Handle) + ' -OwnerProcessId ' + IntToStr(GetCurrentProcessId);
  if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Args, '', ShowMode, ewWaitUntilTerminated, Code) then
    RaiseException('Unable to launch safe service removal; files retained.');
  if Code <> 0 then
    RaiseException('Could not safely restore/remove the service. Files and recovery data retained. Resolve the restore error before uninstalling.');
end;
