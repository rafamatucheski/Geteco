# Corredor urbano e linha 510

Quatro avenidas do Harbor usam duas faixas por sentido: Westgate Drive, Dock Street, Foundry Avenue e Quay Boulevard. As demais ruas conservam sua configuração. O editor salva `lanes_per_direction` junto da largura; duas faixas exigem ao menos 12 m. O corredor implantado tem 14 m, com faixas de 3,5 m.

As seis estações existentes foram alinhadas à faixa externa do circuito. Postes que invadiam a pista foram deslocados; a fachada de roupas NorthFrontage3 recuou 2 m. A ligação do navio foi preservada deslocando Quay Boulevard para oeste. Market Street passou a terminar no centro da Westgate, eliminando o antigo prolongamento de cerca de 4 m dentro da faixa externa. O acesso estreito Westgate Service Lane conecta-se em z=120, afastando sua travessia da estação. As alterações estão no documento compartilhado do editor, com os identificadores originais.

Dois biarticulados circulam independentemente do jogador. Cada um tem 22,7 m, três corpos físicos, duas articulações, três portas, rodas e faróis. A trajetória dos reboques é pré-calculada; cada movimento verifica o volume dos três corpos antes de avançar. A reserva do cruzamento permanece até a traseira sair. Carros podem usar as duas faixas e ultrapassam pela faixa do mesmo sentido nas avenidas duplicadas.

A linha mantém 18 identidades de passageiros, filas, destinos, embarque e desembarque físicos. A capacidade operacional é 36 por ônibus, incluindo o jogador. A simulação distante mantém viagens e passageiros sem manter todos os atores físicos ativos. O funcionamento é das 05h às 02h; fora desse horário, os ônibus aguardam na próxima estação. O jogador embarca pela interação na plataforma e pede desembarque com E ou F. O serviço continua após sua saída.

As plataformas têm três portões sincronizados com as portas do ônibus. Piso, bancos e portões mantêm colisão; o fechamento aguarda a passagem ficar livre. O terminal rodoviário regional e os táxis continuam com suas operações próprias.

## Validação

- `tests/test_biarticulated_platform.gd`: piso e colisão dos três portões abertos/fechados e bancos das seis plataformas.
- `tests/test_biarticulated.gd`: faixas, alinhamento das seis estações e varredura do volume completo dos três corpos a cada 2 m do circuito real. Executar com `--no-save --skip-arrival --population=0 --no-traffic --no-dispatch` para isolar a geometria estática.
- `tests/test_biarticulated_service.gd`: jogador embarca, percorre as seis estações, passageiros embarcam/desembarcam, pedido de saída devolve controle e colisão.
- `tests/measure/measure_biarticulated.gd`: Main renderizada em 1280×720, estação de dia e cruzamento à noite; 8 s de aquecimento e 30 s de amostra por cenário. Evidências em `evidence/biarticulated/`.

## Resultados

O teste dirigido `test_biarticulated_service.gd -- --no-save --skip-arrival --westgate-only` passou **4/4** com população e tráfego normais: embarque, passagem pelo cruzamento entre as duas estações de Westgate e desembarque. A investigação anterior encontrou carros presos na conexão; foram corrigidos o prolongamento viário e a comunicação do estado dos reboques com o trânsito. Uma execução completa posterior excedeu o limite de tempo enquanto outras capturas/testes estavam ativos; não foi contada como aprovação. A execução final, sem outras verificações desta tarefa em paralelo, passou **5/5 com população e tráfego normais**, atendendo às seis estações, realizando trocas físicas e devolvendo controle/colisão ao jogador. Evidência: `evidence/biarticulated/traffic-final.log`.

Verificações aprovadas: plataformas e rampas **60/60**, geometria do circuito **8/8**, atendimento às seis estações e saída do jogador sem tráfego ambiente **5/5**, portas/lotação/horários **10/10**, suspensão e retorno de região **6/6**, ultrapassagem nas quatro faixas **6/6**, incluindo o reboque real do biarticulado parado. A inspeção de geometria foi isolada do tráfego: veículos em movimento são obstáculos legítimos, não falhas de largura da rua. Curvas físicas nas ruas editadas: **8/8**.

Regressões aprovadas: edição dos tubos **15/15**, semáforos **14 verificações**, editor de ruas **19/19**, serviços **20/20**, fachadas físicas **32/32**, desobstrução do trânsito **9 verificações** e operação da rodoviária **25/25**. O teste antigo de tubos passou a sondar a face externa segundo o winding horário do Godot. O piso estava invertido; a rampa não tinha colisão. Os testes agora incluem apoio pelo topo e subida/descida física, sem teletransporte pelo desnível.

A execução acelerada do teste de serviço não acelera o relógio dos semáforos. O pedido de saída é feito na sexta estação distinta; o circuito fechado completo é coberto separadamente pela varredura física. Tentativas anteriores que exigiam mais uma volta dentro do mesmo limite terminaram esperando sinais, sem concluir a etapa de saída. Os logs anteriores foram preservados.

Fotos reais: [embarque](../evidence/biarticulated/boarding.png), [cruzamento à noite](../evidence/biarticulated/after/junction_night/world.png), [Terminal Sul](../evidence/biarticulated/station_0.png), [Westgate](../evidence/biarticulated/station_1.png), [Centro](../evidence/biarticulated/station_2.png), [Foundry](../evidence/biarticulated/station_3.png), [Cais](../evidence/biarticulated/station_4.png), [Docas](../evidence/biarticulated/station_5.png). As seis plataformas foram inspecionadas separadamente em renderização real. Não há certificação integral de interiores por esta alteração.

### Performance: pendente

Godot 4.7.2, Forward Mobile, RTX 4060 Laptop, 1280×720, limite de 144 FPS. Cada célula abaixo mostra FPS médio / p95 / p99 em ms; os JSON guardam os intervalos individuais, aquecimento e configuração.

| Variante | Estação de dia | Cruzamento à noite |
|---|---|---|
| Cópia anterior | 137,0 / 10,12 / 17,77 | 143,8 / 10,27 / 10,66 |
| Primeira execução integrada | 96,9 / 13,97 / 20,63 | 131,5 / 11,68 / 12,66 |
| Controle atual sem serviço urbano | 116,9 / 11,94 / 13,14 | 121,2 / 12,08 / 25,56 |
| Confirmação com serviço | 113,2 / 12,92 / 14,49 | 59,2 / 11,45 / 402,45 |

Houve instâncias de testes e medição de logística portuária concorrentes durante a investigação, além de alterações simultâneas em outros subsistemas. A cópia anterior precede essas alterações. Portanto, a comparação não isola causalmente esta implementação. Mesmo o controle sem ônibus registrou uma travada de 1,28 s; a confirmação integrada chegou a 2,03 s. **A estabilidade de frame time não está aprovada.**

A instrumentação do controlador de ônibus mediu aproximadamente 0,16 ms por tick na estação e 0,12 ms à noite; isso não inclui custo de renderização nem todos os atores e não certifica FPS. A revisão também corrigiu retenção de streaming para os três corpos e para a célula antecipada pelo ônibus. Falta uma comparação sem processos concorrentes após esta última correção, com investigação das travadas se persistirem. Nenhuma redução global de qualidade ou iluminação foi usada para esconder o custo.

Evidências: `evidence/biarticulated/{after,control,confirmation}/`; a cópia anterior e seus resultados ficam em `evidence/biarticulated/baseline-project/`. Alguns encerramentos do Godot registraram recursos/RIDs remanescentes; os testes funcionais mais recentes não registraram erros de script durante a operação.
