@echo off
rem Entrada compartilhada com Jogar.cmd: Godot MONO e roteador C# (RoadGraphSearch.cs).
rem O log registra "csharp_build" e "router_native" para saber qual caminho estava ativo.
rem Logs essenciais por padrao. Diagnostico completo: JogarDiagnostico.cmd.
rem HARBOR_SESSION_PROFILE=1 e HARBOR_STALL_LOG=1 continuam disponiveis separadamente.
rem Teste de A/B da espiral de fisica: teto de 3 passos por quadro (o padrao do motor e 8).
rem Para voltar ao padrao: set HARBOR_MAX_PHYSICS_STEPS=8 antes de rodar este arquivo.
if not defined HARBOR_MAX_PHYSICS_STEPS set "HARBOR_MAX_PHYSICS_STEPS=3"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\Open.ps1" -PauseUsageMonitor
if errorlevel 1 pause
