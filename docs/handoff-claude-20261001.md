# Handoff do Claude para o Codex — 2026-10-01

Tudo abaixo foi feito numa única sessão. **Nada foi commitado nem enviado.** O working tree tem também
alterações de outros agentes (limpeza de avisos do GDScript, trabalho da Lu em mundo/streaming); os arquivos
meus estão listados na seção 6. Godot só foi rodado pelo usuário e por mim em momentos pontuais; nenhuma
medição de desempenho foi feita por script (as medições vêm dos logs que o usuário gerou jogando).

## 1. Diagnóstico (o que os dados provam e o que não)

- A GPU não é o gargalo (3–6 ms típico, máx. 14 ms). O custo é CPU de simulação.
- `evidence/claude-caos-20260929` e o commit `a2aa325` (ranking por script no caos): física em script ≈ 6,5 ms/passo
  (`Vehicle` 1,6, `Actor` 1,3, `DispatchVehicle` 0,95, `DispatchOfficer` 0,66, `DispatchController` 0,43) contra
  ≈ 1,2 ms/passo nativo. O ranking **não** separa linguagem de chamadas ao motor feitas dentro do script.
- A 6 estrelas a mediana do quadro sobe de ~4–5 ms (0★) para ~12–18 ms. **Cortar as unidades de despacho de 8 para 5 não
  baixou a mediana** (comparação de logs 10:27 e 10:57): o custo contínuo a 6★ não é só as viaturas. Causa ainda aberta.
- Espiral de física: aglomerados de ~10 quadros de 100–270 ms com `physics_steps = 8`. Com
  `HARBOR_MAX_PHYSICS_STEPS=3` não houve quadro com mais de 3 passos e os quadros >100 ms caíram de 14–16 para 3 por rodada
  (rodada isolada, cenário parecido, não é A/B controlado).
- Picos por construção na hora: `crew.deploy_police` 20–42 ms, `officer.spawn:tier4` até 26 ms, e a primeira aparição de cada
  modelo de carro (`vehicle_ready_visual:sport_coupe` 95 ms, `cargo_flatbed_truck` 60 ms, `union_sedan` 32 ms, `police_suv` 25 ms).
- Paradas de 0,5–1,8 s **sem trecho do rastro e sem queda de nós**: 2 por rodada nos logs iniciais; no último log só 1 de 530 ms.
  Causa **não identificada** (hipóteses não testadas: leitura síncrona de recurso, compilação de pipeline de efeito, processo externo).
- `process_ms` e `physics_ms` do log são o **máximo do último segundo** (monitor do motor), não custo por quadro.

## 2. Roteador de despacho em C# (`DispatchRoadRouter`)

Arquivos: `Harbor.csproj`, `Harbor.sln`, `gameplay/dispatch/RoadGraphSearch.cs`, `gameplay/dispatch/DispatchRoadRouter.gd`.

- Requer Godot **mono** 4.7.2 e .NET SDK 10 (instalado: 10.0.401). `net10.0`, `Godot.NET.Sdk/4.7.2`. Restore precisa da pasta
  `GodotSharp/Tools/nupkgs` do build mono como fonte NuGet (feito pelo `TestarRoteadorCSharp.cmd`).
- `RoadGraphSearch` é um espelho do grafo (`routes.vertices/edges`): `NearestEdge` com índice espacial em grade de 48 m,
  `Plan`/`Search` (Dijkstra com o mesmo heap do GDScript e parada ao assentar o destino), `BuildPath` (reamostragem da curva).
  O GDScript segue dono do grafo e do `Curve3D`; **o caminho GDScript original é o fallback** e a referência
  (sem build mono, ou com `HARBOR_NO_CSHARP=1`, nada muda). O espelho se refaz sozinho se o grafo mudar
  (assinatura = id do `routes`, tamanhos, primeiro/último vértice).
- Resultado do teste (`tests/dispatch/test_road_graph_native.gd`, grade sintética de 196 vértices, rotas de 725 m):
  0 divergências em 600 consultas de `nearest_edge`, 120 rotas (nós e curva ponto a ponto), 40 rotas de saída e bloqueios com expiração.
  `nearest_edge` 416 → 8 µs; `plan` ~5100 → ~1200 µs. **O que sobra do `plan` é ~90% bake de `Curve3D` pelo motor.**
- Chaves de A/B: `HARBOR_NO_CSHARP=1`; `HARBOR_PLAN_BAKE_SOURCE` e `HARBOR_PLAN_BAKE_RESULT` (intervalo de bake da curva-fonte e da curva
  entregue ao motorista). **Mudei o padrão de 0,25 para 0,5 m nos dois** (desvio medido máx. 3,6 cm; 1,0 m dava ~9 cm e foi descartado).
  `=0.25` restaura o comportamento antigo. Quem mais usa o roteador (táxi, ônibus, porto, terminal) herda o bake de 0,5 m e **não verifiquei** se algum depende de 0,25.
- No log real com C#: os trechos `router.plan:*` deixaram de passar de 2 ms (antes: 7 de `pursuit`, média 3,0, máx. 5,1 ms). Confundido por haver menos viaturas.
- Não portado: o A* de grade de `Gameplay._find_grid_path` (fronteira com busca linear, O(n²)); candidato a heap binário. Também não foi feito mover o `plan` para `WorkerThreadPool`.

## 3. Instrumentação: `StallLog` (log de quadros lentos)

- `runtime/StallLog.gd`, autoload `StallLog` em `project.godot`. Só liga com `HARBOR_STALL_LOG=1` (o `Jogar.cmd` e o `JogarCSharp.cmd` definem); desliga em `--headless`.
- Grava `evidence/stall-logs/stalls-AAAAMMDD-HHMMSS.log` (JSON por linha, ignorado pelo Git por `*.log`):
  `header` (versão, GPU, MSAA, `csharp_build`, chaves de A/B, `max_physics_steps`), `window` a cada 10 s
  (FPS, p50/p95/p99/máx em **ms**, contagem >33,3/50/100 ms, estrelas, unidades por serviço:estado, `router_native`) e `slow`
  (quadro > 40 ms, ou `HARBOR_STALL_MS`): passos de física, monitores, render CPU/GPU, nós/objetos e variações, `removed_roots`
  (raízes `queue_free`), chunks e os trechos do rastro `DispatchTrace` que começaram dentro do quadro.
- Liga `benchmark_trace` no mundo (desligar com `HARBOR_STALL_TRACE=0`). Só conta quadros com a partida pronta, sem pausa e com foco.
- `HARBOR_MAX_PHYSICS_STEPS=N` ajusta `Engine.max_physics_steps_per_frame` (padrão do motor 8). **`JogarCSharp.cmd` define 3 por padrão** (experimento); `Jogar.cmd` não.
- Comparar com `evidence/stall-logs/stalls-20261001-102703.log` (GDScript, 8 passos), `-105756` (C#, 8), `-110701` (C#, 3), `-113535` (C#, 3, regras novas).

## 4. Mudanças de jogo pedidas pelo usuário (todas **sem teste executado após a edição**)

- **Reforços de polícia pela metade** (`DispatchRules.gd`): `MAX_ACTIVE [0,2,3,3,4,4,5]`, `DEPLOYMENT [0,4,5,7,11,15,22]`,
  `FOOT_LIMIT [0,4,5,6,7,8,10]` (resposta inicial de 2 viaturas mantida; resto = inicial + ceil((antigo − inicial)/2)).
  `INTERVAL`, `MAX_UNITS (11)`, helicóptero e K9 **não** foram mexidos.
- **Atrasos:** `INITIAL_DELAY [0,10,8,6,5,5,5]` (antes `[0,6,3,1,1,1,1]`); viatura de averiguação com 0★ só depois de `INVESTIGATION_DELAY = 12 s` (antes imediata).
- **Averiguação:** o `FOOT_LIMIT[0]` era 0, então a equipe nunca descia. `DispatchUnit._deploy_police_crew` usa o limite de 1★ com 0★; a equipe
  desce, fica `INVESTIGATION_LINGER = 15 s` e a viatura entra em `recall` e parte.
- **Saída da van:** no máximo `OFFICERS_DEPLOY_BURST = 2` por vez (a van descia 6 num quadro).
- **Bombeiros** (`DispatchController._dispatch_emergency`): `MAX_FIRE_TRUCKS = 1`; só depois de 10–15 s de fogo
  (`fire_response_delay`); se o caminhão foi destruído, bloqueio de 30–45 s (`_fire_lockout_until`).
- **Carcaças** (`scripts/Vehicle.gd`): vida 0 de trânsito ambiente (`meta ambient_traffic`) ou despacho (`not player_damage_attribution`)
  some em 30 s com fade de 2 s (`transparency` nas malhas), sem colisão e sem luzes. Exceções: carro controlado/dirigido pelo jogador,
  `garage_reward`/`garage_place`, e `meta wreck_hold` (posto por `DispatchUnit._tick_wrecked` enquanto a equipe ainda age a pé).
  **Risco:** a primeira vez que cada material fica transparente pode compilar variante de shader (hitch); alternativa: afundar o carro no chão.
- **Bloqueio de estrada** (`PoliceRoadblock.gd`): removidos os dois blocos de concreto (colisão, faixa refletiva, lâmpada); fica só o tapete de espetos de 3,6 m no meio da pista.
- **Fuga de carro** (`DispatchController._active_police`): unidades em `recall` não contam mais em `MAX_ACTIVE`. Causa vista no log: com teto 5, viaturas
  paradas em recall + em perseguição somavam 5 e nenhuma nova aparecia à frente do jogador. **Causa provável, não confirmada** (sem posições no log).
- **Cheat `godmode`** (`Gameplay.gd`): digitar `godmode` liga/desliga; `_apply_player_damage` retorna, e o jogador e o carro dirigido recebem a marca
  `invulnerable` (a mesma de Maciota) via `_sync_god_mode`. Não vai para o save.

## 5. Testes e verificação

- `VerificarMudancas.cmd` (raiz): compila o C# e roda 8 testes com Godot padrão e com mono; grava `evidence/csharp-router/verificacao.txt`.
  Também há `TestarRoteadorCSharp.cmd` (teste do roteador), `JogarCSharp.cmd` e `Jogar.cmd` (ambos com `StallLog`).
- Última rodada completa do usuário: passam `test_regions`, `test_bridge_approach_terrain`, `test_native_driving`, `test_admission`,
  `test_dispatch_rules`, `test_feedback_police_access`. **Falham `test_dispatch_police` e `test_dispatch_emergency`** (padrão e mono).
- `test_dispatch_emergency`: esperava o caminhão em 5 s; eu atualizei para 20 s só no fogo. **Não reexecutado.**
- `test_dispatch_police`, check `policial vivo reage ao dano com ataque` (`tests/dispatch/test_dispatch_police.gd:184`): falha **3 de 3** no Godot padrão
  (determinístico). Não consegui isolar: o policial reage (o check anterior passa), mas o jogador não perde vida em 90 quadros. As alterações pendentes que li em
  `PoliceAgent.gd`, `PoliceCaseDirector.gd` e `Gameplay._advance_police_rounds` são renomeações (`round`→`round_index`, `visible`→`p_visible`) e as minhas só mexem no dano com `god_mode`.
  **Não sei se falha no `HEAD`.** Passo sugerido: rodar o mesmo teste num checkout limpo, ou conferir com quem fez a limpeza de avisos (`evidence/gdscript-warnings-20261001`).
- Testes que **eu alterei** para os valores novos: `test_dispatch_rules.gd`, `test_feedback_police_access.gd`, `test_dispatch_emergency.gd`. Revise se são os valores pretendidos.
- Falta: abrir o jogo e ver que carrega e anda com todas as mudanças da seção 4 juntas, e rodar a suíte mínima do `CLAUDE.md`.

## 6. Arquivos meus (para o commit; stage explícito)

Novos: `Harbor.csproj`, `Harbor.sln`, `gameplay/dispatch/RoadGraphSearch.cs`, `runtime/StallLog.gd`, `tests/dispatch/test_road_graph_native.gd`,
`TestarRoteadorCSharp.cmd`, `VerificarMudancas.cmd`, `JogarCSharp.cmd`, `docs/handoff-claude-20261001.md`.

Alterados (contêm também hunks de outros agentes em alguns): `gameplay/dispatch/DispatchRoadRouter.gd`, `gameplay/dispatch/DispatchRules.gd`,
`gameplay/dispatch/DispatchController.gd`, `gameplay/dispatch/DispatchUnit.gd`, `gameplay/police_response/ground/PoliceRoadblock.gd`, `scripts/Vehicle.gd`,
`gameplay/Gameplay.gd` (godmode; o resto do diff é de outro agente), `Jogar.cmd`, `project.godot` (só a linha `StallLog=`; o `[dotnet]` e `enabled=` do editor não são meus),
`tests/dispatch/test_dispatch_rules.gd`, `tests/dispatch/test_dispatch_emergency.gd`, `tests/test_feedback_police_access.gd`.

Coordenação: a Lu (mundo/streaming) reservou `NativeRegion.gd`, `ProductionWorld.gd`, `MountainTerrain3D.gd`, `TrafficYieldController.gd`, `PoliceCaseDirector.gd`; eu não toquei nesses.
`DispatchController.gd`, `DispatchUnit.gd`, `DispatchRules.gd` e `PoliceRoadblock.gd` **não estavam na minha reserva**; as edições foram pontuais, a pedido do usuário. Avise a Lu e a simulação antes de commitar.
Regra do repo: ninguém dá push sem o usuário pedir.

## 7. Próximos passos sugeridos (por valor esperado)

1. Rodar `VerificarMudancas.cmd`, abrir o jogo e fechar o item do `test_dispatch_police` (checkout limpo ou autor da limpeza de avisos).
2. Confirmar a fuga de carro: jogar a 6★, fugir dirigindo e ler no log os estados `recall`/`enroute` (acrescentar posições das unidades ao `slow` ajudaria).
3. Pré-construir os modelos de veículo na tela de carregamento (some o 95 ms do `sport_coupe`, 60 ms do caminhão etc.). `Vehicle.gd` + arquivos de mundo (Lu).
4. Achar o custo contínuo a 6★ que **não** são as viaturas: perfil por script (`tests/measure/measure_script_ranking.gd`) com o cenário atual.
5. Identificar as paradas de 0,5–1,8 s (rodar uma vez com `--verbose` e `--log-file` junto do `StallLog` e correlacionar leituras de recurso).
6. Se o `plan` ainda aparecer quente: mover para `WorkerThreadPool` (exige mudar `DispatchUnit._replan_towards`, que hoje espera o resultado na hora) e portar o A* de `Gameplay._find_grid_path`.
7. Android: a exportação com C# **não foi tentada**; o projeto abre sem o build mono (fallback em GDScript), mas isso nunca foi testado em Android.

## 8. Adendo (final da sessão): armas e efeitos — SEM teste executado

Motivação: log `stalls-20261001-122652` mostrou GPU 12–23 ms (normal 3–6) com lança-chamas/bazuca, mais duas paradas de ~1,1–1,3 s no início do uso das armas.
- **MSAA limitado a 4x** (`Settings.MAX_MSAA = 2`, opção 8× removida de `SettingsMenu`); config salva com 8× é rebaixada.
- **Explosões menores** (`CombatEffects.explosion`): escala `radius/7` (antes `/5`), luz 5.0 por 0,22 s (antes 8.0/0,3 s), chamuscado menor, menos partículas (fogo 28→18, fumaça 14→9, fagulhas 28→20, detritos 12→8). Vale para bazuca, granada e canhão do tanque. **Raio de dano da bazuca 140→112 px** (8,75→7 m).
- **Clarão e fumaça de cano menores** (`Gameplay._flash_muzzle`, fumaça 4→3 partículas).
- **Lança-chamas:** pacotes em `local_coords` e carregados com o deslocamento do jogador (`CombatEffects.carry_source`); origem do jato compensa a velocidade do jogador (a pose do bico é do quadro anterior). Queimar pessoas: antes só `gameplay_role == "civilian"` acendia; agora `_can_ignite` (qualquer `CharacterBody3D` vivo com `receive_damage`, exceto jogador e veículos).
- **Pré-aquecimento** (`CombatEffects.prewarm`, chamado por `Gameplay._prewarm_effects` só se `session.ready_for_play` ainda for falso): dispara chama/explosão/fumaça/luzes uma vez sob a tela de carregamento e limpa. Hipótese NÃO confirmada de que a parada de 1 s é primeira compilação de pipeline/luz; o log novo (`weapon`, `effects_emitting`, `effects_lights` nos quadros lentos) diz se continua.
