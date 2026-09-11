# Direcao atual: imagens geradas da primeira CGI

A montagem usa sete imagens originais de `../frames/` e seis imagens novas geradas no mesmo estilo. Nenhuma captura de `assets/stills/` e usada. Consulte [a ampliacao](../frames/GENERATED_EXPANSION.md) e [a previa atual](review/opening_generated.mp4). O audio e os controles de reproducao foram preservados.

## Historico da tentativa anterior, substituida a pedido do usuario

# Abertura em fotografias — GETECO

A apresentação atual usa **25 imagens fixas, em 1920×1080, durante 86 segundos**. A pedido do usuário, a animação contínua foi substituída por montagem fotográfica. Os personagens preservam os modelos e materiais do jogo. Não há pessoas reais, interpolação de poses, movimento de câmera ou lip-sync durante a reprodução. Cortes, duas elipses em preto, vozes, efeitos e música conduzem a história.

## Montagem

| Tempo | Imagens e função |
|---|---|
| 0–13 s | Casa, café, retrato dos irmãos e Dante: rotina e vínculo |
| 13–18,2 s | Telefone no apoio e chamada desconhecida |
| 18,2–38,45 s | Escuta, notícia da soltura, pista da rodoviária e pergunta de Dante |
| 38,45–42 s | Linha desligada e telefone pousado |
| 42–51,2 s | Duas reações silenciosas: absorver a notícia e considerar a decisão |
| 51,2–56 s | Dante consulta uma foto dos irmãos na galeria do celular |
| 56–64 s | Saída pronta e apartamento vazio; a foto permanece no porta-retrato |
| 64–79 s | Dois planos de estrada, celular no ônibus e Dante olhando pela janela |
| 79–86 s | Rodoviária, freio e porta aberta: passagem para o gameplay |

## Reprodução

A cena continua sendo `../OpeningCutscene.tscn`, integrada ao Novo Jogo. `opening_controller.gd` exibe as texturas em `assets/stills/`; o palco 3D não é instanciado no runtime. Os controles de pausa, seek, replay, confirmação de pulo, sinais `finished`/`skipped` e destino `bus_terminal_arrival` continuam disponíveis. O mundo fica pausado durante a abertura.

`opening_timeline.gd` contém os 25 planos, durações e poses de autoria. `opening_stage.gd`, `opening_performance.gd`, `opening_hand.gd` e `opening_coffee.gd` são ferramentas de produção das imagens. O relógio de poses dessas ferramentas é independente da montagem final. Não reintroduzir o transporte da fotografia física: ela fica no quadro; a galeria do telefone usa a mesma textura.

Para regenerar as fotografias, execute Godot com `--path . --script res://tests/visual/render_opening_stills.gd`, seguido de importação. O plano de chamada possui uma variante em inglês. Para a prévia, use MovieWriter com `tests/visual/render_opening_v3.gd`. A prévia atual é [review/opening_stills.mp4](review/opening_stills.mp4); [review/storyboard_stills.jpg](review/storyboard_stills.jpg) reúne os 25 enquadramentos. Vídeos `opening_v3` e imagens `contact_`/`refined_` são revisões históricas da tentativa animada.

## Voz e som

O interlocutor é anônimo, masculino, dirigido como brasileiro de aproximadamente 65 anos, com rouquidão leve e preocupação contida. A fala atual é:

> Dante? Você não me conhece, mas escuta. Seu irmão saiu da prisão. Viram ele em Harbor, perto da rodoviária. Desde então, ele não atende o telefone.

Dante responde: “Quem tá falando?”. O interlocutor desliga. A voz é **sintética e ainda sujeita à avaliação artística do usuário**; a amostra anterior foi rejeitada como artificial. A versão atual foi produzida em uma tomada contínua, sem acelerar, engrossar o pitch ou adicionar distorção para simular idade.

- Interlocutor PT-BR: Qwen3-TTS VoiceDesign, modelo `Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign`, direção e seed em `production/sources/caller_direction_v2.json`. Fonte e documentação: https://github.com/QwenLM/Qwen3-TTS. Não é clonagem de uma pessoa real.
- `production/design_caller.py` gera a fonte; `align_caller.py` registra transcrição e tempos com faster-whisper. O reconhecimento confirmou o texto; Harbor foi transcrito foneticamente como “arbor”. Isso verifica conteúdo, não naturalidade.
- Dante PT: AntonioNeural; EN: AndrewMultilingualNeural e GuyNeural via edge-tts, sem mudança de pitch.
- `production/build_audio.py` produz os stems OGG e o manifesto de legendas a partir das fontes. A duração acompanha a fala integral. O runtime funciona offline, sem modelos de IA ou rede.
- Foley e música: síntese e composição originais. Ambiente urbano: `audio/living_city/street_0.ogg`, fonte CC0 declarada no banco do projeto (Florian Reichelt, Street ambience).
- Mix PT gerado: pico −7,44 dBFS. Música e efeitos respeitam os buses e configurações de volume do jogo.

O irmão recebeu cabelo curto, rosto sem barba e roupa oliva/azul para se distinguir de Dante. O retrato é produzido por `tests/visual/render_opening_family_photo.gd`, com o construtor de personagens do jogo.

Verificação e limitações em [review/VALIDATION.md](review/VALIDATION.md).
