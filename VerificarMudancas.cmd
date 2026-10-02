@echo off
rem Roda a verificacao minima do CLAUDE.md duas vezes: com o Godot PADRAO (caminho GDScript, sem C#)
rem e com o Godot MONO (caminho C#). Mostra OK/FALHOU por teste e grava tudo em
rem evidence\csharp-router\verificacao.txt. Feche os editores do Godot antes.
setlocal enabledelayedexpansion
set "GODOT_PADRAO=D:\Downloads Chrome\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
set "GODOT_MONO=D:\Downloads Chrome\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe"
set "SAIDA=%~dp0evidence\csharp-router\verificacao.txt"
cd /d "%~dp0"
if not exist "evidence\csharp-router" mkdir "evidence\csharp-router"
echo Verificacao iniciada em %date% %time% > "%SAIDA%"
set FALHAS=0

echo Compilando o C#...
dotnet build Harbor.csproj --no-restore >> "%SAIDA%" 2>&1
if errorlevel 1 (
  echo [FALHOU] dotnet build - veja %SAIDA%
  set /a FALHAS+=1
)

call :rodar "PADRAO" "%GODOT_PADRAO%"
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
