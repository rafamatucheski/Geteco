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
