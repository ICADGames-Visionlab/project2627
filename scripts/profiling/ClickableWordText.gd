## ClickableWordText - um texto em que as palavras que servem pro profiling aparecem sublinhadas de
## vermelho e podem ser clicadas pra entrar no glossário.
##
## COMO USAR: use este nó no lugar de um Label/RichTextLabel e chame set_marked_text() com o texto
## já traduzido. A marcação no CSV é a MESMA LEGENDA DO GDD:
##
##     Achei uma [FACA] no beco.                 -> uma palavra clicável
##     O nome dele era [MARCOS]/[CASTRO].        -> duas palavras; clicar em qualquer uma traz as duas
##
## O que está entre colchetes é o ID da palavra (GlossaryWord.id) em maiúsculas. O texto que aparece
## na tela NÃO é o que está entre colchetes: é o texto traduzido da palavra, então a frase continua
## certa em inglês sem ninguém reescrever a marcação.
##
## POR QUE ISTO EXISTE AGORA, se o diálogo ainda não existe: é a porta de entrada das palavras no
## glossário, e ela é do sistema de profiling, não do de diálogo. Hoje ela é usada no texto da
## história resolvida; quando a tela de diálogo existir (outra branch), ela troca o Label dela por
## este nó e as palavras das falas passam a ser clicáveis sem nenhuma edição aqui. O mesmo vale pro
## sistema de inventário, que vai fazer as evidências chamarem ProfilingJournal.discover_word.
##
## O AVISO NA TELA ("Palavra adicionada ao Glossário do Zé") e a animação da palavra descendo pro
## canto não são feitos aqui: quem faz é o WordDiscoveryToast, escutando o EventBus. Este nó só
## descobre a palavra.
##
## A LEITURA DA MARCAÇÃO É PÚBLICA E STATIC (render_markup, render_plain, find_word_ids,
## collect_payload): a fala da tela de diálogo (DialogueEntry) e a caixa de insight (InsightBubble)
## usam a mesma marcação sem serem este nó, porque cada uma já tem o próprio RichTextLabel.
##
## O guia completo está em docs/sistema_de_profiling.md.
class_name ClickableWordText
extends RichTextLabel

## Espaço para constantes

# A marcação do GDD: "[ALGUMA_COISA]", SÓ EM MAIÚSCULAS. O grupo pega o que está dentro dos
# colchetes. As maiúsculas são o que separa a marcação do BBCode que o texto já pode ter ([i], [b]):
# sem isso, um itálico na fala virava uma palavra "i" que não existe.
const MARKUP_PATTERN: String = "\\[([A-Z][A-Z0-9_]*)\\]"

# Separa os ids de um grupo dentro do payload do clique. Não pode ser caractere que apareça em id.
const PAYLOAD_SEPARATOR: String = "|"

## Espaço para variáveis exportadas

## Cor das palavras que ainda podem ser descobertas. O GDD pede vermelho.
@export var clickable_color: Color = Color(1.0, 0.35, 0.3)

## Cor das palavras que o jogador já descobriu. Elas param de ser clicáveis, mas continuam
## destacadas: é o que deixa o jogador ver que aquela palavra já está no glossário dele.
@export var discovered_color: Color = Color(0.65, 0.65, 0.7)

## Espaço para variáveis

# O NPC a cujo glossário as palavras deste texto vão. Vazio significa "quem tiver a palavra no pool"
# (ver ProfilingJournal.discover_word), que é o caso de um texto do mundo.
var _npc_id: StringName = &""
# A marcação original, guardada pra o texto poder ser remontado quando uma palavra sai do vermelho.
var _source: String = ""

## Espaço para funções nativas

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	bbcode_enabled = true
	fit_content = true
	# O texto que entra aqui já foi traduzido por quem chamou set_marked_text; deixar a tradução
	# automática ligada faria o Godot procurar a FRASE como chave do CSV.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	meta_clicked.connect(_on_meta_clicked)

## Espaço para funções personalizadas

# Põe um texto já traduzido no nó, convertendo a marcação do GDD em palavras clicáveis.
#
# npc_id vazio manda a palavra pro glossário de quem a tiver no pool — é o comportamento certo pra
# texto do mundo, que não sabe de quem a palavra é.
func set_marked_text(source: String, npc_id: StringName = &"") -> void:
	_npc_id = npc_id
	_source = source
	refresh()


# Remonta o texto a partir da marcação guardada. Chamada quando o diário muda: a palavra que acabou
# de ser colhida precisa sair do vermelho, e o BBCode já montado não tem mais a marcação pra reler.
func refresh() -> void:
	text = render_markup(_source, _npc_id, clickable_color, discovered_color)


# Converte a marcação em BBCode. Palavras de um mesmo grupo ([A]/[B]) recebem o mesmo payload, então
# clicar em qualquer uma delas descobre todas.
#
# clickable desligado desenha a palavra ainda não descoberta sublinhada, mas sem link: é o insight,
# em que as palavras vão pro glossário sozinhas quando a caixa fecha.
static func render_markup(source: String, npc_id: StringName, clickable_color: Color,
		discovered_color: Color, clickable: bool = true) -> String:
	if source.is_empty():
		return ""

	var regex: RegEx = RegEx.create_from_string(MARKUP_PATTERN)
	var matches: Array[RegExMatch] = regex.search_all(source)
	if matches.is_empty():
		return source

	var payloads: PackedStringArray = build_payloads(source, matches)
	var result: String = ""
	var cursor: int = 0

	for index: int in matches.size():
		var found: RegExMatch = matches[index]
		if found.get_start() > cursor:
			result += source.substr(cursor, found.get_start() - cursor)
		result += _render_token(found.get_string(1), payloads[index], npc_id, clickable_color,
			discovered_color, clickable)
		cursor = found.get_end()

	if cursor < source.length():
		result += source.substr(cursor)
	return result


# O texto como o jogador o lê, sem sublinhado nem cor: a marcação vira o texto traduzido da
# palavra. Serve pra quem precisa CONTAR o texto (tempo de leitura, revelação letra a letra) — contar
# a partir da marcação crua daria "[FACA]" com seis letras, e não "faca" com quatro.
static func render_plain(source: String) -> String:
	var regex: RegEx = RegEx.create_from_string(MARKUP_PATTERN)
	var result: String = source
	for found: RegExMatch in regex.search_all(source):
		var word: GlossaryWord = ProfilingCatalog.find_word(StringName(found.get_string(1).to_lower()))
		var display: String = word.get_display_text() if word != null else found.get_string(1)
		result = result.replace(found.get_string(), display)
	return result


# Os ids de todas as palavras marcadas no texto, sem repetir, na ordem em que aparecem. É o que o
# insight colhe de uma vez quando a caixa fecha.
static func find_word_ids(source: String) -> Array[StringName]:
	var result: Array[StringName] = []
	var regex: RegEx = RegEx.create_from_string(MARKUP_PATTERN)
	for found: RegExMatch in regex.search_all(source):
		var word_id: StringName = StringName(found.get_string(1).to_lower())
		if not result.has(word_id):
			result.append(word_id)
	return result


# Descobre todas as palavras de um payload de clique ("marcos|castro"). Devolve true se alguma era
# nova — false quer dizer que o jogador clicou numa palavra que já tinha.
static func collect_payload(payload: String, npc_id: StringName = &"") -> bool:
	var discovered_anything: bool = false
	for token: String in payload.split(PAYLOAD_SEPARATOR, false):
		discovered_anything = ProfilingJournal.discover_word(
			StringName(token.to_lower()), npc_id) or discovered_anything
	return discovered_anything


# O payload de clique de cada marcação: os ids que aquele clique descobre, separados por
# PAYLOAD_SEPARATOR.
#
# Marcações separadas só por "/" formam um grupo — a notação "[MARCOS]/[CASTRO]" do GDD, que significa
# "clicar em uma adiciona as duas". Qualquer outra coisa entre elas (espaço, vírgula, palavra) quebra
# o grupo, porque aí elas apareceram soltas e valem sozinhas.
# É static e pública porque é a regra de agrupamento do GDD, e é ela que o autoteste confere (ver
# ProfilingSelfTest) — sem depender de tela, de nó nem do catálogo.
static func build_payloads(source: String, matches: Array[RegExMatch]) -> PackedStringArray:
	var payloads: PackedStringArray = PackedStringArray()
	payloads.resize(matches.size())
	var group_start: int = 0

	for index: int in matches.size():
		var ends_group: bool = true
		if index < matches.size() - 1:
			var between: String = source.substr(matches[index].get_end(),
				matches[index + 1].get_start() - matches[index].get_end())
			ends_group = between != "/"
		if not ends_group:
			continue

		var ids: PackedStringArray = PackedStringArray()
		for member: int in range(group_start, index + 1):
			ids.append(matches[member].get_string(1).to_lower())
		var payload: String = PAYLOAD_SEPARATOR.join(ids)
		for member: int in range(group_start, index + 1):
			payloads[member] = payload
		group_start = index + 1

	return payloads


# Desenha uma palavra marcada. Palavra que não existe no projeto aparece como texto normal e avisa no
# console: um id errado no CSV não pode virar uma frase quebrada na cara do jogador.
static func _render_token(token: String, payload: String, npc_id: StringName, clickable_color: Color,
		discovered_color: Color, clickable: bool) -> String:
	var word_id: StringName = StringName(token.to_lower())
	var word: GlossaryWord = ProfilingCatalog.find_word(word_id)
	if word == null:
		push_warning("[Profiling] - AVISO: o texto marca a palavra \"%s\", que não existe" % token)
		return token

	var display: String = word.get_display_text()
	if is_word_collected(word_id, npc_id):
		return "[color=#%s]%s[/color]" % [discovered_color.to_html(false), display]
	var underlined: String = "[color=#%s][u]%s[/u][/color]" % [clickable_color.to_html(false), display]
	if not clickable:
		return underlined
	return "[url=%s]%s[/url]" % [payload, underlined]


# Diz se a palavra já está no glossário a que o texto a mandaria. Sem NPC definido, "descoberta"
# é estar no glossário de qualquer um dos NPCs que a têm no pool.
static func is_word_collected(word_id: StringName, npc_id: StringName = &"") -> bool:
	if npc_id != &"":
		return ProfilingJournal.is_word_discovered(npc_id, word_id)
	for profile: NPCProfile in ProfilingCatalog.find_profiles_with_word(word_id):
		if ProfilingJournal.is_word_discovered(profile.npc_id, word_id):
			return true
	return false


# Clique numa palavra: descobre todas as palavras do grupo e redesenha o texto, pra a palavra sair do
# vermelho e o jogador ver que ela foi colhida.
func _on_meta_clicked(meta: Variant) -> void:
	var payload: String = str(meta)
	if payload.is_empty():
		return

	var discovered_anything: bool = collect_payload(payload, _npc_id)

	if discovered_anything:
		print("[Profiling] - Palavra(s) \"%s\" colhida(s) do texto" % payload)
		refresh()
