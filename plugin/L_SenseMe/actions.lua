SENSEME_ACTIONS = {
  setTarget = function(self, lul_device, newTargetValue)
    local value = math.floor(tonumber(newTargetValue, 10))
    local integrationId = nil
    local zoneId = ""
    local fadeTime = 0
    for k, v in pairs(CASETA.DEVICES) do
      if v.VID == lul_device then
        integrationId = v.ID
        zoneId = v.ZONE
        fadeTime = v.fadeTime or 0
      end
    end
    if (integrationId == nil) then
      debug("(" .. PLUGIN.NAME .. "::SENSEME_ACTIONS::setTarget): intergrationId not found for vera device [" .. (lul_device or "NIL") .. "].")
      return 2, 0
    end
    UTILITIES:setVariable(VERA.SID["SWITCH"], "Status", value, lul_device)
    if value == 1 then
      value = 100
    end
    local cmd = "LIGHT;SET;PWR;1" -- generate proper command here
    SENSEME_UDP:sendCommand(cmd)
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
            debug("(" .. PLUGIN.NAME .. "::SENSEME_ACTIONS::setLoadLevelTarget): Using RampTime specified in UPnP command.")
            fadeTime = UTILITIES:SecondsToHMS(newRampTime or 0)
          elseif (fadeTime > 0) then
            -- fadeTime is programmed into the device, and overide is not specified
            debug("(" .. PLUGIN.NAME .. "::SENSEME_ACTIONS::setLoadLevelTarget): Using RampTime specified in device settings.")
            fadeTime = UTILITIES:SecondsToHMS(fadeTime or 0)
          else
            debug("(" .. PLUGIN.NAME .. "::SENSEME_ACTIONS::setLoadLevelTarget): Using default RampTime = 0.")
            fadeTime = 0
          end
        end
      end
    end
    if (integrationId == nil) then
      debug("(" .. PLUGIN.NAME .. "::SENSEME_ACTIONS::setLoadLevelTarget): intergrationId not found for vera device [" .. (lul_device or "NIL") .. "].")
      return 2, 0
    end
    if devType == "SHADEGRP" then
      cmd = "#SHADEGRP," .. integrationId .. ",1," .. newLoadLevelTarget .. "," .. delay
    else
      cmd = "#OUTPUT," .. integrationId .. ",1," .. newLoadLevelTarget .. "," .. fadeTime
    end
    if ((CASETA["LIP"].ENABLED == true) and (PLUGIN.DISABLE_LIP == false)) then
      debug("(" .. PLUGIN.NAME .. "::SENSEME_ACTIONS::setLoadLevelTarget): Sending command :'" .. cmd .. "' ...")
      SENSEME_LIP:sendCommand(cmd)
    else
      debug("(" .. PLUGIN.NAME .. "::SENSEME_ACTIONS::setLoadLevelTarget): Sending command - zone [" .. (zoneId or "NIL") .. "] value [" .. (newLoadLevelTarget or "NIL") .. "]...")
      SENSEME_LEAP:processStatus(SENSEME_LEAP:setLevel(zoneId, newLoadLevelTarget))
    end
    return 4, 0
  end,
  DimUpDown = function(self, lul_device, dimDirection, dimPercent)
    local integrationId = nil
    local zoneId = ""
    local devType = ""
    local cmd = ""
    debug("(" .. PLUGIN.NAME .. "::SENSEME_ACTIONS::DimUpDown): Vera [" .. (lul_device or "NIL") .. "] dim direction [" .. (dimDirection or "NIL") .. "] dimPercent [" .. (dimPercent or "NIL") .. "].")
    if ((dimDirection ~= "Up") and (dimDirection ~= "Down")) then
      debug("(" .. PLUGIN.NAME .. "::SENSEME_ACTIONS::DimUpDown): Invalid dim direction [" .. (dimDirection or "NIL") .. "].")
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
      debug("(" .. PLUGIN.NAME .. "::SENSEME_ACTIONS::DimUpDown): intergrationId not found for vera device [" .. (lul_device or "NIL") .. "].")
      return 2, 0
    end
    if ((devType ~= "DIMMER") and (devType ~= "BLIND")) then
      debug("(" .. PLUGIN.NAME .. "::SENSEME_ACTIONS::DimUpDown): vera device [" .. (lul_device or "NIL") .. "] is not a dimmer or a blind.")
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
    debug("(" .. PLUGIN.NAME .. "::SENSEME_ACTIONS::DimUpDown): dimDirection [" .. (dimDirection or "NIL") .. "] current level [" .. (cLevel or "NIL") .. "] new level [" .. (newLevel or "NIL") .. "].")
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
