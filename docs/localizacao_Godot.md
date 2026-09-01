# Sistema de Localização Godot 4.7

*Esse documento visa guiar a equipe de programação no processo de localização do jogo*

---

## Sumário

1. [Locale vs. idioma](#1-locale-vs-idioma)
2. [Criando arquivos de tradução (CSV)](#2-criando-arquivos-de-tradução-csv)
3. [Adicionando as traduções ao projeto](#3-adicionando-as-traduções-ao-projeto)
4. [Usando tr() no código](#4-usando-tr-no-código)
5. [Tradução automática em Controls (Button, Label...)](#5-tradução-automática-em-controls-button-label)
6. [Placeholders / textos dinâmicos](#6-placeholders--textos-dinâmicos)
7. [Contexto de tradução](#7-contexto-de-tradução)
8. [Pluralização com tr_n()](#8-pluralização-com-tr_n)
9. [TranslationServer e troca de idioma em runtime](#9-translationserver-e-troca-de-idioma-em-runtime)
10. [Detectando o idioma do sistema automaticamente](#10-detectando-o-idioma-do-sistema-automaticamente)
11. [Localizando recursos (imagens, áudio) com Remaps](#11-localizando-recursos-imagens-áudio-com-remaps)
12. [UI redimensionável e Pseudolocalização](#12-ui-redimensionável-e-pseudolocalização)
13. [Texto bidirecional (RTL) e espelhamento de UI](#13-texto-bidirecional-rtl-e-espelhamento-de-ui)
14. [Localizando números](#14-localizando-números)
15. [Testando traduções](#15-testando-traduções)
16. [Traduzindo o nome do projeto](#16-traduzindo-o-nome-do-projeto)
17. [Referências](#17-referências)

---

## 1. Locale vs. idioma

Um locale normalmente combina um idioma com uma região/país (e pode incluir também script ou variante). Exemplos:

| Locale | Significado |
|---|---|
| en | Inglês (genérico) |
| en_US | Inglês dos EUA |
| en_GB | Inglês britânico |
| pt | Português (genérico) |
| pt_BR | Português do Brasil |
| pt_PT | Português de Portugal |

Isso não é de extrema importância para o projeto, mas é importante saber a diferença.

---

## 2. Criando arquivos de tradução (CSV)

A forma mais comum de localizar um projeto Godot é com planilhas CSV. Qualquer editor de planilhas (LibreOffice Calc, Google Sheets) pode exportar nesse formato.

**Regras do formato:**

- A primeira coluna contém a chave (KEY), única, normalmente em MAIUSCULO_COM_UNDERSCORE.
- As colunas seguintes têm como cabeçalho o **código do locale** (`en`, `pt`, `pt_BR`, `es`, etc.) — precisa ser um locale válido reconhecido pelo Godot.
- O arquivo deve ser salvo em UTF-8 sem BOM (o Excel por padrão salva em ANSI, prefira LibreOffice ou Google Sheets). Dá para mudar isso manualmente no Excel, se preferir, colocando tudo em apenas uma coluna e separando os conteúdos das linhas por vírgula.
- Valores contendo vírgula, quebra de linha ou aspas duplas devem ficar entre aspas duplas (com aspas internas escapadas como `""`).
- Colunas especiais opcionais: `?context` (contexto de tradução) e `?plural` (forma plural).

### Exemplo — translations.csv

```csv
keys,en,pt_BR
GREETING_HELLO,"Hello, %s!","Olá, %s!"
MENU_START,Start Game,Iniciar Jogo
MENU_OPTIONS,Options,Opções
MENU_QUIT,Quit,Sair
LEVEL_COMPLETE,"Level complete!","Fase concluída!"
```

### Importando

- Coloque o arquivo `.csv` em algum lugar dentro de `res://` (ex.: `res://localization/translations.csv`).
- O Godot detecta o arquivo automaticamente e o trata como tradução.
- Selecione o arquivo no FileSystem e abra a aba Import para ajustar opções (compressão, delimitador, escapes de C-string).
- Ao (re)importar, o Godot gera um recurso `.translation` compactado por idioma dentro de `.godot/imported/`, e adiciona automaticamente essas traduções à lista em Project Settings.

---

## 3. Adicionando as traduções ao projeto

Mesmo depois de importado, um arquivo de tradução só é carregado em runtime se estiver listado em:

**Project → Project Settings → Localization → Translations**

Nessa aba dá para adicionar (Add) ou remover traduções do projeto inteiro. Remover ali só tira do sistema de tradução — não apaga o arquivo do disco.

---

## 4. Usando tr() no código

A função `tr()` (herdada de `Object`) busca uma chave nas traduções carregadas e retorna o texto convertido para o locale atual. Se a chave não existir, retorna a própria string original.

**GDScript**

```gdscript
func _ready() -> void:
	$Label.text = tr("MENU_START")
	$StatusLabel.text = tr("GAME_STATUS_%d" % status_index)
```

---

## 5. Tradução automática em Controls (Button, Label...)

Vários controles de UI (Button, Label, etc.) traduzem automaticamente o próprio texto se ele coincidir com uma chave existente nas traduções — ou seja, você pode simplesmente digitar `MENU_START` no campo Text do inspetor, sem chamar `tr()` manualmente.

Isso pode ser indesejado em alguns casos — por exemplo, um Label que mostra o nome de um jogador, que não deve ser "traduzido" mesmo que coincida com alguma chave. Para desativar, defina no inspetor:

**Auto Translate → Mode → Disabled** (no nó em questão)

---

## 6. Placeholders / textos dinâmicos

Para strings com partes variáveis, use printf-style (`%s`, `%d`) ou, preferencialmente, `String.format()` com placeholders nomeados — isso permite que o tradutor reordene as partes da frase, o que muitas vezes é necessário entre idiomas.

```csv
keys,en,pt_BR
PICKUP_MSG,"%s picked up the %s","%s pegou a %s"
PICKUP_MSG_NAMED,"{character} picked up the {weapon}","{character} pegou a {weapon}"
```

```gdscript
# Placeholder posicional — a ordem das partes NÃO pode ser trocada pelo tradutor
message.text = tr("PICKUP_MSG") % ["Ogro", "Espada"]
# pt_BR: "Ogro pegou a Espada"

# Placeholder nomeado — o tradutor pode reordenar livremente
message.text = tr("PICKUP_MSG_NAMED").format({
	"character": "Ogro",
	"weapon": "Espada"
})
# pt_BR: "Ogro pegou a Espada"
```

Em português, por exemplo, a ordem natural de uma frase pode mudar em relação ao inglês — com placeholders nomeados o tradutor resolve isso sem depender de mudanças no código.

---

## 7. Contexto de tradução

Quando o texto-fonte é inglês "puro" (em vez de chaves tipo ASSIM_MESMO), a mesma palavra em inglês pode precisar virar duas palavras diferentes em outro idioma, dependendo do sentido. `tr()` aceita um segundo argumento, o contexto, para desambiguar:

```gdscript
# "Close" como ação (fechar algo)
button.text = tr("Close", "Actions")  # pt_BR: "Fechar"

# "Close" como distância (perto, oposto de "longe")
distance_label.text = tr("Close", "Distance")  # pt_BR: "Perto"
```

No CSV, isso é representado com a coluna especial `?context`:

```csv
keys,?context,en,pt_BR
Close,Actions,Close,Fechar
Close,Distance,Close,Perto
```

---

## 8. Pluralização com tr_n()

Regras de plural variam muito entre idiomas (alguns têm só singular/plural, outros têm 3+ formas). O Godot resolve isso com `tr_n()`, que recebe a forma singular, a forma plural e a quantidade — o motor escolhe a forma certa para o locale atual.

> Use `tr_n()` apenas com números inteiros positivos (ou zero); valores negativos ou fracionários geralmente representam grandezas físicas, onde singular/plural não se aplica claramente.

**GDScript**

```gdscript
var num_apples := 5
label.text = tr_n("There is %d apple", "There are %d apples", num_apples) % num_apples
# en (num_apples = 1): "There is 1 apple"
# en (num_apples = 5): "There are 5 apples"

# Equivalente em pt_BR, supondo chaves traduzidas no CSV:
# "Há %d maçã" / "Há %d maçãs"
```

Também pode ser combinado com contexto:

```gdscript
var num_jobs := 1
label.text = tr_n("%d job", "%d jobs", num_jobs, "Task Manager") % num_jobs
```

No CSV, a forma plural fica em uma linha adicional usando a coluna `?plural`:

```csv
keys,?plural,en,pt_BR
APPLE_COUNT,,"There is %d apple","Há %d maçã"
APPLE_COUNT,plural,"There are %d apples","Há %d maçãs"
```

---

## 9. TranslationServer e troca de idioma em runtime

O `TranslationServer` é o servidor de baixo nível que gerencia as traduções carregadas. Traduções podem ser adicionadas/removidas e o idioma pode ser trocado em tempo de execução (por exemplo, num menu de configurações), sem precisar reiniciar o jogo.

```gdscript
# Trocar o idioma do jogo em runtime
TranslationServer.set_locale("pt_BR")

# Consultar o locale atual
var current_locale := TranslationServer.get_locale()
print(current_locale)  # "pt_BR"
```

Assim que `set_locale()` é chamado, todos os Controls que usam tradução automática (seção 5) e todas as próximas chamadas a `tr()` passam a usar o novo idioma. Se você já preencheu textos antes da troca, normalmente é preciso re-executar a função que atualiza a UI.

---

## 10. Detectando o idioma do sistema automaticamente

É recomendado usar por padrão o idioma preferido do usuário, obtido com `OS.get_locale_language()`. Se o jogo não tiver esse idioma disponível, o Godot cai para o Fallback definido em Project Settings → Internationalization → Locale, ou para `en` se estiver vazio.

```gdscript
var language := "automatic"  # carregado de um arquivo de configurações do usuário

if language == "automatic":
	var preferred_language := OS.get_locale_language()
	TranslationServer.set_locale(preferred_language)
else:
	TranslationServer.set_locale(language)
```

Mesmo detectando automaticamente, é uma boa prática sempre deixar o jogador trocar o idioma manualmente nas configurações (qualidade da tradução ou preferência pessoal podem divergir do idioma do sistema).

---

## 11. Localizando recursos (imagens, áudio) com Remaps

Além de texto, é possível instruir o Godot a usar versões alternativas de um recurso dependendo do idioma atual — útil para outdoors/placas dentro do jogo, ou dublagem de voz.

Em Project Settings → Localization → Remaps, selecione o recurso original (por exemplo `res://art/sign_en.png`) e associe versões alternativas por locale (`pt_BR` → `res://art/sign_pt_br.png`).

> Remaps de recurso não funcionam com DynamicFont. Para trocar fontes conforme o script do idioma (ex.: latim, cirílico, CJK), use o sistema de fallback de fontes do DynamicFont, que permite definir várias fontes de reserva — isso funciona independentemente do idioma atual, o que é útil, por exemplo, em chat multiplayer onde o idioma do texto pode não coincidir com o do cliente.

---

## 12. UI redimensionável e Pseudolocalização

O mesmo texto pode variar muito de tamanho entre idiomas (traduções em alemão ou português tendem a ser mais longas que o inglês). Recomenda-se:

- Usar Containers e as opções de quebra de texto (autowrap) do Label.
- Evitar tamanhos fixos "no talo" para textos traduzíveis.

Para testar isso sem ter as traduções reais prontas, ative a Pseudolocalização em Project Settings → General → Internationalization → Pseudolocalization (ative o toggle Advanced primeiro para ver essa seção). Ela substitui os textos localizáveis por versões mais longas e com acentos estranhos, mas ainda legíveis, mantendo os placeholders intactos.

Exemplo: `"Hello world, this is %s!"` vira algo como `"[Ĥéłłô ŵôŕłd́, ŧh̀íš íš %s!]"`.

Isso ajuda a:

- Identificar strings que não estão passando por `tr()` (ficam sem alteração — fáceis de detectar).
- Verificar se a UI aguenta textos mais longos.
- Checar se a fonte usada cobre os caracteres acentuados necessários (não serve para validar CJK ou RTL).

Também dá para ligar/desligar em runtime via `TranslationServer.pseudolocalization_enabled` e `TranslationServer.reload_pseudolocalization()`.

---

## 13. Texto bidirecional (RTL) e espelhamento de UI

Árabe e hebraico são escritos da direita para a esquerda (exceto números e palavras em latim misturadas). O Godot cuida disso de forma praticamente transparente:

- Espelha âncoras/margens esquerda-direita.
- Troca alinhamento de texto esquerda ↔ direita.
- Espelha a ordem horizontal de filhos em Containers, itens em Tree/ItemList.
- Usa ordem espelhada em elementos internos de controles (dropdown do OptionButton, alinhamento de CheckBox, etc.).
- Não espelha o sistema de coordenadas nem afeta nós que não são de UI (sprites etc.).

**Propriedades relevantes em Control:**

- `text_direction` — direção base do texto (auto detecta pelo primeiro caractere fortemente direcional).
- `language` — sobrescreve o locale do projeto para aquele controle específico.
- `layout_direction` — sobrescreve o espelhamento do controle.
- `structured_text_bidi_override` — trata casos especiais (caminhos de arquivo, URLs, e-mails, código-fonte), onde o algoritmo BiDi padrão do Unicode não funciona bem sozinho.

Para incluir dados do "break iterator" (necessários para quebra de linha/palavra correta em idiomas sem espaços, como chinês/japonês) no build exportado, ative Include Text Server Data em Project Settings → Internationalization → Locale antes de exportar (adiciona ~4 MB ao build).

---

## 14. Localizando números

Controles como SpinBox e ProgressBar já formatam números automaticamente conforme o locale. Para outros lugares, use:

```gdscript
# Converte números arábicos ocidentais (0..9) para o sistema numérico do locale
var texto := TextServer.format_number("1234", "ar")

# Converte de volta para 0..9
var numero := TextServer.parse_number(texto, "ar")
```

---

## 15. Testando traduções

O Godot oferece três formas de testar sem precisar trocar o idioma do sistema operacional:

- **Project Settings → Internationalization → Locale → Test** (ative Advanced): defina o código do locale a testar; o projeto roda com esse locale tanto no editor quanto exportado.
- **Editor → View → Preview Translation**: escolha um idioma na barra superior do editor; todo o texto nas cenas abertas passa a exibir a tradução escolhida, só no editor.
- Linha de comando, ao rodar o projeto:

```bash
godot --language pt_BR
```

> Como o "Test" locale é uma configuração de projeto, esse valor fica salvo em `project.godot` e aparecerá no controle de versão — lembre de zerar antes de commitar.

---

## 16. Traduzindo o nome do projeto

O nome do projeto vira o nome do app ao exportar para diferentes plataformas. Para ter versões por idioma:

**Project → Project Settings → General → Application → Config**

Clique no botão "Localizable String (Size 0)" ao lado do campo Name, depois em "Add Translation", escolha o locale desejado e digite o nome localizado (ex.: `en` → "My Awesome Game", `pt_BR` → "Meu Jogo Incrível").

---

## 17. Referências

- **Documentação oficial — Internationalizing games:** `docs.godotengine.org/en/stable/tutorials/i18n/internationalizing_games.html`
- **Documentação oficial — Importing translations:** `docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_translations.html`
- **Documentação oficial — Pseudolocalization:** `docs.godotengine.org/en/stable/tutorials/i18n/pseudolocalization.html`
- **Documentação oficial — Locale codes:** `docs.godotengine.org/en/stable/tutorials/i18n/locales.html`
- **Notas de lançamento do Godot 4.7:** `godotengine.org/releases/4.7/`
