# Android 0.3.3 — 12/10/2026

APK de teste ARM64 gerado, pacote `com.geteco.harbor`, código 303.
Godot 4.7.2 .NET com templates oficiais mono; desktop .NET 10 e Android .NET 9.
O conjunto inclui todas as fontes, assets, testes e documentos locais do jogo,
incluindo o trabalho das sessões anteriores. APKs, chaves, caches, capturas e
cópias temporárias de `output/` e `tmp/` permanecem no disco fora do Git.

## Controles e correções desta preparação

- Pular agora possui botão de toque, separado da mira, ataque e movimento.
  RAGE e trabalho de motorista estão nas opções; o biarticulado tem comando
  de portas. O fluxo completo de linha, embarque, portas e pagamento foi
  exercitado novamente com eventos reais de toque.
- Inventário traduz também as instruções e o botão de soltar bagagem no toque.
- Caminhão do porto: Ação dentro do veículo parado na vaga inicia o carregamento;
  entrega explícita fora do veículo paga R$ 300 uma vez. A restauração diferencia
  carga ainda suspensa de carga já montada, e sair da vaga reinicia o guindaste.
- Frenagem da arrancada encerra o som de pneu no mesmo passo em que a roda
  recupera aderência, preservando derrapagem lateral e burnout.
- A saída de Último Abrigo retorna 1,5 m mais adiante no mesmo acesso para
  liberar a cápsula do aquecedor externo, mantendo portas, câmera e controles.

## Validação funcional

**44 testes distintos selecionados passaram em sua execução final.**
Compilação C# desktop sem erros ou avisos. Não houve execução da suíte inteira
nem certificação de todas as combinações do jogo.

| Cobertura | Evidência exercitada |
| --- | --- |
| Toque e interface | 69 verificações de controles; salto real, multitouch, pedais, rádio, redimensionamento, menus e garagem; configurações, câmera, controle e inventário |
| Ônibus | Trabalho completo com passageiros, portas, movimento e pagamento; repetido por toque |
| Porto | Carregamento do caminhão controlado, entrega e prevenção de pagamento duplicado; estrutura da rota até o depósito |
| Montanha | Investigação autorada, corrida contra seis adversários e jipe por checkpoints; progressão e integração |
| Deserto | Arrancada normal e livre, fila, corrida física, retorno, cancelamento; correção de áudio e burnout |
| Interiores | 19 acessos registrados; ida e volta em oito acessos representativos, incluindo retorno original de salas compartilhadas; garagem e restrições de armas |
| Persistência | Save completo, armazenamento sintético isolado, recompensas consumidas, garagem, residências, campanha e progressão da ponte |
| Sistemas adicionados | Vozes dirigidas, localização, frota remodelada, pesca, esgoto, parque, arcade e remoção de atores entre áreas |

Relatórios completos, logs de falhas anteriores e metadados ficam em
`evidence/test-suite/`, nos cinco lotes iniciados em UTC 16:04:15, 16:18:14,
16:24:50, 16:45:53 e 16:55:11 de 12/10/2026. A lista consolidada será guardada
em `evidence/android-033/functional-tests.json`.

Falhas anteriores foram preservadas: expectativas fixas em português diante da
interface em inglês; fixture de queda sem o nó Gameplay na árvore; aviso de
material do renderer dummy em testes de malhas; percurso de porta baseado na
direção antiga da câmera; retorno próximo do aquecedor; som de freio mantido
entre sondagens. Foram corrigidos os cenários inadequados ou a causa no produto,
sem remover assertions ou mascarar erros do runner.

## Layouts e pacote

Capturas reais em `evidence/android-033/layout/`: 1170×540, 540×1170, 900×840 e
840×900, a pé e dirigindo, com opções abertas e fechadas, total de 16 imagens.
Os layouts não substituem sensores e dobrar/desdobrar no Android.

`tools/validate_android_package.py` confere o APK efetivo: integridade ZIP,
runtime ARM64/.NET, remapeamentos dos imports, catálogos idênticos às fontes,
vozes referenciadas, modelos da frota, scripts adicionados e exclusão de arquivos
de desenvolvimento. **4.305 verificações passaram**, incluindo 34 catálogos
e 206 takes dirigidos. `apksigner` verificou assinaturas v2/v3; o certificado
SHA-256 coincide com o APK 0.3.2. `aapt2` confirmou versão, pacote,
orientação `fullUser` e atividade redimensionável. O `aapt` antigo não interpretou
um atributo Vulkan do manifesto; `aapt2` leu o mesmo manifesto com saída zero.

Arquivo: `builds/android/harbor-0.3.3-debug.apk`, **452.036.648 bytes (431,10 MiB)**.
SHA-256: `55f87746c67ccf7946c0d2bf65dda8e526ca5628f7b63dac01f4f99d22c2ce45`.
O checksum também está ao lado do APK. Evidências: `package.json`, `signature.log`,
`manifest.log` e `export.log` em `evidence/android-033/`.

A exportação concluiu a publicação C# Android e a verificação do APK.
O encerramento informou ausência de ícone próprio e avisos de recursos do
renderer dummy e EditorSettings/ADB. Esses avisos foram preservados no log;
a integridade e assinatura foram comprovadas independentemente. Não se trata
de teste de gameplay no Android. O exportador permaneceu vivo no encerramento;
somente esse processo foi encerrado após a verificação independente do APK.
O editor do usuário foi preservado. O wrapper registrou saída interrompida;
isso não foi convertido em aprovação de gameplay nem ocultado no resultado.

## Limites

Não há aparelho conectado por ADB. Instalação, recortes físicos, retorno do app
ao primeiro plano e dobrar/desdobrar no Fold não foram validados no dispositivo.
Performance ficou explicitamente a cargo do usuário; nenhuma aprovação de FPS
Android ou de regressão é feita nesta entrega. A verificação de presença das
vozes não aprova subjetivamente atuação ou mixagem.

O teste antigo de frete com caminhão autônomo falhou no início do atendimento;
o fluxo de carga controlado pelo jogador e a rota foram validados, mas o ciclo
autônomo completo não foi certificado novamente. Algumas integrações usam
checkpoints e posicionamento inicial de fixtures: não comprovam percorrer todos
os acessos entre cidades ou toda a campanha a partir de um novo jogo.
