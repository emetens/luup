--
--
module("L_LutronRA2Telnet1", package.seeall)
local g_username = ""
local g_password = ""
local pollPeriod = ""
local pollPeriodOccupancy = "5"
local index = 0
local log = luup.log
local socket = require("socket")
local flagConnect = false
local flagSendCredentials = true
local ipAddress = ""
local ipPort = ""
local DEBUG_MODE = false
local g_lastTripFlag = false
local g_occupancyFlag = false

local SID = {
	["LUTRON"]   	= "urn:schemas-micasaverde-com:serviceId:LutronRA2Telnet1",
	["SW_POWER"] 	= "urn:upnp-org:serviceId:SwitchPower1",
	["DIMMER"]  	= "urn:upnp-org:serviceId:Dimming1",
	["BLINDS"]		= "urn:upnp-org:serviceId:WindowCovering1",
	["SHADEGRP"] 	= "urn:upnp-org:serviceId:WindowCovering1",
	["KEYPAD"]   	= "urn:upnp-org:serviceId:LutronKeypad1",
	["AREA"] 		= "urn:micasaverde-com:serviceId:SecuritySensor1",
}
local DEVTYPE = {
	["SW_POWER"]           	= "urn:schemas-upnp-org:device:BinaryLight:1",
	["DIMMER"]   		   	= "urn:schemas-upnp-org:device:DimmableLight:1",
	["BLINDS"]   			= "urn:schemas-micasaverde-com:device:WindowCovering:1",
	["SHADEGRP"]   			= "urn:schemas-micasaverde-com:device:WindowCovering:1",
	["KEYPAD"]   			= "urn:schemas-micasaverde-com:device:LutronKeypad:1",
	["AREA"]      			= "urn:schemas-micasaverde-com:device:MotionSensor:1"
}

local errorMessage = {
	["1"]    = "Parameter count mismatch",
	["2"]    = "Object does not exist",
	["3"]    = "Invalid action number",
	["4"]    = "Parameter data out of range",
	["5"]    = "Parameter data malformed",
	["6"]    = "Unsupported Command"
}

local deviceActionNumber = {
	["3"]     = "Press / Close / Occupied",
	["4"]     = "Release / Open / Unoccupied",
	["9"]     = "Set (#) or Get (?) LED State",
	["14"]    = "Set or Get Light Level",
	["18"]    = "Start Raising",
	["19"]    = "Start Lowering",
	["20"]    = "Stop Raising / Lowering",
	["22"]    = "Get battery status",
	["23"]    = "Set a custom lift and tilt level of venetian blinds programmed to the phantom button",
	["24"]    = "Set a custom lift level only of venetian blinds programmed to the phantom button",
	["25"]    = "Set a custom tilt level only of venetian blinds programmed to the phantom button"
}

local outputActionNumber = {
	["1"]     = "Set or Get Zone Level",
	["2"]     = "Start Raising",
	["3"]     = "Start Lowering",
	["4"]     = "Stop Raising / Lowering",
	["5"]     = "Start Flash",
	["6"]     = "Pulse",
	["9"]     = "Set (#) or Get (?) Venetian tilt level only",
	["10"]    = "Set (#) or Get (?) Venetian lift & tilt level",
	["11"]    = "Start raising Venetian tilt",
	["12"]    = "Start lowering Venetian tilt",
	["13"]    = "Stop Venetian tilt",
	["14"]    = "Start raising Venetian lift",
	["15"]    = "Start lowering Venetian lift",
	["16"]    = "Stop Venetian lift"
}

local shadegroupActionNumber = {
	["1"]     = "Set or Get Zone Level",
	["2"]     = "Start Raising",
	["3"]     = "Start Lowering",
	["4"]     = "Stop Raising / Lowering",
	["6"]     = "Set (#) or Get (?) Current Preset",
	["14"]    = "Set (#) Venetian Tilt",
	["15"]    = "Set (#) Lift and Tilt for venetians",
	["16"]    = "Raise Venetian Tilt",
	["17"]    = "Lower Venetian Tilt",
	["18"]    = "Stop Venetian Tilt",
	["19"]    = "Raise Venetian Lift",
	["20"]    = "Lower Venetian Lift",
	["21"]    = "Stop Venetian Lift",
	["28"]    = "Get Horizontal Sheer Shade Region"
}

local g_childDevices = {
	-- .id       -> vera id
	-- .integrationId -> lutron internal id
	-- .devType -> device type (dimmer, blinds , binary light or keypad)
	-- .fadeTime 
	-- .componentNumber = {} -> only for keypads
}

------------------------------------------------------------------------------------------
local function debug() end
------------------------------------------------------------------------------------------
function sendCmd(command)
    -- [[
	local cmd = command
    local startTime, endTime
    local dataSize = string.len(cmd)
    assert(dataSize <= 135)
    startTime = socket.gettime()
    luup.sleep(200)
    if (luup.io.write(cmd) == false) then
        log("(Lutron RA2 Gateway PLugin)::(sendCmd) : Cannot send command " .. command .. " communications error")
        return false
    end
    endTime = socket.gettime()
	debug("(Lutron RA2 Gateway PLugin)::(debug)::(sendCmd) : Sending cmd = [" .. cmd .. "]")
    debug("(Lutron RA2 Gateway PLugin)::(debug)::(sendCmd) : Request returned in " .. math.floor((endTime - startTime) * 1000) .. "ms")
    luup.sleep(100)	
	-- ]]
	-- debug("(Lutron RA2 Gateway PLugin)::(debug)::(sendCmd) : Sending cmd = [" .. command .. "]")
	return true
end
local function setUI(parameters, cmdType)
	local devType = ""
	local id = -1
	local index = 1
	for key,value in pairs(g_childDevices) do
		if value.integrationId == parameters[index] then 
			devType = value.devType
			id = value.id
		end
	end
	if cmdType == "OUTPUT" then
		index = index + 1
		if parameters[index] == "1" then
			if devType == "SW_POWER" then
				local val = tonumber(parameters[index + 1])
				if val == 100  or val == 1 then
					luup.variable_set(SID["SW_POWER"],"Status","1",id)
				else 
					luup.variable_set(SID["SW_POWER"],"Status","0",id)
				end
				debug("(Lutron RA2 Gateway PLugin)::(debug)::(setUI) : SW_POWER : UI has been set")
			elseif devType == "DIMMER" or devType == "BLINDS" then
				luup.variable_set(SID["DIMMER"],"LoadLevelStatus", parameters[index + 1], id)
				debug("(Lutron RA2 Gateway PLugin)::(debug)::(setUI) : DIMMER or BLINDS : UI has been set")
			else
				debug("(Lutron RA2 Gateway PLugin)::(debug)::(setUI) : Unknown command type! ")
			end
		end
	elseif cmdType == "SHADEGRP" then
		index = index + 1
		if parameters[index] == "1" then
			if devType == "SHADEGRP" then
				luup.variable_set(SID["SHADEGRP"],"LoadLevelStatus", parameters[index + 1], id)
				debug("(Lutron RA2 Gateway PLugin)::(debug)::(setUI) : SHADEGROUP : UI has been set")
			end
		end
	elseif cmdType == "AREA" then
		if parameters[3] == "3" then
			luup.variable_set(SID["AREA"], "Tripped", "1", id)
			if not g_lastTripFlag then
				luup.variable_set(SID["AREA"], "LastTrip", os.time(), id)
				g_lastTripFlag = true
			end
			debug("(Lutron RA2 Gateway PLugin)::(debug)::(setUI) : AREA : Device " .. id .. " has been tripped!")
		elseif parameters[3] == "4" then
			luup.variable_set(SID["AREA"], "Tripped", "0", id)
			if g_lastTripFlag then
				g_lastTripFlag = false
			end
			debug("(Lutron RA2 Gateway PLugin)::(debug)::(setUI) : AREA : Device " .. id .. "is not tripped!")
		else
			debug("(Lutron RA2 Gateway PLugin)::(debug)::(setUI) : AREA : Unknown parameters received!!! " .. tostring(parameters[3]))
		end
	else
		index = index + 1
		if parameters[index + 1] == "3" then
			luup.variable_set(SID["LUTRON"],"KeypadCommand",parameters[index],id)
			debug("(Lutron RA2 Gateway PLugin)::(debug)::(setUI) : DEVICE : Unknown command type! ")
		end
	end
end
------------------------------------------------------------------------------------------
local RESPONSES_HANDLERS = {

	["OUTPUT"] = function ( parameters)			-- param[1] 	= Integration ID
		debug("(Lutron RA2 Gateway PLugin)::(debug)::(RESPONSES_HANDLERS) : OUTPUT : PARAMETER received :" .. parameters)
		local param = {}						-- param[2] 	= Action Number
		local k = 0								-- param[3-5] 	= Parameters
		for v in parameters:gmatch("(.-),") do
			k = k + 1
			param[k] = v
		end
		--------------
		setUI(param,"OUTPUT")
		debug("(Lutron RA2 Gateway PLugin)::(debug)::(RESPONSES_HANDLERS) : OUTPUT : " .. outputActionNumber[param[2]] .." for device with Integration ID :" .. param[1])
	end,
	
	["DEVICE"] = function ( parameters)				-- param[1] 	= Integration ID
		debug("(Lutron RA2 Gateway PLugin)::(debug)::(RESPONSES_HANDLERS) : DEVICE : PARAMETER received :" .. parameters)
		local param = {}							-- param[2] 	= Component number
		local k = 0									-- param[3] 	= Action Number
		for v in parameters:gmatch("(.-),") do		-- param[4-6] 	= Parameters
			k = k + 1
			param[k] = v
		end
		--------------
		setUI(param,"DEVICE")
		debug("(Lutron RA2 Gateway PLugin)::(debug)::(RESPONSES_HANDLERS) : DEVICE : " .. deviceActionNumber[param[3]] .." for device with Component number : " .. param[2] .. " and Integration ID : " .. param[1] )
	end,
	
	["SHADEGRP"] = function ( parameters)				-- param[1] 	= Integration ID
		debug("(Lutron RA2 Gateway PLugin)::(debug)::(RESPONSES_HANDLERS) : SHADEGRP : PARAMETER received :" .. parameters)
		local param = {}							-- param[2] 	= Action Number
		local k = 0									-- param[3-6] 	= Parameters
		for v in parameters:gmatch("(.-),") do		
			k = k + 1
			param[k] = v
		end
		--------------
		setUI(param,"SHADEGRP")
		debug("(Lutron RA2 Gateway PLugin)::(debug)::(RESPONSES_HANDLERS) : SHADEGRP : " .. shadegroupActionNumber[param[2]] .." for device with Integration ID : " .. param[1] )
	end,
	
	["AREA"] = function ( parameters)				-- param[1] 	= Integration ID
		debug("(Lutron RA2 Gateway PLugin)::(debug)::(RESPONSES_HANDLERS) : SHADEGRP : PARAMETER received :" .. parameters)
		local param = {}							-- param[2] 	= Action Number
		local k = 0									-- param[3-6] 	= Parameters
		for v in parameters:gmatch("(.-),") do		
			k = k + 1
			param[k] = v
		end
		--------------
		setUI(param,"AREA")
		debug("(Lutron RA2 Gateway PLugin)::(debug)::(RESPONSES_HANDLERS) : AREA : Setting Occupancy State")
	end,
	
	["ERROR"] = function ( parameters)
		local param = parameters:sub(1,1)
		debug("(Lutron RA2 Gateway PLugin)::(debug)::(RESPONSES_HANDLERS) : ERROR : " .. errorMessage[param])
	end
}
------------------------------------------------------------------------------------------
function handleResponse(data)
    debug("(Lutron RA2 Gateway PLugin)::(debug)::(handleResponse) : data received:'" .. data .. "'")
	local param = ""
	local cmd = string.match(data,"(%u+)") or ""
	
	if flagSendCredentials == false then
		if data:find("login") then
			sendCmd(g_username)
			sendCmd(g_password)
		end
	end
	if cmd == "" then
		debug("(Lutron RA2 Gateway PLugin)::(debug)::(handleResponse) : 1 Unknown or unhandled message received")
	else
		if cmd == "GNET" then
				data = string.gsub(data,"GNET> ","")
				cmd = string.match(data,"(%u+)")
		end
	end
	if cmd == "OUTPUT" or cmd == "DEVICE" then
		param = string.match(data, ",(.*)") .. ","
		RESPONSES_HANDLERS[cmd](param)
	elseif cmd == "ERROR" then
		param = string.match(data, ",(.*)")
		RESPONSES_HANDLERS[cmd](param)
	elseif cmd == "SHADEGRP" then
		param = string.match(data, ",(.*)") .. ","
		RESPONSES_HANDLERS[cmd](param)
	elseif cmd == "AREA" then
		param = string.match(data, ",(.*)") .. ","
		RESPONSES_HANDLERS[cmd](param)
	else
		debug("(Lutron RA2 Gateway PLugin)::(debug)::(handleResponse) : 2 Unknown or unhandled message received")
	end
    return true
end
------------------------------------------------------------------------------------------


------------------------------------------------------------------------------------------
local function SplitString (str, delimiter)
	delimiter = delimiter or "%s+"
	local result = {}
	local from = 1
	local delimFrom, delimTo = str:find( delimiter, from )
	while delimFrom do
		table.insert( result, str:sub( from, delimFrom-1 ) )
		from = delimTo + 1
		delimFrom, delimTo = str:find( delimiter, from )
	end
	table.insert( result, str:sub( from ) )
	return result
end

local function getDevices(device)
	local dev = luup.variable_get(SID["LUTRON"],"DeviceList",device) or ""
	if dev == "" then
		luup.variable_set(SID["LUTRON"],"DeviceList","",lug_device)
		return false		
	else
		-- Parse the DeviceData variable.
		local deviceList = SplitString( dev, ';' )
		for k,v in pairs(deviceList) do
			local typedev = v:sub(1,1)
			for val in v:gmatch("(%d+)") do
				index = index + 1
				g_childDevices[index] = {}
				g_childDevices[index].id = -1 
				if typedev == "D" then
					g_childDevices[index].integrationId = val
					g_childDevices[index].devType = "DIMMER"
				elseif typedev == "B" then
					g_childDevices[index].integrationId = val
					g_childDevices[index].devType = "BLINDS"
				elseif typedev == "S" then
					g_childDevices[index].integrationId = val
					g_childDevices[index].devType = "SW_POWER"
				elseif typedev == "K" then
					g_childDevices[index].integrationId = val
					g_childDevices[index].devType = "KEYPAD"
				elseif typedev == "G" then
					g_childDevices[index].integrationId = val
					g_childDevices[index].devType = "SHADEGRP"
				elseif typedev == "A" then
					g_childDevices[index].integrationId = val
					g_childDevices[index].devType = "AREA"
				else
					log("(Lutron RA2 Gateway PLugin)::(getDevices) : ERROR : DeviceList spelling error found")	
				end
			end
		end
	end
	return true
end

local function appendDevices(device)
	local ptr = luup.chdev.start(device)
	local index = 0
	for key, value in pairs(g_childDevices) do
		if value.devType == "DIMMER" then
			luup.chdev.append(device,ptr, value.integrationId,"DIMMER_" .. value.integrationId,DEVTYPE[value.devType],"D_DimmableLight1.xml","","",false)
		elseif value.devType == "BLINDS" then
			luup.chdev.append(device,ptr, value.integrationId,"BLINDS_" .. value.integrationId,DEVTYPE[value.devType],"D_WindowCovering1.xml","","",false)
		elseif value.devType == "SW_POWER" then
			luup.chdev.append(device,ptr, value.integrationId,"BINARY_LIGHT_" .. value.integrationId,DEVTYPE[value.devType],"D_BinaryLight1.xml","","",false)
		elseif value.devType == "KEYPAD" then
			luup.chdev.append(device,ptr, value.integrationId,"KEYPAD_" .. value.integrationId,DEVTYPE[value.devType],"D_LutronKeypad1.xml","","",false)
		elseif value.devType == "SHADEGRP" then
			luup.chdev.append(device,ptr, value.integrationId,"SHADEGRP_" .. value.integrationId,DEVTYPE[value.devType],"D_WindowCovering1.xml","","",false)
		elseif value.devType == "AREA" then
			luup.chdev.append(device,ptr, value.integrationId,"AREA_" .. value.integrationId,DEVTYPE[value.devType],"D_MotionSensor1.xml","","",false)
			g_occupancyFlag = true
		else
			log("(Lutron RA2 Gateway PLugin)::(appendDevices) : ERROR : Unknown device type!")	
		end
		if index > 49 then
			log("(Lutron RA2 Gateway PLugin)::(appendDevices) : ERROR : High number of new devices to create, possible ERROR!")	
			break
		end
	end
	luup.chdev.sync(device,ptr)
end

local function getComponentNumber(id)
	local list = luup.variable_get(SID["LUTRON"],"componentNumber",id)
	local flagError = true
	local componentNumber = {}
	local sub = list:gmatch("(%d+)")
	local index = 1
	for v in sub do
		componentNumber[index] = v
		index = index + 1
	end
	for key,value in pairs(g_childDevices) do
		if value.id == id then
			g_childDevices[key].componentNumber = {}
			for i = 1, 6 do
				if componentNumber[i] then
					g_childDevices[key].componentNumber[i] = componentNumber[i]	
				else
					log("(Lutron RA2 Gateway PLugin)::(getComponentNumber) : ERROR : 'componentNumber' error for device : " .. id)	
					flagError = false
				end
			end
		end
	end
	return flagError
end

------------------------------------------------------------------------------------------
local function setChildID(device)
	local flagError = true
	for key, value in pairs(luup.devices) do
		if value.device_num_parent == device then
            for k,v in pairs(g_childDevices) do
				if v.integrationId == value.id then
					g_childDevices[k].id = key
				end
			end
        end
	end
	
	for key,value in pairs(g_childDevices) do
		if value.devType == "KEYPAD" then
			local componentNumber = luup.variable_get(SID["LUTRON"],"componentNumber",value.id) or ""
			if componentNumber == "" or componentNumber == "default" then
				luup.variable_set(SID["LUTRON"],"componentNumber","default",value.id)
				log("(Lutron RA2 Gateway PLugin)::(setChildID) : ERROR : 'componentNumber' cannot be 'null' or 'default' for device " .. value.id)	
				flagError = false
			else
				flagError = getComponentNumber(value.id)
			end
		elseif value.devType == "SHADEGRP" then
			local delay = luup.variable_get(SID[value.devType],"delayTime",value.id) or ""
			if delay == "" then
				g_childDevices[key].delay = "0"
				luup.variable_set(SID[value.devType],"delayTime","0",value.id)
			else
				g_childDevices[key].delay = delay
			end
		else
			local fadeTime = luup.variable_get(SID[value.devType],"fadeTime",value.id) or ""
			if fadeTime == "" then
				g_childDevices[key].fadeTime = "0"
				luup.variable_set(SID[value.devType],"fadeTime","0",value.id)
			else
				g_childDevices[key].fadeTime = fadeTime
			end
		end
	end
	return flagError
end

local function getInfo(device)
	local flagError = true
	g_username = luup.devices[device].user or ""
	g_password = luup.devices[device].pass or ""
	local period = luup.variable_get(SID["LUTRON"],"pollPeriod", device) or "" 
	if g_username == "" or g_password == "" or g_username == "default" or g_password == "default" then
		luup.attr_set("username","default",device)
		luup.attr_set("password","default",device)
		log( "(Lutron RA2 Gateway PLugin)::(getInfo) : ERROR : Username or Password field cannot be blank or default!" )
		flagError = false
	end
	if period == "" then
		pollPeriod = "30"
		luup.variable_set(SID["LUTRON"], "pollPeriod", pollPeriod, device)
		debug("(Lutron RA2 Gateway PLugin)::(debug)::(getInfo) : ERROR : Polling period set to default value!" )
	else
		pollPeriod = period
	end
	local trash
	ipAddress, trash, ipPort = string.match(luup.devices[lug_device].ip, "^([%w%.%-]+)(:?(%d-))$")
	if ipAddress and ipAddress ~= "" then
		if ipPort==nil or ipPort == "" then
			ipPort = "23"
		end
		flagConnect = true
	else
		log("(Lutron RA2 Gateway PLugin)::(getInfo) : ERROR : Insert IP address!")
		flagError = false
	end
	return flagError
end
--------------------
------ACTIONS-------
function setTarget(device,value)
	local integrationId = ""
	local cmd = ""
	local fadeTime = ""
	for k,v in pairs(g_childDevices) do
		if v.id == device then
			integrationId = v.integrationId
			fadeTime = v.fadeTime
		end
	end
	luup.variable_set(SID["SW_POWER"], "Status", value, device)
	if value == "1" then
		value = 100
	end
	cmd = "#OUTPUT," .. integrationId .. ",1," .. value .. "," .. fadeTime
	sendCmd(cmd)
	debug("(Lutron RA2 Gateway PLugin)::(debug)::(setTarget) : Sending command :'" .. cmd .."' ...")
end

function setArmed(device,value)
	luup.variable_set(SID["AREA"], "Armed", value, device)
	debug("(Lutron RA2 Gateway PLugin)::(debug)::(setArmed) : Device Arm Status was set to " .. value)
end

function setLoadLevelTarget(device,value)
	local integrationId = ""
	local devType = ""
	local cmd = ""
	local fadeTime
	local delay
	for k,v in pairs(g_childDevices) do
		if v.id == device then
			integrationId = v.integrationId
			devType = v.devType
			if devType == "SHADEGRP" then
				delay = v.delay
			else
				fadeTime = v.fadeTime
			end
		end
	end
	if devType == "SHADEGRP" then
		cmd = "#SHADEGRP," .. integrationId .. ",1," .. value .. "," .. delay
	else
		cmd = "#OUTPUT," .. integrationId .. ",1," .. value .. "," .. fadeTime
	end
	sendCmd(cmd)
	debug("(Lutron RA2 Gateway PLugin)::(debug)::(setLoadLevelTarget) : Sending command :'" .. cmd .."' ...")
end
function blindsUP(device)
	local integrationId = ""
	local devType = ""
	local cmd = ""
	for k,v in pairs(g_childDevices) do
		if v.id == device then
			integrationId = v.integrationId
			devType = v.devType
		end
	end
	
	if devType == "SHADEGRP" then
		cmd = "#SHADEGRP," .. integrationId .. ",2"
	else
		cmd = "#OUTPUT," .. integrationId .. ",2"
	end
	sendCmd(cmd)
	debug("(Lutron RA2 Gateway PLugin)::(debug)::(blindsUP) : Sending command :'" .. cmd .."' ...")
end
function blindsDown(device)
	local integrationId = ""
	local devType = ""
	local cmd = ""
	for k,v in pairs(g_childDevices) do
		if v.id == device then
			integrationId = v.integrationId
			devType = v.devType
		end
	end
	if devType == "SHADEGRP" then
		cmd = "#SHADEGRP," .. integrationId .. ",3"
	else
		cmd = "#OUTPUT," .. integrationId .. ",3"
	end
	sendCmd(cmd)
	debug("(Lutron RA2 Gateway PLugin)::(debug)::(blindsDown) : Sending command :'" .. cmd .."' ...")
end
function blindsStop(device)
	local integrationId = ""
	local devType = ""
	local cmd = ""
	for k,v in pairs(g_childDevices) do
		if v.id == device then
			integrationId = v.integrationId
			devType = v.devType
		end
	end
	if devType == "SHADEGRP" then
		cmd = "#SHADEGRP," .. integrationId .. ",4"
	else
		cmd = "#OUTPUT," .. integrationId .. ",4"
	end
	sendCmd(cmd)
	debug("(Lutron RA2 Gateway PLugin)::(debug)::(blindsStop) : Sending command :'" .. cmd .."' ...")
end
function sendCommandButton(value)
	if value then
		local first = value:sub(1,1)
		if first ~= "?" and first ~= "~" then
			value = "#" .. value
			sendCmd(value)
			debug("(Lutron RA2 Gateway PLugin)::(debug)::(sendCommandButton) : Sending command :'" .. value .."' ...")
		else
			sendCmd(value)
			debug("(Lutron RA2 Gateway PLugin)::(debug)::(sendCommandButton) : Sending command :'" .. value .."' ...")
		end
	else
		log("(Lutron RA2 Gateway PLugin)::(sendCommandButton) : Field cannot be null")
	end
end
function sendCommandKeypad(device, value)
	local integrationId = ""
	local componentNumber = {}
	for key,value in pairs(g_childDevices) do
		if value.id == device then
			integrationId = value.integrationId
			for i= 1,6 do
				componentNumber[i] = value.componentNumber[i]
			end
		end
	end
	if componentNumber[tonumber(value)] == "0" then
		log("(Lutron RA2 Gateway PLugin)::(sendCommandKeypad) : No scene attached to this button!")
	else
		local cmd = "#DEVICE," .. integrationId .. "," .. componentNumber[tonumber(value)] .. "," .. "3" 
		sendCmd(cmd)
		debug("(Lutron RA2 Gateway PLugin)::(debug)::(sendCommandKeypad) : Device <" .. device .. "> with Integration ID  <" .. integrationId .. "> running scene <" .. componentNumber[tonumber(value)] .. ">"  )
	end
	luup.variable_set(SID["LUTRON"],"KeypadCommand",value,device)
end

function getStatus(value)
	local cmd = ""
	local period = tonumber(value)
	for key, value in pairs(g_childDevices) do
		if value.devType == "DIMMER" or value.devType == "BLINDS" or value.devType == "SW_POWER" then
			cmd = "?OUTPUT," .. value.integrationId .. ",1" 
			sendCmd(cmd)
		else 
			if value.devType == "SHADEGRP" then
				cmd = "?SHADEGRP," .. value.integrationId .. ",1" 
				sendCmd(cmd)
			end
		end
	end
	luup.call_delay("getStatus", period, value)
	debug("(Lutron RA2 Gateway PLugin)::(debug)::(getStatus) : Status checked")
end

function getOccupancyStatus(value)
	local cmd = ""
	local period = tonumber(value)
	for key, value in pairs(g_childDevices) do
		if value.devType == "AREA" then
			cmd = "?AREA," .. value.integrationId .. ",8" 
			sendCmd(cmd)
		end
	end
	luup.call_delay("getOccupancyStatus", period, value)
	debug("(Lutron RA2 Gateway PLugin)::(debug)::(getOccupancyStatus) : Occupancy Status checked")
end

local function checkVersion()
	local ui7Check = luup.variable_get(SID["LUTRON"], "UI7Check", lug_device) or ""
	
	if ui7Check == "" then
		luup.variable_set(SID["LUTRON"], "UI7Check", "false", lug_device)
		ui7Check = "false"
	end
	
	if( luup.version_branch == 1 and luup.version_major == 7 ) then
		luup.variable_set(SID["LUTRON"], "UI7Check", "true", lug_device)
		return true
	else
		luup.variable_set(SID["LUTRON"], "UI7Check", "false", lug_device)
		return false
	end
end

--------------------
function Init (lul_device)
	lug_device = lul_device
	local debugMode = luup.variable_get( SID["LUTRON"], "DebugMode", lug_device ) or ""
	if debugMode == "" then
		luup.variable_set( SID["LUTRON"], "DebugMode", (DEBUG_MODE and "1" or "0"), lug_device )
	else
		DEBUG_MODE = (debugMode == "1") and true or false
	end

	if DEBUG_MODE then
		debug = log
	end
	local flagError = getDevices(lug_device)
	local flagError2 = getInfo(lug_device)
	--[[
	------------------------------------------------------------------------------
	appendDevices(lug_device)
	local flagError3 = setChildID(lug_device)
	getStatus(pollPeriod)
	if g_occupancyFlag then
		getOccupancyStatus(pollPeriodOccupancy)
	end
	------------------------------------------------------------------------------
	-- ]]
	-- [[
	if flagError and flagError2 then
		appendDevices(lug_device)
		local flagError3 = setChildID(lug_device)
		if flagError3 == false then
			log( "(Lutron RA2 Gateway PLugin)::(Startup) : ERROR : Startup failed! " )
			return  
		end
	else
		if flagError == false then
			log( "(Lutron RA2 Gateway PLugin)::(Startup) : ERROR : Insert Devices List " )
		end
		log( "(Lutron RA2 Gateway PLugin)::(Startup) : ERROR : Startup failed! " )
		return  
	end
	if flagConnect then
		log(string.format ("(Lutron RA2 Gateway PLugin)::(Startup) : ipAddress=%s, ipPort=%s", tostring (ipAddress), tostring (ipPort)))
		luup.io.open (lug_device, ipAddress, ipPort)
		if luup.io.is_connected(lug_device) == false then
			log("(Lutron RA2 Gateway PLugin)::(Startup) : ERROR :  Could not connect to the device!")
			return
		else
			log("(Lutron RA2 Gateway PLugin)::(Startup) : OK :  Connection established, continuing startup ...")	
			sendCmd(g_username)
			luup.sleep(500)
			sendCmd(g_password)
			flagSendCredentials = false
			getStatus(pollPeriod)
			if g_occupancyFlag then
				getOccupancyStatus(pollPeriodOccupancy)
			end
		end
	else
		log( "(Lutron RA2 Gateway PLugin)::(Startup) : ERROR : Insert IP address!" )
	end
	-- ]]
	if checkVersion() then
		luup.set_failure(0, lul_device)
	end
	log( "(Lutron RA2 Gateway PLugin)::(Startup) : Startup Successful " )
	return true
end
