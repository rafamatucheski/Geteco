> Atualização 21/10/2026: logs essenciais são o padrão em Jogar.cmd e novas exports release. Ative `HARBOR_SESSION_PROFILE=1` para as métricas e o diagnóstico descritos abaixo, ou use `tools/launchers/JogarDiagnostico.cmd` (inclui StallLog). Sem opt-in, não há métricas básicas periódicas. Evidências antigas abaixo preservam o comportamento da época.

# Captura detalhada de sessÃµes

A captura Ã© automÃ¡tica no Godot .NET. Cada processo cria uma pasta em `%APPDATA%/GetecoV2/session-logs/`. Compartilhe a pasta completa: arquivos `session-000.jsonl`, `session-001.jsonl` etc. sÃ£o partes da mesma sessÃ£o, rotacionadas aos 32 MiB.

## Leitura

```powershell
python tools/read_session_log.py "C:/Users/rafae/AppData/Roaming/GetecoV2/session-logs/PASTA" --top 10
```

O leitor aceita tambÃ©m uma parte JSONL e lÃª suas partes irmÃ£s. Calcula FPS por frames/tempo total e percentis sobre frames individuais; separa cena, foco, pausa e resoluÃ§Ã£o. Mostra os maiores picos, trechos lentos, runtime e descarte correspondente. Uma Ãºltima linha incompleta Ã© informada e ignorada.

## Schema 4

- `session_start.clock_sync`: referÃªncia entre relÃ³gio monotÃ´nico do motor e Stopwatch do C#. UTC serve para localizar a sessÃ£o; `engine_usec`/`start_usec`/`end_usec` servem para correlacionar trabalho.
- `frame_spike`: intervalo >=33,3 ms, IDs de frames, contexto do jogador/regiÃ£o/lugar, operaÃ§Ãµes ativas e snapshot do runtime.
- `frame_history`: buffer de atÃ© 360 frames e atÃ© dois segundos antes do intervalo lento. ApÃ³s um pico, grava frames em blocos de atÃ© 500 ms por dois segundos; novos picos prolongam a captura. A janela anterior pode ser menor em taxas acima de 180 FPS. Nenhuma varredura da Ã¡rvore por frame.
- Os frames do histÃ³rico incluem nÃ³s, objetos, draw calls, foco/pausa, Ãºltimo callback tardio de processamento e sinais pre/post draw. O contexto de posiÃ§Ã£o/regiÃ£o Ã© atualizado a cada 250 ms e carrega seu prÃ³prio timestamp.
- `runtime`: coleÃ§Ãµes GC por geraÃ§Ã£o, bytes alocados cumulativos, memÃ³ria gerenciada, duraÃ§Ã£o cumulativa das pausas GC .NET, fila de escrita, perdas e operaÃ§Ãµes ativas. Compare deltas entre snapshots; GC .NET nÃ£o representa a liberaÃ§Ã£o nativa de recursos do Godot.
- `lifecycle_events`: detalhes de operaÃ§Ãµes `retire.*` mesmo abaixo de 2 ms; atÃ© 64 registros por intervalo, com perdas explÃ­citas. `retire.drain` inclui fila, pilha e variaÃ§Ã£o de nÃ³s durante a fatia sÃ­ncrona. A exclusÃ£o de chunks agendada ocorre posteriormente.
- `slow_operations` mantÃ©m os 16 trechos lentos mais longos do intervalo e informa omissÃµes. As agregaÃ§Ãµes continuam preservando todos os calls dentro do limite de labels.
- `previous_probe_usec`: custo do callback anterior do profiler, incluindo preparaÃ§Ã£o/envio do histÃ³rico. A escrita em disco ocorre em thread separada e a fila Ã© limitada.

## InterpretaÃ§Ã£o

Tempos de trechos sÃ£o inclusivos e podem se sobrepor; nÃ£o some pai e filho. Monitores CPU/fÃ­sica/renderizaÃ§Ã£o sÃ£o `latest_available_not_exact_frame`: nunca atribua automaticamente a amostra ao frame do pico. Sinais pre/post draw sÃ£o limites observados de callbacks, nÃ£o fence da GPU nem mediÃ§Ã£o exata de toda a fase do motor. IDs e timestamps ajudam a localizar lacunas, nÃ£o fornecem stack trace nativo. OperaÃ§Ãµes ativas sÃ£o correlaÃ§Ã£o, nÃ£o prova de causa.

`HARBOR_SESSION_LOG=0` desativa o logger; `HARBOR_SESSION_PROFILE=0` desativa o detalhamento de sistemas e histÃ³rico, mantendo mÃ©tricas bÃ¡sicas. O histÃ³rico e eventos tÃªm limites para evitar que a prÃ³pria captura cresÃ§a sem controle. Em travamentos ainda sem explicaÃ§Ã£o, capture um profiler externo com pilhas nativas/.NET no mesmo cenÃ¡rio.

## Validação em 12/10/2026

Godot 4.7.2 .NET, build sem avisos/erros. O teste dedicado verifica erro com operação ativa, bloqueio de 6,2 s, recuperação de JSON inválido, detalhes em intervalo curto, omissões explícitas, histórico limitado com frames anteriores e snapshots de memória. Os testes de descarte e remontagem passaram com 6 e 12 verificações. O teste standalone de erros GDScript/C#, pausa e retomada também passou. Leitores Python e PowerShell exercitados com logs novos; Python também lê schema 3.

Performance permanece **inconclusiva**. As primeiras amostras do runner antigo mediram momentos diferentes da chegada e foram descartadas como comparação. O runner agora pula a chegada, usa seed fixa, espera prontidão da produção e fixa o jogador. Em Main renderizada, RTX 4060 Laptop, Mobile, 1920×1080, VSync ligado e limite 144, com 36 pedestres e 37 veículos no mesmo ponto, foram medidos 30 segundos:

| Captura | FPS médio | p50 / p95 / p99 (ms) | Máximo (ms) | >33,3 / >66,7 ms |
|---|---:|---|---:|---|
| Desligada | 40,76 | 19,731 / 47,574 / 60,269 | 74,509 | 207 / 6 |
| Ligada | 57,66 | 15,366 / 32,527 / 64,812 | 147,203 | 79 / 17 |

Não atribuir o aumento da média ao logger: o cenário ainda apresenta variação grande e ambas as amostras ficaram abaixo da meta provisória de 60 FPS. p99 e máximo pioraram com captura ligada; a rodada não confirma causalidade nem aprova ausência de regressão. Não foi assegurada apresentação nativa/foco contínuo nem estabilidade de todas as fontes concorrentes. As evidências são `evidence/session-fixed-off-20261012.json` e `evidence/session-fixed-on-20261012.json`. O log produtivo com schema 4 terminou sem erros de captura, perdas da fila ou operações pendentes. O maior custo observado do callback do profiler foi 12,534 ms de parede (inclui preempção), portanto seu custo também continua visível para investigação.

Escopo aprovado funcionalmente: captura, leitura, recuperação de erros e instrumentação de descarte. Não cobre todos os mapas, transições, saturação de disco ou captura de pilhas nativas. A medição controlada do custo adicional permanece pendente.
