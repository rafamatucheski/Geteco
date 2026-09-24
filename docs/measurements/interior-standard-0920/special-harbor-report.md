# Interiores especiais do Porto — 20/09/2026

Escopo: três residências, galeria de manutenção sob o bueiro e garagem Porto Rosso. Northgate Auto foi retirada da reforma por solicitação do usuário; suas alterações experimentais de apresentação e conteúdo foram desfeitas manualmente. O serviço original de entrada, reparo e saída foi preservado.

## Apresentação e identidade

Todos usam geometria 3D, câmera ortográfica com direção `(0,18,15)`, MSAA 2× e atores compartilhando a profundidade da sala. Os tamanhos das câmeras variam para enquadrar a arquitetura, sem alterar a inclinação de referência. Indicadores de acesso usam o retângulo laranja arredondado compartilhado, sem texto.

| Lugar | Renderização efetiva | Enquadramento | Identidade e recompensa |
|---|---|---|---|
| Casa Westgate Garden | 1440×1000 ocupada; 2×2 desativada vazia | Ortho 15,8 | Sala acolhedora com cozinha ao fundo, cama lateral e poltrona de leitura; $300 persistentes |
| Casa Quayside | 1440×1000 ocupada; 2×2 desativada vazia | Ortho 15,8 | Cozinha à frente direita, dormitório ao fundo esquerdo, circulação própria; $700 persistentes |
| Casa Canal North | 1440×1000 ocupada; 2×2 desativada vazia | Ortho 15,8 | Escritório central com notebook e distribuição própria de dormitório e cozinha; $1500 persistentes |
| Galeria do bueiro | 1152×720; atualização contínua ocupada; instância removida ao sair | Ortho 18 | Alvenaria, canal, ponte e tubulações; sawed-off com 24 cartuchos, flutuação, aro e coleta por contato |
| Garagem Porto Rosso | 1600×1200; atualização contínua ativa, desativada vazia | Ortho 28 | Coleção de cinco carros, guardas e veículo exclusivo vendável por $50 mil; entrada entre 1h e 5h |

As casas mantêm guarda-roupa, arsenal, comida, descanso e saída acessíveis; têm luz principal com sombra e duas luzes locais quentes. O esgoto mantém World2D isolado, escada, áudio próprio e retorno à superfície. A garagem preserva veículos dirigíveis, alarme e venda única. Seus guardas foram estreitados somente nesta instância, preservando a altura.

## Evidência já obtida

`special-harbor-contract-typed.log`: três casas e esgoto passaram colisão real do jogador/NPC, profundidade com controle positivo, circulação, coleta e persistência. As duas falhas finais desse lote pertencem à antiga reforma Northgate, posteriormente removida; não são usadas como aprovação do serviço preservado.

Fotos desses quatro ambientes: `Residence_westgate_garden-standard.png`, `Residence_quayside_house-standard.png`, `Residence_canal_north-standard.png`, `RuntimeSewer-standard.png`.

`sewer-functional-final2.log`: PASS sem falhas — abertura, descida e subida da escada, ponte, sólidos, instância isolada, suspensão/retomada da rua e áudio, coleta por contato, munição e save; bala, impacto sonoro, explosão, melee e granada afetam somente o mundo subterrâneo. O teste legado recebeu preparação explícita da pistola possuída e esperas da animação de lançamento e do impulso anterior; os erros iniciais eram da fixture, sem alteração do combate do jogo.

`residence-compaction-final.log`: PASS sem falhas — alvo 2×2 vazio, recuperação de tamanho e invariância de projeção do piso, spawn, sólidos e interações.

`northgate-preserved-final.log`: PASS sem falhas — apresentação/conteúdo experimental ausentes, porta abre, casco real passa, estacionar inicia o reparo, cura completa cobra $100 uma única vez e devolve os controles. Foto: `northgate-preserved.png`. Northgate permanece fora da contagem de reforma.

`port-boss-functional-alarm-fixed.log`: PASS 174 checks — horários, cinco veículos, colisões reais, oclusão separada jogador/guarda (0 pixels atrás; controles livres 865/866), roubo, cabine, direção e saída após fechamento, polícia, venda e save. Pagamento observado: $50.000 do carro + $300 de conquistas separadas; duplicação recusada. Fotos: `port-boss-garagem.png`, `port-boss-porto-rosso-dante.png`.

O teste identificou um defeito real do alarme: desativar a sala após sair congelava seu countdown. A contagem passou para um Timer filho que permanece ativo fora da sala e respeita pausa; o save consulta seu tempo restante. Confirmado: 11,516 s restantes ao sair terminaram em 11,551 s, com despacho policial correto. Não foi necessário alterar combate, gerente de interiores ou outros ambientes.

`port-boss-alarm-resume.log`: PASS cinco checks adicionais — alarme salvo não consome tempo de carregamento, retoma com sala desativada, congela no pause e aciona a polícia ao terminar. A espera do carregamento usa apenas o ramo de save pendente; o benchmark de visita sem alarme permanece equivalente.

## Medição comparável

Cena HarborGame real, janela 1280×720, GPU RTX 4060 Laptop, renderizador Mobile, VSync ligado, limite de 60 FPS, seed 4702. Cada lugar: 5 s de primeira visita, 5 s de aquecimento, 30 s de amostra. Relógio da campanha e streaming seguem o mesmo roteiro; a campanha pode atualizar a hora apesar de `is_dynamic_time=false`. Dados brutos ficam nos JSON `special-harbor-before-*` / `special-harbor-after-*`. FPS medidos não representam a frequência física do monitor.

| Lugar | FPS antes → depois | p50 depois (ms) | p95 antes → depois (ms) | p99 antes → depois (ms) | Máximo depois (ms) | >33,3 / >66,7 depois | Primeira visita antes → depois (máx. ms) |
|---|---:|---:|---:|---:|---:|---:|---:|
| Westgate Garden | 59,98 → 59,98 | 16,654 | 18,087 → 17,839 | 18,714 → 18,283 | 50,136 | 1 / 0 | 121,540 → 121,350 |
| Quayside | 57,18 → 55,90 | 16,726 | 18,174 → 19,112 | 19,091 → 37,938 | 341,844 | 27 / 7 | 27,993 → 20,674 |
| Canal North | 59,95 → 60,01 | 16,672 | 18,184 → 17,936 | 18,888 → 18,298 | 18,641 | 0 / 0 | 203,548 → 188,487 |
| Galeria do bueiro | 60,00 → 60,00 | 16,665 | 16,835 → 16,785 | 17,064 → 16,993 | 17,275 | 0 / 0 | 17,521 → 17,130 |
| Garagem Porto Rosso | 60,01 → 60,01 | 16,663 | 18,292 → 18,144 | 18,592 → 18,491 | 20,784 | 0 / 0 | 51,167 → 46,950 |

Quatro lugares tiveram p95/p99 melhores já na primeira comparação. Quayside recebeu uma única confirmação equivalente devido ao resultado inicial: o replay manteve o prefixo Westgate → Quayside e acrescentou marcadores de início/fim da janela, flags de carregamento regional e contagens do PresentationBudget.

`special-harbor-confirm-quayside_house.json`: **57,38 FPS; p50 16,677 ms; p95 17,675 ms; p99 18,263 ms; máximo 372,170 ms; 8 quadros >33,3 ms e 7 >66,7 ms; primeira visita máximo 28,737 ms.** p95/p99 ficaram melhores que o baseline (18,174/19,091 ms), e as contagens de quadros longos são iguais ao baseline. A regressão inicial de percentis não foi reproduzida. Durante a janela, PresentationBudget permaneceu em 10 builds, enquanto o carregamento da montanha passou de `building=false` para `true`. Isso identifica atividade de streaming concorrente e exclui builds de PresentationBudget nessa janela, mas não quantifica sozinho quanto cada trecho de carregamento causou dos picos.

O prefixo Westgate nessa confirmação teve 59,49 FPS, p95 17,997/p99 18,894 ms, máximo 278,883 ms e um pico de primeira visita de 1095,655 ms (antes/primeiro after: 121,540/121,350 ms). PB permaneceu em 9 builds e a montanha não iniciou durante sua amostra. Essa variação de carregamento está registrada; não atribuir a causa sem um perfil específico.

Fotos finais reais: `special-harbor-after-westgate_garden.png`, `special-harbor-after-quayside_house.png`, `special-harbor-after-canal_north.png`, `special-harbor-after-sewer.png`, `port-boss-final-clean.png`. Todas foram inspecionadas. O texto externo do turno do Porto Sul agora fica oculto dentro de interiores; o Label volta ao sair, preservando o restante do HUD e operação. `special-harbor-confirm.log` confirma `hidden_inside=true restored_outside=true`.

Estado: cinco ambientes aprovados em funcionalidades/colisão/profundidade, com comparação de desempenho concluída e nenhuma regressão reproduzida dos percentis. **Quayside não está aprovado na meta de 60 FPS**: mantém aproximadamente 57 FPS médios durante o carregamento concorrente, já observado no baseline. Há também variação de primeira visita. Mensagens de recursos/RIDs na desmontagem da cena grande também existem no baseline; esta execução não certifica ausência de vazamentos globais.

O diagnóstico posterior, em `harbor-stall-trace-report.md`, identificou a solicitação independente de carregamento no serviço do ônibus Porto–Montanha. O transporte e o streaming foram preservados; Quayside mantém sua pendência de desempenho.
