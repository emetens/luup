local VERA = {
  SID = {
    ["SENSEME"] = "urn:micasaverde-com:serviceId:SenseMe1",
    ["FAN"]     = "urn:upnp-org:serviceId:FanSpeed1",
    ["DIMMER"]  = "urn:upnp-org:serviceId:Dimming1",
    ["SWITCH"]	= "urn:upnp-org:serviceId:SwitchPower1",
  },
  DEVTYPE = {
    ["FAN"]     = { "urn:schemas-upnp-org:device:SenseMeFan:1", "D_SenseMeFan1.xml" },
    ["DIMMER"]  = { "urn:schemas-upnp-org:device:DimmableLight:1", "D_DimmableLight1.xml" },
    ["SWITCH"]	= {"urn:schemas-upnp-org:device:BinaryLight:1","D_BinaryLight1.xml"},
  },
  DEVFILES = {
    -- TODO clean based on the files we really need
    "D_DimmableLight1.xml",
    "D_DimmableLight1.json",
    "S_Dimming1.xml",
    "S_Color1.xml",
    "S_SwitchPower1.xml",
    "S_EnergyMetering1.xml",
    "S_HaDevice1.xml",
    "D_SenseMeFan1.xml",
    "D_SenseMeFan1.json",
    "S_FanSpeed1.xml"
  }
}
