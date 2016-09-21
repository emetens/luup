-- local TEMP_SENSOR_ID = 63 -- living room

local THERMOSTAT_ID = 6
local TEMP_SENSOR_ID = 63
local TARGET_TEMP = 70

-- get thermostat temp

local thermostatTemp = luup.variable_get(
	"urn:upnp-org:serviceId:TemperatureSensor1", "CurrentTemperature", THERMOSTAT_ID)
luup.log(THERMOSTAT_ID .. "### thermostat temperature " .. thermostatTemp)

-- get sensor temp

local sensorTemp = luup.variable_get(
	"urn:upnp-org:serviceId:TemperatureSensor1", "CurrentTemperature", TEMP_SENSOR_ID)
luup.log(TEMP_SENSOR_ID .. "### sensor temperature " .. sensorTemp)

-- assuming heating mode

-- check if we need to start heating

if tonumber(sensorTemp) <= TARGET_TEMP - 1 then
	local mode = luup.variable_get(
		"urn:upnp-org:serviceId:HVAC_UserOperatingMode1", "ModeStatus", THERMOSTAT_ID)
	if mode ~= "HeatOn" then
		luup.call_action(
			"urn:upnp-org:serviceId:HVAC_UserOperatingMode1", "SetModeTarget",
			{NewModeTarget= "HeatOn"}, THERMOSTAT_ID)
		luup.log(THERMOSTAT_ID .. "### thermostat now heating")
	end

	local currentSetpoint = luup.variable_get(
		"urn:upnp-org:serviceId:TemperatureSetpoint1_Cool", "CurrentSetpoint", THERMOSTAT_ID) 

	if tonumber(currentSetpoint) - 2 <= tonumber(thermostatTemp) then 
	  local targetTemp = tostring(tonumber(thermostatTemp)-(-5))
	  luup.call_action(
	  	"urn:upnp-org:serviceId:TemperatureSetpoint1_Cool", "SetCurrentSetpoint", 
	  	{NewCurrentSetpoint= targetTemp}, THERMOSTAT_ID)
		luup.log(THERMOSTAT_ID .. "### already heating, updating target " .. targetTemp)
	end
end

-- check if we need to stop heating

if tonumber(sensorTemp) >= TARGET_TEMP then
	local mode = luup.variable_get("urn:upnp-org:serviceId:HVAC_UserOperatingMode1", "ModeStatus", THERMOSTAT_ID)
	if mode ~= "Off" then
		luup.call_action(
			"urn:upnp-org:serviceId:HVAC_UserOperatingMode1", "SetModeTarget",
			{NewModeTarget= "Off"}, THERMOSTAT_ID)
		luup.log(THERMOSTAT_ID .. "### thermostat off")
	end
end

return true

