# Integração ao Jogo Principal — Percurso Rodoviária → Delegacia → Garagem do Maciota (Geteco V2)

Documentação técnica de conexão, ciclo de vida, cadeia de instanciação e verificação física do componente `HarborRouteDetail3D`.

---

## 1. Responsável pelo Carregamento Regional e Ponto Real de Chamada

O carregamento regional de Harbor é gerenciado pelo nó de terreno e streaming nativo:
- **Arquivo responsável**: `geteco_v2/world/regions/NativeRegion.gd`
- **Fábrica de interface**: `geteco_v2/world/harbor_route_detail/HarborRouteDetailFactory.gd`

### Cadeia de Instanciação Completa desde a Cena Principal:

```
[Início do Jogo / Carregamento de Save]
   │
   ▼
1. ProductionWorld.build()  (ou ProductionWorld.travel("harbor"))
   │
   ▼
2. region = REGION.build_region("harbor")  -> Instancia NativeRegion.gd
   │
   ▼
3. NativeRegion._ready() -> NativeRegion._prepare()
   │  Registra os records espaciais em if region_id == "harbor":
   │  HARBOR_ROUTE_FACTORY.get_zone_records()
   │  - Cell (1, 1): "rodoviaria" (106.25, 0, 70.625)
   │  - Cell (1, 1): "connecting_streets" (86.8, 0, 94.0)
   │  - Cell (1, 2): "delegacia" (67.5, 0, 132.5)
   │  - Cell (0, 1): "maciota" (46.875, 0, 101.7375)
   │
   ▼
4. NativeRegion.set_focus(player.position)  (ou atualização por proximidade)
   │  Calcula as células 64m x 64m no raio de 2 células ao redor do jogador.
   │
   ▼
5. NativeRegion._build_chunk(key) -> NativeRegion._populate_chunk()
   │  Para cada record do tipo "harbor_route_zone":
   │  HARBOR_ROUTE_FACTORY.populate_zone_chunk(chunk, record.zone_id)
   │
   ▼
6. HarborRouteDetailFactory.mount_zone(chunk, zone_id)
   │  - create_zone(zone_id) invoca HarborRouteDetail3D.build_zone(zone_id).
   │  - Constrói diretamente um Node3D independente ("Zone_" + zone_id) sem contêiner intermediário.
   │  - chunk.add_child(zone) anexa a zona como filha direta de Chunk_<x>_<y>.
```

---

## 2. Ciclo de Vida, Descarregamento e Propriedade dos Nós

A arquitetura de nós foi revisada para eliminar qualquer intermediário órfão ou erro de duplo parentesco:

1. **Propriedade Direta e Ausência de Contêiner Órfão**:
   - `HarborRouteDetail3D.build_zone(zone_id)` é estático e constrói a raiz da zona com seus filhos (calçadas, rampas, postes, balizadores). O nó retornado não possui pai (`parent == null`).
   - `HarborRouteDetailFactory.mount_zone(chunk, zone_id)` recebe esse nó desanexado e chama `chunk.add_child(zone)`. O chunk assume a posse direta da zona. Nenhum contêiner `HarborRouteDetail3D` é alocado durante o streaming, eliminando contêineres órfãos na memória.
   - Em `HarborRouteDetail3D`, a variável `@export var auto_mount_all: bool = false` e a trava `if auto_mount_all and _mounted_zones.is_empty()` em `_ready()` asseguram que instanciar ou montar uma zona específica nunca acione a montagem acidental de todas as zonas.

2. **Descarregamento por Distância (Streaming Dinâmico)**:
   - Em `NativeRegion.set_focus()`, quando a célula sai do raio de proximidade (`absi(key.x - cell.x) > 2 or absi(key.y - cell.y) > 2`):
     ```gdscript
     chunks[key].queue_free()
     chunks.erase(key)
     ```
   - O comando `queue_free()` no nó do chunk propaga o agendamento de exclusão pela árvore do Godot, cobrindo os nós das zonas anexadas e seus nós filhos (`StaticBody3D`, `CollisionShape3D`, `MeshInstance3D`).

3. **Troca de Região (Viagem Harbor ↔ Mountain)**:
   - Em `ProductionWorld.travel("mountain")`, a região anterior é liberada sincronicamente:
     ```gdscript
     region.free()
     region = REGION.build_region(region_id)
     ```
   - A chamada `free()` destrói a árvore de `NativeRegion` e todos os nós de chunks sob ela. Ao retornar a Harbor via `travel("harbor")`, um novo `NativeRegion` é instanciado e repopulado a partir do catálogo.

4. **Recarga de Cena / Restauração de Save**:
   - `ProductionWorld.build()` reconstrói o nó do mundo, recriando a instância de `NativeRegion` e montando apenas as células próximas ao ponto inicial de spawn (`exterior_return`).

> [!CAUTION]
> **Ressalva de Validação**: A inspeção estática do código confirma a estrutura de posse correta (`parent == chunk`, sem nós intermediários e sem duplo `add_child`). Entretanto, **a ausência de vazamento de memória ou de duplicação sob estresse não pode ser formalmente declarada sem evidência de profiling em runtime** (execução contínua, monitoramento de contagem de nós com `Performance.get_monitor(Performance.OBJECT_NODE_COUNT)` e verificação com `print_orphan_nodes()`).

---

## 3. Revisão dos Acessos Físicos e Correção de Defeitos Concretos

A geometria de todas as zonas foi confrontada diretamente contra os volumes de colisão, scripts de missão, trajetórias de atores e limites de células de streaming.

### 3.1 Rodoviária (`ZONE_RODOVIARIA`) — Trajetória de Desembarque de Dante
- **Confronto com `Arrival.gd` e `Actor.gd`**:
  - Em `Arrival.gd:124-142`, o ônibus `route_city` para em `Vector3(106.25, 1.0, 78.125)` virado para `-X`. A porta abre em `(108.56, 1.05, 76.31)`.
  - Dante desloca-se em linha reta ao longo de `X = 108.56` até `Z = 70.625`, e em seguida até `ARRIVAL = (106.25, 0.06, 70.625)`.
  - A cápsula de Dante (`Actor.gd:35-37`) possui **raio de 0,30m**, estendendo seu casco físico para a faixa `X ∈ [108.26, 108.86]`.
- **Defeito Identificado**:
  - A rampa lateral `side_ramp_e` situava-se em `X = 109.0`, com a base inclinada projetando-se até `X = 108.65`. A cápsula de Dante colidia frontal e lateralmente com a cunha (invasão de 21cm), gerando risco de emperramento (`stalled > 2s` que cancela o desembarque em `Arrival.gd:294`).
  - Além disso, a pista de `market_street` gerada por `NativeRegion.gd:205` possui cota de topo `Y = 0.05m`. O piso da passagem anterior a `Y = 0.012m` criava um desnível vertical de 3,8cm.
- **Correção Aplicada**:
  - O início da Ala Leste (`curb_e`, `slab_e`, `side_ramp_e`) foi recuado para `X = 110.5`. A rampa `side_ramp_e` inicia agora em `X = 110.15`, garantindo **1,29 metro de folga livre** em relação ao flanco direito da cápsula de Dante (`X = 108.86`).
  - A passagem central nivelada foi ampliada de 5,5m para **7,00m de vão útil** (`X: 103.5 a 110.5`), com cota de piso nivelada em `Y = 0.05m`, em continuidade exata com o topo da caixa de asfalto de `market_street`.

### 3.2 Esquina Market St / Union Ave (`ZONE_CONNECTING_STREETS`) — Conflito de Colisores
- **Confronto Geométrico**:
  - A rampa pedonal de esquina `ramp_market` situa-se em `X = 83.0, Z = 74.55` com vão de 2,2m (`X: 81.9 a 84.1`).
  - O meio-fio `curb_market` estava instanciado com 9,0m centrado em `X = 87.5`, cobrindo `X: 83.0 a 92.0`.
- **Defeito Identificado**:
  - No intervalo `X ∈ [83.0, 84.1]` (1,10 metro de extensão), o colisor de caixa sólida do meio-fio vertical de 14cm estava **sobreposto** ao colisor de cunha da rampa chanfrada de 12cm.
- **Correção Aplicada**:
  - `curb_market` foi recortado para começar exatamente após a rampa em `X = 84.1` (extensão 7,9m, centro `X = 88.05`), eliminando a sobreposição de corpos físicos.

### 3.3 Delegacia (`ZONE_DELEGACIA`) — Acesso e Desobstrução
- **Confronto com `PlaceCatalog.gd` e `FullSession.gd`**:
  - Porta de entrada: `(67.5, 0.10, 132.5)`. Ponto de retorno ao sair do interior: `return_point = (67.5, 0.0, 133.5)`.
  - Em `FullSession.gd:443`, a saída verifica `position_clear(return_point + Vector3.UP * 0.08)`. A query utiliza uma cápsula com base em `Y = 0.13m` e um raio de solo até `Y = -0.42m`.
  - A esplanada a `Y = 0.10m` é detectada como piso pelo raio sem colidir com a base da cápsula (folga de 3cm).
- **Defeito Identificado**:
  - A grade de bueiro `drain` estava posicionada no centro do vão da rampa em `(67.5, 0.0, 134.8)`.
- **Correção Aplicada**:
  - O ralo foi deslocado para a calha junto ao meio-fio lateral em `(63.5, 0.0, 134.4)`, deixando o corredor central de pedestres de 6,0m totalmente livre. Os balizadores preservam 8,00m de vão livre frontal.

### 3.4 Garagem do Maciota (`ZONE_MACIOTA`) — Parada do Tour e Acesso Veicular
- **Confronto com `Arrival.gd`, `ArrivalCar.gd` e `GarageFacade.gd`**:
  - Em `Arrival.gd:218`, o cupê M8 (largura 2,10m, comprimento 5,0m) finaliza o tour da cidade estacionando em `Vector3(42.5, 0.0, 104.55)` alinhado a `-X`. Seu casco ocupa a caixa `X ∈ [40.0, 45.0]`, `Z ∈ [103.5, 105.6]`.
  - A fachada do edifício (`GarageFacade.gd`) fica na coordenada `Z = 101.25`.
- **Defeitos Identificados**:
  - O balizador `bollard_w` (`X = 42.5, Z = 104.5`) e o meio-fio `curb_w` (`X: 39.5 a 43.0, Z = 105.0`) estavam posicionados **diretamente dentro do casco de parada do veículo**. A viatura colidia com o balizador e montava no meio-fio vertical de 10cm.
  - O poste de iluminação `ind_light` (`X = 41.2, Z = 103.5`) ficava rente à lateral do cupê.
  - O piso `slab` começava em `Z = 101.5`, deixando uma fresta de 25cm de chão aberto contra a parede da fachada (`Z = 101.25`).
- **Correções Aplicadas**:
  - O balizador `bollard_w` foi **removido**. O meio-fio `curb_w` foi removido.
  - A rampa chanfrada de acesso veicular foi estendida de 7,8m para **11,30 metros de largura útil** (`X: 39.5 a 50.8`, centro `45.15`), cobrindo tanto a baia mecânica quanto toda a vaga de parada do tour com rampa suave de 5,7°.
  - O poste `ind_light` foi deslocado para a quina do quarteirão em `(38.5, 0.08, 102.5)`, fora do volume do carro.
  - O piso `slab` foi expandido para cobrir de `Z = 101.25` até `Z = 104.6` (profundidade 3,35m), encostando perfeitamente na parede da fachada.

---

## 4. Retenção de Streaming nos Limites das Células

Verificou-se a posição de cada registro contra a malha de streaming (`CELL = 64.0m`):
- `ZONE_RODOVIARIA`: Célula `(1, 1)` [X: 64-128, Z: 64-128]. Ônibus, descida e caminhada ocorrem integralmente dentro da célula `(1, 1)`.
- `ZONE_CONNECTING_STREETS`: Célula `(1, 1)`. As calçadas e meio-fios de Union Ave estendem-se até `Z = 127.0`, contidos na célula `(1, 1)`.
- `ZONE_DELEGACIA`: Registrada na célula `(1, 2)`. Elementos da ala oeste estendem-se entre `X = 59.0` e `64.0` (célula `(0, 2)`). Como o streaming de `NativeRegion.set_focus()` carrega um bloco 3x3 no raio `[-1, 1]`, a célula `(1, 2)` permanece ativada enquanto o jogador estiver em `(0, 2)` (distância euclidiana = 1 <= 2).
- `ZONE_MACIOTA`: Registrada na célula `(0, 1)` [X: 0-64, Z: 64-128]. Toda a cenografia (`X: 38.5 a 57.0`, `Z: 101.25 a 105.4`) está contida na célula `(0, 1)`.

---

## 5. Limitações e Registro de Pendências de Execução

> [!IMPORTANT]
> **Distinção Crítica**: As correções acima baseiam-se em **evidência geométrica estática rigorosa** (confronto dimensional de scripts, coordenadas de transformações e eliminação de sobreposições de malhas/colisores). Nenhuma validação em execução foi declarada como aprovada.

Itens pendentes de validação com motor Godot em tempo de execução:
1. **Passagem física dinâmica do `CharacterBody3D`**: Execução do método `Arrival._walk()` sobre o corredor de desembarque de 7,0m e verificação de que `stalled` não ultrapassa 2 segundos.
2. **Dinâmica de Suspensão Veicular**: Resposta de amortecimento e física de rodas do cupê M8 ao percorrer a rampa alargada de 11,3m e parar em `(42.5, 0, 104.55)`.
3. **Teste de Saída de Interior**: Execução de `FullSession.leave_place()` na porta da delegacia e garagem, confirmando o sucesso de `position_clear()` no primeiro tick.
4. **Profiling de Memória e Nós Órfãos**: Monitoramento com `Performance.get_monitor(OBJECT_NODE_COUNT)` e `print_orphan_nodes()` durante ciclos de afastamento (>128m), troca de região (Harbor ↔ Mountain) e restauração de saves.
