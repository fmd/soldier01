pico-8 cartridge // http://www.pico-8.com
version 16
__lua__
-- debug values to reset on release
starting_level = 2
inventory = { socom = -1,
              c4 = -1 }
inventory_max = { socom = 4,
                  c4 = 2 }
equipped = "hands"

-- load the sprites and that
sprites = { player = {{17,18,19,18,21,22,23}, -- north (last two=roll/shoot)
                      {1,2,3,2,5,6,7},        -- east (last two=roll/shoot)
                      {33,34,35,34,37,38,39}, -- south (last two=roll/shoot)
                      {49,50,51,50,53,54,55}, -- west (last two=roll/shoot)
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
                       scanner = {131, 134},
                       multilock = {136, 137, 138},
                       multidoor = {{88, 144}, {89, 145}},
                       door = {{67, 129}, {68, 130}},
                       goal = {135},
                       relay = {132}},
            items   = {socom = 133,
                       c4 = 133} }

-- we use mset to replace the map while it's in play, so,
-- we store a list of replaced tiles to put back when the level is reset
mset_restore = {}

-- palette swap commands and movement function strings for enemy variants
enemy_variants = {enemy1 = {{"clockwise", {5, 5}}, -- variant 1
                            {"line", {5, 2}} }} -- variant 2

-- for converting a direction to a position change          
pos_map = {{0,1,0,-1}, {-1,0,1,0}}

-- level data
levels = {{0,10,13,9},{13,9,10,12},{11,0,15,6}, {0,0,11,10}} -- xstart, ystart, w, h
level_items = {{},{"socom"}, {"c4"}}
level_enemy_variants = {{},{2,1,2},{2,2}, {1,1,1,1,2}}

-- map runthrough replacements (sprite #, pattern, facing dir)
-- note: facing dir for doors and other items with only 2 dirs is [0/1] rather than [0/1/2/3]
map_replace = {{67, "door", 0}, -- closed regular door
               {68, "door", 1}, 
               {88, "multidoor", 0}, -- closed multilock door
               {89, "multidoor", 1}, 
               {1,  "player",  1}, -- player
               {17,  "player", 0},
               {33,  "player", 2},
               {49,  "player", 3},
               {192,  "enemy1", 1}, -- enemy1
               {208,  "enemy1", 0},
               {224,  "enemy1", 2},
               {240,  "enemy1", 3},
               {131, "scanner", false}, -- sprite #, pattern, player_allowed (scanner)
               {134, "scanner", true},  -- sprite #, pattern, player_allowed (scanner)
               {136, "multilock", false}, -- sprite #, pattern, player_allowed (multilock)
               {138, "multilock", true}, -- sprite #, pattern, player_allowed (multilock)
               {132, "relay"}, -- relays have no extra attribs yet
               {135, "goal"},  -- goals have no extra attribs yet
               {133, "item"}} -- the item type is taken from the level_items variable

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
  a = {id = actor_count, pattern = "enemy1", facing = m[3], variant = level_enemy_variants[level][enemy_count], pos = {x = x, y = y}, life = 1, death_frames = 0, hurt_frames = 0, attack_frames = 0, blood_prints = 0, stunned_turns = 0, act = {a = 0x00, d = -1}}
  add(actors, a)
end

function add_player(m, x, y)
  actor_count += 1
  a = {id = actor_count, pattern = "player", facing = m[3], pos = {x = x, y = y}, life = 3, max_life = 3, death_frames = 0, hurt_frames = 0, attack_frames = 0, blood_prints = 0, stunned_turns = 0, act = {a = 0x00, d = -1}}
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
    if (o.pattern == "blood_prints" and o.pos.x == actor.pos.x and o.pos.y == actor.pos.y) then
      p = o
      break
    end
  end
  return p
end

function do_enemy1_variant_movement_ai(actor, apos)
  movement_type = enemy_variants[actor.pattern][actor.variant][1]
  apos = act_pos(actor)
  
  if (movement_type == "clockwise") then
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

  if (movement_type == "line") then
    if (apos.x == actor.pos.x and apos.y == actor.pos.y) do
      actor.facing += 2
      if (actor.facing > 3) actor.facing = abs(4 - actor.facing)
      actor.act.d = actor.facing
    end
  end

  return
end

function do_enemy1_ai(actor)
  if (actor.life <= 0) then
    actor.act = {a = 0x00, d = -1}
    return
  end

  if (actor.stunned_turns > 0) then
    actor.stunned_turns -= 1
    if (actor.stunned_turns > 0) return
    ha = has_actor(actor.pos, "")
    if (ha and ha.id != actor.id) actor.stunned_turns = 1; return
  end
  
  -- if we find blood prints, follow. else, follow variant movement pattern
  actor.act.d = actor.facing
  printed = print_on_tile(actor)
  if (printed) then
    if (actor.act.a == 0x00) actor.act.d = printed.facing
    -- if we go nowhere with the print facing, try new directions until we find a free direction (invoke variant-based ai pattern).
    do_enemy1_variant_movement_ai(actor, apos)
  else 
    tiles = collect_tile_line(actor)
    if (is_empty(tiles)) then
      -- if we can go nowhere, invoke variant-based ai pattern
      do_enemy1_variant_movement_ai(actor, apos)
    end
  end

  -- with new facing, look for player to shoot
  tiles = collect_tile_line(actor)
  if (not is_empty(tiles)) then
    for k, tile in pairs(tiles) do
      if (player.pos.x == tile.x and player.pos.y == tile.y) actor.act.a = 0x01
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
      end
    end
  end
end

function start_actors_turns()  
  for actor in all(actors) do    
    if (actor.pattern == "player") actor.act = {a=player_action.a, d=player_action.d}
    if (actor.pattern == "enemy1") do_enemy1_ai(actor)
    if (actor.act.d > -1) actor.facing = actor.act.d

    pickup_prints(actor) 
    place_new_prints(actor)
  end

  for actor in all(actors) do
    if (actor.pattern == "enemy1") do_avoidance(actor)
  end
end

function end_actors_turns()
  -- todo: different acts have different patterns
  -- perform all moves first so shots line up
  
  for actor in all(actors) do
    redirect_existing_prints(actor)    
    perform_move(actor)
  end  

  -- perform the moves
  for actor in all(actors) do
    perform_act(actor)    
    actor.act = {a = 0x00, d = -1}
  end
end

function to_pos(dr)
  return { x = pos_map[1][dr + 1],
           y = pos_map[2][dr + 1] }
end

function act_pos(actor)
  -- todo: different acts have different movements
  actor_point = {x = actor.pos.x, y = actor.pos.y}
  if (actor.act.d < 0) return actor_point
  
  act_dir = to_pos(actor.act.d)
  test_point = {x = actor.pos.x + act_dir.x, y = actor.pos.y + act_dir.y}
  if (is_wall(test_point)) return actor_point

  -- todo: other future moves may do not move the player. consider refactoring all actions.
  if (actor.id != player.id and actor.act.a != 0x00) return actor_point
  if (actor.id == player.id and actor.act.a != 0x00) return actor_point
  return test_point
end

function lmapget(x, y)
 return mget(x + levels[level][1], y + levels[level][2])
end

function is_wall(pos)
  m = lmapget(pos.x, pos.y)
  
  for o in all(doors) do 
    if (o.pos.x == pos.x and o.pos.y == pos.y) then
      if (o.open == 1) return false
      return true
    end
  end
  
  return (m >= 64 and m <= 127)
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

function redirect_existing_prints(actor)
  if (actor.life <= 0 or actor.blood_prints <= 0) return

  p = print_on_tile(actor)
  if (p) then
    apos = act_pos(actor)
    if (apos.x != p.pos.x or apos.y != p.pos.y) then 
      p.facing = actor.act.d
    end
  end
end

function place_new_prints(actor)
  if (actor.life <= 0 or actor.blood_prints <= 0) return

  p = print_on_tile(actor)
  if (not p) then
    o = { pattern = "blood_prints", facing = actor.act.d, pos = {x = actor.pos.x, y = actor.pos.y} }
    add(prints, o)
  end

  actor.blood_prints -= 1
end

function pickup_prints(actor)
  if (actor.life <= 0) return
  
  for a in all(actors) do
    if (a.life <= 0 and actor.life > 0 and a.pos.x == actor.pos.x and a.pos.y == actor.pos.y) then
      actor.blood_prints = 5
    end
  end
end

function has_actor(np, exclude_pattern)
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
  h = has_actor(attack_point, "player")
  w = will_have_actor(attack_point, "player")
  if (h) then
    moving_out_point = act_pos(h)
    if (moving_out_point.x == attack_point.x and moving_out_point.y == attack_point.y) then
      stun_actor(h, 3)
      return h
    end
    
    return nil
  end
  
  if (w) then
    stun_actor(w, 3)
    return w
  end

  return nil
end

function attempt_move(actor)  
  -- todo: characters other than player can melee
  if (actor.pattern == "player") attempt_melee(actor)
  actor.pos = act_pos(actor)
end

function collect_tile_line(actor)
  collected = {}
  if (not (actor.act.d >= 0)) return collected
  tx = actor.pos.x + to_pos(actor.act.d).x
  ty = actor.pos.y + to_pos(actor.act.d).y
  
  i = 1
  while not is_wall({x = tx, y = ty}) do
    collected[i] = {x = tx, y = ty}
    i+=1
    tx += to_pos(actor.act.d).x
    ty += to_pos(actor.act.d).y
  end
  
  return collected
end

function stun_actor(actor, turns)
  actor.stunned_turns = turns
end

function hurt_actor(actor)
  if (actor.life > 0) actor.life -= 1
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
    if (inventory["c4"] <= 0) return
    inventory["c4"] -= 1
    
    attempt_c4(player)
    return
  end

  attempt_melee(player)
end

function attempt_c4(actor)

end

function attempt_shot(actor)  
  for i, tile in pairs(collect_tile_line(actor)) do
    for j, a in pairs(actors) do
      if (actor != a and a.pos.x == tile.x and a.pos.y == tile.y) hurt_actor(a)
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
end

function update_frame(start)
  chunk = flr((time() - start) * 100)
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
  start_actors_turns()
end

function end_turn()
  end_actors_turns()
  tick_closing_doors()
  open_doors_near(active_buttons(scanners))
  switch_multilocks(active_buttons(multilocks))
  open_multilock_doors()
  pick_up_items()
  check_goals()
  
  player_action = {a = 0x00, d = -1}
  turn_start = nil
  idle_start = time()
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
  if (player_action.d > -1 and d == -1) start_turn(); return
  
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
    if (actor.act.a != 0x00 and (actor.id != player.id or equipped == "socom")) return sprites[actor.pattern][actor.facing+1][7]
    if (actor.act.d > -1) return sprites[actor.pattern][actor.facing+1][frame+1]
  end
  
  if (actor.facing == -1) return sprites[actor.pattern][1][1]
  return sprites[actor.pattern][actor.facing+1][1]
end

function draw_actors()
  -- draw dead and stunned enemy_variants first
  for actor in all(actors) do    
    if (actor.life <= 0 or actor.stunned_turns > 0) then
      if (actor.pattern != "player") then
        s = tile_shift(actor)
        palswap = enemy_variants[actor.pattern][actor.variant][2]
        pal(palswap[1], palswap[2])
        spr(sprite_for(actor), actor.pos.x*8 + s.x, actor.pos.y*8 + s.y)
        pal(palswap[1], palswap[1])
      end
    end
  end
  
  for actor in all(actors) do
    if (actor.life > 0) then
      if (actor.pattern != "player") then
        s = tile_shift(actor)
        palswap = enemy_variants[actor.pattern][actor.variant][2]
        pal(palswap[1], palswap[2])
        spr(sprite_for(actor), actor.pos.x*8 + s.x, actor.pos.y*8 + s.y)
        pal(palswap[1], palswap[1])
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
      for tile in all(collect_tile_line(actor)) do
        if (actor != player or inventory["socom"] > -1) spr(sprites[actor.pattern][6][actor.act.d % 2 + 1], tile.x*8, tile.y*8)        
      end
    end
  end
end

function draw_objects()
  for o in all(doors) do
    spr(sprites["objects"][o.pattern][o.facing + 1][o.open + 1], o.pos.x*8, o.pos.y*8)
  end

  for o in all(multidoors) do
    spr(sprites["objects"][o.pattern][o.facing + 1][o.open + 1], o.pos.x*8, o.pos.y*8)
  end

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

  for r in all(relays) do
    spr(sprites["objects"][r.pattern][1], r.pos.x*8, r.pos.y*8)
  end
end

function draw_items()
  for i in all(items) do
    spr(sprites["items"][i.pattern], i.pos.x*8, i.pos.y*8)
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
end

function draw_hands()
  spr(139, 118, 118)
end

function draw_socom_bullet(x,y,c)
  pset(x,y,c)
  pset(x,y+1,c)
  pset(x,y+3,c)
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
  rect(2,2,18,7,6)
  rectfill(3,3,17,6,2)
  if (player.life > 0) rectfill(3,3,player.life * 5 + 2,6,3)
  print("life", 4, 6, 7)

  -- draw item use.
  if (equipped == "socom") draw_socom()
  if (equipped == "hands") draw_hands()
  if (equipped == "c4") draw_c4()
  
  -- nice little window border
  rect(0,0,127,127,5)
end

function _draw()
  cls()
  l = levels[level]
  a = act_pos(player)
  if (player.pos.x == a.x and player.pos.y == a.y) then
    camera((player.pos.x * 8) - 64, (player.pos.y * 8) - 64)
  else
    xd = a.x - player.pos.x
    yd = a.y - player.pos.y
    camera((xd * biframe) + (player.pos.x * 8) - 64, (yd * biframe) + (player.pos.y * 8) - 64)
  end
  map(l[1], l[2], 0, 0, l[3], l[4])
  draw_objects()
  draw_prints()
  draw_items()
  draw_actors()  
  draw_lasers()
  camera(0, 0)
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
000000000000000000000000000000000000000000000000000000000000500000000000000b0000008000000000000000000000000000000000000000000000
000000000044400000000000004441000000000000041400000000000004440000000000000b0000008008000000000000808000000000000000000000000000
000000000444440000044400044414001041440000444140004440000044444000000000000b0000000008000088008800800800088008800000000000000000
0000000001111100004444400111110011111440001111100444440000111110bbbbbbbb000b0000000080000800000000000800000800000000000000000000
000000000f441400001111100f44440015555100004444f00111110000f4414000000000000b0000008000000000800000080000000000800000000000000000
000000000044400000f4410001544000f11110f00005441004414f00001111f000000000000b0000008008000880088000800000880088000000000000000000
000000000f555f00000555f0001510000000000000055100015551000005550000000000000b0000000808000000000000800800000000000000000000000000
000000000010100000f1110000100f000000000000f00100001110000001010000000000000b0000000000000000000000000800000000000000000000000000
00000000000000000000000000100000004444000000010000000000000000000000000000008000000000000000000000000000000000000000000000000000
00000000004444000000000001444400041111000044441000000000004444000000000000008000000000000000000000000000002220000000000000000000
00000000041111000044440004111140103f3400041111400044440004111400000000000000800000000000000000000000000002eee2000000000000000000
0000000001f3f3000411110000f3f34001fff410043f3f0000111140043f340000000000000080000000008000000000000000002e222e200000000000000000
0000000004ffff0001f3f3000fffff000f111f0000fffff0003f3f10016ff10088888888000080000000880000000000000000002eee2e200000000000000000
0000000000111000041fff0000111100001150000011110001fff10000f1110000000000000080008088888000000000000000002ee22e200000000000000000
000000000f555f0000111f00001550f0000000000f055100011f110000555000000000000000800000080800000000000000000002eee2000000000000000000
000000000010100000f5100000100000000000000000010000115f10001010000000000000008000000000000000000000000000002220000000000000000000
00000000000000000000000000000000044441440000000000000000000000000000000000000000000000000000000000000000000000000000099999900000
00000000004444000000000004444010011114000444401000000000000444400033300000222000005550000055500000555000005550000000090000900000
0000000000111140004444000111114003f3f00101111140004444000001111403bbb30002888200056665000566650005666500056665000000090000900000
00000000003f3f100011114003f3f4000ffff15103f3f400001111400003f3f13b3b3b3028828820566566505655665056565650566556500009000000009000
0000000000ffff40003f3f100ffff000f1f111510ffff000003f3f100655fff43bb3bb3028282820565556505665565056555650565566500009000000009000
000000000001110000fff14000f11f00000000000f01110000fff440005f11103b3b3b3028828820565656505655665056656650566556500000090000000000
0000000000f555f000f111000005510000000000001550f00f1f11100000555003bbb30002888200056665000566650005666500056665000000090000900000
000000000001010000011f0000100000000000000000010001115100000010100033300000222000005550000055500000555000005550000000099999900000
0000000000000000000000000156651000100100000000000010010000150100015665100c11c110011c11c00000000000000000000000000000000000000000
00111111111111111111110001125110110110111001000101011010010510101115651110101011110101010000000000000000000000000000000000000000
01566555515665555556651000025000510000155111501155666655010610111555651001006105501600100000000000000000000000000000000000000000
016566666566566666665610010250106555555661556655515150511106101065661101c00511666611500c0000000000000000000000000000000000000000
01666666666666666666661001025010622222266656615650505050011601006611500c10116656656611010000000000000000000000000000000000000000
01566551155665551556651000025000510000155155101501010100111610115016001001565551155565100000000000000000000000000000000000000000
01566111115655111116651001125110110110110011000100000000010510101101110111565111111565110000000000000000000000000000000000000000
0156651001566110015665100156651000000000000000000000000000150101011c00c001566510015665100000000000000000000000000000000000000000
01566510015665100116651000111100010110000115651001001000001001000156651000100100000000000000000000000000000000000000000000000000
01566510111665111155651101555510115111500015510010110100010110100119511011011011000000000000000000000000000000000000000000000000
01566110155665515556655115444551115556110006100010166655566610100009500051000015000000000000000000000000000000000000000000000000
01566510666666666666666655555451055665510056610010160510150610100109501065555556000000000000000000000000000000000000000000000000
01556510656566656665666554445451151565510115651001060500050601000109501069999996000000000000000000000000000000000000000000000000
01566510555665515556655554445451151551510015551010161010101610100009500051000015000000000000000000000000000000000000000000000000
01166510115665111111111154445510115655100011610000160101010610010119511011011011000000000000000000000000000000000000000000000000
01566510000561000000000015555100051550100156650001051000001501000156651000000000000000000000000000000000000000000000000000000000
01566510000000000156651000166510010000000010001001061000001601000000000000000000000000000000000000000000000000000000000000000000
01566111111111111116651000166511000100000101c00110160100010610100000000000000000000000000000000000000000000000000000000000000000
0156655155551555155665100156655111101010011c110010166555556610100000000000000000000000000000000000000000000000000000000000000000
01666666666665666666661001666666010100001c01101010150510150510100000000000000000000000000000000000000000000000000000000000000000
0165666666566666666656100165666500010110001101c101050500050501000000000000000000000000000000000000000000000000000000000000000000
01566555515555555556651001566551000110001100cc0110101010101010100000000000000000000000000000000000000000000000000000000000000000
0011111111111111111111000016651100100010011c011000110101010110010000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000156100000000111010100001001000001001000000000000000000000000000000000000000000000000000000000000000000
00111100015665100000000001566100000000000000000001511100000000000000000000000000000000000000000000000000000000000000000000000000
01155110011665100111111111556100111111101515510016651010000000000000000000000000000000000000000000000000000000000000000000000000
01566110015665101155551515566510515555115666661005510010000000000000000000000000000000000000000000000000000000000000000000000000
01566510015565101566566666666610666566516681666156500001000000000000000000000000000000000000000000000000000000000000000000000000
01556510015665101566666656665610666666516110166166510010000000000000000000000000000000000000000000000000000000000000000000000000
01566510015661101115555515566510555551116100156106651010000000000000000000000000000000000000000000000000000000000000000000000000
01166510011551100111111111566100111111106655561015655151000000000000000000000000000000000000000000000000000000000000000000000000
01566510001111000000000000166100000000000166610051115500000000000000000000000000000000000000000000000000000000000000000000000000
0010010001566510000000000010010000000000000000000010010001000010001001000010010000100100bbbbbbbb88888888666666666666666600000000
010110100112511011011011010110100dccccd0000000000101101003bbbb30011651500116515001165150b333333b82222228611000111000111600000000
00000000000000005100001501555510d000000d000000000155551033333333016115100161151001611510b33bbb3b8282222861b308218208211600000000
0100001001000010600000560281182000dccd000055850003b11b300000000000582100005b3100005a9100b3bbbb3b82282228601110001110001600000000
010000100100001060000026028118200d0000d00000000003b11b30bbbbbbbb001285000013b5000019a500b3b3333b82228228608218208218200600000000
00000000000000005100001501555510000cc0000055b5000155551033333333015116100151161001511610b33bbb3b82228828600011100011100600000000
0101101001000010110110110101101001011010005555000101101001000010051561100515611005156110b333333b8222222861b9c8110001110600000000
0010010001000010000000000010010000100100000000000010010013bbbb31001001000010010000100100bbbbbbbb88888888666666666666666600000000
01566510000000000000000000000000000000000000000000100100000000000000000000000000000000008888888888888888bbbbbbbbbbbbbbbb00000000
01195110110110110000000000000000000000000000000000000000000000000000000000000000000000008222222222222228b33333333333333b00000000
00000000510000150000000000000000000000000000000000000000000000000000000000000000000000008288882929292828b3bbbb333993883b00000000
01000010600000560000000000000000000000000000000000000000000000000000000000000000000000008288222929292828b3b3bbb33993883b00000000
01000010600000960000000000000000000000000000000000000000000000000000000000000000000000008282222222222228b3bb3b333333333b00000000
00000000510000150000000000000000000000000000000000000000000000000000000000000000000000008222222929292828b33333333993883b00000000
01000010110110110000000000000000000000000000000000000000000000000000000000000000000000008222222222222228b33333333333333b00000000
01000010000000000000000000000000000000000000000000000000000000000000000000000000000000008888888888888888bbbbbbbbbbbbbbbb00000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
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
00000000000000000000000000006000007060000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
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
408242bf40616161616142406152416161616142000000ff0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000408242bf4061616161614240615241616161614200
5021636173c0808080e050430186438380f083507f000000ff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005021636173c0808080e050430186438380f0835000
50864383508053535380505080806341616144517f000000ff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000508643835080535353805050808063416161445100
508350804383808053805063616161738080f0507f000000ffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000508350804383808053805063616161738080f05000
63447380508053805380505087808443835485507f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000634473805080538053805050878084438354855000
5085508050d0808080f0506082616151616161627f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005085508050d0808080f05060826161516161616200
5080508343807083406162bfbfbf68bf000000007f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005080508343807083406162bfbfbfbfbf0000000000
508643d06345514473bfbfbfbfbfbf00000000007fbf00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000508643d06345514473bfbfbfbfbfbf000000000000
606152617384508750ffbfbf0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000606152617384508750ffbfbf000000000000000000
00000000606152616200bfbf000000000000406142000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000606152616200bfbf000000000000000000
4f63615254526161516565bf00000000000050874300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004f63615254526161516565bf000000000000000000
4048656565478a47656563bf00000000000063597300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004048656565478a47656563bf000000000000000000
484657656547bf476565507f7f7f000000005084500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000484657656547bf476565507f7f7f00000000000000
54bf66464667926646466361416361416161524452614200bf0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000054bf66464667926646466361417f00000000000000
7601bfbf8492bf92bfbf58874343018180808a8380f05000bf000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007601bfbf8492bf92bfbf5887500000000000000000
75bf56464657bf5646466361736361738080726161617300bf0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075bf56464657bf5646466361730000000000000000
655467656547bf476549517f00000050d0808a8080f05000bf00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000655467656547bf476549517f000000000000000000
6565516565478a6361624f4f000000604283406161616200bf000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006565516565478a6361624f4f000000000000000000
4f4f6061416174540000000000af0000634451afaf000000bf000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004f4f60614161745400000000000000000000000000
0000bf0000000000000000000000af00508a50afafbfbfbfbf00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000606162afaf0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
00030202237502175020750187501d7501d750187501d750147501d750107500e7500c7501d7500e75010750327501b75031750307502e7502c75018750177501d75016750157501575013750107500d75008750
001000000e7520c7520c7520e75210752107521075210752107521175200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__music__
00 01024344

