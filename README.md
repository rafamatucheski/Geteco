# GETECO

Jogo de ação top-down em **Godot 4.7.2** (Forward+ / Vulkan), no espírito dos GTA 2D:
uma cidade portuária viva com trânsito, pedestres, polícia com nível de procurado,
serviços de emergência, lojas, missões e uma segunda região de montanha conectada por
streaming contínuo.

Característica técnica central: **a física é 2D, mas a apresentação é 3D**. Personagens,
veículos e vários props são modelos 3D renderizados dentro de `SubViewport`s e exibidos
como sprites no mundo 2D. Isso explica muita coisa no código e no custo de carregamento
(ver [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)).

## Como rodar

O jogo abre pelo menu, não direto no mundo. O entrypoint está declarado em
`project.godot`:

```
run/main_scene="res://ui/MainMenu.tscn"
```

Abra o projeto no editor do Godot 4.7.2 e rode normalmente (F5), ou pela linha de comando:

```bash
"caminho/para/Godot_v4.7.2-stable_win64.exe" --path . 
```

O menu carrega `world/harbor/HarborGame.tscn`, que é o jogo de verdade.

## Como rodar os testes

Os testes são scripts `SceneTree` executados via `--script`. Não existe framework de
teste externo: cada arquivo é um entrypoint independente que imprime seu resultado e sai
com código 0 ou 1.

```bash
GODOT="caminho/para/Godot_v4.7.2-stable_win64_console.exe"
"$GODOT" --path . --script res://tests/test_menu_flow_integration.gd
```

Use a versão `_console.exe` no Windows para capturar a saída no terminal.

**Não use `--headless` para medir performance.** Em headless o Godot usa o driver de
renderização dummy, então FPS, draw calls e custo de GPU deixam de ter significado. Os
scripts de medição em `tests/` dependem de renderização real.

Verificação de integridade de referências (rode antes e depois de mover arquivos):

```bash
python tools/check_references.py
```

## Estrutura de pastas

### Vivo — o jogo que roda hoje

| pasta | o que é |
|---|---|
| `ui/` | Menus. `MainMenu.tscn` é o entrypoint do projeto |
| `world/harbor/` | **O jogo principal.** `HarborGame.tscn` e tudo do distrito portuário: campanha, interiores, gangue das Cobras, eventos |
| `world/mountain_pass/` | Segunda região, carregada por streaming quando o jogador se aproxima |
| `world/shared/` | Infraestrutura compartilhada entre regiões: malha viária, pedestres, natureza, ferrovia, depósitos de emergência |
| raiz (`*.gd`) | Sistemas globais: `Player`, `PlayerCar`, `WantedManager`, `EmergencyVehicle`, `PoliceOfficer`, `HUD`, `SaveManager` e os catálogos de armas/veículos/roupas |
| `audio/`, `cutscenes/`, `data/` | Som, cutscene de abertura, dados de campanha |
| `interiors/`, `missions/`, `scenes/`, `scripts/`, `assets/` | Peças menores usadas pelo jogo vivo |

Dez scripts da raiz são **autoloads** (singletons globais) declarados em `project.godot` —
a lista está em [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

### Legado — geração anterior, ainda carregável

`legacy/` guarda a primeira geração do jogo: `Main.tscn` e os distritos que ela usava.

**Não é código morto.** `HarborSceneRoute.for_save()` ainda carrega `Main.tscn` em runtime
para saves antigos que não têm a flag `harbor_campaign_active`. Apagar ou tornar
inacessível quebra save de jogador.

### Apoio

| pasta | o que é |
|---|---|
| `tests/` | Testes de regressão (`test_*.gd`), capturas de imagem (`capture_*.gd`) e auditorias pontuais (`audit_*`, `profile_*`, `diagnose_*`) |
| `tools/` | Utilitários de manutenção do repositório |
| `docs/` | Documentação estrutural; `docs/history/` guarda relatórios de sessão datados |
| `prototypes/` | Trabalho de arte isolado, fora do mundo compartilhado |
| `addons/` | `city_layout_editor` — plugin de editor habilitado |
| `OLD/` | Arquivo morto. Tem `.gdignore`: o Godot ignora a pasta inteira |

## Convenções

- Comentários e mensagens de log em português; identificadores em inglês.
- Referências a recursos são **strings de caminho** (`preload("res://...")`), não UIDs.
  Por isso mover arquivo exige atualizar as referências — use `tools/check_references.py`
  para conferir.
- Agentes de IA trabalhando neste repositório: leia [CLAUDE.md](CLAUDE.md).
