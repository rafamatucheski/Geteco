# Correção dos erros da sessão de 10/10/2026

Escopo: referências removidas no terminal, zoológico e cemitério; lança-chamas com componente opcional ausente; investigação das quedas no arquivo `session-000.jsonl` da sessão `20261010-145306-036-10956-b36c9e80`. Trabalho dividido entre dois agentes, com execução dos testes coordenada em série.

## Correções

- `TerminalOperations.gd`: valida passageiro destruído ou aguardando `queue_free` antes de atualizar, embarcar, suspender ou retomar. Limpa a referência e ocupação, encerra a fase e conserva os passageiros sobreviventes. Remoção não incrementa embarques/desembarques.
- `ZooAdmission.gd`: exclui visitantes removidos e mortos da fila; limpa referências destruídas antes de acessar posição, estado ou apresentação. Conserva o slot até descarregar a visita, evitando recriar imediatamente uma vítima. A fila sobrevivente e a cobrança continuam funcionando.
- `CemeteryOperations.gd`: helpers de validade e limpeza recebem `Variant`. Um argumento `Node` contendo objeto destruído falhava antes de executar `is_instance_valid`. Identidades e registros de mortes permanecem intactos.
- `Gameplay.gd`: valida o componente opcional `damage_look` antes de acionar incêndio. O dano do lança-chamas e a finalização do disparo continuam mesmo sem apresentação de incêndio. O diff alheio da katana foi preservado.

O serviço funerário de `EmergencyManager.complete/_cleanup` pode remover corpos legitimamente. Os consumidores precisam aceitar essa remoção; manter cadáveres vivos para evitar o erro não seria uma correção.

## Validação funcional

Motor: Godot 4.7.2 .NET, executável `_console.exe`; `dotnet build Harbor.csproj --no-restore -v quiet` aprovado, zero erros/avisos. Testes com `--no-save`; testes funcionais também com `APPDATA` exclusivo em `evidence/session-lifecycle-20261010/userdata`.

| Teste | Resultado |
| --- | --- |
| `test_session_cemetery_fire_lifecycle.gd` | 19 checks, zero falhas/erros de script: vivo, morto, remoção pendente, destruído, funeral, limpeza, restauração, encerramento; raycast e lança-chamas com componente ausente/destruído/válido; bloqueio em área segura |
| `test_terminal_zoo_removed_actors.gd` | 23 checks, zero falhas/erros de script: fases de embarque, suspensão/retorno, passageiros sobreviventes, fila e cobrança após remoção, limpeza e reentrada |
| `test_maciota_transition_safety.gd` | 37 checks, zero falhas: Main real headless, entrada/saída, input e APIs, restauração de save temporário, inventário, bloqueios de armas e proteção de Maciota/mecânico |
| `test_session_removed_actors_integration.gd` | 17 checks, zero falhas/erros de script; Main real renderizado, terminal/cemitério/zoo, remoção, afastamento e retorno |
| `test_mountain_zoo_tickets.gd` | PASS, zero erros de script; fila e pagamento reais de quatro NPCs, ingresso do jogador, saldo, save/restore de estado e bloqueio físico de visitantes sem ingresso |

Total: 96 checks nos quatro runners que publicam contagem, mais a suíte existente de ingressos aprovada. Logs correspondentes: `evidence/session-lifecycle-cemetery-fire-test-20261010.log`, `session-lifecycle-terminal-zoo-test-20261010.log`, `session-lifecycle-garage-20261010.log`, `session-lifecycle-integration-ready-20261010.log` e `session-lifecycle-zoo-tickets-20261010.log` no mesmo diretório.

A primeira integração renderizada passou pelos cenários de terminal e cemitério, mas consultou o zoológico após apenas dez frames de streaming. Falhou na precondição de carregamento, não no comportamento corrigido. O runner agora aguarda o nó pronto com prazo finito, sem mudar o carregador do jogo. Log original preservado em `evidence/session-lifecycle-integration-20261010.log`; execução corrigida aprovada em `evidence/session-lifecycle-integration-ready-20261010.log`.

Os testes usam teleporte para estabelecer locais e remoção dirigida para os passageiros/visitantes. No cemitério, usam dano produtivo, registro da morte e coleta por `EmergencyManager.complete`. Não certificam o percurso viário inteiro, todas as fontes de dano, todos os interiores ou todas as missões.

## Investigação de performance

O log original contém 20.728 erros de script correspondentes às quatro correções. As quedas também ocorrem antes e depois das repetições do terminal; eliminar esses erros não demonstra resolver toda a lentidão. O pior intervalo de gameplay foi 1.294 ms; a pior janela ficou em 4,68 FPS. Não havia posição/região detalhada nem tempo de GPU suficiente para atribuir retrospectivamente cada episódio.

Foi capturada uma rodada renderizada anterior aos patches: `tests/measure/measure_session_lifecycle.gd`, Main real, RTX 4060 Laptop, Mobile/Vulkan, 1280×720, luz diurna fixa, dez segundos de aquecimento e trinta segundos por local. A fixture usa documento de edição vazio, como o medidor existente do terminal; portanto não replica todas as edições do mapa da sessão original. Mantém os diretores normais, mas o serviço urbano registra corredor incompatível nessa fixture. O terminal regional é independente e sua criação de quatro ônibus/dezesseis passageiros aparece no trace.

| Local | FPS | p50 / p95 / p99 ms | Máximo ms | Frames >33,3 / >66,7 ms |
| --- | ---: | --- | ---: | --- |
| Terminal | 69,53 | 12,19 / 30,85 / 50,71 | 115,62 | 73 / 15 |
| Cemitério | 139,24 | 5,68 / 11,59 / 12,81 | 28,57 | 0 / 0 |
| Zoológico | 63,97 | 14,65 / 31,39 / 41,63 | 85,51 | 83 / 3 |

Todos os frames amostrados nessa rodada estavam em foco. Os dados brutos estão em `evidence/session-lifecycle-before-20261010.json`; warmup separado. Monitor de GPU p95: terminal 6,77 ms, cemitério 2,62 ms, zoo 5,98 ms. Esses monitores não estão sincronizados para atribuir cada spike exato.

O trace `evidence/stall-logs/stalls-20261010-124141.log` fornece evidências adicionais:

- Intervalos lentos executaram cinco, seis e até oito passos físicos de compensação. Isso localiza participação da simulação/catch-up, mas não identifica sozinho a causa inicial de cada atraso.
- No terminal, houve aproximadamente 109 ms entre frames com seis passos físicos, sem novos nós ou build jobs. Assim, nem todo pico é carregamento de cenário.
- Na chegada à região da montanha, um intervalo de 85,23 ms incluiu `population_job:traffic` de 26,07 ms e `traffic_spawn` de 25,96 ms. São spans inclusivos e não devem ser somados. A criação/planejamento de tráfego é um componente concreto daquele pico.
- A criação inicial do terminal levou 15,47 ms; quatro ônibus e dezesseis passageiros. Isso é custo de primeira ativação, distinto dos erros repetidos em NPCs removidos.

**Performance global e regressão antes/depois: inconclusivas.** `Actor.gd` e `SessionDiagnostics.cs` foram alterados por outras sessões durante a rodada anterior; seus hashes estão registrados. Depois também surgiram outros runtimes e benchmarks Godot. Nenhum processo alheio foi encerrado. Não há comparação causal válida que permita aprovar ganho ou ausência de regressão dos patches.

Próximo diagnóstico útil: com fontes e carga externas estáveis, repetir os mesmos locais e uma rota real com combate/recuperação, mantendo registro de passos físicos, criação de tráfego e tempos por sistema. Não foram alterados população, iluminação, qualidade, limite de passos físicos ou arquitetura de streaming para esconder os picos.

## Preservação

Nenhum checkout, restore, reset, clean, stash ou commit foi executado. Apenas os quatro arquivos de produção descritos receberam patches desta tarefa. Testes novos e evidências são separados. Manifestos e concorrência: `evidence/session-lifecycle-source-before-20261010.json`, `evidence/session-lifecycle-source-after-20261010.json`, `evidence/session-lifecycle-concurrent-processes-20261010.json`.

Avisos de gravações de voz ausentes e do terreno piloto apareceram em diagnósticos; não foram convertidos em aprovação silenciosa nem corrigidos fora deste escopo. Os dois erros de normalização de eixo do despacho no log original também estão fora das quatro correções solicitadas.
