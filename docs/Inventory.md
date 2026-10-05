#Feito pelo Enzo com uso do Claude — issue #29

# Sistema de Inventário (Evidências)

Sistema de inventário do jogador: guarda os itens que ele possui, permite largá-los no mundo,
destruí-los e mostra tudo numa UI que o jogo chama de "Evidências" (o inventário em si continua
se chamando `Inventory` no código — só o texto exibido ao jogador usa o tema do jogo).

Peças do sistema:

| Arquivo | Papel |
|---|---|
| `scripts/items/ItemData.gd` | Resource que descreve um *tipo* de item (id, nome, ícone, se empilha, se pode ser destruído). |
| `scripts/items/ItemStack.gd` | Par (item, quantidade) guardado dentro do inventário. |
| `scripts/player/Inventory.gd` | O inventário em si — um componente (`Node`), filho do `Player`. |
| `scripts/items/ItemPickup.gd` + `scenes/items/ItemPickup.tscn` | Item largado no chão, coletado ao encostar. |
| `scripts/ui/InventoryUI.gd` + `scenes/ui/InventoryUI.tscn` | Painel "Evidências", abre/fecha com a tecla **I**. |
| `items/EvidenciaExemplo.tres` | Item de exemplo/placeholder, só para testar o sistema (ver "Testando"). |

---

## Por que NÃO é um Singleton

Ao contrário do `AudioManager` ou do `SaveManager` (ver `docs/AudioManager.md`, `docs/SaveManager.md`),
o `Inventory` **não é um Autoload**. O próprio `GUIDELINE_PROGRAMACAO.md` (seção "Singletons") lista
"Inventário" como exemplo do que NÃO deve virar Singleton — porque, diferente de áudio ou save, cada
personagem tem o *seu próprio* inventário: hoje só o `Player`, mas se um dia um NPC precisar guardar
itens, ele ganha a própria instância de `Inventory` como filho, sem qualquer mudança no script.

Um Singleton de inventário obrigaria a resolver "qual personagem essa chamada é sobre?" em todo método
— exatamente o tipo de acoplamento que a seção de Singletons do guideline pede para evitar.

**Como o resto do jogo encontra o inventário, então?** Toda instância de `Inventory` entra no grupo
`Inventory.GROUP_NAME` (`"inventory"`) assim que entra na árvore (`_enter_tree()`), e quem precisa dele
— hoje só a `InventoryUI` — usa `get_tree().get_first_node_in_group(Inventory.GROUP_NAME)`. É o mesmo
padrão documentado em `docs/event_bus.md` (seção "Escutar direito") para o exemplo da `Wallet`. Já o
`ItemPickup`, que sabe exatamente quem está entrando nele (`body is Player`), pega o inventário direto
do corpo (`body.get_node_or_null("Inventory")`) — mais simples e não depende do grupo.

Se um dia existir mais de um personagem com inventário na mesma cena ao mesmo tempo, a busca por grupo
deixa de ser suficiente (`get_first_node_in_group` pega só o primeiro) — nesse ponto a UI passa a
precisar de uma referência explícita a QUAL inventário mostrar (ex: o do jogador local, não o de um NPC).

---

## Quando usar

Qualquer coisa relacionada a "o jogador possui isto": pegar, largar, destruir e listar os itens que ele
carrega. Se um sistema futuro precisar reagir a essas mudanças (missões que avançam ao coletar uma
evidência específica, som ao coletar), ele escuta os sinais do `Inventory` diretamente — e só se um dia
três ou mais sistemas diferentes precisarem reagir ao mesmo fato é a hora de promover esse sinal a um
evento no `EventBus` (ver `docs/event_bus.md`, "Quando usar").

## Quando não usar

Não é lugar para estado de gameplay que não seja posse de item (vida, progresso de missão, dinheiro) —
isso é responsabilidade de outros sistemas (ex: um futuro `GameManager`/`QuestManager`). Também não
controla a UI de outros personagens: cada `InventoryUI` só mostra a evidência do inventário que ela
encontrou.

---

## API pública (`Inventory`)

| Membro | Descrição |
|---|---|
| `add_item(item: ItemData, amount: int = 1)` | Adiciona `amount` unidades. Cria a pilha se for a primeira unidade do item. Emite `item_added` só com o que **realmente** entrou (o delta, não o pedido) — se a pilha já estiver em `item.max_stack`, nada entra e o sinal não dispara. Usado pelo `ItemPickup` e pelo comando de debug. |
| `has_item(item_id: StringName, amount: int = 1) -> bool` | Se o inventário tem ao menos `amount` unidades do item. |
| `get_amount(item_id: StringName) -> int` | Quantidade atual (0 se não tiver). |
| `get_stacks() -> Array[ItemStack]` | Todas as pilhas não vazias — o que a UI usa para desenhar os slots. |
| `drop_item(item_id: StringName, amount: int = 1) -> bool` | Remove do inventário e instancia um `ItemPickup` na posição do dono, dentro do mesmo container y-sorted do dono (ver "Y-sort" abaixo). `false` (item mantido no inventário) se não houver unidades suficientes ou se o `ItemPickup` não puder ser criado. |
| `destroy_item(item_id: StringName, amount: int = 1) -> bool` | Remove sem devolver ao mundo. `false` se não houver unidades suficientes ou se `item.destructible` for `false`. |

Sinais: `item_added(item, amount)`, `item_dropped(item, amount)`, `item_destroyed(item, amount)` — a
`InventoryUI` escuta os três para saber quando redesenhar o painel.

### Y-sort

`drop_item()` instancia o `ItemPickup` como filho do **pai do dono deste inventário** (ver
`Inventory._get_drop_container()`), não de `get_tree().current_scene`. Hoje isso significa o `YSort` de
`main.tscn` — o mesmo nó onde o `Player` e as `Structure` vivem (ver `scripts/world/Structure.gd`). Um
pickup fora do `YSort` desenharia por cima de tudo, independente da posição no mundo, porque entraria
depois dele na ordem de filhos do root. Se o dono do inventário não tiver um pai (não deveria acontecer
hoje), cai em `current_scene` só para evitar crash.

---

## Criando um item novo

1. No FileSystem do editor, clique com o botão direito em `res://items/` → **New Resource** → `ItemData`.
2. Preencha no Inspector: `id` (único, nunca muda depois — ver comentário no script), `display_name_key`
   e `description_key` (chaves de tradução — crie as linhas correspondentes em
   `translations/translations.csv`, ver `docs/localizacao_Godot.md`), `icon`, `max_stack` e
   `destructible`. `description_key` aparece como tooltip do slot na `InventoryUI`.
3. Salve como `.tres` direto em `res://items/` (não numa subpasta): é ali que o `ItemCatalog` procura o
   item quando o save o traz de volta. Item fora dessa pasta some do inventário ao continuar a partida.
4. Para o item aparecer largado no mundo: instancie `scenes/items/ItemPickup.tscn`, preencha `item` e
   `amount` no Inspector. Para o jogador testar sem precisar posicionar nada no mapa, arraste o `.tres`
   para `debug_item_catalog` do nó `Inventory` do `Player` e use o comando de debug (abaixo).

## Testando

- **Console de debug (F1)** ou **Debug Menu visual (F4)**: `inventario.dar_evidencia <id> <quantidade>`
  (ou só `dar_evidencia` — o console aceita o sufixo mais curto que for único, ver `docs/debug_menu.md`).
  Só lista/aceita itens que estiverem em `debug_item_catalog` do nó `Inventory` do `Player` (entradas
  vazias nesse array são ignoradas); o projeto já vem com `items/EvidenciaExemplo.tres`
  (`mysterious_note`) cadastrado lá para esse fim.
- **Tecla I**: abre/fecha o painel "Evidências". Cada slot tem os botões **Largar** e **Destruir** (o
  botão Destruir some para itens com `destructible = false`), e mostra a descrição do item como tooltip
  ao passar o mouse.
- **No mundo**: encostar num `ItemPickup` coleta automaticamente (via `Area2D.body_entered`, igual ao
  detector de jogador que `Structure.gd` já usa). Durante os `pickup_delay` segundos após ser largado
  (padrão 0.5s — ajustável no Inspector do `ItemPickup`), o mesmo corpo que largou o item não consegue
  recolhê-lo de volta; passado esse tempo, o pickup revarre quem já estiver parado em cima dele (não
  depende só do jogador se mover para dentro da área de novo).

---

## Save

O inventário e os itens no chão entram no save sem nenhum caso especial no `SaveManager` (ver
`docs/SaveManager.md`, "Quem já participa"):

- **`Inventory`** é o participante de cena `"inventory"`: registra no `_ready()`, sai no `_exit_tree()` e
  guarda só `{id do item: quantidade}`. Na volta, o `ItemData` sai do `ItemCatalog`
  (`scripts/items/ItemCatalog.gd`, que varre `res://items/`); item que não existe mais é ignorado e a
  quantidade é presa em `1..max_stack`. Todo `add_item`, `drop_item` e `destroy_item` que muda algo pede
  gravação. Como o `Player` nasce de novo em cada cena, é a seção do save que leva o inventário de uma
  cena para a outra; sem partida ativa (F6), ele recomeça vazio.
- **Itens no chão** são da `GameSession` (participante `"pickups"`), que acha todo `ItemPickup` pelo grupo
  `ItemPickup.GROUP`. Por local, ela guarda os itens **postos na cena** que o jogador já pegou (pelo
  caminho do nó na cena) e os que ele **largou** (id, quantidade e posição). Na volta, os pegos saem da
  cena e os largados são recriados. Sem isso, salvar o inventário duplicaria item: o jogador pegava,
  recarregava, e o item estava no chão de novo.

Inventário e chão são gravados no mesmo instante, como retrato da cena: pegar ou largar nunca deixa o
item nos dois lugares, nem em nenhum.

> **Cuidado ao editar uma cena:** renomear ou mover no editor um `ItemPickup` que pode já ter sido pego
> num save faz ele reaparecer para esse jogador (o id dele é o caminho do nó). Se isso importa, é um
> passo de migração no `SaveManager` (checklist "renomeei um id de conteúdo" no `docs/SaveManager.md`).

## Limitações atuais / como escalar

- **Uma pilha por item.** `add_item` satura em `item.max_stack` (o excedente é descartado silenciosamente
  hoje — não há "inventário cheio" nem overflow para uma segunda pilha). Para suportar múltiplas pilhas
  do mesmo item (ex: itens não empilháveis em quantidade, ou um limite de peso/slots total), `_stacks`
  precisa virar `Dictionary[StringName, Array[ItemStack]]`, e a UI, iterar pilhas em vez de itens.
- **Um inventário só no save.** A chave `"inventory"` é constante, então só uma instância pode
  participar. Se um NPC ganhar um `Inventory`, ele precisa de outra chave (ou de não entrar no save),
  senão os dois se sobrescrevem.
- **Catálogo só por id.** O `ItemCatalog` acha um `ItemData` pelo id (é o que o save usa), mas não lista
  "todos os itens do jogo". Se isso for necessário (ex: uma enciclopédia de evidências), é uma função
  `static` a mais nele, sobre o mesmo cache. Não precisa de Autoload: são dados estáticos, sem estado
  por personagem nem por partida. Item novo precisa morar em `res://items/` para o save achá-lo.
- **Coleta automática por contato.** Não há tecla de "interagir" — hoje o jogador pega tudo que encosta.
  Se algum item não dever ser pego automaticamente (ex: evidência que precisa de uma escolha do
  jogador), o `ItemPickup` precisa de uma segunda forma de coleta (tecla de interação em vez de
  `body_entered`).
- **Painel sem rolagem.** `InventoryUI` desenha os slots num `GridContainer` sem scroll — com muitas
  evidências diferentes ao mesmo tempo, o painel só cresce. Trocar o `GridContainer` por um dentro de um
  `ScrollContainer` resolve sem mudar a lógica de `_rebuild_slots()`.
