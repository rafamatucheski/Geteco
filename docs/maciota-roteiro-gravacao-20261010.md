# Roteiro de gravação do Maciota

Atualizado em 10 de outubro de 2026 · Geteco · Português brasileiro

São **38 falas da campanha atual**, **1 mensagem escrita na chegada ao deserto** e **3 falas antigas de compatibilidade**. As falas estão organizadas por cena e progressão, com texto literal, contexto e direção de interpretação. A mensagem do deserto e o material de compatibilidade têm blocos próprios para organizar a gravação.

## Direção vocal

Voz masculina adulta, grave e levemente rouca, com presença de rua e carisma. Maciota é um mecânico experiente: conhece pessoas, carros e atalhos, mantém a calma e usa humor seco. A base é confiança tranquila, acolhimento e articulação clara em português brasileiro, com ritmo de conversa real.

Na ligação inicial, ele é reservado e direto. No terminal e no carro, conduz Dante com segurança. Na oficina, aparecem a gratidão pelo passado e a preocupação com Vicente. Durante os favores, dá instruções claras e cobra responsabilidade. No fim de Harbor, a confiança em Dante já é pessoal. Manter o mesmo personagem e o mesmo timbre em todas essas situações.

Evitar caricatura, voz de vilão, grito constante, excesso de gíria ou leitura de locutor. Não imitar voz, bordões ou interpretação de um ator ou personagem específico. O humor fica nas oportunidades do texto, especialmente no cuidado com a Monaliza; as notícias sobre Vicente e a moradora pedem seriedade.

As indicações de entonação abaixo são direção proposta para a nova gravação. Os blocos **Texto exato** reproduzem as falas atuais sem alterações. Não ler os títulos, as instruções ou os nomes dos arquivos.

## Entrega e tomadas

- Gravar uma fala por WAV, mono, 48 kHz, PCM de 24 ou 16 bits, mantendo o padrão do brief anterior.
- Entregar duas tomadas por fala: **contida**, para conversa natural e discreta; **expressiva**, com intenção e contrastes mais perceptíveis, preservando o timbre e o texto.
- Usar o nome indicado para a tomada contida. Na expressiva, acrescentar `_expressiva` antes de `.wav`.
- Gravar sem música, trânsito, motor, reverberação ou efeito de telefone impresso. Deixar os efeitos para a integração.
- Manter de 100 a 200 ms de silêncio limpo antes e depois, sem cortar consoantes ou respiração necessária. Picos entre −6 e −3 dBFS, sem clipping ou compressão agressiva.
- Não trocar palavras, acrescentar vocativos, risadas faladas ou improvisos. As pausas devem respeitar a pontuação e a intenção, sem virar silêncio longo embutido.

As 38 falas principais correspondem a **76 arquivos em duas tomadas**. A mensagem do deserto acrescenta 2 arquivos se receber locução; as três falas antigas acrescentam 6, se incluídas no lote. O conjunto completo tem 84 arquivos. Os nomes abaixo são nomes de entrega propostos; a associação aos manifestos de áudio é uma etapa posterior.

## Leitura e continuidade

Ler “150” como “cento e cinquenta” e “21h” como “vinte e uma horas”, sem mudar a legenda. Manter a pronúncia de Maciota, Vicente, Harbor, North Pier, Ashbend, Takeshi, Jessica, Monaliza e Ironback consistente entre as tomadas. Usar as pronúncias já adotadas pela produção como referência, sem inventar um sotaque para os nomes estrangeiros.

As pausas e ênfases indicadas são relativas: uma pequena separação de pensamento costuma bastar. A tomada expressiva aumenta a intenção; não exige mais volume. Gravar a fala inteira mesmo quando houver várias frases no mesmo bloco.

## Ligação inicial

### 01 Notícia sobre Vicente

**Arquivo:** `maciota_telefone_01_ptbr.wav`

**Contexto:** Ligação inicial para Dante, ainda em casa.

**Texto exato**

> Seu irmão está em Harbor.

**Entonação e intenção:** Grave, reservado e direto. Entregar a informação como certeza, sem prazer em provocar medo.

**Pausas e ênfases:** Apoiar discretamente “irmão” e “Harbor”. Fechar a frase para baixo e deixar o silêncio para a reação de Dante.

**Fonte:** `runtime/ArrivalDialogue.gd · HOME_CALL`

### 02 Convite para Harbor

**Arquivo:** `maciota_telefone_02_ptbr.wav`

**Contexto:** Dante pergunta quem fala; Maciota conduz a conversa para a viagem.

**Texto exato**

> Se você ainda quer falar com ele, vem. Eu te encontro na chegada.

**Entonação e intenção:** Urgência contida, volume baixo e autoridade tranquila. O convite deve parecer concreto.

**Pausas e ênfases:** Pausa breve depois de “vem”. Dar segurança a “Eu te encontro”, sem transformar a condição inicial em ameaça.

**Fonte:** `runtime/ArrivalDialogue.gd · HOME_CALL`

## Encontro no terminal

### 03 Encontro no terminal

**Arquivo:** `maciota_encontro_01_ptbr.wav`

**Contexto:** Primeira abordagem pessoal de Maciota.

**Texto exato**

> Dante, temos muito que conversar.

**Entonação e intenção:** Reconhecimento e seriedade acolhedora. Falar para alguém próximo.

**Pausas e ênfases:** Pequena pausa depois de “Dante”. Apoiar “muito”, sem alongar dramaticamente.

**Fonte:** `runtime/ArrivalDialogue.gd · MEETING`

### 04 Apresentação

**Arquivo:** `maciota_encontro_02_ptbr.wav`

**Contexto:** Resposta à pergunta de Dante sobre a ligação.

**Texto exato**

> Fui eu. Maciota. Vamos até a minha oficina.

**Entonação e intenção:** Confiante e natural, com leve abertura no sorriso ao dizer o próprio nome.

**Pausas e ênfases:** Respeitar os três períodos: confirmação, nome, convite. Não emendar “Maciota” na frase seguinte.

**Fonte:** `runtime/ArrivalDialogue.gd · MEETING`

### 05 Foto do histórico

**Arquivo:** `maciota_encontro_03_ptbr.wav`

**Contexto:** Dante pergunta como foi reconhecido.

**Texto exato**

> Um contato conseguiu uma foto do teu histórico da polícia. Entra, no carro a gente conversa.

**Entonação e intenção:** Discrição de quem tem contatos e não quer explicar tudo na rua.

**Pausas e ênfases:** Dar clareza a “histórico da polícia”. Pequena mudança para um tom convidativo em “Entra”; terminar sem pressa.

**Fonte:** `runtime/ArrivalDialogue.gd · MEETING`

## Passeio até a oficina

### 06 Porto e oficinas

**Arquivo:** `maciota_passeio_01_ptbr.wav`

**Contexto:** Durante o passeio de carro.

**Texto exato**

> Esse porto vive de carga e oficina. Teu irmão passou por aqui.

**Entonação e intenção:** Conversa casual de quem conhece a cidade. A segunda frase recoloca Vicente no centro.

**Pausas e ênfases:** Ritmo solto na descrição do porto; pausa de pensamento antes de “Teu irmão”.

**Fonte:** `runtime/ArrivalDialogue.gd · TOUR`

### 07 Clientes prejudicados

**Arquivo:** `maciota_passeio_02_ptbr.wav`

**Contexto:** Passeio de carro, primeiras consequências da passagem de Vicente.

**Texto exato**

> Vi o Vicente. Depois começaram a aparecer clientes com carro sumido e conta pra pagar.

**Entonação e intenção:** Mais sério, com preocupação prática. Relatar o que viu sem fazer uma acusação teatral.

**Pausas e ênfases:** Separar “Vi o Vicente” do restante. Apoiar “carro sumido” e “conta pra pagar”, sem cantar a enumeração.

**Fonte:** `runtime/ArrivalDialogue.gd · TOUR`

### 08 Cuidado antes de envolver Dante

**Arquivo:** `maciota_passeio_03_ptbr.wav`

**Contexto:** Passeio, explicação da cautela de Maciota.

**Texto exato**

> Tem gente que conhece o caminho dele. Preciso confirmar umas coisas antes de te colocar no meio.

**Entonação e intenção:** Protetor e prudente, com voz firme. Mostrar responsabilidade pelo que está prestes a propor.

**Pausas e ênfases:** Respirar entre as frases. Ênfase discreta em “confirmar” e “antes”; suavizar o final.

**Fonte:** `runtime/ArrivalDialogue.gd · TOUR`

### 09 Chegada à oficina

**Arquivo:** `maciota_passeio_04_ptbr.wav`

**Contexto:** Fim do passeio.

**Texto exato**

> Minha oficina fica entre esses galpões. Lá a gente conversa com calma.

**Entonação e intenção:** Acolhedor, familiar e seguro. Indicar um lugar conhecido.

**Pausas e ênfases:** Dizer “entre esses galpões” com clareza. Desacelerar levemente em “com calma”.

**Fonte:** `runtime/ArrivalDialogue.gd · TOUR`

## Primeira conversa na oficina

### 10 Entrada na garagem

**Arquivo:** `maciota_oficina_01_ptbr.wav`

**Contexto:** Primeira conversa da campanha dentro da oficina.

**Texto exato**

> Entra, Dante. Vi o Vicente por aqui. Ele deixou muita gente com problema nesta região.

**Entonação e intenção:** Começar receptivo, depois assumir o peso dos problemas deixados por Vicente.

**Pausas e ênfases:** Pausa após “Dante”. A frase final fica mais baixa e séria; evitar tom de fofoca.

**Fonte:** `data/GarageSequence.gd · INTRO_LINES`

### 11 Ainda sem endereço

**Arquivo:** `maciota_oficina_02_ptbr.wav`

**Contexto:** Resposta à pergunta sobre o paradeiro de Vicente.

**Texto exato**

> Ainda não tenho um endereço. Tenho clientes que fizeram serviço pra ele. Vou conversar com essa gente.

**Entonação e intenção:** Honesto e objetivo; admitir o limite sem perder a iniciativa.

**Pausas e ênfases:** Apoiar “Ainda não”. Retomar firmeza em “Vou conversar”, sem prometer um endereço que não tem.

**Fonte:** `data/GarageSequence.gd · INTRO_LINES`

### 12 Carro recuperado no passado

**Arquivo:** `maciota_oficina_03_ptbr.wav`

**Contexto:** Dante pergunta como Maciota conhece os irmãos.

**Texto exato**

> Você recuperou um carro pra mim, anos atrás. Roubaram durante um transporte e disseram que eu tinha feito parte do negócio. Eu quase perdi a oficina.

**Entonação e intenção:** Gratidão misturada à lembrança de uma injustiça. A tensão cresce só no fim.

**Pausas e ênfases:** Separar a lembrança inicial da explicação do roubo. Fazer uma pausa maior antes de “Eu quase perdi a oficina” e baixar o volume.

**Fonte:** `data/GarageSequence.gd · INTRO_LINES`

### 13 O que a oficina significava

**Arquivo:** `maciota_oficina_04_ptbr.wav`

**Contexto:** Dante diz que não se lembra de Maciota.

**Texto exato**

> Imagino. Pra você era trabalho. Pra mim era tudo. Você achou o carro e mostrou que tinham me enganado.

**Entonação e intenção:** Aceitação sem ressentimento, emoção contida e agradecimento sincero.

**Pausas e ênfases:** “Imagino” curto. Preservar o contraste entre “Pra você era trabalho” e “Pra mim era tudo”, com uma pausa entre eles. Não chorar.

**Fonte:** `data/GarageSequence.gd · INTRO_LINES`

### 14 Vicente e os Cobras

**Arquivo:** `maciota_oficina_05_ptbr.wav`

**Contexto:** Dante volta a perguntar sobre Vicente.

**Texto exato**

> Passou pela oficina. Fazia serviço com os Cobras. Depois começou a aparecer em cobrança, carro sumido, corrida que ninguém queria comentar.

**Entonação e intenção:** Cautela crescente, como quem escolhe o que pode afirmar.

**Pausas e ênfases:** Frases iniciais secas. Dar espaço aos itens “cobrança”, “carro sumido” e “corrida”; terminar mais baixo em “comentar”.

**Fonte:** `data/GarageSequence.gd · INTRO_LINES`

### 15 Uma mão lava a outra

**Arquivo:** `maciota_oficina_06_ptbr.wav`

**Contexto:** Maciota estabelece a troca de favores.

**Texto exato**

> Eu quero te ajudar. Mas preciso que você me faça um favor. Uma mão lava a outra nesta cidade.

**Entonação e intenção:** Franqueza e autoridade amigável. Há interesse no acordo, mas também vontade de ajudar.

**Pausas e ênfases:** Pausa depois de “ajudar”. Apoiar “um favor”; dizer a última frase como experiência de vida, sem pose de vilão.

**Fonte:** `data/GarageSequence.gd · INTRO_LINES`

### 16 Primeira orientação

**Arquivo:** `maciota_oficina_07_ptbr.wav`

**Contexto:** Encaminhamento ao banco e ao porto.

**Texto exato**

> Uma peça minha ficou no porto. Primeiro resolve o comprovante com a Helena. Traz a encomenda e eu vou atrás de quem trabalhou com teu irmão.

**Entonação e intenção:** Prático e claro, em ritmo de conversa. O objetivo é que Dante entenda a ordem.

**Pausas e ênfases:** Separar porto, Helena e retorno da encomenda. Ganhar calor na promessa de procurar quem trabalhou com o irmão.

**Fonte:** `data/GarageSequence.gd · INTRO_LINES`

## Primeiro giro

### 17 Comprovante e encomenda

**Arquivo:** `maciota_primeiro_giro_01_ptbr.wav`

**Contexto:** Início de Primeiro giro.

**Texto exato**

> A Helena, do North Pier, liberou o pagamento de uma peça. Busca o comprovante no banco e leva ao porto. A encomenda está no ponto marcado.

**Entonação e intenção:** Instrução de trabalho, segura e organizada.

**Pausas e ênfases:** Pequena pausa depois de “North Pier”. Dar clareza a “comprovante”, “banco” e “porto”; não acelerar o ponto marcado.

**Fonte:** `data/campaign/first-favors-dialogue.json · begin`

### 18 Ferrugem e Helena

**Arquivo:** `maciota_primeiro_giro_02_ptbr.wav`

**Contexto:** Dante pergunta como o favor o aproxima de Vicente.

**Texto exato**

> A peça é para Ferrugem. Teu irmão fazia serviço com ele. Faz essa entrega direito que eu te apresento. E trata bem a Helena: ela segurou as contas da oficina quando ninguém ajudou.

**Entonação e intenção:** Começar explicativo, ficar firme ao pedir uma entrega correta e terminar com respeito por Helena.

**Pausas e ênfases:** Apoiar “Ferrugem” e “te apresento”. Antes de “E trata bem a Helena”, fazer uma pausa; a lembrança da ajuda é pessoal.

**Fonte:** `data/campaign/first-favors-dialogue.json · begin`

### 19 Pagamento acertado

**Arquivo:** `maciota_primeiro_giro_03_ptbr.wav`

**Contexto:** Conclusão das instruções do primeiro favor.

**Texto exato**

> Já está tudo pago. Você não precisa gastar nem roubar nada. Banco, encomenda, depois volta falar comigo. Os 150 são pelo teu trabalho.

**Entonação e intenção:** Tranquilizador e levemente incisivo ao afastar gasto ou roubo.

**Pausas e ênfases:** Separar “Banco, encomenda, depois volta”. Ler “150” como “cento e cinquenta”; dar valor ao trabalho, sem ostentar dinheiro.

**Fonte:** `data/campaign/first-favors-dialogue.json · begin`

### 20 Banco sem atendimento

**Arquivo:** `maciota_primeiro_giro_04_ptbr.wav`

**Contexto:** Alternativa após a confusão impedir a retirada do comprovante.

**Texto exato**

> Sai daí. A transferência já foi feita; vou mandar a segunda via ao pessoal do porto. Retira a peça no ponto marcado e volta. Isso ainda não acabou bem para quem trabalha aí.

**Entonação e intenção:** Começar urgente e firme; depois resolver o problema com clareza. No final, preocupação com os trabalhadores.

**Pausas e ênfases:** “Sai daí” curto, sem grito. Respirar antes da solução. Última frase mais lenta e séria, sem ironia.

**Fonte:** `data/campaign/first-favors-dialogue.json · interact`

### 21 Pagamento do favor

**Arquivo:** `maciota_primeiro_giro_05_ptbr.wav`

**Contexto:** Retorno com peça e comprovante.

**Texto exato**

> Peça e comprovante. Tudo certo. Aqui estão os 150. Você cumpriu o combinado.

**Entonação e intenção:** Satisfação contida, aprovação de quem cumpre acordos.

**Pausas e ênfases:** Primeiras frases curtas, como conferência da entrega. Ler “150” como “cento e cinquenta”. Aquecer “cumpriu o combinado”.

**Fonte:** `data/campaign/first-favors-dialogue.json · finish_dialogue`

### 22 Explicação sobre os Cobras

**Arquivo:** `maciota_primeiro_giro_06_ptbr.wav`

**Contexto:** Dante pergunta sobre cobrança em dobro.

**Texto exato**

> É o bairro dos Cobras. Ferrugem cuida dos carros; outros cuidam de cobrar. Vou avisar que você vai. No quadro está o endereço. Leva a peça e pergunta pelo Vicente.

**Entonação e intenção:** Informativo e cauteloso. Diferenciar as funções sem parecer cúmplice orgulhoso.

**Pausas e ênfases:** Pequena pausa no ponto e vírgula. Tornar “outros cuidam de cobrar” mais sério; voltar à objetividade nas instruções.

**Fonte:** `data/campaign/first-favors-dialogue.json · finish_dialogue`

### 23 Pista para Ferrugem

**Arquivo:** `maciota_primeiro_giro_07_ptbr.wav`

**Contexto:** Pista após Primeiro giro.

**Texto exato**

> A peça está certa. O contato é Ferrugem, na oficina dos Cobras. Ele recebeu teu irmão procurando trabalho. Leva a peça até ele; o serviço já está no quadro.

**Entonação e intenção:** Aprovação profissional e encaminhamento direto.

**Pausas e ênfases:** Apoiar “Ferrugem” e “procurando trabalho”. Pausa curta antes da ordem de entrega; finalizar sem urgência artificial.

**Fonte:** `data/campaign/cobra-dialogue.json · primeiro_giro_clue`

## Contato com os Cobras

### 24 Entrega para Ferrugem

**Arquivo:** `maciota_contato_01_ptbr.wav`

**Contexto:** Início da missão de contato com os Cobras.

**Texto exato**

> Leva a peça que você buscou para Ferrugem, na oficina dos Cobras. Ele falou com teu irmão. Usa a entrega para puxar conversa.

**Entonação e intenção:** Orientação estratégica, discreta e prática.

**Pausas e ênfases:** Destacar destinatário e local. Pausa antes de “Usa a entrega”; dizer isso como um conselho, sem conspirar em sussurros.

**Fonte:** `data/campaign/cobra-dialogue.json · cobra_contact_begin`

### 25 Motorista das corridas

**Arquivo:** `maciota_contato_02_ptbr.wav`

**Contexto:** Pista após o contato com os Cobras.

**Texto exato**

> Ferrugem confirmou: teu irmão perguntou por um motorista da turma das corridas. A prova é tua chance de se aproximar deles. Já pode aceitar no quadro.

**Entonação e intenção:** Uma informação confirmada abre uma possibilidade. Confiança maior, ainda contida.

**Pausas e ênfases:** Apoiar “confirmou” e “tua chance”. Separar a pista da instrução sobre o quadro.

**Fonte:** `data/campaign/cobra-dialogue.json · cobra_contact_clue`

## Prova de rua

### 26 Prova de rua

**Arquivo:** `maciota_prova_rua_01_ptbr.wav`

**Contexto:** Início da corrida noturna até as docas.

**Texto exato**

> Às 21h tem prova até as docas. Vence seguindo os quatro checkpoints e eu consigo falar com o motorista que viu o Vicente. Leva a Monaliza inteira.

**Entonação e intenção:** Energia um pouco maior, confiança e humor seco no cuidado com o carro.

**Pausas e ênfases:** Ler “21h” como “vinte e uma horas”. Articular “quatro checkpoints”. Pausa antes de “Leva a Monaliza inteira”, com sorriso discreto.

**Fonte:** `data/campaign/cobra-dialogue.json · cobra_race_begin`

### 27 Mala reforçada

**Arquivo:** `maciota_prova_rua_02_ptbr.wav`

**Contexto:** Pista e presente depois de vencer Prova de rua.

**Texto exato**

> Mandou bem na corrida, Dante. Separei uma mala reforçada pra tua busca pelo Vicente. Está no porta-malas da Monaliza; pega quando precisar levar mais coisa.

**Entonação e intenção:** Orgulho discreto, cuidado pessoal e generosidade prática.

**Pausas e ênfases:** Sorriso leve em “Mandou bem”. Pausa antes de falar da mala; destacar “porta-malas da Monaliza”, mantendo o final casual.

**Fonte:** `data/campaign/cobra-dialogue.json · cobra_race_clue`

### 28 Moradora em Ashbend

**Arquivo:** `maciota_prova_rua_03_ptbr.wav`

**Contexto:** Continuação da pista após a corrida.

**Texto exato**

> O motorista falou comigo: deixou teu irmão perto da casa de uma moradora em Ashbend. Os Cobras estão cobrando dela. Ajuda a mulher e pergunta o que viu.

**Entonação e intenção:** Informação concreta que se torna preocupação com a moradora.

**Pausas e ênfases:** Respirar depois da localização. Endurecer um pouco “Os Cobras estão cobrando dela”; dar prioridade humana a “Ajuda a mulher”.

**Fonte:** `data/campaign/cobra-dialogue.json · cobra_race_clue`

## Proteção da moradora

### 29 Proteção da moradora

**Arquivo:** `maciota_moradora_01_ptbr.wav`

**Contexto:** Início da missão contra a cobrança dos Cobras.

**Texto exato**

> O motorista deixou teu irmão perto dessa moradora. Protege ela da cobrança dos Cobras; talvez aceite contar o que viu.

**Entonação e intenção:** Sério e protetor. Primeiro a segurança dela, depois a informação.

**Pausas e ênfases:** Apoiar “Protege ela”. O “talvez” deve soar como possibilidade, sem garantir uma resposta.

**Fonte:** `data/campaign/cobra-dialogue.json · cobra_collection_begin`

### 30 Passagem por Jessica

**Arquivo:** `maciota_moradora_02_ptbr.wav`

**Contexto:** Pista após proteger a moradora.

**Texto exato**

> A moradora reconheceu teu irmão e apontou os registros dos Cobras. Antes de entrar lá, conversa com a Jessica junto ao North Pier. Ela quer combinar um serviço e você vai precisar de dinheiro para viajar.

**Entonação e intenção:** Planejamento prudente. Reconhecer o avanço e organizar a próxima etapa.

**Pausas e ênfases:** Separar a descoberta dos registros da orientação sobre Jessica. Dar clareza a “Antes de entrar lá” e “dinheiro para viajar”.

**Fonte:** `data/campaign/cobra-dialogue.json · cobra_collection_clue`

## Serviço com Jessica

### 31 Encontro com Jessica

**Arquivo:** `maciota_jessica_01_ptbr.wav`

**Contexto:** Início do serviço com Jessica.

**Texto exato**

> A Jessica espera na rua do North Pier. Decide com ela como vai ser o serviço. Depois a gente volta aos registros dos Cobras.

**Entonação e intenção:** Delegação tranquila. Maciota encaminha, sem decidir o plano por Dante.

**Pausas e ênfases:** Apoiar “Decide com ela”. Última frase retoma o assunto principal, em tom prático.

**Fonte:** `data/campaign/cobra-dialogue.json · jessica_bank_begin`

### 32 Retomada dos registros

**Arquivo:** `maciota_jessica_02_ptbr.wav`

**Contexto:** Pista após o serviço com Jessica.

**Texto exato**

> Jessica falou que vocês chegaram bem. Agora vamos aos registros. Os papéis que a moradora indicou ficam nos fundos da quadra dos Cobras.

**Entonação e intenção:** Alívio contido por terem chegado bem; retomada firme da investigação.

**Pausas e ênfases:** Pausa depois da primeira frase. “Agora vamos aos registros” com foco renovado; localização final bem articulada.

**Fonte:** `data/campaign/cobra-dialogue.json · jessica_bank_clue`

## Registros dos Cobras

### 33 Papéis e abastecimento

**Arquivo:** `maciota_registros_01_ptbr.wav`

**Contexto:** Início da missão dos registros.

**Texto exato**

> Teu irmão procurava os mesmos registros. A moradora apontou os fundos da quadra. Recupera os papéis e corta o abastecimento dos cobradores.

**Entonação e intenção:** Objetivo e firme, transmitindo um plano já definido.

**Pausas e ênfases:** Dividir as três frases em unidades claras. Apoiar “Recupera os papéis” e “corta o abastecimento”, sem grito de combate.

**Fonte:** `data/campaign/cobra-dialogue.json · cobra_supply_begin`

### 34 Disputa com Takeshi

**Arquivo:** `maciota_registros_02_ptbr.wav`

**Contexto:** Pista após recuperar os registros dos Cobras.

**Texto exato**

> Takeshi guarda a lista completa na casa dele. Ele não vai abrir a porta por conversa. Consegui uma disputa: vence a corrida e ele libera os registros.

**Entonação e intenção:** Certeza de quem conseguiu uma oportunidade difícil.

**Pausas e ênfases:** Apoiar “lista completa” e “casa dele”. Pausa antes de “Consegui uma disputa”; a condição final deve ficar muito clara.

**Fonte:** `data/campaign/cobra-dialogue.json · cobra_supply_clue`

## Disputa com Takeshi

### 35 Desafio final de Takeshi

**Arquivo:** `maciota_takeshi_01_ptbr.wav`

**Contexto:** Início da corrida pelo acesso à casa.

**Texto exato**

> Takeshi aposta que você não ganha dele até as docas. O acesso aos registros é o prêmio. Vence e entra na casa dele; procura a lista de responsáveis pelas corridas.

**Entonação e intenção:** Provocação leve na aposta; depois concentração no objetivo real.

**Pausas e ênfases:** Sorriso mínimo em “não ganha dele”. Dar peso a “registros” e separar vitória, entrada na casa e busca pela lista.

**Fonte:** `data/campaign/cobra-dialogue.json · cobra_finale_begin`

### 36 Contato no deserto

**Arquivo:** `maciota_takeshi_02_ptbr.wav`

**Contexto:** Pista após o desfecho com Takeshi.

**Texto exato**

> Vicente está organizando corridas fora de Harbor. Vou te passar um contato e um lugar para ficar no deserto. Você não vai chegar sozinho.

**Entonação e intenção:** Esperança concreta e compromisso de apoio.

**Pausas e ênfases:** Primeira frase factual. Aquecer a segunda e desacelerar “Você não vai chegar sozinho”, sem grandiosidade.

**Fonte:** `data/campaign/cobra-dialogue.json · cobra_finale_clue`

## Epílogo de Harbor

### 37 Rumo ao deserto

**Arquivo:** `maciota_epilogo_01_ptbr.wav`

**Contexto:** Telefonema do epílogo, depois de Dante relatar a lista.

**Texto exato**

> Então é pra lá que vamos. Vou te passar um contato e um lugar pra ficar. Não chega apostando o que é teu.

**Entonação e intenção:** Decisão compartilhada, apoio concreto e conselho de alguém experiente.

**Pausas e ênfases:** Pausa após “vamos”. A advertência sobre apostas fica mais firme, sem sermão nem ameaça.

**Fonte:** `runtime/MissionWorld.gd · _update_aftermath`

### 38 Confiança conquistada

**Arquivo:** `maciota_epilogo_02_ptbr.wav`

**Contexto:** Dante diz que precisa falar com o irmão; Maciota menciona o Ironback.

**Texto exato**

> Eu sei. O Ironback está na oficina. Você conquistou minha confiança, Dante.

**Entonação e intenção:** Empatia breve, seguida de reconhecimento pessoal.

**Pausas e ênfases:** “Eu sei” baixo e próximo. Separar a informação do carro da última frase; apoiar “confiança” e terminar “Dante” com calor.

**Fonte:** `runtime/MissionWorld.gd · _update_aftermath`

## Mensagem na chegada ao deserto

Esta ocorrência é exibida por `show_message` como texto de interface, não como uma fala no painel de diálogo. O texto completo é preservado abaixo. A orientação vocal só se aplica se a produção decidir gravá-la; o prefixo “Maciota:” identifica o remetente e não deve ser locutado.

### 39 Quarto no Horizonte

**Arquivo:** `maciota_deserto_01_ptbr.wav`

**Contexto:** Mensagem exibida na primeira chegada ao exterior do deserto.

**Texto exato**

> Maciota: deixei um quarto no Horizonte. Vicente está com a turma dele no encontro da arrancada.

**Entonação e intenção:** Para eventual locução: acolhimento prático, seguido de uma pista importante.

**Pausas e ênfases:** Não ler o prefixo de identificação “Maciota:”. Pausa após “Horizonte”; destacar “Vicente” e “encontro da arrancada”.

**Fonte:** `runtime/desert/DesertCampaign.gd · primeira chegada ao deserto`

## Falas antigas de compatibilidade

Estas três falas continuam em `GarageSequence.gd` e no fluxo antigo de `Progression.gd`. A campanha nova usa a conversa de introdução da oficina. Não inserir estas falas no lugar dela; reservar as tomadas para compatibilidade, conforme o uso do fluxo antigo.

### 40 Saudação antiga

**Arquivo:** `maciota_legado_01_ptbr.wav`

**Contexto:** Sequência antiga da peça na bancada, preservada nos dados de compatibilidade.

**Texto exato**

> Olha só quem resolveu dar as caras na minha humilde garagem... Dante, meu consagrado. Sentiu o cheiro do dinheiro ou foi o meu perfume francês?

**Entonação e intenção:** Carisma, intimidade e humor seco mais visível que na campanha atual.

**Pausas e ênfases:** Usar a reticência como preparação da brincadeira. Sorriso em “meu consagrado” e na pergunta sobre perfume, sem caricatura.

**Fonte:** `data/GarageSequence.gd · GREETING`

### 41 Pedido antigo da peça

**Arquivo:** `maciota_legado_02_ptbr.wav`

**Contexto:** Orientação da sequência antiga da bancada.

**Texto exato**

> Fala com o mecânico. Ele separou uma peça pra mim.

**Entonação e intenção:** Cotidiano, breve e objetivo.

**Pausas e ênfases:** Pausa natural entre as duas frases. Destacar “mecânico” e “peça”, sem tratar como uma missão perigosa.

**Fonte:** `data/GarageSequence.gd · REQUEST`

### 42 Agradecimento antigo

**Arquivo:** `maciota_legado_03_ptbr.wav`

**Contexto:** Conclusão ou repetição da sequência antiga da peça.

**Texto exato**

> É isso, Dante. Serviço feito. Depois a gente conversa sobre os próximos.

**Entonação e intenção:** Aprovação simples, com abertura para outros trabalhos.

**Pausas e ênfases:** Pequena pausa após “Dante”. Dar fechamento a “Serviço feito” e deixar a última frase casual.

**Fonte:** `data/GarageSequence.gd · THANKS`

## Conferência para a gravação

Antes de entregar, conferir se cada tomada contém o texto integral, se os nomes próprios permanecem consistentes, se há silêncio limpo nas extremidades e se nenhuma consoante foi cortada. Ouvir a sequência de cada cena para manter timbre, distância do microfone e intensidade coerentes. A aprovação final da interpretação deve ocorrer em contexto, com as respostas de Dante e o ambiente do jogo.

## Referências de conteúdo

- Formato e direção vocal anteriores: `D:/geteco/_arquivo_v1_local/audio/mission_voices/maciota-human-recording-brief.md` e `piloto-maciota.md`, na mesma pasta.
- Ligação ativa: `runtime/OpeningPresentation.gd` seleciona `cutscenes/opening/home/HomeCall.gd`, que usa `HOME_CALL` de `runtime/ArrivalDialogue.gd`.
- Encontro e passeio: `runtime/Arrival.gd` e `runtime/ArrivalDialogue.gd`.
- Introdução e compatibilidade: `data/GarageSequence.gd`, `systems/Progression.gd` e `runtime/FullSession.gd`.
- Favores e pistas: `data/campaign/first-favors-dialogue.json`, `data/campaign/cobra-dialogue.json`, `systems/campaign/OriginalDialogue.gd` e `runtime/MissionWorld.gd`.
- Mensagem do deserto: `runtime/desert/DesertCampaign.gd`.

As antigas falas do piloto da V1 e os textos da versão do filme no ferry não substituem a ligação e o encontro ativos desta edição. O roteiro principal inclui as falas de abertura identificadas como “VOZ AO TELEFONE”, porque a ligação é de Maciota, identidade confirmada no encontro.

