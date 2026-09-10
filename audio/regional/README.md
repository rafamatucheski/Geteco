# Ambientes por região

Sucata: seis variações (três pancadas e três cascatas de peças), com intervalos
irregulares, posição nas pilhas do pátio e menos atividade à noite. O ambiente
pausa durante a entrega para preservar os efeitos sincronizados da prensa.

Neve: brisa de 31 s, vendaval de 37 s e três rajadas de 7 s. Transições suaves
seguem o clima; abrigo reduz o volume e filtra agudos. O mixer continua apenas
para encerrar streams quando o mundo contínuo suspende a montanha.

Rodovia: ondas no tabuleiro sobre água entre o porto e a serra; fade nas cabeceiras.
Usa `../living_city/water_1.ogg` e respeita a posição do carro, interiores e diálogo.
Todos os efeitos seguem o controle SFX. Nenhum download ocorre durante o jogo.

Fontes CC0-1.0, verificadas em 2026-09-10:

- [Metal Impact Sounds — Brian MacIntosh / BMacZero](https://opengameart.org/content/metal-impact-sounds): batidas originais e composições de peças caindo.
- [wind1 — Luke.RUSTLTD](https://opengameart.org/content/wind1): vento pré-renderizado em PureData pelo autor, editado em bases e rajadas. Não é gravação de campo.
- Ondas: [Noted451](https://freesound.org/people/Noted451/sounds/531015/), créditos e hash em `../living_city/SOURCES.json`.

`SOURCES.json` registra downloads, hashes, duração, processamento e níveis.
Reproduzir: `python tools/build_regional_audio.py` (numpy, scipy, imageio-ffmpeg).
Teste integrado: `tests/test_regional_soundscape.gd`; `-- --capture` grava o mixer
real em `docs/measurements/regional-audio-0910/` quando executado sem headless.
