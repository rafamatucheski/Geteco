# Quinta leva — correções diretas

Escopo reduzido conforme o pedido: coordenador + um agente, sem suíte extensa, benchmark ou rodada de capturas. O usuário fará a validação jogando. Nenhum arquivo reservado ao Claude foi editado.

- **Streaming de veículos:** carros estacionados próximos agora conservam o piso mesmo na borda das células. Carros distantes comuns são parados e removidos antes de liberar o piso, eliminando a janela de até 0,25 s em que caíam. A seleção do jogador mantém suporte mesmo com metadado residual de trânsito. Arquivo: `runtime/ProductionWorld.gd`.
- **Bombeiros:** baia central tem passagem física e porta móvel por proximidade, com zoom de entrada/saída e retorno alinhado à porta. O bloco sólido atrás das portas decorativas foi recortado apenas nesse acesso. Reutiliza o fluxo existente. Arquivos: `runtime/WeaponShopEntrance.gd`, `world/urban_detail/UrbanServiceBuilding.gd`, `world/regions/NativeRegion.gd`, `world/places/PlaceCatalog.gd`.
- **Garagem do Chefe:** as três luminárias existentes foram distribuídas pelo piso útil, com ajuste moderado de alcance/intensidade. Antes estavam concentradas no fundo e não alcançavam a entrada à noite. Sem novas fontes, sombras ou alteração dos sólidos. Arquivo: `assets/regions/source/world/harbor/PortBossGarageArt.gd`.

Checagens mínimas executadas:

- Teste existente do carro anterior, ampliado com uma verificação de altura física: **10/10**, incluindo preservação de ID/saúde/equipamento. Antes já havia uma proteção do snapshot; agora o corpo também não cai antes da remoção.
- Smoke dos bombeiros no teste existente de acessos: **14/14**, porta fechada/aberta com corpo varrido, caminhada, zoom, spawn, saída e retorno sem reentrada involuntária.
- Parse da arte da garagem do Chefe: exit 0. O sandbox impediu a gravação do log solicitado, sem erro de script.

A queda original de 02:21 ainda não foi reproduzida: a correção trata a falha de streaming demonstrada, não comprova identidade com aquele incidente. Banco/Maciota não receberam novo patch; seus problemas já corrigidos nas levas anteriores foram preservados. O custo restante das explosões continua sem nova atribuição causal, portanto não recebeu alteração especulativa nesta leva.

**Para o usuário conferir:** entrar/sair dos bombeiros; trocar de carro, afastar-se e voltar; olhar a garagem do Chefe entre 1h e 5h. Visual, oclusão e FPS ficam pendentes dessa validação, sem aprovação automática por testes headless.

Contagem atual: **10 acessos automáticos/10 interiores**, restam **22 acessos/20 interiores**. Nenhuma nova certificação integral. Sem commits e sem descarte do trabalho concorrente.
