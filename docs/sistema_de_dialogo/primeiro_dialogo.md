# Seu primeiro diálogo

Neste tutorial você escreve uma conversa para o Zé e a vê rodando no jogo.

No fim, o Zé diz duas falas e o jogador escolhe entre três opções. A segunda opção fica travada, com o motivo escrito, até o jogo ter a flag `achou_bilhete`.

Você precisa do projeto aberto no Godot 4.7 e de um editor de texto para o `.dlg` e o CSV. Os comandos de debug abaixo usam o console do jogo, que abre com **F1** (ver [debug_menu.md](../debug_menu.md)).

---

## 1. Cadastre os textos

Cada fala e cada opção da conversa é uma linha de `translations/translations.csv`. Acrescente estas no fim do arquivo, cada uma em linha própria:

```csv
DIALOGUE_ZE_BOM_DIA_01,Good morning.,Bom dia.
DIALOGUE_ZE_BOM_DIA_02,The bread just came out. Want some?,O pão saiu agora. Quer um?
DIALOGUE_ZE_BOM_DIA_OPT_PAO,Yes please.,Quero sim.
DIALOGUE_ZE_BOM_DIA_OPT_BILHETE,Ask about the note.,Perguntar do bilhete.
DIALOGUE_ZE_BOM_DIA_REASON_BILHETE,You have not found the note yet.,Você ainda não achou o bilhete.
DIALOGUE_ZE_BOM_DIA_OPT_SAIR,Leave.,Ir embora.
DIALOGUE_ZE_BOM_DIA_PAO,Here you go.,Toma aqui.
DIALOGUE_ZE_BOM_DIA_VOCE,Zé... about that note.,Zé... sobre aquele bilhete.
DIALOGUE_ZE_BOM_DIA_BILHETE,Oh. That. Sit down.,Ah. Isso. Senta aí.
```

Os nomes seguem o padrão `DIALOGUE_<CONVERSA>_<PARTE>`. O padrão é só uma convenção que ajuda a achar as linhas depois.

Preencha as duas colunas de idioma (`en` e `pt_BR`). Numa célula vazia, o jogo mostra a chave crua naquele idioma.

Se o Godot estiver aberto quando você salvar o CSV, ele reimporta sozinho. Se estiver fechado, reimporte pelo dock FileSystem (ver [localization.md](../localization.md), seção 11).

---

## 2. Crie o roteiro mais curto possível

Crie o arquivo `dialogue/ze_bom_dia.dlg`, na pasta `dialogue/` da raiz do projeto:

```
== inicio ==
ze: DIALOGUE_ZE_BOM_DIA_01
```

O nome do arquivo, sem `.dlg`, é o id da conversa: `ze_bom_dia`. Na segunda linha, `ze` é o `id` do NPC que fala e `DIALOGUE_ZE_BOM_DIA_01` é a chave do texto no CSV.

---

## 3. Valide o roteiro

1. Rode o jogo e entre na cidade com **Novo Jogo**.
2. Aperte **F1** para abrir o console.
3. Digite `dialogo.validar_conversas` e aperte Enter.

O relatório aparece no painel Output do Godot. Procure linhas que comecem com `ze_bom_dia/`. Se não houver nenhuma, o roteiro está válido. Avisos de outras conversas do projeto não são seus.

---

## 4. Veja a conversa rodando

No console, digite:

```
dialogo.iniciar_conversa ze_bom_dia
```

O painel de diálogo abre com o Zé dizendo "Bom dia." e um botão **Encerrar**. Clique nele para fechar.

Nos próximos passos você edita o `.dlg` e abre a conversa de novo, sem fechar o jogo, porque o jogo lê o arquivo toda vez que a conversa abre. Só o CSV exige reiniciar: as traduções carregam uma vez, no boot.

---

## 5. Acrescente uma segunda fala

Adicione uma linha ao roteiro:

```
== inicio ==
ze: DIALOGUE_ZE_BOM_DIA_01
ze: DIALOGUE_ZE_BOM_DIA_02
```

Abra a conversa de novo. Agora o botão da primeira fala diz **Continuar**, e só depois da segunda ele vira **Encerrar**.

Duas falas seguidas no mesmo nó viram uma sequência, com **Continuar** entre elas. Você não precisa criar um nó por fala.

---

## 6. Ofereça escolhas

Troque o roteiro inteiro por este:

```
# Zé, logo cedo, na padaria.
== inicio ==
ze: DIALOGUE_ZE_BOM_DIA_01
ze: DIALOGUE_ZE_BOM_DIA_02

- DIALOGUE_ZE_BOM_DIA_OPT_PAO => pao
- DIALOGUE_ZE_BOM_DIA_OPT_SAIR => END

== pao ==
ze: DIALOGUE_ZE_BOM_DIA_PAO
```

Abra a conversa de novo. Depois da segunda fala aparecem duas opções numeradas. Escolha a primeira (clique ou tecla `1`): o Zé responde "Toma aqui." e a conversa termina. Escolha a segunda e ela termina na hora.

Cada linha que começa com `-` é uma opção. O que vem depois de `=>` é o destino: outro nó do arquivo (`pao`) ou `END`, que encerra a conversa. Uma linha que começa com `#` é comentário.

---

## 7. Trave uma opção com uma condição

Acrescente a opção do bilhete e o nó que ela leva:

```
# Zé, logo cedo, na padaria.
== inicio ==
ze: DIALOGUE_ZE_BOM_DIA_01
ze: DIALOGUE_ZE_BOM_DIA_02

- DIALOGUE_ZE_BOM_DIA_OPT_PAO => pao
- DIALOGUE_ZE_BOM_DIA_OPT_BILHETE [if:achou_bilhete show_disabled reason:DIALOGUE_ZE_BOM_DIA_REASON_BILHETE] => bilhete
- DIALOGUE_ZE_BOM_DIA_OPT_SAIR => END

== pao ==
ze: DIALOGUE_ZE_BOM_DIA_PAO

== bilhete ==
player: DIALOGUE_ZE_BOM_DIA_VOCE
ze: DIALOGUE_ZE_BOM_DIA_BILHETE
```

Abra a conversa de novo. A opção 2 aparece travada, com o texto "Você ainda não achou o bilhete." como motivo.

Os colchetes carregam os atributos da opção:

- `if:achou_bilhete` só libera a opção se o jogo tiver essa flag.
- `show_disabled` mostra a opção travada em vez de escondê-la.
- `reason:...` é a chave do texto que explica por que ela está travada.

Agora conceda a flag. No console:

```
insights.conceder_flag achou_bilhete
```

Abra a conversa de novo. A opção 2 está liberada. Escolha-a: o jogador diz "Zé... sobre aquele bilhete." e o Zé responde "Ah. Isso. Senta aí."

A flag fica no diário do jogador e é salva junto com o jogo. Para limpar depois do treino, use **Resetar diário** na seção Insights do menu de debug (**F4**). Ele apaga o diário inteiro, insights lidos e flags.

---

## 8. Ligue a conversa ao Zé

Para o jogador chegar à conversa clicando no NPC, aponte o NPC para ela:

1. Abra `resources/npcs/npc_ze.tres` no Inspector.
2. No campo `conversation_id`, escreva `ze_bom_dia`.
3. Rode o jogo e clique no Zé. Ele fica perto da `CasaDoZe`, segundo a rotina dele (ver [sistema_de_npc.md](../sistema_de_npc.md)).

A conversa abre igual à do passo 4. Se isso foi só treino, apague o `conversation_id` de novo antes de fazer commit.

---

## Onde ir agora

- [referencia.md](referencia.md) tem a sintaxe completa do `.dlg`, os tipos de falante, `grant`, `[auto]` e a tabela de mensagens de erro.
- [como_funciona.md](como_funciona.md) explica o caminho do clique até a tela, para quem vai mexer no código.
