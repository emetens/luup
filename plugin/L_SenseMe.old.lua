
local lug_device = nil

local log = luup.log

local function debug(text, level, forced)
  if (forced == nil) then forced = false end
  if (PLUGIN.DEBUG_MODE or (forced == true)) then
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

function shellExecute(cmd, Output)
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
end

local socket = require("socket")

local PROXY = nil

local g_taskHandle = -1

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

local VERA = {
  SID = {
    ["SENSEME"] = "urn:micasaverde-com:serviceId:SenseMe1",
    ["FAN"] = "urn:upnp-org:serviceId:FanSpeed1",
    ["DIMMER"] = "urn:upnp-org:serviceId:Dimming1",
  },
  DEVTYPE = {
    ["FAN"] = { "urn:schemas-upnp-org:device:SenseMeFan:1", "D_SenseMeFan1.xml" }, -- TODO create senseme fan device file
    ["DIMMER"] = { "urn:schemas-upnp-org:device:DimmableLight:1", "D_DimmableLight1.xml" },
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

local FILE_MANIFEST = {
  -- TODO compute the md5 of these files
  FILE_LIST = {
    ["D_SenseMe.json"] = "fcc7fd9ff9d52d4c494d91cccf74e905",
    ["D_SenseMe.xml"] = "87a99a8a521f7d685e2630e7537ad54f",
    ["D_SenseMeFan1.json"] = "e22047338d70f58519b601ee6fb90b6b",
    ["D_SenseMeFan1.xml"] = "1829ad3d42bb1178118ad63e7e609b7f",
    ["I_SenseMe.xml"] = "1e80efcd576d0e53ee067040bebea2e9",
    ["J_SenseMe.js"] = "e6c2128899f6d27e485bb3683c35f945",
    ["J_SenseMe.lua"] = "e6c2128899f6d27e485bb3683c35f945",
    ["L_SenseMe_socat.mipsel"] = "8a95f4e83737ccdff5fe3ad168c749a8",
    ["S_SenseMe.xml"] = "24b5881cc107811e6752c12c17ce2cba",
  },
  RemoveFile = function(self, fileName)
    local cmd = "rm -f /etc/cmh-ludl/" .. fileName .. ".lzo"
    local file = assert(io.popen(cmd, 'r'))
    local cOutput = file:read('*all')
    file:close()
    return cOutput:gsub("\r", ""):gsub("\n", "")
  end,
  CalculateMD5 = function(self, fileName)
    local cmd = "md5sum /etc/cmh-ludl/" .. fileName .. ".lzo|cut -d' ' -f 1"
    local file = assert(io.popen(cmd, 'r'))
    local cOutput = file:read('*all')
    file:close()
    return cOutput:gsub("\r", ""):gsub("\n", "")
  end,
  ValidateDevices = function(self)
    -- additional file test when running under openluup - notify user if device files are missing
    if (PLUGIN.OPENLUUP == false) then
      -- no need to test the device files on a real Vera
      return true, "NONE"
    end
    local isValid = true
    local uList = ""
    for idx, fName in pairs(VERA.DEVFILES) do
      if (UTILITIES:file_exists("/etc/cmh-ludl/" .. fName) == false) then
        -- files does not exist in /etc/cmh-ludl - see if it was downloaded by the openluup_getfiles utility
        if (UTILITIES:file_exists("/etc/cmh-ludl/files/" .. fName) == false) then
          isValid = false
          uList = uList .. fName .. ","
        else
          os.execute("cp /etc/cmh-ludl/files/" .. fName .. " /etc/cmh-ludl/.")
        end
      end
    end
    if (isValid == true) then uList = "NONE," end
    local iFiles = (uList:sub(1, #uList - 1) or "")
    PLUGIN.missing_device_files_list = iFiles
    debug("(" .. PLUGIN.NAME .. "::FILE_MANIFEST::ValidateDevices): Running under OpenLuup - Missing Device Files [" .. (iFiles or "NONE") .. "].", 2)
  end,
  Validate = function(self)
    if (PLUGIN.OPENLUUP == true) then
      PLUGIN.FILES_VALIDATED = false
      PLUGIN.mismatched_files_list = "FILE VALIDATION NOT SUPPORTED"
      debug("(" .. PLUGIN.NAME .. "::FILE_MANIFEST::Validate): Running under openluup. File Validation not supported.", 1)
      return
    end
    local isValid = true
    local fManifest = ""
    local uList = ""
    for fName, eMD5 in pairs(self.FILE_LIST) do
      if (eMD5 == "OBSOLETE") then
        self:RemoveFile(fName)
      else
        local fMD5 = self:CalculateMD5(fName)
        if (eMD5:sub(1, 1) == "M") then
          -- file is mutable - will be the generic file or the UI5 or UI7 specific version
          eMD5 = eMD5:sub(2, #eMD5)
          local nameUI = fName:gsub(".json", "_" .. PLUGIN.MIOS_VERSION .. ".json")
          local md5UI = self.FILE_LIST[nameUI]
          if ((eMD5 ~= fMD5) and (md5UI ~= fMD5)) then
            isValid = false
            uList = uList .. fName .. ","
            fManifest = fManifest .. "\t[\"" .. fName .. "\"] = \"" .. fMD5 .. "\",\n"
          end
        else
          if (eMD5 ~= fMD5) then
            isValid = false
            uList = uList .. fName .. ","
            fManifest = fManifest .. "\t[\"" .. fName .. "\"] = \"" .. fMD5 .. "\",\n"
          end
        end
      end
    end
    if (((fManifest ~= "") and (#fManifest ~= 1)) or (isValid == false)) then
      debug("(" .. PLUGIN.NAME .. "::FILE_MANIFEST::Validate) Manifest [\n" .. (fManifest:sub(1, #fManifest - 1) or "NIL") .. "\n].")
    end
    if (isValid == true) then uList = "NONE," end
    local iFiles = (uList:sub(1, #uList - 1) or "")
    luup.variable_set(VERA.SID["SENSEME"], "MISMATCHED_FILES", (iFiles or "NONE"), lug_device)
    PLUGIN.FILES_VALIDATED = isValid
    PLUGIN.mismatched_files_list = iFiles
    debug("(" .. PLUGIN.NAME .. "::FILE_MANIFEST::Validate): Plugin Files Validated [" .. (PLUGIN.FILES_VALIDATED and "TRUE" or "FALSE") .. "] invalid files [" .. (iFiles or "NONE") .. "].", 2)
  end
}


local ICONS = {
  ICON_LIST = {
    -- TODO have proper icons for the fans
    ["SenseMe.png"] = "89504E470D0A1A0A0000000D494844520000003C0000003C08030000000D222940000000017352474200AECE1CE90000000467414D410000B18F0BFC610500000300504C544500000003AFEC00AFED02B0ED05B0ED07B1EE08B1EE0AB2ED08B2EE0CB3EE0FB4EE12B4EE14B5EE15B5EF15B6EE16B6EF18B6EF1BB8EF1DB8EF20B9EF22BAEF24BAF029BCF02DBDF02FBEF030BEF032BFF136C0F139C1F13DC2F141C3F242C4F245C4F249C6F24CC7F24EC8F350C8F355C8F154C9F356CAF358CBF35ECCF460CDF461CEF466CFF468CFF468D0F46AD0F56CD1F56ED2F571D2F575D4F578D4F57DD6F680D7F682D8F684D8F687D9F787DAF788DAF689DAF78CDBF78EDCF790DCF795DEF796DEF899DFF89BE0F89DE0F8A0E1F8A4E2F8A5E3F9A8E4F9ADE5F9B2E7FAB4E7FAB6E8FAB8E9FABBEAFABCEAFAC1ECFBC5ECFBC9EEFBCFF0FCD2F1FCD6F2FCD9F3FCDBF4FCDDF4FDE0F5FDE2F6FDE5F6FDE8F8FDEBF9FEECF9FEEEFAFEF0FAFDF1FAFEF5FCFEFBFDFEF9FDFFFBFEFFFEFEFF000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000DD3167310000010074524E53FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0053F70725000000097048597300000EC300000EC301C76FA8640000001A74455874536F667477617265005061696E742E4E45542076332E352E313030F472A1000002C749444154484BED95EF5BD33010C7350DB36528251D0366276D41713011A71B5307084EF9A9D0B221D2D9D90AF7FFFF0778494B5B51D833F47978E1BE2F92CB359FBB24BDB477CEFF42B70B931B6900F7A901DCA706709FFA9770C602545D8E863DF42B6C0230EC60251CF6521ACEAC414E180C44D7532958D9818CF011BD6F986E8114FAC6211F1ABD94C055A0A1EB2EA8A17185A269A8189EEA84FBEDA9EAD3C84860091A91E72A417810F33BBF677E787A7D6209F88928C37A3B371C1D4D0237AE3CE0AC6845BA7B0001D6D0A8F0A02E60D8881C9735D9E6E5460D105557C31C71E218EE54238710AD60829AB0A088ADF609C7D88FBBEAE82A9A267F94C0DFD2F0086E30EB1968317887907A08446C195E4F61901937DC4AB2ECCD708C92C0D9265968532263902648B3F083E7A500DF55C7219C276C01835DC02BDD8BCA28C0387C28C1ECF124C01430175749DB1B2C8F77A6D97C70BA588175283C9B293E9E8961F5ABA82BFA082C891850E0594708AD01E8E8661841258A6F9045EC310E252A2BC630619B38816711E9FF28BDAB4456A418C6E3D0D8F51F01D5B9F43C05F7AF04A6B9B93C46CEF075537EB1A94C65AE21D1F1D25034159F0E89AA19C22686474AEF1BEB65261FF377B6758474DD5BF7B80EF778FBC5529A3EC0D113D2F2E609F9DC4EC3A5B7F3DA6CA3A27477D1BBE761F45530E72AB03D67D92DCB2A07FB5BF086151CD05D0874E27452307D51C5852D96D534CCF0AD2C1362B74C73C1AFF95D5CB3096BEEB17B3276097E85F0CB1A4BE0B518F66DBBE51B818B33386CEB81DD4AC364B96ADD2FD66B4AF7606262E2E3D9B43C6AFB7204DB788EEECA363CCF6A0750741D5202E828A612C34A63A3BEBA94973D5E29A543F002BF441298ECEE3FD885E0CC2B93131C36C0654B2C8649C6589AC46BAEE550B29437745E4E348717688CFF08144D22DAB48EDBD1C6F0F2E434FC4A24F00D3480FBD47F0CDF58B7059F9FFF046A843AFFD91AA9DD0000000049454E44AE426082",
  },
  file_exists = function(self, filename)
    local file = io.open(filename)
    if (file) then
      io.close(file)
      return true
    else
      return false
    end
  end,
  decode_hex_string = function(self, hexStr)
    if (not hexStr) then
      luup.log("(" .. PLUGIN.NAME .. "::ICONS::decode_hex_string) No hex data supplied.", 1)
      return nil
    end
    if (math.floor(#hexStr / 2) ~= (#hexStr / 2)) then
      luup.log("(" .. PLUGIN.NAME .. "::ICONS::decode_hex_string) Invalid hex data supplied.", 1)
      return nil
    end
    debug("(" .. PLUGIN.NAME .. "::ICONS::decode_hex_string) input size [" .. (#hexStr or "NIL") .. "].", 2)
    local i = 1
    local hexStr_len = hexStr:len()
    local VALUE = ""
    while i <= hexStr_len do
      local c = hexStr:sub(i, i + 1)
      VALUE = VALUE .. string.char(tonumber(c, 16))
      i = i + 2
    end
    debug("(" .. PLUGIN.NAME .. "::ICONS::decode_hex_string) output size [" .. (#VALUE or "NIL") .. "].", 2)
    return VALUE
  end,
  create_png = function(self, filename, data)
    -- data = hex encoded png file contents
    local png_data = self:decode_hex_string(data)
    if (png_data and (#png_data == (#data / 2))) then
      debug("(" .. PLUGIN.NAME .. "::ICONS::create_png): writing PNG Data for file [" .. (filename or "NIL") .. "]", 2)
      local file = io.open(filename, "wb")
      if (file) then
        file:write(png_data)
        file:close()
        return true
      else
        return false
      end
    else
      luup.log("(" .. PLUGIN.NAME .. "::ICONS::create_png): PNG Data DECODE ERROR", 1)
      return false
    end
  end,
  CreateIcons = function(self)
    local fPath = "/www/cmh/skins/default/icons/" -- UI5 icon file location
    if (PLUGIN.MIOS_VERSION == "UI7") then
      fPath = "/www/cmh/skins/default/img/devices/device_states/" -- UI7 icon file location
    end
    if (PLUGIN.OPENLUUP and PLUGIN.OPENLUUP_ICONFIX) then
      -- make sure the icons directory exists
      os.execute("mkdir /etc/cmh-ludl/icons")
      fPath = "/etc/cmh-ludl/icons/"
    end
    for fName, fData in pairs(self.ICON_LIST) do
      if (not self:file_exists(fPath .. fName)) then
        self:create_png(fPath .. fName, fData)
      end
    end
  end
}

----------------------------------------------------------
----------------------------------------------------------

local g_childDevices = {-- .id       -> vera id
  -- .integrationId -> lutron internal id
  -- .devType -> device type (dimmer, blinds , binary light or keypad)
  -- .fadeTime
  -- .componentNumber = {} -> only for keypads
}

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

