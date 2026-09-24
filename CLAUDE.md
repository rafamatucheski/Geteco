# Convenções para agentes de IA neste repositório

Este projeto é trabalhado por **mais de um agente ao mesmo tempo** (Claude, Codex,
Antigravity) além do desenvolvedor no editor do Godot. As regras abaixo existem para que
trabalhos paralelos não se atropelem. Leia também [AGENTS.md](AGENTS.md) (regras de jogo,
interiores, desempenho e Git) e [README.md](README.md).

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

O binário fica fora do repositório. Use a variante `_console.exe` no Windows para capturar
saída no terminal.

```bash
GODOT="D:/Downloads Chrome/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"

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
