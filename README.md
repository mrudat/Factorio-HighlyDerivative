
```lua
local HighlyDerivative = require('__HighlyDerivative__/library.lua')

HighlyDerivate.register_filter('item', function(item, item_name)
  item.stack_size = item.stack_size * 2
end)

```
