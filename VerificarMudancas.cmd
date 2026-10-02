@echo off
rem Verifica o projeto no Godot .NET e grava os resultados em evidence\csharp-router.
rem Encerre o jogo antes; o editor pode permanecer aberto.
setlocal enabledelayedexpansion
set "GODOT_MONO=D:\Downloads Chrome\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe"
set "SAIDA=%~dp0evidence\csharp-router\verificacao.txt"
cd /d "%~dp0"
if not exist "evidence\csharp-router" mkdir "evidence\csharp-router"
echo Verificacao iniciada em %date% %time% > "%SAIDA%"
set FALHAS=0

echo Preparando o Godot .NET e compilando o C#...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Open.ps1" -PrepareOnly -GodotPath "%GODOT_MONO%" >> "%SAIDA%" 2>&1
if errorlevel 1 (
  echo [FALHOU] preparacao do projeto - veja %SAIDA%
  pause
  exit /b 1
)

call :rodar "MONO  " "%GODOT_MONO%"

echo.
if %FALHAS%==0 (echo RESULTADO: tudo passou) else (echo RESULTADO: %FALHAS% falha^(s^) - mande o arquivo %SAIDA%)
echo.
echo Falta so abrir o jogo ^(Jogar.cmd^) e ver que carrega e anda.
pause
exit /b %FALHAS%

:rodar
set "ROTULO=%~1"
set "EXE=%~2"
call :um "%ROTULO%" "%EXE%" res://tests/test_regions.gd
call :um "%ROTULO%" "%EXE%" res://tests/test_bridge_approach_terrain.gd
call :um "%ROTULO%" "%EXE%" res://tests/test_native_driving.gd -- --no-save
call :um "%ROTULO%" "%EXE%" res://tests/cold/test_admission.gd
call :um "%ROTULO%" "%EXE%" res://tests/dispatch/test_dispatch_rules.gd
call :um "%ROTULO%" "%EXE%" res://tests/dispatch/test_dispatch_police.gd
call :um "%ROTULO%" "%EXE%" res://tests/dispatch/test_dispatch_emergency.gd
call :um "%ROTULO%" "%EXE%" res://tests/test_feedback_police_access.gd
exit /b 0

:um
echo. >> "%SAIDA%"
echo ===== [%~1] %~3 %~4 %~5 ===== >> "%SAIDA%"
"%~2" --path . --script %~3 %~4 %~5 >> "%SAIDA%" 2>&1
if errorlevel 1 (
  echo [FALHOU] [%~1] %~3
  set /a FALHAS+=1
) else (
  echo [OK]     [%~1] %~3
)
exit /b 0
