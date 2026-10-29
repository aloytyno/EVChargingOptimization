function cfg = config()
%CONFIG Return settings for the speech-driven EV assistant.
%
%   CFG = EVCHARGE.ASSISTANT.CONFIG returns the local LLM, speech, and
%   tool-loop settings. Edit this file to switch Ollama models or the
%   Whisper model size.

cfg.Model = "qwen3:8b";
cfg.Endpoint = "127.0.0.1:11434";
cfg.TimeOutSeconds = 120;
cfg.Temperature = 0.2;
% How long Ollama keeps the model in memory after the last request. The
% Ollama default (5 minutes) means a slow reload after a short pause.
cfg.KeepAlive = "60m";
cfg.MaxToolRounds = 5;
cfg.HistoryTurnsToKeep = 6;

cfg.WhisperModelSize = "small";
% Audio Toolbox finds the model with what("whisper-<size>"), so this must
% be the folder that directly contains model.safetensors.
cfg.WhisperFolder = fullfile(getenv("USERPROFILE"), "MATLAB", "Whisper", ...
    "whisper-small", "whisper-small");
cfg.SampleRateHz = 16000;
cfg.MaxRecordingSeconds = 15;

cfg.UseLiveData = true;
end
