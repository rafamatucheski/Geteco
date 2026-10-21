@echo off
setlocal
set "HARBOR_SESSION_LOG=1"
set "HARBOR_SESSION_PROFILE=1"
set "HARBOR_STALL_LOG=1"
call "%~dp0Jogar.cmd"
exit /b %errorlevel%
