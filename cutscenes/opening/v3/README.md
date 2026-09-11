# Abertura V3 — a fotografia que viaja

Implementada em 11/09/2026. A cena de produção `cutscenes/opening/OpeningCutscene.tscn` usa esta versão. Filme de 68 segundos, precedido por 2,8 segundos de identidade RCM quando iniciado pela campanha.

## Direção e narrativa

A rotina de Dante é interrompida por uma notícia: o irmão saiu da prisão, foi visto em Harbor e desapareceu do contato. Dante leva a fotografia dos dois. O quadro vazio encerra a casa; a mesma fotografia reaparece no ônibus. A porta do ônibus abre e o jogo continua no desembarque, ainda de madrugada, com chuva. O irmão está vivo; a motivação é procurá-lo.

| Tempo | Ação | Função dramática |
|---|---|---|
| 0–6 s | Café, louça, vapor | Estabelecer uma rotina silenciosa |
| 6–13 s | Fotografia e caixa do antigo uniforme | Apresentar vínculo e passado |
| 13–18 s | Telefone e hesitação | Interromper a rotina |
| 18–31 s | Ligação, reação, pergunta e desconexão | Dar uma pista concreta e deixar uma dúvida |
| 31–38 s | Dante retira a fotografia | Tornar a decisão visível |
| 38–42 s | Mochila | Preparar a partida |
| 42–46 s | Quadro vazio, passos e porta | Encerrar o espaço doméstico |
| 46–53 s | Ônibus na estrada, à noite | Comunicar tempo e deslocamento |
| 53–61 s | Fotografia nas mãos, interior do ônibus | Manter o motivo emocional |
| 61–68 s | Terminal, freio pneumático e porta | Entregar a ação ao gameplay |

## Implementação

`opening_stage.gd` constrói os cenários 3D e anima câmera, rig de Dante, braços por IK, olhos, boca, objetos, rodas e portas. A foto é uma textura compartilhada pelo quadro e pelo papel nas mãos. São cenários e animação procedural em estética estilizada do jogo; não é um filme fotorrealista nem captura de movimento.

`opening_timeline.gd` centraliza os dez planos e eventos. `opening_controller.gd` conserva os sinais `finished`/`skipped`, destino `bus_terminal_arrival`, preparo sem autoplay, pausa, seek, replay e confirmação de pulo. O fim só é emitido uma vez, após o fade. O relógio começa após o primeiro quadro desenhado, fora da tela de carregamento. O mundo permanece pausado durante a apresentação.

As vozes e legendas acompanham português/inglês. O áudio é offline em três camadas: efeitos/ambiente, música e diálogo, respeitando os buses SFX/Music do jogo. Os arquivos de revisão e produção têm `.gdignore` e não são conteúdo do runtime.

## Assets e origem

- `assets/brothers_photo.png`: retrato renderizado dentro do Godot com `DantePreviewRig.gd` / `DanteVisualAdapter.gd`. Dante e o irmão posam juntos diante de uma garagem; o irmão usa uma variação terrosa do mesmo figurino e cabelo discretamente grisalho. Ambos preservam geometria, proporções e materiais do elenco do jogo. Esta versão substitui a imagem de aparência realista a pedido do usuário. A mesma textura é usada em todos os planos. Recriação: Godot `--path . --script res://tests/visual/render_opening_family_photo.gd`.
- Dante: rig e visual já existentes no projeto (`DantePreviewRig.gd` / `DanteVisualAdapter.gd`), com ajustes de pose e expressão limitados à cena.
- Ônibus: modelo de produção `HarborTransitBusModel.gd`; rodas e porta animadas na cena.
- Vozes sintetizadas: Microsoft Edge TTS via [edge-tts](https://github.com/rany2/edge-tts). PT: FranciscaNeural e AntonioNeural; EN: JennyNeural e GuyNeural. São vozes sintéticas, não gravações de atores. As seis fontes estão em `production/sources/`.
- Música e efeitos pontuais: composição e síntese originais em `production/build_audio.py`, incluindo café, papel, tecido, telefone, passos, porta e ônibus.
- Base urbana: `audio/living_city/street_0.ogg`, do banco do projeto. Fonte declarada CC0: Florian Reichelt, [Street ambience](https://freesound.org/people/florianreichelt/sounds/451734/), conforme `audio/living_city/SOURCES.json`.

O pico do mix de revisão PT é −7,47 dBFS; não há clipping no mix gerado. Isso não substitui aprovação auditiva em diferentes sistemas. O desenho sonoro usa síntese e ambiente de biblioteca, sem alegação de foley integralmente gravado em estúdio.

## Reprodução e manutenção

Abra `OpeningCutscene.tscn` para assistir isoladamente, ou inicie Novo Jogo para ver a sequência integrada. `review/opening_v3.mp4` é uma captura da reprodução natural no Godot, em 1280×720 a 30 fps, com som. Não é uma montagem de screenshots. Na conversão, o áudio recebeu +14 dB para compensar a atenuação das configurações locais capturadas (pico antes: −21,5 dBFS). O jogo continua respeitando os volumes escolhidos pelo jogador.

Para reconstruir áudio: Python com `numpy`, `scipy`, `imageio-ffmpeg` e `edge-tts`; execute `python cutscenes/opening/v3/production/build_audio.py` a partir da pasta do jogo. As fontes MP3 existentes são reaproveitadas; gerar novas falas requer rede. O script escreve OGG de runtime, masters WAV locais, métricas e o manifesto `voice_timing.gd` incluído por preload no jogo.

Para capturar vídeo, use o Godot com `--path . --resolution 1280x720 --fixed-fps 30 --write-movie cutscenes/opening/v3/review/opening_v3.avi --script res://tests/visual/render_opening_v3.gd`. Converta o AVI com áudio integrado para H.264/AAC. O teste visual por planos está em `tests/visual/capture_opening_v3.gd`.

Resultados da verificação em [review/VALIDATION.md](review/VALIDATION.md).
