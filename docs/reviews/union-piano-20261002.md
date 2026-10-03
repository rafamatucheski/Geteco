# Piano da Union Plaza

Oito teclas transitáveis ao lado leste do chafariz, em frente ao Bay Medical.
Centro: (114.6875, 0, 112.325). Jogador e civis vivos/visíveis tocam notas ao
entrar numa tecla. Ficar parado não repete. A tecla colorida indica a próxima
nota de uma sequência de sete passos; completá-la colore o teclado por 2,4 s.
Notas dos civis não alteram o desafio. Sem prêmio financeiro ou captura de input.

Piso existente mantém apoio/colisão. Peças rasas, sem obstáculos novos, luzes,
sombras, partículas, NPCs ou SubViewports. Oito vozes e oito sons compartilhados.
Timer de 60 ms próximo / 500 ms distante. Limpeza ao afastar, abrir menu ou
entrar em interior/transição. Pausa segue a árvore; descarregamento libera nós.

## Evidência e limites

- `dotnet build Harbor.csproj --no-restore`: zero erros/avisos.
- Godot 4.7.2 .NET, `--headless --script tests/test_union_piano.gd -- --no-save`:
  testes locais de limites espaciais, sequência, interferência de civis,
  deduplicação de passos, limpeza e recarga/cache.
- `tests/capture/capture_union_piano.gd`: prévia isolada renderizada, Mobile,
  RTX 4060 Laptop, 1280×720. Imagens em `artifacts/union-piano/preview/`.
  Inspeção estática; não certifica atores em movimento ou áudio ouvido.
- Primeira tentativa da cena principal bloqueada por preloads ausentes de
  `world/places/supermarket/SupermarketPlace.gd` e `runtime/SupermarketShop.gd`.
  Os arquivos surgiram durante trabalho concorrente; a última execução local
  passou sem erros de preload (zero falhas). Arquivos alheios não alterados.

- Integração na `Main.tscn`, headless, C# ativo, `--functional-only --no-save`:
  jogador real atravessou com movimento automático e física por 8 segundos.
  `notes=[0,1,2,3,4,5,6,7]`, posição final local
  `(8.080666,-0.009157,0.0)`, `passed=true`, saída 0.
  Entrada na área por teleporte de diagnóstico; travessia sem teleporte.

Acesso desde outro bairro, civis em movimento, oclusão de atores, interrupções
e retorno pelo streaming: pendentes. Performance **não medida**, sem baseline válido.
Meta provisória 60 FPS / 16,67 ms; piora >5% em p95/p99 exige confirmação.
Runner `tests/measure/measure_union_piano.gd` preparado: duas janelas de 30 s
(dia/noite), `--without-piano` para comparação, `--out=res://...` exclusivo,
sempre `--no-save`. Executar sem benchmarks concorrentes e com dependências
estáveis. Uma captura de outra sessão (`measure_classic_meet.gd`) estava ativa
na checagem de processos; nenhum benchmark concorrente foi iniciado aqui.
Prévia isolada não comprova FPS ou aprovação na cidade.
