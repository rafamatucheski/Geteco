# Terrain3D: experiência local na montanha

Instalado Terrain3D **1.0.2**, licença MIT, mantendo o pacote oficial em
`addons/terrain_3d` e sua entrada em `project.godot`.

- Origem: https://github.com/TokisanGames/Terrain3D/releases/tag/v1.0.2-stable
- ZIP: `Terrain3D_v1.0.2-stable.zip`
- SHA-256: `A071850250EC5E596AA54DA61C01D75768774EB379EE997584D426A45F4884A2`
- Ambiente: Godot 4.7.2 .NET, Vulkan Mobile, RTX 4060 Laptop, 1280 × 720.

## Comparar no jogo

Na raiz do projeto:

```powershell
.\CompararTerreno.cmd Antes
.\CompararTerreno.cmd Depois
```

Feche uma comparação antes de abrir a outra. O atalho compila C#, prepara os
recursos e abre uma sessão jogável em `(746, 0.08, -434)`, perto do Terminal da
Serra. Cada execução cria seu próprio checkpoint em `evidence/terrain3d-mountain`;
os slots pessoais não são usados. O modo Depois também é o padrão no jogo normal.
`--terrain3d-baseline` mantém o chão anterior durante toda aquela execução.

## Mudança e limite da experiência

Um único trecho de 64 × 64 m: X `[704,768]`, Z `[-448,-384]`.
Aparece uma pequena mancha de rocha entre a neve, centrada em `(740,-430)`,
com raios de 7 × 3,5 m e transição irregular suave que termina antes das bordas.
Alturas, estradas, acessos, colisões e progressão foram
preservados. Não há nova iluminação, vegetação, texto no cenário ou lógica por frame.

O trecho usa uma **malha exportada pelo Terrain3D**, com material adaptado à
paleta existente. É uma experiência visual estática; não é aprovação do Terrain3D
dinâmico, de seu LOD ou de sua física no Geteco.

O nó nativo ao vivo passou no teste isolado, mas provocou dois crashes reproduzidos
na sessão completa durante o carregamento. Windows registrou `0xc0000374`
(corrupção de heap), e o dump contém endereços da DLL do addon na pilha. A mesma
sessão com `--terrain3d-baseline` completou o carregamento e a medição. A causa
exata dentro da extensão/motor não foi resolvida; não se presume compatibilidade
integral com 4.7.2. **O jogo final não instancia esse nó.** A instalação do plugin
permanece para uso e investigação no editor, cuja estabilidade prolongada não foi
certificada.

`tools/terrain3d/bake_mountain.gd` lê a região produtiva `EditableRegion`, incluindo
as alterações do editor, importa as alturas atuais no Terrain3D e usa
`bake_mesh(0, HEIGHT_FILTER_NEAREST)`. A exportação é recortada ao trecho; as
diagonais são alinhadas à colisão original. A malha resultante tem 8.192 triângulos
e fica em `world/regions/terrain3d_pilot/terminal_mesh.res` (aprox. 149 KiB).
Não depende de Terrain3D instanciado para renderizar.

O encaixe é verificado contra os 289 vértices originais antes de aplicar a malha.
Se uma futura edição de estrada/relevo invalidar esse encaixe, o jogo mantém o
terreno original e informa que a exportação precisa ser refeita.

## Validação

- Compilação `dotnet build Harbor.csproj --no-restore`: passou, sem avisos/erros.
- Importação do addon: concluiu, sem erro de parse; houve avisos de recursos no
  encerramento do editor headless. O nó nativo emite também aviso de API obsoleta.
- `tests/test_terrain3d_mountain_pilot.gd`: **17 checks aprovados**, incluindo
  proveniência da exportação, limite espacial, vértices e centros de todas as
  faces, raios físicos nas bordas, vizinho preservado, descarregamento/retorno e
  caminhada do controlador real de Dante e NPC por ambas as bordas.
- Maior erro de altura: vértices **0,000047 m**, centros de faces **0,000035 m**.
- Crash nativo: logs `after.log`, `after2.log`; não repetir o mesmo ensaio sem
  alteração fundamentada de versão, compilação ou integração.

Evidências locais: `evidence/terrain3d-mountain/`. O medidor usa `Main.tscn`,
confirma o roteador C# e salva configuração, população, hashes e frames brutos.
O começo em checkpoint não valida a chegada à montanha pela ponte. A sequência
visual opcional ocorre depois da medição: sua leitura de GPU não entra nos tempos.

Integração da extensão nativa **reprovada por instabilidade antes da medição**;
performance do nó nativo não medida.
Existiram processos
Godot de outra sessão durante o trabalho; não confundir números de diagnóstico
com aprovação isolada de performance. O critério estabelecido é 60 FPS/16,67 ms,
com aumento de p95/p99 acima de 5% pedindo confirmação em condições equivalentes.

### Comparação final da malha exportada

Percurso local de 70 m, 5 s de aquecimento e 30 s medidos, mesma câmera, clima,
resolução e hashes dos sistemas monitorados. Nenhum desses hashes mudou durante
os ensaios. População final de 40 pessoas em ambos; veículos: 3 antes e 2 depois.
Essa diferença e a outra sessão Godot ativa impedem atribuir causalidade aos
números ou aprovar performance isolada.

| Medida | Antes (`before-12020`) | Depois (`after-135240`) |
|---|---:|---:|
| FPS médio | 184,60 | 175,79 |
| Frame time p50 | 4,839 ms | 4,998 ms |
| Frame time p95 | 8,605 ms | 8,630 ms |
| Frame time p99 | 10,073 ms | 10,448 ms |
| Maior frame | 27,316 ms | 25,836 ms |
| Frames acima de 33,3 ms | 0 | 0 |

p95 aumentou 0,29% e p99 3,72%; FPS médio caiu 4,77%. Resultado **diagnóstico**;
não houve crash com a solução exportada nos ensaios completos. Os valores do HUD
nas imagens são instantâneos, anteriores ao intervalo medido.

- Antes: `evidence/terrain3d-mountain/before-12020/comparison.png`.
- Depois: `evidence/terrain3d-mountain/after-135240/comparison.png`.
- Travessia final: `after-135240/sequence`, 120 frames consecutivos, 1,61 s,
  X 766 → 769,27, cruzando a borda X 768; `on_floor=true` em todos os registros.
  Inspeção dos frames inicial/final não mostrou fenda ou degrau; a captura curta
  não certifica estabilidade visual em todos os ângulos, horários e climas.
- Logs finais: `after-delivery.log` e `contract-production.log`.
- Inventário concorrente: `processes-delivery.json`; hashes: `source-delivery.json`.

Pendências: compatibilidade do nó nativo, uso prolongado do plugin no editor,
benchmark isolado, chegada pela ponte, noite e chuva. A experiência local não
aprova migração da montanha inteira nem os recursos de LOD/colisão do addon.
