function s = planToStruct(plan)
%PLANTOSTRUCT JSON-ready view of a trip plan for external UIs.
%
%   S = EVCHARGE.API.PLANTOSTRUCT(PLAN) combines the driver summary from
%   evcharge.assistant.summarizePlan with the arrays a UI needs to draw the
%   battery chart and the route map. Lists are cell arrays so jsonencode
%   always produces JSON arrays, even with one element.

arguments
    plan struct
end

s = evcharge.assistant.summarizePlan(plan);
s.status = plan.Status;
s.next_action = evcharge.ui.nextActionText(plan);
s.trip_time_text = evcharge.ui.formatDuration(plan.TotalTripTimeMinutes);
s.margin_percent = plan.MarginSoCPercent;
s.destination_percent = plan.DestinationSoCPercent;

% Stops with coordinates for map markers.
stops = cell(1, height(plan.Stops));
for k = 1:height(plan.Stops)
    stop = s.stops(k);
    stop.latitude = plan.Stops.Latitude(k);
    stop.longitude = plan.Stops.Longitude(k);
    stops{k} = stop;
end
s.stops = stops;

if isfield(s, "warnings")
    s.warnings = cellstr(s.warnings);
else
    s.warnings = {};
end

profile = plan.SoCProfile;
s.soc_profile = struct( ...
    "distance_km", {num2cell(profile.DistanceKm')}, ...
    "soc_percent", {num2cell(profile.SoCPercent')}, ...
    "event", {cellstr(profile.Event')});

route = struct("latitude", {{}}, "longitude", {{}});
if isfield(plan, "RoutePoints") && height(plan.RoutePoints) > 0
    route.latitude = num2cell(plan.RoutePoints.Latitude');
    route.longitude = num2cell(plan.RoutePoints.Longitude');
end
s.route = route;
end
