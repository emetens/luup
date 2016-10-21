----------------------------------------
-- Globals
----------------------------------------

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

----------------------------------------
-- Vera
----------------------------------------

local VERA = {
  SID = {
    ["SENSEME"] = "urn:micasaverde-com:serviceId:SenseMe1",
    ["FAN"]     = "urn:micasaverde-com:serviceId:SenseMeFan1",
    ["DIMMER"]  = "urn:upnp-org:serviceId:Dimming1",
    ["SWITCH"]	= "urn:upnp-org:serviceId:SwitchPower1",
  },
  DEVTYPE = {
    ["FAN"]     = { "urn:schemas-micasaverde-com:device:SenseMeFan:1", "D_SenseMeFan1.xml" },
    ["DIMMER"]  = { "urn:schemas-upnp-org:device:DimmableLight:1", "D_DimmableLight1.xml" },
    ["SWITCH"]	= {"urn:schemas-upnp-org:device:BinaryLight:1","D_BinaryLight1.xml"},
  },
  DEVFILES = {
    -- TODO clean based on the files we really need
    "D_DimmableLight1.xml",
    "D_DimmableLight1.json",
    "S_Dimming1.xml",
    "S_Color1.xml",
    "S_SwitchPower1.xml",
    "S_EnergyMetering1.xml",
    "S_HaDevice1.xml",
    "D_SenseMeFan1.xml",
    "D_SenseMeFan1.json",
    "S_FanSpeed1.xml"
  }
}
----------------------------------------
-- Plugin
----------------------------------------

local VERSION = "0.60"

local PLUGIN = {
  -- PLUGIN_ID = 8588,
  NAME = "SenseMe Gateway",
  MIOS_VERSION = "unknown",
  DEBUG_MODE = true, -- TODO set this back to false
  PLUGIN_DISABLED = false,
  FILES_VALIDATED = false,
  POLL_PERIOD = "10"
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
----------------------------------------
-- Debug
----------------------------------------

local function debug(text, level, forced)
  if (forced == nil) then forced = false end
  if true then -- TODO remove this and use condition on line 2
--  if (PLUGIN.DEBUG_MODE or (forced == true)) then
    if (#text < 7000) then
      if (level == nil) then
        luup.log((text or "NIL"))
      else
        luup.log((text or "NIL"), level)
      end
    else
      -- split the output into multiple debug lines
      local prefix_string = ""
      local _, debug_prefix, _ = text:find("): ")
      if (debug_prefix) then
        prefix_string = text:sub(1, debug_prefix)
        text = text:sub(debug_prefix + 1)
      end
      while (#text > 0) do
        local debug_text = text:sub(1, 7000)
        text = text:sub(7001)
        if (level == nil) then
          luup.log((prefix_string .. (debug_text or "NIL")))
        else
          luup.log((prefix_string .. (debug_text or "NIL")), level)
        end
      end
    end
  end
end

----------------------------------------
-- Task
----------------------------------------

local TASK = {
  ERROR = 2,
  ERROR_PERM = -2,
  SUCCESS = 4,
  BUSY = 1
}

local function task(text, mode)
  if (text == nil) then text = "" end
  if (mode == nil) then mode = TASK.BUSY end
  debug("(" .. PLUGIN.NAME .. "::task) " .. (text or ""))
  if (mode == TASK.ERROR_PERM) then
    g_taskHandle = luup.task(text, TASK.ERROR, PLUGIN.NAME, g_taskHandle)
  else
    g_taskHandle = luup.task(text, mode, PLUGIN.NAME, g_taskHandle)

    -- Clear the previous error, since they're all transient.
    if (mode ~= TASK.SUCCESS) then
      luup.call_delay("clearTask", 30, "", false)
    end
  end
end

function clearTask()
  task("Clearing...", TASK.SUCCESS)
  return true
end

----------------------------------------
-- Utilities
----------------------------------------

local UTILITIES = {
  padLeft = function(self, s, length, char)
    s = tostring(s)
    return char:rep(length - #s) .. s
  end,
  SecondsToHMS = function(self, seconds)
    seconds = tonumber(seconds, 10)
    if (seconds == nil) then return "0" end
    local HH = math.floor(seconds / (60 * 60))
    local MM = math.floor(seconds / 60) % 60
    local SS = seconds % 60
    return self:padLeft(HH, 2, "0") .. ":" .. self:padLeft(MM, 2, "0") .. ":" .. self:padLeft(SS, 2, "0")
  end,
  arraySize = function(self, arr)
    if (arr == nil) then return 0 end
    local n = 0
    for x, v in pairs(arr) do n = n + 1 end
    return n
  end,
  urlEncode = function(self, str)
    if (str) then
      str = string.gsub(str, "\n", "\r\n")
      str = string.gsub(str, "([^%w %-%_%.%~])",
        function(c) return string.format("%%%02X", string.byte(c)) end)
      str = string.gsub(str, " ", "+")
    end
    return str
  end,
  getMiosVersion = function(self)
    local mios_branch = luup.version_branch
    local mios_major = luup.version_major
    local mios_minor = luup.version_minor
    local vera_model = luup.attr_get("model", 0)
    debug("(" .. PLUGIN.NAME .. "::UTILITIES::getMiosVersion): vera_model [" .. (vera_model or "NIL") .. "] mios_branch [" .. (mios_branch or "NIL") .. "] mios_major [" .. (mios_major or "NIL") .. "] mios_minor [" .. (mios_minor or "NIL") .. "].", 2)
    if (tonumber(mios_branch, 10) == 1) then
      if (tonumber(mios_major, 10) == 5) then
        PLUGIN.MIOS_VERSION = "UI5"
      elseif (tonumber(mios_major, 10) == 7) then
        PLUGIN.MIOS_VERSION = "UI7"
      elseif (tonumber(mios_major, 10) == 6) then
        debug("(" .. PLUGIN.NAME .. "::UTILITIES::getMiosVersion): MIOS_VERSION is UI6.", 2)
        local emulate = getVariable(VERA.SID["SENSEME"], "UI6mode", lug_device)
        if ((emulate == "UI5") or (emulate == "UI7")) then
          debug("(" .. PLUGIN.NAME .. "::UTILITIES::getMiosVersion): MIOS_VERSION is UI6 - using " .. (emulate or "NIL") .. " parameters.", 2)
          PLUGIN.MIOS_VERSION = emulate
        else
          PLUGIN.MIOS_VERSION = "unknown"
        end
      else
        PLUGIN.MIOS_VERSION = "unknown"
      end
    else
      PLUGIN.MIOS_VERSION = "unknown"
    end

    if ((self:file_exists("/mios/usr/bin/cmh_Reset.sh") == false) and (self:file_exists("/etc/cmh-ludl/openLuup/init.lua") == true)) then
      log("(" .. PLUGIN.NAME .. "::getMiosVersion): PLUGIN is running under openluup.", 2)
      PLUGIN.OPENLUUP = true
      -- verify the openluup.io version and enable LIP if newer that 2016.01.26
      INITversion = self:shellExecute('head -n 3 /etc/cmh-ludl/openLuup/init.lua |grep -e "revisionDate ="')
      _, _, init_year, init_month, init_day = INITversion:find("(%d+)\.(%d+)\.(%d+)")
      init_datestamp = (init_year * 372) + ((init_month - 1) * 31) + init_day
      IOversion = self:shellExecute('head -n 3 /etc/cmh-ludl/openLuup/io.lua |grep -e "revisionDate ="')
      _, _, io_year, io_month, io_day = IOversion:find("(%d+)\.(%d+)\.(%d+)")
      io_datestamp = (io_year * 372) + ((io_month - 1) * 31) + io_day
      log("(" .. PLUGIN.NAME .. "::getMiosVersion): openluup.io datestamp [" .. (io_year or "NIL") .. "." .. (io_month or "NIL") .. "." .. (io_day or "NIL") .. "] [" .. (io_datestamp or "NIL") .. "]", 2)
      if (io_datestamp < 749978) then
        log("(" .. PLUGIN.NAME .. "::getMiosVersion): LIP mode is disabled.", 2)
        PLUGIN.DISABLE_LIP = true
      end
      if (init_datestamp > 750007) then
        log("(" .. PLUGIN.NAME .. "::getMiosVersion): OpenLuup v7 Icon fix enabled.", 2)
        PLUGIN.OPENLUUP_ICONFIX = true
      end
    end
    log("(" .. PLUGIN.NAME .. "::getMiosVersion): MIOS_VERSION [" .. (PLUGIN.MIOS_VERSION or "NIL") .. "].", 2)
  end,
  file_exists = function(self, filename)
    local file = io.open(filename)
    if (file) then
      io.close(file)
      return true
    else
      return false
    end
  end,
  string_empty = function(self, string)
    return string == nil or string == ""
  end,
  string_split = function(self, str, sep)
    local array = {}
    local reg = string.format("([^%s]+)", sep) or ""
    for mem in string.gmatch(str, reg) do
      table.insert(array, mem)
    end
    return array
  end,
  encode_json = function(self, arr)
    if (arr == nil) then
      return ""
    end
    local str = ""
    if (type(arr) == "table") then
      for index, value in pairs(arr) do
        if type(index) == "string" then
          str = str .. "\"" .. index .. "\": "
        end
        if type(value) == "table" then
          str = str .. self:encode_json(value) .. ","
        elseif type(value) == "boolean" then
          str = str .. (value and "true" or "false")
        elseif type(value) == "number" then
          str = str .. value
        else
          str = str .. "\"" .. value .. "\""
        end
        str = str .. ","
      end
    elseif (type(arr) == "number") then
      str = arr
    elseif ((type(arr) == "string") or (type(arr) == "number")) then
      str = "\"" .. arr .. "\""
    elseif (type(arr) == "boolean") then
      str = (arr and "TRUE" or "FALSE")
    end
    return ("{" .. str .. "}"):gsub(",,", ","):gsub(",]", "]"):gsub(",}", "}")
  end,
  decode_json = function(self, json)
    if (not json) then
      return nil
    end
    local str = {}
    local escapes = { r = '\r', n = '\n', b = '\b', f = '\f', t = '\t', Q = '"', ['\\'] = '\\', ['/'] = '/' }
    json = json:gsub('([^\\])\\"', '%1\\Q'):gsub('"(.-)"', function(s)
      str[#str + 1] = s:gsub("\\(.)", function(c) return escapes[c] end)
      return "$" .. #str
    end):gsub("%s", ""):gsub("%[", "{"):gsub("%]", "}"):gsub("null", "nil")
    json = json:gsub("(%$%d+):", "[%1]="):gsub("%$(%d+)", function(s)
      return ("%q"):format(str[tonumber(s)])
    end)
    return assert(loadstring("return " .. json))()
  end,
  getVariable = function(self, SID, variable, lul_device)
    debug("(" .. PLUGIN.NAME .. "::UTILITIES::getVariable) SID [" .. (SID or "NIL") .. "] variable [" .. (variable or "NIL") .. "] device [" .. (lul_device or lug_device or "NIL") .. "].")
    if (lul_device == nil) then lul_device = lug_device end
    if (variable == nil) then return end
    if (SID == nil) then return end
    local v = luup.variable_get(SID, variable, lul_device)
    debug(string.format("(" .. PLUGIN.NAME .. "::UTILITIES::getVariable) Got %s [%s].", (variable or "NIL"), (v or "NIL")))
    if (not v) then
      debug("(" .. PLUGIN.NAME .. "::UTILITIES::getVariable) WARNING: Failed to get the value of '" .. (variable or "NIL") .. "'.")
      return
    end
    return v
  end,
  setVariableDefault = function(self, SID, variable, default)
    if (type(default) == "boolean") then
      if (default) then
        default = "1"
      else
        default = "0"
      end
    end
    debug("(" .. PLUGIN.NAME .. "::setVariableDefault) SID [" .. (SID or "NIL") .. "] variable [" .. (variable or "NIL") .. "] default [" .. (default or "NIL") .. "].")
    if (variable == nil) then return end
    if (SID == nil) then return end
    local cValue = luup.variable_get(SID, variable, lug_device)
    if ((cValue == nil) or ((cValue == "") and (default ~= ""))) then
      -- only update the variable if it is currently not set OR if the current value is empty and the default value isn't
      debug(string.format("(" .. PLUGIN.NAME .. "::setVariableDefault) Setting %s [%s].", variable, (default or "nil")))
      luup.variable_set(SID, variable, default, lug_device)
      cValue = default
    end
    return cValue
  end,
  setVariable = function(self, SID, variable, value, lul_device)
    if (lul_device == nil) then lul_device = lug_device end
    if (type(value) == "boolean") then
      if (value) then
        value = "1"
      else
        value = "0"
      end
    end
    debug("(" .. PLUGIN.NAME .. "::UTILITIES::setVariable) SID [" .. (SID or "NIL") .. "] variable [" .. (variable or "NIL") .. "] value [" .. (value or "NIL") .. "] device [" .. (lul_device or "NIL") .. "].")
    if (variable == nil) then return end
    if (SID == nil) then return end
    local cValue = luup.variable_get(SID, variable, lul_device)
    if (not cValue) then cValue = "" end
    if (value ~= cValue) then
      debug(string.format("(" .. PLUGIN.NAME .. "::UTILITIES::setVariable) Setting %s [%s].", variable, (value or "nil")))
      luup.variable_set(SID, variable, value, lul_device)
    end
  end,
  setStatus = function(self, message)
    PLUGIN.BRIDGE_STATUS = message
    self:setVariable(VERA.SID["SENSEME"], "GATEWAY_STATUS", message, lug_device)
  end,
  shellExecute = function(self, cmd, Output)
    if (Output == nil) then Output = true end
    local file = assert(io.popen(cmd, 'r'))
    if (Output == true) then
      local cOutput = file:read('*all')
      file:close()
      return cOutput
    else
      file:close()
      return
    end
  end,
  print_r = function(self, arr, level)
    if (level == nil) then
      level = 0
    end
    if (arr == nil) then
      return ""
    end
    local str = ""
    local indentStr = string.rep("  ", level)
    if (type(arr) == "table") then
      for index, value in pairs(arr) do
        if type(value) == "table" then
          str = str .. indentStr .. index .. ": [\n" .. self:print_r(value, level + 1) .. indentStr .. "]\n"
        elseif type(value) == "boolean" then
          str = str .. indentStr .. index .. ": " .. (value and "TRUE" or "FALSE") .. "\n"
        elseif type(value) == "function" then
          str = str .. indentStr .. index .. ": FUNCTION(" .. self:print_r(value, level + 1) .. ")\n"
        else
          if ((not tonumber(index, 10)) and (index:find("updated_at") or index:find("changed_at"))) then
            str = str .. indentStr .. index .. ": " .. "(" .. value .. ") = " .. unixTimeToDateString(value) .. "\n"
          else
            str = str .. indentStr .. index .. ": " .. value .. "\n"
          end
        end
      end
    elseif ((type(arr) == "string") or (type(arr) == "number")) then
      str = arr
    elseif (type(arr) == "boolean") then
      str = (arr and "TRUE" or "FALSE")
    end
    return  str
  end
}

----------------------------------------
-- Settings
----------------------------------------

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
    UTILITIES:setVariableDefault(VERA.SID["SENSEME"], "pollPeriod", PLUGIN.POLL_PERIOD)
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

----------------------------------------
-- UDP
----------------------------------------

local SENSEME_UDP = {

  FAN_SPEED_INDEX = 5,
  LIGHT_LEVEL_INDEX = 5,
  MOTION_VALUE_INDEX = 4,
  LIGHT_SENSOR_VALUE_INDEX = 4,
  WHOOSH_VALUE_INDEX = 5,

  localIpAddress = "",

  sendCommand = function(self,command,senseMeIp)

    local socket = require "socket"
    if self.localIpAddress == "" then
      local udp = socket.udp()
      udp:settimeout(2)
      udp:setpeername("8.8.8.8", 31415) -- TODO put port, put google dns server in constant to get address
      self.localIpAddress = udp:getsockname()
      debug("("..PLUGIN.NAME.."::SENSEME_UDP::sendCommand) : local ip address initialized ["..(self.localIpAddress or "NIL").."].",2)
      udp:close()
    else
      debug("("..PLUGIN.NAME.."::SENSEME_UDP::sendCommand) : using ip address ["..(self.localIpAddress or "NIL").."].",2)
    end

    local udp = socket.udp()
    debug("("..PLUGIN.NAME.."::SENSEME_UDP::sendCommand) : getting socket", 2)
    udp:settimeout(2)
    udp:setsockname(self.localIpAddress, 31415)
    udp:setoption("broadcast",true)
    debug("("..PLUGIN.NAME.."::SENSEME_UDP::sendCommand) : setting options", 2)
    local ipAddress = senseMeIp
    if ipAddress == "" then
      ipAddress = "255.255.255.255"
    end
    debug("sendto: " .. udp:sendto("<" .. command .. ">", ipAddress, 31415)) -- TODO put as constants
    debug("("..PLUGIN.NAME.."::SENSEME_UDP::sendCommand) : sending",2)
    local response, msg = udp:receive()
    debug("("..PLUGIN.NAME.."::SENSEME_UDP::sendCommand) : received",2)
    if msg then
      debug("("..PLUGIN.NAME.."::SENSEME_UDP::sendCommand): Message:" .. msg)
    end
    udp:close()
    debug("("..PLUGIN.NAME.."::SENSEME_UDP::sendCommand): Command: " .. command .. " Response: " .. (response or "NIL"))
    return response
  end,
}
----------------------------------------
-- SenseMe
----------------------------------------

local SENSEME = {
  SENSEME_DEVICES = {
    {
      ID = "1",
      SENSEME_NAME = "Master Bedroom Fan",
      SENSEME_IP = "192.168.1.132",
      NAME = "Master Bedroom Fan",
      TYPE = "FAN",
      VID = 0, -- will be assigned during matching
    },
--    {
--      ID = "2",
--      SENSEME_NAME = "Master Bedroom Fan",
--      NAME = "Master Bedroom Fan Light",
--      TYPE = "DIMMER",
--      VID = 0, -- will be assigned during matching
--    },
    {
      ID = "3",
      SENSEME_NAME = "Living Room Fan",
      SENSEME_IP = "192.168.1.133",
      NAME = "Living Room Fan",
      TYPE = "FAN",
      VID = 0, -- will be assigned during matching
    },
    {
      ID = "4",
      SENSEME_NAME = "Cafe Fan",
      SENSEME_IP = "192.168.1.134",
      NAME = "Cafe Fan",
      TYPE = "FAN",
      VID = 0, -- will be assigned during matching
    },
    {
      ID = "5",
      SENSEME_NAME = "Spa Fan",
      SENSEME_IP = "192.168.1.139",
      NAME = "Spa Fan",
      TYPE = "FAN",
      VID = 0, -- will be assigned during matching
    },
  },

  -- compile a list of configured devices and store in upnp variable
  buildDeviceSummary = function(self)
    debug("(" .. PLUGIN.NAME .. "::buildDeviceSummary): building device summary.", 2)

    local html = ""
-- TODO reactivate this
--    if ((PLUGIN.FILES_VALIDATED == false) and (PLUGIN.OPENLUUP == false)) then
--      html = html .. "<h2>Installation error</h2><p>Mismatched Files</p>"
--      html = html .. "<ul><li>" .. PLUGIN.mismatched_files_list:gsub(",", "</li><li>") .. "</li></ul><br>"
--    end
    if (self.SENSEME_DEVICES and (#self.SENSEME_DEVICES > 0) and self.SENSEME_DEVICES[1]) then
      html = html .. "<h2>Devices:</h2><ul class='devices'>"
      -- add devices
      for k, DEV in pairs(self.SENSEME_DEVICES) do

        -- display the devices
        debug("(" .. PLUGIN.NAME .. "::buildDeviceSummary): Scanning device [" .. DEV.SENSEME_NAME .. "].")
        if (DEV.TYPE == "Gateway") then
        else
          html = html .. "<li class='wDevice'><b>Vera ID (VID):" .. DEV.VID .. " [" .. DEV.TYPE .. "] " .. DEV.NAME .. "</b><br>"
          html = html .. "<table><tr><td>SenseMe Name:</td><td>" .. DEV.SENSEME_NAME .. "</td></tr>"
          html = html .. "<tr><td>Internal ID:</td><td>" .. DEV.ID .. "</td></tr></table>"
          html = html .. "</li>"
        end
      end
      html = html .. "</ul><br>"
    else
      html = html .. "<h2>Issue building device summary.</h2>"
      -- TODO complete this
--      -- error with installation
--      if (PLUGIN.BRIDGE_STATUS == "User Intervention Required...") then
--        html = html .. "<h2>Bridge device not selected.</h2>"
--      elseif (PLUGIN.BRIDGE_STATUS == "No Bridge Found") then
--        if (PLUGIN.mqttParameters == nil) then
--          html = html .. "<h2>Bridge not found.</h2>"
--        else
--          html = html .. "<h2>Bridge specified by Lutron Account not found on local network.</h2>"
--        end
--      elseif (PLUGIN.BRIDGE_STATUS == "Failed to load bridge config") then
--        html = html .. "<h2>Could not load Bridge Configuration.</h2>"
--      elseif (PLUGIN.BRIDGE_STATUS == "Startup Failed!") then
--        html = html .. "<h2>Could not process Bridge Configuration.</h2>"
--      else
--        html = html .. "<h2>An unspecified error occurred.</h2>"
--      end
    end

    debug("(" .. PLUGIN.NAME .. "::buildDeviceSummary): Device summary html [" .. html .. "].")
    UTILITIES:setVariable(VERA.SID["SENSEME"], "DEVICE_SUMMARY", html)
  end,
  appendDevices = function(self, device)
    log("(" .. PLUGIN.NAME .. "::SENSEME::appendDevices): Preparing for update/append of Vera devices...", 2)
    local added = false
    local veraDevices = {}

    -- add/update devices - cache the scan results before committing in case of error

    for idx, dev in pairs(self.SENSEME_DEVICES) do
      debug("(" .. PLUGIN.NAME .. "::SENSEME::appendDevices):   Processing device [" .. (dev.NAME or "NIL") .. "] type [" .. (dev.TYPE or "NIL") .. "]")
      local devId = "SenseMe_" .. dev.TYPE .. "_" .. dev.ID
      if (VERA.DEVTYPE[dev.TYPE] ~= nil) then
        local devParams = ""
        if (dev.TYPE == "DIMMER") then
          devParams = "urn:upnp-org:serviceId:Dimming1,RampTime=0"
        end
        if (dev.TYPE == "FAN") then
          devParams = "urn:upnp-org:serviceId:Dimming1,RampTime=0"
        end
        veraDevices[#veraDevices + 1] = { devId, dev.NAME, VERA.DEVTYPE[dev.TYPE][1], VERA.DEVTYPE[dev.TYPE][2], "", devParams, false }
        if (dev.VID == 0) then
          added = true
        else
          if (dev.TYPE == "DIMMER") then
            UTILITIES:setVariableDefault(VERA.SID["DIMMER"],"RampTime",0,dev.VID)
          end
          if (dev.TYPE == "FAN") then
            UTILITIES:setVariableDefault(VERA.SID["DIMMER"],"RampTime",0,dev.VID)
          end
        end
      else
        log("(" .. PLUGIN.NAME .. "::SENSEME::appendDevices): ERROR : Unknown device type [" .. (dev.TYPE or "NIL") .. "]!")
        return false, false
      end
    end

    -- scan is complete - do the actual updates

    log("(" .. PLUGIN.NAME .. "::SENSEME::appendDevices): veraDevices count [" .. #veraDevices .. "] veraDevices [" .. UTILITIES:print_r(veraDevices) .. "].", 2)
    if (#veraDevices > 0) then
      log("(" .. PLUGIN.NAME .. "::SENSEME::appendDevices): Attempting to update/append Vera devices...", 2)
      local ptr = luup.chdev.start(device)
      for idx, params in pairs(veraDevices) do
        luup.chdev.append(device, ptr, params[1], params[2], params[3], params[4], params[5], params[6], params[7])
      end
      luup.chdev.sync(device, ptr)
      log("(" .. PLUGIN.NAME .. "::SENSEME::appendDevices): Updated/Appended Vera devices...", 2)
    else
      debug("(" .. PLUGIN.NAME .. "::SENSEME::appendDevices): Configuration error - No devices to process.", 1)
      return false, false
    end

    if (added) then
      log("(" .. PLUGIN.NAME .. "::SENSEME::appendDevices): Device(s) added. RESTART pending!", 1)
    else
      log("(" .. PLUGIN.NAME .. "::SENSEME::appendDevices): Device(s) updated", 2)
    end

    return true, added
  end,
  findDeviceIndex = function(self, devNum)
    for idx,dev in pairs(self.SENSEME_DEVICES) do
     if (tonumber(dev.ID,10) == tonumber(devNum,10)) then
        return idx
      end
    end
    return  0
  end,
  associateDevices = function(self, device)

    debug("("..PLUGIN.NAME.."::SENSEME::associateDevices): Scanning child devices.")

    -- match reported devices to vera devices

    for idx,vDev in pairs(luup.devices) do
      if (vDev.device_num_parent == lug_device) then
        debug("("..PLUGIN.NAME.."::SENSEME::associateDevices):  Processing device ["..(idx or "NIL").."] id ["..(vDev.id or "NIL").."].")
        local _,_, devType, devNum = vDev.id:find("SenseMe_(%w-)_(%d+)")

        if ((devType == nil) and (devNum == nil)) then
          _,_,devNum = vDev.id:find("(%d+)")
          devType = ""
        end
        debug("("..PLUGIN.NAME.."::SENSEME::associateDevices):    Scanned device ["..(idx or "NIL").."] id ["..(vDev.id or "NIL").."] - type ["..(devType or "NIL").."] num ["..(devNum or "NIL").."].")
        if ((devType ~= nil) and (devNum ~= nil)) then
          -- detect a physical device
          local dIdx = self:findDeviceIndex(devNum)
          debug("("..PLUGIN.NAME.."::SENSEME::associateDevices):        Found SenseMe device ["..(dIdx or "NIL").."].")
          if (dIdx > 0) then
            self.SENSEME_DEVICES[dIdx].VID = idx
            debug("("..PLUGIN.NAME.."::SENSEME::associateDevices):        Updated SenseMe device ["..(dIdx or "NIL").."] with Vera id ["..(idx or "NIL").."].")
          end
        end
      end
    end
  end,
  startPolling = function(self)
    luup.call_delay("poll", 5, PLUGIN.POLL_PERIOD)
  end,

  setUI = function(self,parameters, cmdType)
        debug("("..PLUGIN.NAME.."::SENSEME::setUI): Proceesing UI update - command type ["..(cmdType or "NIL").."] params [\n"..UTILITIES:print_r(parameters).."].")
        local devType = ""
        local devName = ""
        local devIdx = -1
        local id = -1
        local index = 1
        for idx,dev in pairs(self.SENSEME_DEVICES) do
          local devID = dev.ID
          if (tonumber(devID,10) == tonumber(parameters[index],10)) then
            devType = dev.TYPE
            devName = dev.NAME
            devIdx = idx
            id = dev.VID
            break
          end
        end
        if (id == -1) then
          debug("("..PLUGIN.NAME.."::SENSEME::setUI): ERROR : Could not find Vera device for SenseMe ID ["..(parameters[index] or "NIL").."].",1)
          return
        end
        debug("("..PLUGIN.NAME.."::SENSEME::setUI): Processing index ["..(index or "NIL").."] device ID ["..(parameters[1] or "NIL").."] TYPE ["..(devType or "NIL").."] VID ["..id.."] NAME ["..(devName or "NIL").."].")
        if cmdType == "MOTION" then
          index = index + 1
          debug("("..PLUGIN.NAME.."::SENSEME::setUI): Processing MOTION command - index ["..(index or "NIL").."]...")
          if (tonumber(parameters[index],10) == 1) then
            if (devType == "FAN") then
              if (parameters and parameters[index + 1]) then
                local var = parameters[index + 1]
                debug("("..PLUGIN.NAME.."::SENSEME::setUI): Setting FAN - VAR ["..(var or "NIL").."].")
                UTILITIES:setVariable(VERA.SID["FAN"],"Motion", var, id)
              else
                debug("("..PLUGIN.NAME.."::SENSEME::setUI): FAN : ERROR processing parameters.",1)
              end
            else
              debug("("..PLUGIN.NAME.."::SENSEME::setUI): ERROR! : Unknown command type! ")
            end
          end
        end
        if cmdType == "LIGHT_SENSOR" then
          index = index + 1
          debug("("..PLUGIN.NAME.."::SENSEME::setUI): Processing LIGHT_SENSOR command - index ["..(index or "NIL").."]...")
          if (tonumber(parameters[index],10) == 1) then
          if (devType == "FAN") then
            if (parameters and parameters[index + 1]) then
              local var = parameters[index + 1]
              debug("("..PLUGIN.NAME.."::SENSEME::setUI): Setting FAN - VAR ["..(var or "NIL").."].")
              UTILITIES:setVariable(VERA.SID["FAN"],"LightSensor", var, id)
            else
              debug("("..PLUGIN.NAME.."::SENSEME::setUI): FAN : ERROR processing parameters.",1)
            end
          else
            debug("("..PLUGIN.NAME.."::SENSEME::setUI): ERROR! : Unknown command type! ")
          end
          end
        end
        if cmdType == "WHOOSH" then
          index = index + 1
          debug("("..PLUGIN.NAME.."::SENSEME::setUI): Processing WHOOSH command - index ["..(index or "NIL").."]...")
          if (tonumber(parameters[index],10) == 1) then
          if (devType == "FAN") then
            if (parameters and parameters[index + 1]) then
              local var = parameters[index + 1]
              debug("("..PLUGIN.NAME.."::SENSEME::setUI): Setting FAN - VAR ["..(var or "NIL").."].")
              UTILITIES:setVariable(VERA.SID["FAN"],"Whoosh", var, id)
            else
              debug("("..PLUGIN.NAME.."::SENSEME::setUI): FAN : ERROR processing parameters.",1)
            end
          else
            debug("("..PLUGIN.NAME.."::SENSEME::setUI): ERROR! : Unknown command type! ")
          end
          end
        end
        if cmdType == "OUTPUT" then
          index = index + 1
          debug("("..PLUGIN.NAME.."::SENSEME::setUI): Processing OUTPUT command - index ["..(index or "NIL").."]...")
          if (tonumber(parameters[index],10) == 1) then
            if (devType == "DIMMER") then
              if (parameters and parameters[index + 1]) then
                local var = math.floor(tonumber(parameters[index + 1],10))
                debug("("..PLUGIN.NAME.."::SENSEME::setUI): Setting DIMMER - VAR ["..(var or "NIL").."].")
                if (var == 0) then
                  UTILITIES:setVariable(VERA.SID["DIMMER"],"LoadLevelStatus", "0", id)
                  UTILITIES:setVariable(VERA.SID["SWITCH"],"Status","0",id)
                else
                  UTILITIES:setVariable(VERA.SID["DIMMER"],"LoadLevelStatus", var, id)
                  UTILITIES:setVariable(VERA.SID["SWITCH"],"Status","1",id)
                  debug("("..PLUGIN.NAME.."::SENSEME::setUI): DIMMER : Vera device has been updated.")
                end
              else
                debug("("..PLUGIN.NAME.."::SENSEME::setUI): DIMMER : ERROR processing parameters.",1)
              end
            elseif (devType == "FAN") then
              if (parameters and parameters[index + 1]) then
                local var = math.floor(tonumber(parameters[index + 1],10))
                debug("("..PLUGIN.NAME.."::SENSEME::setUI): Setting FAN - VAR ["..(var or "NIL").."].")
                if (var == 0) then
                  UTILITIES:setVariable(VERA.SID["DIMMER"],"LoadLevelStatus", "0", id)
                  UTILITIES:setVariable(VERA.SID["SWITCH"],"Status","0",id)
                else
                  UTILITIES:setVariable(VERA.SID["DIMMER"],"LoadLevelStatus", var, id)
                  UTILITIES:setVariable(VERA.SID["SWITCH"],"Status","1",id)
                  debug("("..PLUGIN.NAME.."::SENSEME::setUI): DIMMER : Vera device has been updated.")
                end
              else
                debug("("..PLUGIN.NAME.."::SENSEME::setUI): DIMMER : ERROR processing parameters.",1)
              end
            else
              debug("("..PLUGIN.NAME.."::SENSEME::setUI): ERROR! : Unknown command type! ")
            end
          end
        end
    debug("("..PLUGIN.NAME.."::SENSEME_UDP::setUI): Processing COMPLETE.")
  end,

  fanSpeedForLoadLevel = function(self, loadLevel)
--    local fanSpeed = loadLevel * 7 / 100
    local fanSpeed = tonumber(loadLevel)
    if fanSpeed < 0 then
      fanSpeed = 0
    end
    if fanSpeed > 7 then
      fanSpeed = 7
    end
    return fanSpeed
  end,

  loadLevelForFanSpeed = function(self,fanSpeed)
--    local loadLevel = fanSpeed * 100 / 7
    local loadLevel = tonumber(fanSpeed)
    if loadLevel < 0 then
      loadLevel = 0
    end
    if loadLevel > 7 then
      loadLevel = 7
    end
    return loadLevel
  end,

  dimmerForLoadLevel = function(self, loadLevel)
    local lightLevel = loadLevel * 16 / 100
    if lightLevel < 0 then
      lightLevel = 0
    end
    if lightLevel > 16 then
      lightLevel = 16
    end
    return lightLevel
  end,

  loadLevelForDimmer = function(self,lightLevel)
    local loadLevel = lightLevel * 100 / 16
    if loadLevel < 0 then
      loadLevel = 0
    end
    if loadLevel > 100 then
      loadLevel = 100
    end
    return loadLevel
  end,

  varValueFromSenseMe = function(self, senseMe)
    local varValue = "1"
    if senseMe == "OFF" then
      varValue = "0"
    end
    return varValue
  end,

  senseMeValueFromVar = function(self, varValue)
    local senseMeValue = "ON"
    if varValue == "0" then
      senseMeValue = "OFF"
    end
    return senseMeValue
  end,

  respponseElements = function(self, response)
    local responseTrimmed = response:sub(2, -2)
    local responseElements = UTILITIES:string_split(responseTrimmed,";")
    return responseElements
  end,
}

poll = function(value)
  debug("("..PLUGIN.NAME.."::SENSEME::poll): Checking status")

  -- get status for all devices

  local devID = -1
  for idx,dev in pairs(SENSEME.SENSEME_DEVICES) do
    local devID = dev.ID
    -- TODO reactivate code below
--    if (dev.TYPE == "DIMMER") then
--    local response = SENSEME_UDP:sendCommand(dev.SENSEME_NAME .. ";LIGHT;LEVEL;GET;ACTUAL", dev.SENSEME_IP)
--    if not UTILITIES:string_empty(response) then
--      local responseElements = SENSEME:respponseElements(response)
--      -- TODO check if it is the same device name
--      -- TODO better error management so we can skip updates when we miss
--      (Livin
--      0x0030:  6720 526f 6f6d 2046 616e 3b44 4556 4943  g.Room.Fan;DEVIC
--      0x0040:  453b 4c49 4748 543b 4e4f 5420 5052 4553  E;LIGHT;NOT.PRES
--      0x0050:  454e 5429                                ENT
--
--      local fanSpeed = responseElements[SENSEME_UDP.LIGHT_LEVEL_INDEX]
--      -- TODO cache the value to avoid setting the UI at every poll
--      local level = SENSEME:loadLevelForDimmer(fanSpeed)
--      local params = {devID,1,level}
--      SENSEME:setUI(params,"OUTPUT")
--    end
    if (dev.TYPE == "FAN") then

      -- get speed

      local response = SENSEME_UDP:sendCommand(dev.SENSEME_NAME .. ";FAN;SPD;GET;ACTUAL", dev.SENSEME_IP)
      if not UTILITIES:string_empty(response) then
        local responseElements = SENSEME:respponseElements(response)
        local fanSpeed = responseElements[SENSEME_UDP.FAN_SPEED_INDEX]
        local level = SENSEME:loadLevelForFanSpeed(fanSpeed)
        local params = {devID,1,level}
        SENSEME:setUI(params,"OUTPUT")
      end

      -- get motion

      local response = SENSEME_UDP:sendCommand(dev.SENSEME_NAME .. ";FAN;AUTO;GET", dev.SENSEME_IP)
      if not UTILITIES:string_empty(response) then
        local responseElements = SENSEME:respponseElements(response)
        local senseMeValue = responseElements[SENSEME_UDP.MOTION_VALUE_INDEX]
        local motion = SENSEME:varValueFromSenseMe(senseMeValue)
        local params = {devID,1,motion}
        SENSEME:setUI(params,"MOTION")
      end

      -- get light sensor

      local response = SENSEME_UDP:sendCommand(dev.SENSEME_NAME .. ";LIGHT;AUTO;GET", dev.SENSEME_IP)
      if not UTILITIES:string_empty(response) then
        local responseElements = SENSEME:respponseElements(response)

        local senseMeValue = responseElements[SENSEME_UDP.LIGHT_SENSOR_VALUE_INDEX]
        if senseMeValue ~= "NOT PRESENT" then
          local lightSensor = SENSEME:varValueFromSenseMe(senseMeValue)
          local params = {devID,1,lightSensor}
          SENSEME:setUI(params,"LIGHT_SENSOR")
        end
      end

      -- get whoosh

      local response = SENSEME_UDP:sendCommand(dev.SENSEME_NAME .. ";FAN;WHOOSH;GET;STATUS", dev.SENSEME_IP)
      if not UTILITIES:string_empty(response) then
        local responseElements = SENSEME:respponseElements(response)

        local senseMeValue = responseElements[SENSEME_UDP.WHOOSH_VALUE_INDEX]
        local whoosh = SENSEME:varValueFromSenseMe(senseMeValue)
        local params = {devID,1,whoosh}
        SENSEME:setUI(params,"WHOOSH")
      end

    end
  end

  -- schedule next call

  local period = tonumber(value)
  if (period > 0) then
    luup.call_delay("poll", period, value)
  end
  debug("("..PLUGIN.NAME.."::SENSEME::poll): Status command sent")
end

----------------------------------------
-- Startup
----------------------------------------

function Init(lul_device)
  UTILITIES:setStatus("Initializing devices...")
  SENSEME:associateDevices(lul_device)
  local ret, added = SENSEME:appendDevices(lul_device)
  SENSEME:associateDevices(lul_device)

  SENSEME:buildDeviceSummary()
  SENSEME:startPolling()

  --
--  if (ret == false) then
--    return false, "Failed to add devices", "SenseMe Gateway"
--  end
--  if (added == true) then
--    log("(" .. PLUGIN.NAME .. "::Init): Startup Successful. Restart pending. ", 1)
--    return true, "Devices added. RESTART pending.", "SenseMe Gateway"
--  end
--  -- HERE
--
--  UTILITIES:setStatus("Initializing IO...")
--  if ((CASETA["LIP"].ENABLED == true) and (PLUGIN.DISABLE_LIP == false)) then
--    UTILITIES:setStatus("Initializing LIP connection...")
--    if (luup.io.is_connected(lug_device) == false) then
--      log("(" .. PLUGIN.NAME .. "::Init): Connecting to Smart Bridge LIP server @ " .. (PLUGIN.BRIDGE_IP or "NIL") .. ":23.")
--      PLUGIN.LIP_LOGIN_COMPLETE = false
--      local tries = 0
--      PLUGIN.LUUP_IO_MODE = "LIP"
--      luup.io.open(lug_device, PLUGIN.BRIDGE_IP, 23)
--      --luup.call_delay("do_LIP_Login",1,"")
--      -- schedule start of the periodic status sync loop
--      luup.sleep(250)
--    end
--    if (luup.io.is_connected(lug_device) == false) then
--      log("(" .. PLUGIN.NAME .. "::Init): Failed to connect to Smart Bridge LIP server @ " .. (PLUGIN.BRIDGE_IP or "NIL") .. ":23.")
--      return false, "Failed to connect to LIP server.", "Caseta Connect"
--    else
--      log("(" .. PLUGIN.NAME .. "::Init): Connection to LIP server established.")
--      -- get initial device status
--      getStatusLEAP(0)
--      luup.call_delay("getStatusLIP", 5, PLUGIN.pollPeriod)
--    end
--  else
--    -- test the remote connection and get the mqtt parameters
--    local mqttStatus, mqttError, mqttParameters = false, "", PLUGIN.mqttParameters
--    if (mqttParameters ~= nil) then
--      mqttStatus = true
--    else
--      mqttStatus, mqttError, mqttParameters = Get_MQTT_Parameters()
--    end
--    --mqttStatus = false
--    local polling_required = true
--    if (mqttStatus == true) then
--      UTILITIES:setStatus("Initializing MQTT connection...")
--      -- start the mqtt service
--      log("(" .. PLUGIN.NAME .. "::Init): LIP server not available... Lutron credentials provided... using MQTT...")
--      PLUGIN.mqttParameters = mqttParameters
--      log("(" .. PLUGIN.NAME .. "::Init): Bridge MAC [" .. (PLUGIN.mqttParameters.serial or "NIL") .. "] MQTT MAC [" .. (PLUGIN.BRIDGE_MAC or "NIL") .. "].")
--      if (PLUGIN.mqttParameters.serial == PLUGIN.BRIDGE_MAC:gsub(":", "")) then
--        PLUGIN.LUUP_IO_MODE = "MQTT"
--        --				MQTT_CLIENT = MQTT.client.create("v3mqtt.xively.com", 1883, Process_MQTT_Response)
--        MQTT_CLIENT = MQTT.client.create("lutron.broker.xively.com", 1883, Process_MQTT_Response)
--        MQTT_CLIENT:auth(mqttParameters.username, mqttParameters.password)
--        --				MQTT_CLIENT:connect(lug_device, "MQTT_Client")
--        MQTT_CLIENT:connect(lug_device, mqttParameters.username)
--        MQTT_CLIENT:subscribe({ PLUGIN.mqttParameters.IN, PLUGIN.mqttParameters.OUT, PLUGIN.mqttParameters.STATUS })
--        polling_required = false
--        -- start the MQTT keepalive timer
--        MQTT_KeepAlive()
--        -- get the initial device status
--        getStatusLEAP(0)
--      else
--        log("(" .. PLUGIN.NAME .. "::Init): MQTT ERROR - Bridge device is not associated with the provided Lutron account...", 1)
--      end
--    end
--    if (polling_required == true) then
--      UTILITIES:setStatus("Initializing device polling...")
--      log("(" .. PLUGIN.NAME .. "::Init): LIP server not available... using polling")
--      UTILITIES:setStatus("Initializing Polling...")
--      getStatusLEAP(PLUGIN.pollPeriod)
--    end
--  end
--
  log("(" .. PLUGIN.NAME .. "::Init) : Startup Successful ")
  return true, "Startup complete.", "SenseMe Gateway"
end

function Startup(lul_device)
  lug_device = lul_device
  log("(" .. PLUGIN.NAME .. "::Startup): ************** STARTING SENSEME GATEWAY **************", 2)

  UTILITIES:setStatus("Loading Options...")

  UTILITIES:getMiosVersion()
  if (PLUGIN.MIOS_VERSION == "unknown") then
    log("(" .. PLUGIN.NAME .. "::Startup): Unsupported MIOS version - EXITING!!.", 1)
    task("UNSUPPORTED MIOS VERSION.", TASK.ERROR_PERM)
    return false, "UNSUPPORTED MIOS VERSION.", PLUGIN.NAME
  end

  local isDisabled = luup.attr_get("disabled", lul_device)
  log("(" .. PLUGIN.NAME .. "::Startup): SenseMe Gateway - Plugin version [" .. (VERSION or "NIL") .. "] - isDisabled [" .. (isDisabled or "NIL") .. "] MIOS_VERSION [" .. (PLUGIN.MIOS_VERSION or "NIL") .. "]")
  if ((isDisabled == 1) or (isDisabled == "1")) then
    log("(" .. PLUGIN.NAME .. "::Startup):Plugin version " .. (VERSION or "NIL") .. " - DISABLED", 2)
    PLUGIN.PLUGIN_DISABLED = true
    -- mark device as disabled
    UTILITIES:setStatus("DISABLED")
    log("(" .. PLUGIN.NAME .. "::Startup): Marking SenseMe device: " .. (lul_device or "NIL") .. " as disabled.", 2)
    task("Plugin DISABLED.", TASK.ERROR)
    return true, "Plugin Disabled.", PLUGIN.NAME
  end

  UTILITIES:setStatus("Validating...")
--  FILE_MANIFEST:Validate() -- TODO need to finish this
  getPluginSettings()
  UTILITIES:setStatus("Creating Icons...")
--  ICONS:CreateIcons() -- TODO need proper icons

  -- need to get the list of devices dynamically. for now, we can configure by hand

  debug("(" .. PLUGIN.NAME .. "::Startup): found Devices [" .. UTILITIES:print_r(SENSEME_DEVICES) .. "]")
  local ret, msg, modname = Init(lul_device)
  if (ret == true) then
    log("(" .. PLUGIN.NAME .. "::Startup): \n*************************\n** Startup sucessful  **\n*************************\n", 2)
    UTILITIES:setStatus("Ready")
  else
    UTILITIES:setStatus("Startup Failed!")
    log("(" .. PLUGIN.NAME .. "::Startup): Startup FAILED", 1)
    -- build device summary to display installation errors
    SENSEME:buildDeviceSummary()
    task("Could not initialize plugin.", TASK.ERROR_PERM)
  end
  return true, msg, modname
end

----------------------------------------
-- Actions
----------------------------------------

SENSEME_ACTIONS = {
  SetMotion = function(self, lul_device, motionOnOrOff)
    debug("(" .. PLUGIN.NAME .. "::SENSEME_ACTIONS::SetMotion): device [" .. (lul_device or "NIL") .. "] motionOnOrOff [" .. (motionOnOrOff or "NIL") .. "]", 1)
    for idx,dev in pairs(SENSEME.SENSEME_DEVICES) do
      if dev.VID == lul_device then
        if (dev.TYPE == "FAN") then
           local motionValue = SENSEME:senseMeValueFromVar(motionOnOrOff)
           local response = SENSEME_UDP:sendCommand(dev.SENSEME_NAME .. ";FAN;AUTO;" .. motionValue, dev.SENSEME_IP)
           local params = {dev.ID,1,motionOnOrOff}
           SENSEME:setUI(params,"MOTION")
           break
        end
      end
    end
    return 4, 0
  end,
  SetLightSensor = function(self, lul_device, lightSensorOnOrOff)
    debug("(" .. PLUGIN.NAME .. "::SENSEME_ACTIONS::SetLightSensor): device [" .. (lul_device or "NIL") .. "] lightSensorOnOrOff [" .. (lightSensorOnOrOff or "NIL") .. "]", 1)
    for idx,dev in pairs(SENSEME.SENSEME_DEVICES) do
      if dev.VID == lul_device then
        if (dev.TYPE == "FAN") then
          local motionValue = SENSEME:senseMeValueFromVar(lightSensorOnOrOff)
          local response = SENSEME_UDP:sendCommand(dev.SENSEME_NAME .. ";FAN;AUTO;" .. motionValue, dev.SENSEME_IP)
          local params = {dev.ID,1,lightSensorOnOrOff}
          SENSEME:setUI(params,"LIGHT_SENSOR")
          break
        end
      end
    end
    return 4, 0
  end,
  SetWhoosh = function(self, lul_device, whooshOnOrOff)
    debug("(" .. PLUGIN.NAME .. "::SENSEME_ACTIONS::SetWhoosh): device [" .. (lul_device or "NIL") .. "] whooshOnOrOff [" .. (whooshOnOrOff or "NIL") .. "]", 1)
    for idx,dev in pairs(SENSEME.SENSEME_DEVICES) do
      if dev.VID == lul_device then
        if (dev.TYPE == "FAN") then
          local whooshValue = SENSEME:senseMeValueFromVar(whooshOnOrOff)
          local response = SENSEME_UDP:sendCommand(dev.SENSEME_NAME .. ";FAN;WHOOSH;" .. whooshValue, dev.SENSEME_IP)
          local params = {dev.ID,1,whooshOnOrOff}
          SENSEME:setUI(params,"WHOOSH")
          break
        end
      end
    end
    return 4, 0
  end,
  setTarget = function(self, lul_device, newTargetValue)
    return 4, 0
  end,
  StartRampToLevel = function(self, lul_device, newLoadLevelTarget, newRampTime)
    debug("(" .. PLUGIN.NAME .. "::SENSEME_ACTIONS::StartRampToLevel): device [" .. (lul_device or "NIL") .. "] newLoadLevelTarget [" .. (newLoadLevelTarget or "NIL") .. "] newRampTime [" .. (newRampTime or "NIL") .. "].", 1)
    return self:setLoadLevelTarget(lul_device, newLoadLevelTarget, newRampTime)
  end,
  setLoadLevelTarget = function(self, lul_device, newLoadLevelTarget, newRampTime)
    if (newLoadLevelTarget == nul) then
      debug("(" .. PLUGIN.NAME .. "::SENSEME_ACTIONS::setLoadLevelTarget): newLoadLevelTarget not specified.", 1)
      return 2, 0
    end

    -- TODO add support for dimmer as well
    for idx,dev in pairs(SENSEME.SENSEME_DEVICES) do
      if dev.VID == lul_device then
        if (dev.TYPE == "FAN") then
          local fanSpeed = SENSEME:fanSpeedForLoadLevel(newLoadLevelTarget)
          local response = SENSEME_UDP:sendCommand(dev.SENSEME_NAME .. ";FAN;SPD;SET;" .. fanSpeed, dev.SENSEME_IP)
          local params = {dev.ID,1,newLoadLevelTarget}
          SENSEME:setUI(params,"OUTPUT")
          break
        end
        if (dev.TYPE == "DIMMER") then
          local lightLevel = SENSEME:dimmerForLoadLevel(newLoadLevelTarget)
          local response = SENSEME_UDP:sendCommand(dev.SENSEME_NAME .. ";LIGHT;LEVEL;SET;" .. lightLevel, dev.SENSEME_IP)
          local params = {dev.ID,1,newLoadLevelTarget}
          SENSEME:setUI(params,"OUTPUT")
          break
        end
      end
    end

    debug("(" .. PLUGIN.NAME .. "::SENSEME_ACTIONS::setLoadLevelTarget): " .. newLoadLevelTarget, 2)
    return 4, 0
  end,
  DimUpDown = function(self, lul_device, dimDirection, dimPercent)
    return self:setLoadLevelTarget(lul_device, newLevel, 0)
  end,
  ToggleDebugMode = function(self, lul_device)
    if (PLUGIN.DEBUG_MODE == true) then
      PLUGIN.DEBUG_MODE = false
      UTILITIES:setVariable(VERA.SID["SENSEME"], "DebugMode", "0", lul_device)
      UTILITIES:setVariable(VERA.SID["SENSEME"], "DebugModeText", "DISABLED", lul_device)
      task("DEBUG MODE DISABLED!", TASK.SUCCESS)
    else
      PLUGIN.DEBUG_MODE = true
      UTILITIES:setVariable(VERA.SID["SENSEME"], "DebugMode", "1", lul_device)
      UTILITIES:setVariable(VERA.SID["SENSEME"], "DebugModeText", "ENABLED", lul_device)
      task("DEBUG MODE ENABLED!", TASK.SUCCESS)
    end
    log("(" .. PLUGIN.NAME .. "::toggleDebugMode) Debug mode now [" .. (PLUGIN.DEBUG_MODE and "ENABLED" or "DISABLED") .. "].")
  end,
}

