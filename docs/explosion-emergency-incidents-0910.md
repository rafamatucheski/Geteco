# Explosões e ocorrências de emergência

O chamado de bombeiros começa quando a vida do carro chega a zero e inicia a combustão; a detonação vem 3,2 s depois se não houver extinção. Carros de tráfego a mais de 550 unidades do jogador continuam sem chamar atendimento por acidentes de fundo.

Agora uma ocorrência reúne até três carros a até 550 unidades do primeiro. O mesmo caminhão visita os alvos restantes depois que sua equipe embarca. A frota continua limitada a dois caminhões de atendimento no mundo; os três caminhões dirigíveis do quartel são independentes. Chamados sem veículo ou com saída bloqueada ficam em fila e são tentados a cada segundo. Não existe mais criação ilimitada de veículos na ausência do pool. A fila tem limite de 24 ocorrências.

A explosão veicular tem um cálculo comum para carros do jogador, tráfego e emergência: raio de 230 unidades, dano e impulso decrescentes com distância, paredes bloqueando a onda, veículos vizinhos recebendo dano e podendo iniciar combustão. O empurrão usa colisão física, sem reutilizar o atropelamento fatal. A saída de um carro que detona usa a liberação imediata do ocupante, cancelando animações de embarque pendentes.

Mortes de NPCs até 110 unidades geram quatro partes, com cores de roupa/pele, impulso, giro, queda, colisão e atrito. O corpo intacto fica oculto. Cada vítima é um único alvo do IML; os dois agentes reservam partes distintas, caminham até elas e as recolhem em sacos. Vítimas próximas compartilham um rabecão (até oito alvos), sem despacho por parte. Limites: 16 conjuntos/64 partes simultâneas; restos sem atendimento expiram em 150 s. O jogador mantém seu fluxo de morte/renascimento.

Visual: clarão curto com iluminação local, ignições escalonadas, fumaça mais longa, peças de lataria girando e marca no asfalto. Todos os veículos usam o mesmo efeito limitado, substituindo os emissores sem limpeza da explosão de emergência.

Validação principal: `tests/test_explosion_incidents.gd` testa 1–3 incêndios/um caminhão, limite de dois caminhões, fila, repetição de chamados, troca sequencial de alvo, dano por distância, parede, carros, quatro partes, repouso físico e recolhimento real por agentes IML. Com `-- --capture`, gera as imagens `D:/geteco/artifacts/explosion-01-blast.png`, `explosion-02-remains.png` e `explosion-03-iml.png`.

O teste legado de colisão foi atualizado para esperar a animação de saída já existente. Os logs ainda apresentam os erros preexistentes da importação de atalhos salvos antes da criação de InputMap.

O teste no porto revelou que a saída perpendicular do pumper sobrepunha a fachada com a traseira e prendia o caminhão no tráfego. O despacho agora posiciona o pumper paralelo à fachada e usa a entrada lateral pela própria área de acesso; a verificação de espaço considera 146 × 46 unidades. O tráfego deixa a faixa esvaziar e o caminhão aguarda a entrada sem ser reciclado por esperar. A regressão real percorreu 593 unidades, com passo máximo de 2,9, desembarque e extinção confirmados, sem falhas. O teste aguarda `world_build_ready` antes de verificar os serviços criados de forma assíncrona.

Resultados finais: explosões/ocorrências e coleta IML sem falhas; colisão/saída do carro aprovada; canhão de água sem regressão; atendimento real do porto e limpeza dos veículos na troca de cena aprovados.
