# Sistema de diálogo

Quando o jogador clica num NPC, o jogo abre uma conversa. O roteiro dela é um arquivo de texto (`.dlg`) que descreve só a estrutura: quem fala, quais opções existem e para onde cada uma leva. O texto de cada fala e opção fica no `translations.csv`, como qualquer texto do jogo, e o roteiro o chama pela chave.

## Por onde começar

| Você quer | Leia |
| --- | --- |
| Escrever sua primeira conversa, passo a passo | [primeiro_dialogo.md](primeiro_dialogo.md) |
| Pôr dois NPCs na mesma conversa | [referencia.md](referencia.md#elenco-quem-está-na-conversa) |
| Consultar a sintaxe do `.dlg`, os tipos de falante, as flags ou uma mensagem de erro | [referencia.md](referencia.md) |
| Entender como o sistema funciona por dentro, ou mexer no código | [como_funciona.md](como_funciona.md) |

## Uma conversa em duas partes

O roteiro, em `dialogue/ze_bom_dia.dlg`:

```
== inicio ==
ze: DIALOGUE_ZE_BOM_DIA_01

- DIALOGUE_ZE_BOM_DIA_OPT_PAO => pao
- DIALOGUE_ZE_BOM_DIA_OPT_SAIR => END

== pao ==
ze: DIALOGUE_ZE_BOM_DIA_PAO
```

Os textos, em `translations/translations.csv`:

```csv
DIALOGUE_ZE_BOM_DIA_01,Good morning.,Bom dia.
DIALOGUE_ZE_BOM_DIA_OPT_PAO,Yes please.,Quero sim.
DIALOGUE_ZE_BOM_DIA_OPT_SAIR,Leave.,Ir embora.
DIALOGUE_ZE_BOM_DIA_PAO,Here you go.,Toma aqui.
```

Cada `== nome ==` é um nó da conversa. Uma linha `id: CHAVE` é uma fala, e uma linha `- CHAVE => destino` é uma opção que leva a outro nó, ou a `END` para encerrar.

Uma conversa pode ter **dois NPCs** junto com o jogador. Nesse caso o roteiro começa declarando o elenco, e os dois ficam parados, virados para o jogador, enquadrados pela câmera e com retrato na tela:

```
participants: ze ana
```

## O caminho de uma conversa nova

1. Cadastre os textos no `translations.csv`, nas colunas `en` e `pt_BR`.
2. Crie `dialogue/<id>.dlg` e escreva o roteiro com as chaves do passo 1.
3. Rode `dialogo.validar_conversas` no console do jogo (**F1**) e corrija o que aparecer.
4. Aponte o NPC para a conversa (campo `conversation_id` do `NPCDefinition`) ou abra pelo console com `dialogo.iniciar_conversa <id>`. Numa conversa de dois NPCs, aponte os dois para o mesmo id.

## Onde os iniciantes tropeçam

- Texto solto no `.dlg` dá erro de sintaxe. O roteiro só aceita chaves em `CAIXA_ALTA_COM_UNDERSCORE`, e o texto de verdade vai no CSV.
- Editar o CSV com o jogo aberto não surte efeito, porque as traduções carregam uma vez, no boot. Feche o jogo e rode de novo. Editar só o `.dlg` não exige isso.
- Numa célula de idioma vazia, o jogo mostra a chave crua naquele idioma, e a validação não avisa.
- O parser lê uma linha por vez, então cada opção precisa caber numa linha só.
