# Diagnóstico detalhado de sessões — 11/10/2026

## Entrega

Schema 3 do logger .NET: detalhes de operações lentas independentes do limite
de frame, contagem de chamadas >=2 ms por sistema, preservação de detalhes do
streaming, início/fim de operações e acompanhamento pelo escritor durante
bloqueios da thread principal. Erros preservam suas pilhas e incluem contexto
de operações ativas; encerramento lista operações sem fechamento.

FullSession recebeu spans de criação/configuração em 31 sistemas já existentes,
sem mudar a ordem de inicialização. ProductionWorld publica suas etapas de
cronômetro também em partidas normais. StartupCurtain registra as mudanças de
etapa e suas durações. O leitor PowerShell oferece `-SummaryOnly`, rankings de
custo e carregamento, frequência de chamadas lentas, erros por origem e operações
sem conclusão. Dados são correlacionáveis, não diagnósticos automáticos de causa.

Limites explícitos: 128 operações abertas, 128 rótulos de custo por intervalo,
16 detalhes de operações >=2 ms por intervalo, fila de 8192 registros. O logger
não inspeciona todas as funções automaticamente. Duração de carregamento inclui
esperas; configurações que retornaram não são certificadas como funcionais.

## Validação funcional

- Godot 4.7.2 .NET, Harbor.csproj: build sem erros ou avisos.
- `tests/test_session_detail.py`: aprovado no motor real. Erro com operação
  ativa; bloqueio de 6,2 s com escritor ativo; início/fim e detalhes de carga;
  operação >=2 ms num intervalo <33,3 ms; saturação da lista detalhada com
  preservação das 20 chamadas agregadas; recuperação de JSON inválido; operação
  sem conclusão no encerramento.
- `tests/test_session_diagnostics.py`: aprovado. Erros GDScript/C#, mensagem
  de thread secundária, pausa/retomada, execução após erro com debugger real,
  duas sessões distintas e encerramento normal.
- Leitor PowerShell exercitado sobre a sessão do teste novo: ranking, origem
  do erro, quatro detalhes omitidos e operação sem fechamento presentes.

## Performance e limites da evidência

A medição anterior foi liberada antes das alterações. Primeira tentativa com
`measure_session_diagnostics.gd` descartada: zero pedestres e intervalos de frame
incompatíveis com apresentação normal. Não é baseline válido.

Nova rodada usa `measure_performance_plan.gd` com cena Main, população/trânsito
reais, saves desativados, dez segundos de aquecimento e trinta segundos medidos.
O wrapper valida apresentação nativa da janela pelo PID, monitora processos
concorrentes e compara hashes das fontes antes/depois.

Referência com `HARBOR_SESSION_PROFILE=0`: apresentação nativa completou; 109,63
FPS, p95 16,463 ms, p99 19,391 ms. **Inválida para aprovar regressão**: fontes
mudaram durante a execução, incluindo `runtime/Settings.gd`, catálogos de vozes
e ferramenta de validação de exportação. Não foram sobrescritas alterações
de outras sessões. O perfil desligado mantém erros e métricas gerais.

Evidências da rodada e da verificação com perfil ligado ficam em
`evidence/session-detail-20261011/`. A aprovação de performance depende de
comparativo válido com fontes estáveis. Não há certificação global de mapas,
transições, caos, sessões longas, saturação de disco ou crash fatal.

Rodada ligada: Main chegou à prontidão; o arquivo da sessão confirmou as 31
inicializações instrumentadas, etapas de mundo, custos recorrentes e operações
lentas. Nenhum `telemetry_error`, `logger_capture_error`, descarte da fila ou
overflow de operações; encerramento registrado sem operações abertas. O único
erro foi o timeout explícito do próprio medidor esperando apresentação nativa
da janela, e esse erro foi preservado pelo logger. Também houve mudanças
concorrentes em atividades e catálogos de localização/vozes. **Performance
inconclusiva**, sem comparação causal nem nova tentativa equivalente.

`production-log-check.json` guarda contagens e cobertura observada;
`production-summary.txt` exemplifica o resumo produzido pelo leitor. Esses
registros vieram de uma sessão de validação nova, sem analisar a sessão pessoal
indicada inicialmente pelo usuário. Logs continuam em `user://session-logs`.
