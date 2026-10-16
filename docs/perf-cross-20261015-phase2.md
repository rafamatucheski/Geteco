# Fase 2 da verificação cruzada: o que ainda cai (16/10/2026)

Regras: as mesmas de `docs/perf-cross-20261015-brief.md` (fila única `tools/run_godot_locked.sh`,
só o seu escopo, commits em português só dos seus trechos, sem medir desempenho por conta própria).
Meta do usuário: p50 ≤ 16,7 ms já atingida em tudo; agora **nenhum quadro grande** (alvo: nada
acima de 33 ms depois de jogável, salvo carregamento sob a cortina) e 144 fps onde der.

## Dados
- JSON das rodadas: `%APPDATA%/GetecoV2/benchmark-west/fase2_<cenário>_<n>.json` (e `base_*` = antes).
- Resumo: `evidence/perf-cross-20261015/fase2.log` e `fase2_all.tsv` (ao terminar).
- Logs de sessão (frame_spike com `slow_spans` e `phases`, frame_history, slow_operations,
  operation_timing). O rótulo NÃO fica no log; pasta por rodada (nome em UTC):

| rodada | pasta em %APPDATA%/GetecoV2/session-logs |
|---|---|
| fase2_oeste_1 | 20261016-013456* |
| fase2_sobrados_1 | 20261016-014120* |
| fase2_serra_1 | 20261016-014501* |
| fase2_travessia_1 | 20261016-015055* |
| fase2_oeste_2 | 20261016-015729* |
| fase2_sobrados_2 | 20261016-020349* |
| fase2_serra_2 | 20261016-020729* |
| fase2_travessia_2 | 20261016-021322* |
| fase2_noiteoeste_1 / _2 | 20261016-022629* / 20261016-022936* |
| fase2_chuvaoeste_1 / _2 | 20261016-023244* / 20261016-023551* |
| fase2_dirigindooeste_1 / _2 | 20261016-023858* / 20261016-024500* |

`phases` de cada frame_spike: `early_to_late_ms` (callbacks de _process), `render_bracket_ms`
(desenho na CPU, inclui compilação de pipeline), `post_render_to_next_callback_ms` (física e
sincronização), `physics_ticks`.

## Os 5 problemas que restam (atribuição quadro a quadro, quadros > 33 ms depois de jogável)

1. **`urban.physics`: exatamente 1 pico de 140–195 ms por rodada, em TODAS as rotas**, na fase
   pós-render com 1 tique de física. Mesmo custo em todo lugar → custo único (primeira
   colisão/física urbana montada/ativada). Exemplos: travessia 190/195 ms, oeste 156/168, serra 129/149.
2. **Compilação de pipeline no meio do jogo** (render_bracket enorme, sem span): chuva 586 ms
   (chuvaoeste_2) e 125/134 ms; dirigindo 700 ms (dirigindooeste_1) e 184 ms; noite 116 ms;
   serra 112 ms; travessia 106 ms; oeste 65 ms. O cache de pipelines do release tem 218 MB e
   cresce a cada rodada (relatório do agente de renderização). `HARBOR_STALL_LOG=1` grava
   `pipelines_delta` em cada travada.
3. **Picos de _process SEM SPAN de 140–210 ms com 8 tiques de física de recuperação**:
   sobrados (161–182 ms, 3 por rodada), travessia (145–210 ms), noite (94 ms), chuva (92 ms).
   Nenhuma operação instrumentada explica. Cidade (oeste) piorou: >33 ms subiu de 6–9 para 16–17,
   a maioria sem span.
4. **Streaming ainda pesado**: `stream.mountain.surfaces` 13–16 picos por travessia;
   `chunk.cell_merge` ainda 96–146 ms (process); `stream.harbor.surfaces` até 211 ms;
   `stream.harbor.record.building` ~100 ms (oeste, dirigindo); `stream.harbor.dressing_step`
   ~98 ms; `stream.harbor.record.original_facade` 103–114 ms; `chunk.building_batch`.
5. Cenários especiais: caos 3 estrelas ok (p50 5–6 ms, pior 46–59 ms).

## Fase 3 (16/10 ~02:20-03:50): pastas de log por rodada (UTC = local + 3 h)

| rodada | início local |
|---|---|
| fase3_oeste_1 | 02:20:32 |
| fase3_porto_1 | 02:23:42 |
| fase3_sobrados_1 | 02:26:57 |
| fase3_serra_1 | 02:30:38 |
| fase3_ponte_1 | 02:33:16 |
| fase3_travessia_1 | 02:36:33 |
| fase3_deserto_1 | 02:41:10 |
| fase3_oeste_2 | 02:43:12 |
| fase3_porto_2 | 02:46:23 |
| fase3_sobrados_2 | 02:49:37 |
| fase3_serra_2 | 02:53:19 |
| fase3_ponte_2 | 02:55:56 |
| fase3_travessia_2 | 02:59:14 |
| fase3_deserto_2 | 03:03:50 |
| fase3_caos3porto_1 | 03:05:50 |
| fase3_caos3porto_2 | 03:09:05 |
| fase3_noiteoeste_1 | 03:12:21 |
| fase3_noiteoeste_2 | 03:15:30 |
| fase3_chuvaoeste_1 | 03:18:40 |
| fase3_chuvaoeste_2 | 03:21:51 |
| fase3_dirigindooeste_1 | 03:25:01 |
| fase3_dirigindooeste_2 | 03:33:26 |
| fase3_semdiagsobrados_1 | 03:39:07 |
| fase3_semdiagsobrados_2 | 03:42:48 |
| fase3_semdiagserra_1 | 03:46:28 |
| fase3_semdiagserra_2 | 03:49:07 |

Resultado: quadros >33 ms caíram muito (oeste 16-17 -> 1, travessia 41-49 -> 7-8, sobrados
11-14 -> 1, chuva 19-23 -> 1-2). Sobra 1 quadro isolado de 110-220 ms por rodada, de dois tipos:
- (A) render_bracket 110-180 ms sem span (o agente de pipelines zerou as compilações "draw"):
  suspeitas = upload de textura grande no primeiro desenho, realocação do atlas de sombra,
  pipeline de especialização/sombra. Exemplos (posição do jogador): sobrados (303,0,100) e
  (295,0,2); serra (657,4,-382) e (731,4,-425); ponte (532,0,-285); deserto (-980,0,-1260) e
  (-964,0,-1320); chuva no início (64,0,82); porto (155,0,82) e (226,0,30); caos (192,0,30) e
  (170,0,82); noite (103,0,60) e (102,0,82).
- (B) early_to_late 80-115 ms com spans pequenos perto do início da rota, depois do teleporte
  de aquecimento (233,0,194) -> (64-68,0,82) e em (154,0,82); travessia_1 (233,0,189) com
  stream.harbor.dressing_step.5 de 185 ms; oeste_1 terminal.build/terminal.physics.
- Regressão: ponte_1 (548,0,-285) chunk.cell_merge de 176 ms na fase pós-render com 0 tiques
  de física (provável espera de tarefa de trabalhador no thread principal).
- Chuva/noite: p50 subiu ~1 ms (reflexos agora com MSAA 4x).
