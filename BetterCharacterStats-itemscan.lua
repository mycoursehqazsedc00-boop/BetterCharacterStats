--------------------------------------------------
-- BCSItemScan
--
-- A generic, any-tooltip item-stat text parser, ported into
-- BetterCharacterStats from BonusScanner v1.1 (by Crowley
-- <crowley@headshot.de>, performance improvements by Archarodim).
-- This exists so other addons (originally VanillaRatingBuster) that need
-- to parse an arbitrary item tooltip's text into a table of stat values
-- can depend on BetterCharacterStats instead of a separate BonusScanner
-- addon.
--
-- Only the stateless parsing engine is ported -- not BonusScanner's own
-- equipment-scan loop, slash commands, or Titan Panel integration, since
-- nothing in this addon (or VanillaRatingBuster) uses those. The parsing
-- logic itself (patterns, token matching, AddValue bookkeeping) is kept
-- as close to the original as possible, English patterns only.
--
-- Usage (see VanillaRatingBuster.lua for the real example):
--   BCSItemScan.temp.sets = {}
--   BCSItemScan.temp.set = ""
--   BCSItemScan.temp.slot = ""
--   BCSItemScan.temp.bonuses = {}
--   BCSItemScan.temp.details = {}
--   for each tooltip line:
--       BCSItemScan:ScanLine(line)
--   local bonuses = BCSItemScan.temp.bonuses  -- e.g. bonuses["AGI"] == 15
--------------------------------------------------

BCSITEMSCAN_PATTERN_SETNAME = "^(.*) %(%d/%d%)$";
BCSITEMSCAN_PATTERN_ARMOR_PREFIX = "^(%d+)%%?(.*)$";
BCSITEMSCAN_PATTERN_GENERIC_PREFIX = "^%+(%d+)%%?(.*)$";
BCSITEMSCAN_PATTERN_GENERIC_SUFFIX = "^(.*)%+(%d+)%%?$";

-- equip and set bonus prefixes:
BCSITEMSCAN_PREFIX_EQUIP = "Equip: ";
BCSITEMSCAN_PREFIX_SET = "Set: ";

-- passive bonus patterns. checked against lines which start with above prefixes
BCSITEMSCAN_PATTERNS_PASSIVE = {
	{ pattern = "+(%d+) ranged Attack Power%.", effect = "RANGEDATTACKPOWER" },
	{ pattern = "+(%d+) Attack Power in Cat, Bear, Dire Bear, and Moonkin forms only%.", effect = "FERALATTACKPOWER" },
	{ pattern = "Increases your attack and casting speed by (%d+)%%%.", effect = "HASTE" },
	{ pattern = "Increases your chance to block attacks with a shield by (%d+)%%%.", effect = "BLOCK" },
	{ pattern = "Increases your chance to dodge an attack by (%d+)%%%.", effect = "DODGE" },
	{ pattern = "Increases your chance to parry an attack by (%d+)%%%.", effect = "PARRY" },
	{ pattern = "Improves your chance to get a critical strike with spells by (%d+)%%%.", effect = "SPELLCRIT" },
	{ pattern = "Improves your chance to get a critical strike with Holy spells by (%d+)%%%.", effect = "HOLYCRIT" },
	{ pattern = "Increases the critical effect chance of your Holy spells by (%d+)%%%.", effect = "HOLYCRIT" },
	{ pattern = "Improves your chance to get a critical strike by (%d+)%%%.", effect = "CRIT" },
	{ pattern = "Improves your chance to get a critical strike with missile weapons by (%d+)%%%.", effect = "RANGEDCRIT" },
	{ pattern = "Increases damage done by Arcane spells and effects by up to (%d+)%.", effect = "ARCANEDMG" },
	{ pattern = "Increases damage done by Fire spells and effects by up to (%d+)%.", effect = "FIREDMG" },
	{ pattern = "Increases damage done by Frost spells and effects by up to (%d+)%.", effect = "FROSTDMG" },
	{ pattern = "Increases damage done by Holy spells and effects by up to (%d+)%.", effect = "HOLYDMG" },
	{ pattern = "Increases damage done by Nature spells and effects by up to (%d+)%.", effect = "NATUREDMG" },
	{ pattern = "Increases damage done by Shadow spells and effects by up to (%d+)%.", effect = "SHADOWDMG" },
	{ pattern = "Increases healing done by spells and effects by up to (%d+)%.", effect = "HEAL" },
	{ pattern = "Increases damage and healing done by magical spells and effects by up to (%d+)%.", effect = {"HEAL", "DMG"} },
	{ pattern = "Increases damage done to Undead by magical spells and effects by up to (%d+)", effect = "DMGUNDEAD" },
	{ pattern = "+(%d+) Attack Power when fighting Undead.", effect = "ATTACKPOWERUNDEAD" },
	{ pattern = "Restores (%d+) health per 5 sec%.", effect = "HEALTHREG" },
	{ pattern = "Restores (%d+) health every 5 sec%.", effect = "HEALTHREG" },
	{ pattern = "Restores (%d+) mana per 5 sec%.", effect = "MANAREG" },
	{ pattern = "Restores (%d+) mana every 5 sec%.", effect = "MANAREG" },
	{ pattern = "Improves your chance to hit by (%d+)%%%.", effect = "TOHIT" },
	{ pattern = "Improves your chance to hit with spells by (%d+)%%%.", effect = "SPELLTOHIT" },
	{ pattern = "Decreases the magical resistances of your spell targets by (%d+).", effect = "SPELLPEN" },
	{ pattern = "Your attacks ignore (%d+) of the target's armor.", effect = "ARMORPEN" }
};

-- generic patterns have the form "+xx bonus" or "bonus +xx" with an optional % sign after the value.

-- first the generic bonus string is looked up in the following table
BCSITEMSCAN_PATTERNS_GENERIC_LOOKUP = {
	["All Stats"] 			= {"STR", "AGI", "STA", "INT", "SPI"},
	["Strength"]			= "STR",
	["Agility"]				= "AGI",
	["Stamina"]				= "STA",
	["Intellect"]			= "INT",
	["Spirit"] 				= "SPI",

	["All Resistances"] 	= { "ARCANERES", "FIRERES", "FROSTRES", "NATURERES", "SHADOWRES"},

	["Fishing"]				= "FISHING",
	["Fishing Lure"]		= "FISHING",
	["Increased Fishing"]	= "FISHING",
	["Mining"]				= "MINING",
	["Herbalism"]			= "HERBALISM",
	["Skinning"]			= "SKINNING",
	["Defense"]				= "DEFENSE",
	["Increased Defense"]	= "DEFENSE",

	["Attack Power"] 		= "ATTACKPOWER",
	["Attack Power in Cat, Bear, Dire Bear, and Moonkin forms only"] 		= "FERALATTACKPOWER",
	["Dodge"] 				= "DODGE",
	["Block"]				= "BLOCK",
	["Hit"] 				= "TOHIT",
	["Spell Hit"]			= "SPELLTOHIT",
	["Blocking"]			= "BLOCK",
	["Ranged Attack Power"] = "RANGEDATTACKPOWER",
	["health every 5 sec"] = "HEALTHREG",
	["Healing Spells"] 		= "HEAL",
	["Increases Healing"] 	= "HEAL",
	["Healing and Spell Damage"] = {"HEAL", "DMG"},
	["Damage and Healing Spells"] = {"HEAL", "DMG"},
	["Spell Damage and Healing"] = {"HEAL", "DMG"},
	["mana every 5 sec"] 	= "MANAREG",
	["Mana Regen"] 			= "MANAREG",
	["Spell Damage"] 		= "DMG",
	["Critical"] 			= "CRIT",
	["Critical Hit"] 		= "CRIT",
	["Damage"] 				= "DMG",
	["Health"]				= "HEALTH",
	["HP"]					= "HEALTH",
	["Mana"]				= "MANA",
	["Armor"]				= "ARMOR",
	["Reinforced Armor"]	= "ARMOR",
};

-- next we try to match against one pattern of stage 1 and one pattern of stage 2 and concatenate the effect strings
BCSITEMSCAN_PATTERNS_GENERIC_STAGE1 = {
	{ pattern = "Arcane", 	effect = "ARCANE" },
	{ pattern = "Fire", 	effect = "FIRE" },
	{ pattern = "Frost", 	effect = "FROST" },
	{ pattern = "Holy", 	effect = "HOLY" },
	{ pattern = "Shadow",	effect = "SHADOW" },
	{ pattern = "Nature", 	effect = "NATURE" }
};

BCSITEMSCAN_PATTERNS_GENERIC_STAGE2 = {
	{ pattern = "Resist", 	effect = "RES" },
	{ pattern = "Damage", 	effect = "DMG" },
	{ pattern = "Effects", 	effect = "DMG" },
};

-- finally if we got no match, we match against some special enchantment patterns.
BCSITEMSCAN_PATTERNS_OTHER = {
	{ pattern = "Mana Regen (%d+) per 5 sec%.", effect = "MANAREG" },

	{ pattern = "Minor Wizard Oil", effect = {"DMG", "HEAL"}, value = 8 },
	{ pattern = "Lesser Wizard Oil", effect = {"DMG", "HEAL"}, value = 16 },
	{ pattern = "Wizard Oil", effect = {"DMG", "HEAL"}, value = 24 },
	{ pattern = "Brilliant Wizard Oil", effect = {"DMG", "HEAL", "SPELLCRIT"}, value = {36, 36, 1} },

	{ pattern = "Minor Mana Oil", effect = "MANAREG", value = 4 },
	{ pattern = "Lesser Mana Oil", effect = "MANAREG", value = 8 },
	{ pattern = "Brilliant Mana Oil", effect = { "MANAREG", "HEAL"}, value = {12, 25} },

	{ pattern = "Eternium Line", effect = "FISHING", value = 5 },
};

BCSItemScan = {
	ShowDebug = false;

	-- Running total of the player's OWN equipped gear, kept up to date by
	-- the event-driven scan at the bottom of this file. Some weight tables
	-- (VanillaRatingBuster's threshold-based ones) read this to decide
	-- whether the player is already past a soft cap on some stat.
	bonuses = {};
	bonuses_details = {};

	temp = {
		sets = {},
		set = "",
		slot = "",
		bonuses = {},
		details = {}
	};
};

-- Equipment slot names, in GetInventorySlotInfo's "<name>Slot" form.
BCSItemScan.slots = {
	"Head", "Neck", "Shoulder", "Shirt", "Chest", "Waist", "Legs", "Feet",
	"Wrist", "Hands", "Finger0", "Finger1", "Trinket0", "Trinket1", "Back",
	"MainHand", "SecondaryHand", "Ranged", "Tabard",
};

function BCSItemScan:Debug(Message)
	if (BCSItemScan.ShowDebug) then
		DEFAULT_CHAT_FRAME:AddMessage("BCSItemScan: " .. Message, 0.5, 0.8, 1);
	end
end

function BCSItemScan:AddValue(effect, value)
	local i, e;

	if (type(effect) == "string") then
		if (BCSItemScan.temp.bonuses[effect]) then
			BCSItemScan.temp.bonuses[effect] = BCSItemScan.temp.bonuses[effect] + value;
		else
			BCSItemScan.temp.bonuses[effect] = value;
		end

		if (BCSItemScan.temp.slot) then
			if (BCSItemScan.temp.details[effect]) then
				if (BCSItemScan.temp.details[effect][BCSItemScan.temp.slot]) then
					BCSItemScan.temp.details[effect][BCSItemScan.temp.slot] = BCSItemScan.temp.details[effect][BCSItemScan.temp.slot] + value;
				else
					BCSItemScan.temp.details[effect][BCSItemScan.temp.slot] = value;
				end
			else
				BCSItemScan.temp.details[effect] = {};
				BCSItemScan.temp.details[effect][BCSItemScan.temp.slot] = value;
			end
		end;
	else
		-- list of effects
		if (type(value) == "table") then
			for i, e in effect do
				BCSItemScan:AddValue(e, value[i]);
			end
		else
			for i, e in effect do
				BCSItemScan:AddValue(e, value);
			end
		end
	end
end;

function BCSItemScan:ScanLine(line)
	local tmpStr, found;
	-- Check for "Equip: "
	if (string.sub(line, 0, string.len(BCSITEMSCAN_PREFIX_EQUIP)) == BCSITEMSCAN_PREFIX_EQUIP) then
		tmpStr = string.sub(line, string.len(BCSITEMSCAN_PREFIX_EQUIP) + 1);
		BCSItemScan:CheckPassive(tmpStr);

	-- Check for "Set: "
	elseif (string.sub(line, 0, string.len(BCSITEMSCAN_PREFIX_SET)) == BCSITEMSCAN_PREFIX_SET
			and BCSItemScan.temp.set ~= ""
			and not BCSItemScan.temp.sets[BCSItemScan.temp.set]) then

		tmpStr = string.sub(line, string.len(BCSITEMSCAN_PREFIX_SET) + 1);
		BCSItemScan.temp.slot = "Set";
		BCSItemScan:CheckPassive(tmpStr);

	-- any other line (standard stats, enchantment, set name, etc.)
	else
		-- Check for set name
		_, _, tmpStr = string.find(line, BCSITEMSCAN_PATTERN_SETNAME);
		if (tmpStr) then
			BCSItemScan.temp.set = tmpStr;
		else
			found = BCSItemScan:CheckGeneric(line);
			if (not found) then
				BCSItemScan:CheckOther(line);
			end;
		end
	end
end;

-- Scans passive bonuses like "Set: " and "Equip: "
function BCSItemScan:CheckPassive(line)
	local i, p, value, found;

	found = nil;
	for i, p in BCSITEMSCAN_PATTERNS_PASSIVE do
		_, _, value = string.find(line, "^" .. p.pattern);
		if (value) then
			BCSItemScan:AddValue(p.effect, value)
			found = 1;
			break; -- prevent duplicated patterns to cause bonuses to be counted several times
		end
	end

	if (not found) then
		BCSItemScan:Debug("\"" .. line .. "\"");
		BCSItemScan:CheckGeneric(line);
	end
end

-- Scans generic bonuses like "+3 Intellect" or "Arcane Resistance +4"
function BCSItemScan:CheckGeneric(line)
	local value, token, pos, tmpStr, found, is_ranged;

	-- split line at "/" for enchants with multiple effects
	found = false;
	while (string.len(line) > 0) do
		pos = string.find(line, "/", 1, true);
		if (pos) then
			tmpStr = string.sub(line, 1, pos - 1);
			line = string.sub(line, pos + 1);
		else
			tmpStr = line;
			line = "";
		end

		-- trim line
		tmpStr = string.gsub(tmpStr, "^%s+", "");
		tmpStr = string.gsub(tmpStr, "%s+$", "");
		tmpStr = string.gsub(tmpStr, "%.$", "");
		-- Check for ranged items like wands that deal a specific school of damage
		tmpStr = string.gsub(tmpStr, "%d+%s%-%s%d+%s", "");

		_, _, value, token = string.find(tmpStr, BCSITEMSCAN_PATTERN_GENERIC_PREFIX);
		if (not value) then
			_, _, value, token = string.find(tmpStr, BCSITEMSCAN_PATTERN_ARMOR_PREFIX);
		end
		if (not value) then
			_, _, token, value = string.find(tmpStr, BCSITEMSCAN_PATTERN_GENERIC_SUFFIX);
		end
		if (token and value) then
			-- trim token
			token = string.gsub(token, "^%s+", "");
			token = string.gsub(token, "%s+$", "");
			token = string.gsub(token, "%.$", "");

			if (BCSItemScan:CheckToken(token, value)) then
				found = true;
			end
		end
	end
	return found;
end

-- Identifies simple tokens like "Intellect" and composite tokens like "Fire damage" and
-- add the value to the respective bonus.
-- returns true if some bonus is found
function BCSItemScan:CheckToken(token, value)
	local i, p, s1, s2;

	if (BCSITEMSCAN_PATTERNS_GENERIC_LOOKUP[token]) then
		BCSItemScan:AddValue(BCSITEMSCAN_PATTERNS_GENERIC_LOOKUP[token], value);
		return true;
	else
		s1 = nil;
		s2 = nil;
		for i, p in BCSITEMSCAN_PATTERNS_GENERIC_STAGE1 do
			if (string.find(token, p.pattern, 1, 1)) then
				s1 = p.effect;
			end
		end
		for i, p in BCSITEMSCAN_PATTERNS_GENERIC_STAGE2 do
			if (string.find(token, p.pattern, 1, 1)) then
				s2 = p.effect;
			end
		end
		if (s1 and s2) then
			BCSItemScan:AddValue(s1 .. s2, value);
			return true;
		end
	end
	return false;
end

-- Last fallback for non generic enchants, like "Mana Regen x per 5 sec."
function BCSItemScan:CheckOther(line)
	local i, p, value, start, found;
	local a, b;

	for i, p in BCSITEMSCAN_PATTERNS_OTHER do
		start, _, value = string.find(line, "^" .. p.pattern);
		if (start) then
			if (p.value) then
				BCSItemScan:AddValue(p.effect, p.value)
			elseif (value) then
				BCSItemScan:AddValue(p.effect, value)
			end
			return true;
		end
	end

	return false;
end

--------------------------------------------------
-- Equipment total scan (BCSItemScan.bonuses)
--
-- Ported from BonusScanner:ScanEquipment/ScanTooltip. Uses its own hidden
-- tooltip, kept separate from BetterCharacterStats' own BCS_Tooltip (used
-- by ScanAllGear in helper.lua) so the two scans can never clobber each
-- other's in-progress tooltip state if they happen to run back to back.
--------------------------------------------------

local scanTooltip = CreateFrame("GameTooltip", "BCSItemScanTooltip", nil, "GameTooltipTemplate")
scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

local function ScanTooltipLines()
	local lines = scanTooltip:NumLines()

	for i = 2, lines do
		local tmpText = getglobal("BCSItemScanTooltipTextLeft" .. i)

		if tmpText and tmpText:GetText() then
			BCSItemScan:ScanLine(tmpText:GetText())
		end
	end
end

function BCSItemScan:ScanEquipment()
	BCSItemScan:Debug("Scanning equipment")

	BCSItemScan.temp.bonuses = {}
	BCSItemScan.temp.details = {}
	BCSItemScan.temp.sets = {}
	BCSItemScan.temp.set = ""

	for i, slotname in BCSItemScan.slots do
		local slotid = GetInventorySlotInfo(slotname .. "Slot")
		local okHas, hasItem = pcall(scanTooltip.SetInventoryItem, scanTooltip, "player", slotid)

		if okHas and hasItem then
			BCSItemScan.temp.slot = slotname
			ScanTooltipLines()

			if BCSItemScan.temp.set ~= "" then
				BCSItemScan.temp.sets[BCSItemScan.temp.set] = 1
			end
		end
	end

	BCSItemScan.bonuses = BCSItemScan.temp.bonuses
	BCSItemScan.bonuses_details = BCSItemScan.temp.details
end

-- Scans an arbitrary item link (not necessarily equipped), e.g. for
-- comparing an item still in a vendor or mail window. Does not touch
-- BCSItemScan.bonuses -- only returns this one item's own stats.
function BCSItemScan:ScanItem(itemlink)
	local okName, name = pcall(GetItemInfo, itemlink)

	if not okName or not name then
		return false
	end

	BCSItemScan.temp.bonuses = {}
	BCSItemScan.temp.sets = {}
	BCSItemScan.temp.set = ""
	BCSItemScan.temp.slot = ""

	scanTooltip:SetHyperlink(itemlink)
	ScanTooltipLines()

	return BCSItemScan.temp.bonuses
end

-- Event-driven refresh of BCSItemScan.bonuses, mirroring the debounce
-- pattern BetterCharacterStats itself already uses for UNIT_INVENTORY_CHANGED
-- (see BetterCharacterStats.lua's OnEvent). An initial scan runs once on
-- PLAYER_LOGIN so BCSItemScan.bonuses is populated before anyone can hover
-- a tooltip.
local scanEventFrame = CreateFrame("Frame")
local scanDebouncePending = false
local scanDebounceTimer = 0

scanEventFrame:RegisterEvent("PLAYER_LOGIN")
scanEventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
scanEventFrame:SetScript("OnEvent", function()
	if event == "PLAYER_LOGIN" then
		BCSItemScan:ScanEquipment()
	elseif event == "UNIT_INVENTORY_CHANGED" and arg1 == "player" then
		scanDebouncePending = true
		scanDebounceTimer = 0
	end
end)

scanEventFrame:SetScript("OnUpdate", function()
	if not scanDebouncePending then
		return
	end

	scanDebounceTimer = scanDebounceTimer + arg1

	if scanDebounceTimer >= 0.2 then
		scanDebouncePending = false
		BCSItemScan:ScanEquipment()
	end
end)
