classdef tAssistantLoop < matlab.unittest.TestCase
    %TASSISTANTLOOP Tool-calling loop tests with a scripted fake LLM.

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture( ...
                matlab.unittest.fixtures.PathFixture(root));
        end
    end

    methods (Test)
        function toolCallThenAnswer(testCase)
            responses = {toolCallMessage("plan_trip", ...
                struct("destination", "Oulu")), textMessage( ...
                "**You can make it** with three stops.")};
            [assistant, calls] = makeAssistant(responses);

            reply = assistant.ask("Take me to Oulu");

            testCase.verifyEqual(reply.Text, "You can make it with three stops.");
            testCase.verifyEqual(reply.ToolsCalled, "plan_trip");
            testCase.verifyNotEmpty(reply.Plan);
            testCase.verifyEqual(calls("n"), 2);

            % History: user, assistant tool call, tool result, final answer.
            messages = assistant.History.Messages;
            testCase.verifyNumElements(messages, 4);
            testCase.verifyEqual(messages{3}.role, "tool");
            toolResult = jsondecode(messages{3}.content);
            testCase.verifyTrue(toolResult.can_reach_destination);
            testCase.verifySubstring(messages{1}.content, "battery 72%");
        end

        function toolStartFcnRunsBeforeTool(testCase)
            responses = {toolCallMessage("plan_trip", ...
                struct("destination", "Oulu, Finland")), textMessage("Ok.")};
            assistant = makeAssistant(responses);
            seen = containers.Map();
                function onStart(name, args)
                    seen(char(name)) = args;
                    % The hook runs before the tool, so no plan exists yet.
                    testCase.verifyEmpty(assistant.State.ActivePlan);
                end
            assistant.ToolStartFcn = @onStart;
            assistant.ask("Take me to Oulu");
            testCase.verifyTrue(isKey(seen, "plan_trip"));
            testCase.verifyEqual( ...
                evcharge.assistant.Assistant.progressMessage("plan_trip", ...
                seen("plan_trip")), "Checking the route to Oulu.");
            testCase.verifyEqual( ...
                evcharge.assistant.Assistant.progressMessage( ...
                "get_vehicle_state", struct()), "");
        end

        function failingToolStartFcnIsIgnored(testCase)
            responses = {toolCallMessage("set_charge_limit", ...
                struct("percent", 90)), textMessage("Done.")};
            assistant = makeAssistant(responses);
            assistant.ToolStartFcn = @(~, ~) error("test:boom", "boom");
            reply = assistant.ask("Charge to 90");
            testCase.verifyEqual(reply.Text, "Done.");
            testCase.verifyEqual(assistant.State.ChargeLimitPercent, 90);
        end

        function argumentsAsJsonText(testCase)
            responses = {toolCallMessage("set_charge_limit", ...
                '{"percent": 90}'), textMessage("Done.")};
            assistant = makeAssistant(responses);
            assistant.ask("Charge to 90 tonight");
            testCase.verifyEqual(assistant.State.ChargeLimitPercent, 90);
        end

        function thinkingTagsAreRemoved(testCase)
            assistant = makeAssistant({textMessage( ...
                "<think>plan it</think>" + newline + "Sure thing.")});
            reply = assistant.ask("Hello");
            testCase.verifyEqual(reply.Text, "Sure thing.");
        end

        function endlessToolCallsStop(testCase)
            call = toolCallMessage("get_vehicle_state", struct());
            assistant = makeAssistant(repmat({call}, 1, 10));
            reply = assistant.ask("Hello");
            testCase.verifyNumElements(reply.ToolsCalled, ...
                assistant.Config.MaxToolRounds);
            testCase.verifySubstring(reply.Text, "Sorry");
        end

        function generatorErrorGivesFriendlyReply(testCase)
            cfg = offlineConfig();
            assistant = evcharge.assistant.Assistant(Config=cfg, ...
                GenerateFcn=@failingGenerate);
            reply = assistant.ask("Hello");
            testCase.verifySubstring(reply.Text, "Ollama");
            testCase.verifyEqual(reply.Error, "connection refused");
            testCase.verifyEmpty(assistant.History.Messages);
        end
    end
end

function [assistant, calls] = makeAssistant(responses)
calls = containers.Map("KeyType", "char", "ValueType", "double");
calls("n") = 0;
    function [text, message] = fakeGenerate(~)
        calls("n") = calls("n") + 1;
        message = responses{calls("n")};
        text = string(message.content);
    end
assistant = evcharge.assistant.Assistant(Config=offlineConfig(), ...
    GenerateFcn=@fakeGenerate);
end

function [text, message] = failingGenerate(~) %#ok<STOUT>
error("test:down", "connection refused");
end

function cfg = offlineConfig()
cfg = evcharge.assistant.config();
cfg.UseLiveData = false;
end

function message = toolCallMessage(name, args)
call = struct("id", "call_1", "type", "function", ...
    "function", struct("name", name, "arguments", args));
message = struct("role", "assistant", "content", "", "tool_calls", call);
end

function message = textMessage(text)
message = struct("role", "assistant", "content", string(text));
end
