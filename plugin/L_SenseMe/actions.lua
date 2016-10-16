SENSEME_ACTIONS = {
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

    for idx,dev in pairs(SENSEME.SENSEME_DEVICES) do
      if dev.VID == lul_device then
        if (dev.TYPE == "FAN") then
          local fanSpeed = SENSEME:fanSpeedForLoadLevel(newLoadLevelTarget)
          local response = SENSEME_UDP:sendCommand(dev.SENSEME_NAME .. ";FAN;SPD;SET;" .. fanSpeed)
--          if not UTILITIES:string_empty(response) then
--            local responseElements = SENSEME:respponseElements(response)
--            -- TODO check if it is the same device name
--            -- TODO better error management so we can skip updates when we miss
--            local fanSpeed = responseElements[SENSEME_UDP.FAN_SPEED_INDEX]
--            -- TODO cache the value to avoid setting the UI at every poll
--            local level = SENSEME:loadLevelForFanSpeed(fanSpeed)
--            local params = {devID,1,level}
--            SENSEME:setUI(params,"OUTPUT")
--            break
--          end
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
