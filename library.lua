local M = HighlyDerivative
if M then
  return M
else
  M = {}
  HighlyDerivative = M
end

log("Loading Highly Derivative library...")






--------------------------------------------------------------------------------
-- external functions we're using

local rusty_protoypes = require('__rusty-locale__.prototypes')

local find_prototype = rusty_protoypes.find

local bxor = bit32.bxor
local bor = bit32.bor
local lshift = bit32.lshift
local band = bit32.band





--------------------------------------------------------------------------------
-- constants

--[[

-- recipe flags
#define AVAILABILE_BY_DEFAULT_MASK    12
#define AVAILABLE_BY_DEFAULT_EXPENSIVE 8
#define AVAILABLE_BY_DEFAULT_NORMAL    4
#define AVAILABLE_BY_DEFAULT_BOTH     12

-- difficulty 'constants'
#define DIFFICULTY_EXPENSIVE 2
#define DIFFICULTY_NORMAL    1
#define DIFFICULTY_BOTH      3
#define DIFFICULTY_MASK      3

]]





--------------------------------------------------------------------------------
-- private helper functions

local function autovivify(table, key)
  local foo = table[key]
  if not foo then
    foo = {}
    table[key] = foo
  end
  return foo
end

local function hash(input_string)
  local h = 0
  for _,c in ipairs{string.byte(input_string)} do
    h = bxor(h * 31, c)
  end
  return string.format("%8.8X",h)
end

local function has_hidden_flag(thing_data)
  local flags = thing_data.flags
  if not flags then return end
  for _, flag in pairs(flags) do
    if flag == 'hidden' then
      return true
    end
  end
end





--------------------------------------------------------------------------------
-- public helper functions

do
  local DerivedNames = {}
  local NameColission = {}

  local MAX_NAME_LENGTH = 200
  local DOTS_LENGTH = string.len("…") -- 3
  local MAX_OFFSET = math.pow(2,53) -- 9.0x10^15
  local MAX_OFFSET_LENGTH = math.ceil(math.log10(MAX_OFFSET)) -- 16
  local HASH_LENGTH = 8 -- uint32 0xFFFFFFFF
  -- name = concat(prefix, '-', hash, '-', offset '-', names, "…")
  local MAX_PREFIX_LENGTH = MAX_NAME_LENGTH - HASH_LENGTH - MAX_OFFSET_LENGTH - DOTS_LENGTH - 3 --[[ x '-' ]]

  function M.derive_name(prefix, ...)
    local components = { ... }
    local prefix_len = prefix:len()
    if prefix_len > MAX_PREFIX_LENGTH then
      error("Cannot produce a valid prototype name including prefix if prefix is greater than " .. MAX_PREFIX_LENGTH .. " characters in length.")
    end
    components = table.concat(components, '-')
    if components:len() + prefix_len < 200 then return prefix .. components end
    local prefix_names = DerivedNames[prefix]
    local new_name
    if prefix_names then
      new_name = prefix_names[components]
      if new_name then return new_name end
    else
      prefix_names = {}
      DerivedNames[prefix] = prefix_names
    end
    local ingredients_hash = hash(components)
    new_name = (prefix .. ingredients_hash .. components):sub(1,197) .. "…"
    local offset = NameColission[new_name]
    if not offset then
      NameColission[new_name] = 0
      prefix_names[components] = new_name
      return new_name
    end
    if offset >= MAX_OFFSET then
      error("Cannot create a unique name, too many collisions")
    end
    NameColission[new_name] = offset + 1
    return (prefix .. ingredients_hash .. '-' .. offset .. '-' .. components):sub(1,197) .. "…"
  end
end





--------------------------------------------------------------------------------
-- the point of this exercise

local Callbacks = {}

local register_callback

local function register_descendants(callback_type, descendants, callback)
  for prototype_type, value in pairs(descendants) do
    register_callback(callback_type, prototype_type, callback)
    register_descendants(callback_type, value, callback)
  end
end

function register_callback(callback_type, prototype_type, callback, and_descendants)
  if type(prototype_type) == 'table' then
    for _, value in pairs(prototype_type) do
      register_callback(callback_type, value, callback, and_descendants)
    end
    return
  end
  if and_descendants then
    local descendants = rusty_protoypes.descendants(prototype_type)
    register_descendants(callback_type, descendants, callback)
  end
  local type_callbacks = autovivify(Callbacks, prototype_type)
  local callbacks = autovivify(type_callbacks, callback_type)
  callbacks[#callbacks+1] = callback
end

function M.register_index(prototype_type, index, and_descendants)
  register_callback('index', prototype_type, index, and_descendants)
end

function M.register_filter(prototype_type, filter, and_descendants)
  register_callback('filters', prototype_type, filter, and_descendants)
end

function M.register_derivation(prototype_type, derivation, and_descendants)
  register_callback('derivations', prototype_type, derivation, and_descendants)
end

function M.register_final_derivation(prototype_type, derivation, and_descendants)
  register_callback('final_derivations', prototype_type, derivation, and_descendants)
end

local Seen = {}

local function index_thing2(thing_data, thing_name, thing_type, seen_type, indexes)
  local seen_thing = autovivify(seen_type, thing_name)
  local applied_indexes = seen_thing.applied_indexes
  for _, index in next, indexes, applied_indexes do
    index(thing_data, thing_name, thing_type)
  end
  seen_thing.applied_indexes = #indexes
end

local function index_thing(thing)
  local thing_type = thing.type
  if not thing_type then return end
  local type_callbacks = Callbacks[thing_type]
  if not type_callbacks then return end
  local thing_name = thing.name
  if not thing_name then return end
  local indexes = type_callbacks.index
  if not indexes then return end
  local seen_type = autovivify(Seen, thing_type)
  index_thing2(thing, thing_name, thing_type, seen_type, indexes)
  return
end

function M.index(thing)
  if thing then
    return index_thing(thing)
  end
  for thing_type, type_data in pairs(data.raw) do
    local type_callbacks = Callbacks[thing_type]
    if not type_callbacks then goto next_type end
    local indexes = type_callbacks.index
    if not indexes then goto next_type end
    local seen_type = autovivify(Seen, thing_type)
    for thing_name, thing_data in pairs(type_data) do
      index_thing2(thing_data, thing_name, thing_type, seen_type, indexes)
    end
    ::next_type::
  end
end

local function apply_filters_to_thing2(thing_data, thing_name, thing_type, seen_type, filters, indexes)
  local seen_thing = autovivify(seen_type, thing_name)
  local applied_filters = seen_thing.applied_filters or 0
  local changed = false
  for i = applied_filters+1,#filters do
    changed = filters[i](thing_data, thing_name, thing_type) or changed
  end
  seen_thing.applied_filters = #filters
  if not indexes then return end
  local applied_indexes = seen_thing.applied_indexes or 0
  if changed and applied_indexes > 0 then
    for i = 1,applied_indexes do
      indexes[i](thing_data, thing_name, thing_type, true)
    end
  end
  for i = applied_indexes+1,#indexes do
    indexes[i](thing_data, thing_name, thing_type)
  end
  seen_thing.applied_indexes = #indexes
end

local function apply_filters_to_thing(thing_data, thing_name, thing_type)
  local type_callbacks = Callbacks[thing_type]
  if not type_callbacks then return end
  local filters = type_callbacks.filters
  if not filters then return end
  local indexes = type_callbacks.index
  local seen_type = autovivify(Seen, thing_type)
  apply_filters_to_thing2(thing_data, thing_name, thing_type, seen_type, filters, indexes)
end

local function apply_filters()
  for thing_type, type_data in pairs(data.raw) do
    local type_callbacks = Callbacks[thing_type]
    if not type_callbacks then goto next_type end
    local filters = type_callbacks.filters
    if not filters then goto next_type end
    local indexes = type_callbacks.index
    local seen_type = autovivify(Seen, thing_type)
    for thing_name, thing_data in pairs(type_data) do
      apply_filters_to_thing2(thing_data, thing_name, thing_type, seen_type, filters, indexes)
    end
    ::next_type::
  end
end

local function derive_things()
  local derived_things = {}
  for thing_type, type_data in pairs(data.raw) do
    local type_callbacks = Callbacks[thing_type]
    if not type_callbacks then goto next_type end
    local derivations = type_callbacks.derivations
    if not derivations then goto next_type end
    local seen_type = autovivify(Seen, thing_type)
    for thing_name, thing_data in pairs(type_data) do
      local seen_thing = autovivify(seen_type, thing_name)
      if seen_thing.final then goto next_thing end
      local applied_derivations = seen_thing.applied_derivations or 0
      for i=applied_derivations+1,#derivations do
        derivations[i](derived_things, thing_data, thing_name, thing_type)
      end
      seen_thing.applied_derivations = #derivations
      ::next_thing::
    end
    ::next_type::
  end
  if not next(derived_things) then return derived_things end
  data:extend(derived_things)
  for i = 1,#derived_things do
    local derived_thing = derived_things[i]
    apply_filters_to_thing(derived_thing, derived_thing.name, derived_thing.type)
  end
  return derived_things
end

function M.mark_final(thing)
  local thing_type = thing.type
  local thing_name = thing.name
  local seen_type = autovivify(Seen, thing_type)
  local seen_thing = autovivify(seen_type, thing_name)
  seen_thing.final = true
end

local function derive_final_things()
  local derived_things = {}
  for thing_type, type_data in pairs(data.raw) do
    local type_callbacks = Callbacks[thing_type]
    if not type_callbacks then goto next_type end
    local final_derivations = type_callbacks.final_derivations
    if not final_derivations then goto next_type end
    local seen_type = autovivify(Seen, thing_type)
    for thing_name, thing_data in pairs(type_data) do
      local seen_thing = autovivify(seen_type, thing_name)
      if seen_thing.final then goto next_thing end
      local applied_derivations = seen_thing.applied_final_derivations
      for i=applied_derivations+1,#final_derivations do
        final_derivations[i](derived_things, thing_data, thing_name, thing_type)
      end
      seen_thing.applied_final_derivations = #final_derivations
      ::next_thing::
    end
    ::next_type::
  end
  if not next(derived_things) then return end
  data:extend(derived_things)
  for i = 1,#derived_things do
    local derived_thing = derived_things[i]
    M.mark_final(derived_thing)
    apply_filters_to_thing(derived_thing, derived_thing.name, derived_thing.type)
  end
end

function M.derive()
  apply_filters()

  local derived_things = derive_things()
  while next(derived_things) do
    derived_things = derive_things()
  end

  derive_final_things()
end





--------------------------------------------------------------------------------
-- assorted indexes

do
  --[[
    entity.placeable_by is used by construction robots. they will only use the first item on this list if present.
    item.place_result is usable by the player or construction robots
    mods that build entites before robots may vary.
  ]]

  local ItemsThatPlace = {}

  local function register_item(item, item_name, item_type, is_refresh)
    if is_refresh then
      for _, items_that_place in pairs(ItemsThatPlace) do
        items_that_place[item_name] = nil
      end
    end
    local place_result = item.place_result
    if not place_result then return end
    local items_that_place = autovivify(ItemsThatPlace, place_result)
    items_that_place[item_name] = {
      type = item_type,
      is_hidden = has_hidden_flag(item)
    }
  end

  function M.find_items_that_place(entity, include_hidden)
    local entity_name = entity.name
    local placeable_by = entity.placeable_by
    local return_value = {}
    local seen = {}
    if placeable_by then
      local item_name = placeable_by.item
      if item_name then
        seen[item_name] = true
        local item = find_prototype(item_name, 'item', true)
        if item and include_hidden or not has_hidden_flag(item) then
          return_value[#return_value+1] = { item, 1 }
        end
      else
        for _, item_to_place in pairs(placeable_by) do
          item_name = item_to_place.name
          if seen[item_name] then goto next_item end
          seen[item_name] = true
          local item = find_prototype(item_name, 'item', true)
          if item and include_hidden or not has_hidden_flag(item) then
            return_value[#return_value+1] = { item, item_to_place.count }
          end
          ::next_item::
        end
      end
    end

    local items_that_place = ItemsThatPlace[entity_name]
    if items_that_place then
      for item_name, item_that_places in pairs(items_that_place) do
        if seen[item_name] then goto next_item end
        seen[item_name] = true
        if not include_hidden and item_that_places.is_hidden then goto next_item end
        local item = find_prototype(item_name, item_that_places.type, true)
        if item then
          return_value[#return_value+1] = { item, 1 }
        end
        ::next_item::
      end
    end
    return return_value
  end

  M.register_index('item', register_item, true)
end

do
  local item_type_and_name_to_recipe_name = {}

  local function catalog_result(recipe_name, ingredient_name, ingredient_type, recipe_flags)
    local recipe_index = item_type_and_name_to_recipe_name
    local type_data = autovivify(recipe_index,ingredient_type)
    local ingredient_data = autovivify(type_data,ingredient_name)
    ingredient_data[recipe_name] = bor(ingredient_data[recipe_name] or 0, recipe_flags)
  end

  local function catalog_recipe(recipe_name, recipe_data, disabled, recipe_flags)
    local result_name = recipe_data.result
    if not disabled then
      local enabled = recipe_data.enabled
      if enabled ~= false then
        -- enabled_at_start is 2 bits to the left of the difficulty flags.
        recipe_flags = bor(recipe_flags, lshift(recipe_flags, 2))
      end
    end
    if result_name then
      return catalog_result(recipe_name, result_name, 'item', recipe_flags)
    else
      local results = recipe_data.results
      if not results then return end
      for _,result in ipairs(results) do
        local result_type = result.type
        if result_type then
          catalog_result(recipe_name, result.name, result_type, recipe_flags)
        else
          catalog_result(recipe_name, result.name or result[1], 'item', recipe_flags)
        end
      end
    end
  end

  local function register_recipe(recipe, recipe_name, _, is_refresh)
    if is_refresh then
      for _, type_data in pairs(item_type_and_name_to_recipe_name) do
        for _, ingredient_data in pairs(type_data) do
          ingredient_data[recipe_name] = nil
        end
      end
    end
    -- https://wiki.factorio.com/Prototype/Recipe#Recipe_data
    local expensive = recipe.expensive
    local normal = recipe.normal
    if expensive or normal then
      if expensive == false then
        catalog_recipe(recipe_name, normal, false, 1) -- DIFFICULTY_NORMAL
        catalog_recipe(recipe_name, normal, true, 2) -- DIFFICULTY_EXPENSIVE
      elseif normal == false then
        catalog_recipe(recipe_name, expensive, false, 2) -- DIFFICULTY_EXPENSIVE
        catalog_recipe(recipe_name, expensive, true, 1) -- DIFFICULTY_NORMAL
      elseif expensive == nil then
        catalog_recipe(recipe_name, normal, false, 3) -- DIFFICULTY_BOTH
      elseif normal == nil then
        catalog_recipe(recipe_name, expensive, false, 3) -- DIFFICULTY_BOTH
      else
        catalog_recipe(recipe_name, normal, false, 1) -- DIFFICULTY_NORMAL
        catalog_recipe(recipe_name, expensive, false, 2) -- DIFFICULTY_EXPENSIVE
      end
    else
      catalog_recipe(recipe_name, recipe, false, 3) -- DIFFICULTY_BOTH
    end
  end

  function M.find_recipes_that_make(item)
    local recipes = {}
    local item_name = item.name
    local item_type = item.type
    if item_type ~= 'fluid' then
      item_type = 'item'
    end
    local type_data = item_type_and_name_to_recipe_name[item_type]
    if not type_data then return end
    local item_data = type_data[item_name]
    if not item_data then return end
    for recipe_name, recipe_data in pairs(item_data) do
      recipes[recipe_name] = bor(recipes[recipe_name] or 0, recipe_data)
    end
  end

  function M.can_be_made(item)
    local item_name = item.name
    local item_type = item.type
    if item_type ~= 'fluid' then
      item_type = 'item'
    end
    local type_data = item_type_and_name_to_recipe_name[item_type]
    if not type_data then return end
    local item_data = type_data[item_name]
    if not item_data then return end
    local recipes = 0
    for _, recipe_data in pairs(item_data) do
      recipes = bor(recipes, recipe_data)
      if band(recipes, 3) == 3 then return true end
    end
  end

  M.register_index('recipe', register_recipe)
end

return M
