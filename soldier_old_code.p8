pico-8 cartridge // http://www.pico-8.com
version 16
__lua__
-- --- new todo --- --
-- fix weapon switch
-- add codec
-- --- iffy/general todo --- --
-- todo: introduce blood footprint mechanic with some levels
-- todo: finish c4 placement
-- --- refactor todo --- --
-- todo: convert coord system to strings
-- todo: convert animation data to strings

-- debug values to reset on release
game_speed = 4
turn_break = 0.6 -- time in seconds to break between turns
starting_level = 1

-- universalish input values
z_down = false
x_down = false

-- restart-from-checkpoint options
prev_inventory = { socom = -1,
                   c4 = -1,
                   gloves = -1 }

prev_equipped = ""
prev_keycard = 0
prev_active_relays = {}
current_relay = nil

-- current points
keycard = 0
equipped = ""

inventory = { socom = -1,
              c4 = -1,
              gloves = -1 }

inventory_max = { socom = 4,
                  c4 = 2,
                  gloves = 0}

-- load the sprites and that
sprites = { player = {{17,18,19,18,21,22,23,20}, -- north (last three=roll/shoot/fly)
                      {1,2,3,2,5,6,7,4},        -- east (last three=roll/shoot/fly)
                      {33,34,35,34,37,38,39,36}, -- south (last three=roll/shoot/fly)
                      {49,50,51,50,53,54,55,52}, -- west (last three=roll/shoot/fly)
                      {8,9,10,11}, -- death
                      {12, 13}, -- fall
                      {25, 24}}, -- laser
            enemy1 = {{208,209,210,209,210,211,211,1}, -- north (last two=roll/shoot/fly)
                      {192,193,194,193,194,195,195,1}, -- east (last two=roll/shoot/fly)
                      {224,225,226,225,226,227,227,1}, -- south (last two=roll/shoot/fly)
                      {240,241,242,241,242,243,243,1}, -- west (last two=roll/shoot/fly)
                      {196,197,198,199}, -- death
                      {230, 231}, -- fall
                      {41, 40}, -- laser
                      {228, 229}, -- stunned
                      {212, 213, 214, 215}}, -- attack

            objects = {blood_prints = {26, 27, 28, 29},
                       snow_prints = {162, 163, 164, 165},
                       scanner = {131, 134},
                       multilock = {136, 137, 138},
                       trapdoor = {176, 177},
                       multidoor = {{88, 144}, {89, 145}},
                       keydoor = {{104, 160}, {105, 161}},
                       door = {{67, 129}, {68, 130}},
                       goal = {135},
                       relay = {132, 186},
                       ration = {180},
                       keycard = {185}},
            items   = {socom = 133,
                       c4 = 183,
                       gloves = 184},
            effects = {explosion = {172, 173, 174, 175}} }

-- we use mset to replace the map while it's in play, so,
-- we store a list of replaced tiles to put back when the level is reset
mset_restore = {}

-- palette swap commands and movement function strings for enemy variants
enemy_variants = {enemy1 = {{"clockwise", {5, 5}}, -- variant 1
                            {"line", {5, 2}}, -- variant 2
                            {"still", {5, 13}} }}  -- variant 3

-- for converting a direction to a position change
pos_map = {{0,1,0,-1}, {-1,0,1,0}}

-- level data
levels = {{0, 0, 36, 30}} -- xstart, ystart, w, h
level_items = {{"gloves"}}
level_keycards = {{2,1,3}}
level_keydoors = {{1,2,3}}
level_enemy_variants = {{2,2,3,3, 2,2,3,2, 1,2,2,1,1, 3,3,1,2, 3,3,3,2,1, 3,3,1,1}}

-- map runthrough replacements (sprite #, pattern, facing dir)
-- note: facing dir for doors and other items with only 2 dirs is [0/1] rather than [0/1/2/3]
map_replace = {{67,  "door", 0}, -- closed regular door
               {68,  "door", 1},
               {88,  "multidoor", 0}, -- closed multilock door
               {89,  "multidoor", 1},
               {104,  "keydoor", 0},
               {105,  "keydoor", 1},
               {1,   "player", 1}, -- player
               {17,  "player", 0},
               {33,  "player", 2},
               {49,  "player", 3},
               {192, "enemy1", 1}, -- enemy1
               {208, "enemy1", 0},
               {224, "enemy1", 2},
               {240, "enemy1", 3},
               {176, "trapdoor", no_floor = true},
               {177, "trapdoor", no_floor = true},
               {131, "scanner", false}, -- sprite #, pattern, player_allowed (scanner)
               {134, "scanner", true},  -- sprite #, pattern, player_allowed (scanner)
               {136, "multilock", false}, -- sprite #, pattern, player_allowed (multilock)
               {138, "multilock", true}, -- sprite #, pattern, player_allowed (multilock)
               {132, "relay"}, -- relays have no extra attribs yet
               {135, "goal"},  -- goals have no extra attribs yet
               {133, "item"},  -- the item type is taken from the level_items variable
               {180, "ration"},
               {185, "keycard"}}

function cross_tiles(pos)
  return {{d = 0, x = pos.x, y = pos.y - 1},
         {d = 1, x = pos.x + 1, y = pos.y},
         {d = 2, x = pos.x, y = pos.y + 1},
         {d = 3, x = pos.x - 1, y = pos.y},
         {d = -1, x = pos.x, y = pos.y}}
end

function restore_map()
  for m in all(mset_restore) do
    mset(m.x + levels[level][1], m.y + levels[level][2], m.t)
  end

  mset_restore = {}
end

function reset_level()
  turn = 0
  turn_start = nil
  idle_start = nil
  chunk = 0
  last_frame = 0
  frame = 1
  biframe = 1
  input_act = 0x00
  input_dir = -1
  temp_action = nil
  dir_down = -1
  restart_time = 0
  taking_input = false

  -- todo: fix this for real
  inventory["socom"] = prev_inventory["socom"]
  inventory["c4"] = prev_inventory["c4"]
  inventory["gloves"] = prev_inventory["gloves"]

  -- loading from checkpoint
  equipped = prev_equipped
  keycard = prev_keycard
end

function init_level_from_map(lv)
  actor_count = 0
  enemy_count = 0
  item_count = 0
  keycard_count = 0
  keydoor_count = 0

  actors = {}

  multilocks = {}
  scanners = {}
  relays = {}
  trapdoors = {}
  goals = {}
  items = {}
  prints = {}
  c4s = {}
  explosions = {}
  fires = {}
  rations = {}
  keycards = {}

  doors = {}
  multidoors = {}
  keydoors = {}

  for y = 0, levels[lv][4] - 1, 1 do
    for x = 0, levels[lv][3] - 1, 1 do
      for m in all(map_replace) do
        if (lmapget(x,y) == m[1]) then
          if (not m.no_floor) mset(x + levels[lv][1], y + levels[lv][2], 128) -- 128 is empty tile
          if (m.no_floor) mset(x + levels[lv][1], y + levels[lv][2], 255) -- 128 is pure black
          add(mset_restore, {x = x, y = y, t = m[1]})
          if (m[2] == "door") add_door(m, x, y)
          if (m[2] == "multidoor") add_multidoor(m, x, y)
          if (m[2] == "keydoor") add_keydoor(m, x, y)
          if (m[2] == "enemy1") add_enemy1(m, x, y)
          if (m[2] == "player" and current_relay == nil) add_player(m, x, y)
          if (m[2] == "scanner") add_scanner(m, x, y)
          if (m[2] == "relay") add_relay(m, x, y)
          if (m[2] == "trapdoor") add_trapdoor(m, x, y)
          if (m[2] == "goal") add_goal(m, x, y)
          if (m[2] == "item") add_item(m, x, y)
          if (m[2] == "multilock") add_multilock(m, x, y)
          if (m[2] == "ration") add_ration(m, x, y)
          if (m[2] == "keycard") add_keycard(m, x, y)
        end
      end
    end
  end
end

function add_keycard(m, x, y)
  keycard_count += 1
  k = {pattern = "keycard", pos = {x = x, y = y}, level = level_keycards[level][keycard_count]}
  if k.level > prev_keycard then
    add(keycards, k)
  end
end

function add_trapdoor(m, x, y)
  active_door = true
  if (m[1] == 177) active_door = false
  add(trapdoors, {pattern = "trapdoor", active = active_door, timer = 0, pos = {x = x, y = y}})
end

function add_multidoor(m, x, y)
  add(multidoors, {pattern = "multidoor", facing = m[3], open = 0, pos = {x = x, y = y}})
end

function add_keydoor(m, x, y)
  keydoor_count += 1
  add(keydoors, {pattern = "keydoor", facing = m[3], open = 0, pos = {x = x, y = y}, level = level_keydoors[level][keydoor_count]})
end

function add_multilock(m, x, y)
  add(multilocks, {pattern = "multilock", pos = {x = x, y = y}, active = false, player_allowed = m[3]})
end

function add_ration(m, x, y)
  add(rations, {pattern = "ration", pos = {x = x, y = y}})
end

function add_item(m, x, y)
  item_count += 1
  add(items, {pattern = level_items[level][item_count], pos = {x = x, y = y}})
end

function add_goal(m, x, y)
  add(goals, {pattern = "goal", pos = {x = x, y = y}})
end

function add_relay(m, x, y)
  r = {pattern = "relay", pos = {x = x, y = y}, active = 0}
  for p in all(prev_active_relays) do
    if p.x == x and p.y == y then
      r.active = 1
    end
  end

  add(relays, r)
  if current_relay != nil and cmp_pos(current_relay, {x = x, y = y}) then
    add_player({1, "player", 1}, x, y)
  end
end

function add_scanner(m, x, y)
  add(scanners, {pattern = "scanner", pos = {x = x, y = y}, unlocked = false, player_allowed = m[3]})
end

function add_door(m, x, y)
  add(doors, {pattern = "door", facing = m[3], open = 0, pos = {x = x, y = y}})
end

function add_enemy1(m, x, y)
  actor_count += 1
  enemy_count += 1
  a = {id = actor_count,
       pattern = "enemy1",
       facing = m[3],
       variant = level_enemy_variants[level][enemy_count],
       pos = {x = x, y = y},
       life = 1,
       laser_frames = 0,
       laser_target = 0,
       laser_direction = -1,
       laser_tiles = {},
       death_frames = 0,
       fall_frames = 0,
       hurt_frames = 0,
       attack_frames = 0,
       blood_prints = 0,
       stunned_turns = 0,
       blast_pos = nil,
       act = {a = 0x00, d = -1}}
  add(actors, a)
end

function add_player(m, x, y)
  actor_count += 1
  a = {id = actor_count,
       pattern = "player",
       facing = m[3],
       pos = {x = x, y = y},
       life = 3,
       max_life = 3,
       o2 = 3,
       max_o2 = 3,
       laser_frames = 0,
       laser_target = 0,
       laser_direction = -1,
       laser_tiles = {},
       death_frames = 0,
       fall_frames = 0,
       hurt_frames = 0,
       attack_frames = 0,
       blood_prints = 0,
       stunned_turns = 0,
       blast_pos = nil,
       act = {a = 0x00, d = -1}}
  add(actors, a)
  player = a
end

function _init()
  load_level(starting_level)
end

function load_level(lv)
  restore_map()
  level = lv

  reset_level()
  init_level_from_map(lv)

  player_action = {a = 0x00, d = -1}
  temp_action = nil
  idle_start = time()
end

function is_empty(t)
  for _,_ in pairs(t) do
    return false
  end
  return true
end

function print_on_tile(actor)
  p = nil
  for o in all(prints) do
    if ((o.pattern == "blood_prints" or o.pattern == "snow_prints") and cmp_pos(o.pos, actor.pos)) then
      p = o
      break
    end
  end
  return p
end

function do_enemy1_variant_movement_ai(actor, apos, mt)
  apos = act_pos(actor)

  if (mt == "clockwise") then
    directions_tried = 0
    while cmp_pos(apos, actor.pos) do
      actor.facing += 1
      if (actor.facing > 3) actor.facing = 4 - actor.facing
      actor.act.d = actor.facing
      apos = act_pos(actor)
      directions_tried += 1
      if (directions_tried > 4) actor.stunned_turns = 3; return
    end
  end

  if (mt == "line") then
    if (cmp_pos(apos, actor.pos)) do
      actor.facing += 2
      if (actor.facing > 3) actor.facing = abs(4 - actor.facing)
      actor.act.d = actor.facing
    end
  end

  if (mt == "still") then
    actor.act.d = -1
    actor.act.a = 0x10
  end

  return
end

function do_enemy1_ai(actor)
  if (actor.life <= 0 or actor.blast_pos != nil) then
    actor.act = {a = 0x00, d = -1}
    return
  end

  if (actor.stunned_turns > 0) then
    actor.stunned_turns -= 1
    if (actor.stunned_turns > 0) return
    ha = has_live_actor(actor.pos, "")
    if (ha and ha.id != actor.id) actor.stunned_turns = 1; return
  end

  -- if we find blood prints, follow. else, follow variant movement pattern
  movement_type = enemy_variants[actor.pattern][actor.variant][1]
  prev_facing = actor.facing
  actor.act.d = actor.facing
  printed = print_on_tile(actor)
  if (printed) then
    if (actor.act.a == 0x00) actor.act.d = printed.facing
    -- if we go nowhere with the print facing, try new directions until we find a free direction (invoke variant-based ai pattern).
    do_enemy1_variant_movement_ai(actor, apos, movement_type)
  else
    tiles = collect_tile_line(actor, actor.act.d, false, true)
    if (is_empty(tiles) or movement_type == "still") then
      -- if we can go nowhere, invoke variant-based ai pattern
      do_enemy1_variant_movement_ai(actor, apos, movement_type)
    end
  end

  found_player = false
  -- with old facing, look for player to shoot
  tiles = collect_tile_line(actor, prev_facing, true, true)
  if (not is_empty(tiles)) then
    for k, tile in pairs(tiles) do
      if (cmp_pos(player.pos, tile) and player.life > 0) then
        -- restore old facing on player found (todo: improve).
        actor.act.a = 0x01
        actor.act.d = prev_facing
        found_player = true
      end
    end
  end

  -- with new facing, look for player to shoot
  if (not found_player) then
    tiles = collect_tile_line(actor, actor.act.d, true)
    if (not is_empty(tiles)) then
      for k, tile in pairs(tiles) do
        if (cmp_pos(player.pos, tile) and player.life > 0) actor.act.a = 0x01
      end
    end
  end
end

function do_avoidance(actor)
  if (actor.life <= 0) return
  -- if we are moving into a tile that someone else plans on moving into, only one should move there.
  new_actor_pos = act_pos(actor)
  -- if we arent moving, no need to avoid
  if (cmp_pos(new_actor_pos, actor.pos)) then
    return
  end

  for a in all(actors) do
    if (a.life > 0) then
      apos = act_pos(a)

      -- todo: some enemy_variants should also dodge the player, so remove last clause for other ais
      if (a.id != actor.id and cmp_pos(apos, new_actor_pos) and a.pattern != "player") then
        actor.act.d = -1
        return true -- return true if avoidance was done. if so, all actors need to redo avoidance.
      end
    end
  end

  return false
end

function start_actors_turns()
  for actor in all(actors) do
      if (actor.pattern == "player") actor.act = {a=player_action.a, d=player_action.d}
      if (actor.pattern == "enemy1") do_enemy1_ai(actor)
      if (actor.act.d > -1) then
        actor.facing = actor.act.d
      end
    if (actor.blast_pos == nil) then
      pickup_prints(actor)
      if (actor.act.a == 0x01) sfx(10)
      if (actor.blood_prints >= 1) place_new_prints(actor, "blood_prints")
      if (is_snow(actor.pos)) place_new_prints(actor, "snow_prints")
    end
  end
  avoid = true

  while (avoid) do
    avoid = false
    for actor in all(actors) do
      if (actor.pattern == "enemy1") then
        avoid = do_avoidance(actor) or avoid -- we need to redo avoids if any avoid is found.
      end
    end
  end
end

function end_actors_turns()
  -- todo: different acts have different patterns
  -- todo: dry
  -- perform all moves first so shots line up
  for actor in all(actors) do
    -- todo: redirect to ai?
    if (actor != player) then
      if (actor.blast_pos == nil) then
        if (actor.blood_prints >= 1) redirect_existing_prints(actor, "blood_prints"); actor.blood_prints -= 1
        if (is_snow(actor.pos)) redirect_existing_prints(actor, "snow_prints")
      end
      perform_move(actor)
    end

    if (actor == player) then
      if (is_water(act_pos(actor)) and is_water(actor.pos)) then
        if (player.o2 <= 0 and player.life >= 0) hurt_actor(player, 1)
        if (player.o2 >= 1) player.o2 -= 1; sfx(12)
      else
        player.o2 = player.max_o2
      end
    end
  end

  if (player.blast_pos == nil) then
    if (player.blood_prints >= 1) redirect_existing_prints(player, "blood_prints"); player.blood_prints -= 1
    if (is_snow(player.pos)) redirect_existing_prints(player, "snow_prints")
  end

  perform_move(player)

  -- pick up rations
  for r in all(rations) do
    if (cmp_pos(player.pos, r.pos) and player.life > 0) then
      player.life = player.max_life
      sfx(15)
      del(rations, r)
    end
  end

  for r in all(relays) do
    if (cmp_pos(player.pos, r.pos) and player.life > 0) then
      if (r.active == 0) then
        sfx(18)
        r.active = 1

        del(prev_active_relays, r.pos)
        add(prev_active_relays, r.pos)

        -- ammo and life refill on checkpoint
        player.life = player.max_life
        inventory["socom"] = prev_inventory["socom"]
        inventory["c4"] = prev_inventory["c4"]
        inventory["gloves"] = prev_inventory["gloves"]

        -- save current item and keycard level
        prev_equipped = equipped
        prev_keycard = keycard
        current_relay = r.pos
      end
    end
  end

  -- pick up keycards
  for k in all(keycards) do
    if (cmp_pos(player.pos, k.pos) and player.life > 0) then
      keycard = k.level
      sfx(14)
      del(keycards, k)
    end
  end

  -- perform the acts
  for actor in all(actors) do
    if (actor.blast_pos == nil) then
      perform_act(actor)
    end

    actor.act = {a = 0x00, d = -1}
    actor.blast_pos = nil
  end
end

function to_pos(dr)
  return { x = pos_map[1][dr + 1],
           y = pos_map[2][dr + 1] }
end

function is_vaulting(actor)
  -- refactor for non-player vaulters
  return (actor == player and equipped == "gloves" and actor.act.a == 0x01)
end

function act_pos(actor)
  if (actor.blast_pos != nil) return actor.blast_pos

  -- todo: different acts have different movements.
  -- we shoehorn vaulting in here, but like blast_pos, it needs its own system.
  actor_point = {x = actor.pos.x, y = actor.pos.y}
  if (actor.act.d < 0 and not is_vaulting(actor)) then
    return actor_point
  else
    if (actor.act.d == -1) actor.act.d = actor.facing
  end


  act_dir = to_pos(actor.act.d)
  test_point = {x = actor.pos.x + act_dir.x, y = actor.pos.y + act_dir.y}

  -- gloves function
  if (is_vaulting(actor) and is_vault_gate(test_point)) then
    new_point = {x = test_point.x + act_dir.x, y = test_point.y + act_dir.y}
    if (is_wall(new_point)) return actor_point
    return new_point
  end

  if (is_wall(test_point) or (actor != player and is_water(test_point))) return actor_point

  -- todo: other future moves may not move the player. consider refactoring all actions.
  if (actor.act.a != 0x00) return actor_point
  return test_point
end

function lmapget(x, y)
 return mget(x + levels[level][1], y + levels[level][2])
end

function is_door_wall(ds, pos)
  for o in all(ds) do
    if (cmp_pos(o.pos, pos)) then
      if (o.open == 1) return false
      return true
    end
  end
end

function is_snow(pos)
  m = lmapget(pos.x, pos.y)
  return (m == 146 or m == 162 or m == 163 or m == 164 or m == 165)
end

function is_wall(pos)
  m = lmapget(pos.x, pos.y)
  return is_door_wall(doors, pos) or is_door_wall(multidoors, pos) or is_door_wall(keydoors, pos) or (m >= 64 and m <= 127)
end

function is_vault_gate(pos)
  m = lmapget(pos.x, pos.y)
  return (m == 70 or m == 71)
end

function is_glass(pos)
  m = lmapget(pos.x, pos.y)
  return (m == 119 or m == 120)
end

function is_water(pos)
  m = lmapget(pos.x, pos.y)
  return (m == 182)
end

function is_adjacent(a, b)
  return ((a.pos.x == b.pos.x + 1 and a.pos.y == b.pos.y) or
    (a.pos.x == b.pos.x - 1 and a.pos.y == b.pos.y) or
    (a.pos.x == b.pos.x and a.pos.y == b.pos.y + 1) or
    (a.pos.x == b.pos.x and a.pos.y == b.pos.y - 1))
end


function open_doors_near(scans)
  for s in all(scans) do
    s.unlocked = true

    for d in all(doors) do
      if is_adjacent(d, s) then
        d.open = 1
      end
    end
  end
end

function open_keydoors()
  for d in all(keydoors) do
    if (is_adjacent(d, player)) then
      if (keycard >= d.level) then
        if (d.open < 1) sfx(16)
        d.open = 1
      else
        sfx(17)
      end
    end
  end
end

function switch_multilocks(locks)
  for l in all(locks) do
    l.active = not l.active
  end
end

function open_multilock_doors()
  for l in all(multilocks) do
    if (not l.active) return
  end

  for d in all(multidoors) do
    d.open = 1
  end
end

function active_buttons(bts)
  rets = {}

  for o in all(bts) do
    if (o.pattern == "scanner" or o.pattern == "multilock") then
      for a in all(actors) do
        if (a.pattern != "player" or o.player_allowed) then
          if (cmp_pos(a.pos, o.pos) and a.life > 0) add(rets, o)
        end
      end
    end
  end

  return rets
end

function keycard_door_attempts(doors)

end


function redirect_existing_prints(actor, pat)
  if (actor.life <= 0) return

  p = print_on_tile(actor)
  if (p and actor.act.d != -1 and p.pattern == pat) p.facing = actor.act.d
end

function place_new_prints(actor, pat)
  if (actor.life <= 0) return
  if (is_water(actor.pos)) return
  for t in all(trapdoors) do
    if (cmp_pos(actor.pos, t.pos)) return
  end

  p = print_on_tile(actor)
  if (not p) then
    d = actor.act.d
    if (d == -1) d = actor.facing
    o = { pattern = pat, facing = d, pos = {x = actor.pos.x, y = actor.pos.y} }
    add(prints, o)
  end
end

function pickup_prints(actor)
  if (actor.life <= 0) return

  for a in all(actors) do
    if (a.life <= 0 and actor.life > 0 and cmp_pos(a.pos, actor.pos)) then
      actor.blood_prints = 5
    end
  end
end

function has_live_actor(np, exclude_pattern)
  for a in all(actors) do
    if (a.life > 0) then
      if (a.pattern != exclude_pattern and cmp_pos(a.pos, np)) then
        return a
      end
    end
  end
  return false
end

function attempt_melee(actor)
  attack_point = act_pos(actor)

  h = has_live_actor(attack_point, "player")

  if (h) then
    stun_actor(h, 3)
    return h
  end

  return nil
end

function attempt_move(actor)
  -- todo: characters other than player can melee

  if (actor.pattern == "player" and player.life > 0) attempt_melee(actor)
  actor.pos = act_pos(actor)
end

function collect_tile_line(actor, d, ignore_glass)
  collected = {}
  if (not (d >= 0)) return collected

  tx = actor.pos.x + to_pos(d).x
  ty = actor.pos.y + to_pos(d).y

  i = 1
  p = {x = tx, y = ty}
  while not (is_wall(p) and (not is_glass(p) or not ignore_glass)) do
    collected[i] = p
    i+=1

    tx += to_pos(d).x
    ty += to_pos(d).y

    p = {x = tx, y = ty}
  end

  return collected
end

function stun_actor(actor, turns)
  actor.stunned_turns = turns
end

function fall_actor(actor)
  actor.life = -2
  actor.fall_frames = 2
end

function hurt_actor(actor, amount)
  if (actor.life > 0) actor.life -= amount
  if (actor.life < 0) actor.life = 0
  if (actor.life == 0) then
    sfx(5)
    actor.life = -1
    if (not is_water(actor.pos)) actor.death_frames = 4
  else
    sfx(5, -1, 1, 3)
    if (not is_water(actor.pos)) actor.hurt_frames = 2
  end
end

function attempt_action(player)
  if (equipped == "socom") then
    if (inventory["socom"] <= 0) return
    inventory["socom"] -= 1
    attempt_shot(player)
    return
  end

  if (equipped == "c4") then
    attempt_c4(player)
    return
  end

  attempt_melee(player)
end

function c4s_for(actor)
  cs = {}
  for c in all(c4s) do
    if (c.owner.id == actor.id) add(cs, c)
  end
  return cs
end

function blast_actor(a, d)
  if (d == -1) return

  ts = collect_tile_line(a, d, true, true)
  blast_index = 4
  if (#ts < 4) then
    blast_index = #ts
  end

  blast_to = ts[blast_index]

  for k, t in pairs(ts) do
    if (k > blast_index) break
    break_glass(t)

    for aa in all(actors) do
      if (aa != player and aa.id != a.id and cmp_pos(aa.pos, t) and aa.life > 0) then
        stun_actor(aa, 2)
        a.blast_pos = aa.pos
        return
      end
    end
  end

  hurt_actor(a, 1)
  a.blast_pos = blast_to
end

function cmp_pos(a, b)
  if (a.x == b.x and a.y == b.y) return true
  return false
end

function trip_trapdoors()
  for t in all(trapdoors) do
    if (t.timer > 0) then
      t.timer -=1
      if (t.timer == 0) t.active = false; sfx(13)
    end

    for a in all(actors) do
      if (a.life > 0 and cmp_pos(a.pos, t.pos)) then
        if (t.active) then
          sfx(11)
          t.timer = 1
        else
          sfx(5)
          fall_actor(a)
        end
      end
    end
  end
end

function blow_c4(c, wait)
  sfx(7)

  for t in all(cross_tiles(c.pos)) do
    add(explosions, {frames = 4, pos = {x = t.x, y = t.y}})

    for a in all(actors) do
      if (cmp_pos(a.pos, t) and a.life > -2) then -- > -2 because disappeared shouldnt blow
        hurt_actor(a, 2)
        blast_actor(a, t.d)
      end
    end

    break_glass(t)
    break_wall(t)
  end

  del(c4s, c)
end

function break_wall(pos)
  nt = lmapget(pos.x, pos.y)
  if (nt == 69 or nt == 85) swap_restore(pos, nt, 128)
end

function break_glass(pos)
  nt = lmapget(pos.x, pos.y)
  if (nt == 119) swap_restore(pos, nt, 178)
  if (nt == 120) swap_restore(pos, nt, 179)
end

function swap_restore(pos, a, b)
  mset(pos.x + levels[level][1], pos.y + levels[level][2], b)
  add(mset_restore, {x = pos.x, y = pos.y, t = a})
end

function attempt_c4(actor)
  dir = actor.act.d
  if (dir == -1) dir = actor.facing
  if (inventory["c4"] <= 0) return
  d = to_pos(dir)
  add(c4s, {owner = actor, timer = 3, pattern = "c4", pos = {x = actor.pos.x + d.x, y = actor.pos.y + d.y}})
  inventory["c4"] -= 1
end

function queue_lasers(actor, a, tiles, d)
  actor.laser_frames = 2
  del(tiles, tiles[#tiles])
  actor.laser_target = a.pos
  actor.laser_direction = d
  actor.laser_tiles = tiles
end

function attempt_shot(actor)
  if (actor.id == player.id and player.act.d == -1) player.act.d = player.facing

  sfx(4)
  tiles = {}
  for i, tile in pairs(collect_tile_line(actor, actor.act.d, true)) do
    hurts = {}
    add(tiles, tile)

    for j, a in pairs(actors) do
      if (actor != a and cmp_pos(a.pos, tile) and a.life > 0) then
        add(hurts, a)
      end
    end

    l = #hurts
    for a in all(hurts) do
      if (l > 1) then
        if (a != player and a.life > 0) then
          hurt_actor(a, 1)
          queue_lasers(actor, a, tiles, actor.act.d)
          return
        end
      else
        if (l == 1) then
          hurt_actor(a, 1)
          queue_lasers(actor, a, tiles, actor.act.d)
          return
        end
      end
    end
  end
end

function perform_move(actor)
  if (actor.act.a == 0x00 or (equipped == "gloves" and actor == player and actor.act.a == 0x01)) then
    attempt_move(actor)
  end
end

function perform_act(actor)
  if (actor.act.a == 0x01) then
    if (actor.id == player.id) then
      attempt_action(actor)
    else
      attempt_shot(actor)
    end
  end
end

function check_goals()
  for g in all(goals) do
    for a in all(actors) do
      if (cmp_pos(a.pos, g.pos) and a.life > 0 and a.pattern == "player") then
        load_level(level + 1)
        return true
      end
    end
  end

  return false
end

function roll_frame()
  for actor in all(actors) do
    if (actor.laser_frames > 0) actor.laser_frames -= 1
    if (actor.fall_frames > 0) actor.fall_frames -= 1
    if (actor.death_frames > 0) actor.death_frames -= 1
    if (actor.hurt_frames > 0) actor.hurt_frames -= 1
    if (actor.attack_frames > 0) actor.attack_frames -= 1
  end

  for e in all(explosions) do
    if (e.frames > 0) e.frames -= 1
  end
end

function update_frame(start)
  chunk = flr(((time() - start) * game_speed) * 100)
  frame = mid(1, flr(chunk / 25) + 1, 4)
  biframe = mid(1, flr(chunk / 12.5) + 1, 8)

  -- chunk > 25 ensures every frame gets a fair shake; extends animations into idle time.
  if (frame != last_frame and chunk > 25) then
    roll_frame()
    last_frame = frame
  end
end

function start_turn()
  turn += 1

  idle_start = nil
  turn_start = time()
  update_frame(turn_start)

  for c in all(c4s) do
    if (c.timer == 0) blow_c4(c)
    if (c.timer > 0) then
      sfx(6)
      c.timer -= 1
    end
  end

  start_actors_turns()
end

function end_turn()
  end_actors_turns()
  pick_up_items()
  trip_trapdoors()
  open_doors_near(active_buttons(scanners))
  switch_multilocks(active_buttons(multilocks))
  open_keydoors()
  open_multilock_doors()
  prune_explosions()
  check_goals()

  player_action = {a = 0x00, d = -1}
  turn_start = nil
  idle_start = time()
end

function prune_explosions()
  for e in all(explosions) do
    if (e.frames <= 0) del(explosions, e)
  end
end

function attempt_swap()
  -- todo: refactor
  if (player.life <= 0) return
  temp_action = {a = 0x00, d = -1}
  if (equipped == "c4" and inventory["socom"] > -1) equipped = "socom"; return
  if (equipped == "socom" and inventory["c4"] > -1) equipped = "c4"; return
end

function input_direction(d)
  if (btn(0)) d = 3
  if (btn(1)) d = 1
  if (btn(2)) d = 0
  if (btn(3)) d = 2
  return d
end

-- this function is horribly written but until i refactor "actions" it works and its intuitive to use
function input_action(a)
  if (btn(4)) then
    if (not z_down) then
      if (a == 0x01) then
        a = 0x00
      else
        a = 0x01
      end
      z_down = true
    end
  else
    z_down = false
  end
  if (btn(5)) then
    if (not x_down) then
      if (a == 0x10) then
        a = 0x00
      else
        a = 0x10
      end
      x_down = true
    end
  else
    x_down = false
  end

  return a
end

function any_input()
  return (btn(0) or btn(1) or btn(2) or btn(3) or btn(4) or btn(5))
end

function do_turn()
  if (temp_action != nil) player_action = temp_action

  if (player_action.a == 0x10) then
     attempt_swap()
     player_action = {a = 0x00, d = -1}
   end

  if (turn_start == nil) temp_action = nil; start_turn(); return
  update_frame(turn_start)

  if (chunk >= 100) end_turn()
end

function take_input(restart_only)
  input_act = input_action(input_act)
  input_dir = input_direction(input_dir)

  if (btn(4) and btn(5)) then
    if (not restarting) restart_time = time()
    restarting = true
    if (time() - restart_time >= 2 or restart_only) to_restart = true; return
  else
    if (not (btn(4)) and not (btn(5))) then
      restarting = false
      if (to_restart) to_restart = false; load_level(level);
    end
  end
  if (restart_only) return

  if (idle_start != nil) then
    update_frame(idle_start)
    played_cancel = false

    if (any_input()) then
      if (not taking_input) sfx(9)
      temp_action = {a = input_act, d = input_dir}
      taking_input = true
      return false
    end

    if (taking_input and not any_input()) then
      taking_input = false
      idle_start = nil
      input_act = 0x00
      input_dir = -1
      return false
    end

    return false
  else
    -- if (any_input() and played_cancel == false) played_cancel = true; sfx(8)
  end

  return true
end

function _update()
  if (player.life <= 0) then
    take_input(true)
    do_turn()
    return
  end

  if (not take_input(false)) return
  do_turn()
end

function pick_up_items()
  for i in all(items) do
    if cmp_pos(player.pos, i.pos) then
      inventory[i.pattern] = inventory_max[i.pattern]
      equipped = i.pattern
      del(items, i)
    end
  end
end

function tile_shift(actor)
  apos = act_pos(actor)
  if (not cmp_pos(apos, actor.pos)) return {x = (apos.x - actor.pos.x) * frame * 2, y = (apos.y - actor.pos.y) * frame * 2}
  return {x=0, y=0}
end

function sprite_for(actor)
  if (actor.life <= 0) then
    if (actor.death_frames > 0) then
      return sprites[actor.pattern][5][(4 - actor.death_frames) + 1]
    else
      if (actor.fall_frames > 0) then
        return sprites[actor.pattern][6][(2 - actor.fall_frames) + 1]
      end
    end

    if (actor.life == -2 or is_water(actor.pos)) then -- disappeared
      return 255
    end

    return sprites[actor.pattern][5][4]
  end

  if (actor == player and is_water(actor.pos) and is_water(act_pos(actor))) return 14

  if (actor.blast_pos != nil) then
    return sprites[actor.pattern][actor.facing + 1][8]
  end

  if (actor.hurt_frames > 0) then
    return sprites[actor.pattern][5][(2 - actor.hurt_frames) + 1]
  end

  if (actor.stunned_turns > 0) then
    return sprites[actor.pattern][8][(frame % 2) + 1]
  end

  if (turn_start != nil) then
    if (actor.act.a != 0x00 and (actor.id == player.id and equipped == "c4")) return sprites[actor.pattern][actor.facing+1][6]
    if (actor.act.a != 0x00 and (actor.id != player.id or equipped == "socom")) return sprites[actor.pattern][actor.facing+1][7]
    if (actor.act.d > -1) return sprites[actor.pattern][actor.facing+1][frame+1]
  end

  if (actor.facing == -1) return sprites[actor.pattern][1][1]
  return sprites[actor.pattern][actor.facing+1][1]
end

function pal_swap(actor)
  s = tile_shift(actor)
  palswap = enemy_variants[actor.pattern][actor.variant][2]
  pal(palswap[1], palswap[2])
  spr(sprite_for(actor), actor.pos.x*8 + s.x, actor.pos.y*8 + s.y)
  pal(palswap[1], palswap[1])
end

function draw_actors()
  -- draw dead and stunned enemy_variants first
  for actor in all(actors) do
    if (actor.life <= 0 or actor.stunned_turns > 0) then
      if (actor.pattern != "player") then
        pal_swap(actor)
      end
    end
  end

  for actor in all(actors) do
    if (actor.life > 0) then
      if (actor.pattern != "player") then
        pal_swap(actor)
      end
    end
  end

  -- draw the player
  s = tile_shift(player)
  spr(sprite_for(player), player.pos.x*8 + s.x, player.pos.y*8 + s.y)
end

function draw_lasers()
  for actor in all(actors) do
    if (actor.act.a == 0x01) then
      d = actor.act.d
      if (d == -1) d = actor.facing
      tiles = collect_tile_line(actor, d, true, false)
      for tile in all(tiles) do
        if (actor != player or inventory["socom"] > -1 and equipped == "socom") spr(sprites[actor.pattern][7][d % 2 + 1], tile.x*8, tile.y*8)
      end
      -- if (actor == player and equipped == "socom" and inventory["socom"] > 1) then
      --   spr(46, tiles[1].x*8, tiles[1].y*8)
      --   spr(47, tiles[#tiles].x*8, tiles[#tiles].y*8)
      -- end
    end

    if (actor.laser_frames > 0) then
      for tile in all(actor.laser_tiles) do
        if (actor != player or inventory["socom"] > -1 and equipped == "socom") then
          if (actor.laser_frames == 1) pal(8,2); pal(11,3)
          spr(sprites[actor.pattern][7][actor.laser_direction % 2 + 1], tile.x*8, tile.y*8)
          spr(sprites[actor.pattern][7][actor.laser_direction % 2 + 1], tile.x*8 + (actor.laser_direction % 2), tile.y*8 + (1 - actor.laser_direction % 2))
          pal(8,8)
          pal(11,11)
        end
      end
    end
  end
end

function draw_idle_ui()
  if (idle_start != nil) then
    f = false
    if (frame > 3) f = true
    if (f) pal(7,10)
    if (input_act == 0x01) pal(7,8)
    if (input_act == 0x10) pal(7,3)
    spr(159, player.pos.x * 8, (player.pos.y - 1) * 8)
    pal(7,7)
  end
end

function draw_movement_ui()
  if (temp_action != nil and temp_action.a == 0x00 and temp_action.d != -1 and idle_start != nil) then
    ap = to_pos(temp_action.d)
    fp = {x = player.pos.x + ap.x, y = player.pos.y + ap.y}
    pal(8, 11)
    spr(46, fp.x * 8, fp.y * 8)
    spr(sprites["objects"]["blood_prints"][temp_action.d+1], fp.x * 8, fp.y * 8)
    pal(8, 8)
  end
end

function draw_gloves_ui()
  if (temp_action == nil) return
  if (idle_start != nil and temp_action.a == 0x01 and equipped == "gloves") then
    d = temp_action.d
    if (d == -1) d = player.facing
    ap = to_pos(d)
    fp = {x = player.pos.x + ap.x, y = player.pos.y + ap.y}
    spr(31, fp.x * 8, fp.y * 8)
  end
end


function draw_gun_ui()
  if (temp_action == nil) return
  if (idle_start != nil and temp_action.a == 0x01 and equipped == "socom") then
    d = temp_action.d
    if (d == -1) d = player.facing
    ap = to_pos(d)
    fp = {x = player.pos.x + ap.x, y = player.pos.y + ap.y}
    spr(47, fp.x * 8, fp.y * 8)
  end
end


function draw_death_ui()
  print("game over.", 47, 57, 2)
  print("game over.", 46, 58, 8)
  print("restart? press z+x", 28, 76, 5)
  print("restart? press z+x", 27, 77, 7)
end

function draw_c4_ui()
  if (temp_action == nil) return
  if (idle_start != nil and temp_action.a == 0x01 and equipped == "c4") then
    d = temp_action.d
    if (d == -1) d = player.facing
    ap = to_pos(d)
    fp = {x = player.pos.x + ap.x, y = player.pos.y + ap.y}
    spr(43, fp.x * 8, fp.y * 8)
  end
end

function draw_restart_ui()
  if (temp_action == nil) return
  if (idle_start != nil and btn(4) and btn(5)) then
    print("restart?", 49, 65, 5)
    print("restart?", 48, 66, 7)
    l = 2 - flr(time() - restart_time)
    if (time() - restart_time >= 2) then
      print("release!", 51, 73, 2)
      print("release!", 50, 74, 8)
    else
      print(tostr(l), 63, 73, 2)
      print(tostr(l), 62, 74, 8)
    end
  end
end

function object_spr(o, i)
  spr(sprites["objects"][o.pattern][i], o.pos.x*8, o.pos.y*8)
end

function draw_objects()
  for o in all(scanners) do
    if (o.player_allowed or o.unlocked) then
      object_spr(o, 2)
    else
      object_spr(o, 1)
    end
  end

  for t in all(trapdoors) do
    if (t.active) then
      object_spr(t, 1)
    else
      object_spr(t, 2)
    end
  end

  for m in all(multilocks) do
    if (m.active) then
      object_spr(m, 2)
    else
      if (m.player_allowed) then
        object_spr(m, 3)
      else
        object_spr(m, 1)
      end
    end
  end

  for g in all(goals) do
    object_spr(g, 1)
  end

  for r in all(rations) do
    object_spr(r, 1)
  end

  for k in all(keycards) do
    object_spr(k, 1)
  end
end

function draw_above_prints_objects()
  for o in all(doors) do
    spr(sprites["objects"][o.pattern][o.facing + 1][o.open + 1], o.pos.x*8, o.pos.y*8)
  end

  for o in all(multidoors) do
    spr(sprites["objects"][o.pattern][o.facing + 1][o.open + 1], o.pos.x*8, o.pos.y*8)
  end

  for o in all(keydoors) do
    spr(sprites["objects"][o.pattern][o.facing + 1][o.open + 1], o.pos.x*8, o.pos.y*8)
  end

  for r in all(relays) do
    spr(sprites["objects"][r.pattern][r.active + 1], r.pos.x*8, r.pos.y*8)
  end
end

function draw_items()
  for i in all(items) do
    spr(sprites["items"][i.pattern], i.pos.x*8, i.pos.y*8)
  end

  for i in all(c4s) do
    if (is_wall(i.pos) or is_glass(i.pos)) then
      spr(171, i.pos.x*8, i.pos.y*8)
    else
      spr(170, i.pos.x*8, i.pos.y*8)
    end
  end
end

function draw_explosions()
  for e in all(explosions) do
    if (e.frames > 0) spr(sprites["effects"]["explosion"][(4 - e.frames) + 1], e.pos.x * 8, e.pos.y * 8)
  end
end

function draw_prints()
  for o in all(prints) do
    spr(sprites["objects"][o.pattern][o.facing + 1], o.pos.x*8, o.pos.y*8)
  end
end

function draw_socom()
  spr(155, 110, 118)
  spr(156, 118, 118)

  for i = 0, (3 - inventory["socom"]), 1 do
    draw_socom_bullet(117+i*2,120, 5)
  end
end

function draw_c4()
  spr(157, 110, 118)
  spr(158, 118, 118)

  for i = 0, (1 - inventory["c4"]), 1 do
    draw_c4_bullet(119+i*3,120, 5)
  end
end

function draw_hands()
  spr(139, 118, 118)
end

function draw_socom_bullet(x,y,c)
  pset(x,y,c)
  pset(x,y+1,c)
  pset(x,y+3,c)
end

function draw_c4_bullet(x,y,c)
  pset(x,y,c)
  pset(x,y+1,c)
  pset(x,y+3,c)

  pset(x+1,y,c)
  pset(x+1,y+1,c)
  pset(x+1,y+3,c)
end

function draw_blood_ui()
  spr(143, 112, 3)
  print(player.blood_prints, 121, 4, 7)
end

function draw_keycard_ui()
  spr(185, 85, 3)
  print("lv."..keycard, 93, 4, 7)
end

function draw_ui()
  -- draw action symbols

  --draw health bar
  rect(2,2,player.max_life * 5 + 3,7,6)
  rectfill(3,3,player.max_life * 5 + 2,6,2)
  if (player.life > 0) rectfill(3,3,player.life * 5 + 2,6,3)
  print("life", 4, 6, 7)

  -- draw o2 bar
  if (is_water(player.pos)) then
    rect(2,13,player.max_o2 * 5 + 3,18,6)
    rectfill(3,14,player.max_o2 * 5 + 2,17,1)
    if (player.o2 > 0) rectfill(3,14,player.o2 * 5 + 2,17,12)
    print("o2", 4, 17, 7)
  end

  -- draw item use.
  if (temp_action != nil and temp_action.a == 0x10) then

  else
    if (equipped == "socom") draw_socom()
    if (equipped == "gloves") draw_hands()
    if (equipped == "c4") draw_c4()
  end

  if (player.blood_prints >= 1) draw_blood_ui()
  if (keycard > 0) draw_keycard_ui()

  -- nice little window border
  rect(0,0,127,127,5)
end

function _draw()
  cls()
  l = levels[level]
  a = act_pos(player)
  if cmp_pos(player.pos, a) then
    camera((player.pos.x * 8) - 60, (player.pos.y * 8) - 64)
  else
    xd = a.x - player.pos.x
    yd = a.y - player.pos.y
    camera((xd * biframe) + (player.pos.x * 8) - 60, (yd * biframe) + (player.pos.y * 8) - 64)
  end
  map(l[1], l[2], 0, 0, l[3], l[4])
  draw_objects()
  draw_prints()
  draw_above_prints_objects()
  draw_items()
  draw_actors()
  draw_explosions()
  if (player.life > 0) then
    draw_movement_ui()
    draw_gun_ui()
    draw_gloves_ui()
    draw_c4_ui()
    draw_idle_ui()
  end
  draw_lasers()
  camera(0, 0)
  if (player.life <= 0) then
    draw_death_ui()
  else
    draw_restart_ui()
  end
  draw_ui()
end
__gfx__
00000000000000000000000000000000441444400000000000000000000000000000010080000000080000000000000000000000000000000000000000000000
0000000000444400000000000104444000411110010444400000000004444000004444100e044400000e08000000000000000000000000000000000000000000
00700700041111000044440004111110100f3f30041111100044440041111000041811408883114000808e800000000000000000000000000044440000000000
0007700001f3f30004111100004f3f30151ffff0004f3f30041111001f3f3000043f3f000e8ef340100388140000000000000000000000000411110000000000
0007700004ffff0001f3f300000ffff015111f1f000ffff001f3f3004fff55600888fff01888f440108e8f14000388e1004444000000000001f3f30000000000
0070070000111000041fff0000f11f0000000000001110f0044fff000111f5000081110005811480051ff34480e88388041f110f000000000000000000000000
000000000f555f0000111f0000155000000000000f0551000111f1f0055500000f0551008058000805111e801188ff8401f1f301000000000000000000000000
000000000010100000f110000000010000000000001000000015111001010000000001000011000000f110e811f8844004f1ff0100f000f00000000000000000
000000000000000000000000000000000000000000000000000000000000500000000000000b0000008800000000000000000000000000000000000000000000
00000000004440000000000000444100000000000004140000000000000444000000000000000000008800000000000000800000000000000000000033000033
000000000444440000044400044414001041440000444140004440000044444000000000000b0000008000000000088800880000000088800000000030000003
00000000011111000044444001111100111114400011111004444400001111100b0b0b0b000000000000000000000088008800000000880000000000000bb000
000000000f441400001111100f44440015555100004444f00111110000f4414000000000000b00000000880000880000000000008800000000000000000bbb00
000000000044400000f4410001544000f11110f00005441004414f00001111f000000000000000000000880008880000000008008880000000000000000b0000
000000000f555f00000555f0001510000000000000055100015551000005550000000000000b0000000008000000000000008800000000000000000030000003
000000000010100000f1110000100f000000000000f0010000111000000101000000000000000000000000000000000000008800000000000000000033000033
00000000000000000000000000100000004444000000010000000000000000000000000000008000000000000000000000000000000000000000000000000000
00000000004444000000000001444400041111000044441000000000004444000000000000000000000000000000000000000000002220000000000033000033
00000000041111000044440004111140103f3400041111400044440004111400000000000000800000000000000000000000000002eee2000000000030000003
00000000013f3f000411110000f3f34001fff410043f3f0000111140043f340000000000000000000000008000000000000000002e222e200000000000bbbb00
0000000000ffff0001f3f3000fffff000f111f0000fffff0003f3f10016ff100080808080000800000008800000bb000000880002eee2e200000000000bb0000
0000000000111000041fff0000111100001150000011110001fff10000f1110000000000000000008088888000bbbb00008888002ee22e200000000000b00000
000000000f555f0000111f00001550f0000000000f055100011f110000555000000000000000800000080800300000032000000202eee2003000000330000003
000000000010100000f5100000100000000000000000010000115f10001010000000000000000000000000003300003322000022002220003300003333000033
00000000000000000000000000000000044441440000000000000000000000000000000000000000000000000000000000000000000000000000099999900000
00000000004444000000000004444010011114000444401000000000000444400033300000222000005550000055500000555000005550000000090000900000
0000000000111140004444000111114003f3f00101111140004444000001111403bbb30002888200056665000566650005666500056665000000090000900000
00000000003f3f100011114003f3f4000ffff15103f3f400001111400003f3f13b3b3b3028828820566566505655665056565650566556500009000000009000
0000000000ffff40003f3f100ffff000f1f111510ffff000003f3f100655fff43bb3bb3028282820565556505665565056555650565566500009000000009000
000000000001110000fff14000f11f00000000000f01110000fff440005f11103b3b3b3028828820565656505655665056656650566556500000090000000000
0000000000f555f000f111000005510000000000001550f00f1f11100000555003bbb30002888200056665000566650005666500056665000000090000900000
000000000001010000011f0000100000000000000000010001115100000010100033300000222000005550000055500000555000005550000000099999900000
0000000000000000000000000156651000100100000000000010010000150100015665100c11c110011c11c07656651077777777015665670000000000000000
00111111111111111111110001125110110110111001000101011010010510101115651110101011110101017756651077717776015665771111111100000000
01566555515665555556651000025000510000155111501155666655010610111555651001006105501600107756611055551555015661775555155500000000
016566666566566666665610010250106555555661556655515150511106101065661101c00511666611500c7756651066666566015665176666656600000000
01666666666666666666661001025010622222266656615650505050011601006611500c10116656656611017655651066566666015565676656666600000000
01566551155665551556651000025000510000155155101501010100111610115016001001565551155565107756651051555555015665775155555500000000
01566111115655111116651001125110110110110011000100000000010510101101110111565111111565117716651011111111011665776776766700000000
0156651001566110015665100156651000000000000000000000000000150101011c00c001566510015665107656651000000000015665677777777600000000
01566510015665100116651000111100010110000115651001001000001001000156651000100100015661100776667600000000000000000000000000000000
01566510111665111155651101555510115111500015510010110100010110100119511011011011110655111111116600000000000000000000000000000000
01566110155665515556655115444551115556110006100010166655566610100009500051000015101165155155566700000000000000000000000000000000
01566510666666666666666655555451055665510056610010160510150610100109501065555556c16165566665667600000000000000000000000000000000
01556510656566656665666554445451151565510115651001060500050601000109501069999996010516666666667700000000000000000000000000000000
01566510555665515556655554445451151551510015551010161010101610100009500051000015010015555555566700000000000000000000000000000000
01166510115665111111111154445510115655100011610000160101010610010119511011011011c01001111111116600000000000000000000000000000000
01566510000561000000000015555100051550100156650001051000001501000156651000000000010c10106777666700000000000000000000000000000000
01566510000000000156651000166510010000000000010001061000001601000156651000100100010000000000000000000000000000000000000000000000
0156611111111111111665100016651100510000001511101016010001061010011c511011011011005100000000000000000000000000000000000000000000
0156655155551555155665100156655111151010115666501016655555661010000c500051000015111510100000000000000000000000000000000000000000
0166666666666566666666100166666601516000015565001015051015051010010c501065555556015160000000000000000000000000000000000000000000
0165666666566666666656100165666500015110000155510105050005050100010c50106cccccc6000151100000000000000000000000000000000000000000
0156655551555555555665100156655100011500000016501010101010101010000c500051000015000115000000000000000000000000000000000000000000
0011111111111111111111000016651100100010000051100011010101011001011c511011011011001000100000000000000000000000000000000000000000
00000000000000000000000000156100000000110000110001001000001001000156651000000000000000110000000000000000000000000000000000000000
00111100011665100000000001566100000000000000000001511100005c75000010010000000000005c75000010010000000000000000000000000000000000
011551100156651001111111115561001111111015155100166510100107c01001011010011111110c00c0100101101000000000000000000000000000000000
01566110015565101155551515566510515555115666661005510010000cc00050000005111555550000000050c0000500000000000000000000000000000000
01566510015665101566566666666610666566516681666156500001010cc0107cccc7cc1566666601000010700000cc00000000000000000000000000000000
01556510015661101566666656665610666666516110166166510010010cc010c7cccc7c1566566601000c10c700000c00000000000000000000000000000000
01566510011551101115555515566510555551116100156106651010000c70005000000511555515000c00005000000500000000000000000000000000000000
011665100011110001111111115661001111111066555610156551510107c01001011010011111110107101001011c1000000000000000000000000000000000
01566510000000000000000000166100000000000166610051115500005cc5000010010000000000005cc5000010010000000000000000000000000000000000
0010010001566510000000000010010000000000000000000010010001000010001001000010010000100100bbbbbbbb88888888666666666666666600008000
010110100112511011011011010110100dccccd0000000000101101003bbbb30011651500116515001165150b333333b82222228611000111000111600088800
00000000000000005100001501555510d000000d000000000155551033333333016115100161151001611510b33bbb3b8282222861b308218208211688008800
0100001001000010600000560281182000dccd000055850003b11b300000000000582100005b3100005a9100b3bbbb3b82282228601110001110001688000880
010000100100001060000026028118200d0000d00000000003b11b30bbbbbbbb001285000013b5000019a500b3b3333b82228228608218208218200608800000
00000000000000005100001501555510000cc000005585000155551033333333015116100151161001511610b33bbb3b82228828600011100011100600008800
0101101001000010110110110101101001011010005555000101101001000010051561100515611005156110b333333b8222222861b9c8110001110600008880
0010010001000010000000000010010000100100000000000010010013bbbb31001001000010010000100100bbbbbbbb88888888666666666666666600000088
01566510000000007777677777777677001001000666776677676600001001000000000667777777776766608888888888888888bbbbbbbbbbbbbbbb00000000
01195110110110117677767777677767060110100167677777777760060110100101666706777677777777008222222222222228b33333333333333b00000000
00000000510000156777777767767777676060601006777776777601676060001006777706776776767776018288882929292928b3bbbb333993993b00010000
01000010600000567777777777777767677676760167777777676010677676100167777706777777776760108288222929292928b3b3bbb33993993b00171000
01000010600000967777676767767676777777670106767777777610777777600106767701676776777776108282222222222228b3bb3b333333333b00171000
00000000510000156777767767606066677677771067776777776001677677601067776700060676766760018222222929292928b33333333993993b00111000
01000010110110117777777706011016776777760677777777767610776777600677777701011060760610108222222222222228b33333333333333b00171000
01000010000000007776777600100100777777760066767776776000777777760066767700100100600000008888888888888888bbbbbbbbbbbbbbbb00000000
01566510000000007777677777776777777776777777677700000000000000007717617700000000000000000000000000000000000000000000000000055000
011c5110110110117766767776777777767766777677777700000300000003007116515700199100000000000000000000000000007777000005560000500050
0000000051000015676677776777666767776677677776660000030003000300616115170099a900000000000005500000677000077777700000056050000050
010000106000005677677777777776677777777777777667030000000300000076582167019a991000000800005d850006777700077777700650005000500500
01000010600000c677777777766777777767776776677777030000000000000076128567019aa910000556000056650000777700077777700650005550000000
0000000051000015677766776667767767667677766677770000003000080000615116170199a9100066666000066000006776000a7777a00065000500000050
01000010110110117777667777777777776677777777777700000030000300007515611719aa9a9100000000000000000000600000aaaa000006650000005000
01000010000000007777767677767776777777767776777600000000000000007716717601011010000000000000000000000000000000000000000055500000
0010010001555510005c750000100100001001000100010100100010000000000000000000000000000000000300030300000000000000000000000000000000
01011010500000050c00c0100101101001011010100110100101c00100000000000000000000000003bbbb303003303000000000000000000000000000000000
00000000050550500000000050c00005000bb00000100101011c1100000000000000000000c0ccc0d000000d0030030300000000000000000000000000000000
010000100000000001000010700000cc01b11b10010010101c011010005585000055b500001c1110003bb3000300303000000000000000000000000000000000
011111100000000001000c10c700000c01b33b1010010010001101c10000000000000000001111100d0000d03003003000000000000000000000000000000000
0000000000000000000c000050000005003bb300001001001100cc010055b5000055b50000ccccc0000bb0000030030000000000000000000000000000000000
01000010000000000107101001011c100103301001001001011c0110005555000055550000000000010110100300300300000000000000000000000000000000
0011110005555550005cc50000100100001001001001001010101000000000000000000000000000001001003003003000000000000000000000000000000000
00000000000000000000000000000000000001008000000008000000000000000000000000000000000000000000000000000000000000000000000000000000
00555500000000000005555005555000000555100e055500000e0800000000000022220000000000000000000000000000000000000000000000000000000000
05555500005555000055555055555000005855508883115000808e80000000000222220000000000000000000000000000000000000000000000000000000000
05f3f30005555500005f3f305f3f3000003f3f500e8ef350100388550000000002f8f80000000000000000000000000000000000000000000000000000000000
05ffff0005f3f300000ffff00fff55600888fff01888f550108e8f55000388e502ffff0000000000000000000000000000000000000000000000000000000000
00111000001fff0000f11f000111f5000081110005811080051ff35580e883880033000000000000000000000000000000000000000000000000000000000000
0f555f0000111f0000155000055500000f0551008058000805111e801188ff850f66f00000000000000000000000000000000000000000000000000000000000
0010100000f110000000010001010000000001000011000000f110e811f885500010100000000000000000000000000000000000000000000000000000000000
00000000000000000000000000006000007060007800000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00555000000000000055500000055500070555000555500000555000000555500000000000000000000000000000000000000000000000000000000000000000
05555500000555000555550000555550705555505555507005555570070555550000000000000000000000000000000000000000000000000000000000000000
05555500005555500555550000555550705555505f3f3007053f35077003f3f50000000000000000000000000000000000000000000000000000000000000000
00fff000005555500ffff00000f555f000f555000ffff00705fff107700ffff00000000000000000000000000000000000000000000000000000000000000000
001110000001110000511000001111f0001111f001111f55011ff66055f111100000000000000000000000000000000000000000000000000000000000000000
0f555f00000555f00015500000055500000555000555000000555000000055500000000000000000000000000000000000000000000000000000000000000000
0010100000f1110000100f0000010100000101000101000000101000000010100000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0055550000000000005555000055500000a90a0000a09a0000000000000000000000000000000000000000000000000000000000000000000000000000000000
05555550005555000555555005555500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
05f3f3500555555005f3f350053f3500000f3550000f355000000000000000000000000000000000000000000000000000000000000000000000000000000000
00ffff0005f3f3500fffff00056ff10000fff55000fff55000555500000000000000000000000000000000000000000000000000000000000000000000000000
00111000001fff000011110000f11100051f3550051f3550055f550f00000f000000000000000000000000000000000000000000000000000000000000000000
0f555f0000111f00001550f000555000151ff550151ff55005f5f305000005000000000000000000000000000000000000000000000000000000000000000000
0010100000f51000001000000010100011f0550011f0550005f5ff05000005000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00555500000000000555500000055550000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00555550005555000555550000055555000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
003f3f500055555003f3f5000003f3f5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00ffff00003f3f500ffff0000655fff0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0001110000fff10000f11f00005f1110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00f555f000f111000005510000005550000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0001010000011f000010000000001010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__label__
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005
50666666666666666660000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005
50622222222222222260000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005
50622222222222222260000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005
50622222222222222260000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005
50627222777277727770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005
50667666676676667660000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005
50007000070077007700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005
50007000070070007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005
50007770777070007770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005
50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005
50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005
50666666666666666660000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005
50611111111111111160000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005
50611111111111111160000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005
50611111111111111160000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005
50611771777111111160000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005
50667676667666666660000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005
50007070777000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005
50007070700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005
50007700777000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005
50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005
50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005
50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005
50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005
50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005
50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005
50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005
50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005
50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005
50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005
50000100000001000000010000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005
50000001000000010000000100000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005
50001110101011101010111010101110101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005
50000101000001010000010100000101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005
50000001011000010110000101100001011000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005
50000001100000011000000110000001100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005
50000010001000100010001000100010001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005
50000000001100000011000000110000001100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005
50000010001000100010001000100010001001000000010000000000000000000000000000000000000000000000000000000000000000000000000000000005
50000101c0010101c0010101c0010101c00100010000000100000000000000000000000000000000000000000000000000000000000000000000000000000005
5010011c1100011c1100011c1100011c110011101010111010100000000000000000000000000000000000000000000000000000000000000000000000000005
50001c0110101c0110101c0110101c01101001010000010100000000000000000000000000000000000000000000000000000000000000000000000000000005
5110001101c1001101c1001101c1001101c100010110000101100000000000000000000000000000000000000000000000000000000000000000000000000005
50001100cc011100cc011100cc011100cc0100011000000110000000000000000000000000000000000000000000000000000000000000000000000000000005
5010011c0110011c0110011c0110011c011000100010001000100000000000000000000000000000000000000000000000000000000000000000000000000005
50111010100010101000101010001010100000000011000000110000000000000000000000000000000000000000000000000000000000000000000000000005
50100100100000100100001001000010001001011000001000100100000001000000010000000100000001000000010000000100000001000000000000000005
50011011010001011010010110100101c001115111500101c0010001000000010000000100000001000000010000000100000001000000010000000000000005
5100101666555566665556661010011c110011555611011c11001110101011101010111010101110101011101010111010101110101011101010000000000005
50101016051051515051150610101c011010055665511c0110100101000001010000010100000101000001010000010100000101000001010000000000000005
51c1010605005050505005060100001101c115156551001101c10001011000010110000101100001011000010110000101100001011000010110000000000005
5c011016101001010100101610101100cc01151551511100cc010001100000011000000110000001100000011000000110000001100000011000000000000005
5110001601010000000001061001011c011011565510011c01100010001000100010001000100010001000100010001000100010001000100010000000000005
50000105100000000000001501001010100005155010101010000000001100000011000000110000001100000011000000110000001100000011000000000005
50000011110000100100001501000010001000100010001000100010001000100010001000100010001000100010001000100010001000000000000000000005
50000115511001011010010510100101c0010101c00101012202220222022201c0012202c202220222010101c0010101c0010101c00100111111111111111115
5010015661100000000001061011011c1100011c11000118818882888288811c11088282828881888200011c1100011c1100011c110001566555555515555555
50000156651001000010110610101c0110101c0110101c821082828882822c011082828282822c8280101c0110101c0110101c01101001656666666665666665
5110015565100100001001160100001101c1001101c100820288828282880011018282828288008802c1001101c1001101c1001101c101666666665666666655
50000156651000000000111610111100cc011100cc0111828282828282822200cc8281888c82228282012100cc011100cc011100cc0101566551515555555155
5010011665100101101001051010011c0110011c011001888180818c8188811c018801180188818c8118011c0110011c0110011c011001566111111111111115
50110156651000100100001501011010100010101000101010001010100010101000101010001010100010101000101010001010100001566510000000000005
50000156651000100100011565100000000000100100011c11c00010001000100010010010000010010000100100001001000010010001566510010001010105
50000156651001011010001551001515510001011010110101010101c0010101c001101101000101101001011010010110100101101001566510100110101005
5000015661100000000000061000566666105566665550160010011c1100011c1100101666555566665555666655556666555566665501566110001001010015
500001566510010000100056610066816661515150516611500c1c0110101c011010101605105151505151515051515150515151505101566510010010100105
5000015565100100001001156510611016615050505065661101001101c1001101c1010605005050505050505050505050505050505001556510100100101005
50000156651000000000001555106100156101010100155565101100cc011100cc01101610100101010001010100010101000101010001566510001001000015
5000011665100101101000116100665556100000000011156511011c0110011c0110001601010000000000000000000000000000000001166510010010010105
50000156651000100100015665000166610000000000015665101010100010101000010510000000000000000000000000000000000001566510100100101005
50000156651001555510015665100010010000100100015665100010001000100010001501000010010000100100001001000010010001566510010001010115
50000156651050000005015665100101101001011010015665100101c0010101c001010510100dccccd0010110100101101001011010011851101001101003b5
5000015661100505505001566110000000000000000001566110011c1100011c110001061011d000000d00000000000000000000000000000000001001013335
50000156651000000000015665100100001001000010015665101c0110101c0110101106101001dccd1001000010010000100100001001000010010010100105
5000015565100000000001556510555055500550555055555550555155510011555155565550055005500100555001005050010000100100001010010010bbb5
5000015665100000000001566517775777007707770777577757770777511107775777577711770c770000077750050757500000000000000000001001003335
5000011665100000000001166517570755175551751757575710751c075001175757570755175557555001011710755717100101101001000010010010010105
500001566510055555500156651770577107775075077757755075107700101777077057710777577750001071077710715000100100010000101001001013b5
50000156651000100100015665175757555057107507575757507500050000075007575755505710570001575550700757500000000000000000010001010105
5111111665100101101001566517070777177dcc7cd7071767117111711111171117171777177107701011177711111717111111111111111100100110101005
555515566510000000000156611000000000d000000d015665515156655555551555155665510000000015566551555515555555155555566510001001010015
55666666661001000010015665100100001001dccd10016666666566566666666566666666660100001066666666666665666666656666665610010010100105
5666666656100100001001556510010000100d0000d0016566656666666666566666656566650100001065656665665666666656666666666610100100101005
555555566510000000000156651000000000000cc000015665511556655551555555555665510000000055566551515555555155555515566510001001000015
51111111110001011010011665100101101001011010001665111156551111111111115665110101101011566511111111111111111111166510010010010105
50000000000000100100015665100010010000100100001561000156611000000000000561000010010000056100000000000000000001566510100100101005
51000010010000100100001665100010010000100100015665100156610000100100005c75000010010000100100001001000010010000166510000000000005
5010010110100102222000166511010110100101101001566111115561000dddd0100107c0100101101001011010010110100101101000166511111111111115
500000000000002222200156655155666655000000000156655115566510ddddd000000cc0000000000000000000000000000000000001566551555515555555
501001000010012f3f300166666651515051010000100166666666666610df3f3010010cc0100100001001000010010000100100001001666666666665666665
501001000010010ffff001656665505050500100001001656666566656100fffdd60010cc0100100001001000010010000100100001001656665665666666655
50000000000000f11f0001566551010101000000000001566555155665100111fd00000c70000000000000000000000000000000000001566551515555555155
5010010110100112201000166511000000000101101000111111115661000ddd10100107c0100101101001011010010110100101101000166511111111111115
51000010010000100100001561000000000000100100000000000016610001110100005cc5000010010000100100001001000010010000156100000000000005
50000000000000100100015665100010010000100100001001000016651000100100015665100010010001566510000000000000000001166510000000000005
51111111111001011010111665110222201001011010010110100016651101011010111665110101101011166511111111111101101111556511111111000005
55555155551155666655155665510222220000000000000000000156655155666655155665515566665515566551555515555100001555566551555665100005
556666656651515150516666666603f3f21001000010010000100166666651515051666666665151505166666666666665666000005666666666666656100005
56666666665150505050656566650ffff01001000010010000100165666550505050656566655050505065656665665666666000002666656665666666100005
555555555111010101005556655100f11f0000000000000000000156655101010100555665510101010055566551515555555100001555566555155665100005
51111111111000000000115665110102211001011010010110100016651100000000115665110000000011566511111111111101101111111111111665100005
50000000000000000000000561000010010000100100001001000015610000000000000561000000000000056100000000000000000000000000015665100005
510000100100001001000016651000100100001001000010010001566100001001000010010000100100005c7500001001000010010000100100015665100005
5010010110100101101000166511010110100101101001011010115561000101101001011010010110100107c010010110100101101001022220011251100005
500000000000000000000156655155666655000000005566665515566510000000000000000000000000000cc000000000000000000000222220000250000005
501001000010010000100166666651515051010000105151505166666610010000100100001001000010010cc0100100001001000010012f3f30010250100005
501001000010010388ed0165666550505050011111105050505056665610010000100100001001000010010cc0100100001001000010010ffff0010250100005
50000000000080e883880156655101010100000000000101010015566510000000000000000000000000000c7000000000000000000000f11f00000250000005
5010010110101188ff8d00166511000000000100001000000000115661000101101001011010010110100107c010010110100101101001122010011251100005
51000010010011f88dd00015610000000000001111000000000000166100001001000010010000100100005cc500001001000010010000100100015665100005
50000010010000100100015665100010010000100100001001000015010000100100001111000010010000166510001001000000000000000000015661000005
51111101101101011010111665100101101001011010010110100105101001011010011551100101101000166511010110101111111111111111115561000005
5555510000155000000515566510000000000000000000000000010610110000000001566110000bb00001566551000000005156655555551555155665100005
5666655555567cccc7cc6666661001000010010000100100001011061010010000100156651001b11b1001666666010000106566566666666566666666100005
566669999996c7cccc7c6666561001000010010000100100001001160100010000100155651001b33b1001656665011111106666666666566666566656100005
5555510000155000000555566510000000000000000000000000111610110000000001566510003bb30001566551000000001556655551555555155665100005
5511110110110101101011111100010110100101101001011010010510100101101001166510010330100016651101000010115655111111111111bbbbbbbb05
5110001001000010010000000000001001000010010000100100001501010010010001566510001001000015610000111100015661100000000000b333333b05
5510001001000010010000100100001001000010010000100100001001000010010001566510001001000156651000100100005c75000010010001b33bbb3b05
55100101101001011010010110100101101001011010010110100dccccd001011010011251100101101001125110010110100107c010010dddd001b3bbbb3b05
511000000000000bb00000000000000000000000000000000000d000000d0000000000025000015555100000000000000000000cc000000ddddd01b3b3333b05
55100100001001b11b100100001001000010010000100100001001dccd10010000100102501003b11b300100001001000010010cc0100103f3fd01b33bbb3b05
55100100001001b33b10011111100100001001111110010000100d0000d0011111100102501003b11b300100001001000010010cc01006ddfff001b333333b05
551000000000003bb30000000000000000000000000000000000000cc0000000000000025000015555100000000000000000000c700000df111001bbbbbbbb05
55100101101001033010010000100101101001000010010110100101101001000010011251100101101001000010010110100107c0100101ddd0011665100005
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555

__map__
ffffffffff00ff00000000000000000000000000000000000000000000000000000000000000ff0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
ffffffffff00ff00000000000000000000000000000000000000000000000000000000000000ff0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000005465544154546500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000ff656554b6b5b550b0b5b564000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00007501b654b6b58471b554b554000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000ff65b6b6b654b0b5b054845400000000000000000000000000000000000000ffffff0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000064545464655454c0b5b5650000000000000000000000000000000000ffffffffff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000ff406174e0544542b070546400000000000000000000000000000000ffffffffff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000ff50b5b5b5b5c077b577f065ffffffffffffffffff645464ffff0000ffffffffff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000ff508670b570b571b55065ffff546464655476656454b95464ff0000ffffffffff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000405244514673b5b5b550ffff6470b5765454b570c0b5b5f054650000ffffffffff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000050b5b571b463464646730064c077b5b5f0b5b550b05454b047b65400ff0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000006042b0b58071c0b5b56041614562b56454548643c0b5b5f070b65400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000606142b5b5b5b9b5b068b584b5b554c0b540524161694148b65465000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000606142b5b5f040526174464657b5b547e047b5b550b6b66465640000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000006041784173000054b6b647465460785242b550b6b6b6b640616142ff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000054d0640000ffff54b6478054b5b5b5508454464646465087bb50ff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000ff54000000ffffff6450b055b5b0b543865084b5b5b5a0bbbb50ff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000004061416162b550b5b5f0634651b051616161616162ff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000050b547c0b5b56042b04673c077b5b5b5b563ffffffff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000050b463616146c077b5b463465146516182524200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000050b5478485e0406246b073b5b5b577f0b5b54300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000060615241697862c0b5b547b5708463b0416173ff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000ff00ff50b5b4b0b5b0b584b0438681b577f050ff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000ff60417842b5b5b54078516151b0516162ff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000050d06342b04062b5b5c077b550ff0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000060615273b94386b553b5438650ff0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000063615242f0b5b5636162000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000060616161620000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000ffffffff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000bfffffffffffffffffff00000000000000bf0000000000000000000000006061526152616200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
000802021675016750177501675015750147501575015750137501475015750167501775017750177501775017750177501775017750167501575016750177501875018750187501875018750187501875018750
001000001a752000001a750000001a752000001a750000001a752000001a750000001a752000001a7520000019752000001975200000197520000019750000001575000000157500000015750000001575000000
011000001675000000167500000016750000001675000000167500000016750000001675000000167500000018750000001875000000187500000018750000001575000000157500000015750000001575000000
011000000e7500e7500e7500e7500000016750000001575013750117501075011750137500e750000000d7500d750000000e7500e75010750107500e7500e750000000d7500d7500000000000000000000000000
00120000136400b620046100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000800000f040110300e020110100217001170011500115002100215001d50035600366003760037600386003860038600376003560034600326002f6002b60000000236001d6001760014600106000000000000
00100000270402e0303b7000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00050000376403c65037660336602f6502b640246301e630126200e6100a610086100c60005600206000c600046001f6001660010600000000000000000000000000000000000000000000000000000000000000
000a00000114001060010000b600056000b60011f0011f0011f0011f0011f0011f0011f0011f0011f0011f0011f00000000000000000000000000000000000000000000000000000000000000000000000000000
00060000097201d0000c0000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00040000147401e7401e7301e7201e7101e7001f7001f700207001e70000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000800000a1100b1200b1200110001100077000550005500045000350002500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000800001a730167401a7000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000c00000711006110071100611000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0008000025730277402c7503173031710000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000800002151024520265302652000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00080000267300a7102d7202d7200a710000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000800000d740017200d7400d74001720000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0008000027550295502b5502e55032550335503254033530325203351000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__music__
00 01024344
