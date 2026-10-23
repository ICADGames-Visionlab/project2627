#Feito pelo Enzo com uso do Claude — issue #54

# Movimentação do Jogador (andar e correr)

Como o `Player` anda e corre nos esquemas de movimentação que o jogador escolhe nas configurações
(Options → Movimentação, `GameManager.movement_scheme`):

| Opção na tela | `MovementScheme` | O que vale |
|---|---|---|
| Teclado (WASD) | `KEYBOARD` (padrão) | Só WASD/setas/analógico |
| Clique do mouse | `CLICK` | Só point and click |
| Teclado + clique do mouse | `BOTH` | Os dois ao mesmo tempo (ver [Teclado + clique](#teclado--clique)) |

Quem precisa saber se o teclado ou o clique estão ligados pergunta ao `GameManager`
(`is_keyboard_movement_enabled()` / `is_click_movement_enabled()`), em vez de comparar com cada esquema.

Peças do sistema:

| Arquivo | Papel |
|---|---|
| `scripts/player/Player.gd` | O personagem: lê o input do esquema ativo, anda/corre, escolhe a animação. Dono de todas as variáveis de balanceamento. |
| `scripts/player/ClickMoveGesture.gd` | Intérprete do botão do mouse no esquema de clique: decide o que é clique, clique duplo e "segurar". Lógica pura (`RefCounted`), sem cena nem Input. |
| `scripts/player/PlayerMovementSelfTest.gd` | Autoteste de tudo o que está descrito aqui (ver [Testando](#testando)). |
| `tests/run_player_movement_self_test.gd` | Roda o autoteste completo pela linha de comando. |
| `resources/player_sprite_frames.tres` | Animações `idle_*`, `walk_*` e `run_*`, nas 8 direções. |
| `project.godot` (Input Map) | Ação `move_run` (SHIFT) e `move_click` (botão esquerdo). |

---

## As regras

### Teclado

| O jogador faz | O personagem |
|---|---|
| WASD / setas / analógico | **Anda** (`walk_speed`) |
| Mesma coisa segurando **SHIFT** | **Corre** (`run_speed`) |
| Solta o SHIFT no meio do caminho | Volta a andar na hora |
| Segura o SHIFT parado | Continua parado, com animação de parado |

O SHIFT é lido a cada frame, então não tem estado nenhum para guardar. No clique o SHIFT não faz nada
(nem no esquema só de clique, nem no de teclado + clique): lá quem pede corrida é o clique duplo.

### Clique

| O jogador faz | O personagem |
|---|---|
| **Um clique** | **Anda** até o ponto clicado e para |
| **Dois cliques rápidos** no mesmo lugar | **Corre** até o ponto |
| **Segura** o botão em vez de clicar | **Acompanha o mouse andando** enquanto o botão estiver apertado |
| **Clique duplo e segura** o segundo clique | **Acompanha o mouse correndo** |
| Solta o botão depois de segurar | Termina o trajeto no ponto em que soltou (andando ou correndo, como vinha) |

Detalhes que valem a pena saber:

- **O primeiro clique não espera.** O personagem sai andando no mesmo instante; se vier o segundo clique,
  ele só troca a caminhada em andamento por corrida. Esperar para descobrir se vem um segundo clique
  deixaria todo clique simples com atraso perceptível.
- **"Rápido" e "mesmo lugar"** são `double_click_seconds` (0.4 s) entre os dois apertos e
  `double_click_distance` (24 px) entre eles. A distância é medida na **tela** (na resolução base do
  projeto, 1920x1080, independente do tamanho da janela), não no mundo: a câmera segue o personagem,
  então o mesmo ponto da tela aponta para lugares diferentes do mundo entre um clique e outro.
- **"Segurar"** é o botão ficar apertado por `click_hold_seconds` (0.25 s). Um clique normal dura
  ~0.1 s.
- **Terceiro clique rápido no mesmo lugar continua correndo** (forma par com o segundo). Clicar várias
  vezes não alterna corre/anda/corre.
- **Um "segurar" nunca conta como primeiro clique** de um clique duplo: segurar, soltar e clicar logo em
  seguida anda.
- **Chegar ao destino encerra a corrida.** O próximo clique decide de novo.
- **Acompanhar o mouse usa o Pathfinder**: o caminho é retraçado a cada `follow_repath_seconds` (0.1 s)
  para desviar dos prédios, e entre um retraçado e outro o fim do caminho acompanha o mouse frame a
  frame. Com o mouse em cima do personagem, ele fica parado.

### Teclado + clique

Cada um continua com as próprias regras das tabelas acima. Quando os dois disputam o personagem:

| O jogador faz | O personagem |
|---|---|
| Aperta WASD no meio de um trajeto de clique | **O teclado manda**: o trajeto é descartado |
| Solta o WASD depois disso | Para (o trajeto antigo não é retomado) |
| Aperta WASD com o botão do mouse **segurado** | O teclado manda enquanto estiver apertado |
| Solta o WASD com o botão ainda segurado | Volta a acompanhar o mouse |

### Conversa com NPC

Clicar num NPC (em qualquer esquema) trava o input e faz o personagem se aproximar dele. A aproximação
herda o passo de como o jogador vinha se movendo: quem corria chega correndo. O fim da conversa devolve
o controle sempre andando, e nada do que estava acontecendo antes dela (botão segurado, primeiro clique
de um clique duplo) continua valendo.

---

## Variáveis de balanceamento (Inspector do `Player`)

| Variável | Padrão | O que faz |
|---|---|---|
| `walk_speed` | 225 | Velocidade andando (px/s de tela, no movimento horizontal) |
| `run_speed` | 450 | Velocidade correndo, mesma unidade |
| `vertical_speed_factor` | 0.71 | Velocidade vertical como fração da horizontal (0.71 = cos 45°, o encurtamento da câmera; 1.0 = uniforme na tela) |
| **Esquema de clique** | | |
| `click_hold_seconds` | 0.25 | Quanto tempo apertado vira "segurar" |
| `double_click_seconds` | 0.4 | Intervalo máximo do clique duplo |
| `double_click_distance` | 24 | Distância máxima (px de tela) entre os dois cliques |
| `follow_repath_seconds` | 0.1 | Intervalo entre buscas no Pathfinder enquanto acompanha o mouse |

`walk_speed` e `run_speed` também podem ser ajustados com o jogo rodando, no menu de debug (**F4**,
seção "Jogador").

---

## Como funciona por dentro

### Por que o gesto de clique é uma classe separada

A parte difícil de acertar é o **tempo** (quanto é "segurar", quanto é "rápido"). O `ClickMoveGesture`
recebe só três coisas — apertou, soltou e "o tempo passou" — sempre com o instante informado por quem
chama, e devolve um `Command`:

| Command | Quando | O `Player` faz |
|---|---|---|
| `GO_TO` | Todo apertar | Traça caminho até o mouse, andando ou correndo (`is_running`) |
| `START_FOLLOW` | O botão passou de `hold_seconds` apertado | Passa a acompanhar o mouse |
| `STOP_FOLLOW` | Soltou depois de segurar | Termina o trajeto no ponto em que soltou |
| `CANCEL_FOLLOW` | O botão subiu mas o evento de soltar **nunca chegou** | Para onde está |

Como o instante entra por parâmetro, o autoteste encena qualquer sequência de cliques em microssegundos,
sem esperar relógio nenhum. O relógio que o `Player` passa é a soma dos `delta` de física
(`_click_clock`), e não o relógio do sistema: assim "segurar" e "clique duplo" congelam junto com o jogo
quando ele pausa.

### Redes de segurança

- **Clique na interface não anda.** O `Player` lê o botão em `_unhandled_input`: um clique consumido por
  um botão, um menu ou um orbe de insight nunca chega nele. O soltar só é repassado ao gesto se o apertar
  correspondente passou por ali.
- **Soltar que se perdeu** (jogo pausado, janela sem foco, soltou em cima de um menu): a cada frame o
  gesto também recebe o estado real do botão (`Input.is_action_pressed`). Se o botão subiu sem o evento
  chegar, o acompanhamento é **cancelado** (`CANCEL_FOLLOW`) e o personagem para onde está — ele não vai
  até o mouse, porque a essa altura o mouse pode estar em cima do "Continuar" do menu de pausa.
- **Conversa e troca de esquema** zeram o gesto: um botão segurado não volta a puxar o personagem quando
  a conversa acaba, nem um clique de antes forma clique duplo com um de depois.

### Animação

`movement_state_changed(is_moving, is_running, facing_direction)` é emitido só quando o estado muda. O
próprio `Player` escuta e toca `idle_<dir>`, `walk_<dir>` ou `run_<dir>` (nomes montados por
`TopDown.animation_name`). `is_running` só é verdadeiro junto com `is_moving`: SHIFT segurado parado
não toca animação de corrida.

---

## Testando

### Autoteste (linha de comando)

```
godot --headless --path . --script res://tests/run_player_movement_self_test.gd
```

Sai com código 0 quando tudo passa. Cobre as duas partes:

1. **Gesto** — a regra de tempo do `ClickMoveGesture` (instantâneo).
2. **Player de verdade** — um `Player` criado só para o teste, andando frame a frame, com as teclas e o
   botão simulados pelo próprio Input Map. Confere velocidade e animação de cada regra acima, inclusive
   segurar com o mouse perto do personagem (que antes fazia a animação piscar), soltar perdido,
   conversa e troca de esquema no meio do movimento.

### Pelo menu de debug

**F4 → Jogador → "Autoteste do clique"** roda só a parte do gesto (a que não mexe no personagem da
partida) e imprime o relatório no log.

### Na mão

1. Configurações → Movimentação → **Clique do mouse**.
2. Um clique longe: anda. Dois cliques rápidos: corre. Segurar: o personagem acompanha o mouse andando.
   Clique duplo e segurar: acompanha correndo.
3. Configurações → Movimentação → **Teclado (WASD)**. WASD anda; com SHIFT corre.
4. Configurações → Movimentação → **Teclado + clique do mouse**. Tudo dos passos 2 e 3 vale junto;
   apertar WASD no meio de um trajeto de clique assume o controle.
5. Os prints `[Player] - ...` no log mostram cada decisão (clique simples/duplo, começou/parou de
   correr, começou/parou de acompanhar o mouse).
