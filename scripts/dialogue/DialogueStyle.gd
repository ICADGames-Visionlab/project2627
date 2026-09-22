# DialogueStyle.gd — Todo número e cor visual/tempo do sistema de diálogo vive aqui.
#
# Nenhuma constante visual ou de tempo deve existir em scripts/dialogue/*.gd fora deste arquivo
# (critério de revisão do SPEC §17): trocar o "look" do diálogo é editar este recurso, não código.
@tool
class_name DialogueStyle
extends Resource

@export_group("Layout")
@export var panel_width: float = 600.0
@export var panel_width_min: float = 520.0
@export var panel_width_max: float = 720.0
@export var panel_margin_right: float = 96.0
@export var panel_margin_top: float = 48.0
@export var panel_margin_bottom: float = 48.0
@export var panel_padding_h: float = 32.0
@export var panel_padding_v: float = 24.0
# Respiro dentro da caixa de cada opção — o mesmo em repouso e em destaque, porque é ele que dá
# corpo ao preenchimento do hover sem mexer na posição da linha.
@export var option_padding_h: float = 12.0
@export var option_padding_v: float = 6.0
@export var panel_color: Color = Color("#141414", 0.82)
@export_range(0.0, 1.0) var backdrop_dim_alpha: float = 0.45
@export var backdrop_fade_width: float = 240.0
@export var backdrop_blur_enabled: bool = false
@export var top_fade_height: float = 64.0
@export var portrait_slot_size: Vector2 = Vector2(180, 240)
# Retrato do NPC (DialoguePortrait): fica à esquerda da coluna, alinhado ao topo dela. Em tela
# estreita encolhe até portrait_min_scale do slot e some abaixo disso.
@export var portrait_gap: float = 24.0
@export var portrait_margin_left: float = 24.0
@export var portrait_offset_top: float = 0.0
@export_range(0.1, 1.0) var portrait_min_scale: float = 0.6
@export var portrait_bg_color: Color = Color("#141414", 0.9)
@export var portrait_frame_color: Color = Color("#8A8A8A")
@export var portrait_frame_width: float = 3.0
# Opacidade da silhueta de placeholder, sobre o portrait_bg_color.
@export_range(0.0, 1.0) var portrait_placeholder_alpha: float = 0.55
@export var max_log_entries: int = 300

@export_group("Tipografia")
@export var body_font: Font
@export var body_font_alt: Font
@export var body_size: int = 22
@export var body_size_min: int = 18
@export var line_spacing: float = 1.4
@export var entry_spacing: int = 20

@export_group("Cores")
@export var player_name_color: Color = Color("#FFFFFF")
@export var narration_color: Color = Color("#BDBDBD")
@export var text_color: Color = Color("#EDEDED")
@export var option_color: Color = Color("#E8663D")
# Texto da opção em destaque. A caixa vira a cor que o texto tinha em repouso (option_color ou
# option_chosen_color), então esta é a cor da caixa antes do hover — o panel_color.
@export var option_hover_text_color: Color = Color("#141414")
@export var option_chosen_color: Color = Color("#B07A66")
@export var option_disabled_color: Color = Color("#8A8A8A")
@export var option_tag_color: Color = Color("#D9B26A")
@export var separator_color: Color = Color(1, 1, 1, 0.12)
@export var fallback_speaker_color: Color = Color.MAGENTA
@export var min_contrast_ratio: float = 4.5

@export_group("Estados da fala")
@export_range(0.0, 1.0) var past_alpha: float = 0.65
@export_range(0.0, 1.0) var past_hover_alpha: float = 0.85
@export var entry_fade_in: float = 0.18
@export var entry_slide_px: float = 8.0

@export_group("Opções e confirmação")
@export var options_fade_in: float = 0.15
@export var options_stagger: float = 0.04
@export var options_slide_px: float = 6.0
@export var input_lock: float = 0.25
@export var input_lock_instant: float = 0.15
@export var hover_out: float = 0.08
@export var hover_sfx_min_interval: float = 0.06
@export var confirm_flash: float = 0.22
@export var confirm_pulse_scale: float = 1.02
@export var others_fade_out: float = 0.15
@export var list_collapse: float = 0.12
@export var response_beat: float = 0.35
@export var option_marker_hover: String = "▸"
@export var option_marker_chosen: String = "✓"

@export_group("Avanço e revelação")
@export var default_advance_mode: DialogueStep.AdvanceMode = DialogueStep.AdvanceMode.CONTINUE
@export var auto_base_delay: float = 0.6
@export var auto_per_char: float = 0.02
@export var auto_max_delay: float = 2.5
@export var reveal_chars_per_second: float = 60.0
@export var reveal_pause_comma: float = 0.12
@export var reveal_pause_stop: float = 0.25
@export var max_line_chars: int = 300

@export_group("Rolagem")
@export var stick_threshold: float = 24.0
@export var stick_scroll_duration: float = 0.2
@export var wheel_lines: int = 3
@export var scrollbar_width: float = 6.0
@export var scrollbar_width_hover: float = 10.0

@export_group("Abertura e fechamento")
@export var open_duration: float = 0.25
@export var close_duration: float = 0.2
@export var open_slide_px: float = 48.0

@export_group("Aproximação e câmera")
# Distância mantida do NPC ao parar de andar até ele (NPCInteraction._approach_point): perto o
# bastante pra ler como conversa, longe o bastante pra não empurrar o corpo dele.
@export var approach_distance: float = 90.0
# Zoom da DialogueCamera enquanto os dois conversam. 1.0 é o zoom normal de jogo (PlayerCamera).
@export var camera_zoom: float = 1.6
# Duração do tween de zoom, nos dois sentidos (PhantomCamera2D.tween_duration).
@export var camera_zoom_duration: float = 0.5

@export_group("Sons")
@export var sfx_hover: AudioStream
@export var sfx_confirm: AudioStream
@export var sfx_new_line: AudioStream
@export var sfx_open: AudioStream
@export var sfx_close: AudioStream
@export var sfx_volume_db: float = -8.0


func scaled(duration: float, animation_multiplier: float) -> float:
	return duration * animation_multiplier


# No instantâneo (multiplicador 0), a trava não zera: cai para input_lock_instant (PRD §6.5).
func effective_input_lock(animation_multiplier: float) -> float:
	if animation_multiplier <= 0.0:
		return input_lock_instant
	return scaled(input_lock, animation_multiplier)


# O beat também não zera no instantâneo: mantém response_beat (PRD §6.5).
func effective_beat(animation_multiplier: float) -> float:
	if animation_multiplier <= 0.0:
		return response_beat
	return scaled(response_beat, animation_multiplier)


func effective_panel_width(text_scale: float) -> float:
	return clampf(panel_width * text_scale, panel_width_min, panel_width_max)


func effective_body_size(text_scale: float) -> int:
	return int(maxf(body_size_min, roundf(body_size * text_scale)))


# Aplica fonte, tamanho e cores nas variações de tipo do tema. StyleBoxes ficam livres para a
# direção de arte editar no editor de temas (§6.2).
func apply_to_theme(theme: Theme, text_scale: float, use_alt_font: bool) -> void:
	if theme == null:
		return
	var font: Font = body_font_alt if use_alt_font and body_font_alt != null else body_font
	var size: int = effective_body_size(text_scale)
	# Todas as variações têm base_type RichTextLabel (dialogue_theme.tres), cujas chaves de fonte
	# são normal_font/normal_font_size.
	var type_variations: PackedStringArray = [
		"RichTextLabel", "DialogueSpeakerName", "DialogueText",
		"DialogueOption", "DialogueOptionHover", "DialogueOptionChosen", "DialogueOptionDisabled",
	]
	for type_name: String in type_variations:
		if font != null:
			theme.set_font("normal_font", type_name, font)
		theme.set_font_size("normal_font_size", type_name, size)
	theme.set_color("default_color", "DialogueText", text_color)
	theme.set_color("default_color", "DialogueSpeakerName", player_name_color)
	theme.set_color("default_color", "DialogueOption", option_color)
	theme.set_color("default_color", "DialogueOptionHover", option_hover_text_color)
	theme.set_color("default_color", "DialogueOptionChosen", option_chosen_color)
	theme.set_color("default_color", "DialogueOptionDisabled", option_disabled_color)
