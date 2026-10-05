# Produção da chegada de barco

Filme de 73 segundos, 1920×1080, 30 quadros/s. O cenário, a embarcação e Dante
são os recursos nativos do jogo. `FerryDirector.gd` dirige apenas a captura;
`FerryFilm.gd` reproduz o resultado e não instancia outra cidade em runtime.

## Roteiro e som

O início tem uma conversa tranquila com um passageiro. Dante veio encontrar o
irmão. Aos 29 segundos, o ambiente recua e ele recorda a ligação anônima sobre
Vicente ter saído da prisão e ter sido visto em Harbor. O passageiro chama sua
atenção para a atracação; a despedida devolve o tom cotidiano antes do cais.

As onze falas foram geradas localmente pelo Qwen3-TTS VoiceDesign, com direção
em português brasileiro para três vozes. Não há voz de pessoa real clonada.
`voices.json` registra texto, direção, arquivo e duração das tomadas utilizadas.
`transcripts.json` registra a conferência automática de inteligibilidade feita
com Whisper; isso não equivale a uma avaliação humana da interpretação.

A memória usa filtragem de telefone. Música original simples, água, motor e
chuva sustentam a viagem. Os efeitos são arquivos já existentes no projeto.
As tomadas têm duração natural, sem acelerar a fala para caber nos planos.

## Reprodução da produção

1. `generate_voices.py`: usa o ambiente local `tools/opening_voice_design`, GPU
   e os modelos previamente baixados em `tools/opening_voice_models`. Reutiliza
   as tomadas presentes em `takes/`; não exige rede nem chave de API.
2. `verify_voices.py`: confere as falas com Whisper local. Aceita IDs de falas
   para verificar somente uma tomada corrigida.
3. `python build_audio.py`: requer numpy, scipy e imageio_ffmpeg; gera os stems,
   PCM intermediários, `timing.json` e as legendas SRT.
4. Compilar `Harbor.csproj` e usar Godot **4.7.2 .NET**, com
   `--fixed-fps 30 --write-movie D:/geteco/artifacts/opening-ferry-night-20261003/source1080.avi`
   e `--script res://tests/capture/capture_ferry_opening.gd`, argumentos de usuário
   `--no-save --full-session --skip-arrival --output=D:/geteco/artifacts/opening-ferry-night-20261003`. Os overrides `.movie` preservam
   1080p sem modificar a resolução normal de gameplay.
5. `python encode_movie.py`: retira o aquecimento pelo marcador de frame salvo
   em `render.json`. Gera `arrival.ogv` com a voz embutida e uma prévia MP4 com
   mixagem completa e legendas PT/EN selecionáveis. O áudio da codificação vem
   do PCM original, evitando timestamp irregular na recodificação de Vorbis.

Os intermediários de vídeo e a prévia ficam em
`D:/geteco/artifacts/opening-ferry-night-20261003/`. `encode_movie.py --art` aceita
outra pasta de captura. Os PCM misturados são regeneráveis.
As tomadas usadas e suas direções permanecem junto dos scripts.

## Integração

`OpeningPresentation` mantém a propriedade da pausa e restaura o estado anterior.
Durante o filme opaco, suspende a renderização 3D oculta do viewport; restaura
exatamente o valor anterior no final, no pulo e na remoção da apresentação.
`FerryFilm` usa o relógio do vídeo para as legendas; confirmação de pulo pausa
vídeo e áudio juntos. A voz usa SFX, ambiente usa Ambient e trilha usa Music.
O relógio real de reprodução encerra a apresentação no trecho preto final
(150 ms antes do EOF), evitando o rebobinamento síncrono do Theora. O sinal
nativo de fim continua como fallback. Final e pulo entregam a mesma chegada a `Arrival`.
O checkpoint `opening_completed` existente preserva a compatibilidade dos saves.

Não há animação labial fonética: a atuação visual usa poses, respiração, olhar e
gestos dos rigs existentes. A revisão noturna usa chuva, luz prática no convés
e água contínua fora do raio de streaming. `FerryPhonePose` mantém o celular
preso ao osso da mão, com pose de antebraço e punho própria para segurá-lo.
`FerryPassenger` usa a malha e o rig de produção com identidade e roupa próprias.
Os figurantes da gravação têm posições dirigidas; as rotas do gameplay permanecem.

Novos jogos começam com a mesma noite chuvosa no desembarque. Carregar uma
jornada preserva o horário e o clima salvos. A geometria física do terminal
não é alterada pela direção de captura. O gravador verifica continuidade dos
ossos, deslocamento do aparelho e permanência dos figurantes nos 2.190 frames;
as métricas ficam em `render.json`. Isso complementa a revisão visual dos planos.
