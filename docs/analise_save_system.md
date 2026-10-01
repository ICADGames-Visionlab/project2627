# Análise do Save System — panorama atual

*Análise feita em 30/09/2026, sobre a branch `development` (commit `1f861e0`).*

## Resumo

Não existe um save system unificado. Existe uma camada de I/O (`SaveManager`) e três sistemas que se salvam sozinhos no slot 1. Não há conceito de "partida ativa", o menu de slots está órfão e boa parte do estado do jogo simplesmente não é persistida.

## O que existe

### Camada de I/O

[`SaveManager.gd`](../scripts/singletons/SaveManager.gd) é um Autoload com 4 funções sobre `Dictionary` ↔ JSON:

- `save_game(data, path)`
- `load_game(path) -> Dictionary`
- `reset_save(path)`
- `has_save(path) -> bool`

Também tem 3 caminhos fixos: `user://save1.json`, `user://save2.json` e `user://save3.json`. Não tem estado, não sabe qual é o slot ativo e não coordena ninguém.

### Formato do arquivo

É um JSON único por slot, em que cada sistema é dono de uma chave de topo:

| Chave | Dono | Persiste? | Como |
|---|---|---|---|
| `insights` | [`InsightJournal.gd`](../scripts/singletons/InsightJournal.gd) | ✅ | Autosave a cada mudança, no slot 1 fixo |
| `profiling` | [`ProfilingJournal.gd`](../scripts/singletons/ProfilingJournal.gd) | ✅ | Autosave, slot 1 fixo |
| `dialogue` | [`DialogueState.gd`](../scripts/dialogue/DialogueState.gd) (static) | ✅ | Autosave com carregamento preguiçoso, slot 1 fixo |
| `total_minutes` | [`GameClock.gd`](../scripts/singletons/GameClock.gd) | ❌ | `write_to_save`/`read_from_save` existem, mas **ninguém chama** |
| cabeças desbloqueadas | [`HeadRegistry.gd`](../scripts/singletons/HeadRegistry.gd) | ❌ | Não é persistido por escolha (aguarda o sistema de derrota de NPC) |
| itens | [`Inventory.gd`](../scripts/player/Inventory.gd) | ❌ | Nenhum código de save |
| posição e cena do jogador | nenhum | ❌ | nenhum |

As configurações ficam fora do save, em `ConfigFile` separados: `user://settings.cfg`, `user://audio_settings.cfg` e `user://gameplay_settings.cfg`. Essa separação está correta, porque configuração é do jogador e não da partida.

### Menu de slots

[`SaveSystem.tscn`](../scenes/SaveSystem.tscn):

- O script está embutido na cena (`GDScript` em `sub_resource`) e nenhuma parte do jogo referencia a cena.
- O `start_game` grava `{"Var1": true}` num slot novo, e a troca de cena e o repasse ao `GameManager` estão comentados.
- O [`MainMenu.gd`](../scripts/ui/MainMenu.gd) pula esse menu: "Novo Jogo" vai direto para `City.tscn`.

### O que está bem feito

Os três diários seguem o mesmo padrão, e ele é bom:

- `to_dict()` / `from_dict()` como API pública do estado.
- `save_to_slot()` faz ler o arquivo → mexer só na própria chave → regravar, preservando as chaves dos outros sistemas.
- Tratam de propósito a volta do JSON: `StringName` vira `String` e `int` vira `float`. As conversões são feitas na leitura e documentadas como "armadilha do save".
- O autosave é agrupado por frame (`_autosave_queued`), para não gravar N vezes numa mesma ação.
- `from_dict` não agenda gravação: carregar não é mudança.
- Já deixam os ganchos `save_slot_path` e `autosave_enabled` para quando um dono do slot ativo existir.

## Problemas, por gravidade

### 1. Um arquivo corrompido apaga todo o progresso sem aviso

O `save_game` abre o arquivo com `FileAccess.WRITE`, que trunca, e grava direto por cima. Se o jogo fechar no meio da gravação, o arquivo fica pela metade. O `load_game` então devolve `{}` (dá `push_error`, mas segue), e o próximo autosave de qualquer diário regrava o arquivo só com a chave dele, apagando as outras. Não há backup nem gravação em arquivo temporário seguida de rename.

### 2. "Novo jogo" na prática é "continuar"

Os diários carregam o slot 1 no boot (no `_ready()` dos Autoloads), e o botão de novo jogo não zera nada. Hoje, a única forma de começar do zero é pelo debug menu ("Resetar diário") ou apagando o arquivo à mão.

### 3. O relógio não é salvo, mas as emoções dependem do dia

O `ProfilingJournal` guarda a escolha de emoção com `next_day = dia_atual + 1` ([`ProfilingJournal.gd:320`](../scripts/singletons/ProfilingJournal.gd)), e `resolve_emotion_slot` só aplica a escolha quando `today >= next_day`. Como o `GameClock` não é salvo, ao reabrir o jogo o relógio volta ao dia inicial. Uma escolha feita no dia 5 só passa a valer quando o jogador chegar de novo ao dia 6.

### 4. Ninguém é dono do slot ativo

Cada sistema resolve o caminho sozinho (`SaveManager.save_file_1`). Se amanhã alguém escolher o slot 2, é preciso lembrar de mudar três lugares, e um deles é `static` (`DialogueState`).

### 5. Apagar um slot com o jogo aberto deixa um save fantasma

Se o menu de slots fosse ligado, o `reset_save` apagaria o arquivo, mas os diários continuariam com o estado na memória, e o próximo autosave recriaria o arquivo com o progresso antigo.

### 6. O save não tem versão

Sem um campo `version` no JSON, não há como migrar o formato quando ele mudar. Por enquanto, o uso de `data.get(chave, padrão)` compensa para chaves novas, mas não para chaves renomeadas ou para mudanças de estrutura.

### 7. Custo do autosave

Cada mudança causa uma leitura e uma gravação completas do arquivo, feitas por até três sistemas no mesmo frame. Hoje isso é irrelevante, mas vai pesar quando o save crescer.

### 8. Detalhes menores (guideline)

- Typo em `default_disctionary`.
- Constantes em minúsculas (`save_file_1`, em vez de `SAVE_FILE_1`).
- O `SaveManager` tem tipagem incompleta (`var json = JSON.new()`), e seus prints não seguem o formato `[Area] - mensagem`.
- O menu de slots usa camelCase (`botaoSlot1`, `slotFile`, `dataDictionary`) e tem o script embutido na cena.
- O [`SaveManager.md`](SaveManager.md) descreve um fluxo (`GameManager.currentSaveFile`) que não existe no código.

## Caminho natural daqui

A arquitetura dos diários já é a certa. Falta alguém dono da sessão, algo como `SaveManager.current_slot`, com três responsabilidades:

1. **Registrar os participantes.** Cada sistema se registra com a sua chave e o seu par `to_dict`/`from_dict`.
2. **Gravar com segurança.** Montar e gravar o arquivo inteiro de uma vez, em temporário seguido de rename, com um backup do save anterior e um campo `version`.
3. **Controlar a sessão.** Carregar tudo ao escolher o slot e zerar tudo no novo jogo.

Com isso:

- Os autosaves individuais passariam a chamar esse dono, em vez de ler e regravar o arquivo cada um por si.
- O `GameClock` entraria como mais um participante, o que resolve o problema 3.
- O menu de slots seria ligado ao `MainMenu`, com o script extraído para um `.gd` próprio.
- O `HeadRegistry` e o `Inventory` entrariam quando os donos desses fatos decidirem persistir.
