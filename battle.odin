package main

import "core:fmt"
import "core:math/rand"
import "core:strings"
import "core:time"
import rl "vendor:raylib"

// ─────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────
SCREEN_W :: 800
SCREEN_H :: 600

FONT_SIZE :: 20
BATTLE_LOG_LINES :: 8

// ─────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────
Character_Type :: enum {
	Hero,
	Warrior,
	Priest,
	Mage,
	Monster,
}

Stats :: struct {
	hp:         i32,
	max_hp:     i32,
	mp:         i32,
	max_mp:     i32,
	strength:   i32,
	agility:    i32,
	resilience: i32,
	wisdom:     i32,
	level:      i32,
	xp:         i32,
	xp_next:    i32,
}

Character :: struct {
	name:         string,
	type:         Character_Type,
	stats:        Stats,
	is_alive:     bool,
	is_defending: bool,
	status:       Status_Effect,
	poison_timer: i32,
}

Status_Effect :: enum {
	None,
	Poison,
	Paralyze,
	Sleep,
	Confuse,
}

Action :: enum {
	Attack,
	Defend,
	Spell,
	Item,
	Flee,
}

Battle_State :: enum {
	Player_Turn,
	Enemy_Turn,
	Animating,
	GameOver,
	Victory,
	Escaped,
}

Spell :: enum {
	None,
	Heal,
	Fireball,
	Blizzard,
	Lightning,
	Cure,
}

Battle_Log :: struct {
	messages: [BATTLE_LOG_LINES]string,
	count:    int,
}

Animation :: struct {
	active:      bool,
	progress:    f32,
	source_x:    f32,
	source_y:    f32,
	target_x:    f32,
	target_y:    f32,
	damage:      i32,
	damage_text: string,
}

// ─────────────────────────────────────────────────────────────────────────
// Game State
// ─────────────────────────────────────────────────────────────────────────
Game :: struct {
	state:           Battle_State,
	party:           [4]Character,
	enemies:         [4]Character,
	enemy_count:     int,
	current_enemy:   int,
	selected_enemy:  int,
	selected_action: Action,
	selected_spell:  Spell,
	acting_party:    int,
	battle_log:      Battle_Log,
	anim:            Animation,
	turn_count:      int,
	show_menu:       bool,
	menu_depth:      int, // 0=main, 1=spells, 2=targets
	cursor_pos:      int,
	game_time:       f64,
	win_count:       int,
	lose_count:      int,
}

// ─────────────────────────────────────────────────────────────────────────
// Character Creation
// ─────────────────────────────────────────────────────────────────────────
create_hero :: proc(name: string) -> Character {
	return Character{
		name = name, type = .Hero,
		stats = Stats{hp = 30, max_hp = 30, mp = 10, max_mp = 10, strength = 8, agility = 6, resilience = 5, wisdom = 4, level = 1, xp = 0, xp_next = 10},
		is_alive = true, is_defending = false, status = .None,
	}
}

create_warrior :: proc(name: string) -> Character {
	return Character{
		name = name, type = .Warrior,
		stats = Stats{hp = 40, max_hp = 40, mp = 0, max_mp = 0, strength = 12, agility = 4, resilience = 10, wisdom = 2, level = 1, xp = 0, xp_next = 12},
		is_alive = true, is_defending = false, status = .None,
	}
}

create_priest :: proc(name: string) -> Character {
	return Character{
		name = name, type = .Priest,
		stats = Stats{hp = 25, max_hp = 25, mp = 15, max_mp = 15, strength = 4, agility = 5, resilience = 4, wisdom = 10, level = 1, xp = 0, xp_next = 10},
		is_alive = true, is_defending = false, status = .None,
	}
}

create_mage :: proc(name: string) -> Character {
	return Character{
		name = name, type = .Mage,
		stats = Stats{hp = 20, max_hp = 20, mp = 20, max_mp = 20, strength = 2, agility = 6, resilience = 2, wisdom = 12, level = 1, xp = 0, xp_next = 10},
		is_alive = true, is_defending = false, status = .None,
	}
}

create_monster :: proc(level: i32, type_index: int) -> Character {
	names := []string{"Slime", "Dracky", "Golem", "Wolf", "Bat", "Ghost", "Skeleton", "Orc"}
	name := names[type_index % len(names)]

	base_hp := 10 + level * 4 + i32(rand.int_max(8))
	base_mp := level * 2 + i32(rand.int_max(4))
	base_str := 3 + level * 2 + i32(rand.int_max(3))
	base_agi := 2 + level + i32(rand.int_max(2))
	base_res := 2 + level + i32(rand.int_max(2))

	return Character{
		name = name, type = .Monster,
		stats = Stats{hp = base_hp, max_hp = base_hp, mp = base_mp, max_mp = base_mp, strength = base_str, agility = base_agi, resilience = base_res, wisdom = 1 + level / 2, level = level, xp = 0, xp_next = 0},
		is_alive = true, is_defending = false, status = .None,
	}
}

// ─────────────────────────────────────────────────────────────────────────
// Battle System
// ─────────────────────────────────────────────────────────────────────────
first_alive_party :: proc(game: ^Game) -> int {
	for i in 0 ..< len(game.party) {
		if game.party[i].is_alive do return i
	}
	return -1
}

next_alive_party_after :: proc(game: ^Game, from: int) -> int {
	for i := from + 1; i < len(game.party); i += 1 {
		if game.party[i].is_alive do return i
	}
	return -1
}

init_battle :: proc(game: ^Game) {
	game.enemy_count = 2 + rand.int_max(3)
	for i in 0 ..< game.enemy_count {
		level := i32(game.win_count + 1)
		game.enemies[i] = create_monster(level, i)
		game.enemies[i].is_alive = true
	}
	for i := game.enemy_count; i < 4; i += 1 {
		game.enemies[i].is_alive = false
	}
	game.selected_enemy = 0
	game.selected_action = .Attack
	game.selected_spell = .None
	game.battle_log.count = 0
	game.state = .Player_Turn
	game.turn_count += 1
	game.show_menu = true
	game.menu_depth = 0
	game.cursor_pos = 0
	game.current_enemy = 0
	game.acting_party = first_alive_party(game)

	add_log(game, "Battle begins!")
	add_log(game, "Choose your action:")
}

add_log :: proc(game: ^Game, msg: string) {
	if game.battle_log.count < BATTLE_LOG_LINES {
		game.battle_log.messages[game.battle_log.count] = msg
		game.battle_log.count += 1
	} else {
		for i in 0 ..< BATTLE_LOG_LINES - 1 {
			game.battle_log.messages[i] = game.battle_log.messages[i + 1]
		}
		game.battle_log.messages[BATTLE_LOG_LINES - 1] = msg
	}
}

damage_calc :: proc(attacker: ^Character, defender: ^Character, is_physical: bool) -> i32 {
	base := attacker.stats.strength if is_physical else attacker.stats.wisdom
	defense := defender.stats.resilience
	variation := 1.0 + (rand.float32() - 0.5) * 0.3

	damage := i32(f32(base * 2 + 5 - defense / 2) * variation)
	if damage < 1 do damage = 1

	if rand.int_max(100) < 5 {
		damage *= 2
		return damage
	}
	return damage
}

is_alive_any :: proc(characters: []Character) -> bool {
	for ch in characters do if ch.is_alive do return true
	return false
}

count_alive :: proc(characters: []Character) -> int {
	count := 0
	for ch in characters do if ch.is_alive do count += 1
	return count
}

execute_attack :: proc(game: ^Game, attacker: ^Character, target: ^Character) {
	damage := damage_calc(attacker, target, true)
	target.stats.hp -= damage
	if target.stats.hp < 0 do target.stats.hp = 0

	if target.stats.hp <= 0 {
		target.is_alive = false
		add_log(game, fmt.tprintf("%s defeated %s!", attacker.name, target.name))
	} else {
		add_log(game, fmt.tprintf("%s hits %s for %d damage!", attacker.name, target.name, damage))
	}
}

execute_spell :: proc(game: ^Game, caster: ^Character, targets: []^Character, spell: Spell) {
	switch spell {
	case .Heal:
		heal_amount := 10 + caster.stats.wisdom
		for target in targets {
			if target.is_alive {
				old_hp := target.stats.hp
				target.stats.hp = min(target.stats.hp + heal_amount, target.stats.max_hp)
				healed := target.stats.hp - old_hp
				if healed > 0 do add_log(game, fmt.tprintf("%s heals %s for %d HP!", caster.name, target.name, healed))
			}
		}

	case .Fireball:
		damage := 8 + caster.stats.wisdom
		for target in targets {
			if target.is_alive {
				resist := target.stats.resilience / 4
				final_damage := max(1, damage - resist)
				target.stats.hp -= final_damage
				if target.stats.hp < 0 do target.stats.hp = 0
				if target.stats.hp <= 0 {
					target.is_alive = false
					add_log(game, fmt.tprintf("%s incinerates %s!", caster.name, target.name))
				} else {
					add_log(game, fmt.tprintf("%s hits %s for %d fire damage!", caster.name, target.name, final_damage))
				}
			}
		}

	case .Blizzard:
		damage := 6 + caster.stats.wisdom
		for target in targets {
			if target.is_alive {
				resist := target.stats.resilience / 3
				final_damage := max(1, damage - resist)
				target.stats.hp -= final_damage
				if target.stats.hp < 0 do target.stats.hp = 0
				if target.stats.hp <= 0 {
					target.is_alive = false
					add_log(game, fmt.tprintf("%s freezes %s!", caster.name, target.name))
				} else {
					add_log(game, fmt.tprintf("%s hits %s for %d ice damage!", caster.name, target.name, final_damage))
				}
			}
		}

	case .Lightning:
		damage := 12 + caster.stats.wisdom
		target := targets[0]
		if target.is_alive {
			resist := target.stats.resilience / 2
			final_damage := max(1, damage - resist)
			target.stats.hp -= final_damage
			if target.stats.hp < 0 do target.stats.hp = 0
			if target.stats.hp <= 0 {
				target.is_alive = false
				add_log(game, fmt.tprintf("%s zaps %s!", caster.name, target.name))
			} else {
				add_log(game, fmt.tprintf("%s hits %s for %d lightning damage!", caster.name, target.name, final_damage))
			}
		}

	case .Cure:
		for target in targets {
			if target.is_alive && target.status != .None {
				target.status = .None
				add_log(game, fmt.tprintf("%s cures %s's status!", caster.name, target.name))
			}
		}

	case .None:
		return
	}
}

execute_player_turn :: proc(game: ^Game, action: Action, target_idx: int, spell: Spell) {
	if game.state != .Player_Turn do return

	if game.acting_party < 0 || game.acting_party >= len(game.party) || !game.party[game.acting_party].is_alive {
		game.acting_party = first_alive_party(game)
	}
	if game.acting_party == -1 {
		game.state = .GameOver
		return
	}
	actor := &game.party[game.acting_party]

	switch action {
	case .Attack:
		if target_idx < len(game.enemies) && game.enemies[target_idx].is_alive {
			execute_attack(game, actor, &game.enemies[target_idx])
		}

	case .Defend:
		actor.is_defending = true
		add_log(game, fmt.tprintf("%s defends!", actor.name))

	case .Spell:
		if actor.stats.mp >= 3 {
			targets: [4]^Character
			target_count := 0

			if spell == .Heal || spell == .Cure {
				for i in 0 ..< len(game.party) {
					if game.party[i].is_alive {
						targets[target_count] = &game.party[i]
						target_count += 1
					}
				}
			} else if spell == .Lightning {
				if target_idx < len(game.enemies) && game.enemies[target_idx].is_alive {
					targets[0] = &game.enemies[target_idx]
					target_count = 1
				}
			} else {
				for i in 0 ..< len(game.enemies) {
					if game.enemies[i].is_alive {
						targets[target_count] = &game.enemies[i]
						target_count += 1
					}
				}
			}

			if target_count > 0 {
				execute_spell(game, actor, targets[:target_count], spell)
				actor.stats.mp -= 3
			} else {
				add_log(game, "No valid targets!")
			}
		} else {
			add_log(game, "Not enough MP!")
		}

	case .Flee:
		if rand.int_max(100) < 60 {
			add_log(game, "You got away safely!")
			game.state = .Escaped
			return
		} else {
			add_log(game, "Couldn't escape!")
		}

	case .Item:
		heal := 20
		old_hp := actor.stats.hp
		actor.stats.hp = min(actor.stats.hp + i32(heal), actor.stats.max_hp)
		add_log(game, fmt.tprintf("%s uses a Medicinal Herb! HP +%d", actor.name, actor.stats.hp - old_hp))
	}

	if !is_alive_any(game.enemies[:]) {
		game.state = .Victory
		game.win_count += 1
		give_xp(game)
		return
	}

	nxt := next_alive_party_after(game, game.acting_party)
	if nxt != -1 {
		game.acting_party = nxt
		return
	}

	game.state = .Enemy_Turn
	execute_enemy_turn(game)
}

execute_enemy_turn :: proc(game: ^Game) {
	if game.state != .Enemy_Turn do return

	for i in 0 ..< len(game.enemies) {
		if !game.enemies[i].is_alive do continue

		enemy := &game.enemies[i]

		party_indices: [4]int
		party_count := 0
		for j in 0 ..< len(game.party) {
			if game.party[j].is_alive {
				party_indices[party_count] = j
				party_count += 1
			}
		}
		if party_count == 0 do break

		target_idx := party_indices[rand.int_max(party_count)]
		target := &game.party[target_idx]

		damage := damage_calc(enemy, target, true)
		if target.is_defending {
			damage = damage / 2
			target.is_defending = false
		}

		target.stats.hp -= damage
		if target.stats.hp < 0 do target.stats.hp = 0

		if target.stats.hp <= 0 {
			target.is_alive = false
			add_log(game, fmt.tprintf("%s defeats %s!", enemy.name, target.name))
		} else {
			add_log(game, fmt.tprintf("%s hits %s for %d damage!", enemy.name, target.name, damage))
		}

		if !is_alive_any(game.party[:]) {
			game.state = .GameOver
			game.lose_count += 1
			return
		}
	}

	if game.state != .GameOver && game.state != .Victory {
		game.state = .Player_Turn
		game.acting_party = first_alive_party(game)
		add_log(game, "Your turn!")
	}
}

give_xp :: proc(game: ^Game) {
	total_xp := 0
	for enemy in game.enemies {
		if enemy.is_alive == false do total_xp += 5 + int(enemy.stats.level) * 3
	}

	alive_count := count_alive(game.party[:])
	if alive_count == 0 do return

	for i in 0 ..< len(game.party) {
		if game.party[i].is_alive {
			ch := &game.party[i]
			ch.stats.xp += i32(total_xp / alive_count)

			for ch.stats.xp >= ch.stats.xp_next {
				ch.stats.xp -= ch.stats.xp_next
				ch.stats.level += 1
				ch.stats.xp_next = ch.stats.level * 10 + 5
				ch.stats.max_hp += 4 + ch.stats.resilience / 2
				ch.stats.hp = ch.stats.max_hp
				ch.stats.max_mp += 2 + ch.stats.wisdom / 3
				ch.stats.mp = ch.stats.max_mp
				ch.stats.strength += 1 + ch.stats.level % 2
				ch.stats.agility += 1
				ch.stats.resilience += 1
				ch.stats.wisdom += 1

				add_log(game, fmt.tprintf("%s reached level %d!", ch.name, ch.stats.level))
			}
		}
	}
}

// ─────────────────────────────────────────────────────────────────────────
// Rendering
// ─────────────────────────────────────────────────────────────────────────
draw_character_sprite :: proc(ch: Character, x: i32, y: i32, size: i32) {
	color := rl.GRAY

	switch ch.type {
	case .Hero:
		draw_hero_sprite(x, y, size)
		return
	case .Warrior: color = rl.RED
	case .Priest:  color = rl.WHITE
	case .Mage:    color = rl.PURPLE
	case .Monster: color = rl.GREEN
	}

	rl.DrawRectangle(x - size / 2, y - size / 2, size, size, color)

	eye_size := size / 5
	rl.DrawRectangle(x - size / 3, y - size / 4, eye_size, eye_size, rl.WHITE)
	rl.DrawRectangle(x + size / 3 - eye_size, y - size / 4, eye_size, eye_size, rl.WHITE)

	if ch.type == .Monster {
		rl.DrawRectangle(x - size / 4, y + size / 4, size / 2, size / 8, rl.RED)
	} else {
		rl.DrawLine(x - size / 4, y + size / 4, x + size / 4, y + size / 4, rl.WHITE)
	}

	if ch.status != .None do rl.DrawCircle(x + size / 2 + 5, y - size / 2, 4, rl.GREEN)
}

draw_hero_sprite :: proc(x: i32, y: i32, size: i32) {
	rl.DrawRectangle(x - size / 3, y - size / 4, size * 2 / 3, size * 2 / 3, rl.BLUE)
	rl.DrawCircle(x, y - size / 4, f32(size) / 3, rl.BEIGE)
	rl.DrawRectangle(x - size / 3, y - size / 2, size * 2 / 3, size / 4, rl.DARKBROWN)

	eye := size / 6
	rl.DrawCircle(x - size / 6, y - size / 4, f32(eye), rl.WHITE)
	rl.DrawCircle(x + size / 6, y - size / 4, f32(eye), rl.WHITE)
	rl.DrawCircle(x - size / 6, y - size / 4, f32(eye) / 2, rl.BLACK)
	rl.DrawCircle(x + size / 6, y - size / 4, f32(eye) / 2, rl.BLACK)

	rl.DrawTriangle(
		rl.Vector2{f32(x), f32(y + size / 4)},
		rl.Vector2{f32(x - size / 2), f32(y + size / 2)},
		rl.Vector2{f32(x + size / 2), f32(y + size / 2)},
		rl.RED,
	)

	rl.DrawLine(x + size / 2, y, x + size, y - size / 3, rl.GRAY)
	rl.DrawRectangle(x + size / 2 - 2, y + size / 4, 4, size / 4, rl.GOLD)
}

draw_battle_scene :: proc(game: ^Game) {
	rl.ClearBackground(rl.BLACK)

	for i in 0 ..< SCREEN_H {
		t := f32(i) / f32(SCREEN_H)
		color := rl.Color{u8(10 + i32(t * 30)), u8(10 + i32(t * 20)), u8(30 + i32(t * 40)), 255}
		rl.DrawRectangle(0, i32(i), SCREEN_W, 1, color)
	}

	ground_y: i32 = SCREEN_H - 100
	rl.DrawRectangle(0, ground_y, SCREEN_W, 100, rl.Color{30, 40, 20, 255})
	rl.DrawRectangle(0, ground_y, SCREEN_W, 2, rl.Color{50, 60, 40, 255})

	enemy_y := ground_y - 50
	if game.enemy_count > 0 {
		spacing: i32 = 120
		total_width := i32(game.enemy_count) * spacing
		start_x := (SCREEN_W - total_width) / 2 + spacing / 2

		for i in 0 ..< game.enemy_count {
			x := start_x + i32(i) * spacing
			if game.enemies[i].is_alive {
				draw_character_sprite(game.enemies[i], x, enemy_y, 50)

				hp_frac := f32(game.enemies[i].stats.hp) / f32(game.enemies[i].stats.max_hp)
				bar_color := rl.GREEN
				if hp_frac < 0.3 do bar_color = rl.RED
				else if hp_frac < 0.6 do bar_color = rl.YELLOW

				rl.DrawRectangle(x - 30, enemy_y + 40, 60, 5, rl.DARKGRAY)
				rl.DrawRectangle(x - 30, enemy_y + 40, i32(60.0 * hp_frac), 5, bar_color)

				rl.DrawText(fmt.ctprintf("%s Lv.%d", game.enemies[i].name, game.enemies[i].stats.level), x - 30, enemy_y - 35, 12, rl.WHITE)

				if i == game.selected_enemy && game.state == .Player_Turn {
					rl.DrawRectangleLines(x - 35, enemy_y - 45, 70, 95, rl.YELLOW)
				}
			}
		}
	}

	party_y: i32 = SCREEN_H - 60
	spacing: i32 = 120
	total_width: i32 = 4 * spacing
	start_x := (SCREEN_W - total_width) / 2 + spacing / 2

	for i in 0 ..< 4 {
		x := start_x + i32(i) * spacing
		if game.party[i].is_alive {
			draw_character_sprite(game.party[i], x, party_y, 45)

			hp_frac := f32(game.party[i].stats.hp) / f32(game.party[i].stats.max_hp)
			mp_frac: f32 = 0
			if game.party[i].stats.max_mp > 0 do mp_frac = f32(game.party[i].stats.mp) / f32(game.party[i].stats.max_mp)

			rl.DrawRectangle(x - 30, party_y + 35, 60, 4, rl.DARKGRAY)
			rl.DrawRectangle(x - 30, party_y + 35, i32(60.0 * hp_frac), 4, rl.RED)

			rl.DrawRectangle(x - 30, party_y + 40, 60, 3, rl.DARKGRAY)
			rl.DrawRectangle(x - 30, party_y + 40, i32(60.0 * mp_frac), 3, rl.BLUE)

			if game.party[i].status != .None {
				rl.DrawText(fmt.ctprintf("%s Lv.%d [%v]", game.party[i].name, game.party[i].stats.level, game.party[i].status), x - 30, party_y - 30, 12, rl.WHITE)
			} else {
				rl.DrawText(fmt.ctprintf("%s Lv.%d", game.party[i].name, game.party[i].stats.level), x - 30, party_y - 30, 12, rl.WHITE)
			}

			if game.state == .Player_Turn && i == game.acting_party {
				rl.DrawText(">", x - 45, party_y - 5, 16, rl.YELLOW)
			}
		} else {
			rl.DrawText("X", x - 6, party_y, 30, rl.RED)
		}
	}

	log_x: i32 = 10
	log_y: i32 = 20
	log_w: i32 = SCREEN_W / 2 - 20
	log_h: i32 = i32(BATTLE_LOG_LINES) * 20

	rl.DrawRectangle(log_x, log_y, log_w, log_h, rl.Color{0, 0, 0, 180})
	rl.DrawRectangleLines(log_x, log_y, log_w, log_h, rl.Color{100, 100, 100, 255})

	for i in 0 ..< game.battle_log.count {
		line_y := log_y + 5 + i32(i) * 20
		rl.DrawText(fmt.ctprintf("%s", game.battle_log.messages[i]), log_x + 5, line_y, 14, rl.WHITE)
	}

	if game.state == .Player_Turn && game.show_menu do draw_menu(game)

	if game.state == .GameOver {
		rl.DrawRectangle(SCREEN_W / 2 - 150, SCREEN_H / 2 - 100, 300, 200, rl.Color{0, 0, 0, 200})
		rl.DrawRectangleLines(SCREEN_W / 2 - 150, SCREEN_H / 2 - 100, 300, 200, rl.RED)
		rl.DrawText("GAME OVER", SCREEN_W / 2 - 80, SCREEN_H / 2 - 50, 40, rl.RED)
		rl.DrawText("Press SPACE to restart", SCREEN_W / 2 - 90, SCREEN_H / 2 + 20, 20, rl.WHITE)
	}

	if game.state == .Victory {
		rl.DrawRectangle(SCREEN_W / 2 - 150, SCREEN_H / 2 - 100, 300, 200, rl.Color{0, 0, 0, 200})
		rl.DrawRectangleLines(SCREEN_W / 2 - 150, SCREEN_H / 2 - 100, 300, 200, rl.GOLD)
		rl.DrawText("VICTORY!", SCREEN_W / 2 - 75, SCREEN_H / 2 - 50, 40, rl.GOLD)
		rl.DrawText("Press SPACE to continue", SCREEN_W / 2 - 95, SCREEN_H / 2 + 20, 20, rl.WHITE)
	}

	if game.state == .Escaped {
		rl.DrawRectangle(SCREEN_W / 2 - 150, SCREEN_H / 2 - 100, 300, 200, rl.Color{0, 0, 0, 200})
		rl.DrawRectangleLines(SCREEN_W / 2 - 150, SCREEN_H / 2 - 100, 300, 200, rl.GREEN)
		rl.DrawText("GOT AWAY SAFELY", SCREEN_W / 2 - 110, SCREEN_H / 2 - 50, 26, rl.GREEN)
		rl.DrawText("Press SPACE to continue", SCREEN_W / 2 - 95, SCREEN_H / 2 + 20, 20, rl.WHITE)
	}
}

draw_menu :: proc(game: ^Game) {
	menu_x: i32 = SCREEN_W - 280
	menu_y: i32 = 20
	menu_w: i32 = 260
	menu_h: i32 = 250

	rl.DrawRectangle(menu_x, menu_y, menu_w, menu_h, rl.Color{0, 0, 0, 220})
	rl.DrawRectangleLines(menu_x, menu_y, menu_w, menu_h, rl.Color{150, 150, 150, 255})

	options := []cstring{"Attack", "Defend", "Spells", "Item", "Flee"}

	if game.acting_party >= 0 && game.acting_party < len(game.party) {
		rl.DrawText(fmt.ctprintf("%s's turn", game.party[game.acting_party].name), menu_x + 10, menu_y + 5, 16, rl.WHITE)
	}

	if game.menu_depth == 0 {
		for i := 0; i < len(options); i += 1 {
			y := menu_y + 30 + i32(i) * 26
			color := rl.WHITE
			if i == game.cursor_pos {
				color = rl.YELLOW
				rl.DrawText(">", menu_x + 5, y, 18, rl.YELLOW)
			}
			rl.DrawText(options[i], menu_x + 25, y, 18, color)
		}
	} else if game.menu_depth == 1 {
		spells := []cstring{"Fireball", "Blizzard", "Lightning", "Heal", "Cure"}
		for i := 0; i < len(spells); i += 1 {
			y := menu_y + 30 + i32(i) * 24
			color := rl.WHITE
			if i == game.cursor_pos {
				color = rl.YELLOW
				rl.DrawText(">", menu_x + 5, y, 16, rl.YELLOW)
			}
			rl.DrawText(spells[i], menu_x + 25, y, 16, color)
		}
	} else if game.menu_depth == 2 {
		label: cstring = "Choose a target"
		rl.DrawText(label, menu_x + 10, menu_y + 30, 16, rl.WHITE)
		for i in 0 ..< game.enemy_count {
			if !game.enemies[i].is_alive do continue
			y := menu_y + 55 + i32(i) * 20
			color := rl.WHITE
			if i == game.cursor_pos {
				color = rl.YELLOW
				rl.DrawText(">", menu_x + 5, y, 16, rl.YELLOW)
			}
			rl.DrawText(fmt.ctprintf("%s", game.enemies[i].name), menu_x + 25, y, 16, color)
		}
	}

	rl.DrawText("-- Party Status --", menu_x + 20, menu_y + 200, 14, rl.GRAY)
	for i in 0 ..< 4 {
		if game.party[i].is_alive {
			ch := game.party[i]
			rl.DrawText(fmt.ctprintf("%s HP:%d/%d MP:%d/%d", ch.name, ch.stats.hp, ch.stats.max_hp, ch.stats.mp, ch.stats.max_mp), menu_x + 10, menu_y + 220 + i32(i) * 16, 12, rl.GRAY)
		}
	}
}

// ─────────────────────────────────────────────────────────────────────────
// Input Handling
// ─────────────────────────────────────────────────────────────────────────
handle_input :: proc(game: ^Game) -> bool {
	if rl.IsKeyPressed(.ESCAPE) do return false

	if game.state == .GameOver || game.state == .Victory || game.state == .Escaped {
		if rl.IsKeyPressed(.SPACE) do init_battle(game)
		return true
	}

	if game.state != .Player_Turn do return true

	if !game.show_menu do game.show_menu = true

	menu_len := 5 if game.menu_depth == 0 else (5 if game.menu_depth == 1 else max(1, game.enemy_count))

	if rl.IsKeyPressed(.UP) || rl.IsKeyPressed(.KP_8) do game.cursor_pos = (game.cursor_pos - 1 + menu_len) % menu_len
	if rl.IsKeyPressed(.DOWN) || rl.IsKeyPressed(.KP_2) do game.cursor_pos = (game.cursor_pos + 1) % menu_len

	if rl.IsKeyPressed(.SPACE) || rl.IsKeyPressed(.ENTER) {
		if game.menu_depth == 0 {
			switch game.cursor_pos {
			case 0:
				game.selected_spell = .None
				game.menu_depth = 2
				game.cursor_pos = 0
			case 1:
				execute_player_turn(game, .Defend, 0, .None)
				game.menu_depth = 0
				game.cursor_pos = 0
			case 2:
				game.menu_depth = 1
				game.cursor_pos = 0
			case 3:
				execute_player_turn(game, .Item, 0, .None)
				game.menu_depth = 0
				game.cursor_pos = 0
			case 4:
				execute_player_turn(game, .Flee, 0, .None)
				game.menu_depth = 0
				game.cursor_pos = 0
			}
		} else if game.menu_depth == 1 {
			spell := Spell.None
			switch game.cursor_pos {
			case 0: spell = .Fireball
			case 1: spell = .Blizzard
			case 2: spell = .Lightning
			case 3: spell = .Heal
			case 4: spell = .Cure
			}
			game.selected_spell = spell
			if spell == .Heal || spell == .Cure {
				execute_player_turn(game, .Spell, 0, spell)
				game.selected_spell = .None
				game.menu_depth = 0
				game.cursor_pos = 0
			} else {
				game.menu_depth = 2
				game.cursor_pos = 0
			}
		} else if game.menu_depth == 2 {
			if game.selected_spell == .None {
				if game.cursor_pos < game.enemy_count && game.enemies[game.cursor_pos].is_alive {
					execute_player_turn(game, .Attack, game.cursor_pos, .None)
					game.menu_depth = 0
					game.cursor_pos = 0
				}
			} else {
				execute_player_turn(game, .Spell, game.cursor_pos, game.selected_spell)
				game.selected_spell = .None
				game.menu_depth = 0
				game.cursor_pos = 0
			}
		}
	}

	if rl.IsKeyPressed(.BACKSPACE) {
		if game.menu_depth == 1 {
			game.menu_depth = 0
			game.cursor_pos = 2
		} else if game.menu_depth == 2 {
			if game.selected_spell != .None {
				game.menu_depth = 1
				game.cursor_pos = 0
			} else {
				game.menu_depth = 0
				game.cursor_pos = 0
			}
			game.selected_spell = .None
		}
	}

	if game.menu_depth == 2 && game.enemy_count > 0 {
		if rl.IsKeyPressed(.RIGHT) || rl.IsKeyPressed(.KP_6) do game.cursor_pos = (game.cursor_pos + 1) % game.enemy_count
		if rl.IsKeyPressed(.LEFT) || rl.IsKeyPressed(.KP_4) do game.cursor_pos = (game.cursor_pos - 1 + game.enemy_count) % game.enemy_count
	}

	return true
}

// ─────────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────────
main :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE})
	rl.InitWindow(SCREEN_W, SCREEN_H, "DQ3 Battle System")
	defer rl.CloseWindow()

	rl.SetTargetFPS(60)
	rand.reset(u64(time.to_unix_nanoseconds(time.now())))

	game: Game
	game.win_count = 0
	game.lose_count = 0
	game.turn_count = 0

	game.party[0] = create_hero("Hero")
	game.party[1] = create_warrior("Warrior")
	game.party[2] = create_priest("Priest")
	game.party[3] = create_mage("Mage")

	for i in 0 ..< 4 do game.party[i].is_alive = true

	init_battle(&game)

	for !rl.WindowShouldClose() {
		if !handle_input(&game) do break

		rl.BeginDrawing()
		draw_battle_scene(&game)

		rl.DrawText(fmt.ctprintf("Wins: %d Losses: %d", game.win_count, game.lose_count), 10, SCREEN_H - 25, 16, rl.GRAY)
		rl.DrawText("ESC: Quit", SCREEN_W - 100, SCREEN_H - 25, 16, rl.GRAY)

		rl.EndDrawing()
	}
}
