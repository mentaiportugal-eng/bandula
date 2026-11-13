extends Node
## Cena do servidor dedicado (sem mapa nem gráficos):
##   godot4 --headless --path godot/bandula res://scenes/server.tscn -- --port=9080

func _ready() -> void:
	if not Network.is_server:
		Network.start_server(Network._port_arg(OS.get_cmdline_user_args()))
	print("[Bandula] servidor pronto — os jogadores ligam-se a ws://<IP-deste-computador>:%d" % Network._port_arg(OS.get_cmdline_user_args()))
