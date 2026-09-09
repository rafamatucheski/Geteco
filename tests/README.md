# tests/

Não há framework de teste externo. Cada arquivo é um script `SceneTree` independente,
executado via `--script`, que imprime seu resultado e sai com código 0 ou 1:

```bash
GODOT="D:/Downloads Chrome/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
"$GODOT" --path . --script res://tests/test_menu_flow_integration.gd
```

Por isso os arquivos daqui aparecem como "sem referência" numa varredura de uso: eles são
pontos de entrada, chamados pela linha de comando, não importados por outro script.

## Os três tipos de arquivo aqui

| prefixo | o que é |
|---|---|
| `test_*` | **Regressão.** Afirma um comportamento e falha se ele quebrar. É o que rodar depois de mudar código. |
| `capture_*`, `render_*` | **Captura de imagem.** Carrega uma cena, posiciona a câmera e salva um `.png` na própria pasta. Serve para inspeção visual, não afirma nada. Os `.png` aqui são saída desses scripts. |
| `audit_*`, `profile_*`, `measure_*`, `diagnose_*`, `inspect_*` | **Investigação pontual.** Escritos para responder uma pergunta específica numa data específica. Podem estar desatualizados; leia o cabeçalho antes de confiar. |

`claude_gameplay_audit/` é uma suíte de auditoria de fluxo de jogo com seu próprio
`run_all.ps1`, capturas e logs.

## Suíte mínima depois de mudança estrutural

```bash
"$GODOT" --path . --script res://tests/profile_load_time_0909.gd       # carrega o jogo: errors=0 / issues=0
"$GODOT" --path . --script res://tests/test_menu_flow_integration.gd   # save/load + troca de cena
"$GODOT" --path . --script res://tests/test_opening_cutscene_runtime.gd
"$GODOT" --path . --script res://tests/test_pedestrian_life_routines.gd
"$GODOT" --path . --script res://tests/test_pedestrian_render_lod.gd
```

## Cuidados

- **Não use `--headless` para medir performance.** O driver de renderização dummy torna
  FPS, draw calls e custo de GPU sem significado.
- **A cutscene de chegada pausa a árvore.** `HarborArrivalMission._begin_arrival()` faz
  `get_tree().paused = true`. Teste que carrega `HarborGame.tscn` e não chama
  `campaign_controller.skip_cinematic()` vê todo despacho de emergência retornar `null`,
  porque `request_dispatch()` checa `can_process()`. Isso já produziu um "bug" que era
  só o teste.
- **Suíte verde não prova que o jogo está correto.** Vários defeitos reais desta base
  apareceram em partida de verdade com a suíte aprovada.
