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
