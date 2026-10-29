classdef tAssistantTools < matlab.unittest.TestCase
    %TASSISTANTTOOLS Offline tests for the EV assistant tool layer.

    properties
        RunTool
        State
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture( ...
                matlab.unittest.fixtures.PathFixture(root));
        end
    end

    methods (TestMethodSetup)
        function createTools(testCase)
            [~, testCase.RunTool] = evcharge.assistant.tools(UseLiveData=false);
            testCase.State = evcharge.assistant.VehicleState( ...
                SoCPercent=72, OutsideTempC=5, BatteryTempC=20);
        end
    end

    methods (Test)
        function toolDefinitionsMatchDispatcher(testCase)
            [defs, runTool] = evcharge.assistant.tools(UseLiveData=false);
            testCase.verifyNumElements(defs, 4);
            for k = 1:numel(defs)
                name = defs(k).FunctionName;
                result = runTool(name, struct(), testCase.State);
                testCase.verifyFalse(isfield(result, "error") ...
                    && contains(result.error, "Unknown tool"), name);
            end
        end

        function planTripToOuluNeedsStops(testCase)
            result = testCase.RunTool("plan_trip", ...
                struct("destination", "Oulu"), testCase.State);
            testCase.verifyTrue(result.can_reach_destination);
            testCase.verifyGreaterThan(result.number_of_stops, 0);
            testCase.verifyEqual(numel(result.stops), result.number_of_stops);
            testCase.verifyGreaterThanOrEqual(result.arrival_battery_percent, 10);
            testCase.verifyNotEmpty(testCase.State.ActivePlan);
            testCase.verifyFalse(result.preconditioning_scheduled);
        end

        function planTripToTampereNeedsNoStops(testCase)
            result = testCase.RunTool("plan_trip", ...
                struct("destination", "Tampere"), testCase.State);
            testCase.verifyTrue(result.can_reach_destination);
            testCase.verifyEqual(result.number_of_stops, 0);
        end

        function unknownOfflineDestinationIsRefused(testCase)
            result = testCase.RunTool("plan_trip", ...
                struct("destination", "Turku"), testCase.State);
            testCase.verifyTrue(isfield(result, "error"));
            testCase.verifySubstring(result.error, "Tampere");
            testCase.verifyEmpty(testCase.State.ActivePlan);
        end

        function coldOutsideIncreasesEnergy(testCase)
            warm = testCase.RunTool("plan_trip", ...
                struct("destination", "Oulu"), testCase.State);
            testCase.State.OutsideTempC = -15;
            cold = testCase.RunTool("plan_trip", ...
                struct("destination", "Oulu"), testCase.State);
            testCase.verifyGreaterThan(cold.energy_needed_kwh, ...
                warm.energy_needed_kwh);
            testCase.verifyGreaterThan( ...
                cold.energy_factors.cold_weather_extra_percent, 0);
        end

        function coldBatterySchedulesPreconditioning(testCase)
            testCase.State.BatteryTempC = -5;
            result = testCase.RunTool("plan_trip", ...
                struct("destination", "Oulu"), testCase.State);
            testCase.verifyTrue(result.preconditioning_scheduled);
            testCase.verifyTrue(testCase.State.PreconditioningOn);
            testCase.verifyEqual(testCase.State.PreconditioningTarget, ...
                string(result.stops(1).name));

            % A new trip without charging stops cancels the warming.
            testCase.RunTool("plan_trip", struct("destination", "Tampere"), ...
                testCase.State);
            testCase.verifyFalse(testCase.State.PreconditioningOn);
            testCase.verifyEqual(testCase.State.PreconditioningTarget, "");
        end

        function adviceSuggestsPreconditioningWhenCold(testCase)
            testCase.State.BatteryTempC = 0;
            advice = testCase.RunTool("get_battery_advice", ...
                struct("context", "before_fast_charge"), testCase.State);
            testCase.verifyEqual(string({advice.suggested_actions.action}), ...
                "start_preconditioning");
        end

        function adviceSaysWhenHomeChargingSkipsStops(testCase)
            testCase.State.SoCPercent = 50;
            plan = testCase.RunTool("plan_trip", ...
                struct("destination", "Tampere"), testCase.State);
            testCase.assertTrue(plan.can_reach_destination);
            testCase.assertGreaterThan(plan.number_of_stops, 0);
            advice = testCase.RunTool("get_battery_advice", ...
                struct("context", "before_trip"), testCase.State);
            testCase.verifySubstring(advice.tips(1), "skip the charging stops");
        end

        function adviceSaysStopsNeededEvenWhenFull(testCase)
            testCase.RunTool("plan_trip", struct("destination", "Oulu"), ...
                testCase.State);
            advice = testCase.RunTool("get_battery_advice", ...
                struct("context", "before_trip"), testCase.State);
            testCase.verifySubstring(advice.tips(1), "even with a full battery");
        end

        function savedArrivalTargetIsUsed(testCase)
            testCase.State.ArrivalSoCPercent = 30;
            result = testCase.RunTool("plan_trip", ...
                struct("destination", "Oulu"), testCase.State);
            testCase.verifyEqual(testCase.State.ActivePlan.DestinationSoCPercent, 30);
            testCase.verifyGreaterThanOrEqual(result.arrival_battery_percent, 30);

            % An explicit request in the conversation wins.
            testCase.RunTool("plan_trip", struct("destination", "Oulu", ...
                "arrival_battery_percent", 20), testCase.State);
            testCase.verifyEqual(testCase.State.ActivePlan.DestinationSoCPercent, 20);
        end

        function vehicleStateIsJsonFriendly(testCase)
            result = testCase.RunTool("get_vehicle_state", [], testCase.State);
            decoded = jsondecode(jsonencode(result));
            testCase.verifyEqual(decoded.battery_percent, 72);
            testCase.verifyEqual(string(decoded.location), "Helsinki");
            testCase.verifyEqual(decoded.target_arrival_battery_percent, 10);
            testCase.verifyFalse(isfield(decoded, "charge_limit_percent"));
        end

        function misheardPlaceNamesAreCorrected(testCase)
            fix = @evcharge.assistant.correctPlaceNames;
            testCase.verifyEqual(fix("Drive to Aulu please."), ...
                "Drive to Oulu please.");
            testCase.verifyEqual(fix("Should I charge to 100 tonight?"), ...
                "Should I charge to 100 tonight?");
        end
    end
end
