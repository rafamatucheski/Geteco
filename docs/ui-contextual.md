# UI contextual — migração de 28/09/2026

Implementação de produção em Godot. A HUD não escreve nos estados de combate,
economia, progressão ou sobrevivência. A interface usa as operações já existentes
para equipar armas/roupas, consumir itens, mover bagagem e abrir/fechar menus.

## Mapa de dependências e migração

| Antes | Implementação atual | Fonte dos dados |
| --- | --- | --- |
| `ClassicGameplayHUD.gd`, `GameplayHUD.gd` | Ambos preservam o caminho de recurso e delegam a `hud/ContextualHUDManager.gd`. Só uma HUD é montada por `World.gd`. | `FullSession`, `GameState`, `Gameplay`, `Driving` |
| Status combinado junto ao mapa | `hud/PlayerStatusHUD.gd`, `MoneyHUD.gd`, `WeaponHUD.gd` | Vida/colete do combate, saldo e munição da economia, `ColdSurvival.status()` |
| Objetivo persistente e avisos | `hud/NotificationUI.gd` | Textos e duração das fontes existentes; objetivo visível apenas na atualização |
| Prompt fixo inferior | `hud/InteractionPrompt.gd` | Ação existente, projeção junto ao jogador, `GameInput.prompt()` |
| Minimap com relógio e distância | `v1/HarborMinimap3D.gd` + `hud/Cartography.gd` | Ruas reais, grafo de navegação e destino existente |
| Mapa estático dentro de um menu | `hud/MapUI.gd`, via `v2/WorldMap.gd` | Rotas e entradas da região, objetivo da sessão |
| Duas implementações de inventário por herança | `InventoryPanel.gd` + `InventoryViewState.gd`; caminho `FieldInventory.gd` preservado como alias | `FieldInventoryRuntime`, `GridInventory`, `Economy` |
| Cores locais em menus | `GameStyle.gd`, consumido por `MenuTheme`, HUD, inventário, configurações e apresentação do menu inicial | Tokens únicos, fontes Barlow, StyleBoxes |

`FullSession` e `Driving` conservam os Labels usados como fontes de compatibilidade;
o gerenciador esconde essas fontes. Remover esses nós quebraria referências dos
sistemas existentes. Eles não representam uma segunda HUD visível.

As cópias integrais dos arquivos anteriores estão em
`evidence/ui-refactor-20260928/source-before/`, como texto não executável. Os pontos
de entrada antigos de captura e benchmark delegam aos novos validadores, evitando
manter uma segunda implementação para comparação.

## Comportamento

- Vida e colete: canto superior esquerdo, ícones e barras interpoladas, sem números.
- Frio: terceira barra somente durante exposição/temperatura reduzida, com retirada
  suave após normalização. O mesmo modelo continua determinando perda/recuperação.
- Dinheiro: pequeno contador superior direito; diferença visível por 1,5 segundo.
- Arma: silhueta creme e carregador/reserva no canto inferior direito. Carrossel
  apenas durante a troca, por 1 segundo. Os controles existentes foram mantidos.
- Mochila: botão independente e atalho do dispositivo ativo. Painel central com
  rolagem quando necessário, slots cinza, seleção dourada, quantidades e seção de
  roupas. Detalhes aparecem mediante seleção. Porta-malas conserva restrições.
- Roupas: itens possuídos no catálogo existente, proteção em três indicadores e
  equipamento pelo método existente, atualizando `Actor.set_outfit()`.
- Minimap: superfície arredondada de 188 px, norte, jogador ciano, ruas e destino
  dourado; sem relógio, temperatura, distância ou coleção de ícones de entradas.
- Mapa: tela inteira, arraste/analógico, zoom suave, seleção de marcador e painel
  lateral contextual. Linhas cartográficas são textura visual, sem cotas altimétricas.
- Rádio: permanece acessível pelos controles existentes no veículo; só mostra o
  nome da estação brevemente após interação, com o mesmo tema. Nenhum botão fixo.
- Polícia e velocidade: informações funcionais preservadas quando aplicáveis.
- Pausa, resgate, prisão e menus ocultam a HUD. Garagem mantém armas guardadas e
  bloqueadas, inclusive no primeiro frame da transição.

`GameInput` continua sendo o único detector de dispositivo. `prompt()` escolhe uma
única indicação a partir de suas vinculações; `hint()` mantém as alternativas para
a tela de configurações. O direcional esquerdo abre a mochila no controle, que
antes não tinha essa ação vinculada. Interagir continua usando o botão já
configurado (X no padrão Xbox), sem remapeamento da jogabilidade para A.

As roupas existentes reduzem a perda térmica conforme `ThermalState.PROTECTION`;
nenhuma delas passou a dar imunidade ao frio. Isso preserva a exigência de não
alterar mecânicas existentes. A UI não simula uma temperatura estável falsa.

## Verificação

Aceitação integrada: `tests/test_contextual_ui.gd`, com `--no-save --skip-arrival`.
Capturas em `evidence/ui-refactor-20260928/acceptance/`. Testa proporções 16:9,
16:10 e 21:9, carteira, troca de arma, temporização, frio, prompts/remapeamento,
mochila, roupa, mapa, modais e garagem. Eventos de controle são injetados no motor;
isso não substitui teste manual em hardware Xbox/PlayStation.

Regressões existentes cobrem arsenais, roda do mouse/rádio, grid, consumo e bagagem,
configurações, foco/aceitação de modais, frio e transições/restauração da garagem.
`test_compact_hud.gd` conserva as verificações de navegação/câmera e atualiza suas
expectativas visuais para o novo pedido.

## Performance

Meta provisória: 60 FPS / 16,67 ms. Sinal de regressão: aumento maior que 5% em
p95/p99 exige confirmação finita em ambiente comparável. Sem blur nem SubViewport
novo; estado da HUD é projetado a cada 80 ms, enquanto animações usam Tweens.
Ícones de arma compartilham texturas e as liberam ao sair o último consumidor.
Geografia do minimapa continua em cache; mapa aberto redesenha durante movimento
e em frequência limitada quando parado.

`tests/measure/measure_ui_refactor.gd`: cena Main real, mesma posição/clima/seed,
8 segundos de aquecimento + pelo menos 30 segundos por cenário (HUD, mochila,
mapa). Preserva frames brutos, percentis e capturas. Não usa saves pessoais.

Há processos Godot concorrentes e alterações simultâneas no projeto durante esta
atividade. O comparativo é diagnóstico; não certifica 60 FPS nem atribui mudanças
globais de desempenho exclusivamente à UI. Resultados finais e limitações ficam
no [relatório de evidências desta migração](../evidence/ui-refactor-20260928/REPORT.md).
