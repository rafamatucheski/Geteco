# Kit de prompts: prédio completo em textura (estilo GTA III / Vice City)

Para cada prédio, peça **todas** as peças abaixo, **na mesma conversa**, para manter
o mesmo material, tom e sujeira. Regras que valem para TODAS as imagens:

```
REGRAS FIXAS (cole no começo de cada pedido):
- Textura para jogo 3D, estilo GTA Vice City / San Andreas: pintada à mão com base em foto, cores levemente saturadas e quentes.
- Vista 100% frontal e ortográfica (sem perspectiva, sem ponto de fuga, linhas retas e paralelas).
- Iluminação neutra e uniforme, SEM sombra de sol direcional (o jogo põe a luz).
- A imagem é só a superfície pedida, preenchendo o quadro de borda a borda. Sem céu, chão, pessoas, carros, vegetação, moldura, texto ou marca d'água.
- Proporção exata pedida em cada item (largura x altura em metros).
```

Troque `<ESTILO>` por um dos estilos da lista no fim (ou invente outros) e gere o pacote
inteiro para cada um.

---

## 1. Fachada da frente — dia (6 m x 7 m, proporção 6:7)

```
<REGRAS FIXAS>
Fachada frontal de sobrado urbano, 2 andares, <ESTILO>.
- Andar de cima: 2 janelas guilhotina com moldura de pedra, verga com pedra-chave e peitoril.
- Térreo: 2 janelas iguais à esquerda e, à direita, o VÃO DA PORTA: batente de pedra em arco com bandeira de vidro em leque em cima.
  IMPORTANTE: NÃO desenhe a folha da porta. O vão da porta deve ser um corredor interno escuro (piso de ladrilho e parede escura ao fundo), porque a porta será um objeto 3D separado que abre.
- Cinta de pedra entre os andares, cunhais de pedra nas duas quinas, embasamento de pedra encardido de 0,6 m na base.
- Atrás dos vidros: cortinas de cores diferentes, persianas meio baixadas, reflexo de céu.
- Sujeira escorrida sob os peitoris, base mais encardida, quinas gastas.
```

## 2. Fachada da frente — noite (mesma imagem)

```
Exatamente a mesma imagem anterior, pixel a pixel no mesmo lugar, mas à noite:
2 das 4 janelas acesas com luz amarela quente atravessando a cortina, as outras escuras;
bandeira em leque acesa; corredor da porta com luz fraca; paredes bem mais escuras e azuladas.
```

## 3. Lateral (empena) — dia e noite (8 m x 7 m, proporção 8:7)

```
<REGRAS FIXAS>
Parede lateral (empena) da MESMA casa: mesmo material, mesma cinta entre andares, mesmos cunhais nas duas quinas, mesmo embasamento.
Uma janela pequena por andar perto da borda direita (fundo da casa), mesmo estilo das da frente. Resto da parede lisa, com manchas de umidade, remendos e escorridos.
Depois gere a versão noturna idêntica, com a janela de cima acesa.
```

## 4. Fundos — dia e noite (6 m x 7 m)

```
<REGRAS FIXAS>
Parede dos fundos da MESMA casa, mais simples e mais suja que a frente:
- 2 janelas menores sem pedra-chave, uma porta de serviço estreita SEM a folha (vão escuro, a porta é 3D separada),
- cano de esgoto preso na parede, caixa de ar-condicionado velha, fiação, grade numa janela do térreo.
Versão noturna idêntica com 1 janela acesa.
```

## 5. Telhado (vista de cima) — 6 m x 8 m

```
<REGRAS FIXAS, mas vista de CIMA, ortográfica>
Laje de cobertura plana da MESMA casa vista de cima: manta asfáltica remendada ou cascalho,
ralo, poças secas com manchas, fuligem, platibanda de pedra em volta (0,25 m) vista de cima.
Sem objetos altos (caixa d'água e chaminé são 3D separados).
```
Variante para casa de telhado inclinado:
```
<REGRAS FIXAS>
Água de telhado de telha cerâmica <cor> vista perpendicular à superfície (como se esticada),
6 m x 4,5 m, telhas com variação de tom, musgo nas fiadas de baixo, cumeeira na borda de cima.
```

## 6. Porta da frente (folha) — 1,05 m x 2,25 m, frente E verso

```
<REGRAS FIXAS>
Folha de porta de madeira <cor> com 6 almofadas, só a porta, sem batente e sem parede:
maçaneta de latão, fenda de correio de latão, número da casa, pintura descascando nas bordas de baixo.
Depois gere o VERSO da mesma porta (lado de dentro): mesma madeira e cor, mais limpa, trinco e corrente de segurança.
```

## 7. Porta dos fundos (folha) — 0,9 m x 2,1 m, frente e verso

```
<REGRAS FIXAS>
Porta de serviço de metal pintado <cor>, amassada e enferrujada na base, com visor pequeno e fechadura,
só a folha. Depois o verso.
```

## 8. Peças avulsas (cada uma separada, fundo transparente se possível)

```
<REGRAS FIXAS>
Peças soltas da MESMA casa, uma imagem cada, só a peça:
a) peitoril de pedra visto de frente (1,4 m x 0,15 m)
b) cimalha/cornija do topo vista de frente, faixa contínua repetível na horizontal (2 m x 0,5 m)
c) degrau de pedra da entrada visto de frente e de cima (1,5 m x 0,22 m)
d) toldo de lona listrada visto de frente (2 m x 0,8 m)
```

---

## Estilos para gerar (um pacote completo por estilo)

1. tijolo vermelho-amarronzado com argamassa clara, porta verde-escura
2. reboco creme descascado mostrando tijolo por baixo, porta vinho
3. concreto cinza com marcas de fôrma, porta azul-marinho
4. tijolo amarelo-claro (londrino) com cantaria branca, porta preta brilhante
5. reboco rosa-salmão desbotado de praia (Vice City), porta branca, venezianas de madeira azul-turquesa
6. pastilha cerâmica verde-água anos 60 com caixilhos de alumínio, porta de vidro aramado
7. madeira pintada (lambri horizontal) azul-claro descascando, porta amarela
8. tijolo escuro de fábrica com janelas de aço industriais quadriculadas, porta de aço de correr

## Como entregar

Salve em `output/imagegen/<estilo>/` com estes nomes:
`frente-dia.png`, `frente-noite.png`, `lateral-dia.png`, `lateral-noite.png`,
`fundos-dia.png`, `fundos-noite.png`, `telhado.png`, `porta-frente.png`, `porta-verso.png`,
`porta-fundos.png`, `porta-fundos-verso.png`, `peitoril.png`, `cornija.png`, `degrau.png`, `toldo.png`.
