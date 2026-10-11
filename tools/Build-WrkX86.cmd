@echo off
rem Build-WrkX86.cmd [/N]
rem
rem Builds the WRK x86 kernel with the bundled TOOLS\X86 toolchain
rem (MSVC 13.10.4035, LINK 7.10.4035, NMAKE 7.00.8882). Incremental nmake
rem build only - no clean, no rebuild, no source/makefile changes.
rem Output: WRK-V1.2\BASE\NTOS\BUILD\EXE\wrkx86.exe (+ .pdb/.map/.lib/.exp/.def)
rem
rem   /N   nmake dry run - echoes commands without compiling or linking.
setlocal EnableExtensions DisableDelayedExpansion

if not "%~2"=="" goto usage
set "WRK_NMAKE_OPTS="
if "%~1"=="" goto args_done
if /i "%~1"=="/N" (set "WRK_NMAKE_OPTS=/N") else goto usage
:args_done

for %%I in ("%~dp0..") do set "WRK_ROOT=%%~fI"
if not "%WRK_ROOT%"=="%WRK_ROOT: =%" (
    echo ERROR: repository path contains spaces: "%WRK_ROOT%"
    echo The upstream WRK makefiles do not support spaces; relocate the repo.
    exit /b 1
)

set "WRK_NTOS=%WRK_ROOT%\WRK-V1.2\BASE\NTOS"
set "WRK_TOOLS=%WRK_ROOT%\WRK-V1.2\TOOLS\X86"
set "WRK_FXDIR=%SystemRoot%\Microsoft.NET\Framework\v4.0.30319"
set "WRK_LOGDIR=%WRK_ROOT%\artifacts\logs"
set "WRK_LOG=%WRK_LOGDIR%\build-wrk-x86.log"

if not exist "%WRK_NTOS%\MAKEFILE" (
    echo ERROR: %WRK_NTOS%\MAKEFILE not found - is this the WRK repo root?
    exit /b 1
)
for %%F in (NMAKE.EXE CL.EXE LINK.EXE LIB.EXE ML.EXE RC.EXE) do (
    if not exist "%WRK_TOOLS%\%%F" (
        echo ERROR: bundled tool missing: %WRK_TOOLS%\%%F
        exit /b 1
    )
)

rem The -Foobji386\ flag requires an obji386 dir inside every module BUILD
rem dir (dirs named BUILD that contain a MAKEFILE); EXE holds the final
rem image. Only obji386 is needed for x86.
for /d /r "%WRK_NTOS%" %%D in (BUILD) do (
    if exist "%%D\MAKEFILE" (
        if not exist "%%D\OBJI386" (
            mkdir "%%D\OBJI386" || (echo ERROR: cannot create %%D\OBJI386& exit /b 1)
        )
    )
)
if not exist "%WRK_NTOS%\BUILD\EXE" (
    mkdir "%WRK_NTOS%\BUILD\EXE" || (echo ERROR: cannot create %WRK_NTOS%\BUILD\EXE& exit /b 1)
)
if not exist "%WRK_LOGDIR%" (
    mkdir "%WRK_LOGDIR%" || (echo ERROR: cannot create %WRK_LOGDIR%& exit /b 1)
)

set "PATH=%WRK_TOOLS%;%WRK_FXDIR%;%PATH%"

rem TOOLS\X86 ships no cvtres.exe; link.exe invokes it to convert
rem PREBUILT\i386\ntoskrnl.res (LNK1158 otherwise). The installed .NET
rem Framework v4 runtime supplies a compatible one.
where cvtres.exe >nul 2>&1
if errorlevel 1 (
    echo ERROR: cvtres.exe not found on PATH ^(expected in %WRK_FXDIR%^).
    exit /b 1
)

rem Truly delete compiler/linker env flags. If an env var of the same name
rem exists when nmake starts, nmake exports the makefile's macro value
rem (e.g. LINK = link.exe -nologo) into spawned tools' environments and
rem link.exe then reads 'link.exe' as an input file (LNK1181).
set "CL="
set "_CL_="
set "LINK="
set "_LINK_="
set "LIB="
set "LIBPATH="
set "INCLUDE="

pushd "%WRK_NTOS%" || (echo ERROR: cannot cd to %WRK_NTOS%& exit /b 1)
if defined WRK_NMAKE_OPTS (
    echo Running nmake /N dry run ^(no build performed^). Log: %WRK_LOG%
) else (
    echo Building WRK x86 kernel ^(incremental^). Log: %WRK_LOG%
)
"%WRK_TOOLS%\NMAKE.EXE" -nologo %WRK_NMAKE_OPTS% x86= > "%WRK_LOG%" 2>&1
set "WRK_RC=%ERRORLEVEL%"
popd

if defined WRK_NMAKE_OPTS (
    if "%WRK_RC%"=="0" (
        echo Dry run finished ^(exit 0^); nothing was built. Log: %WRK_LOG%
    ) else (
        echo Dry run FAILED with exit %WRK_RC%. Log: %WRK_LOG%
    )
) else (
    if "%WRK_RC%"=="0" (
        echo Build succeeded: %WRK_NTOS%\BUILD\EXE\wrkx86.exe
    ) else (
        echo Build FAILED with exit %WRK_RC%. See %WRK_LOG%
    )
)
exit /b %WRK_RC%

:usage
echo Usage: %~nx0 [/N]
echo   /N   nmake dry run only - echoes commands, builds nothing.
exit /b 2
