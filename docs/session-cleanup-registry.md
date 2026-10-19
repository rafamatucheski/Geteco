# Registro de limpeza da sessão (`FullSession.CANCEL_STEPS`)

Primeira fatia da quebra de `runtime/FullSession.gd` (18/10/2026). Antes, cada evento da sessão
tinha a própria lista de "cancela o que está rodando" escrita à mão: `_on_death`, `_on_arrest`,
`_respawn`, `load_game`, `return_to_main_menu`, `_begin_transition` e
`ProductionWorld._travel_checked`. As listas eram um pouco diferentes entre si e um sistema
esquecido numa delas seguia rodando através daquele evento. Agora as listas são dados em
`CANCEL_STEPS` e cada função chama `_cancel_for(etapa)`. **O comportamento não mudou**: mesma
ordem, mesmos argumentos, mesmos guardas. As diferenças entre eventos continuam, marcadas abaixo
com ⚑, para alguém decidir caso a caso; nada foi unificado em silêncio.

Contrato: `tests/test_session_cleanup_registry.gd` (lista FAST de `tools/run_core_suite.sh`).
Ele roda as funções de verdade com sistemas falsos que anotam cada chamada e o estado em volta
(saúde, trava de entrada, resgate, prisão, prompt). As sequências esperadas foram conferidas
contra o código **antes** do registro (29 de 29 cenários passaram nele) e depois (38 de 38).

## Etapas

Uma etapa numerada existe onde a função intercala estado ou um guarda entre as chamadas; juntar
etapas mudaria a ordem relativa a esse estado.

| Etapa | Função | O que separa da próxima |
|---|---|---|
| `death_1` | `_on_death` | guarda `rescue_pending` (morte repetida só cancela a ilusão) |
| `death_2` | `_on_death` | `robberies.player_died()` (saque perdido), `arrest_pending = false`, `health = 0` |
| `death_3` | `_on_death` | trava de entrada, `on_player_death`, colisão, `rescue_pending = true`, prompt, HUD |
| `death_4` | `_on_death` | apresentação "SE FODEU" e `_respawn` |
| `arrest_1` | `_on_arrest` | `arrest_pending = true` e trava de entrada (a ilusão pode soltar a trava) |
| `arrest_2` | `_on_arrest` | `prompt.text = ""` |
| `arrest_3` | `_on_arrest` | trava de entrada reafirmada (a desmontagem pode devolver uma trava antiga) |
| `rescue_1` | `_respawn` | guarda `respawn_busy`; depois `_begin_transition("rescue")` roda `transition` |
| `rescue_2` | `_respawn` | quarto desmontado, local, `gameplay.respawn()`, `respawn_player()` |
| `rescue_3` | `_respawn` | `sync_dispatch_location()` e a recuperação de frio e vinho (fora do registro) |
| `load_1` | `load_game` | as cinco recusas (prova, Jessica, transição, desembarque, veículo) |
| `load_2` | `load_game` | `reload_current_scene()` |
| `menu_1` | `return_to_main_menu` | recusa por transição ou desembarque |
| `menu_2` | `return_to_main_menu` | troca para `MainMenu.tscn` |
| `transition` | `_begin_transition` | o parque que segue ativo recusa (`abort_if_active`) antes da serra |
| `travel` | `ProductionWorld._travel_checked` | depois do teste de solo do destino, antes da troca de região |

## Inventário: sistema × evento

Célula = etapa·posição e argumento. Vazio = o sistema **não** é cancelado naquele evento.

| Sistema | Método | Morte | Prisão | Resgate | Carregar | Menu | Transição | Viagem |
|---|---|---|---|---|---|---|---|---|
| `upside_world` | `cancel` | 1·1 `death, false` | 1·1 `arrest` | 1·1 `rescue, false` | 1·1 `load` | 1·1 `main_menu` | | |
| `arcade` | `close` | | | via transição | | | ·1 | |
| `fishing` | `cancel_attempt` | 2·1 "Pesca interrompida." | ⚑ | via transição | 1·2 "Pesca encerrada." | ⚑ | ·2 "Pesca encerrada." | ⚑ |
| `coastal_lookout` | `leave` | 2·2 | ⚑ | via transição | 1·3 | ⚑ | ·3 | ⚑ |
| `amusement_park` | `leave` | 2·3 | 2·1 | via transição | 1·4 | 1·2 | ·4 (aborta se seguir ativo) | ⚑ |
| `regional_coach` | `cancel_for_transition` | 2·4 | 2·2 | | recusa se ocupado | recusa se ocupado | | recusa se ocupado |
| `railway` | `cancel_for_transition` | 2·5 | 2·3 | | recusa se ocupado | recusa se ocupado | | recusa se ocupado |
| sessão | `interrupt_dialogue` | 4·2 | 2·4 | | | | | |
| `desert` | `cancel_attempt` | 3·1 | 2·5 | | ⚑ recusa se em prova | 1·3 | | (viagem recusada se em prova) |
| `mining` | `cancel_attempt` | 3·2 | 2·6 | | ⚑ | 1·4 | | ⚑ |
| `jessica` | `cancel_for_transition` | 3·3 | 3·4 | | recusa se dirigindo | recusa (transição) | | ·8 |
| `services` | `cancel_auto_service` (se existir) | 3·4 `player_death` | 3·1 `player_arrest` | | ⚑ | ⚑ | | ⚑ |
| `world.driving` | `cancel_transition` (se existir) | 3·5 `player_death` | 3·2 `player_arrest` | | recusa se no veículo | | | (viagem recusada no veículo) |
| `passenger_transport` | `_brake` (se embarcado) | 4·1 | 3·3 | | recusa se embarcado | recusa se embarcado | | |
| `passenger_transport` | `cancel_for_transition` | | | 2·1 | | | | ·2 |
| `garage_rewards` | `cancel_press_delivery` | 4·3 | 3·5 | ⚑ | 2·1 | 2·1 | | ·6 |
| `activities` | `cancel_attempt` | 4·4 | 3·6 | | ⚑ | ⚑ | | ·3 |
| `mountain_progression` | `cancel_attempt` | 4·5 | 3·7 | | ⚑ | ⚑ | | ·4 |
| `mountain_activities` | `cancel_attempt` | 4·6 | 3·8 | via transição | ⚑ | ⚑ | ·5 | ·5 |
| `mission_world` | `cancel_attempt` | 4·7 `player_death` | 3·9 `player_arrest` | | ⚑ | ⚑ | | ·7 `world_transition`, só no `jessica_bank` com Jessica montada |
| `building_entrance` | `reset` | | | 2·2 | | | | |
| `service_roofs` | `clear` | | | 2·3 `true` | | | | |
| `armored_transport` | `suspend_for_travel` | (sinal próprio) | (sinal próprio) | | | | | ·1 |
| `world.traffic_yield` | `release_all` | | | 3·1 `rescue` | 2·2 `load` | 2·2 `main_menu` | | ·9 `travel` |
| `world.dispatch` | `dismiss_all` | | | 3·2 `rescue` | 2·3 `load` | 2·3 `main_menu` | | ·10 `travel` |

Fora do registro, de propósito (não é cancelamento ou precisa da resposta):
`robberies.player_died()` na morte (vira `bank_death_loss`), `cold.prepare_collision_at` /
`controller.prepare_connection_at` (posicionamento do resgate), `cold.recover_after_rescue()` e
`wine.recover()` (recuperação), a desmontagem do quarto e dos NPCs de serviço, e o que a viagem
faz com a população (`on_region_changed`, `reset_region`, reações, estacionamento, veículos).

## Diferenças mantidas (⚑) — decidir em fatia própria

1. **Carregar recusado já encerrou pesca, mirante e parque**: `load_1` roda antes das cinco
   recusas. O menu recusado, do mesmo jeito, já cancelou deserto e mineração.
2. **A morte não reafirma a trava de entrada depois da desmontagem**; a prisão sim
   (`arrest_3` é seguida de `input_locked = true`). Se a desmontagem da missão devolver uma trava
   antiga, o corpo fica destravado durante o "SE FODEU" (o contrato mostra isso com um falso).
3. **Pesca e mirante** param na morte, no carregar e na transição, mas não na prisão, no menu
   nem na viagem.
4. **Mineração** para na morte, na prisão e no menu, mas não no carregar nem na viagem.
5. **Serviço automático** (`services`) só para na morte e na prisão.
6. **Atividades, progressão e atividades da serra, missão** param na morte, na prisão e na
   viagem, não no carregar nem no menu (a cena é recarregada, mas o `cancel_attempt` não roda).
7. **Prensa da garagem** para em tudo menos no resgate e na transição.
8. **Deserto** é cancelado na morte, na prisão e no menu; o carregar e a viagem recusam enquanto
   há prova.

## Fora desta fatia, para a próxima

- Seis sistemas ouvem `gameplay.player_died` por conta própria (`ArmoredTransport._failed`,
  `MountainDownhill`, `DesertCampaign._reset_visit`, `DragMeetTakeshi._reset_visit`,
  `DragMeetLife._clear`, `StealableMeetCar._on_death`). Mas `_on_death` também é chamado
  **direto**, sem o sinal: queda para fora do mundo (`FullSession._process`), local restaurado
  inválido (`restore_location`), `JessicaRuntime`, `PassengerTransport` (três pontos) e
  `RegionalCoachTransit`. Nessas mortes esses seis sistemas não ficam sabendo. Não foi conferido
  jogando.
- Muitos sistemas consultam `gameplay.health <= 0` a cada quadro em vez de reagir ao evento
  (mais de 130 arquivos do jogo citam a expressão, parte deles para saúde de NPC ou veículo).
