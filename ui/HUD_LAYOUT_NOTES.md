# HUD — coluna esquerda: contrato de layout (2026-09-08)

## Revisão de integração Astra

Entrega revisada com renderer Vulkan. Abertura natural + desembarque + telefone
testados em `tests/test_arrival_hud_regressions.gd`, sem remover camadas ou
forçar desbloqueio: o erro histórico do terminal não se reproduziu nesta versão.
O teste de layout agora inicia com flags pós-chegada e preserva seu teste
específico de ocultação da CGI simulada. `HUD.gd` posiciona conquistas abaixo
do tamanho real de `TopRightPanel` (inclui relógio); o tamanho vertical vem
do conteúdo mínimo, sem crescimento acumulado entre quadros. Ambos os cards
de objetivo de campanha usam fundo opaco. A pilha de frio/altitude abaixo
continua com o contrato original descrito neste documento.

Contexto: havia sobreposição entre o card de "objetivo da missão", o bloco
de temperatura/proteção térmica e o readout de altitude, todos empilhados
na coluna esquerda (x=24) sem coordenação entre os arquivos que os criam.
Corrigido reorganizando quem eu podia editar (UI/apresentação); o card de
objetivo pertence a scripts de missão que não editei — este documento é o
contrato para a Astra, caso ela precise ajustar algo lá.

## Pilha vertical atual (x = 24, viewport 1280×720 e maiores)

| Bloco | Arquivo | y (topo) | Altura observada | Editável por mim? |
|---|---|---|---|---|
| Vida / Armadura / Arma | `HUD.tscn` (`TopLeftPanel`) | 24 | ~112px (termina ~136) | sim |
| **Card "OBJETIVO ATUAL"** | `CobraCampaignBridge.gd` / `HarborArrivalMission.gd` | 150 | ~76-100px (texto quebra em 1-3 linhas) | **não** — script de missão |
| Temperatura / Proteção térmica | `ColdStatusHUD.gd` | 254 | 96px fixo (`BLOCK_TOP`) | sim (permitido: "HUD de frio") |
| Altitude | `MountainExpedition.gd` | `cold_hud.get_stack_bottom_offset()` (= 350 hoje) | ~34px | sim |
| Avisos temporários (frio/túnel/casaco/chefe) | `MountainExpedition.gd` | topo do readout + 40 (= 390 hoje) | ~34-70px, some quando vazio | sim |

Os dois últimos blocos só ficam visíveis dentro da região da montanha
(`mountain.cold_hud.visible` / `ContinuousWorld._mountain_layers`, ambos
inalterados por mim), então nunca competem com o card de objetivo fora
dali — mas quando o jogador ESTÁ na montanha, os três (objetivo, frio,
altitude) ficam visíveis ao mesmo tempo, daí a pilha acima.

## O contrato

`ColdStatusHUD.gd` expõe:

```gdscript
func get_stack_bottom_offset() -> float:
    return BLOCK_TOP + 96.0  # y logo abaixo do painel de temperatura
```

`MountainExpedition.gd` lê esse valor (com fallback para `350.0` caso
`mountain.cold_hud` ainda não exista na hora de montar sua própria UI — a
ordem de `_ready()` entre nós irmãos não é garantida) em vez de usar um
número mágico solto. Se a Astra alterar a altura do bloco de
`ColdStatusHUD`, `MountainExpedition` acompanha automaticamente.

## O que NÃO editei (e por quê)

O card "OBJETIVO ATUAL" (`CobraCampaignBridge.gd:364` e
`HarborArrivalMission.gd:456`, ambos `position = Vector2(24, 150)`,
`custom_minimum_size = Vector2(400, 0)`) é construído por scripts de
missão/campanha — fora do que fui autorizado a alterar nesta tarefa. Eu
**assumi** que ele nunca ultrapassa ~100px de altura (título ~16px +
objetivo com até 3 linhas quebradas a 16px + margens 16px) para calcular
`BLOCK_TOP = 254` em `ColdStatusHUD.gd` com uma margem de segurança de
~14px abaixo do pior caso observado no código.

**Se a Astra:**
- adicionar objetivos com texto muito mais longo (4+ linhas quebradas), o
  card pode ultrapassar y=254 e voltar a encostar no bloco de temperatura;
- ou preferir uma solução mais robusta (ex.: o card também expor um
  `get_bottom_offset()` e `ColdStatusHUD`/`MountainExpedition` lerem dele
  em vez de um `BLOCK_TOP` fixo, espelhando o padrão que já usei entre
  esses dois arquivos),

isso é livre para ela ajustar — os dois arquivos que editei já leem um
valor "de cima para baixo" (`get_stack_bottom_offset()`) em vez de posições
fixas duplicadas, então estender essa cadeia até o card de objetivo é uma
mudança pequena e localizada.

## Nenhum HUD por cima da CGI de abertura

Durante o teste, uma captura real mostrou o bloco de temperatura/altitude/
avisos renderizado **por cima da CGI de abertura** (Dante servindo café) —
a CGI usa uma `CanvasLayer` própria em `layer=100`
(`HarborArrivalMission.gd: _opening_layer`), e `ColdStatusHUD` (`layer=105`)
e o HUD do `MountainExpedition` (`layer=106`) renderizam depois dela, por
cima. Isso só é alcançável artificialmente (só é possível levar o jogador
para dentro da região da montanha enquanto a CGI ainda está de pé se algo
mais já estiver errado — na sessão em que isso apareceu, o handler de
finalização da CGI estava travando com um erro em `HarborArrivalStop.gd:90`,
um arquivo de missão fora do que fui autorizado a editar), mas o princípio
é válido independente da causa: nenhum HUD deve aparecer sobre a CGI.

Corrigido em `ColdStatusHUD.gd` e `MountainExpedition.gd` com um helper
`_is_cgi_playing()` que lê `ArrivalMission._opening_layer` (por
`get_node_or_null` + `.get()`, sem editar `HarborArrivalMission.gd`) e
esconde os respectivos painéis enquanto essa camada existir. Coberto por
teste (`tests/test_hud_layout_and_minimap_heading.gd`): simula uma CGI
ativa e confirma que os três painéis se escondem, depois reaparecem quando
ela "termina".

## Minimapa — contrato lido de Player.gd

`ui/HarborMinimap.gd` agora usa `actor.velocity` (Vector2, já público em
`Player.gd:796`, não alterado) para calcular o heading do pedestre no
minimapa, porque `Player.gd` mantém `rotation = 0.0` sempre (o modelo 3D
gira, não o nó 2D — ver `Player.gd:802`) e por isso `global_rotation` nunca
refletia a direção real de movimento a pé. Ao dirigir, o heading continua
vindo de `actor.global_rotation` do veículo (que gira de verdade). Abaixo
de 8px/s (bem abaixo dos 125px/s de caminhada base) o pedestre é tratado
como parado e o minimapa conserva o último heading em vez de saltar para
uma direção arbitrária.

Nenhuma propriedade nova foi pedida de `Player.gd` — `velocity` já era
lida por outros arquivos de UI (ex.: `ui/tutorial_preview/GameplayTutorials.gd`
já lia `car.velocity.length()` antes desta tarefa).
