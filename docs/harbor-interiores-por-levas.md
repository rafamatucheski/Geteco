# Harbor acessível — implementação por levas

Pedido de 06/10/2026: tornar os prédios da cidade inicial acessíveis, com interiores distintos, pavimentos e cômodos coerentes com o uso.

## Contagem e limites do inventário

O mapa-base contém **61 registros** de prédios. `FreightDepot` está removido pelo editor: **60 fachadas ativas desse conjunto**, sendo **11 com acesso existente**, **2 implementadas nesta primeira leva** e **47 ainda pendentes de novo acesso**. Acesso existente não significa planta completa nem todos os andares aprovados. Os dois registros `new/` excluídos no editor não entram na contagem.

Esta tabela cobre o conjunto `harbor_buildings`, cruzado com `world_edits.json`. Edificações adicionais do catálogo, vila dos caminhoneiros, peças editoriais e construções autoradas em fábricas de cenário precisam de inventário complementar; os 60 registros não são um censo certificado de toda a cidade. Não somar a esse total a contagem de interiores de outros mapas.

## Primeira leva

- **Customs House** (`NorthFrontage5`): térreo com recepção, espera, atendimento e arquivo; primeiro andar com reunião, diretoria e trabalho; segundo com contabilidade, contratos e cópias; terceiro com copa, armários e descanso dos funcionários.
- **Union Lofts** (`Apartments`, próximo ao Bay Medical): térreo com sala, cozinha e jantar; primeiro andar com dois quartos, banheiro e estudo; segundo com estúdio residencial, cozinha e trabalho; terceiro com biblioteca, leitura, quarto de hóspedes e sala.
- **2 lugares físicos / 2 interiores com múltiplos pavimentos / 8 plantas autoradas**. Térreo + três andares acompanha as três faixas superiores de janelas das fachadas atuais. Não contar oito fachadas nem oito prédios.
- Portas usam o acesso compacto existente; aproximar e interagir. Escada usa ação funcional de subir/descer com a tecla remapeada de interação e transição coberta. Nos andares intermediários, escolher subir, descer ou voltar no menu. Os andares são salas separadas; esta leva não implementa subida física contínua por toda a escada.
- Apenas um pavimento fica instanciado. O save restaura o andar superior em um patamar livre; não restaura a posição exata dentro do cômodo. Uma nova visita pela rua começa no térreo.
- Sem novas rotinas de moradores, diálogos, recompensas ou missões nesta leva. Os NPCs usados nos testes de profundidade são atores de validação, não população residente entregue.
- Mantidos os bloqueios de missão e regras de combate/garagem já existentes.

## Levas seguintes

2. Terraços e lofts de Foundry: separar unidades residenciais e acessos reais.
3. Demais residenciais: plantas e número de pavimentos derivados das fachadas, apartamentos com cômodos próprios.
4. Escritórios, torres e equipamentos públicos: recepção, trabalho, reunião, administração e serviços adequados à função.
5. Comércio e galpões: salões, estoques, cozinhas e áreas técnicas. Northgate Auto deve ser conciliada com seu serviço/animação existente ao implementar o pedido atual de acessibilidade geral.
6. Casas dos Cobras: identidades próprias e compatibilidade com progressão, combate e missões.
7. Revisar pavimentos dos serviços que já têm interior; completar o inventário complementar e testar transições/carga entre levas.

Cada leva exige física, profundidade, entrada/saída, persistência e desempenho renderizado. Não marcar os demais prédios como jogáveis por compartilharem infraestrutura.

Primeira leva: [resultados, fotografias, medições e pendências](reviews/harbor-building-batch1-20261006.md). A validação temporal noturna e a instrumentação específica de primeira visita continuam pendentes; implementação não equivale a certificação integral.

## Inventário do mapa-base efetivo

| Prédio | Tipologia exterior | Leva | Estado |
| --- | --- | --- | --- |
| NorthFrontage0 | bank_branch | Revisão | Acesso existente; revisar planta e pavimentos depois |
| NorthFrontage1 | brownstone | Revisão | Acesso existente; revisar planta e pavimentos depois |
| NorthFrontage2 | brownstone | Revisão | Acesso existente; revisar planta e pavimentos depois |
| NorthFrontage3 | brownstone | Revisão | Acesso existente; revisar planta e pavimentos depois |
| NorthFrontage4 | office | Revisão | Acesso existente; revisar planta e pavimentos depois |
| NorthFrontage5 | office | 1 | Implementado; certificação em andamento |
| FoundryTerraceWest | rowhouse_terrace | 2 | Pendente |
| FoundryTerraceEast | rowhouse_terrace | 2 | Pendente |
| FoundryLofts | l_shaped_block | 2 | Pendente |
| CornerDiner | corner_shop | 5 | Pendente |
| Laundry | commercial_laundromat | 5 | Pendente |
| UnionWorkshop | artisan_workshop | 5 | Pendente |
| MarketHall | warehouse_shop | 5 | Pendente |
| ColdStorage | warehouse | 5 | Pendente |
| Garage | garage | Revisão | Acesso existente; revisar planta e pavimentos depois |
| Police | police_precinct | Revisão | Acesso existente; revisar planta e pavimentos depois |
| Clinic | hospital | Revisão | Acesso existente; revisar planta e pavimentos depois |
| Apartments | office | 1 | Implementado; certificação em andamento |
| FreightOffice | office | 4 | Pendente |
| ExchangeTower | office | 4 | Pendente |
| CivicTower | office | 4 | Pendente |
| MaritimeMuseum | office | 4 | Pendente |
| NorthbankHomes0 | rowhouse_terrace | 2 | Pendente |
| NorthbankHomes1 | brownstone | 3 | Pendente |
| NorthbankHomes2 | artisan_workshop | 5 | Pendente |
| IslandGrocer | corner_shop | 5 | Pendente |
| IslandCinema | shop | 5 | Pendente |
| Aquarium | office | 4 | Pendente |
| PromenadeCafe | corner_shop | 5 | Pendente |
| NorthbankFront0 | brownstone | 3 | Pendente |
| NorthbankFront1 | brownstone | 3 | Pendente |
| NorthbankFront2 | office | 4 | Pendente |
| NorthbankFront3 | office | 4 | Pendente |
| BridgeCourtWest | brownstone | 3 | Pendente |
| BridgeCourtEast | office | 4 | Pendente |
| BridgeQuayHouse | brownstone | 3 | Pendente |
| GatewayFlats | brownstone | 3 | Pendente |
| TransitHouse | office | 4 | Pendente |
| MotorWorkshop | garage | 5 | Pendente |
| RoadsideSupplies | shop | 5 | Pendente |
| ServiceLodge | office | 4 | Pendente |
| ParcelOffice | warehouse | 5 | Pendente |
| NorthFireStation | fire_station | Revisão | Acesso existente; revisar planta e pavimentos depois |
| ServiceCafe | corner_shop | 5 | Pendente |
| CanalHomesWest | brownstone | Revisão | Acesso existente; revisar planta e pavimentos depois |
| CanalHomesEast | brownstone | 3 | Pendente |
| NorthGrocer | corner_shop | 5 | Pendente |
| CycleWorkshop | shop | 5 | Pendente |
| GardenFlats | brownstone | 3 | Pendente |
| UnionApartments | office | 3 | Pendente |
| CommunityHall | office | 4 | Pendente |
| CornerPharmacy | shop | 5 | Pendente |
| PorchHouse | cobra_house | 6 | Pendente |
| Duplex | cobra_house | 6 | Pendente |
| ShingleHouse | cobra_house | 6 | Pendente |
| CobraWorkshop | cobra_house | 6 | Pendente |
| CourtyardHouse | cobra_house | Revisão | Acesso existente; revisar planta e pavimentos depois |
| BrickDuplex | cobra_house | 6 | Pendente |
| TinRoofHouse | cobra_house | 6 | Pendente |
| CornerBungalow | cobra_house | 6 | Pendente |
