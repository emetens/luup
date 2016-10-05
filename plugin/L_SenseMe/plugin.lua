local VERSION = "0.10"

local PLUGIN = {
  -- PLUGIN_ID = 8588,
  NAME = "SenseMe Gateway",
  MIOS_VERSION = "unknown",
  DEBUG_MODE = false,
  PLUGIN_DISABLED = false,
  FILES_VALIDATED = false,
  POLL_PERIOD = "300"
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

local function getPluginSettings(device)

  local plugin_version = UTILITIES:getVariable(VERA.SID["SENSEME"], "PLUGIN_VERSION")

  local period = luup.variable_get(VERA.SID["SENSEME"], "pollPeriod", device) or ""
  if period == "" then
    luup.variable_set(VERA.SID["SENSEME"], "pollPeriod", PLUGIN.POLL_PERIOD, device)
    debug("(" .. PLUGIN.NAME .. "::getPluginSettings): ERROR : Polling period set to default value!")
  end

  if ((plugin_version == nil) or (plugin_version == "") or (plugin_version ~= VERSION)) then
    -- on first run version variable is empty - make sure the panel variables are visible
    -- on subsequent runs, if the version strings do not match, make sure any new variables are visible
    -- panel related VAM variables
    UTILITIES:setVariableDefault(VERA.SID["SENSEME"], "PLUGIN_VERSION", "")
    UTILITIES:setVariableDefault(VERA.SID["SENSEME"], "DEBUG_MODE", "0")
    UTILITIES:setVariableDefault(VERA.SID["SENSEME"], "DEBUG_MODE_TEXT", "DISABLED")
    UTILITIES:setVariableDefault(VERA.SID["SENSEME"], "POLL_PERIOD", PLUGIN.POLL_PERIOD)
    UTILITIES:setVariableDefault(VERA.SID["SENSEME"], "DEVICE_SUMMARY", "")

    UTILITIES:setVariableDefault(VERA.SID["HA_DEVICE"], "CommFailure", 0)
    UTILITIES:setVariableDefault(VERA.SID["HA_DEVICE"], "Configured", 1)
    UTILITIES:setVariableDefault(VERA.SID["HA_DEVICE"], "ID", "SenseMe Gateway")
    UTILITIES:setVariableDefault(VERA.SID["HA_DEVICE"], "PollingEnabled", 0)
    UTILITIES:setVariableDefault(VERA.SID["HA_DEVICE"], "PollMinDelay", 60)
  end

  UTILITIES:setVariable(VERA.SID["SENSEME"], "PLUGIN_VERSION", VERSION, lug_device)
  UTILITIES:setStatus("Loading Options...")
  UTILITIES:setVariable(VERA.SID["SENSEME"], "DEVICE_SUMMARY", "", lug_device)

  if (checkVersion() == true) then
    luup.set_failure(0, lul_device)
  end

  local debugMode = luup.variable_get(VERA.SID["SENSEME"], "DEBUG_MODE", lug_device) or ""
  if debugMode == "" then
    luup.variable_set(VERA.SID["SENSEME"], "DEBUG_MODE", (PLUGIN.DEBUG_MODE and "1" or "0"), lug_device)
  else
    PLUGIN.DEBUG_MODE = (debugMode == "1") and true or false
  end
  UTILITIES:setVariable(VERA.SID["SENSEME"], "DEBUG_MODE", (PLUGIN.DEBUG_MODE and "ENABLED" or "DISABLED"), lug_device)
  --PLUGIN.DEBUG_MODE = true
end
