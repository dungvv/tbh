extends RefCounted
## All design data in one place (docs/core-rpg-quyet-dinh.docx). Rules live in sim.gd, drawing in main.gd.

# --- progression ---
const STAGES_PER_ACT := 10
const ACT_NAMES := ["Đồng Cỏ", "Sa Mạc", "Rừng Tối"]
const STAGES := 30
const WAVES := 10
## Q13.2 C: 4 difficulties. Stage level range per difficulty (TBH: 1–32 / 33–52 / 53–77 / 78–95)
## and the magic-resist penalty heroes take there (TBH −20 / −40 / −60).
const DIFFS := [
	{"name": "Thường", "lv": [1, 32], "mres_pen": 0},
	{"name": "Ác Mộng", "lv": [33, 52], "mres_pen": 20},
	{"name": "Địa Ngục", "lv": [53, 77], "mres_pen": 40},
	{"name": "Đày Đọa", "lv": [78, 95], "mres_pen": 60},
]
const LEVEL_CAP := 60  # Q5.3 A
const SKILL_POINTS_PER_LEVEL := 5  # Q4.5 note
const SKILL_MAX := 25
const REVIVE_SEC := 8.0
const PARTY_SLOTS := 3  # Q4.3 A

## Q2.4 B: systems open as the player progresses. Value = stage index (1..30) on Normal that must be reached.
const UNLOCK_AT := {"rune": 2, "forge": 3, "hero": 4, "portal": 10, "reroll": 11}

# --- balance knobs (tuned with tools/balance.gd) ---
const MOB_HP0 := 24.0
const MOB_HP_GROWTH := 1.095  # per stage level, up to MOB_KNEE_LV
const MOB_KNEE_LV := 52  # end of Nightmare: heroes hit the level cap around here
const MOB_HP_GROWTH2 := 1.055  # per level after the knee
const MOB_ATK0 := 3.0
const MOB_ATK_GROWTH := 1.075
const MOB_ATK_GROWTH2 := 1.01
const MOB_ARMOR_PER_LV := 1.5
const GOLD0 := 2.0
const GOLD_GROWTH := 1.065
const GOLD_GROWTH2 := 1.03
const EXP0 := 3.0
const EXP_GROWTH := 1.075
const LEVEL_EXP0 := 80.0  # Master: EXP needed = 80 × 1.2^(level−1)
const LEVEL_EXP_GROWTH := 1.2
const BOSS_HP := 4.0
const BOSS_ATK := 2.5
const ACT_BOSS_HP := 4.8
const ACT_BOSS_ATK := 3.0
const ELITE_CHANCE := 0.08
const ELITE_HP := 2.5
## Strength of each elite affix when a monster has 1..4 of them: the multipliers stack, so a 4-affix elite
## at full strength outlasts the act boss (bot: 95% of Torment wipes). 1 = as listed in ELITE_AFFIXES.
const ELITE_AFFIX_POWER := [1.0, 0.75, 0.55, 0.4]
const FIRST_KILL_GOLD := 5.0  # Q13.4 note: the first boss kill pays much more

# --- classes (Q4.2 C: 6 classes; Q4.10/4.11 tables) ---
## dmg: "phys" is stopped by armor, "magic" by magic resist (Q6.1 B). range: melee hits the front monster.
const CLASSES := {
	"knight": {"name": "Hiệp Sĩ", "short": "Hiệp", "role": "Tank", "dmg": "phys", "range": "melee",
		"hp": 120, "atk": 10, "armor": 8, "mres": 10, "aspd": 1.4, "crit": 0.05, "critdmg": 1.5, "block": 0.10,
		"g_hp": 12, "g_atk": 2.0, "g_armor": 1.2, "weapon": "sword", "armor_kind": "heavy", "unlock": ""},
	"ranger": {"name": "Cung Thủ", "short": "Cung", "role": "Tầm xa", "dmg": "phys", "range": "ranged",
		"hp": 80, "atk": 9, "armor": 3, "mres": 10, "aspd": 2.0, "crit": 0.15, "critdmg": 1.75,
		"g_hp": 7, "g_atk": 1.9, "g_armor": 0.5, "weapon": "bow", "armor_kind": "light", "unlock": "unlock_ranger"},
	"sorcerer": {"name": "Pháp Sư", "short": "Pháp", "role": "Diệt boss", "dmg": "magic", "range": "ranged",
		"hp": 70, "atk": 13, "armor": 2, "mres": 20, "aspd": 1.0, "crit": 0.05, "critdmg": 1.5,
		"g_hp": 6, "g_atk": 2.6, "g_armor": 0.4, "weapon": "staff", "armor_kind": "robe", "unlock": "unlock_sorcerer"},
	"cleric": {"name": "Tu Sĩ", "short": "Tu", "role": "Hồi máu", "dmg": "magic", "range": "ranged",
		"hp": 85, "atk": 7, "armor": 4, "mres": 20, "aspd": 1.2, "crit": 0.05, "critdmg": 1.5,
		"g_hp": 8, "g_atk": 1.4, "g_armor": 0.6, "weapon": "holy", "armor_kind": "robe", "unlock": "unlock_cleric"},
	"berserker": {"name": "Cuồng Chiến", "short": "Cuồng", "role": "Cận chiến", "dmg": "phys", "range": "melee",
		"hp": 110, "atk": 11, "armor": 5, "mres": 10, "aspd": 1.3, "crit": 0.08, "critdmg": 1.6, "lifesteal": 0.05,
		"g_hp": 11, "g_atk": 2.2, "g_armor": 0.8, "weapon": "axe", "armor_kind": "heavy", "unlock": "unlock_berserker"},
	"assassin": {"name": "Sát Thủ", "short": "Sát", "role": "Chí mạng", "dmg": "phys", "range": "melee",
		"hp": 75, "atk": 10, "armor": 3, "mres": 10, "aspd": 1.8, "crit": 0.25, "critdmg": 2.0, "dodge": 0.10,
		"g_hp": 7, "g_atk": 2.0, "g_armor": 0.5, "weapon": "dagger", "armor_kind": "light", "unlock": "unlock_assassin"},
}
## Q15.1 B: equipment shows on the 3D model (art3d/<class>.glb, KayKit). gear = optional meshes, all hidden
## except `low` (weapon below rarity view3d.HIGH_WEAPON) or `high`; the knight's shield follows armor rarity.
## hat is hidden by the second outfit (Q15.4 B).
const HERO_MODELS := {
	"knight": {"gear": ["1H_Sword", "1H_Sword_Offhand", "2H_Sword", "Badge_Shield", "Rectangle_Shield", "Round_Shield", "Spike_Shield"],
		"low": ["1H_Sword"], "high": ["1H_Sword"], "hat": "Knight_Helmet",
		"shields": ["Round_Shield", "Round_Shield", "Badge_Shield", "Badge_Shield", "Rectangle_Shield", "Spike_Shield"]},
	"ranger": {"gear": ["Knife", "Knife_Offhand", "1H_Crossbow", "2H_Crossbow", "Throwable"], "low": ["1H_Crossbow"], "high": ["2H_Crossbow"], "hat": ""},
	"sorcerer": {"gear": ["1H_Wand", "2H_Staff", "Spellbook", "Spellbook_open"], "low": ["1H_Wand", "Spellbook"], "high": ["2H_Staff"], "hat": "Mage_Hat"},
	"cleric": {"gear": ["1H_Wand", "2H_Staff", "Spellbook", "Spellbook_open"], "low": ["1H_Wand", "Spellbook_open"], "high": ["2H_Staff", "Spellbook_open"], "hat": "Mage_Hat"},
	"berserker": {"gear": ["1H_Axe", "1H_Axe_Offhand", "Barbarian_Round_Shield", "2H_Axe", "Mug"], "low": ["1H_Axe", "Barbarian_Round_Shield"], "high": ["2H_Axe"], "hat": "Barbarian_Hat"},
	"assassin": {"gear": ["Knife", "Knife_Offhand", "1H_Crossbow", "2H_Crossbow", "Throwable"], "low": ["Knife", "Knife_Offhand"], "high": ["Knife", "Knife_Offhand"], "hat": ""},
}
const CLASS_ORDER := ["knight", "ranger", "sorcerer", "cleric", "berserker", "assassin"]

## Skills: 3 actives per class + 6 shared passives, each up to 25 points (Q4.5 note: 5 points per level).
## trigger: "hits" = every N basic attacks, "cd" = cooldown in seconds.
## kind: dmg (target), aoe (all monsters), multi (n hits on random targets), heal, revive, buff, execute.
## base/per: effect at 1 point and added per extra point. req = points spent in this class before it unlocks.
const SKILLS := {
	"knight": [
		{"id": "k_pierce", "name": "Chém Xuyên", "trigger": "hits", "n": 5, "kind": "dmg", "base": 3.0, "per": 0.08, "req": 0, "fx": "sword-slash"},
		{"id": "k_wall", "name": "Tường Khiên", "trigger": "cd", "n": 12, "kind": "buff", "stat": "dmg_reduce", "base": 0.30, "per": 0.01, "dur": 5, "req": 10, "fx": "divine-shield"},
		{"id": "k_slam", "name": "Chấn Động", "trigger": "cd", "n": 10, "kind": "aoe", "base": 1.5, "per": 0.05, "req": 25, "fx": "heavy-cleave"},
	],
	"ranger": [
		{"id": "r_volley", "name": "Liên Xạ", "trigger": "hits", "n": 4, "kind": "multi", "hits": 3, "base": 0.6, "per": 0.03, "req": 0, "fx": "arrow"},
		{"id": "r_pierce", "name": "Tên Xuyên Thấu", "trigger": "cd", "n": 8, "kind": "aoe", "base": 2.5, "per": 0.08, "req": 10, "fx": "crit-hit"},
		{"id": "r_haste", "name": "Gió Lốc", "trigger": "cd", "n": 15, "kind": "buff", "stat": "aspd_pct", "base": 0.40, "per": 0.01, "dur": 5, "req": 25, "fx": "haste"},
	],
	"sorcerer": [
		{"id": "s_fireball", "name": "Cầu Lửa", "trigger": "cd", "n": 4, "kind": "dmg", "base": 4.0, "per": 0.12, "req": 0, "fx": "fireball"},
		{"id": "s_missile", "name": "Phi Đạn Phép", "trigger": "hits", "n": 3, "kind": "dmg", "base": 1.5, "per": 0.05, "req": 10, "fx": "magic-missile"},
		{"id": "s_ring", "name": "Vòng Lửa", "trigger": "cd", "n": 12, "kind": "aoe", "base": 2.0, "per": 0.06, "req": 25, "fx": "fire-ring"},
	],
	"cleric": [
		{"id": "c_heal", "name": "Hồi Máu", "trigger": "cd", "n": 5, "kind": "heal", "base": 3.0, "per": 0.10, "req": 0, "fx": "heal"},
		{"id": "c_smite", "name": "Phán Quyết", "trigger": "hits", "n": 4, "kind": "dmg", "base": 2.5, "per": 0.08, "req": 10, "fx": "smite"},
		{"id": "c_revive", "name": "Hồi Sinh", "trigger": "cd", "n": 30, "kind": "revive", "base": 0.5, "per": 0.01, "req": 25, "fx": "respawn-beam"},
	],
	"berserker": [
		{"id": "b_spin", "name": "Xoáy Rìu", "trigger": "hits", "n": 4, "kind": "aoe", "base": 1.2, "per": 0.05, "req": 0, "fx": "spin-slash"},
		{"id": "b_rage", "name": "Cuồng Nộ", "trigger": "cd", "n": 15, "kind": "buff", "stat": "atk_pct", "base": 0.40, "per": 0.015, "dur": 6, "req": 10, "fx": "rage"},
		{"id": "b_blood", "name": "Máu Chiến", "trigger": "passive", "n": 0, "kind": "berserk", "base": 0.5, "per": 0.02, "req": 25, "fx": ""},
	],
	"assassin": [
		{"id": "a_flurry", "name": "Liên Đao", "trigger": "hits", "n": 3, "kind": "multi", "hits": 4, "base": 0.5, "per": 0.02, "req": 0, "fx": "dagger-flurry"},
		{"id": "a_kill", "name": "Ám Sát", "trigger": "cd", "n": 10, "kind": "execute", "base": 5.0, "per": 0.15, "req": 10, "fx": "crit-hit"},
		{"id": "a_shadow", "name": "Ẩn Thân", "trigger": "cd", "n": 14, "kind": "buff", "stat": "dodge", "base": 0.40, "per": 0.01, "dur": 4, "req": 25, "fx": "poof"},
	],
}
const PASSIVES := [
	{"id": "p_atk", "name": "Sức Mạnh", "stat": "atk_pct", "per": 0.01},
	{"id": "p_hp", "name": "Thể Lực", "stat": "hp_pct", "per": 0.015},
	{"id": "p_armor", "name": "Bền Bỉ", "stat": "armor_pct", "per": 0.02},
	{"id": "p_mres", "name": "Kháng Phép", "stat": "mres", "per": 0.4},
	{"id": "p_crit", "name": "Chính Xác", "stat": "crit", "per": 0.003},
	{"id": "p_aspd", "name": "Nhanh Nhẹn", "stat": "aspd_pct", "per": 0.006},
]

# --- monsters (3D models in art3d/) ---
## role: melee hits the front hero; ranged picks a random hero; pierce hits every hero (Q6.2 note).
## Ranged types only appear from local stage `from`.
## 3D models live in art3d/ (built by tools/build_models.py). size = height on screen relative to a hero.
const MOBS := {
	"slime": {"name": "Slime Hồng", "hp": 0.9, "atk": 1.0, "aspd": 1.2, "armor": 0.8, "mres": 0, "dodge": 0.05, "role": "melee", "dmg": "phys", "model": "slime", "size": 0.55},
	"mushnub": {"name": "Nấm Lùn", "hp": 1.1, "atk": 0.9, "aspd": 0.9, "armor": 1.0, "mres": 5, "dodge": 0.0, "role": "melee", "dmg": "phys", "model": "mushnub", "size": 0.7},
	"frog": {"name": "Ếch Độc", "hp": 1.4, "atk": 0.8, "aspd": 0.7, "armor": 1.4, "mres": 10, "dodge": 0.0, "role": "melee", "dmg": "phys", "model": "frog", "size": 0.8},
	"goleling": {"name": "Dơi Sừng", "hp": 0.7, "atk": 1.1, "aspd": 0.8, "armor": 0.5, "mres": 20, "dodge": 0.10, "role": "ranged", "dmg": "magic", "model": "goleling", "size": 0.5, "fly": true, "from": 5},
	"orc": {"name": "Chiến Binh Orc", "hp": 1.2, "atk": 1.1, "aspd": 1.0, "armor": 1.3, "mres": 5, "dodge": 0.0, "role": "melee", "dmg": "phys", "model": "orc", "size": 0.95},
	"skeleton": {"name": "Bộ Xương", "hp": 0.8, "atk": 1.0, "aspd": 1.4, "armor": 0.7, "mres": 15, "dodge": 0.08, "role": "melee", "dmg": "phys", "model": "skeleton", "size": 0.9},
	"cactoro": {"name": "Xương Rồng", "hp": 1.6, "atk": 0.9, "aspd": 0.8, "armor": 1.8, "mres": 10, "dodge": 0.0, "role": "melee", "dmg": "phys", "model": "cactoro", "size": 1.0},
	"tribal": {"name": "Pháp Sư Mặt Nạ", "hp": 0.8, "atk": 1.2, "aspd": 0.8, "armor": 0.6, "mres": 25, "dodge": 0.05, "role": "ranged", "dmg": "magic", "model": "tribal", "size": 0.85, "fly": true, "from": 4},
	"blue_demon": {"name": "Quỷ Xanh", "hp": 1.1, "atk": 1.2, "aspd": 1.1, "armor": 1.1, "mres": 15, "dodge": 0.05, "role": "melee", "dmg": "phys", "model": "blue_demon", "size": 0.95},
	"ghost": {"name": "Bóng Ma", "hp": 1.0, "atk": 1.0, "aspd": 1.3, "armor": 0.9, "mres": 15, "dodge": 0.12, "role": "melee", "dmg": "phys", "model": "ghost", "size": 0.8, "fly": true},
	"yeti": {"name": "Người Tuyết", "hp": 1.5, "atk": 0.9, "aspd": 0.8, "armor": 1.5, "mres": 20, "dodge": 0.0, "role": "melee", "dmg": "magic", "model": "yeti", "size": 1.0},
	"skeleton_mage": {"name": "Pháp Sư Xương", "hp": 0.9, "atk": 1.0, "aspd": 0.7, "armor": 0.7, "mres": 30, "dodge": 0.05, "role": "pierce", "dmg": "magic", "model": "skeleton_mage", "size": 0.95, "from": 3},
}
const ACT_MOBS := [["slime", "mushnub", "frog", "goleling"], ["orc", "skeleton", "cactoro", "tribal"], ["blue_demon", "ghost", "yeti", "skeleton_mage"]]
const ACT_BOSSES := [
	{"name": "Vua Nấm Gai", "model": "mushroom_king", "size": 1.7},
	{"name": "Vua Xương Rồng", "model": "cactus_king", "size": 1.6},
	{"name": "Rồng Lửa", "model": "dragon", "size": 1.6, "fly": true},
]
## Q6.10 B: boss skills. slam = telegraphed hit on every hero, summon = 2 adds, enrage = faster below 30% HP.
const BOSS_SKILLS := ["slam", "summon", "enrage"]
const SLAM_CD := 9.0
const SLAM_WARN := 1.5
const SLAM_MULT := 1.6
const SUMMON_CD := 16.0

## Q14.3 B / Q14.4 A: elite affixes. `bad` lists affixes that cannot appear together.
const ELITE_AFFIXES := {
	"tough": {"name": "Cứng Cáp", "hp": 2.0},
	"fierce": {"name": "Hung Hãn", "atk": 1.5},
	"swift": {"name": "Nhanh Nhẹn", "aspd": 1.4},
	"armored": {"name": "Bọc Giáp", "armor": 2.0},
	"regen": {"name": "Hồi Phục", "regen": 0.02},
	"thorns": {"name": "Phản Đòn", "thorns": 0.2},
	"evasive": {"name": "Né Tránh", "dodge": 0.25},
	"summoner": {"name": "Triệu Hồi", "bad": ["splitter"]},
	"splitter": {"name": "Tách Đôi", "bad": ["summoner"]},
	"arcane": {"name": "Phép Thuật", "magic": true},
	"golden": {"name": "Vàng Ròng", "gold": 4.0},
	"treasure": {"name": "Kho Báu", "loot": true},
}

# --- items (Q7) ---
## Q7.1 B: weapon and armor follow the class; the other four are shared.
const SLOTS := ["weapon", "armor", "helm", "boots", "gloves", "accessory"]
const SLOT_NAMES := {"weapon": "Vũ khí", "armor": "Giáp", "helm": "Mũ", "boots": "Giày", "gloves": "Găng", "accessory": "Trang sức"}
const WEAPON_NAMES := {"sword": "Kiếm", "bow": "Cung", "staff": "Trượng", "holy": "Pháp Trượng", "axe": "Rìu", "dagger": "Song Đao"}
const ARMOR_NAMES := {"heavy": "Giáp Nặng", "light": "Giáp Nhẹ", "robe": "Áo Choàng"}
## Q7.2 B names, Q7.5 B drop weights (Master), stat multiplier, affix count (Q7.4 C), max affix quality.
const RARITIES := [
	{"name": "Common", "vn": "Thường", "w": 70.0, "mult": 1.0, "affixes": 0, "qmax": 0, "color": Color(0.85, 0.85, 0.85)},
	{"name": "Uncommon", "vn": "Khá", "w": 20.0, "mult": 1.5, "affixes": 0, "qmax": 0, "color": Color(0.35, 0.8, 0.35)},
	{"name": "Rare", "vn": "Hiếm", "w": 7.5, "mult": 2.2, "affixes": 1, "qmax": 6, "color": Color(0.3, 0.55, 1.0)},
	{"name": "Mystical", "vn": "Huyền Bí", "w": 2.0, "mult": 3.2, "affixes": 2, "qmax": 8, "color": Color(0.66, 0.33, 0.97)},
	{"name": "Legendary", "vn": "Huyền Thoại", "w": 0.4, "mult": 4.8, "affixes": 3, "qmax": 10, "color": Color(1.0, 0.6, 0.1)},
	{"name": "Immortal", "vn": "Bất Tử", "w": 0.1, "mult": 7.0, "affixes": 4, "qmax": 10, "color": Color(0.95, 0.2, 0.25)},
]
const IMMORTAL_PITY := 1000  # Q7.5 note: chests without an Immortal before one is guaranteed
## Main stat per slot at Common (× rarity mult × enhancement).
const MAIN_STATS := {
	"weapon": {"atk": 6.0},
	"armor": {"hp": 30.0, "armor": 3.0},
	"helm": {"hp": 18.0, "mres": 2.0},
	"boots": {"aspd_pct": 0.025},
	"gloves": {"crit": 0.012},
	"accessory": {"atk_pct": 0.03},
}
## Affix pool: [stat, low, high] at quality 1 and 10. Quality colors follow MU (Master III.3).
const AFFIXES := {
	"atk_pct": {"name": "Sát thương", "lo": 0.03, "hi": 0.25, "pct": true},
	"crit": {"name": "Chí mạng", "lo": 0.02, "hi": 0.15, "pct": true},
	"critdmg": {"name": "ST chí mạng", "lo": 0.10, "hi": 0.60, "pct": true},
	"aspd_pct": {"name": "Tốc đánh", "lo": 0.02, "hi": 0.12, "pct": true},
	"skill_dmg": {"name": "ST kỹ năng", "lo": 0.05, "hi": 0.35, "pct": true},
	"dmg_boss": {"name": "ST lên boss", "lo": 0.03, "hi": 0.25, "pct": true},
	"hp_pct": {"name": "Máu", "lo": 0.03, "hi": 0.25, "pct": true},
	"armor_pct": {"name": "Giáp", "lo": 0.05, "hi": 0.40, "pct": true},
	"mres": {"name": "Kháng phép", "lo": 2.0, "hi": 15.0, "pct": false},
	"dmg_reduce": {"name": "Giảm sát thương", "lo": 0.01, "hi": 0.08, "pct": true},
	"block": {"name": "Chặn đòn", "lo": 0.02, "hi": 0.10, "pct": true},
	"gold": {"name": "Vàng", "lo": 0.03, "hi": 0.20, "pct": true},
	"exp": {"name": "EXP", "lo": 0.02, "hi": 0.15, "pct": true},
	"mf": {"name": "Rơi đồ", "lo": 0.01, "hi": 0.08, "pct": true},
}
const QUALITY_COLORS := [Color(1, 1, 1), Color(0.63, 0.63, 0.63), Color(0.23, 0.51, 0.96), Color(0.66, 0.33, 0.97), Color(0.92, 0.70, 0.03)]

# --- defense caps (Q6.4 A, Q6.5 A) ---
const ARMOR_CAP := 0.75
const MRES_CAP := 75.0
const DMG_REDUCE_CAP := 0.75
const DODGE_CAP := 0.5
const BLOCK_CAP := 0.6
const BLOCK_POWER := 0.5
const CRIT_CAP := 1.0

# --- enhancement (Q9: per item, +15, drops a level from +7 with floors, stones, pity, gold protection) ---
const ENH_MAX := 15
const ENH_CHANCE := [1.0, 0.92, 0.84, 0.76, 0.68, 0.60, 0.50, 0.40, 0.35, 0.25, 0.20, 0.15, 0.10, 0.08, 0.05]  # to reach +1..+15
const ENH_FLOORS := [6, 9, 12]
const ENH_PITY := 0.03
const ENH_COST0 := 500.0
const ENH_COST_GROWTH := 1.5  # per level; the cost is also × the rarity multiplier, so high gear is the late gold sink
## Bonus to the main stat per level reached: +1..+5 5%, +6..+8 6%, +9..+10 7%, +11..+15 8% (Q9.7 B).
const ENH_STEP := [0.05, 0.05, 0.05, 0.05, 0.05, 0.06, 0.06, 0.06, 0.07, 0.07, 0.08, 0.08, 0.08, 0.08, 0.08]
const STONE_BONUS := [0.02, 0.04, 0.07, 0.11, 0.16]  # chance added per stone of level 1..5
const STONES_PER_TRY := 3

# --- reroll (Q11: cheaper than Master; ×2 per locked line) ---
const REROLL_COST0 := 200.0
const REROLL_GROWTH := 3.0

# --- chests and offline (Q2) ---
const CHEST_SEC := 240.0
const CHEST_CAP := 20
const CHEST_ITEMS := 2
const OFFLINE_BASE_H := 8  # Q2.2 B: available from the start; hoard runes raise it to 12 h (Q2.3 B)
const OFFLINE_VOID_SEC := 30 * 86400
const BAG_CAP := 60

# --- special zone (Q13.3 B) and endless tower (Q14.5 B) ---
const ZONE_INTENSITY_MAX := 20
const ZONE_HP_PER_INT := 0.6
const ZONE_LOOT_PER_INT := 0.08

# --- runes (Q12.1 B rewrite; max 0 = no cap, then cost × (1 + level)^grow instead of cost × grow^level) ---
const RUNES := [
	{"id": "growth", "name": "Khởi Đầu", "fmt": "+%d%% ATK", "per": 5, "max": 5, "cost": 60, "grow": 1.6, "req": "", "at": [0, 3]},
	{"id": "vitality", "name": "Sinh Lực", "fmt": "+%d%% Máu", "per": 6, "max": 5, "cost": 80, "grow": 1.6, "req": "growth", "at": [1, 2]},
	{"id": "unlock_ranger", "name": "Cung Thủ", "fmt": "Mở class Cung Thủ", "per": 0, "max": 1, "cost": 300, "grow": 1.0, "req": "growth", "at": [1, 4]},
	{"id": "command", "name": "Chỉ Huy", "fmt": "Mở ô đội 2", "per": 0, "max": 1, "cost": 1500, "grow": 1.0, "req": "unlock_ranger", "at": [2, 4]},
	{"id": "unlock_cleric", "name": "Tu Sĩ", "fmt": "Mở class Tu Sĩ", "per": 0, "max": 1, "cost": 4000, "grow": 1.0, "req": "command", "at": [3, 4]},
	{"id": "unlock_sorcerer", "name": "Pháp Sư", "fmt": "Mở class Pháp Sư", "per": 0, "max": 1, "cost": 12000, "grow": 1.0, "req": "command", "at": [3, 5]},
	{"id": "command2", "name": "Chỉ Huy II", "fmt": "Mở ô đội 3", "per": 0, "max": 1, "cost": 150000, "grow": 1.0, "req": "command", "at": [4, 5]},
	{"id": "unlock_berserker", "name": "Cuồng Chiến", "fmt": "Mở class Cuồng Chiến", "per": 0, "max": 1, "cost": 60000, "grow": 1.0, "req": "unlock_sorcerer", "at": [5, 4]},
	{"id": "unlock_assassin", "name": "Sát Thủ", "fmt": "Mở class Sát Thủ", "per": 0, "max": 1, "cost": 250000, "grow": 1.0, "req": "unlock_berserker", "at": [6, 4]},
	{"id": "greed", "name": "Tham Lam", "fmt": "+%d%% vàng", "per": 8, "max": 5, "cost": 200, "grow": 1.7, "req": "growth", "at": [1, 1]},
	{"id": "training", "name": "Rèn Luyện", "fmt": "+%d%% EXP", "per": 10, "max": 5, "cost": 150, "grow": 1.7, "req": "growth", "at": [1, 0]},
	{"id": "hoard", "name": "Ngủ Sâu", "fmt": "+%dh trần offline", "per": 1, "max": 4, "cost": 500, "grow": 2.0, "req": "training", "at": [2, 0]},
	{"id": "bag", "name": "Túi Lớn", "fmt": "+%d ô túi", "per": 10, "max": 4, "cost": 800, "grow": 1.8, "req": "greed", "at": [2, 1]},
	{"id": "chest_time", "name": "Đồng Hồ Cát", "fmt": "−%ds chờ rương", "per": 15, "max": 4, "cost": 400, "grow": 1.8, "req": "greed", "at": [3, 1]},
	{"id": "auto_chest", "name": "Dây Cót", "fmt": "Tự mở rương", "per": 0, "max": 1, "cost": 3000, "grow": 1.0, "req": "chest_time", "at": [4, 1]},
	{"id": "auto_sell", "name": "Thương Nhân", "fmt": "Tự phân rã đồ dưới ngưỡng", "per": 0, "max": 1, "cost": 5000, "grow": 1.0, "req": "bag", "at": [3, 0]},
	{"id": "luck", "name": "May Mắn", "fmt": "+%d%% rơi đồ", "per": 4, "max": 5, "cost": 600, "grow": 1.7, "req": "vitality", "at": [2, 2]},
	{"id": "fortune", "name": "Vận May", "fmt": "+%d%% đồ phẩm cao", "per": 6, "max": 5, "cost": 1500, "grow": 1.8, "req": "luck", "at": [3, 2]},
	{"id": "smith", "name": "Thợ Rèn", "fmt": "−%d%% phí rèn", "per": 4, "max": 5, "cost": 2000, "grow": 1.8, "req": "fortune", "at": [4, 2]},
	{"id": "might", "name": "Sức Mạnh", "fmt": "+%d%% ATK", "per": 10, "max": 5, "cost": 1000, "grow": 1.8, "req": "vitality", "at": [2, 3]},
	{"id": "guard", "name": "Hộ Vệ", "fmt": "+%d%% giáp", "per": 8, "max": 5, "cost": 1000, "grow": 1.8, "req": "might", "at": [3, 3]},
	{"id": "haste", "name": "Nhanh Nhẹn", "fmt": "+%d%% tốc đánh", "per": 4, "max": 5, "cost": 1200, "grow": 1.8, "req": "might", "at": [4, 3]},
	{"id": "mastery", "name": "Bậc Thầy", "fmt": "+%d%% ATK", "per": 5, "max": 0, "cost": 20000, "grow": 2.0, "req": "haste", "at": [5, 3]},
	{"id": "bulwark", "name": "Thành Lũy", "fmt": "+%d%% Máu và giáp", "per": 5, "max": 0, "cost": 20000, "grow": 2.0, "req": "mastery", "at": [6, 3]},
	{"id": "wisdom", "name": "Minh Triết", "fmt": "+%d%% EXP", "per": 2, "max": 0, "cost": 15000, "grow": 2.0, "req": "smith", "at": [5, 2]},
]
