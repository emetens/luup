SENSEME_ACTIONS = {
  SetMotion = function(self, lul_device, motionOnOrOff)
    debug("(" .. PLUGIN.NAME .. "::SENSEME_ACTIONS::SetMotion): device [" .. (lul_device or "NIL") .. "] motionOnOrOff [" .. (motionOnOrOff or "NIL") .. "]", 1)
    for idx,dev in pairs(SENSEME.SENSEME_DEVICES) do
      if dev.VID == lul_device then
        if (dev.TYPE == "FAN") then
           local motionValue = SENSEME:senseMeValueFromVar(motionOnOrOff)
           local response = SENSEME_UDP:sendCommand(dev.SENSEME_NAME .. ";FAN;AUTO;" .. motionValue)
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
          local response = SENSEME_UDP:sendCommand(dev.SENSEME_NAME .. ";FAN;AUTO;" .. motionValue)
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
          local response = SENSEME_UDP:sendCommand(dev.SENSEME_NAME .. ";FAN;WHOOSH;" .. whooshValue)
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
          local response = SENSEME_UDP:sendCommand(dev.SENSEME_NAME .. ";FAN;SPD;SET;" .. fanSpeed)
          local params = {dev.ID,1,newLoadLevelTarget}
          SENSEME:setUI(params,"OUTPUT")
          break
        end
        if (dev.TYPE == "DIMMER") then
          local lightLevel = SENSEME:dimmerForLoadLevel(newLoadLevelTarget)
          local response = SENSEME_UDP:sendCommand(dev.SENSEME_NAME .. ";LIGHT;LEVEL;SET;" .. lightLevel)
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
