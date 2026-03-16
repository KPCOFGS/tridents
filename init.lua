-- Tridents Mod
-- Melee tridents with elemental powers.

local S = core.get_translator("tridents")

-- =============================================================================
-- Configuration
-- =============================================================================

local BASE_DAMAGE        = 8        -- melee hit damage
local CARRY_BUFF_DAMAGE  = 2        -- extra damage while holding trident
local BURN_DURATION      = 5        -- seconds target burns
local BURN_DAMAGE        = 1        -- damage per burn tick
local BURN_TICK_INTERVAL = 1        -- seconds between burn ticks
local TRIDENT_DURABILITY = 250      -- uses before it breaks

-- =============================================================================
-- Tracking: burn timers and carry buff
-- =============================================================================

local burning_entities = {}
local withering_entities = {}
local buffed_players = {}
local support_heal_cooldown = {} -- player name -> time remaining
local master_heal_cooldown = {}  -- player name -> time remaining

-- =============================================================================
-- Utility: spawn fire particles on an object
-- =============================================================================

local function spawn_fire_particles(pos, attached_to)
    if not pos then return end
    local def = {
        amount = 6,
        time = 1,
        minpos = {x = pos.x - 0.3, y = pos.y - 0.2, z = pos.z - 0.3},
        maxpos = {x = pos.x + 0.3, y = pos.y + 0.6, z = pos.z + 0.3},
        minvel = {x = -0.2, y = 0.5, z = -0.2},
        maxvel = {x = 0.2, y = 1.5, z = 0.2},
        minacc = {x = 0, y = 0.3, z = 0},
        maxacc = {x = 0, y = 0.6, z = 0},
        minexptime = 0.3,
        maxexptime = 0.8,
        minsize = 1.5,
        maxsize = 3.0,
        texture = "tridents_fire_particle.png",
        glow = 14,
    }
    if attached_to then
        def.attached = attached_to
        def.minpos = {x = -0.3, y = -0.2, z = -0.3}
        def.maxpos = {x = 0.3, y = 0.6, z = 0.3}
    end
    core.add_particlespawner(def)
end

-- =============================================================================
-- Burn system: apply fire damage over time
-- =============================================================================

local function apply_burn(target)
    if not target or not target:get_pos() then
        return
    end

    local key = tostring(target)

    burning_entities[key] = {
        target = target,
        timer = 0,
        remaining = BURN_DURATION,
    }
end

-- =============================================================================
-- Wither system: fast damage over time (faster than burn)
-- =============================================================================

local WITHER_DURATION      = 4
local WITHER_DAMAGE        = 2
local WITHER_TICK_INTERVAL = 0.5

local function spawn_wither_particles(pos, attached_to)
    if not pos then return end
    local def = {
        amount = 8,
        time = 1,
        minpos = {x = pos.x - 0.3, y = pos.y - 0.2, z = pos.z - 0.3},
        maxpos = {x = pos.x + 0.3, y = pos.y + 0.8, z = pos.z + 0.3},
        minvel = {x = -0.3, y = 0.3, z = -0.3},
        maxvel = {x = 0.3, y = 1.0, z = 0.3},
        minacc = {x = 0, y = 0.2, z = 0},
        maxacc = {x = 0, y = 0.5, z = 0},
        minexptime = 0.4,
        maxexptime = 1.0,
        minsize = 1.5,
        maxsize = 3.0,
        texture = "tridents_wither_particle.png",
        glow = 4,
    }
    if attached_to then
        def.attached = attached_to
        def.minpos = {x = -0.3, y = -0.2, z = -0.3}
        def.maxpos = {x = 0.3, y = 0.8, z = 0.3}
    end
    core.add_particlespawner(def)
end

local function apply_wither(target)
    if not target or not target:get_pos() then return end
    local key = tostring(target)
    withering_entities[key] = {
        target = target,
        timer = 0,
        remaining = WITHER_DURATION,
    }
end

-- =============================================================================
-- Heal particle utility
-- =============================================================================

local function spawn_heal_particles(pos)
    if not pos then return end
    core.add_particlespawner({
        amount = 10,
        time = 0.5,
        minpos = vector.subtract(pos, 0.4),
        maxpos = vector.add(pos, {x = 0.4, y = 1.5, z = 0.4}),
        minvel = {x = -0.3, y = 0.5, z = -0.3},
        maxvel = {x = 0.3, y = 1.5, z = 0.3},
        minacc = {x = 0, y = 0.2, z = 0},
        maxacc = {x = 0, y = 0.4, z = 0},
        minexptime = 0.5,
        maxexptime = 1.0,
        minsize = 1.5,
        maxsize = 3.0,
        texture = "tridents_heal_particle.png",
        glow = 10,
    })
end

local SUPPORT_HEAL_COOLDOWN = 30

-- =============================================================================
-- Main globalstep
-- =============================================================================

core.register_globalstep(function(dtime)
    -- Burn tick processing
    for key, burn in pairs(burning_entities) do
        local obj = burn.target
        if not obj or not obj:get_pos() then
            burning_entities[key] = nil
        else
            burn.timer = burn.timer + dtime
            burn.remaining = burn.remaining - dtime

            if burn.remaining <= 0 then
                burning_entities[key] = nil
            elseif burn.timer >= BURN_TICK_INTERVAL then
                burn.timer = 0
                local hp = obj:get_hp()
                if hp and hp > 0 then
                    obj:punch(obj, 1.0, {
                        full_punch_interval = 1.0,
                        damage_groups = {fleshy = BURN_DAMAGE},
                    }, nil)
                    spawn_fire_particles(obj:get_pos(), nil)
                end
            end
        end
    end

    -- Wither tick processing (faster than burn)
    for key, wither in pairs(withering_entities) do
        local obj = wither.target
        if not obj or not obj:get_pos() then
            withering_entities[key] = nil
        else
            wither.timer = wither.timer + dtime
            wither.remaining = wither.remaining - dtime

            if wither.remaining <= 0 then
                withering_entities[key] = nil
            elseif wither.timer >= WITHER_TICK_INTERVAL then
                wither.timer = 0
                local hp = obj:get_hp()
                if hp and hp > 0 then
                    -- Use punch so mob APIs handle death + drops properly
                    obj:punch(obj, 1.0, {
                        full_punch_interval = 1.0,
                        damage_groups = {fleshy = WITHER_DAMAGE},
                    }, nil)
                    spawn_wither_particles(obj:get_pos(), nil)
                end
            end
        end
    end

    -- Support heal cooldown tick
    for name, remaining in pairs(support_heal_cooldown) do
        support_heal_cooldown[name] = remaining - dtime
        if support_heal_cooldown[name] <= 0 then
            support_heal_cooldown[name] = nil
        end
    end

    -- Per-player checks
    for _, player in ipairs(core.get_connected_players()) do
        local name = player:get_player_name()
        local wielded = player:get_wielded_item()

        -- Fire trident carry buff
        local wname = wielded:get_name()
        if wname == "tridents:fire_trident" or wname == "tridents:master_trident" then
            if not buffed_players[name] then
                buffed_players[name] = true
                spawn_fire_particles(player:get_pos(), player)
            end
        else
            if buffed_players[name] then
                buffed_players[name] = nil
            end
        end
    end

    -- Master trident heal cooldown
    for name, remaining in pairs(master_heal_cooldown) do
        master_heal_cooldown[name] = remaining - dtime
        if master_heal_cooldown[name] <= 0 then
            master_heal_cooldown[name] = nil
        end
    end
end)

-- =============================================================================
-- The Fire Trident tool
-- =============================================================================

core.register_tool("tridents:fire_trident", {
    description = S("Fire Trident") .. "\n" ..
        core.colorize("#ff6600", S("Ignites targets on hit")) .. "\n" ..
        core.colorize("#ffaa00", S("+" .. CARRY_BUFF_DAMAGE ..
            " damage buff when held")) .. "\n" ..
        core.colorize("#ff4400", S("Immunity to fire while in inventory")),
    inventory_image = "tridents_fire_trident.png",
    wield_image = "tridents_fire_trident.png",
    wield_scale = {x = 2, y = 2, z = 1.5},

    tool_capabilities = {
        full_punch_interval = 0.9,
        max_drop_level = 1,
        groupcaps = {
            cracky = {
                times = {[3] = 3.0},
                uses = TRIDENT_DURABILITY,
                maxlevel = 0,
            },
            snappy = {
                times = {[3] = 0.4},
                uses = TRIDENT_DURABILITY,
                maxlevel = 0,
            },
            crumbly = {
                times = {[3] = 0.7},
                uses = TRIDENT_DURABILITY,
                maxlevel = 0,
            },
            choppy = {
                times = {[3] = 3.0},
                uses = TRIDENT_DURABILITY,
                maxlevel = 0,
            },
        },
        damage_groups = {fleshy = BASE_DAMAGE + CARRY_BUFF_DAMAGE},
    },

    groups = {weapon = 1, trident = 1},

    light_source = 5,

    -- Left-click: if hitting an entity, apply fire then let engine handle dig
    on_use = function(itemstack, user, pointed_thing)
        if pointed_thing.type == "object" then
            local target = pointed_thing.ref
            if target and target ~= user then
                target:punch(user, 1.0, itemstack:get_tool_capabilities(), nil)
                apply_burn(target)
                spawn_fire_particles(target:get_pos(), target)

                local tpos = target:get_pos()
                if tpos then
                    core.add_particlespawner({
                        amount = 12,
                        time = 0.2,
                        minpos = vector.subtract(tpos, 0.3),
                        maxpos = vector.add(tpos, 0.3),
                        minvel = {x = -1.5, y = 0.5, z = -1.5},
                        maxvel = {x = 1.5, y = 3, z = 1.5},
                        minexptime = 0.3,
                        maxexptime = 0.8,
                        minsize = 2,
                        maxsize = 4,
                        texture = "tridents_fire_burn.png",
                        glow = 14,
                    })
                end

                itemstack:add_wear(65535 / TRIDENT_DURABILITY)
                return itemstack
            end
        end
        -- Return nil for non-entity clicks so engine handles block digging
    end,
})

-- =============================================================================
-- Crafting recipe
-- =============================================================================

core.register_craft({
    output = "tridents:fire_trident",
    recipe = {
        {"",              "default:diamond",    "default:torch"},
        {"",              "default:obsidian",   "default:diamond"},
        {"default:stick", "",                   ""},
    },
})

-- =============================================================================
-- Lightning Trident
-- =============================================================================

local LIGHTNING_DAMAGE    = 10
local LIGHTNING_DURABILITY = 200

local has_lightning = core.get_modpath("lightning") ~= nil

-- Strike lightning at a position, with guaranteed fire
local function strike_lightning(pos)
    if has_lightning and lightning and lightning.strike then
        lightning.strike(pos)
    else
        -- Fallback: fake lightning with flash + sound + particles
        core.sound_play("default_cool_lava", {
            pos = pos,
            gain = 1.0,
            max_hear_distance = 64,
        }, true)

        -- Bright vertical bolt particle
        core.add_particlespawner({
            amount = 1,
            time = 0.1,
            minpos = {x = pos.x, y = pos.y, z = pos.z},
            maxpos = {x = pos.x, y = pos.y + 20, z = pos.z},
            minvel = {x = 0, y = 0, z = 0},
            maxvel = {x = 0, y = 0, z = 0},
            minexptime = 0.3,
            maxexptime = 0.5,
            minsize = 20,
            maxsize = 30,
            texture = "tridents_fire_particle.png",
            glow = 14,
        })
    end

    -- Guaranteed fire: place flame on top of the nearest solid node below
    local ground = pos
    for y = pos.y, pos.y - 5, -1 do
        local check = {x = pos.x, y = y, z = pos.z}
        local node = core.get_node(check)
        if node.name ~= "air" and node.name ~= "ignore" then
            local above = {x = check.x, y = check.y + 1, z = check.z}
            local above_node = core.get_node(above)
            if above_node.name == "air" then
                if core.registered_nodes["fire:basic_flame"] then
                    core.set_node(above, {name = "fire:basic_flame"})
                end
            end
            break
        end
    end

    -- Electric sparks
    core.add_particlespawner({
        amount = 20,
        time = 0.3,
        minpos = vector.subtract(pos, 0.5),
        maxpos = vector.add(pos, 0.5),
        minvel = {x = -3, y = 0, z = -3},
        maxvel = {x = 3, y = 5, z = 3},
        minacc = {x = 0, y = -5, z = 0},
        maxacc = {x = 0, y = -3, z = 0},
        minexptime = 0.2,
        maxexptime = 0.6,
        minsize = 1,
        maxsize = 3,
        texture = "tridents_fire_burn.png",
        glow = 14,
    })
end

core.register_tool("tridents:lightning_trident", {
    description = S("Lightning Trident") .. "\n" ..
        core.colorize("#88ccff", S("Strikes lightning on hit")) .. "\n" ..
        core.colorize("#ffaa00", S("Sets ground on fire")) .. "\n" ..
        core.colorize("#aaddff", S("Immunity to lightning while in inventory")),
    inventory_image = "tridents_lightning_trident.png",
    wield_image = "tridents_lightning_trident.png",
    wield_scale = {x = 2, y = 2, z = 1.5},

    tool_capabilities = {
        full_punch_interval = 1.1,
        max_drop_level = 1,
        groupcaps = {
            cracky = {
                times = {[3] = 3.0},
                uses = LIGHTNING_DURABILITY,
                maxlevel = 0,
            },
            snappy = {
                times = {[3] = 0.4},
                uses = LIGHTNING_DURABILITY,
                maxlevel = 0,
            },
            crumbly = {
                times = {[3] = 0.7},
                uses = LIGHTNING_DURABILITY,
                maxlevel = 0,
            },
            choppy = {
                times = {[3] = 3.0},
                uses = LIGHTNING_DURABILITY,
                maxlevel = 0,
            },
        },
        damage_groups = {fleshy = LIGHTNING_DAMAGE},
    },

    groups = {weapon = 1, trident = 1},

    light_source = 7,

    on_use = function(itemstack, user, pointed_thing)
        if pointed_thing.type == "object" then
            local target = pointed_thing.ref
            if target and target ~= user then
                target:punch(user, 1.0, itemstack:get_tool_capabilities(), nil)

                local tpos = target:get_pos()
                if tpos then
                    strike_lightning(tpos)
                    apply_burn(target)
                    spawn_fire_particles(tpos, target)
                end

                itemstack:add_wear(65535 / LIGHTNING_DURABILITY)
                return itemstack
            end
        end
    end,
})

core.register_craft({
    output = "tridents:lightning_trident",
    recipe = {
        {"",              "default:diamond",    "default:mese_crystal"},
        {"",              "default:steel_ingot", "default:diamond"},
        {"default:stick", "",                    ""},
    },
})

-- =============================================================================
-- Wither Trident
-- =============================================================================

local WITHER_TRIDENT_DAMAGE    = 9
local WITHER_TRIDENT_DURABILITY = 220

core.register_tool("tridents:wither_trident", {
    description = S("Wither Trident") .. "\n" ..
        core.colorize("#6030a0", S("Applies fast wither effect")) .. "\n" ..
        core.colorize("#402060", S("2 damage every 0.5s for 4s")),
    inventory_image = "tridents_wither_trident.png",
    wield_image = "tridents_wither_trident.png",
    wield_scale = {x = 2, y = 2, z = 1.5},

    tool_capabilities = {
        full_punch_interval = 0.8,
        max_drop_level = 1,
        groupcaps = {
            cracky = {
                times = {[3] = 3.0},
                uses = WITHER_TRIDENT_DURABILITY,
                maxlevel = 0,
            },
            snappy = {
                times = {[3] = 0.4},
                uses = WITHER_TRIDENT_DURABILITY,
                maxlevel = 0,
            },
            crumbly = {
                times = {[3] = 0.7},
                uses = WITHER_TRIDENT_DURABILITY,
                maxlevel = 0,
            },
            choppy = {
                times = {[3] = 3.0},
                uses = WITHER_TRIDENT_DURABILITY,
                maxlevel = 0,
            },
        },
        damage_groups = {fleshy = WITHER_TRIDENT_DAMAGE},
    },

    groups = {weapon = 1, trident = 1},

    light_source = 2,

    on_use = function(itemstack, user, pointed_thing)
        if pointed_thing.type == "object" then
            local target = pointed_thing.ref
            if target and target ~= user then
                target:punch(user, 1.0, itemstack:get_tool_capabilities(), nil)
                apply_wither(target)
                spawn_wither_particles(target:get_pos(), target)

                local tpos = target:get_pos()
                if tpos then
                    core.add_particlespawner({
                        amount = 15,
                        time = 0.2,
                        minpos = vector.subtract(tpos, 0.3),
                        maxpos = vector.add(tpos, 0.3),
                        minvel = {x = -1.5, y = 0.5, z = -1.5},
                        maxvel = {x = 1.5, y = 2, z = 1.5},
                        minexptime = 0.3,
                        maxexptime = 0.8,
                        minsize = 2,
                        maxsize = 4,
                        texture = "tridents_wither_particle.png",
                        glow = 4,
                    })
                end

                itemstack:add_wear(65535 / WITHER_TRIDENT_DURABILITY)
                return itemstack
            end
        end
    end,
})

core.register_craft({
    output = "tridents:wither_trident",
    recipe = {
        {"",              "default:diamond",    "default:obsidian"},
        {"",              "default:obsidian",   "default:diamond"},
        {"default:stick", "",                   ""},
    },
})

-- =============================================================================
-- Support Trident
-- =============================================================================

local SUPPORT_TRIDENT_DAMAGE    = 6
local SUPPORT_TRIDENT_DURABILITY = 300

core.register_tool("tridents:support_trident", {
    description = S("Support Trident") .. "\n" ..
        core.colorize("#60dd70", S("Hitting targets heals you")) .. "\n" ..
        core.colorize("#ff88aa", S("Right-click: full heal (30s cooldown)")),
    inventory_image = "tridents_support_trident.png",
    wield_image = "tridents_support_trident.png",
    wield_scale = {x = 2, y = 2, z = 1.5},

    tool_capabilities = {
        full_punch_interval = 1.0,
        max_drop_level = 1,
        groupcaps = {
            cracky = {
                times = {[3] = 3.0},
                uses = SUPPORT_TRIDENT_DURABILITY,
                maxlevel = 0,
            },
            snappy = {
                times = {[3] = 0.4},
                uses = SUPPORT_TRIDENT_DURABILITY,
                maxlevel = 0,
            },
            crumbly = {
                times = {[3] = 0.7},
                uses = SUPPORT_TRIDENT_DURABILITY,
                maxlevel = 0,
            },
            choppy = {
                times = {[3] = 3.0},
                uses = SUPPORT_TRIDENT_DURABILITY,
                maxlevel = 0,
            },
        },
        damage_groups = {fleshy = SUPPORT_TRIDENT_DAMAGE},
    },

    groups = {weapon = 1, trident = 1},

    light_source = 4,

    -- Left-click: hit target, heal user for the damage amount
    on_use = function(itemstack, user, pointed_thing)
        if pointed_thing.type == "object" then
            local target = pointed_thing.ref
            if target and target ~= user then
                target:punch(user, 1.0, itemstack:get_tool_capabilities(), nil)

                -- Heal user by the weapon's base damage
                local heal_amount = SUPPORT_TRIDENT_DAMAGE
                local user_hp = user:get_hp()
                local user_max = user:get_properties().hp_max
                local new_hp = math.min(user_hp + heal_amount, user_max)
                if new_hp > user_hp then
                    user:set_hp(new_hp)
                    spawn_heal_particles(user:get_pos())
                end

                itemstack:add_wear(65535 / SUPPORT_TRIDENT_DURABILITY)
                return itemstack
            end
        end
    end,

    -- Right-click: full heal with 30s cooldown
    on_secondary_use = function(itemstack, user, pointed_thing)
        if not user or not user:is_player() then return end
        -- Only heal if the player is actually wielding the trident
        local wielded = user:get_wielded_item()
        if wielded:get_name() ~= "tridents:support_trident" then return end

        local name = user:get_player_name()
        if support_heal_cooldown[name] then
            local remaining = math.ceil(support_heal_cooldown[name])
            core.chat_send_player(name,
                core.colorize("#ff4444", S("Heal on cooldown: ") .. remaining .. "s"))
            return
        end

        local max_hp = user:get_properties().hp_max
        user:set_hp(max_hp)
        spawn_heal_particles(user:get_pos())
        support_heal_cooldown[name] = SUPPORT_HEAL_COOLDOWN

        core.chat_send_player(name,
            core.colorize("#44ff44", S("Fully healed!")))

        itemstack:add_wear(65535 / SUPPORT_TRIDENT_DURABILITY)
        return itemstack
    end,

    on_place = function(itemstack, user, pointed_thing)
        return core.registered_tools["tridents:support_trident"].on_secondary_use(
            itemstack, user, pointed_thing
        )
    end,
})

core.register_craft({
    output = "tridents:support_trident",
    recipe = {
        {"",              "default:diamond",     "default:apple"},
        {"",              "default:mese_crystal", "default:diamond"},
        {"default:stick", "",                     ""},
    },
})

-- =============================================================================
-- Master Trident - all powers combined
-- =============================================================================

local MASTER_DAMAGE        = 12
local MASTER_DURABILITY    = 500
local MASTER_HEAL_COOLDOWN = 30
core.register_tool("tridents:master_trident", {
    description = S("Master Trident") .. "\n" ..
        core.colorize("#ffd700", S("All elemental powers combined")) .. "\n" ..
        core.colorize("#ff6600", S("Ignites targets")) .. "\n" ..
        core.colorize("#88ccff", S("Strikes lightning")) .. "\n" ..
        core.colorize("#6030a0", S("Applies wither")) .. "\n" ..
        core.colorize("#60dd70", S("Heals on hit")) .. "\n" ..
        core.colorize("#ff88aa", S("Right-click: full heal (30s cooldown)")) .. "\n" ..
        core.colorize("#ff4400", S("Immune to fire")) .. "\n" ..
        core.colorize("#aaddff", S("Immune to lightning")),
    inventory_image = "tridents_master_trident.png",
    wield_image = "tridents_master_trident.png",
    wield_scale = {x = 2, y = 2, z = 1.5},

    tool_capabilities = {
        full_punch_interval = 0.8,
        max_drop_level = 1,
        groupcaps = {
            cracky = {
                times = {[3] = 3.0},
                uses = MASTER_DURABILITY,
                maxlevel = 0,
            },
            snappy = {
                times = {[3] = 0.4},
                uses = MASTER_DURABILITY,
                maxlevel = 0,
            },
            crumbly = {
                times = {[3] = 0.7},
                uses = MASTER_DURABILITY,
                maxlevel = 0,
            },
            choppy = {
                times = {[3] = 3.0},
                uses = MASTER_DURABILITY,
                maxlevel = 0,
            },
        },
        damage_groups = {fleshy = MASTER_DAMAGE},
    },

    groups = {weapon = 1, trident = 1},

    light_source = 10,

    -- Left-click: all offensive effects
    on_use = function(itemstack, user, pointed_thing)
        if pointed_thing.type == "object" then
            local target = pointed_thing.ref
            if target and target ~= user then
                target:punch(user, 1.0, itemstack:get_tool_capabilities(), nil)

                local tpos = target:get_pos()
                if tpos then
                    -- Fire
                    apply_burn(target)
                    spawn_fire_particles(tpos, target)

                    -- Lightning
                    strike_lightning(tpos)

                    -- Wither
                    apply_wither(target)
                    spawn_wither_particles(tpos, target)

                    -- Heal user (support)
                    local user_hp = user:get_hp()
                    local user_max = user:get_properties().hp_max
                    local new_hp = math.min(user_hp + MASTER_DAMAGE, user_max)
                    if new_hp > user_hp then
                        user:set_hp(new_hp)
                        spawn_heal_particles(user:get_pos())
                    end
                end

                itemstack:add_wear(65535 / MASTER_DURABILITY)
                return itemstack
            end
        end
    end,

    -- Right-click: full heal with cooldown
    on_secondary_use = function(itemstack, user, pointed_thing)
        if not user or not user:is_player() then return end
        local wielded = user:get_wielded_item()
        if wielded:get_name() ~= "tridents:master_trident" then return end

        local name = user:get_player_name()
        if master_heal_cooldown[name] then
            local remaining = math.ceil(master_heal_cooldown[name])
            core.chat_send_player(name,
                core.colorize("#ff4444", S("Heal on cooldown: ") .. remaining .. "s"))
            return
        end

        local max_hp = user:get_properties().hp_max
        user:set_hp(max_hp)
        spawn_heal_particles(user:get_pos())
        master_heal_cooldown[name] = MASTER_HEAL_COOLDOWN

        core.chat_send_player(name,
            core.colorize("#ffd700", S("Fully healed!")))

        itemstack:add_wear(65535 / MASTER_DURABILITY)
        return itemstack
    end,

    on_place = function(itemstack, user, pointed_thing)
        return core.registered_tools["tridents:master_trident"].on_secondary_use(
            itemstack, user, pointed_thing
        )
    end,
})

core.register_craft({
    output = "tridents:master_trident",
    recipe = {
        {"tridents:fire_trident",    "default:diamond",  "tridents:lightning_trident"},
        {"",                          "default:mese",     ""},
        {"tridents:wither_trident",  "",                  "tridents:support_trident"},
    },
})

-- =============================================================================
-- Inventory-based immunities
-- =============================================================================

local function player_has_item(player, itemname)
    local inv = player:get_inventory()
    if inv then
        return inv:contains_item("main", itemname)
    end
    return false
end

-- Block lightning damage. The lightning mod does obj:punch(obj, ...) meaning
-- the player punches itself with {fleshy=8}. Detect self-punch and cancel it.
core.register_on_punchplayer(function(player, hitter, time_from_last_punch,
                                      tool_capabilities, dir, damage)
    if hitter == player and (player_has_item(player, "tridents:lightning_trident")
            or player_has_item(player, "tridents:master_trident")) then
        return true
    end
    return false
end)

-- Block fire/lava damage. These come through as node_damage (damage_per_second).
core.register_on_player_hpchange(function(player, hp_change, reason)
    if hp_change < 0 and reason and reason.type == "node_damage" then
        if player_has_item(player, "tridents:fire_trident")
                or player_has_item(player, "tridents:master_trident") then
            return 0
        end
    end
    return hp_change
end, true)

-- =============================================================================
-- Player leave cleanup
-- =============================================================================

core.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    buffed_players[name] = nil
    support_heal_cooldown[name] = nil
    master_heal_cooldown[name] = nil
end)

core.log("action", "[tridents] Loaded!")
