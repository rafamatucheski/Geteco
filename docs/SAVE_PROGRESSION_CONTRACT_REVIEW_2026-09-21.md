# Revisão dos contratos de save e progressão — V1 → V2

Data: 2026-09-21  
Escopo: revisão estática por leitura de missões, atividades, recompensas únicas, inventário/dinheiro, veículos e localização.  
Limite desta rodada: nenhum formato de persistência ou arquivo de runtime foi alterado; nenhum save real foi aberto ou modificado.

## Resultado executivo por prioridade

### P0 — O V2 não oferece caminho de importação do save produtivo do V1 (defeito comprovado por código)

**Efeito no jogador:** `Continuar`/`Carregar` no V2 não apresenta os cinco slots nem o autosave do V1. Todo o dinheiro, inventário, missões, recompensas únicas, veículos e localização parecem perdidos, embora o arquivo V1 permaneça intacto.

**Fonte V1 conferida**

- `systems/SaveManager.gd:7-11` define `user://saves/slot_NN.json` e `autosave.json`.
- `systems/SaveManager.gd:184-221` produz o envelope `{save_version, campaign, player, world, wanted}`.
- `systems/SaveManager.gd:272-313` lê esse envelope sem reescrever o arquivo; `systems/SaveManager.gd:321-345` restaura os quatro consumidores.
- `characters/Player.gd:1715-1750` produz dinheiro, armas/munição, roupas, recompensas únicas, colecionáveis, conquistas e Monaliza.
- `systems/CampaignState.gd:199-215` produz campanha canônica, campanha Cobra, atividades, residência e incidentes.
- `systems/RegionTravel.gd:134-179` produz região e veículo controlado.

**Implementação V2 conferida**

- `geteco_v2/project.godot:15-16` separa o diretório de usuário do V2.
- `geteco_v2/runtime/SaveStore.gd:3,7-20` procura apenas um caminho V2 e só aceita dados que `GameState.restore_snapshot` aceite.
- `geteco_v2/runtime/GameState.gd:43-46` exige `game == "geteco_v2"` e schemas 1/2 do próprio V2. `_migrate_intro` (`:98-109`) converte somente o protótipo V2 antigo, não o envelope produtivo V1.
- `geteco_v2/runtime/SessionLaunch.gd:4-32` enumera apenas `progress` e cinco slots dentro do namespace V2; não enumera `user://saves` do projeto V1.
- `geteco_v2/ui/MainMenu.gd:29-36,70-87,115-127` só inicia itens fornecidos por `V2Launch`.

**Cadeia atual**

`V1 Player/CampaignState/RegionTravel` → `SaveManager.save_game` → `user://saves/*.json` → **nenhum produtor de importação V2** → `SessionLaunch.list_slots` vê apenas arquivos V2 → `SaveStore.read_valid` rejeitaria o envelope V1 → nenhum consumidor V2 recebe o progresso.

**Ponto exato de integração proposto (não aplicado)**

1. Criar um adaptador isolado e somente-leitura, por exemplo `geteco_v2/runtime/V1SaveImporter.gd`, que leia uma cópia em memória dos slots do diretório de usuário `Geteco`; nunca renomeie, apague ou grave o V1.
2. Em `geteco_v2/runtime/SessionLaunch.gd:13-47`, listar separadamente slots V1 válidos como opções de **importar para um slot V2 vazio**. Não passar o arquivo V1 diretamente a `SaveStore`.
3. O adaptador deve produzir um `GameState` V2 completo em memória, validá-lo por `GameState.restore_snapshot`, e só então publicá-lo via `SaveStore.save` no destino V2. O arquivo V1 continua a fonte imutável.
4. A UI de `geteco_v2/ui/MainMenu.gd:70-87` deve distinguir “Carregar V2” de “Importar V1”; falha de conversão não pode tornar o slot V1 inválido nem ocupá-lo.

### P0 — O progresso canônico de nove beats não pertence ao snapshot V2 (defeito comprovado por código)

**Efeito no jogador:** o beat canônico já alcançado no V1 não tem destino no estado V2. Além disso, se `CanonicalCampaign` for conectado ao runtime como está, qualquer avanço nele desaparece ao recarregar.

**Evidência**

- O V1 produtivo mantém `current_stage`, `completed_beats`, regiões, territórios e flags em `systems/CampaignState.gd:16-21`; `to_save_data` os grava em `:199-215` e `restore_from_save` os consome em `:218-259`.
- A abertura produtiva realmente avança o primeiro beat em `world/harbor/campaign/HarborArrivalMission.gd:241-245`.
- O V2 possui um ledger compatível em `geteco_v2/systems/campaign/CanonicalCampaign.gd:4-14,58-97`.
- Porém a única referência executável a esse módulo fora dele está no teste (`geteco_v2/tests/test_campaign_economy.gd`); `geteco_v2/runtime/GameState.gd:2-7` instancia somente `Economy`, `CampaignRuntime` (o arco Harbor de seis missões) e `Progression`.
- `GameState.snapshot` (`geteco_v2/runtime/GameState.gd:40-42`) não contém o ledger canônico; `restore_snapshot` (`:60-96`) tampouco o restaura.

**Cadeia atual**

`V1 HarborArrivalMission.complete_current_beat` → `CampaignState` → `SaveManager.campaign` → **sem campo/adapter no GameState V2**.  
Em V2: `CanonicalCampaign.complete_beat` → estado apenas em memória → **fora de GameState.snapshot** → reload cria ledger novo → consumidor retornaria ao `prologue_call`.

**Ponto exato de integração proposto (não aplicado)**

- Em uma futura versão explícita do schema central, `geteco_v2/runtime/GameState.gd:5-7,40-42,60-96` deve possuir, validar e restaurar `CanonicalCampaign` de modo transacional.
- O importador deve mapear diretamente os campos V1 `current_stage/completed_beats/campaign_flags/unlocked_regions/unlocked_territories` para o ledger e exigir `CanonicalCampaign.validate_snapshot` antes da publicação.
- Não inferir beats posteriores a partir das seis missões Harbor: são namespaces diferentes. O V1 só fornece prova para os beats e flags realmente presentes no slot.

### P0 — Marcadores de recompensa e economia são validados separadamente (defeito comprovado por código; manifestação em saves normais exige execução)

**Efeito no jogador:** um snapshot estruturalmente aceito pode esconder uma recompensa já marcada como coletada/concedida sem que dinheiro, arma ou recibo correspondente exista. O jogador não consegue recolhê-la novamente. Esse risco é crítico no importador V1, que terá de montar os dois lados do contrato.

**Evidência 1 — recompensa de missão**

- O produtor V2 conclui missão, cria `pending_rewards` e depois tenta pagar em `geteco_v2/systems/campaign/CampaignRuntime.gd:162-193`.
- O consumidor de mundo chama `claim_reward`, ignora seu retorno e salva em `geteco_v2/runtime/MissionWorld.gd:188-197`.
- `CampaignRuntime.validate_snapshot` só exige que cada missão concluída esteja em `pending_rewards` **ou** `claimed_rewards` (`:217-243`); não exige recibo `reward:campaign:<id>` na economia para `claimed_rewards`.
- `GameState.restore_snapshot` cria e valida economia/campanha separadamente em `geteco_v2/runtime/GameState.gd:60-63`; não há reconciliação cruzada.

Snapshot aceito demonstrável por inspeção: mover um ID concluído para `claimed_rewards`, removê-lo de `pending_rewards` e omitir o recibo na economia ainda satisfaz ambos os validadores. Depois, `claim_reward` (`CampaignRuntime.gd:179-193`) não tem pendência a pagar. Isso é prova estática do furo de contrato; não foi executado para afirmar que algum save real já chegou a esse estado.

**Evidência 2 — recompensas únicas do mundo**

- O produtor/consumidor está em `geteco_v2/runtime/FullSession.gd:916-940`: `world.rewards` decide visibilidade, enquanto `Economy` entrega o resultado.
- O código adiciona o ID a `world.rewards` mesmo sem verificar o retorno de `grant_reward`, `grant_weapon`, `add_ammo` ou `grant_item` (`:931-938`).
- `GameState.restore_snapshot` verifica apenas que `world.rewards` é `Array` (`geteco_v2/runtime/GameState.gd:64-72`), sem conferir dinheiro/arma/inventário/recibo.
- Exemplos concretos de IDs estão em `geteco_v2/world/places/PlaceCatalog.gd:60-65` e `geteco_v2/world/places/CargoPlaneNative.gd:36-43`.

**Cadeias**

`CampaignRuntime.apply_event` → `pending_rewards` → `Economy.grant_reward`/recibo → `claim_reward` → `GameState.snapshot` → restores independentes → objetivo/HUD e saldo.  
`NativePlace/CargoPlaneNative.reward_points` → `_collect_reward` → `Economy` + `world.rewards` → `GameState.snapshot` → `_update_reward` esconde o item → inventário/saldo.

**Ponto exato de integração proposto (não aplicado)**

- Adicionar uma validação cruzada pura chamada por `GameState.restore_snapshot` após `:63` e antes de atribuir os módulos em `:90-96`.
- Para campanha: todo `claimed_rewards[id]` deve ter recibo `reward:campaign:<id>` com o valor canônico; pendência pode ser reconciliada com recibo já existente porque `claim_reward` já suporta esse caso.
- Para `world.rewards`: cash exige recibo e valor canônico; arma exige posse; item exige a quantidade mínima. O catálogo de recompensa, não o save, deve fornecer tipo/valor.
- Em `FullSession._collect_reward:931-938`, só marcar/esconder depois de sucesso ou de reconciliação comprovada e idempotente.
- O importador deve construir ambos os lados no mesmo objeto e validar antes de gravar; nunca “corrigir” o saldo do V1 somando novamente recompensas históricas.

## P1 — Adaptações V1 → V2 obrigatórias; cópia direta é incompatível

### Missões Harbor e recompensa única (comprovado)

O V1 usa `cobra_campaign` com `completed` e `reward_claimed` como dicionários, `active_id` e `stage` (`world/harbor/campaign/CobraCampaignState.gd:24-44,106-137`). O runtime V1 conclui, marca o prêmio e soma dinheiro em `world/harbor/campaign/CobraCampaignController.gd:331-340`. O V2 exige `completed` ordenado, `pending_rewards`, `claimed_rewards` e `step` compatível com os steps autorados (`geteco_v2/systems/campaign/CampaignRuntime.gd:5-13,213-264`).

Integração proposta:

- mapear apenas IDs comuns e concluídos na ordem canônica: `primeiro_giro` + os cinco `CobraCampaignState.MISSION_IDS`;
- `reward_claimed[id] == true` → `claimed_rewards`; caso contrário → `pending_rewards` com o valor de `HarborMissions`;
- não somar novamente recompensas já incluídas em `player.money`;
- não copiar `stage` para `step`: os estados intermediários não têm contrato de equivalência comprovado. Preservar missões concluídas e reiniciar uma missão ativa do começo, apresentando essa adaptação ao jogador. Mapear stage exige uma tabela por evento físico, ainda não existente.

### Inventário, combate e recompensas únicas (comprovado)

O snapshot V1 separa esses dados em `player` (`characters/Player.gd:1724-1750`); o V2 os separa entre `Economy` (`geteco_v2/systems/economy/Economy.gd:13-26,292-361`), `combat` (`geteco_v2/gameplay/Gameplay.gd:1283-1305`) e `world.rewards`.

Mapeamento mínimo:

- `money` → `economy.balance` sem reexecutar pagamentos;
- `weapon_inventory` + `weapon_ammo.clip/reserve` → `economy.weapons.magazine/reserve`, apenas IDs presentes no catálogo V2;
- `active_weapon_id`, roupas, loadout, colecionáveis e conquistas → seus campos equivalentes, passando por validação de catálogo;
- `health`, `armor` e wanted sanitizado → `combat`; `weapon_customization` deve ser normalizado para `combat.customization`, não colocado na economia;
- `world_pickups_collected` deve ser dividido por catálogo: IDs de cenário vão para `world.rewards`; `monaliza_starter_case` precisa do recibo idempotente correspondente; descobertas de arma precisam alimentar `economy.discoveries` quando o catálogo V2 exigir.

Qualquer ID V1 sem equivalente deve gerar aviso de importação e permanecer apenas no arquivo V1; não inventar substituto.

### Veículos e residência (comprovado; posição física exige execução)

O V1 grava o veículo controlado em `systems/RegionTravel.gd:152-176`, a Monaliza em `characters/Player.gd:1733`/`world/harbor/monaliza/PersonalCarManager.gd:85-101`, e a vaga extra em `CampaignState.residence_state`. O V2 divide o carro corrente (`FleetState`, `GameState.world.vehicles`), Monaliza/garagem (`GarageRewards`) e vaga extra (`Activities.home`).

Incompatibilidades diretas:

- V1 usa posição 2D em pixels; V2 usa `[x,y,z]` em metros (`geteco_v2/runtime/FleetState.gd:3-20`).
- V1 residência aceita status `stored/deployed/parked/driven` (`world/harbor/residences/ResidenceManager.gd:394-438,482-520`); V2 aceita só `stored/deployed` (`geteco_v2/activities/Residence.gd:115-138`).
- V1 mantém nitro e pneus antifuro na vaga (`ResidenceManager.gd:461-479`); o snapshot V2 de residência não possui esses campos.

Integração proposta:

- mapear apenas arquétipos existentes em `FleetCatalog`; veículo desconhecido deve resultar em retomada a pé com aviso, sem apagar o V1;
- converter Harbor `(x,y)` para `(x/16, chão, y/16)`; no Mountain, respeitar `world.coordinates_version` e o offset documentado no produtor V1 (`systems/RegionTravel.gd:134-151`) antes da escala V2 (`geteco_v2/activities/ActivityDefinitions.gd:2-3,28-30`);
- normalizar `parked/driven` para `deployed` somente depois de resolver duplicidade com `world.vehicle`; `stored` permanece `stored`;
- decidir explicitamente a perda ou futura implementação de nitro/pneu; não fingir que foram preservados.

A conversão numérica é comprovável por código. Chão livre, colisão, orientação e ausência de duplicidade no mundo renderizado são **hipóteses que exigem execução**.

### Localização (comprovado; admissão física exige execução)

O V1 salva `player.position`, `world.region`, interior e retorno externo (`characters/Player.gd:1718-1726`; `systems/RegionTravel.gd:134-151`). O V2 persiste `region_id/place_id/checkpoint_id` e, ao ar livre, `world.pedestrian` (`geteco_v2/runtime/GameState.gd:9-12,40-59`; `geteco_v2/runtime/FullSession.gd:327-358,950-953`).

Integração proposta:

- mapear região apenas para `harbor`/`mountain`;
- mapear interior somente quando houver ID explícito com correspondente em `PlaceCatalog`; caso contrário retomar pelo checkpoint seguro da região;
- produzir `world.pedestrian` apenas para posição externa finita e dentro do limite V2;
- nunca restaurar diretamente posição interior V1 como posição global V2.

O fallback de contrato existe no V2. A segurança física do ponto convertido precisa de execução com colisão carregada; não foi validada nesta rodada.

## Hipóteses que exigem execução dirigida

1. Saves V1 reais podem conter variantes antigas de `cobra_campaign`, `residence_state`, veículo ou IDs de pickup não cobertos pelos produtores atuais. É preciso testar cópias representativas, sem modificar os originais.
2. Posições convertidas podem cair sobre sólido, fora do terreno ou longe do chunk carregado. Validar Harbor/Mountain, exterior/interior, a pé/dirigindo e vaga armazenada/deployed.
3. Missão ativa reiniciada pode deixar ator/veículo exclusivo V1 sem equivalente; validar cada ID ativo com entrada limpa do adaptador, não transportar `stage` cru.
4. O defeito de recompensa cruzada é comprovado por validação estática; não há prova nesta revisão de que saves V2 produzidos normalmente já contenham essa inconsistência.

## Arquivos alterados e verificações

Arquivo criado nesta frente:

- `geteco_v2/docs/SAVE_PROGRESSION_CONTRACT_REVIEW_2026-09-21.md`

Nenhum código, schema ou save foi alterado. Não foram executados Godot, testes, benchmarks, build, validação física ou commits, conforme solicitado. A revisão comprova contratos e incompatibilidades apenas por leitura; compilação, funcionamento, colisão e desempenho permanecem não validados.
