#requires -Version 5.1
function Open-SidepieceUiSession([long]$OwnerWindow=0,[int]$OwnerProcessId=0){
 if(-not ('SidepieceUi.Window' -as [type])){
  Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;
namespace SidepieceUi {
 public sealed class Window : IWin32Window {
  public IntPtr Handle { get; private set; }
  public Window(long handle) { Handle = new IntPtr(handle); }
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr handle);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr handle);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr handle, out uint pid);
  private delegate bool EnumProc(IntPtr handle, IntPtr state);
  [DllImport("user32.dll")] private static extern bool EnumWindows(EnumProc callback, IntPtr state);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] private static extern int GetWindowText(IntPtr handle, StringBuilder text, int count);
  public static bool HasVisibleConfiguration(int processId) {
   bool found=false;
   EnumWindows(delegate(IntPtr handle, IntPtr state) {
    uint pid; GetWindowThreadProcessId(handle, out pid);
    var text=new StringBuilder(256); GetWindowText(handle,text,text.Capacity);
    if(pid==processId && IsWindowVisible(handle) && text.ToString()=="GeForce Sidepiece - Configuration") { found=true; return false; }
    return true;
   },IntPtr.Zero);
   return found;
  }
 }
}
'@
 }
 $parent=$null;$owner=$null
 if($OwnerWindow -or $OwnerProcessId){
  if(-not $OwnerWindow -or $OwnerProcessId -le 0){throw 'Incomplete installer window identity.'}
  $owner=[SidepieceUi.Window]::new($OwnerWindow);[uint32]$windowPid=0
  [void][SidepieceUi.Window]::GetWindowThreadProcessId($owner.Handle,[ref]$windowPid)
  $actualParent=(Get-CimInstance Win32_Process -Filter "ProcessId=$PID").ParentProcessId
  if(-not [SidepieceUi.Window]::IsWindow($owner.Handle) -or $windowPid -ne $OwnerProcessId -or $actualParent -ne $OwnerProcessId){throw 'Invalid installer window identity.'}
  $parent=Get-Process -Id $OwnerProcessId -ErrorAction Stop
  # Open the process handle now so PID reuse cannot adopt a different installer.
  $null=$parent.Handle
  if($parent.HasExited){$parent.Dispose();throw 'Installer has exited.'}
 }
 $mutex=[Threading.Mutex]::new($false,'Global\GeForceSidepiece.Configuration')
 $held=$false
 try{
  try{$held=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$held=$true}
  if(-not $held){throw 'Another Sidepiece configuration or installer session is already open. Close it before retrying.'}
  [pscustomobject]@{Mutex=$mutex;Parent=$parent;Owner=$owner}
 }catch{$mutex.Dispose();if($parent){$parent.Dispose()};throw}
}
function Close-SidepieceUiSession($Session){
 if($Session){$Session.Mutex.ReleaseMutex();$Session.Mutex.Dispose();if($Session.Parent){$Session.Parent.Dispose()}}
}
