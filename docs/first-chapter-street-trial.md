# Prova de rua — primeiro capítulo

A prova qualifica Dante para conversar com o motorista ligado a Vicente. É uma tomada de tempo organizada por Ferrugem, com uma volta e quatro portões, sem aposta ou pagamento de inscrição. A antiga dependência de um rival dirigindo no trânsito foi retirada: a missão mede o percurso e o tempo do jogador.

## Fluxo jogável

- Ao aceitar no quadro, a campanha prepara 21h e Ferrugem organiza a praça. Se o jogador explorar até outro horário antes da largada, a confirmação de largada volta à janela noturna.
- A organização fecha apenas a entrada de trânsito na via de acesso. Os carros existentes seguem as conexões normais do grafo até a saída oeste, mantendo corpos, colisões e identidade. O evento conserva ativos os carros do percurso e da saída mesmo com Dante na garagem, pelo contrato `simulation_keep_alive` do gerenciador de população.
- A prova só larga quando a pista estiver desocupada. A espera tem objetivo explícito, cancelamento pelo Diário sem cobrança e limite de 90 segundos de bloqueio contínuo. A saída de trânsito permanece aberta; a direção vem da pista atual, não dos metadados de spawn do carro. A parada da entrada fica 500 unidades antes da junção oeste, fora da janela de reserva do cruzamento; assim um carro aguardando a prova não pode reservar a junção e bloquear quem precisa sair.
- Dante pode usar seu carro ou outro carro disponível. Precisa parar na marca, apontando para o primeiro portão ao norte, e apertar a ação indicada. Um veículo quebrado, em movimento ou desalinhado recebe instrução específica antes de iniciar o cronômetro.
- Depois de fechar o briefing, a contagem mostra 3, 2, 1, JÁ. Mover o carro mais de 18 unidades durante a contagem queima a largada. A volta deve cruzar norte, leste, sul e chegada, nesta ordem, em 100 segundos.
- A rota e as setas usam a faixa externa do circuito no sentido horário, obtida da geometria real do grafo. A antiga fixture dirigia na faixa interna, na contramão; os dois sentidos não são intercambiáveis.
- Sair do asfalto abre uma janela visível de quatro segundos para voltar pelo mesmo lugar. Atalhos, saltos de posição, abandonar/trocar o carro, destruição, morte e prisão encerram a tentativa sem completar a missão.
- Vitória paga uma única recompensa de $200, avança a pista sobre Vicente e libera o trânsito. Cancelamento, falha, restauração e limpeza também removem somente as reservas e os planos temporários pertencentes ao evento.

## Validação e limites

`tests/test_cobra_race_contract.gd` cobre regras, admissão, contagem, cancelamento de preparação bloqueada, sentidos de trânsito, prazo, checkpoints e recompensa. `tests/test_cobra_race_player_car.gd` usa o PlayerCar real e ações do GameInput; após a montagem inicial, não altera posição, velocidade nem colisões. O teste acompanha a saída física dos carros, preservação da frota e toda a volta. `tests/test_cobra_campaign_runtime.gd` mantém os contratos dos encontros e do retry, com o fluxo completo do guincho validado em `tests/test_first_favors.gd`.

Durante a investigação foram identificadas fixtures antigas com ações `ui_*` em vez de `move_*`, condução na contramão e retorno prematuro à faixa após ultrapassagem. A validação final deve usar as fixtures atualizadas. Passagens parciais e falhas do piloto automatizado não certificam a vitória jogável. Resultados finais e medições renderizadas da entrega são registrados no relatório principal do capítulo; testes headless não certificam FPS nem acabamento visual.

Validação final: contrato da corrida aprovado em 57 verificações; integração de campanha (`test_cobra_campaign_runtime.gd`) terminou com zero falhas, incluindo morte e substituição do contato, recompensa e encontros finitos. Foi corrigida a restauração indevida do registro médico do contato na nova tentativa e a leitura tipada prematura de uma referência médica já removida.

A prova completa com o PlayerCar real passou: o tráfego liberou a praça em 38,13 segundos, preservando os oito carros inicialmente no circuito e a frota de 59 carros; o maior deslocamento físico de evacuação foi 12,39 unidades por quadro. Depois da montagem inicial, somente ações de entrada moveram o carro por 2.032,4 unidades até a vitória, com maior passo de 1,90, saúde do carro e do jogador em 100 e nenhuma recuperação em ré. Evidências: `tmp/pdfs/race-player-gate6900.log` e `tmp/pdfs/race-contract-final.log`, relativos à raiz do repositório. Não foi necessário alterar o controlador físico, retirar colisões ou eliminar tráfego.

O último contrato e a prova física encerraram sem erros ou avisos de recursos, além do aviso conhecido da câmera sobre interpolação física. Execuções anteriores de integração/headless apresentaram avisos de recursos de áudio no encerramento; a validação funcional não é uma certificação global de ausência de vazamentos no motor. As medições renderizadas de produção são registradas no relatório principal do capítulo.
