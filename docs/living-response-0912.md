# Resposta da cidade — 12/09/2026

Pedido: polícia que escale e combata, pedestres que consigam circular e fugir,
socorro físico coerente e trânsito que suporte as ruas estreitas.

## Plano e responsabilidades

Cinco agentes por área: polícia; pedestres; trânsito; ambulâncias; bombeiros.
Integração central: frota, motos, minimapa, combate veicular, circulação compartilhada,
incêndio residual, rádio e testes no mapa real. Execução por etapas respeitando três
agentes auxiliares simultâneos. Alterações anteriores no workspace preservadas.

## Polícia

| Estrelas | Unidades simultâneas | Unidades mobilizáveis por perseguição | Intervalo reforço |
|---|---:|---:|---:|
| 1 | 2 | 4 | 10 s |
| 2 | 3 | 6 | 8 s |
| 3 | 4 | 10 | 6 s |
| 4 | 6 | 14 | 5 s |
| 5 | 7 | 18 | 4 s |
| 6 | 8 | 22 | 4 s |

Primeira unidade sai da delegacia quando disponível. Reforços de duas estrelas ou
mais preferem faixas fora da câmera, entre 520 e 1800 unidades, com espaço físico.
Na falta de faixa válida tentam a delegacia. Não há criação fora da malha viária.
O orçamento conta apenas despachos bem-sucedidos e persiste no save; matar a equipe
não o reinicia. Ele zera quando acaba a perseguição.

Uma estrela prioriza aviso/rendição. Fuga a pé mantida por seis segundos após aviso
e sob visão eleva a duas. Duas ou mais autorizam combate, inclusive contra carro.
Policial morto pelo jogador estabelece ao menos três estrelas.

Há oito viaturas e duas motos no pool; motos atuam nas estrelas baixas, com um único
policial e sem portas/escudo fictícios. Interceptores de nível três levam SMGs;
níveis superiores misturam patrulha e equipes com fuzil. Policiais têm tempo de
mira e pausas entre rajadas. Passageiros de viaturas podem disparar contra carro
em fuga, com dano moderado, cadência limitada e linha de visão.

Após o relato de moto sem desembarque, um teste físico reproduziu a causa:
a saída fixa à esquerda estava bloqueada por parede. A moto agora verifica o
corredor com o tamanho do policial e escolhe o lado livre antes do desembarque.
Sem corredor, tenta abrir espaço fisicamente. A renderização do piloto atualiza
ao montar/desmontar e sua IA não tenta usar cobertura de porta inexistente.
O mesmo cenário passou com parada automática, desembarque, dano por projétil e
reembarque físico; antes ficava sete segundos preso, sem causar dano.

A percepção tem alcance e verifica obstáculos. Sem contato, as unidades usam a
última posição conhecida. Busca dura 18 + 5 × estrelas segundos sem contato
(23–48 s). Ver o suspeito ou receber novo crime reinicia o prazo. O minimapa mostra
viaturas, motos e policiais a pé; a cor muda durante a busca. Interior usa posição
externa conhecida, sem seguir as coordenadas internas escondidas.

Um segundo relato revelou voltas infinitas em faixas circulares quando o alvo
ficava a mais de 160 unidades da rua. A chegada agora termina no ponto viário
mais próximo; esse estado não aciona marcha à ré por inatividade. Quando o alvo
está até 550 unidades desse ponto, policiais podem desembarcar e continuar a pé.
A direção freia para pontos atrás do veículo e para curvas curtas, reduzindo
órbitas. Teste físico reproduziu duas falhas antes da correção e passou cinco
verificações depois, incluindo desembarque para alvo a 440 unidades da rua.

## Pedestres e circulação

Pedestres antecipam encontros, mantêm lado consistente de passagem, pausam fora
das travessias e podem conversar brevemente com acompanhantes. A fuga usa também
passos curtos em corredores estreitos e o retorno encontra o segmento acessível
mais próximo, em vez de prender o pedestre na rota anterior.

A frota aleatória urbana prioriza carros, motos e vans. Caminhões de entrega são
limitados a dois e começam em vias longas/largas. Motoristas cedem lateralmente
quando há espaço dentro do asfalto e corpo/pedestre não bloqueiam. Eles continuam
liberando cruzamentos e trilhos. Após saída congestionada por seis segundos podem
usar outro conector legal e livre; reservas, sinais e destinos de táxi permanecem.

## Socorro e incêndios

Ocorrências médicas são ordenadas por gravidade e espera. Testemunhas inacessíveis
são substituídas; equipes que realmente enxergam a vítima também podem comunicar.
Observadores dispersam quando a ambulância chega para liberar a passagem da maca.
As duas ambulâncias podem atender; vagas fixas principal/reserva e fila de admissão
evitam que as duas ocupem a mesma vaga/porta. A equipe transporta a maca desde a
posição real do veículo. Interrupções preservam o paciente para nova tentativa.

Bombeiros reservam postos diferentes, somam progresso da água e respeitam paredes.
O trabalho já feito permanece ao reposicionar. Acesso impossível tem tentativa
limitada e intervalo antes de novo despacho. Ocorrências concluídas saem da fila.
Explosões deixam fogo residual por até 60 segundos: apagar não repara a carcaça.
O canhão de água do jogador contribui para o mesmo progresso.

Rádio usa falas originais sintetizadas em português com controle de frequência.
Polícia informa avistamento, reforço, viatura roubada, policial abatido e fim da
busca; socorro usa áudio posicional curto para despacho/conclusão.

## Validação

Testes comportamentais incluem projétil real e parede, rendição, orçamento e save,
travessia da mesma viatura para a montanha e volta, moto com desembarque real,
encontros/fuga de pedestres, tráfego cedendo sem atravessar corpos, fila e água
compartilhada. O teste `test_living_police_city.gd` usa HarborGame completo, tráfego
ativo, quatro estrelas e observa despacho/combate sem chamar reforços manualmente.

Na execução integrada headless, houve contato em cerca de dez segundos, seis
viaturas mobilizadas e dano real ao jogador. Os testes de polícia cobriram também
rendição, projétil bloqueado por parede, passageiro disparando e perseguição da
mesma viatura até a montanha e de volta. Uma execução anterior da travessia parou
antes da ponte; a execução instrumentada passou. Isso não certifica estabilidade
estatística de todas as rotas.

O fluxo médico completo passou tanto na vaga principal como na reserva: chamado,
resgate, transporte, passagem do paciente pela porta, retorno da maca, reembarque,
alta e reutilização. A identidade dos envolvidos permaneceu a mesma. A navegação
compartilhada foi corrigida em três pontos: recuperação física da margem de
contato, exclusões de colisão e dimensionamento dos postos pelo corpo real da maca.
Regressões finais de reação a tiros, fuga, circulação e rotinas de pedestres
passaram sem erros de script. Algumas fixtures registram recursos retidos ao
encerrar; isso permanece separado dos resultados comportamentais.

Logs desta integração e imagem renderizada da frota ficam em
`D:/geteco/artifacts/living-response-0912`. Testes funcionais não equivalem a uma
medição comparativa de FPS nem cobrem todas as combinações do mundo aberto.
O estado completo anterior não foi capturado, portanto não há baseline confiável
para certificar ganho ou ausência de regressão de FPS nesta entrega.

## Desempenho medido: pendente

Godot 4.7.2, renderer Mobile/Vulkan, RTX 4060 Laptop, limite 60 FPS e VSync
desativado conforme configuração carregada. HarborGame completo, tráfego ativo,
câmera no jogador parado em (1540,1168), quatro estrelas, cinco segundos de
aquecimento após carregar. Alvo provisório: 60 FPS / 16,67 ms.

| Execução | Frames / duração | FPS médio | p50 | p95 | p99 | Máximo | >33,3 / >66,7 ms |
|---|---|---:|---:|---:|---:|---:|---|
| Tela carregada 3440×1440 | 716 / 35,03 s | 20,44 | 41,58 ms | 93,86 ms | 156,28 ms | 636,80 ms | 489 / 105 |
| Janela fixa 1280×720 | 796 / 34,78 s | 22,89 | 35,85 ms | 83,63 ms | 144,17 ms | 538,52 ms | 471 / 101 |

Ambas passaram despacho/combate, mas falham no alvo de desempenho. As amostras
individuais estão nos arquivos `city-frame-times.json` e `city-frame-times-720.json`
do diretório de artefatos. A segunda execução incorpora as correções posteriores
de loop e de ciclo de vida do rig de pedestres, portanto não é uma comparação
isolada de resolução nem uma medição antes/depois da implementação inteira.
Reduzir a resolução não foi suficiente para atingir a meta; isso não identifica
sozinho a causa em CPU ou GPU. Primeira visita, noite/chuva e demais regiões não
foram certificados por esse cenário. Não foi alterada a qualidade global para
encobrir o resultado.
