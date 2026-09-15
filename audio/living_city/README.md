# Bairro vivo e rádio — 10/09/2026

Gravações reais de rua, café, oficina, água e pássaros, com quatro músicas completas.
Os loops de ambiente duram 29/37 segundos e usam sobreposição de 2 segundos;
os eventos de gaivotas, aves e oficina têm três trechos alternados. O processamento
suaviza transientes de louça e metal, remove graves abaixo de 110 Hz nos ambientes
e mantém margem de pico. O runtime carrega os recursos em cache.

## Fontes e créditos

Todas as fontes abaixo foram disponibilizadas pelos autores sob
[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).
Os links de origem, downloads e SHA-256 estão em `SOURCES.json`.
Freesound: versões públicas de prévia em alta qualidade, convertidas e editadas.

| Uso | Obra / autor | Origem |
|---|---|---|
| Café e louça | Cafe Noise.WAV — alistair.i.macdonald | https://freesound.org/people/alistair.i.macdonald/sounds/156909/ |
| Oficina | metal workshop quiet.wav — Walter_Odington | https://freesound.org/people/Walter_Odington/sounds/26802/ |
| Pássaros | birds 3.wav — patchytherat | https://freesound.org/people/patchytherat/sounds/532146/ |
| Água | Ocean Waves.wav — Noted451 | https://freesound.org/people/Noted451/sounds/531015/ |
| Rua e mercado | Shopping Street Ambience — florianreichelt | https://freesound.org/people/florianreichelt/sounds/451734/ |
| Gaivotas | Seagulls-M.wav — DaveGould | https://freesound.org/people/DaveGould/sounds/32930/ |
| Porto FM | Empty Stretch — Zane Little Music | https://opengameart.org/content/empty-stretch |
| Porto Noite | (Basically not) Fusion Jazz — Julie Damsgaard / Spring Spring | https://opengameart.org/content/basically-not-fusion-jazz |
| Porto Groove | Wednesday Night — Zane Little Music | https://opengameart.org/content/wednesday-night-funk-fusion |
| Porto Brisa | Apple Cider — Zane Little Music | https://opengameart.org/content/apple-cider |

## No jogo

- Anchor Diner: café, louça, música vindo de um aparelho e dois clientes que
  caminham entre as mesas, param e gesticulam. O ambiente de conversa diminui
  quando esses clientes entram em pânico. São vozes indistintas da gravação,
  sem novas falas inteligíveis em português.
- Westgate Motor Co.: trabalho e rádio na fachada; fonte separada dentro da
  garagem. As duas representações não tocam juntas ao entrar no interior.
- Mercado, terminal, pátio e cais: fontes e camas distintas; pássaros diurnos,
  comércio mais quieto à noite e água gravada no cais. O freio de ônibus continua
  sincronizado às visitas/partidas reais do serviço já existente.
- Carros próprios e do trânsito: **R** percorre Porto FM, Porto Noite, Porto Groove,
  Porto Brisa e desligado. Botões de anterior/próxima e Mute/Ouvir clicáveis
  ficam visíveis enquanto dirige. Mute silencia apenas a rádio do veículo e
  mantém a música avançando; a escolha vale entre carros durante a sessão.
  Identificação persistente da estação; volume pelo controle Música; retomada
  ao sair e voltar ao mesmo carro. Segurar R não troca a cada quadro.
- Diálogos reduzem ambiente e música; fontes distantes param de decodificar.
  O porto desaparece gradualmente ao avançar para a montanha.

Cada estação tem uma faixa completa (2:21 / 4:06 / 2:57 / 3:20).
Locução, anúncios e boletins da campanha ficam para uma expansão editorial.
Não há serviço de streaming externo nem dependência de rede durante a partida.

## Reproduzir os arquivos

`python tools/build_living_city_audio.py` usa numpy, scipy e imageio-ffmpeg.
Depois, `python tools/expand_radio.py` acrescenta as duas estações novas e seus créditos.
O cache é local em `tools/.living_audio_cache` e não entra no Git nem no Godot.
O manifesto permite reutilizar downloads já verificados, sem nova consulta.
Arquivos finais e manifesto ficam em `audio/living_city`.

Teste: `--script res://tests/test_living_city_soundscape.gd`.
Acrescente `-- --capture` sem headless para gravar o percurso e suas imagens em
`docs/measurements/living-city-0910/`.
