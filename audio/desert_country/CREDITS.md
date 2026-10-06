# Fronteira Country

Programação instrumental da rádio do deserto, com três músicas completas:

- **Country** — Alex McCulloch (Pro Sensory). [Publicação e licença CC0](https://opengameart.org/content/country).
- **Gone Fishin'** — Memoraphile @ You're Perfect Studio. [Publicação e licença CC0](https://opengameart.org/content/gone-fishin).
- **Beary Fishy** — Memoraphile @ You're Perfect Studio. [Publicação e licença CC0](https://opengameart.org/content/gone-fishin).

As publicações oferecem os arquivos sob [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/). Para as duas últimas músicas, a publicação oferece licenças alternativas; esta distribuição utiliza CC0. Autoria das gravações permanece com os artistas acima.

Adaptação para o jogo: normalização de volume, fades curtos nas extremidades, intervalo de 300 ms entre músicas e codificação Ogg Vorbis estéreo. Não há geração ou síntese em runtime. O programa completo volta ao início ao terminar; sair do carro interrompe a reprodução e guarda sua posição durante a sessão.

`SOURCES.json` registra URLs, hashes dos originais, durações, processamento e métricas do OGG distribuído. `tools/build_desert_country_radio.py` reconstrói o arquivo a partir dos originais. O jogo reproduz o arquivo local e não acessa a internet.
