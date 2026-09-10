-- Default loot-priority tables: the spec-priority list (defaultLootPriorityText) and the
-- named-player list (defaultNamedItemsText). Kept out of Core so the data lives on its own. Loaded
-- right after Core (which creates the WeirdLoot table); consumed at login by the config init, which
-- re-seeds a character's saved prio whenever these defaults change (see the stamp logic in Core).
local addon = WeirdLoot

addon.defaultLootPriorityText = [=[
Gauntlets of the Lost Conqueror, warlock demonology / warlock affliction / priest holy / priest discipline / priest shadow / paladin holy / paladin protection > paladin retribution
Gauntlets of the Lost Protector, shaman enhancement / hunter survival / hunter marksmanship > warrior fury / warrior arms / shaman restoration
Gauntlets of the Lost Vanquisher, rogue assassination / mage arcane / mage fire / death knight frost / death knight blood / druid balance / druid restoration > rogue combat / death knight unholy / druid balance
Shadow of the Ghoul, paladin protection / warrior protection
Haunting Call, shaman elemental
Silent Crusader, death knight frost
Inevitable Defeat, death knight blood
Lost Jewel, warlock affliction / warlock demonology / druid balance / mage fire > priest shadow
Sand-Worn Band, death knight blood / paladin protection > warrior protection
Fool's Trial, death knight frost / druid feral / hunter survival / hunter marksmanship / paladin retribution / shaman enhancement / warrior arms / warrior fury > rogue combat / rogue subtlety / rogue assassination / death knight unholy
Heritage, death knight blood
Thunderstorm Amulet, warlock affliction / warlock demonology 
Aged Winter Cloak, druid feral / hunter survival / hunter marksmanship / death knight frost / death knight unholy / warrior fury / warrior arms
Shroud of Luminosity, shaman elemental / shaman restoration / paladin holy
Crown of the Lost Conqueror, warlock affliction / warlock demonology / paladin protection > priest shadow / priest holy / priest discipline / paladin retribution / paladin holy
Mantle of the Lost Conqueror, paladin protection / paladin retribution / paladin holy / priest discipline / priest holy / priest shadow / warlock affliction / warlock demonology
Breastplate of the Lost Conqueror, warlock affliction / warlock demonology / paladin protection / paladin retribution / paladin holy > priest discipline / priest holy / priest shadow
Legplates of the Lost Conqueror, paladin holy > paladin retribution
Crown of the Lost Protector, shaman elemental / shaman restoration / warrior fury / warrior arms > shaman enhancement / hunter survival / hunter marksmanship
Mantle of the Lost Protector, hunter survival / hunter marksmanship / shaman restoration / shaman enhancement / warrior fury / warrior arms > shaman elemental
Breastplate of the Lost Protector, shaman enhancement / shaman restoration / shaman elemental
Legplates of the Lost Protector, shaman restoration / shaman enhancement / warrior fury / warrior arms
Crown of the Lost Vanquisher, rogue combat / rogue assassination / rogue subtlety / death knight blood / mage fire / mage arcane / druid balance / druid feral
Mantle of the Lost Vanquisher, rogue combat / rogue assassination / rogue subtlety / death knight frost / death knight blood / death knight unholy / mage fire / mage arcane / druid balance / druid restoration / druid feral
Breastplate of the Lost Vanquisher, druid balance / mage fire / mage arcane / death knight frost / death knight blood / death knight unholy
Legplates of the Lost Vanquisher, mage arcane / rogue assassination / death knight frost / death knight blood > druid balance / death knight unholy
Mantle of the Locusts, druid restoration
Sash of the Parlor, priest discipline
Leggings of Atrophy, shaman elemental
Dawnwalkers, rogue combat / rogue assassination / rogue subtlety
Arachnoid Gold Band, shaman enhancement
Pauldrons of Unnatural Death, warrior protection
Inexorable Sabatons, paladin protection / warrior protection
Sabatons of Sudden Reprisal, death knight unholy > death knight frost
Webbed Death, rogue combat / rogue assassination / rogue subtlety
Gemmed Wand of the Nerubians, mage fire / priest shadow / warlock affliction > mage arcane > warlock demonology
Punctilious Bindings, priest shadow
Gloves of Token Respect, priest discipline
Seized Beauty, priest discipline > paladin holy
Sinner's Bindings, druid feral / rogue combat / rogue assassination / rogue subtlety / warrior fury / warrior arms
Torn Web Wrapping, hunter survival / hunter marksmanship / shaman enhancement
Bindings of the Hapless Prey, paladin protection / warrior protection
Ablative Chitin Girdle, warrior protection / paladin protection / death knight blood
Matriarch's Spawn, druid restoration / warlock affliction > mage arcane / priest discipline > warlock demonology
Wraith Strike, shaman enhancement > shaman restoration
Sash of Solitude, priest discipline
Belt of the Tortured, rogue assassination > paladin retribution / druid feral / shaman enhancement
Fleshless Girdle, warrior protection
Surplus Limb, priest shadow / warlock demonology / mage fire / mage arcane > warlock affliction
Split Greathammer, warrior protection
Arrowsong, hunter survival / hunter marksmanship
Cowl of Vanity, priest shadow
Mantle of the Corrupted, shaman elemental > druid balance
Slime Stream Bands, shaman enhancement / hunter survival / hunter marksmanship
Depraved Linked Belt, hunter survival / hunter marksmanship
Girdle of Chivalry, paladin retribution / death knight frost / death knight unholy
Plague Igniter, priest discipline
Urn of Lost Memories, priest discipline
Cincture of Polarity, mage fire / druid balance / shaman elemental
Faceguard of the Succumbed, paladin holy
Sabatons of Endurance, paladin protection / warrior protection
Spire of Sunset, priest discipline
Thrusting Bands, paladin retribution > druid feral
Gauntlets of the Disobedient, warrior protection
Accursed Spine, druid balance
Spinning Fate, warrior fury / warrior arms / rogue combat / rogue assassination / rogue subtlety
Heigan's Putrid Vestments, shaman elemental / priest shadow
Serene Echoes, priest discipline
Stalk-Skin Belt, druid feral / rogue combat / rogue assassination / rogue subtlety / warrior fury / warrior arms
Eruption-Scarred Boots, shaman restoration > shaman elemental
Breastplate of Tormented Rage, warrior protection
Boots of Impetuous Ideals, warlock affliction / warlock demonology / mage fire
Footwraps of Vile Deceit, druid feral
Fading Glow, priest discipline
Bindings of the Expansive Mind, druid balance
Shoulderpads of Secret Arts, hunter survival / hunter marksmanship
Bands of Mutual Respect, shaman restoration / shaman elemental
Girdle of Recuperation, shaman restoration
Bracers of the Unholy Knight, death knight blood > paladin protection / warrior protection
Girdle of Razuvious, death knight frost / death knight unholy
Legplates of Double Strikes, warrior fury / warrior arms
Leggings of Failed Escape, hunter survival / hunter marksmanship
Helm of Vital Protection, warrior protection / paladin protection / death knight blood
Abetment Bracers, paladin holy
Zeliek's Gauntlets, death knight unholy
Broken Promise, paladin protection
Gloves of Grandeur, druid balance
Legguards of the Boneyard, druid restoration
Boots of the Great Construct, shaman enhancement
Cosmic Lights, shaman restoration / priest holy / priest discipline / paladin holy
Icy Blast Amulet, rogue combat / rogue assassination / rogue subtlety
Gatekeeper, warrior protection > death knight blood
Ring of Decaying Beauty, shaman restoration / priest holy / priest discipline / paladin holy / druid restoration
Soul of the Dead, paladin holy
Cape of the Unworthy Wizard, warlock affliction / warlock demonology / druid balance / priest shadow
Leggings of Mortal Arrogance, priest discipline > warlock affliction / warlock demonology  
Boundless Ambition, death knight blood / warrior protection > paladin protection
Calamity's Grasp, rogue combat > shaman enhancement
Sinister Revenge, rogue assassination
Last Laugh, death knight unholy > warrior protection / paladin protection / death knight blood
Journey's End, druid feral > hunter survival / hunter marksmanship
Wall of Terror, paladin protection / warrior protection
Envoy of Mortality, hunter survival / hunter marksmanship
Gem of Imprisoned Vassals, death knight unholy
Kel'Thuzad's Reach, rogue combat
Hammer of the Astral Plane, priest shadow / paladin holy
Wand of the Archlich, mage arcane / warlock demonology > warlock affliction / mage fire
Wyrmrest Band, shaman restoration / paladin holy
Chestguard of Flagrant Prowess, hunter survival / hunter marksmanship
Greatring of Collision, warrior fury / warrior arms / death knight frost > death knight unholy
Dragon Brood Legguards, paladin protection
Sanctum's Flowing Vestments, mage arcane / priest shadow / druid restoration > priest discipline
Leggings of the Honored, rogue combat / rogue assassination / rogue subtlety / druid feral / paladin retribution
Gown of the Spell-Weaver, druid balance
Footsteps of Malygos, druid balance / shaman elemental > shaman restoration
Surge Needle Ring, hunter survival / hunter marksmanship / druid feral / shaman enhancement / rogue combat / rogue assassination / rogue subtlety > warrior fury / warrior arms / death knight frost
Hailstorm, death knight unholy
Greatstaff of the Nexus, druid balance
Barricade of Eternity, warrior protection
Hood of Rationality, priest shadow / priest holy / priest discipline
Mantle of Dissemination, priest shadow / priest holy / priest discipline
Blanketing Robes of Snow, priest discipline
Leggings of the Wanton Spellcaster, druid balance / mage fire / priest shadow / shaman elemental / warlock affliction / warlock demonology 
Arcanic Tramplers, warlock affliction / warlock demonology / mage fire / mage arcane / priest shadow > druid restoration
Blue Aspect Helm, hunter survival / hunter marksmanship / shaman enhancement
Chestguard of the Recluse, druid feral / rogue combat / rogue assassination / rogue subtlety / warrior fury / warrior arms
Winter Spectacle Gloves, shaman restoration
Boots of the Renewed Flight, hunter survival / hunter marksmanship > shaman enhancement
Legplates of Sovereignty, paladin protection / warrior protection
Boots of Healing Energies, paladin holy
Melancholy Sabatons, paladin retribution / death knight frost / warrior fury / warrior arms > death knight unholy
Mark of Norgannon, rogue combat / rogue assassination / rogue subtlety / paladin retribution
]=]

-- Generated by tools/sheet_named_items.py from the loot sheet (gid 1419766178); rerun it rather
-- than editing these lines. Lines may carry class/spec tokens as well as player names:
-- the addon routes each token to the right rule set at parse time.
addon.defaultNamedItemsText = table.concat({
    "Crown of the Wayward Conqueror, paladin / priest / warlock",
    "Mantle of the Wayward Conqueror, paladin / priest / warlock",
    "Breastplate of the Wayward Conqueror, paladin / priest / warlock",
    "Gauntlets of the Wayward Conqueror, paladin / priest / warlock",
    "Legplates of the Wayward Conqueror, paladin / priest / warlock",
    "Crown of the Wayward Protector, warrior / hunter / shaman",
    "Mantle of the Wayward Protector, warrior / hunter / shaman",
    "Breastplate of the Wayward Protector, warrior / hunter / shaman",
    "Gauntlets of the Wayward Protector, warrior / hunter / shaman",
    "Legplates of the Wayward Protector, warrior / hunter / shaman",
    "Crown of the Wayward Vanquisher, rogue / death knight / mage / druid",
    "Mantle of the Wayward Vanquisher, rogue / death knight / mage / druid",
    "Breastplate of the Wayward Vanquisher, rogue / death knight / mage / druid",
    "Gauntlets of the Wayward Vanquisher, rogue / death knight / mage / druid",
    "Legplates of the Wayward Vanquisher, rogue / death knight / mage / druid",
    "Boots of Fiery Resolution, Lexissa / Aldeberron > Bisket / Volckerr",
    "Plated Leggings of Ruination, death knight frost / death knight unholy / paladin retribution",
    "Pendant of Fiery Havoc, Friendhelper / Scarletrage > Volckerr / Helvi > LC",
    "Golden Saronite Dragon, rogue combat / shaman enhancement",
    "Living Flame, Cutiedot > Lexissa",
    "Grasps of Reason, Bisket / Volckerr > Aldeberron / Aest / Helvi > LC",
    "Gloves of the Steady Hand, hunter survival / hunter marksmanship",
    "Breastplate of the Devoted, paladin holy",
    "Charm of Meticulous Timing, Shapiffany > Naturalfocus / Stickboard",
    "Drape of Mortal Downfall, Uzragol > Friendhelper",
    "Shoulderpads of the Intruder, druid feral / rogue combat / rogue assassination / paladin retribution",
    "Greaves of Swift Vengeance, hunter survival / hunter marksmanship",
    "Belt of Colossal Rage, death knight unholy / death knight frost",
    "Sapphire Amulet of Renewal, mage arcane / druid restoration",
    "Drape of Icy Intent, rogue combat / rogue assassination / shaman enhancement",
    "Bindings of Winter Gale, Uzragol / Stickboard > Naturalfocus / Curatewf",
    "Frigid Strength of Hodir, death knight frost / death knight unholy",
    "Constellus, Fellera / Shapiffany > Uzragol / Stickboard > LC",
    "Sif's Promise, death knight unholy",
    "Scale of Fates, Aldeberron / Helvi > Scarletrage / Friendhelper > LC",
    "Embrace of the Gladiator, Owlation > Thalamier",
    "Warhelm of the Champion, death knight unholy / paladin retribution",
    "Skyforge Crossbow, Owlation > Notdewbie",
    "Wisdom's Hold, Shapiffany > Uzragol / Stickboard",
    "Gauntlets of Ruthless Reprisal, death knight unholy",
    "Drape of the Sullen Goddess, priest discipline / paladin holy",
    "Leggings of the Enslaved Idol, mage arcane",
    "Bladetwister, Rigul > Notdewbie > rogue",
    "Dreambinder, Thalamier > Owlation",
    "Crown of Luminescence, Volckerr > Bisket",
    "Armbands of Bedlam, death knight frost / death knight unholy / paladin retribution",
    "Conductive Seal, Uzragol / Friendhelper > Cutiedot / Lexissa / Bisket > LC",
    "Starshard Edge, Aest / Helvi > Friendhelper / Lexissa > LC",
    "Pharos Gloves, Lexissa / Bisket > Aldeberron / Uzragol / Aest > LC",
    "Starwatcher's Binding, Volckerr / Cutiedot > Scarletrage / Fellera / Aldeberron > LC",
    "Solar Bindings, warrior fury / rogue assassination",
    "Star-beaded Clutch, shaman restoration / druid restoration / paladin holy",
    "Boundless Gaze, shaman enhancement / hunter survival / hunter marksmanship",
    "Sabatons of Lifeless Night, death knight unholy / death knight frost / paladin retribution",
    "Cosmos, Scarletrage / Aldeberron > Volckerr / Cutiedot > LC",
    "Comet's Trail, Timthedk > Rigul > LC",
    "Reply-Code Alpha, Zenkahi / Runereaver > Lueburry / Bisket / Owlation > LC",
    "Handwraps of the Vigilant, priest discipline",
    "Pendulum of Infinity, Lueburry / Rigul > Notdewbie / Curatewf > LC",
    "Flare of the Heavens, Uzragol / Lexissa > Friendhelper / Scarletrage / Aest > LC",
    "Voldrethar, Dark Blade of Oblivion, Styrza > warrior fury / paladin retribution",
    "Blood of the Old God, Lehran",
    "Treads of the False Oracle, Aest / Shapiffany > Barnyard / Naturalfocus",
    "Legguards of Cunning Deception, Lueburry / Notdewbie > Styrza / Rigul > LC",
    "Seal of the Betrayed King, Timthedk > Styrza",
    "Show of Faith, Naturalfocus > Barnyard",
    "Dark Edge of Depravity, death knight blood",
    "Mantle of Fiery Vengeance, hunter survival / hunter marksmanship",
    "Twirling Blades, warrior fury / rogue combat",
    "Igniter Rod, priest discipline",
    "Fluxing Energy Coils, Thalamier > Owlation",
    "Breastplate of the Stoneshaper, shaman restoration",
    "Seal of Ulduar, death knight blood",
    "Loop of the Agile, shaman enhancement",
    "Pendant of the Shallow Grave, shaman elemental",
    "Mjolnir Runestone, Thalamier > Styrza > LC",
    "Sif's Remembrance, shaman restoration",
    "Fire Orchid Signet, paladin holy / druid restoration",
    "Petrified Ivy Sprig, Cutiedot / Aest > Bisket / Lexissa > LC",
    "Mimiron's Flight Goggles, rogue combat",
    "Tempered Mercury Greaves, shaman enhancement",
    "Starlight Treads, priest discipline",
    "Gloves of the Endless Dark, rogue combat",
    "Band of Lights, Runereaver > Zenkahi",
    "Nebula Band, Aest / Bisket > Uzragol / Naturalfocus / Barnyard",
    "Dark Matter, Rigul > Notdewbie > Curatewf",
    "Meteorite Crystal, Stickboard > Shapiffany",
    "46052, Owlation",
    "Drape of the Faceless General, Styrza / Zenkahi > Lueburry / Runereaver > LC",
    "Aesuga, Hand of the Ardent Champion, shaman enhancement",
    "Royal Seal of King Llane, death knight blood",
    "Amice of Inconceivable Horror, Lexissa > Cutiedot",
    "Soul-Devouring Cinch, Thalamier / Styrza > Owlation / Rigul > LC",
    "Signet of Soft Lament, priest discipline",
    "Caress of Insanity, Runereaver > Zenkahi",
}, "\n")
