# Referência do sistema de diálogo

Consulta rápida. Para aprender do zero, comece pelo [tutorial](primeiro_dialogo.md).

---

## Onde fica cada coisa

| O quê | Onde |
| --- | --- |
| Roteiro da conversa | `dialogue/<id>.dlg` |
| Texto de cada fala e opção | `translations/translations.csv` |
| Falantes que não são NPC (ex.: narrador) | `resources/dialogue/speakers/<id>.tres` |
| Qual NPC abre qual conversa | campo `conversation_id` do `NPCDefinition` |
| Quem está na conversa (um ou dois NPCs) | linha `participants:` do `.dlg` |
| Retrato do NPC na conversa | campo `portrait` do `NPCDefinition` |
| Cores, tempos e limites da tela | `resources/dialogue/dialogue_style.tres` |

O nome do arquivo sem `.dlg` é o id da conversa. `dialogue/ze_bom_dia.dlg` é a conversa `ze_bom_dia`, e é esse id que vai em `conversation_id`.

---

## Sintaxe do `.dlg`

```
# Comentário: a linha inteira é ignorada.
participants: ze ana

== inicio ==
ze: DIALOGUE_ZE_BOM_DIA_01
ze: DIALOGUE_ZE_BOM_DIA_02

- DIALOGUE_ZE_BOM_DIA_OPT_PAO => pao
- DIALOGUE_ZE_BOM_DIA_OPT_SAIR => END

== pao ==
ze: DIALOGUE_ZE_BOM_DIA_PAO
```

O parser lê uma linha por vez, ignora linhas em branco e recuo, e não junta linhas. Cada fala, cada opção e cada `=>` cabe numa linha só.

### Elenco: quem está na conversa

```
participants: ze ana
```

Uma conversa é sempre com o jogador, e com **um ou dois NPCs**. A linha `participants:` declara quais, pelo `id` do `NPCDefinition`, separados por espaço ou vírgula. Ela vem antes do primeiro `== nó ==` e aparece uma vez só no arquivo.

Com dois NPCs declarados, ao abrir a conversa:

- os dois ficam parados e viram para o jogador, mesmo que a rotina fosse levar um deles embora;
- a câmera enquadra o jogador e os dois;
- a tela mostra **dois retratos**, um por NPC, na ordem escrita aqui (ver [Retratos](#retratos-dos-npcs)).

Numa conversa de um NPC só, a linha não é necessária: quem participa é o NPC em que o jogador clicou. Escrevê-la mesmo assim (`participants: ze`) não muda nada.

O elenco não é deduzido das falas de propósito: um NPC pode estar na roda e calado num galho inteiro da conversa, e mesmo assim precisa estar parado, virado e enquadrado. O contrário — um NPC que fala sem estar declarado — é que atrapalha, e **Validar conversas** avisa quando acontece.

Qualquer um dos dois pode puxar a conversa: basta os dois `NPCDefinition` apontarem o mesmo `conversation_id`. Quem o jogador clicou é quem ele aborda; o resto é igual.

Se um dos dois estiver em outra cena, ou longe demais (`DialogueStyle.camera_group_max_distance`), a conversa abre do mesmo jeito e ele continua falando — só não é enquadrado. O Output registra os dois casos.

### Nós

`== nome ==` abre um nó. O nome começa com letra ou `_` e continua com letras, números e `_`. O primeiro nó do arquivo é onde a conversa começa. Dois nós não podem ter o mesmo nome.

### Falas

```
falante: CHAVE
```

`CHAVE` é uma chave de `translations.csv`. O sistema procura o `falante` nesta ordem e usa o primeiro que achar:

| Escrito no `.dlg` | Quem fala |
| --- | --- |
| só a chave, sem falante | Narração, sem nome de falante. |
| `player` | O jogador. O nome vem de `DIALOGUE_SPEAKER_PLAYER` (Você). |
| `head:<id>` | A cabeça de insight com esse id, buscada no `HeadRegistry`. |
| `ze`, `ana`... | O NPC do roster com esse `id`. Nome e cor vêm do `NPCDefinition`. |
| o `id` de uma cabeça, sem `head:` | A cabeça com esse id, se nenhum NPC tiver o mesmo. |
| `narrator`... | O `DialogueSpeaker` de `resources/dialogue/speakers/` com esse `id`. |

Se nada bate, o falante é desconhecido. A fala aparece com o id no lugar do nome, numa cor de reserva, e a validação avisa.

O nome dos personagens segue o padrão **Nome, Alcunha**, como em "Alexandre, O Grande". A alcunha não é campo do recurso: fica no CSV, na chave do nome com o sufixo `_ALCUNHA`. Para o Zé, `NPC_NAME_ZE` dá "Zé" e `NPC_NAME_ZE_ALCUNHA` dá "O Padeiro", e o diálogo mostra **ZÉ, O PADEIRO**. A vírgula vem de `DIALOGUE_SPEAKER_EPITHET_FORMAT`. Vale para NPCs, cabeças e `DialogueSpeaker`; o jogador e a narração nunca têm alcunha. Sem a linha `_ALCUNHA`, aparece só o nome, e a validação avisa quando isso acontece com um NPC do roster.

Para criar um falante novo que não é NPC, crie um recurso `DialogueSpeaker` em `resources/dialogue/speakers/` e preencha `id`, `name_key` e `name_color`. O campo `resumo` mostra o contraste da cor contra o painel.

Várias falas seguidas no mesmo nó viram uma sequência, com **Continuar** entre elas. Uma fala não pode vir depois de uma opção ou de um `=>` no mesmo nó.

Para montar a sequência, o parser cria nós internos chamados `nome__2`, `nome__3` e assim por diante. Não dê esses nomes a nós seus: se houver colisão, um dos dois sobrescreve o outro sem aviso. As opções e o `=>` do nó valem só para a última fala da sequência.

### Opções

```
- CHAVE [atributos] => destino
```

`destino` é o nome de outro nó do mesmo arquivo, ou `END` para encerrar. Os colchetes são opcionais e guardam atributos separados por espaço:

| Atributo | Valor | O que faz |
| --- | --- | --- |
| `tag:CHAVE` | chave do CSV | Mostra um rótulo antes do texto da opção, como `[Autoridade]`. |
| `if:flag` | nome de uma flag | A opção só fica disponível se o jogo tiver a flag. |
| `show_disabled` | sem valor | Se `if:` falhar, mostra a opção travada em vez de escondê-la. |
| `reason:CHAVE` | chave do CSV | Texto que explica por que a opção está travada. |
| `grant:flag` | nome de uma flag | Ao escolher a opção, concede a flag. |

Exemplo com todos juntos:

```
- ZE_BOM_DIA_OPT_FIADO [tag:DIALOGUE_TAG_AUTHORITY if:tem_distintivo show_disabled reason:ZE_BOM_DIA_SEM_DISTINTIVO grant:ze_deu_fiado] => n_fiado
```

Um nó aceita no máximo 9 opções, porque cada uma ganha um atalho de teclado de `1` a `9`.

O jogador vê uma marca ao lado das opções que já escolheu antes. Essa memória guarda a conversa e a chave do texto juntas, então duas opções da mesma conversa com a mesma chave de texto compartilham a marca.

### Avanço sem opções

```
=> destino
```

Um nó sem opções termina de um destes jeitos:

| No nó | O que acontece |
| --- | --- |
| `=> outro_no` | Mostra **Continuar** e segue para o nó indicado depois do clique. |
| `=> outro_no [auto]` | Segue sozinho depois de um tempo de leitura. |
| `=> END` ou nada | Mostra **Encerrar** e fecha a conversa. |

Com `[auto]`, a espera é `0,6 s + 0,02 s por caractere`, com teto de 2,5 s (valores de `DialogueStyle`). O tempo que a fala gastou aparecendo letra por letra já conta como leitura.

Um nó com opções não aceita `=>`, e um nó com `=>` não aceita opções.

---

## Textos, chaves e CSV

O `.dlg` só aceita chave em fala, `tag` e `reason`. A chave começa com letra maiúscula e continua com letras maiúsculas, números e `_`. Qualquer outra coisa é erro de sintaxe, para o texto cru não chegar à tela por engano.

- O texto de cada idioma mora no CSV, nas colunas `en` e `pt_BR`. Preencha as duas: numa célula vazia, o jogo mostra a chave crua naquele idioma, e a validação não avisa.
- O texto aceita BBCode, como `[i]itálico[/i]`.
- Texto com vírgula, aspas ou mais de uma linha vai entre aspas duplas no CSV (ver [localization.md](../localization.md), seção 2).
- Falas acima de 300 caracteres (`max_line_chars` no `DialogueStyle`) geram aviso na validação. O painel quebra linhas longas sozinho.
- **As traduções carregam uma vez, no boot.** Editou o CSV com o jogo aberto? Feche o jogo e rode de novo. Editar só o `.dlg` não exige isso.

---

## Flags

`if:` lê e `grant:` grava as flags do `InsightJournal`, as mesmas que os insights usam para abrir e fechar portas. Elas são salvas junto com o jogo.

Para testar, o console (**F1**) tem `insights.conceder_flag <flag>`. Para zerar, a seção Insights do menu (**F4**) tem **Resetar diário**, que apaga o diário inteiro, insights lidos e flags.

---

## Retratos dos NPCs

Enquanto a conversa está aberta, a tela mostra um retrato por NPC do elenco, numa coluna à esquerda da coluna de diálogo, alinhada ao topo dela. A imagem vem do campo `portrait` do `NPCDefinition` (grupo Diálogo).

- A imagem deve ter proporção 3:4. O slot é de 180×240 px (`DialogueStyle.portrait_slot_size`), e uma imagem em outra proporção é cortada embaixo.
- Sem imagem, a tela desenha uma silhueta na `dialogue_color` do NPC. O boot registra no log, uma vez por NPC, que está usando essa silhueta de placeholder.
- A ordem é a do `participants:`. Sem essa linha, há um retrato só: o do NPC em que o jogador clicou.
- Com dois retratos, o de quem está falando fica cheio e o outro apaga para `DialogueStyle.portrait_inactive_alpha`. Falas do jogador, da narração e de cabeças de insight não mudam quem está aceso.
- Um NPC que fala sem estar no elenco entra na coluna se ainda houver espaço; se não houver, ele assume o retrato de quem não está falando. Isso é rede de segurança para roteiro com `participants:` incompleto, não um jeito de escrever: **Validar conversas** avisa.
- Numa conversa aberta pelo console (`dialogo.iniciar_conversa`) não há NPC de origem, mas o `participants:` do roteiro continua valendo, então os retratos aparecem do mesmo jeito.
- Em tela estreita ou baixa os retratos encolhem juntos, mantendo a proporção, até 60% do slot. Abaixo disso eles somem.

Espaço, cores, moldura e o vão entre os dois são os campos `portrait_*` do `DialogueStyle`.

---

## Ferramentas de debug

Ficam na seção **Diálogo** do menu (**F4**). No console (**F1**) o comando é `dialogo.` seguido do nome do botão em minúsculas, sem acento e com `_` no lugar dos espaços. Por exemplo, `dialogo.iniciar_conversa ze_bom_dia`.

| Botão | O que faz |
| --- | --- |
| Iniciar conversa | Abre uma conversa pelo id, como um NPC faria. |
| Pular para nó | Abre a conversa direto num nó, para testar um trecho sem repetir o começo. |
| Validar conversas | Confere as chaves fixas do sistema, as conversas de teste e todo `.dlg`. Erros de sintaxe vêm com o número da linha. |
| Validar estilo | Confere o contraste WCAG (pior caso) de cada cor do `DialogueStyle`, dos NPCs, das cabeças e dos `DialogueSpeaker`. |
| Mostrar IDs | Mostra o id de cada fala no log. |
| Ignorar condições | Faz toda opção condicional aparecer disponível. |
| Teste de estresse de texto | Escala 2.0 temporária, com a fala mais longa do CSV e o nome de falante mais longo. |
| Passeio automático | Roda a conversa sozinha, escolhendo ao acaso, `N` vezes. Acusa beco sem saída e loop. Não mexe no save. |
| Resetar escolhas | Zera as marcas de "já escolhida" e os nós visitados. Pede confirmação. |

O projeto não usa testes automatizados unitários. A verificação de conteúdo é Validar conversas/Validar estilo (rodam também pelo console, `dialogo.validar_conversas` e `dialogo.validar_estilo`) e o Passeio automático, acima.

---

## Mensagens de erro e o que fazer

### Erros de sintaxe do `.dlg`

Aparecem no Output ao abrir a conversa e no relatório de **Validar conversas**, sempre com `linha N:`. Com erro de sintaxe, a conversa não abre.

| Mensagem | Causa | Correção |
| --- | --- | --- |
| `"..." não parece uma chave de translations.csv` | Texto solto onde devia estar uma chave. | Cadastre o texto no CSV e escreva a chave. |
| `opção sem "=> destino"` | A opção não tem `=>`, ou está quebrada em duas linhas. | Ponha a opção inteira numa linha, terminando em `=> nó` ou `=> END`. |
| `opção sem destino depois de "=>"` | Falta o nome do nó depois da seta. | Escreva o nó ou `END`. |
| `opção sem texto` | Nada antes do `=>`, ou só atributos. | Comece a opção pela chave. |
| `fala depois de opções/avanço não é permitida neste nó` | Uma fala veio depois de `-` ou de `=>`. | Ponha as falas antes das opções, ou abra outro nó. |
| `opção depois de "=>" no mesmo nó` | O nó mistura `=>` e opções. | Use um ou outro por nó. |
| `"=>" depois de opções` | O nó tem opções e um `=>`. | Tire o `=>`. Um nó com opções não avança sozinho. |
| `"=>" sem destino` | Falta o nome do nó depois da seta. | Escreva o nó ou `END`. |
| `conteúdo antes do primeiro "== nó =="` | Algo veio antes do primeiro `== nome ==`. | Abra um nó antes. |
| `nó "x" repetido` | Dois nós com o mesmo nome. | Renomeie um deles. |
| `nó "x": opção "..." aponta para "y", que não existe` | O destino tem erro de digitação ou o nó não foi escrito. | Corrija o nome ou crie o nó `y`. |
| `nó "x" avança para "y", que não existe` | O `=>` aponta para um nó que não existe. | Corrija o nome ou crie o nó `y`. |
| `atributo precisa de um valor (ex.: tag:ALGO)` | `tag` ou `reason` sem valor. | Escreva `tag:CHAVE` ou `reason:CHAVE`. |
| `nenhum nó ("== id ==") encontrado no roteiro` | O arquivo está vazio ou só tem comentários. | Escreva ao menos um nó. |
| `"participants:" só vale antes do primeiro "== nó =="` | A linha do elenco ficou dentro de um nó. | Mova-a para o topo do arquivo. |
| `"participants:" repetido` | Duas linhas de elenco no mesmo arquivo. | Declare o elenco inteiro numa linha só. |
| `"participants:" sem nenhum id de NPC` | A linha está vazia. | Escreva `participants: ze ana`, ou apague a linha. |
| `"x" não parece um id de NPC` | O id tem espaço, acento ou símbolo. | Use o `id` do `NPCDefinition` (ex.: `ze`). |
| `NPC "x" repetido em "participants:"` | O mesmo id duas vezes. | Escreva cada NPC uma vez. |
| `N NPCs na conversa, no máximo 2` | Mais de dois NPCs declarados. | Uma conversa é com o jogador e até dois NPCs. |

### Problemas de conteúdo (Validar conversas)

| Relatório | Causa | Correção |
| --- | --- | --- |
| `chave "X" ausente no CSV` (erro) | A chave não existe em `translations.csv`, ou tem erro de digitação. | Cadastre a chave ou corrija o nome. |
| `falante "x" desconhecido` (aviso) | Nenhum NPC, cabeça ou `DialogueSpeaker` tem esse id. | Corrija o id ou crie o `DialogueSpeaker`. |
| `N opções, mais de 9 possíveis` (erro) | O nó tem opções demais para os atalhos `1` a `9`. | Divida em dois nós. |
| `fala "X" com N caracteres (máximo 300)` (aviso) | A fala é longa demais. | Divida em duas falas seguidas. |
| `participante "x" não é um NPC do roster` (aviso) | O id do `participants:` não existe no `npc_roster.tres`. | Corrija o id ou ponha o NPC no roster. |
| `NPC "x" fala nesta conversa mas não está em "participants:"` (aviso) | Dois NPCs falam e o elenco não cobre os dois. | Acrescente o id ao `participants:`. |

### Sintomas no jogo

| O que você vê | Provável causa |
| --- | --- |
| A tela mostra `DIALOGUE_ALGO_01` em vez do texto | A chave não está no CSV, o CSV mudou com o jogo aberto, ou a célula daquele idioma está vazia. Rode **Validar conversas**, depois reinicie o jogo. |
| Nada abre, e o Output diz `Roteiro "x" não encontrado` | O nome do arquivo não bate com o `conversation_id`. |
| Nada abre, e o Output lista `linha N:` | Erro de sintaxe. Corrija as linhas indicadas. |
| Clicar no NPC não faz nada | O `conversation_id` do NPC está vazio. O clique só funciona com uma conversa definida. |
| Só um retrato aparece numa conversa de dois | Falta o `participants:` no roteiro, ou o segundo id está errado. Rode **Validar conversas**. |
| O segundo NPC fala mas continua andando | Mesma causa: sem `participants:`, ele não é segurado nem virado para o jogador. |
| A câmera não enquadra o segundo NPC | Ele está em outra cena naquele horário, ou mais longe que `camera_group_max_distance`. O Output diz qual dos dois. |
| Uma opção some | O `if:` falhou e ela não tem `show_disabled`. Com **Ignorar condições** ligado ela aparece. |
