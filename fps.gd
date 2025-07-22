extends Label

var long_frame := 0.0
var timer := 0


#func _ready():
	#universe = get_parent().get_parent() as Universe
	#player = universe.player
	##player = get_parent().get_parent() as InvertedCamera
	##var universe = player.get_parent() as Universe
	#planet = universe.planet_manager
	
func _process(delta: float) -> void:
	if delta > 0.02:
		timer = Time.get_ticks_usec()
		long_frame = delta * 1000.0 # ms
	

func _physics_process(_delta):
	text = "FPS: %d\nDraws: %d\nPRIMS: %d\n" % [
		Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
	]
	

	var time = Time.get_ticks_usec()
	if timer > 0 and time - timer < 1000000: # show for 10 ms
		text += "Long Frame: %.1f ms" % long_frame
		
