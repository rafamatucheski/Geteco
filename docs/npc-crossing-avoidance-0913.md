# Desvio de veículos parados em travessias

O teste `test_pedestrian_parked_crossing.gd` reproduziu um morador parado em
(0, -82) durante 660 ticks, com uma moto de colisão 20×40 no centro da
travessia. A espera por tráfego rejeitava veículos estacionados antes de
consultar a navegação. O corredor de centros de 14 px também não comportava
o contorno com o raio físico de 11 px.

Veículos com velocidade inferior a 1 px/s agora ficam a cargo da colisão e
da busca de caminho. Veículos em movimento continuam bloqueando a entrada.
O corredor de travessia permite até 28 px de deslocamento lateral do centro;
isso inclui a margem adjacente à pintura, sem alterar a geometria da rua.
A consulta espacial e a checagem de sinal usam o mesmo limite, corrigindo
também a possibilidade de ignorar o vermelho após um deslocamento lateral.
O orçamento compartilhado de busca permanece em 1 ms por frame.

## Evidências

Logs em `D:/geteco/artifacts/npc-crossing-0913/`:

- `parked-final.log`: seis verificações aprovadas, incluindo chegada à outra
  calçada, corpo fora da moto, deslocamento contínuo, limite lateral, veículo
  em movimento e sinal vermelho com o pedestre deslocado.
- `recovery-final.log`: regressões de poste junto ao meio-fio, recuo em rota
  fechada, progresso, pausas, encontro frontal e semáforo.
- `obstacles.log`: seis verificações de obstáculos aprovadas. Essa execução
  ainda registrou erro de compilação no autoload de atendimento médico.
- `parked-rendered.log`: comportamento aprovado com renderer Mobile, mas com
  o mesmo erro de autoload; não certifica integração visual da cidade.

Foram corrigidos dois erros sintáticos encontrados nos autoloads em edição:
tipo explícito de `candidate` em `CoronerCare.gd` e indentação do despacho
em `NPCMedicalCare.gd`. O teste final de travessia carregou sem esses erros.
O teste adicional `test_npc_medical_routine.gd` foi interrompido após
diagnóstico: sua cena só registra base de ambulância e mata o paciente,
enquanto o despacho atual solicita `coroner` para mortos. O log
`medical-routine.log` registra a ausência dessa base. A rotina médica não
foi aprovada nem teve suas expectativas alteradas nesta tarefa.

Desempenho na cidade permanece **não medido**. A tentativa de baseline em
HarborGame foi interrompida ao identificar outros testes renderizados e
benchmarks concorrentes; seus resultados não seriam comparáveis. Referência
mantida: 60 FPS / 16,67 ms, sinal de regressão acima de 5% em p95/p99, a medir
em janela estável de 30 s com aquecimento separado e máquina disponível.
Não se certifica todo NPC, obstáculo ou cruzamento com este caso local.
