@echo off
setlocal
rem A/B do crash de 29/10 (c0000005 em GetecoV2.exe+0x279942d, ordenacao dos transparentes no desenho):
rem motoristas visiveis do transito desligados (GETECO_TRAFFIC_DRIVERS=0, dc548db8), o suspeito pela ordem
rem dos fatos. Mantem o registro de travadas e o de congelamento (hang-*.log); sem a sonda de pipelines,
rem que so pesa. O .NET do jogo grava um dump no crash (createdump do CoreCLR), sem mexer no registro do
rem Windows: evidence\crash-dumps\GetecoV2-<pid>.dmp.
set "HARBOR_SESSION_LOG=1"
set "HARBOR_STALL_LOG=1"
set "HARBOR_STALL_STACKS=1"
set "GETECO_TRAFFIC_DRIVERS=0"
if not exist "%~dp0evidence\crash-dumps" mkdir "%~dp0evidence\crash-dumps"
set "DOTNET_DbgEnableMiniDump=1"
set "DOTNET_DbgMiniDumpType=1"
set "DOTNET_DbgMiniDumpName=%~dp0evidence\crash-dumps\GetecoV2-%%p.dmp"
call "%~dp0Jogar.cmd"
exit /b %errorlevel%
