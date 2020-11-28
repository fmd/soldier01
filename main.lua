-- sprite_store = { floor = 181,
--                  void = 255,
--                  select = 46,
--                  choose = 30,
--                  bad = 15,
--                  vault = 31 }

-- map_store = { actor_player    = {17, 1, 33, 49},
--               actor_enemy     = {208, 192, 224, 240},
--               door_multidoor  = {88, 89},
--               door_keydoor    = {104, 105},
--               item_ration     =  180,
--               item_keycard    =  185,
--               item_equip      =  133,
--               object_trapdoor =  176,
--               object_relay    =  132,
--               object_multikey =  136 }

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

raw_sprite_store = "floor=181|void=255|select=46|choose=30|bad=15|vault=31"
raw_map_store = "actor_player=17,1,33,49|actor_enemy=208,192,224,240|door_multidoor=88,89|door_keydoor=104,105|item_ration=180|item_keycard=185|item_equip=133|object_trapdoor=176|object_relay=132|object_multikey=136"
raw_animations = "player=17,18,19,18,21,23,22,20:1,2,3,2,5,7,6,4:33,34,35,34,37,39,38,36:49,50,51,50,53,55,55,52:8,9,10,11:12,13:25,24,25,24|enemy=208,209,210,209,210,211,211,1:192,193,194,193,194,195,195,1:224,225,226,225,226,227,227,1:240,241,242,241,242,243,243,1:196,197,198,199:230,231:41,40,41,40:228,229|door=67,129:68,130|keydoor=104,160:105,161|multidoor=88,144:89,145|multikey=136,137|blood_prints=26,27,28,29|trapdoor=176,177|relay=132,186|ration=180|equip=133|keycard=185"
raw_global_objects = "actor=nil|object=nil|relay=nil|door=nil|trapdoor=nil|prints=nil|item=nil|multikey=nil"
--

function unmarshal_store(raw_store)
  local store = {}
  elements = split(raw_store, "|")
  for e in all(elements) do
    split_elements = split(e, "=")
    key,value = split_elements[1], split_elements[2]
    if split_elements[2] == "nil" then
      store[key] = {}
    else
      split_values = split(value, ":")
      store[key] = {}
      for s in all(split_values) do
        split_commas = split(s)
        local store_key = {}
        if #split_commas == 1 then
          add(store_key, split_commas[1])
        else
          add(store_key, split_commas)
        end

        if #store_key == 1 then
          store_key = store_key[1]
        end

         add(store[key], store_key)
      end

      if #store[key] == 1 then
        store[key] = store[key][1]
      end
    end
  end

  return store
end
-- --
sprite_store = unmarshal_store(raw_sprite_store)
map_store = unmarshal_store(raw_map_store)
animations = unmarshal_store(raw_animations)

-- animations = { player = {{17,18,19,18,21,23,22,20},
--                          {1,2,3,2,5,7,6,4},
--                          {33,34,35,34,37,39,38,36},
--                          {49,50,51,50,53,55,55,52},
--                          {8,9,10,11},
--                          {12,13},
--                          {25,24,25,24}},
--
--                 enemy = {{208,209,210,209,210,211,211,1},
--                          {192,193,194,193,194,195,195,1},
--                          {224,225,226,225,226,227,227,1},
--                          {240,241,242,241,242,243,243,1},
--                          {196,197,198,199},
--                          {230, 231},
--                          {41, 40, 41, 40},
--                          {228, 229}},
--
--                  door = {{67, 129}, {68, 130}},
--               keydoor = {{104, 160}, {105, 161}},
--             multidoor = {{88, 144}, {89, 145}},
--              multikey =  {136, 137},
--          blood_prints =  {26, 27, 28, 29},
--              trapdoor =  {176, 177},
--                 relay =  {132, 186},
--                ration =   180,
--                 equip =   133,
--               keycard =   185 }

enemy_variants = {player = {{"player", {5, 5}}},
                  enemy = {{"clockwise", {5, 13}},
                           {"line", {5, 2}},
                           {"still", {5, 5}},
                           {"cc", {5, 6}} }}

levels = {{0,0,36,30}}
level_items = {{"diving_suit", "gloves"}}
level_keydoors = {{2,1,1,2,2}}
level_multidoors = {{ {{11,18}}, {{23,24}, {25,27}} }} -- positions
level_enemy_variants = {{2, 2, 3,3,3,3, 2,4, 3,2, 1,4, 1, 1,3, 2, 1, 2,2,3, 3, 3,2, 1, 3, 1, 3,1, 1}}

turn, chunk, frame, biframe, last_frame = 0,0,1,1,0
global_time, turn_start = nil, nil
input_act, input_dir, input_down = 0, 0, {false,false,false,false,false,false}
last_camera_pos = { x = 0, y = 0 }
queued_input = nil

level_loaded = false
current_level = 0
game_speed = 2.5 -- edit me!

local actormt = {}
local objectmt = {}
local vecmt = {}

local make_methods = {}
local object_methods = {}
local actor_methods = {}
local vector_methods = {}


function reset_global_objects()
   global_objects = unmarshal_store(raw_global_objects)
   -- printh("------ globob ------")
   -- printh(dump(global_objects))
   inventory = {}
   global_object_counts = {}
   queued_input = nil
end


mset_restore = {}
checkpoint = { active_relays = {},
               inventory = { keycard_level = 0,
                             gloves = false,
                             diving_suit = false,
                             socom = false } }


function _init()
  load_level(1)
end

function _update60()
  if not level_loaded or not player then return end

  local new_input = take_input()
  if new_input and new_input[1] > 1 and player.life <= 0 then load_level(current_level); return end -- TODO: Refactor this crappy restart end
  if new_input and not queued_input then queued_input = new_input end

  update_frame()

  if turn_start then
    if chunk > 999 then end_turn() end
    return
  end

  if player.life > 0 then
    if queued_input and queued_input[1] > 4 then
      queued_input[1] = queued_input[1] - 3
    end

    player.input_act = queued_input
    queued_input = nil
    if not player.input_act then return end

    player:determine_act()
    if player:act_pos() == player.pos and player.input_act[1] == 1 then return end
    start_turn(); player.input_act = nil
  end

  if not turn_start and chunk > 499 then start_turn() end -- allow a little "thinking" time if player is dead
end

------------------------------------------------------
--- SECTION 3: draw cycle deals with camera and UI ---
------------------------------------------------------
function _draw()
  cls()

  if not level_loaded or not player then return end
  local p = to_pixel(player.pos)

  -- center camera
  buffer = make_vec2d(0,0)
  if p ~= last_camera_pos then -- player has new pos, we transition
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

  -- -- TODO: refactor how we display the movement indicator to reduce tokens

  local v = make_vec2d(player.pos.x, player.pos.y)
  local marker = sprite_store.select

  local bad_act = false
  local player_act = player.act
  if player_act and player_act[1] == 1 then
    local p = v + dir_to_vec(player_act[2])
    if p:is_vault_gate() and inventory.gloves then p = p + dir_to_vec(player_act[2]) end
    if p:is_wall() then bad_act = true end
    if not bad_act then v = p end
  end

  if queued_input and queued_input[1] == 1 then
    local p = v + dir_to_vec(queued_input[2])
    if p:is_vault_gate() and inventory.gloves then p = p + dir_to_vec(queued_input[2]) end
    if p:is_wall() then bad_act = true end
    if not bad_act then v = p end
  end
  --
  local ui = to_pixel(v)

  bad_act = false
  if v ~= player.pos then zspr(marker, ui.x, ui.y) end

  if input_act == 1 and not queued_input then
    marker = sprite_store.select
    local vault_act = false

    local p = dir_to_vec(input_dir) + v
    if p:is_wall() then bad_act = true end
    if p:is_vault_gate() and inventory.gloves then bad_act = false; vault_act = true end
    local ui = to_pixel(p)

    marker = sprite_store.choose
    if bad_act then marker = sprite_store.bad end
    if vault_act then marker = sprite_store.vault end
    zspr(marker, ui.x, ui.y)
  end

  if input_act == 5 then zspr(57, p.x + 4, p.y - 7, 1) end
  if input_act == 6 then zspr(56, p.x + 4, p.y - 7, 1) end

  camera(0,0)

  draw_bar("life", player.life, player.max_life, 3, 2, 0)
  if player:in_water() then draw_bar("o2", player.o2, player.max_o2, 12, 1, 1) end
  if inventory.keycard_level > 0 then draw_keycard_ui() end
  if player.blood_prints > 0 then draw_blood_ui() end
  rectcolor = 3
  if turn_start ~= nil then rectcolor = 5 end
  rect(0,0,127,127,rectcolor)
end

-- load a level.
function load_level(l)
  level_loaded = false

  reset_global_objects()
  player = nil

  inventory = copymt(checkpoint.inventory)
  global_time = time()

  restore_msets(current_level)
  current_level = l

  for y = 0, levels[l][4] - 1, 1 do
    for x = 0, levels[l][3] - 1, 1 do
      local v = make_vec2d(x, y)
      local t = lmapget(v, l)
      local o = get_tile_pattern(t)
      if o then
        add(mset_restore, {v, t})
        lmapset(v, l, extract_object_from_map(v, o))
      end
    end
  end

  c = checkpoint.current_relay
  if c then local a = make_actor(make_vec2d(c.x, c.y), {"actor", "player", 2}); add(global_objects.actor, a); player = a end

  level_loaded = true
end

function extract_object_from_map(pos, opts)
  local object = {}
  if opts[1] == "actor" then
    if opts[2] ~= "player" or not checkpoint.current_relay then
      object = make_actor(pos, opts)
      add(global_objects.actor, object)
      if opts[2] == "player" then player = object end
    end
  else
    object = make_object(pos, opts)
    if opts[1] == "object" then
      add(global_objects[opts[2]], object)
    else
      add(global_objects[opts[1]], object)
    end

    if opts[2] == "trapdoor" or opts[1] == "door" then return sprite_store.void end
  end

  return sprite_store.floor
end

function make_object(pos, opts, skip_submatch)
  local t = {
    pattern = opts[1],
    subpattern = opts[2],
    pos = make_vec2d(pos.x, pos.y),
    facing = opts[3] or 1,
  }

  mt = copymt(objectmt)
  mk = "make_"..t.subpattern

  if not global_object_counts[t.subpattern] then global_object_counts[t.subpattern] = 0 end
  global_object_counts[t.subpattern] = global_object_counts[t.subpattern] + 1

  mmm = make_methods[mk]
  if not skip_submatch then mmm(t, mt); add(global_objects.object, t) end
  setmetatable(t, mt)
  return t
end

function make_actor(pos, opts)
  local t = make_object(pos, opts, true)

  -- game data
  t.life, t.max_life = 1, 1
  t.aquatic = false
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
  local mt = copymt(actormt)
  if opts[2] == "player" then make_methods.make_player(t, mt) end

  setmetatable(t, mt)
  return t
end

function make_methods.make_player(t, mt)
  t.aquatic = true
  t.variant = 1
  t.life, t.max_life = 3, 3 -- TODO: bosses raise your health
  local o2 = 3
  if inventory.diving_suit then o2 = 6 end
  t.o2, t.max_o2 = o2, o2

  function mt.__index.determine_act(self)
    self.act = copymt(self.input_act)
    self:turn_to_face_act()
  end

  -- TODO: generic this out for vaulting enemies?
  function mt.__index.act_pos(self)
    local act_pos = actor_methods.act_pos(self)
    if not inventory.gloves or not (self.act[2] > 0) then return act_pos end
    local d = dir_to_vec(self.act[2])

    if (d + self.pos):is_vault_gate() and self.act[1] == 1 then
      local vault_pos = d + d + self.pos
      if vault_pos:is_wall() then return make_vec2d(self.pos.x,self.pos.y) end
      return vault_pos
    end

    return act_pos
  end
end

-- generic -- only subpattern items (keycards, rations) are made, which call this.
function make_item(t, mt)
  function mt.__index.activate(self)
    if self.pos == player.pos then self:pick_up(); del(global_objects.item, self); del(global_objects.object, self) end
  end

  function mt.__index.pick_up(self)

  end

  function mt.__index.draw(self)
    local p = to_pixel(self.pos)
    local shift = abs(biframe - 4) - 3
    if not turn_start then shift = 3 end
    zspr(self:sprite(), p.x, p.y - shift)
  end
end

function make_methods.make_door(t, mt)
  t.solid = 1
  function mt.__index.draw(self)
  end
  function mt.__index.draw_above(self)
    local p = to_pixel(self.pos)
    zspr(animations[self.subpattern][self.facing][(1 - self.solid) + 1], p.x, p.y)
  end
end

function make_methods.make_multidoor(t, mt)
  t.scanner_positions = level_multidoors[current_level][global_object_counts["multidoor"]]
  make_methods.make_door(t, mt)
  function mt.__index.activate(self)
    if self.solid == 0 then return end
    local open = true
    for p in all(self.scanner_positions) do
      local s = make_vec2d(p[1], p[2])
      local o = s:objects_on_here(nil,"multikey")[1]
      if not o or o.activated ~= 1 then open = false end
    end

    if open then self.solid = 0; sfx(16) end
  end
end

function make_methods.make_keydoor(t, mt)
  t.keycard_level = level_keydoors[current_level][global_object_counts["keydoor"]]
  make_methods.make_door(t, mt)
  function mt.__index.activate(self)
    if self.solid == 0 then return end -- TODO: fix object data to save tokens here
    if self.pos:is_adjacent(player.pos) then
      if inventory.keycard_level >= self.keycard_level then
        sfx(16)
        self.solid = 0
      else
        sfx(17)
      end
    end
  end
end

function make_methods.make_relay(t, mt)
  t.active = 0
  for p in all(checkpoint.active_relays) do
    if t.pos == p then
      t.active = 1
    end
  end

  local c = checkpoint.current_relay

  function mt.__index.activate(self)
    if player.life <= 0 or player.pos ~= self.pos or self.active ~= 0 then return end
      sfx(18)
      self.active = 1

      v = make_vec2d(self.pos.x, self.pos.y)
      del(checkpoint.active_relays, v)
      add(checkpoint.active_relays, v)

      player.life = player.max_life
      checkpoint.inventory = copymt(inventory)
      checkpoint.current_relay = copymt(self.pos)
  end

  function mt.__index.sprite(self)
    return animations.relay[self.active + 1]
  end
end

function make_methods.make_keycard(t, mt)
  make_item(t, mt)
  function mt.__index.pick_up(self)
    if player.life <= 0 then return end
    inventory.keycard_level = inventory.keycard_level + 1
    sfx(14)
  end
end

function make_methods.make_ration(t, mt)
  make_item(t, mt)
  function mt.__index.pick_up(self)
    if player.life <= 0 then return end
    player.life = player.max_life
    sfx(15)
  end
end

function make_methods.make_equip(t, mt)
  make_item(t, mt)
  t.equip = level_items[current_level][global_object_counts["equip"]]
  function mt.__index.pick_up(self)
    inventory[t.equip] = true
    if t.equip == "diving_suit" then player.max_o2 = 6; player.o2 = 6 end -- TODO: change this?
    sfx(21)
  end
end

function make_methods.make_multikey(t, mt)
  t.activated = 0

  function mt.__index.draw(self)
    local p = to_pixel(self.pos)
    zspr(animations[self.subpattern][self.activated + 1], p.x, p.y)
  end

  function mt.__index.activate(self)
    local actors = self.pos:actors_on_here()
    if not actors then return end

    for a in all(actors) do
      if a.life > 0 and a ~= player then
        self.activated = 1 - self.activated
        sfx(20 - self.activated) -- cheeky!
        return
      end
    end
  end
end

function make_methods.make_trapdoor(t, mt)
  t.timer = false
  -- t.facing = 1 -- use facing instead of "active" for trapdoors to save tokens. 1 = set, 2 = open
  function mt.__index.activate(self)
    if self.timer then self.timer = false; self.facing = 2; sfx(13) end

    local actors = self.pos:actors_on_here()
    if not actors then return end

    for a in all(actors) do
      if a.life > -2 then
        if self.facing == 1 then sfx(11); self.timer = true; return end
        sfx(5)
        a:fall()
      end
    end
  end
end

function get_tile_pattern(tile)
  for pattern, tileobj in pairs(map_store) do
    local p = split(pattern, "_")
    if not check_type(tileobj, "table") then
      if tileobj == tile then return {p[1], p[2], 1} end -- return facing
    else
      for f, i in pairs(tileobj) do
        if i == tile then return {p[1], p[2], f} end -- return facing
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

function start_turn()
  for actor in all(global_objects.actor) do
    if actor.life > 0 then
      actor:determine_act()
      actor:pickup_prints()
      if actor.blood_prints >= 1 then actor:place_new_prints("blood_prints") end
      -- end
    end
  end

  local avoid = true
  while (avoid) do
    avoid = false
    for actor in all(global_objects.actor) do
      if actor ~= player and actor.life > 0 then
        avoid = actor:do_avoidance() or avoid
      end
    end
  end

  turn = turn + 1
  global_time = time()
  turn_start = time()

  update_frame()
end

function end_turn()
  turn_start = nil
  global_time = time()

  if player.blood_prints >= 1 then player:redirect_existing_prints("blood_prints") end
  for a in all(global_objects.actor) do
    a:tick_oxygen()
    if a.blood_prints >= 1 then a.blood_prints = a.blood_prints - 1 end
    if a ~= player then a:attempt_act(1) end -- attempt all moves for actors first
  end

  player:attempt_melee()
  player:attempt_act(1)


  for a in all(global_objects.actor) do
    a:attempt_act(2)
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
    if input_dir == 0 then input_dir = player.facing end
  else
    input_dir = i
    if input_act < 5 then input_act = 1 end
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
      if input_act == i or (input_dir == i and input_act == 1) then input_act = 0; return {temp_act, input_dir} end
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

  if frame ~= last_frame and chunk > 250 then
    roll_frame()
    last_frame = frame
  end
end

function roll_frame()
  for a in all(global_objects.actor) do
    if a.laser.frames > 0 then a.laser.frames = a.laser.frames - 1 end
    if a.frames.n > 0 then a.frames.n = a.frames.n - 1 end
  end
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
    if y < player.pos.y + 5 and y > player.pos.y - 5 then
      for x = levels[current_level][1], levels[current_level][3] - 1, 1 do
        if x > player.pos.x - 5 and x < player.pos.x + 5 then
          local v = make_vec2d(x, y)
          local pp = to_pixel(v)
          local tile = lmapget(v)
          if tile > 0 then zspr(tile, pp.x, pp.y) end
        end
      end
    end
  end
end

-- draw ui bar
function draw_bar(label, current, full, full_color, empty_color, position)
  barp = position * 10
  rect(2, 2 + barp, full * 5 + 3, 7 + barp, 6)
  rectfill(3, 3 + barp, full * 5 + 2, 6 + barp, empty_color)
  if current > 0 then rectfill(3, 3 + barp, current * 5 + 2, 6 + barp, full_color) end
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


function default_sprite(subpattern, index)
  s = animations[subpattern]
  if not check_type(s, "table") then return s end

  if index <= 0 or not index then return s[1] end
  if not check_type(s[index], "table") then return s[index] end

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

function actor_methods.act_pos(self)
  local a = self.act[1]
  local d = self.act[2]
  if d == 0 then return self.pos end
  local test_point = self.pos + dir_to_vec(d)

  if a == 1 then
    if not test_point:is_wall() and (not test_point:is_water() or self.aquatic) then return test_point end
  end

  return self.pos
end

function actor_methods.attempt_melee(self)
  if self.life <= 0 then return end
  attack_point = self:act_pos()
  h = attack_point:actors_on_here("player")
  for a in all(h) do
    if a.life > 0 then a.stunned_turns = 3 end
  end
end

function actor_methods.tick_oxygen(self)
  if self:in_water() then
    if self.o2 <= 0 and self.life > 0 then self:hurt(1, true) end
    if self.o2 >= 1 then self.o2 = self.o2 - 1; sfx(12) end
  else
    self.o2 = self.max_o2
  end
end

function actor_methods.in_water(self)
  return self.pos:is_water() and self:act_pos():is_water()
end

function actor_methods.turn_to_face_act(self)
  if self.act[2] > 0 then self.facing = self.act[2] end
end

function actor_methods.move_type(self)
  return enemy_variants[self.subpattern][self.variant][1]
end

function actor_methods.determine_act(self)
  if self.life <= 0 then
    self.act = {a = 0, d = 0}
    return
  end

  if self.stunned_turns > 0 then
    self.stunned_turns = self.stunned_turns - 1
    if self.stunned_turns > 0 then return end
    ha = self.pos:actors_on_here()
    if ha and ha[1].life > 0 and ha[1] ~= self then self.stunned_turns = 1; return end
  end

  previous_facing = self.facing

  follow_prints = self.pos:objects_on_here("prints", "blood_prints")
  if follow_prints then self.facing = follow_prints[1].facing end

  self.act[1] = 1
  self.act[2] = self.facing

  self:determine_facing()

  tiles = self:tiles_ahead(previous_facing, true)
  for k, tile in pairs(tiles) do
    if player.pos == tile then
      self.act = {2, previous_facing}
      self.facing = previous_facing
      sfx(10)
      return
    end
  end

  -- with new facing, look again
  tiles = self:tiles_ahead(self.facing, true)
  for k, tile in pairs(tiles) do
    if player.pos == tile then
      self.act[1] = 2
      sfx(10)
      return
    end
  end

  self:turn_to_face_act()
end

function actor_methods.determine_facing(self)
  local mvt = self:move_type()
  local apos = self:act_pos()
  if mvt == "clockwise" then
    local directions_tried = 0
    while apos == self.pos do
      local f = self.facing + 1
      if f > 4 then f = 5 - f end
      self.act[2], self.facing = f, f
      apos = self:act_pos()
      directions_tried = directions_tried + 1
      if directions_tried > 4 then self.stunned_turns = 3; return end
    end
  end

  if mvt == "still" then self.act = {0, 0}; return end

  if mvt == "line" then
    if apos == self.pos then
      f = self.facing + 2
      if f > 4 then f = abs(5 - f) + 1 end
      self.act[2], self.facing = f, f
    end
  end

  if mvt == "cc" then
    local directions_tried = 0
    while apos == self.pos do
      f = self.facing - 1
      if f < 1 then f = 4 end
      self.act[2], self.facing = f, f
      apos = self:act_pos()
      directions_tried = directions_tried + 1
      if directions_tried > 4 then self.stunned_turns = 3; return end
    end
  end
end

function actor_methods.do_avoidance(self)
  if self.act[1] > 1 then return false end
  local new_pos = self:act_pos()

  for a in all(global_objects.actor) do
    if a.life > 0 then
      apos = a:act_pos()

      if a ~= self and apos == new_pos and a.subpattern ~= "player" then
        self.act = {0, 0}
        return true
      end
    end
  end

  return false
end

function actor_methods.pickup_prints(self)
  for a in all(global_objects.actor) do
    if a.life <= 0 and a.pos == self.pos then self.blood_prints = 6; return end
  end
end

function actor_methods.place_new_prints(self, subpattern)
  if self.life <= 0 or self.pos:is_water() or self.pos:objects_on_here(nil, "trapdoor") then return end
  p = self.pos:objects_on_here("prints", subpattern)

  if not p then
    d = self.act[2]
    if d <= 0 then d = self.facing end
    o = make_object(self.pos, {"prints", subpattern, d}, true)
    add(global_objects.prints, o)
    add(global_objects.object, o)
  end
end

function actor_methods.attempt_act(self, act_type)
  a = self.act[1]
  if a == 1 and act_type == 1 then self:attempt_move() end
  if a == 2 and act_type == 2 then self:attempt_shot() end
end

function actor_methods.attempt_move(self)
  self.pos = self:act_pos()
end

function actor_methods.attempt_shot(self)
  sfx(4)

  tiles = {}
  for i, tile in pairs(self:tiles_ahead(self.act[2], true)) do
    hurts = {}
    add(tiles, tile)

    as = tile:actors_on_here()
    if as then
      for a in all(as) do
        if a and self ~= a and a.life > 0 then add(hurts, a) end
      end
    end

    l = #hurts
    for a in all(hurts) do
      if l > 1 then
        if a ~= player and a.life > 0 then
          a:hurt()
          self:queue_lasers(tiles, a)
          return
        end
      elseif l == 1 then
        a:hurt()
        self:queue_lasers(tiles, a)
        return
      end
    end
  end
end

function actor_methods.redirect_existing_prints(self, subpattern)
  if self.life <= 0 then return end
  p = self.pos:objects_on_here("prints", subpattern)
  if not p then return end
  -- if (self.act[2] > 0 and p[1].subpattern == pattern) p[1].facing = self.act[2]
  if self.act[2] > 0 then p[1].facing = self.act[2] end
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
  if self.life == 0 then
    sfx(5)
    if not hide_anim then self:set_frames("death", 4) end
  else
    sfx(5, -1, 1, 3)
    if not hide_anim then self:set_frames("hurt", 2) end
  end
end

function actor_methods.fall(self)
  self.life = -2
  self:set_frames("fall", 2)
end

function actor_methods.tiles_ahead(self, d, ignore_glass)
  ignore_glass = ignore_glass or false
  if d <= 0 then d = self.facing end
  p = self.pos + dir_to_vec(d)
  collected = {}
  i = 1

  while not (p:is_wall() and (not p:is_glass() or not ignore_glass)) do
    collected[i] = p
    i = i + 1
    p = p + dir_to_vec(d)
  end

  return collected
end

function actor_methods.draw_sprite(self)
  local p = to_pixel(self.pos)
  local s = self:tile_shift()
  ssw, ssh, y_shift = 8, 8, 0
  if self:in_water() then ssh = 4; y_shift = 2 end

  palswap = enemy_variants[self.subpattern][self.variant][2]
  pal(palswap[1], palswap[2])
  zspr(self:sprite(), p.x + s.x * 2, p.y + s.y * 2 + y_shift, 2, 1, 1, ssw, ssh)
  pal(palswap[1], palswap[1])
end

function actor_methods.draw_below(self)
  if self.life > 0 then return end
  self:draw_sprite()
end

function actor_methods.draw(self)
  if self.life <= 0 then return end
  self:draw_sprite()
end

function actor_methods.draw_above(self)
  -- draw speculative lasers
  anim = animations[self.subpattern][7]
  if self.act[1] == 2 or (self == player and input_act == 5 and turn_start == nil) then
    d = self.act[2]
    if self == player and input_act == 5 then d = input_dir end
    if d <= 0 then d = self.facing end
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

  if l.frames > 0 then
    for tile in all(l.tiles) do
      if l.frames == 1 then pal(8,2); pal(11,3) end
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

  if frames_n > 0 then
    if frames_pattern == "death" then return animations[pattern][5][(4 - frames_n) + 1] end
    if frames_pattern == "hurt" then return animations[pattern][5][(2 - frames_n) + 1] end
    if frames_pattern == "fall" then return animations[pattern][6][(2 - frames_n) + 1] end
  end

  if self.life <= 0 then
    if self.life == -2 then return 255 end
    return animations[pattern][5][4]
  end

  if self.stunned_turns > 0 then return animations[pattern][8][(frame % 2) + 1] end

  anim = animations[pattern][self.facing]

  if turn_start ~= nil then
    if self.act[1] == 1 then return anim[frame+1] end
  end

  -- TODO: refactor this into player sprite method
  if input_act == 6 and self == player and turn_start == nil then return animations[pattern][input_dir][1] end
  if input_act == 5 and self == player and turn_start == nil then anim = animations[pattern][input_dir] end
  if self.act[1] == 2 or (input_act == 5 and self == player and turn_start == nil) then return anim[6] end

  return default_sprite(pattern, self.facing)
end

function actor_methods.tile_shift(self)
  apos = self:act_pos()
  if not (apos == self.pos) and turn_start then return make_vec2d((apos.x - self.pos.x) * biframe, (apos.y - self.pos.y) * biframe) end
  return make_vec2d(0, 0)
end

actormt.__index = actor_methods

pos_map = {{0,1,0,-1}, {-1,0,1,0}}

function dir_to_vec(dr)
  return make_vec2d(pos_map[1][dr], pos_map[2][dr])
end

function make_vec2d(x, y)
    local t = {
        x = x,
        y = y
    }

    setmetatable(t, vecmt)
    return t
end
function vector_methods.distance_to(self, pos)
 local v = pos - self
 return sqrt(v.x * v.x + v.y * v.y)
end

function vector_methods.is_adjacent(self, pos)
  return ((self.x == pos.x + 1 and self.y == pos.y) or
    (self.x == pos.x - 1 and self.y == pos.y) or
    (self.x == pos.x and self.y == pos.y + 1) or
    (self.x == pos.x and self.y == pos.y - 1))
end

function get_global_objects(pattern, subpattern)
  pattern = pattern or subpattern

  local objects = {}
  for o in all(global_objects[pattern]) do
    if not subpattern or o.subpattern == subpattern then add(objects, o) end
  end
  return objects
end

function vector_methods.objects_on_here(self, pattern, subpattern)
  local objects, on_here = get_global_objects(pattern, subpattern), {}
  for o in all(objects) do
    if o.pos == self then add(on_here, o) end
  end
  if #on_here > 0 then return on_here end
  return nil
end

function vector_methods.actors_on_here(self, exclude_pattern)
  exclude_pattern = exclude_pattern or ""
  local actors = {}
  for a in all(global_objects.actor) do
    if a.pos == self and a.subpattern ~= exclude_pattern then add(actors, a) end
  end
  if #actors > 0 then return actors end
  return nil
end

function vector_methods.is_glass(self)
  m = lmapget(self)
  return (m == 119 or m == 120)
end

function vector_methods.is_wall(self)
  a = self:objects_on_here("door")
  if a and a[1].solid == 1 then return true end
  m = lmapget(self)
  return (m >= 64 and m <= 127)
end

function vector_methods.is_vault_gate(pos)
  m = lmapget(pos)
  return (m == 70 or m == 71)
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

function to_pixel(vec)
  return make_vec2d(vec.x * 16, vec.y * 16)
end

function n_to_vec(n)
  return make_vec2d(8 * (n % 16), 8 * flr(n / 16))
end
