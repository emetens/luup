-- local LIGHT_ID = 143 -- guest
-- local LIGHT_ID = 112 -- master

local LIGHT_ID = 143
local TIMER_DURATION = 10
if allStates == nil then 
  allStates = {}
end
if allStates[LIGHT_ID] == nil then
  allStates[LIGHT_ID] = {}
end

local prev = allStates[LIGHT_ID].prev
local current = luup.variable_get("urn:upnp-org:serviceId:SwitchPower1", "Status",LIGHT_ID)
luup.log(LIGHT_ID .. "### current" .. current)
if (prev == nil or prev == "0") and current == "1" then
  luup.log(LIGHT_ID .. "### start timer")
  local currentTime = os.date("*t")
  allStates[LIGHT_ID].prevTimeMin = currentTime.hour * 64 + currentTime.min
end
if current == "1" then
  local currentTime = os.date("*t")
  local currentTimeMin = currentTime.hour * 64 + currentTime.min
  local deltaTime = currentTimeMin - allStates[LIGHT_ID].prevTimeMin
  luup.log(LIGHT_ID .. "### delta time minutes " .. deltaTime)
  if deltaTime > TIMER_DURATION then
   luup.call_action("urn:upnp-org:serviceId:SwitchPower1", "SetTarget", {newTargetValue = "0"}, LIGHT_ID)
   luup.log(LIGHT_ID .. "### turning off light")
  end
end
allStates[LIGHT_ID].prev=current  
return true