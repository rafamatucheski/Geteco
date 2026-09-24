# Cobertura do mapa V1 → V2

Inventário produtivo revisto em 21/09/2026, durante trabalho concorrente. Este documento não certifica a cidade completa: contratos headless e pares renderizados dirigidos foram executados para as áreas prioritárias, mas o benchmark antes/depois continua bloqueado por outra instância Godot ativa. A presença dos modelos e IDs não é usada como substituto de equivalência visual.

## Referência de produção

- `world/harbor/HarborGame.gd` estende a base HarborPreview e acrescenta conteúdo em `_start_gameplay`, incluindo cemitério, eventos, residências, trânsito e mundo contínuo. Comparar só `HarborPreview.tscn` perde esses elementos.
- `world/harbor/ContinuousWorld.gd` carrega `MountainPass.tscn` com deslocamento `(4300,-4960)` e transfere tráfego pela ponte. A serra não é somente uma cena legada desconectada.
- `world/mountain_pass/MountainPass.gd` monta ponte, túnel, paisagem, povoado, ski, trânsito e interiores. Arquivos em `prototypes` ou cópias de benchmarks não são obrigações independentes: precisam de chamada produtiva demonstrada.
- No V2, `NativeRegion.gd` converte pixels em metros (`1/16`) e aplica o mesmo deslocamento da serra. `PlaceCatalog` identifica lugares e acessos; uma entrada de catálogo não comprova fachada, acesso físico ou serviço funcionando.

## Inventário por conjunto

| Conjunto | Fonte produtiva V1 | Implementação/conexão V2 por leitura | Diferenças e pendências |
|---|---|---|---|
| Cidade e vias | HarborPreview + sua cena, HarborGame | NativeRegion lê `OriginalWorldData.json`; `_add_road`, `_building` e UrbanBuildingFactory montam chunks | Extrair geometria não comprova todos os detalhes. Cruzamentos, colisões, portas, escala e percurso precisam de comparação renderizada |
| Porto Sul | Conteúdo produtivo HarborGame/porto | OriginalSouthPort está sendo integrado por outra frente; NativeRegion já contém chamadas específicas | Trabalho concorrente: cobertura final a consolidar; não certificado neste inventário |
| Navio Northstar | HarborPreview/porto | `_build_ship`: contorno, passarela, cargas, cabine e guarda-corpos | Representação nativa simplificada; ocupação, acesso e continuidade da passarela não executados |
| Rodoviária, delegacia, Maciota e ruas próximas | Cenas e acessos produtivos Harbor | HarborRouteDetailFactory registra quatro zonas em NativeRegion | Fábrica conectada não prova igualdade do bairro inteiro nem ausência de duplicação |
| Residências e casa do zelador | ResidenceManager, HarborCemetery → CemeteryKeeperHome | PlaceCatalog, UrbanBuildingFactory e registros `original_facade` | Casa do zelador já existia; o terreno e conjunto funerário exterior estavam ausentes |
| Cemitério exterior | HarborGame `_start_gameplay`: centro `(-650,1740)`; HarborCemetery `_build_ground/_build_wall/_build_gardens` | Novo `OriginalCemetery3D.gd`, contrato de montagem abaixo | Preserva lote, portão, 31 túmulos, caminhos, bancos, árvores e postes. Sem simulação funerária, eventos, atmosfera ou iluminação ativa migrada nesta mudança |
| Serra e estrada principal | MountainPassRoad, MountainSceneryBuilder | NativeRegion recria curva e cinco ramais autorados; terreno/vegetação em outra frente desta rodada | Elevação nova deve preservar condução e acessos. Não considerar terreno genérico anterior equivalente ao relevo completo |
| Chalés e abrigo | MountainInteriorManager/SceneryBuilder | `_mountain_place` instancia LumberjackCabin3D para todos os ids mountain_cabin e lumberjack_shelter | Mesma fachada compartilhada é aproximação: interiores identificados no catálogo não comprovam equivalência dos exteriores |
| Bunker, Summit, lojas e caverna | MountainPass e seus construtores | Ramos explícitos de `_mountain_place` e `_original_facade` | Colisão e acesso requerem execução; fallback de `_mountain_place` cria somente Marker3D. Atualmente os ids mountain do catálogo têm ramos, mas futuros ids cairiam em marcador invisível |
| Serraria e vila | MountainSceneryBuilder e MountainSettlement | MountainDetailFactory, SawmillYard3D e MountainVillage3D montados em NativeRegion | Reaproveitamento presente, sem inventário exaustivo prop a prop ou comparação visual nesta rodada |
| Lagos e avião | Paisagem/expedição produtiva da serra | NativeLake e CargoPlaneNative registrados em NativeRegion | Existência de lago não comprova margem, profundidade, travessia, flora e lógica original completas |
| Ligação cidade ↔ serra | `HarborMountainConnector`, `ContinuousWorld`, `HarborBridge`, `MountainPassRoad` e `MountainTunnel` | `WorldConnection3D` monta a aproximação elevada, ponte, cabeceiras e túnel; `ProductionWorld` mantém Harbor e Mountain residentes na travessia e une o grafo viário | Conexão efetiva por código, sem teleporte: vias encontram-se em `(456,25 m, -285 m)`. Caminhada, condução, colisão, visual e custo ainda não foram executados |

## Inventário urbano nominal desta rodada

Legenda obrigatória: **fiel** = identidade, posição e geometria própria conferidas por implementação e evidência renderizada disponível; **aproximado** = existe e está conectado, mas ainda usa adaptação ou não tem comparação equivalente; **ausente** = conjunto autorado V1 ainda não foi portado; **desconectado** = modelo ou destino existe sem encaixe produtivo utilizável. “Há um prédio nessa posição” nunca eleva o estado para fiel.

### Cadeia realmente produtiva

`HarborGame.gd` estende `HarborPreview.gd` e sua cena. A cena monta `HarborDistrict`, `HarborRoadLayout`/`HarborRoadNetwork`, `HarborWaterfront`, `HarborEastDistrict`, `HarborNorthDistrict`, `HarborMountainConnector`, `CobraNeighborhood`, `HarborSouthPort`, rodoviária, hospital e interiores. `_start_gameplay()` acrescenta cemitério, residências, garagem do chefe do porto, esgoto, ferro-velho, mundo contínuo, serviços e eventos. No V2, a cadeia produtiva é `ProductionWorld` → `NativeRegion` → `OriginalWorldData`/`OriginalSouthPort`/`OriginalCemetery3D`/`HarborRouteDetailFactory`/`UrbanBuildingFactory`, com destinos e retornos em `PlaceCatalog`.

Construtores V1 rastreados como parte da produção urbana: na cena, `HarborDistrict`, `HarborRoadLayout`, `HarborRoadNetwork`, `HarborHospital`, `HarborWaterfront`, `HarborLife`, `HarborRailLine`, `HarborSafety`, `HarborEastDistrict`, `HarborBridge`, `HarborAlleys`, `HarborNorthDistrict`, `HarborGatewayWorks`, `HarborInteriorManager`, `HarborMountainConnector`, `CobraNeighborhood` e `HarborSouthPort`; no início do jogo, `PortBossGarage`, `ResidenceManager`, `ContinuousWorld`, `HarborAutoService`, `HarborCemetery`, `HarborWorldEvents`, `HarborRestaurantLife`, `HarborRobberies`, `HarborClothingShops`, `UrbanTransit`, o pátio/serviço de salvamento e `HarborManholeSewer`. Sistemas de campanha, HUD e áudio foram rastreados apenas para confirmar a montagem e permaneceram fora da edição.

### Bairros e áreas

| Área produtiva | Estado | Evidência e pendência |
|---|---|---|
| Westgate / Foundry | aproximado | 20 lotes e vias estão nas posições V1; North Pier, Union e posto têm fachadas próprias. Miolo, quintais e paisagismo ainda não têm comparação integral |
| Memorial / margem oeste | aproximado | três vias, cemitério e ferro-velho existem; faixa arborizada, iluminação e atividades permanecem parciais |
| Northbank / East District | aproximado | 16 lotes, pátio e waterfront estão geograficamente presentes; promenade, jardins e monumento continuam incompletos |
| North Gateway / Canal | aproximado | 18 lotes e quatro vias principais presentes; praças de entrada e mobiliário são parciais |
| Cobra / Ashbend | aproximado | oito casas e circuito viário presentes; o par dirigido agora mostra terreno seco, jardim central, árvores, rochas, bancos, postes, barris, barricadas, cercas e variações de cobertura/planta. Quintais e densidade fina ainda divergem do V1 |
| Waterfront / Northstar | aproximado | casco com laterais, convés escuro, passarela, 18 cargas nervuradas, cabine em dois níveis, stack, guarda-corpos e três gruas presentes; operação e detalhe do convés continuam abaixo do V1 |
| Porto Sul / Santa Mare | aproximado | superfícies em concreto, cinco edifícios, navio, três gruas, cargas, dois píeres, acesso e travessias foram conectados; operação, trabalhadores e acabamento fino ainda incompletos |
| Ligação Harbor–serra | aproximado | continuidade preservada; a ponta de concreto na convergência foi reproduzida e corrigida com o polígono de 13 amostras do V1. A ilha clara anterior ao afunilamento é estrutural e permanece; nenhuma reforma da montanha nesta rodada |

### Ruas, acessos viários e cruzamentos

Todos os 39 ids produtivos foram encontrados em `HarborRoadLayout`, `HarborNorthAccess`, `HarborSouthPortLayout` e no extrato V2. Todos estão **aproximados**: centro, largura e traçado foram portados, mas o construtor V2 ainda segmenta asfalto/calçadas e não há travessia visual e física equivalente em cada interseção.

| Via V1/V2 | Estado | Observação pendente |
|---|---|---|
| `memorial_north` | aproximado | cruzamento oeste e acesso ao ferro-velho |
| `memorial_west` | aproximado | margem do cemitério |
| `memorial_south` | aproximado | fechamento sul do quarteirão |
| `foundry_avenue` | aproximado | eixo Foundry |
| `market_street` | aproximado | mercado/terminal |
| `dock_street` | aproximado | cais norte |
| `westgate_drive` | aproximado | Maciota/serviços |
| `union_avenue` | aproximado | praça e hospital |
| `warehouse_way` | aproximado | depósitos |
| `quay_boulevard` | aproximado | margem d’água |
| `island_esplanade` | aproximado | Northbank waterfront |
| `east_union_avenue` | aproximado | ligação leste |
| `eastgate_drive` | aproximado | eixo Eastgate |
| `island_market_street` | aproximado | comércio Northbank |
| `island_dock_street` | aproximado | orla Northbank |
| `exchange_lane` | aproximado | torres Exchange/Civic |
| `courtyard_lane` | aproximado | acesso ao pátio Northbank |
| `northbank_neighborhood_street` | aproximado | residências Northbank |
| `northbank_civic_avenue` | aproximado | museu/aquário |
| `northbank_gateway_avenue` | aproximado | saída norte |
| `map2_highway_inbound` | aproximado | pista de entrada |
| `map2_highway_outbound` | aproximado | pista de saída |
| `map2_temporary_return` | aproximado | retorno urbano existente, não nova elevação |
| `westgate_service_lane` | aproximado | serviço Maciota |
| `medical_garden_lane` | aproximado | pátio médico |
| `south_port_north` | aproximado | borda norte do Porto Sul |
| `south_port_east` | aproximado | borda leste do Porto Sul |
| `south_port_south` | aproximado | borda sul do Porto Sul |
| `south_port_west` | aproximado | borda oeste do Porto Sul |
| `south_port_dispatch` | aproximado | despacho/carga |
| `south_port_access` | aproximado | ligação urbana ao porto |
| `mountain_bridge_outbound` | aproximado | somente a ligação existente; montanha fora do escopo |
| `mountain_bridge_inbound` | aproximado | somente a ligação existente; montanha fora do escopo |
| `cobra_approach` | aproximado | entrada de Ashbend |
| `cobra_court_northwest` | aproximado | circuito da praça |
| `cobra_court_northeast` | aproximado | circuito da praça |
| `cobra_court_southeast` | aproximado | circuito da praça |
| `cobra_court_southwest` | aproximado | circuito da praça |
| `salvage_access` | aproximado | acesso rural ao pátio do Neco |

Interseções, calçadas e superfícies: as zonas autoradas da rodoviária, ruas de ligação, delegacia e Maciota estão conectadas pelo `HarborRouteDetailFactory`, mas o restante continua aproximado. A validação física global de cruzamentos, sobreposição de calçadas e emendas de chunk permanece pendente; nenhuma dessas vias é declarada fiel por captura distante.

### Praças, pátios, margens e passarelas

| Elemento V1 | Estado | V2 / pendência explícita |
|---|---|---|
| Union Plaza e fonte `(1675,1810)` | aproximado | piso, juntas, bacia sólida, água, aro e pedestal foram conectados nas coordenadas/radii V1; falta comparação renderizada |
| pátio/jardim Foundry | aproximado | pavimento, jardim, caminho, bancos, birdbath, passagem, pátio de serviço, objetos e terraço foram reconstruídos; botânica é simplificada |
| praça frontal do mercado/rodoviária | aproximado | zona da rodoviária conectada; encontro completo com Market Hall não comparado |
| pátio médico e acessos de ambulância/coroner | aproximado | área de rota existe; marcação e operação produtiva V1 não foram comprovadas |
| Northbank Courtyard | aproximado | acesso viário existe; mobiliário e circulação ainda sem comparação equivalente |
| promenade Northbank, quatro jardins e quatro bancos | aproximado | dividida em dois registros de streaming; piso, quatro canteiros, arbustos e quatro bancos presentes; vegetação é simplificada |
| monumento-bússola do museu | aproximado | discos e quatro pontos cardeais conectados no centro V1 `(6080,1000)` |
| praça/circuito Cobra | aproximado | quatro vias preservam o circuito; cenário, bloqueios e objetos da prova continuam parciais |
| passarela do Northstar | aproximado | ligação básica presente, continuidade jogável não percorrida nesta rodada |
| passarela e gangway do Santa Mare | aproximado | recorte e guarda-corpos presentes; percurso completo e colisão em jogo pendentes |
| margens, píeres e paredões do Porto Sul | aproximado | superfícies autoradas conectadas, material/acabamento simplificados |

### Prédios, residências e estabelecimentos — 61 registros produtivos

As posições, pegadas, cores-fonte e nomes vêm do V1. `ExchangeTower` e `CivicTower` voltaram a usar as alturas especiais V1 de `128/16 m` e `95/16 m`. Os estados abaixo avaliam identidade do modelo, não mera presença.

| Id produtivo (nome próprio) | Estado | Modelo V2 / diferença |
|---|---|---|
| `NorthFrontage0` (North Pier) | fiel | fachada própria com colunas e ATMs; evidência conectada existente |
| `NorthFrontage1` (Foundry Flats) | aproximado | brownstone nativo |
| `NorthFrontage2` (Ammu-Nation) | aproximado | fachada própria, acesso corrigido atomicamente e escala ajustada ao lote V1 de 230×180 px; o par equivalente confirma o ganho, mas quarteirão, mobiliário e fachada lateral ainda diferem |
| `NorthFrontage3` (Union) | fiel | fachada própria e manequins vestidos; evidência conectada existente |
| `NorthFrontage4` (posto sem nome próprio) | fiel | fachada/bombas nos offsets V1; evidência conectada existente |
| `NorthFrontage5` (Customs House) | aproximado | comercial nativo |
| `FoundryTerraceWest` | aproximado | terraço residencial nativo |
| `FoundryTerraceEast` | aproximado | terraço residencial nativo |
| `FoundryLofts` (Union Lofts & Works) | aproximado | bloco L, pátio fisicamente aberto |
| `CornerDiner` (Anchor Diner) | aproximado | loja de esquina nativa |
| `Laundry` | aproximado | lavanderia nativa |
| `UnionWorkshop` (Harbor Bindery) | aproximado | oficina artesanal nativa |
| `MarketHall` (Breakwater Market) | aproximado | loja-armazém nativa |
| `ColdStorage` | aproximado | armazém nativo |
| `Garage` (Maciota) | fiel | lugar autorado montado por `ProductionWorld`; primeiro marco visual disponível |
| `Police` (Harbor Patrol) | aproximado | modelo de serviço nativo; zona externa autorada conectada |
| `Clinic` (Bay Medical) | aproximado | modelo 3D próprio reutilizado; integração exterior ainda sem par desta rodada |
| `Apartments` (Union Lofts) | aproximado | comercial nativo |
| `FreightOffice` (Port Authority) | aproximado | comercial nativo |
| `FreightDepot` | aproximado | armazém nativo |
| `ExchangeTower` (Northbank Exchange) | aproximado | comercial nativo, altura V1 restaurada a 8 m |
| `CivicTower` (Horizon) | aproximado | comercial nativo, altura V1 restaurada a 5,9375 m |
| `MaritimeMuseum` | aproximado | comercial nativo; monumento externo reconstruído no pátio |
| `NorthbankHomes0` | aproximado | terraço residencial nativo |
| `NorthbankHomes1` | aproximado | brownstone nativo |
| `NorthbankHomes2` | aproximado | oficina artesanal nativa |
| `IslandGrocer` (Northbank Grocery) | aproximado | loja de esquina nativa |
| `IslandCinema` (The Orion) | aproximado | shopfront nativo |
| `Aquarium` (Bay Aquarium) | aproximado | comercial nativo |
| `PromenadeCafe` (Tideline) | aproximado | loja de esquina nativa |
| `NorthbankFront0` (Bridge House) | aproximado | brownstone nativo |
| `NorthbankFront1` (Founders Club) | aproximado | brownstone nativo |
| `NorthbankFront2` (Design Works) | aproximado | comercial nativo |
| `NorthbankFront3` (Eastgate Hotel) | aproximado | comercial nativo |
| `BridgeCourtWest` | aproximado | brownstone nativo |
| `BridgeCourtEast` | aproximado | comercial nativo |
| `BridgeQuayHouse` | aproximado | brownstone nativo |
| `GatewayFlats` | aproximado | brownstone nativo |
| `TransitHouse` | aproximado | comercial nativo |
| `MotorWorkshop` | aproximado | oficina nativa; vão aceita o casco integral do veículo |
| `RoadsideSupplies` | aproximado | shopfront nativo |
| `ServiceLodge` (Gateway Lodge) | aproximado | comercial nativo |
| `ParcelOffice` (North Parcel) | aproximado | armazém nativo |
| `NorthFireStation` | aproximado | quartel nativo |
| `ServiceCafe` (Early Shift) | aproximado | loja de esquina nativa |
| `CanalHomesWest` / `canal_north` | aproximado | fachada de residência própria reutilizada e conectada ao catálogo |
| `CanalHomesEast` | aproximado | brownstone nativo |
| `NorthGrocer` (Canal Grocery) | aproximado | loja de esquina nativa |
| `CycleWorkshop` (Spoke) | aproximado | shopfront nativo |
| `GardenFlats` | aproximado | brownstone nativo |
| `UnionApartments` (North Union) | aproximado | comercial nativo |
| `CommunityHall` (Northgate Hall) | aproximado | comercial nativo |
| `CornerPharmacy` | aproximado | shopfront nativo |
| `PorchHouse` | aproximado | casa Cobra nativa |
| `Duplex` | aproximado | casa Cobra nativa |
| `ShingleHouse` | aproximado | casa Cobra nativa |
| `CobraWorkshop` | aproximado | casa/oficina Cobra nativa |
| `CourtyardHouse` | aproximado | casa Cobra nativa |
| `BrickDuplex` | aproximado | casa Cobra nativa |
| `TinRoofHouse` | aproximado | casa Cobra nativa |
| `CornerBungalow` | aproximado | casa Cobra nativa |

### Lugares catalogados, interiores e conexões

| Lugar/acesso | Estado | Contrato atual |
|---|---|---|
| `harbor_bank` | fiel | fachada e entrada no `NorthFrontage0`; interior preservado |
| `harbor_ammunation` | aproximado | fachada, catálogo, entrada, retorno e referência mudaram juntos para `NorthFrontage2` `(1550,140)`; 14 verificações passaram |
| `harbor_clothing` | fiel | `NorthFrontage3`, vitrine própria e interior preservado |
| `harbor_fuel` | fiel | `NorthFrontage4`, bombas próprias e acesso preservado |
| `harbor_police` | aproximado | prédio e zona exterior conectados; percurso real pendente |
| `harbor_hospital` | aproximado | fachada própria e destino catalogado; percurso real pendente |
| `harbor_fire_station` | aproximado | fachada nativa e destino catalogado |
| `westgate_garden` | aproximado | residência própria catalogada |
| `quayside_house` | aproximado | residência própria catalogada |
| `canal_north` | aproximado | residência própria em `CanalHomesWest` |
| `cemetery_keeper` | aproximado | casa própria, cemitério e catálogo conectados; rotina/atmosfera pendentes |
| `port_boss_garage` | aproximado | antes sem exterior; agora portal nas dimensões V1, aproximação a oeste, retorno no `EXTERIOR` exato e vão validado |
| `harbor_sewer` | aproximado | antes sem exterior; agora bueiro transitável no ponto V1 `(1182,2114)` e destino preservado |
| garagem do Maciota | fiel | exterior/interior produtivos; regras de invulnerabilidade e área sem armas não foram alteradas |

Não houve reforma de interiores. As duas novas peças são exteriores de acesso; seus destinos continuam os modelos existentes. A travessia visual do `harbor_sewer` foi validada no jogo 3D com abertura da tampa, descida, saída e retorno dos controles. A travessia visual de `port_boss_garage` e a restauração de save dos dois acessos continuam pendentes no checklist, sem marcar interior concluído.

### Portos, navios, ferro-velho e cemitério

| Conjunto reconhecível | Estado | Cobertura atual |
|---|---|---|
| Northstar | aproximado | casco com laterais, convés, cabine/wheelhouse/stack, 11 áreas de deck, 18 cargas nervuradas, passarela, guarda-corpos e três gruas; o par confirma que ocupação e equipamento fino ainda diferem |
| Santa Mare / Porto Sul | aproximado | piso de concreto, casco, gangway, carga, cabine, três gruas, cinco edifícios, suprimentos, cargas soltas, oito postes e duas travessias conectados |
| dois píeres do Porto Sul | aproximado | superfícies e rails presentes, percurso não validado em jogo |
| 18 conjuntos de contêineres | aproximado | posições/pegadas V1 preservadas; visual reutiliza modelo 3D original |
| pátio do Neco / ferro-velho | aproximado | acesso, cerca, prensa, sucata, grua, contêineres, prado periférico, 12 árvores, rochas e paredões reconhecíveis presentes; serviço produtivo e densidade do terreno V1 não foram portados por esta frente |
| cemitério | aproximado | lote, portão, 31 túmulos, caminhos, muros, bancos, árvores, postes, casa e faixa arborizada exterior presentes; funerais, atmosfera, luz e persistência não equivalentes |
| seis mesas de restaurante | aproximado | âncoras V1 exatas de Anchor, Tideline e Early Shift agora montam mesa, duas cadeiras, louça, comida, vaso e parasol com colisão própria; clientes, horários e reação à chuva pertencem à rotina externa ainda pendente |

### Resultado objetivo do inventário

Não há agora acesso urbano catalogado conhecido em estado **desconectado**, nem conjunto nominal deste inventário ainda classificado como **ausente**: Ammu-Nation foi alinhada atomicamente, garagem do chefe/esgoto ganharam exteriores produtivos e os quatro conjuntos públicos faltantes foram conectados. A maioria dos conjuntos permanece apenas **aproximada**, sem comparação equivalente ou percurso integral. Portanto, a cidade inteira ainda não está concluída.

## Fileira norte acessível — banco, Union e Posto

Rodada dirigida em 21/09/2026, limitada a `world/urban_detail`. O escopo fechado desta área contém os três acessos cuja geografia do catálogo V2 já coincide com a produção V1:

| Lugar | Fonte produtiva V1 | Diferença encontrada | Correção conectada |
|---|---|---|---|
| Banco North Pier (`NorthFrontage0` / `harbor_bank`) | `HarborDistrict` em `(650,140)`, `BankFacade.gd` e duas ATMs | V2 usava `UrbanShopfrontBuilding`, igual a lojas comuns | `UrbanLandmarkFrontage3D` porta pedra, quatro colunas, duas ATMs, glazing, pedimento, claraboia e apenas o nome `North Pier` |
| Union (`NorthFrontage3` / `harbor_clothing`) | `HarborClothingShops` + `UnionClothingFacade`, centro `(1890,140)` | V2 usava brownstone genérico; identidade da vitrine não aparecia | Fachada `Union`, porta recuada e duas vitrines com manequins completos vestidos em escala humana |
| Posto (`NorthFrontage4` / `harbor_fuel`) | `HarborRobberies`, centro `(2460,140)`, bombas relativas em `(-70,140)` e `(70,140)` | V2 usava escritório genérico e não montava as bombas | Loja envidraçada e duas bombas nos offsets V1 exatos, convertidos por `1/16`; sem placa de categoria porque o V1 não fornece nome próprio |

Conexão efetiva: `NativeRegion._building()` continua entregando cada registro a `UrbanBuildingFactory.populate_chunk()`. A fábrica seleciona o novo modelo pelos três ids, sem novo registro, sem alteração de `NativeRegion`, terreno ou acesso. Execução renderizada da região confirmou nós especializados nos chunks, metadados `place_id` e `entry_position` do catálogo:

- `NorthFrontage0`: posição `(40.625,0,8.75)`, entrada `(40.625,0,16.875)`, `harbor_bank`;
- `NorthFrontage3`: posição `(118.125,0,8.75)`, entrada `(118.125,0,16.875)`, `harbor_clothing`;
- `NorthFrontage4`: posição `(153.75,0,8.75)`, entrada `(153.75,0,16.875)`, `harbor_fuel`.

Física e oclusão foram verificadas separadamente. Cada prédio possui exatamente quatro sólidos layer 1 — corpo traseiro, flancos e lintel — e o percurso de 1,70 m desde o marcador ficou livre; um percurso equivalente contra o flanco colidiu. ATMs, colunas, manequins, vitrines e bombas não possuem sólidos próprios. A oclusão renderizada usou cápsula magenta com controle positivo ao lado e posição atrás do casco: North Pier `787 → 0` pixels, Union `787 → 0`, Posto `481 → 0`.

Evidências renderizadas (1280×720, Godot 4.7.2, OpenGL Compatibility):

- isoladas: `north-pier-front.png`, `union-front.png`, `fuel-frontage-front.png`;
- oclusão: pares `*-occlusion-control.png` / `*-occluded.png`, consolidados em `urban-landmarks-visual.json`;
- conectadas: `north-frontage-west-connected.png`, `north-frontage-fuel-connected.png` e `north-frontage-connected.json`;
- diretório: `C:/Users/rafae/.codex/visualizations/2026/09/21/01a0c59c-dd86-7e80-affd-f22d2af9af60/`.

Validação funcional dirigida passou depois de corrigir o equipamento de teste para parar no vão real das alcovas e contar somente os 61 registros do JSON: `tests/urban_detail/test_urban_building_factory.gd` montou 3 modelos próprios, 57 reconstruções e o lugar Maciota, verificou colisão layer 1, ausência de SubViewport, acessos especiais e as alturas das duas torres, com zero falhas.

Ammu-Nation foi corrigida atomicamente nesta integração. `PlaceCatalog`, `NativeRegion`, `UrbanBuildingFactory` e `UrbanSignage` agora concordam com o V1 em `NorthFrontage2` `(1550,140)`; `NorthFrontage1` voltou a ser Foundry Flats. `tests/urban_detail/test_harbor_ammunation_atomic.gd` passou 14 verificações de fachada, catálogo, entrada, retorno, publicação no chunk e ausência da Ammu no lote antigo. A fidelidade visual ainda depende de um par renderizado equivalente.

Não houve benchmark: já existia outra instância Godot ativa e o contrato proíbe medições concorrentes. As capturas e a ausência de callbacks, luzes ou SubViewports novos não aprovam frame time. O restante da cidade e do mapa continua pendente conforme o inventário; esta seção não declara o mapa concluído.

## Ligação física Harbor → serra

### Fonte V1 e percurso implementado

- `HarborMountainConnector.road_definitions()` fornece as duas pistas desde a rodovia norte (`5880/6120,-4200`) até `OUTLET/INLET = (7300,-4529/-4591)`. Sua estrutura começa em `x=6480` e afunila na cabeceira `(7300,-4560)`.
- `ContinuousWorld` mantém `MountainPass` no mesmo mundo com offset `(4300,-4960)`, seleciona a serra em `x >= 7300 && y < -2000` e transfere tráfego entre as faixas sem trocar a cena do jogador.
- `MountainPassRoad` começa localmente em `(3000,400)`, portanto no mesmo ponto global `(7300,-4560)`. `HarborBridge` ocupa o trecho local `x=3200..4650`; `MountainTunnel` começa em `(4950,400)`, tem `850×150` pixels e termina no vale em `(5800,400)`.
- No V2, o percurso contínuo ficou: rodovia norte de Harbor → aproximação elevada dividida → cabeceira global `(456,25,-285)` → ponte única até `x=559,375` → acesso de encosta → túnel de `x=578,125` a `631,25` → estrada sinuosa já portada pela `NativeRegion`. Todas as medidas V2 usam a conversão existente de 16 pixels por metro.

### Implementação V2 e conexão efetiva

- O asfalto e sua colisão continuam nos registros autorados de `NativeRegion`: as duas pistas `mountain_bridge_outbound/inbound` terminam na cabeceira e `mountain_pass` começa exatamente ali. `WorldConnection3D` acrescenta somente deck, margens sólidas, guarda-corpos, pilares, cabeceiras, paredes/portais e travessas do túnel; não cria uma segunda estrada concorrente.
- As células `(6,-5)`, `(7,-5)` e `(8,-5)` do terreno genérico da serra não são construídas. Elas coincidem com o vão original; Harbor conserva a água abaixo e a estrutura compartilhada sustenta a pista. Isso evita terreno e colisão duplicados atravessando a ponte quando as duas regiões estão presentes.
- `ProductionWorld` agora separa `state.region_id`/`region` (contexto lógico) de `regions` (presença física). A região apontada pela posição sempre fica residente. A até 240 m da cabeceira, Harbor e Mountain são mantidas juntas e recebem o mesmo foco de chunks; a estrutura só pode sair depois de 320 m. O túnel termina a 175 m da cabeceira, portanto o piso da origem não é candidato a descarregamento durante ponte, acesso ou túnel.
- Cruzar o limite V1 apenas chama `_commit_logical_region`: os nós do jogador, carro ocupado, carro de passageiro, câmera e mundo não são recriados nem teleportados. Velocidade, dano, equipamento, ocupação e anexos permanecem no mesmo objeto. A viagem rápida antiga continua em `travel()` e mantém sua admissão/teleporte próprios; ela não é usada pela travessia física.
- Enquanto as duas regiões residem, o grafo `NativeTrafficRoutes` recebe as vias de ambos os lados e duas arestas dirigidas curtas que reproduzem a transferência V1 entre as faixas separadas e o centro da estrada da serra. O tráfego ambiente troca apenas o metadado lógico conforme a posição; não há remoção/recriação na emenda.

### Contrato dos consumidores da região

- **População e tráfego:** a travessia física não limpa `world.people` nem `vehicles`; spawns próximos consultam o conjunto viário residente. Veículos visíveis atualizam `region_id` por posição. Despacho refaz o roteador e o controlador de preferência de passagem refaz seu modelo quando a residência ou o contexto muda.
- **Jogador, veículo e passageiros:** o foco físico segue o carro dirigido ou o veículo de transporte quando ocupados. A troca lógica atualiza o metadado desses veículos sem chamar `cancel_for_transition`, `Driving.leave` ou `Vehicle.place`.
- **Missões e atividades:** seus objetos e snapshots não são reiniciados pela travessia. Eles já observam `state.region_id`; regras regionais existentes podem suspender/cancelar uma tentativa incompatível depois da mudança, mas a integração não cancela indiscriminadamente a missão nem apaga o estado.
- **Clima, frio e áudio regional:** `Weather` e `ColdSurvival` leem o novo `state.region_id`; a mudança força atualização imediata do clima. `ProductionWorld.logical_region_changed(previous,next)` é o contrato para consumidores adicionais e chama `WorldAudio.on_region_changed` quando o módulo de áudio oferecer esse método. O `WorldAudio` atual ainda mantém o leito urbano fixo e não implementa o hook: a troca completa da ambiência base da serra permanece pendente da frente de som.
- **Persistência:** o mesmo `region_id` existente passa a representar o lado lógico atual, e posição pedestre/veículo continua em coordenadas globais V2. Não houve alteração de schema. Saves sentados continuam restaurados pelo fluxo existente; pontos de viagem rápida e retornos autorados não foram removidos.

### Diferenças restantes e validações pendentes

- A estrutura 3D conserva posições, extensões e corredor do V1, mas é uma adaptação nativa: cabos, luminárias, materiais, neve, corte visual do teto e detalhes dos encontros ainda não têm paridade visual demonstrada.
- Não foi executado Godot. Permanecem sem prova: compilação dos scripts, suporte contínuo para a cápsula do jogador, quatro rodas em toda a largura, guarda-corpos sem enrosco, altura de todos os veículos no túnel, saída lateral a pé, retorno oeste e ausência de degrau nas três junções.
- Não foi executada travessia real com carro ocupado, passageiro, reboque/veículo de missão, perseguição, incidente de despacho ou tráfego nos dois sentidos. Também falta verificar se regras de missão específicas respondem à mudança lógica sem perda indevida.
- Não há baseline ou comparativo renderizado. A sobreposição é limitada à vizinhança da conexão: ambas solicitam 3×3, a região física pode reter células já visitadas num raio 5×5 e a secundária é aparada para 3×3. O teto estrutural é, portanto, 34 chunks residentes, não dois mapas completos. A estrutura compartilhada não possui callback por quadro, luz dinâmica ou SubViewport, mas primeira montagem, formas estáticas, dois terrenos residentes e reconstrução do grafo precisam ser medidos na cena real.
- Para aprovar: percorrer ida e volta a pé e com os maiores veículos; parar sobre cada limite de chunk; salvar/restaurar em ambos os lados e dentro de carro; testar tráfego/dispatch/missão durante a travessia; inspecionar dia/noite e chuva/neve; medir primeira visita e retorno com p50/p95/p99, pior quadro e quadros acima de 33,3/66,7 ms.

## Cemitério: implementação e contrato

`OriginalCemetery3D.world_position()` retorna `(-40.625,0,108.75)`. Instanciar uma vez como filho do chunk que contém esse ponto, definir sua `position` com esse valor e descarregar com o chunk. O script usa coordenadas locais e não conhece sessões, saves ou despacho. Não monta outra casa do zelador.

Lote original: 780×700 pixels (48,75×43,75 m). Centro e abertura norte conservados. A parede tem cinco segmentos; a abertura tem 52 pixels antes dos postes. O caminho da casa mantém o percurso original `(-235,-178) → (-235,-145) → (0,-145)`, relativo ao cemitério. Foram mantidas as cinco exclusões de túmulos que reservam a casa e o corredor.

Os 31 túmulos usam medidas e partes de `CemeteryGrave3D`, convertendo a projeção original de 20 pixels/unidade para 16 pixels/metro. Flores foram simplificadas em geometria agrupada; não há SubViewports por túmulo. Laje e cabeceira têm sólidos separados. Muros, bancos, troncos e postes possuem colisão layer 1. Piso usa suporte nativo; caminhos são revestimentos rasos. A câmera e o indicador da casa permanecem os existentes.

Estado da conexão: `NativeRegion._prepare` registra o centro e `_build_chunk` instancia `cemetery` com a posição original. Conexão confirmada por leitura, nenhum comportamento validado. Não registrar no checklist de interiores como interior concluído: não foi criada nem alterada sala interna.

## Integração da rodada de três agentes

- `NativeRegion` instancia `MountainTerrain3D`, configura reservas com estradas, definições e acessos do catálogo e substitui o piso plano da serra pela malha com colisão. Pinheiros usam a altura interpolada da mesma superfície. Ski, construções, lagos e acessos conservam áreas planas; as elevações externas são adaptação nova ao 3D, não relevo existente no V1.
- `TerrainDressing3D.build_chunk` é chamado nos chunks da serra com a altura do terreno e reservas adicionais em torno dos pinheiros. Grama e pedras são limitadas por chunk; pedras maiores possuem colisão. Sem decoração procedural adicional no porto.
- `OriginalSouthPort` fornece 36 registros de modelos originais: cinco edifícios, carga e cabine do Santa Mare, três gruas, seis conjuntos de suprimentos, doze cargas soltas e oito postes. `NativeRegion` monta esses registros e os guarda-corpos, recorta passarelas, casco, píeres e acostamento de acesso por chunk. Os 18 conjuntos de contêineres existentes permanecem em seu caminho anterior.
- Porto Sul ainda não está completo: operação de gruas, trabalhadores, empilhadeiras, portões e iluminação ativa não foram implementados por este componente. Superfícies usam material simplificado. A conexão por código não certifica escala, colisão ou percurso navegável.
- Foram executados somente os contratos headless urbanos listados nesta rodada; não houve benchmark, percurso visual integral nem commit. A cidade e a ligação com a serra continuam dependendo das validações físicas/renderizadas acima e das diferenças explícitas deste inventário.

## Pendências específicas do cemitério

- `HarborCemetery.restore_burials`, reserva de sepulturas, identidade persistente e mortician não foram portados por este componente exterior.
- CemeteryStoryteller, CemeteryAtmosphere, rotina do zelador e segredo/carta não são substituídos por decoração. A existência de serviços independentes no V2 deve ser conferida antes de afirmar ausência ou paridade desses comportamentos.
- Postes são modelos visuais, sem quatro novas luzes dinâmicas. Atmosfera noturna, sons, vegetação detalhada, textura do caminho e marcas da carta continuam diferentes.
- Verificar em jogo: portão norte com jogador e carro; caminho até casa e retorno do save; caminhar em torno de túmulos/bancos; tiros contra laje/cabeceira; profundidade visual; entrada em chunk vizinho sem desaparecimento prematuro.

## Performance e critério de conclusão

Foi usado agrupamento MultiMesh por cor, uma raiz de colisão com formas locais, oito pinheiros compartilhados e nenhum callback por quadro, luz dinâmica nova ou SubViewport. Isso reduz trabalho estrutural, mas não comprova custo aceitável. Risco restante: montagem do lote em um chunk e custo das formas estáticas na primeira visita.

Na ligação cidade–serra, a residência sobreposta limita-se à aproximação (240 m para carregar; 320 m para liberar) e a estrutura compartilhada é estática. O risco concreto é a primeira construção sobreposta (3×3 solicitado por lado; até 5×5 retido só no lado físico e 3×3 no secundário), mais formas da ponte/túnel e reconfiguração do grafo de tráfego. A medição antes/depois não foi executada nesta rodada porque já havia outra instância Godot ativa e o pedido proíbe benchmark concorrente.

Sem baseline nem medição renderizada desta alteração. Alvo provisório: 60 FPS / 16,67 ms, hardware ainda não estabelecido. Comparar primeira visita e retorno, dia/noite, junto de tráfego real, com p95/p99 e pior quadro; aumento superior a 5% exige investigação, não aprovação automática. Compilação e contratos dirigidos de colisão/acesso passaram; oclusão global, percurso real e frame time permanecem pendentes porque outra sessão Godot já estava ativa.

## Evidências e validação da integração urbana

Execução headless em Godot 4.7.2:

| Contrato | Resultado | O que prova | O que não prova |
|---|---:|---|---|
| `tests/urban_detail/test_urban_building_factory.gd` | PASS, 0 falhas | 61 registros; criação; layer 1; ausência de SubViewport; placas; pátio L; baia de veículo; alcovas; alturas Exchange/Civic | fidelidade visual e percurso entre chunks |
| `tests/urban_detail/test_harbor_ammunation_atomic.gd` | PASS, 14 checks | catálogo, fachada, entrada, retorno, `place_id`, lote NF2 e ausência no NF1 | compra, interior e captura equivalente |
| `tests/urban_detail/test_harbor_access_exteriors.gd` | PASS, 11 checks | aproximação oeste e retorno `EXTERIOR` da garagem do chefe, portão transitável, flancos sólidos e tampa do bueiro com suporte físico quando fechada | save e comparação de frame time |
| `tests/urban_detail/test_harbor_public_realm.gd` | PASS, 20 checks | cinco registros públicos, peças reconhecíveis, zero SubViewport, colisão da fonte e piso livre | equivalência visual e botânica completa |
| `tests/urban_detail/test_harbor_fidelity_contract.gd` | PASS, 0 falhas | polígono da emenda com 13 amostras por borda, suporte próprio, seis âncoras exatas, parasol, colisão do mobiliário, geometria direta e dressing com visual/colisão separados | rotinas dos restaurantes, percurso real e frame time |
| `tests/test_regions.gd` | PASS, 0 falhas | montagem integrada das regiões e sólidos dos 28 lugares, incluindo Ammu, garagem do chefe e esgoto | percurso jogável e fidelidade visual |

Os avisos de log `user://` e certificado do sistema são limitações do ambiente de teste; os três scripts encerraram com código 0 depois dos ajustes. Não foram alterados HUD, menus, Gameplay, Actor, áudio de combate, missão ou economia.

Comparações atuais:

| Área | V1 | V2 | Leitura |
|---|---|---|---|
| Mercado / Foundry | [`harbor-comparison-v1-market.png`](../evidence/harbor-comparison-v1-market.png) | [`harbor-comparison-v2-market.png`](../evidence/harbor-comparison-v2-market.png) | mesmo centro `(1620,900)`, 2000×1100 e escala vertical equivalente; V2 confirma lotes/conexão, mas acabamento e sinalização continuam aproximados |
| Northbank | [`harbor-comparison-v1-northbank.png`](../evidence/harbor-comparison-v1-northbank.png) | [`harbor-comparison-v2-northbank.png`](../evidence/harbor-comparison-v2-northbank.png) | mesmo centro `(5530,1230)`, 2000×1100 e escala vertical equivalente; monumento aparece, mas arborização, mobiliário e fachadas ainda diferem |
| Maciota | [`maciota-exterior-after.png`](../../docs/measurements/maciota-exterior-after.png) | [`v2-exterior.png`](../evidence/v2-exterior.png) | primeiro marco reconhecível, porém enquadramentos diferentes; não conta como par equivalente final |

Novo conjunto dirigido em `C:/Users/rafae/.codex/visualizations/2026/09/21/01a0c5d4-0aa6-7ba0-819f-d0c3afa28d07/harbor-fidelity`, 1600×900, centro autorado e escala aparente fixos: `v1-*`, `before-*` e `final-*`. Ele cobre Ammu-Nation, Northstar, Porto Sul, ferro-velho, cemitério, Cobra, garagem do chefe, esgoto, os três restaurantes e a emenda. Os pares demonstram a correção da ponta da emenda e as adições descritas, mas mantêm todas essas áreas como **aproximadas** onde material, fachada, densidade, operação ou contexto ainda divergem.

A oclusão foi conferida separadamente da colisão em `final-occlusion-cobra-ahead.png` e `final-occlusion-cobra-behind.png`: a mesma cápsula magenta fica legível à frente e é coberta pelo tronco/copa quando passa atrás. A colisão usa os ensaios físicos do contrato dirigido e dos acessos, não essa imagem.

`tests/urban_detail/capture_harbor_comparison.gd` conserva os dois pares urbanos anteriores. `tests/urban_detail/capture_harbor_fidelity.gd` e o companheiro V1 `tests/visual/capture_harbor_v1_fidelity.gd` cobrem as onze vistas prioritárias com os mesmos centros, escala, resolução e horário fixo. A projeção 3D do V2 não é idêntica à apresentação 2D V1, então os pares localizam diferenças e impedem aprovação nominal; não constituem equivalência pixel a pixel.

### Bloqueios para declarar Harbor concluída

1. Refinar os pares já capturados com vistas de aproximação em perspectiva jogável; a matriz superior equivalente já existe, mas não substitui percurso.
2. Percorrer a pé e de carro cada acesso, cruzamento, passarela e emenda de chunk; validar colisão e oclusão em ensaios separados.
3. Revalidar entrada, retorno e restauração de save na Ammu, garagem do chefe do porto e esgoto.
4. Fechar paridade operacional do Northstar, Porto Sul, ferro-velho e cemitério, ou manter cada diferença explicitamente como aproximada.
5. Comparar os novos conjuntos públicos e refinar botânica, materiais e mobiliário onde o par V1/V2 demonstrar diferença.
6. Medir antes/depois na cena renderizada real, sem outra instância Godot ativa, com mesma câmera, população, tráfego, horário e duração.

Estado final desta rodada: **cidade produtiva parcialmente migrada; não concluída**.
