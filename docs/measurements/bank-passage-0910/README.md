# Banco: passagem pela porta e interior — 10/09/2026

A gravação mostrava um fade ao se aproximar, sem entrada, e um salão achatado com personagens fora de proporção.

## Correção

- A cortina agora responde ao início de uma transição, não à abertura visual da porta. Aproximar e passar de lado não escurecem a tela. Também funciona quando a porta já está aberta.
- O vão da fachada tem colisão recortada. Cruzar a soleira andando entra; cruzar a faixa SAÍDA retorna à calçada. Reversões rápidas aguardam o cooldown, e recuar cancela uma passagem pendente.
- A câmera 3D do cenário em cache e as câmeras dos NPCs não interpolam a partir da origem. A imagem é atualizada na entrada. NPCs usam projeção paralela com o mesmo ângulo do salão e contato dos pés calibrado.
- O salão tem passadeira, identificação dos caixas, caixas eletrônicos, floreiras e indicação de saída, com colisões correspondentes aos novos móveis. O enquadramento e a instrução de saída foram ajustados.

## Verificação

`tests/test_bank_walkthrough.gd` passou com Vulkan: aproximação, espera, passagem lateral, cinco entradas/saídas pelo movimento real do Player (incluindo reversões imediatas), circulação no salão, alinhamento visual do piso, restauração de câmera e escala, e interação explícita no posto. Não chama o teleporte do gerenciador para entrar no banco.

`tests/test_bank_heist_flow.gd` também passou: combate, cartão, cofre bloqueado/desbloqueado, coleta sem duplicação, cerco com três viaturas, saída, retorno ao cofre e caixa do posto. O verificador de referências registrou zero quebras novas.

Os logs resumidos em `validation.txt` preservam as verificações e diagnósticos distintos. Estas execuções também registraram erros externos ao banco em `HarborLivingQuarter.gd` (inicialização de vizinhos/fontes de áudio), ações de InputMap no carregamento de configurações e recursos remanescentes no encerramento. Portanto, aprovação dos cenários do banco não significa carregamento do jogo inteiro sem erros. Durante a verificação foram necessárias duas anotações de tipo booleano em `VehicleRadioReceiver.gd`, um arquivo novo de outra sessão; o restante dessa implementação não integra o commit do banco.

Não houve avaliação de dificuldade de combate nem medição de desempenho.

## Capturas

- `01_aproximacao.png`: porta aberta sem cortina e sem transferência.
- `02_salao.png`: entrada por caminhada e interior corrigido.
- `03_retorno.png`: retorno físico à calçada.
- `03_cofre.png`, `04_coleta.png`: fechadura e dinheiro na suíte de assalto.
