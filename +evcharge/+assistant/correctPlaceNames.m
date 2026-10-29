function text = correctPlaceNames(text)
%CORRECTPLACENAMES Fix Finnish place names misheard by speech recognition.
%
%   TEXT = EVCHARGE.ASSISTANT.CORRECTPLACENAMES(TEXT) replaces capitalized
%   words that are one edit away from a known Finnish town (two edits for
%   long names), e.g. "Aulu" -> "Oulu", "Jyvaskula" -> "Jyvaskyla".

arguments
    text (1,1) string
end

places = ["Helsinki", "Espoo", "Vantaa", "Tampere", "Turku", "Oulu", ...
    "Jyvaskyla", "Lahti", "Kuopio", "Pori", "Joensuu", "Lappeenranta", ...
    "Hameenlinna", "Vaasa", "Seinajoki", "Rovaniemi", "Mikkeli", "Kotka", ...
    "Porvoo", "Kokkola", "Kajaani", "Savonlinna", "Rauma", "Kemi", ...
    "Levi", "Ivalo", "Inari", "Hanko", "Naantali", "Heinola", "Lohja", ...
    "Hyvinkaa", "Kouvola", "Iisalmi", "Raahe", "Tornio", "Kuusamo"];
plainPlaces = lower(stripAccents(places));

[words, separators] = split(text, delimiterPattern());
for k = 1:numel(words)
    word = words(k);
    if strlength(word) < 4 || ~isstrprop(extractBefore(word, 2), "upper")
        continue
    end
    plainWord = lower(stripAccents(word));
    if any(plainWord == plainPlaces)
        continue
    end
    distances = editDistance(plainWord, plainPlaces);
    allowed = 1 + (strlength(plainPlaces) >= 8);
    candidates = find(distances <= allowed);
    if isscalar(candidates)
        words(k) = places(candidates);
    end
end
text = join(words, separators);
end

function pattern = delimiterPattern()
pattern = characterListPattern(" ,.?!;:");
end

function text = stripAccents(text)
text = replace(text, ["ä", "ö", "å", "Ä", "Ö", "Å"], ...
    ["a", "o", "a", "A", "O", "A"]);
end
