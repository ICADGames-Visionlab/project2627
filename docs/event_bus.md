# Event Bus

Como os sistemas do jogo conversam sem depender uns dos outros.

---

## A ideia

Sistemas não chamam uns aos outros. Quem faz algo **anuncia o fato**, e quem se interessa **escuta**. O
`EventBus` é o Singleton que leva o recado — ele não guarda estado nem tem lógica.

```gdscript
EventBus.day_started.emit(3)                      # anunciar
EventBus.day_started.connect(_on_day_started)     # escutar
```

Todos os eventos do jogo ficam em `autoload/EventBus.gd`, cada um com um comentário dizendo quem emite e
quem escuta. Abrir esse arquivo é ver o jogo inteiro conversando.

> **Estado atual:** o projeto tem a infraestrutura do bus, mas **nenhum evento declarado** ainda. Eventos
> nascem junto com o sistema que produz os fatos. Os exemplos deste guia são ilustrativos — nenhum deles
> existe no projeto hoje.

**Por que vale a pena:** quando o jogador coleta algo, o inventário, o HUD e as missões precisam reagir. Sem
o bus, quem coleta precisaria conhecer os três — e cada sistema novo obrigaria a mexer em código antigo que
já funcionava. Com o bus, o emissor anuncia uma vez e não conhece ninguém.

**O preço:** o acoplamento fica invisível. Se alguém apagar um listener, nada quebra na tela — a feature
simplesmente para de acontecer, sem erro. É por isso que existe o overlay de debug (F3) e é por isso que
evento sem ouvinte é motivo de alerta.

## Quando usar

Use o bus quando **três ou mais sistemas diferentes** reagem ao mesmo fato, ou quando emissor e ouvinte
vivem em cenas diferentes.

Nos outros casos, prefira o simples:

| Situação | Use |
| --- | --- |
| Pai e filho da mesma cena | Chamada direta (para baixo), signal local (para cima) |
| Dois objetos com relação fixa e permanente | Chamada direta |
| Avisar N instâncias iguais (todos os inimigos) | `get_tree().call_group()` |
| Precisa de resposta, ou a ordem importa | Chamada direta |

Bus para tudo vira um emaranhado difícil de seguir. Na dúvida, comece com chamada direta e promova a evento
quando aparecer o terceiro interessado.

---

## Criar um evento

**1. Declare o sinal** em `autoload/EventBus.gd`, na seção do módulo, com um comentário acima:

```gdscript
# Emitido quando o jogador termina uma receita na bancada.
# Emissor: CraftingStation. Ouvintes: InventorySystem, QuestSystem.
signal recipe_crafted(recipe_id: StringName, amount: int)
```

Pronto. Não precisa registrar nada em lugar nenhum — o overlay de debug encontra o evento novo sozinho.

**2. Emita** de quem produziu o fato:

```gdscript
# Conclui a receita e anuncia o fato para os demais sistemas.
func finish_recipe() -> void:
	EventBus.recipe_crafted.emit(recipe_id, output_amount)
	print("[Crafting] - Receita \"%s\" concluída" % recipe_id)
```

**3. Escute** de quem se interessa:

```gdscript
func _ready() -> void:
	EventBus.recipe_crafted.connect(_on_recipe_crafted)


# Adiciona ao inventário o resultado de qualquer receita concluída.
func _on_recipe_crafted(recipe_id: StringName, amount: int) -> void:
	add_item(recipe_id, amount)
```

### Regras de nome

Evento é **fato no passado**, em inglês, `snake_case`: `item_added`, `day_started`, `gold_changed`.

Nunca dê ao evento o nome do que o ouvinte deve fazer. `add_item_to_inventory` está errado — isso é chamada
direta disfarçada, e o acoplamento continua lá, só ficou invisível.

Duas convenções úteis:

- **Mudança de valor** manda o valor novo **e** o delta: `gold_changed(new_value: int, delta: int)`. Uns
  ouvintes querem o total, outros querem a variação.
- **Pedido** usa o sufixo `_requested` (`save_requested`). É a exceção: não é fato, é ordem, e espera
  **exatamente um** sistema atendendo. Se ninguém atender, nada acontece e ninguém percebe — por isso o
  logger acusa quando a contagem não é 1.

### Regras de parâmetro

Sempre tipado. Nada de `Dictionary` ou `Array` solto como "saco de dados": sem tipo não há contrato, e
procurar quem usa o quê no projeto vira impossível.

Até três parâmetros, mande direto. **A partir de quatro, crie uma classe de payload** em
`events/payloads/` — assim adicionar um campo novo não quebra a assinatura de todos os ouvintes:

```gdscript
class_name ItemTransactionEvent
extends RefCounted

var item_id: StringName
var amount: int
var source: StringName
var resulting_total: int


func _init(p_item_id: StringName, p_amount: int, p_source: StringName, p_resulting_total: int) -> void:
	item_id = p_item_id
	amount = p_amount
	source = p_source
	resulting_total = p_resulting_total


# Sem isso o log de eventos imprime "<RefCounted#...>" e não ajuda em nada.
func _to_string() -> String:
	return "ItemTransactionEvent(item=%s, amount=%d, total=%d)" % [item_id, amount, resulting_total]
```

O payload é uma **fotografia** do momento: preencha tudo no `_init()`, não crie setters, e guarde **IDs, não
nós** (`source_id: int`, nunca `source: Node`) — o nó pode nem existir mais quando alguém for ler.

---

## Escutar direito

**Conecte no `_ready()`, por código, com método nomeado.** Não conecte pelo editor (a conexão some da busca
no projeto) e não use lambda (não aparece nas ferramentas de inspeção e não desconecta de forma previsível).

**Precisa do valor atual, não só das mudanças?** O bus só entrega o que acontece *depois* que você conectou.
Um HUD criado no meio da partida ficaria zerado até a primeira emissão. A solução é pegar o valor inicial de
quem é dono dele:

```gdscript
func _ready() -> void:
	var wallet: Wallet = get_tree().get_first_node_in_group(&"wallet") as Wallet
	_set_gold(wallet.current_gold)                  # valor inicial: do dono
	EventBus.gold_changed.connect(_on_gold_changed) # mudanças: do bus
```

E quem vai ser consultado assim entra no grupo em `_enter_tree()`, não em `_ready()` — a engine roda todos
os `_enter_tree` antes de qualquer `_ready`, então a consulta nunca depende da ordem dos nós na cena.

**Duas variações úteis do `connect`:**

- `connect(callable, CONNECT_ONE_SHOT)` — para tutorial e inicialização, que só interessam uma vez.
- `connect(callable, CONNECT_DEFERRED)` — quando seu handler instancia ou libera nós.

**Desconectar:** conexão de método de um `Node` cai sozinha quando o nó é liberado. Se o ouvinte **não** for
um `Node` da árvore, desconecte em `_exit_tree()`.

---

## Depurar

**F3** abre o overlay do Event Bus com o jogo rodando (só existe em build de debug): emissões no último
frame, eventos mais emitidos, eventos que ninguém escutou e o histórico das últimas emissões.

Se um evento "não chega", cheque nesta ordem: (1) o listener conectou no `_ready()`? (2) o nó está na
árvore? (3) o emissor rodou? O overlay responde as três em segundos.

Alertas que aparecem no console:

| Mensagem | O que costuma ser |
| --- | --- |
| `AVISO: x emitido sem nenhum listener conectado` | Fiação esquecida, ou evento que ninguém usa mais |
| `ERRO: pedido x_requested tem N listeners` | Pedido precisa de exatamente 1 dono: 0 = não acontece, 2+ = acontece em dobro |
| `AVISO: x emitido N vezes no frame` | Provável laço, ou evento que deveria ser agregado |

No Inspetor, o nó `EventBusLogger` (filho do `EventBus`) tem duas flags para investigação:
`log_every_emission` loga toda emissão, e `deep_trace` mede profundidade de cascata.

---

## Erros comuns

**Cadeia longa.** Um evento pode gerar no máximo mais um. `production_collected → item_added` é o limite;
se você precisar de um terceiro salto, aplique o efeito por chamada direta no dono do estado. Cadeia longa é
o caminho conhecido para laço infinito e para bug que ninguém consegue rastrear.

**Depender da ordem dos ouvintes.** Se `A` precisa rodar antes de `B`, ou os dois são o mesmo sistema, ou
`B` deve reagir a um segundo fato que `A` emite. Nunca conte com a ordem de conexão.

**Um evento por frame, por entidade.** 500 entidades não emitem 500 eventos. O sistema processa em laço e
emite um só, agregado: `sources_completed(ids: PackedInt32Array)`.

**UI inteira plugada no bus.** Se 12 widgets querem `gold_changed`, conecte **um** controlador de HUD e
distribua internamente por chamada direta.

**Criar evento "porque um dia alguém vai usar".** Evento existe porque alguém escuta. Sem ouvinte, ele só
engorda o arquivo e confunde quem chega depois.

---

## Antes de abrir PR

Não há verificação automática: tipagem dos parâmetros, imutabilidade do payload e padrão de nomenclatura são
conferidos na **revisão do PR**. É uma escolha proporcional ao tamanho atual do projeto — vale reavaliar
quando o número de eventos crescer a ponto de a revisão manual não dar conta.

O que o revisor procura:

- O sinal está tipado, e o nome é fato no passado em `snake_case`?
- Tem comentário acima dizendo quem emite e quem escuta?
- Payload (se houver) preenche tudo no `_init()`, sem setters, guardando IDs em vez de nós?
- O evento tem pelo menos um ouvinte de verdade?
- A cadeia continua em no máximo dois saltos?
