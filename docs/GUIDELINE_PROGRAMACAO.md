# Guideline da Equipe de Programação

> Documento de referência (bíblia técnica) para a equipe de programação. Reúne convenções, padrões e boas práticas adotadas no projeto. Em caso de dúvida, consulte o Lead de Programação.
>
> **Última atualização:** 31/07/2026
> **Status:** documento vivo — qualquer alteração deve ser comunicada à equipe e republicada.

---

## Índice

1. [Github](#github)
   - [Commits](#commits)
   - [Branches](#branches)
   - [Pull Requests](#pull-requests)
   - [Fluxo de desenvolvimento de uma tarefa](#fluxo-de-desenvolvimento-de-uma-tarefa)
   - [Github Projects](#github-projects)
2. [Definições de Arquitetura](#definições-de-arquitetura)
   - [Event-Driven / Event Bus](#event-driven--event-bus)
3. [Godot](#godot)
   - [Singletons](#singletons)
   - [Tipagem Forte](#tipagem-forte)
   - [Variáveis de Balanceamento](#variáveis-de-balanceamento)
   - [Strings e Localização](#strings-e-localização)
   - [Placeholders](#placeholders)
   - [Debug (prints)](#padrões-de-debug-prints)
   - [Comentários](#comentários)
   - [Idioma do código](#idioma-do-código)
   - [Nomenclatura](#nomenclatura)
   - [Organização das funções](#organização-das-funções)
4. [Resumo rápido (checklist)](#resumo-rápido-checklist)

---

## Github

### Commits

Padronização baseada em **Conventional Commits**, adaptada para a equipe. Objetivo: qualquer pessoa entende o que mudou só lendo o histórico de commits.

> ⚠️ **Regra de ouro:** divida o trabalho em vários commits pequenos, cada um com um único objetivo. Não faça commits gigantes com várias alterações diferentes.

#### Formato

```
[Tipo] - Título no imperativo, curto e objetivo
```

Exemplos:
```
[Feat] - Adiciona sistema de inventário
[Fix] - Corrige colisão do personagem com paredes
[Refactor] - Reorganiza scripts da IA dos inimigos
```

#### Tipos de commit

| Tipo | Quando usar | Exemplos |
|---|---|---|
| `[Feat]` | Nova funcionalidade que o jogador pode usar/perceber | `[Feat] - Implementa sistema de salvamento` |
| `[Fix]` | Correção de bug | `[Fix] - Corrige câmera atravessando paredes` |
| `[Refactor]` | Reorganização/melhoria de código sem alterar comportamento | `[Refactor] - Separa sistema de combate em componentes` |
| `[Remove]` | Remoção de código, sistemas, assets, cenas ou features | `[Remove] - Remove sistema antigo de inventário` |
| `[Perf]` | Melhoria de performance (diferente de refactor: foco direto em desempenho) | `[Perf] - Otimiza geração procedural do mapa` |
| `[Docs]` | Alteração de documentação (nunca de código) | `[Docs] - Atualiza o guideline de programação` |

#### Descrições de commit

Devem ser explicativas o suficiente para que, ao final da sprint, a junção das descrições sirva como relatório do trabalho de cada membro. Requisitos mínimos:
- Uma frase resumindo o que foi feito para **cada arquivo** modificado/incluído/removido.
- Um **resumo geral** das modificações e das motivações por trás de decisões de engenharia relevantes.

#### Boas práticas de commit

- Commits pequenos, com um único objetivo.
- Evite commits gigantes com várias alterações diferentes.
- Títulos claros e objetivos.
- Faça o commit logo após concluir uma ação que se encaixe em uma categoria.
- Um bom commit deve ser entendido por qualquer membro da equipe sem precisar abrir o código.

---

### Branches

Modelo adotado: **Master → Development → Feature branches**, com **HotFixes** como exceção.

| Branch | Papel |
|---|---|
| **Master (main)** | Versão mais estável do projeto. É daqui que builds para eventos e playtests são geradas. |
| **HotFixes** | Correções de emergência pré-evento/playtest (ex: bugs resolvidos in loco na INDIECON). **Uso restrito a emergências.** |
| **Development** | Branch principal de desenvolvimento. Todas as features novas chegam aqui primeiro. Representa a versão mais atual do projeto, pode conter features incompletas. Todas as feature branches são mergeadas aqui. |
| **Feature branches** | Uma branch por issue/tarefa (ex: `#078-implementar-sistema-de-inventario`). Apesar do nome, também cobrem fixes, refactors etc. Commits seguem o padrão da seção [Commits](#commits). Ao concluir, abre-se PR para `development`. |

---

### Pull Requests

> ⚠️ **Todo PR deve ser direcionado para a branch `development`.**

#### Quando abrir um PR

Abra um PR quando a funcionalidade/correção/refactor estiver concluída e pronta para integração. Checklist antes de abrir:

- [ ] Funcionalidade finalizada.
- [ ] Projeto compila sem erros vermelhos ou amarelos.
- [ ] Nenhum arquivo desnecessário sendo enviado.
- [ ] Commits seguem o padrão do documento.

#### Nome e descrição do PR

Seguem o mesmo padrão da seção de commits (`[Tipo] - Título` + descrição explicativa).

#### Revisão de PRs

- Sempre que possível, **2 revisores** por PR.
- Critérios de aprovação:
  - Legibilidade do código.
  - Testes das funcionalidades descritas no PR.
  - Cumprimento das convenções do projeto.
  - Testes de impacto em outros sistemas.
  - Ausência de erros vermelhos/crashes.
- Mudanças solicitadas via chat do próprio PR, marcando o autor.
- **Warnings:** devem ser evitados a todo custo. Se forem o único problema, não bloqueiam o merge — mas se houver qualquer outro problema além de warnings, o revisor deve exigir a remoção dos warnings **junto** com a correção do outro problema.

---

### Fluxo de desenvolvimento de uma tarefa

Ao receber uma tarefa, siga nesta ordem:

1. Criar branch a partir da issue no Github Projects (branch source: `development`) e mover o card para **"Em Andamento"**.
2. Desenvolver a tarefa, commitando conforme o padrão de commits.
3. Abrir PR direcionado para `development`, solicitando 2 revisores.

---

### Github Projects

- Deve ser mantido atualizado sempre que possível pela equipe (fiscalização é responsabilidade do lead).
- Kanban ligado a issues e branches: toda issue vira um card, toda feature branch é criada a partir do card, mantendo rastreabilidade.

---

## Definições de Arquitetura

> Padrões de arquitetura não devem ser aplicados religiosamente a tudo. Use interpretação/contexto. Em caso de dúvida, perguntar é sempre bem-vindo.

### Event-Driven / Event Bus

**Conceito:** sistemas evitam depender diretamente uns dos outros. Em vez de chamadas diretas, um sistema emite um evento (`Signal` no Godot) quando algo acontece; sistemas interessados reagem de forma independente, sem que o emissor saiba quem está ouvindo. Resultado: desacoplamento entre módulos, manutenção mais fácil, menor impacto entre sistemas quando um módulo muda.

**Event Bus:** implementação centralizada do Event-Driven — um Singleton (`Events`/`EventBus`) por onde todos os sistemas emitem/escutam eventos, em vez de conectar Signals diretamente entre objetos.

```gdscript
# Events.gd (Autoload)
extends Node

signal player_died
signal item_collected(item)
signal enemy_killed(enemy)
signal money_changed(amount)
signal game_paused
signal game_resumed
```

```gdscript
# Player.gd
func _on_death() -> void:
    Events.player_died.emit()
```

```gdscript
# Inventory.gd
func _ready() -> void:
    Events.item_collected.connect(_on_item_collected)

func _on_item_collected(item) -> void:
    add_item_to_inventory(item)
```

Fluxo: **algo acontece → objeto emite evento no Event Bus → Event Bus notifica todos os ouvintes → cada ouvinte reage como quiser.** Os emissores não conhecem os ouvintes.

#### Quando utilizar

Quando um mesmo evento pode interessar a múltiplos sistemas, ou quando módulos devem permanecer independentes. Exemplos: atualização de UI, sons, progresso de missões, conquistas, notificações de gameplay.

> Exemplo: ao derrotar um inimigo, um único evento `enemy_killed` pode conceder XP, atualizar missão, tocar SFX e registrar conquista — tudo desacoplado.

#### Quando evitar

Para comunicação simples entre dois objetos com relação direta e permanente — nesse caso, chamada de função ou Signal direto é mais simples, legível e fácil de debugar.

> Exemplo: um botão de menu chamando `start_game()` diretamente não precisa passar pelo Event Bus (emissor e receptor únicos e diretos).

---

## Godot

Convenções específicas da engine.

### Singletons

**Definição:** código sempre carregado (Autoload), independente da cena atual. Representado em runtime como um node vazio; pode consumir memória (principalmente via `_process` e afins). Ideais para sistemas compartilhados globalmente, evitando passar referências entre cenas/objetos. Uso excessivo aumenta acoplamento e dificulta testes/manutenção/reuso.

> ⚠️ **A criação de novos Singletons deve ser discutida com o Lead de Programação.** Antes de criar um Autoload, avalie se o sistema realmente precisa ser global ou se uma referência direta / Event Bus já resolve.

#### Quando utilizar

Quando o sistema precisa de acesso global e possui apenas uma instância durante todo o jogo.
Exemplos: `EventBus`, `AudioManager`, `SaveManager`.

#### Quando não utilizar

Para objetos que pertencem a uma cena específica ou que podem existir em múltiplas instâncias.
Exemplos: `Player`, Inimigos, NPCs, Inventário, Interfaces específicas.

---

### Tipagem Forte

Use tipagem explícita sempre que possível em variáveis, parâmetros e retornos. Melhora legibilidade, facilita identificação de erros, reduz ambiguidade.

```gdscript
var player_health: int = 100
var current_item: ItemData

func attack(target: Enemy) -> void:
    pass
```

> ⚠️ Evite deixar variáveis sem tipo definido quando o tipo puder ser especificado explicitamente.

---

### Variáveis de Balanceamento

Toda variável de balanceamento (velocidade, dano, vida, cooldowns, distâncias, probabilidades etc.) deve ser exposta no Inspector via `@export`, permitindo ajustes por designers/equipe sem tocar no código.

**Evite:**
```gdscript
const PLAYER_SPEED := 250.0
var ENEMY_DAMAGE := 15
```

**Prefira:**
```gdscript
@export var player_speed: float = 250.0
@export var enemy_damage: int = 15
@export var attack_cooldown: float = 0.8
```

---

### Strings e Localização

Nenhum texto exibido ao jogador deve estar hardcoded. Todas as strings ficam numa base de localização (CSV) — cobre diálogos, descrições de itens, mensagens de erro, tutoriais, nomes de missões e qualquer texto de UI (código e editor, incluindo campo `Text` de nodes `Label`).

**Evite:**
```gdscript
dialog_label.text = "Você encontrou uma chave!"
```

**Prefira:**
```gdscript
dialog_label.text = tr("found_key")
```

---

### Placeholders

Permitidos para arte, som, modelos, animações etc. ainda não produzidos — **desde que claramente identificáveis** (texto/imagem indicando o que representam; pode usar arte gerada por IA como placeholder temporário).

**Evite:** quadrado vermelho genérico, textura cinza sem identificação, cubo qualquer sem indicação.

**Prefira:** imagem com texto `"Placeholder - NPC Pescador"`, sprite temporário identificável, ícone com nome/descrição do item.

> ⚠️ Antes de abrir o PR, todo placeholder deve ter uma **Issue no GitHub Projects com a tag "Substituição de Placeholder"**. PRs com placeholders são permitidos desde que devidamente identificados e com a tarefa de substituição já criada.

---

### Padrões de debug (prints)

Formato obrigatório:

```
[AreaDoDebug] - O que aconteceu
```

Exemplos:
```gdscript
print("[Player] - Jogador morreu")
print("[Inventory] - Item \"Machado\" adicionado ao inventário")
print("[Combat] - Iniciando turno do inimigo")
print("[Quest] - Quest \"Primeira Pesca\" concluída")
print("[Audio] - Música da floresta iniciada")
print("[Save] - Jogo salvo com sucesso.")
```

Sempre que relevante, incluir IDs, nomes de objetos ou valores úteis para debugging.

> ⚠️ Prints temporários (só para teste) devem ser removidos antes do PR.
> ⚠️ **Toda funcionalidade implementada em um PR deve ter prints de DEBUG úteis**, seguindo este formato.

---

### Comentários

Use comentários para explicar **decisões de implementação**, comportamentos não óbvios, ou contexto relevante para manutenção futura. Não comente o que já é óbvio pela leitura do código.

Código de debug/teste temporário deve ser marcado com `// [DEBUG]` e envolvido pela condição:

```gdscript
if OS.has_feature("editor") or OS.is_debug_build():
    # [DEBUG]
    if Input.is_action_just_pressed("1"):
        inventory.add_item("Cachaça")
```

Isso garante que ferramentas de debug não rodem em builds de produção e facilita localizar/remover esses trechos em revisão.

> ⚠️ Antes de abrir um PR, todo código `[DEBUG]` deve ser revisado e removido se não for mais necessário.

#### Comentários para funções

Toda função não-nativa do Godot deve ter, logo acima, um comentário explicando sua funcionalidade e motivação.

```gdscript
# Verifica se o jogador possui energia suficiente para realizar a ação de pesca.
# Caso não possua, a função encerra imediatamente para evitar estados inválidos.
func start_fishing() -> void:
    if player.current_energy < FISHING_COST:
        return
    player.current_energy -= FISHING_COST
    EventBus.fishing_started.emit()
```

---

### Idioma do código

**Todo o código deve ser escrito em inglês:** variáveis, funções, classes, cenas, recursos, constantes, signals e qualquer identificador.

**Comentários são a exceção: devem ser escritos em português**, pois seu objetivo é facilitar o entendimento da equipe.

**Evite:**
```gdscript
var velocidade_jogador: float

func iniciar_pesca():
    pass

signal item_coletado
```

**Prefira:**
```gdscript
var player_speed: float

func start_fishing() -> void:
    pass

signal item_collected
```

---

### Nomenclatura

| Elemento | Convenção | Exemplo |
|---|---|---|
| Classes | `PascalCase` | `PlayerController` |
| Scripts | `PascalCase` | `InventoryManager.gd` |
| Variáveis | `snake_case` | `player_health` |
| Funções | `snake_case` | `start_fishing()` |
| Constantes | `UPPER_SNAKE_CASE` | `MAX_PLAYER_SPEED` |
| Signals | `snake_case` | `item_collected` |
| Cenas | `PascalCase` | `MainMenu.tscn` |

---

### Organização das funções

Ordem recomendada dentro de um script (não obrigatória em todos os casos, mas deve ser seguida sempre que possível):

1. `signal`
2. `enum`
3. Constantes (`const`)
4. Variáveis exportadas (`@export`)
5. Variáveis comuns
6. Referências (`@onready`)
7. Funções nativas do Godot (`_ready()`, `_process()`, `_physics_process()`, etc.)
8. Funções não nativas

---

## Resumo rápido (checklist)

Revisar antes de iniciar uma tarefa ou abrir um PR:

- [ ] Commits pequenos, um único objetivo, padrão `[Tipo] - Título`.
- [ ] Desenvolvimento sempre em Feature Branch criada a partir de `development`.
- [ ] PR direcionado para `development`, com 2 revisores sempre que possível.
- [ ] GitHub Projects atualizado conforme o andamento.
- [ ] Event Bus apenas para sistemas independentes; preferir chamada direta/Signal quando houver relação direta.
- [ ] Novo Singleton? Confirmar necessidade real de global + validar com o Lead de Programação.
- [ ] Tipagem forte sempre que possível.
- [ ] Toda variável de balanceamento exposta via `@export`.
- [ ] Nenhum texto hardcoded — usar base de localização (CSV).
- [ ] Placeholders identificáveis + Issue "Substituição de Placeholder" criada antes do PR.
- [ ] Prints de debug no padrão `[Area] - O que aconteceu`; remover prints temporários antes do PR.
- [ ] Código `[DEBUG]` envolvido por `OS.has_feature("editor") or OS.is_debug_build()`.
- [ ] Toda função não nativa com comentário de finalidade/motivação (em português).
- [ ] Código em inglês, comentários em português.
- [ ] Nomenclatura e organização de scripts respeitadas.

---

*Estas convenções existem para tornar o projeto mais organizado, previsível e fácil de manter. Em caso de dúvida ou necessidade de exceção, consulte o Lead de Programação antes de prosseguir.*
