function vehicle = selectVehicle(vehicleID)
%SELECTVEHICLE Return a vehicle profile by ID or name.

arguments
    vehicleID (1,1) string = "tesla-model-y-performance"
end

profiles = evcharge.vehicleProfiles();
ids = string({profiles.ID});
names = string({profiles.Name});
match = find(strcmpi(vehicleID, ids) | strcmpi(vehicleID, names), 1);

if isempty(match)
    error("evcharge:UnknownVehicle", ...
        "Unknown vehicle profile '%s'.", vehicleID);
end

vehicle = profiles(match);
end
