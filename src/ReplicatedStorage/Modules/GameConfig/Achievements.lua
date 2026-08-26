local Achievements = {
	-- Kills
	{ key = "Kills_100", name = "First Blood", desc = "Defeat 100 creatures", counter = "Kills", goal = 100, reward = { dna = 1000 } },
	{ key = "Kills_1000", name = "Monster Hunter", desc = "Defeat 1,000 creatures", counter = "Kills", goal = 1000, reward = { diamonds = 50 } },
	{ key = "Kills_10000", name = "Exterminator", desc = "Defeat 10,000 creatures", counter = "Kills", goal = 10000, reward = { title = "Slayer" } },
	{ key = "Kills_50000", name = "Apex Predator", desc = "Defeat 50,000 creatures", counter = "Kills", goal = 50000, reward = { title = "Apex" } },
	{ key = "Kills_100000", name = "Extinction Event", desc = "Defeat 100,000 creatures", counter = "Kills", goal = 100000, reward = { title = "Destroyer" } },

	-- Rebirths
	{ key = "Rebirths_1", name = "Born Again", desc = "Rebirth for the first time", counter = "Rebirths", goal = 1, reward = { diamonds = 100 } },
	{ key = "Rebirths_5", name = "Veteran", desc = "Rebirth 5 times", counter = "Rebirths", goal = 5, reward = { title = "Veteran" } },
	{ key = "Rebirths_10", name = "Immortal", desc = "Rebirth 10 times", counter = "Rebirths", goal = 10, reward = { title = "Immortal" } },
	{ key = "Rebirths_25", name = "Eternal", desc = "Rebirth 25 times", counter = "Rebirths", goal = 25, reward = { title = "Eternal" } },
	{ key = "Rebirths_50", name = "Godlike", desc = "Rebirth 50 times", counter = "Rebirths", goal = 50, reward = { title = "Godlike" } },

	-- Eggs Opened (hatches)
	{ key = "Eggs_10", name = "Hatchling", desc = "Open 10 eggs", counter = "EggsOpened", goal = 10, reward = { dna = 5000 } },
	{ key = "Eggs_100", name = "Collector", desc = "Open 100 eggs", counter = "EggsOpened", goal = 100, reward = { diamonds = 100 } },
	{ key = "Eggs_500", name = "Beastmaster", desc = "Open 500 eggs", counter = "EggsOpened", goal = 500, reward = { title = "Beastmaster" } },
	{ key = "Eggs_2000", name = "Zoologist", desc = "Open 2,000 eggs", counter = "EggsOpened", goal = 2000, reward = { title = "Zoologist" } },
	{ key = "Eggs_10000", name = "Mother of Dragons", desc = "Open 10,000 eggs", counter = "EggsOpened", goal = 10000, reward = { title = "Breeder" } },

	-- Secret Pets
	{ key = "Secrets_1", name = "Hidden Potential", desc = "Hatch a Secret Pet", counter = "SecretsHatched", goal = 1, reward = { diamonds = 500 } },
	{ key = "Secrets_5", name = "Whisperer", desc = "Hatch 5 Secret Pets", counter = "SecretsHatched", goal = 5, reward = { title = "Whisperer" } },
	{ key = "Secrets_20", name = "Enigma", desc = "Hatch 20 Secret Pets", counter = "SecretsHatched", goal = 20, reward = { title = "Enigma" } },

	-- Fuses
	{ key = "Fuses_1", name = "Alchemist", desc = "Fuse a pet", counter = "Fuses", goal = 1, reward = { dna = 10000 } },
	{ key = "Fuses_50", name = "Scientist", desc = "Fuse 50 pets", counter = "Fuses", goal = 50, reward = { diamonds = 150 } },
	{ key = "Fuses_250", name = "Mad Scientist", desc = "Fuse 250 pets", counter = "Fuses", goal = 250, reward = { title = "Mad Scientist" } },
	{ key = "Fuses_1000", name = "Creator", desc = "Fuse 1,000 pets", counter = "Fuses", goal = 1000, reward = { title = "Creator" } },

	-- Zone Floors (Expeditions/Zones)
	{ key = "Zones_2", name = "Explorer", desc = "Unlock 2 zones", counter = "ZoneFloorsCleared", goal = 2, reward = { diamonds = 20 } },
	{ key = "Zones_5", name = "Adventurer", desc = "Unlock 5 zones", counter = "ZoneFloorsCleared", goal = 5, reward = { title = "Adventurer" } },
	{ key = "Zones_10", name = "Trailblazer", desc = "Unlock 10 zones", counter = "ZoneFloorsCleared", goal = 10, reward = { title = "Trailblazer" } },
	{ key = "Zones_15", name = "Pathfinder", desc = "Unlock 15 zones", counter = "ZoneFloorsCleared", goal = 15, reward = { title = "Pathfinder" } },
	{ key = "Zones_20", name = "World Walker", desc = "Unlock 20 zones", counter = "ZoneFloorsCleared", goal = 20, reward = { title = "World Walker" } },

	-- Minigame Plays
	{ key = "Minigames_5", name = "Gamer", desc = "Play 5 minigames", counter = "MinigamesPlayed", goal = 5, reward = { dna = 50000 } },
	{ key = "Minigames_50", name = "Arcade Rat", desc = "Play 50 minigames", counter = "MinigamesPlayed", goal = 50, reward = { diamonds = 200 } },
	{ key = "Minigames_200", name = "Pro Gamer", desc = "Play 200 minigames", counter = "MinigamesPlayed", goal = 200, reward = { title = "Pro Gamer" } },
	{ key = "Minigames_1000", name = "Esports Champion", desc = "Play 1,000 minigames", counter = "MinigamesPlayed", goal = 1000, reward = { title = "Champion" } },

	-- Total Clicks
	{ key = "Clicks_1000", name = "Clicker", desc = "Click 1,000 times", counter = "TotalClicks", goal = 1000, reward = { dna = 1000 } },
	{ key = "Clicks_10000", name = "Tapper", desc = "Click 10,000 times", counter = "TotalClicks", goal = 10000, reward = { diamonds = 50 } },
	{ key = "Clicks_100000", name = "Spammer", desc = "Click 100,000 times", counter = "TotalClicks", goal = 100000, reward = { title = "Spammer" } },
	{ key = "Clicks_500000", name = "Machine Gun", desc = "Click 500,000 times", counter = "TotalClicks", goal = 500000, reward = { title = "Auto Clicker" } },
	{ key = "Clicks_1000000", name = "Millionaire", desc = "Click 1,000,000 times", counter = "TotalClicks", goal = 1000000, reward = { title = "Millionaire" } },

	-- Time Played (Seconds)
	{ key = "Time_3600", name = "Tourist", desc = "Play for 1 hour", counter = "TimePlayed", goal = 3600, reward = { diamonds = 50 } },
	{ key = "Time_36000", name = "Regular", desc = "Play for 10 hours", counter = "TimePlayed", goal = 36000, reward = { title = "Regular" } },
	{ key = "Time_180000", name = "Dedicated", desc = "Play for 50 hours", counter = "TimePlayed", goal = 180000, reward = { title = "Dedicated" } },
	{ key = "Time_360000", name = "Addict", desc = "Play for 100 hours", counter = "TimePlayed", goal = 360000, reward = { title = "Addict" } },
}

return Achievements