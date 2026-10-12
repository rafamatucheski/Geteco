# Corredor urbano e linha 510

## Jogar de motorista — 10/10/2026

F continua sendo a entrada/roubo livre. B, junto à porta dianteira de um ônibus parado da linha, assume o trabalho sem retirar um motorista à força nem registrar roubo. O abre/fecha as portas na próxima parada. As ações são remapeáveis; no controle, D-pad direito assume o trabalho e Quadrado/X opera as portas. F encerra o turno ao sair; o ônibus emprestado mantém sua posição e pode ser retomado por B.

O painel mostra destino, distância, passageiros, paradas e ganhos; o minimapa acompanha a próxima plataforma. As três seções precisam estar alinhadas e o ônibus parado para abrir as portas. A partida fica bloqueada com portas abertas; o fechamento aguarda o embarque/desembarque real e espaço livre no vão. Cada parada concluída paga R$ 12 mais R$ 2 por passageiro embarcado; uma volta completa paga mais R$ 60. O objetivo avança antes de aceitar outro atendimento, impedindo pagamento repetido por alternar as portas. `bus_work` guarda o progresso no snapshot de frota. As saídas do ônibus projetam os pés sobre o piso real, inclusive plataformas elevadas, e aguardam a sincronização física do portão.

Validação em Godot 4.7.2 .NET, C# compilado: `test_bus_driver_shift.gd` **16/16**; `test_bus_driver_session.gd --next-stop` **24/24** em Main renderizada; regressão de roubo em Main **20/20**; controles/migração DualSense **26/26**. Foram atendidas duas estações reais, Docas e Cais, dirigindo entre elas sem teleporte. A volta completa/bonus foi exercitada no contrato isolado; não se certifica aqui o circuito completo das seis plataformas nem o novo ciclo de save/load da campanha. Fotos: `evidence/biarticulated/driver-20261010/`.

Performance comparativa permanece **inconclusiva** com alterações e processos concorrentes. Na estação equivalente (30 s), antes: 31,80 FPS / p95 64,291 ms / p99 92,232 ms; depois: 100,65 FPS / p95 14,904 ms / p99 18,234 ms. Não atribuir essa variação ao modo motorista. Com motorista e troca de passageiros ativos: 90,18 FPS / p50 11,814 ms / p95 16,984 ms / p99 19,455 ms, máximo 36,600 ms, 1 frame acima de 33,3 ms e nenhum acima de 66,7 ms; 2.706 frames em 30,007 s. RTX 4060 Laptop, Mobile/Vulkan, 1280×720, VSync ligado, limite 144. Amostras em `evidence/biarticulated/wheels-ads-20261010/{driver-before,driver-after}/` e `evidence/biarticulated/driver-20261010/performance.json`. Não há aprovação universal de FPS, noite ou todas as regiões.

## Roubo e direção do biarticulado — 10/10/2026

F junto à porta dianteira direita usa o roubo compartilhado de veículos: retirada do motorista antes de liberar o controle, reporte de crime pelo fluxo existente e saída/reentrada. A linha deixa de comandar o ônibus roubado. Os três corpos acompanham a direção e a ré, com limite de articulação e admissão conjunta de colisão. O ônibus não retorna à rota quando a cidade é reativada; aguarda admissão física da posição estacionada. O portão da plataforma fica aberto durante a retirada dos ocupantes. Passageiros desembarcam somente em pontos com piso e cápsula livre e permanecem visíveis enquanto estão próximos.

O arquétipo `biarticulated_510` preserva a família de áudio de ônibus e a durabilidade de 700. O snapshot inclui os dois ângulos relativos de articulação; a restauração/fábrica instancia o veículo de três corpos. `vehicle_position_clear` verifica piso e colisão de todos os módulos. A cabine reutiliza `VehicleInterior`, com medidas autoradas para o módulo dianteiro.

Godot 4.7.2 .NET, C# compilado, Main com prewarm de rotas nativo. Testes: `test_biarticulated_theft.gd` **20/20** (inclui JSON temporário gravado/lido, curvas, ré, engates e recusa de desembarque sem piso); `test_vehicle_carjacking.gd` **66/66**; `test_biarticulated_theft_session.gd --quick` **20/20** em Main renderizada após o ajuste final de piso. Cobertura integrada: um ônibus, plataforma das Docas, dia, roubo, passageiros, entrada, direção, saída, suspensão e retorno, reentrada. A retomada pode esperar colisões desaparecerem; o harness concede uma janela finita de 12 s e registra o bloqueador. Não valida campanha inteira, todas as plataformas, garagem, perseguição ou novo ciclo completo de save/load da sessão.

Performance **inconclusiva**: amostras de 30 s ao dirigir registraram 97,74 FPS / p95 15,758 ms / p99 17,723 ms e, na confirmação, 60,55 FPS / p95 57,303 ms / p99 98,663 ms. A confirmação teve outros jogos/testes renderizados, incluindo `measure_meshy_body.gd --mode=crowd`, além de mudanças concorrentes. Não há atribuição causal nem aprovação de regressão/FPS; a execução `--quick` serve somente para comportamento. Fotos e amostras: `evidence/biarticulated/theft-20261010/`. O ciclo temporário de FleetState não certifica o fluxo completo de save/load da campanha.

## Corredor e operação

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
