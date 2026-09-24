# Proteções costeiras do v2 — 22/09/2026

## Auditoria e escopo

Harbor tinha piso recortado e mar sem colisão, mas não uma proteção contínua nas bordas de seus terrenos. Northstar e Santa Mare já tinham guarda-corpos. A conexão Harbor–Mountain tinha um vão de 12,5 m entre o guarda-corpo de aproximação e o da ponte; o acostamento após o tabuleiro também não tinha a continuação da proteção. Na travessia de Foundry Avenue, o material visual da calçada avançava além do colisor do asfalto sobre o canal.

Na montanha, NativeLake mantém fundo transitável e água rasa, conforme o contrato existente. Os caminhos de exploração, pedras de travessia, acampamento e acesso ao avião não foram cercados. Esta entrega protege as bordas costeiras de queda de Harbor e a ponte de conexão; não introduz natação, afogamento ou fechamento arbitrário de todas as margens dos lagos. Não altera terrenos/interiores da montanha.

## Implementação

`CoastalProtection.gd` calcula as bordas expostas dos terrenos, cais, passarelas, navios e superfícies viárias autoradas. Divide os segmentos em interseções reais antes de excluir bordas interiores, evitando fechar passagens por amostragem grosseira. Os perímetros dos navios com guarda-corpos existentes são preservados. As novas barreiras ficam recuadas 0,24 m para o lado seco, têm colisão contínua de 1,15 m de altura e são divididas por células de carregamento de 64 m.

Tipos por ambiente:

- Urbano: mureta de alvenaria com coroamento e corrimão escuro.
- Cais, passarelas e canal: rodapé de concreto com guarda-corpo metálico aberto.
- Estrada: defensa de concreto com perfil metálico superior.
- Margens residenciais externas e áreas verdes: muro de pedra com coroamento irregular.

Geometria estática agrupada em MultiMeshes por material/célula; um corpo estático com formas simples por célula. Não há callbacks por frame, luzes novas ou SubViewports. Os recursos descarregam com o chunk. A configuração integrada à nova ponte Foundry identifica **132 segmentos novos em 48 células possíveis**, que não ficam todas carregadas simultaneamente.

Calçadas viárias expostas à água ganharam suporte físico correspondente às superfícies já visíveis. O guarda-corpo da ponte agora começa na junção real e continua até a entrada do túnel. O guarda-corpo antigo da popa de Northstar foi dividido no vão da passarela sul, mantendo os dois lados protegidos.

## Validação

`tests/test_coastal_protection.gd`: **448 verificações, zero falhas**. Inclui varredura dos corpos reais de jogador, NPC e carro contra todos os segmentos novos, exigindo contato com o corpo de proteção costeira; apoio da calçada sobre o canal; passagem de cápsula inteira nas conexões principais; pontos de entrada e retorno de Harbor; ambos os lados da lacuna da ponte; passagem pela popa na geometria real de Northstar. Em cantos côncavos curtos, contatos iniciais de recuperação do carro contra a barreira adjacente contam como bloqueio e são explicitamente identificados pelo colisor.

Na primeira execução, a face do novo apoio estava invertida e foi corrigida. O teste inicial também usava uma pose de carro perpendicular que não cabia na passarela estreita; a fixture final usa o casco paralelo e considera os contatos reais nos cantos, sem excluir nenhum segmento. Os avisos de log de usuário/certificados do headless são restrições do ambiente; a saída de verificações acima é funcional, não medição de GPU.

`tests/capture/capture_coastal_protection.gd`: captura Main.tscn com população solicitada 24, resolução 1280×720, Mobile/Vulkan e RTX 4060 Laptop. Fotos de urbano, industrial, pedra, estrada, ponte e profundidade urbana em `evidence/coast-protection-*.png`. Os cenários iniciais renderizaram sem erros de script ou shader. A primeira posição escolhida para a estrada expôs sobreposição preexistente de terreno da montanha sobre Harbor; a captura de revisão usa o acesso à ponte, onde o corredor de água é autorado. Esse problema de terreno em outra célula não foi alterado nem aprovado nesta tarefa.

**Performance pendente**, mantendo o pedido do usuário de não executar a medição. É necessário comparar carregamento/streaming e frame times antes/depois na cena real; os testes físicos e as imagens não aprovam FPS. O cálculo das bordas, os novos colisores e as malhas têm custo adicional ainda não medido. Preservam-se o alvo provisório de 60 FPS e o critério de investigar aumentos acima de 5% em p95/p99 quando a janela de medição estiver disponível.

## Bloqueio de integração concorrente — estado final desta rodada

Outra sessão introduziu `world/urban_detail/HarborBridge3D.gd` durante a validação. O erro transitório de inferência de tipo registrado na captura adicional foi corrigido pela outra sessão; entretanto, o apoio EastAbutment está em `Vector3(x+1.05,.65,0)` com altura 1,3 m, bloqueando a pista de y=0 até y=1,3.

As proteções próprias passaram a respeitar os guarda-corpos dessa nova ponte, eliminando a duplicação. O teste passou a instanciar a ponte nova real. **Resultado integrado: 443 verificações, 440 aprovadas e 3 falhas**, todas no mesmo apoio: raycast da passagem, cápsula do jogador e casco do veículo. A colisão foi localizada em `(273.675, 0.7, 25)` no corpo BridgeStructureSolids. As 448 verificações anteriores registram a versão anterior à integração concorrente, não aprovação do estado atual.

Correção proposta, ainda NÃO aplicada: baixar somente o centro de EastAbutment de y=+0,65 para y=-0,65, mantendo dimensões, material e colisão, para que o topo do apoio fique em y=0. A revisão automática rejeitou essa edição por se tratar de arquivo alterado por outra sessão e pela regra explícita do usuário contra sobrescrita concorrente. O arquivo dessa sessão foi preservado. A entrega integrada permanece bloqueada até autorização/correção e nova validação dirigida. As capturas adicionais highway/urban-depth tiveram erro de compilação durante a execução e não substituem uma captura limpa do estado integrado.
