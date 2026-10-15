# Prompts: todos os prédios do jogo em textura pintada (15/10)

Inventário de onde saiu cada item: `world/regions/OriginalWorldData.json` (porto, cidade e
Northbank/ilha), `world/mountain_detail/` (serra com neve), `world/desert/` e `world/mining/`
(deserto). Os sobrados (`brownstone`, `rowhouse_terrace`) já têm os 7 estilos residenciais,
e galpão e loja já têm um estilo cada.

Três agentes ao mesmo tempo, cada um numa pasta diferente. O texto completo de cada agente
está abaixo e pode ser colado direto.

---

## Agente A: cidade (comércio, escritórios, torres, ilha)

```
Você vai gerar PACOTES DE TEXTURAS para prédios de um jogo 3D, usando geração de imagem. Gere uma imagem por vez e SALVE cada uma no disco no caminho indicado. Não pare até terminar todos os prédios da lista.

REGRAS PARA TODAS AS IMAGENS:
- Estilo GTA Vice City / San Andreas: pintado à mão com base em foto, cores levemente saturadas e quentes, cidade portuária brasileira com ar anos 80/90.
- Vista 100% frontal e ortográfica (sem perspectiva), linhas retas e paralelas.
- Iluminação neutra e uniforme, SEM sombra de sol.
- Só a superfície pedida, preenchendo o quadro de borda a borda. Sem céu, chão, pessoas, carros, plantas, moldura.
- Letreiros: só o NOME PRÓPRIO indicado, em letras grandes e legíveis. Nada de palavras genéricas como "LOJA" ou "BANCO".
- Respeite a proporção (largura x altura) de cada item.
- Dentro de um mesmo prédio, todas as imagens têm o mesmo material, cores e sujeira. Cada versão "noite" é a imagem "dia" com tudo exatamente no mesmo lugar, metade das janelas acesas em amarelo quente, vitrines e letreiros acesos, paredes escuras e azuladas.
- PORTAS: nunca desenhe a folha da porta na fachada. O vão é um corredor ou saguão escuro, porque a porta é um objeto 3D que abre. A folha vai em imagem separada.

PACOTE PADRÃO DE CADA PRÉDIO (salve em D:\geteco\game\output\imagegen\<pasta>\):
frente-dia.png, frente-noite.png, lateral-dia.png, lateral-noite.png, fundos-dia.png, fundos-noite.png, telhado.png (visto de cima), porta-frente.png (só a folha), porta-frente-verso.png, porta-fundos.png (só a folha), porta-fundos-verso.png.
Lateral e fundos: mesmo material, menos janelas, canos, ar-condicionado, fiação, manchas. Fundos com porta de serviço sem a folha (vão escuro).

PRÉDIOS ALTOS (marcados com [ALTO]): em vez de uma frente única, gere frente-terreo-dia/noite (térreo, 4 m de altura), frente-andar-dia/noite (UM andar típico de 3 m, que se repete sem emenda na vertical), frente-topo-dia/noite (último andar com coroamento, 3 m). Faça o mesmo para lateral e fundos (lateral-terreo, lateral-andar, lateral-topo, etc.).

LISTA DESTE AGENTE:
1) pasta "escritorio-a" [ALTO] (12 m de largura): prédio de escritórios anos 70 de concreto e faixas de vidro fumê, caixilhos de alumínio, térreo com portaria de vidro e granito.
2) pasta "escritorio-b" [ALTO] (12 m): escritórios art déco de pedra clara com pilastras, janelas verticais de ferro, portaria com marquise de bronze.
3) pasta "escritorio-c" [ALTO] (12 m): escritórios anos 90 de pastilha azul e vidro espelhado verde, térreo com lojinha e portaria.
4) pasta "torre-exchange" [ALTO] (16 m): torre de bolsa e negócios "Exchange", granito escuro e vidro, coroamento iluminado.
5) pasta "torre-civica" [ALTO] (16 m): torre da prefeitura "Civic Tower", pedra clara clássica, relógio no topo.
6) pasta "banco" (12 x 8 m): agência bancária "Northfrontage" de granito e vidro, caixa eletrônico embutido na fachada, porta giratória sem a folha.
7) pasta "lanchonete-esquina" (10 x 6 m): lanchonete de esquina "Corner Diner" anos 50, faixa cromada, janelões, letreiro de neon.
8) pasta "mercearia-esquina" (10 x 6 m): mercearia de esquina, vitrine com frutas e caixotes, toldo, apartamento em cima.
9) pasta "lavanderia" (10 x 6 m): lavanderia "Laundry" com vitrine mostrando máquinas de lavar, azulejo verde-água.
10) pasta "cinema" (14 x 9 m): cinema de rua "Island Cinema" art déco, marquise com lâmpadas, bilheteria, cartazes sem texto.
11) pasta "mercado-ilha" (12 x 6 m): mercadinho "Island Grocer", vitrine, caixotes na calçada pintados na base, toldo.
12) pasta "cafe-orla" (10 x 6 m): café da orla "Promenade Cafe", madeira pintada de branco, janelas basculantes, varandinha.
13) pasta "lofts-fundicao" [ALTO] (14 m): lofts numa antiga fundição, "Foundry Lofts", tijolo escuro, janelas industriais grandes, escada de incêndio pintada.
14) pasta "predio-misto" [ALTO] (10 m): prédio residencial de 4 andares com loja no térreo, reboco descascado, varandinhas de ferro, roupa no varal.

Ao terminar, liste os arquivos salvos por pasta e aponte qualquer imagem com perspectiva, sombra, texto errado ou fora da proporção, para gerar de novo.
```

---

## Agente B: serviços públicos e indústria

```
Você vai gerar PACOTES DE TEXTURAS para prédios de um jogo 3D, usando geração de imagem. Gere uma imagem por vez e SALVE cada uma no disco no caminho indicado. Não pare até terminar todos os prédios da lista.

REGRAS PARA TODAS AS IMAGENS:
- Estilo GTA Vice City / San Andreas: pintado à mão com base em foto, cores levemente saturadas e quentes, cidade portuária brasileira com ar anos 80/90.
- Vista 100% frontal e ortográfica (sem perspectiva), linhas retas e paralelas.
- Iluminação neutra e uniforme, SEM sombra de sol.
- Só a superfície pedida, preenchendo o quadro de borda a borda. Sem céu, chão, pessoas, carros, plantas, moldura.
- Letreiros: só o NOME PRÓPRIO ou a palavra institucional indicada, em letras grandes e legíveis.
- Respeite a proporção (largura x altura) de cada item.
- Dentro de um mesmo prédio, todas as imagens têm o mesmo material, cores e sujeira. Cada versão "noite" é a imagem "dia" com tudo exatamente no mesmo lugar, metade das janelas acesas em amarelo quente, letreiros e luminárias acesos, paredes escuras e azuladas.
- PORTAS e PORTÕES: nunca desenhe a folha na fachada. O vão é escuro (corredor, garagem ou galpão por dentro), porque a porta é um objeto 3D que abre. A folha vai em imagem separada.

PACOTE PADRÃO DE CADA PRÉDIO (salve em D:\geteco\game\output\imagegen\<pasta>\):
frente-dia.png, frente-noite.png, lateral-dia.png, lateral-noite.png, fundos-dia.png, fundos-noite.png, telhado.png (visto de cima), porta-frente.png (só a folha), porta-frente-verso.png, porta-fundos.png, porta-fundos-verso.png.
Se o prédio tiver portão grande (garagem, bombeiros, galpão), gere também portao.png e portao-verso.png (só a folha ou porta de enrolar fechada).
Lateral e fundos: mesmo material, menos janelas, canos, ar-condicionado, fiação, manchas.

LISTA DESTE AGENTE:
1) pasta "delegacia" (16 x 8 m, 2 andares): delegacia central "POLÍCIA", tijolo e concreto azul-acinzentado, brasão, luminárias azuis na entrada, janelas com grade no térreo, escada de acesso.
2) pasta "posto-policial" (8 x 4 m, 1 andar): posto policial de bairro, pequeno, azul e branco, janelão de vidro, "POLÍCIA" em cima.
3) pasta "bombeiros" (16 x 8 m, 2 andares): quartel de bombeiros "BOMBEIROS" de tijolo vermelho, 2 portões grandes de viatura (vão escuro, portões em imagem separada), torre de mangueira na lateral.
4) pasta "clinica" (14 x 8 m, 2 andares): clínica/hospital "CLÍNICA" branca e verde-água, cruz verde, entrada de ambulância com marquise.
5) pasta "galpao-portuario" (20 x 8 m): galpão de carga do porto, chapa ondulada pintada e enferrujada, portão de enrolar grande, número do armazém pintado.
6) pasta "camara-fria" (16 x 7 m): armazém frigorífico "Cold Storage", painéis isotérmicos brancos encardidos, doca de caminhão, portões de enrolar.
7) pasta "mercado-municipal" (20 x 9 m): mercado coberto "Market Hall" de tijolo e ferro, arcos grandes envidraçados, relógio.
8) pasta "oficina-mecanica" (12 x 6 m): oficina "Motor Workshop", porta de enrolar aberta mostrando a oficina escura, placas de óleo, pneus encostados pintados na base.
9) pasta "oficina-artesao" (10 x 6 m): oficina de marcenaria "Union Workshop", madeira e tijolo, portas de celeiro.
10) pasta "garagem-predio" (14 x 6 m): edifício-garagem de concreto com aberturas horizontais, rampa de entrada.
11) pasta "escritorio-frete" (12 x 6 m): escritório da transportadora "Freight Office", pré-moldado, janelas fitas, logotipo de caminhão.
12) pasta "museu-maritimo" (18 x 9 m): museu "Maritime Museum", pedra clássica, colunas, âncora decorativa pintada, janelões em arco.
13) pasta "aquario" (18 x 7 m): aquário municipal "Aquarium", anos 60, curvas, pastilha azul e branca, painel de vidro com peixes pintados.
14) pasta "estacao-onibus" (12 x 5 m): estação de ônibus "Transit House", concreto e vidro, painel de horários sem texto pequeno.

Ao terminar, liste os arquivos salvos por pasta e aponte qualquer imagem com perspectiva, sombra, texto errado ou fora da proporção, para gerar de novo.
```

---

## Agente C: casas do bairro, da serra (neve) e do deserto

```
Você vai gerar PACOTES DE TEXTURAS para casas e prédios pequenos de um jogo 3D, usando geração de imagem. Gere uma imagem por vez e SALVE cada uma no disco no caminho indicado. Não pare até terminar todos os itens da lista.

REGRAS PARA TODAS AS IMAGENS:
- Estilo GTA Vice City / San Andreas: pintado à mão com base em foto, cores levemente saturadas e quentes.
- Vista 100% frontal e ortográfica (sem perspectiva), linhas retas e paralelas.
- Iluminação neutra e uniforme, SEM sombra de sol.
- Só a superfície pedida, preenchendo o quadro de borda a borda. Sem céu, chão, pessoas, carros, plantas soltas, moldura.
- Letreiros: só o NOME PRÓPRIO indicado, em letras grandes e legíveis.
- Respeite a proporção (largura x altura) de cada item.
- Dentro de uma mesma casa, todas as imagens têm o mesmo material, cores e sujeira. Cada versão "noite" é a imagem "dia" com tudo exatamente no mesmo lugar, 1 ou 2 janelas acesas em amarelo quente, paredes escuras e azuladas.
- PORTAS: nunca desenhe a folha na fachada. O vão é um corredor escuro, porque a porta é um objeto 3D que abre. A folha vai em imagem separada.
- CASA DE TELHADO INCLINADO: a frente e os fundos vão só até o beiral (parede retangular). A empena (triângulo da lateral) entra NA IMAGEM DA LATERAL, com o topo em ponta, e fundo transparente ou preto chapado fora do triângulo. O telhado é a superfície de UMA água, esticada como se fosse plana.

PACOTE PADRÃO DE CADA CASA (salve em D:\geteco\game\output\imagegen\<pasta>\):
frente-dia.png, frente-noite.png, lateral-dia.png, lateral-noite.png, fundos-dia.png, fundos-noite.png, telhado.png, porta-frente.png (só a folha), porta-frente-verso.png, porta-fundos.png, porta-fundos-verso.png.

BAIRRO COBRA (casas térreas do porto, 8 x 4 m de frente, telhado inclinado 8 x 4,5 m):
1) pasta "casa-varanda": casa térrea com varanda de madeira pintada (pilares e guarda-corpo pintados na base da frente), madeira azul-acinzentada.
2) pasta "casa-duplex": duplex térreo geminado de alvenaria bege, duas portas, dois números.
3) pasta "casa-telha-madeira": casa revestida de telhas de madeira (shingle) cinza-esverdeada.
4) pasta "casa-patio": casa com muro e portão de pátio (vão escuro), reboco branco.
5) pasta "casa-tijolo-duplex": duplex de tijolo aparente com janelas brancas.
6) pasta "casa-telha-zinco": casa simples com telhado de zinco ondulado, madeira pintada verde desbotada.
7) pasta "casa-bangalo": bangalô de esquina com reboco amarelo e varandinha.
8) pasta "casa-oficina-cobra": casa com garagem/oficina, porta de enrolar (vão escuro), muro pichado sem palavras.

PATROL COURT (cidade, 8 x 6 m, 2 andares, laje plana):
9) pasta "casa-patrol-a": casa urbana moderna de reboco cinza e madeira.
10) pasta "casa-patrol-b": casa urbana com fachada de pedra e garagem embutida.

SERRA COM NEVE (vila de montanha, telhados inclinados com neve):
11) pasta "chale-cedro" (8 x 5 m de frente): chalé alpino de toras de cedro, base de pedra, varanda, lenha empilhada pintada na base, neve no peitoril.
12) pasta "chale-pedra" (8 x 5 m): casa de pedra de vila de montanha, venezianas vermelhas, chaminé de pedra.
13) pasta "chale-enxaimel" (8 x 6 m, 2 andares): casa enxaimel branca com vigas escuras, sacada de madeira com flores.
14) pasta "loja-casacos" (10 x 5 m): loja de roupas de inverno "Casacos da Vila", vitrine com manequins de proporção humana real vestindo casacos, madeira e pedra, neve no toldo.
15) pasta "terminal-serra" (14 x 5 m): terminal rodoviário "Terminal da Serra", madeira e vidro, marquise com neve, bilheteria.
16) pasta "pousada-serra" (12 x 7 m, 2 andares): pousada de montanha, madeira escura e pedra, sacadas.
TELHADOS DA SERRA: telha escura coberta de neve com beirais de neve escorrida; gere também telhado-sem-neve.png.

DESERTO (vila Santa Lua e estrada):
17) pasta "casa-adobe" (8 x 4 m): casa de adobe ocre com cantos arredondados, vigas de madeira (vigas aparentes pintadas), janelas pequenas com grade.
18) pasta "casa-pedra-deserto" (8 x 4 m): casa de pedra arenito, telhado plano de barro.
19) pasta "casa-rancho" (10 x 4 m): casa de rancho de madeira desbotada pelo sol, varanda coberta, telhado de zinco.
20) pasta "galpao-deserto" (8 x 4 m): galpão de madeira e zinco enferrujado, porta de celeiro.
21) pasta "armazem-santa-lua" (12 x 5 m): armazém geral "Santa Lua", fachada falsa de faroeste, alpendre, vitrine empoeirada.
22) pasta "pedagio" (14 x 4 m): praça de pedágio de concreto com cabines, faixa amarela e preta, cobertura metálica.
23) pasta "escritorio-mina" (10 x 4 m): escritório de mineradora em contêiner/pré-moldado, poeira laranja, placas de segurança sem texto.
24) pasta "posto-deserto" (12 x 4 m): loja de conveniência de posto de estrada anos 80, poeira, letreiro apagado sem texto.

Ao terminar, liste os arquivos salvos por pasta e aponte qualquer imagem com perspectiva, sombra, texto errado ou fora da proporção, para gerar de novo.
```
