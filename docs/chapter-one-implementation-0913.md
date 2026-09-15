# Primeiras missões do Geteco — 13/09/2026

Esta entrega implementa o início do capítulo: chegada, Primeiro giro, recuperação para Ferrugem e Prova de rua. A investigação de Vicente passa por atividades do próprio jogo. Esqui e a compra narrativa de armas continuam como propostas para missões posteriores; não fazem parte desta implementação.

## Sequência jogável

| Missão | Ação do jogador | Motivo na história | Horário |
| --- | --- | --- | --- |
| Atrás do irmão | Delegacia, chamada, encontro com Maciota no Neco, passeio como passageiro e chegada à garagem | Dante começa a procurar Vicente e ganha seu primeiro contato na cidade | Fluxo de chegada existente |
| Primeiro giro | Conversar com Helena no banco, retirar uma peça no porto e devolvê-la a Maciota | O comprovante e as transferências ligam Vicente aos serviços da oficina | Encontro às 10h |
| Dentro do território | Conversar com Ferrugem, pegar o guincho do Neco, carregar o carro da cliente, descarregar na baia e confirmar com Neco | A ordem 017, assinada por V. Ferraz, revela a procura de motoristas para a serra | Encontro às 15h |
| Prova de rua | Preparar o carro, alinhar na largada, aguardar a liberação do circuito e completar quatro portões em ordem | Ferrugem testa se Dante pode dirigir nos serviços ligados à pista de Vicente | Encontro às 21h |

Cada etapa tem instrução de ação e destino no GPS. O banco exige presença e conversa; o guincho exige carga e descarga reais. A prova usa uma volta de até 100 segundos, contagem regressiva e o trajeto da faixa externa no chão e no minimapa. A largada usa **R**, preservando **E** para sair do veículo. O diário usa **J**.

## Horários e liberdade do jogador

`ChapterOneSchedule.gd` centraliza os encontros. Aceitar no quadro avança o relógio real para o próximo horário apropriado, com transição visual. Uma janela de duas horas aceita chegadas próximas ao horário marcado. O relógio sempre avança; uma aceitação repetida não salta outro dia. A chegada tardia à largada permite aguardar novamente a noite.

Não é possível usar o salto de horário para escapar de perseguição, combate ou outro serviço ativo. Tempo de campanha e recuperação médica recebem o mesmo avanço. O relógio normal continua a partir daí, e o horário persiste no save. Descanso continua opcional, na garagem e fora de missão.

O jogador pode explorar entre etapas, voltar ao contato e sair do veículo. O objetivo acompanha a situação: quem abandona o guincho carregado recebe o destino do próprio caminhão. Conversar, consultar o diário e usar interfaces interrompem os controles de maneira consistente; fechar o painel restaura o estado anterior.

O banco oferece uma visita pacífica com arma guardada. Se uma ação anterior deixou o estabelecimento interditado ou Helena indisponível, a missão orienta uma segunda via por telefone na fachada, depois de despistar a polícia. A missão não apaga as consequências de um assalto.

A prova organiza o escoamento do trânsito pela malha viária existente antes de iniciar a contagem. Durante o evento, novas entradas são retidas. O jogador pode cancelar pelo diário, inclusive ao volante, e aceitar novamente sem cobrança. Sair da pista por muito tempo, abandonar/trocar/destruir o carro, morrer, ser preso ou exceder o limite gera uma falha explícita com possibilidade de nova tentativa.

## Continuidade e recompensas

Primeiro giro usa flags para comprovante e peça, preservando saves antigos já em andamento no percurso original. A recuperação usa o `TowService` existente, inclusive persistência da carga. Recarregar uma partida interrompida permite nova aceitação e reutilização do mesmo carro restaurado. As recompensas ficam registradas antes do pagamento, impedindo recebimento repetido.

O carro da cliente não pode ser vendido à prensa. Serviços laterais e cargas existentes não são apagados para iniciar a recuperação. Maciota e seu mecânico continuam invulneráveis; a garagem continua sem armas.

Depois do recebimento, Neco explica que a cliente buscará o carro. O serviço mantém a retirada pendente mesmo após concluir a missão: o veículo só é retirado quando está parado, vazio, sem embarque ou carga, fora da câmera e longe de Dante e do pátio. Isso libera a baia para a próxima encomenda sem desaparecer diante do jogador nem conceder pagamento adicional.

## Banco: física e profundidade

Os bloqueios agora são derivados das malhas visíveis por `BankInteriorGeometry` e `InteriorSolidProjection`: paredes, balcões completos, bancos de espera, caixas eletrônicos, vasos, pilares e porta do cofre. Piso, tapetes, partes suspensas e itens coletáveis têm classificação própria.

Jogador, guardas e funcionários usam seus rigs originais no mesmo viewport da sala, por `InteriorActorPresentation`. Isso permite oclusão real por móveis e paredes e suspende seus viewports individuais. A saída restaura a apresentação externa. A porta física do cofre acompanha sua abertura; os disparos dos guardas usam a projeção da sala.

## Validação registrada

| Caso | Evidência |
| --- | --- |
| Chegada e passeio | `test_story_arrival_v2.gd`: PASS, incluindo rota física, passageiro, cancelamento, checkpoints e porta da garagem |
| Banco → porto → Maciota; recuperação com guincho | `test_first_favors.gd`: 54 verificações headless e 57 renderizadas, zero falhas |
| Transporte existente | `test_salvage_towing.gd`: 68 verificações, zero falhas |
| Retirada da cliente e reutilização da baia | `test_story_customer_pickup.gd`: 19 verificações, zero falhas; preserva carro próximo, visível, ocupado, em embarque ou carregado, mantém a retirada após concluir a missão e permite guinchar/descarregar outra encomenda na mesma baia |
| Garagem e personagens protegidos | `test_garage_weapon_restrictions.gd`: zero falhas |
| Interface da campanha | `test_cobra_campaign_gameplay.gd`: zero falhas |
| Horários, GPS e cancelamento | `test_chapter_one_schedule.gd`: 31 verificações renderizadas, zero falhas; inclui porta real da garagem, iluminação noturna externa, impedimento por perseguição, R ao volante, pausa/cancelamento sem cobrança e relógio no save |
| Regras da prova | `test_cobra_race_contract.gd`: 57 verificações, zero falhas |
| Prova com carro real | `test_cobra_race_player_car.gd`: volta completa com controles reais, 2032,4 unidades percorridas, maior passo de 1,90; carro e jogador com 100 HP ao final, sem manobras de recuperação |
| Escoamento do circuito | Oito carros saíram fisicamente em 38,13 s, com maior passo de 12,39; frota de 59 carros preservada |
| Campanha e encontros existentes | `test_cobra_campaign_runtime.gd`: zero falhas, incluindo retry de contato e limpeza dos encontros |
| Colisão e profundidade do banco | `test_bank_interior_depth.gd`: 911 verificações renderizadas, zero falhas; varreduras com jogador e NPC, controle positivo de oclusão, saída caminhando, reentrada e recuperação de posição inválida |
| Oclusão nos móveis reais | `capture_bank_furniture_depth.gd`: dez capturas inspecionadas de jogador/Helena frente, atrás e ao lado do balcão, atrás da divisória e diante do cofre; todas as posições fisicamente livres |
| Assalto ao banco e caixa do posto | `test_bank_heist_flow.gd`: zero falhas; advertência, combate, cofre, coleta, cerco, fuga e pagamento único |
| Recursos | `python tools/check_references.py`: nenhuma referência quebrada |

Os testes integrados posicionam atores entre alguns destinos para testar estados e interações. Isso não equivale a uma certificação de todas as viagens urbanas, combinações de tráfego ou configurações de hardware. As verificações visuais e os testes headless não substituem medição de FPS.

## Medição renderizada

Amostras de 30 segundos em HarborGame, Vulkan Mobile, NVIDIA RTX 4060 Laptop GPU, limite de 60 FPS e VSync desligado. Cidade e banco foram medidos em 1280×720; a prova ativa, em 3440×1440. Os dois agentes interromperam suas execuções para as medições finais; o editor que já estava aberto permaneceu aberto.

| Cenário | FPS médio | p95 do quadro | p99 do quadro |
| --- | ---: | ---: | ---: |
| Cidade à noite, antes | 59,95 | 18,783 ms | 20,143 ms |
| Mesma posição e câmera, depois | 59,94 | 18,568 ms | 20,115 ms |
| Banco ocupado, depois | 59,96 | 17,993 ms | 18,615 ms |
| Prova ativa, motorista parado na pista | 59,95 | 19,134 ms | 21,249 ms |

O comparativo da cidade não mostrou regressão de p95/p99. A amostra do banco teve um quadro acima de 33,3 ms e nenhum acima de 66,7 ms. O arquivo `before-bank.json` é **inválido como baseline**: seu log registra erros de compilação de uma dependência que estava sendo editada. Portanto, a medição final do banco comprova o desempenho observado, mas não permite afirmar seu delta antes/depois. A câmera urbana medida fica em `(3150, 590)` e não cobre o circuito de Ashbend. A amostra da prova cobre o evento ativo, seus marcadores, a contagem e o escoamento já concluído; o motorista ficou parado durante a medição. A volta dirigindo foi validada funcionalmente em outro teste, sem usar seus tempos como benchmark.

Detalhes: [Primeiro giro, guincho e persistência](chapter-one-first-favors-0913.md) e [Prova de rua](first-chapter-street-trial.md). Capturas e medições desta tarefa ficam em `D:/geteco/artifacts/chapter-one-0913/`.
