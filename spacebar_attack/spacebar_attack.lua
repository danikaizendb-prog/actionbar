spacebarAttackButton = nil

function init()
  spacebarAttackButton = modules.client_topmenu.addRightGameToggleButton('spacebarAttackButton', tr('Spacebar Attack'), '/spacebar_attack/spacebar', toggleSpacebarBind)
  spacebarAttackButton:setOn(true)
  if spacebarAttackButton:isOn() then
    bindSpacebar()
  else
    unbindSpacebar()
  end
end

function terminate()
  unbindSpacebar()
  spacebarAttackButton:destroy()
end

function getFirstValidCreature()
    local battlePanel = modules.game_battle.battlePanel
    if not battlePanel then return nil end

    local children = battlePanel:getChildren()
    for i = 1, #children do
        local battleButton = children[i]
        if battleButton:isVisible() then
            local creature = battleButton.creature
            if creature and creature:getHealthPercent() > 0 and isNpcOrSafeFight(creature:getId()) then
                return creature
            end
        end
    end
    return nil
end

function chooseAimFromBattleList()
    local creature = getFirstValidCreature()
    if creature then
        g_game.attack(creature)
    else
        g_game.cancelAttack()
    end
end

function isNpcOrSafeFight(creatureId)
    local creatureData = g_map.getCreatureById(creatureId)
    if not creatureData then return false end

    -- Verificar si la criatura está ignorada usando la misma función del battle list
    if modules.game_battle.isCreatureIgnored and modules.game_battle.isCreatureIgnored(creatureData) then
        return false
    end

    if creatureData:isMonster() then
        return true
    elseif creatureData:isPlayer() then
        return not g_game.isSafeFight()
    end
    return false
end

function bindSpacebar()
    g_keyboard.bindKeyPress('Space', chooseAimFromBattleList)
end

function unbindSpacebar()
    g_keyboard.unbindKeyPress('Space', chooseAimFromBattleList)
end

function toggleSpacebarBind()
    if spacebarAttackButton:isOn() then
        unbindSpacebar()
        spacebarAttackButton:setOn(false)
    else
        bindSpacebar()
        spacebarAttackButton:setOn(true)
    end
end

-------------------------------------------------
--Scripts END------------------------------------
-------------------------------------------------