function routeData = getRouteData(options)
%GETROUTEDATA Return route and charging-station data for the demo.
%
%   ROUTEDATA = GETROUTEDATA("Scenario", NAME) returns cached Finland data.
%
%   ROUTEDATA = GETROUTEDATA(..., "UseLiveData", true) first tries a
%   public OpenStreetMap-based route request and falls back to cached data.
%   The live path is intentionally isolated from the rest of the demo so
%   Simulink and the optimizer remain deterministic.

arguments
    options.StartAddress (1,1) string = "Helsinki, Finland"
    options.DestinationAddress (1,1) string = "Oulu, Finland"
    options.Scenario (1,1) string = "helsinki-to-oulu"
    options.UseLiveData (1,1) logical = false
    options.DepartureTime (1,1) datetime = datetime("now", TimeZone="UTC")
end

if options.UseLiveData
    try
        routeData = evcharge.internal.liveRouteData( ...
            options.StartAddress, options.DestinationAddress, ...
            options.DepartureTime);
        routeData.Source = "live-public-api";
        return
    catch ME
        warning("evcharge:LiveDataFallback", ...
            "Live route data failed (%s). Falling back to cached Finland data.", ...
            ME.message);
    end
end

routeData = evcharge.getScenario(options.Scenario);
routeData.StartAddress = options.StartAddress;
routeData.DestinationAddress = options.DestinationAddress;
routeData.Source = "cached-finland";
end
