----------
--ESTRAL--
----------

require "CarClaimSystem_Core"

-- who may do what to a claimed vehicle. nothing in here touches the game, so it runs the same
-- on the server, on a client reading the stamped copy, and in the tests.

CarClaimSystem_Perms = CarClaimSystem_Perms or {}

-- a flag table holding only the known flags that are set, whatever was handed in. everything
-- a client sends is a claim: this is the one way a table out of a packet becomes a grant.
function CarClaimSystem_Perms.clean(flags)
    local out = {}
    if type(flags) ~= "table" then return out end

    for _, flag in ipairs(CarClaimSystem.FLAGS) do
        if flags[flag] == true then out[flag] = true end
    end

    return out
end

function CarClaimSystem_Perms.all()
    local out = { owner = true }

    for _, flag in ipairs(CarClaimSystem.FLAGS) do out[flag] = true end

    return out
end

function CarClaimSystem_Perms.any(flags)
    if type(flags) ~= "table" then return false end

    for _, flag in ipairs(CarClaimSystem.FLAGS) do
        if flags[flag] == true then return true end
    end

    return false
end

-- the flags username holds on claim.
--
--   the owner holds everything.
--   a player with an entry of their own holds exactly that entry, even an empty one: that is
--   how one faction member is kept out of a car the rest of the faction can use.
--   anyone else holds whatever the owner's faction and safehouse grants add up to, for as long
--   as they are in that faction or safehouse. sameFaction and sameSafehouse are asked every
--   time, so joining or being kicked takes effect at once.
function CarClaimSystem_Perms.resolve(claim, username, sameFaction, sameSafehouse)
    if claim.owner == username then return CarClaimSystem_Perms.all() end

    local own = claim.players and claim.players[username]
    if own then return CarClaimSystem_Perms.clean(own) end

    local out = {}

    if CarClaimSystem_Perms.any(claim.faction) and sameFaction(claim.owner, username) then
        for flag in pairs(CarClaimSystem_Perms.clean(claim.faction)) do out[flag] = true end
    end

    if CarClaimSystem_Perms.any(claim.safehouse) and sameSafehouse(claim.owner, username) then
        for flag in pairs(CarClaimSystem_Perms.clean(claim.safehouse)) do out[flag] = true end
    end

    return out
end
