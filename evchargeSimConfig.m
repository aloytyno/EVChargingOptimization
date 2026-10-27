function config = evchargeSimConfig()
%EVCHARGESIMCONFIG Return default Simulink demo settings.
%
%   CONFIG = EVCHARGESIMCONFIG returns the start and destination labels used
%   by the generated Simulink model. Edit this file to point the Simulink
%   demo at another cached or live-data route.

config.StartAddress = "Helsinki, Finland";
config.DestinationAddress = "Oulu, Finland";
config.Scenario = "helsinki-to-oulu";
config.UseLiveData = false;
end
