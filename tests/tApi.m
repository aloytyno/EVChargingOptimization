classdef tApi < matlab.unittest.TestCase
    %TAPI Offline tests for the JSON command interface used by external UIs.

    properties
        ProgressFile
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture( ...
                matlab.unittest.fixtures.PathFixture(root));
        end
    end

    methods (TestMethodSetup)
        function initSession(testCase)
            folder = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            testCase.ProgressFile = string(fullfile(folder, "progress.jsonl"));
            % Script: plan a trip to Oulu, then answer.
            responses = {toolCall("plan_trip", struct("destination", "Oulu")), ...
                textMessage("You can make it with stops.")};
            health = call(struct("command", "init", "useLiveData", false, ...
                "speech", false, "progressFile", testCase.ProgressFile), ...
                scriptedGenerator(responses));
            testCase.assertTrue(health.model_ok);
            testCase.addTeardown(@() clear("evcharge.api.request"));
        end
    end

    methods (Test)
        function getAndSetState(testCase)
            s = call(struct("command", "getState"));
            testCase.verifyEqual(s.vehicle_id, 'kia-ev6-long-range-2wd');
            testCase.verifyEqual(s.arrival_percent, 10);

            s = call(struct("command", "setState", "soc_percent", 55, ...
                "arrival_percent", 20, "location", "Tampere", ...
                "battery_temp_c", -3));
            testCase.verifyEqual(s.soc_percent, 55);
            testCase.verifyEqual(s.arrival_percent, 20);
            testCase.verifyEqual(s.location, 'Tampere');
            testCase.verifyEqual(s.battery_temp_c, -3);
        end

        function askReturnsPlanForUi(testCase)
            r = call(struct("command", "ask", "text", "Take me to Oulu"));
            testCase.verifyEqual(r.reply, 'You can make it with stops.');
            testCase.verifyEqual(string(r.tools_called), "plan_trip");

            plan = r.plan;
            testCase.verifyTrue(plan.can_reach_destination);
            testCase.verifyGreaterThan(numel(plan.stops), 0);
            stop = plan.stops(1);
            if iscell(plan.stops), stop = plan.stops{1}; end
            testCase.verifyTrue(all(isfield(stop, ["latitude", "longitude", ...
                "name", "charge_minutes"])));
            testCase.verifyEqual(numel(plan.soc_profile.distance_km), ...
                numel(plan.soc_profile.soc_percent));
            testCase.verifySubstring(plan.next_action, "Charge at");
            testCase.verifyTrue(r.state.has_plan);
        end

        function singleStopIsStillAnArray(testCase)
            plan = evcharge.runChargingOptimization(UseLiveData=false, ...
                Scenario="helsinki-to-tampere", DestinationAddress="Tampere", ...
                InitialSoCPercent=50, VehicleID="kia-ev6-long-range-2wd");
            testCase.assumeEqual(height(plan.Stops), 1);
            json = jsonencode(evcharge.api.planToStruct(plan));
            testCase.verifySubstring(json, '"stops":[{');
        end

        function toolStartWritesProgress(testCase)
            call(struct("command", "ask", "text", "Take me to Oulu"));
            lines = readlines(testCase.ProgressFile, EmptyLineRule="skip");
            event = jsondecode(lines(1));
            testCase.verifyEqual(event.type, 'progress');
            testCase.verifyEqual(event.text, 'Checking the route to Oulu.');
        end

        function listsAreArrays(testCase)
            vehicles = call(struct("command", "listVehicles"));
            testCase.verifyGreaterThanOrEqual(numel(vehicles), 2);
            locations = call(struct("command", "listLocations"));
            testCase.verifyTrue(any(strcmp({locations.name}, 'Oulu')));
        end

        function badRequestsReturnErrors(testCase)
            r = call(struct("command", "fly"));
            testCase.verifySubstring(r.error, "Unknown command");
            r = call(struct("command", "setState", "location", "Atlantis"));
            testCase.verifySubstring(r.error, "Unknown location");
            r = call(struct("command", "startListening"));
            testCase.verifySubstring(r.error, "Speech is not available");
            r = jsondecode(evcharge.api.request("not json"));
            testCase.verifyTrue(isfield(r, "error"));
        end

        function noPlanBeforeAsking(testCase)
            p = call(struct("command", "getPlan"));
            testCase.verifyEmpty(p);
        end
    end
end

function result = call(req, varargin)
result = jsondecode(evcharge.api.request(jsonencode(req), varargin{:}));
end

function fcn = scriptedGenerator(responses)
count = 0;
fcn = @generate;
    function [text, message] = generate(~)
        count = count + 1;
        message = responses{min(count, numel(responses))};
        text = string(message.content);
    end
end

function message = toolCall(name, args)
call = struct("id", "call_1", "type", "function", ...
    "function", struct("name", name, "arguments", args));
message = struct("role", "assistant", "content", "", "tool_calls", call);
end

function message = textMessage(text)
message = struct("role", "assistant", "content", string(text));
end
