# Áudio original da Monaliza — cupê turbo do Dante (2026-09-08)

Sons originais e isolados para o primeiro carro pessoal do Dante: a
Monaliza, um cupê turbo de quatro cilindros preparado, azul e laranja
(ver `docs/history/PROMPT_ANTIGRAVITY_MONALIZA_WORKSHOP.md` para o contexto visual
do carro, feito por outro agente). **Nada aqui integra com o jogo** —
`VehicleEngineSound.gd`, `ProceduralAudio.gd`, `PlayerCar`, scripts de
carro, `Player` e saves não foram tocados. A Astra decide como (e quando)
conectar estes arquivos ao carro de verdade.

Todo o áudio é 100% procedural, gerado do zero (osciladores + ruído
filtrado) — nenhum sample de terceiros, sem questão de licenciamento.

## Arquivos entregues

| Arquivo | Tipo | Duração | Pico sugerido (int16) | O que é |
|---|---|---|---|---|
| `engine.wav` | loop | 1.000s | ~13150 / 32767 (~40%) | Motor 4 cilindros turbo, encorpado, **não** um V8 |
| `turbo_spool.wav` | loop | 1.000s | ~7549 / 32767 (~23%) | Assobio de turbina, discreto (mais baixo que o motor) |
| `turbo_release.wav` | one-shot | 0.550s | ~13755 / 32767 (~42%) | Alívio/blow-off ao soltar o acelerador após carga |
| `ignition.wav` (opcional) | one-shot | 1.300s | ~12836 / 32767 (~39%) | Arranque girando + motor pegando |
| `demo_start_accelerate_release.wav` | one-shot (demo) | 4.600s | ~18312 / 32767 (~56%) | Partida → aceleração → alívio, para audição |

Gerados por `MonalizaAudioKit.gd` via `export_monaliza_audio.gd`. Nenhum
arquivo tem clipping: todo pico ficou abaixo de ~56% da escala de 16 bits
(headroom generoso para o volume/pitch que a integração for aplicar).

## Sample rate e formato

- **22050 Hz**, mono, PCM 16-bit (`AudioStreamWAV.FORMAT_16_BITS`) — mesmo
  padrão usado em `VehicleEngineSound.gd` e `ProceduralAudio.gd` no resto
  do projeto.
- `engine.wav` e `turbo_spool.wav` são loops de **exatamente 1.000s**
  (22050 amostras), desenhados com todas as frequências fixas em Hz
  inteiro (ex.: motor a 64Hz, turbo a 1200/1215Hz) para fechar em ciclos
  inteiros dentro de 1 segundo — a emenda do loop mede **degrau = 0** entre
  a última e a primeira amostra (ver `tests/test_monaliza_audio.gd`).

## ⚠️ Loop e o arquivo .wav em si (importante para a integração)

`AudioStreamWAV.save_to_wav()` grava um `.wav` só com os chunks `fmt`/
`data` — **não** grava um chunk `smpl` com os pontos de loop. Isso quer
dizer que, ao carregar `engine.wav`/`turbo_spool.wav` de volta (seja via
`load()` depois de importado no editor, seja via
`AudioStreamWAV.load_from_file()`), o `loop_mode` volta como
`LOOP_DISABLED` por padrão — **o loop precisa ser ligado explicitamente na
integração**:

```gdscript
var engine_stream := load("res://audio/vehicle/monaliza_engine.wav") as AudioStreamWAV
engine_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
engine_stream.loop_begin = 0
engine_stream.loop_end = engine_stream.data.size() / 2 # 22050 amostras = 1.000s
```

(É exatamente o padrão que `VehicleEngineSound._generate_engine_stream()`
já usa para o próprio stream que ela gera em memória — aqui só precisa
repetir o mesmo passo depois do `load()`, já que o `.wav` em si não carrega
essa marcação sozinho.) Alternativamente, o editor do Godot também permite
marcar "Loop" no painel de import do `.wav` depois de importado — qualquer
um dos dois caminhos funciona; qual usar é decisão da integração.

## Por que "não V8"

Um V8 tem uma cadência de disparo bem diferente (8 pulsos por 2 voltas de
virabrequim, "lombado"/irregular no ralenti, com bastante energia
sub-40Hz). Para o 4 cilindros turbo da Monaliza, `engine.wav` foi desenhado
com:
- fundamental em 64Hz (não abaixo de ~40Hz — evita o "rumble" grave de V8);
- harmônicos pares (2º e 4º) reforçados em ~1.4× sobre os ímpares — é esse
  reforço que dá o "zumbido" característico de motor inline-4/boxer, em
  vez do borbulhar mais grave e irregular de um V8;
- um leve "clatter" mecânico (válvulas/injeção) uma vez por ciclo de
  combustão, não um chiado contínuo — dá corpo sem ficar arenoso.

## Volumes sugeridos (para a integração)

Valores de referência, pensados para tocar junto (o motor sempre mais
presente que o turbo, igual a um carro de verdade):

| Stream | `volume_db` sugerido | Observação |
|---|---|---|
| `engine.wav` | -20 a -14 dB conforme RPM/carga | Já tem ~40% de pico; ajuste fino de RPM/carga por volume_db, como o `VehicleEngineSound.update()` já faz para os outros motores do projeto |
| `turbo_spool.wav` | -10 a -14 dB abaixo do `engine.wav` ativo | "Discreto" por pedido — mesmo no boost máximo, não deve competir com o motor |
| `turbo_release.wav` | -4 a 0 dB (one-shot, toca por cima) | Curto o bastante para não precisar abafar o resto |
| `ignition.wav` | -2 a 0 dB (one-shot, início da cena) | Só toca uma vez, no arranque |

## Pitch e RPM variável

Os três arquivos foram desenhados para tolerar `pitch_scale` alterado em
tempo real pela integração (mesmo mecanismo que `VehicleEngineSound.gd` já
usa: `pitch_scale = clampf((0.68 + rpm*1.18) * engine_pitch, 0.5, 2.4)`):

- `engine.wav`: conteúdo harmônico até a 8ª ordem (64Hz → 512Hz). Mesmo no
  teto de pitch (~2.4×), o harmônico mais agudo fica em ~1229Hz — bem
  abaixo do Nyquist de 22050Hz (11025Hz), sem risco de aliasing perceptível.
- `turbo_spool.wav`: par de tons em 1200/1215Hz (batimento suave de 15Hz).
  Pitchado a 2.4× chega a ~2900Hz; pitchado a 0.5× cai a ~600Hz — continua
  soando como assobio de turbina nos dois extremos.
- `turbo_release.wav`: chirp descendente de 2200Hz a 900Hz; em pitch alto
  (2.4×) o topo chega a ~5280Hz, ainda com boa margem do Nyquist.

**Limite recomendado**: não passar de ~3× pitch_scale nestes três arquivos
sem testar de ouvido — acima disso o harmônico mais agudo do motor começa
a se aproximar de uma faixa onde formatos de reamostragem mais simples
podem introduzir aliasing leve.

## Duração e limites

- `engine.wav` / `turbo_spool.wav`: 1.000s cravado (22050 amostras),
  loop; qualquer variação de RPM é feita via `pitch_scale`/`volume_db` pela
  integração, não regenerando o arquivo.
- `turbo_release.wav`: 0.550s, one-shot, decai a menos de 1.2% do pico
  nos últimos ~18ms (fade limpo, sem corte abrupto).
- `ignition.wav`: 1.300s (0.550s de arranque + 0.750s de "engine pega e
  assenta"), one-shot, mesmo padrão de fade no final.
- `demo_start_accelerate_release.wav`: 4.600s, one-shot, só para audição
  (não é pensado para uso direto no jogo).
- Nenhum arquivo satura: pico máximo medido foi ~56% da escala de 16 bits
  (na demonstração); os quatro entregáveis individuais ficam entre ~23% e
  ~42%. Headroom generoso para volume/pitch aplicados depois.
- Nenhuma camada de ruído contínuo é alta: o "sopro" do `turbo_spool.wav` e
  o "clatter" do `engine.wav` são deliberadamente de baixo nível (peso
  0.05–0.06 na mixagem crua, antes do soft-clip) — texturas, não chiado.

## Demonstração composta (`demo_start_accelerate_release.wav`)

Não é uma simples concatenação dos 4 arquivos (colar buffers com pitch
diferente entre si causaria estalos de emenda nos pontos de corte) — é uma
síntese contínua dedicada, em `MonalizaAudioKit.generate_demo_stream()`,
que reaproveita exatamente as mesmas peças de síntese (`_engine_tone`,
`_cranking_sample`, `_release_sample`) ao longo de uma única linha do
tempo, com frequência/amplitude variando suavemente:

1. **0.0–0.55s** — arranque (motor de partida girando, textura mecânica).
2. **0.46–0.55s** — cruzamento suave: arranque desvanece enquanto o motor
   "pega" (mesma técnica do `ignition.wav`).
3. **0.55–3.05s** — aceleração: frequência do motor sobe de 58Hz a 145Hz;
   o turbo entra por volta de 1.4s e cresce até ~1650Hz/pico de amplitude
   perto de 2.9s (construindo pressão).
4. **~3.05s** — alívio do acelerador: o `turbo_release` (blow-off) é
   misturado nesse instante, o motor cai rapidamente para ~68Hz e o turbo
   desliga em seguida.
5. **3.35–4.20s** — assentamento numa marcha lenta mais alta (~80Hz).
6. **4.20–4.60s** — fade final até o silêncio.

Como é um cálculo contínuo (não há loop, não há costura para fechar), não
existe risco de clique de emenda em nenhum ponto do arquivo.

## Testes executados

Godot 4.7.2, `D:/Downloads Chrome/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe`.

```bash
# Gera/regrava os 5 WAVs em audio/monaliza_review/.
Godot_v4.7.2-stable_win64_console.exe --headless --path "D:/geteco/game" --script "res://audio/monaliza_review/export_monaliza_audio.gd"
# -> MONALIZA_AUDIO_EXPORT all_ok=true

# Verificações: arquivos existem, duração, amplitude/clipping, continuidade
# das emendas de loop, fade dos one-shots.
Godot_v4.7.2-stable_win64_console.exe --headless --path "D:/geteco/game" --script "res://tests/test_monaliza_audio.gd"
# -> MONALIZA_AUDIO_TEST failures=0 (38 verificações, todas ok)
```

O teste usa `AudioStreamWAV.load_from_file()` para reabrir os `.wav`
diretamente do disco (eles não foram importados pelo editor, então
`load()` comum falha com "No loader found") e então analisa o PCM:
pico (sem clipping), RMS, duração, degrau na emenda do loop (comparado ao
maior degrau que já ocorre naturalmente dentro do próprio sinal — a
métrica correta para tons de frequência mais alta, que têm deltas grandes
entre amostras vizinhas por natureza) e pico da cauda dos one-shots
(fade real, não corte abrupto).

## Nota de honestidade

**Não ouvi nenhum destes arquivos** — não tenho capacidade de reproduzir
ou escutar áudio. Toda a validação foi feita por análise numérica do PCM
gerado: pico e RMS (sem clipping, corpo audível), continuidade amostra-a-
amostra na emenda dos loops, forma do envelope dos one-shots (ataque
suave, cauda decaindo perto do silêncio) e presença de energia nos
momentos certos da demonstração composta (partida, aceleração, alívio).
Os 5 `.wav` ficam disponíveis em `audio/monaliza_review/` para quem quiser
ouvir de verdade antes da integração.
