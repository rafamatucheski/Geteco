# Disparos, impactos e chuva de fundo — 06/09/2026

Revisão posterior de 10/09: impactos corporais e gritos eletrônicos substituídos por gravações CC0 de pancada e voz. Fontes e reconstrução em [reactions/CREDITS.md](../reactions/CREDITS.md). O contato corporal não contém mais a vogal sintetizada descrita na atualização anterior.

Atualização de 10/09: cinco takes por família, doze/serrada reforçadas, reação curta de dor e materiais dos objetos integrados. Os detalhes e validações atuais estão em [vehicle-combat-feedback-0910.md](../../docs/vehicle-combat-feedback-0910.md). O restante deste arquivo documenta a entrega histórica de 06/09.

## Entrega

- Sete famílias de armas: pistola, Magnum, SMG, AK-47, M4A1, escopeta e cano serrado. Cada uma tem três takes originais, escolhidos sem repetição consecutiva, com pequena variação de afinação/volume. Transiente, corpo, mecanismo e reflexões curtas têm parâmetros distintos; as automáticas têm caudas mais curtas.
- Cinco materiais de impacto: metal, concreto, corpo, madeira e vidro. Metal/concreto/corpo estão conectados aos grupos existentes no Bullet. Madeira/vidro ficam disponíveis via metadata `impact_material` do collider; não se afirma que todos os prédios já tenham esses materiais autorados.
- Áudio de impacto posicional, enviado a SFX, com dez vozes por cena. Colisões muito próximas no mesmo intervalo de 40 ms compartilham um som, evitando excesso em chumbos de escopeta. Dano continua aplicado por projétil; apenas o áudio é agrupado.
- Chuva dez decibéis abaixo da versão que o usuário aprovou: `RAIN_TRIM_DB = -16.0`, antes -6.0. Trovão reduzido em 4 dB. Preferência persistida: **chuva deve ser fundo, sem dominar voz, motor e disparos**, inclusive quando visualmente forte.
- Chuva visual agora tem textura de rastro, orientação pela velocidade, gotas mais compridas/rápidas conforme intensidade, respingos elípticos com fade e região de emissão ajustada à câmera. Orçamento máximo de 620 gotas + 180 respingos. Não é simulação de água/molhamento físico nem de cobertura por telhados; são efeitos visuais limitados. Interior mantém emissão desligada.

São sons sintetizados offline, não gravações de armas reais. Não houve escuta direta pelo agente; a qualidade perceptiva deve ser julgada ouvindo a amostra. O usuário aprovou a textura da chuva anterior, e seus assets foram preservados: foi alterado o ganho.

## Integração e trabalho dos outros

`ProceduralAudio.gd` preserva as assinaturas dos getters existentes e eventuais overrides externos em `audio/gunshot_<arma>.wav/.ogg`. Os getters agora devolvem AudioStreamRandomizer, compatível com o retorno AudioStream já declarado. Consumidores não devem pressupor um WAV único nem extrair `.data` diretamente. APIs de motor, buzina, vozes, explosão, RPG, lança-chamas e ataque corpo a corpo foram preservadas. Essas últimas famílias não receberam novos timbres nesta rodada.

`Bullet.gd` chama o pool somente na colisão real, após a chamada de dano existente. Não foram alterados dano, velocidade, cadência, munição ou regras de explosão. A classificação de corpo inclui `gang_member`. Efeitos visuais de sangue/corpo e animações não foram reescritos.

Nos arquivos compartilhados `Player.gd`, `PoliceOfficer.gd` e `AnimatedPedestrian3D.gd`, a única edição desta rodada é `player.bus = &"SFX"` no helper `_play_audio()`. Também foi roteado o áudio de explosão do Bullet para SFX. Preserve essas linhas ao integrar os trabalhos em andamento. Não há alterações de UI nem commit.

## Verificação e amostras

- `tests/test_combat_audio.gd`: PASS. Exercita colisão física do Bullet com cinco materiais, verifica um dano de 15 por projétil e agrupamento apenas de áudio. Exercita `_shoot_towards()` na classe Player real com sete armas: consome uma munição e cria o player de áudio correto no SFX. Esse trecho chama a API de produção; não é uma sessão manual de mira/input. Verifica limites do pool e comportamento das partículas/interior.
- `tools/check_combat_audio.py`: PASS nos 36 WAVs e na gravação real do barramento SFX. Amostras mono posicionáveis, takes distintos, bordas suaves, pico de fonte até 0.61. Gravação mista de 22.15 s: pico 0.760, sem clipping; RMS de chuva forte isolada no início 0.0228. Isso não garante ausência de clipping em toda combinação possível de sons do jogo.
- `tests/test_weather_audio_mixer.gd`: reexecutado para conferir as transições e o abafamento com o novo volume.
- Capturas reais Compatibility, RTX 4060, 1280x720: `D:/geteco/artifacts/combat-audio/rain-light.png` e `rain-strong.png`, inspecionadas. Não foi feito benchmark de FPS; há limite explícito de partículas, mas não se declara custo zero nem 60 FPS estáveis.
- A campanha completa ainda encontra erro de parsing de Variant no arquivo externo `HarborArrivalMission.gd`, reproduzido por check-only nesta rodada. Os testes próprios de áudio/Player/Bullet e a captura de HarborPreview passam independentemente disso. Não se editou esse arquivo da frente de UI.

Ouvir `D:/geteco/artifacts/combat-audio/weapons-with-rain.wav`: 0–2 s só chuva forte de fundo; 2–16 s pistola, Magnum, SMG, AK, M4, escopeta e cano serrado em seções de aproximadamente dois segundos; 16–21 s metal, concreto, corpo, madeira e vidro; final só chuva. A gravação usa AudioEffectRecord no SFX com WASAPI, volumes reais do WeaponCatalog e as APIs públicas, em fixture isolada. Não inclui diálogo ou motores de uma campanha inteira.

Os logs ficam em `D:/geteco/artifacts/combat-audio/`. Avisos ambientais de certificados/preparação de saves são identificados separadamente. Não foram escritos slots nem configurações pessoais.

Scripts reproduzíveis: `D:/geteco/tools/build_combat_audio.py` e `D:/geteco/tools/check_combat_audio.py`. Referências de API: [AudioStreamRandomizer](https://docs.godotengine.org/en/stable/classes/class_audiostreamrandomizer.html) e [CPUParticles2D](https://docs.godotengine.org/en/stable/classes/class_cpuparticles2d.html).
