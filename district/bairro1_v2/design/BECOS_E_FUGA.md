# Bairro 1 V2 — becos, visão e perseguição

Os becos são parte do loop principal de fuga. Não são uma rua estreita nem
meramente um lugar para props.

## Regra de experiência

O jogador pode escapar de um carro e quebrar a visão de quem o segue entrando
em um beco. Isso não apaga a perseguição instantaneamente:

1. veículo não entra no beco;
2. parede, marquise, casa, muro, escada ou vegetação alta bloqueia a linha de
   visão de verdade;
3. o perseguidor precisa ficar sem visão direta por três segundos, com distância
   de pelo menos 180 pixels;
4. então ele muda de **perseguição** para **busca** por 12 segundos, investigando
   entradas e saídas próximas;
5. um beco sem saída pode virar armadilha, especialmente na Cobra área.

## Becos necessários

| Beco | Conecta | Decisão de gameplay |
| --- | --- | --- |
| Mercado | Mercado ↔ centro | primeiro atalho seguro e ensinamento do sistema |
| Residencial | casas ↔ terminal/estacionamento | três saídas; melhor fuga curta a pé |
| Cobra | Cobra ↔ casas ↔ Paint & Spray | rota rápida, mas gangue pode vigiar/emboscar |
| Cemitério | IML/cemitério ↔ saída leste | muro, árvores e manutenção; fuga silenciosa |
| Favela | favela ↔ Cobra ↔ Paint & Spray | labirinto pedestre com esconderijos e encontros |

## Responsabilidades

- **Claude:** coloca os corredores no layout, largura de 52–76 px, ao menos
  duas saídas onde a tabela manda; sem rota de carro e sem colisões fechando a
  passagem.
- **Antigravity:** usa geometria opaca para visão (paredes, muros, fachadas,
  marquises); props e vegetação não podem fechar o corredor. Cria leitura clara
  de entrada/saída, mas sem placas técnicas flutuantes.
- **Codex:** implementa detecção de linha de visão, última posição vista,
  estados perseguição/busca/perdido e testes de fuga. Não haverá teleporte ou
  “perdeu a polícia” apenas por cruzar um trigger.

Nenhum prédio começa a ser reposicionado até a nova planta baseada no desenho
do Rafael receber estes cinco corredores e os lotes correspondentes.
