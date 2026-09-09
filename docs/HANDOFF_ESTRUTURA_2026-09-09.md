# Handoff — reestruturação de pastas (2026-09-09)

**Para: Codex Astra.** Leia antes de tocar no repositório. A estrutura de pastas mudou
bastante hoje, e caminhos que você conhecia não existem mais. Nenhum comportamento do jogo
foi alterado — só a organização e a documentação.

Ponto de partida: `5ce5fd0`. Quatro commits de reestruturação, 2.165 arquivos tocados.

Os dados brutos que sustentam todo número citado aqui estão em
[measurements/review-0909/](measurements/review-0909/), versionados junto com as
evidências originais do usuário.

---

## 1. O que mudou de lugar

### Antes → depois

| antes | depois |
|---|---|
| `district/harbor_preview/` | **`world/harbor/`** |
| `district/mountain_pass/` | **`world/mountain_pass/`** |
| `district/roads/` | `world/shared/roads/` |
| `district/pedestrians/` | `world/shared/pedestrians/` |
| `district/nature/`, `district/rail/` | `world/shared/nature/`, `world/shared/rail/` |
| `district/Emergency*`, `DepotGate`, `DocksParking`, `EmergencyVehicleYard`, `ModernTrafficFactory` | `world/shared/emergency/` |
| `city_demo/scripts/TrafficVehicle.gd`, `city_demo/scenes/TrafficVehicle.tscn` | `world/shared/traffic/` |
| `city_demo/scripts/WeaponEffects.gd` | `world/shared/combat/` |
| `city_demo/scripts/roads/CityIntersection.gd` | `world/shared/roads/` |
| `city_demo/scenes/pickups/PoliceLoot.{gd,tscn}` | `world/shared/pickups/` |
| `city_demo/art/` | **`assets/art/`** |
| `Main.tscn` | **`legacy/Main.tscn`** |
| `CentralDistrict.*`, `DistrictInteriorManager.*`, `DistrictRestrictionFeedback.*` | `legacy/` |
| `district/` (bairro1, bairro1_v2, borough_one, coast, highway) | `legacy/district/` |
| `city_demo/` (o que sobrou) | `legacy/city_demo/` |

**A pasta `district/` não existe mais.** O nome misturava região viva, malha viária e
protótipos mortos. E `harbor_preview` não era preview nenhum: era o jogo principal — foi o
nome mais enganoso do repositório.

### Estrutura de hoje

```
world/          349 arq   o jogo que roda
  harbor/       184       jogo principal (HarborGame.tscn)
  mountain_pass/105       segunda região, por streaming
  shared/        59       roads, pedestrians, traffic, emergency, combat, pickups, nature, rail
ui/              33       MainMenu.tscn = entrypoint declarado no project.godot
legacy/         109       geração anterior — AINDA CARREGA, ver seção 3
OLD/             46       arquivo morto, tem .gdignore
tools/            2       check_references.py, move_folder_refactor.py
docs/                     estrutural na raiz, medições em docs/measurements/,
                          sessões antigas em docs/history/
raiz             72 .gd   sistemas globais (Player, PlayerCar, WantedManager, HUD, catálogos)
```

Os 72 scripts soltos na raiz **não** foram reorganizados. Ficou como fase separada,
adiada de propósito: são alvo de ~1.556 caminhos hardcoded e dos 10 autoloads, e não valia
juntar esse risco com o resto.

---

## 2. A armadilha que você precisa conhecer

O projeto referencia recursos por **string de caminho**, não por UID: 653 `preload("res://…")`
e 903 `load("res://…")`, e quase nenhum `path=` de `.tscn` tem `uid=` como companheiro.
Mover arquivo quebra referência de verdade.

Pior: **corrigir todas as strings não basta.** O registro global de `class_name` do Godot
(`.godot/global_script_class_cache.cfg`) continua apontando para os caminhos antigos e
quebra a resolução de classes mesmo com tudo certo no código. Isso me custou um ciclo de
depuração hoje: o verificador dizia 0 quebras e o jogo não carregava.

Procedimento obrigatório ao mover arquivo:

```bash
GODOT="D:/Downloads Chrome/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"

# 1. git mv (leve junto os .uid e .import)
# 2. substituir res://<antigo> por res://<novo> em .gd/.tscn/.tres/.cfg/project.godot
python tools/check_references.py     # 3. tem que dar 0 quebras novas
"$GODOT" --path . --import           # 4. RECONSTRUIR o cache de class_name
"$GODOT" --path . --script res://tests/profile_load_time_0909.gd   # 5. carregar de verdade
```

Pular o passo 4 produz erro que parece do seu código e não é.

### As duas ferramentas em `tools/`

`move_folder_refactor.py` faz o move + reescrita de referências com `--dry-run`. Foi o que
rodou nas Fases 2 e 3 (306 e 105 arquivos) e está pronto para a Fase 4 — basta preencher a
lista `MOVES`. O docstring traz o procedimento completo.

### `tools/check_references.py`

Ferramenta nova. Valida que toda referência `res://` aponta para arquivo existente, e
distingue por contexto (não por lista fixa):

- **sondagem opcional** — caminho dentro de `ResourceLoader.exists(...)`, tem fallback
- **destino de escrita** — caminho passado a `save_png()`/`ResourceSaver.save()`, é saída

Sai com código 1 só em quebra **nova**. Uma quebra real pré-existente está registrada em
`KNOWN_BROKEN` para ficar visível sem travar o portão — ver seção 5.

---

## 3. `legacy/` não é código morto

Não confunda com `OLD/`. **`legacy/` não tem `.gdignore` e é carregada em runtime.**

`world/harbor/HarborSceneRoute.gd`:

```gdscript
const GAME   := "res://world/harbor/HarborGame.tscn"
const LEGACY := "res://legacy/Main.tscn"
```

Save **sem** a flag `harbor_campaign_active` carrega `legacy/Main.tscn`. Quem começou a
jogar antes da campanha do porto continua na primeira geração do mapa. Apagar a pasta, ou
colocar `.gdignore` nela, quebra o save dessas pessoas.

`tests/test_legacy_save_route.gd` (novo) guarda esse contrato: instancia a cena legada de
verdade, não só confere a string. Rode-o se mexer em qualquer coisa dessa árvore.

As duas gerações **compartilham** `Player.gd`, `PlayerCar.gd`, `DynamicCamera.gd` e
`world/shared/emergency/EmergencyDepots.tscn`. Só o mapa difere.

---

## 4. Documentação criada

Não existia `README.md` na raiz nem `CLAUDE.md`, e os 81 `.md` eram quase todos relatórios
de sessão datados.

| arquivo | conteúdo |
|---|---|
| `README.md` | o que é o projeto, como rodar, como rodar testes, mapa de pastas |
| `CLAUDE.md` | convenções para agentes: territórios, procedimento de move, suíte de verificação |
| `docs/ARCHITECTURE.md` | **comece por aqui** — cadeia de entrada, autoloads, física 2D com apresentação 3D, perfil de carregamento, streaming, cadeia de despacho de emergência |
| `world/`, `legacy/`, `tests/`, `docs/`, `prototypes/` | README por pasta |
| `docs/history/` | 21 relatórios de sessão anteriores |

Cuidado ao ler `docs/history/`: descreve estado de uma data específica e usa os caminhos
antigos. Confira contra o código antes de agir.

---

## 5. Pendências — o que continua aberto

Em ordem de impacto.

### 5.1 Congelamento de ~9,2 s no carregamento

O maior item, e o que se sente ao abrir o jogo. Perfil medido com renderização real:

| fase | tempo |
|---|---|
| `load()` do `.tscn` | ~1,9 s |
| `add_child()` (`_ready()` síncrono) | ~1,2 s |
| **primeiro frame depois** | **~9,2 s** |
| até estabilizar | ~4 s |

Causa: `HarborPreview._ready()` faz `call_deferred("_start_review")`, e `_start_review()`
constrói o mundo inteiro — distritos, emergência, frota, auditorias — **em um único frame**.
É congelamento, não carregamento progressivo. A correção é fatiar esse trabalho entre
frames.

### 5.2 `RegionTravel.gd:190` — crash latente

```gdscript
car = load("res://PlayerCar.tscn").instantiate()
```

`PlayerCar.tscn` **não existe em lugar nenhum do projeto**. `load()` devolve null e
`.instantiate()` estoura. É autoload, no caminho que reconstrói veículo a partir do save.
Encontrado pela ferramenta nova, registrado em `KNOWN_BROKEN`. Não corrigi porque não sei
qual era a cena pretendida — precisa de decisão de quem conhece o histórico.

### 5.3 Circulação de emergência (investigação parada no meio)

Reprodução com dados reais, 45 s de perseguição:

| viatura | ciclos de ré | deslocamento líquido |
|---|---|---|
| #1 | 0 | 65 (ficou na base) |
| #2 | 0 | 12.014 |
| #3 | 2 | 11.940 |
| #4 | **15** | 12.070 |

Três das quatro andam normal. A quarta deu 15 ciclos de ré em 45 s (~1 a cada 3 s) e
mesmo assim progrediu — não é travamento permanente, é uma taxa de recuperação anormal
cuja causa **não foi isolada**.

Ambulância: as duas do pool nunca saíram da posição de estacionamento nos 45 s, apesar de
um atropelamento sobrevivível real perto do hospital. Junto apareceu erro reproduzível —
`Paramedic.gd:368` chama `rescue_from_emergency()` em `AnimatedPedestrian3D.gd:1424`, que
tenta reconectar o sinal `arrived_at_depot` já conectado.

Script de reprodução: `tests/reproduce_review_0909_stage2.gd`; log bruto em
`docs/measurements/review-0909/review0909_stage2.txt`. A folha de contato que mostra a
viatura girando está em `docs/measurements/review-0909/evidencias/video2-sheet0.jpg`.

**Armadilha que já produziu um "bug" que era só o teste:** `HarborGame.tscn` toca uma
cutscene de chegada que faz `get_tree().paused = true`, e `request_dispatch()` checa
`can_process()`. Teste que não chama `campaign_controller.skip_cinematic()` vê **todo**
despacho retornar null e parece que o sistema está quebrado.

### 5.4 `.tscn` com BOM não carrega

Dois arquivos começam com byte order mark UTF-8 e o parser do Godot recusa
(`Expected '['`): `legacy/district/bairro1_v2/landmarks/LandmarksV2.tscn` e
`prototypes/living_cast/FleetShowcasePhase2.tscn`. Nenhum está no jogo vivo. Os 30 `.gd`
com BOM o Godot aceita normalmente. Pré-existente; não corrigi para não misturar com
refactor estrutural.

### 5.5 Performance em partida — o que foi descartado e o que não foi

Medição de 3 amostras de 60 s em cada resolução, renderização real:

| | 720p | 1080p |
|---|---|---|
| frame time mediano | ~22 ms | ~22,7 ms |
| p95 | ~82 ms | ~92 ms |
| p99 | ~124 ms | ~140 ms |
| draw calls | ~16.050 | ~16.420 |

**A resolução não explica a queda percebida** — 1080p renderiza 2,25× mais pixels e o
frame time mediano é praticamente o mesmo. O que aparece nas duas é stutter forte na
cauda (p95/p99), não framerate baixo constante.

Uma bisecção pausando os 249 `SubViewport` não mostrou efeito — eles já usam
`UPDATE_ONCE`/`UPDATE_DISABLED`, então custam pouco por frame (mas caro na construção e
~1,3 GB de VRAM). **Atenção:** isso é ausência de evidência numa rodada confundida, não
prova de que SubViewport e resolução estão descartados. A hipótese mais sustentada pelos
dados é custo crescente ligado à duração da perseguição, e ela **não** foi confirmada com
medição isolada.

Reporte percentis em **milissegundos**, não convertidos para FPS: percentilar uma métrica
invertida distorce a cauda.

---

## 6. Territórios

- `prototypes/gameplay_repair_art_0909/` é do Antigravity. Não editar.
- `OLD/` é arquivo morto com `.gdignore`. Só entra arquivo verificado sem referência
  **por caminho e por UID** — a varredura só por nome já produziu conclusão errada aqui
  (`car.png` parecia sem uso e é usado por `EmergencyVehicle.gd`, `PlayerCar.gd` e
  `VehicleCatalog.gd`).
- Outra sessão trabalhou em paralelo hoje e entregou o sistema de reação de civis a
  tiroteio (`PedestrianDanger.gd`, integrado em `Bullet.gd` e `AnimatedPedestrian3D.gd`,
  com `tests/test_civilian_gunfire_response.gd`). Está commitado e passa na verificação.

## 7. Nota sobre verificação

Suíte verde não prova que o jogo está correto — prova que aqueles casos passaram. Vários
defeitos reais desta base apareceram em partida de verdade com a suíte aprovada. Ao
reportar, diga o que foi medido **e o que não foi**.
