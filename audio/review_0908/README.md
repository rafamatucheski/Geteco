# Revisão de áudio 2026-09-08 — sirene, alarme, conquista + BearAudio

Escopo: melhorar o timbre/qualidade das streams de sirene e conquista em
`ProceduralAudio.gd` (artificiais/desagradáveis) e criar o módulo
independente `BearAudio.gd`, sem tocar em regras de perseguição, disparo de
conquista, ou nos arquivos fora de escopo (WantedManager, EmergencyVehicle,
PoliceOfficer, Player*, TrafficVehicle, mapas, RegionTravel, SaveManager,
UI, Localization, controllers de achievement).

## Arquivos alterados

- **`ProceduralAudio.gd`** — só a *geração* de PCM dentro de 3 funções foi
  reescrita; assinaturas, nomes, tipos de retorno e o cache estático
  (`_cached_siren`, `_cached_police_alarm`, `_cached_mission_passed`) foram
  preservados byte-a-byte:
  - `static func get_siren_stream() -> AudioStream` (linha ~247)
  - `static func get_police_alarm_stream() -> AudioStream` (linha ~310)
  - `static func get_mission_passed_stream() -> AudioStream` (linha ~1466)

  Nada mais no arquivo foi tocado (motor, skid, crash, buzina, rádio,
  tiros, clima, passos, portas, etc. seguem exatamente como estavam).

## Arquivos criados

- `audio/review_0908/BearAudio.gd` — módulo novo, independente, documentado.
- `audio/review_0908/test_procedural_audio_quality.gd` — teste headless.
- `audio/review_0908/capture_audio_comparison.gd` — exporta os WAVs abaixo.
- `audio/review_0908/README.md` — este arquivo.
- 9 arquivos `.wav` (ver "WAVs exportados" abaixo).

## O que mudou em cada som (e por quê)

### Sirene principal (`get_siren_stream`)
- **Antes**: sweep 650↔1150Hz de 1.2s calculado como `sin(2*PI*freq*t)` com
  `freq` variando a cada amostra. Isso não é uma fase realmente contínua
  (equivale a `sin` avaliado com uma frequência "instantânea" multiplicada
  direto pelo tempo absoluto, não integrada) e o loop de 1.2s não fechava
  de forma alinhada — resultava em uma alternância rápida e um pouco
  artificial, com possível descontinuidade sutil na costura do loop.
- **Depois**: duração de 3.0s (650↔1150Hz, sweep raised-cosine simétrico
  "sobe-desce" — um wail completo por ciclo, alternância bem reconhecível).
  A frequência é **integrada em fase** (`phase += 2*PI*freq/sample_rate`,
  amostra tirada a partir da fase acumulada) em vez de multiplicada
  diretamente pelo tempo, e a duração foi escolhida para que a frequência
  média (900Hz) × 3.0s dê exatamente 2700 ciclos — um número inteiro — o
  que faz a fase acumulada terminar num múltiplo exato de 2π, fechando o
  loop sem salto. Um leve reforço harmônico (2º/3º harmônico, ~14%) dá
  corpo sem ficar agudo, e a soma passa por `tanh` (soft-clip) em vez de
  clamp duro, garantindo que não há clipping e que o topo da onda fica
  arredondado (sem agudos dolorosos).

### Alarme de viatura (`get_police_alarm_stream`)
- **Antes**: alternava 880Hz/1380Hz a cada ~0.167s trocando a frequência
  **instantaneamente** (`int(t*6)%2`), sem crossfade — isso causa uma
  descontinuidade de fase a cada troca, ouvida como estalo/clique.
- **Depois**: duas frequências (880Hz/1320Hz) tocando o tempo todo em fase
  contínua, misturadas por um crossfade suave (`tanh` de uma senoide,
  transição de poucos milissegundos) em vez de uma chave liga/desliga.
  Duração de 0.8s = exatamente 2 períodos de 0.4s, e ambas as frequências
  completam um número inteiro de ciclos nesse intervalo (704 e 1056
  ciclos), então o loop fecha sem estalo. A alternância entre os dois tons
  continua nitidamente reconhecível (validado no teste, ver abaixo).

### Conquista / fanfarra (`get_mission_passed_stream`)
- **Antes**: 4 notas (Dó4-Mi4-Sol4-Dó5) com envelope
  `exp(-fmod(t,0.35)*4.0)` — o `fmod` cortava a nota abruptamente no limite
  de 0.35s enquanto a envoltória ainda estava em ~22% do pico, criando um
  salto de amplitude audível a cada troca de nota.
  - **Depois**: cada nota tem seu próprio envelope (ataque linear de 12ms +
  decaimento exponencial) calculado no relógio local da nota, sem corte —
  uma nota nunca é truncada no meio da decaída; ela apenas continua
  decaindo (ficando inaudível) enquanto a próxima nota já começou. Isso
  elimina o clique de transição. A soma final passa por `tanh` (soft-clip),
  garantindo volume coerente com o resto dos SFX e sem risco de clipping
  mesmo quando duas notas se sobrepõem. Duração total mantida em 2.4s
  (igual ao original).

### `get_distant_siren_stream` — **não alterado**
Deixado como estava: não tem chaveamento abrupto (é um sweep suave com
envelope de fade in/out), então não apresentava o defeito de clique
identificado nos outros dois. Alterá-lo estaria fora do escopo mínimo
necessário.

## BearAudio.gd (módulo novo, isolado)

`audio/review_0908/BearAudio.gd` — 3 sons procedurais discretos, com
interface documentada no topo do arquivo (comentários com exemplo de uso
para o script do urso se conectar). Nenhum script de urso foi tocado.

- `BearAudio.get_breathing_stream() -> AudioStream` — respiração contínua
  e grave, `loop_mode == LOOP_FORWARD`, loop de 3.2s sem estalo (envelope
  raised-cosine que fecha em zero nas duas pontas).
- `BearAudio.get_grunt_alert_stream() -> AudioStream` — grunhido/alerta
  curto, one-shot (`LOOP_DISABLED`), ataque rápido + decaimento.
- `BearAudio.get_charge_stream() -> AudioStream` — rugido de investida,
  one-shot (`LOOP_DISABLED`), ~1.1s, intensidade crescente.

Todo o áudio é 100% procedural (osciladores + ruído filtrado, mesmo padrão
de síntese de `ProceduralAudio.gd`) — sem samples de terceiros, então não
há questão de licenciamento.

## Testes executados

Godot 4.7.2 headless, `D:/Downloads Chrome/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe`:

```bash
# Teste de qualidade (geração, amostras finitas, pico sem clipping, cache, continuidade do loop)
Godot_v4.7.2-stable_win64_console.exe --headless --path "D:/geteco/game" --script "res://audio/review_0908/test_procedural_audio_quality.gd"
# -> PROCEDURAL_AUDIO_QUALITY failures=0 (38 verificações, todas ok)

# Exportação dos WAVs de comparação
Godot_v4.7.2-stable_win64_console.exe --headless --path "D:/geteco/game" --script "res://audio/review_0908/capture_audio_comparison.gd"
# -> AUDIO_COMPARISON_CAPTURE all_ok=true (9/9 arquivos salvos)

# Teste de regressão pré-existente (não criado por mim), para checar que o
# fluxo real de sirene/alarme da viatura da PM continua funcionando:
Godot_v4.7.2-stable_win64_console.exe --headless --path "D:/geteco/game" --script "res://tests/test_police_car_alarm_theft.gd"
# -> SUCESSO: TODAS AS VERIFICAÇÕES DE VIATURA DA PM PASSARAM! (EXIT 0)
```

O teste de qualidade verifica, para cada uma das 3 funções de
`ProceduralAudio.gd` e das 3 de `BearAudio.gd`:
- que a stream é gerada como `AudioStreamWAV` finita e não vazia;
- que o pico não passa de ~97% da escala de 16 bits (sem clipping);
- que a **segunda chamada retorna a mesma instância** (cache funcionando —
  não regenera PCM a cada acionamento);
- para os loops (`LOOP_FORWARD`): que o "degrau" entre a última e a
  primeira amostra é **menor ou igual ao maior degrau que já ocorre
  naturalmente dentro do próprio sinal** (métrica relativa correta para
  tons de frequência alta, que naturalmente têm deltas grandes entre
  amostras vizinhas — um número absoluto fixo geraria falso-positivo);
- para o alarme: que os dois tons continuam com energia audível em janelas
  separadas do buffer (a alternância não virou um tom só) e que não há
  saltos amostra-a-amostra fora do padrão do próprio sinal;
- para a conquista: ataque suave na primeira amostra, cauda final
  decaindo perto do silêncio, e ausência de salto forte nas 3 transições
  de nota (0.35s/0.70s/1.05s).

**Nota de honestidade**: não abri o jogo nem toquei os sons pelo motor de
áudio real (sem driver de áudio no ambiente headless) — a validação foi
100% pela análise das amostras PCM geradas (picos, deltas, cache,
metadados de loop) e pelos WAVs exportados abaixo, que ficam disponíveis
para audição manual. Não afirmo ter validado a experiência de gameplay.

## WAVs exportados (para audição)

Todos em `D:/geteco/game/audio/review_0908/`:

| Arquivo | O quê |
|---|---|
| `siren_before.wav` | Sirene principal, algoritmo antigo (réplica exata, só para audição) |
| `siren_after.wav` | Sirene principal, algoritmo novo (o que `get_siren_stream()` retorna agora) |
| `police_alarm_before.wav` | Alarme de viatura, algoritmo antigo |
| `police_alarm_after.wav` | Alarme de viatura, algoritmo novo |
| `achievement_before.wav` | Fanfarra de conquista, algoritmo antigo |
| `achievement_after.wav` | Fanfarra de conquista, algoritmo novo |
| `bear_breathing.wav` | BearAudio: respiração (loop) |
| `bear_grunt_alert.wav` | BearAudio: grunhido/alerta (one-shot) |
| `bear_charge.wav` | BearAudio: investida (one-shot) |

Os arquivos `*_before.wav` são gerados por réplicas do algoritmo antigo
mantidas só dentro de `capture_audio_comparison.gd` (não existem mais em
`ProceduralAudio.gd`) — servem apenas para audição comparativa.

## Funções públicas preservadas

Confirmado por leitura de todos os consumidores antes de editar
(`EmergencyVehicle.gd`, `city_demo/scripts/TrafficVehicle.gd`,
`district/harbor_preview/interiors/HarborFireStationInterior.gd`,
`CityAudioManager.gd`, `HUD.gd`, `NightRaceController.gd`,
`MissionManager.gd`) — nenhum deles lê `.get_length()` da stream nem
depende da duração exata; todos apenas atribuem `.stream = ProceduralAudio.get_X_stream()`
e chamam `.play()`/`.stop()`. Nenhum desses arquivos foi editado.

- `ProceduralAudio.get_siren_stream() -> AudioStream` — mesma assinatura, 0 argumentos.
- `ProceduralAudio.get_police_alarm_stream() -> AudioStream` — mesma assinatura, 0 argumentos.
- `ProceduralAudio.get_mission_passed_stream() -> AudioStream` — mesma assinatura, 0 argumentos.
- `ProceduralAudio.get_distant_siren_stream() -> AudioStream` — inalterada.

Bus de áudio, `volume_db`, `pitch_scale` e demais configurações do usuário
não foram tocados — continuam definidos nos arquivos consumidores (fora do
escopo desta revisão).
