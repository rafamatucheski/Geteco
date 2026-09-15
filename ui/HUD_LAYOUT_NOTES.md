# Atualização: HUD clássico (2026-09-13)

Revisão solicitada: botão do diário removido do HUD (atalho J preservado).
Conquistas no topo central, y=28 e largura máxima de 440 px; texto centralizado.
A vinheta de missão é original e sintetizada, com quatro segundos, melodia e
ritmo próprios (`v5-original`). A inclusão equivocada da gravação de GTA foi
desfeita. Evidências visuais na subpasta `v2`; áudio e origem em `v5-original`.

Esta revisão substitui os layouts históricos abaixo. Relógio/clima, arma/munição,
vida vermelha, colete claro, dinheiro verde e procurado ficam no canto superior
direito. O minimapa tem área útil quadrada de 208 × 208 px, com borda preta;
objetivos e rotas continuam sendo alimentados pelos controladores existentes.
Não há descrição permanente de missão na lateral. O diário mantém os detalhes.

`HUD._layout_classic_status()` monta os controles existentes em
`RootMargin/TopRightPanel/Status` depois de resolver as referências `@onready`.
Consumidores devem usar `health_bar`, `armor_bar` e `weapon_row`, e não o antigo
caminho de `TopLeftPanel`. A temperatura corporal agora é um vital de 120 × 12
px anexado por `HUD.attach_vital_indicator()`, imediatamente abaixo do colete;
mostra somente floco, barra fina e porcentagem. A coluna esquerda fica livre
para avisos contextuais da expedição desde y=24.

Conclusões da primeira entrega e da campanha chamam `show_mission_passed` com
dinheiro efetivamente concedido e o aumento real de reputação civil. A faixa
central dourada dura cerca de seis segundos, responde ao tamanho da tela e
continua animando durante os diálogos de conclusão. Não concede recompensas,
não dispara em carregamento e não substitui a lógica de pagamento único.
O contorno é preservado pelo tema com `preserve_hud_ink`.

Validação dirigida: `tests/test_classic_mission_hud.gd` e
`tests/test_reward_audio.gd`. Evidências em `D:/geteco/artifacts/sa-hud-0913`.
Desempenho sem certificação: o baseline foi interrompido ao detectar outra
medição renderizada concorrente. As capturas não são um benchmark.

# Histórico: vida e arma discretas (2026-09-11)

O bloco superior esquerdo usa vida de 144 × 6 px e armadura de 144 × 4 px, sem ícones nem molduras. Armadura aparece somente enquanto há proteção. Sem arma equipada, o bloco da arma desaparece; com faca, aparece somente a imagem; armas de fogo mostram carregador/reserva em 14 px abaixo da imagem. O shader local do HUD oculta a moldura incorporada à arte compartilhada. `GameplayPresentation` continua posicionando frio/altitude pela altura real de `TopLeftPanel`, inclusive quando arma ou armadura aparecem e desaparecem.

# Atualização: objetivo discreto (2026-09-11)

Os dois objetivos usam uma faixa de 320 px, sem cabeçalho visível, com texto de 15 px, margens de 6 px na vertical e fundo translúcido. Um traço de 2 px substitui a moldura. `GameStyle.objective_strip()` centraliza o estilo; `preserve_panel_style` impede que a aplicação do tema restaure o card opaco e as margens grandes. O texto completo continua quebrando linhas e respeitando a escala de acessibilidade. A posição na coluna direita e a ocultação durante modais permanecem coordenadas pelos controladores existentes.

# Atualização: objetivo na coluna direita (2026-09-10)

O objetivo de chegada e o da campanha ficam a 24 px da borda direita, abaixo do dinheiro/relógio, diário e conquistas visíveis. GameplayPresentation ajusta o topo pelo tamanho real desses elementos. No modo touch, o minimapa fica abaixo do objetivo. Frio e altitude continuam na esquerda e não dependem mais da altura do objetivo. As notas abaixo registram o layout anterior.

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
