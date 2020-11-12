pico-8 cartridge // http://www.pico-8.com
version 29
__lua__

-- big TODO: --
-- reimplementing doors, rations, player items, relays, explosives
-- Codec & Dialogue
-- Main menu
-- Sfx overhaul
-- Music

-- facing guide: 0=none, 1=up, 2=right, 3=down, 4=left
-- act guide:    0=still, 1=walk, 2=shoot, 3=change, 4=blast, 5=vault, 6=nil, 7=nil

------------------------------------
--- global level and sprite data ---
-- some global handles for commonly used sprites
sprite_store = { floor = 128,
                 void = 255,
                 select = 46 }

animations = { player = {{17,18,19,18,21,22,23,20}, -- north (last three=roll/shoot/fly)
                         {1,2,3,2,5,6,7,4},        -- east (last three=roll/shoot/fly)
                         {33,34,35,34,37,38,39,36}, -- south (last three=roll/shoot/fly)
                         {49,50,51,50,53,54,55,52}, -- west (last three=roll/shoot/fly) THESE SHOULD ALWAYS BE RIGHT FLIPPED
                         {8,9,10,11}, -- death
                         {12, 13}, -- fall
                         {25, 24, 25, 24}}, -- laser

                enemy = {{208,209,210,209,210,211,211,1}, -- north (last two=roll/shoot/fly)
                         {192,193,194,193,194,195,195,1}, -- east (last two=roll/shoot/fly)
                         {224,225,226,225,226,227,227,1}, -- south (last two=roll/shoot/fly)
                         {240,241,242,241,242,243,243,1}, -- west (last two=roll/shoot/fly)
                         {196,197,198,199}, -- death
                         {230, 231}, -- fall
                         {41, 40, 41, 40}, -- laser
                         {228, 229}},  -- stunned

              objects = { door = {{68, 130}, {67, 129}},
                  blood_prints =  {26, 27, 28, 29},
                      trapdoor =  {176, 177},
                       scanner =  {131, 134},
                        ration =   180 }}

-- global object sprite-on-map store
map_store = { player   = {17,1,33,49},
              enemy    = {208,192,224,240},
              door     = {67, 68},
              scanner  = {131, 134},
              trapdoor =  176,
              ration   =  180 }

-- enemy variants data
enemy_variants = {player = {{"player", {5, 5}}},
                  enemy = {{"clockwise", {5, 13}}, -- variant 1
                           {"line", {5, 2}}, -- variant 2
                           {"still", {5, 5}} }}  -- variant 3

-- misc global vars
current_level = 0 -- don't touch, change param of load_level instead
turn, chunk, frame, biframe, last_frame = 0,0,1,1,0
global_time, turn_start = nil, nil
input_act, input_dir, input_down = 0, 0, {false,false,false,false,false,false}
last_camera_pos = { x = 0, y = 0 }

--- / global level and sprite data ---
--------------------------------------
--- inter-level storage globals ------
---  (these persist between resets)

-- global level-on-map store
-- edity vars
levels = {{0,0,32,30}}
level_items = {{"gloves"}}
level_keycards = {{2,1,3}}
level_keydoors = {{1,2,3}}

-- TODO: refactor above vars into level class?
level_enemy_variants = {{2,2,3,3, 2,2,3,2, 1,2,2,1,1, 3,3,1,2, 3,3,3,2,1, 3,3,1,1}}
game_speed = 2.5 -- edit me!

--- types to hold classes ---
local actormt = {}
local objectmt = {}
local vecmt = {}

local object_methods = {}
local actor_methods = {}
local vector_methods = {}

--- / inter-level storage globals ----
--------------------------------------
--- checkpoint storage globals ---
player = nil

-- store global objects
global_objects = { actor = {},   -- includes player and enemy patterns
                   object = {},  -- includes all of the following:

                   -- the following are all "objects"
                   relay = {},    -- checkpoints
                   door = {},     -- includes keydoors and multilock doors.
                   trapdoor = {},
                   prints = {},   -- includes "blood_prints" and "snow_prints" patterns?
                   item = {}}     -- ration, keycard, equipment (TODO: unimplemented)

objects = {} -- global list of objects
relays = {} -- global list of relays (checkpoints)
doors = {} -- global list of doors
trapdoors = {} -- global trapdoors
prints = {} -- global prints

mset_restore = {} -- we use mset to replace the map while it's in play, so we store a list of replaced tiles to put back when the level is reset
-- mset_restore format: {position_vector,tile} (referred to as [1],[2])
--- / checkpoint storage globals ---
--------------------------------------

-------------------------------------------------------
-- SECTION 1: on init, simply load the first level. ---
-------------------------------------------------------
function _init()
  load_level(1)
end

-----------------------------------------------
-- SECTION 2: update cycle deals with turns ---
-----------------------------------------------
function _update60()
  update_frame()

  if (turn_start) then
    if (chunk > 999) end_turn()
    return
  end

  if (player.life > 0) then
    player.input_act = take_input()
    if (not player.input_act) return
    start_turn(); player.input_act = nil
  end

  if (not turn_start and chunk > 499) start_turn() -- allow a little "thinking" time if player is dead
end

------------------------------------------------------
--- SECTION 3: draw cycle deals with camera and UI ---
------------------------------------------------------
function _draw()
  cls()

  if (not player) return
  local p = to_pixel(player.pos)

  -- center camera
  buffer = make_vec2d(0,0)
  if (p != last_camera_pos) then -- player has new pos, we transition
    buffer = p - last_camera_pos
    buffer.x = -flr(buffer.x / 1.5)
    buffer.y = -flr(buffer.y / 1.5)
  end
  camera(p.x + buffer.x - 56, p.y + buffer.y - 56)
  last_camera_pos = p + buffer

  -- draw map
  --map(0, 0, 0, 0, 32, 30)
  draw_map()

  -- sneaky draw-layering to avoid excessive splitting of objects (TODO: for now...)
  draw_set(global_objects.object)
  draw_set(global_objects.actor)
  draw_set({player})

  -- debug ui
  if input_dir > 0 and input_act > 0 then
    local ui = to_pixel(dir_to_vec(input_dir) + player.pos)
    zspr(sprite_store.select, ui.x, ui.y)
  end

  -- debug action
  if (input_act == 5) zspr(57, p.x, p.y)
  if (input_act == 6) zspr(56, p.x, p.y)

  camera(0,0)

  -- debug frame ui
  -- print(frame.." "..biframe.." "..chunk, 10,10)

  -- health bar
  -- printh(player.life .. " " .. player.max_life .. " " .. player.o2 .. " " .. player.max_o2)
  draw_bar("life", player.life, player.max_life, 3, 2, 0)
  if (player:in_water()) draw_bar("o2", player.o2, player.max_o2, 12, 1, 1)
  -- draw_bar("boss", 5, 7, 9, 4, 2)

  -- window border
  rectcolor = 3
  if (turn_start != nil) rectcolor = 5
  rect(0,0,127,127,rectcolor)
end

---------------------------------------------
--- RELATING TO SECTION 1: Making the map ---
---------------------------------------------

-- load a level.
function load_level(l)
  enemy_count = 0
  current_level = l

  global_time = time()
  restore_msets(l)

  for y = 0, levels[l][4] - 1, 1 do
    for x = 0, levels[l][3] - 1, 1 do
      local v = make_vec2d(x, y)
      local t = lmapget(v, l)
      local o = get_tile_pattern(t)
      if (o) then
        add(mset_restore, {v, t})
        lmapset(v, l, make_object_from_map(v, o))
      end
    end
  end
end

-- make_object_from_map makes objects ready to start the level from what's on the pico8 map.
-- it returns the code to replace it with on the map.
-- o is passed from get_tile_pattern
function make_object_from_map(v, o)
  local pattern = o[1]
  if (pattern == "player") p = make_actor("player", v, o[2], 3); player = p; add(global_objects.actor, p); return sprite_store.floor
  if (pattern == "enemy") enemy_count += 1; a = make_actor("enemy", v, o[2]); add(global_objects.actor, a); return sprite_store.floor

  if (pattern == "trapdoor") t = make_object(pattern, v); add(global_objects.object, t); add(global_objects.trapdoor, t); return sprite_store.void
  if (pattern == "door") d = make_object(pattern, v); add(global_objects.object, d);  add(global_objects.door, d);  return sprite_store.void

  o = make_object(pattern, v); add(objects, o)
  return sprite_store.floor
end

function make_object(pattern, pos, facing)
  local t = {
    pattern = pattern,
    pos = make_vec2d(pos.x, pos.y),
    facing = facing or 1,
    solid = 0
  }

  mt = copymt(objectmt)

  if (pattern == "trapdoor") make_trapdoor(t, mt)
  if (pattern == "door") make_door(t, mt)
  -- if (pattern == "scanner") make_scanner(t, mt)
  if (pattern == "ration") then
    function mt.__index.activate(self)
      -- printh("Ration Activated")
    end
  end

  setmetatable(t, mt)
  return t
end

-- get_tile_pattern returns a more detailed object to make a tile out of,
-- or nil if there is nothing to make here.
-- the returned object is passed to make_object_from_map
function get_tile_pattern(tile)
  for k, o in pairs(map_store) do
    if not check_type(o, "table") then
      if (o == tile) return {k, o}
    else
      for f, i in pairs(o) do
        if (i == tile) return {k, f}
      end
    end
  end
  return nil
end

-- restore replaced map tiles
function restore_msets(l)
  for m in all(mset_restore) do
    mset(m[1].x + levels[l][1], m[1].y + levels[l][2], m[2])
  end

  mset_restore = {}
end

function lmapget(v, l)
  l = l or current_level
  return mget(v.x + levels[l][1], v.y + levels[l][2])
end

function lmapset(v, l, tile)
  mset(v.x + levels[l][1], v.y + levels[l][2], tile)
end

--------------------------------------------
--- RELATING TO SECTION 2: Turns & Input ---
--------------------------------------------

function start_turn()
  for actor in all(global_objects.actor) do
    if (actor.life > 0) then
      -- run ai routine (looking for player, etc)
      actor:determine_act()

      -- if (actor.blast_pos == nil) then TODO:blast_pos
      actor:pickup_prints()
      if (actor.blood_prints >= 1) actor:place_new_prints("blood_prints")
      -- end
    end
  end

  -- ensure actors don't try and occupy the same space as each other
  avoid = true
  while (avoid) do
    avoid = false
    for actor in all(global_objects.actor) do
      if (actor != player) then
        avoid = actor:do_avoidance() or avoid -- we need to redo avoids if any avoid is found.
      end
    end
  end

  turn += 1
  global_time = time()
  turn_start = time()

  update_frame() -- update frame here so we don't get a weird ghost drawing due to draw and update running independently
end

function end_turn()
  turn_start = nil
  global_time = time()

  for a in all(global_objects.actor) do
    if (a.blood_prints >= 1) a:redirect_existing_prints("blood_prints"); a.blood_prints -= 1
    a:tick_oxygen()
    if (a != player) a:attempt_act(1) -- attempt all moves for actors first
  end

  player:attempt_melee()
  player:attempt_act(1) -- we have to attempt the player's move last

  for a in all(global_objects.actor) do
    a:attempt_act(2) -- attempt all shots last
    a.act = {0, 0}
  end

  for o in all(global_objects.object) do
    o:activate()
  end
end

-- Input funcs
function btnpress(i)
  if i > 4 then
    input_act = i
    if (input_dir == 0) input_dir = player.facing
  else
    input_dir = i
    if (input_act < 5) input_act = 1
  end
end

function take_input()
  local immediate_input = { btn(2), btn(1), btn(3), btn(0), btn(4), btn(5) }

  for i=1,6 do
    if immediate_input[i] and not input_down[i] then
      input_down[i] = true
      btnpress(i)
    elseif not immediate_input[i] and input_down[i] then
      input_down[i] = false
      temp_act = input_act
      if (input_act == i or (input_dir == i and input_act == 1)) input_act = 0; return {temp_act, input_dir}
    end
  end

  return nil
end

function cut_chunk(c, v, m)
  return mid(1, flr(c / v) + 1, m)
end

function update_frame()
  chunk = flr((time() - global_time) * 1000 * game_speed)
  frame = cut_chunk(chunk, 250, 4)
  biframe = cut_chunk(chunk, 125, 8)

  if (frame != last_frame and chunk > 250) then
    roll_frame()
    last_frame = frame
  end
end

function roll_frame()
  for a in all(global_objects.actor) do
    if (a.laser.frames > 0) a.laser.frames -= 1
    if (a.frames.n > 0) a.frames.n -= 1
  end
end

---------------------------------------------
--- RELATING TO SECTION 3: draw functions ---
---------------------------------------------

function draw_set(draws)
  for o in all(draws) do
    o:draw_below()
  end

  for o in all(draws) do
    o:draw()
  end

  for o in all(draws) do
    o:draw_above()
  end
end

function draw_map()
  for y = levels[current_level][2], levels[current_level][4] - 1, 1 do
    for x = levels[current_level][1], levels[current_level][3] - 1, 1 do
      local v = make_vec2d(x, y)
      local pp = to_pixel(v)
      local tile = lmapget(v)
      if (tile > 0) zspr(tile, pp.x, pp.y)
    end
  end
end

-- concat tables
-- function concat(t1,t2)
--     local t3 = {}
--     for i=1,#t1 do
--         t3[i] = t1[i]
--     end
--     for i=1,#t2 do
--         t3[#t1+i] = t2[i]
--     end
--     return t3
-- end

-- sprite sheet n to vector position
function n_to_vec(n)
  return make_vec2d(8 * (n % 16), 8 * flr(n / 16))
end

-- zoomed sprite
function zspr(n, dx, dy, dz, w, h, ssw, ssh)
  local v = n_to_vec(n)
  w = w or 1
  h = h or 1
  ssw = ssw or 8
  ssh = ssh or 8
  dz = dz or 2
  sw, sh = ssw * w, ssh * h
  dw, dh = sw * dz, sh * dz
  sspr(v.x,v.y,sw,sh,dx,dy,dw,dh)
end

----------------------
--- OBJECT METHODS ---
----------------------

function make_trapdoor(t, mt)
  t.timer = false
  -- t.facing = 1 -- use facing instead of "active" for trapdoors to save tokens. 1 = set, 2 = open
  function mt.__index.activate(self)
    if (self.timer) self.timer = false; self.facing = 2; sfx(13)

    local actors = self.pos:actors_on_here()
    if (not actors) return

    for a in all(actors) do
      if (a.life > -2) then
        if (self.facing == 1) sfx(11); self.timer = true; return
        sfx(5); a:fall()
      end
    end
  end
end

-- function make_scanner(t, mt)
--   function mt.__index.activate(self)
--     if (not self:stepped_on()) return
--     self:unlock_adjacent_doors()
--   end
--
--   function mt.__index.stepped_on(self)
--     for a in all(global_objects.actor) do
--       if (a.pos == self.pos) return true
--     end
--     return false
--   end
--
--   function mt.__index.unlock_adjacent_doors(self)
--     for door in all(self.pos:adjacent_objects("door")) do
--       if (door.solid) sfx(16); door.solid = 0
--     end
--   end
--   function mt.__index.draw(self)
--   end
-- end

function make_door(t, mt)
  t.solid = 1
  function mt.__index.draw(self)
  end
  function mt.__index.draw_above(self)
    local p = to_pixel(self.pos)
    zspr(animations.objects.door[self.facing][(1 - self.solid) + 1], p.x, p.y)
  end
end

function default_sprite(pattern, facing)
  s = animations[pattern]
  if (not s) s = animations["objects"][pattern]
  if (not check_type(s, "table")) return s
  if (facing <= 0) return s[1]
  if (not check_type(s[facing], "table")) return s[facing]
  return s[facing][1]
end

function object_methods.sprite(self)
  return default_sprite(self.pattern, self.facing)
end

function object_methods.draw(self)
  local p = to_pixel(self.pos)
  zspr(self:sprite(), p.x, p.y)
end

-- TODO: refactor this draw_below stuff
function object_methods.draw_below(self)
  -- printh("Generic draw_below call!")
end

function object_methods.draw_above(self)
  -- printh("Generic draw_above call!")
end

function object_methods.activate(self)
  -- printh("Generic object!")
end

objectmt.__index = object_methods

---------------------
--- ACTOR METHODS ---
---------------------

function make_actor(pattern, pos, facing, life)
  local t = make_object(pattern, pos, facing)
  life = life or 1

  -- game data
  t.life, t.max_life, t.o2, t.max_o2 = life, life, life, life
  t.aquatic = false -- aquatic is whether water appears as floor or wall for the actor AI. Player is aquatic.
  t.variant = level_enemy_variants[current_level][enemy_count] -- TODO: get variant from level data array
  -- blood prints data
  t.blood_prints, t.stunned_turns = 0, 0
  -- laser data
  t.laser = { frames = 0, target = make_vec2d(0, 0), dir = 0, tiles = {} }
  -- frames data
  t.frames = { n = 0, pattern = "" }
  -- see input acts and directions
  t.act = {0, 0}
  -- player changes to the actormt
  mt = copymt(actormt)
  if (pattern == "player") make_player(t, mt)

  setmetatable(t, mt)
  return t
end

function make_player(t, mt)
  t.aquatic = true
  t.variant = 1
  function mt.__index.determine_act(self)
    self.act = copymt(self.input_act)
    self:turn_to_face_act()
  end
end

function actor_methods.act_pos(self)
  local a = self.act[1]
  local d = self.act[2]
  if (d == 0) return self.pos
  check_point = self.pos + dir_to_vec(d)

  if a == 1 then
    if (not check_point:is_wall() and (not check_point:is_water() or self.aquatic)) return check_point
  end

  return self.pos
end

function actor_methods.attempt_melee(self)
  if (self.life <= 0) return
  attack_point = self:act_pos()
  h = attack_point:actors_on_here("player")
  if (h) h[1].stunned_turns = 3; return
end

function actor_methods.tick_oxygen(self)
  if (self:in_water()) then
    if (self.o2 <= 0 and self.life > 0) self:hurt(1, true)
    if (self.o2 >= 1) self.o2 -= 1; sfx(12)
  else
    self.o2 = self.max_o2
  end
end

function actor_methods.in_water(self)
  return self.pos:is_water() and self:act_pos():is_water()
end

function actor_methods.turn_to_face_act(self)
  if (self.act[2] > 0) self.facing = self.act[2]
end

function actor_methods.move_type(self)
  return enemy_variants[self.pattern][self.variant][1]
end

function actor_methods.determine_act(self)
  -- wait out any stuns. TODO: move this so it affects player also. it's an early returner
  if (self.stunned_turns > 0) then
    self.stunned_turns -= 1
    if (self.stunned_turns > 0) return
    ha = self.pos:actors_on_here()
    if (ha and ha[1].life > 0 and ha[1] != self) self.stunned_turns = 1; return
  end

  -- save previous facing so we can prioritise shooting player over following prints
  previous_facing = self.facing

  -- follow footprints at first, if any.
  follow_prints = self.pos:objects_on_here("prints", "blood_prints")
  if (follow_prints) self.facing = follow_prints[1].facing

  -- initiate action
  self.act[1] = 1
  self.act[2] = self.facing
  -- run variant AI subroutine (whether we about face or circle clockwise; boss movement patterns etc.)
  self:determine_facing()

  -- if player is dead, no need to look
  if (player.life <= 0) return

  -- with old facing, look for player to shoot
  tiles = self:tiles_ahead(previous_facing, true)
  for k, tile in pairs(tiles) do
    if (player.pos == tile) then
      self.act = {2, previous_facing}  -- shoot
      self.facing = previous_facing
      sfx(10)
      return
    end
  end

  -- with new facing, look again
  tiles = self:tiles_ahead(self.facing, true)
  for k, tile in pairs(tiles) do
    if (player.pos == tile) then
      self.act[1] = 2 -- shoot
      sfx(10)
      return
    end
  end

  self:turn_to_face_act()
end

function actor_methods.determine_facing(self)
  mvt = self:move_type()
  apos = self:act_pos()
  if (mvt == "clockwise") then
    directions_tried = 0
    while apos == self.pos do
      self.facing += 1
      if (self.facing > 4) self.facing = 5 - self.facing
      self.act[2] = self.facing
      apos = self:act_pos()
      directions_tried += 1
      if (directions_tried > 4) self.stunned_turns = 3; return
    end
  end

  if (mvt == "still") self.act = {0, 0}; return

  if (mvt == "line") then
    if (apos == self.pos) then
      f = self.facing + 2
      if (f > 4) f = abs(5 - f) + 1
      self.act[2], self.facing = f, f
    end
  end
end

function actor_methods.do_avoidance(self)
  -- if (self.life <= 0) return
  -- if we are moving into a tile that someone else plans on moving into, only one should move there.
  new_pos = self:act_pos()
  -- if we arent moving, no need to avoid
  if (new_pos == self.pos) return

  for a in all(global_objects.actor) do
    if (a.life > 0) then
      apos = a:act_pos()

      -- TODO: maaaybe some enemy_variants should also dodge the player, so remove last clause for other AIs (this might not matter)
      if (a != self and apos == new_pos and a.pattern != "player") then
        self.act = {0, 0}
        return true -- return true if avoidance was done. if so, all actors need to redo avoidance.
      end
    end
  end

  return false
end

function actor_methods.pickup_prints(self)
  if (self.life <= 0) return

  for a in all(global_objects.actor) do
    if (a.life <= 0 and a.pos == self.pos) self.blood_prints = 5; return
  end
end

function actor_methods.place_new_prints(self, pattern)
  if (self.life <= 0 or self.pos:is_water() or self.pos:objects_on_here("trapdoor")) return

  p = self.pos:objects_on_here("prints", pattern)
  if (not p) then
    d = self.act[2]
    if (d <= 0) d = self.facing
    o = make_object(pattern, self.pos, d)
    add(global_objects.prints, o)
    add(global_objects.object, o)
  end
end

-- TODO: bit hacky way to ensure that some things happen in a certain order in determine_act
function actor_methods.attempt_act(self, act_type)
  a = self.act[1]
  if (a == 1 and act_type == 1) self:attempt_move()
  if (a == 2 and act_type == 2) self:attempt_shot()
end

function actor_methods.attempt_move(self)
  self.pos = self:act_pos()
end

-- determine who gets shot by what. It's important that the player is shot last.
function actor_methods.attempt_shot(self)
  sfx(4)

  tiles = {}
  for i, tile in pairs(self:tiles_ahead(self.act[2], true)) do
    hurts = {}
    add(tiles, tile)

    as = tile:actors_on_here()
    if (as) then
      for a in all(as) do
        if (a and self != a and a.life > 0) add(hurts, a)
      end
    end

    l = #hurts
    for a in all(hurts) do
      -- if the bullet could hit more than one person, hit the non-player. TODO: some bullets should go through all?
      if (l > 1) then
        if (a != player and a.life > 0) then
          a:hurt()
          self:queue_lasers(tiles, a)
          return
        end
      elseif (l == 1) then
        a:hurt()
        self:queue_lasers(tiles, a)
        return
      end
    end
  end
end

function actor_methods.redirect_existing_prints(self, pattern)
  if (self.life <= 0) return
  p = self.pos:objects_on_here("prints", pattern)
  if (self.act[2] > 0 and p[1].pattern == pattern) p[1].facing = self.act[2]
end

function actor_methods.set_frames(self, pattern, n)
  self.frames = { pattern = pattern, n = n }
end

function actor_methods.queue_lasers(self, tiles, a, d)
  d = d or self.act[2]
  self.laser = { frames = 2, target = a.pos, dir = d, tiles = {} }
  del(tiles, tiles[#tiles])
  self.laser.tiles = tiles
end

function actor_methods.hurt(self, amount, hide_anim)
  amount = amount or 1
  self.life = max(0, self.life - amount)
  if (self.life == 0) then
    sfx(5)
    if (not hide_anim) self:set_frames("death", 4)
    -- if (not is_water(actor.pos)) actor.death_frames = 4
  else
    sfx(5, -1, 1, 3)
    if (not hide_anim) self:set_frames("hurt", 2)
    -- if (not is_water(actor.pos)) actor.hurt_frames = 2
  end
end

function actor_methods.fall(self)
  self.life = -2
  self:set_frames("fall", 2)
end

function actor_methods.tiles_ahead(self, d, ignore_glass)
  ignore_glass = ignore_glass or false
  d = d or self.facing
  p = self.pos + dir_to_vec(d)

  collected = {}
  i = 1

  while not (p:is_wall() and (not p:is_glass() or not ignore_glass)) do
    collected[i] = p
    i += 1
    p = p + dir_to_vec(d)
  end

  return collected
end

function actor_methods.draw_sprite(self)
  local p = to_pixel(self.pos)
  local s = self:tile_shift()
  ssw, ssh, y_shift = 8, 8, 0
  if (self:in_water()) ssh = 4; y_shift = 2

  palswap = enemy_variants[self.pattern][self.variant][2]
  pal(palswap[1], palswap[2])
  -- printh("sprite:" ..self:sprite().." px "..p.x.." py "..p.y.." sx "..s.x.." sy "..s.y)
  zspr(self:sprite(), p.x + s.x * 2, p.y + s.y * 2 + y_shift, 2, 1, 1, ssw, ssh)
  pal(palswap[1], palswap[1])
end

function actor_methods.draw_below(self)
  if (self.life > 0) return
  self:draw_sprite()
end

function actor_methods.draw(self)
  if (self.life <= 0) return
  self:draw_sprite()
end

function actor_methods.draw_above(self)
  -- draw speculative lasers
  anim = animations[self.pattern][7]
  if (self.act[1] == 2) then
    d = self.act[2]
    s = anim[d]

    tiles = self:tiles_ahead(d, true)
    for tile in all(tiles) do
      t = to_pixel(tile)
      zspr(s, t.x, t.y)
    end
  end

  -- draw post-shot lasers
  l = self.laser
  s = anim[l.dir]

  if (l.frames > 0) then
    for tile in all(l.tiles) do
      if (l.frames == 1) pal(8,2); pal(11,3)
      t = to_pixel(tile)
      l_dir_mod = (l.dir+1) % 2
      zspr(s, t.x, t.y)
      zspr(s, t.x + l_dir_mod * 2, t.y + (1 - l_dir_mod) * 2)
      pal(8,8)
      pal(11,11)
    end
  end
end

function actor_methods.sprite(self)
  frames_n = self.frames.n
  pattern = self.pattern
  frames_pattern = self.frames.pattern

  if (frames_n > 0) then
    if (frames_pattern == "death") return animations[pattern][5][(4 - frames_n) + 1]
    if (frames_pattern == "hurt") return animations[pattern][5][(2 - frames_n) + 1]
    if (frames_pattern == "fall") return animations[pattern][6][(2 - frames_n) + 1]
  end

  if (self.life <= 0) then
    if (self.life == -2) return 255
    return animations[self.pattern][5][4]
  end

  if (self.stunned_turns > 0) return animations[pattern][8][(frame % 2) + 1]

  if (turn_start != nil) then
    anim = animations[pattern][self.facing]
    if (self.act[1] == 1) return anim[frame+1]
    if (self.act[1] == 2) return anim[6]
  end

  return default_sprite(pattern, self.facing)
end

function actor_methods.tile_shift(self)
  apos = self:act_pos()
  if (not (apos == self.pos) and turn_start) return make_vec2d((apos.x - self.pos.x) * biframe, (apos.y - self.pos.y) * biframe)
  return make_vec2d(0, 0)
end

actormt.__index = actor_methods

----------------------
--- VECTOR METHODS ---
----------------------

-- for converting a direction to a position change
pos_map = {{0,1,0,-1}, {-1,0,1,0}}

function dir_to_vec(dr)
  return make_vec2d(pos_map[1][dr], pos_map[2][dr])
end

-- function to create a new vector
function make_vec2d(x, y)
    local t = {
        x = x,
        y = y
    }

    setmetatable(t, vecmt)
    return t
end

-- function vector_methods.debug_print(self, msg)
--   printh(msg.." ("..self.x..", "..self.y..")")
-- end

-- function vector_methods.is_adjacent(self, pos)
--   return ((self.x == pos.x + 1 and self.y == pos.y) or
--     (self.x == pos.x - 1 and self.y == pos.y) or
--     (self.x == pos.x and self.y == pos.y + 1) or
--     (self.x == pos.x and self.y == pos.y - 1))
-- end

function get_global_objects(pattern, subpattern)
  pattern = pattern or "object"
  subpattern = subpattern or pattern
  local objects = {}
  for o in all(global_objects[pattern]) do
    if (o.pattern == subpattern) add(objects, o)
  end
  return objects
end

function vector_methods.objects_on_here(self, pattern, subpattern)
  local objects, on_here = get_global_objects(pattern, subpattern), {}
  for o in all(objects) do
    if (o.pos == self) add(on_here, o)
  end
  if (#on_here > 0) return on_here
  return nil
end

function vector_methods.actors_on_here(self, exclude_pattern)
  exclude_pattern = exclude_pattern or ""
  local actors = {}
  for a in all(global_objects.actor) do
    if (a.pos == self and a.pattern != exclude_pattern) add(actors, a)
  end
  if (#actors > 0) return actors
  return nil
end

-- function vector_methods.adjacent_objects(self, pattern)
--   pattern = pattern or "object"
--   local os = {}
--   for o in all(objects) do
--     if (o.pattern == pattern and self:is_adjacent(o.pos)) add(os, o)
--   end
--   return os
-- end

-- no more than one "prints" can appear at once per tile

function vector_methods.is_glass(self)
  m = lmapget(self)
  return (m == 119 or m == 120)
end

function vector_methods.is_wall(self)
  a = self:objects_on_here("door")
  if (a and a[1].solid == 1) return true
  m = lmapget(self)
  return (m >= 64 and m <= 127)
end

function vector_methods.is_water(pos)
  return lmapget(pos) == 182
end

function vecmt.__add(a, b)
    return make_vec2d(
        a.x + b.x,
        a.y + b.y
    )
end

function vecmt.__sub(a, b)
    return make_vec2d(
        a.x - b.x,
        a.y - b.y
    )
end

function vecmt.__eq(a, b)
    return a.x == b.x and a.y == b.y
end

vecmt.__index = vector_methods

-----------------------
--- UI DRAW METHODS ---
-----------------------
function draw_bar(label, current, full, full_color, empty_color, position)
  barp = position * 10
  rect(2, 2 + barp, full * 5 + 3, 7 + barp, 6)
  rectfill(3, 3 + barp, full * 5 + 2, 6 + barp, empty_color)
  if (current > 0) rectfill(3, 3 + barp, current * 5 + 2, 6 + barp, full_color)
  print(label, 4, 6 + barp, 7)
end

--- MISC FUNCTIONS ---
function check_type(v, t)
  return type(v) == t
end

-- convert vector to screen pixel
function to_pixel(vec)
  return make_vec2d(vec.x * 16, vec.y * 16)
end

-- metatable copy method
function copymt(o)
  local c
  if type(o) == 'table' then
    c = {}
    for k, v in pairs(o) do
      c[k] = copymt(v)
    end
  else
    c = o
  end
  return c
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
00000000000000000000000000000000000001008000000008000000000000000000000000000000000000000000000000000000000000001010101020202020
00555500000000000005555005555000000555100e055500000e0800000000000022220000000000000000000000000000000000000000000001000100020002
05555500005555000055555055555000005855508883115000808e80000000000222220000000000000000000000000000000000000000001000100020002000
02f3f30005555500002f3f302f3f3000003f3f200e8ef350100388550000000002f8f80000000000000000000000000000000000000000000101010102020202
05ffff0002f3f300000ffff00fff55600888fff01888f520108e8f55000388e502ffff0000000000000000000000000000000000000000001010101020202020
00111000001fff0000f11f000111f5000081110005811080051ff32580e883880033000000000000000000000000000000000000000000000001000100020002
0f555f0000111f0000155000055500000f0551008058000805111e801188ff850f66f00000000000000000000000000000000000000000001000100020002000
0010100000f110000000010001010000000001000011000000f110e811f882500010100000000000000000000000000000000000000000000101010102020202
00000000000000000000000000006000007060007800000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00555000000000000055500000055500070555000555500000555000000555500000000000000000000000000000000000000000000000000000000000000000
05555500000555000555550000555550705555505555507005555570070555550000000000000000000000000000000000000000000000000000000000000000
05555200005555500555520000555520705555202f3f3007023f35077003f3f20000000000000000000000000000000000000000000000000000000000000000
00fff000005555200ffff00000f555f000f555000ffff00705fff107700ffff00000000000000000000000000000000000000000000000000000000000000000
001110000001110000511000001111f0001111f001111f55011ff66055f111100000000000000000000000000000000000000000000000000000000000000000
0f555f00000555f00015500000055500000555000555000000555000000055500000000000000000000000000000000000000000000000000000000000000000
0010100000f1110000100f0000010100000101000101000000101000000010100000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0055550000000000005555000055500000a90a0000a09a0000000000000000000000000000000000000000000000000000000000000000000000000000000000
05555550005555000555555005555500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
02f3f3500555555002f3f350023f3500000f3550000f355000000000000000000000000000000000000000000000000000000000000000000000000000000000
00ffff0002f3f3500fffff00056ff10000fff55000fff55000555500000000000000000000000000000000000000000000000000000000000000000000000000
00111000001fff000011110000f11100051f3550051f3550055f550f00000f000000000000000000000000000000000000000000000000000000000000000000
0f555f0000111f00001550f000555000151ff550151ff55002f5f305000005000000000000000000000000000000000000000000000000000000000000000000
0010100000f51000001000000010100011f0250011f0250005f5ff05000005000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00555500000000000555500000055550000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00555550005555000555550000055555000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
003f3f200055555003f3f2000003f3f2000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00ffff00003f3f200ffff0000655fff0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
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
ffffffffffffffff000000000000000000000000000000000000000000000000000000000000ff0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
ffffffffffffff00000000000000000000000000000000000000000000000000000000000000ff0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
ffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
ffffffffff005465544154546500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00ffff656554b6b5b550b0b5b564000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000075b5b654b6b58471b5540154000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000ff65b6b6b654b0b5b054845400000000000000000000000000000000000000ffffff0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000064545464655454c0b5b5650000000000000000000000000000000000ffffffffff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000ff406174e0544542b070546400000000000000000000000000000000ffffffffff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000ff50b5b5b5b5c077b577f065ffffffffffffffffff645464ffff0000ffffffffff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000ff50b570b570b571b55065ffff546464655476656454b95464ff0000ffffffffff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000405282514673b5b5b550ffff6470b5765454b570c0b5b5f054650000ffffffffff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000050b5b5718463464646730064c077b5b5f0b5b550b05454b047b65400ff0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
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
00100000160401f0303b7000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00050000376403c65037660336602f6502b640246301e630126200e6100a610086100c60005600206000c600046001f6001660010600000000000000000000000000000000000000000000000000000000000000
000a00000114001060010000b600056000b60011f0011f0011f0011f0011f0011f0011f0011f0011f0011f0011f00000000000000000000000000000000000000000000000000000000000000000000000000000
00060000097201d0000c0000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00040000147401e7401e7301e7201e7101e7001f7001f700207001e70000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000800000a1100b1200b1200110001100077000550005500045000350002500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000800001a730167401a7000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000c00000711006110071100611000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0008000025710277202c7303173031710000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000800002151024520265202651000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00080000267300a7102d7202d7200a710000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000800000d740017200d7400d74001720000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0008000027550295502b5502e55032550335503254033530325203351000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__music__
00 01024344
