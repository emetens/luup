local LIGHT_ID = 129
local LUX_ID = 104

local light = luup.variable_get("urn:upnp-org:serviceId:SwitchPower1", "Status",LIGHT_ID)
if light == "1" then
  return false
end

local lul_lux = luup.variable_get("urn:micasaverde-com:serviceId:LightSensor1","CurrentLevel", LUX_ID)
if (tonumber(lul_lux) > 40) then
 return false
end
return true