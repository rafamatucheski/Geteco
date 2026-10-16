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

## Segunda montagem (16/10/2026)

O porto mudou depois da primeira captura (viaduto sobre o canal, passarela do
terminal, fachadas pintadas), e os planos antigos passaram a ter pilares na frente
dos rostos. A segunda montagem mantém as mesmas onze falas nos mesmos instantes
(PT e EN continuam sincronizados) e refaz só a imagem e as camadas de ambiente:

- 14 planos: descida aérea pelo canal ao lado do Northstar; travelling rente à água;
  conversa no convés; "Tempo demais" por cima do ombro, olhando o caminho percorrido;
  a balsa entra na sombra do viaduto e a lembrança começa ali.
- A lembrança fica fria e dessaturada (`adjustment_*` do Environment, só na captura).
  Em "ele foi visto em Harbor" o filme corta para **Vicente** de costas na rua do
  cais, parando sob o poste; o rosto fica para o jogo.
- Volta ao presente por cima dos contêineres do cargueiro, despedida e Dante
  andando até a amurada da popa enquanto a câmera sobe até a cidade.
- A balsa desce o canal e entra **de proa** na vaga: a vaga entre o píer e o
  cargueiro tem ~16 m e não comporta o giro da primeira montagem.
  `capture_ferry_opening.gd --check-route` varre a caixa do casco acima da linha
  d'água contra os sólidos; só restam contatos com a passarela no próprio berço,
  que existem também na posição de jogo da balsa.
- Som: camadas gravadas de porto, mar aberto e chuva fraca (`audio/ambience_el`),
  apito, sino de boia, viaduto, trânsito atrás de Vicente, contêineres na
  atracação e um pad grave sob a lembrança. A margem voz/fundo por fala ficou
  entre 8,5 e 16,6 dB (RMS no intervalo de cada fala).

## Reprodução da produção

1. `generate_voices.py`: usa o ambiente local `tools/opening_voice_design`, GPU
   e os modelos previamente baixados em `tools/opening_voice_models`. Reutiliza
   as tomadas presentes em `takes/`; não exige rede nem chave de API.
2. `verify_voices.py`: confere as falas com Whisper local. Aceita IDs de falas
   para verificar somente uma tomada corrigida.
3. `python build_audio.py`: requer numpy, scipy e imageio_ffmpeg; gera os stems,
   PCM intermediários, `timing.json` e as legendas SRT.
4. Compilar `Harbor.csproj` e usar Godot **4.7.2 .NET**, com
   `--fixed-fps 30 --write-movie evidence/intro-v2-20261016/movie/source1080.avi`
   e `--script res://tests/capture/capture_ferry_opening.gd`, argumentos de usuário
   `--no-save --full-session --skip-arrival --verify-work-routes --output=<mesma pasta>`.
   Os overrides `.movie` preservam 1080p sem modificar a resolução normal de gameplay.
   `--stills` (com `--times=3,9.5,...` opcional) grava quadros soltos para revisar
   planos sem gravar o filme; `--check-route` só confere a rota da balsa.
   `--probe=x0,z0,x1,z1` imprime um mapa livre/ocupado (cápsula de pessoa, passo de
   0,5 m) para traçar rotas de figurantes quando o cais muda.
5. `python encode_movie.py`: retira o aquecimento pelo marcador de frame salvo
   em `render.json`. Gera `arrival.ogv` com a voz embutida e uma prévia MP4 com
   mixagem completa e legendas PT/EN selecionáveis. O áudio da codificação vem
   do PCM original, evitando timestamp irregular na recodificação de Vorbis.

Os intermediários de vídeo e a prévia ficam em
`D:/geteco/artifacts/opening-ferry-night-20261003/`. `encode_movie.py --art` aceita
outra pasta de captura. Os PCM misturados são regeneráveis.
As tomadas usadas e suas direções permanecem junto dos scripts.
`--movie-output CAMINHO.ogv` permite revisar a codificação antes de substituir
o `arrival.ogv` utilizado pelo jogo.

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
`FerryHarborActivity` dirige o trabalho dos estivadores nas rotas existentes,
um carregador entre as caixas do terminal, os três guindastes, os pescadores
e o balanço dos barcos atracados. O relógio é o mesmo do filme. Os barcos de
pesca são separados do lote estático apenas na captura, para casco, bancos e
motor acompanharem o movimento juntos. Esses controladores não rodam no jogo.
O trabalhador do corredor da passarela usa somente o trecho plano na tomada,
sem atravessar a borda elevada da plataforma. O carregador junto ao guindaste
fica no cais residente, sem depender do piso de um navio sujeito a streaming.
`capture_ferry_opening.gd` com `--check-work-routes` verifica piso e sólidos;
`--verify-work-routes` faz essa verificação antes de gravar o filme. Ambos
exigem a cena renderizada; o renderer
dummy headless não fornece os transforms dos MultiMeshes usados nesta captura.

A captura desativa também os modos explícitos dos serviços filhos: suspender
só a raiz não impede um serviço `ALWAYS` de alterar o turno ou remover atores.
As luzes locais são resolvidas no horário noturno antes de manter suas posições.
Os passageiros gerados pelo gameplay ficam ocultos durante a tomada, que tem
elenco próprio a bordo; isso evita figurantes suspensos sobre a água.

Novos jogos começam com a mesma noite chuvosa no desembarque. Carregar uma
jornada preserva o horário e o clima salvos. A geometria física do terminal
não é alterada pela direção de captura. O gravador verifica continuidade dos
ossos, deslocamento do aparelho, permanência dos figurantes estacionários e
movimento efetivo dos trabalhadores e guindastes nos 2.190 frames; as métricas
ficam em `render.json`. Isso complementa a revisão visual dos planos.
