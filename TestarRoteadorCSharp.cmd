@echo off
rem Compila o C# e roda o teste que compara o roteador em C# com o GDScript.
rem Feche os editores do Godot antes. A saída também vai para evidence\csharp-router\saida.txt.
setlocal
set "GODOT_MONO=D:\Downloads Chrome\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe"
set "NUPKGS=D:\Downloads Chrome\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64\GodotSharp\Tools\nupkgs"
set "SAIDA=%~dp0evidence\csharp-router\saida.txt"
cd /d "%~dp0"
if not exist "evidence\csharp-router" mkdir "evidence\csharp-router"

echo === dotnet build === > "%SAIDA%"
dotnet restore Harbor.csproj --source "%NUPKGS%" --source https://api.nuget.org/v3/index.json >> "%SAIDA%" 2>&1
dotnet build Harbor.csproj --no-restore >> "%SAIDA%" 2>&1
if errorlevel 1 (
  echo A compilacao falhou. Veja %SAIDA%
  type "%SAIDA%"
  pause
  exit /b 1
)

echo. >> "%SAIDA%"
echo === teste === >> "%SAIDA%"
"%GODOT_MONO%" --path . --script res://tests/dispatch/test_road_graph_native.gd >> "%SAIDA%" 2>&1
set RESULTADO=%errorlevel%
echo. >> "%SAIDA%"
echo codigo de saida: %RESULTADO% >> "%SAIDA%"

type "%SAIDA%"
echo.
echo Saida gravada em %SAIDA%
pause
exit /b %RESULTADO%
