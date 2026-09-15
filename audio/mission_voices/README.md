# Vozes das missões

O piloto do encontro e passeio do Maciota já usa sete tomadas neurais expressivas em português. Elas são síntese de voz, não gravações humanas reais, e continuam sendo um draft de integração. As sete tomadas contidas permanecem na pasta `ai_draft_2026-09-14` para comparação e eventual troca.

As gravações humanas ainda não foram produzidas ou aprovadas. Não apresentar as tomadas neurais como dublagem humana final.

Entregar WAV PCM, preferencialmente mono, 48 kHz/16 bits, sem música, ambiente ou efeitos impressos. Uma fala por arquivo, sem clipping, com pausas e intenção dirigidas para a cena. Começar pelo encontro e passeio do Maciota como cena piloto. A direção é uma voz masculina adulta, grave e levemente rouca, com carisma de rua, humor seco e autoridade amigável. Usar apenas traços gerais de um personagem de crime urbano; não pedir nem reproduzir a voz, os bordões ou a interpretação de Lamar ou de um ator específico. Dante pergunta com preocupação pelo irmão; Maciota fala com calma e familiaridade, sem caricatura exagerada.

`recordings.json` associa a chave SHA-256 de `persona.to_lower() + "|" + texto_exato` ao caminho `res://audio/mission_voices/arquivo.wav`. A chave é calculada por `ExpressiveVoice.recording_key`. Português e inglês têm chaves próprias. O manifesto atual aponta para as sete tomadas expressivas do draft; registrar separadamente elenco, autorização de uso e aprovação de cada tomada humana futura.

O carregador prioriza a gravação disponível sobre o áudio provisório. As fontes registradas no MissionVoiceMixer usam Dialogue; os demais sons recebem redução de 16 dB durante as falas, com respiro de 1,2 s e retorno gradual. O volume escolhido pelo jogador é preservado.

Em 14/09/2026 foi integrado o lote português do Dante em `dante_pt_2026-09-14`. Os onze arquivos nomeados foram associados ao texto exato da campanha: ligação (`M00_DANTE_01`, `DANTE_MM_02`), delegacia (`DANTE_MM_03` a `DANTE_MM_05`), encontro (`DANTE_MM_06`), garagem (`DANTE_MM_07`), primeiro favor (`DANTE_MM_08` a `DANTE_MM_10`) e a rota alternativa do banco fechado (`DANTE_MM_11`). A tomada `alternates/ElevenLabs_Jon_Oliveira_Shy_and_Apologetic.mp3` foi preservada sem associação porque o arquivo não identifica qual fala contém.

O lote do Maciota em `maciota_pt_2026-09-14` contém as dezoito falas do caminho principal, na ordem cronológica dos arquivos ElevenLabs: telefonema, encontro no ferro-velho, quatro falas do passeio, conversa completa da garagem, briefing do Primeiro giro e encerramento da entrega. Ele substitui os seis drafts do piloto no manifesto. A alternativa do banco fechado continua sem locução gravada neste lote.

Validar cada tomada por escuta no trajeto real com motor, trânsito, chuva, rádio e efeitos ativos, incluindo fala seguinte, interrupção e saída da cena. A lista de gravações vazia indica que nenhuma dublagem humana foi entregue.
