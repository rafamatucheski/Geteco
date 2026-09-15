# Revisão do ferro-velho do Neco

O pátio do Harbor fica em `(-750, 550)`, junto ao terreno da Memorial North. O gramado encontra o distrito a leste e o terreno da Memorial ao sul; o acesso sai de `(-1250, 1250)`. Muros visíveis e sólidos fecham as bordas externas voltadas para o mar. Saves no antigo pátio isolado retomam no acesso novo.

As carcaças, contêineres, recepção, motores, barris, pneus, sucata, torre do guindaste e prensa produzem polígonos de colisão a partir dos próprios modelos, incluindo rotação e altura projetada. Isso impede veículos e pedestres de atravessar os objetos ou ocupar visualmente seus tetos. A cerca usa os mesmos extremos da geometria, com um único portão de veículos ao sul.

O jogo simula deslocamento em 2D: a geodata dos modelos 3D alimenta `StaticBody2D` e `CollisionPolygon2D`. A lança e o ímã suspensos têm uma camada de apresentação acima dos veículos, compartilhando o mesmo mundo e animação 3D. Não são paredes invisíveis sobre a baia de entrega.

Neco tem câmera oblíqua e figurino próprio: avental, alças, boné escuro, óculos de proteção, bigode grisalho, luvas, botas e chave de oficina. Seu corpo tem colisão e o caminho até o atendimento permanece livre.

A entrada e o minimapa usam o mesmo pictograma de carro sob a prensa. A revisão posterior removeu as placas NECO/ENTREGA/PRENSA e a faixa de instruções: a baia tem um contorno luminoso pulsante. Ao estacionar, aparece apenas a tecla configurada para sair; a pé, junto do carro, a tecla de interação entrega diretamente à prensa. Ao lado de Neco, a interação continua abrindo as encomendas. O pagamento continua ocorrendo somente após esmagar o veículo, e a Monaliza permanece protegida. A cota fica na conversa; o HUD mostra somente uma encomenda ativa.

## Verificação

`tests/test_salvage_geometry.gd` amplia o teste de entrega existente com varreduras físicas de um carro de 78 × 38 px nas laterais, fundo e frente; entrada pelo portão; colisão sobre a geometria visível; caminho a pé da baia até Neco; conexão do terreno e migração do save antigo. Os testes usam APPDATA isolado.

Evidências em `D:/geteco/artifacts/neco-fix-0910/`: imagens do pátio, detalhe de Neco, conexão com a rua e todas as fases da entrega, além dos logs de execução. `final.log` registra 78 verificações aprovadas, incluindo save/load real; `geometry.log` registra 68 verificações aprovadas sem renderização; `legacy-final.log` registra 66 verificações aprovadas no mapa legado; `overhead.log` registra 68 verificações aprovadas com a camada suspensa do guindaste em Vulkan.

Os scripts de diagnóstico registram avisos preexistentes de interpolação de câmera e encerramento do mundo. As alterações desta revisão estão em `ChopShopZone.gd`, `ui/HarborMinimap.gd` e `world/shared/salvage/{SalvageLocation,SalvageYard3D,SalvageSign,Neco}.gd`.
