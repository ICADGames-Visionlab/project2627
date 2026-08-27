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

> **Estado atual:** o projeto ainda não tem gameplay, então só existe a seção **Sistema** (ver abaixo), que
> não depende de nenhum sistema de jogo. Ela também serve de exemplo vivo de como registrar.

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
