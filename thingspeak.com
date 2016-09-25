local API_KEY = "XXX"

local THERMOSTAT_TEMP_SENSOR_ID = 6

local LIVING_ROOM_TEMP_SENSOR_ID = 63
local LIVING_ROOM_LUX_SENSOR_ID = 64
local LIVING_ROOM_HUM_SENSOR_ID = 65

local PORCH_TEMP_SENSOR_ID = 103
local PORCH_LUX_SENSOR_ID = 104
local PORCH_HUM_SENSOR_ID = 105

local thermostatTemp = luup.variable_get("urn:upnp-org:serviceId:TemperatureSensor1", "CurrentTemperature", THERMOSTAT_TEMP_SENSOR_ID)

local livingRoomTemp = luup.variable_get("urn:upnp-org:serviceId:TemperatureSensor1", "CurrentTemperature", LIVING_ROOM_TEMP_SENSOR_ID)
local livingRoomLux = luup.variable_get("urn:micasaverde-com:serviceId:LightSensor1", "CurrentLevel", LIVING_ROOM_LUX_SENSOR_ID)
local livingRoomHum = luup.variable_get("urn:micasaverde-com:serviceId:HumiditySensor1", "CurrentLevel", LIVING_ROOM_HUM_SENSOR_ID)

local porchTemp = luup.variable_get("urn:upnp-org:serviceId:TemperatureSensor1", "CurrentTemperature", PORCH_TEMP_SENSOR_ID)
local porchLux = luup.variable_get("urn:micasaverde-com:serviceId:LightSensor1", "CurrentLevel", PORCH_LUX_SENSOR_ID)
local porchHum = luup.variable_get("urn:micasaverde-com:serviceId:HumiditySensor1", "CurrentLevel", PORCH_HUM_SENSOR_ID)

-- Send data to ThingSpeak.com
local http = require("socket.http")
http.TIMEOUT = 5
result, status = http.request("http://api.thingspeak.com/update?key=" .. API_KEY .. "&" .. 
	"field1="  .. livingRoomTemp ..
	"&field2=" .. porchTemp ..
	"&field3=" .. livingRoomLux ..
	"&field4=" .. porchLux ..
	"&field5=" .. livingRoomHum ..
	"&field6=" .. porchHum ..
	"&field7=" .. thermostatTemp ..
	"", "run=run")
