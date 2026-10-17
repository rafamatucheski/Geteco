# Convenções para agentes de IA neste repositório

Este projeto é trabalhado por **mais de um agente ao mesmo tempo** (Claude, Codex,
Antigravity) além do desenvolvedor no editor do Godot. As regras abaixo existem para que
trabalhos paralelos não se atropelem. Leia também [AGENTS.md](AGENTS.md) (regras de jogo,
interiores, desempenho e Git) e [README.md](README.md).

**Antes de qualquer mudança, leia [docs/HOW-TO-DEVELOP.md](docs/HOW-TO-DEVELOP.md)**: fila única
de Godot (`tools/run_godot_locked.sh`), como medir desempenho em release e as regras de código
que evitam quadros grandes (streaming, shaders, prédios pintados, portas).

### Resumo do How to Develop (detalhes e razões no guia)

- **Godot só pela fila** `tools/run_godot_locked.sh <args>`, um por vez na máquina. Export:
  `GODOT_RUN_TIMEOUT=240 tools/run_godot_locked.sh --headless --path . --export-release "Geteco V2 Windows" <pasta>/GetecoV2.exe`
  (o export às vezes não sai sozinho depois de gravar o pacote). Não feche janelas de teste.
- **Meta:** p50 ≤ 16,7 ms, nenhum quadro > 33 ms depois de jogável, p50 ≤ 6,9 ms onde der.
- **Medir só no export release**, A/B no mesmo export e no mesmo dia com interruptor `GETECO_*`
  (nunca trocar arquivos pelo HEAD). Rotas: `tools/perf_cross_bench.sh <pasta> <rótulo> [rodadas] [rotas]`;
  tudo: `tools/perf_cross_phase2.sh`. Logs em `%APPDATA%/GetecoV2/session-logs/`; diagnóstico com
  `HARBOR_STALL_LOG=1` e `HARBOR_STALL_STACKS=1`.
- **Código novo pesado leva span** (`StallWorkTrace.begin/finish/finish_slow`) para o pico ter nome.
- **Nada pesado num quadro só:** sob a cortina, fatiado (~2 ms) ou em `WorkerThreadPool`.
  Nunca `surface_get_arrays` no jogo (use `MeshArrayCache`), nem varrer o mapa inteiro por ponto,
  nem `load()` síncrono grande, nem cálculo procedural na primeira aparição.
- **Shader nunca compila no jogo:** sem `hint_depth_texture`; material novo entra num pré-aquecimento
  (`BridgeLookPrewarm`, `VehicleMaterialVariantPrewarm`, `PaintedFacadePrewarm`, `WildlifePrewarm`) e fica retido.
- Objetos que somem e voltam (ursos, fontes de calor): montar uma vez e **estacionar**, não recriar.
- Luz nova passa por `LightBudget`; textura nova em BC7 com mipmaps.
- Board do projeto: `docs/painel-geteco.html`, gerado por `python tools/build_geteco_board.py` a partir
  de `docs/board-*.json` (acrescente um `board-atualizacoes-<data>.json` novo em vez de reescrever os antigos).

## Estrutura

A raiz do repositório **é o jogo** (a antiga V2, promovida em 2026-09-24). O projeto Godot
é `project.godot` na raiz; todo caminho `res://` é relativo a ela.

- `runtime/`, `scripts/`, `systems/`, `data/`, `migration/`: sessão, mundo de produção,
  save, progressão, catálogos e importação do save da V1.
- `world/`: regiões Harbor/Mountain em streaming (`world/regions/NativeRegion.gd`),
  cidade, lugares e a conexão da ponte.
- `gameplay/`, `activities/`: combate, polícia, trânsito, rua, atividades.
- `audio/`, `ui/`, `cutscenes/`, `assets/`: som, interface, abertura e arte.
- `tests/`, `tools/`: testes e medições; ferramentas de exportação.
- `docs/`: documentação; `evidence/`: relatórios de validação (só `.md`/`.json`/`.patch`
  são versionados — capturas e vídeos ficam no disco, fora do Git).

**A V1 não está mais em `main`.** O estado final dela está no ramo `v1-legado` e na tag
`v1-final`. Ferramentas que ainda leem fontes da V1 (por exemplo
`tests/urban_detail/export_v1_building_atlas.gd`) precisam daquele ramo.

Antes de mover ou apagar qualquer coisa, confira se outra sessão está com o repositório
aberto — arquivos novos com timestamp recente que você não criou são sinal disso.

## Godot: como rodar

O projeto usa GDScript e C#. Use sempre **Godot 4.7.2 .NET (mono)**.
Compile `Harbor.csproj` antes dos testes diretos (`dotnet build Harbor.csproj`);
`Jogar.cmd`, `Editar.cmd` e os runners principais fazem isso automaticamente.
O binário fica fora do repositório. Use a variante `_console.exe` no Windows para capturar
saída no terminal.

```bash
GODOT="D:/Downloads Chrome/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe"

"$GODOT" --path . --script res://tests/<nome>.gd   # roda um teste
"$GODOT" --path . --import                          # reimporta e reconstrói caches
```

Também há `Jogar.cmd` (jogo) e `Editar.cmd` (editor).

**Nunca use `--headless` para medir performance.** Em headless o Godot usa o driver de
renderização dummy: FPS, draw calls e custo de GPU perdem o significado.

**Não inicie Godot enquanto houver outra instância, importação ou medição ativa** de outra
sessão: medições concorrentes se contaminam (CPU, GPU e cache de shader compartilhados).

## Ao mover ou renomear arquivos

O projeto referencia recursos por **string de caminho** (`preload("res://...")`,
`load("res://...")`, `path=` em `.tscn`). Mover arquivo quebra referência de verdade.

1. `git mv` (preserva histórico) levando junto os companheiros `.uid` e `.import`.
2. Substituir o caminho antigo pelo novo em todo `.gd`, `.tscn`, `.tres`, `.cfg` e
   `project.godot`.
3. `"$GODOT" --path . --import` — o registro de `class_name` fica obsoleto depois de um
   move e quebra a resolução de classes mesmo com todas as strings corretas.
4. Carregar o jogo de verdade e rodar a verificação (abaixo).

## Verificação

Depois de qualquer mudança estrutural, no mínimo:

```bash
"$GODOT" --path . --script res://tests/test_regions.gd
"$GODOT" --path . --script res://tests/test_bridge_approach_terrain.gd
"$GODOT" --path . --script res://tests/test_native_driving.gd -- --no-save
"$GODOT" --path . --script res://tests/cold/test_admission.gd
```

E abra o jogo (`Jogar.cmd`) para ver que ele carrega e anda.

## Git — cada agente commita o próprio trabalho

1. **Commite antes de encerrar.** Não deixe seu trabalho pendente para o próximo agente.
2. **Stage explícito, nunca `git add -A` às cegas.** Adicione os arquivos que você mexeu.
   Se `git status` mostrar arquivo que você não criou e com timestamp recente, é outra
   sessão trabalhando — deixe fora do seu commit.
3. **Rode a verificação antes.** Commit que não carrega o jogo custa mais caro do que
   commit atrasado.
4. **Mensagem descritiva, em português, explicando o porquê**: o que mudou, por que mudou
   e o que foi verificado. Veja `git log` para o padrão.
5. **Ninguém dá push sem o usuário pedir.**
6. **Nunca** `git reset --hard`, `push --force`, `checkout .` ou `clean -f` sem pedido
   explícito. Se precisar desfazer algo, prefira mover para o lado a destruir.
7. Nunca versione `.secrets/`, exports `.pck`, caches de shader ou capturas/vídeos de
   `evidence/` (o `.gitignore` já cobre).

## Saída de script

Script que gera arquivo grava **dentro do projeto** (`res://` +
`ProjectSettings.globalize_path`), não em pasta absoluta fora dele. Evidência de mídia vai
para `evidence/` (fica no disco, fora do Git).

## Estilo

- Comentários e mensagens de log em **português**; identificadores em **inglês**.
- Testes são scripts `SceneTree` independentes, executados via `--script`: cada arquivo
  imprime seu resultado e sai com código 0 ou 1.
- Comentário explica **por quê**, não o quê. Preserve comentários que registram a razão
  de uma escolha não óbvia (e a medição que a motivou).

## Honestidade de verificação

Uma suíte verde **não** prova que o jogo está correto: prova que aqueles casos passaram.
Ao reportar resultado, diga o que foi medido e o que **não** foi; não apresente ausência de
evidência como prova de ausência do problema; percentis de tempo de quadro vão em
**milissegundos**.
