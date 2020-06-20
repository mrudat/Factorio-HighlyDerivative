# Highly Derivative

A library to help write mods that derive things from existing things, most definitely still a work in progress.

```lua
-- load the Highly Derivative library.
local HighlyDerivative = require('__HighlyDerivative__.library')
```

## Public Functions

### derive()

Runs through every prototype currently in data.raw and calls all registered callbacks.

Will call each (non-index) callback exactly once for each new prototype encountered.

This should be called in `data-updates.lua` and `data-final-fixes.lua`.

```lua
-- data-updates and data-final-fixes
require('__HighlyDerivative__.library').derive()
```

### index(prototype)

Called with no arguments, will cause the library to re-index all prototypes in data.raw, in case they may have been changed.

Called with a prototype, causes that prototype to be (re)-indexed.

```lua
HighlyDerivative.index(thing)
```

### mark_final(prototype)

Marks `prototype` as 'final' which will prevent prototype from being fed to any derivation callbacks.

Only needs name and type, so can be called ahead of time for a prototype that may not end up being created at all.

```lua
HighlyDerivative.mark_final({
  type = 'item',
  name = 'fred',
})
```

### register_index(prototype_type, callback, and_descendants)

Registers `callback` to be called for each instance of prototype_type in data.raw.

If `and_descendants` is true, the callback will be registered against every descendant of `prototype_type`.

`callback` can be called again with `is_reindex` set to true if it is known that the prototype has changed since the last call.

```lua
local items_by_stack_size = {}

HighlyDerivative.register_index('item', function(item, item_name, item_type, is_reindex)
  if is_reindex then
    for _, item_list in pairs(items_by_stack_size) do
      item_list[item_name] = nil
    end
  end
  local stack_size = item.stack_size
  local item_list = items_by_stack_size[stack_size]
  if not item_list then
    item_list = {}
    items_by_stack_size[stack_size] = item_list
  end
  item_list[item_name] = true
end, true)
```

### register_filter(prototype_type, callback, and_descendants)

Registers `callback` to be called for each instance of prototype_type in data.raw, with the intent of modifying the prototype in some way.

If `and_descendants` is true, the callback will be registered against every descendant of `prototype_type`.

`callback` is expected to return true if it has modified the prototype, to prompt the library to call the index callback on the prototype again.

```lua
HighlyDerivative.register_filter('item', function(item, item_name, item_type)
  if item_name:sub(1,PREFIX:len()) == PREFIX then return end
  if item_type == 'item-with-entity-data' then return end
  item.stack_size = item.stack_size * 2
  return true
end, true)
```

### register_derivation(prototype_type, callback, and_descendants)

Registers `callback` to be called for each instance of prototype_type in data.raw, with the intent of creating new things based on the prototype.

If `and_descendants` is true, the callback will be registered against every descendant of `prototype_type`.

`callback` is expected to add newly created items to new_things, to allow the library to index, filter, and further derive more new things from `new_things`. All prototypes in `new_things` are fed to data:extend by the library.

`callback` will be called exactly once for each prototype in data.raw; if you create a new item of the same type that the callback is registered for, the callback will be called for the new item as well.

```lua
HighlyDerivative.register_derivation('item', function(new_things, item, item_name, item_type)
  if item_name:sub(1,PREFIX:len()) == PREFIX then return end
  if item_type == 'item-with-entity-data' then return end
  local new_item = table.deepcopy(item)
  new_item.stack_size = new_item.stack_size * 2
  new_item.name = PREFIX .. new_item.name .. '-2'
  table.insert(new_things, new_item)
end, true)
```

### register_final_derivation(prototype_type, callback, and_descendants)

Registers `callback` to be called for each instance of prototype_type in data.raw, with the intent of creating new things based on the prototype.

If `and_descendants` is true, the callback will be registered against every descendant of `prototype_type`.

`callback` is expected to add newly created items to new_things, to allow the library to index and filter the `new_things`. All prototypes in `new_things` are fed to data:extend and mark_final by the library.

`callback` will be called exactly once for each prototype in data.raw.

```lua
HighlyDerivative.register_final_derivation('item', function(new_things, item, item_name, item_type)
  if item_name:sub(1,PREFIX:len()) == PREFIX then return end
  local new_item = table.deepcopy(item)
  new_item.stack_size = new_item.stack_size * 4
  new_item.name = PREFIX .. new_item.name .. '-4'
  table.insert(new_things, new_item)
end, true)
```

## Utility functions

Not certain if these should remain here, or be moved to a distinct mod, possibly named 'A Certain Overcomplicated Index'.

### find_items_that_place(entity, include_hidden)

Inspects both `entity.placeable_by`, and an index of `item.place_result` and returns a list of `{ item_prototype, count }` for every item that can place entity.

If include hidden is true, also includes any items with the hidden flag.

```lua
local recipes = HighlyDerivative.find_items_that_place(data.raw.accumulator.accumulator)

for _, ingredient in pairs(recipes) do
  local item = ingredient[1]
  local count = ingredient[2]
  log('you could place an accumulator using ' .. count .. ' x ' .. item.name)
end
```

### find_recipes_that_make(item)

Inspects an index of `item.result`/`item.results` and returns a table of recipes that can make the item.

```lua
local recipes = HighlyDerivative.find_recipes_that_make({
  type = 'fluid',
  name = 'light-oil'
})

for recipe_name, difficulty_flags in pairs(recipes) do
  log(recipe_name .. ' creates light-oil in:')
  if bit32.band(difficulty_flags, 3) == 3 then
    log('  both difficulties')
  else
    if bit32.band(difficulty_flags, 1) == 1 then log('  normal') end
    if bit32.band(difficulty_flags, 2) == 2 then log('  expensive') end
  end
end
```

### can_be_made(item)

Inspects an index of `item.result`/`item.results` and returns true if at least one recipe in normal difficulty and at least one recipe in expensive difficulty is capable of crafting item.

```lua
if HighlyDerivative.can_be_made({ type = 'fluid', name = 'light-oil' }) then
  log('light-oil can be made')
end
```
