-- ==============================================================================
-- SHENKY HUB - GAME MANIFEST & TIER REGISTRY
-- File: games.luau
-- 
-- Supported Tiers:
--   "keyless" : Loads immediately without any key prompt
--   "public"  : Requires PlatoBoost key (or bypassed with Premium Key)
--   "private" : Requires VIP Premium Key (SHK_...) bound to HWID
-- ==============================================================================

return {
    -- [Keyless Games]
    ["10766845655"] = {
        name = "Piano Rhythm Tiles",
        tier = "keyless",
        script = "piano-rhythm-tiles.luau"
    },
    ["9553887523"] = {
        name = "Caramel Cozy Pixel Farm",
        tier = "keyless",
        script = "Caramel/main.luau",
        isRoot = true
    },

    -- [Public Games (PlatoBoost Key)]
    ["10526463655"] = {
        name = "8 Ball Duels",
        tier = "public",
        script = "8ball-duels.luau"
    },
    ["10582324587"] = {
        name = "Flick Football",
        tier = "public",
        script = "Flick Football/main.luau",
        isRoot = true
    },
    ["137151641329864"] = {
        name = "RoFront",
        tier = "public",
        script = "rofront.luau"
    },

    -- [Hybrid Games (Supports Both PlatoBoost Free & VIP Premium Key)]
    ["10767928510"] = {
        name = "Pixel Lineage",
        tier = { "public", "private" },
        script = "pixel-lineage.luau"
    }
}
