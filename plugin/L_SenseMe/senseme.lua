local SENSEME = {
  SENSEME_DEVICES = {
--    {
--      ID = "1", -- TODO do we need this ID at all? what is this used for
--      SENSEME_NAME = "Master Bedroom Fan",
--      NAME = "Master Bedroom Fan",
--      TYPE = "FAN",
--      VID = 0, -- will be assigned during matching
--    },
    {
      ID = "2",
      SENSEME_NAME = "Master Bedroom Fan",
      NAME = "Master Bedroom Fan Light",
      TYPE = "DIMMER",
      VID = 0, -- will be assigned during matching
    },
    {
      ID = "3",
      SENSEME_NAME = "Living Room Fan",
      NAME = "Living Room Fan",
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
          html = html .. "<table><tr><td>MAC:</td><td>" .. DEV.SENSEME_NAME .. "</td></tr>"
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
        if cmdType == "OUTPUT" then
          index = index + 1
          debug("("..PLUGIN.NAME.."::SENSEME::setUI): Processing OUTPUT command - index ["..(index or "NIL").."]...")
          if (tonumber(parameters[index],10) == 1) then -- TODO what does this mean?
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
--            elseif (devType == "FAN") then
--              if (parameters and parameters[index + 1]) then
--                local var = math.floor(tonumber(parameters[index + 1],10))
--                debug("("..PLUGIN.NAME.."::SENSEME::setUI): Setting FAN - VAR ["..(var or "NIL").."].")
--                if (var == 0) then
--                  UTILITIES:setVariable(VERA.SID["DIMMER"],"LoadLevelStatus", "0", id)
--                  UTILITIES:setVariable(VERA.SID["SWITCH"],"Status","0",id)
--                else
--                  UTILITIES:setVariable(VERA.SID["DIMMER"],"LoadLevelStatus", var, id)
--                  UTILITIES:setVariable(VERA.SID["SWITCH"],"Status","1",id)
--                  debug("("..PLUGIN.NAME.."::SENSEME::setUI): DIMMER : Vera device has been updated.")
--                end
--              else
--                debug("("..PLUGIN.NAME.."::SENSEME::setUI): DIMMER : ERROR processing parameters.",1)
--              end
            else
              debug("("..PLUGIN.NAME.."::SENSEME::setUI): ERROR! : Unknown command type! ")
            end
          end
        end

    --    elseif cmdType == "SHADEGRP" then
    --      debug("("..PLUGIN.NAME.."::SENSEME_UDP::setUI): Processing SHADEGRP command...")
    --      index = index + 1
    --      if (parameters and parameters[index] and (parameters[index] == "1")) then
    --        if devType == "SHADEGRP" then
    --          UTILITIES:setVariable(VERA.SID["SHADEGRP"],"LoadLevelStatus", parameters[index + 1], id)
    --          debug("("..PLUGIN.NAME.."::SENSEME_UDP::setUI): SHADEGROUP : Vera device has been set.")
    --        end
    --      end
    --    elseif cmdType == "AREA" then
    --      debug("("..PLUGIN.NAME.."::SENSEME_UDP::setUI): Processing AREA command...")
    --      if (parameters and parameters[3] and (parameters[3] == "3")) then
    --        UTILITIES:setVariable(VERA.SID["AREA"], "Tripped", "1", id)
    --        if not g_lastTripFlag then
    --          UTILITIES:setVariable(VERA.SID["AREA"], "LastTrip", os.time(), id)
    --          g_lastTripFlag = true
    --        end
    --        debug("("..PLUGIN.NAME.."::SENSEME_UDP::setUI): AREA : Device " .. id .. " has been tripped!")
    --      elseif (parameters and parameters[3] and (parameters[3] == "4")) then
    --        UTILITIES:setVariable(VERA.SID["AREA"], "Tripped", "0", id)
    --        if g_lastTripFlag then
    --          g_lastTripFlag = false
    --        end
    --        debug("("..PLUGIN.NAME.."::SENSEME_UDP::setUI): AREA : Device " .. id .. "is not tripped!")
    --      else
    --        debug("("..PLUGIN.NAME.."::SENSEME_UDP::setUI): AREA : Unknown parameters received!!! " .. tostring(parameters[3] or "NIL"))
    --      end
    --    else
    --      debug("("..PLUGIN.NAME.."::SENSEME_UDP::setUI): Processing KEYPAD command...")
    --      index = index + 1
    --      if (parameters and parameters[index] and parameters[index + 1]) then
    --        local button = parameters[index] and tonumber(parameters[index],10) or 0
    --        local event = parameters[index + 1] and tonumber(parameters[index + 1],10) or 0
    --        if (devIdx ~= 1) then	-- ignore device 1 (virtual buttons (scenes) )
    --        if ((event == 3) or (event == 4)) then
    --          debug("("..PLUGIN.NAME.."::SENSEME_UDP::setUI): Processing KEYPAD event - device ["..(devIdx or "NIL").."] button ["..(button or "NIL").."] event ["..(event or "NIL").."].")
    --          createSceneControllerEvent(devIdx, button,event)
    --        else
    --          debug("("..PLUGIN.NAME.."::SENSEME_UDP::setUI): Received unrecognized KEYPAD command - device ["..(devIdx or "NIL").."] button ["..(button or "NIL").."] event ["..(event or "NIL").."].",1)
    --        end
    --        end
    --      else
    --        debug("("..PLUGIN.NAME.."::SENSEME_UDP::setUI): Error processing KEYPAD command parameters.",1)
    --      end
    --    end
    debug("("..PLUGIN.NAME.."::SENSEME_UDP::setUI): Processing COMPLETE.")
  end,

  loadLevelForFanSpeed = function(self,fanSpeed)
    local loadLevel = fanSpeed * 100 / 7
    if loadLevel < 0 then
      loadLevel = 0
    end
    if loadLevel > 100 then
      loadLevel = 100
    end
    return loadLevel
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
    if (dev.TYPE == "DIMMER") then -- TODO handle other device type (fan)
      local response = SENSEME_UDP:sendCommand(dev.SENSEME_NAME .. ";FAN;SPD;GET;ACTUAL")
      if not UTILITIES:string_empty(response) then
        local responseElements = SENSEME:respponseElements(response)
  -- TODO check if it is the same device name
  -- TODO better error management so we can skip updates when we miss
        local fanSpeed = responseElements[SENSEME_UDP.FAN_SPEED_INDEX]
  -- TODO cache the value to avoid setting the UI at every poll
        local level = SENSEME:loadLevelForFanSpeed(fanSpeed)
        local params = {devID,1,level}
          SENSEME:setUI(params,"OUTPUT")
        break
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
