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
## O guia completo está em docs/sistema_de_profiling.md.
class_name ClickableWordText
extends RichTextLabel

## Espaço para constantes

# A marcação do GDD: "[ALGUMA_COISA]". O grupo pega o que está dentro dos colchetes.
const MARKUP_PATTERN: String = "\\[([A-Za-z0-9_]+)\\]"

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
	text = _build_bbcode(_source)


# Converte a marcação em BBCode. Palavras de um mesmo grupo ([A]/[B]) recebem o mesmo payload, então
# clicar em qualquer uma delas descobre todas.
func _build_bbcode(source: String) -> String:
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
		result += _render_token(found.get_string(1), payloads[index])
		cursor = found.get_end()

	if cursor < source.length():
		result += source.substr(cursor)
	return result


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
func _render_token(token: String, payload: String) -> String:
	var word_id: StringName = StringName(token.to_lower())
	var word: GlossaryWord = ProfilingCatalog.find_word(word_id)
	if word == null:
		push_warning("[Profiling] - AVISO: o texto marca a palavra \"%s\", que não existe" % token)
		return token

	var display: String = word.get_display_text()
	if _is_already_discovered(word_id):
		return "[color=#%s]%s[/color]" % [discovered_color.to_html(false), display]
	return "[url=%s][color=#%s][u]%s[/u][/color][/url]" % [
		payload, clickable_color.to_html(false), display]


# Diz se a palavra já está no glossário a que este texto a mandaria. Sem NPC definido, "descoberta"
# é estar no glossário de qualquer um dos NPCs que a têm no pool.
func _is_already_discovered(word_id: StringName) -> bool:
	if _npc_id != &"":
		return ProfilingJournal.is_word_discovered(_npc_id, word_id)
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

	var discovered_anything: bool = false
	for token: String in payload.split(PAYLOAD_SEPARATOR, false):
		discovered_anything = ProfilingJournal.discover_word(
			StringName(token.to_lower()), _npc_id) or discovered_anything

	if discovered_anything:
		print("[Profiling] - Palavra(s) \"%s\" colhida(s) do texto" % payload)
		refresh()
