# Debug Menu (Mod Menu)

Uma tela, aberta com o jogo rodando, onde qualquer ação de debug fica a um clique — sem recompilar, sem
console, sem mexer em código.

---

## A ideia

Qualquer sistema pode pendurar uma ação no menu com uma chamada só, no próprio `_ready()`:

```gdscript
DebugMenu.register_action(&"Jogador", "Matar", _die)
```

O menu **se monta sozinho** a partir do que foi registrado — ninguém edita a cena para adicionar um botão.
`DebugMenu` (Autoload) guarda o registro e escuta a tecla de abrir; `DebugMenuOverlay` (cena instanciada sob
demanda) desenha os botões e chama o `Callable` no clique. Ninguém precisa desregistrar: um `Callable` cujo
dono já saiu da árvore some sozinho na próxima abertura do menu.

> **Estado atual:** o projeto ainda não tem gameplay, então só existem as seções **Sistema** e
> **Desempenho** (ver abaixo), que não dependem de nenhum sistema de jogo. Elas também servem de exemplo
> vivo de como registrar.

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
| **F2** | Overlay de desempenho (ver [seção "Desempenho"](#overlay-de-desempenho-seção-desempenho)) |
| **F3** | Overlay do EventBus (ver `docs/event_bus.md`) |
| **F4** | Este menu |

Todas caem para a tecla direta se a ação correspondente sumir do Input Map, então uma configuração quebrada
não deixa nenhuma ferramenta inacessível.

---

## Registrar uma ação

Duas funções, chamadas de dentro do `_ready()` do sistema que tem o que depurar, sob o guard de debug:

```gdscript
func _ready() -> void:
	if OS.has_feature("editor") or OS.is_debug_build():
		# [DEBUG] Ações deste sistema no menu de debug.
		DebugMenu.register_action(&"Jogador", "Matar", _die)
		DebugMenu.register_toggle(&"Jogador", "Invencível", _set_invincible)


# Liga/desliga a invencibilidade. Recebe o estado novo do interruptor do menu de debug.
func _set_invincible(enabled: bool) -> void:
	_is_invincible = enabled
```

- `register_action(section, label, action)` — um botão que dispara `action.call()` no clique.
- `register_toggle(section, label, on_changed, initial)` — um interruptor. O **menu** guarda o `bool` e
  chama `on_changed(novo_valor)` quando ele muda. Se o sistema alterar o valor por outro caminho, o menu
  desencontra até ser reaberto — não há getter.

**Criar uma seção nova é grátis**: ela nasce sozinha na primeira vez que algo é registrado nela, na ordem em
que as seções aparecem pela primeira vez. Não existe enum nem registro prévio de seção.

**Registrar de novo com o mesmo par (seção, rótulo) substitui a entrada anterior** em vez de duplicar — é o
que evita botão repetido quando a cena que registra recarrega.

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
| Sair do jogo | action | `get_tree().quit()` |

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

**Minha ação precisa de um argumento** (matar um inimigo específico, dar uma quantidade de item). O menu
sempre chama `action.call()` sem argumento nenhum — quem entrega o valor é o `Callable.bind()` do próprio
GDScript:

```gdscript
DebugMenu.register_action(&"Jogador", "Dar 100 de ouro", _give_gold.bind(100))
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

**Não existe `DebugMenu.open()` ou `.close()` público hoje** — a única entrada é a tecla F4. Se algum dia
precisar abrir o menu por código (por exemplo, num teste automatizado), a lógica já está isolada em
`_toggle_menu()`; expor uma função pública em cima dela é uma mudança pequena.

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
