# Manual de Integração — Urban Detail 3D (Geteco V2)

Este documento descreve a arquitetura, as regras de conformidade, a tabela de correspondência e as instruções passo a passo para conectar o módulo `UrbanBuildingFactory` à cena nativa `NativeRegion.gd` de Harbor.

---

## 1. Visão Geral e Arquitetura

O módulo `urban_detail` foi desenvolvido para substituir os blocos geométricos genéricos que representavam os edifícios da cidade no primeiro rascunho de migração do V2 por arquitetura 3D nativa de alta qualidade, sem incorrer em custos proibitivos de renderização.

### Diretrizes Centrais Cumpridas:
- **Zero SubViewports**: Todos os edifícios são malhas nativas 3D (`MeshInstance3D`) com materiais compartilhados.
- **Física 3D Nativa**: Cada volume sólido gera corpos `StaticBody3D` (Collision Layer 1, Mask 0), preservando com exatidão a geometria autorada em V1.
- **Acessos Livres**: Vãos de entrada, portas sociais, o pátio sudoeste do bloco em L (`FoundryLofts`), os nichos recuados de lojas térreas (`UrbanShopfrontBuilding`) e o vão livre de oficina (`MotorWorkshop`) não possuem colisores bloqueando a passagem.
- **Identidade Visual por Aparência**: Fachadas recebem **apenas o nome próprio** do estabelecimento. Prefixos como `BANCO /`, `ROUPAS /`, `POSTO /`, avisos de horário e descrições de serviço foram eliminados das placas em estrita obediência às regras permanentes do projeto.
- **Materiais Compartilhados**: Todas as malhas consom instâncias cacheadas em `UrbanMaterials.gd`, eliminando desperdício em VRAM e prevenindo trocas excessivas de estado de pipeline (*material thrashing*). *(Nota técnica: no renderizador do Godot, instâncias avulsas de `MeshInstance3D` não sofrem unificação física automática de draw calls; para agrupar chamadas de desenho em lote na cena final, utiliza-se `MultiMeshInstance3D` ou mesclagem estática de malhas; o cache de materiais garante conformidade do pipeline e baixo consumo de memória).*
- **Sem Luzes com Sombras Indiscriminadas**: Nenhuma luz omni ou spot dinâmica com projeção de sombras foi adicionada aos edifícios. As vidraças utilizam `cast_shadow = OFF`.

---

## 2. Inventário de Modelos e Reconstruções

### 2.1 Distribuição dos 61 Registros de Harbor (`OriginalWorldData.json`)
A base de dados oficial de Harbor totaliza **61 registros de edifícios urbanos**, atendidos estritamente sem lacunas:
1. **1 Lugar Primário (`Garage` / Maciota)**: Atendido pelo catálogo central do jogo como localidade persistente independente; a fábrica retorna `null` para evitar duplicações na cena.
2. **3 Modelos 3D Originais Reaproveitados no registro de 61**:
   - `Clinic` (`harbor_hospital`) -> `HarborHospitalModel3D.gd`
   - `NorthFrontage2` (`harbor_ammunation`) -> `AmmunationFacade3D.gd`
   - `CanalHomesWest` (`canal_north`) -> `ResidenceExterior3D.gd`
   `cemetery_keeper` é somente catálogo e usa `CemeteryHouseExterior3D.gd`; não faz parte dos 61. As residências `westgate_garden` e `quayside_house` também são registros adicionais do catálogo e compartilham `ResidenceExterior3D.gd`.
3. **3 fachadas de marco reconstruídas especificamente**: `NorthFrontage0`, `NorthFrontage3` e `NorthFrontage4` usam `UrbanLandmarkFrontage3D` em vez do arquétipo genérico.
4. **54 demais edifícios reconstruídos em 3D nativo**: tipologias procedurais 2D convertidas em geometria modular. Na contagem operacional do teste, os três marcos entram junto destas reconstruções, totalizando 57.

### 2.2 Tabela de Reconstrução de Arte 2D em Geometria 3D Nativa
Onde a arte original existia exclusivamente em comandos de desenho vetorial 2D (`ProceduralBuilding.gd` e `HarborBuilding.gd`), os detalhes foram reconstruídos integralmente em 3D:

| Arquétipo / Script | Edifícios Atendidos | Detalhes Arquitetônicos Reconstruídos em 3D |
| :--- | :--- | :--- |
| `UrbanBrownstoneBuilding.gd` | `FoundryTerraceWest`, `FoundryTerraceEast`, `FoundryFlats`, `CanalHomesEast`, `GatewayFlats`, `BridgeCourtWest`, `GardenFlats` (12 prédios) | Escadarias de pedra (*stoops*) com corrimãos de ferro, portas sociais recuadas com bandeiras *fanlight*, cornijas com mísulas e modilhões, caixas d'água de madeira sobre cavaletes de aço, chaminés com vasos de argila, janelas guilhotina em pares e props no patamar (bicicleta/vaso de flores). |
| `UrbanCommercialBuilding.gd` | `NorthbankExchange`, `ExchangeTower`, `CivicTower`, `CustomsHouse`, `PortAuthority`, `MaritimeMuseum`, `Aquarium`, `Horizon`, `EastgateHotel`, `BridgeCourtEast`, `TransitHouse`, `ServiceLodge`, `UnionApartments`, `CommunityHall` (15 prédios) | Portais de entrada envidraçados com portas duplas, esquadrias ritmadas com montantes e faixas de tímpano, áticos recuados na cobertura, chillers HVAC industriais duplos com coifas e antenas de telecomunicação com dipolos. |
| `UrbanShopfrontBuilding.gd` | `AnchorDiner`, `Laundry`, `NorthbankGrocery`, `OrionCinema`, `Tideline`, `Early Shift`, `CanalGrocery`, `Hardware`, `Spoke`, `CornerPharmacy`, `North Pier` (11 prédios) | Vitrines comerciais amplas com rodapés, toldos listrados em tecido, marquises envolventes para prédios de esquina, portas de pedestres recuadas em nicho aberto com puxadores em latão, letreiro sobre a testeira. Para a lavanderia (`Laundry`), silhuetas estilizadas de tambores de lavar são visíveis através do vidro. |
| `UrbanIndustrialBuilding.gd` | `ColdStorage`, `FreightDepot`, `ParcelOffice`, `UnionWorkshop` (Harbor Bindery), `MarketHall` (Breakwater) (5 prédios) | Pilastras robustas de tijolos, esteiras metálicas seccionadas para carga, doca elevada com guias emborrachadas, portas duplas de carruagem em madeira com dobradiças compridas de ferro forjado, coberturas em shed (dente de serra) com claraboias verticais envidraçadas. |
| `UrbanServiceBuilding.gd` | `NorthFireStation` (Northgate Fire), `Police` (Harbor Patrol), `MotorWorkshop` (3 prédios) | **Bombeiros**: 3 baias largas com portões vermelhos, torre alta de secagem de mangueiras, sirene no teto e ferramentas cruzadas. **Polícia**: baia de viaturas, entrada fortificada, escudo policial e faixa azul/branca. **Oficina**: vão livre aberto transitável por veículos (largura 6.875m, profundidade livre 10.5m), paredes laterais e de fundo sólidas, estrutura de vigas com sinalização zebrada amarela/preta. |
| `UrbanCobraHouse.gd` | `PorchHouse`, `Duplex`, `ShingleHouse`, `CobraWorkshop`, `CourtyardHouse`, `BrickDuplex`, `TinRoofHouse`, `CornerBungalow` (8 casas) | Bangalôs residenciais do leste de Harbor: telhados inclinados de zinco corrugado ou tábuas com beirais, varandas frontais de madeira com pilares e degraus de acesso, portas residenciais com maçaneta e janelas com venezianas. |
| `UrbanLShapedBlock.gd` | `FoundryLofts` (Union Lofts & Works) (1 bloco) | Volume em L dividindo a ala principal norte da ala leste, mantendo o pátio sudoeste desobstruído de colisões. Janelas loft Crittall com grade 3×3, portas de doca no pátio e torre de água na cobertura. |

---

## 3. Ciclo de Vida em Duas Etapas e Instruções de Integração

### 3.1 Separação entre Criação e Finalização Pós-Mount
Os modelos 3D originais reaproveitados constroem suas malhas no método `_ready()`. Se inspecionados ou configurados antes de entrarem na árvore de cena, `find_children("*", "MeshInstance3D")` retorna uma lista vazia.

Por essa razão, a fábrica provê um ciclo explícito e seguro:
1. `UrbanBuildingFactory.build_building(data)`: Instancia a classe correta, define posição e metadados, e conecta o sinal `ready` à finalização automática caso adicionado à árvore posteriormente.
2. `UrbanBuildingFactory.populate_chunk(chunk, data)`: Adiciona o edifício ao nó do chunk e chama imediatamente de forma síncrona `UrbanBuildingFactory.finalize_building(building, data)`, garantindo que:
   - Portas sociais e automáticas abram corretamente (`set_door_amount(1.0)`, `set_open_amount(1.0)`, etc.);
   - As malhas criadas em `_ready()` recebam camadas de renderização corretas (`layers = 1`);
   - Colisores nativos trimesh (`StaticBody3D` camada 1) sejam gerados nos volumes estruturais dos modelos autorados;
   - Letreiros e placas sejam ajustados para exibir exclusivamente nomes próprios.

### 3.2 Instruções para `NativeRegion.gd`
Quando o integrador for conectar este módulo ao pipeline de streaming de Harbor:

#### Passo 1: Importar a fábrica no topo
Em `geteco_v2/world/regions/NativeRegion.gd`:
```gdscript
const URBAN_FACTORY := preload("res://world/urban_detail/UrbanBuildingFactory.gd")
```

#### Passo 2: Substituir a chamada de construção de edifício
Na função `_build_chunk(key: Vector2i)` de `NativeRegion.gd` (por volta da linha 205):

**Antes:**
```gdscript
			"building": _building(chunk, record.data)
```

**Depois:**
```gdscript
			"building": URBAN_FACTORY.populate_chunk(chunk, record.data)
```

*(Nota: a função interna `_building` de `NativeRegion.gd` pode ser desativada ou mantida como fallback).*

---

## 4. Comandos de Verificação e Validação

Todas as execuções de teste devem ser coordenadas pelo integrador:

### 4.1 Teste Automatizado Headless
Verifica todos os 61 edifícios, ausência de SubViewports, integridade de colisores na camada 1, nomes próprios, passagens livres de pedestres e veículos, e estações de trânsito:
```powershell
& "C:\Program Files\Godot\Godot_v4.3-stable_win64.exe" --headless --path D:\geteco\game\geteco_v2 --script res://tests/urban_detail/test_urban_building_factory.gd
```

### 4.2 Fixture de Demonstração Visual e Benchmark de FPS
Abre a cena de vitrine com todos os 11 arquétipos + estações dispostos lado a lado com câmera e iluminação de teste, exibindo métricas de amostragem de frame time:
```powershell
& "C:\Program Files\Godot\Godot_v4.3-stable_win64.exe" --path D:\geteco\game\geteco_v2 --script res://tests/urban_detail/urban_detail_fixture.gd
```

---

## 5. Pendências Reais e Próximos Passos

1. **Ajuste Fino de Paletas Concorrentes**: Os tons de tijolo e reboco foram calibrados a partir dos dados de V1; validação estética conjunta com o integrador de iluminação global e ciclo dia/noite do V2.
2. **Integração dos Marcadores de Acesso Interiores**: As portas dos arquétipos respeitam os acessos físicos, mas a montagem dos pontos de transição (`DoorAccessMarker`) para os interiores 3D integrados em `PlaceCatalog` será coordenada na fase de junção exterior-interior.
3. **Propagação para Regiões de Montanha**: A fábrica atual atende toda a mancha urbana de Harbor (61 edifícios). As estruturas rurais/alpinas de Mountain Pass (chalés, estação de esqui, bunker) continuam consumindo suas fontes dedicadas em `PlaceCatalog`.
