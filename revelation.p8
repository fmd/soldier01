pico-8 cartridge // http://www.pico-8.com
version 16
__lua__
-- --- iffy/general todo --- --
-- todo: introduce blood footprint mechanic with some levels
-- todo: finish c4 placement
-- --- refactor todo --- --
-- todo: convert coord system to strings
-- todo: convert animation data to strings
-- todo: refactor entire input system
-- todo: refactor c4 timer

-- debug values to reset on release
game_speed = 2
starting_level = 9
inventory = { socom = 4,
              c4 = 2 }
inventory_max = { socom = 4,
                  c4 = 2 }
equipped = "c4"

-- load the sprites and that
sprites = { player = {{17,18,19,18,21,22,23,20}, -- north (last three=roll/shoot/fly)
                      {1,2,3,2,5,6,7,4},        -- east (last three=roll/shoot/fly)
                      {33,34,35,34,37,38,39,36}, -- south (last three=roll/shoot/fly)
                      {49,50,51,50,53,54,55,52}, -- west (last three=roll/shoot/fly)
                      {8,9,10,11}, -- death
                      {25, 24}}, -- laser
            enemy1 = {{208,209,210,209,210,211,211}, -- north (last two=roll/shoot)
                      {192,193,194,193,194,195,195}, -- east (last two=roll/shoot)
                      {224,225,226,225,226,227,227}, -- south (last two=roll/shoot)
                      {240,241,242,241,242,243,243}, -- west (last two=roll/shoot)
                      {196,197,198,199}, -- death
                      {41, 40}, -- laser
                      {228, 229}, -- stunned
                      {212, 213, 214, 215}}, -- attack
            objects = {blood_prints = {26, 27, 28, 29},
                       snow_prints = {162, 163, 164, 165},
                       scanner = {131, 134},
                       multilock = {136, 137, 138},
                       multidoor = {{88, 144}, {89, 145}},
                       door = {{67, 129}, {68, 130}},
                       goal = {135},
                       relay = {132}},
            items   = {socom = 133,
                       c4 = 133},
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
levels = {{53,13,11,12}, {33,22,14,10}, {19,23,6,9}, {40,11,13,11}, {3, 25, 13, 7}, {3, 20, 9, 5}, {28,13,13,9}, {0,10,13,9}, {13,9,12,12}, {11,0,9,6}, {20,0,6,8}, {0,0,11,10}, {26,0,22,16}} -- xstart, ystart, w, h
level_items = {{}, {}, {}, {}, {}, {}, {}, {}, {}, {"socom"}, {}, {"c4"}, {}}
level_enemy_variants = {{1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,3,3,3,3,3}, {2,2,2,2,2,2,2,2}, {2,1}, {1,2,1,1,2}, {2,2,1,2,1}, {1,1}, {2,2,2,2}, {1,2,1}, {2,1,2}, {2,2}, {2,2}, {1,1,1,1,2}, {2,2,2,2,2,2,2,2,2,2,2,2,2}}

-- map runthrough replacements (sprite #, pattern, facing dir)
-- note: facing dir for doors and other items with only 2 dirs is [0/1] rather than [0/1/2/3]
map_replace = {{67,  "door", 0}, -- closed regular door
               {68,  "door", 1}, 
               {88,  "multidoor", 0}, -- closed multilock door
               {89,  "multidoor", 1}, 
               {1,   "player",  1}, -- player
               {17,  "player", 0},
               {33,  "player", 2},
               {49,  "player", 3},
               {192, "enemy1", 1}, -- enemy1
               {208, "enemy1", 0},
               {224, "enemy1", 2},
               {240, "enemy1", 3},
               {131, "scanner", false}, -- sprite #, pattern, player_allowed (scanner)
               {134, "scanner", true},  -- sprite #, pattern, player_allowed (scanner)
               {136, "multilock", false}, -- sprite #, pattern, player_allowed (multilock)
               {138, "multilock", true}, -- sprite #, pattern, player_allowed (multilock)
               {132, "relay"}, -- relays have no extra attribs yet
               {135, "goal"},  -- goals have no extra attribs yet
               {133, "item"}} -- the item type is taken from the level_items variable

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
  z_down = 0
  x_down = 0  
end

function init_level_from_map(lv)  
  actor_count = 0
  enemy_count = 0
  item_count = 0

  if (inventory["socom"] > -1) inventory["socom"] = 4
  if (inventory["c4"] > -1) inventory["c4"] = 2  

  multilocks = {}
  multidoors = {}
  actors = {}
  scanners = {}
  relays = {}
  doors = {}
  goals = {}
  items = {}
  prints = {}
  c4s = {}
  explosions = {}
  fires = {}

  for y = 0, levels[lv][4] - 1, 1 do
    for x = 0, levels[lv][3] - 1, 1 do
      for m in all(map_replace) do
        if (lmapget(x,y) == m[1]) then
          mset(x + levels[lv][1], y + levels[lv][2], 128) -- 128 is empty tile
          add(mset_restore, {x = x, y = y, t = m[1]})
          if (m[2] == "door") add_door(m, x, y)
          if (m[2] == "multidoor") add_multidoor(m, x, y)
          if (m[2] == "enemy1") add_enemy1(m, x, y)
          if (m[2] == "player") add_player(m, x, y)
          if (m[2] == "scanner") add_scanner(m, x, y)
          if (m[2] == "relay") add_relay(m, x, y)
          if (m[2] == "goal") add_goal(m, x, y)
          if (m[2] == "item") add_item(m, x, y)
          if (m[2] == "multilock") add_multilock(m, x, y)
        end
      end
    end
  end
end

function add_multidoor(m, x, y)
  add(multidoors, {pattern = "multidoor", facing = m[3], open = 0, pos = {x = x, y = y}})
end

function add_multilock(m, x, y)
  add(multilocks, {pattern = "multilock", pos = {x = x, y = y}, active = false, player_allowed = m[3]})
end

function add_item(m, x, y)
  item_count += 1
  add(items, {pattern = level_items[level][item_count], pos = {x = x, y = y}})
end

function add_goal(m, x, y)
  add(goals, {pattern = "goal", pos = {x = x, y = y}})
end

function add_relay(m, x, y)
  add(relays, {pattern = "relay", pos = {x = x, y = y}})
end

function add_scanner(m, x, y)
  add(scanners, {pattern = "scanner", pos = {x = x, y = y}, player_allowed = m[3]})
end

function add_door(m, x, y)
  add(doors, {pattern = "door", facing = m[3], open = 0, open_turns = 0, pos = {x = x, y = y}})
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
       death_frames = 0,
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
       life = 12, 
       max_life = 12, 
       death_frames = 0, 
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
  idle_start = time()
end

function input_direction()
  d = -1
  if (btn(0)) d = 3
  if (btn(1)) d = 1
  if (btn(2)) d = 0
  if (btn(3)) d = 2
  return d
end

function input_action()
  a = player_action.a
  if (btn(4)) then
    if (z_down == 0) a = bxor(a,0x01)
    z_down = 1
  else
    z_down = 0
  end
  if (btn(5)) then
    if (x_down == 0) a = bxor(a,0x10)
    x_down = 1
  else
    x_down = 0
  end
  return a
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
    if ((o.pattern == "blood_prints" or o.pattern == "snow_prints") and o.pos.x == actor.pos.x and o.pos.y == actor.pos.y) then
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
    while (apos.x == actor.pos.x and apos.y == actor.pos.y) do      
      actor.facing += 1
      if (actor.facing > 3) actor.facing = 4 - actor.facing
      actor.act.d = actor.facing
      apos = act_pos(actor)
      directions_tried += 1
      if (directions_tried > 4) actor.stunned_turns = 3; return
    end
  end

  if (mt == "line") then
    if (apos.x == actor.pos.x and apos.y == actor.pos.y) do
      actor.facing += 2
      if (actor.facing > 3) actor.facing = abs(4 - actor.facing)
      actor.act.d = actor.facing
    end
  end

  if (mt == "still") then
    actor.act.d = -1
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
    tiles = collect_tile_line(actor, actor.act.d, false)
    if (is_empty(tiles) or movement_type == "still") then      
      -- if we can go nowhere, invoke variant-based ai pattern
      do_enemy1_variant_movement_ai(actor, apos, movement_type)
    end
  end

  found_player = false
  -- with old facing, look for player to shoot
  tiles = collect_tile_line(actor, prev_facing, false)
  if (not is_empty(tiles)) then
    for k, tile in pairs(tiles) do
      if (player.pos.x == tile.x and player.pos.y == tile.y) then
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
        if (player.pos.x == tile.x and player.pos.y == tile.y) actor.act.a = 0x01
      end
    end
  end
end

function do_avoidance(actor)
  if (actor.life <= 0) return
  -- if we are moving into a tile that someone else plans on moving into, only one should move there.
  new_actor_pos = act_pos(actor)
  -- if we arent moving, no need to avoid
  if (new_actor_pos.x == actor.pos.x and new_actor_pos.y == actor.pos.y) then
    return
  end
  
  for a in all(actors) do
    if (a.life > 0) then
      apos = act_pos(a)
      
      -- todo: some enemy_variants should also dodge the player, so remove last clause for other ais
      if (a.id != actor.id and apos.x == new_actor_pos.x and apos.y == new_actor_pos.y and a.pattern != "player") then
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
    if (actor.act.d > -1) actor.facing = actor.act.d    
    pickup_prints(actor)
    if (actor.blood_prints >= 1) place_new_prints(actor, "blood_prints")
    if (is_snow(actor.pos)) place_new_prints(actor, "snow_prints")
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
    if (actor != player) then
      if (actor.blast_pos == nil) then 
        if (actor.blood_prints >= 1) redirect_existing_prints(actor, "blood_prints"); actor.blood_prints -= 1
        if (is_snow(actor.pos)) redirect_existing_prints(actor, "snow_prints")
      end
      perform_move(actor)
    end
  end
  if (player.blast_pos == nil) then 
    if (player.blood_prints >= 1) redirect_existing_prints(player, "blood_prints"); player.blood_prints -= 1
    if (is_snow(player.pos)) redirect_existing_prints(player, "snow_prints")
  end
  
  perform_move(player)

  -- perform the acts
  for actor in all(actors) do
    if (actor.blast_pos == nil) then
      perform_act(actor)      
    end
    
    actor.act = {a = 0x00, d = -1}
    --actor.blast_pos = nil
  end
end

function to_pos(dr)
  return { x = pos_map[1][dr + 1],
           y = pos_map[2][dr + 1] }
end

function act_pos(actor)
  if (actor.blast_pos != nil) return actor.blast_pos
  -- todo: different acts have different movements
  actor_point = {x = actor.pos.x, y = actor.pos.y}
  if (actor.act.d < 0) return actor_point
  
  act_dir = to_pos(actor.act.d)
  test_point = {x = actor.pos.x + act_dir.x, y = actor.pos.y + act_dir.y}
  if (is_wall(test_point)) return actor_point

  -- todo: other future moves may do not move the player. consider refactoring all actions.
  if (actor.act.a != 0x00) return actor_point
  return test_point
end

function lmapget(x, y)
 return mget(x + levels[level][1], y + levels[level][2])
end

function is_door_wall(ds, pos)
  for o in all(ds) do 
    if (o.pos.x == pos.x and o.pos.y == pos.y) then
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
  return is_door_wall(doors, pos) or is_door_wall(multidoors, pos) or (m >= 64 and m <= 127)
end

function is_glass(pos)
  m = lmapget(pos.x, pos.y)
  return (m == 119 or m == 120)
end

function open_doors_near(scans)
  for s in all(scans) do
    for d in all(doors) do
      if ((d.pos.x == s.pos.x + 1 and d.pos.y == s.pos.y) or
          (d.pos.x == s.pos.x - 1 and d.pos.y == s.pos.y) or
          (d.pos.x == s.pos.x and d.pos.y == s.pos.y + 1) or
          (d.pos.x == s.pos.x and d.pos.y == s.pos.y - 1)) then
        d.open = 1
        d.open_turns = 5
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

function close_multilock_doors()
  for l in all(multilocks) do
    if (not l.active) then
      for d in all(multidoors) do
        d.open = 0
      end
      return
    end
  end
end

function tick_closing_doors()
  for d in all(doors) do
    if (d.open_turns > 0) then
      d.open_turns -= 1
    else
      in_space = false
      for a in all(actors) do
        apos = act_pos(a)
        if (apos.x == d.x and apos.y == d.y) in_space = true
      end
      
      if (not in_space) d.open = 0
    end
  end
end

function active_buttons(bts)
  rets = {}
  
  for o in all(bts) do
    if (o.pattern == "scanner" or o.pattern == "multilock") then
      for a in all(actors) do
        if (a.pattern != "player" or o.player_allowed) then
          if (a.pos.x == o.pos.x and a.pos.y == o.pos.y and a.life > 0) add(rets, o)
        end
      end
    end
  end

  return rets
end

function is_scanner_active(scan)
  for a in all(actors) do
    if (a.pattern != "player" or scan.player_allowed) then
      if (a.pos.x == scan.pos.x and a.pos.y == scan.pos.y) return true
    end
  end

  return false
end

function redirect_existing_prints(actor, pat)
  if (actor.life <= 0) return

  p = print_on_tile(actor)
  if (p and actor.act.d != -1 and p.pattern == pat) p.facing = actor.act.d
end

function place_new_prints(actor, pat)
  if (actor.life <= 0) return

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
    if (a.life <= 0 and actor.life > 0 and a.pos.x == actor.pos.x and a.pos.y == actor.pos.y) then
      actor.blood_prints = 5
    end
  end
end

function has_live_actor(np, exclude_pattern)
  for a in all(actors) do
    if (a.life > 0) then
      if (a.pattern != exclude_pattern and a.pos.x == np.x and a.pos.y == np.y) then
        return a
      end
    end
  end
  return false
end

-- todo: make exclude_pattern better
function will_have_actor(np, exclude_pattern)  
  for a in all(actors) do
    apos = act_pos(a)
    if (a.life > 0) then
      if (a.pattern != exclude_pattern and apos.x == np.x and apos.y == np.y) then
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
  if (actor.pattern == "player") attempt_melee(actor)
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

function hurt_actor(actor, amount)
  if (actor.life > 0) actor.life -= amount
  if (actor.life < 0) actor.life = 0
  if (actor.life == 0) then 
    actor.life = -1
    actor.death_frames = 4
  else
    actor.hurt_frames = 2
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
  ts = collect_tile_line(a, d, false)
  blast_to = ts[#ts]
  for t in all(ts) do
    for k, aa in pairs(actors) do
      if (aa.id != a.id and aa.pos.x == t.x and aa.pos.y == t.y and aa.life > 0) then
        stun_actor(aa, 2)
        p = to_pos(d)
        a.blast_pos = { x = aa.pos.x - p.x, y = aa.pos.y - p.y}
        return
      end
    end
  end

  a.blast_pos = blast_to
end

function blow_c4(c, wait)
  for t in all(cross_tiles(c.pos)) do
    add(explosions, {frames = 4, pos = {x = t.x, y = t.y}})

    for a in all(actors) do
      if (a.pos.x == t.x and a.pos.y == t.y) then
        hurt_actor(a, 3)
        blast_actor(a, t.d)
      end
    end

    nt = lmapget(t.x, t.y) 
    
    if (nt == 69 or nt == 85) then -- broken walls
      mset(t.x + levels[level][1], t.y + levels[level][2], 128)
      add(mset_restore, {x = t.x, y = t.y, t = nt})
    end
  end

  del(c4s, c)
end

function attempt_c4(actor)
  if (actor.act.d == -1) then -- if there's no direction, blow up existing c4
    for c in all(c4s_for(actor)) do
      if (c.timer == -1) c.timer = 0
    end
  else -- if we're placing a c4, cool
    if (inventory["c4"] <= 0) return
    d = to_pos(actor.act.d)
    add(c4s, {owner = actor, timer = -1, pattern = "c4", pos = {x = actor.pos.x + d.x, y = actor.pos.y + d.y}})
    inventory["c4"] -= 1
  end
end

function attempt_shot(actor)
  if (actor.id == player.id and player.act.d == -1) player.act.d = player.facing
  for i, tile in pairs(collect_tile_line(actor, actor.act.d, true)) do
    hurts = {}
    
    for j, a in pairs(actors) do
      if (actor != a and (a.pos.x == tile.x and a.pos.y == tile.y) and a.life > 0) then 
        add(hurts, a)
      end
    end

    l = #hurts
    for a in all(hurts) do
      if (l > 1) then
        if (a != player and a.life > 0) then
          hurt_actor(a, 1)
          return
        end
      else
        if (l == 1) then
          hurt_actor(a, 1)
          return
        end
      end
    end
  end
end

function perform_move(actor)
  if (actor.act.a == 0x00 or (actor.id == player.id and equipped == "hands")) attempt_move(actor)
end

function perform_act(actor)
  if (actor.act.a == 0x01) then
    if (actor.id == player.id) then
      if (equipped != "hands") then
        attempt_action(actor)
      end
    else
      attempt_shot(actor)
    end
  end
end

function check_goals()
  for g in all(goals) do
    for a in all(actors) do
      if (a.pos.x == g.pos.x and a.pos.y == g.pos.y and a.life > 0 and a.pattern == "player") then
        load_level(level + 1)
        return true
      end
    end
  end

  return false
end

function roll_frame() 
  for actor in all(actors) do
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
  
  if (frame != last_frame) then
    roll_frame()
  end
  last_frame = frame
end

function start_turn()
  if (player_action.a == 0x11 or player.life <= 0) then
    load_level(level)
    return
  end

  turn += 1

  idle_start = nil
  turn_start = time()
  update_frame(turn_start)

  for c in all(c4s) do
    if (c.timer == 0) blow_c4(c)
    if (c.timer > 0) c.timer -= 1
  end
  
  start_actors_turns()
end

function end_turn()
  end_actors_turns()
  tick_closing_doors()
  open_doors_near(active_buttons(scanners))
  switch_multilocks(active_buttons(multilocks))
  open_multilock_doors()
  close_multilock_doors()
  pick_up_items()
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
  player_action = {a = 0x00, d = -1}
  if (equipped == "c4" and inventory["socom"] > -1) equipped = "socom"; return
  if (equipped == "socom" and inventory["c4"] > -1) equipped = "c4"; return
end

function update_turn()
  update_frame(turn_start)
  if (chunk >= 100) end_turn()
end

function update_idle()
  update_frame(idle_start) 
  if (chunk >= 100) idle_start = time()
end

function _update()
  if (turn_start == nil) player_action.a = input_action()
  d = input_direction()
  if (d > -1) player_action.d = d
  if (turn_start != nil) update_turn(); return
  if ((player_action.d > -1 and d == -1 and player_action.a != 0x10)
    or (not btn(4) and player_action.a == 0x01)
    or (not (btn(4) or btn(5)) and player_action.a == 0x11)) then
    start_turn(); return
  end

  if (player_action.a == 0x10 and not btn(5)) then
    attempt_swap()
  end
  
  update_idle()
end

function pick_up_items()
  for i in all(items) do
    if (player.pos.x == i.pos.x and player.pos.y == i.pos.y) then
      inventory[i.pattern] = inventory_max[i.pattern]
      equipped = i.pattern
      del(items, i)
    end
  end
end

function pos_equal(pos1, pos2)
 return (pos1.x == pos2.x and pos1.y == pos2.y)
end

function tile_shift(actor)
  apos = act_pos(actor)
  if (not pos_equal(apos, actor.pos)) return {x=((apos.x - actor.pos.x) * frame * 2), y=((apos.y - actor.pos.y) * frame * 2)}
  return {x=0, y=0}
end

function sprite_for(actor)
  if (actor.life <= 0) then
    if (actor.death_frames > 0) then
      return sprites[actor.pattern][5][(4 - actor.death_frames) + 1]
    end
    
    return sprites[actor.pattern][5][4]
  end

  if (actor.blast_pos != nil) then
    return sprites[actor.pattern][actor.facing + 1][8]
  end

  if (actor.hurt_frames > 0) then
    return sprites[actor.pattern][5][(2 - actor.hurt_frames) + 1]
  end

  if (actor.stunned_turns > 0) then
    return sprites[actor.pattern][7][(frame % 2) + 1]
  end


  if (actor.attack_frames > 0) then    
    return sprites[actor.pattern][6][actor.facing + 1]
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
      tiles = collect_tile_line(actor, d, true)
      for tile in all(tiles) do
        if (actor != player or inventory["socom"] > -1 and equipped == "socom") spr(sprites[actor.pattern][6][actor.act.d % 2 + 1], tile.x*8, tile.y*8)
      end
      -- if (actor == player and equipped == "socom" and inventory["socom"] > 1) then
      --   spr(46, tiles[1].x*8, tiles[1].y*8)
      --   spr(47, tiles[#tiles].x*8, tiles[#tiles].y*8)
      -- end
    end
  end
end

function draw_movement_ui()
  if (idle_start != nil and player_action.a == 0x00 and player_action.d > -1) then
    ap = to_pos(player_action.d)
    fp = {x = player.pos.x + ap.x, y = player.pos.y + ap.y}
    if (not (is_wall(fp) or is_glass(fp))) then
      pal(8, 11)
      spr(46, fp.x * 8, fp.y * 8)
      spr(sprites["objects"]["blood_prints"][player_action.d+1], fp.x * 8, fp.y * 8)
      pal(8, 8)
    end
  end
end

function draw_gun_ui()
  if (idle_start != nil and player_action.a == 0x01 and equipped == "socom") then
    d = player_action.d
    if (d == -1) d = player.facing
    ap = to_pos(d)
    fp = {x = player.pos.x + ap.x, y = player.pos.y + ap.y}
    spr(47, fp.x * 8, fp.y * 8)
  end
end

function draw_c4_ui()
  if (idle_start != nil and player_action.a == 0x01 and equipped == "c4") then
    d = player_action.d
    if (d == -1) then
      fp = {x = player.pos.x, y = player.pos.y - 1}
      spr(31, fp.x * 8, fp.y * 8)
      return
    end
    ap = to_pos(d)
    fp = {x = player.pos.x + ap.x, y = player.pos.y + ap.y}
    spr(43, fp.x * 8, fp.y * 8)
  end
end

function draw_restart_ui()
  if (idle_start != nil and player_action.a == 0x11) then
    print("restart?", 48, 66, 7)
  end
end

function draw_objects()
  for o in all(scanners) do
    if (o.player_allowed or is_scanner_active(o)) then
      spr(sprites["objects"][o.pattern][2], o.pos.x*8, o.pos.y*8)
    else
      spr(sprites["objects"][o.pattern][1], o.pos.x*8, o.pos.y*8)    
    end
  end

  for m in all(multilocks) do
    if (m.active) then
      spr(sprites["objects"][m.pattern][2], m.pos.x*8, m.pos.y*8)
    else
      if (m.player_allowed) then
        spr(sprites["objects"][m.pattern][3], m.pos.x*8, m.pos.y*8)
      else
        spr(sprites["objects"][m.pattern][1], m.pos.x*8, m.pos.y*8)
      end
    end
  end

  for g in all(goals) do
    spr(sprites["objects"][g.pattern][1], g.pos.x*8, g.pos.y*8)
  end  
end

function draw_above_prints_objects()
  for o in all(doors) do
    spr(sprites["objects"][o.pattern][o.facing + 1][o.open + 1], o.pos.x*8, o.pos.y*8)
  end

  for o in all(multidoors) do
    spr(sprites["objects"][o.pattern][o.facing + 1][o.open + 1], o.pos.x*8, o.pos.y*8)
  end

  for r in all(relays) do
    spr(sprites["objects"][r.pattern][1], r.pos.x*8, r.pos.y*8)
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

function draw_ui()
  -- draw action brackets
  if (idle_start != nil and (player_action.d > -1 or player_action.a != 0x00)) then
    if (player_action.a != 0x11) then
      spr(62, 17, 3)
      spr(63, 41, 3)
    else
      spr(62, 17, 3)
      spr(63, 49, 3)
    end
  end

  -- draw action symbols
  if (idle_start != nil and player_action.a == 0x01) spr(57, 25, 3)
  if (idle_start != nil and player_action.a == 0x10) spr(56, 25, 3)
  if (idle_start != nil and player_action.a == 0x11) spr(57, 25, 3); spr(56, 33, 3)
  if (idle_start != nil and player_action.a == 0x00 and player_action.d > -1) spr(58 + player_action.d, 25, 3)
  if (idle_start != nil and (player_action.a == 0x01 or player_action.a == 0x10) and player_action.d > -1) spr(58 + player_action.d, 33, 3)
  if (idle_start != nil and player_action.a == 0x11 and player_action.d > -1) spr(58 + player_action.d, 41, 3)

  -- draw health bar
  rect(2,2,player.max_life * 5 + 3,7,6)
  rectfill(3,3,player.max_life * 5 + 2,6,2)
  if (player.life > 0) rectfill(3,3,player.life * 5 + 2,6,3)
  print("life", 4, 6, 7)

  -- draw item use.
  if (equipped == "socom") draw_socom()
  if (equipped == "hands") draw_hands()
  if (equipped == "c4") draw_c4()
  if (player.blood_prints >= 1) draw_blood_ui()
  
  -- nice little window border
  rect(0,0,127,127,5)
end

function _draw()
  cls()
  l = levels[level]
  a = act_pos(player)
  if (player.pos.x == a.x and player.pos.y == a.y) then
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
    draw_c4_ui()
  end
  draw_lasers()
  camera(0, 0)
  draw_restart_ui()
  draw_ui()
end
__gfx__
00000000000000000000000000000000441444400000000000000000000000000000010080000000080000000000000000000000000000000000000000000000
0000000000444400000000000104444000411110010444400000000004444000004444100e044400000e08000000000000000000000000000000000000000000
00700700041111000044440004111110100f3f30041111100044440041111000041811408883114000808e800000000000000000000000000000000000000000
0007700001f3f30004111100004f3f30151ffff0004f3f30041111001f3f3000043f3f000e8ef340100388140000000000000000000000000000000000000000
0007700004ffff0001f3f300000ffff015111f1f000ffff001f3f3004fff55600888fff01888f440108e8f14000388e100000000000000000000000000000000
0070070000111000041fff0000f11f0000000000001110f0044fff000111f5000081110005811480051ff34480e8838800000000000000000000000000000000
000000000f555f0000111f0000155000000000000f0551000111f1f0055500000f0551008058000805111e801188ff8400000000000000000000000000000000
000000000010100000f110000000010000000000001000000015111001010000000001000011000000f110e811f8844000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000500000000000000b0000008800000000000000000000000000000000000000000000
000000000044400000000000004441000000000000041400000000000004440000000000000b0000008800000000000000800000000000000000000033000033
000000000444440000044400044414001041440000444140004440000044444000000000000b0000008000000000088800880000000088800000000030000003
0000000001111100004444400111110011111440001111100444440000111110bbbbbbbb000b00000000000000000088008800000000880000000000000b0000
000000000f441400001111100f44440015555100004444f00111110000f4414000000000000b00000000880000880000000000008800000000000000000bb000
000000000044400000f4410001544000f11110f00005441004414f00001111f000000000000b00000000880008880000000008008880000000000000000bb000
000000000f555f00000555f0001510000000000000055100015551000005550000000000000b0000000008000000000000008800000000000000000030000003
000000000010100000f1110000100f000000000000f00100001110000001010000000000000b0000000000000000000000008800000000000000000033000033
00000000000000000000000000100000004444000000010000000000000000000000000000008000000000000000000000000000000000000000000000000000
00000000004444000000000001444400041111000044441000000000004444000000000000008000000000000000000000000000002220000000000033000033
00000000041111000044440004111140103f3400041111400044440004111400000000000000800000000000000000000000000002eee2000000000030000003
0000000001f3f3000411110000f3f34001fff410043f3f0000111140043f340000000000000080000000008000000000000000002e222e200000000000bbbb00
0000000004ffff0001f3f3000fffff000f111f0000fffff0003f3f10016ff100888888880000800000008800000bb000000880002eee2e200000000000bb0000
0000000000111000041fff0000111100001150000011110001fff10000f1110000000000000080008088888000bbbb00008888002ee22e200000000000b00000
000000000f555f0000111f00001550f0000000000f055100011f110000555000000000000000800000080800300000032000000202eee2003000000330000003
000000000010100000f5100000100000000000000000010000115f10001010000000000000008000000000003300003322000022002220003300003333000033
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
01566510000000000156651000166510010000000010001001061000001601000156651000100100000000000000000000000000000000000000000000000000
01566111111111111116651000166511000100000101c00110160100010610100118511011011011000000000000000000000000000000000000000000000000
0156655155551555155665100156655111101010011c110010166555556610100008500051000015000000000000000000000000000000000000000000000000
01666666666665666666661001666666010100001c01101010150510150510100108501065555556000000000000000000000000000000000000000000000000
0165666666566666666656100165666500010110001101c101050500050501000108501068888886000000000000000000000000000000000000000000000000
01566555515555555556651001566551000110001100cc0110101010101010100008500051000015000000000000000000000000000000000000000000000000
0011111111111111111111000016651100100010011c011000110101010110010118511011011011000000000000000000000000000000000000000000000000
00000000000000000000000000156100000000111010100001001000001001000156651000000000000000000000000000000000000000000000000000000000
00111100011665100000000001566100000000000000000001511100005c75000010010000000000000000000000000000000000000000000000000000000000
011551100156651001111111115561001111111015155100166510100107c0100101101001111111000000000000000000000000000000000000000000000000
01566110015565101155551515566510515555115666661005510010000cc0005000000511155555000000000000000000000000000000000000000000000000
01566510015665101566566666666610666566516681666156500001010cc0107cccc7cc15666666000000000000000000000000000000000000000000000000
01556510015661101566666656665610666666516110166166510010010cc010c7cccc7c15665666000000000000000000000000000000000000000000000000
01566510011551101115555515566510555551116100156106651010000c70005000000511555515000000000000000000000000000000000000000000000000
011665100011110001111111115661001111111066555610156551510107c0100101101001111111000000000000000000000000000000000000000000000000
01566510000000000000000000166100000000000166610051115500005cc5000010010000000000000000000000000000000000000000000000000000000000
0010010001566510000000000010010000000000000000000010010001000010001001000010010000100100bbbbbbbb88888888666666666666666600008000
010110100112511011011011010110100dccccd0000000000101101003bbbb30011651500116515001165150b333333b82222228611000111000111600088800
00000000000000005100001501555510d000000d000000000155551033333333016115100161151001611510b33bbb3b8282222861b308218208211688008800
0100001001000010600000560281182000dccd000055850003b11b300000000000582100005b3100005a9100b3bbbb3b82282228601110001110001688000880
010000100100001060000026028118200d0000d00000000003b11b30bbbbbbbb001285000013b5000019a500b3b3333b82228228608218208218200608800000
00000000000000005100001501555510000cc0000055b5000155551033333333015116100151161001511610b33bbb3b82228828600011100011100600008800
0101101001000010110110110101101001011010005555000101101001000010051561100515611005156110b333333b8222222861b9c8110001110600008880
0010010001000010000000000010010000100100000000000010010013bbbb31001001000010010000100100bbbbbbbb88888888666666666666666600000088
01566510000000007777677777777677001001000666776677676600001001000000000667777777776766608888888888888888bbbbbbbbbbbbbbbb00000000
01195110110110117677767777677767060110100167677777777760060110100101666706777677777777008222222222222228b33333333333333b00000000
00000000510000156777777767767777676060601006777776777601676060001006777706776776767776018288882929292928b3bbbb333993993b00000000
01000010600000567777777777777767677676760167777777676010677676100167777706777777776760108288222929292928b3b3bbb33993993b00000000
01000010600000967777676767767676777777670106767777777610777777600106767701676776777776108282222222222228b3bb3b333333333b00000000
00000000510000156777767767606066677677771067776777776001677677601067776700060676766760018222222929292928b33333333993993b00000000
01000010110110117777777706011016776777760677777777767610776777600677777701011060760610108222222222222228b33333333333333b00000000
01000010000000007776777600100100777777760066767776776000777777760066767700100100600000008888888888888888bbbbbbbbbbbbbbbb00000000
01566510000000007777677777776777777776777777677700000000000000007717617700000000000000000000000000000000000000000000000000055000
01185110110110117766767776777777767766777677777700000300000003007116515700199100000000000000000000000000007777000005560000500050
0000000051000015676677776777666767776677677776660000030003000300616115170099a900000000000005500000677000077777700000056050000050
010000106000005677677777777776677777777777777667030000000300000076582167019a991000000800005d850006777700077777700650005000500500
010000106000008677777777766777777767776776677777030000000000000076128567019aa910000556000056650000777700077777700650005550000000
0000000051000015677766776667767767667677766677770000003000080000615116170199a9100066666000066000006776000a7777a00065000500000050
01000010110110117777667777777777776677777777777700000030000300007515611719aa9a9100000000000000000000600000aaaa000006650000005000
01000010000000007777767677767776777777767776777600000000000000007716717601011010000000000000000000000000000000000000000055500000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
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
00ffff0005f3f3500fffff00056ff10000fff55000fff55000000000000000000000000000000000000000000000000000000000000000000000000000000000
00111000001fff000011110000f11100051f3550051f355000000000000000000000000000000000000000000000000000000000000000000000000000000000
0f555f0000111f00001550f000555000151ff550151ff55000000000000000000000000000000000000000000000000000000000000000000000000000000000
0010100000f51000001000000010100011f0550011f0550000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00555500000000000555500000055550000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00555550005555000555550000055555000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
003f3f500055555003f3f5000003f3f5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00ffff00003f3f500ffff0000655fff0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0001110000fff10000f11f00005f1110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00f555f000f111000005510000005550000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0001010000011f000010000000001010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
404442bf40616161616142406152416161616142636141616142bfbfbfbfbfbfbf7f7f7f7f7f7f7f7f7f7f7f7f7f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000408242bf4061616161614240615241616161614200
5021636173c0808080e050430186438380f08350430181c080504961516146545446464646464646464646464657000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005021636173c0808080e050430186438380f0835000
50864383508053535380505080806341616144516361738053505065476565769894970fbf98979894970f989747000000000000000000000000bfbf0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000508643835080535353805050808063416161445100
508350804383808053805063616161738080f050636173d05350636151617498929296a70f999292939294929a47000000000000000046464646bfbf0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000508350804383808053805063616161738080f05000
6344738050805380538050508780844383548550508750888050430181bfa69992929294978495968595939abf470000000000000000000000bfbfbf0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000634473805080538053805050878084438354855000
5085508050d0808080f0506082616151616161626359738080506361516174989293929292949293949aa70000470000000000000000920000bf00bf00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005085508050d0808080f05060826161516161616200
5080508643807083406162bfbfbf0fbf000000005084438680505065476576999abf999292929a009594970000636142000000000000000000bf00ff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005080508343807083406162bfbfbfbfbf0000000000
508643d06345514473bfbfbfbfbf0f000000000060615261616260465146466161740f99939a0f0099929294976887500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000508643d06345514473bfbfbfbfbfbf000000000000
606152617384508750ffbfbf0000000000000000000000000000bfbf4798949497bfbfbf0fbfa7000f9993939a6361620000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000606152617384508750ffbfbf000000000000000000
00000000606152616200bfbf000000000000bf40614200000000bfbf479993939abf000fa600000f0000000f00470000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000606152616200bfbf000000000000000000
4f63615254526161516565bf0000bfbfbfbf65508743000000000000664646464646464646464646464646464667000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004f63615254526161516565bf000000000000000000
4048656565478a47656563bfbfbfbfbfbf65655159730000000000007f7f7f7f7f7f7f7f7f7f7f7fbfbfbfbfbfbfbfbfbfbf0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004048656565478a47656563bf000000000000000000
48465765566780665765507fbfbf65656565655084506565000000bfbfbfbfbfbfbfbfbf7f7f0000bfbfbfbfbfbfbfbfbfbf000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000484657656547bf476565507f7f7f00000000000000
548066466780c0806646636141636141616161524452614a6500bfbfbf40614200406142bf0000bfbfbfbfbfbfbfbfbfbfbf0000004961616161416161614a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000054bf66464667926646466361417f00000000000000
5401808480805380808a5887434301818080808a8380f0506500bf00bf508460617380636142bfbfbfbf406142634442406142000050808080e0718080805000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007601bfbf8492bf92bfbf5887500000000000000000
758056465780f080564663617363615274808072616161730000bf00bf430180805088638050bfbfbf4062c06073016362806042bf5080567880807857e050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075bf56464657bf5646466361730000000000000000
6554676566578056674951545451545476d0808a8080f0500000bf00bf636142e071d07180636142bf5080808877807780808850bf508077c08080e07780500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000655467656547bf476549517f000000000000000000
6565516565478a636162656565656565547080496161616200000000bfbfbf50808a8080e0588750bf50808880c0808080888050bf6374c08080808080f05000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006565516565478a6361624f4f000000000000000000
4f4f6061416174540000000000af6565655080506565000000000000bfbfbf738070807088636162bf5088808077807788808050bf50c0d08011808080795142000000000000000000000000000000000000000000000000000000000000000000000000000000000000004f4f60614161745400000000000000000000000000
0000bf0000000000000000000000af656550885065bfbfbfbf00000000000050885080508050bebebf6042804051595142f04062bf508077d08080f07780504300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000406161614200000000000065606162af0000000000000000000050806361526162bebebebe6061625087506061620000508066788080786780636200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000406152c080805161420000000000000000000000000000000000000060616200bfbfbfbfbfbfbfbfbfbf606162bfbfbf00005080808070d0808080506500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000500180888a88588743000000000000000000000000000000000000000000bfbfbfbf406142bfbfbfbf00000000bfbfbf0000638040455141787841486500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000006061418080f05161620000000000000000404461420000000000000000004061616173e06361615161614200000000000000508343f08643f08643875400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000606161616200000000000000000040622188604200000000000000005080808043834380808080f0500000bf00000000606151616151616151746500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000004061616161614200000000000050808080885000000000000000005088636151805161615180887300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000004061425080c08080835000000000000050888080f05000000000000000005080500180f0c080807780f050bf000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000508460738040616144510000000000006042d080406200000000000000005080508070804061615261616200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000043018343e050c0808060416142000000405261597300bf00000000bf000050d0508063595161614161420000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000634280508050805380834387500000005087808450bfbfbf000000bfbf005088637873834384f08187500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000bf50d05080508080f0405261620000006061616162bfbfbf000000bfbf00508050d050806361615261620000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000bf52615161516161615100000000000000bf0000000000000000000000006061526152616200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
000802021675016750177501675015750147501575015750137501475015750167501775017750177501775017750177501775017750167501575016750177501875018750187501875018750187501875018750
001000001a752000001a750000001a752000001a750000001a752000001a750000001a752000001a7520000019752000001975200000197520000019750000001575000000157500000015750000001575000000
011000001675000000167500000016750000001675000000167500000016750000001675000000167500000018750000001875000000187500000018750000001575000000157500000015750000001575000000
011000000e7500e7500e7500e7500000016750000001575013750117501075011750137500e750000000d7500d750000000e7500e75010750107500e7500e750000000d7500d7500000000000000000000000000
__music__
00 01424344

