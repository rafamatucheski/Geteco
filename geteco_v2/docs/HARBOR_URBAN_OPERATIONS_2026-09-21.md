# Operações e rotinas urbanas de Harbor — V1 → V2

Data: 22/09/2026. Escopo: Harbor; serra excluída. A referência produtiva foi rastreada desde `ui/MainMenu.gd` até `world/harbor/HarborGame.tscn`, `HarborGame.gd` e os nós que ele efetivamente instancia. Protótipos e eventos de campanha sem chamada nessa árvore não viraram obrigação nova.

## Inventário por sistema

| Sistema | Chamada produtiva V1 | Equivalente V2 conectado | Classe do estado | Situação nesta rodada |
|---|---|---|---|---|
| Três operadores do cais norte | `HarborWaterfront` → `HarborDockCrew` → `HarborDockWorker` | `RoutineCatalog._ship_dock_crew` → `RoutineDirector` → `V1RoutineActor` | rotina ambiental com lote físico de 3 caixas | já existia e foi reconfirmado no `RoutineValidation` |
| 32 trabalhadores do Porto Sul | `HarborSouthPort._build_life` | `RoutineCatalog._south_port_workers` → `RoutineDirector` | rotina ambiental, com streaming e retomada | já existia; a rota 07 foi deslocada de x=3570 para o corredor livre x=3552, sem atravessar o sólido atual |
| Duas lanchas de carga | `HarborSouthPort` → `HarborLaunchRoutine` | `urban_v1/PortOperations` | operação funcional e persistida | implementado: 30 caixas, partida, fase ausente, retorno vazio e novo lote; um carregador por embarcação; afastamento/restauração sem duplicação |
| Portaria, cancela e segurança privada | `HarborPortCheckpoint` + `HarborPortSecurity` | `urban_v1/HarborPortSecurity` → `UrbanOperations` | acesso temporário e alarme criminal | implementado: cancela física, três funcionários de segurança, autorização de R$ 100, abertura para emergência/saída e alarme ao cruzar sem autorização |
| Tráfego e população genéricos no porto | `ProductionWorld` + estradas de `HarborSouthPortLayout` | `HarborPortPolicy` + grafo ambiental separado | população ambiente; grafo completo mantido para missão/despacho | implementado: cidadãos aleatórios e carros ambientais não usam vias privadas nem entram no perímetro; rotas de campanha, despacho e veículos solicitados preservam o grafo viário completo |
| Santa Mare, gruas, contêineres e píeres | `HarborSouthPortLayout`/`HarborSouthPort._advance_cargo` | `OriginalSouthPort` + `urban_v1/PortCargoOperations` | cenário e transferência transitória | implementado: três gruas mantêm o ciclo V1 de 48 s navio↔cais, adiam o pouso se uma pessoa ou veículo ocupar a área; o cargueiro Santa Mare permanece estático, como na origem |
| Três caminhões de carga e duas empilhadeiras | `HarborPortTruckLogistics` + `HarborSouthPort._build_life` | `urban_v1/PortCargoOperations` + `Vehicle` | frota operacional, carga e veículos dirigíveis | implementado: caminhões seguem circuito privado, param para receber um contêiner e continuam carregados; empilhadeiras dirigíveis e seis caixas aparecem junto dos trabalhadores |
| Terreno e túmulos históricos do cemitério | `HarborGame._start_gameplay` → `HarborCemetery` | `OriginalCemetery3D` | cenário | já existente; não alterado |
| Identidade, fila do necrotério, lote e túmulo novo | `CoronerCare` + `HarborCemetery.reserve_burial_plot/restore_buried_body` | `urban_v1/CemeteryOperations` observando o `EmergencyManager` real | progresso persistido | implementado: identidade estável, 12 lotes, fases, nome e restauração; funeral interrompido volta à fila, nunca duplica sepultura |
| Agente funerário, carro e sepultamento | `CoronerCare`/`Mortician` | `CemeteryOperations` + `MorticianModel` + veículo `station_wagon` existente | serviço funcional | implementado: chegada, percurso físico, trabalho, sepultamento e retirada; anexos não são donos do save |
| Cinco participantes do funeral | `HarborWorldEvents.start_funeral` | cinco `UrbanRoutineActor` vinculados ao funeral ativo | rotina ambiental do serviço | implementado com entrada/saída e descarte conjunto; restauração recria exatamente cinco |
| Zelador Anselmo | `CemeteryKeeperHome` → `CemeteryKeeper` | `CemeteryOperations` | personagem e serviço de conversa | implementado no pátio e na casa, usando a entrada/saída já existente |
| Elias e quatro histórias | `CemeteryStoryteller` | `CemeteryOperations` | rotina ambiental/conversa | implementado com quatro paradas e quatro falas produtivas |
| Segredo de Samuel e carta | `CemeteryKeeper` + carta em `HarborCemetery` | conversa de Anselmo + recompensa `memorial_letter` já existente em `ActivityDefinitions` | progresso persistido em duas frentes | conversa e flag `secret_known` implementadas; coleta/recompensa atômica da carta permanece no proprietário existente |
| Northgate Auto Service | `HarborAutoService` | `Services._tick_auto` | serviço funcional persistido | equivalência já conectada: baia física, R$100, 4,5 s, reparo e limpeza de procurado; não foi duplicada |
| Residências | `ResidenceManager` | `Activities` + `ResidenceServices` | serviço/progresso persistido | equivalência já conectada; não foi duplicada |
| Union/roupas | `HarborClothingShops` | catálogo, loja e `FullSession.show_services` | serviço/progresso persistido | equivalência já conectada; não foi duplicada |
| Banco/posto e assaltos | `HarborRobberies` | `Robberies`/`BankLockpick` | serviço/evento persistido | equivalência específica já conectada; nenhum atendimento genérico foi inventado |
| Ônibus urbano e transporte | `UrbanTransit`/`UrbanPlayerRide` | `PassengerTransport` + `UrbanTransitPresentation` | serviço funcional | já conectado pela sessão; não foi duplicado nesta rodada |
| Ferro-velho, colecionáveis, drift e corridas | montagem de `HarborGame` | `Activities`, `GarageRewards` e módulos próprios | serviço/progresso persistido | proprietários V2 existentes preservados |
| Mesas externas de três restaurantes | `HarborRestaurantLife` → `RestaurantTerraceView` | nenhum modelo/âncora produtivo encontrado no V2 | rotina ambiental | pendente de encaixe visual do Chat 1; não foram criados clientes sem mesas nem uma interface substituta |
| Assalto de rua aleatório | `HarborWorldEvents` → `HarborStreetRobbery` | nenhum equivalente específico confirmado | evento de combate | pendente da frente de combate/Actor; `Robberies` de banco/posto não foi declarado equivalente indevidamente |
| Incêndio urbano ambiental | `HarborWorldEvents.start_incident` | `EmergencyManager.ignite`/bombeiro | serviço funcional | mecanismo equivalente já existe; o disparador ambiental aleatório não foi duplicado |

## Conexão implementada

`FullSession` cria um único `UrbanOperations`, encaminha consulta/execução da conversa, atualiza o contexto em entrada, saída e restauração, e publica `world_state.urban_operations` antes do retorno antecipado de `--no-save`. `UrbanOperations` é o proprietário único de `PortOperations` e `CemeteryOperations`. Nenhum trecho de `handle_arsenal_input`, cobrança, recompensa, combate, HUD, menus ou transição foi substituído.

`GameState` agora valida esse payload completo antes de publicar qualquer parte do estado. A chave continua opcional para compatibilidade com saves V2 anteriores; quando presente, porto e cemitério são obrigatórios e validados juntos. `FullSession.save_game` também bloqueia um snapshot vivo incompleto antes de atribuí-lo a `world_state`.

O snapshot urbano tem versão 1:

- `port.boats[2]`: id, fase, relógio, carga, posição e estado do carregador;
- `cemetery`: serial de identidade, segredo, parada de Elias e até 64 casos `{identity,name,phase,plot}`;
- funerais em andamento são normalizados para `morgue`; barcos conservam fase/carga; atores, carro funerário e convidados são apenas anexos reconstruídos.

## Cenários executados

| Cenário | Resultado |
|---|---|
| Ciclo completo das duas lanchas; transferência da 30ª caixa; partida; ausência; retorno vazio; novo lote | passou |
| Afastar do porto no meio da carga, voltar e restaurar snapshot com carregadores ativos | passou; uma instância por id e total de carga conservado |
| Entrada real na casa do zelador, conversa do segredo, saída e retorno ao pátio | passou; um Anselmo e um Elias no contexto correto |
| Óbito fatal pelo `EmergencyManager`, coleta, necrotério, agente funerário, cinco participantes, lote e sepultura | passou |
| Restaurar durante o segundo funeral; afastar do cemitério; voltar | passou; caso volta à fila, depois retoma uma vez; sepultura concluída não duplica |
| Snapshot urbano em sessão `--no-save` | passou; nenhum save pessoal foi lido ou escrito |
| Política do Porto Sul: área privada, vias ambientais e rotas aleatórias | `tests/test_harbor_port_policy.gd` | passou |
| Portaria física, propina, travessia autorizada e saída; pedestre/carro ambiental removidos, transporte de missão preservado | `tests/test_urban_operations.gd` | passou |
| Referência de pedestre já liberada antes da reação | `tests/test_civilian_reactions.gd` | passou |
| Persistência sintética central de porto/cemitério | 14/14; save V2 anterior compatível, round-trip completo e payload parcial rejeitado sem mutação |
| `RoutineValidation` completo | passou, 2.035 verificações |
| Entrada de arsenal real | passou |
| Transferência física da garagem | passou, 11 verificações |
| `test_full_session` | falha anterior fora desta frente: a fixture marca `primeiro_giro` como recompensa recebida sem a transação econômica exigida por `GameState`; arsenal, garagem, lugares e demais passos anteriores passam |
| `test_full_save` | não iniciou por erro de inferência já presente na própria fixture, linha 71 |

## Performance renderizada

O benchmark usa `Main.tscn`, renderização OpenGL real, população solicitada 24, 5 s de aquecimento e 30 s de intervalos; headless não foi usado como prova de FPS. As capturas e JSONs estão em `evidence/urban-operations-*.{json,png}`.

| Execução | População efetiva | FPS médio | p95 | p99 | >33,3 ms | Leitura |
|---|---:|---:|---:|---:|---:|---|
| antes, porto | 24 | 60,000 | 17,402 ms | 19,055 ms | 0 | referência anterior à implementação |
| antes, cemitério | 24 | 60,002 | 17,154 ms | 17,511 ms | 0 | referência anterior à implementação |
| controle atual sem `UrbanOperations`, cemitério | 24 | 59,762 | 30,096 ms | 38,049 ms | 57 | carga externa já maior que na referência |
| ativo atual, cemitério | 24 | 59,533 | 36,274 ms | 39,778 ms | 161 | regressão de p95 maior que 5% contra o controle atual |
| ativo final, porto | 3 | 60,002 | 17,273 ms | 17,437 ms | 0 | não comparável: o produtor materializou só 3 dos 24 residentes solicitados |

Havia editor/jogo e testes Godot de outras frentes ativos durante a série. Uma tentativa adicional no cemitério também sofreu pico externo de 124 ms e CPU p95 de 50 ms; a redução experimental de sombras baixou draw calls, mas não corrigiu o p95 e foi revertida para preservar a apresentação. Portanto, **performance não está aprovada nesta rodada**: não houve queda média para 12–15 FPS, mas a regressão de cauda no cemitério é reproduzível nas medições concorrentes e precisa de nova comparação isolada com população 24 antes do fechamento.

**Atualização 22/09/2026:** o checkpoint 3D, a política de população/tráfego e as transferências visuais das três gruas foram alterados depois dessas medições. Quatro processos Godot de outras sessões estavam abertos durante esta implementação; por isso não foi feita nova comparação renderizada. Os resultados acima não validam a performance dessas mudanças, que permanece sem aprovação.

## Encaixes entregues ao Chat 1

1. **Validação central do save — concluída.** `GameState` exige `Dictionary` e `UrbanOperations.validate_snapshot(...)` quando a chave existe, antes do commit; ausência permanece aceita para saves V2 anteriores.
2. **Restaurantes.** Publicar no mundo nativo as seis âncoras produtivas de `HarborRestaurantLife.VENUES` — `(555,1132)`, `(685,1132)`, `(5735,1644)`, `(5845,1644)`, `(6145,-1238)`, `(6255,-1238)`, convertidas por 16 — com o modelo original de mesa/cadeiras/comida/parasol. O módulo de rotina pode então aplicar horários e chuva sem editar `NativeRegion` ou modelos nesta frente.
3. **Evento de assalto de rua.** Se a frente de combate portar `HarborStreetRobbery`, expor início/fim e identidade de participantes sem transferir posse de dano, recompensa ou wanted para `UrbanOperations`.
4. **Incidentes fatais.** O encaixe atual lê o ledger real do `EmergencyManager`. Um sinal futuro de “coleta fatal concluída” pode substituir a observação, desde que entregue uma identidade estável e não crie pagamento, corpo ou funeral duplicado.

Não é necessário alterar `ProductionWorld`, `NativeRegion`, `PlaceCatalog` ou modelos para ativar porto e cemitério: a ligação fica integralmente em `FullSession` e nos módulos exclusivos desta entrega.
