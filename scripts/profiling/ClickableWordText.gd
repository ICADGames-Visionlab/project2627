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
## EvidenceViewer, que mostra o texto das evidências do mundo.
##
## HOVER: com o mouse em cima, a palavra troca o sublinhado por fundo vermelho e letra branca. O par
## dela acende junto ("[MARCOS] [CASTRO]" ou "[MARCOS]/[CASTRO]"), porque o par vem do atributo
## paired_words da palavra (ProfilingCatalog.find_pair_group), não da marcação: é o mesmo par que o
## clique colhe.
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
# O payload ("faca" ou "marcos|castro") da palavra sob o mouse, ou vazio.
var _hovered_payload: String = ""
# O RichTextLabel voltou a acompanhar a palavra sob o mouse depois do último refresh (que zera o
# acompanhamento dele, ver _forget_native_hover). Até lá, se o mouse sair da palavra, ninguém avisa e
# o fundo vermelho ficaria preso. Ver _on_text_gui_input.
var _hover_confirmed: bool = false
# Liga só durante _forget_native_hover, para os sinais que ela provoca não serem lidos como o mouse
# saindo da palavra.
var _forgetting_hover: bool = false

## Espaço para funções nativas

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	bbcode_enabled = true
	fit_content = true
	# O texto que entra aqui já foi traduzido por quem chamou set_marked_text; deixar a tradução
	# automática ligada faria o Godot procurar a FRASE como chave do CSV.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	# O sublinhado é desenhado pela marcação ([u]); o do link por cima dele apareceria também sob a
	# palavra acesa, onde não deve haver sublinhado nenhum.
	meta_underlined = false
	meta_clicked.connect(_on_meta_clicked)
	meta_hover_started.connect(_on_word_hover_started)
	meta_hover_ended.connect(_on_word_hover_ended)
	mouse_exited.connect(_on_word_hover_ended.bind(null))
	gui_input.connect(_on_text_gui_input)

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
	_forget_native_hover()
	text = render_markup(_source, _npc_id, clickable_color, discovered_color, true,
		hover_group(_hovered_payload))
	_hover_confirmed = false


# Converte a marcação em BBCode. Palavras de um mesmo grupo ([A]/[B]) recebem o mesmo payload, então
# clicar em qualquer uma delas descobre todas.
#
# clickable desligado desenha a palavra ainda não descoberta sublinhada, mas sem link: é o insight,
# em que as palavras vão pro glossário sozinhas quando a caixa fecha.
#
# hovered_ids são as palavras acesas pelo hover (ver hover_group): fundo clickable_color, letra branca.
static func render_markup(source: String, npc_id: StringName, clickable_color: Color,
		discovered_color: Color, clickable: bool = true, hovered_ids: Array[StringName] = []) -> String:
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
			discovered_color, clickable, hovered_ids)
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


# Diz se o jogador já colheu todas as palavras marcadas no texto: é o que libera fechar uma evidência.
# Palavra que nenhum NPC tem no pool fica de fora: ela nunca entra em glossário nenhum
# (discover_word só avisa no console), e contá-la prenderia o jogador num texto que não fecha.
static func all_words_collected(source: String, npc_id: StringName = &"") -> bool:
	for word_id: StringName in find_word_ids(source):
		if ProfilingCatalog.find_profiles_with_word(word_id).is_empty():
			continue
		if not is_word_collected(word_id, npc_id):
			return false
	return true


# As palavras que acendem juntas com o hover de um payload: as dele e os pares de cada uma
# (paired_words). Pelo par, e não só pelo payload, para "[MARCOS] [CASTRO]" separados por espaço
# também acenderem juntos: o clique em um colhe os dois, então o hover precisa mostrar os dois.
static func hover_group(payload: String) -> Array[StringName]:
	var result: Array[StringName] = []
	for token: String in payload.split(PAYLOAD_SEPARATOR, false):
		for member: StringName in ProfilingCatalog.find_pair_group(StringName(token.to_lower())):
			if not result.has(member):
				result.append(member)
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
		discovered_color: Color, clickable: bool, hovered_ids: Array[StringName]) -> String:
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
	if hovered_ids.has(word_id):
		return "[url=%s][bgcolor=#%s][color=#ffffff]%s[/color][/bgcolor][/url]" % [
			payload, clickable_color.to_html(false), display]
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
		# A palavra colhida deixa de ser link: não há mais o que acender sob o mouse.
		_hovered_payload = ""
		mouse_default_cursor_shape = Control.CURSOR_ARROW
		refresh()


# Acende a palavra (e o par) sob o mouse e troca o cursor pra mãozinha. O redesenho é adiado: trocar
# o texto DENTRO do sinal de hover apagaria o link que o RichTextLabel ainda está usando ao emiti-lo.
func _set_hovered(payload: String) -> void:
	if payload == _hovered_payload:
		return
	_hovered_payload = payload
	mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND if not payload.is_empty() else Control.CURSOR_ARROW)
	refresh.call_deferred()


func _on_word_hover_started(meta: Variant) -> void:
	if _forgetting_hover:
		return
	if str(meta) == _hovered_payload:
		# O mesmo link de novo, depois de um refresh: o RichTextLabel voltou a acompanhá-lo.
		_hover_confirmed = true
		return
	_set_hovered(str(meta))


func _on_word_hover_ended(_meta: Variant) -> void:
	if not _forgetting_hover:
		_set_hovered("")


# Trocar o texto apaga os links, mas o RichTextLabel (Godot 4.7) continua guardando o link que estava
# sob o mouse e o lê no próximo movimento: memória já liberada. O hover redesenha o texto com o mouse
# em cima da palavra, então isso aconteceria a cada palavra acesa. A saída do mouse é o único caminho
# da engine que zera esse link; os sinais que ela emite aqui são ignorados.
func _forget_native_hover() -> void:
	_forgetting_hover = true
	notification(NOTIFICATION_MOUSE_EXIT)
	_forgetting_hover = false


# Depois de um refresh, o primeiro movimento do mouse diz se ele ainda está na palavra: se estiver, o
# RichTextLabel emite meta_hover_started de novo (ainda neste evento, depois deste sinal) e
# _hover_confirmed liga; se não, nada é emitido e a checagem adiada apaga o hover que ficou para trás.
func _on_text_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and not _hovered_payload.is_empty() and not _hover_confirmed:
		_drop_lost_hover.call_deferred()


func _drop_lost_hover() -> void:
	if not _hover_confirmed:
		_set_hovered("")
