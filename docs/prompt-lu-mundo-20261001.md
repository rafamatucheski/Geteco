# Prompt para a Lu — engasgos de mundo/streaming (2026-10-01)

> Atualização do Codex: a análise dos deltas antigos foi corrigida abaixo. Acrescentei medições pontuais em `NativeRegion.gd` e `ProductionWorld.gd`, sem alterar o algoritmo de descarte, e fatiei o censo do logger. Resultados, arquivos e limites estão em `evidence/stall-investigation-20261001/RESULTADO.md`. Os trechos em primeira pessoa seguintes descrevem a sessão original do Claude.

Você cuida de carregamento, construção, cache e descarte do mundo (`NativeRegion.gd`, `ProductionWorld.gd`, builders, `MountainTerrain3D.gd`,
`TrafficYieldController.gd`, `PoliceCaseDirector.gd`). Esta sessão gerou logs reais de jogo que apontam engasgos nessa área. Não mexi
nos seus arquivos. Leia `docs/handoff-claude-20261001.md` (seção 3) para o formato do log.

## Como ler os logs

`evidence/stall-logs/stalls-*.log`, uma linha JSON por registro (só ficam no disco do usuário, `*.log` não vai para o Git):
- `window` (a cada 10 s): `fps`, `p50_ms`, `p95_ms`, `p99_ms`, `max_ms`, contagens >33,3/50/100 ms.
- `slow` (quadro > 40 ms): `frame_ms`, `physics_steps`, `nodes`/`nodes_delta`, `objects_delta`, `removed_nodes`, `removed_roots` (raízes `queue_free`),
  `chunks`/`chunks_delta`/`build_jobs`, `spans` (trechos do `DispatchTrace` ≥ 2 ms que começaram dentro do quadro), `render_gpu_ms`, `driving`, `weapon`.
- `process_ms`/`physics_ms` são o **máximo do último segundo** do monitor do motor, não custo por quadro.
- Nos logs antigos, sem `format_version: 2`, `nodes_delta`/`objects_delta` comparam com o registro `slow` anterior, que pode estar segundos atrás; `chunks_delta` compara com o último estado registrado. Não atribua essas diferenças inteiras ao quadro lento. `removed_nodes` conta saídas da árvore desde a amostra anterior, inclusive nós apenas destacados para cache.
- A instrumentação do Codex (`format_version: 2`) avança a referência de nós, objetos e chunks a cada `_process`. `work` nos registros lentos e `work_summary` nas janelas medem descarte, saída da região e desmontagem. Tempos de chamadas aninhadas não devem ser somados. `delta_interval_ms` identifica o intervalo de amostragem.
- O censo atual percorre a árvore em fatias de 0,4 ms e publica o resultado completo numa janela seguinte. `started_t`, `finished_t` e `sampling_ms` delimitam a coleta; não é uma fotografia instantânea. `HARBOR_STALL_SELF_PROFILE=1` mede o próprio callback do logger; `HARBOR_STALL_WORK=0` desliga apenas a cronometragem de descarte. `HARBOR_STALL_BACKGROUND=1` permite sondas renderizadas sem foco e deve ser identificado na interpretação.
- Principais: `stalls-20261001-133600.log` (500 s, a mais completa), `-133134`, `-122652`, `-113535`, `-110701`.

## 1. Parada de 1238 ms ao dirigir — hipótese de descarte de região

`stalls-20261001-133600.log`, t = 440,31 s, `driving: true`: `frame_ms 1237.85`, `nodes_delta −4894`, `objects_delta −8179`, `removed_nodes 244`,
uma raiz `Vehicle.gd` com 12 filhos removida, `physics_steps 1`, GPU 1,2 ms, sem trecho do rastro, `chunks_delta -7`.
O registro lento anterior é de t=422,05 s: a queda de ~4900 nós e ~8200 objetos cobre 18,26 s, não comprova liberação em um único quadro. As 244 saídas da árvore são o contador do intervalo entre callbacks. Há indício de descarte, mas falta medir a duração da operação para atribuir a travada a ela.
O código tem uma fila com orçamento de 1,5 ms; `_exit_tree` libera o restante dessa fila sincronamente ao desmontar a região. A instrumentação nova mede esse caminho separadamente.
Pedido: confirmar o custo e o volume efetivamente liberado no quadro; se o descarte estourar o orçamento, fatiar a liberação preservando cache, colisão e suporte dos veículos.

## 2. Primeira aparição de cada modelo de carro (construção na hora)

Spans medidos (1ª vez de cada modelo): `traffic_spawn_vehicle:sport_coupe` **95–99 ms**, `cargo_flatbed_truck` 60 ms, `union_sedan` 30–32 ms, `police_suv` 22–27 ms,
`army_tank` 12–14 ms; `population_job:traffic` chega a 97 ms. Hoje o preaquecimento (`ProductionWorld._prewarm_fleet_shaders`) não cobre isso.
Pedido: pré-construir um exemplar de cada arquétipo de `ProductionWorld` na tela de carregamento (ou espalhar por quadros). `Vehicle.gd` é meu; você pode chamar o que precisar dele, mas combine antes de editar.

## 3. Paradas de 1,1–1,8 s sem causa conhecida

Atualização posterior do Codex: a investigação também confirmou **1264,231 ms na leitura de `shotgun_0.wav`, sem debugger**, e **1941,961 ms em `ResourceLoader.load` de `audio/vehicle_crashes/metal_0.wav`**, com profiler e marcador independente concordando. O segundo caminho vem de colisão de adereço derrubado, inclusive fora do callback normal de física do veículo. `CombatAudio` agora retém os 110 sons de gameplay e os 33 de recarga; `VehicleCrashAudio` prepara seus 29 sons de contato antes de liberar a partida. A derrapagem também usa cinco ondas importadas já retidas. São recursos e regras sonoras existentes. Os testes dirigidos passaram; os controles renderizados finais e seus limites estão no relatório. Uma pausa de 1,04 s medida em `vehicle.physics` antes de ampliar o rastro ainda não recebeu atribuição direta; não considerar cada evento antigo explicado por essas leituras.

Atualização do Codex, após retomar a investigação: uma captura gráfica silenciosa com profiler localizou **1529,999 ms em `FileAccess.flush` do próprio `StallLog`**, não no censo ou no descarte. A escrita foi movida para uma thread com fila limitada, preservando ordem e registrando perdas. Um controle gráfico sem profiler reproduziu **435 ms de flush** e quadro de 486 ms na forma antiga; a captura com escrita assíncrona mediu cinco minutos de combate com 6★, sem quadros ≥500 ms, máximo de 179 ms em callbacks de física. Esse pico físico segue sem operação interna isolada.

Outras paradas com profiler ativo foram localizadas em granada, `move_and_slide` e resumo do logger, mas não repetiram nas duas capturas sem debugger. Não atribuir todas as travadas originais ao disco nem considerar o restante aprovado. WPR falhou por política de privilégios do Windows (`0xc5585011`); nenhuma política foi alterada. Evidência, limites e reprodução: [relatório do Codex](../evidence/stall-investigation-20261001/RESULTADO.md). O `Projectile.gd` ganhou apenas cronometragem opt-in; nenhuma regra de projétil mudou.

Aparecem 1–2 vezes por rodada de 5 min (1795, 1519, 1767, 1557, 1356, 1444 ms), sem trecho do rastro, sem queda de nós, GPU ~3–6 ms.
Hipóteses não testadas: leitura síncrona de recurso, compilação de pipeline na primeira vez de um efeito, troca de arma montando o modelo (a de 1356 ms
coincidiu com o primeiro quadro com `weapon: shotgun`). Se você tem capacidade nativa de rastrear (WPR/ETL do seu `WINDOW.md`), uma janela de captura nesse cenário resolveria.

## 4. O que EU mudei e toca no seu território (confira antes de medir)

- `scripts/Vehicle.gd`: carcaça (vida 0) de trânsito ambiente ou de despacho some em 30 s com fade de 2 s via `queue_free()`. Se `ProductionWorld.vehicles` ou outro registro guarda referências,
  elas ficam inválidas (o código já usa `is_instance_valid`, mas confira). Exceções: carro do jogador, `garage_reward`/`garage_place`, `meta wreck_hold`.
- `runtime/StallLog.gd` (autoload) liga `benchmark_trace` no mundo e poda `perf_costs` a cada 2 s (mantém os últimos 5 s). Só com `HARBOR_STALL_LOG=1` (`Jogar.cmd`/`JogarCSharp.cmd`).
- `gameplay/CombatEffects.gd` ganhou `prewarm()` chamado por `Gameplay._prewarm_effects` sob a tela de carregamento (só se `ready_for_play` ainda for falso).
- `project.godot`: autoload `StallLog`. As outras alterações nesse arquivo ([dotnet], plugins do editor) não são minhas.
- Chaves de A/B: `HARBOR_MAX_PHYSICS_STEPS=3` (o `JogarCSharp.cmd` já define), `HARBOR_NO_CSHARP=1`, `HARBOR_PLAN_BAKE_SOURCE/RESULT`.

## 5. Pendência que pode ser sua: restos que acumulam e pesam

No log de 500 s, com 6★, o `p50` foi de aproximadamente 11,9–15,4 ms nas janelas t≈139–199, 10,57 ms em t=209, 4,16 ms em t=219 e 2,78 ms em t=229. As três últimas janelas registram cinco unidades policiais, mas a população, outros serviços, posição e conteúdo do mundo também mudaram. A queda coincide com redução de carcaças
(7→2) e nós (16,9k→10,5k entre registros separados); é correlação, não isolamento da causa. Não sei se o peso era corpos, carcaças, fogo no chão, decalques ou outra coisa. O arquivo `stalls-20261001-133600.log` não tem `census`; a implementação atual traz esse campo dentro de `window` a cada 30 s nas próximas capturas,
(classes e scripts de nó mais numerosos), `fires_ground`, `burning_people` e `wrecks` nos quadros lentos. Se o censo mostrar acúmulo de algo que o mundo gerencia (corpos, decalques, props quebrados),
o limite/tempo de vida é seu.

## Regras do repositório (CLAUDE.md)

Nada de push sem pedido do usuário; não rodar Godot enquanto houver outra instância/medição ativa; commits só dos seus arquivos (stage explícito); percentis em ms.
`DispatchController.gd`, `DispatchUnit.gd`, `DispatchRules.gd`, `PoliceRoadblock.gd` e `Vehicle.gd` têm edições minhas não commitadas; avise antes de commitar por cima.
