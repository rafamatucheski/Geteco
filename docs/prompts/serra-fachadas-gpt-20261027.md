# Prompts: fachadas antigas da serra para o GPT (27/10)

Levantamento feito no jogo de verdade (capturas em `evidence/serra-predios-20261027/`, fora do
Git). Na serra, só os quatro chalés da vila e a loja "Casacos da Vila" já são prédios pintados
(`PaintedFacadeKit`). Todo o resto ainda é caixa de cor lisa ou com textura procedural, e é isso
que lê como "textura antiga". Em ordem de prioridade (o topo da serra primeiro):

| # | Prédio no jogo | Onde | Modelo atual | Pasta do pacote |
|---|---|---|---|---|
| 1 | **Estação Zero** (bunker) | topo da serra, ao lado do heliponto | `world/places/BunkerExteriorNative.gd` (caixas lisas, sem textura nenhuma) | `estacao-zero` |
| 2 | **Cume Branco** (chalé de esqui "Summit") | topo, junto ao teleférico | `SummitSkiLodge3D.gd` | `cume-branco` |
| 3 | **Boutique Alpina** | topo, ao lado do Cume Branco | `ResortShop3D.gd` | `boutique-alpina` |
| 4 | **Último Abrigo** (loja de equipamento) | floresta, perto da madeireira | `ResortShop3D.gd` (mesmo modelo da Boutique) | `ultimo-abrigo` |
| 5 | **Ammu-Nation da serra** | estrada da serra | `MountainGunShop3D.gd` | `ammunation-serra` |
| 6 | **Chalé dos Pinhais, Chalé da Encosta, Abrigo dos Lenhadores** e o escritório da madeireira | encosta sul | `LumberjackCabin3D.gd` (cabana de toras pequena) | `cabana-toras` |
| 7 | **Posto Florestal** | encosta sul | `LumberjackCabin3D.gd` | `posto-florestal` |
| 8 | **Terminal da Serra** (versão de 8 m) | vila | 3D (`OriginalVillageArchitecture.gd`); a pintura de 14 m não cabe entre a encosta e o ônibus | `terminal-serra-8m` |

Ficam fora do pacote: o Refúgio da Serra e a forja (estruturas abertas de toras, que o kit de
fachada não monta), os galpões abertos da madeireira e as estações do teleférico.

Depois de gerar: salvar em `output/imagegen/<pasta>/`, medir os vãos de porta em
`tools/painted_facades_serra.json` e importar com
`python -I tools/build_painted_facades.py --styles=<pastas>` (ver `docs/HOW-TO-DEVELOP.md`, §4).

---

## Texto para colar no GPT

```
Você vai gerar PACOTES DE TEXTURAS para prédios de uma vila de montanha com neve, num jogo 3D, usando geração de imagem. Gere uma imagem por vez e SALVE cada uma no disco no caminho indicado. Não pare até terminar todos os prédios da lista.

REGRAS PARA TODAS AS IMAGENS:
- Estilo GTA Vice City / San Andreas: pintado à mão com base em foto, cores levemente saturadas, serra brasileira fria com neve, ar anos 80/90.
- Vista 100% frontal e ortográfica (sem perspectiva, sem ponto de fuga), linhas retas e paralelas.
- Iluminação neutra e uniforme, SEM sombra de sol.
- Só a superfície pedida, preenchendo o quadro de borda a borda. Sem céu, chão, pessoas, carros, árvores, moldura, marca d'água.
- Neve: só onde ela fica numa parede de verdade (peitoris, beirais, topo de muretas e um pouco acumulada na base). Nada de neve caindo.
- Letreiros: só o NOME PRÓPRIO indicado, em letras grandes e legíveis. Nada de palavras genéricas.
- Respeite a proporção (largura x altura) de cada item.
- Dentro de um mesmo prédio, todas as imagens têm o mesmo material, cores e sujeira. Cada versão "noite" é a imagem "dia" com tudo exatamente no mesmo lugar, 1 ou 2 janelas acesas em amarelo quente, letreiro e luminária da porta acesos, paredes escuras e azuladas.
- PORTAS: nunca desenhe a folha da porta na fachada. O vão é um corredor escuro, porque a porta é um objeto 3D que abre. A folha vai em imagem separada.
- TELHADO INCLINADO: a frente e os fundos vão só até o beiral (parede retangular). A empena (triângulo) entra NA IMAGEM DA LATERAL, com o topo em ponta e preto chapado fora do triângulo. O telhado é UMA água, esticada como se fosse plana, telha escura coberta de neve com beiral de neve escorrida; gere também telhado-sem-neve.png.

PACOTE PADRÃO DE CADA PRÉDIO (salve em D:\geteco\game\output\imagegen\<pasta>\):
frente-dia.png, frente-noite.png, lateral-dia.png, lateral-noite.png, fundos-dia.png, fundos-noite.png, telhado.png (+ telhado-sem-neve.png se inclinado), porta-frente.png (só a folha), porta-frente-verso.png, porta-fundos.png, porta-fundos-verso.png.
Lateral e fundos: mesmo material, menos janelas, canos, caixa de luz, lenha ou entulho pintado na base, manchas. Fundos com porta de serviço sem a folha (vão escuro).

LISTA:
1) pasta "estacao-zero" — LAJE PLANA. Frente 14 x 4 m, lateral 7 x 4 m, fundos 14 x 4 m, telhado 14 x 7 m visto de cima.
   Posto militar de comunicações "ESTAÇÃO ZERO" no alto da serra, meio enterrado: concreto aparente cinza-azulado com marcas de fôrma e furos de tirante, escorridos de ferrugem, aterro de terra e neve encostado na base (0,5 m). Platibanda de concreto no topo. Porta blindada de aço NO CENTRO da frente, 1,4 m de largura (vão escuro, folha separada), com moldura de aço e faixa de perigo amarela e preta em cima, luminária de grade sobre a porta. Três seteiras horizontais estreitas (0,6 m de altura) com grade, duas à esquerda e uma à direita da porta. Letreiro "ESTAÇÃO ZERO" em letras de estêncil pintadas no concreto acima da porta. Pilares de reforço a cada 3 m.
   Telhado: laje de concreto com manta remendada, respiros, ralo, cabos e a base de uma antena (sem objetos altos: antena e radar são 3D).
   Lateral: concreto com uma seteira, caixa de energia com cabos indo para o gerador. Fundos: porta de serviço de aço sem a folha, tomadas de ar com grade, manchas de fuligem.
   Porta-frente: folha de aço blindada cinza-chumbo com rebites, visor estreito e volante/manopla. Porta-fundos: chapa de aço pintada verde-oliva descascando.

2) pasta "cume-branco" — TELHADO INCLINADO, cumeeira paralela à frente. Frente 14 x 3,5 m, lateral 8,5 m de largura (parede de 3,5 m + empena até 6 m no meio), fundos 14 x 3,5 m, telhado (uma água) 14 x 5 m.
   Chalé de esqui "CUME BRANCO": toras de madeira cor de mel envernizada sobre embasamento de pedra (0,6 m), janelões de vidro com caixilho escuro dos dois lados da porta, porta dupla de madeira NO CENTRO (vão escuro), marquise de madeira sobre a porta com neve em cima, letreiro "CUME BRANCO" de madeira entalhada acima da marquise, esquis encostados pintados na base. Fundos: porta NO CENTRO para as pistas (vão escuro) com rack de esquis e bastões pintado na parede. Lateral: chaminé de pedra subindo pela empena.

3) pasta "boutique-alpina" — TELHADO INCLINADO, cumeeira paralela à frente. Frente 7 x 3,2 m, lateral 4 m de largura (parede 3,2 m + empena até 4,8 m), fundos 7 x 3,2 m, telhado 7 x 2,6 m.
   Loja de roupas de esqui "Boutique Alpina": lambri de madeira clara pintada de creme, moldura escura, duas vitrines com manequins de proporção humana real vestindo jaquetas de esqui coloridas, porta de vidro NO CENTRO (vão escuro), letreiro "Boutique Alpina" sobre a porta, floreira com pinheirinho na base das vitrines.

4) pasta "ultimo-abrigo" — mesmas medidas da Boutique Alpina.
   Loja de equipamento de montanha "Último Abrigo": tábuas escuras com tinta verde-musgo desbotada, base de pedra, vitrine com mochila, corda, lampião, machado e casacos em manequins de proporção humana real, porta NO CENTRO (vão escuro), placa de madeira "Último Abrigo" pendurada sobre a porta.

5) pasta "ammunation-serra" — TELHADO INCLINADO. Frente 8 x 3,5 m, lateral 4,5 m (parede 3,5 m + empena até 5 m), fundos 8 x 3,5 m, telhado 8 x 3 m.
   Loja de armas de estrada de montanha "AMMU-NATION": tábuas verticais pintadas de verde-escuro, faixa vermelha com o letreiro "AMMU-NATION" e o alvo do logotipo, vitrine gradeada com rifles e caixas de munição, porta gradeada NO CENTRO (vão escuro), cabeça de alce de madeira pintada acima do letreiro, neve no beiral.

6) pasta "cabana-toras" — TELHADO INCLINADO. Frente 4 x 2,8 m, lateral 4,5 m (parede 2,8 m + empena até 4,2 m), fundos 4 x 2,8 m, telhado 4,5 x 2,6 m.
   Cabana de toras roliças escuras de caçador/lenhador, cantos com as pontas das toras cruzadas, base de pedra, uma janelinha de quatro vidros com veneziana, porta NO CENTRO (vão escuro), lenha empilhada e um machado num toco pintados na base de um lado.

7) pasta "posto-florestal" — mesmas medidas da cabana-toras.
   Posto da guarda florestal "POSTO FLORESTAL": tábuas horizontais pintadas de marrom-avermelhado com acabamento creme, placa oficial de madeira "POSTO FLORESTAL" acima da porta, mapa da trilha sob uma pequena cobertura na parede (sem texto pequeno), rádio-antena pintada no canto, porta NO CENTRO (vão escuro).

8) pasta "terminal-serra-8m" — TELHADO INCLINADO. Frente 8 x 5 m, lateral 7,7 m (parede 5 m + empena), fundos 8 x 5 m, telhado 8 x 4 m.
   O mesmo "Terminal da Serra" que já existe (madeira e vidro, marquise com neve, bilheteria), mas compacto, em 8 m de largura: porta NO CENTRO com 1,6 m (vão escuro), bilheteria com guichê à direita, banco e quadro de horários sem texto pequeno à esquerda, letreiro "Terminal da Serra".

Ao terminar, liste os arquivos salvos por pasta e aponte qualquer imagem com perspectiva, sombra, texto errado ou fora da proporção, para gerar de novo.
```

---

## Importação (27/10, noite)

Os 95 PNGs voltaram e os oito estilos estão em `assets/facades/`. Vãos de porta medidos à mão
até o batente e a soleira (a detecção automática parava no miolo escuro) em
`tools/painted_facades_serra.json`, com `margin` 0,004.

As frentes da Estação Zero e do Cume Branco vieram em 2,7:1 em vez de 3,5:1 e 4:1. Não foi
preciso gerar de novo: o kit tira a altura do prédio da proporção da imagem, então a largura do
módulo foi escolhida pelo tamanho da porta, e o prédio fica um pouco mais alto e estreito que o
pedido. Os fundos do Cume Branco (2,5:1) esticam ~9% na horizontal para casar com a frente.

| Estilo | Módulo (m) | Fundo (m) | Porta da frente | Lugares |
|---|---|---|---|---|
| estacao-zero | 11,6 × 4,24 (laje) | 7,4 | 1,4 m | Estação Zero |
| cume-branco | 12,4 × 4,53 | 8,4 | dupla, 1,9 m | Cume Branco (Summit) |
| boutique-alpina | 7,0 × 3,2 | 4,0 | 1,1 m | Boutique Alpina |
| ultimo-abrigo | 7,0 × 3,2 | 4,0 | 1,1 m | Último Abrigo |
| ammunation-serra | 9,0 × 3,94 | 5,0 | 1,2 m | Ammu-Nation da serra |
| cabana-toras | 5,6 × 3,93 | 4,6 | 0,85 m | Chalé dos Pinhais, Chalé da Encosta, Abrigo dos Lenhadores (3 acessos) |
| posto-florestal | 5,4 × 3,78 | 4,6 | 0,9 m | Posto Florestal |
| terminal-serra-8m | 8,0 × 5,0 | 5,0 | 1,4 m | Terminal da Serra |

Ligação: `world/mountain_detail/PaintedMountainPlaces.gd` (tabela `PLACE_STYLES`), terminal em
`OriginalVillageArchitecture.gd`. Os modelos 3D antigos continuam para `GETECO_PAINTED_FACADES=0`.
