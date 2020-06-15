-- TODO write some tests
local hd = require('__HighlyDerivative__/library')

local MOD_NAME = 'Test Mod'
local PREFIX = MOD_NAME .. '-'
local PREFIX_LENGTH = PREFIX:len()

local function derive_from_turret_and_ammo(new_things, turret, ammo) --luacheck: ignore
  local ammo_category = ammo.ammo_type.category
  local turret_ammo_category = turret.attack_parameters.ammo_category
  if ammo_category ~= turret_ammo_category then return end
  local turret_name = turret.name
  if turret_name:sub(1,PREFIX_LENGTH) == PREFIX then return end
  local ammo_name = ammo.name
  log("Could derive new thing from " .. turret_name .. " and " .. ammo_name)
end

local ammo_list = {}
local turret_list = {}

hd.register_derivation('ammo', function(new_things, ammo, ammo_name)
  ammo_list[#ammo_list+1] = ammo_name
  local turret_data = data.raw['ammo-turret']
  for _, turret_name in ipairs(turret_list) do
    derive_from_turret_and_ammo(new_things, turret_data[turret_name], ammo)
  end
end)

hd.register_derivation('ammo-turret', function(new_things, turret, turret_name)
  turret_list[#turret_list+1] = turret_name
  local ammo_data = data.raw['ammo']
  for _, ammo_name in ipairs(ammo_list) do
    derive_from_turret_and_ammo(new_things, turret, ammo_data[ammo_name])
  end
end)

hd.derive()
