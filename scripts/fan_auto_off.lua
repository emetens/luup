-- local FAN_ID = 112 -- master fan
-- local SECOND_LIGHT_ID = 111 -- master light

-- local FAN_ID = 143 -- guest fan
-- local SECOND_LIGHT_ID = 142 -- guest light

local FAN_ID = 143
local SECOND_LIGHT_ID = 142
local TIMER_DURATION = 10
if allStates == nil then 
  allStates = {}
end
if allStates[FAN_ID] == nil then
  allStates[FAN_ID] = {}
end

local prev = allStates[FAN_ID].prev
local current = luup.variable_get("urn:upnp-org:serviceId:SwitchPower1", "Status", FAN_ID)
luup.log(FAN_ID .. "### current" .. current)
if (prev == nil or prev == "0") and current == "1" then
  luup.log(FAN_ID .. "### start timer")
  local currentTime = os.date("*t")
  allStates[FAN_ID].prevTimeMin = currentTime.hour * 60 - (-currentTime.min)
end
if current == "1" then

  local currentTime = os.date("*t")
  local currentTimeMin = currentTime.hour * 60 - (-currentTime.min)

  -- turn off once per 10m to avoid race condition when user turn light back on
  local timeLastTurnedOffMin = allStates[FAN_ID].timeLastTurnedOffMin
  local deltaTimeLastTurnedOff = TIMER_DURATION
  if timeLastTurnedOffMin ~= nil then
    deltaTimeLastTurnedOff = currentTimeMin - timeLastTurnedOffMin
  end
  if deltaTimeLastTurnedOff >= TIMER_DURATION then
    local deltaTime = currentTimeMin - allStates[FAN_ID].prevTimeMin
    luup.log(FAN_ID .. "### delta time minutes " .. deltaTime)
    if deltaTime > TIMER_DURATION then
     allStates[FAN_ID].timeLastTurnedOffMin = currentTimeMin
     luup.call_action("urn:upnp-org:serviceId:SwitchPower1", "SetTarget", {newTargetValue = "0"}, FAN_ID)
     luup.call_action("urn:upnp-org:serviceId:SwitchPower1", "SetTarget", {newTargetValue = "0"}, SECOND_LIGHT_ID)
     luup.log(FAN_ID .. "### turning off light")
    end
  end
end
allStates[FAN_ID].prev=current
return true