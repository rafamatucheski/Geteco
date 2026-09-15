# Rodas, motores e impactos — 10/09/2026

## Revisão do esportivo após feedback sobre 0:11

O trecho de 8,4–16,4 s da primeira gravação é o `sport_coupe`. O usuário descreveu o alto giro como um liquidificador. O perfil tinha um oscilador contínuo na ordem 46 do ciclo, amplificado por saturação alta (3,4). Esse oscilador foi removido do esportivo. O novo perfil usa duas bancadas de três cilindros com ressonâncias próprias, menor saturação (1,55 no alto giro) e menos ruído de admissão. Os parâmetros de marcha e as outras famílias foram preservados nesta revisão.

Direção sonora: boxer de seis cilindros inspirado no Porsche 911, com referência conceitual à [descrição oficial do conjunto motor/escape do 911 S/T](https://newsroom.porsche.com/en/press-kits/911-s-t/Powertrain-and-performance.html). É síntese original, não uma gravação licenciada de Porsche nem uma reprodução acústica exata.

Prévia isolada atual: `D:/geteco/artifacts/boxer-sport-preview.wav` (8,21 s, acelera e alivia). No trecho comparável de aceleração, a fração de energia acima de 2 kHz caiu de 37,76% para 0,037%; pico total da nova prévia 0,155, sem clipping. Essa medição confirma a retirada do agudo dominante, não substitui a avaliação auditiva do usuário. Dados: `D:/geteco/artifacts/boxer-audio-metrics.json`.

Verificações: `test_vehicle_engine_and_name.gd` passou; `test_engine_loop_seam.gd -- sport-only` testa as três camadas atuais no mixer real. Logs em `D:/geteco/boxer-engine-validation.log`, `boxer-seams.log` e `boxer-capture.log`. A amostra completa anterior foi mantida para comparação; o novo timbre já está no código do jogo.

## Resultado

- O rig compartilhado abre caixas de roda na geometria da carroceria, considerando raio, largura e esterço máximo do pneu. Não desloca cubos nem reduz o esterço. O recorte é feito na montagem, usa cache e passa a ser a geometria original do sistema de dano/reparo.
- Marchas mais longas por família e sobremarcha com reserva de giro na máxima de rua. Variação discreta de carga/timbre em velocidade constante; loops de quatro segundos com variações de combustão, admissão e oito amostras de guarda na emenda. A curva física de aceleração e a velocidade máxima não foram alteradas.
- Cinco takes sem repetição consecutiva por arma/material. Doze e serrada têm mais corpo, pressão e ataque; a doze inclui mecanismo de bombeamento mais perceptível. Fontes sintetizadas offline pelo gerador existente `D:/geteco/tools/build_combat_audio.py`.
- Acertos em pessoas combinam contato, roupa e uma reação vocal curta sintetizada. Volume de impacto considera o dano, com ganho limitado. O pool continua limitado a dez vozes, agrupando contatos próximos de chumbos sem agrupar o dano.
- Uma resolução de material compartilhada entre som e efeitos visuais reconhece também paramédicos, bombeiros e agentes funerários, além de metadata no objeto pai. Árvores e carga de madeira receberam material autorado; tambores/carrinhos/estruturas metálicas mantêm contato metálico. Superfícies sem classificação usam concreto. Vidro é suportado por metadata; não se converte uma fachada inteira em vidro.

## Verificação

- `test_wheel_body_clearance.gd`: passou nos 14 modelos do catálogo. Cordas atravessando o volume real dos pneus não cruzaram triângulos da carroceria no centro nem nos dois batentes; repetido após dano e reparo.
- `test_coupe_wheel_mounts.gd`: passou, preservando cubos, pinças, giro e deformação.
- Captura Compatibility inspecionada: `D:/geteco/artifacts/wheel-clearance.png`, sedan e cupê nos dois batentes.
- `test_vehicle_engine_and_name.gd` e `test_vehicle_engine_layers_runtime.gd`: passaram. Famílias distintas, reserva de giro, variação de cruzeiro, camadas limitadas e desligamento ao sair do carro.
- `test_engine_loop_seam.gd`: 13 medições no mixer real, zero estalos detectados e zero resultados inconclusivos. Janela ampliada para cruzar a emenda dos novos loops.
- `test_combat_audio.gd -- combat-only`: passou nas colisões físicas, materiais, chamadas reais do Player, consumo de munição e limites do pool.
- `D:/geteco/tools/check_combat_audio.py`: 60 WAVs mono, limites de pico/bordas e takes distintos; gravação real de aproximadamente 30 s sem clipping. Isso cobre a sequência gravada, não toda combinação possível do jogo. Não houve avaliação auditiva humana nesta validação.

## Evidências e limites

Áudio: `D:/geteco/artifacts/driving-combat-audio.wav`. Ordem: sedan, esportivo, pistola, doze, serrada, AK, pessoa, metal, concreto, madeira e vidro. Aceleração controlada e APIs de áudio de produção; não é uma partida manual completa.

As suítes amplas também executadas têm duas verificações fora da cobertura acima que continuam falhando: a densidade de chuva em `test_combat_audio.gd` e quatro assertivas de ângulo mínimo (0,05 rad) nas curvas de trânsito em `test_vehicle_wheel_steering.gd` (medição de cerca de 0,042 rad). A lógica de inferência de esterço não foi modificada. Não se declara que essas suítes completas passaram.

Logs: `D:/geteco/wheel-body-clearance.log`, `wheel-clearance-mounts.log`, `engine-extended-gears.log`, `engine-extended-runtime.log`, `engine-extended-seams.log`, `combat-impact-upgrade.log` e `driving-combat-capture.log`.
