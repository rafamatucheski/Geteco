# Harbor Art Pack — Kit Procedural 3D de Ambientação do Porto (GETECO)

Kit procedural 3D de ambientação portuária de alta performance para o projeto **GETECO**, desenvolvido exclusivamente em `prototypes/harbor_art_pack/`. Todos os modelos respeitam estritamente a métrica humana do jogo (1 unidade = 1 metro), origem no solo (\(y = 0.0\)), compatibilidade com Vulkan Forward+, legibilidade em vista isométrica/top-down e otimização por agrupamento estático de malhas.

---

## 1. Diretrizes Técnicas e Padrões de Engenharia

- **Escala e Unidades:** Metros reais (\(1.0\text{ unit} = 1.0\text{ m}\)). Portas, alturas de paletes, diâmetros de tambores e cabines são proporcionais ao manequim estivador de 1,80 m.
- **Origem dos Nós:** Piso nivelado em \(y = 0.0\). Nenhum modelo possui geometria afundada no solo por padrão.
- **Processamento Contínuo:** **Zero `_process()` ou `_physics_process()`** nos objetos estáticos. Construção procedural gerada uma única vez no ciclo `_ready()`.
- **Biblioteca de Materiais Compartilhada (`PortArtMaterials.gd`):** Gerenciador centralizado de `StandardMaterial3D` em cache. Evita duplicações e minimiza draw calls no Vulkan Forward+.
- **Otimizador de Lotes Estáticos (`PortMeshOptimizer.gd`):** Combina geometrias de múltiplos objetos que compartilham o mesmo material em malhas únicas via `SurfaceTool`, reduzindo centenas de draw calls para um punhado de lotes consolidados.

---

## 2. Distinção Metodológica: Medições Exatas vs. Estimativas Operacionais

Para garantir rigor de engenharia na integração pela equipe da Astra, o kit distingue categoricamente:

1. **Medições Físicas Reais da Geometria (Milimétricas/Métricas):**
   - Dimensões exatas dos vértices modelados, incluindo partes rotacionadas (portas abertas a 115°, pernas de cavalete em 'A', inclinação de refletores, flanges e guarnições).
2. **Estimativas de Desobstrução Operacional (Gameplay Envelopes):**
   - Áreas de manobra e circulação recomendadas ao redor dos objetos para tráfego do jogador, veículos ou empilhadeiras.

### Tabela Comparativa de Medições e Estimativas dos 21 Props

| # | Prop / Classe | Medição Geométrica Exata (\(L \times A \times P\)) | Meshes | Envelope Operacional Recomendado (\(L \times P\)) | Descrição Técnica dos Limites |
|---|---|---|---|---|---|
| 1 | `PortContainer20ft3D` | \(2.44 \times 2.59 \times 6.06\text{ m}\) | 90 | \(3.50 \times 8.00\text{ m}\) | ISO 20ft padrão (largura 2,44m, altura 2,59m, comprimento 6,06m). Área operacional inclui raio de giro frontal para manobra de caminhão/empilhadeira. |
| 2 | `PortContainer40ft3D` | \(2.44 \times 2.89 \times 12.19\text{ m}\) | 136 | \(3.50 \times 15.00\text{ m}\) | ISO 40ft High-Cube (comprimento 12,19m). Corrugações estampadas de 4 cm em cada flanco. |
| 3 | `PortContainerOpen3D` | \(3.32 \times 2.59 \times 7.13\text{ m}\) | 67 | \(4.00 \times 8.50\text{ m}\) | **Geometria com portas abertas a 115°**: As pontas das portas atingem \(X = \pm 1,66\text{ m}\) e \(Z = +4,10\text{ m}\). O vão de entrada livre é de 2,12m e o corredor interno é 100% desimpedido. |
| 4 | `PortReeferContainer3D` | \(2.44 \times 2.59 \times 6.06\text{ m}\) | 52 | \(3.50 \times 7.50\text{ m}\) | Contêiner frigorífico com unidade de refrigeração recuada na face frontal (-Z) e portas traseiras lisas isotérmicas. |
| 5 | `PortWoodenPallet3D` | \(1.20 \times 0.144 \times 0.80\text{ m}\) | 20 | \(1.40 \times 1.00\text{ m}\) | Medição padrão Euro Pallet (1200 x 800 x 144 mm). Vãos de garfo de 78 mm de altura livre. |
| 6 | `PortWeatheredPallet3D` | \(1.20 \times 0.144 \times 0.80\text{ m}\) | 24 | \(1.40 \times 1.00\text{ m}\) | Palete envelhecido com lascas e tábuas rompidas mantendo o gabarito estrutural de 1,20 x 0,80m. |
| 7 | `PortPalletStack3D` | \(1.20 \times 0.72 \times 0.80\text{ m}\) | 100 | \(1.40 \times 1.00\text{ m}\) | 5 paletes empilhados de 144 mm com jitter angular de \(\pm 1,2^\circ\). Altura total medida: 0,72m. |
| 8 | `PortCargoCrate3D` | \(1.10 \times 0.95 \times 0.90\text{ m}\) | 27 | \(1.30 \times 1.10\text{ m}\) | Caixa pesada com reforço em 'X' e cantoneiras de aço de 10 cm nos 8 vértices. |
| 9 | `PortLongCrate3D` | \(2.20 \times 0.60 \times 0.70\text{ m}\) | 27 | \(2.50 \times 1.00\text{ m}\) | Caixa para eixos e peças navais com 4 cintas de aço e sapatas inferiores transversais. |
| 10 | `PortPlasticTote3D` | \(0.60 \times 0.35 \times 0.40\text{ m}\) | 15 | \(0.70 \times 0.50\text{ m}\) | Eurobox plástica com abas superiores de empilhamento e alças vazadas de 12 cm nas cabeceiras. |
| 11 | `PortOilDrum3D` | \(0.58 \times 0.88 \times 0.58\text{ m}\) | 8 | \(0.70 \times 0.70\text{ m}\) | Tambor padrão 55 galões / 200L. Diâmetro do corpo: 58 cm; altura com chimes: 88 cm. |
| 12 | `PortRustyDrum3D` | \(0.58 \times 0.88 \times 0.58\text{ m}\) | 9 | \(0.70 \times 0.70\text{ m}\) | Tambor amassado na geratriz frontal com recuo de 4 cm no bordo e pátina de oxidação. |
| 13 | `PortDrumClusterPallet3D` | \(1.20 \times 1.03 \times 0.80\text{ m}\) | 41 | \(1.40 \times 1.00\text{ m}\) | Palete com 4 tambores e cinta com catraca. Altura total medida: 1,024m (topo dos bujões). |
| 14 | `PortHandTruck3D` | \(0.55 \times 1.30 \times 0.50\text{ m}\) | 16 | \(0.80 \times 0.80\text{ m}\) | Chassi tubular de 55 cm de largura, rodas de 24 cm de diâmetro e chapa de base em \(Z = +0,30\text{ m}\). |
| 15 | `PortPlatformCart3D` | \(1.25 \times 0.95 \times 0.75\text{ m}\) | 19 | \(1.60 \times 1.00\text{ m}\) | Deck a \(Y = 0,20\text{ m}\), alça a \(Y = 0,95\text{ m}\) e 4 rodízios industriais de 16 cm de diâmetro. |
| 16 | `PortForklift3D` | \(1.25 \times 2.25 \times 3.50\text{ m}\) | 48 | \(2.00 \times 5.00\text{ m}\) | Chassi de 2,40m (\(Z = -1,80\text{ a }+0,60\text{ m}\)) + garfos forjados projetados até \(Z = +1,70\text{ m}\). Comprimento total medido: 3,50m. |
| 17 | `PortLifebuoyStand3D` | \(0.50 \times 1.45 \times 0.35\text{ m}\) | 14 | \(0.80 \times 0.60\text{ m}\) | Pedestal com boia toroidal de 70 cm de diâmetro externo montada a \(Y = 1,05\text{ m}\). |
| 18 | `PortPierFender3D` | \(1.50 \times 0.55 \times 0.55\text{ m}\) | 11 | \(1.80 \times 0.80\text{ m}\) | Cilindro de borracha marinha de 55 cm de diâmetro com manilhas e elos de corrente em aço. |
| 19 | `PortMooringBollard3D` | \(0.70 \times 0.65 \times 0.60\text{ m}\) | 13 | \(1.00 \times 0.90\text{ m}\) | Cabeço *Tee-Head* em ferro fundido. Largura dos chifres: 70 cm; altura: 65 cm; base flange: 56 cm de diâmetro. |
| 20 | `PortFloodlightTower3D` | \(1.40 \times 4.50 \times 0.90\text{ m}\) | 59 | \(1.60 \times 1.20\text{ m}\) | Base de concreto de 70x70 cm, mastro tubular de 4,0m, cruzeta superior de 1,30m e para-raios atingindo \(Y = 4,50\text{ m}\). |
| 21 | `PortHazardSign3D` | \(0.75 \times 0.90 \times 0.45\text{ m}\) | 17 | \(0.90 \times 0.60\text{ m}\) | Cavalete em 'A' com abertura de pernas de 45 cm na base e placa zebrada de 65x55 cm. |

---

## 3. Arquitetura de Colisão do Contêiner Aberto (`PortContainerOpen3D`)

Diferente de caixas ou contêineres fechados que utilizam um único AABB sólido, o `PortContainerOpen3D` decompõe seus limites de colisão em **7 volumes sólidos perimetrais**, deixando o vão da porta e todo o corredor interior desobstruídos:

```
                  +Z (Frente / Entrada Cais)
                           |
    [Porta Esquerda]       |       [Porta Direita]
    (-1.66 a -1.10)        |       (1.10 a 1.66)
           \               |               /
            \              |              /
   ----------+=====[ VÃO LIVRE 2.12m ]=====+----------
   |                                                 |
   |                                                 |
   |           CORREDOR INTERNO LIVRE                |
   |         (Largura 2.12m x Altura 2.29m)          |
   |                                                 |
   |                                                 |
   -------------------[Fundo -Z]----------------------
```

### Lista dos 7 AABBs de Colisão Específicos:
1. **Piso Estrutural:** `AABB(Vector3(-1.22, 0.0, -3.03), Vector3(2.44, 0.14, 6.06))`
2. **Teto:** `AABB(Vector3(-1.22, 2.45, -3.03), Vector3(2.44, 0.14, 6.06))`
3. **Parede de Fundo (-Z):** `AABB(Vector3(-1.22, 0.14, -3.03), Vector3(2.44, 2.31, 0.16))`
4. **Parede Lateral Esquerda (-X):** `AABB(Vector3(-1.22, 0.14, -3.03), Vector3(0.16, 2.31, 6.06))`
5. **Parede Lateral Direita (+X):** `AABB(Vector3(1.06, 0.14, -3.03), Vector3(0.16, 2.31, 6.06))`
6. **Folha da Porta Esquerda Aberta:** `AABB(Vector3(-1.66, 0.14, 3.03), Vector3(0.56, 2.31, 1.08))`
7. **Folha da Porta Direita Aberta:** `AABB(Vector3(1.10, 0.14, 3.03), Vector3(0.56, 2.31, 1.08))`

- **Métodos Auxiliares de Navegação:**
  - `get_interior_bounds() -> AABB`: Retorna `(2.12, 2.29, 5.86)m` para posicionamento de itens internos.
  - `get_entrance_bounds() -> AABB`: Retorna o pórtico de passagem de `2.12m` de largura livre.

---

## 4. Otimização de Malhas por Agrupamento de Material (`PortMeshOptimizer`)

Nas cenas de composição onde múltiplos modelos estão presentes, instanciar centenas de nós `MeshInstance3D` individuais gerava centenas de draw calls desnecessárias. O `PortMeshOptimizer` percorre a árvore do nó e funde as primitivas num único `ArrayMesh` por material:

### Benchmark Real de Otimização (Antes vs. Depois)

| Composição | Dimensões Reais (\(L \times A \times P\)) | Malhas Antes (Original) | Lotes Depois (Otimizado) | Redução de Draw Calls |
|---|---|---|---|---|
| **Área de Carga e Estivação** (`PortCargoStagingArea3D`) | \(15.22 \times 5.48 \times 9.70\text{ m}\) | **618 meshes** | **27 lotes** | **-95.6%** |
| **Depósito Portuário** (`PortStorageDepot3D`) | \(8.20 \times 1.20 \times 6.00\text{ m}\) | **467 meshes** | **20 lotes** | **-95.7%** |
| **Canto de Manutenção Naval** (`PortMaintenanceCorner3D`) | \(6.00 \times 2.59 \times 7.15\text{ m}\) | **204 meshes** | **21 lotes** | **-89.7%** |
| **TOTAL CONSOLIDADO** | — | **1.289 meshes** | **68 lotes** | **-94.7%** |

*Nota:* O agrupamento pode ser ativado ou desativado via `@export var optimize_batch: bool = true` em cada composição.

---

## 5. Demonstração Prática de Integração (Guia para Astra)

### Exemplo 1: Instanciando o Contêiner Aberto e Gerando Colisores com Circulação

```gdscript
extends Node3D

func spawn_open_depot(world_pos: Vector3) -> void:
    var container := PortContainerOpen3D.new()
    container.position = world_pos
    add_child(container)

    # Gerar corpo estático com passagem livre garantida
    var static_body := StaticBody3D.new()
    static_body.position = world_pos
    
    for aabb in container.get_obstacle_bounds():
        var col := CollisionShape3D.new()
        var box := BoxShape3D.new()
        box.size = aabb.size
        col.shape = box
        col.position = aabb.position + aabb.size * 0.5
        static_body.add_child(col)
        
    add_child(static_body)

    # Opcional: Popular itens no interior usando o volume seguro
    var interior_box := container.get_interior_bounds()
    var safe_spot := world_pos + interior_box.position + Vector3(interior_box.size.x * 0.5, 0.0, interior_box.size.z * 0.5)
    # Dante e pedestres entram e saem sem qualquer obstrução!
```

### Exemplo 2: Instanciando uma Composição Completa de Alto Desempenho

```gdscript
func spawn_cargo_area(pier_position: Vector3) -> void:
    var staging := PortCargoStagingArea3D.new()
    staging.position = pier_position
    staging.optimize_batch = true # Mantém os 27 lotes agrupados em vez de 618 meshes
    add_child(staging)

    # Registro de colisão perimetral no mapa
    var static_body := StaticBody3D.new()
    static_body.position = pier_position
    for aabb in staging.get_obstacle_bounds():
        var col := CollisionShape3D.new()
        var box := BoxShape3D.new()
        box.size = aabb.size
        col.shape = box
        col.position = aabb.position + aabb.size * 0.5
        static_body.add_child(col)
    add_child(static_body)
```

---

## 6. Verificação Automatizada e Capturas Vulkan Forward+

Para executar os testes e re-renderizar todas as capturas com verificação de integridade:

```powershell
& "D:\Downloads Chrome\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --script res://prototypes/harbor_art_pack/test_harbor_art_pack.gd
```

O script `test_harbor_art_pack.gd`:
- Valida o manequim de 1,80 m com precisão de float.
- Dispara raios de teste geométricos confirmando que o vão de 2,12m e os 6 pontos do corredor central do contêiner aberto estão desimpedidos.
- Confirma que as superfícies de paredes e portas sólidas colidem.
- Compara a contagem de malhas das composições e confirma redução de mais de 89% em todas.
- Captura os 6 ângulos em resolução 1920x1080 com checagem estrita de retorno de código `OK` na gravação em disco.
