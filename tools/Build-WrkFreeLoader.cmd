@echo off
rem Build-WrkFreeLoader.cmd [ReactOSRoot] [/N]
rem
rem Reproducible recipe for the ReactOS _bootldr (FreeLoader) x86 build:
rem   modern MSVC via vcvarsall x86 + CMake/Ninja + portable WinFlexBison.
rem WRK's kernel itself is NOT built here (see tools\Build-WrkX86.cmd).
rem
rem   ReactOSRoot   path to the reactos checkout (default: <repo>\..\reactos)
rem   /N            print-only dry run - performs all read-only prerequisite
rem                 and build-cache validation, then exits WITHOUT executing
rem                 cmake, compilers, mkdir, or log writes.
setlocal EnableExtensions DisableDelayedExpansion

for %%I in ("%~dp0..") do set "WRK_ROOT=%%~fI"
if not "%WRK_ROOT%"=="%WRK_ROOT: =%" (
    echo ERROR: repository path contains spaces: "%WRK_ROOT%"
    exit /b 1
)

set "DRYRUN="
set "ROSARG="
:argloop
if "%~1"=="" goto argsdone
if /i "%~1"=="/N" (
    set "DRYRUN=1"
) else (
    if defined ROSARG (echo Usage: %~nx0 [ReactOSRoot] [/N]& exit /b 2)
    set "ROSARG=%~1"
)
shift
goto argloop
:argsdone

if defined ROSARG (set "ROSDIR=%ROSARG%") else (set "ROSDIR=%WRK_ROOT%\..\reactos")
for %%I in ("%ROSDIR%") do set "ROSDIR=%%~fI"

set "BUILDDIR=%WRK_ROOT%\artifacts\freeldr-build-x86"
set "WFB=%WRK_ROOT%\.tools\winflexbison-2.5.25"
set "LOGDIR=%WRK_ROOT%\artifacts\logs"
set "CMAKE=C:\Strawberry\c\bin\cmake.exe"
set "VCVARS=C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvarsall.bat"
set "ROS_FWD=%ROSDIR:\=/%"

rem The generated host-tools\cmake_shim.cmd runs vcvarsall /clean_env and
rem wipes PATH, so the host-tools subconfigure cannot see tools on PATH.
rem host-tools.cmake appends CMAKE_HOST_TOOLS_EXTRA_ARGS to the
rem subconfigure's CMAKE_ARGS; passing absolute -D paths through that seam
rem is the supported fix (survives /clean_env).
set "EXTRA=-DCMAKE_HOST_TOOLS_EXTRA_ARGS:STRING=-DBISON_EXECUTABLE=%WFB%\win_bison.exe;-DFLEX_EXECUTABLE=%WFB%\win_flex.exe"

echo Recipe:
echo   call "%VCVARS%" x86
echo   set PATH=%WFB%;%%PATH%%   ^(plus CL/_CL_/LINK/_LINK_ deleted; LIB/INCLUDE kept^)
echo   "%CMAKE%" -S "%ROSDIR%" -B "%BUILDDIR%" -G Ninja -DCMAKE_TOOLCHAIN_FILE="%ROSDIR%\toolchain-msvc.cmake" -DARCH:STRING=i386 -DSARCH:STRING=pc -DCMAKE_GENERATOR_PLATFORM= -DCMAKE_BUILD_TYPE=Debug -DRUNTIME_CHECKS=OFF -DBISON_EXECUTABLE="%WFB%\win_bison.exe" -DFLEX_EXECUTABLE="%WFB%\win_flex.exe" "%EXTRA%"
echo   "%CMAKE%" --build "%BUILDDIR%" --target wrkboot isoboot --parallel 2

rem ---- read-only prerequisite checks (also exercised by /N) ---------------
if not exist "%ROSDIR%\toolchain-msvc.cmake" (echo ERROR: ReactOS toolchain-msvc.cmake missing under %ROSDIR%& exit /b 1)
if not exist "%ROSDIR%\_bootldr" (echo ERROR: %ROSDIR%\_bootldr missing& exit /b 1)
if not exist "%CMAKE%" (echo ERROR: cmake not found at %CMAKE%& exit /b 1)
if not exist "%VCVARS%" (echo ERROR: vcvarsall.bat not found - expected VS BuildTools x86 env& exit /b 1)
if not exist "%WFB%\win_bison.exe" (
    echo ERROR: portable WinFlexBison missing at %WFB%
    echo Prerequisite: approved portable win_flex_bison-2.5.25 package
    echo extracted under .tools. This script does not download.
    exit /b 1
)
if not exist "%WFB%\win_flex.exe" (echo ERROR: %WFB%\win_flex.exe missing& exit /b 1)

rem ---- read-only cache identity check -------------------------------------
rem Reuse an existing build dir only if its cache provably matches THIS
rem source tree, toolchain file, Ninja (not Multi-Config), ARCH=i386 and
rem SARCH=pc. Exact whole-line comparisons; a foreign cache is an error,
rem a missing cache just means "needs configure". Flat flow (no nested
rem parenthesized blocks) because exit /b inside double-nested parens
rem silently loses the exit code.
set "MATCHING_CACHE="
if not exist "%BUILDDIR%\CMakeCache.txt" goto cachedone

findstr /i /l /x /c:"CMAKE_HOME_DIRECTORY:INTERNAL=%ROS_FWD%" "%BUILDDIR%\CMakeCache.txt" >nul || goto badhome
findstr /i /l /x /c:"CMAKE_TOOLCHAIN_FILE:FILEPATH=%ROS_FWD%/toolchain-msvc.cmake" "%BUILDDIR%\CMakeCache.txt" >nul || goto badtc
findstr /l /x /c:"CMAKE_GENERATOR:INTERNAL=Ninja" "%BUILDDIR%\CMakeCache.txt" >nul || goto badgen
findstr /i /l /x /c:"ARCH:STRING=i386" "%BUILDDIR%\CMakeCache.txt" >nul && goto archok
findstr /i /l /x /c:"ARCH:UNINITIALIZED=i386" "%BUILDDIR%\CMakeCache.txt" >nul || goto badarch
:archok
findstr /i /l /x /c:"SARCH:STRING=pc" "%BUILDDIR%\CMakeCache.txt" >nul || goto badsarch
set "MATCHING_CACHE=1"
echo Cache check: %BUILDDIR% was configured for this source/toolchain/arch - will reuse.
goto cachedone

:badhome
echo ERROR: %BUILDDIR%\CMakeCache.txt names a different source tree - refusing.
exit /b 1
:badtc
echo ERROR: cache toolchain file is not %ROS_FWD%/toolchain-msvc.cmake - refusing.
exit /b 1
:badgen
echo ERROR: cache generator is not exactly Ninja - refusing.
exit /b 1
:badarch
echo ERROR: cache ARCH is not i386 - refusing.
exit /b 1
:badsarch
echo ERROR: cache SARCH is not pc - refusing.
exit /b 1
:cachedone

if defined DRYRUN (
    echo DRY RUN - nothing executed ^(no mkdir, no logs, no cmake/compilers^).
    exit /b 0
)

if not exist "%LOGDIR%" mkdir "%LOGDIR%"
if defined MATCHING_CACHE goto build

call "%VCVARS%" x86 || (echo ERROR: vcvarsall failed& exit /b 1)
set "PATH=%WFB%;%PATH%"
set "CL="
set "_CL_="
set "LINK="
set "_LINK_="

"%CMAKE%" -S "%ROSDIR%" -B "%BUILDDIR%" -G Ninja ^
 -DCMAKE_TOOLCHAIN_FILE="%ROSDIR%\toolchain-msvc.cmake" ^
 -DARCH:STRING=i386 -DSARCH:STRING=pc -DCMAKE_GENERATOR_PLATFORM= ^
 -DCMAKE_BUILD_TYPE=Debug -DRUNTIME_CHECKS=OFF ^
 -DBISON_EXECUTABLE="%WFB%\win_bison.exe" ^
 -DFLEX_EXECUTABLE="%WFB%\win_flex.exe" ^
 "%EXTRA%" > "%LOGDIR%\freeldr-configure.log" 2>&1
set "RC=%ERRORLEVEL%"
echo configure exit %RC% - log: %LOGDIR%\freeldr-configure.log
if not "%RC%"=="0" exit /b %RC%

:build
call "%VCVARS%" x86 >nul 2>&1 || (echo ERROR: vcvarsall failed& exit /b 1)
set "PATH=%WFB%;%PATH%"
set "CL="
set "_CL_="
set "LINK="
set "_LINK_="
"%CMAKE%" --build "%BUILDDIR%" --target wrkboot isoboot --parallel 2 > "%LOGDIR%\freeldr-build.log" 2>&1
set "RC=%ERRORLEVEL%"
echo build exit %RC% - log: %LOGDIR%\freeldr-build.log
exit /b %RC%
