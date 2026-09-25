# Sexta leva — acessos restantes e travamentos

Execução com coordenador e um auxiliar, conforme o pedido. Somente checagens dirigidas; o usuário fará a avaliação visual e de FPS. Os arquivos reservados ao Claude na Ammu-Nation não foram alterados.

## Implementado

- **19 acessos convencionais / 17 interiores:** sete chalés, três portas do abrigo compartilhado, três lojas de roupas da montanha, três residências, zelador, bunker e Summit. As folhas existentes abrem por proximidade e os blocos das fachadas têm vãos físicos. Entrar/voltar caminhando usa zoom; a autorização de propriedade das casas continua valendo. Duas fachadas ausentes do abrigo foram montadas nas posições cadastradas. O retorno e o zoom respeitam a porta usada, inclusive quando precisam desviar de um obstáculo.
- **Três acessos especiais:** esgoto, porão Santa Mare e caverna. Escotilhas abrem por proximidade; a caverna usa o limiar da boca do túnel. Caminhar entra/sai, sem E; ficar parado perto não transfere. A descida existente no esgoto foi preservada. A escotilha decorativa do navio agora abre de verdade.
- **Streaming de carros:** antes de remover um chunk, veículos ativos nele ficam suspensos com velocidade vertical zerada. O fluxo existente só retoma a física após confirmar apoio livre. Complementa a proteção dos carros estacionados feita na quinta leva, incluindo trânsito que perde o piso.
- **Explosões:** preparação dos cinco sons durante o carregamento e reaproveitamento dos recursos visuais do fogo. Cada incêndio conserva seus próprios nós, intensidade, idade e limite de luzes. Dano, duração, partículas e aparência foram preservados.
- **Interiores:** catálogo de moradores lê o JSON uma vez e devolve cópias independentes; o fundo dos interiores isolados usa cinza escuro, eliminando o céu colorido atrás do recorte. Não acrescenta geometria ou luzes.

Contagem de implementação: **32 acessos físicos / 30 interiores distintos com entrada automática**. São os ambientes existentes; não são 32 interiores novos. **Zero novas certificações integrais** de visual, oclusão, circulação completa ou FPS.

## Checagens essenciais

- Acessos convencionais: seis famílias e duas origens extras do abrigo exercitadas em Main, caminhando, com porta fechada/aberta, entrada, saída e gate de casa. Primeira execução 65/66; a única falha exigia retorno exatamente no ponto autorado, ocupado por `outfitters_heater`. Reexecução somente dessa loja: **10/10**, usando o desvio existente de 75 cm, com corpo livre. O runtime não foi relaxado para satisfazer a fixture. Não houve caminhada individual pelos 19 acessos.
- Esgoto, navio e caverna, mais cache de fogo e suspensão/retomada do carro: **20/20**, Main real headless, save isolado. Nenhum erro de script ou aviso de ownership na confirmação final.
- Três explosões reais de veículos, diagnóstico de CPU headless: antes **21,471 / 15,968 / 14,052 ms**; depois **6,524 / 2,713 / 6,409 ms**. O som e a construção de recursos do fogo eram os maiores custos. Preparação antecipada transfere trabalho para o carregamento; não prova ganho de FPS/GPU. A coleta anterior completou as três explosões, mas falhou ao escrever o JSON no diretório padrão; o log preserva as medidas. A coleta posterior terminou com exit 0. Avisos de ownership vistos nessa coleta foram corrigidos e não reapareceram no smoke final.

Logs em `C:/Users/rafae/.codex/visualizations/2026/09/24/01a0d558-4410-7471-98cb-1032e2e21647/`: `conventional-access-smoke.log`, `conventional-outfitters-smoke.log`, `phase6-special.log`, `phase6-explosion-stages.log`, `phase6-explosion-after.log` e `phase6-explosion-after.json`.

## Para o teste do usuário

Entrar/sair dos novos lugares; conferir altura/abertura das portas e zoom; trocar de carro e voltar depois de se afastar; explodir veículos e passar de moto pelo porto. Visual, oclusão e FPS aguardam esse feedback, conforme solicitado.

A queda original de 02:21 continua sem reprodução que prove a causa. As proteções corrigem falhas concretas de streaming, sem afirmar identidade com aquele incidente. Revisão artística ampla de materiais/personagens e cobertura completa de colisões continuam abertas. Os móveis e rochas da caverna já tinham metadados de colisão; não receberam alteração especulativa. Ammu-Nation continua na frente do Claude.

Sem commits, sem descarte de alterações concorrentes e sem encerrar o jogo/editor do usuário.
