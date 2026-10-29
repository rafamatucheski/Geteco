@echo off
setlocal
rem Log completo para cacar travadas e crash jogando: sessao, perfil por sistema, travadas, pilha nativa da
rem thread principal (StallStackSampler, com arquivo hang-*.log em congelamento) e minidump do .NET no crash
rem (evidence\crash-dumps), sem mexer no registro do Windows. A sonda de pipelines (GETECO_PIPELINE_PROBE=1)
rem saiu daqui em 29/10: revarre ~10 mil nos a cada pipeline nova e gerava centenas de
rem "String formatting error"; ligue a mao quando precisar dela.
set "HARBOR_SESSION_LOG=1"
set "HARBOR_SESSION_PROFILE=1"
set "HARBOR_STALL_LOG=1"
set "HARBOR_STALL_STACKS=1"
if not exist "%~dp0evidence\crash-dumps" mkdir "%~dp0evidence\crash-dumps"
set "DOTNET_DbgEnableMiniDump=1"
set "DOTNET_DbgMiniDumpType=2"
set "DOTNET_DbgMiniDumpName=%~dp0evidence\crash-dumps\GetecoV2-%%p.dmp"
call "%~dp0Jogar.cmd"
exit /b %errorlevel%
