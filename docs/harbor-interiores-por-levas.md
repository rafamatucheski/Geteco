# Harbor acessível — implementação por levas

## Atualização de 07/10/2026 — cidade inicial completa no catálogo

O pedido seguinte ampliou a primeira leva para todas as construções de Harbor: entrar caminhando, sem indicador laranja, explorar pavimentos na altura real e alcançar a cobertura com vista da cidade. O inventário e os estados históricos abaixo descrevem **06/10**, não a implementação atual.

O catálogo atual contém **59 edifícios de exploração**, com **119 pavimentos internos e 59 coberturas**. Inclui os 48 prédios do mapa-base sem serviço próprio, quatro adições ativas do editor, cinco construções do porto, Torque e a loja do Tonico. Dois desses 59 são Customs House e Union Lofts, já presentes na primeira leva: não somar novamente esses lugares. O depósito removido e as adições excluídas continuam excluídos.

Outros **24 edifícios com proprietário de interior existente** recebem acesso à cobertura, preservando loja, garagem, residência, missão e autorização: banco, supermercado, Ammu-Nation, Union, posto, Maciota, delegacia, hospital, bombeiros, Canal North, casa de Takeshi, Westgate, Quayside, zelador, garagem do chefe, seis casas da vila, borracharia, Vértice e Northgate Auto. São **83 edifícios/coberturas neste inventário**, não 83 interiores novos nem uma certificação dos demais mapas. Plataformas abertas, pontes, guindastes e abrigos de transporte não são contados como salas fechadas.

O exterior e os andares de exploração compartilham as coordenadas do mundo. O acesso da rua é contínuo; o teto e os volumes superiores cedem à câmera. A escada usa interação de subir/descer com transição coberta, e cada pavimento fica na altura correspondente da fachada. Não há promessa de subir cada degrau sem transição. O save restaura um patamar livre do andar salvo; uma visita nova pela rua começa no térreo. Saltar da cobertura abre um vão físico, usa gravidade e aplica dano de queda.

Há seis famílias de uso, combinações de mobiliário e materiais, ocupação variável e 38 salas trancadas elegíveis. São **200 recompensas persistentes**: 81 suprimentos, 60 caches internos e 59 caches de cobertura. Os 183 postos de moradores distribuem-se em 108 pavimentos ocupados; 11 pavimentos ficam vazios. Só os moradores do pavimento ativo são instanciados. Os programas compartilham componentes e subplantas; não são 119 plantas desenhadas manualmente e exclusivas. [Conteúdo, evidências e limites](harbor-building-content-20261007.md).

Validação atual: **11.773 verificações físicas, 59 edifícios/178 níveis, zero falhas** em `evidence/harbor-building-contract-180184-4434147`, complementadas por **1.598/1.598** após ampliar os compactos; lockpick **34/34**; morte/resgate/preload/escadas **65/65**; queda real renderizada **13/13**. Os 59 exteriores, 119 pavimentos e 59 coberturas foram fotografados na cena principal, seguidos de correções e dirigidos registrados no [checklist](interior-standard-checklist.md). As 24 coberturas complementares também foram percorridas, preservando a admissão do proprietário. A repetição noturna de Bridge Court West confirma a correção do trem que encobria a sala, com 11 verificações e 2.637 quadros nativos. A comparação isolada de desempenho continua pendente; essas evidências não certificam todas as condições de iluminação ou todos os ângulos.

## Registro histórico da primeira leva — 06/10/2026

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
