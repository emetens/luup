local VERSION = "0.10"

local IO_BUFFER = ""

local PLUGIN = {
  -- PLUGIN_ID = 8588,
  NAME = "SenseMe Gateway",
  MIOS_VERSION = "unknown",
  -- DISABLE_LIP = false,						-- this is a debugging option to allow testing MQTT with SmartBridge Pro
  -- DISABLE_MDNS = false,						-- this is a debugging option to allow testing of device discovery
  -- LIP_USERNAME = "",
  -- LIP_PASSWORD = "",
  -- LIP_LOGIN_COMPLETE = false,
  -- pollPeriod = "",
  -- pollPeriodOccupancy = "5",
  DEBUG_MODE = false,
  -- g_lastTripFlag = false,
  -- g_occupancyFlag = false,
  -- DEFAULT_MAC_FILTER= "ec:24:b8|68:c9:0b|68:9e:19",
  -- LUUP_IO_MODE = "NONE",
  -- BRIDGE_IP = "",
  -- BRIDGE_MAC = "",
  PLUGIN_DISABLED = false,
  FILES_VALIDATED = false,
  -- OPENLUUP = false,
  -- OPENLUUP_ICONFIX = false,
  -- SSH_KEYFILE = "",
  -- SSH_OPTIONS = "",
  -- mismatched_files_list = "",
  -- mqttParameters = nil,
  -- ARP_LOAD_TIMESTAMP = 0,
  -- BRIDGE_STATUS = ""
}

local MQTT_CLIENT = nil

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

----------------------------------------------------------------
----------------------------------------------------------------

local MQTTmodule = [[
---
-- @module L_Caseta_MQTT - MQTT for Vera IO system
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- based on paho mqtt_library Version: 0.3 2014-10-06
-- -------------------------------------------------------------------------- --
-- Copyright (c) 2011-2012 Geekscape Pty. Ltd.
-- All rights reserved. This program and the accompanying materials
-- are made available under the terms of the Eclipse Public License v1.0
-- which accompanies this distribution, and is available at
-- http://www.eclipse.org/legal/epl-v10.html
--
-- Contributors:
--    Andy Gelme    - Initial API and implementation
--    Kevin KIN-FOO - Authentication and rockspec
-- -------------------------------------------------------------------------- --
--
-- Documentation
-- ~~~~~~~~~~~~~
-- Paho MQTT Lua website
--   http://eclipse.org/paho/
--
-- References
-- ~~~~~~~~~~
-- MQTT Community
--   http://mqtt.org

-- MQTT protocol specification 3.1
--   https://www.ibm.com/developerworks/webservices/library/ws-mqtt
--   http://mqtt.org/wiki/doku.php/mqtt_protocol   # Clarifications
--
-- Notes
-- ~~~~~
-- - Always assumes MQTT connection "clean session" enabled.
-- - Supports connection last will and testament message.
-- - Does not support connection username and password.
-- - Fixed message header byte 1, only implements the "message type".
-- - Only supports QOS level 0.
-- - Maximum payload length is 268,435,455 bytes (as per specification).
-- - Publish message doesn't support "message identifier".
-- - Subscribe acknowledgement messages don't check granted QOS level.
-- - Outstanding subscribe acknowledgement messages aren't escalated.
-- - Works on the Sony PlayStation Portable (aka Sony PSP) ...
--     See http://en.wikipedia.org/wiki/Lua_Player_HM
--
-- ToDo
-- ~~~~
-- * Consider when payload needs to be an array of bytes (not characters).
-- * Maintain both "last_activity_out" and "last_activity_in".
-- * - http://mqtt.org/wiki/doku.php/keepalive_for_the_client
-- * Update "last_activity_in" when messages are received.
-- * When a PINGREQ is sent, must check for a PINGRESP, within KEEP_ALIVE_TIME..
--   * Otherwise, fail the connection.
-- * When connecting, wait for CONACK, until KEEP_ALIVE_TIME, before failing.
-- * Should MQTT.client:connect() be asynchronous with a callback ?
-- * Review all public APIs for asynchronous callback behaviour.
-- * Implement parse PUBACK message.
-- * Handle failed subscriptions, i.e no subscription acknowledgement received.
-- * Fix problem when KEEP_ALIVE_TIME is short, e.g. mqtt_publish -k 1
--     MQTT.client:handler(): Message length mismatch
-- - On socket error, optionally try reconnection to MQTT server.
-- - Consider use of assert() and pcall() ?
-- - Only expose public API functions, don't expose internal API functions.
-- - Refactor "if self.connected()" to "self.checkConnected(error_message)".
-- - Maintain and publish messaging statistics.
-- - Memory heap/stack monitoring.
-- - When debugging, why isn't mosquitto sending back CONACK error code ?
-- - Subscription callbacks invoked by topic name (including wildcards).
-- - Implement asynchronous state machine, rather than single-thread waiting.
--   - After CONNECT, expect and wait for a CONACK.
-- - Implement complete MQTT broker (server).
-- - Consider using Copas http://keplerproject.github.com/copas/manual.html
-- ------------------------------------------------------------------------- --

require("socket")
require("io")
require("ltn12")

local MQTT = {}

MQTT.IO_BUFFER = ""

---
-- @field [parent = #mqtt_library] utility#utility Utility
--

-- MQTT.Utility = require "L_Caseta_MQTT_UTIL"
MQTT.Utility = {
	debug_mode = true,

	get_time = function()
		return(socket.gettime())
	end,

	expired=function(last_time, duration, type)
	  local time_expired = get_time() >= (last_time + duration)

	  --if (time_expired) then debug("Event: " .. type) end
	  return(time_expired)
	end,

	-- ------------------------------------------------------------------------- --

	shift_left = function(value, shift)
	  return(value * 2 ^ shift)
	end,

	shift_right=function(value, shift)
	  return(math.floor(value / 2 ^ shift))
	end,

	-- ------------------------------------------------------------------------- --

	table_to_string=function(table)
	  local result = ''

	  if (type(table) == 'table') then
	    result = '{ '

	    for index = 1, #table do
	      result = result .. table_to_string(table[index])
	      if (index ~= #table) then
	        result = result .. ', '
	      end
	    end

	    result = result .. ' }'
	  else
	    result = tostring(table)
	  end

	  return(result)
	end
}

---
-- @field [parent = #mqtt_library] #number VERSION
--
MQTT.VERSION = 0x03

---
-- @field [parent = #mqtt_library] #boolean ERROR_TERMINATE
--
MQTT.ERROR_TERMINATE = false      -- Message handler errors terminate process ?

---
-- @field [parent = #mqtt_library] #string DEFAULT_BROKER_HOSTNAME
--
MQTT.DEFAULT_BROKER_HOSTNAME = "m2m.eclipse.org"

---
-- An MQTT client
-- @type client

---
-- @field [parent = #mqtt_library] #client client
--
MQTT.client = {}
MQTT.client.__index = MQTT.client

---
-- @field [parent = #client] #number DEFAULT_PORT
--
MQTT.client.DEFAULT_PORT       = 1883

---
-- @field [parent = #client] #number KEEP_ALIVE_TIME
--
MQTT.client.KEEP_ALIVE_TIME    =   600  -- seconds (maximum is 65535)

---
-- @field [parent = #client] #number MAX_PAYLOAD_LENGTH
--
MQTT.client.MAX_PAYLOAD_LENGTH = 268435455 -- bytes

-- MQTT 3.1 Specification: Section 2.1: Fixed header, Message type

---
-- @field [parent = #mqtt_library] message
--
MQTT.message = {}
MQTT.message.TYPE_RESERVED    = 0x00
MQTT.message.TYPE_CONNECT     = 0x01
MQTT.message.TYPE_CONACK      = 0x02
MQTT.message.TYPE_PUBLISH     = 0x03
MQTT.message.TYPE_PUBACK      = 0x04
MQTT.message.TYPE_PUBREC      = 0x05
MQTT.message.TYPE_PUBREL      = 0x06
MQTT.message.TYPE_PUBCOMP     = 0x07
MQTT.message.TYPE_SUBSCRIBE   = 0x08
MQTT.message.TYPE_SUBACK      = 0x09
MQTT.message.TYPE_UNSUBSCRIBE = 0x0a
MQTT.message.TYPE_UNSUBACK    = 0x0b
MQTT.message.TYPE_PINGREQ     = 0x0c
MQTT.message.TYPE_PINGRESP    = 0x0d
MQTT.message.TYPE_DISCONNECT  = 0x0e
MQTT.message.TYPE_RESERVED    = 0x0f

-- MQTT 3.1 Specification: Section 3.2: CONACK acknowledge connection errors
-- http://mqtt.org/wiki/doku.php/extended_connack_codes

MQTT.CONACK = {}
MQTT.CONACK.error_message = {          -- CONACK return code used as the index
  "Unacceptable protocol version",
  "Identifer rejected",
  "Server unavailable",
  "Bad user name or password",
  "Not authorized"
--"Invalid will topic"                 -- Proposed
}

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
-- Create an MQTT client instance
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

---
-- Create an MQTT client instance.
-- @param #string hostname Host name or address of the MQTT broker
-- @param #number port Port number of the MQTT broker (default: 1883)
-- @param #function callback Invoked when subscribed topic messages received
-- @function [parent = #client] create
-- @return #client created client
--
function MQTT.client.create(                                      -- Public API
  hostname,  -- string:   Host name or address of the MQTT broker
  port,      -- integer:  Port number of the MQTT broker (default: 1883)
  callback)  -- function: Invoked when subscribed topic messages received
           -- return:   mqtt_client table

  local mqtt_client = {}

  setmetatable(mqtt_client, MQTT.client)

  mqtt_client.callback = callback  -- function(topic, payload)
  mqtt_client.hostname = hostname
  mqtt_client.port     = port or MQTT.client.DEFAULT_PORT

  mqtt_client.connected     = false
  mqtt_client.destroyed     = false
  mqtt_client.last_activity = 0
  mqtt_client.message_id    = 0
  mqtt_client.outstanding   = {}

  return(mqtt_client)
end

--------------------------------------------------------------------------------
-- Specify username and password before #client.connect
--
-- If called with empty _username_ or _password_, connection flags will be set
-- but no string will be appended to payload.
--
-- @function [parent = #client] auth
-- @param self
-- @param #string username Name of the user who is connecting. It is recommended
--                         that user names are kept to 12 characters.
-- @param #string password Password corresponding to the user who is connecting.
function MQTT.client.auth(self, username, password)
  -- When no string is provided, remember current call to set flags
  self.username = username or true
  self.password = password or true
end

--------------------------------------------------------------------------------
-- Transmit MQTT Client request a connection to an MQTT broker (server).
-- MQTT 3.1 Specification: Section 3.1: CONNECT
-- @param self
-- @param #string identifier MQTT client identifier (maximum 23 characters)
-- @param #string will_topic Last will and testament topic
-- @param #string will_qos Last will and testament Quality Of Service
-- @param #string will_retain Last will and testament retention status
-- @param #string will_message Last will and testament message
-- @function [parent = #client] connect
--
function MQTT.client:connect(                                     -- Public API
	lug_device,		 -- Vera device id
  identifier,    -- string: MQTT client identifier (maximum 23 characters)
  will_topic,    -- string: Last will and testament topic
  will_qos,      -- byte:   Last will and testament Quality Of Service
  will_retain,   -- byte:   Last will and testament retention status
  will_message)  -- string: Last will and testament message
               -- return: nil or error message

  if (self.connected) then
    return("MQTT.client:connect(): Already connected")
  end

  luup.log("MQTT.client:connect(): " .. identifier)

  luup.io.open(lug_device, self.hostname, self.port)

  self.connected = true
  luup.log("MQTT.client:connect(): Connected")

-- Construct CONNECT variable header fields (bytes 1 through 9)
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  local payload
  payload = MQTT.client.encode_utf8("MQIsdp")
  payload = payload .. string.char(MQTT.VERSION)

	-- Connect flags (byte 10)
	-- ~~~~~~~~~~~~~
	-- bit    7: Username flag =  0  -- recommended no more than 12 characters
	-- bit    6: Password flag =  0  -- ditto
	-- bit    5: Will retain   =  0
	-- bits 4,3: Will QOS      = 00
	-- bit    2: Will flag     =  0
	-- bit    1: Clean session =  1
	-- bit    0: Unused        =  0

  local username = self.username and 0x80 or 0
  local password = self.password and 0x40 or 0
  local flags    = username + password

  if (will_topic == nil) then
    -- Clean session, no last will
    flags = flags + 0x02
  else
    flags = flags + MQTT.Utility.shift_left(will_retain, 5)
    flags = flags + MQTT.Utility.shift_left(will_qos, 3)
    -- Last will and clean session
    flags = flags + 0x04 + 0x02
  end
  payload = payload .. string.char(flags)

-- Keep alive timer (bytes 11 LSB and 12 MSB, unit is seconds)
-- ~~~~~~~~~~~~~~~~~
  payload = payload .. string.char(math.floor(MQTT.client.KEEP_ALIVE_TIME / 256))
  payload = payload .. string.char(MQTT.client.KEEP_ALIVE_TIME % 256)

-- Client identifier
-- ~~~~~~~~~~~~~~~~~
  payload = payload .. MQTT.client.encode_utf8(identifier)

-- Last will and testament
-- ~~~~~~~~~~~~~~~~~~~~~~~
  if (will_topic ~= nil) then
    payload = payload .. MQTT.client.encode_utf8(will_topic)
    payload = payload .. MQTT.client.encode_utf8(will_message)
  end

  -- Username and password
  -- ~~~~~~~~~~~~~~~~~~~~~
  if type(self.username) == 'string' then
    payload = payload .. MQTT.client.encode_utf8(self.username)
  end
  if type(self.password) == 'string' then
    payload = payload .. MQTT.client.encode_utf8(self.password)
  end

  luup.log("MQTT.client:connect(): payload: " .. #payload .. " bytes.")

-- Send MQTT message
-- ~~~~~~~~~~~~~~~~~
  return(self:message_write(MQTT.message.TYPE_CONNECT, payload))
end

--- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
-- Destroy an MQTT client instance.
-- @param self
-- @function [parent = #client] destroy
--
function MQTT.client:destroy()                                    -- Public API
  luup.log("MQTT.client:destroy()")

  if (self.destroyed == false) then
    self.destroyed = true         -- Avoid recursion when message_write() fails

    if (self.connected) then self:disconnect() end

    self.callback = nil
    self.outstanding = nil
  end
end

--- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
-- Transmit MQTT Disconnect message.
-- MQTT 3.1 Specification: Section 3.14: Disconnect notification
-- bytes 1,2: Fixed message header, see MQTT.client:message_write()
-- @param self
-- @function [parent = #client] disconnect
--
function MQTT.client:disconnect()                                 -- Public API
  luup.log("MQTT.client:disconnect()")

  if (self.connected) then
    self:message_write(MQTT.message.TYPE_DISCONNECT, nil)
    self.connected = false
  else
    error("MQTT.client:disconnect(): Already disconnected")
  end
end

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
-- Encode a message string using UTF-8 (for variable header)
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- MQTT 3.1 Specification: Section 2.5: MQTT and UTF-8
--
-- byte  1:   String length MSB
-- byte  2:   String length LSB
-- bytes 3-n: String encoded as UTF-8

function MQTT.client.encode_utf8(                               -- Internal API
  input)  -- string

  local output
  output = string.char(math.floor(#input / 256))
  output = output .. string.char(#input % 256)
  output = output .. input

  return(output)
end

function MQTT.client:keepalive()
-- Transmit MQTT PING message
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~
-- MQTT 3.1 Specification: Section 3.13: PING request
--
-- bytes 1,2: Fixed message header, see MQTT.client:message_write()

  local activity_timeout = self.last_activity + MQTT.client.KEEP_ALIVE_TIME

  if (MQTT.Utility.get_time() > activity_timeout) then
    luup.log("MQTT.client:handler(): PINGREQ")

    self:message_write(MQTT.message.TYPE_PINGREQ, nil)
  end

end

--- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
-- Handle received messages and maintain keep-alive PING messages.
-- This function must be invoked periodically (more often than the
-- `MQTT.client.KEEP_ALIVE_TIME`) which maintains the connection and
-- services the incoming subscribed topic messages
-- @param self
-- @function [parent = #client] handler
--
function MQTT.client:handler(lul_data)                                    -- Public API
  if (self.connected == false) then
    error("MQTT.client:handler(): Not connected")
    return false
  end

  luup.log("MQTT.client:handler()")

	MQTT.IO_BUFFER = MQTT.IO_BUFFER .. lul_data
  if (#MQTT.IO_BUFFER > 0) then

    if (MQTT.IO_BUFFER ~= nil and #MQTT.IO_BUFFER > 0) then
      local index = 1

      -- Parse individual messages (each must be at least 2 bytes long)
      -- Decode "remaining length" (MQTT v3.1 specification pages 6 and 7)

      while (index < #MQTT.IO_BUFFER) do
        local message_type_flags = string.byte(MQTT.IO_BUFFER, index)
        local multiplier = 1
        local remaining_length = 0

        repeat
          index = index + 1
          if (MQTT.IO_BUFFER:sub(index,index) == nil) then return false end
          local digit = string.byte(MQTT.IO_BUFFER, index)
          if (digit == nil) then return false end
          remaining_length = remaining_length + ((digit % 128) * multiplier)
          multiplier = multiplier * 128
        until digit < 128                              -- check continuation bit

				if ((index + remaining_length) > #MQTT.IO_BUFFER) then return false end

        local message = string.sub(MQTT.IO_BUFFER, index + 1, index + remaining_length)

        if (#message == remaining_length) then
          self:parse_message(message_type_flags, remaining_length, message)
          MQTT.IO_BUFFER = MQTT.IO_BUFFER:sub(index + remaining_length + 1)
        else
        	return false
        end

        index = index + remaining_length + 1
			end
			return true
    end
  else
    luup.log("MQTT.client:handler: no data")
    return false
  end

  return(nil)
end

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
-- Transmit an MQTT message
-- ~~~~~~~~~~~~~~~~~~~~~~~~
-- MQTT 3.1 Specification: Section 2.1: Fixed header
--
-- byte  1:   Message type and flags (DUP, QOS level, and Retain) fields
-- bytes 2-5: Remaining length field (between one and four bytes long)
-- bytes m- : Optional variable header and payload

function MQTT.client:message_write(                             -- Internal API
  message_type,  -- enumeration
  payload)       -- string
               -- return: nil or error message

-- TODO: Complete implementation of fixed header byte 1

  local message = string.char(MQTT.Utility.shift_left(message_type, 4))

  if (payload == nil) then
    message = message .. string.char(0)  -- Zero length, no payload
  else
    if (#payload > MQTT.client.MAX_PAYLOAD_LENGTH) then
      return(
        "MQTT.client:message_write(): Payload length = " .. #payload ..
        " exceeds maximum of " .. MQTT.client.MAX_PAYLOAD_LENGTH
      )
    end

    -- Encode "remaining length" (MQTT v3.1 specification pages 6 and 7)

    local remaining_length = #payload

    repeat
      local digit = remaining_length % 128
      remaining_length = math.floor(remaining_length / 128)
      if (remaining_length > 0) then digit = digit + 128 end -- continuation bit
      message = message .. string.char(digit)
    until remaining_length == 0

    message = message .. payload
  end

  local status = luup.io.write(message)

  if ((status == nil) or (status == false)) then
--    self:destroy()
    return("MQTT.client:message_write(): FAILED!!")
  end

  self.last_activity = MQTT.Utility.get_time()
  luup.log("MQTT.client:message_write(): packet sent")
  return(nil)
end

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
-- Parse MQTT message
-- ~~~~~~~~~~~~~~~~~~
-- MQTT 3.1 Specification: Section 2.1: Fixed header
--
-- byte  1:   Message type and flags (DUP, QOS level, and Retain) fields
-- bytes 2-5: Remaining length field (between one and four bytes long)
-- bytes m- : Optional variable header and payload
--
-- The message type/flags and remaining length are already parsed and
-- removed from the message by the time this function is invoked.
-- Leaving just the optional variable header and payload.

function MQTT.client:parse_message(                             -- Internal API
  message_type_flags,  -- byte
  remaining_length,    -- integer
  message)             -- string: Optional variable header and payload

  local message_type = MQTT.Utility.shift_right(message_type_flags, 4)
      luup.log("MQTT.client:parse_message(): message type: " .. message_type)


-- TODO: MQTT.message.TYPE table should include "parser handler" function.
--       This would nicely collapse the if .. then .. elseif .. end.

  if (message_type == MQTT.message.TYPE_CONACK) then
    self:parse_message_conack(message_type_flags, remaining_length, message)

  elseif (message_type == MQTT.message.TYPE_PUBLISH) then
    self:parse_message_publish(message_type_flags, remaining_length, message)

  elseif (message_type == MQTT.message.TYPE_PUBACK) then
    luup.log("MQTT.client:parse_message(): PUBACK -- UNIMPLEMENTED --")    -- TODO

  elseif (message_type == MQTT.message.TYPE_SUBACK) then
    self:parse_message_suback(message_type_flags, remaining_length, message)

  elseif (message_type == MQTT.message.TYPE_UNSUBACK) then
    self:parse_message_unsuback(message_type_flags, remaining_length, message)

  elseif (message_type == MQTT.message.TYPE_PINGREQ) then
    self:ping_response()

  elseif (message_type == MQTT.message.TYPE_PINGRESP) then
    self:parse_message_pingresp(message_type_flags, remaining_length, message)

  else
    local error_message =
      "MQTT.client:parse_message(): Unknown message type: " .. message_type

    if (MQTT.ERROR_TERMINATE) then             -- TODO: Refactor duplicate code
      self:destroy()
      error(error_message)
    else
      luup.log(error_message)
    end
  end
end

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
-- Parse MQTT CONACK message
-- ~~~~~~~~~~~~~~~~~~~~~~~~~
-- MQTT 3.1 Specification: Section 3.2: CONACK Acknowledge connection
--
-- byte 1: Reserved value
-- byte 2: Connect return code, see MQTT.CONACK.error_message[]

function MQTT.client:parse_message_conack(                      -- Internal API
  message_type_flags,  -- byte
  remaining_length,    -- integer
  message)             -- string

  local me = "MQTT.client:parse_message_conack()"
  luup.log(me)

  if (remaining_length ~= 2) then
    error(me .. ": Invalid remaining length")
  end

  local return_code = string.byte(message, 2)

  if (return_code ~= 0) then
    local error_message = "Unknown return code"

    if (return_code <= table.getn(MQTT.CONACK.error_message)) then
      error_message = MQTT.CONACK.error_message[return_code]
    end

    error(me .. ": Connection refused: " .. error_message)
  end
end

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
-- Parse MQTT PINGRESP message
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- MQTT 3.1 Specification: Section 3.13: PING response

function MQTT.client:parse_message_pingresp(                    -- Internal API
  message_type_flags,  -- byte
  remaining_length,    -- integer
  message)             -- string

  local me = "MQTT.client:parse_message_pingresp()"
  luup.log(me)

  if (remaining_length ~= 0) then
    error(me .. ": Invalid remaining length")
  end

-- ToDo: self.ping_response_outstanding = false
end

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
-- Parse MQTT PUBLISH message
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~
-- MQTT 3.1 Specification: Section 3.3: Publish message
--
-- Variable header ..
-- bytes 1- : Topic name and optional Message Identifier (if QOS > 0)
-- bytes m- : Payload

function MQTT.client:parse_message_publish(                     -- Internal API
  message_type_flags,  -- byte
  remaining_length,    -- integer
  message)             -- string

  local me = "MQTT.client:parse_message_publish()"
  luup.log(me)

  if (self.callback ~= nil) then
    if (remaining_length < 3) then
      error(me .. ": Invalid remaining length: " .. remaining_length)
    end

    local topic_length = string.byte(message, 1) * 256
    topic_length = topic_length + string.byte(message, 2)
    local topic  = string.sub(message, 3, topic_length + 2)
    local index  = topic_length + 3

		-- Handle optional Message Identifier, for QOS levels 1 and 2
		-- TODO: Enable Subscribe with QOS and deal with PUBACK, etc.

    local qos = MQTT.Utility.shift_right(message_type_flags, 1) % 3

    if (qos > 0) then
      local message_id = string.byte(message, index) * 256
      message_id = message_id + string.byte(message, index + 1)
      index = index + 2
    end

    local payload_length = remaining_length - index + 1
    local payload = string.sub(message, index, index + payload_length - 1)

    self.callback(topic, payload)
  end
end

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
-- Parse MQTT SUBACK message
-- ~~~~~~~~~~~~~~~~~~~~~~~~~
-- MQTT 3.1 Specification: Section 3.9: SUBACK Subscription acknowledgement
--
-- bytes 1,2: Message Identifier
-- bytes 3- : List of granted QOS for each subscribed topic

function MQTT.client:parse_message_suback(                      -- Internal API
  message_type_flags,  -- byte
  remaining_length,    -- integer
  message)             -- string

  local me = "MQTT.client:parse_message_suback()"
  luup.log(me)

  if (remaining_length < 3) then
    error(me .. ": Invalid remaining length: " .. remaining_length)
  end

  local message_id  = string.byte(message, 1) * 256 + string.byte(message, 2)
  local outstanding = self.outstanding[message_id]

  if (outstanding == nil) then
    error(me .. ": No outstanding message: " .. message_id)
  end

  self.outstanding[message_id] = nil

  if (outstanding[1] ~= "subscribe") then
    error(me .. ": Outstanding message wasn't SUBSCRIBE")
  end

  local topic_count = table.getn(outstanding[2])

  if (topic_count ~= remaining_length - 2) then
    error(me .. ": Didn't received expected number of topics: " .. topic_count)
  end
end

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
-- Parse MQTT UNSUBACK message
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- MQTT 3.1 Specification: Section 3.11: UNSUBACK Unsubscription acknowledgement
--
-- bytes 1,2: Message Identifier

function MQTT.client:parse_message_unsuback(                    -- Internal API
  message_type_flags,  -- byte
  remaining_length,    -- integer
  message)             -- string

  local me = "MQTT.client:parse_message_unsuback()"
  luup.log(me)

  if (remaining_length ~= 2) then
    error(me .. ": Invalid remaining length")
  end

  local message_id = string.byte(message, 1) * 256 + string.byte(message, 2)

  local outstanding = self.outstanding[message_id]

  if (outstanding == nil) then
    error(me .. ": No outstanding message: " .. message_id)
  end

  self.outstanding[message_id] = nil

  if (outstanding[1] ~= "unsubscribe") then
    error(me .. ": Outstanding message wasn't UNSUBSCRIBE")
  end
end

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
-- Transmit MQTT Ping response message
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- MQTT 3.1 Specification: Section 3.13: PING response

function MQTT.client:ping_response()                            -- Internal API
  luup.log("MQTT.client:ping_response()")

  if (self.connected == false) then
    error("MQTT.client:ping_response(): Not connected")
  end

  self:message_write(MQTT.message.TYPE_PINGRESP, nil)
end

--- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
-- Transmit MQTT Publish message.
-- MQTT 3.1 Specification: Section 3.3: Publish message
--
-- * bytes 1,2: Fixed message header, see MQTT.client:message_write()
--            Variable header ..
-- * bytes 3- : Topic name and optional Message Identifier (if QOS > 0)
-- * bytes m- : Payload
-- @param self
-- @param #string topic
-- @param #string payload
-- @function [parent = #client] publish
--
function MQTT.client:publish(                                     -- Public API
  topic,    -- string
  payload)  -- string

  if (self.connected == false) then
    error("MQTT.client:publish(): Not connected")
  end

  luup.log("MQTT.client:publish(): " .. topic)

  local message = MQTT.client.encode_utf8(topic) .. payload

  self:message_write(MQTT.message.TYPE_PUBLISH, message)
end

--- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
-- Transmit MQTT Subscribe message.
-- MQTT 3.1 Specification: Section 3.8: Subscribe to named topics
--
-- * bytes 1,2: Fixed message header, see MQTT.client:message_write()
--            Variable header ..
-- * bytes 3,4: Message Identifier
-- * bytes 5- : List of topic names and their QOS level
-- @param self
-- @param #string topics table of strings
-- @function [parent = #client] subscribe
--
function MQTT.client:subscribe(                                   -- Public API
  topics)  -- table of strings

  if (self.connected == false) then
    error("MQTT.client:subscribe(): Not connected")
  end

  self.message_id = self.message_id + 1

  local message
  message = string.char(math.floor(self.message_id / 256))
  message = message .. string.char(self.message_id % 256)

  for index, topic in ipairs(topics) do
    luup.log("MQTT.client:subscribe(): " .. topic)
    message = message .. MQTT.client.encode_utf8(topic)
    message = message .. string.char(0)  -- QOS level 0
  end

  self:message_write(MQTT.message.TYPE_SUBSCRIBE, message)

  self.outstanding[self.message_id] = { "subscribe", topics }
end

--- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
-- Transmit MQTT Unsubscribe message
-- MQTT 3.1 Specification: Section 3.10: Unsubscribe from named topics
--
-- * bytes 1,2: Fixed message header, see MQTT.client:message_write()
--            Variable header ..
-- * bytes 3,4: Message Identifier
-- * bytes 5- : List of topic names
-- @param self
-- @param #string topics table of strings
-- @function [parent = #client] unsubscribe
--
function MQTT.client:unsubscribe(                                 -- Public API
  topics)  -- table of strings

  if (self.connected == false) then
    error("MQTT.client:unsubscribe(): Not connected")
  end

  self.message_id = self.message_id + 1

  local message
  message = string.char(math.floor(self.message_id / 256))
  message = message .. string.char(self.message_id % 256)

  for index, topic in ipairs(topics) do
    luup.log("MQTT.client:unsubscribe(): " .. topic)
    message = message .. MQTT.client.encode_utf8(topic)
  end

  self:message_write(MQTT.message.TYPE_UNSUBSCRIBE, message)

  self.outstanding[self.message_id] = { "unsubscribe", topics }
end

-- For ... MQTT = require 'paho.mqtt'

return(MQTT)
]]

local MQTT = assert(loadstring(MQTTmodule))()

----------------------------------------------------------
----------------------------------------------------------

local g_childDevices = {-- .id       -> vera id
  -- .integrationId -> lutron internal id
  -- .devType -> device type (dimmer, blinds , binary light or keypad)
  -- .fadeTime
  -- .componentNumber = {} -> only for keypads
}


-- key for local SSH server
local SSHkey = [[
-----BEGIN RSA PRIVATE KEY-----
MIIEogIBAAKCAQEApX6g2uGLyC8ZDw13Vvn/lgp4pf5BrEy2oZf+yFouGOn+UI+J
7d9yWWrP8nUJXIzz1YQ3Fs4YgDFus5bu1g/3XuK3J7kk5lVuz3wTgqDGw2jIP3mb
IUIlonEvJp+5aKNjMUkFGHkWo6nlqXx0nQjFrqhU1bZTPKwKON35IrauqmQaI+z7
pA2DEW1w2a/sO+Y4t/iBzTU0U4M9C/5PcT5GRtfb23RFP5NaiE38OC68rWfqFR91
+37smywvX1vaxhVbP5DkZXtZNBDK5jXtQ3j0dHwnKSyu7JDmhhq/pHgMEZaxtAjE
ziFJdP56P8Hy0TdXcvG/Wfw+F94KltOsp/wJfQIDAQABAoIBABvlX2nl0PEad0fh
RjeEBoAdHb8lP56yg6pze3/8K38JmlOsDlzpaFYIOistbTmLjOJ12e9fKCQbsQRW
scWlhVYaMzNf8wdcaURSLtu7DCYOOIryjaKqirt6Bq+lBtTLjcHWBCTe7GEEF3Fd
SC7cNq49M6eehyNYAJUbXY5rar/PwEpKFE/5LuTP4xXjJCvCsMffcenBj/rZp7g8
nigZ4pboNJNY7ODpTg4J2tk6x5HPSoYr9aM8CL4IjG4pcoJe8ROXm5YM+JQSwL1d
nUH4SA4qQOpE3cHLtxfmAoJ8vwu7tIpxD5YMMAACg1dVZGPgVVSOlTXH9jxC2vfn
GVQa98ECgYEA27HMMeWPFbgVuscR6cVmCriAuKlhYvJJkhYFjJV8qWMvgwsjOdl6
O1wGzW4IWSzzSoz0MdBs1ikUj1FlfriGpRWBQkT7rdIGwbKus3BXSIt52b/3cCvx
2H1qS/P9gAW8yfw6LcIGA9L26BOWCDqtmMX1aJ/zkVdrafr7AOIf+w0CgYEAwNfm
AW3oSald1NpG1CoB6rA7VJg9ulXm2t0Ha8czQ483pFjkDaaETQyIO+dtTg1sqrbO
dcFn+FF66fBlQN/ZNGb9+IbGSdITkI5iV5D1RSXJVuxaZFkX6IZPwwBgL6ouBPW2
lNfg06j4RKj32fddPxtjJIwTkOo6VUbSCbbh7DECgYBjDuIRRX6kvmId25C6JWWD
Q/nWSZk9sh12HzPVVbnl7nEH10fE18iDZ1Ux34EoJFp2rOOWanIIhnFcxcjLwIwF
d5LWvJ/2mhKt19Fp2yef8DO6+RGqpEXh5Xq+UH9m8C9Vq8LXyvpHUyI9NkeZ4ktP
7UJgMG70g8RM/vuaRFtDKQKBgGHD0qZ82tulUp2bf3cGSOx7JckQWZMDA8OHdMCu
P44LqHDYY92Lwtzw8ow0GpUMdz/g57CJObWJUWAScLLACXTole8OHK7GIwcROEge
hEnnCzjXIEhpZpaKqRs6MIlZpHT9QPAata94pUzhwK2vG4Xn045uuWipZqNfARLN
taGxAoGAQGFYb63lBeGS2vkUyovP2kMwBF0E6Y+3Il+TGjwPalyg+TyNzEAvkOUe
2iy8Eul9rT6qcByzNXnNAMRHYhXDWQWmRaHM/lzyIkNr/O3UBEQKiSew/YhH6s1W
iMwh+x+ekyFOxb98aNqlnEH/7PsQonzWThpzcAAojllTt9AIbbc=
-----END RSA PRIVATE KEY-----
]]


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
    return str
  end
}

local CASETA = {
  CONFIG = {}, -- TODO Remove?
  SENSEME_DEVICES = {
    {
      MAC = "20:F8:5E:AB:31:1B",
      NAME = "Spa Room Fan",
      TYPE = "FAN",
    },
    {
      MAC = "20:F8:5E:AB:31:1B",
      NAME = "Spa Room Fan Light",
      TYPE = "DIMMER",
    },
  },

  --	DEVICES = {},
  --	SCENES = {},
  LIP_CONSTANTS = {
    errorMessage = {
      ["1"] = "Parameter count mismatch",
      ["2"] = "Object does not exist",
      ["3"] = "Invalid action number",
      ["4"] = "Parameter data out of range",
      ["5"] = "Parameter data malformed",
      ["6"] = "Unsupported Command"
    },
    deviceActionNumber = {
      ["3"] = "Press / Close / Occupied",
      ["4"] = "Release / Open / Unoccupied",
      ["9"] = "Set (#) or Get (?) LED State",
      ["14"] = "Set or Get Light Level",
      ["18"] = "Start Raising",
      ["19"] = "Start Lowering",
      ["20"] = "Stop Raising / Lowering",
      ["22"] = "Get battery status",
      ["23"] = "Set a custom lift and tilt level of venetian blinds programmed to the phantom button",
      ["24"] = "Set a custom lift level only of venetian blinds programmed to the phantom button",
      ["25"] = "Set a custom tilt level only of venetian blinds programmed to the phantom button"
    },
    outputActionNumber = {
      ["1"] = "Set or Get Zone Level",
      ["2"] = "Start Raising",
      ["3"] = "Start Lowering",
      ["4"] = "Stop Raising / Lowering",
      ["5"] = "Start Flash",
      ["6"] = "Pulse",
      ["9"] = "Set (#) or Get (?) Venetian tilt level only",
      ["10"] = "Set (#) or Get (?) Venetian lift & tilt level",
      ["11"] = "Start raising Venetian tilt",
      ["12"] = "Start lowering Venetian tilt",
      ["13"] = "Stop Venetian tilt",
      ["14"] = "Start raising Venetian lift",
      ["15"] = "Start lowering Venetian lift",
      ["16"] = "Stop Venetian lift"
    },
    shadegroupActionNumber = {
      ["1"] = "Set or Get Zone Level",
      ["2"] = "Start Raising",
      ["3"] = "Start Lowering",
      ["4"] = "Stop Raising / Lowering",
      ["6"] = "Set (#) or Get (?) Current Preset",
      ["14"] = "Set (#) Venetian Tilt",
      ["15"] = "Set (#) Lift and Tilt for venetians",
      ["16"] = "Raise Venetian Tilt",
      ["17"] = "Lower Venetian Tilt",
      ["18"] = "Stop Venetian Tilt",
      ["19"] = "Raise Venetian Lift",
      ["20"] = "Lower Venetian Lift",
      ["21"] = "Stop Venetian Lift",
      ["28"] = "Get Horizontal Sheer Shade Region"
    }
  },
  ["LEAP"] = {
    SERVER = 0,
    ENABLED = false,
    ACTIVE = false,
    CONNECTED = false,
    JSON = ""
  },
  ["LIP"] = {
    SERVER = 0,
    ENABLED = false,
    ACTIVE = false,
    CONNECTED = false,
    JSON = ""
  },
  SERVER_TYPE = "",
  sendCommand = function(self, command)
    -- send a command to the LEAP server/LIP server or raw socket interface
    if ((self.LIP.ENABLED) and (self.LIP.ACTIVE)) then
      -- use the Lutron Integration Protocol
      return self:sendCommandLIP(command)
    elseif ((self.LEAP.ENABLED) and (self.LEAP.ACTIVE)) then
      -- use the LEAP server (SSH Proxy)
      return self:sendCommandLEAP(command)
    elseif ((self.PROXY.ENABLED) and (self.PROXY.ACTIVE)) then
    else
      -- use fallback method
      return self:sendCommandFALLBACK(command)
    end
  end,
  configureBridgeConnection = function(self, BridgeIP)
    if (self.LIP_CONNECTED == true) then
      log("" .. PLUGIN.NAME .. "::SENSEME::configureBridgeConnection: Integration Server already configured.")
      return true
    end
    log("" .. PLUGIN.NAME .. "::SENSEME::configureBridgeConnection: Preparing Caseta Integration support elements.")
    if (UTILITIES:file_exists("/etc/cmh-ludl/caseta_openssh_key") == false) then
      log("" .. PLUGIN.NAME .. "::SENSEME::configureBridgeConnection: Creating caseta key file.", 2)
      -- create the ssh key for the SmartBridge
      local file = io.open("/etc/cmh-ludl/caseta_openssh_key", "w")
      if (file) then
        file:write(SSHkey)
        file:close()
        -- convert the key to dropbear format
        --				os.execute("dropbearconvert openssh dropbear /etc/cmh-ludl/caseta_ssh_key /etc/cmh-ludl/caseta_key; rm /etc/cmh-ludl/caseta_ssh_key")
        os.execute("chmod 600 /etc/cmh-ludl/caseta_openssh_key;dropbearconvert openssh dropbear /etc/cmh-ludl/caseta_openssh_key /etc/cmh-ludl/caseta_dropbear_key; chmod 600 /etc/cmh-ludl/caseta_dropbear_key")
        if (UTILITIES:file_exists("/etc/cmh-ludl/caseta_dropbear_key") == false) then
          if (PLUGIN.OPENLUUP == false) then
            log("" .. PLUGIN.NAME .. "::SENSEME::configureBridgeConnection: Failed to write caseta dropbear key file.", 1)
            return false, "Could not convert openssh key to dropbear format"
          else
            -- running on openluup -- assume openssh ssh client
            if (UTILITIES:file_exists("/etc/cmh-ludl/caseta_openssh_key") == false) then
              log("" .. PLUGIN.NAME .. "::SENSEME::configureBridgeConnection: Failed to write caseta openssh key file.", 1)
              return false, "Could not write openssh key"
            else
              log("" .. PLUGIN.NAME .. "::SENSEME::configureBridgeConnection: Created caseta openssh key file.", 2)
              PLUGIN.SSH_KEYFILE = "/etc/cmh-ludl/caseta_openssh_key"
              PLUGIN.SSH_OPTIONS = "-t -y -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
            end
          end
        else
          PLUGIN.SSH_KEYFILE = "/etc/cmh-ludl/caseta_dropbear_key"
          PLUGIN.SSH_OPTIONS = "-t -y"
          log("" .. PLUGIN.NAME .. "::SENSEME::configureBridgeConnection: Created caseta dropbear key file.", 2)
        end

      else
        log("" .. PLUGIN.NAME .. "::SENSEME::configureBridgeConnection: Failed to create caseta keyfile.", 1)
        return false, "Could not create openssh key"
      end
    else
      -- key already exists
      PLUGIN.SSH_KEYFILE = "/etc/cmh-ludl/caseta_openssh_key"
      PLUGIN.SSH_OPTIONS = "-t -y -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
      if (UTILITIES:file_exists("/etc/cmh-ludl/caseta_dropbear_key") == true) then
        PLUGIN.SSH_KEYFILE = "/etc/cmh-ludl/caseta_dropbear_key"
        PLUGIN.SSH_OPTIONS = "-t -y"
      end
      log("" .. PLUGIN.NAME .. "::SENSEME::configureBridgeConnection: Using existing keyfile.")
    end
    -- create the socat executable
    if (UTILITIES:file_exists("/etc/cmh-ludl/socat") == false) then
      if (PLUGIN.OPENLUUP == true) then
        -- create a file softlink to the installed socat
        local socat_path = shellExecute("echo `which socat`")
        if (socat_path:gsub("\r", ""):gsub("\n", "") ~= "") then
          log("" .. PLUGIN.NAME .. "::SENSEME::configureBridgeConnection: linking socat executable [" .. (socat_path or "NIL") .. "] to /etc/cmh-ludl/socat.")
          os.execute("ln -s " .. socat_path .. " /etc/cmh-ludl/socat")
        else
          log("" .. PLUGIN.NAME .. "::SENSEME::configureBridgeConnection: socat executable not installed.", 1)
          local apt_get_path = shellExecute("echo `which socat`")
          if (apt_get_path:gsub("\r", ""):gsub("\n", "") ~= "") then
            return false, "SOCAT package not installed. run \"apt-get install socat\" from a command prompt."
          else
            return false, "SOCAT package not installed."
          end
        end
      else
        log("" .. PLUGIN.NAME .. "::SENSEME::configureBridgeConnection: creating socat executable.")
        os.execute("pluto-lzo d /etc/cmh-ludl/L_Caseta_socat.mipsel.lzo /etc/cmh-ludl/socat.uue;uudecode -o /etc/cmh-ludl/socat /etc/cmh-ludl/socat.uue;chmod 755 /etc/cmh-ludl/socat")
      end
    else
      log("" .. PLUGIN.NAME .. "::SENSEME::configureBridgeConnection: Using existing socat executable.")
    end
    return true
  end,
  DeviceTypes = {
    ["SmartBridge"] = "Gateway",
    ["SmartBridgePro"] = "Gateway",
    ["WallDimmer"] = "DIMMER",
    ["PlugInDimmer"] = "DIMMER",
    ["WallSwitch"] = "SWITCH",
    ["FourGroupRemote"] = "KEYPAD",
    ["Pico1Button"] = "KEYPAD",
    ["Pico2Button"] = "KEYPAD",
    ["Pico2ButtonRaiseLower"] = "KEYPAD",
    ["Pico3Button"] = "KEYPAD",
    ["Pico3ButtonRaiseLower"] = "KEYPAD",
    ["Pico4Button2Group"] = "KEYPAD",
    ["Pico4ButtonScene"] = "KEYPAD",
    ["Pico4ButtonZone"] = "KEYPAD",
    ["QsWirelessShade"] = "SHADEGRP",
    ["SerenaHoneycombShade"] = "BLIND",
    ["SerenaRollerShade"] = "BLIND",
    ["TriathlonHoneycombShade"] = "SHADEGRP",
    ["TriathlonRollerShade"] = "SHADEGRP",
    ["VirtualButton"] = "SCENE"
  },
  ButtonBase = {
    -- define the button id base offset (lowest button component number)
    ["FourGroupRemote"] = 2,
    ["Pico1Button"] = 2,
    ["Pico2Button"] = 2,
    ["Pico2ButtonRaiseLower"] = 2,
    ["Pico3Button"] = 2,
    ["Pico3ButtonRaiseLower"] = 2,
    ["Pico4Button2Group"] = 2,
    ["Pico4ButtonScene"] = 8,
    ["Pico4ButtonZone"] = 8
  },
  ButtonMap = {
    -- define the pico button component number to Vera scene button mapping)
    ["FourGroupRemote"] = { [2] = 1, [3] = 2, [4] = 3, [5] = 4 },
    ["Pico1Button"] = { [2] = 1 },
    ["Pico2Button"] = { [2] = 1, [4] = 2 },
    ["Pico2ButtonRaiseLower"] = { [2] = 1, [4] = 2, [5] = 3, [6] = 4 },
    ["Pico3Button"] = { [2] = 1, [3] = 2, [4] = 3 },
    ["Pico3ButtonRaiseLower"] = { [2] = 1, [3] = 2, [4] = 3, [5] = 4, [6] = 5 },
    ["Pico4Button2Group"] = { [2] = 1, [3] = 2, [4] = 3, [5] = 4, [8] = 5, [9] = 6, [10] = 7, [11] = 8 },
    ["Pico4ButtonScene"] = { [8] = 1, [9] = 2, [10] = 3, [11] = 4 },
    ["Pico4ButtonZone"] = { [8] = 1, [9] = 2, [10] = 3, [11] = 4 }
  },
  DEFINITIONS = {
    ["OneProjectDefinition"] = "Project",
    ["OneSystemDefinition"] = "System",
    ["MultipleServerDefinition"] = "Servers",
    ["MultipleDeviceDefinition"] = "Devices",
    ["MultipleZoneDefinition"] = "Zones",
    ["MultipleButtonDefinition"] = "Button",
    ["MultipleButtonGroupDefinition"] = "Buttons",
    ["MultipleVirtualButtonDefinition"] = "VirtualButtons",
    ["OneLIPIdListDefinition"] = "LIP"
  },
  findDeviceIndex = function(self, devNum, zoneNum, buttonNum)
    for idx, dev in pairs(self.DEVICES) do
      if ((tonumber(dev.ID, 10) == tonumber(devNum, 10)) and (tonumber(dev.ZONE, 10) == tonumber(zoneNum, 10)) and (tonumber(dev.BUTTON, 10) == tonumber(buttonNum, 10))) then
        return idx
      elseif ((tonumber(dev.ID, 10) == tonumber(devNum, 10)) and (zoneNum == nil) and (buttonNum == nil)) then
        return idx
      end
    end
    return 0
  end,
  findSceneIndex = function(self, devNum, zoneNum, buttonNum)
    if (tonumber(devNum, 10) == 1) then
      if (tonumber(zoneNum, 10) == 0) then
        for idx, scene in pairs(self.SCENES) do
          if (tonumber(scene.ID, 10) == tonumber(buttonNum, 10)) then
            return idx
          end
        end
      end
    end
    return 0
  end,
  findSceneByVeraId = function(self, veraId)
    for idx, scene in pairs(self.SCENES) do
      if (tonumber(scene.VID, 10) == tonumber(veraId, 10)) then
        return idx
      end
    end
    return 0
  end,
  findDeviceByName = function(self, targetNAME)
    for idx, dev in pairs(self.DEVICES) do
      if (dev.NAME == targetNAME) then
        return idx
      end
    end
    return 0
  end,
  -- compile a list of configured devices and store in upnp variable
  buildDeviceSummary = function(self)
    debug("(" .. PLUGIN.NAME .. "::buildDeviceSummary): building device summary.", 2)

    local html = ""
    if ((PLUGIN.FILES_VALIDATED == false) and (PLUGIN.OPENLUUP == false)) then
      html = html .. "<h2>Installation error</h2><p>Mismatched Files</p>"
      html = html .. "<ul><li>" .. PLUGIN.mismatched_files_list:gsub(",", "</li><li>") .. "</li></ul><br>"
    end
    if (self.DEVICES and (#self.DEVICES > 0) and self.DEVICES[1]) then
      html = html .. "<h2>Bridge:</h2><table>"
      html = html .. "<tr><td>Model:</td><td>" .. self.DEVICES[1].MODEL .. "</td><td>&nbsp;&nbsp;</td><td>Serial:</td><td>" .. self.DEVICES[1].SERIAL .. "</td></tr>"
      html = html .. "<tr><td>MAC:</td><td>" .. PLUGIN.BRIDGE_MAC .. "</td><td>&nbsp;&nbsp;</td><td>IP:</td><td>" .. PLUGIN.BRIDGE_IP .. "</td></tr>"

      html = html .. "<tr><td>LIP:</td><td>" .. (((self["LIP"].ENABLED == true) and ((PLUGIN.DISABLE_LIP == false) and "ENABLED" or "FALLBACK") or (self.CONFIG["LIP"] and "DISABLED" or "NOT AVAILABLE")) or "Not Available") .. "</td><td>&nbsp;&nbsp;</td><td>LEAP:</td><td>" .. ((self["LIP"].ENABLED and (PLUGIN.DISABLE_LIP == false)) and "INACTIVE" or "ACTIVE") .. "</td></tr>"

      html = html .. "</table>"
      -- enumerate by hubs
      html = html .. "<h2>Devices:</h2><ul class='devices'>"
      -- add devices
      for k, DEV in pairs(self.DEVICES) do
        -- display the devices
        debug("(" .. PLUGIN.NAME .. "::buildDeviceSummary): Scanning device [" .. DEV.ID .. "].")
        if (DEV.TYPE == "Gateway") then
        elseif (DEV.TYPE == "KEYPAD") then
          html = html .. "<li class='wDevice'><b>Vera ID:" .. DEV.VID .. " [" .. DEV.TYPE .. "] " .. DEV.NAME .. "</b><br>"
          html = html .. "<table><tr><td>Model:</td><td>" .. DEV.MODEL .. "</td><td>&nbsp;&nbsp;</td><td>Serial:</td><td>" .. DEV.SERIAL .. "</td></tr>"
          html = html .. "<tr><td>LEAP/LIP ID:</td><td>" .. DEV.ID .. "/" .. DEV.LIPid .. "</td><td>&nbsp;&nbsp;</td><td>Button Group:</td><td>" .. DEV.BUTTON .. "</td></tr></table>"
          html = html .. "</li>"
        elseif ((DEV.TYPE == "DIMMER") or (DEV.TYPE == "SWITCH")) then
          html = html .. "<li class='wDevice'><b>Vera ID:" .. DEV.VID .. " [" .. DEV.TYPE .. "] " .. DEV.NAME .. "</b><br>"
          html = html .. "<table><tr><td>Model:</td><td>" .. DEV.MODEL .. "</td><td>&nbsp;&nbsp;</td><td>Serial:</td><td>" .. DEV.SERIAL .. "</td></tr>"
          html = html .. "<tr><td>LEAP/LIP ID:</td><td>" .. DEV.ID .. "/" .. DEV.LIPid .. "</td><td>&nbsp;&nbsp;</td><td>Zone: </td><td>" .. DEV.ZONE .. "</td></tr></table>"
          html = html .. "</li>"
        else
          html = html .. "<li class='wDevice'><b>Vera ID:" .. DEV.VID .. " [" .. DEV.TYPE .. "] " .. DEV.NAME .. "</b><br>"
          html = html .. "<table><tr><td>Model:</td><td>" .. DEV.MODEL .. "</td><td>&nbsp;&nbsp;</td><td>Serial:</td><td>" .. DEV.SERIAL .. "</td></tr>"
          html = html .. "<tr><td>LEAP/LIP ID:</td><td>" .. DEV.ID .. "/" .. DEV.LIPid .. "</td><td>&nbsp;&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td></tr></table>"
          html = html .. "</li>"
        end
      end
      html = html .. "</ul><br>"
      -- add scenes
      html = html .. "<h2>Scenes:</h2><ul class='scenes'>"
      for k, DEV in pairs(self.SCENES) do
        -- display the scenes
        debug("(" .. PLUGIN.NAME .. "::buildDeviceSummary): Scanning scene [" .. DEV.ID .. "].")
        html = html .. "<li class='wDevice'><b>Vera ID:" .. DEV.VID .. " [" .. DEV.TYPE .. "] " .. DEV.NAME .. "</b><br>"
        html = html .. "<table><tr><td>ID:</td><td>" .. DEV.ID .. "</td><td>&nbsp;&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td></tr></table>"
        html = html .. "</li>"
      end
      html = html .. "</ul><br>"
    else
      -- error with installation
      if (PLUGIN.BRIDGE_STATUS == "User Intervention Required...") then
        html = html .. "<h2>Bridge device not selected.</h2>"
      elseif (PLUGIN.BRIDGE_STATUS == "No Bridge Found") then
        if (PLUGIN.mqttParameters == nil) then
          html = html .. "<h2>Bridge not found.</h2>"
        else
          html = html .. "<h2>Bridge specified by Lutron Account not found on local network.</h2>"
        end
      elseif (PLUGIN.BRIDGE_STATUS == "Failed to load bridge config") then
        html = html .. "<h2>Could not load Bridge Configuration.</h2>"
      elseif (PLUGIN.BRIDGE_STATUS == "Startup Failed!") then
        html = html .. "<h2>Could not process Bridge Configuration.</h2>"
      else
        html = html .. "<h2>An unspecified error occurred.</h2>"
      end
    end

    debug("(" .. PLUGIN.NAME .. "::buildDeviceSummary): Device summary html [" .. html .. "].")
    UTILITIES:setVariable(VERA.SID["SENSEME"], "DEVICE_SUMMARY", html)
  end,
  buildButtonMapLIP = function(self, lipButtons)
    local buttonMap = {}
    for idx, button in pairs(lipButtons) do
      local bID = button["Number"]
      buttonMap[bID] = idx
    end
    return buttonMap
  end,
  processBridgeConfig = function(self)
    log("(" .. PLUGIN.NAME .. "::SENSEME::processBridgeConfig): Processing Smart Bridge configuration.")
    local bridgeType = "SmartBridge"
    -- process the servers
    if ((self.CONFIG["Servers"] == nil) or (self.CONFIG["Devices"] == nil)) then
      log("(" .. PLUGIN.NAME .. "::SENSEME::processBridgeConfig): NO CONFIGURATION to process.", 1)
      return false
    end
    for idx, svr in pairs(self.CONFIG["Servers"]["Body"]["Servers"]) do
      self[svr["Type"]].ENABLED = (svr["EnableState"] == "Enabled") and true or false
      self[svr["Type"]].SERVER = svr["href"]
      self[svr["Type"]].JSON = UTILITIES:encode_json(svr)
      if (svr["Type"] == "LIP") then
        bridgeType = "SmartBridge Pro"
      end
      log("(" .. PLUGIN.NAME .. "::SENSEME::processBridgeConfig): Found SERVER - type [" .. UTILITIES:print_r(svr["Type"]) .. "] EnableState [" .. UTILITIES:print_r(svr["EnableState"]) .. "] JSON [" .. (self[svr["Type"]].JSON or "NIL") .. "]")
    end
    local modelString = (self.CONFIG["Project"] and self.CONFIG["Project"]["Body"] and self.CONFIG["Project"]["Body"]["Project"] and self.CONFIG["Project"]["Body"]["Project"]["Name"] or "")
    if (bridgeType == "SmartBridge Pro") then
      -- make sure the LIP server is enabled
      if (self["LIP"].ENABLED == false) then
        -- try to enable the LIP server
        local cmd = '{"CommuniqueType":"UpdateRequest","Header":{"MessageBodyType":"MultipleServerDefinition","Url":"%s"},"Body":{"Server":%s}}}}'
        local svr = self["LIP"].JSON:gsub("Disabled", "Enabled")
        cmd = string.format(cmd, self["LIP"].SERVER, svr)
        self:sendBridgeConfigCommand(cmd)
      end
    end
    debug("" .. PLUGIN.NAME .. "::SENSEME::processBridgeConfig): SmartBridge Model - raw [" .. (modelString or "NIL") .. "] eval [" .. (bridgeType or "NIL") .. "]")
    self.DEVICES = {}
    for idx, dev in pairs(self.CONFIG["Devices"]["Body"]["Devices"]) do
      local devName = dev["Name"]
      local devHref = dev["href"]
      local devId = dev["href"]:gsub("/device/", ""):gsub("/", "")
      local devModel = dev["DeviceType"]
      local devType = self.DeviceTypes[dev["DeviceType"]]
      local devZone = dev["LocalZones"] and dev["LocalZones"][1]["href"]:gsub("/zone/", "") or 0
      local devButton = dev["ButtonGroups"] and dev["ButtonGroups"][1]["href"]:gsub("/buttongroup/", "") or 0
      local devSerial = dev["SerialNumber"] or 0
      if ((bridgeType == "SmartBridge Pro") or (devType ~= "KEYPAD")) then
        local addDevice = {
          ID = devId,
          LEAPid = devId,
          LIPid = 0,
          HREF = devHref,
          SERIAL = devSerial,
          NAME = devName,
          MODEL = devModel,
          TYPE = devType,
          ZONE = devZone,
          BUTTON = devButton,
          VID = 0
        }
        if (tonumber(devButton, 10) > 0) then
          local bGroup = "/buttongroup/" .. devButton
          local numButtons = 0
          local buttonBase = 0
          local buttonMap = {}
          for bidx, btn in pairs(self.CONFIG["Buttons"]["Body"]["ButtonGroups"]) do
            if (btn["href"] == bGroup) then
              numButtons = btn["Buttons"] and #btn["Buttons"] or 0
              buttonBase = self.ButtonBase[dev["DeviceType"]] or 1
              buttonMap = self.ButtonMap[dev["DeviceType"]] or {}
              break
            end
          end
          addDevice.NUM_BUTTONS = numButtons
          addDevice.BUTTON_BASE = buttonBase
          addDevice.BUTTON_MAP = buttonMap
        end
        if (tonumber(devId, 10) == 1) then
          addDevice.MODEL = bridgeType
        end
        self.DEVICES[#self.DEVICES + 1] = addDevice
      end
    end

    -- process the defined scenes into Vera devices
    self.SCENES = {}
    if (self.CONFIG["VirtualButtons"] and self.CONFIG["VirtualButtons"]["Body"] and self.CONFIG["VirtualButtons"]["Body"]["VirtualButtons"]) then
      for idx, scene in pairs(self.CONFIG["VirtualButtons"]["Body"]["VirtualButtons"]) do
        if (scene.IsProgrammed == true) then
          local sceneName = scene["Name"]
          local sceneHref = scene["href"]
          local sceneId = tonumber(scene["href"]:gsub("/virtualbutton/", ""):gsub("/", ""), 10)
          local sceneModel = scene["DeviceType"]
          local sceneType = self.DeviceTypes["VirtualButton"]
          local addScene = {
            ID = sceneId,
            BUTTON = sceneId,
            HREF = sceneHref,
            NAME = sceneName,
            MODEL = sceneModel,
            TYPE = sceneType,
            VID = 0
          }
          self.SCENES[sceneId] = addScene
        end
      end
    end

    if (self["LIP"].ENABLED and ((self.CONFIG["LIP"] == nil) or UTILITIES:arraySize(self.CONFIG["LIP"]) == 0)) then
      -- getBridgeConfig did not retrieve the LIP integration report - try to get it again
      log("(" .. PLUGIN.NAME .. "::SENSEME::processBridgeConfig): LIP Integration report not yet received. Attempting to retrieve report.", 1)
      local retries = 5
      local lipReport = nil
      repeat
        lipReport = self:getBridgeConfigLIP()
        if (UTILITIES:arraySize(lipReport) > 0) then
          self.CONFIG["LIP"] = lipReport
        end
        retries = retries - 1
      until ((UTILITIES:arraySize(self.CONFIG["LIP"]) > 0) or (retries == 0))
      if ((self.CONFIG["LIP"] == nil) or (UTILITIES:arraySize(self.CONFIG["LIP"]) == 0)) then
        -- could not retrieve LIP integration report - force fallback to LEAP server
        log("(" .. PLUGIN.NAME .. "::SENSEME::processBridgeConfig): LIP Integration report not retrieved. Forcing LEAP mode.", 1)
        PLUGIN.DISABLE_LIP = true
      else
        log("(" .. PLUGIN.NAME .. "::SENSEME::processBridgeConfig): LIP Integration report retrieved.", 2)
      end
    end

    -- match LIP ids to LEAP devices if required
    if (self.CONFIG["LIP"] and self.CONFIG["LIP"]["Body"] and self.CONFIG["LIP"]["Body"]["LIPIdList"]) then
      -- process devices (picos, etc)
      local LIPIdList = self.CONFIG["LIP"]["Body"]["LIPIdList"]
      for oidx, lDevices in pairs(LIPIdList) do
        for idx, lipDev in pairs(lDevices) do
          local lipID = lipDev["ID"]
          local devIdx = self:findDeviceByName(lipDev["Name"])
          if (devIdx > 0) then
            self.DEVICES[devIdx].LIPid = lipID
            if (lipDev["Buttons"]) then
              self.DEVICES[devIdx].LIP_NUM_BUTTONS = #lipDev["Buttons"]
              self.DEVICES[devIdx].LIP_BUTTON_BASE = tonumber(lipDev["Buttons"][1]["Number"]) or 1
              self.DEVICES[devIdx].LIP_BUTTON_MAP = self:buildButtonMapLIP(lipDev["Buttons"])
            end
          end
        end
      end
    else
      if (self["LIP"].ENABLED == true) then
        -- LIP server is enabled, but integration report is not available - force fallback to LEAP server
        log("(" .. PLUGIN.NAME .. "::SENSEME::processBridgeConfig): LIP Integration report not available. Forcing LEAP mode.", 1)
        PLUGIN.DISABLE_LIP = true
      end
    end

    debug("(" .. PLUGIN.NAME .. "::SENSEME::processBridgeConfig): Scanning child devices.")
    -- match reported devices to vera devices
    for idx, vDev in pairs(luup.devices) do
      if (vDev.device_num_parent == lug_device) then
        debug("(" .. PLUGIN.NAME .. "::SENSEME::processBridgeConfig):  Processing device [" .. (idx or "NIL") .. "] id [" .. (vDev.id or "NIL") .. "].")
        local _, _, devType, devNum, zoneNum, buttonNum = vDev.id:find("Caseta_(%w-)_(%d-)_(%d-)_(%d+)")
        if ((devType == nil) and (devNum == nil) and (zoneNum == nil) and (buttonNum == nil)) then
          _, _, devNum = vDev.id:find("(%d-)")
          devType, zoneNum, buttonNum = "", 0, 0
        end
        debug("(" .. PLUGIN.NAME .. "::SENSEME::processBridgeConfig):    Scanned device [" .. (idx or "NIL") .. "] id [" .. (vDev.id or "NIL") .. "] - type [" .. (devType or "NIL") .. "] num [" .. (devNum or "NIL") .. "] zone [" .. (zoneNum or "NIL") .. "] button [" .. (buttonNum or "NIL") .. "].")
        if ((devType ~= nil) and (devNum ~= nil)) then
          if (devType == "SCENE") then
            -- detect a virtual device (scene)
            if (tonumber(devNum, 10) == 1) then
              -- scene are always attached to device 1
              local sIdx = self:findSceneIndex(devNum, zoneNum, buttonNum)
              debug("(" .. PLUGIN.NAME .. "::SENSEME::processBridgeConfig):        Found Caseta scene [" .. (sIdx or "NIL") .. "].")
              if (sIdx > 0) then
                self.SCENES[sIdx].VID = idx
                debug("(" .. PLUGIN.NAME .. "::SENSEME::processBridgeConfig):        Updated Caseta scene [" .. (sIdx or "NIL") .. "] with Vera id [" .. (idx or "NIL") .. "].")
              end
            end
          else
            -- detect a physical device
            local dIdx = self:findDeviceIndex(devNum, zoneNum, buttonNum)
            debug("(" .. PLUGIN.NAME .. "::SENSEME::processBridgeConfig):        Found Caseta device [" .. (dIdx or "NIL") .. "].")
            if (dIdx > 0) then
              self.DEVICES[dIdx].VID = idx
              debug("(" .. PLUGIN.NAME .. "::SENSEME::processBridgeConfig):        Updated Caseta device [" .. (dIdx or "NIL") .. "] with Vera id [" .. (idx or "NIL") .. "].")
            end
          end
        end
      end
    end
    --		local self.DEVICES = Config["MultipleDeviceDefinition"]["Devices"]
    self:buildDeviceSummary()
  end,
  sendBridgeConfigCommand = function(self, cmd, responseType)
    local CFG = UTILITIES:shellExecute("(sleep 2;echo '" .. cmd .. "')|/etc/cmh-ludl/socat - EXEC:\"ssh -t -y -i /etc/cmh-ludl/caseta_dropbear_key leap@" .. PLUGIN.BRIDGE_IP .. "\",pty,setsid,ctty|grep -e 'Response'")
    local cJson = UTILITIES:decode_json(line)
    return cJson
  end,
  getBridgeConfigLIP = function(self)
    local lipCMD = "(sleep 2;echo '" .. self.CONFIG_COMMANDS.LIP_REPORT .. "')|/etc/cmh-ludl/socat - EXEC:\"ssh " .. PLUGIN.SSH_OPTIONS .. " -i " .. PLUGIN.SSH_KEYFILE .. " leap@" .. PLUGIN.BRIDGE_IP .. "\",pty,setsid,ctty|grep -e 'ReadResponse'"
    local lipCFG = UTILITIES:shellExecute(lipCMD)
    lipCFG = lipCFG:gsub("\r\n\r\n", "\r\n")
    debug("(SENSEME::getBridgeConfigLIP): Retrieved LIPconfig [" .. (lipCFG or "NIL") .. "].")
    for line in lipCFG:gmatch("(.-)\r\n") do
      local cJson = UTILITIES:decode_json(line)
      if (cJson and cJson["Header"] and cJson["Header"]["MessageBodyType"] and self.DEFINITIONS[cJson["Header"]["MessageBodyType"]]) then
        debug("Received CONFIG[" .. self.DEFINITIONS[cJson["Header"]["MessageBodyType"]] .. "]")
        if (self.DEFINITIONS[cJson["Header"]["MessageBodyType"]] == "LIP") then
          debug("returning CONFIG[" .. self.DEFINITIONS[cJson["Header"]["MessageBodyType"]] .. "]")
          return cJson
        end
      end
    end
    return nil
  end,
  getBridgeConfig = function(self)
    debug("(" .. PLUGIN.NAME .. "::SENSEME::getBridgeConfig): Retrieving config from Bridge [" .. (PLUGIN.BRIDGE_IP or "NIL") .. "].")
    if (PLUGIN.SSH_KEYFILE == "") then
      debug("(" .. PLUGIN.NAME .. "::SENSEME::getBridgeConfig): Plugin SSH options not configured.")
      return nil
    end
    retryCount = 5
    repeat
      self.CONFIG = nil
      debug("(" .. PLUGIN.NAME .. "::SENSEME::getBridgeConfig): Requesting configuration from bridge.", 2)
      local cCMD = "(sleep 2;echo '" .. self.CONFIG_COMMANDS.PROJECT .. "';echo '" .. self.CONFIG_COMMANDS.SYSTEM .. "';echo '" .. self.CONFIG_COMMANDS.SERVERS .. "';echo '" .. self.CONFIG_COMMANDS.DEVICES .. "';echo '" .. self.CONFIG_COMMANDS.ZONES .. "';echo '" .. self.CONFIG_COMMANDS.BUTTONS .. "';echo '" .. self.CONFIG_COMMANDS.VIRTUAL_BUTTONS .. "')|/etc/cmh-ludl/socat - EXEC:\"ssh " .. PLUGIN.SSH_OPTIONS .. " -i " .. PLUGIN.SSH_KEYFILE .. " leap@" .. PLUGIN.BRIDGE_IP .. "\",pty,setsid,ctty|grep -e 'ReadResponse'"
      --			local cCMD = "(sleep 2;echo '"..self.CONFIG_COMMANDS.PROJECT.."';echo '"..self.CONFIG_COMMANDS.SYSTEM.."';echo '"..self.CONFIG_COMMANDS.SERVERS.."';echo '"..self.CONFIG_COMMANDS.DEVICES.."';echo '"..self.CONFIG_COMMANDS.ZONES.."';echo '"..self.CONFIG_COMMANDS.BUTTON.."';echo '"..self.CONFIG_COMMANDS.BUTTONS.."';echo '"..self.CONFIG_COMMANDS.VIRTUAL_BUTTONS.."')|/etc/cmh-ludl/socat - EXEC:\"ssh "..PLUGIN.SSH_OPTIONS.." -i "..PLUGIN.SSH_KEYFILE.." leap@"..PLUGIN.BRIDGE_IP.."\",pty,setsid,ctty|grep -e 'ReadResponse'"
      debug("(SENSEME::getBridgeConfig): Sending Command[" .. (cCMD or "NIL") .. "].")
      local CFG = UTILITIES:shellExecute(cCMD)
      -- get the LIP integration report if available
      local lipCMD = "(sleep 2;echo '" .. self.CONFIG_COMMANDS.LIP_REPORT .. "')|/etc/cmh-ludl/socat - EXEC:\"ssh " .. PLUGIN.SSH_OPTIONS .. " -i " .. PLUGIN.SSH_KEYFILE .. " leap@" .. PLUGIN.BRIDGE_IP .. "\",pty,setsid,ctty|grep -e 'ReadResponse'"
      local lipCFG = UTILITIES:shellExecute(lipCMD)
      if ((lipCFG ~= nil) and (lipCFG ~= "")) then
        CFG = CFG .. "\r\n" .. lipCFG
      end
      CFG = CFG:gsub("\r\n\r\n", "\r\n")
      debug("(SENSEME::getBridgeConfig): Retrieved config [" .. (CFG or "NIL") .. "].")
      self.CONFIG = nil
      for line in CFG:gmatch("(.-)\r\n") do
        --				debug("CFG line: "..(line or "NIL"))
        local cJson = UTILITIES:decode_json(line)
        --				debug("CFG json: "..(UTILITIES:print_r(cJson)))
        if (cJson and cJson["Header"] and cJson["Header"]["MessageBodyType"] and self.DEFINITIONS[cJson["Header"]["MessageBodyType"]]) then
          debug("Setting CONFIG[" .. self.DEFINITIONS[cJson["Header"]["MessageBodyType"]] .. "]")
          if (self.CONFIG == nil) then self.CONFIG = {} end
          self.CONFIG[self.DEFINITIONS[cJson["Header"]["MessageBodyType"]]] = cJson
        end
      end
      debug("(SENSEME::getBridgeConfig): Retrieved [" .. UTILITIES:arraySize(self.CONFIG) .. "] configuration entries.", 2)
      retryCount = retryCount - 1
    until ((UTILITIES:arraySize(self.CONFIG) > 6) or (retryCount == 0))
    if (self.CONFIG) then
      debug("(SENSEME::getBridgeConfig): Retrieved config [" .. UTILITIES:print_r(self.CONFIG["Devices"]) .. "] device entries.", 2)
    else
      debug("(SENSEME::getBridgeConfig): Bridge config not retrieved.", 1)
    end
    return self.CONFIG
  end,
  appendDevices = function(self, device)
    log("(" .. PLUGIN.NAME .. "::SENSEME::appendDevices): Preparing for update/append of Vera devices...", 2)
    local added = false
    local veraDevices = {}

    -- add/update devices - cache the scan results before committing in case of error

    for idx, dev in pairs(self.SENSEME_DEVICES) do
      debug("(" .. PLUGIN.NAME .. "::SENSEME::appendDevices):   Processing device [" .. (dev.NAME or "NIL") .. "] type [" .. (dev.TYPE or "NIL") .. "]")
      local devId = "SenseMe_" .. dev.TYPE .. "_" .. dev.MAC
      if (VERA.DEVTYPE[dev.TYPE] ~= nil) then
        local devParams = ""
        if (dev.TYPE == "DIMMER") then
          devParams = "urn:upnp-org:serviceId:Dimming1,RampTime=0"
        end
        veraDevices[#veraDevices + 1] = { devId, dev.NAME, VERA.DEVTYPE[dev.TYPE][1], VERA.DEVTYPE[dev.TYPE][2], "", devParams, false }
        added = true
      else
        log("(" .. PLUGIN.NAME .. "::SENSEME::appendDevices): ERROR : Unknown device type [" .. (dev.TYPE or "NIL") .. "]!")
        return false
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
  CONFIG_COMMANDS = {
    -- PROJECT = the smartbridge device name and master device list
    PROJECT = "{\"CommuniqueType\":\"ReadRequest\",\"Header\":{\"Url\":\"/project\"}}",
    -- SYSTEM = system settings/state (mode, timezone, time, etc)
    SYSTEM = "{\"CommuniqueType\":\"ReadRequest\",\"Header\":{\"Url\":\"/system\"}}",
    -- SERVERS = indicated which servers are available - LEAP(ssh - always enabled) or LIP(telnet - can be enabled on SmartBridge Pro)
    SERVERS = "{\"CommuniqueType\":\"ReadRequest\",\"Header\":{\"Url\":\"/server\"}}",
    -- DEVICES = list of individutal devices
    DEVICES = '{"CommuniqueType":"ReadRequest","Header":{"Url":"/device"}}',
    ZONES = '{"CommuniqueType":"ReadRequest","Header":{"Url":"/zone"}}',
    -- BUTTON= individual remote buttons
    BUTTON = '{"CommuniqueType":"ReadRequest","Header":{"Url":"/button"}}',
    -- BUTTON_GROUPS = pico (and possibly other) remotes
    BUTTONS = '{"CommuniqueType":"ReadRequest","Header":{"Url":"/buttongroup"}}',
    -- VIRTUAL_BUTTONS = scenes
    VIRTUAL_BUTTONS = '{"CommuniqueType":"ReadRequest","Header":{"Url":"/virtualbutton"}}',
    LIP_REPORT = '{"CommuniqueType":"ReadRequest","Header":{"Url":"/server/2/id"}}'
  }
}

CASETA_LIP = {
  setUI = function(self, parameters, cmdType)
    debug("(" .. PLUGIN.NAME .. "::CASETA_LIP::setUI): Proceesing UI update - command type [" .. (cmdType or "NIL") .. "] params [\n" .. UTILITIES:print_r(parameters) .. "].")
    local devType = ""
    local devName = ""
    local devIdx = -1
    local id = -1
    local index = 1
    for idx, dev in pairs(CASETA.DEVICES) do
      local devID = dev.ID
      if (PLUGIN.LUUP_IO_MODE == "LIP") then
        devID = dev.LIPid
      end
      if (tonumber(devID, 10) == tonumber(parameters[index], 10)) then
        devType = dev.TYPE
        devName = dev.NAME
        devIdx = idx
        id = dev.VID
        break
      end
    end
    if (id == -1) then
      debug("(" .. PLUGIN.NAME .. "::CASETA_LIP::setUI): ERROR : Could not find Vera device for Caseta ID [" .. (parameters[index] or "NIL") .. "].", 1)
      return
    end
    debug("(" .. PLUGIN.NAME .. "::CASETA_LIP::setUI): Processing index [" .. (index or "NIL") .. "] device ID [" .. (parameters[1] or "NIL") .. "] TYPE [" .. (devType or "NIL") .. "] VID [" .. id .. "] NAME [" .. (devName or "NIL") .. "].")
    if cmdType == "OUTPUT" then
      index = index + 1
      debug("(" .. PLUGIN.NAME .. "::CASETA_LIP::setUI): Processing OUTPUT command - index [" .. (index or "NIL") .. "]...")
      if (tonumber(parameters[index], 10) == 1) then
        if devType == "SWITCH" then
          if (parameters and parameters[index + 1]) then
            local val = tonumber(parameters[index + 1])
            debug("(" .. PLUGIN.NAME .. "::CASETA_LIP::setUI): Setting SWITCH - VAL [" .. (val or "NIL") .. "].")
            if (val > 0) then
              UTILITIES:setVariable(VERA.SID["SWITCH"], "Status", "1", id)
            else
              UTILITIES:setVariable(VERA.SID["SWITCH"], "Status", "0", id)
            end
            debug("(" .. PLUGIN.NAME .. "::CASETA_LIP::setUI): SWITCH : Vera device has been updated.")
          else
            debug("(" .. PLUGIN.NAME .. "::CASETA_LIP::setUI): SWITCH : ERROR processing parameters.", 1)
          end
        elseif ((devType == "DIMMER") or (devType == "BLIND")) then
          if (parameters and parameters[index + 1]) then
            local var = math.floor(tonumber(parameters[index + 1], 10))
            debug("(" .. PLUGIN.NAME .. "::CASETA_LIP::setUI): Setting DIMMER - VAR [" .. (var or "NIL") .. "].")
            if (var == 0) then
              UTILITIES:setVariable(VERA.SID["DIMMER"], "LoadLevelStatus", "0", id)
              UTILITIES:setVariable(VERA.SID["SWITCH"], "Status", "0", id)
            else
              UTILITIES:setVariable(VERA.SID["DIMMER"], "LoadLevelStatus", var, id)
              UTILITIES:setVariable(VERA.SID["SWITCH"], "Status", "1", id)
              debug("(" .. PLUGIN.NAME .. "::CASETA_LIP::setUI): DIMMER or BLINDS : Vera device has been updated.")
            end
          else
            debug("(" .. PLUGIN.NAME .. "::CASETA_LIP::setUI): DIMMER or BLINDS : ERROR processing parameters.", 1)
          end
        else
          debug("(" .. PLUGIN.NAME .. "::CASETA_LIP::setUI): ERROR! : Unknown command type! ")
        end
      end
    elseif cmdType == "SHADEGRP" then
      debug("(" .. PLUGIN.NAME .. "::CASETA_LIP::setUI): Processing SHADEGRP command...")
      index = index + 1
      if (parameters and parameters[index] and (parameters[index] == "1")) then
        if devType == "SHADEGRP" then
          UTILITIES:setVariable(VERA.SID["SHADEGRP"], "LoadLevelStatus", parameters[index + 1], id)
          debug("(" .. PLUGIN.NAME .. "::CASETA_LIP::setUI): SHADEGROUP : Vera device has been set.")
        end
      end
    elseif cmdType == "AREA" then
      debug("(" .. PLUGIN.NAME .. "::CASETA_LIP::setUI): Processing AREA command...")
      if (parameters and parameters[3] and (parameters[3] == "3")) then
        UTILITIES:setVariable(VERA.SID["AREA"], "Tripped", "1", id)
        if not g_lastTripFlag then
          UTILITIES:setVariable(VERA.SID["AREA"], "LastTrip", os.time(), id)
          g_lastTripFlag = true
        end
        debug("(" .. PLUGIN.NAME .. "::CASETA_LIP::setUI): AREA : Device " .. id .. " has been tripped!")
      elseif (parameters and parameters[3] and (parameters[3] == "4")) then
        UTILITIES:setVariable(VERA.SID["AREA"], "Tripped", "0", id)
        if g_lastTripFlag then
          g_lastTripFlag = false
        end
        debug("(" .. PLUGIN.NAME .. "::CASETA_LIP::setUI): AREA : Device " .. id .. "is not tripped!")
      else
        debug("(" .. PLUGIN.NAME .. "::CASETA_LIP::setUI): AREA : Unknown parameters received!!! " .. tostring(parameters[3] or "NIL"))
      end
    else
      debug("(" .. PLUGIN.NAME .. "::CASETA_LIP::setUI): Processing KEYPAD command...")
      index = index + 1
      if (parameters and parameters[index] and parameters[index + 1]) then
        local button = parameters[index] and tonumber(parameters[index], 10) or 0
        local event = parameters[index + 1] and tonumber(parameters[index + 1], 10) or 0
        if (devIdx ~= 1) then -- ignore device 1 (virtual buttons (scenes) )
        if ((event == 3) or (event == 4)) then
          debug("(" .. PLUGIN.NAME .. "::CASETA_LIP::setUI): Processing KEYPAD event - device [" .. (devIdx or "NIL") .. "] button [" .. (button or "NIL") .. "] event [" .. (event or "NIL") .. "].")
          createSceneControllerEvent(devIdx, button, event)
        else
          debug("(" .. PLUGIN.NAME .. "::CASETA_LIP::setUI): Received unrecognized KEYPAD command - device [" .. (devIdx or "NIL") .. "] button [" .. (button or "NIL") .. "] event [" .. (event or "NIL") .. "].", 1)
        end
        end
      else
        debug("(" .. PLUGIN.NAME .. "::CASETA_LIP::setUI): Error processing KEYPAD command parameters.", 1)
      end
    end
    debug("(" .. PLUGIN.NAME .. "::CASETA_LIP::setUI): Processing COMPLETE.")
  end,
  getParameters = function(self, parameters)
    if (parameters == nil) then return {} end
    if (parameters:sub(#parameters, #parameters) ~= ",") then parameters = parameters .. "," end
    local param = {} -- param[2] 	= Action Number
    local k = 0 -- param[3-5] 	= Parameters
    for v in parameters:gmatch("(.-),") do
      k = k + 1
      param[k] = v
    end
    return param
  end,
  sendCommand = function(self, command)
    local cmd = command
    local startTime, endTime
    local dataSize = string.len(cmd)
    assert(dataSize <= 135)
    startTime = socket.gettime()
    --		luup.sleep(200)
    if (luup.io.write(cmd .. "\r\n") == false) then
      debug("(" .. PLUGIN.NAME .. "::CASETA_LIP::sendCommand) : Cannot send command " .. command .. " communications error")
      return false
    end
    endTime = socket.gettime()
    debug("(" .. PLUGIN.NAME .. "::CASETA_LIP::sendCommand) : Sending cmd = [" .. cmd .. "]")
    --		debug("("..PLUGIN.NAME.."::CASETA_LIP::sendCommand) : Request returned in " .. math.floor((endTime - startTime) * 1000) .. "ms")
    luup.sleep(100)
    return true
  end
}

CASETA_LEAP = {
  processStatus = function(self, status)
    debug("(" .. PLUGIN.NAME .. "::CASETA_LEAP::processStatus) : Received raw status message [\n" .. (status or "NIL") .. "].", 2)
    local status = UTILITIES:decode_json("{" .. status:gsub("\r", ""):gsub("\n", ""):gsub("}{", "},{") .. "}")
    if (status) then
      for _, sResp in pairs(status) do
        -- process individual device status updates
        if (sResp["CommuniqueType"] == "ReadResponse") then
          debug("(" .. PLUGIN.NAME .. "::CASETA_LEAP::processStatus) : Received status message [\n" .. UTILITIES:print_r(sResp) .. "\n].")
          local zone = sResp["Body"]["ZoneStatus"]["Zone"]["href"]:gsub("/zone/", "")
          local level = tonumber(sResp["Body"]["ZoneStatus"]["Level"], 10)
          local devID = -1
          for idx, dev in pairs(CASETA.DEVICES) do
            local devID = dev.ID
            if ((CASETA["LIP"].ENABLED == true) and (PLUGIN.DISABLE_LIP == false)) then
              devID = dev.LIPid
            end
            if (tonumber(dev.ZONE, 10) == tonumber(zone, 10)) then
              if ((dev.TYPE == "DIMMER") or (dev.TYPE == "SWITCH") or (dev.TYPE == "BLIND")) then
                params = { devID, 1, level }
                CASETA_LIP:setUI(params, "OUTPUT")
                break
              elseif (dev.TYPE == "SHADEGRP") then
                params = { devID, 1, level }
                CASETA_LIP:setUI(params, "OUTPUT")
                break
              end
            end
          end
        end
      end
    end
  end,
  sendCommand = function(self, command)
    debug("(" .. PLUGIN.NAME .. "::CASETA_LEAP::sendCommand) : sending command [\n" .. (command or "NIL") .. "].", 2)
    return UTILITIES:shellExecute("(sleep 2;echo '" .. command .. "')|/etc/cmh-ludl/socat - EXEC:\"ssh " .. PLUGIN.SSH_OPTIONS .. " -i " .. PLUGIN.SSH_KEYFILE .. " leap@" .. PLUGIN.BRIDGE_IP .. "\",pty,setsid,ctty|grep -e 'Response'")
  end,
  runScene = function(self, sceneId)
    local setCMD = '{"CommuniqueType":"CreateRequest","Header":{"Url":"/virtualbutton/%s/commandprocessor"},"Body":{"Command":{"CommandType":"PressAndRelease"}}}'
    setCMD = string.format(setCMD, sceneId)
    debug("(" .. PLUGIN.NAME .. "::CASETA_LEAP::runScene) : Sending command [" .. (setCMD or "NIL") .. "].")
    return self:sendCommand(setCMD)
  end,
  setLevel = function(self, zone, level)
    local setCMD = '{"CommuniqueType":"CreateRequest","Header":{"Url":"/zone/%s/commandprocessor"},"Body":{"Command":{"CommandType":"GoToLevel","Parameter":[{"Type":"Level","Value":%s}]}}}'
    setCMD = string.format(setCMD, zone, level)
    debug("(" .. PLUGIN.NAME .. "::CASETA_LEAP::setLevel) : Sending command [" .. (setCMD or "NIL") .. "].")
    return self:sendCommand(setCMD)
  end,
  blindRaise = function(self, zone)
    local setCMD = '{"CommuniqueType":"CreateRequest","Header":{"Url":"/zone/%s/commandprocessor"},"Body":{"Command":{"CommandType":"ShadeLimitRaise","Parameter":{"Type":"Action","Value":"Start"}}}}'
    setCmd = string.format(setCMD, zone, level)
    return self:sendCommand(setCMD)
  end,
  blindStop = function(self, zone)
    local setCMD1 = '{"CommuniqueType":"CreateRequest","Header":{"Url":"/zone/%s/commandprocessor"},"Body":{"Command":{"CommandType":"ShadeLimitRaise","Parameter":{"Type":"Action","Value":"Stop"}}}}'
    local setCMD2 = '{"CommuniqueType":"CreateRequest","Header":{"Url":"/zone/%s/commandprocessor"},"Body":{"Command":{"CommandType":"ShadeLimitLower","Parameter":{"Type":"Action","Value":"Stop"}}}}'
    setCmd1 = string.format(setCMD1, zone)
    setCmd2 = string.format(setCMD2, zone)
    self:sendCommand(setCMD1)
    self:sendCommand(setCMD2)
    return
  end,
  blindLower = function(self, zone)
    local setCMD = '{"CommuniqueType":"CreateRequest","Header":{"Url":"/zone/%s/commandprocessor"},"Body":{"Command":{"CommandType":"ShadeLimitLower","Parameter":{"Type":"Action","Value":"Start"}}}}'
    setCmd = string.format(setCMD, zone, level)
    return self:sendCommand(setCMD)
  end
}

CASETA_ACTIONS = {
  setTarget = function(self, lul_device, newTargetValue)
    local value = math.floor(tonumber(newTargetValue, 10))
    local integrationId = nil
    local zoneId = ""
    local cmd = ""
    local fadeTime = 0
    for k, v in pairs(CASETA.DEVICES) do
      if v.VID == lul_device then
        integrationId = v.ID
        if ((CASETA["LIP"].ENABLED == true) and (PLUGIN.DISABLE_LIP == false)) then
          integrationId = v.LIPid
        end
        zoneId = v.ZONE
        fadeTime = v.fadeTime or 0
      end
    end
    if (integrationId == nil) then
      debug("(" .. PLUGIN.NAME .. "::CASETA_ACTIONS::setTarget): intergrationId not found for vera device [" .. (lul_device or "NIL") .. "].")
      return 2, 0
    end
    UTILITIES:setVariable(VERA.SID["SWITCH"], "Status", value, lul_device)
    if value == 1 then
      value = 100
    end
    if ((CASETA["LIP"].ENABLED == true) and (PLUGIN.DISABLE_LIP == false)) then
      cmd = "#OUTPUT," .. integrationId .. ",1," .. value .. "," .. fadeTime
      debug("(" .. PLUGIN.NAME .. "::CASETA_ACTIONS::setTarget): Sending command :'" .. cmd .. "' ...")
      CASETA_LIP:sendCommand(cmd)
    else
      debug("(" .. PLUGIN.NAME .. "::CASETA_ACTIONS::setTarget): Sending command - zone [" .. (zoneId or "NIL") .. "] value [" .. (value or "NIL") .. "]...")
      CASETA_LEAP:processStatus(CASETA_LEAP:setLevel(zoneId, value))
    end
    return 4, 0
  end,
  setArmed = function(lul_device, newArmedValue)
    debug("(" .. PLUGIN.NAME .. "::CASETA_ACTIONS::setArmed): Device Arm Status was set to " .. newArmedValue)
    UTILITIES:setVariable(VERA.SID["AREA"], "Armed", newArmedValue, lul_device)
    return 4, 0
  end,
  StartRampToLevel = function(self, lul_device, newLoadLevelTarget, newRampTime)
    debug("(" .. PLUGIN.NAME .. "::CASETA_ACTIONS::StartRampToLevel): device [" .. (lul_device or "NIL") .. "] newLoadLevelTarget [" .. (newLoadLevelTarget or "NIL") .. "] newRampTime [" .. (newRampTime or "NIL") .. "].", 1)
    return self:setLoadLevelTarget(lul_device, newLoadLevelTarget, newRampTime)
  end,
  setLoadLevelTarget = function(self, lul_device, newLoadLevelTarget, newRampTime)
    if (newLoadLevelTarget == nul) then
      debug("(" .. PLUGIN.NAME .. "::CASETA_ACTIONS::setLoadLevelTarget): newLoadLevelTarget not specified.", 1)
      return 2, 0
    end
    local integrationId = nil
    local zoneId = ""
    local devType = ""
    local cmd = ""
    local fadeTime = 0
    local delay = 0
    for k, v in pairs(CASETA.DEVICES) do
      if v.VID == lul_device then
        integrationId = v.ID
        if ((CASETA["LIP"].ENABLED == true) and (PLUGIN.DISABLE_LIP == false)) then
          integrationId = v.LIPid
        end
        devType = v.TYPE
        zoneId = v.ZONE
        if ((devType == "DIMMER") or (devType == "BLIND")) then
          fadeTime = tonumber(UTILITIES:getVariable(VERA.SID["DIMMER"], "RampTime", lul_device), 10)
          if ((newRampTime ~= nil) and (tonumber(newRampTime, 10) > 0)) then
            debug("(" .. PLUGIN.NAME .. "::CASETA_ACTIONS::setLoadLevelTarget): Using RampTime specified in UPnP command.")
            fadeTime = UTILITIES:SecondsToHMS(newRampTime or 0)
          elseif (fadeTime > 0) then
            -- fadeTime is programmed into the device, and overide is not specified
            debug("(" .. PLUGIN.NAME .. "::CASETA_ACTIONS::setLoadLevelTarget): Using RampTime specified in device settings.")
            fadeTime = UTILITIES:SecondsToHMS(fadeTime or 0)
          else
            debug("(" .. PLUGIN.NAME .. "::CASETA_ACTIONS::setLoadLevelTarget): Using default RampTime = 0.")
            fadeTime = 0
          end
        end
      end
    end
    if (integrationId == nil) then
      debug("(" .. PLUGIN.NAME .. "::CASETA_ACTIONS::setLoadLevelTarget): intergrationId not found for vera device [" .. (lul_device or "NIL") .. "].")
      return 2, 0
    end
    if devType == "SHADEGRP" then
      cmd = "#SHADEGRP," .. integrationId .. ",1," .. newLoadLevelTarget .. "," .. delay
    else
      cmd = "#OUTPUT," .. integrationId .. ",1," .. newLoadLevelTarget .. "," .. fadeTime
    end
    if ((CASETA["LIP"].ENABLED == true) and (PLUGIN.DISABLE_LIP == false)) then
      debug("(" .. PLUGIN.NAME .. "::CASETA_ACTIONS::setLoadLevelTarget): Sending command :'" .. cmd .. "' ...")
      CASETA_LIP:sendCommand(cmd)
    else
      debug("(" .. PLUGIN.NAME .. "::CASETA_ACTIONS::setLoadLevelTarget): Sending command - zone [" .. (zoneId or "NIL") .. "] value [" .. (newLoadLevelTarget or "NIL") .. "]...")
      CASETA_LEAP:processStatus(CASETA_LEAP:setLevel(zoneId, newLoadLevelTarget))
    end
    return 4, 0
  end,
  blindsUP = function(self, lul_device)
    local integrationId = nil
    local zoneId = ""
    local devType = ""
    local cmd = ""
    for k, v in pairs(CASETA.DEVICES) do
      if v.VID == lul_device then
        integrationId = v.ID
        if ((CASETA["LIP"].ENABLED == true) and (PLUGIN.DISABLE_LIP == false)) then
          integrationId = v.LIPid
        end
        zoneId = v.ZONE
        devType = v.TYPE
      end
    end
    if (integrationId == nil) then
      debug("(" .. PLUGIN.NAME .. "::CASETA_ACTIONS::blindsUP): intergrationId not found for vera device [" .. (lul_device or "NIL") .. "].")
      return 2, 0
    end

    if devType == "SHADEGRP" then
      cmd = "#SHADEGRP," .. integrationId .. ",2"
    else
      cmd = "#OUTPUT," .. integrationId .. ",2"
    end
    if ((CASETA["LIP"].ENABLED == true) and (PLUGIN.DISABLE_LIP == false)) then
      debug("(" .. PLUGIN.NAME .. "::CASETA_ACTIONS::blindsUP): Sending command :'" .. cmd .. "' ...")
      CASETA_LIP:sendCommand(cmd)
    else
      debug("(" .. PLUGIN.NAME .. "::CASETA_ACTIONS::blindsUP): Sending command...")
      CASETA_LEAP:blindRaise(zoneId)
    end
    return 4, 0
  end,
  blindsDown = function(self, lul_device)
    local integrationId = nil
    local zoneId = ""
    local devType = ""
    local cmd = ""
    for k, v in pairs(CASETA.DEVICES) do
      if v.VID == lul_device then
        integrationId = v.ID
        if ((CASETA["LIP"].ENABLED == true) and (PLUGIN.DISABLE_LIP == false)) then
          integrationId = v.LIPid
        end
        zoneId = v.ZONE
        devType = v.TYPE
      end
    end
    if (integrationId == nil) then
      debug("(" .. PLUGIN.NAME .. "::CASETA_ACTIONS::blindsDown): intergrationId not found for vera device [" .. (lul_device or "NIL") .. "].")
      return 2, 0
    end
    if devType == "SHADEGRP" then
      cmd = "#SHADEGRP," .. integrationId .. ",3"
    else
      cmd = "#OUTPUT," .. integrationId .. ",3"
    end
    if ((CASETA["LIP"].ENABLED == true) and (PLUGIN.DISABLE_LIP == false)) then
      debug("(" .. PLUGIN.NAME .. "::CASETA_ACTIONS::blindsDown): Sending command :'" .. cmd .. "' ...")
      CASETA_LIP:sendCommand(cmd)
    else
      debug("(" .. PLUGIN.NAME .. "::CASETA_ACTIONS::blindsDown): Sending command...")
      CASETA_LEAP:blindLower(zoneId)
    end
    return 4, 0
  end,
  blindsStop = function(self, lul_device)
    local integrationId = nil
    local zoneId = ""
    local devType = ""
    local cmd = ""
    for k, v in pairs(CASETA.DEVICES) do
      if v.VID == lul_device then
        integrationId = v.ID
        if ((CASETA["LIP"].ENABLED == true) and (PLUGIN.DISABLE_LIP == false)) then
          integrationId = v.LIPid
        end
        zoneId = v.ID
        devType = v.TYPE
      end
    end
    if (integrationId == nil) then
      debug("(" .. PLUGIN.NAME .. "::CASETA_ACTIONS::blindsStop): intergrationId not found for vera device [" .. (lul_device or "NIL") .. "].")
      return 2, 0
    end
    if devType == "SHADEGRP" then
      cmd = "#SHADEGRP," .. integrationId .. ",4"
    else
      cmd = "#OUTPUT," .. integrationId .. ",4"
    end
    if ((CASETA["LIP"].ENABLED == true) and (PLUGIN.DISABLE_LIP == false)) then
      debug("(" .. PLUGIN.NAME .. "::CASETA_ACTIONS::blindsStop): Sending command :'" .. cmd .. "' ...")
      CASETA_LIP:sendCommand(cmd)
    else
      debug("(" .. PLUGIN.NAME .. "::CASETA_ACTIONS::blindsStop): Sending command...")
      CASETA_LEAP:blindStop(zoneId)
    end
    return 4, 0
  end,
  DimUpDown = function(self, lul_device, dimDirection, dimPercent)
    local integrationId = nil
    local zoneId = ""
    local devType = ""
    local cmd = ""
    debug("(" .. PLUGIN.NAME .. "::CASETA_ACTIONS::DimUpDown): Vera [" .. (lul_device or "NIL") .. "] dim direction [" .. (dimDirection or "NIL") .. "] dimPercent [" .. (dimPercent or "NIL") .. "].")
    if ((dimDirection ~= "Up") and (dimDirection ~= "Down")) then
      debug("(" .. PLUGIN.NAME .. "::CASETA_ACTIONS::DimUpDown): Invalid dim direction [" .. (dimDirection or "NIL") .. "].")
      return 2, 0
    end
    for k, v in pairs(CASETA.DEVICES) do
      if v.VID == lul_device then
        integrationId = v.ID
        if ((CASETA["LIP"].ENABLED == true) and (PLUGIN.DISABLE_LIP == false)) then
          integrationId = v.LIPid
        end
        zoneId = v.ZONE
        devType = v.TYPE
      end
    end
    if (integrationId == nil) then
      debug("(" .. PLUGIN.NAME .. "::CASETA_ACTIONS::DimUpDown): intergrationId not found for vera device [" .. (lul_device or "NIL") .. "].")
      return 2, 0
    end
    if ((devType ~= "DIMMER") and (devType ~= "BLIND")) then
      debug("(" .. PLUGIN.NAME .. "::CASETA_ACTIONS::DimUpDown): vera device [" .. (lul_device or "NIL") .. "] is not a dimmer or a blind.")
      return 2, 0
    end
    if (dimPercent == nil) then dimPercent = 10 end
    dimPercent = tonumber(dimPercent, 10) or 0
    if (dimPercent < 1) then dimPercent = 1 end
    if (dimPercent > 100) then dimPercent = 100 end
    -- get the current dim level
    local cLevel = luup.variable_get(VERA.SID["DIMMER"], "LoadLevelStatus", lul_device)
    local newLevel = cLevel + (dimPercent * ((dimDirection:lower() == "down") and -1 or 1))
    if (newLevel > 100) then newLevel = 100 end
    if (newLevel < 0) then newLevel = 0 end
    debug("(" .. PLUGIN.NAME .. "::CASETA_ACTIONS::DimUpDown): dimDirection [" .. (dimDirection or "NIL") .. "] current level [" .. (cLevel or "NIL") .. "] new level [" .. (newLevel or "NIL") .. "].")
    return self:setLoadLevelTarget(lul_device, newLevel, 0)
  end,
  SetPollPeriod = function(self, lul_device, newPollTime)
    debug("(" .. PLUGIN.NAME .. "::SetPollPeriod) Store bridge poll time.")
    if (not newPollTime) then
      debug("(" .. PLUGIN.NAME .. "::SetPollPeriod) ERROR: Poll Time missing.")
      task("No Poll Time in the Poll Time input field.", TASK.ERROR)
      return 2, 0
    end

    local pTime = tonumber(newPollTime, 10)
    if ((pTime == nil) or (pTime < 0)) then
      debug("(" .. PLUGIN.NAME .. "::SetPollPeriod) ERROR: Poll Time invalid.")
      task("Invalid Poll Time in the Poll Time input field.", TASK.ERROR)
      return 2, 0
    end

    UTILITIES:setVariable(VERA.SID["SENSEME"], "pollPeriod", pTime, device)
    PLUGIN.pollPeriod = pTime
    debug("(" .. PLUGIN.NAME .. "::SetPollPeriod) SUCCESS: Poll Time stored [" .. pTime .. "].")
    task("Bridge Poll Time stored.", TASK.BUSY)
    return 4, 0
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
  SetLutronUsername = function(self, lul_device, newUsername)
    debug("(" .. PLUGIN.NAME .. "::SetLutronUsername) Store Lutron Account Username.")
    if (newUsername == nil) then newUsername = "" end
    UTILITIES:setVariable(VERA.SID["SENSEME"], "LUTRON_USERNAME", newUsername, device)
    debug("(" .. PLUGIN.NAME .. "::SetLutronUsername) SUCCESS: Lutron Account Username stored [" .. newUsername .. "].")
    task("Lutron Account Username stored.", TASK.BUSY)
    return 4, 0
  end,
  SetLutronPassword = function(self, lul_device, newPassword)
    debug("(" .. PLUGIN.NAME .. "::SetLutronPassword) Store Lutron Account Password.")
    if (newPassword == nil) then newPassword = "" end
    UTILITIES:setVariable(VERA.SID["SENSEME"], "LUTRON_PASSWORD", newPassword, device)
    debug("(" .. PLUGIN.NAME .. "::SetLutronPassword) SUCCESS: Lutron Account Password stored [" .. newPassword .. "].")
    task("Lutron Account Username stored.", TASK.BUSY)
    return 4, 0
  end,
  RunLutronScene = function(self, lul_device)
    debug("(" .. PLUGIN.NAME .. "::RunLutronScene) Run Lutron Scene started.")
    -- find the scene number for this device
    local sceneId = SENSEME:findSceneByVeraId(lul_device)
    if (sceneId == 0) then
      debug("(" .. PLUGIN.NAME .. "::CASETA_ACTIONS::RunLutronScene): Could not find sceneId for Vera device [" .. (lul_device or "NIL") .. "].")
      return 2, 0
    end
    -- flash the ui button to provide feedback
    UTILITIES:setVariable(VERA.SID["SWITCH"], "Status", 1, lul_device)
    local cmd1 = "#DEVICE,1," .. sceneId .. ",3"
    local cmd2 = "#DEVICE,1," .. sceneId .. ",4"
    if ((CASETA["LIP"].ENABLED == true) and (PLUGIN.DISABLE_LIP == false)) then
      debug("(" .. PLUGIN.NAME .. "::CASETA_ACTIONS::RunLutronScene): Sending scene [" .. (sceneId or "NIL") .. "] command :'" .. cmd1 .. "' ...")
      CASETA_LIP:sendCommand(cmd1)
      CASETA_LIP:sendCommand(cmd2)
    else
      debug("(" .. PLUGIN.NAME .. "::CASETA_ACTIONS::RunLutronScene): Sending scene [" .. (sceneId or "NIL") .. "] command...")
      CASETA_LEAP:runScene(sceneId)
    end
    luup.sleep(250)
    UTILITIES:setVariable(VERA.SID["SWITCH"], "Status", 0, lul_device)
    return 4, 0
  end,
  sendCommandButton = function(self, lul_device, CommandList)
    if CommandList then
      local first = CommandList:sub(1, 1)
      if first ~= "?" and first ~= "~" then
        debug("(" .. PLUGIN.NAME .. "::CASETA_ACTIONS::sendCommandButton): Sending command :'" .. CommandList .. "' ...")
        CommandList = "#" .. CommandList
        CASETA_LIP:sendCommand(CommandList)
      else
        debug("(" .. PLUGIN.NAME .. "::CASETA_ACTIONS::sendCommandButton): Sending command :'" .. CommandList .. "' ...")
        CASETA_LIP:sendCommand(CommandList)
      end
    else
      debug("(" .. PLUGIN.NAME .. "::CASETA_ACTIONS::sendCommandButton): Field cannot be null")
    end
    return 4, 0
  end,
  sendCommandKeypad = function(self, lul_device, CommandKeypad)
    local integrationId = ""
    local componentNumber = {}
    for key, value in pairs(CASETA.DEVICES) do
      if value.VID == lul_device then
        integrationId = value.ID
        if ((CASETA["LIP"].ENABLED == true) and (PLUGIN.DISABLE_LIP == false)) then
          integrationId = v.LIPid
        end
        for i = 1, 6 do
          componentNumber[i] = value.componentNumber[i]
        end
      end
    end
    if componentNumber[tonumber(value)] == "0" then
      debug("(" .. PLUGIN.NAME .. "::CASETA_ACTIONS::sendCommandKeypad): No scene attached to this button!")
    else
      local cmd = "#DEVICE," .. integrationId .. "," .. componentNumber[tonumber(value)] .. "," .. "3"
      debug("(" .. PLUGIN.NAME .. "::CASETA_ACTIONS::sendCommandKeypad): Device <" .. device .. "> with Integration ID  <" .. integrationId .. "> running scene <" .. componentNumber[tonumber(value)] .. ">")
      CASETA_LIP:sendCommand(cmd)
    end
    UTILITIES:setVariable(VERA.SID["SENSEME"], "KeypadCommand", value, device)
    return 4, 0
  end
}

------------------------------------------------------------------------------------------
local MDNS = {
  socket = require("socket"),
  MDNS_IP = "224.0.0.251",
  MDNS_PORT = 5353,
  MDNS_SOCKET = nil,
  decode_rr_flags = function(self, flags)
    function DecToBinary(IN)
      local B, K, OUT, D = 2, "01", ""
      while IN > 0 do
        IN, D = math.floor(IN / B), math.mod(IN, B) + 1
        OUT = string.sub(K, D, D) .. OUT
      end
      return OUT
    end

    bFlags = DecToBinary(flags)
    return {
      QR = tonumber(bFlags:sub(1, 1), 2),
      OPCODE = tonumber(bFlags:sub(2, 5), 2),
      AA = tonumber(bFlags:sub(6, 6), 2),
      TC = tonumber(bFlags:sub(7, 7), 2),
      RD = tonumber(bFlags:sub(8, 8), 2),
      RA = tonumber(bFlags:sub(9, 9), 2),
      Z = tonumber(bFlags:sub(10, 12), 2),
      RCODE = tonumber(bFlags:sub(13, 16), 2)
    }
  end,
  decode_rr_type_name = function(self, typeName)
    local rr_type_names = {
      ["A"] = 1,
      ["NS"] = 2,
      ["CNAME"] = 5,
      ["SOA"] = 6,
      ["WKS"] = 11,
      ["PTR"] = 12,
      ["HINFO"] = 13,
      ["MINFO"] = 14,
      ["MX"] = 15,
      ["TXT"] = 16,
      ["RP"] = 17,
      ["AAAA"] = 28,
      ["SRV"] = 33,
      ["OPT"] = 41,
      ["NSEC"] = 47
    }
    return rr_type_names[typeName] or ("Unknown (" .. typeName .. ")")
  end,
  decode_rr_type = function(self, typeNum)
    local rr_types = {
      [1] = "A",
      [2] = "NS",
      [5] = "CNAME",
      [6] = "SOA",
      [11] = "WKS",
      [12] = "PTR",
      [13] = "HINFO",
      [14] = "MINFO",
      [15] = "MX",
      [16] = "TXT",
      [17] = "RP",
      [28] = "AAAA",
      [33] = "SRV",
      [41] = "OPT",
      [47] = "NSEC"
    }
    return rr_types[tonumber(typeNum, 10)] or ("Unknown (" .. typeNum .. ")")
  end,
  decode_rr_class = function(self, classNum)
    if (classNum == nil) then return nil end
    local class_types = {
      [1] = "IN",
      [3] = "CH",
      [4] = "HS",
      [254] = "QCLASS NONE",
      [255] = "QCLASS ANY"
    }
    return class_types[tonumber(classNum % 32768, 10)] or ("Unknown (" .. classNum .. ")")
  end,
  cStrings = {},
  extract_rr_string = function(self, packet, parseIDX, parseEND, single)
    if (parseEND == nil) then parseEND = #packet end
    if (single == nil) then single = false end
    debug("(CybrMage::mDns::extract_rr_string): starting - idx[ " .. parseIDX .. "] end[" .. (parseEND or "NIL") .. "] single[" .. UTILITIES:print_r(single) .. "]")
    local cPTR = parseIDX
    local dnsStr = ""
    local sLen = packet:byte(parseIDX)
    if (sLen == 0) then
      parseIDX = parseIDX + 1
      return nil, parseIDX
    end
    --print("Initial sLen:"..sLen.." - idx: "..parseIDX)
    while ((sLen ~= nil) and (sLen > 0) and (parseEND > parseIDX)) do
      --print("sLen = "..sLen.." idx = "..parseIDX)
      if (sLen > 191) then
        pIndex = (packet:byte(parseIDX) - 192) + packet:byte(parseIDX + 1) + 1
        print("  lookup cStrings[" .. pIndex .. "]")
        if (cStrings[pIndex] ~= nil) then
          print("    retrieving cStrings[" .. pIndex .. "] = \"" .. cStrings[pIndex] .. "\"")
          dnsStr = dnsStr .. cStrings[pIndex] .. "."
          parseIDX = parseIDX + 2
          sLen = packet:byte(parseIDX)
          if ((sLen == nil) or (sLen == 0) or (single == true)) then break end
        else
          dnsStr = dnsStr .. self:extract_rr_string(packet, pIndex) .. "."
          parseIDX = parseIDX + 2
          sLen = packet:byte(parseIDX)
          if ((sLen == nil) or (sLen == 0) or (single == true)) then break end
        end
      else
        dnsStr = dnsStr .. packet:sub(parseIDX + 1, parseIDX + 0 + sLen) .. "."
        parseIDX = parseIDX + sLen + 1
        sLen = packet:byte(parseIDX)
        if ((sLen == nil) or (sLen == 0) or (single == true)) then
          if (single == false) then
            parseIDX = parseIDX + 1
          end
          break
        end
      end
    end
    if ((cStrings[cPTR] == nil) and (dnsStr ~= "")) then
      debug("  Saving cString[" .. cPTR .. "] = \"" .. dnsStr:sub(1, #dnsStr - 1) .. "\"")
      cStrings[cPTR] = dnsStr:sub(1, #dnsStr - 1)
    end
    debug("(CybrMage::mDns::extract_rr_string): finished - idx[" .. (parseIDX or "NIL") .. "] dnsStr [" .. (dnsStr:sub(1, #dnsStr - 1) or "NIL") .. "]")
    return dnsStr:sub(1, #dnsStr - 1), parseIDX
  end,
  extract_rr_record = function(self, packet, parseIDX, isQuestion)
    debug("(CybrMage::mDns::extract_rr_record): started")
    if (isQuestion == nil) then isQuestion = false end
    local RECORD = {}
    if (parseIDX > #packet) then
      debug("(CybrMage::mDns::extract_rr_record): ERROR: attempt to parse beyond end-of-packet")
      return RECORD
    end
    local dEnd = 0
    local DNS_RESP_NAME = ""
    DNS_RESP_NAME, parseIDX = self:extract_rr_string(packet, parseIDX)
    local DNS_RESP_TYPE = (packet:byte(parseIDX) * 256) + packet:byte(parseIDX + 1)
    parseIDX = parseIDX + 2
    local DNS_RESP_CLASS = (packet:byte(parseIDX) * 256) + packet:byte(parseIDX + 1)
    parseIDX = parseIDX + 2
    debug("(CybrMage::mDns::extract_rr_record): processing resp type [" .. DNS_RESP_TYPE .. "] class [" .. DNS_RESP_CLASS .. "] parseIDX [" .. parseIDX .. "]")
    local DNS_RESP_TTL = nil
    if ((isQuestion == true) or ((DNS_RESP_TYPE == 12) and (DNS_RESP_CLASS > 32767))) then
      RECORD.NAME = DNS_RESP_NAME
      RECORD.TYPE = self:decode_rr_type(DNS_RESP_TYPE)
      RECORD.CLASS = self:decode_rr_class(DNS_RESP_CLASS)
      return parseIDX, RECORD
    end
    DNS_RESP_TTL = ((packet:byte(parseIDX) * 256) + packet:byte(parseIDX + 1) * 65536) + (packet:byte(parseIDX + 2) * 256) + packet:byte(parseIDX + 3)
    parseIDX = parseIDX + 4

    if (DNS_RESP_TYPE == 12) then -- PTR record
    dEnd = parseIDX + (packet:byte(parseIDX) * 256) + packet:byte(parseIDX + 1) + 2
    parseIDX = parseIDX + 2
    local DNS_RESP_DOMAIN_NAME = ""
    DNS_RESP_DOMAIN_NAME, parseIDX = self:extract_rr_string(packet, parseIDX, dEnd)
    RECORD.DOMAIN_NAME = DNS_RESP_DOMAIN_NAME
    elseif (DNS_RESP_TYPE == 1) then -- A record
    local aStr = ""
    aLen = (packet:byte(parseIDX) * 256) + packet:byte(parseIDX + 1)
    parseIDX = parseIDX + 2
    for idx = 1, aLen do
      aStr = aStr .. packet:byte(parseIDX) .. "."
      parseIDX = parseIDX + 1
    end
    RECORD.ADDRESS = aStr:sub(1, #aStr - 1)
    debug("(CybrMage::mDns::extract_rr_record):  Extracted A ADDRESS = \"" .. RECORD.ADDRESS .. "\"")
    elseif (DNS_RESP_TYPE == 28) then -- AAAA record
    local aStr = ""
    aLen = (packet:byte(parseIDX) * 256) + packet:byte(parseIDX + 1)
    parseIDX = parseIDX + 2
    for idx = 1, aLen, 2 do
      aStr = aStr .. string.format("%02X", packet:byte(parseIDX)) .. string.format("%02X", packet:byte(parseIDX + 1)) .. ":"
      parseIDX = parseIDX + 2
    end
    RECORD.ADDRESS = aStr:sub(1, #aStr - 1)
    debug("(CybrMage::mDns::extract_rr_record):  Extracted AAAA ADDRESS = \"" .. RECORD.ADDRESS .. "\"")
    elseif (DNS_RESP_TYPE == 16) then -- TXT record
    local TXT = {}
    dEnd = parseIDX + (packet:byte(parseIDX) * 256) + packet:byte(parseIDX + 1) + 2
    parseIDX = parseIDX + 2
    while (parseIDX < dEnd) do
      DNS_RESP_TXT, parseIDX = self:extract_rr_string(packet, parseIDX, dEnd, true)
      TXT[#TXT + 1] = DNS_RESP_TXT
    end
    RECORD.TXT = TXT
    elseif (DNS_RESP_TYPE == 33) then -- SRV record
    RECORD.LENGTH = (packet:byte(parseIDX) * 256) + packet:byte(parseIDX + 1)
    parseIDX = parseIDX + 2
    local parseEND = parseIDX + RECORD.LENGTH
    RECORD.Priority = (packet:byte(parseIDX) * 256) + packet:byte(parseIDX + 1)
    parseIDX = parseIDX + 2
    RECORD.weight = (packet:byte(parseIDX) * 256) + packet:byte(parseIDX + 1)
    parseIDX = parseIDX + 2
    RECORD.Port = (packet:byte(parseIDX) * 256) + packet:byte(parseIDX + 1)
    parseIDX = parseIDX + 2
    RECORD.Target, parseIDX = self:extract_rr_string(packet, parseIDX, parseEND)
    elseif (DNS_RESP_TYPE == 41) then -- OPT record
    local pSize = DNS_RESP_CLASS
    DNS_RESP_CLASS = nil
    local flags = string.format("%08X", DNS_RESP_TTL)
    DNS_RESP_TTL = nil
    RECORD.eRCODE = tonumber(flags:sub(1, 2), 16)
    RECORD.EDNS0version = tonumber(flags:sub(3, 4), 16)
    RECORD.PAYLOADsize = tonumber(flags:sub(5, 8), 16)
    DNS_RESP_NAME = "<root>"
    RECORD.LENGTH = (packet:byte(parseIDX) * 256) + packet:byte(parseIDX + 1)
    parseIDX = parseIDX + 2
    local parseEND = parseIDX + RECORD.LENGTH
    local OPTIONS = {}
    while (parseIDX < parseEND) do
      local optCODE = (packet:byte(parseIDX) * 256) + packet:byte(parseIDX + 1)
      parseIDX = parseIDX + 2
      local optLength = (packet:byte(parseIDX) * 256) + packet:byte(parseIDX + 1)
      parseIDX = parseIDX + 2
      local optData = ""
      for idx = 1, optLength do
        optData = optData .. string.format("%02X", packet:byte(parseIDX))
        parseIDX = parseIDX + 1
      end
      OPTIONS[#OPTIONS + 1] = {
        CODE = optCODE,
        LENGTH = optLength,
        DATA = optData
      }
    end
    RECORD.OPTIONS = OPTIONS
    elseif (DNS_RESP_TYPE == 47) then -- NSEC record
    RECORD.LENGTH = (packet:byte(parseIDX) * 256) + packet:byte(parseIDX + 1)
    parseIDX = parseIDX + 2
    local parseEND = parseIDX + RECORD.LENGTH
    RECORD.NEXT_NAME, parseIDX = self:extract_rr_string(packet, parseIDX, parseEND)
    RECORD.TYPEBITMAPS = {}
    while (parseIDX < parseEND) do
      bWindow = packet:byte(parseIDX)
      parseIDX = parseIDX + 1
      bLen = packet:byte(parseIDX)
      parseIDX = parseIDX + 1
      local bMap = ""
      for idx = 1, bLen do
        bMap = bMap .. string.format("%02X", packet:byte(parseIDX))
        parseIDX = parseIDX + 1
      end
      local MAP = {}
      MAP.WINDOW = bWindow
      MAP.LENGTH = bLen
      MAP.BITMAP = bMap
      RECORD.TYPEBITMAPS[bWindow] = MAP
    end
    parseIDX = parseEND
    end
    RECORD.NAME = DNS_RESP_NAME
    RECORD.TYPE = DNS_RESP_TYPE
    RECORD.TYPEname = self:decode_rr_type(DNS_RESP_TYPE)
    RECORD.CLASS = self:decode_rr_class(DNS_RESP_CLASS)
    RECORD.TTL = DNS_RESP_TTL
    debug("(CybrMage::mDns::extract_rr_record): finished")
    return parseIDX, RECORD
  end,
  decodePackets = function(self, packets)
    if (packets == nil) then
      debug("(CybrMage::mDns::decodePackets): ERROR: PACKET structure is NIL")
      return {}
    end
    if (type(packets) == "table") then
      local dPackets = {}
      for _, pkt in pairs(packets) do
        dPackets[#dPackets + 1] = self:decodePacket(pkt)
      end
      return dPackets
    elseif (type(packets) == "string") then
      return self:decodePacket(packet)
    end
  end,
  decodePacket = function(self, packet)
    cStrings = {}
    local RESPONSE = {}
    local TID = (packet:byte(1) * 256) + packet:byte(2)
    local FLAGS = self:decode_rr_flags((packet:byte(3) * 256) + packet:byte(4))
    debug("(CybrMage::mDns::decodePacket): FLAGS: " .. UTILITIES:print_r(FLAGS))
    local QUESTIONS = {}
    local numQUESTIONS = (packet:byte(5) * 256) + packet:byte(6)
    debug("(CybrMage::mDns::decodePacket): QUESTIONS: " .. numQUESTIONS)
    local ANSWERS = {}
    local numANSWERS = (packet:byte(7) * 256) + packet:byte(8)
    debug("(CybrMage::mDns::decodePacket): ANSWERS: " .. numANSWERS)
    local AUTHORITY = {}
    local numAUTHORITY = (packet:byte(9) * 256) + packet:byte(10)
    debug("(CybrMage::mDns::decodePacket): AUTHORITYs: " .. numAUTHORITY)
    local ADDITIONAL = {}
    local numADDITIONAL = (packet:byte(11) * 256) + packet:byte(12)
    debug("(CybrMage::mDns::decodePacket): ADDITIONALs: " .. numADDITIONAL)
    local parseIDX = 13

    -- process questions
    if (numQUESTIONS > 0) then
      for loop = 1, numQUESTIONS do
        parseIDX, RECORD = self:extract_rr_record(packet, parseIDX, true)
        QUESTIONS[#QUESTIONS + 1] = RECORD
      end
      RESPONSE.QUESTIONS = QUESTIONS
    end

    -- process answers
    if (numANSWERS > 0) then
      for loop = 1, numANSWERS do
        parseIDX, RECORD = self:extract_rr_record(packet, parseIDX)
        ANSWERS[#ANSWERS + 1] = RECORD
      end
      RESPONSE.ANSWERS = ANSWERS
    end

    -- process authorities
    if (numAUTHORITY > 0) then
      for loop = 1, numAUTHORITY do
        parseIDX, RECORD = self:extract_rr_record(packet, parseIDX)
        AUTHORITY[#AUTHORITY + 1] = RECORD
      end
      RESPONSE.AUTHORITY = AUTHORITY
    end

    -- process additional
    if (numADDITIONAL > 0) then
      for loop = 1, numADDITIONAL do
        parseIDX, RECORD = self:extract_rr_record(packet, parseIDX)
        ADDITIONAL[#ADDITIONAL + 1] = RECORD
      end
      RESPONSE.ADDITIONAL = ADDITIONAL
    end
    RESPONSE.numQUESTIONS = numQUESTIONS
    RESPONSE.numADDITIONAL = numADDITIONAL
    RESPONSE.numAUTHORITY = numAUTHORITY
    RESPONSE.numANSWERS = numANSWERS
    RESPONSE.TransactionID = TID
    RESPONSE.FLAGS = FLAGS
    return RESPONSE
  end,
  getRecordsByType = function(self, Record, rType)
    -- get individual entry from question/answer/authority/additional record array by entry type
    if (type(rType) == "string") then
      rType = self:decode_rr_type_name(rType)
    else
      local typeTest = self:decode_rr_type(rType)
      if (typeTest:find("Unknown")) then rType = nil end
    end
    if ((type(rType) == "string") or (rType == nil)) then
      debug("(CybrMage::mDns::getRecordsByType): ERROR: invalid Recource Record type")
      return nil
    end
    local RESP = {}
    for _, rr in pairs(Record) do
      if (rr.TYPE == rType) then
        RESP[#RESP + 1] = rr
      end
    end
    return (#RESP > 0) and RESP or nil
  end,
  packetHasQuestions = function(self, packet)
    if (((packet:byte(5) * 256) + packet:byte(6)) > 0) then return true else return false end
  end,
  packetHasAnswers = function(self, packet)
    if (((packet:byte(7) * 256) + packet:byte(8)) > 0) then return true else return false end
  end,
  packetHasAuthority = function(self, packet)
    if (((packet:byte(9) * 256) + packet:byte(10)) > 0) then return true else return false end
  end,
  packetHasAdditional = function(self, packet)
    if (((packet:byte(11) * 256) + packet:byte(12)) > 0) then return true else return false end
  end,
  getResponse = function(self, timeout)
    self.MDNS_SOCKET:settimeout(timeout)
    local packet, ip, port = self.MDNS_SOCKET:receivefrom()
    return packet, ip, port
  end,
  sendQuery = function(self, qString)
    function string_split(str, sep)
      local array = {}
      local reg = string.format("([^%s]+)", sep)
      for mem in string.gmatch(str, reg) do
        table.insert(array, mem)
      end
      return array
    end

    if (self.MDNS_SOCKET == nil) then
      debug("(CybrMage::mDns::sendQuery): ERROR: mDns not initialized")
      return false, "Not Initialized"
    end
    if ((qString == nil) or (qString == "")) then
      return false
    end
    local packet = ""
    packet = string.char(0, 0, 0, 0)
    packet = packet .. string.char(0, 1, 0, 0, 0, 0, 0, 0)
    local qStr = string_split(qString, ".")
    for _, Str in pairs(qStr) do packet = packet .. string.char(#Str) .. Str end
    packet = packet .. string.char(0)
    packet = packet .. string.char(0, 12) -- record type
    packet = packet .. string.char(128, 1)

    self.MDNS_SOCKET:sendto(packet, self.MDNS_IP, self.MDNS_PORT)
    return true
  end,
  doQuery = function(self, qString, timeOut)
    if (self.MDNS_SOCKET == nil) then
      debug("(CybrMage::mDns::doQuery): ERROR: mDns not initialized")
      return false, "Not Initialized"
    end
    if (timeOut == nil) then timeOut = 10 end
    if ((qString == nil) or (qString == "")) then
      return false, "No Query"
    end
    if (self:sendQuery(qString) == false) then
      debug("(CybrMage::mDns::doQuery): ERROR: failed to send query packet")
    end

    local Responses = {}
    local endTime = os.time() + timeOut
    while (os.time() < endTime) do
      debug("(CybrMage::mDns::doQuery): Timeout in " .. math.floor(endTime - os.time()) .. " seconds")
      local resp, recv_ip, recv_port = self:getResponse(1)
      debug("(CybrMage::mDns::doQuery): received packet: " .. (resp and #resp or "NIL") .. " bytes")
      --debug(hex_dump(resp))
      if (resp and self:packetHasAnswers(resp)) then
        debug("(CybrMage::mDns::doQuery): ADDED PACKET to response")
        Responses[#Responses + 1] = resp
      end
    end
    debug("(CybrMage::mDns::doQuery): Response size: " .. (#Responses or "NIL") .. " entries")
    if ((Responses ~= nil) and (#Responses > 0)) then
      return true, Responses
    end
    return false, "No mDns responses"
  end,
  getAllServices = function(self, timeOut)
    if (self.MDNS_SOCKET == nil) then
      debug("(CybrMage::mDns::getAllServices): ERROR: mDns not initialized")
      return false, "Not Initialized"
    end
    if (timeOut == nil) then timeOut = 1 end
    if (self:sendQuery("_services._dns-sd._udp.local") == false) then
      debug("(CybrMage::mDns::getAllServices): ERROR: failed to send query packet")
    end

    local Responses = {}
    local endTime = os.time() + timeOut
    while (os.time() < endTime) do
      debug("(CybrMage::mDns::getAllServices): Timeout in " .. math.floor(endTime - os.time()) .. " seconds")
      local resp, recv_ip, recv_port = self:getResponse(1)
      if (resp) then debug("(CybrMage::mDns::getAllServices): received packet: " .. (resp and #resp or "NIL") .. " bytes") end
      --debug(hex_dump(resp))
      if (resp and self:packetHasAnswers(resp)) then
        debug("(CybrMage::mDns::getAllServices): ADDED PACKET to response")
        Responses[#Responses + 1] = { source = recv_ip .. ":" .. recv_port, response = self:decodePacket(resp) }
      end
    end
    debug("(CybrMage::mDns::getAllServices): Response size: " .. (#Responses or "NIL") .. " entries")
    -- convert responses to a table of services keyed by IP address
    local Services = {}
    for idx, pkt in pairs(Responses) do
      local service = {}
      for idx2, svc in pairs(pkt.response.ANSWERS) do
        local svcName = svc.DOMAIN_NAME
        if (svc.DOMAIN_NAME:sub(#svc.DOMAIN_NAME - #svc.NAME, #svc.DOMAIN_NAME) == "." .. svc.NAME) then
          svcName = svc.DOMAIN_NAME:sub(1, #svc.DOMAIN_NAME - #svc.NAME - 1)
        end
        service[#service + 1] = { DOMAIN = svcName, NAME = svc.NAME }
      end
      Services[Responses[idx].source] = service
    end
    return Services
  end,
  OPEN = function(self)
    if (self.MDNS_SOCKET ~= nil) then
      debug("(CybrMage::mDns::CLOSE): ERROR: mDns already initialized")
      return false, "Already Initialized"
    end
    self.MDNS_SOCKET = self.socket.udp()
    self.MDNS_SOCKET:setsockname("0.0.0.0", 5353)
    self.MDNS_SOCKET:setoption("ip-multicast-loop", false)
    self.MDNS_SOCKET:setoption("ip-add-membership", { interface = "0.0.0.0", multiaddr = "224.0.0.251" })
    ip, port = self.MDNS_SOCKET:getsockname()
    assert(ip, port)
    return true
  end,
  CLOSE = function(self)
    if (self.MDNS_SOCKET == nil) then
      debug("(CybrMage::mDns::CLOSE): ERROR: mDns not initialized")
      return false, "Not Initialized"
    end
    self.MDNS_SOCKET:close()
    self.MDNS_SOCKET = nil
    return true
  end
}

------------------------------------------------------------------------------------------
function createSceneControllerEvent(event_device_id, componentId, event_id)
  -- event_device_id = the device index of the device

  debug("(" .. PLUGIN.NAME .. "::createSceneControllerEvent): Processing SceneController Event - device [" .. (event_device_id or "NIL") .. "] componentID [" .. (componentId or "NIL") .. "] event_id [" .. (event_id or "NIL") .. "].", 2)

  local vTimestamp = os.time()
  local pressType = "short"
  -- component ids vary with the remote device type and need to be translated
  local num_buttons = CASETA.DEVICES[event_device_id].NUM_BUTTONS
  local button_base = CASETA.DEVICES[event_device_id].BUTTON_BASE
  local buttonId = 0
  if ((CASETA["LIP"].ENABLED == true) and (PLUGIN.DISABLE_LIP == false)) then
    num_buttons = (CASETA.DEVICES[event_device_id].LIP_NUM_BUTTONS > 0) and CASETA.DEVICES[event_device_id].LIP_NUM_BUTTONS or 1
    button_base = (CASETA.DEVICES[event_device_id].LIP_BUTTON_BASE > 0) and CASETA.DEVICES[event_device_id].LIP_BUTTON_BASE or 1
    buttonId = CASETA.DEVICES[event_device_id].LIP_BUTTON_MAP[componentId]
    debug("(" .. PLUGIN.NAME .. "::createSceneControllerEvent): LIP componentId [" .. (componentId or "NIL") .. "] = buttonId [" .. (buttonId or "NIL") .. "].", 2)
  else
    buttonId = componentId - button_base + 1
  end
  if ((tonumber(buttonId, 10) < 1) or (tonumber(buttonId, 10) > tonumber(num_buttons, 10))) then
    debug("(" .. PLUGIN.NAME .. "::createSceneControllerEvent): Request for Invalid button [" .. (buttonId or "NIL") .. "].", 1)
    return false
  end
  if (tonumber(event_id, 10) == 3) then
    CASETA.DEVICES[event_device_id].LAST_BUTTON_PRESS = vTimestamp
    debug("(" .. PLUGIN.NAME .. "::createSceneControllerEvent): Processed EventID [" .. (event_id or "NIL") .. "] for ButtonID [" .. (buttonId or "NIL") .. "] lastPressTime [" .. (CASETA.DEVICES[event_device_id].LAST_BUTTON_PRESS or "") .. "].", 2)
    return
  elseif (tonumber(event_id, 10) == 4) then
    local lastPressTime = CASETA.DEVICES[event_device_id].LAST_BUTTON_PRESS or 0
    local pressTime = -1
    if (lastPressTime ~= nil) then
      pressTime = vTimestamp - lastPressTime
      if (pressTime > 1) then
        pressType = "long"
      end
    end
    debug("(" .. PLUGIN.NAME .. "::createSceneControllerEvent): Processing EventID [" .. (event_id or "NIL") .. "] for ButtonID [" .. (buttonId or "NIL") .. "] vTimestamp [" .. (vTimestamp or "NIL") .. "] lastPressTime [" .. (CASETA.DEVICES[event_device_id].LAST_BUTTON_PRESS or "NIL") .. "].", 2)
    debug("(" .. PLUGIN.NAME .. "::createSceneControllerEvent): Processing EventID [" .. (event_id or "NIL") .. "] for ButtonID [" .. (buttonId or "NIL") .. "] pressTime [" .. (pressTime or "NIL") .. "] pressType [" .. (pressType or "NIL") .. "].", 2)
  else
    debug("(" .. PLUGIN.NAME .. "::createSceneControllerEvent): Request for Invalid EventID [" .. (event_id or "NIL") .. "].", 1)
    return false
  end
  if ((pressType ~= "short") and (pressType ~= "long")) then
    debug("(" .. PLUGIN.NAME .. "::createSceneControllerEvent): Request for Invalid PressType [" .. (pressType or "NIL") .. "].", 1)
    return false
  end
  debug("(" .. PLUGIN.NAME .. "::createSceneControllerEvent): Request for button [" .. (buttonId or "NIL") .. "].", 2)

  local lFireEvent = UTILITIES:getVariable(VERA.SID["KEYPAD"], "FiresOffEvents", CASETA.DEVICES[event_device_id].VID)
  -- if the device is configured for firing OFF events, use a long ( > 2 seconds) button press to deactivate the scene
  -- otherwise, use the press/long press event to activate a scene
  if (tonumber(lFireEvent, 10) == 1) then
    debug("(" .. PLUGIN.NAME .. "::createSceneControllerEvent): FireOffEvents [ENABLED].", 2)
    -- activate / deactivate processing
    local ButtonAction = "sl_SceneActivated"
    if (pressType == "long") then
      -- long button press
      ButtonAction = "sl_SceneDeactivated"
    end
    -- trigger the scene
    --		buttonId = buttonId -1
    debug("(" .. PLUGIN.NAME .. "::createSceneControllerEvent): Scene Request - scene [" .. (buttonId or "NIL") .. "] action [" .. (ButtonAction or "NIL") .. "].", 2)
    luup.variable_set(VERA.SID["KEYPAD"], ButtonAction, (buttonId), CASETA.DEVICES[event_device_id].VID)
    luup.variable_set(VERA.SID["HA_DEVICE"], 'LastUpdate', vTimestamp, CASETA.DEVICES[event_device_id].VID)
    luup.variable_set(VERA.SID["KEYPAD"], "LastSceneID", (buttonId), CASETA.DEVICES[event_device_id].VID)
    luup.variable_set(VERA.SID["KEYPAD"], "LastSceneTime", vTimestamp, CASETA.DEVICES[event_device_id].VID)
  else
    -- activate only processing
    -- convert the button index to allow on and off events to fire twice as many on events
    debug("(" .. PLUGIN.NAME .. "::createSceneControllerEvent): FireOffEvents [DISABLED].", 2)
    local sceneId = ((tonumber(buttonId, 10) * 2) - 1) + ((pressType == "long") and 1 or 0)
    debug("(" .. PLUGIN.NAME .. "::createSceneControllerEvent): Scene Request - scene [" .. (sceneId or "NIL") .. "] action [sl_SceneActivated].", 2)
    luup.variable_set(VERA.SID["KEYPAD"], "sl_SceneActivated", sceneId, CASETA.DEVICES[event_device_id].VID)
    luup.variable_set(VERA.SID["HA_DEVICE"], 'LastUpdate', vTimestamp, CASETA.DEVICES[event_device_id].VID)
    luup.variable_set(VERA.SID["KEYPAD"], "LastSceneID", sceneId, CASETA.DEVICES[event_device_id].VID)
    luup.variable_set(VERA.SID["KEYPAD"], "LastSceneTime", vTimestamp, CASETA.DEVICES[event_device_id].VID)
  end
  return true
end

------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------
local function RESPONSES_HANDLER(cmd, parameters)
  local param = CASETA_LIP:getParameters(parameters) -- param[2] 	= Action Number, param[3-5] 	= Parameters
  debug("(" .. PLUGIN.NAME .. "::RESPONSES_HANDLER:" .. (cmd or "NIL") .. "): PARAMETER received :" .. (parameters or "NIL"))
  if ((cmd == "OUTPUT") or (cmd == "DEVICE") or (cmd == "SHADEGRP") or (cmd == "AREA")) then
    CASETA_LIP:setUI(param, cmd)
    debug("(" .. PLUGIN.NAME .. "::RESPONSES_HANDLER:" .. (cmd or "NIL") .. "): Processed status for device with Integration ID :" .. (param[1] or "NIL"))
  elseif (cmd == "ERROR") then
    debug("(" .. PLUGIN.NAME .. "::RESPONSES_HANDLER:ERROR): " .. (CASETA.LIP_CONSTANTS.errorMessage[param[1]] or "NIL"))
  end
end

------------------------------------------------------------------------------------------
function handleResponseLIP(data)
  debug("(" .. PLUGIN.NAME .. "::handleResponseLIP): raw data [" .. (data:gsub("\r", "\\r"):gsub("\n", "\\n") or "NIL") .. "].", 2)
  data = data:gsub("\r", "")
  data = data:gsub("GNET> \n", ""):gsub("\nGNET> ", ""):gsub("GNET> ", "")
  if (data == "") then
    debug("(" .. PLUGIN.NAME .. "::handleResponseLIP): No data to process.", 1)
    return false
  end
  debug("(" .. PLUGIN.NAME .. "::handleResponseLIP): filtered data [" .. (data:gsub("\r", "\\r"):gsub("\n", "\\n") or "NIL") .. "].", 2)
  -- possibility exists for command string to contain multiple command
  for line in string.gmatch(data, "~(.-)\n") do
    debug("(" .. PLUGIN.NAME .. "::handleResponseLIP): input line [" .. (line or "NIL") .. "]")
    local cmd, params = string.match(line, "(%u+),(.*)")
    debug("(" .. PLUGIN.NAME .. "::handleResponseLIP): cmd [" .. (cmd or "NIL") .. "] params [" .. (params or "NIL") .. "].")
    RESPONSES_HANDLER(cmd, params)
    -- debug("("..PLUGIN.NAME.."::handleResponseLIP): ERROR 2 - Unknown or unhandled message received",1)
  end
  return true
end

------------------------------------------------------------------------------------------


------------------------------------------------------------------------------------------
local function SplitString(str, delimiter)
  delimiter = delimiter or "%s+"
  local result = {}
  local from = 1
  local delimFrom, delimTo = str:find(delimiter, from)
  while delimFrom do
    table.insert(result, str:sub(from, delimFrom - 1))
    from = delimTo + 1
    delimFrom, delimTo = str:find(delimiter, from)
  end
  table.insert(result, str:sub(from))
  return result
end


------------------------------------------------------------------------------------------
function getStatusLEAP(value)
  debug("(" .. PLUGIN.NAME .. "::getStatusLEAP): Checking Status")
  local cmd = ""
  local period = tonumber(value)
  for key, dev in pairs(CASETA.DEVICES) do
    if dev.TYPE == "DIMMER" or dev.TYPE == "BLIND" or dev.TYPE == "SWITCH" then
      cmd = cmd .. string.format("{\"CommuniqueType\":\"ReadRequest\",\"Header\":{\"Url\":\"/zone/%s/status\"}}", dev.ZONE) .. "\r\n"
    else
      if dev.TYPE == "SHADEGRP" then
        cmd = cmd .. string.format("{\"CommuniqueType\":\"ReadRequest\",\"Header\":{\"Url\":\"/zone/%s/status\"}}", dev.ZONE) .. "\r\n"
      end
      if dev.devType == "AREA" then
        cmd = cmd .. string.format("{\"CommuniqueType\":\"ReadRequest\",\"Header\":{\"Url\":\"/zone/%s/status\"}}", dev.ZONE) .. "\r\n"
      end
    end
  end
  if (cmd ~= "") then
    local RESP = CASETA_LEAP:sendCommand(cmd)
    debug("(" .. PLUGIN.NAME .. "::getStatusLEAP): processing Status response")
    CASETA_LEAP:processStatus(RESP)
  else
    debug("(" .. PLUGIN.NAME .. "::getStatusLEAP): No Status command to send", 1)
  end
  if (period > 0) then
    luup.call_delay("getStatusLEAP", period, value)
  end
  debug("(" .. PLUGIN.NAME .. "::getStatusLEAP): Status checked")
end

function getStatusLIP(value)
  debug("(" .. PLUGIN.NAME .. "::getStatusLIP): Checking Status")
  local cmd = ""
  local period = tonumber(value)
  for key, dev in pairs(CASETA.DEVICES) do
    if ((dev.TYPE == "DIMMER") or (dev.TYPE == "BLIND") or (dev.TYPE == "SWITCH")) then
      cmd = "?OUTPUT," .. ((dev.LIPid > 0) and dev.LIPid or dev.ID) .. ",1"
      CASETA_LIP:sendCommand(cmd)
    elseif (dev.TYPE == "SHADEGRP") then
      cmd = "?SHADEGRP," .. ((dev.LIPid > 0) and dev.LIPid or dev.ID) .. ",1"
      CASETA_LIP:sendCommand(cmd)
    elseif (dev.devType == "AREA") then
      cmd = "?AREA," .. ((dev.LIPid > 0) and dev.LIPid or dev.ID) .. ",8"
      CASETA_LIP:sendCommand(cmd)
    end
  end
  if (period > 0) then
    luup.call_delay("getStatusLIP", period, value)
  end
  debug("(" .. PLUGIN.NAME .. "::getStatusLIP): Status command sent")
end

local function checkVersion()
  local ui7Check = luup.variable_get(VERA.SID["SENSEME"], "UI7Check", lug_device) or ""

  if ui7Check == "" then
    luup.variable_set(VERA.SID["SENSEME"], "UI7Check", "false", lug_device)
    ui7Check = "false"
  end

  if (luup.version_branch == 1 and luup.version_major == 7) then
    luup.variable_set(VERA.SID["SENSEME"], "UI7Check", "true", lug_device)
    return true
  else
    luup.variable_set(VERA.SID["SENSEME"], "UI7Check", "false", lug_device)
    return false
  end
end

local function getPluginSettings(device)

  local plugin_version = UTILITIES:getVariable(VERA.SID["SENSEME"], "PLUGIN_VERSION")

  local period = luup.variable_get(VERA.SID["SENSEME"], "pollPeriod", device) or ""
  if period == "" then
    PLUGIN.pollPeriod = "300"
    luup.variable_set(VERA.SID["SENSEME"], "pollPeriod", PLUGIN.pollPeriod, device)
    debug("(" .. PLUGIN.NAME .. "::getPluginSettings): ERROR : Polling period set to default value!")
  else
    if (tonumber(period, 10) < 300) then
      period = "300"
    end
    PLUGIN.pollPeriod = period
  end

  if ((plugin_version == nil) or (plugin_version == "") or (plugin_version ~= VERSION)) then
    -- on first run version variable is empty - make sure the panel variables are visible
    -- on subsequent runs, if the version strings do not match, make sure any new variables are visible
    -- panel related VAM variables
    UTILITIES:setVariableDefault(VERA.SID["SENSEME"], "PLUGIN_VERSION", "")
    UTILITIES:setVariableDefault(VERA.SID["SENSEME"], "BRIDGE_IP", "")
    UTILITIES:setVariableDefault(VERA.SID["SENSEME"], "BRIDGE_MAC", "")
    UTILITIES:setVariableDefault(VERA.SID["SENSEME"], "Bridge_MAC_Filter", "")
    UTILITIES:setVariableDefault(VERA.SID["SENSEME"], "MDNS_DEVICES", "")
    UTILITIES:setVariableDefault(VERA.SID["SENSEME"], "ARP_DEVICES", "")
    UTILITIES:setVariableDefault(VERA.SID["SENSEME"], "DebugMode", "0")
    UTILITIES:setVariableDefault(VERA.SID["SENSEME"], "DebugModeText", "DISABLED")
    UTILITIES:setVariableDefault(VERA.SID["SENSEME"], "BRIDGE_STATUS", "")
    UTILITIES:setVariableDefault(VERA.SID["SENSEME"], "pollPeriod", PLUGIN.pollPeriod)
    UTILITIES:setVariableDefault(VERA.SID["SENSEME"], "DEVICE_SUMMARY", "")

    UTILITIES:setVariableDefault(VERA.SID["SENSEME"], "LUTRON_USERNAME", "")
    UTILITIES:setVariableDefault(VERA.SID["SENSEME"], "LUTRON_PASSWORD", "")

    UTILITIES:setVariableDefault(VERA.SID["HA_DEVICE"], "CommFailure", 0)
    UTILITIES:setVariableDefault(VERA.SID["HA_DEVICE"], "Configured", 1)
    UTILITIES:setVariableDefault(VERA.SID["HA_DEVICE"], "ID", "Lutron SmartBridge Controller")
    UTILITIES:setVariableDefault(VERA.SID["HA_DEVICE"], "PollingEnabled", 0)
    UTILITIES:setVariableDefault(VERA.SID["HA_DEVICE"], "PollMinDelay", 60)
  end
  UTILITIES:setVariable(VERA.SID["SENSEME"], "PLUGIN_VERSION", VERSION, lug_device)
  UTILITIES:setStatus("Loading Options...")
  UTILITIES:setVariable(VERA.SID["SENSEME"], "DEVICE_SUMMARY", "", lug_device)

  if (checkVersion() == true) then
    luup.set_failure(0, lul_device)
  end

  local debugMode = luup.variable_get(VERA.SID["SENSEME"], "DebugMode", lug_device) or ""
  if debugMode == "" then
    luup.variable_set(VERA.SID["SENSEME"], "DebugMode", (PLUGIN.DEBUG_MODE and "1" or "0"), lug_device)
  else
    PLUGIN.DEBUG_MODE = (debugMode == "1") and true or false
  end
  UTILITIES:setVariable(VERA.SID["SENSEME"], "DebugModeText", (PLUGIN.DEBUG_MODE and "ENABLED" or "DISABLED"), lug_device)
  --PLUGIN.DEBUG_MODE = true

  PLUGIN.LIP_USERNAME = "lutron"
  PLUGIN.LIP_PASSWORD = "integration"
end

function Get_MQTT_Parameters()
  log("(" .. PLUGIN.NAME .. "::Get_MQTT_Parameters): Attempting to get Lutron account parameters", 2)
  local AUTH_TOKEN = nil
  local username = UTILITIES:getVariable(VERA.SID["SENSEME"], "LUTRON_USERNAME")
  local password = UTILITIES:getVariable(VERA.SID["SENSEME"], "LUTRON_PASSWORD")

  if ((username == nil) or (username == "")) then
    log("(" .. PLUGIN.NAME .. "::Get_MQTT_Parameters): No Lutron username supplied.", 1)
    return false, "No Lutron username", nil
  end
  if ((password == nil) or (password == "")) then
    log("(" .. PLUGIN.NAME .. "::Get_MQTT_Parameters): No Lutron password supplied.", 1)
    return false, "No Lutron password", nil
  end

  local http = require("socket.http")
  local https = require("ssl.https")
  local ltn12 = require("ltn12")
  local respBody = {}

  function do_https_request(method, headers, API_URL, REQUEST, debugFlag, AUTH_TOKEN)
    if (headers == nil) then
      headers = {}
    else
      headers["User-Agent"] = "Mozilla/5.0 (Linux; Android 4.4; Nexus 4 Build/KRT16E) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/30.0.1599.105 Mobile Safari"
      if (REQUEST and (REQUEST:sub(1, 1) == "{")) then
        headers["Content-Type"] = "application/json"
      end
      if ((method == "POST") and ((REQUEST ~= nil) and (REQUEST ~= ""))) then
        headers["Content-Length"] = #REQUEST
      end
    end
    if (method == "GET") then
      if ((REQUEST ~= nil) and (REQUEST ~= "")) then
        API_URL = API_URL .. "?" .. REQUEST
      end
      REQUEST = nil
    end
    if ((AUTH_TOKEN) and ((AUTH_TOKEN ~= nil) and (AUTH_TOKEN ~= ""))) then
      headers["Authorization"] = "Bearer " .. AUTH_TOKEN
      --			print("Authorization: Bearer "..AUTH_TOKEN)
    end
    log("(OAUTH2::LOGIN): Sending https request [" .. method .. "] [" .. API_URL .. "] [" .. (REQUEST or "") .. "].")
    local HTTPS_REQUEST = {
      method = method,
      url = API_URL,
      headers = headers,
      sink = ltn12.sink.table(respBody),
      verify = "none",
      mode = "client",
      protocol = "tlsv1",
      options = "all",
      redirect = false
    }
    if (REQUEST) then
      HTTPS_REQUEST.source = ltn12.source.string(REQUEST)
    end
    local rBody, rCode, rHeaders, rStatus = https.request(HTTPS_REQUEST)
    --		if (debugFlag == true) then
    log("(OAUTH2::LOGIN): Received https response [" .. (rCode or "FAILED") .. "] [" .. (rStatus or "NIL") .. "] [" .. (table.concat(rHeaders or {}) or "") .. "] [" .. (table.concat(respBody or {}) or "") .. "].")
    --		end
    return rCode, rHeaders, respBody
  end

  function do_http_request(method, headers, API_URL, REQUEST, CONTENT_TYPE, debugFlag, AUTH_TOKEN)
    if (headers == nil) then
      headers = {}
    else
      headers["User-Agent"] = "Mozilla/5.0 (Linux; Android 4.4; Nexus 4 Build/KRT16E) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/30.0.1599.105 Mobile Safari"
      if (REQUEST and (REQUEST:sub(1, 1) == "{")) then
        headers["Content-Type"] = "application/json"
      end
      if ((method == "POST") and ((REQUEST ~= nil) and (REQUEST ~= ""))) then
        headers["Content-Length"] = #REQUEST
      end
    end
    if (method == "GET") then
      if ((REQUEST ~= nil) and (REQUEST ~= "")) then
        API_URL = API_URL .. "?" .. REQUEST
      end
      REQUEST = nil
    end
    if ((AUTH_TOKEN) and ((AUTH_TOKEN ~= nil) and (AUTH_TOKEN ~= ""))) then
      headers["Authorization"] = "Bearer " .. AUTH_TOKEN
      --			print("Authorization: Bearer "..AUTH_TOKEN)
    end
    --		log("(OAUTH2::LOGIN): Sending http request ["..method.."] ["..API_URL.."].")
    if (CONTENT_TYPE and (CONTENT_TYPE ~= "")) then
      headers["Content-Type"] = CONTENT_TYPE
    end
    local HTTP_REQUEST = {
      method = method,
      url = API_URL,
      headers = headers,
      sink = ltn12.sink.table(respBody),
      redirect = true
    }
    if (REQUEST) then
      HTTP_REQUEST.source = ltn12.source.string(REQUEST)
    end
    local rBody, rCode, rHeaders, rStatus = http.request(HTTP_REQUEST)
    if (debugFlag == true) then
      --			log("(OAUTH2::LOGIN): Received http response ["..(rCode or "FAILED").."] ["..(rStatus or "NIL").."] ["..(table.concat(rHeaders or {}) or "").."] ["..(table.concat(respBody or {}) or "").."].")
    end
    return rCode, rHeaders, respBody
  end

  function url_encode(str)
    if (str) then
      str = string.gsub(str, "\n", "\r\n")
      str = string.gsub(str, "([^%w %-%_%.%~])",
        function(c) return string.format("%%%02X", string.byte(c)) end)
      str = string.gsub(str, " ", "+")
    end
    return str
  end

  function ExtractHeader(headers, name)
    for k, v in pairs(headers) do
      --print("testing k ["..k.."] v["..v.."]")
      if (k == name) then
        return v
      end
    end
    return nil
  end


  local CLIENT_ID = "e001a4471eb6152b7b3f35e549905fd8589dfcf57eb680b6fb37f20878c28e5a"
  local CLIENT_SECRET = "b07fee362538d6df3b129dc3026a72d27e1005a3d1e5839eed5ed18c63a89b27"

  local redirect_uri = "urn:ietf:wg:oauth:2.0:oob"

  log("(" .. PLUGIN.NAME .. "::Get_MQTT_Parameters): Connecting to Lutron Sign-In server.", 2)
  -- load the sign-in page
  API_URL = "https://device-login.lutron.com/users/sign_in"
  REQUEST = ""
  local rCode, rHeaders, rBody = do_https_request("GET", {}, API_URL, REQUEST)

  local COOKIE = ExtractHeader(rHeaders or {}, "set-cookie")
  rBody = table.concat(rBody)
  local _, _, aToken = rBody:find('name=\"authenticity_token\" value=\"(.-)\"')
  --	print ("COOKIE: "..COOKIE)
  --	print ("Authenticity_code: "..aToken)
  if (aToken == nil) then
    log("(" .. PLUGIN.NAME .. "::Get_MQTT_Parameters): Connect to Lutron Sign-In server FAILED! rCode [" .. (rCode or "nil") .. "]  rHeaders [" .. UTILITIES:print_r(rHeaders) .. "] rBody [" .. (rBody or "NIL") .. "].", 1)
    return false, "REMOTE DEVICE CONNECT FAILED!!", nil
  else
    log("(" .. PLUGIN.NAME .. "::Get_MQTT_Parameters): AUTHENTICITY TOKEN [" .. (aToken or "nil") .. "].", 2)
  end


  log("(" .. PLUGIN.NAME .. "::Get_MQTT_Parameters): Signing In to Lutron Sign-In server.", 2)
  -- do the login
  API_URL = "https://device-login.lutron.com/users/sign_in?utf8=" .. url_encode("&#x2713;") .. "&" .. url_encode("authenticity_token") .. "=" .. url_encode(aToken) .. "&" .. url_encode("user[email]") .. "=" .. url_encode(username) .. "&" .. url_encode("user[password]") .. "=" .. url_encode(password) .. "&commit=" .. url_encode("Sign In")
  REQUEST = nil
  local rCode, rHeaders, rBody = do_https_request("POST", { ["Cookie"] = COOKIE }, API_URL, REQUEST)
  --	print("Code: "..rCode.." type ["..type(rCode).."]")
  if (tonumber(rCode, 10) == 200) then
    --		print("LOGIN FAILED!!")
    log("(" .. PLUGIN.NAME .. "::Get_MQTT_Parameters): Sign In to Lutron Sign-In server FAILED! rCode [" .. (rCode or "nil") .. "]  rHeaders [" .. UTILITIES:print_r(rHeaders) .. "].", 1)
    return false, "REMOTE DEVICE LOGIN FAILED!!", nil
  else
    --		print("LOGIN OK!!")
  end

  log("(" .. PLUGIN.NAME .. "::Get_MQTT_Parameters): Obtaining Authorization CODE.", 2)
  -- get the authorization code
  COOKIE = ExtractHeader(rHeaders, "set-cookie") or ExtractHeader(rHeaders, "cookie") or ""
  API_URL = "https://device-login.lutron.com/oauth/authorize?redirect_uri=" .. url_encode(redirect_uri) .. "&client_id=" .. url_encode(CLIENT_ID) .. "&response_type=code"
  REQUEST = nil
  rCode, rHeaders, rBody = do_https_request("GET", { ["Cookie"] = COOKIE }, API_URL, REQUEST)
  --	print("Code: "..rCode.." type ["..type(rCode).."]")
  rBody = table.concat(rBody)

  local _, _, AUTHORIZATION_CODE = rBody:find("<code id=\"authorization_code\">(.-)</code>")
  if (AUTHORIZATION_CODE == nil) then
    _, _, AUTHORIZATION_CODE = rBody:find("oauth/authorize/(.-)\"")
  end
  --	print ("AUTHORIZATION_CODE ["..AUTHORIZATION_CODE.."]")
  if ((AUTHORIZATION_CODE == nil) or (AUTHORIZATION_CODE == "")) then
    log("(" .. PLUGIN.NAME .. "::Get_MQTT_Parameters): FAILED to get Authorization CODE.", 1)
    return false, "FAILED to get authorization CODE", nil
  end

  log("(" .. PLUGIN.NAME .. "::Get_MQTT_Parameters): Obtaining Authorization TOKEN.", 2)
  -- get auth token
  API_URL = "https://device-login.lutron.com/oauth/token"
  REQUEST = "redirect_uri=" .. url_encode(redirect_uri) .. "&client_id=" .. url_encode(CLIENT_ID) .. "&client_secret=" .. url_encode(CLIENT_SECRET) .. "&code=" .. url_encode(AUTHORIZATION_CODE) .. "&grant_type=authorization_code"
  --API_URL = "http://device-login.lutron.com/oauth/token?redirect_uri="..url_encode(redirect_uri).."&client_id="..url_encode(CLIENT_ID).."&client_secret="..url_encode(CLIENT_SECRET).."&code="..url_encode(AUTHORIZATION_CODE).."&grant_type=authorization_code"
  --REQUEST = nil
  rCode, rHeaders, rBody = do_https_request("POST", { ["Cookie"] = COOKIE }, API_URL, REQUEST, "application/x-www-form-urlencoded", false)
  rBody = table.concat(rBody)
  if (rCode ~= 200) then
    log("(" .. PLUGIN.NAME .. "::Get_MQTT_Parameters): FAILED to get Authorization TOKEN.", 1)
    return false, "FAILED to get authorization TOKEN", nil
  end
  local _, _, AUTH_TOKEN = rBody:find("{\"access_token\":\"(.-)\"")
  --	print ("AUTHORIZATION_TOKEN ["..AUTH_TOKEN.."]")

  log("(" .. PLUGIN.NAME .. "::Get_MQTT_Parameters): Obtaining user data.", 2)
  --os.exit()
  COOKIE = nil
  API_URL = "https://device-login.lutron.com/api/v1/users/me"
  REQUEST = nil
  --rCode,rHeaders,rBody = do_http_request("GET",{}, API_URL, REQUEST, "application/x-www-form-urlencoded",false,AUTH_TOKEN)
  rCode, rHeaders, rBody = do_https_request("GET", {}, API_URL, REQUEST, false, AUTH_TOKEN)
  if (rCode ~= 200) then
    log("(" .. PLUGIN.NAME .. "::Get_MQTT_Parameters): FAILED to get user data.", 1)
    return false, "FAILED to get user data", nil
  end
  --	print("Code: "..rCode.." type ["..type(rCode).."]")
  rBody = table.concat(rBody)
  rBody = rBody:gsub("<!DOCTYPE html>", ""):gsub("<html(.-)/html>", ""):gsub("\r", ""):gsub("\n", "")
  rBody = rBody:gsub("{\"access_token\":(.-)\"bearer\"}", "")
  rBody = rBody:gsub("}{", "},{")
  XI_DATA = UTILITIES:decode_json("[" .. rBody .. "]")
  XI_DATA = XI_DATA[#XI_DATA] or XI_DATA
  --	print("/api/v1/users/me response: ["..print_r(XI_DATA).."]")

  local MQTT_data = {
    serial = string.lower(XI_DATA.serialnumber),
    ng_id = XI_DATA.xively_ng_id,
    ng_secret = XI_DATA.xively_ng_secret,
    ng_rpcreq = XI_DATA.xively_ng_rpcreq_topic,
    ng_rpcres = XI_DATA.xively_ng_rpcres_topic,
    ng_status = XI_DATA.xively_ng_status_topic,
    username = XI_DATA.xi_username__c,
    password = XI_DATA.xi_password__c,
    IN = XI_DATA.topic_in__c,
    OUT = XI_DATA.topic_out__c,
    STATUS = XI_DATA.topic_status__c
  }

  if ((XI_DATA == nil) or (XI_DATA.xi_username__c == nil) or (XI_DATA.xi_password__c == nil)) then
    log("(" .. PLUGIN.NAME .. "::Get_MQTT_Parameters): FAILED to extract XI data.", 1)
    return false, "No MQTT parameters returned", nil
  end
  log("(" .. PLUGIN.NAME .. "::Get_MQTT_Parameters): Obtained user data [" .. UTILITIES:print_r(MQTT_data) .. "].", 2)
  return true, "OK", MQTT_data
end


function Process_MQTT_Response(topic, payload)
  log("(" .. PLUGIN.NAME .. "::Process_MQTT_Response): Received MQTT message - topic [" .. (topic or "NIL") .. "] payload [" .. (payload or "NIL") .. "].", 1)
  if (topic == PLUGIN.mqttParameters.IN) then
    log("(" .. PLUGIN.NAME .. "::Process_MQTT_Response): Processing MQTT message - topic [" .. (topic or "NIL") .. "] payload [" .. (payload or "NIL") .. "].", 1)
    CASETA_LEAP:processStatus(payload)
  else
  end
end


function MQTT_KeepAlive()
  if (MQTT_CLIENT) then
    MQTT_CLIENT:keepalive()
    luup.call_delay("MQTT_KeepAlive", (MQTT.client.KEEP_ALIVE_TIME / 2), "")
  end
end

function Init(lul_device)
  UTILITIES:setStatus("Initializing devices...")
  local ret, added = SENSEME:appendDevices(lul_device)

  if (ret == false) then
    return false, "Failed to add devices", "Caseta Connect"
  end
  if (added == true) then
    log("(" .. PLUGIN.NAME .. "::Init): Startup Successful. Restart pending. ", 1)
    return true, "Devices added. RESTART pending.", "Caseta Connect"
  end
  -- HERE

  UTILITIES:setStatus("Initializing IO...")
  if ((CASETA["LIP"].ENABLED == true) and (PLUGIN.DISABLE_LIP == false)) then
    UTILITIES:setStatus("Initializing LIP connection...")
    if (luup.io.is_connected(lug_device) == false) then
      log("(" .. PLUGIN.NAME .. "::Init): Connecting to Smart Bridge LIP server @ " .. (PLUGIN.BRIDGE_IP or "NIL") .. ":23.")
      PLUGIN.LIP_LOGIN_COMPLETE = false
      local tries = 0
      PLUGIN.LUUP_IO_MODE = "LIP"
      luup.io.open(lug_device, PLUGIN.BRIDGE_IP, 23)
      --luup.call_delay("do_LIP_Login",1,"")
      -- schedule start of the periodic status sync loop
      luup.sleep(250)
    end
    if (luup.io.is_connected(lug_device) == false) then
      log("(" .. PLUGIN.NAME .. "::Init): Failed to connect to Smart Bridge LIP server @ " .. (PLUGIN.BRIDGE_IP or "NIL") .. ":23.")
      return false, "Failed to connect to LIP server.", "Caseta Connect"
    else
      log("(" .. PLUGIN.NAME .. "::Init): Connection to LIP server established.")
      -- get initial device status
      getStatusLEAP(0)
      luup.call_delay("getStatusLIP", 5, PLUGIN.pollPeriod)
    end
  else
    -- test the remote connection and get the mqtt parameters
    local mqttStatus, mqttError, mqttParameters = false, "", PLUGIN.mqttParameters
    if (mqttParameters ~= nil) then
      mqttStatus = true
    else
      mqttStatus, mqttError, mqttParameters = Get_MQTT_Parameters()
    end
    --mqttStatus = false
    local polling_required = true
    if (mqttStatus == true) then
      UTILITIES:setStatus("Initializing MQTT connection...")
      -- start the mqtt service
      log("(" .. PLUGIN.NAME .. "::Init): LIP server not available... Lutron credentials provided... using MQTT...")
      PLUGIN.mqttParameters = mqttParameters
      log("(" .. PLUGIN.NAME .. "::Init): Bridge MAC [" .. (PLUGIN.mqttParameters.serial or "NIL") .. "] MQTT MAC [" .. (PLUGIN.BRIDGE_MAC or "NIL") .. "].")
      if (PLUGIN.mqttParameters.serial == PLUGIN.BRIDGE_MAC:gsub(":", "")) then
        PLUGIN.LUUP_IO_MODE = "MQTT"
        --				MQTT_CLIENT = MQTT.client.create("v3mqtt.xively.com", 1883, Process_MQTT_Response)
        MQTT_CLIENT = MQTT.client.create("lutron.broker.xively.com", 1883, Process_MQTT_Response)
        MQTT_CLIENT:auth(mqttParameters.username, mqttParameters.password)
        --				MQTT_CLIENT:connect(lug_device, "MQTT_Client")
        MQTT_CLIENT:connect(lug_device, mqttParameters.username)
        MQTT_CLIENT:subscribe({ PLUGIN.mqttParameters.IN, PLUGIN.mqttParameters.OUT, PLUGIN.mqttParameters.STATUS })
        polling_required = false
        -- start the MQTT keepalive timer
        MQTT_KeepAlive()
        -- get the initial device status
        getStatusLEAP(0)
      else
        log("(" .. PLUGIN.NAME .. "::Init): MQTT ERROR - Bridge device is not associated with the provided Lutron account...", 1)
      end
    end
    if (polling_required == true) then
      UTILITIES:setStatus("Initializing device polling...")
      log("(" .. PLUGIN.NAME .. "::Init): LIP server not available... using polling")
      UTILITIES:setStatus("Initializing Polling...")
      getStatusLEAP(PLUGIN.pollPeriod)
    end
  end

  log("(" .. PLUGIN.NAME .. "::Init) : Startup Successful ")
  return true, "Startup complete.", "Caseta Connect"
end


function Startup(lul_device)
  lug_device = lul_device
  log("(" .. PLUGIN.NAME .. "::Startup): SenseMe Gateway v" .. VERSION .. " - ************** STARTING **************", 2)

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
  FILE_MANIFEST:Validate()
  getPluginSettings()
  UTILITIES:setStatus("Creating Icons...")
  ICONS:CreateIcons()

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
