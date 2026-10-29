@echo off
setlocal
rem Log completo para cacar travadas jogando: o mesmo do JogarDiagnostico.cmd mais a pilha nativa da thread
rem principal nas travadas (StallStackSampler) e a sonda que diz qual material criou cada pipeline nova
rem (PipelineProbe). Na partida de 29/10 os quadros de 1,2-1,75 s tinham script em ~10 ms e
rem specialization/surface subindo: o tempo estava no desenho, e so esses dois registros dizem onde.
rem A sonda custa CPU por no novo: serve para atribuir a causa, nao para medir tempo de quadro.
set "HARBOR_SESSION_LOG=1"
set "HARBOR_SESSION_PROFILE=1"
set "HARBOR_STALL_LOG=1"
set "HARBOR_STALL_STACKS=1"
set "GETECO_PIPELINE_PROBE=1"
call "%~dp0Jogar.cmd"
exit /b %errorlevel%
