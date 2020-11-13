-- big TODO: --
-- no more red scanner green scanner. there is only keydoors and multidoors.
-- get rid of meaningful keys so that minification works
-- maybe a big puzzle room for the gloves
-- reimplementing doors, rations, player items, relays, explosives
-- Codec & Dialogue
-- Main menu
-- Sfx overhaul
-- Music

-- facing guide: 0=none, 1=up, 2=right, 3=down, 4=left
-- act guide:    0=still, 1=walk, 2=shoot, 3=change, 4=blast, 5=vault, 6=nil, 7=nil

------------------------------------
--- global level and sprite data ---
------------------------------------

-- some global handles for commonly used sprites
sprite_store = { floor = 181,
                 void = 255,
                 select = 46 }

-- global object sprite-on-map store
--        -> pattern  -> subpattern -> sprite #s
map_store = { actor    = { player        = {17, 1, 33, 49},
                           enemy         = {208, 192, 224, 240} },
              door     = { door          = {67, 68},
                           keydoor       = {104, 105} },
              scanner  = { red_scanner   =  131,
                           green_scanner =  134 },
              item     = { ration        =  180,
                           keycard       =  185 },
              object   = { trapdoor      =  176,
                           relay         =  132 }}

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

                 door = {{67, 129}, {68, 130}},
              keydoor = {{104, 160}, {105, 161}},
         blood_prints =  {26, 27, 28, 29},
             trapdoor =  {176, 177},
          red_scanner =  {131, 134},
        green_scanner =  {134, 134},
                relay =  {132, 186},
               ration =   180,
              keycard =   185 }

-- enemy variants data
enemy_variants = {player = {{"player", {5, 5}}},
                  enemy = {{"clockwise", {5, 13}}, -- variant 1
                           {"line", {5, 2}}, -- variant 2
                           {"still", {5, 5}} }}  -- variant 3

checkpoint_inventory = { keycard_level = 0 }
inventory = {}

-- misc global vars
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
level_keydoors = {{1,2,3}}
level_enemy_variants = {{2, 2, 3,3, 2,2, 3,2, 1,2,2, 1, 2,1,3, 3,3, 1, 1,2,2,3, 3,3, 3,1,3,2, 1, 3, 3,1, 1}}

current_level = 0 -- don't touch, change param of load_level instead
-- TODO: refactor above vars into level class?
game_speed = 2.5 -- edit me!

--- types to hold classes ---
local actormt = {}
local objectmt = {}
local vecmt = {}

local make_methods = {}
local object_methods = {}
local actor_methods = {}
local vector_methods = {}

--- / inter-level storage globals ----
--------------------------------------
--- checkpoint storage globals ---
player = nil

-- store global objects ALWAYS PATTERN TODO: we should probably clone and empty out map_store for this.
global_objects = { actor = {},   -- includes player and enemy patterns
                   object = {},  -- includes all of the following:

                   -- the following are all "objects"
                   relay = {},    -- relay should be own item?
                   door = {},     -- includes doors, keydoors and multilock doors.
                   scanner = {},
                   trapdoor = {},
                   prints = {},   -- includes "blood_prints" and "snow_prints" patterns?
                   item = {}}     -- ration, keycard, equipment (TODO: unimplemented)

global_object_counts = {}
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
  if (not player) return

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
  draw_set(concat(global_objects.actor, player))

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
  -- draw other ui bits
  if (inventory.keycard_level > 0) draw_keycard_ui()
  if (player.blood_prints > 0) draw_blood_ui()
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
  inventory = copymt(checkpoint_inventory)
  global_object_counts = {}

  enemy_count, keydoor_count = 0, 0 -- these are items with additional level data and have to be counted!
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
        lmapset(v, l, extract_object_from_map(v, o))
      end
    end
  end
end

-- extract_object_from_map makes objects ready to start the level from what's on the pico8 map.
-- it returns the code to replace it with on the map.
-- o is passed from get_tile_pattern
function extract_object_from_map(pos, opts)
  -- make_PATTERN(PATTERN, SUBPATTERN, POSITION FACING_OR_SPRITENUM)
  -- make_PATTERN splits INSIDE (so we don't have to replicate setmetatable calls in each subpattern make)
  -- so inside make_PATTERN we need to do make_SUBPATTERN.
  local object = {}
  -- printh("making " .. opts[1] .. " of type " .. opts[2])
  if (opts[1] == "actor") then
    object = make_actor(pos, opts)
    add(global_objects.actor, object)
  else
    object = make_object(pos, opts)
    if (opts[1] == "object") then
      add(global_objects[opts[2]], object)
    else
      add(global_objects[opts[1]], object)
    end

    if (opts[2] == "trapdoor" or opts[1] == "door") return sprite_store.void
  end

  return sprite_store.floor
end

-- opts = {pattern, subpattern, position, facing}
function make_object(pos, opts, skip_submatch)
  local t = {
    pattern = opts[1],
    subpattern = opts[2],
    pos = make_vec2d(pos.x, pos.y),
    facing = opts[3] or 1,
  }

  mt = copymt(objectmt)
  mk = "make_"..t.subpattern
  printh(mk)
  mmm = make_methods[mk]
  if (not skip_submatch) mmm(t, mt); add(global_objects.object, t)
  setmetatable(t, mt)

  if (not global_object_counts[t.subpattern]) global_object_counts[t.subpattern] = 0
  global_object_counts[t.subpattern] += 1
  return t
end

function make_actor(pos, opts)
  local t = make_object(pos, opts, true)

  -- game data
  t.life, t.max_life = 1, 1
  t.aquatic = false -- aquatic is whether water appears as floor or wall for the actor AI. Player is aquatic.
  t.variant = level_enemy_variants[current_level][global_object_counts[t.subpattern]] -- TODO: get variant from level data array
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
  if (opts[2] == "player") make_methods.make_player(t, mt)

  setmetatable(t, mt)
  return t
end

function make_methods.make_player(t, mt)
  t.aquatic = true
  t.variant = 1
  life = 3
  t.life, t.max_life, t.o2, t.max_o2 = life, life, life, life

  function mt.__index.determine_act(self)
    self.act = copymt(self.input_act)
    self:turn_to_face_act()
  end

  player = t
end

-- generic -- only subpattern items (keycards, rations) are made, which call this.
function make_item(t, mt)
  function mt.__index.activate(self)
    if (self.pos == player.pos) self:pick_up(); del(global_objects.item, self); del(global_objects.object, self)
  end

  function mt.__index.pick_up(self)

  end

  function mt.__index.draw(self)
    local p = to_pixel(self.pos)
    local shift = abs(biframe - 4) - 3
    if (not turn_start) shift = 3
    zspr(self:sprite(), p.x, p.y - shift)
  end
end

function make_methods.make_door(t, mt)
  t.solid = 1
  function mt.__index.draw(self)
  end
  function mt.__index.draw_above(self)
    local p = to_pixel(self.pos)
    zspr(animations[t.subpattern][t.facing][(1 - t.solid) + 1], p.x, p.y)
  end
end

function make_methods.make_keydoor(t, mt)
  make_methods.make_door(t, mt)
  t.key_level = level_keydoors[current_level][global_object_counts[t.subpattern]]
end

function make_methods.make_relay(t, mt)
end

function make_methods.make_red_scanner(t, mt)
end

function make_methods.make_green_scanner(t, mt)
end

function make_methods.make_keycard(t, mt)
  make_item(t, mt)
  function mt.__index.pick_up(self)
    inventory.keycard_level += 1
    sfx(14)
  end
end

function make_methods.make_ration(t, mt)
  make_item(t, mt)
  function mt.__index.pick_up(self)
    player.life = player.max_life
    sfx(15)
  end
end

function make_methods.make_trapdoor(t, mt)
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
-- get_tile_pattern returns a more detailed object to make a tile out of,
-- or nil if there is nothing to make here.
-- the returned object is passed to make_object_from_map
function get_tile_pattern(tile)
  for pattern, subpatobj in pairs(map_store) do
    for subpattern, tileobj in pairs(subpatobj) do
      if not check_type(tileobj, "table") then
        if (tileobj == tile) return {pattern, subpattern, 1} -- return facing
      else
        for f, i in pairs(tileobj) do
          if (i == tile) return {pattern, subpattern, f} -- return facing
        end
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
  local avoid = true
  while (avoid) do
    avoid = false
    for actor in all(global_objects.actor) do
      if (actor != player and actor.life > 0) then
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

-- second-order layering (corpses underneath actors, prints underneath objects, etc) TODO: refactor?
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

-- draw ui bar
function draw_bar(label, current, full, full_color, empty_color, position)
  barp = position * 10
  rect(2, 2 + barp, full * 5 + 3, 7 + barp, 6)
  rectfill(3, 3 + barp, full * 5 + 2, 6 + barp, empty_color)
  if (current > 0) rectfill(3, 3 + barp, current * 5 + 2, 6 + barp, full_color)
  print(label, 4, 6 + barp, 7)
end

function draw_blood_ui()
  spr(143, 112, 3)
  print(player.blood_prints, 121, 4, 7)
end

function draw_keycard_ui()
  spr(185, 85, 3)
  print("lv."..inventory.keycard_level, 93, 4, 7)
end


----------------------
--- OBJECT METHODS ---
----------------------

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

function default_sprite(subpattern, index)
  s = animations[subpattern]
  if (not check_type(s, "table")) return s

  if (index <= 0 or not index) return s[1]
  if (not check_type(s[index], "table")) return s[index]

  return s[index][1]
end

function object_methods.sprite(self)
  return default_sprite(self.subpattern, self.facing)
end

function object_methods.draw(self)
  local p = to_pixel(self.pos)
  zspr(self:sprite(), p.x, p.y)
end

-- TODO: refactor this draw_below stuff
function object_methods.draw_below(self)
end

function object_methods.draw_above(self)
end

function object_methods.activate(self)
end

objectmt.__index = object_methods

---------------------
--- ACTOR METHODS ---
---------------------

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
  return enemy_variants[self.subpattern][self.variant][1]
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
      f = self.facing + 1
      if (f > 4) f = 5 - f
      self.act[2], self.facing = f, f
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
  local new_pos = self:act_pos()
  -- if we arent moving, no need to avoid

  for a in all(global_objects.actor) do
    if (a.life > 0) then
      apos = a:act_pos()

      -- TODO: maaaybe some enemy_variants should also dodge the player, so remove last clause for other AIs (this might not matter)
      if (a != self and apos == new_pos and a.subpattern != "player") then
        self.act = {0, 0}
        return true -- return true if avoidance was done. if so, all actors need to redo avoidance.
      end
    end
  end

  return false
end

function actor_methods.pickup_prints(self)
  for a in all(global_objects.actor) do
    if (a.life <= 0 and a.pos == self.pos) self.blood_prints = 6; return
  end
end

function actor_methods.place_new_prints(self, subpattern)
  if (self.life <= 0 or self.pos:is_water() or self.pos:objects_on_here(nil, "trapdoor")) return
  p = self.pos:objects_on_here("prints", subpattern)

  if (not p) then
    d = self.act[2]
    if (d <= 0) d = self.facing
    o = make_object(self.pos, {"prints", subpattern, d}, true)
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

function actor_methods.redirect_existing_prints(self, subpattern)
  if (self.life <= 0) return
  p = self.pos:objects_on_here("prints", subpattern)
  if (not p) return
  -- if (self.act[2] > 0 and p[1].subpattern == pattern) p[1].facing = self.act[2]
  if (self.act[2] > 0) p[1].facing = self.act[2]
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

  palswap = enemy_variants[self.subpattern][self.variant][2]
  pal(palswap[1], palswap[2])
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
  anim = animations[self.subpattern][7]
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
  pattern = self.subpattern
  frames_pattern = self.frames.pattern

  if (frames_n > 0) then
    if (frames_pattern == "death") return animations[pattern][5][(4 - frames_n) + 1]
    if (frames_pattern == "hurt") return animations[pattern][5][(2 - frames_n) + 1]
    if (frames_pattern == "fall") return animations[pattern][6][(2 - frames_n) + 1]
  end

  if (self.life <= 0) then
    if (self.life == -2) return 255
    return animations[pattern][5][4]
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
  pattern = pattern or subpattern

  local objects = {}
  for o in all(global_objects[pattern]) do
    if ((o.subpattern == subpattern) or not subpattern) add(objects, o)
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
    if (a.pos == self and a.subpattern != exclude_pattern) add(actors, a)
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

--- MISC FUNCTIONS ---
function check_type(v, t)
  return type(v) == t
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

-- concat tables
function concat(t1,t2)
    local t3 = {}
    for i=1,#t1 do
        t3[i] = t1[i]
    end
    for i=1,#t2 do
        t3[#t1+i] = t2[i]
    end
    return t3
end

-- convert vector to screen pixel
function to_pixel(vec)
  return make_vec2d(vec.x * 16, vec.y * 16)
end

-- sprite sheet n to vector position
function n_to_vec(n)
  return make_vec2d(8 * (n % 16), 8 * flr(n / 16))
end

function dump(o)
   if type(o) == 'table' then
      local s = '{ '
      for k,v in pairs(o) do
         if type(k) ~= 'number' then k = '"'..k..'"' end
         s = s .. '['..k..'] = ' .. dump(v) .. ','
      end
      return s .. '} '
   else
      return tostring(o)
   end
end
