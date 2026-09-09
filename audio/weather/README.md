# Áudio climático — primeira entrega, 06/09/2026

**Atualização posterior do usuário:** a textura foi aprovada, mas a chuva deve ser baixa e permanecer ao fundo. A rodada de combate reduziu o trim da chuva em 10 dB e o trovão em 4 dB, além de reforçar os efeitos visuais. Consulte `../combat/README.md` para o estado atual e a amostra atualizada. Os números, limites de partículas e gravação abaixo registram a primeira entrega.

Integrado ao `DayNightWeatherManager.gd` existente. Não há outro relógio nem outro controlador de clima. UI, veículos, Player, vozes e CGI não foram editados.

## O que mudou

- Três camadas estéreo: fundo de água, gotas com ataque/cauda e chuva densa. Loops de 13, 17 e 19 segundos, sem fade periódico para silêncio. São assets de síntese original, produzidos offline pelo script `D:/geteco/tools/build_weather_audio.py`; não são gravações de campo.
- Intensidade contínua: chuva leve/moderada varia dentro do estado 1, tempestade mantém estado 2. Os IDs existentes 0/1/2 foram preservados. `set_rain_intensity(0.25)` e `set_weather(1)` permitem experimentar chuva leve; 0.60 é moderada. O ciclo natural escolhe intensidade de 0.22 a 0.65 ao entrar no estado de chuva.
- Transições por alvo único, sem Tweens de áudio sobrepostos que deixavam callbacks antigos interromper a chuva reativada. Três segundos para percorrer toda a escala de intensidade.
- Interior mantém a chuva audível e distante: filtro de agudos com corte chegando a 850 Hz, redução do fundo e maior redução das gotas próximas, transição de 0.8 segundo. Usa `set_interior_mode()` já chamado por HarborGame.
- Duas caudas de trovão de 7/8 segundos, com pequena variação de afinação e atraso de 0.8–3.2 segundos após o relâmpago. Entrar/sair de interior não cria um novo relâmpago. Cancelar a tempestade cancela o disparo pendente.
- Barramento privado por instância, enviado a SFX; não filtra diálogo, arma ou motor. Respeita volume/mute de efeitos. Barramento e players são liberados ao remover o gerenciador.
- Mantidas as referências públicas `rain_audio` e `thunder_audio`. A opacidade das partículas acompanha a intensidade, sem aumentar quantidade de partículas. Atualização de luz não sobrescreve a animação do relâmpago nem escurece interior.

O mixer mantém três vozes de chuva e uma de trovão. Não aloca players nem sintetiza PCM por frame. A síntese antiga de ProceduralAudio permanece disponível a outros consumidores e foi usada para exportar a referência anterior.

## Amostras

- `D:/geteco/artifacts/weather-audio/rain-before.wav`: seis segundos da síntese antiga, repetindo o loop e aplicando os -12 dB usados pelo gerenciador para chuva normal.
- `D:/geteco/artifacts/weather-audio/weather-in-game.wav`: aproximadamente 36 segundos gravados pelo AudioEffectRecord no barramento real do novo mixer, depois do filtro. Godot 4.7.2, display headless, driver de áudio WASAPI. É uma execução isolada do WeatherManager, sem sons de tráfego/vozes da campanha.

| Tempo aproximado | Trecho |
| --- | --- |
| 0–6 s | Chuva leve |
| 6–12 s | Chuva moderada |
| 12–20 s | Tempestade e trovão |
| 20–26 s | Interior abafado |
| 26–32 s | Retorno ao exterior |
| 32–36 s | Dissipação até silêncio |

Não houve escuta humana pelo agente. A avaliação de naturalidade ainda depende de audição; validação matemática não substitui essa avaliação. Os arquivos permitem comparar e ajustar a direção sonora.

## Verificação

- `test_weather_audio_mixer.gd`: zero falhas; leve/moderada/forte, troca rápida claro/chuva, entrar/sair, filtro e ganho, trovão atrasado/cancelado, deserto seco, quantidade fixa de players e remoção do barramento.
- A execução isolada desativa os sons temporizados do autoload CityAudioManager apenas no teste. Antes disso, a sirene global iniciada durante a fixture deixava um WAV/playback retido ao encerrar. A execução final com verbose termina sem aviso de ObjectDB; o arquivo de produção CityAudioManager não foi editado.
- `tools/check_weather_audio.py`: PASS nos cinco WAVs, stereo, energia, margem sem clipping, média próxima de zero, continuidade dos loops e gravação real. Pico da gravação 0.436, sem saturação. RMS medido: leve 0.0209, moderada 0.0385, forte 0.0730, interior 0.0055; silêncio final zero. Fração de energia acima de 3 kHz cai de 0.370 para 0.006 no interior.
- `test_harbor_finish_lamps.gd`: 17 postes, zero falhas na cena HarborPreview; vínculo com os sinais de dia/noite preservado.
- `test_harbor_weather_readout.gd`: integração bloqueada pelo erro de parsing já presente no arquivo não editado `world/harbor/campaign/HarborArrivalMission.gd:362`: inferência de Variant em `var board := garage.get(...) ...`, tratada como erro. O check-only desse arquivo reproduz a falha independentemente da execução do mixer. Corrigir a tipagem na frente de UI e repetir o teste integrado. Não se declara HarborGame completo aprovado nesta entrega.

Logs e métricas: `D:/geteco/artifacts/weather-audio/`. Houve avisos ambientais de certificados/permissões do Godot; não foram tratados como falhas do mixer. Não foram salvos slots nem modificadas configurações pessoais. Sem commits. Não houve benchmark geral de FPS nem certificação visual nova do clima.

## Próximas etapas de áudio

Passos por superfície, equilíbrio com tiros/motores/vozes e ambientação urbana ainda não foram alterados. A rodada atual fecha o mixer e a primeira paleta de chuva/trovões. A avaliação sonora da campanha completa depende também de concluir a integração externa de UI.

Referências de API: [AudioServer](https://docs.godotengine.org/en/4.5/classes/class_audioserver.html) e [AudioStreamWAV](https://docs.godotengine.org/en/4.4/classes/class_audiostreamwav.html).
