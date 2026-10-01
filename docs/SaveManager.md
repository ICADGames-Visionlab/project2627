# SaveManager

Como o jogo guarda e recupera a partida, e como um sistema novo entra no save sem mexer no núcleo.

---

## A ideia

O `SaveManager` (Autoload, o primeiro da lista) é o **dono da partida ativa**: sabe qual slot está
aberto, junta o que cada sistema tem a guardar e é o **único** que escreve e lê os arquivos de save.

```
 Quem abre e fecha a partida                   Quem tem fatos a guardar (participantes)
 ---------------------------                   ----------------------------------------
 SaveSlotMenu: start_new_game,                 GameClock          "clock"
   continue_game, delete_slot                  InsightJournal     "insights"
 PauseMenu: end_session                        ProfilingJournal   "profiling"
 Janela fechando: save_now                     DialogueState      "dialogue"
 EventBus.day_changed: request_save            GameSession        "world" (+ Player)
            |                                              |
            |        register_participant(chave, to_dict, from_dict)
            |        request_save() a cada mudança de fato
            v                                              v
        +---------------------------- SaveManager ----------------------------+
        |  slot ativo  |  seções por chave  |  1 escrita por frame no máximo  |
        +----------------------------------+----------------------------------+
                                           |  .tmp -> (principal -> .bak) -> principal
                                           v
         user://save1.json, save2.json, save3.json (+ .bak, .tmp)
```

Três ideias sustentam tudo:

1. **Save é retrato de fatos.** Cada sistema devolve um `Dictionary` de ids e números. Nada de texto
   traduzido, objeto da engine ou valor que dá para recalcular (o dia sai do `total_minutes`).
2. **Quem muda estado só pede.** O sistema chama `request_save()`; o `SaveManager` junta todos os
   pedidos do frame e grava **uma vez**. Ninguém escreve arquivo.
3. **`from_dict({})` é novo jogo.** Todo participante sabe começar do zero quando recebe um
   `Dictionary` vazio. É assim que "Novo jogo" zera a memória inteira sem nenhum caso especial.

**Sem partida ativa, nada grava.** No menu principal e numa cena rodada direto pelo editor, não existe
slot: `request_save()` não faz nada e `save_now()` devolve `ERR_UNAVAILABLE`. Nenhum arquivo nasce.

---

## Ciclo da partida

| O que | Chamada | Quem chama |
| --- | --- | --- |
| Novo jogo | `start_new_game(slot)` | `SaveSlotMenu` (depois de confirmar, se o slot tem jogo); debug |
| Continuar | `continue_game(slot)` | `SaveSlotMenu`; debug |
| Encerrar | `end_session()` | `PauseMenu` ("Salvar e sair para o menu"); `MainMenu._ready()` |
| Fechar a janela | `save_now()` | O próprio `SaveManager`, em `NOTIFICATION_WM_CLOSE_REQUEST` |
| Apagar | `delete_slot(slot)` | `SaveSlotMenu` (depois de confirmar); debug |

O caminho de quem joga: `MainMenu` → `SaveSlotMenu` → `start_new_game`/`continue_game` → o menu troca
para a cena do local salvo (`GameSession.scene_path_for(...)`). O `SaveManager` nunca troca cena.

- **`start_new_game(slot)`** fecha a partida anterior gravando, apaga os três arquivos do slot, entrega
  `{}` a todos os participantes e grava na hora. Recusa slot `DAMAGED` e `NEWER`. A confirmação de
  "substituir a partida?" é da tela, antes de chamar.
- **`continue_game(slot)`** lê com fallback, migra o formato antigo e entrega cada seção ao seu dono, a
  **todos** os registrados (nada da partida anterior sobra na memória). Não grava: o disco só muda na
  próxima gravação.
- **`end_session()`** grava e fecha a partida. Sem partida ativa não faz nada, por isso o `MainMenu`
  chama no `_ready()` como rede de segurança: qualquer caminho de volta ao menu grava e fecha.
- **Fechar a janela** grava de forma síncrona antes de a Godot sair. `get_tree().quit()` **não** emite essa
  notificação, então todo botão de sair do jogo passa por `end_session()` antes (só o "Sair do jogo" do
  debug escapa, e ele não é do jogador).
- **`delete_slot(slot)`** apaga principal, `.tmp` e `.bak`. Se o slot é a partida ativa, fecha a sessão
  **sem gravar**, senão o próximo flush recriaria o que o jogador acabou de apagar. Recusa `NEWER`.

Retornos (`Error`): `OK`; `ERR_PARAMETER_RANGE_ERROR` (slot fora de 1..3); `ERR_FILE_NOT_FOUND` (continuar
slot vazio); `ERR_FILE_CORRUPT` (danificado); `ERR_FILE_UNRECOGNIZED` (versão mais nova); `ERR_UNAVAILABLE`
(`save_now` sem partida); ou o erro do disco. `start_new_game` devolve `OK` sempre que a partida abriu,
mesmo se a primeira gravação falhar: o indicador já avisou e a próxima gravação tenta de novo.

Consultas que não mexem no disco: `get_slot_info(slot) -> SaveSlotInfo`, `has_any_save()`,
`has_active_session()`, `get_active_slot()`, `get_section(key)` (cópia da seção da partida ativa).

### O que dispara uma gravação

| Gatilho | Quem | Como |
| --- | --- | --- |
| Mudança de fato (insight lido, escolha, palavra nova) | O sistema dono | `request_save()` |
| Virada de dia (`EventBus.day_changed`) | O próprio `SaveManager` escuta | `request_save()` |
| "Salvar e sair para o menu" | `PauseMenu` | `end_session()` |
| Fechar a janela (X, Alt+F4) | `SaveManager` | `save_now()` |
| Debug "Salvar agora" | Menu de debug | `save_now()` |

`request_save()` só marca o pedido. A escrita acontece no começo do **frame seguinte**, então cinco
pedidos do mesmo gesto (ler um insight marca o lido e concede uma flag) viram **uma** escrita. Durante
troca de cena (`GameManager.in_transition`) ela espera o fade acabar: no meio da troca a cena velha já
saiu e a nova ainda não se registrou. `save_now()` grava já e cancela o pedido pendente.

Toda gravação bem-sucedida mostra "Jogo salvo" por 1,5 s no canto inferior direito. Se falhar (disco cheio,
sem permissão), mostra "Falha ao salvar; o save anterior ficou" por 6 s: o save anterior está intacto, o
jogo segue e a próxima gravação tenta de novo.

### Posição e hora: o último valor seguro

Fatos gravam a qualquer instante. Só **posição** e **hora** pedem cuidado, e cada dono guarda o seu
último valor seguro; o `SaveManager` não consulta ninguém:

- **Posição.** O `Player` só atualiza `_last_safe_position` com o jogador no controle, acordado, fora de
  conversa e de troca de cena. Fechar o jogo no meio de um diálogo grava os fatos já consumados e a
  posição de antes da abordagem. Na volta, a posição é validada contra o mapa (se caiu dentro de uma
  parede, o jogador volta ao ponto de partida).
- **Hora.** No sonho o `GameClock` grava o minuto **em que o dia fechou**, não o do sonho (03:00 fica
  além do horário máximo). Continuar depois de fechar o jogo no sonho = acordado no dia N, na hora em que
  deitou, com as palavras do sonho já no glossário.

---

## Como um sistema novo entra no save

Sem mexer no `SaveManager`. Cinco passos:

1. **Escolha uma chave** `snake_case`, única (`"reputation"`). Ela vira o nome da seção no arquivo e é
   contrato: renomear pede migração (ver [Migração](#migração)).
2. **Escreva `to_dict()`**, que devolve só o que o JSON traz de volta igual (tabela abaixo).
3. **Escreva `from_dict(data)`**, que converte os tipos e trata `{}` como **novo jogo**.
4. **Registre** no `_ready()` com `SaveManager.register_participant(chave, to_dict, from_dict)`.
5. **Peça gravação** com `SaveManager.request_save()` a cada mudança de fato.

Exemplo fictício, um Autoload que guarda a reputação de cada NPC:

```gdscript
const SAVE_KEY: String = "reputation"     # nome da seção no save; nunca renomear sem migração
const SCORES_KEY: String = "scores"

var _scores: Dictionary = {}              # StringName(npc) -> int

func _ready() -> void:
	SaveManager.register_participant(SAVE_KEY, to_dict, from_dict)

func add_reputation(npc_id: StringName, delta: int) -> void:
	_scores[npc_id] = int(_scores.get(npc_id, 0)) + delta
	SaveManager.request_save()             # mudou um fato: pede, não grava

# Pura e barata: roda a cada gravação. Sem I/O, sem request_save().
func to_dict() -> Dictionary:
	var scores: Dictionary = {}
	for npc_id: StringName in _scores:
		scores[String(npc_id)] = int(_scores[npc_id])   # chave String, valor int
	return { SCORES_KEY: scores }

# {} é o novo jogo: zera tudo, sem erro e sem aviso.
func from_dict(data: Dictionary) -> void:
	_scores.clear()
	var saved: Dictionary = data.get(SCORES_KEY, {})
	for raw_id: Variant in saved:
		_scores[StringName(str(raw_id))] = int(saved[raw_id])   # o JSON devolveu String e float
	# Não pede gravação: carregar não é mudança.
```

### Contrato de tipos

O arquivo é JSON, e o JSON não tem `int`, `StringName` nem `Vector2`. O que você grava volta diferente:

| Você grava | Volta do JSON como | Converta na leitura com |
| --- | --- | --- |
| `String`, `bool` | igual | nada |
| `int` | `float` (`4380` vira `4380.0`) | `int(x)` |
| `float` | `float` | `float(x)` |
| `StringName` | `String` | `StringName(str(x))` |
| `Vector2` | não existe | grave `[x, y]`, volte com `Vector2(float(a[0]), float(a[1]))` |
| `Array`, `Dictionary` | igual | converta cada elemento; a chave é `String` |
| `Node`, `Resource`, `Callable` | nunca | grave o **id** e ache o objeto de novo |

> **Armadilha do JSON:** comparar `StringName` com `String` falha em silêncio, e `int` que volta `float`
> quebra divisão e `match` sem nenhum erro. O sintoma é o jogador reencontrar insights que já leu. As
> conversões na leitura são obrigatórias, não estilo. O `GameClock` tem o caso mais caro: um `total_minutes`
> `float` desmonta o calendário inteiro.

### As regras do participante

- **`to_dict()` é pura e barata.** Roda a cada gravação: nada de I/O, nada de `request_save()`.
- **`from_dict({})` é novo jogo.** Zere tudo. Chega `{}` também quando o save não tem a sua chave (save
  antigo, outra branch, slot novo): nunca é erro.
- **`from_dict` não pede gravação.** Carregar não é mudança; pedir regravaria o arquivo a cada partida
  aberta por nada. (A única exceção do projeto é a `GameSession`: quando o local salvo não é o da cena,
  como num novo jogo, **entrar no local** é um gesto, e ela pede a gravação.)
- **Toda mudança de fato chama `request_save()`.** Esquecer isso perde o progresso até o próximo gesto
  de qualquer sistema. Pedidos no mesmo frame viram uma escrita só.
- **Grave fatos, não derivados.** Ids e números. O dia, a hora e o rótulo do slot saem do `total_minutes`.
- **Id que o conteúdo não tem mais é ignorado**, sem erro. Conteúdo novo nunca invalida save antigo.
- **Chave desconhecida sobrevive.** O que está no arquivo e ninguém registrou (outra branch, sistema
  removido) volta ao disco intacto a cada gravação.

### Participante de cena

Nó que nasce e morre com a cena (a `GameSession` hoje; o `Inventory`, quando entrar) registra no
`_ready()` e **sai no `_exit_tree()`**:

```gdscript
func _ready() -> void:
	SaveManager.register_participant(SAVE_KEY, _to_save, _from_save)

func _exit_tree() -> void:
	SaveManager.unregister_participant(SAVE_KEY)   # a seção fica guardada e volta ao disco
```

**Registro tardio:** com partida ativa, `register_participant` já chama o `from_dict` com a seção
guardada, na hora. É por isso que uma cena que abre depois do `continue_game` recebe o estado sem caso
especial. Cuidado: nesse instante os irmãos que vêm depois na árvore ainda não rodaram o `_ready()`. Se o
`from_dict` depende de outro nó, ache-o por grupo (a `GameSession` acha o `Player` por `Player.GROUP`) e
deixe a verificação que precisa da cena montada para o primeiro frame.

Sem `unregister_participant`, o `SaveManager` descarta o `Callable` morto na gravação seguinte, com
um aviso no log. É rede de segurança, não caminho.

### Participante static (sem `_ready`)

O `DialogueState` é `static` e não tem `_ready()`. Ele registra na **primeira consulta**, com um
`ensure_registered()` no começo de toda função pública, e os `Callable`s são sobre o próprio script:
`Callable(DialogueState, "to_dict")`. O registro tardio entrega a seção da partida aberta nessa hora.

### Quem já participa

| Chave | Dono | Entra como | Guarda |
| --- | --- | --- | --- |
| `clock` | `GameClock` | Autoload | `total_minutes` (no sonho, o minuto em que o dia fechou) |
| `insights` | `InsightJournal` | Autoload | `read` (ids lidos), `flags` |
| `profiling` | `ProfilingJournal` | Autoload | `discovered`, `fills`, `solved`, `marks`, `emotions`, `met` |
| `dialogue` | `DialogueState` | static, primeira consulta | `chosen`, `visited` |
| `world` | `GameSession` | nó de cena | `location` (id do local), `position` `[x, y]` |

### Antes de abrir PR com um participante novo

- [ ] A chave é `snake_case`, única, e está numa constante do dono.
- [ ] `to_dict()` só devolve `String`, `int`, `float`, `bool`, `Array` e `Dictionary` (chave `String`).
- [ ] `from_dict` converte com `int()` e `StringName(str())`, e `from_dict({})` zera tudo.
- [ ] Toda função que muda fato chama `request_save()`; `from_dict` e `to_dict` não chamam.
- [ ] Participante de cena chama `unregister_participant` no `_exit_tree()`.
- [ ] O autoteste do sistema que mexe em estado desliga `SaveManager.autosave_enabled` e devolve no fim.

---

## O arquivo

Cada slot (1 a 3) é um `save<N>.json` na pasta `user://` do Godot. No Windows:
`%APPDATA%\Godot\app_userdata\Project2627\`. No editor, **Project → Open User Data Folder** abre a pasta.

| Arquivo | O que é |
| --- | --- |
| `save<N>.json` | O principal do slot |
| `save<N>.json.tmp` | A gravação em andamento; só vira principal depois de escrita por inteiro |
| `save<N>.json.bak` | A última versão boa anterior (uma geração) |

Os `.cfg` de configuração (`settings.cfg`, `audio_settings.cfg`, `gameplay_settings.cfg`) ficam onde estão:
o `SaveManager` nunca os toca, e trocar de partida não muda volume, idioma nem esquema de movimento.

### Envelope v1

`JSON.stringify` com tab e chaves ordenadas: dá para abrir, ler e comparar à mão. Condensado aqui (o
arquivo real sai com um item por linha):

```json
{
	"data": {
		"clock": { "total_minutes": 6260 },
		"dialogue": { "chosen": ["ze_ana_feira:DIALOGUE_ZE_ANA_FEIRA_OPT_CHUVA"], "visited": ["inicio"] },
		"insights": { "flags": ["puddle_examined"], "read": ["city_ground_puddle"] },
		"profiling": { "discovered": { "ze": ["barco", "rede"] }, "fills": {}, "marks": {}, "met": [],
			"solved": [], "emotions": { "ze": { "next_day": 6, "next_slot": 1 } } },
		"world": { "location": "city", "position": [412.5, -96.0] }
	},
	"saved_at": 1790781600,
	"version": 1
}
```

| Campo | Tipo | Significado |
| --- | --- | --- |
| `version` | int | Versão do **formato** (`FORMAT_VERSION`). Sobe quando há migração |
| `saved_at` | int | Unix UTC da gravação. O menu converte para a hora local |
| `data` | Dictionary | Uma seção por participante, pela chave de registro |
| `clock.total_minutes` | int | Único estado do relógio. 6260 = dia 5, sexta, 14:20 |
| `world.location` | String | Id do local, não caminho de cena: renomear o `.tscn` não quebra o save |
| `world.position` | [float, float] | Última posição segura. `Vector2` não sobrevive ao JSON |

O rótulo do slot ("Dia 5, Sexta, 14:20 — Cidade") é **derivado** de `clock` e `world` na hora de
desenhar. Nada derivado é gravado, então trocar o idioma com slots cheios não toca o arquivo.

### Como grava (e por que não corrompe)

A Godot no Windows não troca arquivo de forma atômica: renomear por cima de um destino existente apaga o
destino antes de mover. Por isso a gravação **nunca renomeia por cima do principal**:

1. O texto inteiro vai para o `.tmp`. Principal e `.bak` ficam intocados.
2. O principal vira `.bak` (se estava bom; se estava podre, é apagado, para não empurrar o último `.bak`
   bom para fora).
3. O `.tmp` vira o principal.

Em qualquer ponto de queda de energia, a leitura acha o save anterior ou o novo, inteiro. Ela segue a ordem
**principal → `.tmp` → `.bak`** e o primeiro arquivo válido vence. Ler nunca muda o disco.

---

## Estados do slot

`get_slot_info(slot)` devolve um `SaveSlotInfo` com o `state`, a `version` lida, o `saved_at` e as
`sections` já migradas. Só lê: nunca cria, move nem apaga arquivo.

| Estado | O que é | Continuar | Novo jogo | Aviso |
| --- | --- | --- | --- | --- |
| `EMPTY` | Nenhum arquivo do slot | Novo jogo | Novo jogo | "Vazio" |
| `OCCUPIED` | O principal abriu | Continuar, Apagar | Novo jogo\*, Apagar | nenhum |
| `RECOVERED` | Só `.tmp` ou `.bak` abriu | Continuar, Apagar | Novo jogo\*, Apagar | "Recuperado do backup" |
| `DAMAGED` | Há arquivo, mas nenhum abre | Apagar | Apagar | "Save danificado" |
| `NEWER` | Gravado por uma versão mais nova | nada | nada | "Feito por uma versão mais nova" |

As colunas **Continuar** e **Novo jogo** são os botões que a tela de slots mostra, conforme o jogador
a abriu pelo "Continuar" ou pelo "Novo jogo" do menu principal. \* = pede confirmação de substituir.

- **Nunca vira `EMPTY` por engano.** Arquivo ilegível é `DAMAGED`, e "Novo jogo" por cima dele é
  recusado: save ilegível só sai pelo Apagar.
- **`NEWER` é intocável.** Não abre, não é apagado e não é sobrescrito por caminho nenhum. É o que protege
  o save de quem abre o jogo numa build mais velha.
- **`RECOVERED` abre normalmente**, com um aviso amarelo. A próxima gravação apaga o principal podre em
  vez de empurrá-lo para o `.bak`, que guarda a última cópia boa.
- Arquivo **inválido** é: vazio, que não parseia, que não é objeto, ou de versão 1+ sem `data` objeto.
- O "Continuar" do menu principal fica habilitado se **qualquer** arquivo de slot existir, em qualquer
  estado: o jogador precisa chegar à tela de slots para apagar um save danificado.

---

## Migração

O formato do arquivo evolui por **versões**. `FORMAT_VERSION` (hoje `1`) é a versão do formato, não do
jogo. Save antigo é migrado **na leitura**, em memória; o disco só muda na próxima gravação, já no
formato atual.

- **v0** é qualquer objeto JSON **sem** `version` (o `save1.json` de desenvolvimento de antes do
  envelope). O objeto inteiro vira `data`, e a regra v0 → v1 move o `total_minutes` do topo para
  `clock.total_minutes`. O `{"Var1": true}` do menu antigo fica como chave desconhecida, inofensiva.
- **Versão maior que `FORMAT_VERSION`** é `NEWER`. Nunca se tenta abrir.

### Quando precisa de migração

| Mudança | Migra? |
| --- | --- |
| Campo novo numa seção, ou seção nova | Não: `from_dict` usa `data.get(chave, padrão)` |
| Conteúdo novo (insight, NPC, história) | Não: id novo nunca invalida save antigo |
| **Renomear uma chave de seção** | **Sim** |
| **Renomear um id de conteúdo** já gravado | **Sim** (ver o checklist abaixo) |
| **Mudar o formato** de uma seção | **Sim** |

### Como adicionar um passo

Em `SaveManager.gd`, três mudanças:

```gdscript
const FORMAT_VERSION: int = 2     # 1. sobe a versão

func _migrate(sections: Dictionary, from_version: int) -> Dictionary:
	var migrated: Dictionary = sections
	if from_version < 1:
		migrated = _migrate_v0_to_v1(migrated)
	if from_version < 2:          # 2. encadeia o passo novo
		migrated = _migrate_v1_to_v2(migrated)
	return migrated

# v1 -> v2: o insight "city_ground_puddle" virou "city_puddle".
func _migrate_v1_to_v2(sections: Dictionary) -> Dictionary:     # 3. escreve o passo
	var insights: Variant = sections.get("insights")            # literais, nunca InsightJournal.SAVE_KEY
	if insights is Dictionary and (insights as Dictionary).get("read") is Array:
		var read: Array = (insights as Dictionary)["read"]
		for index: int in read.size():
			if str(read[index]) == "city_ground_puddle":
				read[index] = "city_puddle"
	return sections
```

- **Use literais** (`"insights"`, `"read"`), não constantes dos donos. Migração é história congelada: o
  dono pode renomear a própria constante depois, e o que um save v1 significa não muda.
- O passo recebe as seções **da versão anterior** e devolve as da seguinte. Seja tolerante: a seção ou o
  campo pode nem existir.
- **Confira com um save antigo.** Guarde uma cópia de um save do formato anterior, abra-a pelo debug
  (**Continuar slot**) e confira as seções migradas em **Listar slots**. Sem isso a migração quebra sem
  ninguém ver.

### Checklist: "renomeei um id de conteúdo"

Id de conteúdo vive dentro dos saves: ids de insight (`insights.read`), flags (`insights.flags`), NPC,
palavra e história (`profiling`), escolha e nó de diálogo (`dialogue`), local (`world.location`). Se você
vai renomear um que já pode estar gravado:

- [ ] **Alguém tem esse id num save?** Se ele só existe na sua branch, renomeie e siga.
- [ ] **Sem migração**, o dono ignora o id velho (sem erro): o insight reaparece, a palavra some da
      página, a história volta a "não resolvida". Decida se isso é aceitável.
- [ ] Senão, escreva o **`_migrate_vN_to_vN1`** que troca o id velho pelo novo em **todas** as seções onde
      ele aparece (listas e chaves de `Dictionary`), com literais.
- [ ] **Suba `FORMAT_VERSION`** e encadeie o passo em `_migrate`.
- [ ] Abra um save com o id velho pelo debug e confira em **Listar slots** que sai o novo.
- [ ] Avise o time: uma build antiga vê o save novo como `NEWER` e se recusa a abri-lo.

O mesmo vale para renomear a **chave de uma seção** (`"insights"`, `"clock"`…) e para mudar o formato de
uma seção.

---

## Debug: seção "Save"

Só existe no editor e em build de debug. Menu **F4 → Save**; cada entrada é também um comando do console
(**F1**). O console aceita o sufixo mais curto que seja único (`continuar_slot 2`).

| Entrada no menu | Comando no console | O que faz |
| --- | --- | --- |
| Estado da sessão | `save.estado_da_sessao` | Slot ativo, pedido pendente, gravações e participantes |
| Listar slots | `save.listar_slots` | Estado, versão, data e um resumo cru das seções dos 3 slots |
| Salvar agora | `save.salvar_agora` | `save_now()`. Sem partida ativa, avisa e não faz nada |
| Continuar slot | `save.continuar_slot <slot>` | `continue_game(slot)` e recarrega a cena atual |
| ⚠ Novo jogo no slot | `save.novo_jogo_no_slot <slot>` | `start_new_game(slot)` e recarrega a cena atual |
| ⚠ Apagar slot | `save.apagar_slot <slot>` | `delete_slot(slot)`. No slot ativo, fecha a sessão sem gravar |
| Salvar automático | `save.salvar_automatico <ligado>` | Liga/desliga `autosave_enabled` |

Os relatórios saem por `print()`, então aparecem no visualizador de log (**F5**). O menu pede confirmação
nas entradas com ⚠; o console não pede (digitar o comando inteiro já é o ato deliberado).

**Salvar automático** desliga só os *pedidos* (`request_save`). `save_now()` continua gravando: "Salvar
agora", "Salvar e sair" e fechar a janela não são afetados. É o toggle que os diários tinham cada um, agora
num lugar só. Os autotestes de insights e profiling desligam e devolvem esse toggle sozinhos.

**"Resetar lidos", "Resetar diário" e "Resetar profiling"** (seções Insights e Profiling) continuam
existindo e zeram o estado da **partida ativa**, pedindo gravação. As entradas "Salvar …", "Carregar …" e
"Salvar automático" dessas seções saíram: quem grava e carrega agora é o `SaveManager`.

### Mudou o fluxo de dev: F6 não carrega mais o slot 1

Antes, o diário e o diálogo carregavam o `save1.json` no boot, então rodar a cena com **F6** já vinha com
progresso. **Isso acabou.** Rodar a cena direto pelo editor abre uma cena **sem partida ativa**: estado
vazio, e nenhum arquivo é lido nem criado (é o mesmo que o menu principal).

Para jogar com progresso numa cena rodada por F6:

1. Rode a cena (**F6** no editor).
2. **F4 → Save → Continuar slot** `<n>` (ou `save.continuar_slot <n>` no console).
3. O `SaveManager` abre a partida e recarrega a cena, que monta já com o estado do slot.

Para começar do zero num slot: **Novo jogo no slot** `<n>`. O `save1.json` antigo de desenvolvimento
abre normalmente, como versão 0, e vira v1 na próxima gravação.

---

## O que ainda não persiste

| Sistema | Situação | Como entraria |
| --- | --- | --- |
| Cabeças (`HeadRegistry`) | Não salva | Participante `"heads"`; `{}` volta às `starts_unlocked()` |
| Itens (`Inventory`) | Não salva | Participante de cena `"inventory"` (`_ready()` e `_exit_tree()`) |
| Páginas do `Diary` | Não salva | **Não vira participante**: as páginas se reconstroem dos insights lidos |

Em todos, o `SaveManager` não muda: é um `register_participant` e um `request_save()`. Tempo jogado,
screenshot do slot e estado de NPC ficaram de fora de propósito.

---

## Erros comuns

**Esquecer o `request_save()`.** O estado muda e nada grava. O sintoma aparece só depois: o jogador
volta e perdeu o que fez, porque nenhum outro sistema pediu gravação no meio.

**Devolver `Vector2`, `StringName` ou `Object` no `to_dict()`.** O JSON não devolve igual. Pior: não dá
erro, o valor só volta errado.

**Pedir gravação de dentro do `from_dict` por rotina.** Carregar vira escrever, e cada partida aberta
regrava o arquivo à toa. Só peça se o próprio carregamento for um **gesto** (a `GameSession` pede quando
o jogador entra num local novo).

**Usar `get_tree().quit()` num botão de sair.** Não emite a notificação de fechar a janela e nada grava.
Chame `SaveManager.end_session()` antes.

**Gravar a posição ou a hora "de agora".** Grave o último valor seguro (ver acima), senão o save de uma
conversa ou de um sonho volta num estado que o jogo não sabe retomar.

**Constante do dono dentro da migração.** Se o dono renomear a constante, o passo de migração passa a
significar outra coisa. Use o literal.

**Tocar nos `.cfg` a partir do save.** Configuração do jogador (volume, idioma, esquema de movimento) não
é da partida e não troca com o slot.

---

## Onde olhar

| Arquivo | O que tem |
| --- | --- |
| [`SaveManager.gd`](../scripts/singletons/SaveManager.gd) | Sessão, gravação, leitura, migração, debug |
| [`SaveSlotInfo.gd`](../scripts/save/SaveSlotInfo.gd) | O retrato de um slot: estado, versão, data, seções |
| [`SaveSlotMenu.gd`](../scripts/ui/SaveSlotMenu.gd) | A tela de slots (Continuar, Novo jogo, Apagar) |
| [`SaveIndicator.gd`](../scripts/ui/SaveIndicator.gd) | O aviso "Jogo salvo" / "Falha ao salvar" |
| [`GameSession.gd`](../scripts/world/GameSession.gd) | Participante `world` e a tabela de locais |
