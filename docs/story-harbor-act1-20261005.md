# História de Harbor e implementação do ato 1

O roteiro atual começa com a ligação em casa e a chegada de barco. Maciota reconhece Dante pela fotografia do histórico policial e o leva na M8 preta à oficina industrial. Os favores, o serviço com Jessica e a corrida de Takeshi conduzem à lista que identifica Vicente como responsável pelas corridas do deserto.

O passado reservado ao ato 2 é a operação em outra cidade, Dante prendendo o próprio irmão, oito anos de prisão e as tentativas de reabrir o caso. Dante encontrou indícios de armação e deixou a corporação; Vicente interpreta o período como abandono. A origem da dívida de Maciota é o veículo de cliente que Dante recuperou, demonstrando que Maciota havia sido enganado.

## Campanha atual

| Ordem | Missão | Execução e consequência |
|---|---|---|
| M00 | Chegada | Casa, barco, Maciota na rua, passeio e oficina |
| M01 | Primeiro Giro | Helena, comprovante e peça no porto; Monaliza concedida depois |
| M02 | Dentro do território | Ferrugem, guincho, cliente e ordem de serviço |
| M03 | Prova de rua | Corrida até as docas e aproximação dos contatos |
| M04 | A conta chega | Proteção da moradora e indicação dos registros |
| M05 | Serviço com Jessica | Saque real no banco, embarque de passageiro, fuga física e conversa; recibo bancário separado dos R$ 500 da missão |
| M06 | Cortar o abastecimento | Recuperação dos papéis dos Cobras |
| M07 | A última volta | Corrida de Takeshi, entrada na casa e lista de responsáveis; R$ 600 e Ironback |

Os IDs anteriores permanecem. `cobra_finale` agora contém corrida e casa, mantendo o recibo de recompensa. Saves do formato anterior conservam missões, inventário, dinheiro e recibos; uma tentativa antiga do confronto final retorna à nova largada, enquanto a missão de Jessica é registrada como exceção de migração quando o save já havia avançado além dela. Nenhum saque antigo deve concluir o trabalho novo.

## Jessica

Jessica usa o rig articulado do jogo, identidade feminina loira, corpo mais magro e altura medida em relação a Dante. Seu Jetta GLI é branco, turbo e tem neon vermelho de alcance curto, sem sombras, apagado durante o dia. Encontro, aceite do trabalho, retorno e reencontro ficam registrados individualmente, sem medidor de afeto.

O trabalho depende do saque e recibo reais de `Robberies`, saída viva do banco, passageiro no veículo correto, trajeto concluído, desembarque livre e fim natural da perseguição. Não há pagamento fabricado por abrir um diálogo. Morte, prisão, cancelamento e viagem precisam devolver controle e preservar o que já pertence à carteira.

## Oficina e casa

A oficina passou para `(168.5, 0, 101.5)`, com acesso em `(166, 0, 109.8)`, pátio em L entre os galpões de frete e fachada de galpão. O lote preserva o ponto de quatro táxis e a área de drift anteriores. A decoração procedural deve respeitar a entrada dos veículos. Maciota e o mecânico continuam sem rotinas de dano; armas permanecem proibidas na garagem. Planta e baia aprovadas são preservadas com acabamento revisto.

A casa de Takeshi usa a fachada CourtyardHouse existente, com sala e escritório novos, mesa, lista, móveis sólidos e recompensa de R$ 1.200 registrada no contrato de save. A entrada depende da vitória e a lista não paga a missão duas vezes.

## Abertura e áudio

`HomeCall` usa as imagens de casa existentes, telefone, saída com mochila e desembarque jogável. PT e EN têm textos autorados; a duração se amplia conforme a tomada exata, sem acelerar fala. A confirmação de pulo pausa imagem e áudio; conclusão e pulo preservam o checkpoint.

As falas PT são produzidas localmente por Qwen3-TTS VoiceDesign e associadas por hash de persona e texto. O manifesto fica em `audio/mission_voices/harbor_story/production.json`. Ausência de tomada resulta em legenda e silêncio, sem tratar som não verbal como dublagem. Tomadas EN ainda não foram produzidas. Produção interrompida pode ser retomada sem apagar os arquivos concluídos; não executar o gerador pesado junto de benchmarks ou enquanto comprometer o uso do PC.

Das 89 falas únicas do roteiro novo, 70 WAVs foram produzidos. A transcrição offline de uma thread verificou os 70; duas perguntas curtas de Dante permaneceram ambíguas após revisão sem VAD, por isso seus arquivos foram preservados e retirados da reprodução automática. São 68 tomadas ativas, 19 ausentes e 2 aguardando revisão de pronúncia. O carregamento gradual protegeu a memória residente, mas a geração dentro do orçamento de GPU/alocações falhou; não foi retomada em modo pesado. ASR não certifica interpretação ou continuidade de timbre. A abertura completa com WAVs importados passou em 44,4 s.

A conferência final sem modelos comparou o roteiro atual, o hash de texto/personagem, o manifesto de reprodução e a duração dos WAVs. Os 68 vínculos ativos estão consistentes, sem mudança de texto, personagem ou duração; as 19 falas ausentes e as duas em revisão permanecem identificadas em `evidence/harbor-story-voice-bindings.json`. As legendas continuam disponíveis nas falas sem tomada. Essa verificação de arquivos não substitui revisão artística da dublagem.

## Outros conteúdos encontrados no código

Esta leitura distingue adaptadores conectados, arquivos históricos e código novo preparado por outro chat. A coluna de conexão não equivale a uma nova certificação de gameplay.

| Conteúdo | Fonte atual | Conexão/estado |
|---|---|---|
| Volta do Porto e Circuito Foundry | `activities/ActivityDefinitions.gd`, `Activities.gd`, `Motorsport.gd` | 2 corridas opcionais de Harbor conectadas à sessão; o catálogo histórico de 5 corridas é da CityDemo |
| Pátio Westgate e Pátio dos Armazéns | Mesmos adaptadores | 2 zonas de drift de Harbor; o catálogo histórico de 3 não é a lista do mapa atual |
| Cinco serviços de guincho | `data/catalogs/TowJobs.gd`, `activities/Activities.gd` | Sequência de contratos repetível, separada do guincho narrativo dos Cobras |
| Primeira descida, Slalom do Pinhal, Pista da Sombra | `activities/MountainProgression.gd` | Esqui e pistas de expedição conectados à sessão |
| Motocross e skate | `activities/motocross/`, `activities/skate/` | Atividades com estados próprios instaladas por FullSession |
| Serviço de Tonico | `gameplay/urban_v1/TruckersVillageQuest.gd` | Correia e manivela para a bomba, R$ 450, recibo e escolhas de comércio |
| Frete e logística portuária | `PortFreightDelivery.gd`, `PortLogistics.gd` | Adaptadores de entrega física e pagamentos, separados da campanha |
| Pasta de Vicente e rede subterrânea | `SecretNetworkProgression.gd`, `TruckersVillageSecretPassage.gd`, `SecretFileRuntime.gd` | Dossiê, fragmentos, keypad, energia e rotas opcionais; quatro gravações da pasta ainda não possuem streams e o runtime informa gravação danificada |
| Banco, saque de casas/contêineres, colecionáveis e conquistas | `Robberies.gd`, `TruckersVillageHouseLoot.gd`, `PortContainerLoot.gd`, `Activities.gd` | Sistemas de mundo com seus próprios recibos; não são missões obrigatórias novas |
| Nove beats e quatro contratos da campanha anterior | `data/campaign/campaign_v1.json`, `CanonicalCampaign.gd` | Arquivo/compatibilidade; não disparar a antiga notícia de assassinato na abertura nova |
| Carga dos Cobras no avião e rastro de Vicente na caverna | `activities/mountain_story/`, `MountainStoryProgress.gd` | 2 side quests preparadas por outro chat; agregador ainda não instalado em FullSession nesta leitura |
| Descida noturna contra seis NPCs e trilha de jipe | `activities/mountain_downhill/`, `activities/mountain_jeep/`, `MountainActivities.gd` | Código e patch preparados, sem integração/validação assumida por este lote; ver `docs/integracao-montanha-20261005.md` |

Ideias futuras registradas: encontro com Vicente e revelação da armação no deserto; reencontro e vitória de Jessica; contatos/moradia providenciados por Maciota; novas etapas da rede secreta; cidade 4 como última cidade, escura, cinza e com neblina. Nenhuma dessas descrições representa uma cidade pronta. A nova ponte norte está em integração por outro chat e consulta a conclusão real da última missão; o acesso lateral à montanha deve continuar independente.

## Cobertura e pendências

Já houve compilação C# e testes aprovados de estado da campanha/economia, Jessica, carro, save, banco, recompensa e transferência de garagem, abertura natural/pulo, chegada e trajeto pedestre. A casa passou pelos testes de jogador/NPC contra móveis e paredes, lista, recibo exato, restauração e regras de armas.

O passeio completo da M8 passou em 66,2 s após corrigir sólidos no acesso, reservar a circulação da decoração procedural e estacionar o cupê inicial fora da passagem. O teste de recuperação passou em 20,5 s e o percurso físico da rota direta passou em 25,5 s, com 78 verificações. A rota conserva os sinais, colisões e os quatro táxis existentes. A casa passou em 68/68 verificações; capturas com controles positivos comprovaram a oclusão de jogador e NPC na mesa e no sofá, separadamente da colisão.

O teste de Jessica já comprovou banco, saque, recibo, embarque e a pose real de Dante sentado. O desvio físico de um pedestre passou em 13,6 s na regressão final; a manobra entre um carro dianteiro e outro traseiro passou em 17,7 s. A rota padrão usa Foundry/Quay em três trechos C# contínuos, com verificação das duas emendas, altura e suporte de todo o casco. O ajuste do piso do túnel agora só se aplica a caminhos que realmente incluem o túnel; antes ele rebaixava erroneamente Quay nas mesmas coordenadas X/Z. O trajeto real do canal passou em 61,1 s e a verificação da rota Foundry em 18,9 s após essa correção.

A espera mantém sua idade através das mudanças do sinal e cancela após um ciclo sem avanço. Um par recíproco de carros é tratado com ré local do Jetta para ceder espaço a quem já ocupa o miolo; os cenários com e sem espaço traseiro passaram em 24,9 s e 15,2 s, preservando colisões e semáforos. As curvas de entrada e o estacionamento, com galpão, cerca e M8 presentes, passaram em 33 s. O desembarque agora posiciona e sincroniza os atores fora do casco antes de reativar sua colisão e zera a velocidade residual do carro. O caso curto ampliado passou em 38,2 s, incluindo 60 frames de estabilidade e caminhada física pelo corredor sul até Jessica.

A primeira execução com imagem encontrou um policial diante do Jetta e o cupê atrás: a ré fixa de 4,5 m não cabia. O desvio admite alternativas curtas para pedestres e deslocamento lateral de 1,4 m ou 1,8 m, sempre com suporte, casco completo, trajetória varrida e raio compatível com o volante real. A geometria reproduzida com policial, cupê e parede passou em 11,8 s; o caso anterior de pedestre passou em 14,6 s. A primeira tentativa desse caso curto foi preservada: o deslocamento lateral maior interrompia a previsão da curva junto da parede. A preferência pelo menor desvio livre resolveu essa falha, sem remover corpos ou colisões.

O fluxo Main renderizado final passou em **65/65 verificações, em 157,5 s**: saque real de R$ 15.000, três trechos C#, cerca de 254 m percorridos, perda natural da perseguição, saúde de Dante em 82 e do carro em 260, desembarque, conversa, recibo próprio de R$ 500, proprietário único do Jetta e save/load isolado com validação real de GameState. Evidência em [integration.json](../evidence/jessica-integration-7877765/integration.json), com fotos na mesma pasta. O combate é controlado depois do primeiro tiro real e os pinos do cofre são resolvidos pelo teste; essa execução não certifica balanceamento do assalto nem todas as configurações possíveis de trânsito/polícia. A população solicitada para a execução renderizada foi 24.

A regressão da garagem identificou que o retorno veicular ainda usava o ponto pedestre antigo. O retorno agora é separado, em `(166, 0, 110.8)`, orientado para oeste e admitido pelo casco completo; entrada e saída da Ironback, inclusive na garagem do chefe, passaram em 19,3 s. Save completo, campanha/economia, restauração de condutor, estado de Jessica e carro passaram no lote proporcional. Um lote registrou mudança exclusiva no fixture de benchmark; os scripts funcionais selecionados mantiveram seus hashes, e essa limitação foi preservada nos metadados.

Medições renderizadas de 30 segundos foram concluídas no Mobile/Vulkan, 1920×1080, RTX 4060 Laptop GPU, MSAA 2×, escala 100%, VSync desligado e FPS sem limite. O alvo provisório é 60 FPS / 16,67 ms. As fotos reais de interiores e do novo exterior foram concluídas.

| Cenário | FPS médio | p95 / p99 (ms) | Maior quadro (ms) | Quadros >33,3 / >66,7 ms | NPCs / veículos |
|---|---:|---|---:|---|---|
| Garagem — base | 317,1 | 5,617 / 6,296 | 17,851 | 0 / 0 | 24 / 30 |
| Garagem — atual | 242,4 | 7,251 / 8,767 | 104,195 | 1 / 1 | 24 / 43 |
| Entorno de Jessica — base | 171,5 | 9,835 / 10,988 | 21,808 | 0 / 0 | 23 / 34 |
| Jessica/Jetta — antes do brilho adicional no piso | 152,6 | 10,737 / 11,698 | 34,263 | 1 / 0 | 24 / 39 |
| Jessica/Jetta — brilho final no piso | 181,8 | 9,412 / 10,239 | 15,477 | 0 / 0 | 21 / 39 |
| Nova oficina — orçamento atual | 125,2 | 11,737 / 12,850 | 16,687 | 0 / 0 | 23 / 46 |
| Sala de Takeshi — orçamento atual | 1.217,8 | 1,245 / 1,481 | 3,491 | 0 / 0 | 0 / 1 |
| Fuga de Jessica — trajeto renderizado atual | 130,3 | 14,105 / 17,731 | 94,667 | 34 / 7 | 15–24 / 33–43 |

O lote novo não possui baseline no mesmo local; a sala nova de Takeshi foi medida como orçamento atual, sem comparação causal anterior. Na região de acesso da casa, 48 segmentos curvos medem 2,453 m, abaixo do mínimo de 4 m que o spawner aceita. A população efetiva de zero no interior é o resultado natural do cenário, mantendo o alvo solicitado de 24; nenhum personagem ou carro foi removido para o benchmark. Essa medição inclui caminhada de mais de 10 m, leitura real da lista e save/load isolado, e não representa desempenho de uma rua populosa.

As bases tiveram o editor aberto, enquanto as medições atuais tinham apenas o gerenciador de projetos, além do jogo. As quantidades de carros diferem, e a base de Jessica tinha um NPC a menos. Os tempos maiores da garagem e de Jessica não são aprovação de regressão nem podem ser atribuídos somente ao conteúdo novo. A comparação controlada permanece inconclusiva. As medições estacionárias atuais tiveram p95/p99 abaixo de 16,67 ms; o pico de 104 ms da garagem permanece registrado.

A fuga foi medida durante 80,47 s depois de 5 s de aquecimento, com 10.482 frames reais, em cena integrada, câmera jogável e população/tráfego naturais. O p99 de 17,731 ms ultrapassa a meta provisória de 16,67 ms, com sete frames acima de 66,7 ms; **performance da fuga permanece pendente**, embora o fluxo funcional tenha passado. Não há baseline equivalente desse trajeto para atribuir os picos ao código novo. O aquecimento inclui a captura inicial do passageiro e não comprova tempo de primeira visita sem custo de captura. A execução renderizada anterior falhou antes de sair do banco e gerou somente 21,46 s de amostragem: é diagnóstico preservado, não um benchmark aprovado.

A revisão final do neon registrou o piso do lado voltado à câmera em 954 frames durante 30,25 s: fonte apagada durante o dia, intensidade noturna constante em 0,997 e componente vermelha positiva em todos os registros. A variação de cor foi inspecionada nos extremos e acompanha a iluminação externa sobre o piso; o brilho vermelho permanece visível. A mancha suave usa o mesmo padrão dos faróis, com uma textura compartilhada de 64×64, um mesh sem colisão/sombra e teste de profundidade ativo. A medição final do brilho teve três NPCs a menos que a base imediatamente anterior; não prova isoladamente que o efeito melhorou FPS. O limite de oito OmniLights por mesh do Mobile consta na [documentação do Godot 4.7](https://docs.godotengine.org/en/4.7/engine_details/architecture/internal_rendering_architecture.html); isso não comprova, por si só, a causa do brilho fraco observado. A revisão cobre a vista estacionária do banco, com capturas maiores que 250 ms durante gravação de PNGs completos. Não certifica estabilidade em câmera móvel, distância, perseguição ou toda a iluminação do jogo.

O ato 2 está registrado em `data/campaign/harbor-story.json`; a cidade do deserto, Vicente e a corrida em que Jessica vence Dante ainda não são conteúdo jogável desta implementação de Harbor.
