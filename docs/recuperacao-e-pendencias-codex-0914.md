# Recuperação de trabalho apagado e pendências do Codex — 14/09/2026

Sessão do Claude pedida pelo usuário depois que o Codex parou por limite de
tokens: "faça o teu trabalho e termine o dele". Três frentes: o jogo não
compilava, havia trabalho perdido e havia tarefas do Codex sem validação.

## 1. O que quebrou o jogo: `git checkout` sobre trabalho não commitado

A maior parte do repositório não está commitada. Nesta noite o Antigravity rodou
`git checkout <arquivo>` em arquivos com dias de mudanças, descartando tudo
desde o último commit de cada um:

| Horário | Arquivo | Efeito |
| --- | --- | --- |
| 13/09 01:01 | `audio/VehicleEngineSound.gd` | laço de 4 s refeito depois como 1 s (já superado) |
| 14/09 08:54 | `ui/MainMenu.gd` | refeito depois por outras sessões |
| 20:40 | `PlayerCar.gd` | tração, derrapagem, `rotate_clear`, partículas |
| 20:41 | `prototypes/living_cast/HarborCoupe.gd` | idem, lanternas, profundidade urbana |
| 20:43 e 20:44 | `world/shared/traffic/TrafficVehicle.gd` | toda a lógica de faixa (`TRAFFIC_SWEEP`, `TRAFFIC_FLOW`, `_lane_step_is_clear`), queda de moto, alarme |
| 20:49 | `world/harbor/HarborTransitBus.gd` | roubo do ônibus e corredor de pedestres |
| 20:53 | `world/harbor/cemetery/CemeteryKeeperHome.gd` | nada: arquivo não rastreado, o checkout falhou |

Consequência direta: `UrbanBus.gd` não compilava, e com ele a cena do porto.
O arquivo de 21:19 da tarefa de sombras do Antigravity partiu da versão do commit
de 11/09 do `TrafficVehicle.gd`.

### Como foi recuperado

- `TrafficVehicle.gd`: cópia completa de 20:46 guardada no banco de conversa do
  Antigravity (`~/.gemini/antigravity/conversations/fad0b524-….db`, passo 323).
  Tinha todas as edições do Codex até o biarticulado de 20:29.
- `PlayerCar.gd`: `git diff` completo das 17:41 no log do Codex + o diff das 20:24.
- `HarborCoupe.gd`: backup do Codex de 12/09 21:18 (`artifacts/feedback-0914-teste2`)
  + 3 diffs de hoje.
- `HarborTransitBus.gd`: backup do Codex de 12/09 10:37 (última edição dele).

Todos foram mesclados em 3 vias (`git merge-file recuperado HEAD atual`), para
**preservar o trabalho de sombras e de batida em poste do Antigravity** feito
depois do checkout. Conflitos resolvidos à mão: funções da moto recuperadas +
assinatura `is_post`; amassado reduzido em poste + faróis danificados; áudio de
batida pelo `VehicleCrashAudio` (sistema por material) em vez do som inline; um
único `ContactShadow.add_vehicle`. Cópias anteriores à restauração ficaram no
scratchpad da sessão, não no repositório.

Pedido aos agentes: **não usar `git checkout`/`restore`/`reset` em arquivo com
mudanças**. Neste repositório isso apaga trabalho de outras sessões.

## 2. Correções feitas

- **Compilação:** `LivingCivil._die` volta a casar com a assinatura do pai.
  Restou 1 script sem compilar, `prototypes/gameplay_repair_art_0909/ExtractionDemoRigFactory.gd`,
  território do Antigravity e não carregado pelo jogo.
- **Roubo de veículo sem vão para o motorista** (`TrafficVehicle`): desde 12:05 de
  hoje, se o motorista ejetado não tinha ponto livre de saída, o roubo inteiro
  era cancelado. O ônibus 01 do terminal, encostado na plataforma, ficava
  impossível de roubar. Agora o motorista não aparece, mas o roubo continua.
- **Monaliza de lado na entrega** (pedido "carro de lado" que o Codex não
  terminou): sprite e modelo só sincronizavam no `_physics_process`, parado
  durante o diálogo. `HarborCoupe.sync_presentation_heading()` é chamado pelo
  `PersonalCarManager` ao fim da entrega.
- **Guindastes do porto sul** (pedido "passar pelos guindastes"): a colisão nova
  do Codex descia 110 px abaixo da base e cobria o pátio onde os caminhões
  recebem o contêiner, quebrando a logística (23 falhas). A torre continua sólida
  para quem anda a pé; a colisão para na base original. Cais e `PortMarkedCarSet`
  mantêm a versão do Codex (sem efeito medido nos testes).
- **Áudio de revisão da Monaliza:** o kit usava `ENGINE._PROFILES.monaliza`, que
  não existe mais; passou a `ENGINE._profile("monaliza")`. WAVs regerados com o
  motor atual (laço de 1 s).
- **Capacete de moto desligado no jogo:** `Player.ensure_motorcycle_helmet()`,
  `motorcycle_helmet.sync_visual()` na reconstrução do figurino e
  `apply_on_foot_pose()` na física tinham sumido do `Player.gd` (o
  `MotorcycleModel` só liga o capacete se o método existir). Restaurados do backup
  do Codex de 12/09 (`artifacts/cave-review-0912/baseline-project/Player.gd`),
  junto com `ski_controller.sync_visuals()` na reconstrução.

## 3. Testes desatualizados (o jogo mudou, o teste não)

Cada um foi confirmado com diagnóstico antes da mudança:

- `test_menu_flow_integration`: o menu agora toca a transição do pôr do sol antes
  de `GameLoading.begin()` e a abertura dura ~86 s. O teste espera o carregador
  começar e pula a abertura. Os "Could not preload" no fim do log eram o
  encerramento abortando a carga em thread, não defeito.
- `test_bus_theft`: espera a saída terminar (ônibus longo usa perfil de caminhão).
- `test_monaliza_garage_access`: entra pela porta real; o `WorldPerimeter`
  devolve ao último ponto seguro quem está fora do mapa sem marca de interior.
- `test_monaliza_garage_exit`: marca a apresentação da Monaliza como vista (ela
  pausa o jogo); portão em 4,3 m; o bloco de reentrada que o Codex inseriu foi
  movido para depois do trajeto portão→rua, que ele invalidava.
- `test_water_presentation`: espera o fade exponencial das ondas; mede o riacho
  sobre o curso desenhado.
- `test_harbor_safety`: a rampa segue `HarborSouthPortLayout.ACCESS` (x=3310).
- `test_south_port`: prazo de caminhada calculado pela velocidade real (27,6 px/s,
  aumento de 15% pedido pelo usuário).
- `test_meshy_dante`: contrato novo, todos os trajes vestem o Meshy.
- `test_player_combat_pose` e `test_dante_motorcycle_helmet`: medem o rig
  procedural antigo e passam a fixar `use_meshy_dante = false`.
- `test_player_render_visibility`: aceita `UPDATE_WHEN_VISIBLE` (só exige não
  desativado ao mostrar o Player).
- `test_dante_gameplay_integration`: ações `move_*` do GameInput (desde 10/09),
  espera o embarque/desembarque animado, socket da arma = palma real, cadência
  comparando corrida com caminhada.
- `test_mountain_ski_3d_and_loop`: ajusta o relógio que o `MountainSkiSchedule`
  lê (primeiro nó de `day_night_manager`), não um relógio falso.
- `test_living_cast_contract`: não compilava antes (`LivingCivil`); agora acelera
  com `move_up` e espera o embarque animado terminar antes de medir o amassado.

## 4. Pendências conhecidas

- `test_harbor_safety` é instável: duas execuções seguidas do mesmo código deram
  2 falhas e 0 falhas (carro civil que não retoma a tempo / telemetria de
  travamento de cruzamento). Não foi resolvido.
- Veja a seção de verificação final para o estado dos demais testes.

## 5. Verificação final

Godot 4.7.2, renderizado (sem `--headless`), RTX 4060 Laptop, depois da última
edição do `Player.gd`:

- `tools/check_references.py`: 0 quebras novas. Varredura de compilação: 1.635
  scripts, 1 falha (`ExtractionDemoRigFactory.gd`, protótipo do Antigravity).
- 0 falhas: `test_menu_flow_integration`, `profile_load_time_0909`,
  `test_opening_cutscene_runtime`, `test_pedestrian_life_routines`,
  `test_pedestrian_render_lod`, `test_legacy_save_route`, `test_meshy_outfits`,
  `test_meshy_dante`, `test_meshy_knuckles`, `test_clothing_preview`,
  `test_dante_gameplay_integration`, `test_dante_motorcycle_helmet`,
  `test_player_combat_pose`, `test_player_render_visibility`,
  `test_mountain_ski_3d_and_loop`, `test_mountain_ski_transitions`,
  `test_character_fall_animation`, `test_vehicle_boarding_animation`,
  `test_respawn_upright`, `test_bus_theft`, `test_urban_bus_player_contact`,
  `test_articulated_driving`, `test_long_traffic`, `test_urban_bus_route_turns`,
  `test_tire_launch`, `test_coupe_handling`, `test_fixed_traffic_signals`,
  `test_street_lamp_impact`, `test_monaliza_audio`, `test_monaliza_paused_handoff`,
  `test_monaliza_garage_access`, `test_monaliza_garage_exit`,
  `test_water_presentation`, `test_harbor_ship_access`, `test_harbor_train_3d`,
  `test_harbor_mountain_rail`, `test_running_vehicle_theft_alarm`,
  `test_moving_vehicle_theft_reentry`, `test_motorcycles`, `test_south_port`,
  `test_garage_weapon_restrictions`, `test_living_cast_contract`.
- `test_harbor_safety`: 0 falhas nesta execução, mas 2 em uma de três execuções
  anteriores com o mesmo código. Instável; não resolvido.

Não medido: partida jogada de ponta a ponta, performance (FPS/frame), encaixe do
capacete sobre o cabelo do Dante Meshy.
