extends Node
## Sound effects synthesized in code (sfxr style): no audio files to ship or license.
## Combat sounds are quiet and rate-limited because the game runs next to work apps all day.

const RATE := 22050
const POOL := 8
const MODES := ["on", "low", "off"]
const MODE_DB := {"on": 0.0, "low": -14.0, "off": -80.0}

## name -> [list of notes, volume dB, min seconds between plays]
## note = [wave, freq start Hz, freq end Hz, seconds, volume 0..1]
const SOUNDS := {
	"hit":      [[["noise", 900, 300, 0.05, 0.35]], -16.0, 0.12],
	"pierce":   [[["square", 260, 110, 0.09, 0.4]], -12.0, 0.15],
	"arrow":    [[["square", 1400, 700, 0.05, 0.2]], -18.0, 0.12],
	"fireball": [[["noise", 500, 80, 0.3, 0.5]], -10.0, 0.2],
	"kill":     [[["square", 880, 880, 0.04, 0.3], ["square", 1320, 1320, 0.07, 0.3]], -14.0, 0.15],
	"drop":     [[["triangle", 1200, 1600, 0.06, 0.4]], -10.0, 0.1],
	"boss_win": [[["square", 523, 523, 0.07, 0.35], ["square", 659, 659, 0.07, 0.35], ["square", 784, 784, 0.07, 0.35], ["square", 1047, 1047, 0.16, 0.35]], -6.0, 0.5],
	"chest":    [[["triangle", 392, 392, 0.07, 0.5], ["triangle", 523, 523, 0.07, 0.5], ["triangle", 659, 659, 0.12, 0.5]], -6.0, 0.1],
	"level":    [[["sine", 523, 523, 0.06, 0.5], ["sine", 659, 659, 0.06, 0.5], ["sine", 784, 784, 0.06, 0.5], ["sine", 1047, 1047, 0.06, 0.5], ["sine", 1319, 1319, 0.14, 0.5]], -6.0, 0.4],
	"success":  [[["triangle", 660, 990, 0.14, 0.5]], -6.0, 0.05],
	"great":    [[["square", 784, 784, 0.05, 0.3], ["square", 1047, 1047, 0.05, 0.3], ["square", 1568, 1568, 0.2, 0.3]], -4.0, 0.05],
	"fail":     [[["square", 300, 140, 0.22, 0.35]], -6.0, 0.05],
	"click":    [[["square", 1000, 1000, 0.02, 0.2]], -12.0, 0.03],
}

var mode := "on"
var _streams := {}
var _last_play := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	for name in SOUNDS:
		_streams[name] = build(name)
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func play(name: String) -> void:
	if mode == "off":
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_play.get(name, -INF) < SOUNDS[name][2]:
		return
	_last_play[name] = now
	var p := _players[_next]
	_next = (_next + 1) % POOL
	p.stream = _streams[name]
	p.volume_db = SOUNDS[name][1] + MODE_DB[mode]
	p.play()


func cycle_mode() -> String:
	mode = MODES[(MODES.find(mode) + 1) % MODES.size()]
	return mode


## Render a sound's notes into 16-bit mono PCM.
static func build(name: String) -> AudioStreamWAV:
	var data := PackedByteArray()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)  # same noise every run
	for note in SOUNDS[name][0]:
		var n := int(note[3] * RATE)
		var phase := 0.0
		var held := 0.0  # sample-and-hold value for noise
		for i in n:
			var t := float(i) / n
			var freq: float = lerpf(note[1], note[2], t)
			var prev_phase := phase
			phase = fmod(phase + freq / RATE, 1.0)
			var s := 0.0
			match note[0]:
				"square": s = 1.0 if phase < 0.5 else -1.0
				"triangle": s = 4.0 * absf(phase - 0.5) - 1.0
				"sine": s = sin(phase * TAU)
				_:  # noise: new random value each cycle, so freq sets the "pitch" of the hiss
					if phase < prev_phase:
						held = rng.randf_range(-1.0, 1.0)
					s = held
			var env := minf(1.0, t * 40.0) * (1.0 - t)  # 2.5% attack, linear decay: no clicks
			var v := clampi(int(s * env * note[4] * 32767.0), -32768, 32767)
			data.append(v & 0xFF)
			data.append((v >> 8) & 0xFF)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w
