# Teste ElevenLabs — Dante e Maciota (20/10)

Vozes: Dante = "Otto – Intimidating and Aggressive" (`ycxdm1PRMs962FxyyuJ0`);
Maciota = "Lucas – Deep & Profound Narrator" (`GIuLCSVfgJaUuh7hYOY8`). Modelo `eleven_v4`, 1 take por fala.

- `plan.json`: as 51 falas (chegada, oficina, primeiros favores, Cobras) com a chave de
  `data/dialogue/voice-line-direction.json`, a fala `spoken_pt` e a indicação usada (a `intent` do roteiro;
  no Maciota, prefixo "ágil" porque a voz é lenta).
- `ledger.json` (e `ledger.tsv`): índice do plano (ou nome da variação) → flow → session_id → créditos.
  Os links assinados expiram em 2 h; para baixar de novo, consultar o status pelo session_id.
- Variações aleatórias: 4 tons do "Ai!" de dor do Dante (`80a833fa…`) e 3 tons do cumprimento
  repetido do Maciota (`873a8bd5…`).

Os áudios ainda **não** estão no jogo: o runtime lê `audio/mission_voices/directed/runtime.json`
(WAV mono PCM16 24 kHz, validação técnica e ASR). Revisão artística: pendente.
