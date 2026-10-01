## GameSession - Liga e desliga o relógio junto com a cena de jogo, e guarda no save onde o jogador
## está (participante "world" do SaveManager).
##
## COMO USAR: um nó com este script dentro da cena de gameplay, em qualquer lugar da árvore.
## Só isso. Ele chama GameClock.start_session() ao entrar e stop_session() ao sair, e entra no save
## no _ready() e sai no _exit_tree(). Numa cena que não seja a cidade, ajuste location_id no Inspector
## e ponha o local em LOCATION_SCENES.
##
## POR QUE ISTO EXISTE EM VEZ DE O RELÓGIO SE LIGAR SOZINHO: o GameClock é Autoload, ou seja,
## existe desde o boot do jogo — inclusive no menu principal e na tela de loading, que são cenas
## comuns e não pausa. Se ele começasse a contar no próprio _ready(), o tempo passaria enquanto o
## jogador escolhe o slot de save. Quem sabe que uma partida começou é a cena de jogo, então é
## ela que avisa.
##
## Efeito colateral bem-vindo: rodar a cena de jogo direto pelo editor (F6) também liga o
## relógio, sem precisar passar pelo menu. Mas F6 não abre partida: sem sessão, nada é carregado nem
## gravado. Para jogar com progresso, F4 -> Save -> "Continuar slot".
##
## A SEÇÃO "world" DO SAVE: o id do local (não o caminho da cena: renomear um .tscn não quebra save)
## e a última posição segura do Player (ver Player.get_last_safe_position()). O Player é achado pelo
## grupo, então a cena não precisa ligar nada no Inspector. LOCATION_SCENES é a única tabela de
## locais do jogo: o menu de slots escolhe a cena e o nome do local por ela.
##
## QUEM ABRE O DIA SEGUINTE NÃO É ESTE ARQUIVO, É A CAMA (ver Bed.gd). Ao bater no horário
## máximo o relógio congela e o jogo fica esperando: o jogador continua andando, mas o tempo não
## anda mais até ele ir dormir. Virar o dia por conta própria aqui tiraria do jogador a única
## decisão que o sistema de tempo cobra dele.
class_name GameSession
extends Node

## Espaço para constantes

# Chave da seção no save. É contrato do arquivo: renomear pede um passo de migração no SaveManager.
const SAVE_KEY: String = "world"
# Campos da seção: o id do local (String) e a posição, como [x, y] (Vector2 não sobrevive ao JSON).
const LOCATION_KEY: String = "location"
const POSITION_KEY: String = "position"

# Local de um novo jogo, e o destino de um save sem local ou com um local que o jogo não conhece.
const DEFAULT_LOCATION: StringName = &"city"

# Local -> cena. Única tabela de locais do jogo; o menu de slots abre e rotula por ela.
const LOCATION_SCENES: Dictionary = { &"city": "res://scenes/City.tscn" }

# Prefixo da chave de tradução do nome do local (LOCATION_CITY no translations.csv).
const LOCATION_LABEL_PREFIX: String = "LOCATION_"

## Espaço para variáveis exportadas

# Que local esta cena de jogo é. O padrão cobre City.tscn sem editar a cena.
@export var location_id: StringName = DEFAULT_LOCATION

## Espaço para funções nativas

func _ready() -> void:
	# Com partida aberta, o registro já entrega a seção "world" (registro tardio do SaveManager) e a
	# posição é restaurada aqui, antes do primeiro quadro de física do Player.
	SaveManager.register_participant(SAVE_KEY, _to_save, _from_save)
	# Adiado de propósito: start_session() anuncia time_changed, e o _ready() dos irmãos que
	# escutam o relógio (HUD, NPCs) pode ainda não ter rodado — _ready corre na ordem da árvore,
	# e depender dela seria um bug esperando a primeira vez que alguém arrastar um nó. O
	# call_deferred cai no fim do frame, com a cena inteira já montada e conectada.
	GameClock.start_session.call_deferred()


func _exit_tree() -> void:
	# A seção fica no SaveManager como estava na última gravação: sair da cena não apaga o local.
	SaveManager.unregister_participant(SAVE_KEY)
	GameClock.stop_session()

## Espaço para funções personalizadas

# Cena do local salvo na seção "world". Local vazio ou desconhecido (novo jogo, save v0, save de
# outra branch) cai em DEFAULT_LOCATION: abrir a cidade é melhor que não abrir nada.
static func scene_path_for(world: Dictionary) -> String:
	var path: String = LOCATION_SCENES[_resolve_location(world)]
	return path


# Chave de tradução do nome do local salvo: LOCATION_ + id em maiúsculas (LOCATION_CITY). Usa o
# mesmo fallback de scene_path_for(), então o menu mostra o nome do lugar onde o jogo vai abrir.
static func location_label_key(world: Dictionary) -> String:
	return LOCATION_LABEL_PREFIX + String(_resolve_location(world)).to_upper()


# O id de local da seção, se o jogo conhece esse local; senão DEFAULT_LOCATION. O id volta do JSON
# como String e as chaves da tabela são StringName, por isso a conversão antes de consultar.
static func _resolve_location(world: Dictionary) -> StringName:
	var location: StringName = StringName(str(world.get(LOCATION_KEY, "")))
	if LOCATION_SCENES.has(location):
		return location
	return DEFAULT_LOCATION


# Seção "world" do save: o local e a última posição segura do Player. Sem Player na cena, só o local.
func _to_save() -> Dictionary:
	var data: Dictionary = { LOCATION_KEY: String(location_id) }
	var player: Player = _find_player()
	if player != null:
		var position: Vector2 = player.get_last_safe_position()
		data[POSITION_KEY] = [position.x, position.y]
	return data


# Recebe a seção "world". Local salvo diferente deste ({} de novo jogo, save v0, ou uma porta no
# futuro): o Player fica no ponto de partida da cena e isto pede gravação, porque entrar num local é
# gesto — o pedido espera o fade da troca de cena acabar. Mesmo local com uma posição de dois
# números: o Player volta para ela (e ele mesmo confere se não caiu dentro de uma parede).
func _from_save(data: Dictionary) -> void:
	var saved_location: StringName = StringName(str(data.get(LOCATION_KEY, "")))
	if saved_location != location_id:
		print("[GameSession] - Local salvo \"%s\" não é \"%s\"; jogador no ponto de partida" % [
			saved_location, location_id])
		SaveManager.request_save()
		return

	var raw_position: Variant = data.get(POSITION_KEY)
	var player: Player = _find_player()
	if player == null or not _is_position_pair(raw_position):
		print("[GameSession] - Sem posição salva utilizável em \"%s\"; jogador no ponto de partida" % location_id)
		return
	var pair: Array = raw_position
	player.restore_position(Vector2(float(pair[0]), float(pair[1])))


# O Player da cena, pelo grupo (mesmo jeito do NPCInteraction), ou null numa cena sem jogador.
func _find_player() -> Player:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(Player.GROUP) as Player


# A posição do save é uma lista de exatamente dois números? Qualquer outra coisa (save editado à mão,
# formato futuro) é tratada como posição ausente, não como erro.
static func _is_position_pair(value: Variant) -> bool:
	if value is not Array:
		return false
	var pair: Array = value
	if pair.size() != 2:
		return false
	return (pair[0] is float or pair[0] is int) and (pair[1] is float or pair[1] is int)
