# Sistema de Tempo

Como o jogo conta as horas, os dias e o dia da semana — e como usar isso sem quebrar nada.

---

## A ideia

O tempo corre sozinho enquanto o jogador joga. O dia começa numa hora fixa e tem um **horário
máximo**: o jogador não madruga, apaga quando o tempo acaba. Quanto o dia dura — em horas de jogo
e em minutos reais — é balanceamento, ajustável pelo design sem tocar em código.

Os valores de agora aparecem no console toda vez que o jogo abre, e no campo `resumo` do
`TimeSettings.tres`:

```
[GameClock] - Relógio pronto e parado. Dia jogável: 06:00 -> 22:00 (16.0 h de jogo) |
Duração real: 5.0 min reais por dia | 1 h de jogo = 19 s reais · 1 min de jogo = 0.31 s reais
```

Todo o estado do sistema é **um número inteiro**: `total_minutes`, os minutos de jogo desde o começo
da partida. Hora, dia, dia da semana e semana são divisões dele. Não existe um contador de horas,
outro de dias e outro de semanas — seriam três lugares pra dessincronizar.

```gdscript
GameClock.time.get_hour()        # 14
GameClock.time.get_minute()      # 5
GameClock.time.get_day()         # 3
GameClock.time.get_weekday()     # 2  (0 = segunda)
GameClock.time.format_clock()    # "14:05"
GameClock.time.format_weekday()  # "Quarta"
```

> ⚠️ **O relógio não corre sempre.** Ele é um Autoload, mas nasce parado: não conta no menu
> principal, não conta com o jogo pausado e não conta durante um diálogo. Ver
> [As três portas](#as-três-portas).

---

## Os arquivos

| Arquivo | O que faz |
|---|---|
| `resources/TimeSettings.tres` | **O arquivo do design.** Hora de acordar, duração do dia, ritmo. |
| `scripts/time/TimeSettings.gd` | O script por trás do `.tres`. Só balanceamento e contas derivadas. |
| `scripts/time/GameTime.gd` | O calendário. Converte `total_minutes` em hora, dia e dia da semana. Não é Node, não emite nada. |
| `scripts/singletons/GameClock.gd` | Autoload. Faz o tempo andar, corta no horário máximo, anuncia no EventBus. |
| `scripts/world/GameSession.gd` | Nó na cena de jogo. Liga o relógio ao entrar, desliga ao sair. |
| `scripts/ui/ClockHud.gd` | Mostra a hora na tela. **Provisório** — ver [O que ainda falta](#o-que-ainda-falta). |

Os eventos ficam no `EventBus.gd`, seção "Tempo", como qualquer outro evento do projeto.

---

## Como reagir ao tempo

**Escute o EventBus. Nunca leia o relógio em `_process`.** Esse é o único erro que custa
performance de verdade aqui: o sistema foi desenhado pra avisar você, e ler todo frame joga isso
fora.

```gdscript
# HUD, NPC, loja, qualquer coisa que precise reagir à passagem do tempo.
func _ready() -> void:
	EventBus.hour_changed.connect(_on_hour_changed)

# Abre a loja às 9 e fecha às 18.
func _on_hour_changed(hour: int) -> void:
	is_open = hour >= 9 and hour < 18
```

### Os eventos

| Evento | Quando sai |
|---|---|
| `time_changed(total_minutes: int)` | A cada 10 minutos de jogo, e sempre que o tempo é escrito de uma vez (começo de sessão, save carregado, dia novo) |
| `hour_changed(hour: int)` | A hora virou (13:59 → 14:00) |
| `day_changed(day: int)` | O dia virou — **ao acordar**, não à meia-noite |
| `day_ended(day: int, reason: int)` | O jogador dormiu ou apagou no horário máximo |

**Por que `time_changed` só sai de 10 em 10 minutos:** por dentro o relógio anda de minuto em
minuto, mas anunciar todo minuto seriam 1440 avisos por dia pra cidade inteira, e nenhum HUD mostra
diferença. Se você precisa de precisão de minuto (um prazo, um cronômetro), leia
`GameClock.time.total_minutes` direto quando precisar, em vez de pedir um evento por minuto.

### Comparar prazos é aritmética

Como o tempo é um inteiro, prazo é conta:

```gdscript
# "Essa encomenda vence daqui a 2 dias, ao meio-dia."
var prazo: int = GameClock.time.total_minutes + (2 * GameTime.MINUTES_PER_DAY)

func _on_time_changed(total_minutes: int) -> void:
	if total_minutes >= prazo:
		_falhar_encomenda()
```

---

## As três portas

O relógio é Autoload — existe desde que o jogo abre, inclusive no menu principal. Ele não conta
porque três condições precisam estar abertas ao mesmo tempo:

| Porta | Quem controla | Fecha quando |
|---|---|---|
| **Árvore ativa** | `process_mode = PAUSABLE` | `get_tree().paused` — menu de pausa, toggle do F4 |
| **Sessão ativa** | `start_session()` / `stop_session()` | Menu principal, tela de loading, game over |
| **Sem freeze** | `freeze()` / `unfreeze()` | Diálogo, cutscene, troca de cena, fim do dia |

A primeira é de graça: Autoload é um nó filho do root e herda o estado de pausa, então pausar o
jogo já para o relógio. **Não marque o GameClock como `PROCESS_MODE_ALWAYS`** — é assim que o tempo
começa a passar dentro do menu de pausa.

A segunda existe porque o menu principal é uma *cena*, não uma pausa: ali a árvore não está
pausada, e sem essa porta o tempo passaria enquanto o jogador escolhe o slot de save. Quem abre é
o nó `GameSession`, que mora na cena de jogo:

```gdscript
# GameSession.gd, resumido
func _ready() -> void:
	GameClock.start_session.call_deferred()

func _exit_tree() -> void:
	GameClock.stop_session()
```

> ⚠️ O `call_deferred` não é firula. `start_session()` anuncia `time_changed`, e o `_ready()` dos
> irmãos que escutam o relógio pode ainda não ter rodado — `_ready` corre na ordem da árvore.
> Adiando pro fim do frame, a cena inteira já está montada e conectada.

**Se você criar uma nova cena de gameplay, coloque um nó com `GameSession.gd` nela.** Sem isso o
relógio não anda. Como efeito colateral bem-vindo, rodar a cena direto pelo editor (F6) também
liga o relógio, sem precisar passar pelo menu.

### Segurar o tempo durante um diálogo

```gdscript
func abrir_dialogo() -> void:
	GameClock.freeze(&"dialogo")
	# ... mostra a caixa de diálogo ...

func fechar_dialogo() -> void:
	GameClock.unfreeze(&"dialogo")
```

O freeze é uma **pilha de motivos**, não um `bool`. Diálogo dentro de cutscene é normal, e com um
`bool` o primeiro a terminar descongelaria o relógio no meio do outro. Cada sistema solta só o
motivo que ele mesmo registrou. O nome é livre, mas use sempre o mesmo string pro mesmo sistema.

Motivos já usados pelo projeto: `&"transicao"` (GameManager, durante a troca de cena) e
`&"fim_do_dia"` (GameClock).

---

## O dia

```
 wake_hour                                     limite            wake_hour
  06:00                                        22:00               06:00
    |---------- playable_hours (16 h = 960 min) ---|                 |
    acorda                                   apaga        dia seguinte
                                                 '----- pulado ------'
```

*(O desenho usa os valores de hoje; as duas pontas saem de `wake_hour` e `playable_hours`.)*

**A data vira ao acordar, não à meia-noite.** Se virasse à meia-noite, o HUD trocaria de "Dia 3"
para "Dia 4" com o jogador ainda acordado, e os NPCs receberiam `day_changed` duas horas antes do
dia realmente acabar. Por isso o minuto 0 de cada dia é a hora de acordar:

```gdscript
GameClock.time.total_minutes = 1080   # 18 h depois de acordar
GameClock.time.get_hour()             # 0   → meia-noite
GameClock.time.get_day()              # 1   → ainda é o dia 1
```

Um dia de calendário continua tendo 1440 minutos, mesmo que só 1200 sejam jogáveis. As 4 horas
dormidas existem em `total_minutes` — elas só não são vividas. É isso que mantém a conta de dia da
semana exata sem nenhum caso especial.

### Fim do dia

Dormir e apagar são o mesmo caminho, mudando só o motivo:

```gdscript
GameClock.end_day()                              # dormiu (SLEPT)
GameClock.end_day(GameClock.DayEndReason.SLEPT)  # idem, explícito
# O horário máximo dispara COLLAPSED sozinho, de dentro do advance().
```

Os dois congelam o relógio e emitem `day_ended`. **O relógio não conhece tela**: o fade, a tela de
resumo e o save automático são de quem escuta. E o relógio fica parado até alguém chamar
`start_next_day()`:

```gdscript
func _on_day_ended(day: int, reason: int) -> void:
	await _mostrar_resumo_do_dia(day)     # fade, tela de resumo, save...
	GameClock.start_next_day()            # sem isso, o jogo trava com o tempo parado
```

> ⚠️ **`start_next_day()` não é `advance()`.** As horas dormidas são puladas, não vividas: o
> relógio escreve direto o minuto 0 do dia seguinte. Se você adiantar com `advance()` até o
> amanhecer, o jogo dispara viradas de hora que ninguém viveu e bate no horário máximo de novo no
> meio do caminho.

Hoje quem responde ao `day_ended` é o `GameSession`, com uma espera de 1 segundo e um print. É
provisório e está marcado como tal no arquivo — a sequência de verdade entra ali.

---

## Ajustar a duração do dia

Abra `resources/TimeSettings.tres` no Inspector. São três campos:

| Campo | O que é |
|---|---|
| `wake_hour` | Hora em que o jogador acorda. É o minuto 0 do dia. |
| `playable_hours` | Quantas horas de jogo até apagar. O horário do limite é derivado daqui. |
| `real_minutes_per_day` | **Quanto tempo real dura um dia jogável inteiro.** |

Não existe campo de aviso de fim de dia: quem quiser avisar o jogador escuta `time_changed` e
compara com `GameClock.get_minutes_left()`.

O campo `resumo`, cinza e só leitura, se reescreve a cada mudança e diz o que a combinação produz:

```
Dia jogável: 06:00 -> 02:00 (20.0 h de jogo)
Duração real: 15.0 min reais por dia
1 h de jogo = 45 s reais  ·  1 min de jogo = 0.75 s reais
```

Não existe campo pra "hora do limite" nem pra "velocidade do relógio": os dois são derivados. Dois
campos pra mesma coisa é o jeito garantido de eles divergirem no primeiro ajuste.

Não precisa fazer essa conta na mão — o `resumo` já traduz. Mas, pra referência, é ela:

```
segundos reais por 1 h de jogo = (real_minutes_per_day × 60) ÷ playable_hours
```

**Duplicar o `.tres` cria um preset** ("playtest rápido", "ritmo final") sem tocar em código: basta
apontar `GameClock.SETTINGS_PATH` para o novo arquivo.

---

## Debug

Seção **"Tempo"** no menu (F4) e no console (F1):

| Entrada | O que faz |
|---|---|
| Avançar minutos | Adianta o relógio. Respeita o horário máximo — avançar 1440 para no limite |
| Dormir (ir para o dia seguinte) | Fecha o dia como se o jogador tivesse dormido |
| Mostrar data e hora | Imprime dia, dia da semana, semana, hora e quanto falta pro fim do dia |
| Congelar relógio | Freeze com o motivo `&"debug"`, sem atropelar os motivos de gameplay |
| Minutos reais por dia | Ajusta o ritmo com o jogo rodando |

O último é o que mais paga no dia a dia: dá pra girar o valor jogando, sentir o ritmo, e só depois
escrever o número no `.tres`. **É a mesma unidade do Inspector de propósito** — o número que você
achou aqui é o número que você digita lá.

### Conferir se o calendário está certo

Os valores de borda, pra bater o olho depois de mexer em qualquer conta:

Valem para `wake_hour = 6`; o dia da semana e a virada de dia não dependem do balanceamento.

| `total_minutes` | Resultado esperado |
|---|---|
| 0 | Dia 1, Segunda, 06:00 |
| 1080 | Dia 1 (**ainda**), Segunda, 00:00 |
| 1439 | Dia 1, 05:59 — o último minuto do dia de calendário |
| 1440 | Dia 2, Terça, 06:00 |
| 10080 | Dia 8, Segunda de novo, semana 2 |

`GameTime` não é Node e não depende de nada: dá pra instanciar e conferir sem rodar o jogo.

---

## Save

O relógio não salva sozinho — ele entrega e recebe o valor:

```gdscript
# Ao salvar
var data: Dictionary = {}
GameClock.write_to_save(data)          # data["total_minutes"] = 4380
SaveManager.save_game(data, slot)

# Ao carregar
var data: Dictionary = SaveManager.load_game(slot)
GameClock.read_from_save(data)
GameClock.start_session()
```

> ⚠️ **Por que existe um `int()` dentro do `read_from_save`.** O `SaveManager` grava em JSON, e
> JSON não tem tipo inteiro: tudo volta como `float`. `4380` salvo volta como `4380.0`, e um
> `float` ali quebraria todas as divisões do calendário **sem nenhum erro no console**. Se você
> escrever outro sistema que salva número inteiro, lembre do mesmo cuidado.

Salve apenas `total_minutes`. Hora e dia são derivados — salvar os três é criar a chance de eles
voltarem inconsistentes entre si.

---

## O que ainda falta

Coisas conhecidas, pra ninguém "descobrir" de novo:

- **O HUD é provisório.** `ClockHud` é um Label num canto, sem arte. Quando o HUD de verdade
  existir, o que importa copiar de lá é o jeito de ler o tempo (escutar evento, usar `tr()`), não
  o visual.
- **`hour_changed` ainda não tem ouvinte**, então o EventBus avisa uma vez no console que ele foi
  emitido sem ninguém escutando. Isso é a instrumentação funcionando, não um bug. O candidato
  natural era a rotina de NPC, mas ela precisa de granularidade mais fina que a hora e escuta
  `time_changed` (ver `docs/sistema_de_npc.md`); o primeiro ouvinte será quem reagir à hora cheia —
  som ambiente, loja abrindo e fechando.
- **O save não está plugado no fluxo.** As funções existem e estão testadas; falta chamá-las de
  dentro do fluxo de save/carga quando ele deixar de ser teste.
- **A sequência de fim de dia é um print.** Ver [Fim do dia](#fim-do-dia).

---

## Armadilhas

Checklist rápido pra revisão de PR que mexa em tempo:

- [ ] Ninguém lê o relógio em `_process` — reagir é escutando evento.
- [ ] Nenhum NPC ou sistema usa `Timer` próprio pra marcar hora de jogo. `Timer` não congela junto
      com o relógio, não acelera junto e não sobrevive a um save.
- [ ] Nenhum `freeze()` sem o `unfreeze()` correspondente (e com o mesmo motivo).
- [ ] Nenhum `advance()` usado pra pular a noite — isso é `start_next_day()`.
- [ ] Nenhum campo novo de hora/dia guardado em paralelo ao `total_minutes`.
- [ ] `Engine.time_scale` não foi usado como velocidade de jogo — ela acelera animação, física e
      áudio junto. Use `GameClock.speed_multiplier`.
- [ ] Nenhum texto de data ou hora hardcoded — as chaves estão no CSV (`TIME_FORMAT`, `DAY_LABEL`,
      `WEEKDAY_MON`…).
- [ ] O `GameClock` continua `PROCESS_MODE_PAUSABLE`.
