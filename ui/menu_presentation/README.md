# Apresentação dos menus — Geteco V2

Entrega isolada, sem conexão com produção. Todos os arquivos desta entrega estão nesta pasta. Não foram alterados FullSession, GameInput, Settings, WorldMap, Main, project.godot ou os menus existentes. A raiz de recursos do V2 é `geteco_v2/`, não a raiz do jogo legado.

## Conteúdo e direção visual

| Arquivo | Uso |
| --- | --- |
| `MenuTheme.gd` | Fábrica de Theme local, reutilizável por outros Controls |
| `MenuPanel.gd` | Modal visual, título, corpo rolável, rodapé fixo e ciclo explícito de foco |
| `MenuAction.gd` | Button nativo com Label que quebra linhas e altura calculada |
| `MenuVolume.gd` | HSlider nativo de 0 a 1, passo 0,05, com rótulo original |
| `Demo.tscn` / `Demo.gd` | Galeria isolada das quatro apresentações |
| `preview.html` | Prancha visual responsiva; referência HTML, não captura do motor |
| `VALIDATION.md` | Revisão estática realizada e verificações pendentes |

Superfícies opacas azul-escuras (`#101923`, `#1c2a38`), texto claro (`#f4f1e8`), bordas discretas e foco âmbar de 3 px (`#f2bc75`). Hover, pressionado e desabilitado têm estados próprios. Não há blur, shader, SubViewport, animação, textura importada ou processamento por frame. O Theme herda a fonte do projeto V2 (Barlow); a galeria HTML usa fontes locais como aproximação.

Texto base 20, título 30, linhas acionáveis de no mínimo 52 e slider com área de 44 unidades lógicas. Painel central com largura máxima 760 e margens de 32 (16 abaixo de 700). O título quebra linhas; o corpo rola verticalmente; o rodapé permanece fora da rolagem. Nada reduz a fonte automaticamente para acomodar conteúdo. Usa o `canvas_items` já configurado no V2; não modifica escala global. Abaixo de 640×360 lógicos, o layout não tem garantia; ver matriz pendente.

## Demonstração (somente após coordenar com o integrador)

Abrir `geteco_v2/project.godot` e executar apenas `res://ui/menu_presentation/Demo.tscn` como cena atual. Não executar Main nem trocar a cena principal. Não foi executado nesta entrega.

A galeria navega entre as quatro páginas. Valores de inventário/configurações são amostras explícitas (R$ 0, PUNHOS, volume 0,8, tela cheia não, suavização 1), não leitura de um save. A missão mostra o primeiro objetivo real de Primeiro Giro, lido do catálogo. Controles são lidos de `GameInput.KEYS`, `label()` e `hint(action, true)`, com as mesmas exclusões de FullSession. Os botões de ação demonstram foco/pressionamento, mas não equipam, curam, cancelam missões, restauram controles ou remapeiam. O slider move apenas seu valor local. O aviso de demonstração permanece nas páginas.

A cena não instancia FullSession, mundo ou Main. **Os autoloads do projeto continuam sendo inicializados pelo motor**: Settings pode aplicar as preferências salvas da janela/áudio e GameInput carrega os bindings existentes. A demo não chama métodos de gravação, restauração ou alteração desses autoloads. Fechar demonstração encerra o processo de demonstração; não incorporar Demo à produção.

## Conexão pelo integrador

Preferir montar um MenuPanel dedicado somente para inventário, missões, configurações e controles. Não substituir `_menu()` globalmente: ele também atende diálogo, lojas, personalização, mapa e resgate, que estão fora do escopo.

1. Instanciar `preload("res://ui/menu_presentation/MenuPanel.gd").new()` uma vez sob o HUD/CanvasLayer do V2. O painel ocupa a área do pai, inicia oculto e usa `PROCESS_MODE_ALWAYS`.
2. Na abertura, manter exatamente os bloqueios existentes de jogador/veículo e `modal`/`dialogue_open`. O componente só apresenta a UI: não pausa nem desbloqueia o mundo.
3. Chamar `begin(titulo)`, adicionar as ações na ordem atual e finalizar com `finish()`. `begin` remove a lista anterior; `finish` deve ser chamado uma vez por montagem. Não adicionar ações depois de finalizar sem reconstruir a página.
4. Conectar `back_requested` uma única vez a um roteador do menu atual. Inventário, missões e configurações usam `close_menu`; controles retornam a configurações; captura de tecla cancela o remapeamento e retorna a controles. Ao fechar, executar `dismiss()` além da lógica original de fechamento.
5. Preservar callbacks e condições da tabela abaixo. Não transferir lógica de negócio para o Theme ou componentes.
6. Para reconstruções (tela cheia/suavização), passar a posição da ação anterior em `finish("Voltar", indice)` ou localizar novamente a ação por ID no adaptador. O índice é limitado ao intervalo válido. Para mudanças de página, usar foco inicial. `dismiss()` tenta restaurar o foco anterior se ainda existir e estiver visível.

Exemplo de montagem, para adaptação pelo integrador (não está conectado):

```gdscript
var view = preload("res://ui/menu_presentation/MenuPanel.gd").new()
world.hud.add_child(view)
# Conectar uma vez. O roteador deve respeitar a página e rebinding_action.
view.back_requested.connect(route_menu_back)

view.begin("Configurações")
view.add_volume(settings.master_volume, func(value):
    settings.master_volume = value
    settings.apply_settings()
    settings.save_settings())
view.add_action("Tela cheia: " + ("sim" if settings.fullscreen else "não"), toggle_fullscreen)
view.add_action("Suavização: %d" % settings.msaa, cycle_msaa)
view.add_action("Restaurar controles", restore_controls)
view.add_action("Configurar teclas", show_controls)
view.finish()
```

Os nomes `route_menu_back`, `toggle_fullscreen`, `cycle_msaa` e `restore_controls` representam callbacks do adaptador a serem ligados às closures atuais; não são novos métodos existentes em FullSession.

| Origem em FullSession | Contrato preservado na conexão |
| --- | --- |
| `show_inventory` | Título com saldo real; WEAPONS.ORDER filtrado por owns_weapon; label original; equipar fecha primeiro; primeiros socorros somente com estoque, heal(40), consumo condicionado e save; Configurações; Voltar |
| `show_journal` | Com missão ativa: objective() acionável para fechar e Cancelar missão ligado a cancel_mission (incluindo bloqueio do guincho). Sem missão ativa: somente available_missions(), títulos reais e guardas/callbacks atuais. Não inventar lista vazia, progresso, recompensas ou objetivos |
| `show_settings` | Volume 0–1/0,05, mesma aplicação e persistência; rótulos Tela cheia: sim/não, Suavização: número; restauração de bindings e mensagem existentes; Configurar teclas; Voltar. Não acrescentar VSync ou opções só porque Settings as possui |
| `show_controls` | KEYS na ordem atual, sem pause_game/inventory; label + ` · ` + hint(action,true). Preservar erros de conflito, teclas reservadas, gravação e flags de captura |
| Captura de tecla | `begin("Pressione uma tecla · Esc cancela")` e `finish("Cancelar")`; roteador cancela rebinding_action e controls.remapping. A camada visual não captura/remapeia teclas |

### Entrada e foco

Setas/cima-baixo, Tab/Shift+Tab e ações `ui_*` usam o sistema nativo do Godot; D-pad/analógico, A e B dependem dos bindings já configurados por GameInput. O painel não modifica InputMap. Esquerda/direita ficam no slider; os vizinhos de foco verticais e Tab formam um ciclo restrito à lista de controles habilitados e ao retorno. `follow_focus` mantém o controle selecionado na área rolável. Clique fora não fecha.

O painel emite `back_requested` para `ui_cancel` **não consumido**. FullSession já trata `pause_game`/Esc em `_input`, antes do GUI; o integrador deve centralizar esse caminho no roteador para evitar fechar uma página errada ou duplicar a ação. Durante captura de tecla, a lógica atual deve consumir o evento e cancelar corretamente as flags antes de redesenhar. Não deixar o cancelamento genérico vencer o remapeamento. O overlay bloqueia mouse, mas não bloqueia `_input` ou polling de gameplay: manter as guardas `modal` e os locks originais é obrigatório.

`MenuAction.configure` é para uma instância nova. Não editar `Button.text`: o conteúdo está em `caption.text`; reconstruir por `begin/add_action/finish` atualiza texto, medição e callbacks juntos. Sem callback válido, o botão fica desabilitado e fora do ciclo. Não usar isso para fingir funcionalidades que ainda não existem.

## Limites da entrega

Implementação e revisão estática concluídas; integração, importação/compilação Godot, renderização, navegação real, escala e performance **não validadas**. A prévia HTML não comprova o comportamento do Godot. O integrador precisa coordenar as execuções descritas em VALIDATION.md antes de adotar a apresentação em produção.
