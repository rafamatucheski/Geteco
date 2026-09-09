# Cupê: teste isolado de colisão e iluminação

Abra `CoupeCrashLab.tscn` no Godot e use F6. Não substitui a cena principal.

- W/S: acelerar/ré. A/D: direção. Espaço: freio.
- L: apagado / baixo / alto. N: dia/noite. C: câmera traseira/frontal.
- R: restaurar posição, integridade, carroceria, peças e faróis.
- Acelere em linha reta desde o início para atingir a barreira com o canto direito.

Implementado: controlador arcade CharacterBody3D; rodas girando e esterçando;
colisão física aciona deformação localizada da malha, limitada a 0,32 m;
impactos leves/fortes diferentes; riscos e representação inicial de trincas;
farol atingido apaga; impacto frontal forte desprende uma peça com física;
integridade reduz aceleração/velocidade; dois SpotLight3D iluminam o cenário
com sombras; luzes de freio; reparação completa.

Validação automatizada: `tests/test_coupe_crash_lab.gd` dirige contra uma
barreira real, verifica colisão, dano, localização, limites, peças, luzes e
reparação. `tests/visual/capture_coupe_crash_lab.gd` compara pixels com luzes
apagadas/acesas e captura uma colisão real. Não é benchmark da cidade.

## Limites explícitos

Este é um laboratório **inteiramente 3D**. O distrito usa mundo/colisões 2D:
agora existe uma adaptação separada em `HarborCoupe.gd`, descrita em
`HARBOR_COUPE_INTEGRATION.md`. Esta cena de laboratório continua independente
e nem todos os seus recursos físicos foram transplantados.

Dano visual não muda o volume de colisão; não há simulação estrutural,
suspensão física, áudio de motor ou sistema de entrada/saída neste teste.
A peça destacável inicial é o acabamento central do para-choque, não todas
as peças. Trincas são linhas geométricas simples, não vidro fraturado.
Geometria reconstruída somente no impacto; ainda requer orçamento/LOD para
vários carros, além de medir picos de colisão no cenário real.

Sem mudanças nas otimizações do Claude, na quadra do Antigravity ou commits.

## Pendências relatadas para a futura revisão do mapa

Segundo o relatório do Claude (não revalidado nesta tarefa): fila na
Courtyard Lane; pavimentação de becos sobreposta aos prédios novos da Quadra
1; picos de 250–300 ms; visão geral abaixo de 60 fps. Integrar este carro não
resolve essas pendências. Coordenar também StreetLamp e acesso da clínica
com as mudanças do Antigravity antes de declarar o mapa pronto.
