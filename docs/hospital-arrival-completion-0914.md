# Encerramento da chegada ao hospital — 14/09/2026

A ambulância agora confirma a chegada à vaga e encerra a direção. Com paciente, desembarca a equipe e a maca e conclui a admissão depois de cruzar a entrada. Após a entrega, a equipe e a maca são removidas dentro do hospital; o veículo permanece disponível na vaga, com sirene, luzes de emergência e motor desligados. O retorno vazio também termina estacionado.

## Implementação

- `EmergencyVehicle.gd`: aplica a chegada hospitalar tanto ao transporte de paciente quanto ao retorno vazio. O estado de chegada impede novas manobras e a sirene não volta a tocar durante a espera pela admissão.
- `HospitalArrival.gd`: aceita uma pequena faixa de posições alinhadas, em vez de exigir convergência a 1,5 pixel. Preserva espaço no corredor de circulação e verifica o corpo real contra as colisões.
- `HospitalParkingSearch.gd`: quando a aproximação simples não cabe, procura uma sequência de avanços e rés com raio mínimo de 70 pixels. Usa o mesmo volume e margem da execução física, com busca limitada a 4.500 expansões e fatias de trabalho de aproximadamente 0,9 ms, verificadas entre expansões. Não gira o veículo parado nem o desloca lateralmente para encaixar.
- A manobra hospitalar reserva temporariamente a passagem pelo mecanismo existente de frenagem do tráfego. Um pedestre cruzando a entrada faz a ambulância ceder passagem por até oito segundos, preservando a trajetória; um bloqueio persistente leva a novo planejamento, considerando também os corpos dos pedestres. A execução segue os arcos calculados, inclusive durante trechos parciais entre frames.
- `HarborEmergencyDirector.gd`: verifica ocupação física e reserva exclusiva das vagas. Uma vaga obstruída pode ser substituída; duas vagas ocupadas não atribuem a mesma vaga a outra ambulância. A admissão é liberada ao concluir a entrega, sem desalojar a primeira ambulância.
- `MedicalRescueSequence.gd`: mantém o mesmo paciente até cruzar a entrada e termina após a entrega dentro do hospital. Elimina o segundo ciclo externo de carregar uma maca vazia. A distância de extração hospitalar não é mais encurtada por confundir uma posição deslocada com outra vaga; a vaga reserva deixa a folga correspondente junto à fachada.

Nenhuma alteração desta correção foi feita no HUD, no combate ou nos modelos dos personagens. Alterações simultâneas de outras tarefas foram preservadas.

## Verificações

`tests/test_hospital_arrival_completion.gd -- --road-arrival --capture` passou na cena HarborGame real:

- Primeira ambulância ajusta a parada no pátio e entrega seu paciente.
- Segunda ambulância chega orientada ao longo da rua, manobra pelo acesso físico e usa a vaga reserva, mantendo a primeira estacionada.
- Ambos os pacientes cruzam a entrada e ficam registrados no hospital; as duas sequências terminam em `parked`.
- Retorno vazio já dentro da vaga termina em até um segundo e permanece imóvel e silencioso durante mais sete segundos.
- Com as duas vagas ocupadas, nenhuma atribuição duplicada é feita; retirar o obstáculo torna a vaga disponível novamente.
- A sirene é verificada pelo estado real de reprodução do `AudioStreamPlayer2D`. O MP4 não contém áudio.

`tests/test_ambulance_parking_contract.gd` passou em 17 verificações, incluindo reserva de tráfego durante o retorno hospitalar, liberação ao estacionar e preservação/retomada da manobra quando um pedestre cruza a passagem. A gravação final do hospital tem aproximadamente 43 segundos e inclui uma pausa mostrando o estado concluído.

`tests/test_medical_choreography_continuity.gd -- --native-hospital` também passou: resgate, transporte, admissão, recuperação do mesmo NPC e reutilização do veículo, com identidade preservada e deslocamento visível máximo de 2,067 pixels.

O watchdog global desse teste foi ajustado de 100 para 150 segundos simulados: o diagnóstico mostrou a conclusão em aproximadamente 110 segundos após substituir o encaixe por giro/deslizamento por uma trajetória física. Os limites de acesso e de ausência de progresso de cada fase não foram afrouxados. A fixture usa uma vítima sobrevivente, de acordo com a separação atual entre atendimento médico e atendimento de óbitos.

Evidências em `D:/geteco/artifacts/ambulance-hospital-0914/`: vídeo `road-capture/hospital-completo.mp4`, quadros PNG, `motion.csv`, `report.json` e logs. Tentativas anteriores e seus diagnósticos foram conservados nessa pasta.

## Limitações

- Pátio completamente bloqueado ainda exige que alguma passagem ou vaga seja liberada. A ambulância aguarda silenciosa, sem atravessar sólidos ou concluir uma entrega fictícia. A busca finita não garante solução para toda combinação possível de obstáculos.
- Performance não certificada. As amostras exploratórias renderizadas registraram 40,05 FPS, p95 de 35,23 ms e p99 de 47,38 ms antes das alterações; uma execução posterior sem captura registrou 46,45 FPS, p95 de 30,21 ms e p99 de 34,83 ms. Não são um comparativo controlado da versão final: havia outras execuções do Godot, mudanças simultâneas na população e na geometria do mapa, e a última amostra antecede o ajuste de espera por pedestres. As gravações com leitura e gravação de PNG também não servem para aprovar FPS. A referência provisória continua sendo 60 FPS, no Godot 4.7.2 Mobile/Vulkan, RTX 4060 Laptop, 1280 × 720.
