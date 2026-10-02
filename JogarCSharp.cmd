@echo off
rem Entrada compartilhada com Jogar.cmd: Godot MONO e roteador C# (RoadGraphSearch.cs).
rem O log registra "csharp_build" e "router_native" para saber qual caminho estava ativo.
if not defined HARBOR_STALL_LOG set "HARBOR_STALL_LOG=1"
rem Teste de A/B da espiral de fisica: teto de 3 passos por quadro (o padrao do motor e 8).
rem Para voltar ao padrao: set HARBOR_MAX_PHYSICS_STEPS=8 antes de rodar este arquivo.
if not defined HARBOR_MAX_PHYSICS_STEPS set "HARBOR_MAX_PHYSICS_STEPS=3"
set "GODOT_EXE=D:\Downloads Chrome\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64.exe"
cd /d "%~dp0"
if not exist ".godot\mono\temp\obj\project.assets.json" (
  dotnet restore Harbor.csproj --source "D:\Downloads Chrome\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64\GodotSharp\Tools\nupkgs" --source https://api.nuget.org/v3/index.json
  if errorlevel 1 (
    echo A preparacao do C# falhou.
    pause
    exit /b 1
  )
)
dotnet build Harbor.csproj --no-restore
if errorlevel 1 (
  echo A compilacao do C# falhou.
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Open.ps1"
if errorlevel 1 pause
