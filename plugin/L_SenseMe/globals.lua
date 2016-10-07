local lug_device = nil
local log = luup.log
local socket = require("socket")
local PROXY = nil -- TODO Do we need this?
local g_taskHandle = -1

-- TODO do we need this?
local g_childDevices = {-- .id       -> vera id
  -- .integrationId -> lutron internal id
  -- .devType -> device type (dimmer, blinds , binary light or keypad)
  -- .fadeTime
  -- .componentNumber = {} -> only for keypads
}
