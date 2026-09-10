# Áudio do GTA Godot — Guia de Sons Necessários

## Como adicionar sons ao projeto

Coloque os arquivos de áudio nas pastas abaixo dentro da pasta do projeto:
`C:\Users\rafae\.gemini\antigravity\scratch\gta_godot\audio\`

O jogo carrega esses arquivos automaticamente em runtime — não precisa reimportar no editor.

---

## Arquivos Esperados

### Motor e Condução (pasta: `audio/`)

O motor **não precisa de arquivo**: `audio/VehicleEngineSound.gd` sintetiza cada
família em runtime. Ver a seção "Motor por família" abaixo antes de substituir
qualquer coisa aqui.

| Arquivo | Uso | Onde Baixar (Royalty-Free) |
|---|---|---|
| `engine_loop.wav` | Loop de motor genérico (tráfego ambiente, `ProceduralAudio`) | freesound.org: "car engine idle loop" |
| `engine_<familia>.wav` (opcional) | Substitui a família inteira por uma gravação | freesound.org: "car engine loop" |
| `vehicle/<id>_<familia>.wav`, `vehicle/<id>.wav` (opcional) | Substitui um veículo específico | Use os mesmos bancos de busca acima |
| `skid.wav` | Derrapagem de pneu | freesound.org: "tire screeching" |
| `vehicle/<id>_skid.wav` | Derrapagem de pneu por veículo (opcional) | Use os mesmos bancos de busca acima |
| `horn.wav` | Buzina | freesound.org: "car horn" |
| `vehicle/<id>_horn.wav` | Buzina por veículo (opcional) | Use os mesmos bancos de busca acima |
| `crash.wav` | Batida de metal | freesound.org: "car crash metal" |
| `vehicle/<id>_crash.wav` | Batida de metal por veículo (opcional) | Use os mesmos bancos de busca acima |

### Rádio (pasta: `audio/radio/`)
| Arquivo | Uso |
|---|---|
| `*.mp3` ou `*.ogg` | Qualquer música colocada aqui toca como rádio |

Tecla para trocar de faixa: **Enter** (enquanto dentro do carro)

---

## Sugestões de Sites Royalty-Free
- https://freesound.org
- https://pixabay.com/sound-effects/
- https://soundbible.com

Formatos suportados pelo Godot 4: `.wav`, `.ogg`, `.mp3`

> **Dica:** Para um loop de motor convincente, procure por "car engine loop" no freesound.org — há versões de .wav gratuitas e sem licença.

---

## Motor por família

`audio/VehicleEngineSound.gd` sintetiza o motor em vez de tocar um arquivo. Cada
família tem **três camadas** em rotações nominais diferentes (marcha lenta, meio,
alto giro) e o controlador cruza entre elas conforme o giro, esticando cada uma
no máximo ~2x. Um laço único puxado de 0.5x a 2.4x era a causa do timbre
"computadorizado": motor real muda de timbre ao subir de giro, não só de altura.

Cada camada é montada como a cadeia física do som: trem de pulsos de combustão
(um por cilindro, na ordem de ignição) → ressoadores de escapamento e carroceria
→ estalo de injeção (diesel), chiado de admissão e assobio de turbina/câmbio.

| Família | Quem cai nela | Caráter | Corte | Marchas |
|---|---|---|---|---|
| `street` | sedan, táxi, perua | 4 cilindros liso | ~6000 rpm | 5 |
| `sport` | esportivo, hatch, buggy, Monaliza | agudo, áspero, turbina | ~7400 rpm | 6 |
| `muscle` | Cobra V8, Stallion | V8 de virabrequim cruzado, borbulha | ~5400 rpm | 4 longas |
| `suv` | SUV, jipe, picape V8 | abafado, grave, "bum" de caixa fechada | ~5000 rpm | 6 |
| `diesel` | furgões | 4 cilindros diesel estalando | ~3400 rpm | 6 |
| `truck` | caminhões, limpa-neves, guincho | seis em linha, batida de injeção, turbina | ~2300 rpm | 8 curtas |
| `bus` | Route City | grave e oco, assobio de câmbio | ~2200 rpm | 6 |
| `fire_diesel` / `ambulance` / `police` | emergência | pelo `roof_prop` do catálogo | — | 7 / 5 / 6 |

A família sai de `family_for_vehicle()`, lida de `VehicleCatalog` (massa,
`engine_pitch`, `roof_prop`). Para mudar como um carro soa, ajuste o catálogo —
ou crie a gravação em `audio/vehicle/`, que tem prioridade sobre a síntese.

Uma camada de **rolagem de pneu e vento** sobe com a velocidade absoluta. Ela
existe porque, num carro real, quinta a 4000 rpm não soa como primeira a 4000 rpm
por causa desse ruído — não porque o motor mudou de altura. Sem ela, marchas
fisicamente corretas soam todas iguais.

Para ouvir e comparar as famílias:

```
"$GODOT" --path . --script res://tests/measure_engine_families.gd
```

Ele grava um relatório em `docs/measurements/engine_families.txt` e as camadas
soltas em `docs/measurements/engine_layers/*.wav` (não versionadas).
