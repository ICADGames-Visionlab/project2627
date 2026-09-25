extends Node

# AudioManager (Autoload) — detalhes completos no AudioManager.md

const CONFIG_PATH := "user://audio_settings.cfg"

const BUS_MASTER := "Master"
const BUS_MUSIC := "Master" # trocar para "Music" se criar esse bus
const BUS_SFX := "Master"   # trocar para "SFX" se criar esse bus

@export var sfx_pool_size: int = 8

var general_volume: float = 1.0:
	set(value):
		general_volume = clamp(value, 0.0, 1.0)
		_apply_bus_volume(BUS_MASTER, general_volume)

var _sfx_players: Array[AudioStreamPlayer] = []
var _next_sfx := 0
var _music_player: AudioStreamPlayer


func _ready() -> void:
	_create_sfx_pool()

	_music_player = AudioStreamPlayer.new()
	_music_player.bus = BUS_MUSIC
	add_child(_music_player)

	_load_settings()


# Cria o pool fixo de players de SFX, reutilizados em rodízio por play_sfx().
func _create_sfx_pool() -> void:
	for i in sfx_pool_size:
		var player := AudioStreamPlayer.new()
		player.bus = BUS_SFX
		add_child(player)
		_sfx_players.append(player)
	print("[Audio] - Pool de SFX criado com %d players" % sfx_pool_size)


# --- API pública ---

# Ajusta o volume geral e persiste a escolha em disco. Usar sempre este método
# (nunca a variável general_volume direto) quando o volume vier do jogador.
func set_general_volume(value: float) -> void:
	general_volume = value
	_save_settings()
	print("[Audio] - Volume geral definido para %.2f" % general_volume)


# Toca um efeito sonoro usando o próximo player disponível do pool (rodízio).
# Se todos os players estiverem ocupados, interrompe o som mais antigo tocando.
func play_sfx(stream: AudioStream, volume_db: float = 0.0) -> void:
	if stream == null:
		return
	var player := _sfx_players[_next_sfx]
	_next_sfx = (_next_sfx + 1) % _sfx_players.size()
	player.stream = stream
	player.volume_db = volume_db
	player.play()
	var stream_name := stream.resource_path if not stream.resource_path.is_empty() else "(sem resource_path)"
	print("[Audio] - SFX tocado: %s" % stream_name)


# Troca a música atual. Não reinicia a faixa se ela já estiver tocando.
func play_music(stream: AudioStream) -> void:
	if stream == null or _music_player.stream == stream:
		return
	_music_player.stream = stream
	_music_player.play()
	var stream_name := stream.resource_path if not stream.resource_path.is_empty() else "(sem resource_path)"
	print("[Audio] - Música iniciada: %s" % stream_name)


# Interrompe a música atual (ex: cutscenes sem trilha sonora).
func stop_music() -> void:
	_music_player.stop()
	print("[Audio] - Música interrompida")


# --- Internos ---

# Aplica um volume linear (0-1) a um bus específico, silenciando quando chega a zero.
func _apply_bus_volume(bus_name: String, linear_value: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_mute(idx, linear_value <= 0.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(clamp(linear_value, 0.001, 1.0)))


# Salva as configurações de áudio atuais em disco.
func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "general", general_volume)
	config.save(CONFIG_PATH)
	print("[Audio] - Configurações de áudio salvas")


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) == OK:
		var legacy_value: float = config.get_value("audio", "geral", 1.0)
		general_volume = config.get_value("audio", "general", legacy_value)
		print("[Audio] - Configurações de áudio carregadas (volume geral: %.2f)" % general_volume)
	else:
		general_volume = 1.0
		print("[Audio] - Nenhuma configuração salva encontrada, usando volume padrão")
