@echo off
if not exist "%APPDATA%\GetecoV2\session-logs" mkdir "%APPDATA%\GetecoV2\session-logs"
explorer.exe "%APPDATA%\GetecoV2\session-logs"
