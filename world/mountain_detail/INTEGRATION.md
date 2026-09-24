# Manual de Integração — Mountain Detail 3D (Geteco V2)

Este documento descreve a arquitetura, as regras de conformidade, a correspondência geométrica e as instruções para conectar a fábrica independente `MountainDetailFactory` à cena nativa de streaming `NativeRegion.gd` para as regiões da **Madeireira (Sawmill / Logging Camp)** e do **Vilarejo da Montanha (Mountain Transit Village)**.

---

## 1. Visão Geral e Arquitetura

O módulo `mountain_detail` foi desenvolvido para fornecer a apresentação exterior 3D completa e autêntica dos dois principais centros de atividade humana da montanha: a madeireira em East Vale e o vilarejo alpino de trânsito.

### Diretrizes Centrais Cumpridas:
- **Zero SubViewports**: Todas as estruturas, telhados, baias e props são malhas nativas 3D (`MeshInstance3D`) integradas ao espaço métrico do jogo, eliminando os SubViewports 2.5D do V1.
- **Escala e Geografia Preservadas**: Baseadas na proporção métrica canônica de **16 pixels por metro** (`SCALE = 1.0 / 16.0 = 0.0625 m/px`). As coordenadas de todos os elementos batem milimetricamente com os dados originais (`OriginalWorldData.json` e `MountainTransitVillageLayout.gd`).
- **Física e Colisões 3D Nativas**: Volumes sólidos geram corpos `StaticBody3D` (Collision Layer 1, Mask 0).
- **Acessibilidade e Vãos Livres**:
  - A via de acesso e o pátio de manobra da madeireira possuem vão livre contínuo para passagem de caminhões e picapes (largura de entrada de 5.6m desobstruída);
  - As portas dos 4 chalés, do terminal e da loja mantêm patamares livres de colisores;
  - A baia de parada de ônibus (Coach Berth 01) e o concourse de passageiros estão desimpedidos.
- **Identidade Visual por Aparência (AGENTS.md)**:
  - Fachadas recebem **apenas o nome próprio**: "Terminal da Serra" e "Casacos da Vila"; slogans e descrições de serviço foram eliminados;
  - A vitrine de roupas utiliza **manequins vestidos em proporções humanas naturais** (altura ~1.7m com parcas, capuzes e botas), em estrita conformidade com a regra que proíbe peças de roupa gigantes flutuantes.
- **Materiais Compartilhados**: Centralizados em `MountainMaterials.gd`, prevenindo alocações dinâmicas de material e minimizando o overhead de pipeline.
- **Iluminação Eficiente**: O braseiro do vilarejo possui luz pontual sem projeção dinâmica de sombras (`shadow_enabled = false`), preservando a taxa de quadros.

---

## 2. Inventário de Elementos e Correspondência com o Original

### 2.1 A Madeireira (Logging Camp / Sawmill) — Ponto Central: `(6350, 560)`
| Elemento | Arquivo / Classe | Origem em V1 / Descrição |
| :--- | :--- | :--- |
| **Pátio e Acesso de Terra** | Polígonos de solo | `NativeRegion.gd:389` e `MountainSceneryBuilder.gd:975-990` (`Rect2(-180,-110,360,240)` e `Rect2(-35,-165,70,65)`). |
| **Galpão de Corte** | `SawmillShed3D.gd` | Galpão rústico semiaberto com colunas de toras, tesouras de madeira, serra circular com disco de aço (`metal_blade`), esteira de roletes para troncos e bancada de trabalho. |
| **Escritório da Madeireira** | `LumberjackCabin3D.gd` | Microchalé com ferramentas de corte, entalhes de toras e raspador de botas (modelo 3D original reaproveitado). |
| **Pilhas de Toras Cobertas** | `CoveredWoodpile3D.gd` | Estruturas em `(-95, 5)` e `(-95, 55)` com toras empilhadas com anéis de corte, telhado com neve e toco com machado cravado. |
| **Pilhas de Madeira Serrada** | `LumberStack3D.gd` | 4 fiadas de pranchas sobrepostas cintadas com fitas metálicas de aço galvanizado (`SawmillYardDetails.gd`). |
| **Área de Serragem** | Patch de solo | Monte de serragem amarelada e cavacos soltos em `(-30, 81)` (área transitável sem colisão). |
| **Fogueira do Pátio** | Fogueira com anel de pedra | Círculo de pedras de rio em `(90, 20)` com brasas e toras de assento. |
| **Cercas Rústicas** | `SawmillFence3D.gd` | Cerca de mourões e varas contornando o pátio com abertura para a entrada de veículos. |

### 2.2 O Vilarejo da Montanha (Mountain Transit Village) — Ponto Central: `(7560, -1650)`
| Elemento | Arquivo / Classe | Origem em V1 / Descrição |
| :--- | :--- | :--- |
| **Terminal de Trânsito** | `MountainTerminal3D.gd` | Estação em toras com embasamento de pedra, ampla cobertura de espera para passageiros e letreiro "Terminal da Serra". |
| **Baia de Ônibus 01** | Plataforma marcada | Ponto de parada em `(7500, -1760)` com demarcação no piso e inscrição "01". |
| **Loja de Roupas de Inverno** | `VillageShopfront3D.gd` | Fachada de `mountain_village_outfitters` ("Casacos da Vila") com vitrine e manequins vestidos em proporções naturais. |
| **4 Chalés Residenciais** | `MountainChalet3D.gd` | Casas alpinas em `(7405,-1480)`, `(7545,-1480)`, `(7725,-1440)` e `(7870,-1440)` com variantes de cor, mansardas e chaminés. |
| **Praça e Braseiro Comunitário** | `VillagePlaza3D.gd` | Calçamento central e braseiro de ferro fundido em `(7650, -1553)` como fonte de calor para sobrevivência ao frio. |
| **Postes de Iluminação** | Postes de lanterna | 4 postes de madeira com lanterna de vidro âmbar e topo nevado. |
| **Depósitos de Lenha** | Abrigos de lenha | 3 abrigos rústicos de lenha comunitária com cobertura nevada. |
| **Cercas de Encosta** | `SawmillFence3D.gd` | Cercas de toras protegendo os declives ao redor do vilarejo sem bloquear os caminhos limpos. |

---

## 3. Instruções Passo a Passo para o Integrador em `NativeRegion.gd`

Quando o integrador for conectar o módulo ao streaming de chunks da montanha:

### Passo 1: Pré-carregar a fábrica independente
No topo de `geteco_v2/world/regions/NativeRegion.gd`:
```gdscript
const MOUNTAIN_FACTORY := preload("res://world/mountain_detail/MountainDetailFactory.gd")
```

### Passo 2: Registrar a localidade do vilarejo em `_prepare()`
Dentro do bloco `if region_id == "mountain":` (por volta da linha 90):
```gdscript
_record(CATALOG._at(Vector2(7560, -1650), region_id), {"kind": "mountain_village"})
```
*(Nota: o registro da madeireira `_record(CATALOG._at(Vector2(6350,560),region_id),{"kind":"sawmill_yard"})` já existe na linha 92).*

### Passo 3: Conectar a instanciação em `_build_chunk()`
Na função `_build_chunk(key: Vector2i)` de `NativeRegion.gd` (por volta da linha 188):

**Substituição para a madeireira:**
```gdscript
			# Antes: "sawmill_yard": _build_sawmill_yard(chunk)
			"sawmill_yard": MOUNTAIN_FACTORY.populate_sawmill_chunk(chunk, record)
```

**Adição para o vilarejo:**
```gdscript
			"mountain_village": MOUNTAIN_FACTORY.populate_village_chunk(chunk, record)
```

---

## 4. Registro do que Ainda Não Foi Validado

Em cumprimento à instrução *"Não execute testes ou benchmarks nesta etapa; registre o que ainda não foi validado"*, destacamos os itens que requerem validação conjunta na fase de montagem com o integrador:

1. **Varredura Física Automatizada (Swept Hulls)**:
   - Teste de colisão dinâmica com o probe veicular padrão (`Vector3(2.46, 1.5, 5.21)`) percorrendo a via de acesso e o pátio da madeireira.
   - Teste de aproximação de pedestre (cápsula) nas portas dos 4 chalés do vilarejo, da loja e do terminal.
2. **Integração Visual com o Shader de Terreno e Neve**:
   - Avaliação estética da transição de cor entre o solo plano das estradas de terra (`dirt_earth`) e o terreno nevado do shader `MountainGround.gdshader`.
3. **Métricas de Frame Time e Benchmarks de FPS**:
   - Aferição de custo de renderização em runtime real (janela de amostragem de frame times) na cena final consolidada da montanha.
4. **Marcadores de Transição de Interiores (`DoorAccessMarker`)**:
   - Conexão dos pontos de entrada/saída das portas dos chalés e da loja de roupas aos seus respectivos interiores mapeados em `PlaceCatalog.gd`.
