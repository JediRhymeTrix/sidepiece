[CmdletBinding()]
param([switch]$Analyze,[switch]$SkipTests)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$build=Join-Path $root 'build'
New-Item -ItemType Directory -Path $build -Force | Out-Null
$vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs=& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if(-not $vs){throw 'Install Visual Studio C++ Build Tools and Windows SDK.'}
$version=([IO.File]::ReadAllText((Join-Path $root 'VERSION'))).Trim()
if($version -notmatch '^\d+\.\d+\.\d+$'){throw 'Invalid VERSION'}
$extra=if($Analyze){'/analyze'}else{''}
$targets=@(@{source='src\main.cpp';name='sidepiece'},@{source='tests\core_tests.cpp';name='core_tests'},@{source='tests\proxy_tests.cpp';name='proxy_tests'},@{source='tests\rules_tests.cpp';name='rules_tests'})
foreach($target in $targets){
    $cmd='call "'+$vs+'\Common7\Tools\VsDevCmd.bat" -arch=x64 -host_arch=x64 >nul && cl /nologo /std:c++17 /EHsc /O1 /MT /W4 /WX /wd4505 /utf-8 '+$extra+' /DSIDEPIECE_VERSION=\"'+$version+'\" "'+(Join-Path $root $target.source)+'" /Fo"'+$build+'\'+$target.name+'.obj" /Fe"'+$build+'\'+$target.name+'.exe" /link advapi32.lib /INCREMENTAL:NO /OPT:REF /OPT:ICF /DYNAMICBASE /NXCOMPAT'
    & $env:ComSpec /d /s /c $cmd
    if($LASTEXITCODE){throw ('Build failed: '+$target.name)}
}
if(-not $SkipTests){
    foreach($name in 'core_tests','proxy_tests','rules_tests'){
        $p=Start-Process -FilePath (Join-Path $build ($name+'.exe')) -PassThru -NoNewWindow
        if(-not $p.WaitForExit(30000)){$p.Kill();throw ('Test timeout: '+$name)}
        if($p.ExitCode){throw ('Test failed: '+$name)}
    }
}
