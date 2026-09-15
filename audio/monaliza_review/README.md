# Monaliza — áudio e resposta de direção (10/09/2026)

O motor ao vivo usa cinco camadas exclusivas de seis cilindros em linha em
`audio/VehicleEngineSound.gd`, inspiradas no RB26 dos Skyline R33/R34.
A construção de escape parte do perfil Porsche já presente no jogo, com
dois coletores de três cilindros e pressão mais uniforme entre ignições.
O perfil `monaliza` usa camadas em 960, 1920, 3360, 5280 e 7440 RPM,
com marcha lenta em 900 RPM e limite de 7920 RPM. A mistura responde à
rotação, carga e troca de marcha, com faixa de crossfade mais estreita para
reduzir o esticamento das ressonâncias ao acelerar.
São sons sintetizados originais, não gravações de um carro real.

Referência de arquitetura: [Nissan — GT-R e Skyline](https://www.nissan.ca/vehicles/discontinued/gt-r.html).
Nenhum áudio de vídeo, jogo ou biblioteca externa foi incorporado.

O antigo loop único não substitui mais o controlador a cada quadro.
O turbo perdeu os osciladores de 1200/1215 Hz e o chirp do alívio: agora usa
fluxo de ar filtrado, bem abaixo do motor. O volume entra e sai gradualmente.
O alívio dura 0,38 s, tem intervalo mínimo entre disparos e termina em zero.
A Monaliza não dispara o estouro genérico de escape ao soltar o acelerador.
O turbo segue o mesmo GameInput da direção, incluindo controles remapeados.

Após cada subida de marcha sob aceleração, um flutter de 0,32 s toca quando
o corte de torque termina. São três pulsos de ar de intensidade decrescente,
com volume proporcional à pressão do turbo. O efeito não dispara ao manter
a mesma marcha, reduzir ou simplesmente soltar o acelerador; o alívio normal
continua com seu som próprio. Sair do carro cancela o som e qualquer disparo pendente.

Todos os loops têm quatro segundos e oito amostras de guarda depois de
loop_end para a interpolação do Godot. A síntese usa filtros circulares:
não achata a cauda do loop nem cria um buraco a cada repetição.

## Fontes e exportação

`MonalizaAudioKit.gd` gera partida, turbo e prévia offline.
`MonalizaAudio.gd` mantém os streams em cache no jogo; arquivos WAV antigos
não sobrescrevem as fontes. O controlador compartilhado gera e cacheia
as cinco camadas do motor durante a preparação do carro.

| Arquivo exportado | Duração | Uso |
|---|---:|---|
| engine.wav | 4 s + guarda | Marcha lenta para inspeção |
| turbo_spool.wav | 4 s + guarda | Sopro discreto |
| turbo_release.wav | 0,38 s | Alívio de pressão |
| turbo_shift.wav | 0,32 s | Flutter depois do engate da próxima marcha |
| ignition.wav | 1,30 s | Arranque e motor pegando |
| demo_start_accelerate_release.wav | 8 s | Demonstração offline |

PCM mono de 16 bits a 22050 Hz. Os WAVs exportados não preservam metadados de
loop; para reprodução no jogo, usar os streams gerados com loop_end e guarda.

Exportar com Godot: `--headless --path game --script res://audio/monaliza_review/export_monaliza_audio.gd`.

## Direção

O catálogo é a fonte da regulagem: aceleração 1380, máxima autoral 680
(máxima de rua 380,8 px/s), freio 1350. A resistência ao rolar é 120,
antes 600. Recuperar na garagem e restaurar um save reaplicam essa regulagem.
O carro mantém a física compartilhada de aderência, colisões e marchas.

O câmbio tem sete marchas. Segunda e terceira esticam até 48% e 70% da
máxima de rua (antes 41% e 60%). As marchas superiores trocam em 82%, 90%
e 96%, antes dos seus limites teóricos de giro. Separar os pontos de troca
das relações evita que uma marcha fique inacessível por exigir velocidade
acima da máxima do jogo. A sétima estabiliza perto de 5580 RPM na máxima,
com reserva até 7920 RPM. A redução usa os mesmos pontos, com histerese.

No teste com o controlador atual, a regulagem antiga (460/560) leva 2,58 s
para atingir 200 px/s; a nova leva 0,883 s. Partindo de 300 px/s, soltar
o acelerador por meio segundo deixa 240 px/s. O freio continua independente.

## Validação

- `tests/test_monaliza_drivetrain.gd`: aceleração, máxima, marchas, coasting,
  freio, fontes ao vivo, alívio, saída, restauração da regulagem e guarda.
- `tests/test_monaliza_audio.gd`: exportação, amplitude e envelopes.
- `tests/test_engine_loop_seam.gd -- monaliza-only`: mixer real, cinco
  camadas a pitch 1,82; zero picos de descontinuidade nas emendas.
- `tests/test_vehicle_engine_and_name.gd`: regressão das outras famílias.
- `tests/test_monaliza_starter.gd`: porta-malas e restauração de inventário.
- `tests/capture_monaliza_driving.gd`: grava o carro real em pista vazia,
  com partida, aceleração, alívio, retomada e desaceleração. Saída:
  `artifacts/monaliza-rb26-review/monaliza-rb26-shift-flutter.wav` na raiz do workspace.

A gravação de revisão é normalizada para audição e recebe fade nas bordas;
isso não muda o volume do carro no jogo. O timbre ainda requer avaliação
auditiva do usuário: os testes medem continuidade, amplitude e integração,
não equivalência com uma gravação real.
