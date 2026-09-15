# Sirene, abertura de passagem e retorno à faixa

## Comportamento implementado

Os motoristas de carros percebem uma unidade prioritária aproximando-se por trás, começam uma curva para um espaço lateral livre, aguardam sua passagem e fazem outra curva para retomar a mesma faixa e o mesmo percurso. A detecção permanece ativa fora da câmera. A unidade mantém a sirene e pode buzinar para solicitar passagem.

O acostamento disponível é calculado a partir da largura real da estrada e da calçada desenhada. A manobra pode ocupar a calçada livre, mas valida todo o corpo e o espaço varrido durante as curvas contra pessoas, postes, veículos, edifícios e áreas de atendimento. Não há deslocamento lateral instantâneo nem remoção de veículos. O motorista não começa essa manobra em conectores, travessias ferroviárias comprometidas ou aproximações controladas por um sinal ainda sem autorização.

A ambulância calcula um desvio temporário e sua volta à estrada, preservando o destino do roteador. O fim do desvio considera a fila próxima inteira: voltar logo depois do primeiro carro podia colocar a ambulância atrás do segundo e reiniciar a disputa. São avaliados corredores alternativos e uma conexão curva para reencontrar a faixa. Cada passo verifica novamente os sólidos em movimento; um bloqueio interrompe o avanço e provoca nova tentativa, sem atravessar o obstáculo. Manobras de estacionamento já comprometidas conservam seu controle.

`EmergencyRoadManeuver.gd` compartilha a validação geométrica entre `TrafficSirenManeuver.gd` e `AmbulanceTrafficPassage.gd`. A validação incremental tem fatias de 700 µs e orçamento compartilhado de 2,4 ms por frame. Esses limites reduzem concentração de consultas; não constituem garantia de desempenho, porque uma consulta individual e a preparação da rota também têm custo.

O acesso emergencial ao estacionamento passou a considerar o pavimento real da calçada, mantendo a varredura do veículo e do espaço de serviço. Na integração da equipe, foi corrigida uma divergência adicional: a busca da formação ignorava pessoas, embora o movimento físico dos socorristas colidisse com elas. Cada integrante agora planeja com sua própria máscara física. HUD e regras de dano não foram alterados por este trabalho.

## Verificações realizadas

Godot 4.7.2. Os testes isolados usam os carros e a ambulância de produção em uma estrada de teste com largura e pavimento explícitos.

| Cenário | Resultado |
| --- | --- |
| `test_siren_passage.gd -- --two-cars --capture`, Vulkan | Passou: ambos cedem espaço, aguardam e retornam; ambulância desvia e retoma a faixa. Observação em movimento gravada. |
| `test_siren_passage.gd -- --two-cars --joining` | Passou: inclui entrada inicial da ambulância a 90 graus; monitora os três corpos. |
| `test_siren_passage.gd -- --two-cars --blocked-side` | Passou: poste bloqueia a primeira opção; ambulância escolhe corredor lateral de 95 px, ultrapassa a fila e retorna. Zero sobreposições; deslocamento máximo observado de 3,5 px por passo. |
| `test_traffic_emergency_response.gd` | Passou: prioridade, sentido de aproximação, processamento fora da câmera, recusa em conectores e sinal não autorizado, duas laterais ocupadas por pessoas, retomada após a unidade passar e seleção da frota pela largura. |
| `test_ambulance_parking_contract.gd` | Passou após a inclusão do pavimento da calçada: envelope de serviço, raio de curva, sólidos, percurso e reserva do estacionamento. |
| `test_medical_formation.gd` | Passou, incluindo o novo obstáculo na camada de pessoas. Antes da correção, a busca autorizava o passo, a equipe parava e o teste falhava. Depois, contorna a pessoa; zero contatos e apoios coordenados. |
| `test_rescue_junction.gd -- far-parking-people-fixed --near-post --far-parking --motion`, Vulkan | Passou: dois resgates no cruzamento real com unidades inicialmente estacionadas; a segunda parte da vaga distante `(1939.899,1981)`. Ambas as vítimas embarcaram, zero violações de sólidos observadas. Antes da correção da máscara, a mesma vaga produzia `patient_inaccessible`. |
| `test_rescue_junction.gd -- siren-integrated-final --near-post`, Vulkan | Passou na execução final: primeira equipe inicialmente estacionada junto ao semáforo, segunda ambulância despachada do hospital com condução e estacionamento nativos. Ambas as vítimas em `transport`, segundo embarque confirmado com ambos os socorristas a bordo, zero violações de sólidos registradas. |

Vídeo da passagem com dois carros: `D:/geteco/artifacts/siren-passage/sirene-desvio-retorno.mp4`. É uma demonstração isolada de tráfego, sem áudio, com os intervalos reais das capturas preservados; não representa um resgate completo no mapa. Contato visual das fases em `manobra-em-movimento.png`, no mesmo diretório.

Vídeo adicional no mapa: `D:/geteco/artifacts/rescue-0913/resgate-vaga-distante.mp4`, câmera fixa no cruzamento. A chegada desde o hospital não faz parte dessa gravação; as equipes começam estacionadas e a vaga distante fica fora do enquadramento. O registro comportamental acompanha também o retorno e o embarque fora da câmera.

## Limites da entrega

A chegada autônoma da segunda ambulância desde o hospital, seguida de dois resgates no cruzamento real, **passou na execução final** depois da correção da camada de pessoas. O teste manteve a exigência de ambas as vítimas transportadas em 95 segundos. As execuções anteriores falharam: a saída do hospital e a seleção de uma vaga entre ônibus e estruturas da estação variaram; em outra, a unidade desembarcou e ficou bloqueada na aproximação da vítima. Esses fracassos não foram apagados nem convertidos em aprovação. A execução final comprova esse caso observado, não a resolução de congestionamento arbitrário.

Ônibus articulados continuam com seu controlador próprio e não executam a nova curva lateral dos carros. Não foram certificados todos os cruzamentos, ferrovias, tipos de veículo, combinações de congestionamento ou oclusões visuais de veículos na calçada. A verificação de profundidade dos socorristas junto ao semáforo permanece separada, documentada em `medical-rescue-0913.md`.

## Desempenho observado

Renderer Forward Mobile/Vulkan, RTX 4060 Laptop, 1280×720, limite 60 FPS, VSync desligado. Amostras sem captura contínua, obtidas na cena real; outras tarefas alteraram o mapa de 38 para 40 estradas durante o trabalho, e outras instâncias estavam ativas. Portanto, **não são um benchmark isolado antes/depois nem aprovação da meta de 60 FPS**.

| Amostra em `artifacts/rescue-0913` | Duração | FPS médio | p95 | p99 | Máximo |
| --- | ---: | ---: | ---: | ---: | ---: |
| `siren-before-frames.json` | 93,94 s | 22,56 | 83,57 ms | 189,48 ms | 2231,37 ms |
| `siren-pavement-final-frames.json` | 94,84 s | 37,95 | 41,05 ms | 67,00 ms | 433,75 ms |
| `siren-access-diagnostic-frames.json` | 94,82 s | 45,40 | 33,60 ms | 41,85 ms | 355,44 ms |
| `siren-integrated-final-frames.json`, dois resgates concluídos | 80,72 s | 42,86 | 35,22 ms | 47,90 ms | 215,85 ms |

Ausência de regressão de p95/p99 permanece sem comprovação em condições comparáveis. Alguns testes isolados também avisaram sobre objetos ainda vivos na saída; não se certifica limpeza de teardown por esses testes.
