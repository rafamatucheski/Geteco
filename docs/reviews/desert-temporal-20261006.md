# Revisão temporal da arrancada do deserto — 2026-10-06

Escopo: captura real da Main em Godot .NET 4.7.2, renderer Mobile, RTX 4060 Laptop, 1280×720. Sequência examinada: [sequence.json](../../evidence/desert-drag-temporal-28392-43778501/sequence.json). A revisão foi somente leitura; os arquivos brutos e o runtime não foram alterados.

Os dois defeitos identificados na captura anterior foram corrigidos neste cenário: o rival agora tem projetor efetivamente ligado, e a câmera mantém Dante legível quando a diferença física entre os carros aumenta. Isso não certifica todos os carros, rivais, condições meteorológicas ou áreas do jogo.

## Cobertura e evidência

| Fase | Frames | Tempo na captura | Imagem representativa |
| --- | ---: | ---: | --- |
| Dia parado | 169 | 0,14–5,99 s | [dia](../../evidence/desert-drag-temporal-28392-43778501/day_static.png) |
| Transição contínua 0,72→0,90 do relógio | 173 | 6,03–12,01 s | [crepúsculo](../../evidence/desert-drag-temporal-28392-43778501/00255.jpg) |
| Noite parada | 174 | 12,04–18,01 s | [noite](../../evidence/desert-drag-temporal-28392-43778501/night_static.png) |
| Grid | 89 | 18,08–21,04 s | [dois carros](../../evidence/desert-drag-temporal-28392-43778501/night_drag_staging.png) |
| Corrida e breve pausa modal | 811 | 21,07–48,28 s | [carros próximos](../../evidence/desert-drag-temporal-28392-43778501/00700.jpg), [vantagem real](../../evidence/desert-drag-temporal-28392-43778501/01014.jpg) |
| Frenagem | 111 | 48,32–52,06 s | sequência 01416–01526 |
| Retorno à câmera normal | 175 | 52,10–58,10 s | [retorno](../../evidence/desert-drag-temporal-28392-43778501/night_cleanup.png) |

Inspeção visual manual: PNGs das fases dia, noite, grid e retorno; JPEGs 00255, 00310, 00700, 00791, 00792, 00799, 00800, 01014, 01300, 01349, 01350 e 01351. Os frames consecutivos junto à entrada da seta e a um intervalo maior de captura complementam as amostras espaçadas. Não houve reprodução manual integral de todos os 1.702 JPEGs.

## Faróis e enquadramento

- Em todos os 1.011 frames ativos, Dante registra dois projetores visíveis com energia 1,3; Digo registra um projetor visível com energia 1,3. Os projetores automáticos de NPC permanecem desligados, sem duplicar a fonte usada pela corrida. As energias e a disponibilidade dessas fontes não alternam durante a amostra completa da telemetria.
- As imagens 00700 e 00791 mostram os feixes de ambos os carros sobre a pista. A telemetria comprova estado das fontes, não substitui inspeção do resultado renderizado nem detecta sozinha limitações do renderer.
- O ponto de referência de Dante (posição do carro + 0,7 m de altura) está dentro do viewport em todos os 1.011 frames ativos. Os pontos de ambos estão dentro em todos os 89 frames de grid; essa telemetria não mede a caixa completa de cada modelo. As imagens confirmam duas silhuetas na largada, parcialmente sobrepostas pela perspectiva das faixas reais, sem duplicação de carro para a câmera.
- Recuo lateral medido: 18–27 m. Distância entre câmera e Dante: 16,96–28,92 m. O carro mantém escala legível nas amostras de grande vantagem, corrigindo as miniaturas da sequência anterior.
- O rival permanece dentro do viewport em 284 frames ativos. A seta à esquerda aparece uma única vez, em 00792, com aproximadamente 29 m de vantagem; o centro do rival sai do viewport em 00800. A seta permanece consistente enquanto a diferença aumenta e diminui na frenagem, sem alternância de estado na telemetria.
- O resultado da execução coordenada informou Dante em 19,943 s e Digo em 26,986 s, com 50 verificações aprovadas e stderr vazio. A câmera não modifica posições, potência, resultado ou ritmo dos carros.

## Iluminação observada e limites

As amostras da transição mostram mudança de cor e sombra do dia para a noite. Não identifiquei apagamento involuntário dos faróis nem alternância brusca de câmera nas imagens examinadas. O fogo residual da antiga prova de destruição desapareceu da cobertura: esse teste ocorre depois de encerrar a gravação.

Persistem observações de acabamento: o asfalto ainda apresenta grão organizado e fissuras arredondadas perceptíveis na câmera normal; o horizonte continua com grandes volumes geométricos. Isso não invalida as correções de enquadramento e faróis, mas esta revisão não aprova o acabamento artístico de todo o deserto.

O primeiro frame do grid desta sequência contém a transição inicial do HUD, com nome do rival ainda não preenchido, distância zero e minimapa anterior sobre os comandos. As amostras subsequentes exibem os dados completos; ícones normais de arma/mochila e a seta do objetivo permanecem elementos concorrentes com a interface da corrida. Essa pendência foi verificada novamente na sequência 3, abaixo.

## Cadência: não usar como benchmark

1.702 frames em 57,957 s; zero saltos no contador de frames renderizados. Intervalo mediano entre capturas: 33,254 ms; p95: 37,588 ms; máximo: 331,628 ms. Há 24 intervalos acima de 50 ms e 12 acima de 100 ms. Os maiores intervalos coincidem em parte com PNGs de referência das mudanças de fase.

O processo foi limitado a 30 FPS e gravou JPEG em todo frame renderizado, além dos PNGs. Esses números descrevem a cadência da captura com sua sobrecarga, não o desempenho normal. Eles também limitam a capacidade de excluir flickering rápido durante intervalos maiores. Comparação de frame time pertence ao benchmark separado do coordenador.

Não cobertos: cidade inteira, interiores, posto de caminhões, chuva, outros perfis de carro ou adversários, corrida com Dante muito atrás, qualidade auditiva, comparação de FPS e inspeção contínua de cada frame. Nenhum resultado desta revisão deve ser generalizado para esses cenários.

## Fechamento da interface — sequência 3

[Captura final](../../evidence/desert-drag-temporal-59764-41845574/sequence.json): 1.639 frames, 55,503 s, sem salto de frames renderizados. Execução coordenada: 59 verificações aprovadas, stderr vazio; Dante 19,943 s, Digo 23,905 s. A inspeção adicional ficou restrita à interface e suas transições.

- [Primeiro frame do grid](../../evidence/desert-drag-temporal-59764-41845574/night_drag_staging.png): já mostra “DANTE × DIGO”, 800 m, contagem 3 e faixa de RPM de largada. Minimap, ícones comuns e seta do objetivo não cobrem os controles.
- [Corrida](../../evidence/desert-drag-temporal-59764-41845574/00976.jpg): instrumentos e comandos legíveis; seta do rival mostra a diferença real. A fixture confirmou supressão contínua do HUD comum e dos indicadores de objetivo.
- [Retorno](../../evidence/desert-drag-temporal-59764-41845574/01465.jpg) e [estado estabilizado](../../evidence/desert-drag-temporal-59764-41845574/01552.jpg): câmera normal, minimapa, status e inventário restaurados; resultado de vitória e recompensa aparecem. A fixture também verificou restauração após queimada, Q e destruição.

Ressalva pequena de transição: o primeiro frame de cleanup, 01464, ainda contém o texto antigo “Abandonar arrancada”; no frame imediatamente seguinte, 01465, esse texto desapareceu e o resultado correto está visível. Não foi observada persistência.

A sobreposição de interfaces e os dados vazios do primeiro grid estão resolvidos na cobertura examinada. Permanecem as reservas de cadência, ausência de benchmark de FPS e impossibilidade de certificar flickering universal descritas acima. Nenhum arquivo de runtime foi alterado durante esta revisão.
