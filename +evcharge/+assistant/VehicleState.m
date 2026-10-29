classdef VehicleState < handle
    %VEHICLESTATE Simulated car state shared by the assistant and the UI.
    %
    %   STATE = EVCHARGE.ASSISTANT.VEHICLESTATE creates a car parked in
    %   Helsinki with 72% charge. The assistant tools read and change this
    %   object; listen to the StateChanged event to refresh a UI.

    properties (SetObservable)
        SoCPercent (1,1) double = 72
        LocationName (1,1) string = "Helsinki"
        OutsideTempC (1,1) double = 5
        BatteryTempC (1,1) double = 12
        VehicleID (1,1) string = "tesla-model-y-performance"
        ChargeLimitPercent (1,1) double = 80
        PreconditioningOn (1,1) logical = false
        PreconditioningTarget (1,1) string = ""
        ActivePlan = []
    end

    events
        StateChanged
    end

    methods
        function obj = VehicleState(options)
            arguments
                options.?evcharge.assistant.VehicleState
            end
            names = string(fieldnames(options))';
            for name = names
                obj.(name) = options.(name);
            end
            props = string(properties(obj))';
            for name = props
                addlistener(obj, name, "PostSet", ...
                    @(~, ~) notify(obj, "StateChanged"));
            end
        end

        function address = startAddress(obj)
            %STARTADDRESS Address string used for route planning.
            address = obj.LocationName + ", Finland";
        end

        function vehicle = vehicle(obj)
            %VEHICLE Selected vehicle profile struct.
            vehicle = evcharge.selectVehicle(obj.VehicleID);
        end

        function s = toStruct(obj)
            %TOSTRUCT Compact description for the LLM.
            v = obj.vehicle();
            usableKWh = v.UsableBatteryCapacityKWh;
            s = struct( ...
                "battery_percent", round(obj.SoCPercent), ...
                "energy_left_kwh", round(obj.SoCPercent / 100 * usableKWh, 1), ...
                "location", obj.LocationName, ...
                "outside_temperature_c", round(obj.OutsideTempC), ...
                "battery_temperature_c", round(obj.BatteryTempC), ...
                "vehicle", v.Name, ...
                "charge_limit_percent", round(obj.ChargeLimitPercent), ...
                "preconditioning_on", obj.PreconditioningOn);
        end
    end

    methods (Static)
        function locations = knownLocations()
            %KNOWNLOCATIONS Start locations offered by the simulated car.
            locations = table( ...
                ["Helsinki"; "Tampere"; "Turku"; "Jyvaskyla"; "Oulu"], ...
                [60.1699; 61.4978; 60.4518; 62.2426; 65.0121], ...
                [24.9384; 23.7610; 22.2666; 25.7473; 25.4651], ...
                VariableNames=["Name", "Latitude", "Longitude"]);
        end
    end
end
