# run_player_movement_self_test.gd — Roda o autoteste da movimentação do jogador (andar/correr nos dois
# esquemas) pela linha de comando.
#
#     godot --headless --path . --script res://tests/run_player_movement_self_test.gd
#
# Sai com código 0 quando todos os casos passam e 1 quando algum falha, para poder virar verificação
# automática antes de PR. Os casos ficam em PlayerMovementSelfTest: a parte do gesto de clique é a mesma
# da ação "Autoteste do clique" do menu de debug; a parte que move um Player de verdade só roda por aqui.
#
# Leva alguns segundos porque espera frames de física reais. Com --fixed-fps 60 os frames deixam de
# esperar o relógio e o teste roda o mais rápido que a máquina aguenta, com o mesmo resultado (os casos
# contam frames, não segundos).
extends SceneTree

# Carregado por caminho, e não pelo nome da classe: com --script, este arquivo é compilado antes de os
# Autoloads existirem, e citar PlayerMovementSelfTest aqui forçaria a compilação dele (e do Player, que
# usa EventBus, GameManager e DebugMenu) cedo demais — "Identifier not found".
const SELF_TEST_PATH: String = "res://scripts/player/PlayerMovementSelfTest.gd"


func _initialize() -> void:
	# Adiado para o primeiro quadro: os Autoloads ainda estão entrando na árvore quando _initialize() roda.
	_run.call_deferred()


# Executa o autoteste, imprime o relatório e encerra com o código de saída do resultado.
func _run() -> void:
	var self_test_script: GDScript = ResourceLoader.load(SELF_TEST_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as GDScript
	if self_test_script == null or not self_test_script.can_instantiate():
		push_error("[Player] - ERRO: autoteste da movimentação não compilou (%s)" % SELF_TEST_PATH)
		quit(1)
		return
	var self_test: RefCounted = self_test_script.new()
	await self_test.call(&"run", self)
	print(self_test.call(&"report"))
	quit(0 if int(self_test.get(&"failed_count")) == 0 else 1)
