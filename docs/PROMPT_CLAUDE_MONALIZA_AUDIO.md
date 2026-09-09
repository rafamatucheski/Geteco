# Claude — áudio exclusivo da Monaliza turbo

Crie sons originais para o primeiro carro pessoal do Dante, um cupê turbo de quatro cilindros preparado, azul e laranja. Trabalhe SOMENTE em audio/monaliza_review/ e tests/test_monaliza_audio.gd. A Astra implementa carro e controle; não altere VehicleEngineSound.gd, ProceduralAudio.gd, PlayerCar, scripts de carro, Player ou saves.

Entregue WAVs prontos: engine.wav (loop de motor encorpado, sem ser V8), turbo_spool.wav (loop de assobio discreto), turbo_release.wav (one-shot curto de alívio ao soltar acelerador após carga). Opcional ignition.wav. Pode gerar PCM procedural original; não baixe áudio protegido. Sem chiado contínuo alto, clicks de emenda ou clipping. Loop e pitch precisam tolerar RPM variável. Cache será responsabilidade da integração.

Crie test_monaliza_audio.gd verificando arquivos, duração, amplitude, continuidade das emendas e fade dos one-shots. Exporte uma demonstração composta de partida, aceleração e alívio para audição. Documente sample rate, volumes sugeridos, duração e limites, e declare se ouviu ou só analisou PCM. Não edite outros diretórios, não faça commit/reset nem desligue o computador.
