# Prévia de tutorial — dicas contextuais discretas (2026-09-08)

Baseado em `prototypes/loadout/index.html` (prévia interativa da Astra, sem
integração ao save real). Este diretório é um apresentador Godot isolado
para as dicas contextuais descritas ali — **sem** integração ao jogo real,
ao save, ao HUD real ou a qualquer outro sistema. A Astra decide a
integração e a persistência depois.

## Arquivos

- `TutorialHintCatalog.gd` — catálogo estático PT/EN dos 7 contextos
  pedidos: `first_trunk` (primeiro porta-malas), `loadout_capacity`
  (capacidade do loadout), `cold_shelter` (abrigo do frio), `thermal_shop`
  (loja térmica), `tunnel` (túnel), `rare_item` (item raro),
  `police_search` (busca policial fora de uma casa). Textos curtos.
- `TutorialHintPresenter.gd` — `class_name TutorialHintPresenter extends
  CanvasLayer`. A API pública pedida:
  - `request_hint(id: String) -> bool`
  - `dismiss_hint() -> void`
  - `reset_preview() -> void`

  Mais configuração recebida do chamador (nada fixo no arquivo):
  `set_dismiss_action(action_name)`, `set_hint_duration(seconds)`,
  `set_locale("pt"|"en")`, e os três estados de bloqueio informados por
  quem integra: `set_modal_active(bool)`, `set_combat_active(bool)`,
  `set_fast_driving_active(bool)`. Getters de consulta:
  `is_showing()`, `get_active_hint_id()`, `get_pending_hints()`,
  `has_seen(id)`, `is_blocked()`. Sinais: `hint_shown`, `hint_dismissed`,
  `hint_queued`, `hint_rejected`.
- `TutorialHintDemo.gd` — demonstração independente (`extends SceneTree`),
  roda sozinha fora do jogo, exercita fila/bloqueio/dispensa/repetição ao
  vivo e tira screenshots reais da UI (ver os PNGs abaixo).
- `capture_hint_shown.png`, `capture_blocked_queue.png`,
  `capture_next_after_unblock.png` — screenshots reais capturados rodando
  a demo (ver "Execução" abaixo).

O teste automatizado fica em `tests/test_tutorial_preview.gd` (fora deste
diretório, pedido assim explicitamente).

## Regras implementadas

- **Uma dica por vez**: pedidos que chegam com outra dica ativa (ou
  enquanto bloqueado) entram numa fila FIFO e aparecem na vez certa.
- **Sem repetição na sessão**: uma vez mostrada (inclusive se expirar
  sozinha por tempo), a mesma id nunca mais aparece até `reset_preview()`.
- **Duração limitada**: cada dica soma um `Timer` interno configurável via
  `set_hint_duration()`; expira sozinha se não for dispensada antes.
- **Tecla de dispensar configurável**: `set_dismiss_action(action_name)`
  recebe o nome de uma action já registrada no InputMap de quem integra —
  nenhuma tecla é fixada ou inventada aqui. Se a action não existir no
  InputMap, a dispensa por teclado simplesmente não ocorre (sem erro); o
  botão "×" na UI e `dismiss_hint()` continuam funcionando sempre.
- **Nunca interrompe o jogo**: `CanvasLayer` com um painel pequeno no canto
  inferior esquerdo, `mouse_filter = MOUSE_FILTER_IGNORE` na área não
  clicável, sem pausar a árvore, sem roubar foco.
- **Modal / combate / direção veloz**: não são inferidos por este arquivo
  — o chamador informa via `set_modal_active()`, `set_combat_active()`,
  `set_fast_driving_active()`. Enquanto qualquer um estiver `true`, nenhuma
  dica nova aparece (fica na fila); assim que todos voltarem a `false`, a
  próxima da fila aparece sozinha.

## Uso sugerido (para a integração futura da Astra)

```gdscript
const PRESENTER := preload("res://ui/tutorial_preview/TutorialHintPresenter.gd")

var hints: TutorialHintPresenter

func _ready() -> void:
    hints = PRESENTER.new()
    hints.set_locale(SettingsManager.current_locale) # exemplo -- não integrado aqui
    hints.set_dismiss_action("ui_cancel")             # ou uma action real do jogo, já existente
    hints.set_hint_duration(8.0)
    add_child(hints)

func _process(_delta: float) -> void:
    hints.set_combat_active(player.is_in_combat())
    hints.set_fast_driving_active(player.is_driving_fast())
    hints.set_modal_active(pause_menu.visible or settings_menu.visible)

func _on_player_opened_trunk_first_time() -> void:
    hints.request_hint("first_trunk")
```

## Execução

Godot 4.7.2, `D:/Downloads Chrome/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe`.

```bash
# Testes lógicos (headless, sem renderer): fila, bloqueio, dispensa, repetição, catálogo PT/EN.
Godot_v4.7.2-stable_win64_console.exe --headless --path "D:/geteco/game" --script "res://tests/test_tutorial_preview.gd"
# -> TUTORIAL_PREVIEW_TEST failures=0 (60 verificações, todas ok)

# Demonstração independente com renderer real, gera os 3 PNGs deste diretório.
Godot_v4.7.2-stable_win64_console.exe --path "D:/geteco/game" --script "res://ui/tutorial_preview/TutorialHintDemo.gd"
# -> DEMO_TUTORIAL_PREVIEW done (rodou com Vulkan/NVIDIA real, não software)
```

**Nota de honestidade**: não integrei nem toquei em nenhum sistema real do
jogo (Player, save, HUD, menus, MountainExpedition, áudio, trânsito,
pontes, streaming, `prototypes/loadout/`) — este é um módulo isolado,
validado sozinho. Não afirmo ter testado a experiência dentro do jogo real
com o mundo/HUD verdadeiros.
