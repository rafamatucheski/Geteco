@echo off
rem O jogo principal usa o Godot .NET e compila o roteador C# antes de abrir.
call "%~dp0JogarCSharp.cmd"
exit /b %errorlevel%
