extends RefCounted
## Background music generated in code: one looping chiptune per act, no audio files to license.
## Each track = bass on the chord root, a soft arpeggio, and a seeded melody that leans on chord tones.

const RATE := 22050
const BARS_PER_CHORD := 2
const BEATS_PER_BAR := 4

## scale: semitones from the root. chords: scale degrees (0-based) of each chord root, 4 chords per loop.
const THEMES := [
	{"name": "Đồng cỏ", "root": 60, "bpm": 96, "scale": [0, 2, 4, 5, 7, 9, 11], "chords": [0, 4, 5, 3],
		"lead": "triangle", "seed": 1},  # C major, I-V-vi-IV
	{"name": "Sa mạc", "root": 62, "bpm": 84, "scale": [0, 1, 4, 5, 7, 8, 10], "chords": [0, 1, 0, 6],
		"lead": "square", "seed": 2},  # D phrygian dominant
	{"name": "Rừng tối", "root": 57, "bpm": 72, "scale": [0, 2, 3, 5, 7, 8, 10], "chords": [0, 5, 2, 6],
		"lead": "sine", "seed": 3},  # A natural minor, i-VI-III-VII
]
const BASS_VOL := 0.22
const ARP_VOL := 0.06
const LEAD_VOL := 0.16
const REST_CHANCE := 0.3


static func midi_hz(note: float) -> float:
	return 440.0 * pow(2.0, (note - 69.0) / 12.0)


static func _osc(wave: String, phase: float) -> float:
	match wave:
		"square": return 1.0 if phase < 0.5 else -1.0
		"triangle": return 4.0 * absf(phase - 0.5) - 1.0
		_: return sin(phase * TAU)


## Add one note into the float buffer. Short attack and release so notes never click.
static func _note(buf: PackedFloat32Array, start: int, length: int, hz: float, wave: String, vol: float) -> void:
	var attack := mini(110, length / 4)
	var release := mini(660, length / 2)
	var phase := 0.0
	for i in length:
		var env := 1.0
		if i < attack:
			env = float(i) / attack
		elif i > length - release:
			env = float(length - i) / release
		buf[start + i] += _osc(wave, phase) * env * vol
		phase = fmod(phase + hz / RATE, 1.0)


static func loop_samples(act_index: int) -> int:
	var th: Dictionary = THEMES[act_index]
	var beats: int = th.chords.size() * BARS_PER_CHORD * BEATS_PER_BAR
	return int(beats * 60.0 / th.bpm * RATE)


## Render one act's loop. Same input, same output: the melody comes from a fixed seed.
static func build(act_index: int) -> AudioStreamWAV:
	var th: Dictionary = THEMES[act_index]
	var scale: Array = th.scale
	var total := loop_samples(act_index)
	var beat := int(60.0 / th.bpm * RATE)
	var buf := PackedFloat32Array()
	buf.resize(total)
	var rng := RandomNumberGenerator.new()
	rng.seed = th.seed
	var deg := 0  # current melody scale degree, relative to the chord root
	for c in th.chords.size():
		var root_deg: int = th.chords[c]
		var chord := [root_deg, root_deg + 2, root_deg + 4]  # triad from the scale
		for bar in BARS_PER_CHORD:
			var bar_start: int = (c * BARS_PER_CHORD + bar) * BEATS_PER_BAR * beat
			for b in BEATS_PER_BAR:
				var at := bar_start + b * beat
				_note(buf, at, beat, midi_hz(_pitch(th, scale, root_deg) - 24), "triangle", BASS_VOL)
				for half in 2:  # arpeggio in eighths
					var tone: int = chord[(b * 2 + half) % 3]
					_note(buf, at + half * beat / 2, beat / 2, midi_hz(_pitch(th, scale, tone)), "square", ARP_VOL)
				if rng.randf() < REST_CHANCE and b != 0:
					continue
				if b == 0 or b == 2:  # strong beats land on a chord tone
					deg = chord[rng.randi() % 3] - root_deg
				else:
					deg = clampi(deg + [-2, -1, 1, 2][rng.randi() % 4], -2, 7)
				_note(buf, at, beat, midi_hz(_pitch(th, scale, root_deg + deg) + 12), th.lead, LEAD_VOL)

	var data := PackedByteArray()
	data.resize(total * 2)
	for i in total:
		data.encode_s16(i * 2, clampi(int(buf[i] * 32767.0), -32768, 32767))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = total
	return w


## MIDI pitch of a scale degree (may run past one octave) above the theme root.
static func _pitch(th: Dictionary, scale: Array, d: int) -> int:
	var octave := floori(d / float(scale.size()))
	return th.root + octave * 12 + scale[posmod(d, scale.size())]
