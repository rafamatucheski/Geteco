# Música da oficina do Digo

`digo_blues_loop.ogg` é uma composição instrumental original criada para este
projeto, sem gravações, melodias comerciais ou amostras externas. A receita
determinística está em `tools/audio/compose_digo_workshop.py`.

- Blues/funk discreto, 84 BPM, 12 compassos em 4/4, 34,285714 segundos.
- Baixo, teclas elétricas, guitarra abafada e bateria sintetizados offline.
- Três repetições são renderizadas; o trecho central conserva as caudas do
  anterior e recebe reflexões circulares antes da exportação Vorbis.
- Stereo, 44,1 kHz; RMS 0,14 e pico aproximado 0,742 antes do bus Music.
- O player usa volume local de −18 dB, fade de entrada de 0,8 s e saída de 1 s.

O helper `DigoWorkshopMusic.gd` é dono de uma única voz, ativada pelo estado de
localização da sessão. Ele pausa o rádio do veículo pelo override de dono fraco
em `WorldAudio`, preservando estação e posição, e devolve esse rádio após o fade
ou imediatamente ao descarregar a sessão. Não existe síntese de música no jogo.

A prévia WAV e as medições da composição ficam em
`artifacts/tuning-design-20261019/workshop-music/`.
