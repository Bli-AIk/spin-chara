local rules = {}

-- The rules of the show, as the player can recall them from the ACT menu.
--
-- The enemy only *hints* at these with green highlights inside its dialogue;
-- the lines below are the authoritative statements, written by hand.  Nothing
-- is parsed out of the dialogue, so the two can never disagree about wording,
-- only about emphasis.
--
-- One rule per round, in the order the enemy announces them, so the index is
-- the round number itself.  Rounds 6-10 are still the placeholder wave with
-- nothing to announce, which is why the list stops at five.
local announced = {
    "Battle.Rules.1",
    "Battle.Rules.2",
    "Battle.Rules.3",
    "Battle.Rules.4",
    "Battle.Rules.5",
}

-- The menu dialogue box is 596x130 with the text starting 14px in, leaving
-- 116px, and a line costs about 36-38px whichever locale is loaded (English is
-- determination_mono at 27px, Chinese is simsun at 13px drawn at double size to
-- match it).  Three lines fit and a fourth would draw past the box and over the
-- command buttons, so three rules to a screen.
local PER_SCREEN = 3

-- Builds the text array Battle.BattleDialogue wants: one screen per element,
-- which the typer advances one confirm press at a time.  The lead-in gets a
-- screen of its own -- sharing one with three rules would put a fourth line on
-- the box and overflow English.
function rules.Pages(round)
    -- Held in a local first: a table constructor collects every value the call
    -- returns, and localizeText is assert-based under test.
    local intro = Localize.localizeText("Battle.Rules.Intro")
    local texts = {intro}
    local lines = {}
    for r = 1, math.min(round or 0, #announced) do
        lines[#lines + 1] = Localize.localizeText(announced[r])
    end
    for i = 1, #lines, PER_SCREEN do
        local screen = {}
        for j = i, math.min(i + PER_SCREEN - 1, #lines) do
            screen[#screen + 1] = lines[j]
        end
        texts[#texts + 1] = table.concat(screen, "\n")
    end
    return texts
end

return rules
