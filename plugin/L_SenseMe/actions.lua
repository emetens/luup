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
    -- TODO Depending on the type of device (fan speed or dimmer, we will need to send different commands
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
