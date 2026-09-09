# Medições da revisão de 2026-09-09

Dados brutos que sustentam os números citados em
[../../HANDOFF_ESTRUTURA_2026-09-09.md](../../HANDOFF_ESTRUTURA_2026-09-09.md) e
[../../ARCHITECTURE.md](../../ARCHITECTURE.md). Estão versionados de propósito: número
sem o log que o gerou é afirmação, não evidência.

## Como foram produzidos

Renderização **real** (Vulkan, janela), nunca `--headless` — em headless o Godot usa o
driver dummy e FPS, draw calls e custo de GPU perdem o significado.

Um bot-script pilota o player, o carro e a câmera reais dentro de `HarborGame.tscn`, com
chuva e uma perseguição policial de verdade disparada por `WantedManager.report_crime()`.
Nada é teleportado e nenhuma colisão é desligada. **Não é um humano jogando** — é
automação, e os números devem ser lidos com essa ressalva.

```bash
GODOT="D:/Downloads Chrome/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
"$GODOT" --path . --script res://tests/measure_review_0909.gd -- res=720 sample=1
"$GODOT" --path . --script res://tests/measure_review_0909_bisect.gd
"$GODOT" --path . --script res://tests/profile_load_time_0909.gd
"$GODOT" --path . --script res://tests/reproduce_review_0909_stage2.gd
```

Os scripts gravam aqui por padrão. `run_measurements.ps1` roda a bateria completa das seis
amostras em sequência.

## Os arquivos

| arquivo | o que contém |
|---|---|
| `review0909_res720_sample{1,2,3}.txt` | 3 amostras de 60 s em 1280×720 (`CANVAS_ITEMS`) |
| `review0909_res1080_sample{1,2,3}.txt` | 3 amostras de 60 s em 1920×1080 real (`VIEWPORT`) |
| `review0909_bisect.txt` | bisecção por fases: pedestres desligados, veículos desligados, SubViewports pausados |
| `load_profile.txt` | perfil de carregamento por fase, com os picos de frame |
| `review0909_stage2.txt` | comportamento de cada veículo de emergência em 45 s de perseguição |
| `run_measurements.ps1` | roteiro da bateria de 6 amostras |

## O que os dados dizem — e o que não dizem

**Dizem:** frame time mediano praticamente igual entre 720p e 1080p (~22 ms nos dois),
com draw calls quase idênticos, apesar de 1080p renderizar 2,25× mais pixels. O que
aparece nas duas resoluções é stutter forte na cauda (p95 ~82–92 ms, p99 ~124–140 ms),
não framerate baixo constante.

**Não dizem** que resolução e SubViewport estão descartados como causa. A bisecção rodou
em fases sequenciais dentro de uma mesma sessão, então o estado do mundo (número de
viaturas despachadas, nível de procurado, colisões acumuladas) cresceu ao longo dela e
confunde a leitura. É ausência de evidência numa rodada confundida, não prova de ausência.

A hipótese mais sustentada é custo crescente ligado à **duração da perseguição**, e ela
não foi confirmada com medição isolada.

Ao citar estes dados, use percentis de tempo de frame em **milissegundos**. Converter para
FPS distorce a cauda, porque percentilar uma métrica invertida inverte o sentido do
percentil.

## Concorrência durante a coleta

O editor do Godot do usuário ficou aberto o tempo todo, e em parte das amostras havia
processos do Antigravity rodando validações. Isso afeta os números absolutos. Não afeta a
comparação 720p×1080p, que rodou sob a mesma condição — mas concorrência semelhante não
garante carga equivalente.
