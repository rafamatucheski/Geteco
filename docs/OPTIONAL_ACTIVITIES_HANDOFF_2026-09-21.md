# Handoff — atividades opcionais V1 → Geteco V2

Data da inspeção: 2026-09-21. Escopo: leitura estática das cadeias produtivas e implementação isolada da regra de pagamento das provas de ski. Nenhum relatório anterior foi usado como prova de execução.

## Prioridade e impacto no jogador

### P1 — prova de ski repetida paga menos que no V1 (defeito comprovado)

No V1 produtivo, `world/mountain_pass/SkiRaceController.gd:153-165` paga a recompensa base em **toda** conclusão e acrescenta o bônus em **todo** novo recorde. No V2, `geteco_v2/activities/MountainProgression.gd:214-223` usa os recibos fixos `ski_finish:<curso>` e `ski_record:<curso>`; depois da primeira conclusão, ambos recusam qualquer novo pagamento. O jogador pode repetir a atividade, mas deixa de receber a base e também não recebe bônus ao melhorar o tempo mais tarde.

Foi criado `geteco_v2/activities/V1OptionalRewardPolicy.gd`, módulo sem estado e sem trabalho por frame. Ele:

- calcula a base por conclusão e o bônus somente quando o tempo melhora;
- cria recibos seriados a partir das transações já persistidas pela economia, sem acrescentar campo ao snapshot de atividades;
- aplica base e bônus de forma atômica, restaurando a carteira se a segunda concessão falhar;
- convive com os recibos fixos já gravados pelo V2, pois estes não têm o sufixo serial.

O módulo ainda não está conectado porque `MountainProgression.gd` está ocupado por outra sessão. Encaixe exato para o integrador: em `MountainProgression.gd:_finish` (`:214-225`), antes de alterar `data.best`, obter `previous_best = data.best.get(race.id, null)`, montar o settlement com `V1OptionalRewardPolicy.ski_settlement(race.id, spec, race.elapsed, previous_best, session.state.economy.snapshot().transactions)`, aplicá-lo com `apply_ski_settlement`, e somente então atualizar `data.best` quando `settlement.record` for verdadeiro. O valor da mensagem deve vir de `settlement.amount`. O bloco atual dos dois recibos fixos deve ser removido na integração.

### P2 — identidade do RPG de exploração diverge (defeito comprovado)

O V1 salva o RPG da caverna como `mountain_waterfall_secret_rpg_01` em `world/mountain_pass/CaveSecretWeapon.gd:21`. O V2 declara o mesmo prêmio como `mountain_cave_rpg` em `geteco_v2/world/places/PlaceCatalog.gd:65`. É o único ID divergente entre os prêmios de exploração conferidos abaixo. Isso quebra a equivalência de recibo durante migração e pode reapresentar o item como não recolhido se o estado V1 for convertido literalmente.

Não foi alterado porque `PlaceCatalog.gd` não está na reserva exclusiva desta frente e a compatibilidade exige decisão conjunta com a migração de save. Encaixe exato: usar `mountain_waterfall_secret_rpg_01` como ID canônico futuro em `PlaceCatalog.gd:65` e, no adaptador de migração/restauração, tratar o ID V2 já publicado `mountain_cave_rpg` como alias já recolhido. Não basta apenas renomear o catálogo, pois saves V2 existentes com o ID novo precisam continuar reconhecidos.

### P2 — drift 3D acrescenta regra inexistente no V1 (adaptação comprovada; aceitação pendente)

As duas zonas, duração, tolerância fora da área, limiares de velocidade/lateral, combo e pagamento foram preservados. Porém `geteco_v2/activities/Motorsport.gd:57-64` exige ângulo entre 8° e 80°, mede deslocamento real e rejeita giro em ré/pressão contra parede; `cars/DriftChallengeZone.gd:82-116` não tinha os limites angulares. É uma adaptação anti-exploit ao movimento 3D, não uma cópia exata da regra V1. Ela precisa de decisão do integrador e verificação dirigida ao volante; não foi alterada no arquivo ocupado.

## Fonte V1 produtiva e estado V2

### Cadeia realmente conectada no V1

- Novo jogo: `ui/MainMenu.gd:7,114` abre `world/harbor/HarborGame.tscn`.
- Corridas e coleta do porto: `HarborGame._start_gameplay` chama `_spawn_world_extras` e `_spawn_motorsport_weather`; as definições produtivas estão em `world/harbor/HarborGame.gd:161-205,251-260`.
- Serra: `HarborGame` instancia `world/harbor/ContinuousWorld.gd`; este carrega `world/mountain_pass/MountainPass.tscn`, que instancia `MountainExpedition`, `MountainSkiArea` e `MountainMysteryDirector` em `world/mountain_pass/MountainPass.gd:86-102`.
- A cena `legacy/Main.tscn` e `legacy/city_demo/scripts/CityDemo.gd` só são escolhidas para saves antigos sem a flag Harbor por `world/harbor/HarborSceneRoute.gd:3-10`. As cinco provas de `cars/RaceCatalog.gd`, instanciadas por `legacy/city_demo/scripts/CityDemo.gd:111,138-141`, não são as corridas do novo jogo produtivo e não foram migradas como substitutas.

### Corridas livres do Harbor — conectadas

O V1 produtivo possui exatamente:

- `harbor_docks`: base R$ 400, recorde R$ 200, quatro checkpoints e retorno à largada;
- `harbor_foundry`: base R$ 650, recorde R$ 300, quatro checkpoints e retorno à largada.

Fonte: `world/harbor/HarborGame.gd:255-256`; pagamento repetível e bônus de recorde: `cars/NightRaceController.gd:163-174`.

O V2 replica IDs, rotas e valores em `geteco_v2/activities/ActivityDefinitions.gd:8-22`, converte pixels para metros uma única vez por `at()`, apresenta as ações por `Activities.nearest_action`, executa por `Motorsport` e paga por tentativa em `Activities._finish_motorsport` (`:171-188`). A cadeia está conectada por `geteco_v2/runtime/FullSession.gd:262-264,538-610`. Não foi encontrada lacuna estática nesta cadeia.

### Drift livre — conectado com adaptação 3D

O V1 produtivo instancia `harbor_westgate` (raio 120, R$ 150/1.000 pontos) e `harbor_cold_storage` (raio 130, R$ 200/1.000 pontos) em `world/harbor/HarborGame.gd:193-202`. O V2 mantém IDs, posições, raios e valores em `ActivityDefinitions.gd:23-28`; `Activities` converte os raios para metros e paga por tentativa. A diferença angular descrita em P2 é a única divergência de regra encontrada por leitura.

### Desafios da serra — conectados, recompensa parcial

As três provas produtivas vêm de `world/mountain_pass/MountainSkiLayout.gd:13-43`:

- `ski_primeira_descida`: R$ 260 + R$ 120 por novo recorde;
- `ski_slalom_pinhal`: R$ 480 + R$ 220 por novo recorde;
- `ski_pista_da_sombra`: R$ 900 + R$ 400 por novo recorde, exige as três pistas da expedição.

O V2 preserva cursos, janelas de 08:00–18:00, aluguel de R$ 250, retirada do equipamento, requisito das três pistas e movimento 3D em `MountainProgression.gd`. `FullSession.nearest/interact` encaminha ações `ski_*` ao módulo (`FullSession.gd:538-582`) e o snapshot é capturado em `FullSession.gd:963`. A atividade está conectada; somente a política de pagamento repetido está parcial.

### Coleta — conectada

O V1 produtivo possui dez IDs conhecidos: sete no Harbor (incluindo a carta do cemitério) e três evidências da expedição. As seis peças do mapa são instanciadas em `HarborGame.gd:178-191`; a carta em `HarborCemetery.gd:267-269`; mochila, diário e câmera em `MountainSceneryBuilder.gd:1061-1064` e `MountainMysteryCaveInterior.gd:49-66`. Cada coleta paga R$ 50 e os totais 3, 5 e 10 acrescentam R$ 100, R$ 200 e R$ 500 (`economy/CollectibleCatalog.gd:57-58`; `characters/Player.gd:687-705`).

O V2 mantém os dez IDs e os mesmos valores em `data/catalogs/CollectibleCatalog.gd` e `systems/economy/Economy.gd:186-191`. `ActivityDefinitions.collectibles` contém os dez pontos; `Activities._rebuild` cria `Area3D`, usa raycast apenas para apoiar achados exteriores no chão e preserva coordenadas locais no interior. A coleta chama `Economy.collect`, atualiza conquistas e salva. O menu existente lista os mesmos IDs em `ui/PauseMenu.gd:94-118`. Está conectada.

Adaptação 3D conferida: coordenadas exteriores V1 são divididas por 16; a região da montanha recebe o offset contínuo; diário/câmera usam as posições locais originais; a mochila usa o ponto da cachoeira mais o deslocamento local do modelo. A apresentação virou malha simples sem criar menu novo.

### Exploração e prêmios únicos — conectados, com um ID divergente

Foram conferidos no V1 e no V2:

- dinheiro dos seis chalés variantes: R$ 5.000 / 850 / 450 / 1.200 / 650 / 1.800;
- Estação Zero: R$ 1.500 (`mountain_bunker_cash_01`);
- Summit: R$ 900 (`summit_lodge_cash_01`);
- abrigo dos lenhadores: machado (`lumberjack_shelter_axe`);
- chalé principal: rifle de caça + 35 munições, machado e faca;
- avião cargueiro: R$ 1.800 (`mountain_cargo_plane_treasure_01`) e SMG + 20 munições (`mountain_cargo_plane_smg_01`);
- caverna: RPG, com a divergência de ID descrita em P2.

No V2, `PlaceCatalog.definitions()` entrega os prêmios de interiores a `NativePlace`, `NativeRegion` instancia `CargoPlaneNative`, e `FullSession._collect_reward` (`:921-939`) concede e registra uma única coleta. A cadeia está conectada por código; proximidade, acessibilidade física e restauração ainda exigem execução.

## Arquivos desta frente

- Criado: `geteco_v2/activities/V1OptionalRewardPolicy.gd`.
- Criado: `geteco_v2/docs/OPTIONAL_ACTIVITIES_HANDOFF_2026-09-21.md`.
- Nenhum arquivo existente foi alterado.
- Nenhum arquivo central, ocupado ou pertencente às outras frentes foi editado.

## Conectado versus dependente do integrador

Conectado atualmente: duas corridas Harbor, duas zonas de drift, três provas de ski, dez colecionáveis e os prêmios físicos de exploração listados.

Dependente do integrador:

1. conectar `V1OptionalRewardPolicy` em `MountainProgression._finish` para restaurar pagamento repetível sem alterar o snapshot;
2. reconciliar o ID do RPG com alias para saves V2 existentes;
3. decidir se os filtros angulares do drift são adaptação 3D aceita ou regressão de regra;
4. evitar qualquer conexão pelo `RouteActivity.gd` do sandbox: ele é um percurso demonstrativo separado, sem as recompensas V1.

## Defeitos comprovados, hipóteses e verificações pendentes

Comprovados por código: pagamento único do ski no V2 versus repetível no V1; ID divergente do RPG; regra angular extra do drift; catálogo de cinco corridas pertence à cena legada, não ao novo jogo produtivo.

Hipóteses que exigem execução: todos os portões podem ser alcançados sobre a pista 3D; os dez colecionáveis estão apoiados em piso acessível e não dentro de sólidos; entradas de caverna/chalés expõem todos os prêmios; raycasts de aterramento encontram o terreno após streaming; o movimento de ski atravessa gates na escala correta; filtros do drift aceitam manobras normais com os veículos atuais.

Por proibição expressa, não foram executados Godot, testes, benchmarks ou commits. Portanto não há declaração de compilação, funcionamento, colisão, acessibilidade ou desempenho. O módulo novo recebeu apenas revisão estática; a integração futura deve validar uma conclusão comum, repetição sem recorde, novo recorde posterior, falha por limite de carteira, restauração de save e as rotas 3D reais. Como não houve mudança em loop/runtime conectado nesta frente, também não existe comparativo de frame time antes/depois.
