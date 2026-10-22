@echo off
setlocal
rem Joga pelo export release (tools\PlayRelease.ps1): o binario do editor roda o GDScript com as
rem verificacoes de depuracao e mediu p50 ~38%% maior na mesma rota (docs\perf-playthrough-20261021.md).
rem Exporta para builds\jogar\ so quando algum arquivo do jogo mudou; o save e as opcoes sao os mesmos.
rem Pelo binario do editor, como antes: JogarCSharp.cmd. Diagnostico pesado: JogarDiagnostico.cmd.
rem Logs essenciais (sessao e travadas); perfil por sistema e pilhas so para cacar picos.
set "HARBOR_SESSION_LOG=1"
set "HARBOR_STALL_LOG=1"
rem Mesmo teto de passos de fisica do JogarCSharp.cmd (o padrao do motor e 8).
if not defined HARBOR_MAX_PHYSICS_STEPS set "HARBOR_MAX_PHYSICS_STEPS=3"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\PlayRelease.ps1" -PauseUsageMonitor
if errorlevel 1 pause
exit /b %errorlevel%
