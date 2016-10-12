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
