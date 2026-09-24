# Migração do mundo Geteco V2

## Escopo implementado

Harbor e Mountain usam Node3D no mesmo World3D, sem projeção 2D nem SubViewport por ambiente. PlaceCatalog cataloga 28 interiores distintos; Maciota separado soma29 do inventário original. Northgate Auto permanece serviço exterior. Avião acidentado é local exterior separado, instalado no lago original.

A escala de coordenadas originais é 16px por metro, calibrada por Coupe72–74px/4,6m e ruas120px/7,5m. Mountain recebe o deslocamento original ContinuousWorld (4300,-4960) antes da conversão XY para XZ. Geometria3D original permanece em metros1:1.

NativeRegion conserva ruas/locais/identificadores de HarborRoadLayout, HarborLocalStreets, HarborSouthPortLayout, HarborMountainConnector, HarborCobras e MountainPassRoad. Ruas paramétricas e plantas2D foram reconstruídas em3D com dados originais; essa reconstrução não equivale a copiar um modelo3D inexistente. Edifícios preservam footprints, tipos e cores disponíveis. Ashbend/Cobras e acesso Salvage usam coordenadas originais.

Chunks64m carregam vizinhança3x3 progressivamente, descarregam fora do raio2 e criam colisões somente na região ativa. Interiores são instanciados sob demanda por create_place(id). Árvores usam27 configurações originais de bosque, distribuição determinística com exclusão de vias/locais e meshes compartilhados das variantes originais Pine3D.

## Conteúdo reaproveitado

- Banco: bank-finished.tscn original e Helena BankClerkModel.
- Polícia, hospital, bombeiros, roupas, combustível: respectivas geometrias originais.
- Ammu-Nation Harbor/Mountain: AmmunationArt e fachadas originais.
- Chalé básico e6 variantes, bunker, abrigo dos lenhadores, Summit e caverna: modelos originais;3 acessos compartilham o mesmo abrigo.
- Residências Westgate/Quayside/Canal, casa do zelador, garagem do chefe e esgoto: geometria original isolada.
- Lojas da montanha: fachadas ResortShop3D originais e interior ClothingInteriorArt3D por variante.
- Ferro-velho: SalvageYard3D extraído em Node3D, com guindaste/prensa estáticos, colisões nativas e acesso original. NativeYard expõe npc_point e dock_point livres.
- Navio Northstar: reconstrução nativa da planta HarborWaterfront, incluindo convés poligonal, gangway original, guarda-corpos com abertura,18 cargas e cabine. CargoInspection permanece(3515,1450)/16 com piso físico.
- ServiceResidentModel/NecoModel: geometrias originais de HarborConversationalNPC/Neco, sem rotinas2D nem dependências globais antigas. Comportamento pertence à integração de sessão.

Cópias isoladas ficam assets/regions/source. Recursos res:// externos foram reescritos. Helpers visuais permanecem quando usados apenas para bounds/materiais; não são instanciados renderizadores projetados. O construtor2D não utilizado de DanteVisualAdapter foi excluído da cópia de tailoring.

## API

NativeRegion.build_region(id), set_focus(global_position), spawn_position, roads, buildings, entries, chunks.
PlaceCatalog.definitions/get_definition/create_place/access_points.
NativePlace expõe spawn_position, exit_position, camera_target, camera_size, interaction_points, reward_points, solid_bodies, solid_bounds, set_active e set_reward_available. Definições incluem source_id, região, exterior/entrada/retorno e NPC original quando disponível.

## Validação realizada

2026-09-21: test_regions.gd PASS sem erros de script:28 interiores instanciados, spawn/saída livres para cápsula real, sólidos presentes, nenhum SubViewport;2 regiões com carregamento limitado e descarga; modelos de serviço/Neco/Helena instanciados; raios confirmam piso em CargoInspection, gangway e aproximação de Neco; cápsula livre nesses3 pontos. Variante de montanha força fachadas/árvores para validar dependências.

Execução posterior confirmou remoção de recompensa genérica, três armas independentes do chalé com abordagens físicas livres, duas recompensas originais do avião e85 amostras de piso/cápsula e desníveis no percurso rampa→carga→cockpit. PASS sem erros de script; ambiente restrito impediu apenas log/certstore.

## Pendências reais para fechamento

- Capturas comparáveis e frame time renderizado de Harbor/Mountain/interiores: validação coordenada pelo integrador; headless não aprova FPS.
- Oclusão visual e navegação completa entre todos os móveis não foram aprovadas só pelo teste de spawn/saída. Necessário percurso e inspeção visual por ambiente.
- Avião acidentado instalado com modelo original, cutaway, rampa/convés/cockpit físicos e recompensas originais1800/SMG20. A água/ambientação original do lago continua pendente.
- Bunker agora tem exterior reconstruído da planta2D original e heliponto3D original. Fachadas Harbor ainda genéricas ou ausentes estão discriminadas no inventário abaixo.
- Terreno da montanha está plano. Lagos agora usam polígonos originais; nado/profundidade, cachoeiras volumétricas, relevo, detalhes urbanos/porto/ferrovia e ambientação restante ainda precisam lotes próprios.
- Chalé básico agora expõe3armas originais (hunting_rifle35munições, axe, knife), IDs originais e disponibilidade independente.
- Guindaste/prensa do ferro-velho preservam aparência; animação e entrega de veículo dependem do sistema integrado.
- Pontos de NPCs e interiores além dos acessos básicos exigem validação física dirigida. A escala visual dos residentes precisa revisão com Dante.

Este documento registra migração estrutural e arte reaproveitada; não declara paridade integral nem qualidade/performance final aprovada.

## Complemento recompensas múltiplas e avião

PlaceCatalog.rewards lista cada recompensa e mantém reward legado somente onde singular. Cada NativePlace.reward_points inclui campos do item, reward separado, position global e visual Node3D. set_reward_available(bool,id) atua individualmente; id vazio mantém chamada antiga. CargoPlaneNative usa mesmo contrato e entra no grupo native_world_rewards para descoberta da sessão após streaming.

## Inventário de apresentação: lote seguinte

| Local/conjunto | Situação nativa atual | Fonte original e trabalho restante |
|---|---|---|
| Hospital exterior | Modelo3D original instalado; entrada livre testada | HarborHospitalModel3D; portas abertas para acesso; câmera/oclusão render ainda a inspecionar |
| Bunker exterior | Reconstrução da planta2D, torre/radar/gerador e acesso; heliponto original3D | MountainSceneryBuilder.build_detailed_bunker + MountainHelipad3D; não havia modelo3D da fachada |
| Lagos alpino e glacial | Polígonos originais, cores, riacho, gelo, ilhota/camp/pedras reconstruídos em malhas | MountainSceneryBuilder, MountainLakeIce; água ainda rasa sobre terreno, sem paridade de nado/molhado; fogueira visual estática; jeep/cache da ilha não integrados neste lote |
| Banco exterior | Bloco com footprint original; arquitetura específica pendente | BankFacade.gd desenha2D; copiar colunas, entrada e materiais por reconstrução |
| Union exterior | Bloco original; vitrine/identidade pendentes | UnionClothingFacade.gd é2D; reconstruir com manequins proporcionais |
| Fuel exterior | Bloco original; arquitetura específica pendente | HarborBuilding.gd e geometria CanvasItem da fachada |
| Polícia exterior | Bloco original; arquitetura específica pendente | HarborBuilding.gd tipo police_precinct; modelo HarborPoliceStation3D é interior |
| Bombeiros exterior | Bloco original; baias/identidade específicas pendentes | HarborBuilding.gd tipo fire_station; FireStationArt3D é interior |
| Esgoto acesso exterior | Entrada catalogada; tampa original ainda ausente | ManholeCover3D.gd é reutilizável; HarborManholeSewer é wrapper2D |
| Garagem do chefe exterior | Interior original presente; acesso sem arquitetura específica | PortBossGaragePortal.gd e contexto HarborSouthPortLayout |
| Chalés/abrigo exteriores | Modelo LumberjackCabin3D reutilizado para todos | Revisar diferenças originais de pintura, variantes e ocupação; não afirmar paridade de cada variante |
| Outras fachadas Harbor e Cobras | Footprints/paleta/tipos reconstruídos | HarborBuilding/HarborCobras originais2D; acabamento específico ainda parcial |
| Relevo/rochedos/neve | Solo plano com divisão simples de neve | MountainSceneryBuilder.build_rocky_cliffs_and_ridges e polígonos terrace/permafrost/snow_pack/high_snow; fonte2D não fornece altitude física |

Os28 interiores têm fontes3D instanciadas e colisões nativas, mas todos exigem revisão visual por ambiente antes de declarar paridade de apresentação. Pontos específicos: banco cutaway de sua cena embutida; hospital abertura de portas; cavernas casco poligonal; chalés3armas individuais; armas/roupas variantes; residências mobiliário; esgoto canal/profundidade. A validação de entrada não substitui o percurso e oclusão de cada peça de mobiliário.

Lote lagos/bunker/hospital: test_regions PASS incluindo polígonos dos2lagos, domínio de água excluindo convés, entradas exteriores hospital/bunker. Serviços originais testados livres com cápsula: polícia(1.4,0,3.8), hospital pickup(2,0,-1), triagem(2,0,-3.5), bombeiros(10,0,-120/28), todos locais à sala.

## Revisão visual executada

Os28 interiores receberam captura real de entrada e posição atrás de móvel com Dante, câmera/luz da produção. Todas as56 imagens finais foram inspecionadas; foram corrigidos cortes de polícia, bombeiros, abrigo e Summit e enquadramento da garagemChefe. Aprovação limitada aos enquadramentos/pontos observados, sem substituir percurso completo ou performance. Relatório por sala: [interior-visual-review.md](D:/geteco/game/geteco_v2/docs/interior-visual-review.md).


### Residentes originais e estoque PortBoss (2026-09-21)

`OriginalResidentData.json` preserva os cinco habitantes da delegacia (Morales, Ribeiro, Ferreira, Dente de Ouro e Cida), Clara/Miguel do hospital e Capitão Rocha. Guarda nome, aparência, falas e coordenadas das fontes `HarborPoliceInterior`, `HarborHospitalInterior3D` e `HarborFireStationInterior`. `definition.npcs` expõe `id`, `name`, `model`, `local_position`, `source_position`, `appearance`, `dialogue_id`, `dialogue` e `source`. `OriginalResidents.create_model` aplica aparência original; o runtime cria atores/comportamento, evitando duplicar funcionário genérico. `NativePlace.interaction_points[id]` é global. Acessórios médicos vêm da fonte original.

`PortBossStock` fornece cinco spawns originais em `definition.vehicles`, sem instanciar carros ou pagar recompensas. Baias x=-8,-4,0,4,8; z=-4; yaw=-PI conforme conversão original `-rotation2D-PI/2`. `vehicle_rules` documenta disponibilidade, alarme, estado exclusivo e entrega, sem confundir Porto Rosso com Ironback da campanha Cobra. `vehicle_spawn=(0,.04,4)` e `vehicle_exit=(0,.04,8)` são locais; `vehicle_return=(5515/16,.04,5870/16)` é global. A rampa original agora tem piso físico explícito até z10.95.

Validação: `test_regions.gd` executado com exit0/REGIONS PASS. Cápsulas dos oito NPCs nas posições originais livres; hull conservador 2.46×5.21m livre nas cinco baias e dois pontos internos. Isso não comprova circulação completa dos cinco carros, retorno externo, interação em sessão, visual dos novos residentes/carros ou desempenho. Quatro capturas povoadas inspecionadas; a divisória da delegacia recebeu corte visual para revelar Ferreira, preservando colisão. Sessão integrada e desempenho seguem pendentes. Maciota: fonte atual `HarborGarageInterior.get_vehicle_bay_position()` usa origem3D da sala, enquanto CobraBossReward ainda contém BAY2D legado; root/gameplay validam a baia e transições.


## Integração urban_detail — implementada, não validada (pedido sem engine/testes)

NativeRegion agora monta a fábrica urban_detail no lugar do antigo bloco genérico, dentro do mesmo chunk de64m e mesmo ciclo de descarregamento. Posições/footprints do OriginalWorldData já convertidos para metros são passados como Vector3/Vector2, sem segundo /16. Garage continua excluído: Maciota é montado exclusivamente pelo controlador. Os oito registros correspondentes a lugares recebem identidade, ponto de entrada/retorno e origem do PlaceCatalog; não são instanciados novamente a partir desse catálogo. As três fachadas adicionais Westgate Garden/Quayside/cemitério usam a mesma fábrica, mantendo uma instância por local.

Modelos próprios Hospital/Ammu-Nation/Canal North são preservados. A fábrica abre portas suportadas após ready. Nos procedurais, a finalização deixa intactos os BoxShape nativos já existentes, evitando criar uma segunda colisão trimesh sobre os mesmos corpos. Portal visual da delegacia foi centrado no acesso existente; Northgate Auto mantém a baia aberta, sem novo interior. Placas de lugares vinculados usam nome próprio do catálogo. Interiores, marcadores, pontos de transição e Maciota não foram alterados.

Estações não foram posicionadas por aproximação: V1 UrbanTransit._setup calcula pose após amostrar a faixa da rua, deslocando90px no eixo da viagem e60px na perpendicular; STOP_DEFS.point sozinho não é a origem da estação. Hook disponível UrbanBuildingFactory.populate_transit(chunk,id,position,station_type,orientation), tipos0parada/1terminalurbano/2rodoviária, retorna Node3D com get_boarding_approach(). Exige pose real do adaptador de transporte/Arrival e uma única instância em chunk. Modelos já são métricos; o chamador converte apenas posição V1 por16. Ligação das estações e reconciliação da rodoviária com Arrival continuam pendentes, sem alegação de integração destes edifícios.

Nenhum Godot, teste, captura ou benchmark executado para este lote por instrução explícita. Pendente parser/import e validação real de todos os acessos, retorno, colisões/oclusão, compatibilidade do vão Northgate com frota, continuidade de streaming e custo renderizado com população. O material entregue pelo colaborador externo contém afirmações de validação/qualidade próprias; esta integração não as certifica.


## Mountain detail integrado — NÃO VALIDADO

Sem executar engine, testes ou benchmark, NativeRegion monta madeireira e vilarejo nos mesmos chunks de64m, com origem calculada exclusivamente por PlaceCatalog._at. Madeireira mantém os polígonos de terra em0,024m (acima da trilha), origem(6350,560), cabana3D original na origem e duas pilhas cobertas3D originais em(-95,5)/(-95,55). Não foram montados o escritório deslocado, o galpão inventado e cercas sem fonte. Pranchas preservam os quatro retângulos do SawmillYardDetails (passo9px e centros corrigidos), reinterpretados em volume; a serragem continua não sólida. Cabana e pilhas usam colisões por malha, sem preencher um abrigo semiaberto inteiro com caixa.

Vilarejo em(7560,-1650) reutiliza as seções originais ground/station/amenities de MountainTransitArchitecture3D, com calibração(18/16,1,18*FLOOR_Y/16), preservando a mudança de18px da estação e suas estruturas/apoios. As seções originais shop/chalet são omitidas deste composto: as cinco fachadas já montadas pelo catálogo permanecem únicas, com acessos/retornos intactos. O módulo reconstruído entregue fica disponível mas não substitui indiscriminadamente modelos originais existentes. Colisões nativas por malha mantêm livres os espaços sob cobertura; esta intenção ainda exige validação física real. A reserva florestal original MountainTransitVillageLayout.is_reserved é aplicada após geração determinística, sem sortear novas posições para árvores fora dela.

Fogueira e braseiro extra do pacote NÃO são montados. HeatPresentation permanece dono das fontes originais existentes e respectivas colisões/efeitos; não foi acrescentada luz. Coordenação confirmada com agente de gameplay. Caminhos, transporte, interiores e ProductionWorld não foram alterados. Fonte do terminal não cria um novo interior acessível.

Pendências: import/parser dos novos scripts; conferir colisão/alturas/escala e degraus; circulação real nos bancos, pátio e acessos; revisar sobreposição de pavimento e pistas; medir custo de streaming e frame time renderizado. Nenhuma garantia de qualidade/performance contida no pacote externo foi tomada como validação desta integração.
