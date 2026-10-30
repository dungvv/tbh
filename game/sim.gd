extends RefCounted
## Combat and economy logic, no rendering. The same numbers drive live play and offline reward.

const WAVES_PER_STAGE := 10
const STAGES_PER_ACT := 10
const ACT_NAMES := ["Đồng cỏ", "Sa mạc", "Rừng tối"]
const MAX_STAGE := STAGES_PER_ACT * 3  # keep in sync with ACT_NAMES (checked by test_sim.gd)
const BOSS_HP_MULT := 4.0
const ACT_BOSS_HP_MULT := 1.2  # extra on top of BOSS_HP_MULT for the X-10 boss

## Balance knobs. Tune with tools/balance.gd.
const HP_BASE := 25.0
const HP_GROWTH := 1.47  # weapon enhancement (ENH_*) is the exponential power source that keeps act 3 moving
const GOLD_BASE := 2.0
const GOLD_GROWTH := 1.3
const EXP_BASE := 3.0
const EXP_GROWTH := 1.25
const LEVEL_EXP_BASE := 80.0
const LEVEL_EXP_GROWTH := 1.2
## Level gap EXP penalty, shaped after the TBH table for a level 30 hero (design doc 5.6).
const STAGE_LEVEL_PER_STAGE := 1.9  # measured with tools/balance.gd: heroes reach stage s around level 1.3-1.9 x s
const OVER_LEVEL_SAFE := 2  # up to 2 levels above the stage: full EXP
const OVER_LEVEL_MID := 8.0  # 50% EXP at 8 levels above
const OVER_LEVEL_SCALE := 1.6
const UNDER_LEVEL_SAFE := 5  # pushing ahead is punished less
const UNDER_LEVEL_STEP := 0.05
const UNDER_LEVEL_MIN := 0.5
const RUNE_COST_MULT := 5.0
## Enhancement: per hero, per gear slot. Weapon compounds (the exponential power source), the others add.
const ENH_WEAPON_MULT := 1.05  # ATK x this per weapon level
const ENH_GLOVES_APS := 0.02
const ENH_RING_GOLD := 0.05
const ENH_COST_BASE := 500.0
const ENH_COST_GROWTH := 1.35
const ENH_SAFE_LEVEL := 5  # up to +5 never fails
const ENH_FAIL_STEP := 0.07  # chance lost per level above that
const ENH_MIN_CHANCE := 0.3
const BOSS_TIME_SEC := 30.0
const CHEST_INTERVAL_SEC := 240.0  # 4 min, design doc 5.3
const CHEST_CAP := 20
const OFFLINE_BASE_CAP_SEC := 4 * 3600  # +1h per "hoard" rune level, up to TBH's 8h
const OFFLINE_VOID_SEC := 30 * 86400  # absent longer = clock tampering, reward 0

const TIERS := ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic"]
const SLOTS := ["weapon", "gloves", "ring"]  # +ATK, +attack speed %, +gold %
const BAG_CAP := 60
const DROP_CHANCE := 0.08
const CHEST_ITEMS := 3
## Synthesis 9 -> 1, per input tier: [chance +1, chance +2]. The rest fails and returns 1 item of the same tier.
## Only the last two steps can fail (design doc 5.4). Mythic cannot be synthesized.
const SYNTH := [[0.95, 0.05], [0.96, 0.04], [0.98, 0.02], [0.80, 0.0025], [0.50, 0.0]]
const SAFE_SYNTH_TIERS := 3  # auto-synth only touches tiers that cannot fail

## Rune tree. `per` is the effect of one level in the unit shown by `fmt` (0 = on/off rune).
## Cost of the next level = cost * grow^level. `at` = [column, row] in the tree panel.
const RUNES := [
	{"id": "growth", "name": "Khởi đầu", "fmt": "+%d%% ATK", "per": 5, "max": 5, "cost": 50, "grow": 1.6, "req": "", "at": [0, 2]},
	{"id": "repose", "name": "Nghỉ ngơi", "fmt": "Mở thưởng offline", "per": 0, "max": 1, "cost": 100, "grow": 1.0, "req": "growth", "at": [1, 0]},
	{"id": "training", "name": "Rèn luyện", "fmt": "+%d%% EXP", "per": 10, "max": 5, "cost": 150, "grow": 1.7, "req": "growth", "at": [1, 1]},
	{"id": "greed", "name": "Tham lam", "fmt": "+%d%% vàng", "per": 8, "max": 5, "cost": 200, "grow": 1.7, "req": "growth", "at": [1, 2]},
	{"id": "haste", "name": "Nhanh nhẹn", "fmt": "+%d%% tốc đánh", "per": 4, "max": 5, "cost": 300, "grow": 1.8, "req": "growth", "at": [1, 4]},
	{"id": "hoard", "name": "Ngủ sâu", "fmt": "+%dh trần offline", "per": 1, "max": 4, "cost": 500, "grow": 2.0, "req": "repose", "at": [2, 0]},
	{"id": "bag", "name": "Túi lớn", "fmt": "+%d ô túi", "per": 10, "max": 4, "cost": 500, "grow": 1.7, "req": "training", "at": [2, 1]},
	{"id": "chest_time", "name": "Đồng hồ cát", "fmt": "−%ds chờ rương", "per": 15, "max": 4, "cost": 400, "grow": 1.8, "req": "greed", "at": [2, 2]},
	{"id": "luck", "name": "May mắn", "fmt": "+%d%% rơi đồ", "per": 2, "max": 5, "cost": 600, "grow": 1.7, "req": "greed", "at": [2, 3]},
	{"id": "might", "name": "Sức mạnh", "fmt": "+%d%% ATK", "per": 10, "max": 5, "cost": 1000, "grow": 1.8, "req": "haste", "at": [2, 4]},
	{"id": "alchemy", "name": "Giả kim", "fmt": "+%d%% giá bán", "per": 10, "max": 5, "cost": 800, "grow": 1.7, "req": "bag", "at": [3, 1]},
	{"id": "chest_cap", "name": "Kho rương", "fmt": "+%d sức chứa rương", "per": 5, "max": 4, "cost": 300, "grow": 1.6, "req": "chest_time", "at": [3, 2]},
	{"id": "fortune", "name": "Vận may", "fmt": "+%d%% lên phẩm", "per": 3, "max": 5, "cost": 1500, "grow": 1.8, "req": "luck", "at": [3, 3]},
	{"id": "focus", "name": "Tập trung", "fmt": "+%ds giờ boss", "per": 3, "max": 5, "cost": 800, "grow": 1.6, "req": "might", "at": [3, 4]},
	{"id": "auto_chest", "name": "Dây cót", "fmt": "Tự mở rương", "per": 0, "max": 1, "cost": 5000, "grow": 1.0, "req": "chest_cap", "at": [4, 2]},
	{"id": "command", "name": "Chỉ huy", "fmt": "Mở ô đội 2: Ranger", "per": 0, "max": 1, "cost": 300, "grow": 1.0, "req": "growth", "at": [1, 5]},
	{"id": "command2", "name": "Chỉ huy II", "fmt": "Mở ô đội 3: Sorcerer", "per": 0, "max": 1, "cost": 30000, "grow": 1.0, "req": "command", "at": [2, 5]},  # x5 = 150k, the TBH price
	# max 0 = no cap: endless gold sinks once the fixed runes are done
	{"id": "mastery", "name": "Bậc thầy", "fmt": "+%d%% ATK", "per": 5, "max": 0, "cost": 4000, "grow": 1.12, "req": "focus", "at": [4, 4]},
	{"id": "wisdom", "name": "Minh triết", "fmt": "+%d%% EXP", "per": 2, "max": 0, "cost": 3000, "grow": 1.15, "req": "alchemy", "at": [4, 1]},
]

## atk/aps are multipliers on the shared base stats. Skills are fixed passives for now.
const CLASSES := {
	"knight": {"name": "Knight", "atk": 1.0, "aps": 1.5, "skill": "Đâm xuyên: đòn thứ 5 gây x3"},
	"ranger": {"name": "Ranger", "atk": 0.7, "aps": 2.2, "skill": "Ngắm bắn: 20% chí mạng x2"},
	"sorcerer": {"name": "Sorcerer", "atk": 1.3, "aps": 0.9, "skill": "Cầu lửa: mỗi 4 giây gây x4"},
}
const PIERCE_EVERY := 5
const PIERCE_MULT := 3.0
const CRIT_CHANCE := 0.2
const CRIT_MULT := 2.0
const FIREBALL_CD := 4.0
const FIREBALL_MULT := 4.0

var stage := 1
var wave := 1
var wave_kills := 0  # kills inside the current wave
var max_stage := 1  # highest unlocked stage; the portal can jump to any stage up to here
var repeat := false  # farm mode: stay on the stage after its boss instead of moving on
## Slot i of the party. Slot 2 (Ranger) only fights once the "command" rune is bought.
## `attacks` and `cd` are runtime-only and not saved.
var heroes := [_new_hero("knight"), _new_hero("ranger"), _new_hero("sorcerer")]
var gold := 0
var kills := 0
var chests := 0
var chest_ready_at := 0.0  # unix time; chests only drop while the game runs
var bag := {}  # "slot:tier" -> count. Items carry no random stats, so a count per kind is the whole bag.
var runes := {}  # id -> level
var rng := RandomNumberGenerator.new()

var monster_hp := 0.0
var monster_max_hp := 0.0
var boss_time_left := 0.0
var last_crit := false  # for the UI: did the latest Ranger shot crit


func _init() -> void:
	rng.randomize()
	_spawn()


static func _new_hero(cls: String) -> Dictionary:
	return {"cls": cls, "level": 1, "xp": 0, "equipped": {"weapon": -1, "gloves": -1, "ring": -1},
		"enh": {"weapon": 0, "gloves": 0, "ring": 0},
		"attacks": 0, "cd": 0.0, "casts": 0, "skill_cd": FIREBALL_CD}


func party_size() -> int:
	return 1 + rune_level("command") + rune_level("command2")


# --- item stats ---

static func sell_value(tier: int) -> int:
	return int(10 * pow(3, tier))  # 9 inputs always sell for more than 1 output: 90 vs 30


static func item_bonus(slot: String, tier: int) -> float:
	if tier < 0:
		return 0.0
	match slot:
		"weapon": return 3.0 * pow(3, tier)  # flat ATK
		"gloves": return 0.05 * (tier + 1)  # attack speed %
		_: return 0.10 * (tier + 1)  # gold %


# --- runes ---

static func rune_def(id: String) -> Dictionary:
	for r in RUNES:
		if r.id == id:
			return r
	return {}


static func is_maxed(r: Dictionary, lv: int) -> bool:
	return r.max > 0 and lv >= r.max


func rune_level(id: String) -> int:
	return runes.get(id, 0)


## Total effect of a rune in its display unit (e.g. 15 for "+15% ATK").
func rv(id: String) -> int:
	return rune_def(id).per * rune_level(id)


func rune_cost(id: String) -> int:
	var r := rune_def(id)
	return int(r.cost * RUNE_COST_MULT * pow(r.grow, rune_level(id)))


func rune_unlocked(id: String) -> bool:
	var req: String = rune_def(id).req
	return req == "" or rune_level(req) > 0


func can_buy_rune(id: String) -> bool:
	return rune_unlocked(id) and not is_maxed(rune_def(id), rune_level(id)) and gold >= rune_cost(id)


func buy_rune(id: String) -> bool:
	if not can_buy_rune(id):
		return false
	gold -= rune_cost(id)
	runes[id] = rune_level(id) + 1
	return true


# --- derived stats ---

func hero_atk(i := 0) -> float:
	var h: Dictionary = heroes[i]
	var base: float = 5.0 + 2.0 * (h.level - 1) + item_bonus("weapon", h.equipped.weapon)
	return base * CLASSES[h.cls].atk * pow(ENH_WEAPON_MULT, h.enh.weapon) * (1.0 + (rv("growth") + rv("might") + rv("mastery")) / 100.0)


func hero_aps(i := 0) -> float:
	var h: Dictionary = heroes[i]
	return CLASSES[h.cls].aps * (1.0 + item_bonus("gloves", h.equipped.gloves) + ENH_GLOVES_APS * h.enh.gloves + rv("haste") / 100.0)


## Average damage per second of the active party, skills included.
func team_dps() -> float:
	var dps := 0.0
	for i in party_size():
		match heroes[i].cls:
			"knight": dps += hero_atk(i) * hero_aps(i) * (1.0 + (PIERCE_MULT - 1.0) / PIERCE_EVERY)
			"ranger": dps += hero_atk(i) * hero_aps(i) * (1.0 + CRIT_CHANCE * (CRIT_MULT - 1.0))
			_: dps += hero_atk(i) * (hero_aps(i) + FIREBALL_MULT / FIREBALL_CD)
	return dps


## Rings on every active hero stack.
func gold_mult() -> float:
	var m := 1.0 + rv("greed") / 100.0
	for i in party_size():
		m += item_bonus("ring", heroes[i].equipped.ring) + ENH_RING_GOLD * heroes[i].enh.ring
	return m


func chest_interval() -> float:
	return CHEST_INTERVAL_SEC - rv("chest_time")


func chest_cap() -> int:
	return CHEST_CAP + rv("chest_cap")


func bag_cap() -> int:
	return BAG_CAP + rv("bag")


func sell_price(tier: int) -> int:
	return int(sell_value(tier) * (1.0 + rv("alchemy") / 100.0))


func offline_cap() -> float:
	return OFFLINE_BASE_CAP_SEC + rv("hoard") * 3600


func is_boss() -> bool:
	return wave > WAVES_PER_STAGE


func act() -> int:
	return (stage - 1) / STAGES_PER_ACT + 1


func local_stage() -> int:
	return (stage - 1) % STAGES_PER_ACT + 1


## Waves get crowded deeper into an act: 1 monster at X-1, 7 at X-10.
func mobs_per_wave() -> int:
	return 1 + (local_stage() - 1) * 2 / 3


## Stage X-10 ends with the act boss instead of a regular stage boss.
func is_act_boss() -> bool:
	return is_boss() and local_stage() == STAGES_PER_ACT


func exp_to_next(i := 0) -> int:
	return int(LEVEL_EXP_BASE * pow(LEVEL_EXP_GROWTH, heroes[i].level - 1))


func _base_hp(w: int) -> float:
	return HP_BASE * pow(HP_GROWTH, stage - 1) * (1.0 + 0.1 * (w - 1))


func _gold_per_kill() -> int:
	return int(GOLD_BASE * pow(GOLD_GROWTH, stage - 1) * gold_mult())


func _exp_per_kill() -> int:
	return int(EXP_BASE * pow(EXP_GROWTH, stage - 1) * (1.0 + (rv("training") + rv("wisdom")) / 100.0))


func _spawn() -> void:
	if is_boss():
		monster_max_hp = _base_hp(WAVES_PER_STAGE) * BOSS_HP_MULT * (ACT_BOSS_HP_MULT if is_act_boss() else 1.0)
		boss_time_left = BOSS_TIME_SEC + rv("focus")
	else:
		monster_max_hp = _base_hp(wave)
	monster_hp = monster_max_hp


# --- combat ---

## Advance combat by dt seconds. `now` is unix time, used for chest drops.
func step(dt: float, now: float) -> void:
	if chest_ready_at == 0.0:
		chest_ready_at = now + chest_interval()
	if now >= chest_ready_at:
		chests = mini(chests + 1, chest_cap())
		chest_ready_at = now + chest_interval()
		if rune_level("auto_chest") > 0:
			open_chest()

	if is_boss():
		boss_time_left -= dt
		if boss_time_left <= 0.0:
			wave = 1  # failed the boss: replay the stage, like TBH
			_spawn()
			return

	for i in party_size():
		var h: Dictionary = heroes[i]
		h.cd -= dt
		if h.cls == "sorcerer":
			h.skill_cd -= dt
			if h.skill_cd <= 0.0:
				h.skill_cd += FIREBALL_CD
				h.casts += 1
				monster_hp -= hero_atk(i) * FIREBALL_MULT
				if monster_hp <= 0.0:
					_on_kill()
					return
		while h.cd <= 0.0:
			h.cd += 1.0 / hero_aps(i)
			h.attacks += 1
			monster_hp -= _hit_damage(i)
			if monster_hp <= 0.0:
				_on_kill()
				return


func _hit_damage(i: int) -> float:
	var h: Dictionary = heroes[i]
	var dmg := hero_atk(i)
	if h.cls == "knight" and h.attacks % PIERCE_EVERY == 0:
		dmg *= PIERCE_MULT
	elif h.cls == "ranger":
		last_crit = rng.randf() < CRIT_CHANCE
		if last_crit:
			dmg *= CRIT_MULT
	return dmg


func _on_kill() -> void:
	var boss := is_boss()
	var mult := 5 if boss else 1
	kills += 1
	gold += _gold_per_kill() * mult
	for i in party_size():  # every active hero gets full exp, like a TBH party
		_gain_exp(i, int(_exp_per_kill() * mult * hero_exp_mult(i)))
	if boss:
		for i in 2:
			add_item(SLOTS[rng.randi() % SLOTS.size()], _roll_tier(1))
		wave = 1
		max_stage = maxi(max_stage, mini(stage + 1, MAX_STAGE))
		if not repeat:
			stage = mini(stage + 1, MAX_STAGE)
	else:
		if rng.randf() < DROP_CHANCE + rv("luck") / 100.0:
			add_item(SLOTS[rng.randi() % SLOTS.size()], _roll_tier(0))
		wave_kills += 1
		if wave_kills >= mobs_per_wave():
			wave_kills = 0
			wave += 1
	_spawn()


func _gain_exp(i: int, amount: int) -> void:
	var h: Dictionary = heroes[i]
	h.xp += amount
	while h.xp >= exp_to_next(i):
		h.xp -= exp_to_next(i)
		h.level += 1


## Each step up has a chance that grows with stage. Act 1 drops stop at Epic, act 2 at Legendary, act 3 at Mythic.
func _roll_tier(floor_tier: int) -> int:
	var tier := floor_tier
	while tier < 2 + act() and rng.randf() < 0.2 + 0.015 * stage + rv("fortune") / 100.0:
		tier += 1
	return tier


func open_chest() -> bool:
	if chests <= 0:
		return false
	chests -= 1
	gold += 20 * stage
	for i in CHEST_ITEMS:
		add_item(SLOTS[rng.randi() % SLOTS.size()], _roll_tier(0))
	return true


# --- bag ---

static func key(slot: String, tier: int) -> String:
	return "%s:%d" % [slot, tier]


func count(slot: String, tier: int) -> int:
	return bag.get(key(slot, tier), 0)


func bag_total() -> int:
	var n := 0
	for c in bag.values():
		n += c
	return n


## Full bag: the item is sold on the spot instead of lost.
func add_item(slot: String, tier: int) -> bool:
	if bag_total() >= bag_cap():
		gold += sell_price(tier)
		return false
	bag[key(slot, tier)] = count(slot, tier) + 1
	return true


func _take(slot: String, tier: int, n: int) -> void:
	var left := count(slot, tier) - n
	if left > 0:
		bag[key(slot, tier)] = left
	else:
		bag.erase(key(slot, tier))


func sell(slot: String, tier: int, n: int) -> int:
	n = mini(n, count(slot, tier))
	_take(slot, tier, n)
	var g := n * sell_price(tier)
	gold += g
	return g


## Swap the bag item into hero `i`'s slot; the old one goes back to the bag.
func equip(slot: String, tier: int, i := 0) -> bool:
	if count(slot, tier) <= 0:
		return false
	var eq: Dictionary = heroes[i].equipped
	_take(slot, tier, 1)
	if eq[slot] >= 0:
		bag[key(slot, eq[slot])] = count(slot, eq[slot]) + 1
	eq[slot] = tier
	return true


## 9 same slot + same tier -> 1. Returns {} if not possible, else {"tier": result, "kind": "up"|"great"|"fail"}.
func synth(slot: String, tier: int) -> Dictionary:
	if tier >= SYNTH.size() or count(slot, tier) < 9:
		return {}
	_take(slot, tier, 9)
	var r := rng.randf()
	var res := {"tier": tier, "kind": "fail"}
	if r < SYNTH[tier][1]:
		res = {"tier": mini(tier + 2, TIERS.size() - 1), "kind": "great"}
	elif r < SYNTH[tier][0] + SYNTH[tier][1]:
		res = {"tier": tier + 1, "kind": "up"}
	bag[key(slot, res.tier)] = count(slot, res.tier) + 1
	return res


## Synthesize every safe group until none has 9 left. Returns how many synths ran.
func auto_synth() -> int:
	var n := 0
	for tier in SAFE_SYNTH_TIERS:
		for slot in SLOTS:
			while count(slot, tier) >= 9:
				synth(slot, tier)
				n += 1
	return n


# --- offline and save ---

## Gold and xp for `elapsed` seconds away. Needs the "repose" rune, like TBH. No chests or items offline.
# ponytail: kill rate estimated from a mid-wave monster, ignores boss walls; simulate if offline balance matters
func offline_reward(elapsed: float) -> Dictionary:
	if rune_level("repose") == 0 or elapsed <= 0.0 or elapsed > OFFLINE_VOID_SEC:
		return {"gold": 0, "xp": 0}
	var t := minf(elapsed, offline_cap())
	var kills_per_sec := minf(team_dps() / _base_hp(5), 1.0)
	return {
		"gold": int(t * kills_per_sec * _gold_per_kill()),
		"xp": int(t * kills_per_sec * _exp_per_kill()),  # per active hero
	}


func apply_offline(elapsed: float) -> Dictionary:
	var r := offline_reward(elapsed)
	gold += r.gold
	for i in party_size():
		_gain_exp(i, int(r.xp * hero_exp_mult(i)))  # TBH 1.3.0: the penalty applies offline too
	return r


func to_dict() -> Dictionary:
	var hs := []
	for h in heroes:
		hs.append({"cls": h.cls, "level": h.level, "xp": h.xp, "equipped": h.equipped, "enh": h.enh})
	return {
		"stage": stage, "max_stage": max_stage, "repeat": repeat, "wave": mini(wave, WAVES_PER_STAGE), "heroes": hs,
		"gold": gold, "kills": kills, "chests": chests, "bag": bag, "runes": runes,
	}


func from_dict(d: Dictionary) -> void:
	stage = clampi(int(d.get("stage", 1)), 1, MAX_STAGE)
	max_stage = clampi(maxi(int(d.get("max_stage", 1)), stage), 1, MAX_STAGE)  # old saves: the current stage was the furthest
	repeat = bool(d.get("repeat", false))
	wave = int(d.get("wave", 1))
	gold = int(d.get("gold", 0))
	kills = int(d.get("kills", 0))
	chests = int(d.get("chests", 0))
	bag = {}
	for k in d.get("bag", {}):
		bag[k] = int(d.bag[k])  # JSON turns ints into floats
	# Saves before the party existed kept level/xp/equipped at the top level: that was the Knight.
	var saved: Array = d.get("heroes", [{"level": d.get("level", 1), "xp": d.get("xp", 0), "equipped": d.get("equipped", {})}])
	for i in heroes.size():
		var src: Dictionary = saved[i] if i < saved.size() else {}
		var h: Dictionary = heroes[i]
		h.level = maxi(1, int(src.get("level", 1)))
		h.xp = int(src.get("xp", 0))
		for s in SLOTS:
			h.equipped[s] = int(src.get("equipped", {}).get(s, -1))
			h.enh[s] = maxi(0, int(src.get("enh", {}).get(s, 0)))
	runes = {}
	for r in RUNES:  # only known ids, clamped to max: a hand-edited save cannot overshoot
		var lv := clampi(int(d.get("runes", {}).get(r.id, 0)), 0, r.max if r.max > 0 else 100000)
		if lv > 0:
			runes[r.id] = lv
	_spawn()


# --- enhancement ---

func enh_cost(i: int, slot: String) -> int:
	return int(ENH_COST_BASE * pow(ENH_COST_GROWTH, heroes[i].enh[slot]))


## Chance that the next level succeeds.
static func enh_chance(level: int) -> float:
	return clampf(1.0 - maxi(0, level - ENH_SAFE_LEVEL + 1) * ENH_FAIL_STEP, ENH_MIN_CHANCE, 1.0)


## Pays the cost and rolls. Returns {} if gold is short, else {"ok": bool, "level": new level}.
## A failure only costs gold; the level never drops.
func enhance(i: int, slot: String) -> Dictionary:
	var cost := enh_cost(i, slot)
	if gold < cost:
		return {}
	gold -= cost
	var eh: Dictionary = heroes[i].enh
	var ok := rng.randf() < enh_chance(eh[slot])
	if ok:
		eh[slot] += 1
	return {"ok": ok, "level": eh[slot]}


# --- portal ---

## Jump to an unlocked stage, starting from its first wave. Returns false if it is still locked.
func go_to_stage(s: int) -> bool:
	if s < 1 or s > max_stage:
		return false
	stage = s
	wave = 1
	wave_kills = 0
	_spawn()
	return true


# --- level gap ---

func stage_level(s := -1) -> int:
	return maxi(1, roundi(STAGE_LEVEL_PER_STAGE * (stage if s < 0 else s)))


## EXP multiplier for a hero `diff` levels above (positive) or below (negative) the stage.
static func exp_mult(diff: int) -> float:
	if diff > OVER_LEVEL_SAFE:
		return 1.0 / (1.0 + exp((diff - OVER_LEVEL_MID) / OVER_LEVEL_SCALE))
	if diff < -UNDER_LEVEL_SAFE:
		return maxf(UNDER_LEVEL_MIN, 1.0 - UNDER_LEVEL_STEP * (-diff - UNDER_LEVEL_SAFE))
	return 1.0


func hero_exp_mult(i: int) -> float:
	return exp_mult(heroes[i].level - stage_level())
