# Debug Menu (Mod Menu)

Um menu (F4) e um console de comando (F1), abertos com o jogo rodando, onde qualquer ação de debug fica a
um clique ou um comando — sem recompilar, sem mexer em código.

---

## A ideia

Qualquer sistema pode pendurar uma ação no menu com uma chamada só, no próprio `_ready()`:

```gdscript
DebugMenu.register_action(&"Jogador", "Matar", _die)
```

O menu **se monta sozinho** a partir do que foi registrado — ninguém edita a cena para adicionar um botão.
`DebugMenu` (Autoload) guarda o registro e escuta as teclas de abrir; `DebugMenuOverlay` e
`DebugConsoleOverlay` (cenas instanciadas sob demanda) são só dois jeitos de ler o mesmo registro — um botão
ou um comando de texto, nunca um sem o outro. Ninguém precisa desregistrar: um `Callable` cujo dono já saiu
da árvore some sozinho na próxima abertura do menu.

> **Estado atual:** o projeto ainda não tem gameplay, então as únicas seções são as de fábrica —
> **Sistema**, **Desempenho**, **Tela**, **Captura** e **Log** (ver abaixo) —, que não dependem de nenhum
> sistema de jogo. Elas também servem de exemplo vivo de como registrar. A seção **Eventos** (ver
> [abaixo](#eventos)) some por junto: ela só aparece depois que o primeiro `signal` for declarado em
> `EventBus.gd`.

**Onde mora cada ferramenta de fábrica.** "Sistema" e "Desempenho" são registradas pelo próprio
`DebugMenu`, porque são ações de engine e controles de um overlay que ele mesmo instancia. "Tela", "Captura"
e "Log" têm estado próprio (a proporção escolhida, o filtro do log), então cada uma é um **nó filho do
autoload** — `DebugScreenTester`, `DebugScreenCapture`, `DebugLogViewer` — que registra a própria seção no
`_ready()`, exatamente como um sistema de jogo faria. O autoload só as segura vivas e roteia a tecla de
atalho até elas. A regra para código novo é essa: **ferramenta com estado é dona da própria seção**.

**Por que existe:** matar o jogador, pular o dia, travar o tempo — tudo isso é mais rápido de testar num
botão do que reproduzindo a condição de jogo de verdade toda vez.

**O preço:** ação de debug nunca pode ser o único caminho para um comportamento do jogo. Se a única forma de
avançar o dia é pelo menu, isso é uma feature disfarçada de debug, não uma ferramenta de debug.

---

## Como abrir

**F4**, com o jogo rodando. Abre e fecha; não pausa o jogo sozinho — pausar é um toggle na seção Sistema,
porque metade do debug é olhar o jogo se mexendo.

A tela tem duas colunas: as seções à esquerda, os botões e interruptores da seção selecionada à direita.
Clique numa seção pra trocar o que aparece do lado direito.

A primeira vez que F4 é apertado instancia a cena do menu; até lá, a ferramenta não custa nada. O cursor do
mouse é liberado automaticamente ao abrir e volta ao estado anterior ao fechar.

Em build de release o F4 não faz nada — a ferramenta não existe fora de editor/debug.

### Teclas de debug do projeto

| Tecla | Ferramenta |
| --- | --- |
| **F1** | Console de comando livre (ver [seção "Console (F1)"](#console-f1)) |
| **F2** | Overlay de desempenho (ver [seção "Desempenho"](#overlay-de-desempenho-seção-desempenho)) |
| **F3** | Overlay do EventBus (ver `docs/event_bus.md`) |
| **F4** | Este menu |
| **F5** | Visualizador de log (ver [seção "Log"](#visualizador-de-log-seção-log)) |
| **F6** | Captura de tela (ver [seção "Captura"](#captura-de-tela-seção-captura)) |

Todas caem para a tecla direta se a ação correspondente sumir do Input Map, então uma configuração quebrada
não deixa nenhuma ferramenta inacessível.

---

## Registrar uma ação

Quatro funções, chamadas de dentro do `_ready()` do sistema que tem o que depurar, sob o guard de debug:

```gdscript
func _ready() -> void:
	if OS.has_feature("editor") or OS.is_debug_build():
		# [DEBUG] Ações deste sistema no menu de debug.
		DebugMenu.register_action(&"Jogador", "Matar", _die)
		DebugMenu.register_toggle(&"Jogador", "Invencível", _set_invincible)
		DebugMenu.register_value(&"Jogador", "Velocidade", _set_speed,
			DebugParam.float_value("", move_speed, 0.0, 600.0, 10.0),
			func() -> float: return move_speed)
		DebugMenu.register_input(&"Jogador", "Dar ouro", _give_gold, [
			DebugParam.int_value("quantidade", 100, 1, 9999)
		])


# Liga/desliga a invencibilidade. Recebe o estado novo do interruptor do menu de debug.
func _set_invincible(enabled: bool) -> void:
	_is_invincible = enabled
```

- `register_action(section, label, action, requires_confirmation = false)` — um botão que dispara
  `action.call()` no clique. Ver ["Ação destrutiva"](#ação-destrutiva) para `requires_confirmation`.
- `register_toggle(section, label, on_changed, initial)` — um interruptor. O **menu** guarda o `bool` e
  chama `on_changed(novo_valor)` quando ele muda. Se o sistema alterar o valor por outro caminho, o menu
  desencontra até ser reaberto — não há getter. Não recebe `requires_confirmation`: um interruptor é
  reversível por definição (desfazer é clicar de novo).
- `register_value(section, label, on_changed, param, getter = Callable())` — um campo solto (número, texto,
  bool ou opção), sem botão. O **menu** guarda o valor no `DebugParam` e chama `on_changed(novo_valor)` a
  cada mudança do widget. `getter` é opcional: quando presente, o overlay lê o valor de verdade do sistema
  ao remontar em vez da cópia guardada — resolve o mesmo desencontro do toggle, agora com saída.
- `register_input(section, label, action, params, requires_confirmation = false)` — um botão que só dispara
  depois de os campos declarados (`Array[DebugParam]`) serem preenchidos. O clique chama
  `action.callv()` com os valores **na ordem declarada**. É o que substitui o `.bind(100)` hardcoded para
  ações com argumento de verdade (ver ["Casos que aparecem na prática"](#casos-que-aparecem-na-prática)).

### `DebugParam`: descrevendo um parâmetro

`DebugParam` (`scripts/debug/DebugParam.gd`) guarda o **tipo** de um parâmetro — nunca como ele é exibido.
É essa separação que faz o menu escolher um `SpinBox` e o console escolher uma conversão de texto a partir
da mesma declaração, sem os dois nunca divergirem. Fábricas estáticas, uma por tipo:

| Fábrica | Tipo | Widget no menu | Token no console |
| --- | --- | --- | --- |
| `DebugParam.int_value(nome, default, min, max, step)` | `INT` | `SpinBox` (+ `HSlider` se `use_slider = true`) | inteiro |
| `DebugParam.float_value(nome, default, min, max, step)` | `FLOAT` | `SpinBox` (+ `HSlider` se `use_slider = true`) | decimal |
| `DebugParam.string_value(nome, default, sugestões)` | `STRING` | `LineEdit` | texto (aspas para espaço) |
| `DebugParam.bool_value(nome, default)` | `BOOL` | `CheckBox` | `1/true/sim/on` ou `0/false/nao/off` |
| `DebugParam.enum_value(nome, opções, índice_default)` | `ENUM` | `OptionButton` | texto da opção (sem diferenciar maiúsculas) — o Callable recebe o **índice**, não o texto |

`sugestões` (só em `string_value`) é um `Callable` sem argumento que devolve a lista de valores válidos
**agora** — não uma lista assada no registro. É o que faz `DebugMenu.register_input(&"Inventário", "Dar item",
_give_item, [DebugParam.string_value("id", "", ItemDatabase.get_all_ids), DebugParam.int_value("quantidade", 1, 1, 99)])`
sempre sugerir os itens atuais no autocomplete do console, mesmo que o catálogo mude depois do registro.

**Criar uma seção nova é grátis**: ela nasce sozinha na primeira vez que algo é registrado nela, na ordem em
que as seções aparecem pela primeira vez. Não existe enum nem registro prévio de seção.

**Registrar de novo com o mesmo par (seção, rótulo) substitui a entrada anterior** em vez de duplicar — é o
que evita botão repetido quando a cena que registra recarrega. Para `register_value`/`register_input`, se a
nova lista de parâmetros tiver o mesmo tamanho e os mesmos tipos da anterior, o valor digitado sobrevive ao
re-registro; se os tipos mudaram, o novo default vale (a assinatura mudou de verdade).

---

## O que vem de fábrica: seção "Sistema"

O próprio `DebugMenu` registra estas cinco entradas no `_ready()`, antes de qualquer cena de jogo — por isso
"Sistema" aparece sempre em primeiro:

| Entrada | Tipo | O que faz |
| --- | --- | --- |
| Pausar jogo | toggle | `get_tree().paused` |
| Câmera lenta (0.25x) | toggle | `Engine.time_scale` |
| Avançar 1 frame | action | Despausa, espera um `process_frame`, pausa de novo — só faz sentido com o jogo pausado |
| Recarregar cena | action | `get_tree().reload_current_scene()`, tirando a pausa antes |
| Sair do jogo | action, **pede confirmação** | `get_tree().quit()` — mata a sessão, ver ["Ação destrutiva"](#ação-destrutiva) |

"Avançar 1 frame" é a ferramenta certa para investigar um bug que dura um frame só: pause o jogo no instante
certo e avance de um em um.

---

## Overlay de desempenho (seção "Desempenho")

Um OSD no canto da tela, no espírito do **MSI Afterburner** e do **RivaTuner Statistics Server**: fonte
monoespaçada, fundo escuro translúcido, um mini-gráfico por métrica e cor por faixa (verde dentro do
orçamento, amarelo no limite, vermelho acima). Serve para responder de canto de olho a única pergunta que
importa quando o jogo engasga: **o gargalo é CPU ou GPU?**

**Abre com F2**, ou pelo interruptor na seção Desempenho. Os dois caminhos são o mesmo código, então nunca
divergem. O OSD é independente do menu — a ideia é justamente deixá-lo ligado enquanto se joga.

| Entrada | Tipo | O que faz |
| --- | --- | --- |
| Overlay de desempenho (F2) | toggle | Liga/desliga o OSD |
| Gráficos das métricas | toggle | Esconde os mini-gráficos, deixando só os números |
| Mover para o próximo canto | action | Gira entre os quatro cantos da tela |

### O que cada linha mede de verdade

| Linha | Fonte | Cuidado ao ler |
| --- | --- | --- |
| **Quadro** | Relógio de parede entre dois quadros | Medido em `Time.get_ticks_usec()`, não em `delta` — a câmera lenta da seção Sistema **não** distorce este número |
| **Quadro CPU** | Duração dos passos de física e de processamento da árvore + custo de CPU de submeter o desenho | Não inclui trabalho fora desses passos (threads de áudio, carregamento em background) |
| **Quadro GPU** | Tempo de GPU do viewport, medido pelo driver | Pode ficar em `--` para sempre se o renderizador/driver não reportar. Verificado funcionando em GL Compatibility + AMD |
| **Draw calls** | `Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME` | Conta o quadro inteiro, **incluindo os painéis de debug abertos** (o próprio OSD custa dezenas) |
| **Objetos** | `Performance.RENDER_TOTAL_OBJECTS_IN_FRAME` | Idem: com os painéis de debug abertos numa cena vazia já dá ~1000 |
| **RAM** | `OS.get_static_memory_usage()` | É a memória alocada **pela engine**, não o número do Gerenciador de Tarefas (que inclui binário, driver e afins e é sempre maior) |
| **Uso CPU** | `Quadro CPU ÷ Quadro` | Ocupação do orçamento do quadro, **não** a utilização do sistema |
| **Uso GPU** | `Quadro GPU ÷ Quadro` | Idem |

> **A diferença mais importante em relação ao Afterburner.** O Afterburner lê a utilização de CPU e GPU do
> driver (NVAPI/ADL) e mostra quanto do *hardware inteiro* está em uso. Um jogo não tem acesso a esse
> número. O que este OSD mostra é quanto do **orçamento do quadro** cada lado ocupou: `100%` significa que
> aquele lado não tem folga nenhuma e é o gargalo; `5%` significa que ele passou o quadro esperando (vsync,
> ou o outro lado). Para a pergunta "quem está me segurando", essa é a métrica útil — só não é a mesma
> métrica.
>
> Consequência prática: **sem vsync e sem limite de FPS, "Uso CPU" tende a 100%** porque o loop principal
> nunca dorme. Isso é o número correto, não um bug.

Uma linha mostra `--` enquanto nunca recebeu leitura válida. Preferimos isso a escrever `0,00`: zero é um
valor, e uma métrica que a plataforma não reporta não é zero.

### Draw calls e objetos: a métrica que mais importa em 2D

Num jogo 2D, o número que denuncia um problema de render quase nunca é o milissegundo — é a **contagem de
draw calls**. A engine junta (batching) vários sprites num único desenho enquanto eles compartilham textura
e material; qualquer troca no meio quebra o lote e vira um draw call novo. Cem sprites do mesmo atlas custam
um punhado de draw calls; os mesmos cem sprites com texturas soltas custam cem. O tempo de CPU e de GPU só
mostra o resultado disso depois que já está caro — a contagem mostra a causa.

**Como usar na prática:** deixe o OSD ligado, ande pelo jogo e olhe quando a linha **Draw calls** dá um
salto. O salto aponta o que entrou em cena — um efeito, uma UI, um tileset fora do atlas.

Os dois limites de cor (`draw_calls_budget`, `render_objects_budget` e seus críticos) são **chute inicial**
e existem para ser calibrados quando houver jogo de verdade. Os painéis de debug abertos entram na conta:
numa cena vazia com o OSD e o visualizador de log ligados, a medição deu ~49 draw calls e ~1000 objetos.

### Detalhe: como o tempo de CPU é medido

A engine expõe `Performance.TIME_PROCESS` e `TIME_PHYSICS_PROCESS`, mas eles **não servem** aqui: são
publicados uma vez por segundo e trazem o *pior* quadro do segundo. Num teste com vsync a 60 fps eles
reportavam 30 a 44 ms para quadros de 16,67 ms — usá-los deixava "Uso CPU" grudado em 100%.

O OSD mede sozinho: um nó auxiliar (`FrameClock`) roda com a prioridade mínima e o overlay com a máxima, em
ambos os passos. Como a ordem de processamento do Godot é global e ordenada por prioridade, a diferença
entre os dois instantes é o tempo que a árvore inteira levou naquele passo. A esse valor soma-se o custo de
CPU do render, que a `RenderingServer` mede por quadro.

Pelo mesmo motivo as porcentagens são calculadas **na razão entre as médias do intervalo**, e não quadro a
quadro: a razão por quadro e depois promediada infla o resultado, porque quadro curto leva a razão ao teto
de 100% e puxa a média para cima. No mesmo teste, a razão errada dava 55% e a certa 18%.

### Ajustes

Tudo o que é ajustável está exposto via `@export` em `DebugStatsOverlay.gd`, agrupado em **Layout**,
**Limites de alerta** e **Cores** — largura do painel, tamanho da fonte, intervalo de atualização e os
limites em que cada linha vira amarela e vermelha (`frame_budget_ms`, `ram_budget_mb`, etc.).

Os gráficos guardam ~3 s de histórico para as métricas medidas por quadro e ~15 s para as de uso (que ganham
um ponto por atualização, não por quadro), e crescem da direita para a esquerda como no RivaTuner. A escala
vertical de cada gráfico acompanha o próprio pico, com um piso para que ruído irrelevante não vire montanha.

### O preço de deixar ligado

Ligar o OSD pede à `RenderingServer` a medição de tempo de render do viewport, que custa uma consulta ao
driver por quadro. Por isso desligar o OSD **libera a cena** em vez de só escondê-la: um medidor invisível
que continua cobrando pela medição envenena exatamente o profiling que ele deveria ajudar.

---

## Achar uma ação

Um campo `Filtrar ações…` mora no topo do menu, entre o cabeçalho e o corpo — fora da área que é
remontada a cada seção trocada, então digitar nele nunca perde o foco nem o cursor entre caracteres.

Com texto no filtro, a coluna da direita para de mostrar só a seção selecionada e passa a mostrar os
resultados de **todas as seções**, cada um prefixado pela seção de origem (`Jogador · Dar ouro`); a coluna
da esquerda fica visualmente apagada enquanto isso. É proposital: o problema real de achar uma ação não é
"o que tem nesta seção", é "não lembro em que seção está 'Dar item'" — o modelo é o de uma command palette,
não o de um filtro por categoria.

- **Casa sem acento e sem diferenciar maiúsculas.** `camera` acha "Câmera lenta (0.25x)" — os rótulos deste
  projeto são em português, e ninguém para pra compor o circunflexo no meio de uma investigação.
- **Pontuação por qualidade do match**, não só por "contém": igual > começa com > início de palavra >
  substring qualquer > subsequência espalhada. Empate desempata pela ordem de registro.
- Limpar o campo devolve a seção que estava selecionada antes de filtrar.
- Zero resultados mostra `Nenhuma ação corresponde a "..."`, nunca uma coluna vazia sem explicação.
- O cabeçalho ganha a contagem enquanto filtra (`3 de 27 ações`).
- **Esc** com texto no campo limpa o filtro; **Esc** com o campo vazio fecha o menu.
- Por padrão o campo **não** rouba o teclado ao abrir o menu (metade do debug é olhar o jogo se mexendo);
  quem quer digitar clica nele. Dá pra mudar isso via `@export var focus_search_on_open` no overlay.

O casador (`DebugTextFilter`, em `scripts/debug/DebugTextFilter.gd`) é o mesmo usado pelo autocomplete do
console — um casador só, dois front-ends.

---

## Ação destrutiva

Botões que exigem confirmação nascem com um **`⚠ `** no próprio texto — esse marcador importa mais que o
diálogo em si: o diálogo é a rede de segurança, o marcador é o aviso que aparece **antes** do clique, e quem
já sabe o que vai fazer confirma no automático de qualquer forma.

**O critério que decide se uma ação pede confirmação:**

> Confirmação custa atrito em **todo** clique para proteger contra **um** clique errado. Vale quando desfazer
> é caro ou impossível; não vale quando refazer é barato.

Não é sobre o quão "grave" a ação parece — é sobre reversibilidade. "Pausar jogo" é trivial de reverter
(clique de novo) mesmo sendo usado o tempo todo; "Sair do jogo" mata a sessão de investigação inteira e não
tem desfazer. Use isto como regra de revisão de PR: **a ação destrutiva foi marcada por reversibilidade, não
por importância?**

```gdscript
DebugMenu.register_action(&"Save", "Resetar save", _reset_save, true)
```

- `register_toggle()` **não** recebe este parâmetro de propósito: um interruptor é reversível por definição.
  Se um toggle parece precisar de confirmação, ele não era um toggle.
- O diálogo (`ConfirmationDialog`) é único por overlay e reusado por toda entrada — clicar em várias ações
  destrutivas em sequência não acumula conexões nem abre um diálogo por clique.
- **O console (F1) não pede confirmação nenhuma.** Digitar o comando inteiro já é o ato deliberado que a
  confirmação existe para exigir; a confirmação protege contra o clique errado numa lista de botões
  vizinhos, situação que o console não tem.

---

## Console (F1)

Um campo de comando ancorado no rodapé da tela (o menu e o overlay de desempenho ocupam o topo), para quem
já sabe o nome da ação e digitar é mais rápido que seção → item. **Não tem registro próprio**: os comandos
do console **são** as entradas do `DebugMenu` — registrar uma ação passa a dar as duas coisas de uma vez.

### O id do comando

Cada entrada ganha um `command` derivado automaticamente no registro:

```
seção normalizada + "." + rótulo normalizado (sem acento, minúsculas, sufixo entre parênteses cortado)

"Dar 100 de ouro" em &"Jogador"  →  jogador.dar_100_de_ouro
"Overlay de desempenho (F2)"     →  desempenho.overlay_de_desempenho
```

> **O preço:** renomear o rótulo renomeia o comando, e quebra a memória muscular de quem digitava o antigo.
> É o custo de não obrigar todo call site a inventar um id à mão.

O console aceita o **sufixo mais curto que for único**: se só uma seção tem `dar_ouro`, digitar `dar_ouro`
basta. Havendo ambiguidade entre seções, ele lista os candidatos e não executa nada.

### Digitando um comando

```
> ajuda
sistema.pausar_jogo
sistema.sair_do_jogo
jogador.dar_ouro
...

> jogador.dar_ouro 100
"jogador.dar_ouro" executado.

> jogador.dar_ouro muito
Erro: "muito" não é um int válido para <quantidade>.
Uso: jogador.dar_ouro <quantidade:int>
```

A linha de uso (`Uso: ...`) sai direto dos `DebugParam` declarados no registro — não tem como ficar
desatualizada, porque é a mesma declaração que o menu usa para desenhar o widget.

- **Aspas** agrupam um valor com espaço: `dar_item "semente de trigo" 5`.
- **Tab** completa pelo prefixo comum e cicla entre os candidatos a cada Tab seguinte — na posição de
  comando, contra a lista de comandos; na posição de argumento, contra as sugestões daquele `DebugParam`
  (ex.: `dar_item <Tab>` lista os ids de item que existem *agora*, vindos do `Callable` de sugestões).
- **↑ / ↓** navegam um histórico circular guardado no `DebugMenu` (sobrevive a fechar o console).
- `ajuda` sozinho lista todos os comandos; `ajuda <texto>` filtra pelo mesmo casador do menu; `ajuda
  <comando>` mostra a linha de uso de um comando específico.
- `secoes` lista as seções; `limpar` limpa a saída do console.
- Escape hatch: com o prefixo `>` e `@export var allow_expressions = true` no console, a linha vira uma
  `Expression` do Godot avaliada livremente (`> get_tree().paused = true`). **Desligado por padrão** — ver
  `SPEC.md` §2.4 para os riscos de segurança e arquitetura de deixar isso ser o caminho principal.

---

## Eventos

A seção **"Eventos"** aparece sozinha, sem ninguém registrar nada: o `EventBusLogger` (que já varre
`Script.get_script_signal_list()` para se instrumentar) pendura um `register_input()` por `signal` declarado
no `EventBus`, com os parâmetros derivados dos tipos declarados no próprio sinal. Um evento novo aparece no
menu **e** no console (`eventos.emitir_<evento> <args>`) no mesmo commit que declara o `signal` — sem código
específico de console, porque passa pelo caminho genérico de registro.

**Mapeamento de tipos:** `int` → `INT`, `float` → `FLOAT`, `String`/`StringName` → `STRING`, `bool` →
`BOOL`. Qualquer outro tipo — em particular uma classe de payload, obrigatória a partir de quatro parâmetros
por `docs/event_bus.md` — não tem como virar um `DebugParam`, então esse evento **não** ganha botão. Ele gera
um `push_warning` no primeiro registro, e continua acessível do jeito de sempre: uma ação registrada à mão
no sistema que sabe montar o payload.

"Sistema" continua sendo sempre a primeira seção: o registro dos eventos é adiado (`call_deferred()`) porque
o `EventBus` é o primeiro Autoload da lista e o `DebugMenu` ainda não existe quando o `_ready()` do bus roda —
o adiamento cai no fim do frame, depois de `DebugMenu._ready()` já ter registrado "Sistema" e "Desempenho".

---

## Erros comuns

**Registrar fora do `_ready()`.** Registrar dentro de `_process()` não duplica o botão (o par seção/rótulo
substitui), mas reescreve a entrada a cada frame à toa. Registre uma vez, no `_ready()`.

**Esquecer o guard de debug.** `register_action()`/`register_toggle()` já não fazem nada em build de release
— mas sem o guard `if OS.has_feature("editor") or OS.is_debug_build():` no call site, o Guideline de código
`[DEBUG]` não é cumprido, e é isso que a revisão de PR cobra.

**Registrar uma ação que depende de nó de outra cena.** Guarde a referência do próprio nó dono do
`Callable`, nunca de um nó externo capturado por closure. Se o dono sair da árvore, o `Callable` para de ser
válido e a entrada some sozinha (ver "Callable morto" abaixo); se for o nó externo que sai, o clique quebra
sem aviso.

---

## Casos que aparecem na prática

**Minha ação precisa de um argumento de entrada** (dar uma quantidade de ouro, um id de item). Use
`register_input()` com um `DebugParam` por argumento — o menu desenha um campo por parâmetro e só dispara a
ação depois de preenchidos; o console ganha o mesmo comando de graça:

```gdscript
DebugMenu.register_input(&"Jogador", "Dar ouro", _give_gold, [
	DebugParam.int_value("quantidade", 100, 1, 9999)
])
```

`Callable.bind()` continua existindo e continua certo — mas para amarrar **contexto** (qual inimigo, qual
instância), não um **valor de entrada** que o operador deveria poder escolher a cada clique:

```gdscript
DebugMenu.register_action(&"Inimigos", "Matar", _die.bind(self))
```

Funciona igual num toggle: `on_changed.bind(contexto)` recebe `novo_valor` primeiro e o valor do `bind`
depois, na ordem normal do GDScript.

**O toggle não nasce marcado do jeito que o sistema já está.** Passe o valor atual em `initial` na hora de
registrar:

```gdscript
DebugMenu.register_toggle(&"Jogador", "Invencível", _set_invincible, _is_invincible)
```

Como o registro roda de novo a cada `_ready()`, o toggle nasce sincronizado toda vez que a cena carrega. Se
algo mudar `_is_invincible` por fora do menu depois disso, o toggle desencontra do valor real — abrir e
fechar o menu não resolve, porque isso só relê o registro, sem chamar `_ready()` de ninguém. Só volta a
sincronizar quando o sistema registrar de novo (recarregar a cena, por exemplo).

**Duas partes diferentes do jogo podem registrar na mesma seção.** Seção é só uma `StringName` usada como
chave; nada impede um script de `Player.gd` e outro de `PlayerInventory.gd` registrarem os dois em
`&"Jogador"`. As entradas se somam na ordem em que cada uma registrou primeiro.

**Não existe `DebugMenu.open()` público hoje**, só `close_menu()`/`close_console()` (usados pelo Esc do
filtro e por fechar o console por código) — abrir continua sendo só pela tecla. Se algum dia precisar abrir
por código (por exemplo, num teste automatizado), a lógica já está isolada em `_toggle_menu()`/
`_toggle_console()`; expor uma função pública em cima delas é uma mudança pequena.

---

## Detalhe: `Callable` morto depois de troca de cena

O sistema que registrou a ação vive numa cena; a cena descarrega; o `Callable` aponta para um nó liberado.
Ninguém precisa desregistrar — a limpeza acontece sozinha na próxima vez que o registro é lido (abertura do
menu), removendo entradas cujo `Callable` não é mais válido.

---

## Antes de abrir PR

O que o revisor procura:

- A ação está registrada no `_ready()`, sob o guard `OS.has_feature("editor") or OS.is_debug_build()`?
- O rótulo é claro e a seção faz sentido (nasce uma seção nova só quando a existente não serve)?
- O `Callable` pertence ao próprio nó que registrou, não a uma referência externa capturada por closure?
- Se for um toggle, o `on_changed` só aplica o estado — quem lê o estado "de verdade" continua sendo o
  sistema, o menu só guarda a cópia exibida?
- A ação de debug não é o único caminho para o comportamento (não é feature disfarçada de debug)?
- **A ação com parâmetro declara tipos e faixas via `DebugParam`/`register_input`, em vez de um botão fixo
  por valor (`.bind(100)`, `.bind(200)`, `.bind(300)`)?**
- **A ação destrutiva foi marcada com `requires_confirmation = true` por reversibilidade, não por
  importância?** (ver ["Ação destrutiva"](#ação-destrutiva))
