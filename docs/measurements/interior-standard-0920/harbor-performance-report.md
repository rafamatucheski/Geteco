# Porto — comparativo final de interiores

Godot 4.7.2, Vulkan Mobile, RTX 4060 Laptop, saída 1280×720, VSync ligado e limite de 60 FPS. Cena real HarborGame, mesma ordem de portas e seed 13092026; saves isolados. Cinco segundos de primeira visita, cinco de aquecimento e trinta de amostra por sala. Dados brutos `harbor-before-*.json` e `harbor-final-*.json`. O cenário WorkshopInterior sem acesso foi descartado.

**Estado mais recente:** [diagnóstico monitorado de CPU/GPU](harbor-stall-trace-report.md). Sem outras capturas detectadas, clínica, bombeiros e Ammu-Nation tiveram amostras de aproximadamente 60 FPS; os picos anteriores permanecem documentados, sem alegar uma correção de código inexistente. A delegacia ficou em 52,52 FPS durante o trabalho regional e permanece pendente. O ônibus regional solicita a montanha independentemente da distância do jogador, por `HarborMountainCoachService.gd`; não foi alterado por esta reforma.

**Conveniência, confirmação isolada final:** `harbor-fuel-isolated.log`, código 0, 41 snapshots de processos sem concorrência detectada; 59,98 FPS, p50 16,665 / p95 17,614 / p99 18,349 ms, máximo estável 52,479 ms, um quadro acima de 33,3 ms e nenhum acima de 66,7 ms. Primeira visita: máximo 33,269 ms. Roteiro focado na sala após inicializar HarborGame, mantendo resolução/qualidade, VSync, seed e janelas de 5+5+30 s. Comparativo p95/p99 dentro da tolerância; aprovado nesse cenário. [Foto final do atendente e sala](harbor-fuel-isolated-FuelInterior.png).

## Primeira execução depois das alterações

FPS = quadros / tempo real total; p95/p99 e máximos em milissegundos. Não confundir resolução interna, MSAA ou limite de FPS com fluidez comprovada.

| Ambiente | Antes FPS / p95 / p99 | Depois FPS / p95 / p99 | Máximo estável | Quadros >33,3 / >66,7 ms | Máximo primeira visita | Estado |
|---|---|---|---:|---:|---:|---|
| Maciota | 59,98 / 17,960 / 18,327 | 59,98 / 18,137 / 18,490 | 54,782 | 1 / 0 | 33,444 | Sem regressão significativa; checks funcionais aprovados |
| Delegacia | 56,91 / 17,946 / 24,070 | 56,81 / 18,299 / 25,608 | 376,066 | 16 / 9 | 20,198 | Confirmação pendente; queda já existia, p99 aumentou 6,4% |
| Clínica | 60,01 / 17,810 / 18,220 | 57,51 / 19,579 / 40,116 | 55,116 | 32 / 0 | 227,679 | Confirmação pendente; não aprovada nesta execução |
| Bombeiros | 60,01 / 18,100 / 18,461 | 60,01 / 17,921 / 18,245 | 19,840 | 0 / 0 | 31,772 | Aprovado nos cenários medidos |
| Zelador | 60,01 / 17,996 / 18,267 | 60,01 / 18,084 / 18,382 | 19,060 | 0 / 0 | 22,184 | Aprovado nos cenários medidos |
| Ammu-Nation | 59,99 / 18,021 / 18,403 | 57,30 / 19,170 / 40,565 | 68,775 | 38 / 1 | 21,022 | Confirmação pendente; não aprovada nesta execução |
| Banco | 60,00 / 18,047 / 18,866 | 59,95 / 17,786 / 18,402 | 48,081 | 3 / 0 | 527,401 | Regime estável próximo de 60; conferir pico de primeira visita |
| Conveniência | 60,01 / 17,838 / 18,359 | 60,01 / 17,824 / 18,369 | 24,204 | 0 / 0 | 47,993 | Atendente recebeu correção visual posterior; nova foto/medição pendentes |
| Union | 59,99 / 17,905 / 18,601 | 60,01 / 17,693 / 18,071 | 24,577 | 0 / 0 | 18,114 | Aprovado nos cenários medidos |

Logs `PB_BUILD` entre salas não demonstram que as construções ocorreram na janela estável. A confirmação terá marcações de começo/fim e contadores de construções para evitar atribuir causa sem evidência. A simulação exterior continua por contrato, incluindo eventos e resposta policial; não foi desligada para obter um resultado melhor.

Análise dos tempos brutos: na delegacia os primeiros 1.500 quadros ficaram próximos de 16,67 ms e os picos se concentraram no final; na clínica concentraram-se nos primeiros 600 quadros; na Ammu-Nation, após o quadro 1.200. Isso justifica a confirmação instrumentada, mas não prova a origem dos picos nem permite descartá-los do resultado.

## Confirmação instrumentada

`harbor-confirm-performance.log` repetiu o roteiro, registrando as janelas de amostra, contagem de construções de atores e estado do carregamento da montanha. A física efetiva é de 60 Hz.

| Ambiente | FPS / p95 / p99 (ms) | Máximo estável / primeira visita (ms) | Resultado da conferência |
|---|---|---|---|
| Maciota | 59,98 / 18,387 / 18,885 | 54,681 / 34,893 | Mantém comparativo sem regressão significativa |
| Delegacia | 57,09 / 18,355 / 21,559 | 432,480 / 19,917 | p99 melhor que antes; meta 60 ainda pendente pelos picos. Montanha começa a carregar durante a janela, sem construções PB |
| Clínica | 57,29 / 19,685 / 39,827 | 65,421 / 262,942 | Picos repetidos; montanha já pronta e nenhuma construção PB durante a janela. Causa ainda não demonstrada |
| Bombeiros | 57,68 / 18,957 / 36,913 | 111,604 / 25,884 | Novos picos nesta conferência; aprovação de desempenho retirada até diagnóstico |
| Zelador | 60,01 / 18,145 / 18,458 | 23,029 / 21,535 | Mantém comparativo aprovado |
| Ammu-Nation | 60,01 / 17,880 / 18,384 | 19,741 / 29,309 | Houve captura de outra tarefa durante a amostra; resultado não usado para aprovação final |
| Banco | 60,01 / 17,959 / 18,899 | 43,741 / 21,994 | Pico frio anterior não se repetiu; funcional e desempenho aprovados |
| Conveniência | 60,01 / 18,234 / 18,844 | 25,186 / 36,621 | Foto confirma roupas/proporções corrigidas; outra captura sobreposta impede usar esta amostra como aprovação final |
| Union | 60,01 / 18,092 / 18,490 | 20,837 / 19,985 | Mantém comparativo aprovado |

A concorrência foi identificada por inspeção dos processos: `capture_maciota_compact_exterior.gd -- before` iniciou às 10:29:49; outra captura iniciou às 10:31:36. São processos de outra tarefa, não encerrados por esta sessão. Esses horários sobrepõem Ammu-Nation e conveniência. Não explicam automaticamente os picos anteriores de clínica/bombeiros. Um próximo diagnóstico, se executado, terá monitor de processos e telemetria de CPU/física/GPU; não será uma repetição cega.

## Qualidade efetiva capturada no jogo

Todas as nove salas: projeção ortográfica alinhada, MSAA 2× e atualização contínua do viewport enquanto ocupado (`UPDATE_ALWAYS`). Jogador e NPC compartilham a profundidade do cenário. A frequência observada é a medição acima; não existe promessa de 60 Hz apenas por selecionar atualização contínua.

| Ambiente | Resolução interna | Tamanho ortográfico | Identidade/recompensa |
|---|---:|---:|---|
| Maciota | 2048×1024 | 15 | Garagem e escritório; Monaliza/progressão, sem armas |
| Delegacia | 1760×1100 | 18 | Atendimento policial e cela; dinheiro |
| Clínica | 1440×1040 | 22 | Recepção e quatro leitos; recuperação de vida |
| Bombeiros | 1600×1100 | 30 | Três baias, caminhões e equipamentos; cura e veículos |
| Zelador | 1200×960 | 12 | Casa do cemitério; dinheiro e pista |
| Ammu-Nation | 1440×1000 | 16,4 | Expositores e balcão; soco-inglês coletável |
| Banco | 1440×1000 | 14,8 | Salão e cofre; R$ 10.000 no assalto |
| Conveniência | 1440×1000 | 16 | Geladeiras, gôndolas e café; R$ 350 coletáveis e caixa funcional |
| Union | 1280×900 | 12,5 | Roupas em manequins e araras; R$ 300 |

As resoluções diferentes acompanham proporção e área da planta. Fotos finais: `harbor-final-NOME.png`, ao lado dos JSONs. As medições foram feitas uma por vez. Os logs ainda registram recursos retidos no encerramento completo do jogo; este trabalho não certifica ausência de vazamentos globais.
