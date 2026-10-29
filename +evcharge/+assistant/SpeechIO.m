classdef SpeechIO < handle
    %SPEECHIO Push-to-talk speech recognition and local speech synthesis.
    %
    %   IO = EVCHARGE.ASSISTANT.SPEECHIO creates the audio front end. Call
    %   STARTLISTENING when the talk button is pressed and
    %   TEXT = STOPLISTENING when it is pressed again. SPEAK(IO, TEXT) reads a
    %   reply aloud without blocking. Replies are synthesized one sentence at
    %   a time and the first sentence starts playing as soon as it is ready.
    %
    %   Speech-to-text uses the Audio Toolbox Whisper model and
    %   text-to-speech uses HiFi-GAN. Both run locally.

    properties (SetAccess = private)
        SampleRateHz (1,1) double = 16000
        IsListening (1,1) logical = false
        RecognizerName (1,1) string = ""
    end

    properties (Access = private)
        Config struct
        Recorder = []
        Player = []
        Queue = {}
        Generation (1,1) double = 0
        Recognizer = []
        Synthesizer = []
    end

    methods
        function obj = SpeechIO(config)
            arguments
                config struct = evcharge.assistant.config()
            end
            obj.Config = config;
            obj.SampleRateHz = config.SampleRateHz;
        end

        function warmUp(obj)
            %WARMUP Load the speech models now instead of on first use.
            obj.recognizer();
            obj.synthesizer();
        end

        function startListening(obj)
            obj.stopSpeaking();
            obj.Recorder = audiorecorder(obj.SampleRateHz, 16, 1);
            record(obj.Recorder);
            obj.IsListening = true;
        end

        function text = stopListening(obj)
            text = "";
            if ~obj.IsListening
                return
            end
            stop(obj.Recorder);
            obj.IsListening = false;
            audio = getaudiodata(obj.Recorder);
            maxSamples = obj.Config.MaxRecordingSeconds * obj.SampleRateHz;
            audio = audio(1:min(end, maxSamples));
            text = obj.transcribe(audio, obj.SampleRateHz);
        end

        function text = transcribe(obj, audio, fs)
            %TRANSCRIBE Convert an audio vector to text.
            if numel(audio) < 0.3 * fs || max(abs(audio)) < 1e-3
                text = "";
                return
            end
            if fs ~= 16000
                audio = resample(audio, 16000, fs);
                fs = 16000;
            end
            audio = audio ./ max(abs(audio)) * 0.9;
            transcript = speech2text(audio, fs, Client=obj.recognizer());
            if istable(transcript)
                transcript = strjoin(string(transcript.Transcript), " ");
            end
            text = evcharge.assistant.correctPlaceNames( ...
                strtrim(string(transcript)));
        end

        function speak(obj, text, options)
            %SPEAK Read text aloud without blocking.
            %
            %   SPEAK(IO, TEXT, Interrupt=false) queues TEXT after whatever
            %   is already playing instead of cutting it off.
            arguments
                obj
                text (1,1) string
                options.Interrupt (1,1) logical = true
            end
            if options.Interrupt
                obj.stopSpeaking();
            end
            generation = obj.Generation;
            for sentence = splitSentences(speakable(text))
                [audio, fs] = text2speech(obj.synthesizer(), sentence);
                if generation ~= obj.Generation
                    return  % Interrupted while synthesizing.
                end
                obj.Queue{end+1} = {audio, fs};
                if ~obj.isPlaying()
                    obj.playNext();
                end
            end
        end

        function stopSpeaking(obj)
            obj.Generation = obj.Generation + 1;
            obj.Queue = {};
            if obj.isPlaying()
                stop(obj.Player);
            end
        end

        function tf = isSpeaking(obj)
            %ISSPEAKING True while audio is playing or queued.
            tf = obj.isPlaying() || ~isempty(obj.Queue);
        end

        function delete(obj)
            obj.stopSpeaking();
            if obj.IsListening
                stop(obj.Recorder);
            end
        end
    end

    methods (Access = private)
        function tf = isPlaying(obj)
            tf = ~isempty(obj.Player) && isplaying(obj.Player);
        end

        function playNext(obj)
            if isempty(obj.Queue)
                return
            end
            next = obj.Queue{1};
            obj.Queue(1) = [];
            player = audioplayer(next{1}, next{2});
            generation = obj.Generation;
            player.StopFcn = @(src, ~) obj.onPlayerStopped(src, generation);
            obj.Player = player;
            play(player);
        end

        function onPlayerStopped(obj, player, generation)
            % Ignore callbacks from interrupted or already-replaced players.
            % StopFcn can arrive late while MATLAB is busy synthesizing, by
            % which time speak() may have started the next sentence itself.
            if isvalid(obj) && generation == obj.Generation ...
                    && isequal(player, obj.Player)
                obj.playNext();
            end
        end

        function client = recognizer(obj)
            if isempty(obj.Recognizer)
                if isfolder(obj.Config.WhisperFolder)
                    addpath(obj.Config.WhisperFolder);
                end
                try
                    obj.Recognizer = speechClient("whisper", ...
                        ModelSize=obj.Config.WhisperModelSize, ...
                        Segmentation="none");
                catch ME
                    error("evcharge:assistant:NoWhisper", ...
                        "Whisper %s model not found. Unzip " ...
                        + "https://ssd.mathworks.com/supportfiles/audio/" ...
                        + "whisper-%s.zip into %s (%s)", ...
                        obj.Config.WhisperModelSize, ...
                        obj.Config.WhisperModelSize, ...
                        obj.Config.WhisperFolder, ME.message);
                end
                obj.RecognizerName = "Whisper " + obj.Config.WhisperModelSize;
            end
            client = obj.Recognizer;
        end

        function client = synthesizer(obj)
            if isempty(obj.Synthesizer)
                obj.Synthesizer = speechClient("hifigan");
            end
            client = obj.Synthesizer;
        end
    end
end

function sentences = splitSentences(text)
%SPLITSENTENCES Split text into sentences for incremental synthesis.
sentences = strtrim(regexp(text, "[^.!?]+[.!?]*", "match"));
sentences = sentences(strlength(sentences) > 0);
end

function text = speakable(text)
%SPEAKABLE Expand symbols that the speech model reads poorly.
text = replace(text, ["%", "°C", "kWh", "kW", "km/h", " km", "≈", "~"], ...
    [" percent", " degrees", " kilowatt hours", " kilowatts", ...
    " kilometres per hour", " kilometres", "about ", "about "]);
text = regexprep(text, "[*#`_]", "");
end
