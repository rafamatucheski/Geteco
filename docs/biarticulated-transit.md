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

## Revisão de 07/10/2026

O board `inv-050` corresponde a esta implementação existente, incluindo os dois ônibus e as seis plataformas. Foi corrigida uma falha de ciclo de vida: durante a mudança de região ou entrada num interior, a câmera ainda podia mostrar o ônibus da rua e impedir sua suspensão. O serviço agora retira imediatamente os três corpos físicos quando Harbor está desabilitada, preservando as identidades e retomando o mesmo ônibus no retorno. A proteção contra desaparecimento visível permanece para o descarregamento por distância dentro da cidade.

`tests/test_biarticulated_lifecycle.gd` reproduziu **3 falhas em 9 verificações** antes da correção e passou **9/9** depois. A fixture mantém a câmera explicitamente voltada ao ônibus durante a transição, caso ausente no teste anterior. Evidências: `evidence/biarticulated/task-20261007-lifecycle-{before,after}.log`.

O serviço urbano passou novamente **5/5 em Main renderizada com população/tráfego normais**: embarque, atendimento às seis estações, passageiros embarcando/desembarcando e saída com visibilidade/colisão do jogador restauradas. Fotos e log: `evidence/biarticulated/task-20261007-service/` e `evidence/biarticulated/task-20261007-service.log`. O relógio do serviço foi acelerado pelo harness; isso não é uma medição de FPS nem validação temporal noturna.

O baseline renderizado desta revisão, antes da correção, registrou **65,38 FPS / p95 25,512 ms / p99 32,900 ms** na estação e **75,06 FPS / p95 19,895 ms / p99 26,926 ms** no cruzamento noturno. Outras sessões iniciaram capturas durante a janela; não se atribui esse custo à linha 510 e o comparativo continua **inconclusivo**. Amostras brutas e capturas: `evidence/biarticulated/task-20261007-before/`. Isso não substitui a medição isolada pendente acima.

As viagens rodoviárias Harbor–Estação de Gelo–Cobre são um serviço regional separado (`runtime/regional/`). O grafo usa as vias autoradas e conserva o bloqueio da ponte norte até a última missão de Harbor. O teste de rede passou **20/20** com busca C# nas seis direções, seis NPCs sentados mais motorista, casco físico, faróis compartilhados por horário e participação no mixer de motor de ônibus. A varredura estática das seis rotas encontrou **zero bloqueios em 3.270 amostras**, com apoio obtido do piso físico: `evidence/regional-coach-clearance-49216-4847846/clearance.json`. Esses testes não certificam, isoladamente, a viagem dirigida, a aparência da cabine nem estabilidade temporal/performance.

A validação dirigida regional encontrou um gancho na curva de entrada do gelo: controles próximos limitavam o arco de mudança de faixa e faziam o ônibus voltar ao ramo de entrada. `CoachGraph` ajusta somente a geometria dessa aproximação, coalescendo controles suaves da mesma via; o grafo dirigido, os cruzamentos, o tráfego e as colisões permanecem ativos. A fixture de aproximação real passou após a correção (`task-20261007-coach-approach-repaired.log`). O teste de rede final passou **26/26**, acrescentando ausência de reversão nas duas entradas do gelo e docagem: parado, com a frente na plataforma e posição física próxima ao destino, mesmo havendo fila adiante. Um ônibus em movimento ou ainda a 48 metros da estação não conta como chegada. Log: `evidence/biarticulated/task-20261007-coach-network-final2.log`.
O percurso completo Harbor–Gelo corrigido chegou automaticamente e passou **73/73** na sessão integrada: `evidence/regional-ice-final.log`, fotos em `evidence/regional-session-43528-5918964/`. A nova varredura local das duas entradas examinou **182 poses sem colisão de casco**. Ela registrou uma sonda de apoio ausente/inclinada em `(704.2005, 0, -386.3814)`, antes do trecho alterado; persistiu após três frames de assentamento da região. Esse ponto não está certificado pela varredura e não foi corrigido por esta mudança, embora o percurso dirigido completo tenha passado pelo acesso. Evidência: `evidence/regional-coach-clearance-169028-4731619/clearance.json`; as outras amostras, incluindo a curva reparada, não apresentaram falhas.
