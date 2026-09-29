# Travamentos de 0,5–1,9 s no caos: causa localizada e corrigida (29/09/2026)

Autor: Claude. Execuções em **cópia isolada** do projeto (`%TEMP%\geteco_probe`), uma instância de Godot por vez,
renderizado (Vulkan, RTX 4060 Laptop), `--no-save --skip-arrival --benchmark --population=40`, semente 20260929,
mesmo roteiro de recuperação do Codex (aquecimento 8 s, normal 30 s, caos 35 s, cessação 60 s).
A cópia recebeu apenas prints de diagnóstico (`CHUNKTRACE`, `STAGE0/RECORD/DRESS`, `MOUNTPROBE/BUILDPROBE`);
a árvore compartilhada só recebeu a correção final (2 arquivos).

## O que foi medido

1. **A regressão do caos não reproduziu.** Três execuções com a árvore atual (sem sondas do Codex):

   | Execução | FPS caos (quadros/35 s) | p99 caos | máx. caos |
   |---|---:|---:|---:|
   | probe1 | 51,5 | 45,7 ms | 194 ms |
   | probe2 | 54,8 | 35,2 ms | 167 ms |
   | probe3 | 53,1 | 36,3 ms | 142 ms |

   Referência do Codex: base 53,37 FPS / p99 51,8 / máx. 138; "regressão" 47,45 / 99,7 / 1918.
   Nenhum bloqueio ≥ 500 ms em três execuções. Não afirmo que o problema não exista (o Codex o viu em ~60 % das
   execuções antigas): afirmo que, com esta árvore, ele não apareceu em 3/3.
2. **O que ainda gera quadros de 100–190 ms no caos** (demonstrado, `CHUNKTRACE`): reconstruções síncronas
   dos chunks do porto (3,3) 60–75 ms, (4,3) 87–109 ms, por `set_vehicle_support`/`prepare_collision_at`
   depois que a retenção os solta (`retention=2`, chunk a 3–4 células do foco). Coincidem com os quadros
   de 106–194 ms (ex.: build 66,8 ms → quadro 106 ms). Ocorrem 2–3 vezes por 100 s.
3. **Fonte dos bloqueios de ~1 s — medida diretamente.** O chunk **(4,2)** (navio Santa Mare, `SantaMareCargo3D`)
   leva **1,07–1,33 s** para construir de forma síncrona (`prepare_collision_at` → `_ensure_chunk`),
   e é liberado de novo pela retenção (é a 4 células do foco). Qualquer veículo/unidade que peça o piso ali
   paga esse tempo num único tick — assinatura idêntica aos bloqueios de 1058/1400/1919 ms (um tick, sem fila,
   sem GPU/CPU de render). Divisão do build de 1,07 s (`STAGE0/RECORD/MOUNTPROBE`):
   - `PortMeshOptimizer.optimize_hierarchy` (junta ~1900 caixas): ~400–434 ms
   - **`create_trimesh_collision` em ~1900 malhas originais que o próprio otimizador já enfileirou com `queue_free`**:
     485–564 ms (colisão gerada e destruída no fim do quadro; desperdício puro)
   - normais/dressing/demais: ~100 ms
   O cache de contêineres do Codex (`LootablePortContainer`) não cobre este caminho (`HarborPortModel3D._container`).
4. O Codex já tinha medido (4,3) em 506 ms com 6 contêineres saqueáveis; com o cache dele, na minha cópia (4,3) caiu para ~100 ms —
   confirma aquele ganho.

**O que NÃO foi provado:** que o bloqueio de 1,9 s do "clean-chaos-recovery" foi o (4,2). Não há sonda de build nessa
execução. É a única fonte de bloqueio de ≥1 s demonstrada no caminho, com assinatura compatível, mas o vínculo
causal com aquela execução específica continua inferido. Em 3 execuções minhas nenhuma unidade pediu o (4,2) naturalmente.
Também vi, na execução probe3, ~1,5 s de quadros de ~100 ms (6–8 passos de física, `physics_process_max` ~20 ms, custo do
despacho ≈ 0): episódio de física do mundo, não localizado; não ligado ao caos.

## Correção (2 arquivos, sem mudar geometria nem colisão final)

- `world/regions/OriginalSouthPort.gd` — `mount`: pula `create_trimesh_collision` em malhas `is_queued_for_deletion()`.
  Colisão das malhas agrupadas (22 corpos) fica igual; só some a colisão de nós que morrem no fim do quadro.
- `assets/regions/source/world/harbor/HarborPortModel3D.gd` — `build`: para `ship_cargo`, guarda as malhas agrupadas
  finais (`_batch_cache`, chave = tipo/tamanho/variante) e as reaproveita nas reconstruções; nós continuam novos por instância.

Medição na cópia (mesmo cenário, build síncrono do (4,2)):

| | antes | depois |
|---|---:|---:|
| build ao vivo do chunk (4,2) | 1070 / 1329 ms | **95 ms** |
| `SantaMareCargo3D` (mount, 1º build) | 1215 ms | 487 + 40 ms (só a 1ª vez, no aquecimento) |
| `SantaMareCargo3D` (rebuild) | ~1215 ms | 0,2 + 22 ms |
| prewarm do (4,2) | 1020–1312 ms | 593 ms |

Quadros do caos com a correção (probe7): 56,1 FPS, p99 32,7 ms, máx. 166,6 ms (o máximo é o build síncrono de (4,x) de ~100 ms + forçado pela sonda).

## Verificação e limites

- Passaram na árvore compartilhada com a correção: `test_regions`, `test_port_ships_3d`, `test_harbor_port_policy`,
  `test_bridge_approach_terrain`, `test_native_driving -- --no-save`, `cold/test_admission`.
- **Falhas já existentes, não causadas por esta correção:** `test_port_expansion_3d` ("Depot unload returns the carrier to the next circuit")
  e `test_port_real_loading_3d` ("Loaded truck reaches the warehouse, unloads and returns to approach") falham igual com `--no-save`
  na cópia com a correção desligada. Alteração local não commitada (PortLogistics/ProductionWorld/LootablePortContainer) é a suspeita natural; não investiguei.
- Rodei duas vezes esses dois testes **sem** `--no-save` na árvore real antes de notar (o teste avisa "must isolate the personal save"); pode ter escrito no save pessoal.
- Não medi 150 s comparativos com a correção; não abri o jogo (Jogar.cmd).
- Retenção continua soltando (3,3)/(4,3)/(5,3) e reconstruindo 60–110 ms no caos: possível próximo passo (fatiar por orçamento
  os builds de suporte de veículo / histerese na retenção) — exige mexer em `PortLogistics._ground_ready` e no ônibus, não feito.
- Corrigir também o `continue` do estágio 3 em `_run_build_job` (o Codex apontou: pula o orçamento) não foi tocado.
