# Desert Drag Circuit — ideia futura

## Visão

Criar no segundo mapa uma área noturna de corridas clandestinas no deserto: posto, oficina improvisada, trailers, carros preparados, público, música e iluminação de neon. O circuito deve funcionar como um sistema opcional de progressão da Monalisa, sem transformar o GETECO inteiro em simulador de carro.

Fora das Drag Races, a Monalisa continua simples e agradável de dirigir. A mecânica avançada de marcha, launch, temperatura e acerto fino fica concentrada nas corridas de arrancada, enquanto as peças conquistadas continuam afetando o carro no mundo aberto.

## Estrutura de progressão

- Duas primeiras corridas integradas à campanha para ensinar o sistema e apresentar a área.
- Depois, campeonato paralelo opcional com cerca de 2–4 horas de conteúdo adicional.
- Quadro de classificação **Desert 10**, começando como `UNRANKED` e avançando por desafios diretos ao piloto imediatamente acima.
- Corridas com entrada e premiação, incluindo apostas especiais de peças/protótipos, sem colocar a Monalisa da história em risco de perda permanente.
- Adversários com nomes, carros, personalidade e estilos de pilotagem próprios.
- Após o primeiro lugar, desbloquear pistas para o adversário secreto `#0 — The Nomad`.
- Recompensa final única: uma ECU da Monalisa que libera configuração real de launch RPM, shift light, boost e final drive.

## Vertical slice inicial

Antes de construir oficina, ranking e elenco de rivais, validar uma única Drag Race completa:

1. Staging e preparação da largada.
2. Controle de launch por faixa de RPM.
3. Saída com estados `PERFECT LAUNCH`, `SLOW LAUNCH` e `WHEELSPIN`.
4. Trocas manuais com zonas `NORMAL`, `GOOD`, `PERFECT` e `LIMITER`.
5. Feedback de `PERFECT SHIFT`, `EARLY SHIFT`, `LATE SHIFT` e `REV LIMITER`.
6. Física baseada nos parâmetros reais das peças da Monalisa.
7. Resultado da corrida e persistência do setup.

O vertical slice só deve evoluir para o restante do sistema se o núcleo de staging → launch → shift → resultado for divertido e legível.

## Peças e parâmetros reais

As peças não devem ser apenas níveis ou bônus falsos na interface. Cada instalação deve alterar o comportamento do veículo:

| Peça | Parâmetro principal |
|---|---|
| Intake | Resposta do acelerador |
| ECU | Limite de RPM e curva de potência |
| Exhaust | Potência em RPM alto |
| Clutch | Velocidade das trocas |
| Gearbox | Relações e perda entre marchas |
| Differential | Tração na largada |
| Tires | Grip |
| Suspension | Transferência de peso |
| Turbo | Potência e turbo lag |
| Intercooler | Manutenção da performance |
| Nitrous | Explosão temporária de potência |
| Weight reduction | Aceleração |
| Final drive | Relação entre aceleração e velocidade final |

O jogador deve poder escolher entre builds diferentes, como uma Monalisa forte nos primeiros metros ou outra que perde na largada e domina o final dos 800 m. Habilidade de pilotagem deve continuar relevante: upgrade não substitui launch e troca bem executados.

## Temperatura e acerto

Combinações agressivas de turbo e ECU devem gerar temperatura de motor e perda progressiva de performance em provas longas. Isso cria espaço para radiador, intercooler e oil cooler sem transformar o jogo em um simulador completo.

## Neon e identidade noturna

As corridas devem acontecer principalmente à noite, com contraste entre o deserto escuro e a área clandestina iluminada. A Monalisa pode receber um botão dedicado de `NEON ON/OFF`, funcionando também fora das corridas depois da instalação.

Possíveis opções visuais:

- Underglow simples, lateral ou completo.
- Intensidade ajustável.
- Cores desbloqueáveis.
- Kit especial obtido no Desert 10.

Manter estética tuner de 2001–2005, evitando RGB exagerado. O neon pode permanecer aceso por alguns segundos depois de desligar o motor e desaparecer suavemente.

## Diretrizes de implementação

- Preservar a identidade da Monalisa e sua dirigibilidade no mundo aberto.
- Fazer upgrades alterarem torque, lag, som, relações, grip e comportamento observável, não apenas números exibidos na UI.
- Usar aparência, iluminação, carros e ambiente para comunicar a cultura automotiva; evitar textos decorativos desnecessários.
- Garantir que recompensas do circuito continuem funcionando no mundo aberto.
- Manter o campeonato opcional depois das missões introdutórias.
- Tratar o `#0 — The Nomad` como encerramento especial, em estrada vazia, sem público e sem música.

## Fora de escopo por enquanto

Não implementar ainda oficina completa, ranking, apostas, rivais, temperatura, neon ou tuning avançado antes da validação do vertical slice de uma corrida.
