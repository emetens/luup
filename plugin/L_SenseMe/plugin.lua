local VERSION = "0.10"

local PLUGIN = {
  -- PLUGIN_ID = 8588,
  NAME = "SenseMe Gateway",
  MIOS_VERSION = "unknown",
  DEBUG_MODE = true, -- TODO set this back to false
  PLUGIN_DISABLED = false,
  FILES_VALIDATED = false,
  POLL_PERIOD = "1000"
}

local function checkVersion()
  local ui7Check = luup.variable_get(VERA.SID["SENSEME"], "UI7_CHECK", lug_device) or ""

  if ui7Check == "" then
    luup.variable_set(VERA.SID["SENSEME"], "UI7_CHECK", "false", lug_device)
    ui7Check = "false"
  end

  if (luup.version_branch == 1 and luup.version_major == 7) then
    luup.variable_set(VERA.SID["SENSEME"], "UI7_CHECK", "true", lug_device)
    return true
  else
    luup.variable_set(VERA.SID["SENSEME"], "UI7_CHECK", "false", lug_device)
    return false
  end
end