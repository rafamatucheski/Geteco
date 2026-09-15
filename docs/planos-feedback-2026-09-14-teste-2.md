# Planos — Geteco teste 2, 14/09/2026

Estado: alterações implementadas e fluxo de missão validado. A eliminação dos congelamentos gerais e a produção da dublagem humana continuam pendentes. Resultados e evidências em [resultado-feedback-2026-09-14-teste-2.md](resultado-feedback-2026-09-14-teste-2.md).

## 1. Congelamentos intermitentes — prioridade crítica

- Reproduzir nas duas primeiras missões e em circulação livre, registrando o momento e o estado do jogo. Separar congelamento de renderização de carro/NPC preso com o mundo ainda funcionando.
- Medir a cena real renderizada: primeira passagem e retorno, na mesma máquina, configuração, rota e população. Usar janelas finitas de pelo menos 30 segundos que cubram os eventos relevantes.
- Correlacionar picos com streaming, criação de veículos/personagens, áudio, física e rotinas de tráfego. São hipóteses, ainda sem causa demonstrada.
- Corrigir o subsistema identificado; distribuir trabalho, preparar recursos ou reutilizá-los somente conforme a evidência.
- Conclusão: comparar antes/depois com frame time p50/p95/p99, máximo e frames acima de 33,3/66,7 ms; eliminar os congelamentos reproduzidos sem regressão funcional. Usar 60 FPS/16,67 ms como alvo provisório no hardware registrado, sem certificar cenários não medidos.

## 2. Segunda missão: trajeto livre e ritmo mais cuidadoso — prioridade alta

- Identificar a segunda missão na sequência efetivamente jogada e reproduzir o ponto onde o carro ficou preso antes de escolher o controlador a alterar.
- Reservar temporariamente os trechos necessários da rota: impedir novos veículos de entrarem e conduzir os existentes para fora ou por um desvio seguro. Manter o restante da cidade funcionando. Liberar a reserva ao concluir, falhar ou cancelar a missão.
- Em um bloqueio persistente, permitir que Maciota use a contramão ou a calçada quando houver espaço. Verificar o carro inteiro contra a geometria pavimentada e os sólidos, reduzir a velocidade na calçada, reavaliar pedestres durante a manobra e retornar à rota sem teletransporte.
- Retardar o início dos diálogos e dar respiro entre falas. Sincronizar legenda e voz, respeitar a duração do áudio e evitar iniciar falas importantes no meio de manobras.
- Reduzir a presença do motor e desacelerar o ritmo das trocas de marcha, com aceleração e curvas suaves. Usar a experiência da Monaliza como referência de cuidado; distinguir trocas mecânicas de mudanças apenas no som antes de ajustar.
- Conclusão: completar o trajeto com via inicialmente livre e com tráfego preexistente, sem bloqueio, colisões forçadas, teletransporte ou perda de falas; conferir restauração do trânsito também após interrupção/reinício.

## 3. Primeira missão: embarque e estacionamento do Maciota — prioridade alta

- Atualizar aproximação, orientação e posição final de estacionamento com base na localização atual da garagem; evitar depender de coordenadas antigas.
- Encadear aproximação à porta, abertura, embarque, acomodação, fechamento e partida, sem saltos de posição. Carregar a skill criar-bonecos-dante antes de alterar animações de personagens.
- Suavizar aceleração, esterçamento e trajetória da curva; sincronizar câmera e devolução de controle.
- Garantir área livre para estacionar, desembarcar e acessar a garagem, seguindo o contrato de colisão e profundidade. Validar ambos separadamente e preservar as regras de proteção dos personagens e de armas na garagem.
- Conclusão: revisar a sequência completa em movimento e testar embarque, estacionamento, saída e retomada após interrupção. Reutilizar os testes pertinentes de campanha/embarque e executar test_garage_weapon_restrictions.gd se as transições da garagem forem alteradas.

## 4. Falas audíveis e dublagem humana — prioridade alta

- Planejar dublagem humana para os diálogos das missões, começando pelas duas primeiras, com interpretação e direção cuidadosas.
- Dar prioridade às vozes: enquanto houver fala dublada, reduzir todos os demais grupos de áudio — ambiente, veículos, trânsito, rádio, música, buzinas, sirenes e efeitos. Aplicar redução suave, configurável por grupo, mantendo as falas claras e sem distorção.
- Manter a redução entre falas próximas para evitar oscilações de volume; restaurar suavemente os níveis definidos pelo jogador ao encerrar ou interromper o diálogo, cancelar a missão ou mudar de cena. A dublagem não deve reduzir o próprio volume.
- Revisar as duas primeiras missões em movimento, com os demais sons ativos, e aplicar a mesma regra às outras missões dubladas. O ajuste do sedã M8 no plano 8 deve integrar esta mixagem.
- Preparar roteiro por personagem, intenção de cada fala, pausas e lista de arquivos para gravação humana. Fazer uma cena piloto com direção e revisão de interpretação antes de gravar o restante.
- Conclusão da mixagem: diálogos compreensíveis durante o trajeto, sem cortes ou picos, com legendas sincronizadas. Conclusão da dublagem: gravações humanas aprovadas e integradas. Esta etapa depende de elenco, orçamento e gravações; planejamento não equivale à contratação nem à produção do áudio.
- Verificar todos os grupos de áudio, falas consecutivas e interrupções: nenhum som deve disputar volume com a voz, e nenhum grupo deve permanecer atenuado após o diálogo.

## 5. Semáforos: ciclos mais rápidos e melhor acabamento — prioridade média

- Interpretar “mais rápidos” como menor espera no ciclo. Medir os tempos atuais e encurtar a espera preservando amarelo, travessia e segurança entre movimentos conflitantes.
- Melhorar modelo, material, lentes e leitura da luz ativa na câmera normal, de dia e à noite. Evitar brilho excessivo e detalhes caros sem ganho perceptível.
- Conferir concordância entre sinal visual e regra seguida pelos veículos.
- Conclusão: espera perceptivelmente menor, luzes legíveis e cruzamentos sem liberações conflitantes ou retenção permanente; comparar custo de renderização antes/depois.

## 6. Reposição de carros estacionados — prioridade média

- Guardar a identidade da vaga, posição, orientação e configuração original do veículo.
- Iniciar um prazo configurável quando o carro for retirado. Definir o tempo final em revisão de gameplay, sem fixar um número arbitrário como requisito.
- Após o prazo, repor somente com a vaga livre e fora da observação próxima do jogador. Adiar se houver pessoa ou veículo ocupando o espaço.
- Separar o carro levado da reposição da vaga, sem apagar um veículo em uso. Controlar identidade e ciclo de vida para evitar duplicações a cada carregamento e acúmulo ilimitado de abandonados.
- Conclusão: retirar, aguardar e retornar; conferir vaga ocupada, jogador perto, veículo levado ainda em uso, saída/retorno da região e salvar/carregar. Reposição única na posição e orientação originais, sem colisões ou desaparecimento do carro utilizado.

## 7. Retirada do aviso vermelho ao roubar veículos policiais — ajuste pontual

- Reproduzir o roubo de carro e moto da polícia e identificar exatamente o aviso vermelho relatado.
- Remover o disparo dessa mensagem nos dois fluxos. O pedido é de interface; consequências policiais existentes não devem mudar por acidente.
- Conclusão: conferir os dois roubos, ausência do aviso e funcionamento de entrada, condução e reação policial. Usar o teste existente test_police_car_alarm_theft.gd quando cobrir o fluxo alterado; ampliar para moto apenas se faltar cobertura pertinente.

## 8. Sedã M8 do Maciota: revisão completa de som e marchas — prioridade alta

- Revisar o áudio do sedã M8 do Maciota em partida, marcha lenta, aceleração leve e forte, velocidade constante, desaceleração, redução e parada.
- Melhorar a qualidade e a identidade do motor e escapamento, com transições contínuas entre faixas de giro, sem repetição evidente, cortes, estalos ou mudanças artificiais de tom.
- Sincronizar som com giro, carga do acelerador e marcha real. Nas trocas, reproduzir alívio do motor, queda coerente de giro e retomada progressiva.
- Ajustar relações, pontos de troca e intervalo entre marchas conforme o comportamento observado, para uma progressão mais espaçada e natural; evitar trocas rápidas em sequência e alternância constante entre duas marchas.
- Harmonizar resposta de aceleração, desaceleração e condução do Maciota com o som. Aplicar o cuidado solicitado tanto no passeio de missão quanto nos demais usos disponíveis do sedã M8.
- Integrar a prioridade de voz do plano 4: motor e demais sons do carro devem baixar durante a dublagem e retornar suavemente depois.
- Conclusão: avaliar por escuta e gameplay os estados acima, incluindo subida, descida, retomada e diálogo durante aceleração. Conferir coerência entre giro, marcha, movimento e áudio, sem trocas nervosas nem som encobrindo as falas. Reutilizar cobertura pertinente de test_maciota_engine.gd e test_vehicle_drivetrain.gd, ampliando somente lacunas comportamentais relevantes.

## Pontos de partida encontrados no projeto

Estes caminhos orientam a investigação; a inspeção inicial não demonstra a causa dos defeitos.

- Campanha e chegada: world/harbor/campaign/HarborArrivalMission.gd, MaciotaTourCar.gd e CobraCampaignController.gd.
- Referência Monaliza: world/harbor/monaliza/MonalizaCar.gd e MonalizaAudio.gd; transmissão: VehicleDrivetrain.gd.
- Semáforos: world/shared/roads/traffic/FixedTrafficSignal.gd e TrafficSignalModel3D.gd.
- Testes candidatos: test_harbor_campaign_flow.gd, test_maciota_interrupted_conversation.gd, test_maciota_engine.gd, test_vehicle_boarding_animation.gd, test_vehicle_boarding_sides.gd, test_monaliza_drivetrain.gd, test_monaliza_audio.gd e test_taken_vehicle_parking.gd. Ler a cobertura antes de selecionar; nomes não garantem que cubram o feedback.
- Contrato obrigatório: docs/interior-physics-and-depth.md.

## Ordem de execução e entrega

1. Registrar baseline dos congelamentos e reproduzir o bloqueio da segunda missão.
2. Corrigir o bloqueio e as causas de congelamento identificadas.
3. Polir primeira e segunda missões, incluindo prioridade das vozes, pausas e a revisão completa de som e marchas do sedã M8.
4. Ajustar semáforos, reposição dos estacionados e aviso policial; o aviso pode ser antecipado por ser independente.
5. Integrar dublagem humana quando houver gravações aprovadas.

Cada frente deve ter alteração revisável e validação proporcional segundo testes-com-criterio. Reutilizar testes existentes; criar cobertura comportamental somente para lacunas relevantes. Aprovar áudio por escuta e movimento por sequência renderizada, nunca apenas por captura parada. Relatar separadamente o que foi corrigido, medido e ficou pendente.
