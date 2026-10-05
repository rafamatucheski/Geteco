# Continuação do JIT do roteador e das travas — 05/10/2026

A preparação de `9689db41` foi exercitada com um save isolado a **507,46 m do terminal**.
A verificação mínima passou, e `Jogar.cmd` abriu o menu, carregou esse save e respondeu à
caminhada. Uma gravação WPR longa capturou pausas de **646,776 ms** e **1.804,791 ms**.
A pausa maior foi localizada em espera no kernel, com NTFS/FLTMGR nos stacks. A causa
original e uma correção de gameplay continuam pendentes; há possível interferência da
coleta de stacks e perda de foco. Não há aprovação de FPS ou da estabilidade global.

O código de produção permanece o do commit herdado. Esta continuação amplia apenas
`tests/measure/probe_first_dispatch_plan.gd`, que agora prepara/restaura uma fixture por
`SaveStore`, exige C# e planos completos, registra tempos absolutos e intervalos reais,
usa deadline de loading em tempo e mantém os frames brutos fora do console. O UID da
sonda também é preservado. Alterações de chegada/história de outra sessão ficam fora
desta revisão e do commit.

## Verificação funcional

Godot `4.7.2.stable.mono.official.ed1daf0bf`, .NET 10, renderer Mobile/Vulkan;
RTX 4060 Laptop GPU. `dotnet build Harbor.csproj --no-restore`: zero avisos/erros.

| Verificação | Resultado |
|---|---|
| `test_regions` | PASS, failures=0 |
| `test_bridge_approach_terrain` | PASS, failures=0 |
| `test_native_driving -- --no-save` | PASS; chão e admissão na porta confirmados |
| `cold/test_admission` | 11 checks, zero falhas |
| `dispatch/test_road_graph_native` | equivalência C# × GDScript passou |
| `Jogar.cmd` | recompilou/importou, CONTINUAR restaurou o save, jogador caminhou |
| Sonda final após ajustes de log/caminho | exit 0; C# ativo; todos os planos ok |

Os cinco testes foram executados sequencialmente em 12:44–12:45, antes dos benchmarks
concorrentes identificados depois. O launcher e a sonda final também passaram no estado
compartilhado posterior. Isso não certifica as mudanças de história daquela outra sessão.
O editor PID 15408 foi encerrado com autorização explícita. Saves/configurações de teste
ficaram em userdata próprio; o launcher foi fechado ao fim. Capturas do menu, carregamento
concluído e caminhada estão em `evidence/router-jit-continuation-20261005/launcher/`.
O input da verificação do launcher foi dirigido à janela própria por mensagens Windows.

## Save distante e custo do primeiro plano

Fixture schema 3, Mountain, posição solicitada `(472.5, 0.08, -285.0)`, criada num caminho
novo dentro da evidência. Foi restaurada pela entrada produtiva `menu_save_path`, embora
`--no-save` bloqueie gravações. Posição admitida `(472.5, -0.009909, -285.0)`, diferença
0,09 m. Em todas essas sondas: `loaded_save=true`, terminal a 507,46 m,
`terminal_road_prepared=false`, roteador real sem espelho nativo antes do primeiro plano.
O grafo tem 421 vértices/listas de arestas. A preparação descartável concluiu um plano C#.

Mesma seed 21092026, população solicitada 40, 1920×1080, MSAA enum 1, VSync 0 e limitador
0 nas configurações efetivas. `SDL_JOYSTICK_DIRECTINPUT=0` acompanha o `Open.ps1` atual.

| Rodada sem processo concorrente | Preparação no loading, ms | Primeiro plano real, ms | Foco dos frames |
|---|---:|---:|---|
| baseline3, preparação desligada | — | 32,286 | nenhum |
| baseline5, preparação desligada | — | 23,494 | nenhum |
| prewarm2, preparação ligada | 34,851 | 2,116 | todos |
| prewarm3, preparação ligada | 29,235 | 4,628 | nenhum; watcher interrompido por caminho de captura |
| smoke final, preparação ligada | 36,660 | 2,084 | amostra curta, apenas funcional |

Esses tempos são observações dirigidas do primeiro plano, compatíveis com deslocar o
trabalho de inicialização para o loading. O resultado funcional antes não medido está
comprovado para esta fixture distante. A diferença de foco impede atribuir uma melhoria
certificada de FPS. A sonda chama `router.plan` no `process_frame` do teste; não prova
latência do despacho dentro de seu callback físico nem todos os locais de save.

As amostras completas de 30 s antes/depois estão nos JSONs das sondas. Exemplos:

| Rodada | Antes: p95/p99/máximo, ms | Depois: p95/p99/máximo, ms |
|---|---|---|
| baseline3 (sem foco) | 3,043 / 4,797 / 25,686 | 5,488 / 6,298 / 12,379 |
| prewarm2 (com foco) | 3,907 / 5,695 / 45,399 | 5,652 / 6,557 / 13,538 |

Critério prévio: 60 FPS/16,67 ms provisórios, sinal de regressão acima de 5% em p95/p99,
janela mínima de 30 s. **Comparativo de performance inconclusivo**, pois as condições de
foco diferem. O resumo retém frames, duração, FPS por frames/tempo, p50/p95/p99, máximo,
contagens >33,3/>66,7 e foco; os intervalos brutos permanecem nos resultados locais.

`baseline2` e `prewarm` tiveram concorrência com benchmarks de história e foram excluídos
do comparativo. O primeiro plano de `baseline2` levou 1.075,562 ms, com 31,25 ms registrados
por `GetThreadTimes`; o número não é evidência de JIT determinístico nem de ganho do toggle.
As tentativas com falha de caminho/foco foram preservadas. Nenhuma delas foi promovida a
aprovação. Os runners posteriores registraram fontes e detecção de processos concorrentes.

## WPR longo: esperas localizadas

Evidência: `evidence/router-jit-continuation-20261005/codex-long-01/`.
Jogo sem elevação; apenas o helper WPR foi elevado via UAC. Perfil CPU/CSwitch/ReadyThread/
SampledProfile, sem FileIO/DiskIO/HardFaults/NetworkIO, arquivo com deadline de 150 s e
limite de 4 GiB. A sessão própria `GetecoAudit-d6836b5f452c48c28ea65efb49301991` terminou
por `measurement_finished`, salvou 2.124.414.976 bytes e confirmou cleanup equivalente ao
estado anterior. O ETL não entra no Git.

A rota durou 120,020 s, mais cauda de 3,002 s. Não houve alterações de fonte durante o jogo
nem erros de script. **Validade do gameplay: `lost_focus`** (14.427/14.455 frames sem foco,
incluindo loading/cauda). Rota/retorno e C# foram exercitados, mas esta condição não aprova
jogo em primeiro plano, FPS ou a comparação com a captura histórica.

O leitor completo atingiu limites de exportação. A extração final restringiu stacks/eventos
às janelas ±3 s dos dois picos, mantendo módulos e metadados. Preservaram-se as exportações
truncadas anteriores. Na exportação usada: retorno normal, `EventsLost=0`, export drops=0,
QPC consistente em 10 MHz; eventos regulares de READY+0,549449 até +124,542044 s. Não foi
extraído um vetor separado `LastDroppedTimes` por CPU; isso permanece uma limitação da
auditoria. Pares CSwitch In→Out no mesmo CPU cobrem ambos os frames e o gap escolhido,
sem Unknown ou trecho descoberto dentro deles. Fronteiras entre janelas ficam fora da
cobertura, sem interpolação; ReadyThread não corta retroativamente um trecho Running.

| Frame / fase | Parede, ms | Scheduled running, ms | Ready, ms | Waiting, ms |
|---|---:|---:|---:|---:|
| 742 / primeira passagem | 646,776 | 15,580 | 0,103 | 631,094 |
| 11408 / combate | 1.804,791 | 46,749 | 0,125 | 1.757,917 |

No frame 11408, o trecho entre o fim dos callbacks de processo e `pre_draw` durou
**1.758,814 ms**: 1,221 ms Scheduled running, 0,024 ms Ready e **1.757,569 ms Waiting**.
Os contadores de CPU da main não avançaram nesse trecho. Os dois waits principais,
razão kernel `Executive`, duraram **449,402 ms** e **1.308,167 ms**. Contexto: 32 pessoas,
42 veículos, 3 unidades, zero estrelas e health 100; difere do estado da pausa histórica.

Os stacks ligados a esses waits contêm `ntoskrnl.exe`, `FLTMGR.SYS` e `Ntfs.sys`.
Checksum, tamanho de imagem e timestamp PE dos arquivos locais coincidem com o rundown.
Nomes abaixo só foram associados quando o export coincide com o início da função na
`.pdata`: `IofCallDriver`, `IofCompleteRequest`, `KeWaitForSingleObject`/`KeWaitForMutexObject`
e **`RtlWalkFrameChain`**. Não foram nomeadas funções privadas por export vizinho.

**Fato:** esta pausa tem esperas com caminho do sistema de arquivos no kernel; a main
não ficou executando o roteador C# por 1,8 s. **Hipótese:** a coleta de stacks/paginação
pode estar interferindo, pois `RtlWalkFrameChain` aparece nessa cadeia. Isso não identifica
qual arquivo, o motivo da espera, um filtro responsável nem comprova que a captura causou
o pico. Também não transfere essa atribuição às pausas antigas sem WPR. Não há evidência
para culpar antivírus, GPU, solver ou GC/JIT.

Próximo discriminante: capturar FileIO/DiskIO/HardFaults e separar o custo do stack walking,
com foco mantido e dados de I/O dentro da própria espera. A documentação Microsoft lista
[HardFaults](https://learn.microsoft.com/en-us/windows/win32/etw/event-trace-properties) e
[eventos de stack walking](https://learn.microsoft.com/en-us/windows-hardware/test/wpt/stackwalk).
O perfil em arquivo segue [as opções WPR](https://learn.microsoft.com/en-us/windows-hardware/test/wpt/wpr-command-line-options).
Esses providers não foram ativados nesta rodada; nenhuma causa nova foi mascarada com
mudança de gameplay ou configuração global.

## Estado da entrega

- Funcionamento da preparação no save distante e verificações mínimas: **aprovado no escopo descrito**.
- Menu, carregamento e caminhada por `Jogar.cmd`: **aprovado na fixture isolada**.
- Performance/regressão: **inconclusivo por foco desigual/perdido**.
- Captura WPR e cleanup: **concluídos**; novo pico longo tem partição e caminho de kernel registrados.
- Causa/correção das travas históricas de 472 ms, 1,6 s e 1,7 s: **pendentes**.

Dados locais: `probe-summary.json`, resultados brutos das sondas, `codex-long-01/analysis.md`,
`native-windows-v2.json`, `native-peak-analysis.json`, `kernel-modules-v2.json` e
`kernel-pe-sites.json`. Os scripts privados de captura/análise e o perfil ficam no mesmo
diretório de evidência. O próximo lote pode reutilizar o ETL e essas verificações, sem
repetir a suíte funcional enquanto as dependências pertinentes permanecerem iguais.
Na conferência final, WPR não estava gravando e o PID 115464 já não existia.
Seu encerramento não foi executado por esta sessão.

Reprodução da fixture: use um diretório de evidência novo e alterne a variável
HARBOR_ROUTER_JIT_PREWARM=0/1 antes de iniciar o Godot .NET compilado:

```powershell
& $GodotExe --path D:/geteco/game --script res://tests/measure/probe_first_dispatch_plan.gd -- --no-save --fixture=mountain --mode=whole --wait-frames=0 --sample-seconds=30 --out=res://evidence/router-jit-novo/result.json
```