@echo off
set "variant=%~1"
if not defined variant set "variant=Depois"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Compare-MountainTerrain.ps1" -Variant "%variant%"
exit /b %errorlevel%
