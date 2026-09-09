# Convenções para agentes de IA neste repositório

Este projeto é trabalhado por **mais de um agente ao mesmo tempo** (Claude e Antigravity,
em sessões separadas) além do desenvolvedor no editor do Godot. As regras abaixo existem
para que trabalhos paralelos não se atropelem.

Leia primeiro o [README.md](README.md) para a estrutura de pastas, e
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) para o mapa técnico.

## Territórios

- **`prototypes/gameplay_repair_art_0909/`** é território do Antigravity. Não editar.
- **`OLD/`** é arquivo morto: tem `.gdignore`, o Godot ignora a pasta inteira. Nada ali é
  carregado pelo jogo. Só entra arquivo verificado como sem referência.
- **`legacy/`** é a geração anterior do jogo e **não tem `.gdignore`**:
  `legacy/Main.tscn` ainda é carregado em runtime para saves antigos
  (`HarborSceneRoute.for_save()`). Não é código morto. Ao mexer ali, rode
  `tests/test_legacy_save_route.gd`, que instancia a cena legada de verdade.

Antes de mover ou apagar qualquer coisa, confira se outra sessão está com o repositório
aberto — arquivos novos com timestamp recente que você não criou são sinal disso.

## Godot: como rodar

O binário fica fora do repositório. Use a variante `_console.exe` no Windows para capturar
saída no terminal.

```bash
GODOT="D:/Downloads Chrome/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"

"$GODOT" --path . --script res://tests/<nome>.gd   # roda um teste
"$GODOT" --path . --import                          # reimporta e reconstrói caches
```

**Nunca use `--headless` para medir performance.** Em headless o Godot usa o driver de
renderização dummy: FPS, draw calls e custo de GPU perdem o significado. As medições em
`tests/measure_*` e `tests/profile_*` dependem de renderização real com Vulkan.

## Ao mover ou renomear arquivos

O projeto referencia recursos por **string de caminho**, não por UID: são ~653
`preload("res://...")` e ~903 `load("res://...")`, e dos `path=` em `.tscn` quase nenhum
tem `uid=` como companheiro. Mover arquivo quebra referência de verdade.

Procedimento obrigatório:

1. `git mv` (preserva histórico) e leve junto os companheiros `.uid` (scripts) e
   `.import` (assets).
2. Substituir o caminho antigo pelo novo em todo `.gd`, `.tscn`, `.tres`, `.cfg` e
   `project.godot`.
3. `python tools/check_references.py` — tem que voltar **0 quebras novas**.
4. **`"$GODOT" --path . --import`** — o registro global de `class_name`
   (`.godot/global_script_class_cache.cfg`) fica obsoleto depois de um move e quebra a
   resolução de classes *mesmo com todas as strings corretas*. O verificador do passo 3
   não pega isso; só o carregamento real pega.
5. Carregar o jogo de verdade e rodar a suíte de verificação (abaixo).

## Suíte de verificação

Depois de qualquer mudança estrutural:

```bash
python tools/check_references.py
"$GODOT" --path . --script res://tests/profile_load_time_0909.gd      # deve dar errors=0 / issues=0
"$GODOT" --path . --script res://tests/test_menu_flow_integration.gd  # save/load + troca de cena
"$GODOT" --path . --script res://tests/test_opening_cutscene_runtime.gd
"$GODOT" --path . --script res://tests/test_pedestrian_life_routines.gd
"$GODOT" --path . --script res://tests/test_pedestrian_render_lod.gd
```

`test_menu_flow_integration` é o mais valioso depois de mover arquivos: ele exercita
save/load e troca de cena, que é onde caminho quebrado aparece.

## Estilo

- Comentários e mensagens de log em **português**; identificadores em **inglês**.
- Testes são scripts `SceneTree` independentes, executados via `--script`. Não há
  framework externo: cada arquivo imprime seu resultado e sai com código 0 ou 1.
- Comentário explica **por quê**, não o quê. Vários comentários no código registram a
  razão de uma escolha não óbvia (por exemplo, por que o coronel usa direção reta em vez
  do roteador de faixas) — preserve esse tipo de contexto ao editar.

## Honestidade de verificação

Uma suíte verde **não** prova que o jogo está correto: ela prova que aqueles casos
passaram. Vários defeitos reais desta base apareceram em partida de verdade com suítes
aprovadas. Ao reportar resultado:

- Diga o que foi medido e o que **não** foi.
- Não apresente ausência de evidência como prova de ausência do problema.
- Percentis de tempo de frame vão em **milissegundos**, não convertidos para FPS —
  percentilar uma métrica invertida distorce a cauda.
