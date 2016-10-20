# Haiku Fans Plugin For VeraLite

This is a [VeraLite](http://getvera.com/controllers/veralite/) plugin for [Haiku Fans](https://www.haikuhome.com) From Big Ass Solutions.
Plugin supports fans and lights with SenseMe enabled. This is for UI7.
 
This is how your fans will display on the vera dashboard:

![Alt](docs/fans.png "Fans")
 
Fan lights display as a regular dimmer:

![Alt](docs/dimmer.png "Dimmer")

The SenseMe gateway device will display like this:

![Alt](docs/gateway.png "Gateway")
 
Currently the plugin fully support the lights and in addition to setting the fan speed, it allows switching the motion sensor, light sensor and whoosh mode. 
 
## Install 

Install and config is pretty manual.
  
--- add details ---

This is optional - if you don't copy the icons to the controller, it will display generic ones.

copy icons:
scp haiku_fan_off.png root@192.168.1.108:/www/cmh/skins/default/img/devices/device_states/
scp haiku_fan_on.png  root@192.168.1.108:/www/cmh/skins/default/img/devices/device_states/
scp haiku.png  root@192.168.1.108:/www/cmh/skins/default/img/devices/device_states/
 
## Thanks

 - https://github.com/sean9keenan/BigAssFansAPI - for all the SenseMe messages
 - http://bruce.pennypacker.org/2015/07/17/hacking-bigass-fans-with-senseme/ - for the great intro to SenseMe
 - http://www.lutron.com/en-US/Pages/default.aspx - This source code is based on the Caseta plugin 






