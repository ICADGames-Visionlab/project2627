# Sistema de Troca de Cenas com Loading

Como o jogo troca de cena sem congelar em carregamentos pesados.

---

## Visão geral

Trocar de cena com `get_tree().change_scene_to_file()` puro é síncrono: a engine para tudo até
terminar de instanciar a cena nova. Em cenas leves isso não se nota, mas assim que uma cena
carregar assets pesados (mapas grandes, muitos recursos), o jogo trava por um tempo perceptível
na hora da troca — sem barra de progresso, sem feedback nenhum pro jogador.

Este sistema resolve isso com quatro peças que trabalham juntas:

1. **Fade preto** (já existia antes) — cobre a transição visualmente, evita o "corte seco" de uma
   cena pra outra.
2. **Cena de loading** (`LoadingScreen.tscn`) — fica visível enquanto a cena de destino carrega,
   com uma barra de progresso.
3. **Carregamento assíncrono** (`ResourceLoader.load_threaded_request`) — carrega a cena de
   destino em thread separada, sem travar o jogo, permitindo atualizar a barra de progresso
   quadro a quadro.
4. **Período de tolerância** (`GameManager.LOADING_GRACE_PERIOD_SECONDS`) — antes de mostrar a
   loading screen, o `GameManager` dá um tempo curto (padrão `0.15s`) pro carregamento terminar
   sozinho. Se a cena for leve o suficiente pra carregar dentro desse tempo, a troca acontece
   direto e a loading screen nunca chega a aparecer — evita o "flash" de loading em cenas rápidas.

**Por que existe:** para o jogo dar feedback visual em qualquer troca de cena que demore, sem que
cada sistema que troca de cena precise se preocupar com fade, thread de carregamento ou
progresso — tudo isso fica centralizado em um único ponto de entrada.

---

## Como usar

Qualquer troca de cena do projeto deve passar pelo `GameManager`:

```gdscript
GameManager.change_scene("res://scenes/levels/Level02.tscn")
```

Opcionalmente, dá pra ajustar a duração do fade (padrão: `0.5` segundos):

```gdscript
GameManager.change_scene("res://scenes/levels/Level02.tscn", 1.0)
```

Enquanto a troca está em andamento, `GameManager.in_transition` fica `true`. Útil para, por
exemplo, ignorar input do jogador durante a transição.

> ⚠️ **Nunca chame `get_tree().change_scene_to_file()` ou `change_scene_to_packed()` diretamente
> em outro script.** Isso pula o fade, a cena de loading e o carregamento assíncrono — o jogador
> veria um corte seco e, em cenas pesadas, o jogo travaria sem feedback nenhum.

---

## Estrutura de arquivos

| Arquivo | Papel |
|---|---|
| [`scripts/singletons/GameManager.gd`](../scripts/singletons/GameManager.gd) | Singleton (Autoload). Expõe `change_scene()`, orquestra o fade e escuta o sinal de conclusão do carregamento. |
| [`scenes/loading_screen/LoadingScreen.tscn`](../scenes/loading_screen/LoadingScreen.tscn) | Cena intermediária exibida durante o carregamento. |
| [`scripts/ui/LoadingScreen.gd`](../scripts/ui/LoadingScreen.gd) | Script da cena acima: dispara o carregamento assíncrono, faz polling do progresso e troca para a cena final quando termina. |

---

## Fluxo passo a passo

```
GameManager.change_scene("res://.../Alvo.tscn")
		│
		▼
1. in_transition = true
2. Fade-out (tela vai a preto)
		│
		▼
3. GameManager já dispara ResourceLoader.load_threaded_request(caminho) — antes de decidir
   se a loading screen é necessária
		│
		▼
4. _try_load_within_grace_period(): faz polling de load_threaded_get_status() por até
   LOADING_GRACE_PERIOD_SECONDS (padrão 0.15s)
		│
		├── "loaded" (carregou a tempo) ─────────────────────────────────┐
		│                                                                 ▼
		│                                            5a. change_scene_to_packed() direto.
		│                                                A loading screen NUNCA é exibida.
		│
		├── "failed" (deu erro) ─────────────────────────────────────────┐
		│                                                                 ▼
		│                                            5b. push_error, mantém a cena atual
		│                                                (nenhuma troca acontece)
		│
		└── "pending" (ainda carregando) ────────────────────────────────┐
		                                                                  ▼
		                                             5c. GameManager troca para LoadingScreen.tscn
		                                                 (change_scene_to_file)
		                                                         │
		                                                         ▼
		                                             LoadingScreen._ready() lê o caminho via
		                                             get_target_scene_path() e, como o carregamento
		                                             já está em andamento (is_load_already_in_progress),
		                                             só passa a acompanhar — não pede de novo
		                                                         │
		                                                         ▼
		                                             A cada _process(), consulta
		                                             load_threaded_get_status() e atualiza a
		                                             ProgressBar (0–100%)
		                                                         │
		                                                         ▼
		                                             Status THREAD_LOAD_LOADED:
		                                             - busca a cena com load_threaded_get()
		                                             - garante o tempo mínimo de exibição
		                                               (minimum_display_time)
		                                             - troca para a cena de destino
		                                               (change_scene_to_packed)
		                                             - emite GameManager.scene_loaded
		│                                                        │
		▼◄───────────────────────────────────────────────────────┘
6. GameManager retoma (direto em 5a/5b, ou via await scene_loaded em 5c):
   - Fade-in (revela a cena de destino, ou a cena atual em caso de falha)
   - in_transition = false
```

### Comunicação entre LoadingScreen e GameManager

Não existe polling entre os dois nós — a comunicação é só por sinal:

- **GameManager → LoadingScreen:** guarda o caminho de destino em `_target_scene_path`, que a
  LoadingScreen lê via `GameManager.get_target_scene_path()` no próprio `_ready()`. Não dá pra
  passar o caminho por parâmetro porque a troca de cena (`change_scene_to_file`) não aceita
  argumentos extras.
- **GameManager → LoadingScreen (carregamento em andamento):** o `GameManager` já chama
  `load_threaded_request()` antes de decidir se a loading screen é necessária (ver período de
  tolerância, abaixo). Se ela acabar aparecendo, a LoadingScreen consulta
  `GameManager.is_load_already_in_progress()` e, se `true`, **não** chama `load_threaded_request`
  de novo — só passa a fazer polling do carregamento que já está rolando. Pedir o carregamento do
  mesmo caminho duas vezes dá erro no `ResourceLoader`.
- **LoadingScreen → GameManager:** emite `GameManager.scene_loaded` assim que a troca final para
  a cena de destino já foi disparada. O GameManager fica em `await scene_loaded` esperando esse
  aviso antes de começar o fade-in.

### Período de tolerância (pular a loading screen em cenas rápidas)

Depois do fade-out, o `GameManager` não troca direto para `LoadingScreen.tscn`. Em vez disso:

1. Chama `ResourceLoader.load_threaded_request(scene_path)` ele mesmo.
2. Faz polling de `load_threaded_get_status()` por até `LOADING_GRACE_PERIOD_SECONDS` (constante
   em `GameManager.gd`, padrão `0.15s`).
3. Se carregar dentro desse tempo, troca direto (`change_scene_to_packed`) — a loading screen
   nunca chega a ser instanciada. Como a tela já está preta (fade-out), o jogador só vê um fade
   um pouco mais longo, não um "flash" de loading.
4. Se não carregar a tempo, **só então** troca para `LoadingScreen.tscn`, que assume o
   acompanhamento do carregamento já em andamento (ver comunicação acima).

Isso resolve o problema de loading desnecessário sem precisar "adivinhar" o tamanho da cena de
antemão — é uma medição real do tempo de carregamento, não uma estimativa.

Se `0.15s` estiver muito curto ou muito longo pro seu caso (ex.: mostrar a loading screen com
mais ou menos frequência), ajuste `GameManager.LOADING_GRACE_PERIOD_SECONDS`.

### Por que a LoadingScreen é um `CanvasLayer` e não um `Control` puro

O fade preto do GameManager é um `CanvasLayer` com `layer = GameManager.FADE_LAYER` (bem alto,
acima de qualquer cena comum) — ele fica de pé durante toda a transição, inclusive enquanto a
LoadingScreen está ativa. Se a LoadingScreen fosse um `Control` comum (layer implícito 0), ficaria
escondida atrás do preto. Por isso o root da cena é um `CanvasLayer` com layer maior que o do
fade (`layer = 1002` vs. `FADE_LAYER = 1001`), garantindo que a barra de progresso sempre
apareça por cima do overlay.

---

## Como adicionar elementos visuais novos na loading screen

A cena já reserva um node `Extras` (`Layout/Extras`, um `Control` vazio cobrindo a tela) para
isso — spinner, texto de progresso, dicas de carregamento, etc. Para adicionar algo novo:

1. Abra `scenes/loading_screen/LoadingScreen.tscn` no editor.
2. Adicione o node visual (ex.: `Label`, `AnimatedSprite2D`, `RichTextLabel`) como filho de
   `Layout/Extras`.
3. Se o elemento precisa refletir o progresso (ex.: um texto "Carregando... 42%"), exponha uma
   referência `@onready` no script e atualize dentro de `_poll_loading_status()`, junto da
   `ProgressBar`.
4. Dicas de carregamento (textos rotativos) podem ser um `@export var loading_tips:
   Array[String]` sorteado em `_ready()` — não é necessário nenhuma mudança na lógica de
   carregamento existente.

Não é necessário mexer no `GameManager` para isso — toda a lógica visual fica isolada na
LoadingScreen.

---

## Limitações conhecidas e pontos de atenção

- **Não chamar `change_scene_to_file`/`change_scene_to_packed` fora do `GameManager`.** Qualquer
  troca de cena direta pula fade, loading screen e carregamento assíncrono.
- **Acoplamento de layers.** `LoadingScreen.layer` precisa continuar maior que
  `GameManager.FADE_LAYER`. Se um dos dois valores mudar isoladamente, a barra de progresso pode
  ficar escondida atrás do fade preto.
- **Falha de carregamento.** Se `THREAD_LOAD_FAILED`/`THREAD_LOAD_INVALID_RESOURCE` acontecer
  ainda dentro do período de tolerância, o `GameManager` loga com `push_error` e simplesmente
  mantém a cena atual (nenhuma troca ocorre, o fade-in revela a mesma cena de antes — o jogo não
  fica travado atrás do preto). Se a falha só aparecer depois, já com a LoadingScreen na tela, ela
  também loga com `push_error`, mas nesse caso não existe fallback visual: a LoadingScreen fica
  parada, sem cena de erro nem retry automático.
- **Uma troca de cena por vez.** Chamar `change_scene()` enquanto `in_transition` já é `true`
  não é tratado (a segunda chamada some dentro do `await` da primeira). Cheque
  `GameManager.in_transition` antes de disparar uma nova troca, se isso for uma possibilidade real
  no fluxo do jogo (ex.: jogador clicando várias vezes num botão de menu).
- **`minimum_display_time`** é `@export` na `LoadingScreen` (padrão `0.5s`), então dá pra ajustar
  pelo Inspector sem mexer em código.
