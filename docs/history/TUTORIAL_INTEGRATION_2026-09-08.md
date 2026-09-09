# Revisão da entrega do Claude

Catálogo e apresentador revisados no código local. Os 60 checks originais passaram novamente com Godot 4.7.2 headless.

Integração por `ui/tutorial_preview/GameplayTutorials.gd`, instalado pelo HarborGame. Contextos conectados: aproximação da loja térmica, temperatura baixa, aviso do túnel, coleta real de arma rara e jogador procurado entrando em interior. As duas dicas de porta-malas/loadout continuam bloqueadas até existir a funcionalidade real.

Correção no apresentador: esconder uma dica já ativa quando abre modal, começa combate ou direção rápida; pausar seu tempo e retomá-la depois. Antes, o bloqueio impedia apenas novas dicas. Reset libera também o timer pausado. Botão de fechar não rouba foco de teclado.

O adaptador verifica pausa, diálogo, controles desativados, morte e modais dos interiores/quadros; considera ataque pelo cooldown real da arma e perda recente de vida; suspende a dica acima de 180 unidades/s ao volante. A verificação ocorre a cada 0,2 s. Histórico é por sessão, não gravado no save. Sem nova tecla de jogo: botão fechar e timeout continuam disponíveis. A camada ocupa o canto inferior direito, sem sobrepor o objetivo principal.

Textos de frio e item raro foram ajustados ao comportamento existente; não anunciam slots limitados ainda inexistentes. PT/EN acompanha o idioma do jogo. As dicas antigas de frio/túnel da expedição encaminham para o apresentador, evitando mensagens duplicadas.

Testes adicionais em `tests/test_gameplay_tutorials.gd`: contexto suportado e não suportado, esconder/retomar durante diálogo e ataque, pausa, não repetição, busca exterior e gatilhos da montanha. Captura real Vulkan: `D:/geteco/tutorial-gameplay-review.png`. O teste da encomenda no navio também passou após integração. Persiste aviso de uma instância ObjectDB ao encerrar alguns testes do mundo; não atribuído a esta entrega nem tratado como resolvido.
