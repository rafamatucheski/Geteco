# Guincho e serviços do Neco

O Towmaster amarelo fica junto à estrada de acesso do ferro-velho. Fale com Neco e escolha **Aceitar serviço de guincho**. As encomendas antigas continuam disponíveis; os dois tipos compartilham uma encomenda ativa, três serviços aceitos e seis entregas por dia.

Ao volante, pare com a traseira próxima de um carro vazio. Use a interação configurada (E por padrão; A no controle) para carregá-lo na plataforma. O modelo do carro aparece sobre o caminhão, acompanhado de animação e som hidráulico. A mesma ação descarrega: alinhe a traseira com a baia do Neco, saia do caminhão e entregue o carro à prensa. O pagamento ocorre após esmagar.

| Etapa | Serviço | Pagamento | Prazo |
| --- | --- | --- | --- |
| 1 | Primeiro reboque, próximo do pátio | $1800 | 6 min |
| 2 | Esportivo do outro lado | $3200 | 9 min |
| 3 | Viatura fora de serviço | $4200 | 10 min |
| 4 | Colecionador sem sorte | $4800 | 9 min |
| 5 | Encomenda da madrugada | $6000 | 10 min |

A série volta ao primeiro serviço depois da quinta entrega. A etapa avança somente com pagamento da encomenda. Esportivos e carros especiais usam as vagas mais distantes disponíveis. As viaturas do estacionamento policial são priorizadas; se acabarem, uma vaga distante recebe a próxima viatura encomendada. Buscar uma viatura entre **20h e 6h** gera no mínimo uma estrela; de dia, três. A verificação usa a hora da coleta. É preciso despistar a polícia antes de entregar.

O caminhão também pode transportar carros vazios fora dos serviços. Não carrega motos, caminhões grandes, veículos ocupados, veículos de missão/emergência em serviço nem a Monaliza. Consultas físicas impedem carregar através de obstáculos e descarregar sobre sólidos. Neco permite recuperar no acesso um guincho vazio abandonado ou destruído.

`CampaignState.salvage_state` guarda a etapa, o guincho e a carga. `SaveManager` pede um snapshot antes de serializar. O carregamento reaproveita o guincho restaurado pelo sistema de viagem quando o jogador salvou ao volante. A prensa mantém o bloqueio de gravação durante sua operação. Perda do alvo, prazo vencido, morte ou prisão encerram a encomenda, como nas entregas anteriores.

Foi necessário fixar a orientação local da câmera 3D do pátio antes de adicioná-la à árvore: durante a criação progressiva do Harbor, a projeção estava colocando a baia em Y=645; com a pose correta, Y≈102. As colisões e a marca de entrega voltam a usar a mesma projeção.

## Verificação

- `tests/test_salvage_towing.gd`: **67 checks aprovados**, em Vulkan / Forward+. Exercita a série e repetição, alvos reais, proteção do guincho, obstáculo na coleta, modelo carregado, GPS, duas restaurações reais de save (a pé e ao volante), condução com carga, descarga, pagamento após a prensa e diferença entre dia e noite.
- `tests/test_salvage_geometry.gd -- --harbor`: **68 checks aprovados**, sem renderização. Inclui os testes anteriores de entrega, limites diários e geometria do pátio.
- `tools/check_references.py`: nenhuma referência quebrada nova.
- Capturas em `docs/measurements/towing-0910/01_jobs.png` e `02_loaded.png`; logs finais em `render.log` e `geometry.log`. As execuções usam APPDATA separado. Persistem avisos de câmera/interpolação e instâncias retidas ao encerrar; os logs finais não apresentam erro de script.

Os testes incluem um trecho de condução, mas não uma viagem manual completa por cada rota nem uma medição de desempenho.

## Integração com trabalho paralelo

A base do ferro-velho já estava modificada e seus scripts ainda estavam fora do Git quando este trabalho começou. `docs/measurements/towing-0910/integration.patch` registra somente os acréscimos desta tarefa nos quatro arquivos compartilhados, já aplicados na cópia de trabalho. Os novos scripts e testes podem ser versionados separadamente sem incluir a implementação anterior do pátio no commit desta tarefa. O patch depende dessa base do Neco e não deve ser reaplicado sobre a cópia atual.
