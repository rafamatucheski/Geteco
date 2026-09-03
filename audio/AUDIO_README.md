# Áudio do GTA Godot — Guia de Sons Necessários

## Como adicionar sons ao projeto

Coloque os arquivos de áudio nas pastas abaixo dentro da pasta do projeto:
`C:\Users\rafae\.gemini\antigravity\scratch\gta_godot\audio\`

O jogo carrega esses arquivos automaticamente em runtime — não precisa reimportar no editor.

---

## Arquivos Esperados

### Motor e Condução (pasta: `audio/`)
| Arquivo | Uso | Onde Baixar (Royalty-Free) |
|---|---|---|
| `engine_loop.wav` | Loop de motor do carro | freesound.org: "car engine idle loop" |
| `skid.wav` | Derrapagem de pneu | freesound.org: "tire screeching" |
| `crash.wav` | Batida de metal | freesound.org: "car crash metal" |

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
