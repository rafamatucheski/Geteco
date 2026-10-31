@echo off
setlocal
rem Mesmo log completo do JogarLogCompleto.cmd, mas abrindo o editor: o jogo que o editor roda (F5) herda
rem estas variaveis. Feito para o ramo jolt, onde o usuario valida a troca de motor pelo editor.
set "HARBOR_SESSION_LOG=1"
set "HARBOR_SESSION_PROFILE=1"
set "HARBOR_STALL_LOG=1"
set "HARBOR_STALL_STACKS=1"
if not exist "%~dp0..\..\evidence\crash-dumps" mkdir "%~dp0..\..\evidence\crash-dumps"
set "DOTNET_DbgEnableMiniDump=1"
set "DOTNET_DbgMiniDumpType=2"
set "DOTNET_DbgMiniDumpName=%~dp0..\..\evidence\crash-dumps\GetecoV2-%%p.dmp"
call "%~dp0..\..\Editar.cmd"
exit /b %errorlevel%
