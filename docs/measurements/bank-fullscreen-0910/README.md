# Banco: câmera de gameplay e atendentes

- Removida a instrução permanente de saída. Alertas do assalto ficam no HUD e desaparecem ao sair do banco.
- O enquadramento agora preenche o viewport e acompanha o personagem dentro dos limites da arquitetura. A sala deixa de aparecer inteira como um quadro cercado de preto. A restauração do interior recupera esse enquadramento; sair devolve a câmera da rua.
- Helena e Marcos substituem os dois atendentes iguais: proporções adultas, cabelo e roupa próprios, ombros e braços articulados. Um recorte na altura do tampo encobre o corpo mantendo as mãos sobre a mesa. O modelo continua inteiro quando deixa o balcão ou cai.

## Verificação

`test_bank_fullscreen.gd` verifica movimento da câmera, cenário nos quatro cantos, personagem no quadro, ausência do texto normal, advertência dentro do HUD, identidades, recorte do balcão, recuperação do enquadramento e saída. Exercita 16:9, 4:3 e ultrawide com o viewport lógico expandido **apenas no teste**; a configuração global de letterbox do jogo não foi alterada.

`test_bank_walkthrough.gd` verifica cinco entradas/saídas por caminhada, incluindo reversões imediatas. `test_bank_fullscreen_heist.gd` executa a suíte do assalto e grava capturas nesta pasta, preservando as anteriores. `test_dynamic_camera_finite.gd` confere os estados numéricos da câmera externa; esse teste lógico usa headless, os testes visuais e do banco usam Vulkan.

Resultados e diagnósticos distintos estão em `validation.txt`. As execuções ainda registram erros de ações InputMap durante a importação das configurações e avisos de recursos no encerramento; aprovação dos casos do banco não significa ausência de erros globais no projeto. Não houve medição de desempenho.

As capturas `01_entrada_fullscreen.png` e `02_atendimento_fullscreen.png` mostram o gameplay real. `03_formato_*` demonstra outros formatos; `04_atendente_corpo_inteiro.png` registra o modelo fora do balcão. `heist_*` registra o fluxo de assalto.
