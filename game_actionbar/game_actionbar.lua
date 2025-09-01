HOTKEY_USE = nil
HOTKEY_USEONSELF = 1
HOTKEY_USEONTARGET = 2
HOTKEY_USEWITH = 3

local maxSlots = 60
actionBar = nil
actionBarPanel = nil
bottomPanel = nil
slotToEdit = nil
spellAssignWindow = nil
spellsPanel = nil
textAssignWindow = nil
objectAssignWindow = nil
mouseGrabberWidget = nil
actionRadioGroup = nil
editHotkeyWindow = nil
missedSlotToEdit = nil
itemDragRetry = nil
slotReassign = nil
lastHotkeyTime = 0
cooldown = {}
groupCooldown = {}

-- Nueva configuración: nombre del nodo para perfiles
local profilesNodeName = 'game_actionbar_profiles'

-- Estado de perfiles por personaje
local currentProfile = 'default'
-- Nota: cada character tendrá root[char] = { current = 'default', profiles = { default = { slots = {...} } } }

local ProgressCallback = {
    update = 1,
    finish = 2
}

function init()
    bottomPanel = modules.game_interface.getBottomPanel()
    actionBar = g_ui.loadUI('game_actionbar', bottomPanel)
    actionBarPanel = actionBar:getChildById('actionBarPanel')
    mouseGrabberWidget = g_ui.createWidget('UIWidget')
    mouseGrabberWidget:setVisible(false)
    mouseGrabberWidget:setFocusable(false)
    mouseGrabberWidget.onMouseRelease = onChooseItemMouseRelease

    local console = modules.game_console.consolePanel
    if console then
        console:addAnchor(AnchorTop, actionBar:getId(), AnchorBottom)
    end

    -- Si hay un botón en tu UI con id 'profileButton', lo enlazamos para ciclar perfiles.
    local profileBtn = actionBar:getChildById('profileButton')
    if profileBtn then
        profileBtn.onClick = function() cycleProfile(true) end
    end

    if g_game.isOnline() then
        addEvent(function()
            setupActionBar()
            -- migración / carga de perfiles
            migrateLegacyActionBarIfNeeded()
            loadActionBar()
        end)
    end

    connect(g_game, {
        onGameStart = online,
        onGameEnd = offline,
        onSpellGroupCooldown = onSpellGroupCooldown,
        onSpellCooldown = onSpellCooldown
    })

end

function terminate()
    saveActionBar()
    actionBar:destroy()
    mouseGrabberWidget:destroy()
    disconnect(g_game, {
        onGameStart = online,
        onGameEnd = offline,
        onSpellGroupCooldown = onSpellGroupCooldown,
        onSpellCooldown = onSpellCooldown
    })
    if spellAssignWindow then
        closeSpellAssignWindow()
    end
    if objectAssignWindow then
        closeObjectAssignWindow()
    end
    if textAssignWindow then
        closeTextAssignWindow()
    end
    if editHotkeyWindow then
        closeEditHotkeyWindow()
    end
    if spellsPanel then
        disconnect(spellsPanel, {
            onChildFocusChange = function(self, focusedChild)
                if focusedChild == nil then
                    return
                end
                updatePreviewSpell(focusedChild)
            end
        })
    end

    local console = modules.game_console.consolePanel
    if console then
        console:removeAnchor(AnchorTop)
        console:fill('parent')
    end
end

function online()
    actionBarPanel:destroyChildren()
    addEvent(function()
        setupActionBar()
        loadActionBar()
    end)
end

function offline()
    saveActionBar()
    unbindHotkeys()
end

function copySlot(fromSlotId, toSlotId, visible)
    local fromSlot = actionBarPanel:getChildById(fromSlotId)
    local tmpslot = actionBarPanel:getChildById(toSlotId)
    
    if not fromSlot then
        return
    end
    
    if not tmpslot then
        tmpslot = g_ui.createWidget('ActionSlot', actionBarPanel)
        tmpslot:setId(toSlotId)
    end
    
    tmpslot:setVisible(visible)
    
    local tmptext = fromSlot.text == nil
    local tmpid = fromSlot.itemId == nil
    local tmpwords = fromSlot.words == nil
    
    local imageSource = fromSlot.getImageSource and fromSlot:getImageSource() or nil
    local imageClip = fromSlot.getImageClip and fromSlot:getImageClip() or nil
    
    local imgsrcbool = not imageSource
    local imgclipbool = not imageClip
    
    imageSource = (imgsrcbool or (tmptext and tmpid and tmpwords)) and '/images/game/actionbar/slot-actionbar' or imageSource
    imageClip = imgclipbool and '0 0 0 0' or imageClip
    
    tmpslot:setImageSource(imageSource)
    tmpslot:setImageClip(imageClip)
    
    local tmpItem = fromSlot.getItem and fromSlot:getItem() or nil
    if tmpItem then
        tmpslot:setItem(tmpItem)
    else
        tmpslot:setItem(nil)
    end
    
    tmpslot:setText(fromSlot.getText and fromSlot:getText() or "")
    tmpslot.autoSend = fromSlot.autoSend or false
    tmpslot.itemId = fromSlot.itemId or nil
    tmpslot.subType = fromSlot.subType or nil
    tmpslot.words = fromSlot.words or nil
    tmpslot.text = fromSlot.text or nil
    tmpslot.parameter = fromSlot.parameter or nil
    tmpslot.useType = fromSlot.useType or nil
    
    local fromSlotTextChild = fromSlot.getChildById and fromSlot:getChildById('text')
    local toSlotTextChild = tmpslot.getChildById and tmpslot:getChildById('text')
    if fromSlotTextChild and toSlotTextChild then
        toSlotTextChild:setText(fromSlotTextChild:getText())
    end
    
    tmpslot:setTooltip(fromSlot.getTooltip and fromSlot:getTooltip() or "")
end

function onDropFunc(slotId)
    if slotReassign then
        local fromSlotId = slotToEdit
        local toSlotId = slotId
        local fromSlot = actionBarPanel:getChildById(fromSlotId)
        local toSlot = actionBarPanel:getChildById(toSlotId)
        
        if fromSlot and toSlot then
            local tmpslotid = 'slot' .. maxSlots + 1
            copySlot(fromSlotId, tmpslotid, false)
            copySlot(toSlotId, fromSlotId, true)
            copySlot(tmpslotid, toSlotId, true)
            clearSlotById(tmpslotid)
        else
            slotReassign = nil
            slotToEdit = nil
        end
        slotReassign = nil
        slotToEdit = nil
    end
    
    slotToEdit = slotId
    
    if itemDragRetry and missedSlotToEdit then
        local widget1 = missedSlotToEdit[1]
        local mousePos1 = missedSlotToEdit[2]
        local item1 = missedSlotToEdit[3]
        if widget1 and mousePos1 and item1 then
            onChooseItemByDrag(widget1, mousePos1, item1)
        end
        itemDragRetry = nil
        missedSlotToEdit = nil
    end
    
    setupHotkeys()
end

function setupActionBar()
    local slotsToDisplay = math.floor((actionBarPanel:getWidth()) / 34)
    for i = 1, maxSlots do
        slot = g_ui.createWidget('ActionSlot', actionBarPanel)
        slot:setId('slot' .. i)
        slot:setVisible(true)
        slot.itemId = nil
        slot.subType = nil
        slot.words = nil
        slot.text = nil
        slot.useType = nil
        slot:setTooltip('Empty slot') -- Tooltip inicial

        -- mantener binding para seleccionar el slot al presionar (no lo eliminamos)
        g_mouse.bindPress(slot, function()
            slotToEdit = 'slot' .. i .. ''
        end, MouseLeftButton)

        g_mouse.bindPress(slot, function()
            createMenu('slot' .. i)
        end, MouseRightButton)

        g_mouse.bindOnDrop(slot, function()
            if slotToEdit == 'slot' .. i then
                slotReassign = 'slot' .. i
            end
            onDropFunc('slot' .. i)
        end)

        -- Nota: NO asignamos onMouseRelease aquí; lo haremos en setupHotkeys() para mantener la lógica centralizada.

        if i == 1 then
            slot:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        end
    end
end

function createMenu(slotId)
    local menu = g_ui.createWidget('PopupMenu')
    slotToEdit = slotId
    menu:addOption('Assign Spell', function()
        openSpellAssignWindow()
    end)
    menu:addOption('Assign Object', function()
        startChooseItem()
        openObjectAssignWindow()
    end)
    menu:addOption('Assign Text', function()
        openTextAssignWindow()
    end)
    menu:addOption('Edit Hotkey', function()
        openEditHotkeyWindow()
    end)
    local actionSlot = actionBarPanel:recursiveGetChildById(slotToEdit)
    if actionSlot.itemId or actionSlot.words or actionSlot.text or actionSlot.useType or actionSlot.hotkey then
        menu:addOption('Clear Slot', function()
            clearSlot()
            clearHotkey()
        end)
    end
    menu:display()
end

function openSpellAssignWindow()
    spellAssignWindow = g_ui.loadUI('assign_spell', g_ui.getRootWidget())
    spellsPanel = spellAssignWindow:getChildById('spellsPanel')
    addEvent(function()
        initializeSpelllist()
    end)
    spellAssignWindow:raise()
    spellAssignWindow:focus()
    spellAssignWindow:getChildById('filterTextEdit'):focus()
    modules.game_hotkeys.enableHotkeys(false)
end

function closeSpellAssignWindow()
    spellAssignWindow:destroy()
    spellAssignWindow = nil
    spellsPanel = nil
    modules.game_hotkeys.enableHotkeys(true)
end

function initializeSpelllist()
    g_keyboard.bindKeyPress('Down', function()
        spellsPanel:focusNextChild(KeyboardFocusReason)
    end, spellsPanel:getParent())
    g_keyboard.bindKeyPress('Up', function()
        spellsPanel:focusPreviousChild(KeyboardFocusReason)
    end, spellsPanel:getParent())

    for spellProfile, _ in pairs(SpelllistSettings) do
        for i = 1, #SpelllistSettings[spellProfile].spellOrder do
            local spell = SpelllistSettings[spellProfile].spellOrder[i]
            local info = SpellInfo[spellProfile][spell]
            if info then
                local tmpLabel = g_ui.createWidget('SpellListLabel', spellsPanel)
                tmpLabel:setId(spell)
                tmpLabel:setText(spell .. '\n\'' .. info.words .. '\'')
                tmpLabel:setPhantom(false)
                tmpLabel.defaultHeight = tmpLabel:getHeight()
                tmpLabel.words = info.words:lower()
                tmpLabel.name = spell:lower()

                local iconId = tonumber(info.icon)
                if not iconId and SpellIcons[info.icon] then
                    iconId = SpellIcons[info.icon][1]
                end

                tmpLabel:setHeight(SpelllistSettings[spellProfile].iconSize.height + 4)
                tmpLabel:setTextOffset(topoint((SpelllistSettings[spellProfile].iconSize.width + 10) .. ' ' ..
                                                   (SpelllistSettings[spellProfile].iconSize.height - 32) / 2 + 3))
                tmpLabel:setImageSource(SpelllistSettings[spellProfile].iconFile)
                tmpLabel:setImageClip(Spells.getImageClip(iconId, spellProfile))
                tmpLabel:setImageSize(tosize(SpelllistSettings[spellProfile].iconSize.width .. ' ' ..
                                                 SpelllistSettings[spellProfile].iconSize.height))
            end
        end
    end

    for v, k in ipairs(spellsPanel:getChildren()) do
        if k:isVisible() then
            spellsPanel:focusChild(k, KeyboardFocusReason)
            updatePreviewSpell(k)
            break
        end
    end
    connect(spellsPanel, {
        onChildFocusChange = function(self, focusedChild)
            if focusedChild == nil then
                return
            end
            updatePreviewSpell(focusedChild)
        end
    })
end

function updatePreviewSpell(focusedChild)
    local spellName = focusedChild:getId()
    iconId = tonumber(Spells.getClientId(spellName))
    local spell = Spells.getSpellByName(spellName)
    local profile = Spells.getSpellProfileByName(spellName)
    spellsPanel:getParent():getChildById('previewSpell'):setImageSource(SpelllistSettings[profile].iconFile)
    spellsPanel:getParent():getChildById('previewSpell'):setImageClip(Spells.getImageClip(iconId, profile))
    spellsPanel:getParent():getChildById('previewSpellName'):setText(spellName)
    spellsPanel:getParent():getChildById('previewSpellWords'):setText('\'' .. spell.words .. '\'')
    if spell.parameter then
        spellAssignWindow:getChildById('parameterTextEdit'):enable()
    else
        spellAssignWindow:getChildById('parameterTextEdit'):disable()
    end
end

function spellAssignAccept()
    clearSlot()
    local focusedChild = spellsPanel:getFocusedChild()
    if not focusedChild then
        return
    end
    local spellName = focusedChild:getId()
    iconId = tonumber(Spells.getClientId(spellName))
    local spell = Spells.getSpellByName(spellName)
    local profile = Spells.getSpellProfileByName(spellName)
    local slot = actionBarPanel:getChildById(slotToEdit)
    slot:setImageSource(Spells.getIconFileByProfile(profile))
    slot:setImageClip(Spells.getImageClip(iconId, profile))
    slot.words = spell.words
    slot.itemId = 469
    slot:setItemId(469)
    if spell.parameter then
        slot.parameter = spellAssignWindow:getChildById('parameterTextEdit'):getText():gsub('"', '')
    else
        slot.parameter = nil
    end
    closeSpellAssignWindow()
    setupHotkeys()
end

function clearSlot()
    local slot = actionBarPanel:getChildById(slotToEdit)
    slot:setImageSource('/images/game/actionbar/slot-actionbar')
    slot:setImageClip('0 0 0 0')
    slot:clearItem()
    slot:setText('')
    slot.itemId = nil
    slot.subType = nil
    slot.words = nil
    slot.text = nil
    slot.useType = nil
    slot:getChildById('text'):setText('')
    slot:setTooltip('Empty slot') -- Restaurar tooltip
end

function clearSlotById(slotId)
    local slot = actionBarPanel:getChildById(slotId)
    slot:setImageSource('/images/game/actionbar/slot-actionbar')
    slot:setImageClip('0 0 0 0')
    slot:clearItem()
    slot:setText('')
    slot.itemId = nil
    slot.subType = nil
    slot.words = nil
    slot.text = nil
    slot.useType = nil
    slot:getChildById('text'):setText('')
    slot:setTooltip('')
end

function clearHotkey()
    local slot = actionBarPanel:getChildById(slotToEdit)
    slot.hotkey = nil
    slot:getChildById('key'):setText('')
end

function openTextAssignWindow()
    textAssignWindow = g_ui.loadUI('assign_text', g_ui.getRootWidget())
    textAssignWindow:raise()
    textAssignWindow:focus()
    modules.game_hotkeys.enableHotkeys(false)
end

function closeTextAssignWindow()
    textAssignWindow:destroy()
    textAssignWindow = nil
    modules.game_hotkeys.enableHotkeys(true)
end

function textAssignAccept()
    local text = textAssignWindow:getChildById('textToSendTextEdit'):getText()
    if text == '' then
        return
    end
    local checkForParameter = text:split(' "')
    local name, parameter = nil, nil
    if #checkForParameter == 2 then
        name = checkForParameter[1]
        parameter = checkForParameter[2]
    else
        name = text
    end

    local spell, profile, spellName = Spells.getSpellByWords(name)

    local slot = actionBarPanel:getChildById(slotToEdit)
    if spellName then
        iconId = tonumber(Spells.getClientId(spellName))
        clearSlot()
        slot:setImageSource(Spells.getIconFileByProfile(profile))
        slot:setImageClip(Spells.getImageClip(iconId, profile))
        slot.words = spell.words
        slot.itemId = 469
        slot:setItemId(469)
        if parameter and spell.parameter then
            slot.parameter = parameter
        else
            slot.parameter = nil
        end
    else
        clearSlot()
        slot:getChildById('text'):setText(text)
        while slot:getChildById('text'):getTextSize().height > 30 do
            local subString = slot:getChildById('text'):getText()
            subString = string.sub(subString, 1, #subString - 1)
            slot:getChildById('text'):setText(subString)
        end
        slot:setImageSource('/images/game/actionbar/item-background')
        slot.text = text
        slot.itemId = 469
        slot:setItemId(469)
        slot.autoSend = textAssignWindow:recursiveGetChildById('sendAutomaticallyCheckBox'):isChecked()
        
        -- Actualizar tooltip
        local tooltipText = text
        if slot.autoSend then
            tooltipText = tooltipText .. ' (Auto)'
        end
        slot:setTooltip(tooltipText)
        
        setupHotkeys()
    end
    closeTextAssignWindow()
    saveActionBar()
end

function openObjectAssignWindow()
    if objectAssignWindow ~= nil then
        objectAssignWindow:destroy()
    end
    objectAssignWindow = g_ui.loadUI('assign_object', g_ui.getRootWidget())
    actionRadioGroup = UIRadioGroup.create()
    actionRadioGroup:addWidget(objectAssignWindow:getChildById('useOnYourselfCheckbox'))
    actionRadioGroup:addWidget(objectAssignWindow:getChildById('useOnTargetCheckbox'))
    actionRadioGroup:addWidget(objectAssignWindow:getChildById('useWithCrosshairCheckbox'))
    actionRadioGroup:addWidget(objectAssignWindow:getChildById('equipCheckbox'))
    actionRadioGroup:addWidget(objectAssignWindow:getChildById('useCheckbox'))
    objectAssignWindow:setVisible(false)
end

function closeObjectAssignWindow()
    objectAssignWindow:destroy()
    objectAssignWindow = nil
    actionRadioGroup = nil
    modules.game_hotkeys.enableHotkeys(true)
end

function startChooseItem()
    if g_ui.isMouseGrabbed() then
        return
    end
    mouseGrabberWidget:grabMouse()
    g_mouse.pushCursor('target')
end

function objectAssignAccept()
    clearSlot()
    local item = objectAssignWindow:getChildById('previewItem'):getItem()
    if not item then
        return
    end
    local slot = actionBarPanel:getChildById(slotToEdit)
    slot:setItem(item)
    slot:setImageSource('/images/game/actionbar/item-background')
    slot:setBorderWidth(0)
    slot.itemId = item:getId()
    if item:isFluidContainer() then
        slot.subType = item:getSubType()
    end
    
    local useTypeText = ''
    if objectAssignWindow:getChildById('equipCheckbox'):isChecked() then
        slot.useType = 'equip'
        useTypeText = 'Equip'
    elseif objectAssignWindow:getChildById('useCheckbox'):isChecked() then
        slot.useType = 'use'
        useTypeText = 'Use'
    elseif objectAssignWindow:getChildById('useOnYourselfCheckbox'):isChecked() then
        slot.useType = 'useOnSelf'
        useTypeText = 'Use on self'
    elseif objectAssignWindow:getChildById('useOnTargetCheckbox'):isChecked() then
        slot.useType = 'useOnTarget'
        useTypeText = 'Use on target'
    elseif objectAssignWindow:getChildById('useWithCrosshairCheckbox'):isChecked() then
        slot.useType = 'useWith'
        useTypeText = 'Use with'
    end
    
    slot:setTooltip(item:getName() .. ' (' .. useTypeText .. ')')
    
    setupHotkeys()
    closeObjectAssignWindow()
    saveActionBar()
end

function onChooseItemMouseRelease(self, mousePosition, mouseButton)
    local item = nil
    if mouseButton == MouseLeftButton then
        local clickedWidget = modules.game_interface.getRootPanel():recursiveGetChildByPos(mousePosition, false)
        if clickedWidget then
            if clickedWidget:getClassName() == 'UIItem' and not clickedWidget:isVirtual() then
                item = clickedWidget:getItem()
            end
        end
    end

    if item and item:getPosition().x == 65535 and slotToEdit then
        objectAssignWindow:getChildById('previewItem'):setItemId(item:getId())
        objectAssignWindow:getChildById('previewItem'):setItemCount(1)
        objectAssignWindow:getChildById('equipCheckbox'):setEnabled(false)
        objectAssignWindow:getChildById('useCheckbox'):setEnabled(false)
        objectAssignWindow:getChildById('useOnYourselfCheckbox'):setEnabled(false)
        objectAssignWindow:getChildById('useOnTargetCheckbox'):setEnabled(false)
        objectAssignWindow:getChildById('useWithCrosshairCheckbox'):setEnabled(false)
objectAssignWindow:getChildById('equipCheckbox'):setEnabled(true) -- Siempre habilitado
if item:isMultiUse() then
    objectAssignWindow:getChildById('useOnYourselfCheckbox'):setEnabled(true)
    objectAssignWindow:getChildById('useOnTargetCheckbox'):setEnabled(true)
    objectAssignWindow:getChildById('useWithCrosshairCheckbox'):setEnabled(true)
else
    objectAssignWindow:getChildById('useCheckbox'):setEnabled(true)
end
actionRadioGroup:selectWidget(objectAssignWindow:getChildById('equipCheckbox')) -- Selecciona equipar por defecto
        if not objectAssignWindow:isVisible() then
            objectAssignWindow:show()
        end
        objectAssignWindow:raise()
        objectAssignWindow:focus()
    end
    g_mouse.popCursor('target')
    self:ungrabMouse()
    return true
end

function onChooseItemByDrag(self, mousePosition, item)
    if item and item:getPosition().x == 65535 and slotToEdit then
        openObjectAssignWindow()
        objectAssignWindow:getChildById('previewItem'):setItemId(item:getId())
        objectAssignWindow:getChildById('previewItem'):setItemCount(1)
        objectAssignWindow:getChildById('equipCheckbox'):setEnabled(false)
        objectAssignWindow:getChildById('useCheckbox'):setEnabled(false)
        objectAssignWindow:getChildById('useOnYourselfCheckbox'):setEnabled(false)
        objectAssignWindow:getChildById('useOnTargetCheckbox'):setEnabled(false)
        objectAssignWindow:getChildById('useWithCrosshairCheckbox'):setEnabled(false)
objectAssignWindow:getChildById('equipCheckbox'):setEnabled(true) -- Siempre habilitado
if item:isMultiUse() then
    objectAssignWindow:getChildById('useOnYourselfCheckbox'):setEnabled(true)
    objectAssignWindow:getChildById('useOnTargetCheckbox'):setEnabled(true)
    objectAssignWindow:getChildById('useWithCrosshairCheckbox'):setEnabled(true)
else
    objectAssignWindow:getChildById('useCheckbox'):setEnabled(true)
end
actionRadioGroup:selectWidget(objectAssignWindow:getChildById('equipCheckbox')) -- Selecciona equipar por defecto
        if not objectAssignWindow:isVisible() then
            objectAssignWindow:show()
        end
        objectAssignWindow:raise()
        objectAssignWindow:focus()
    elseif not slotToEdit then
        itemDragRetry = true
        missedSlotToEdit = {self, mousePosition, item}
    end
end

function onDragReassign(self, item)
    slotReassign = self
end

function openEditHotkeyWindow()
    editHotkeyWindow = g_ui.loadUI('edit_hotkey', g_ui.getRootWidget())
    editHotkeyWindow:grabKeyboard()

    local comboLabel = editHotkeyWindow:recursiveGetChildById('comboPreview')
    comboLabel.keyCombo = ''
    editHotkeyWindow.onKeyDown = hotkeyCapture
    editHotkeyWindow:raise()
    editHotkeyWindow:focus()
    modules.game_hotkeys.enableHotkeys(false)
end

function closeEditHotkeyWindow()
    editHotkeyWindow:destroy()
    editHotkeyWindow = nil
    modules.game_hotkeys.enableHotkeys(true)
end

function unbindHotkeys()
    for v, slot in pairs(actionBarPanel:getChildren()) do
        if slot.hotkey and slot.hotkey ~= '' then
            g_keyboard.unbindKeyPress(slot.hotkey)
        end
    end
end

function setupHotkeys()
    unbindHotkeys()

    -- Asignar manejador de mouse release para cada slot (con firma correcta)
    for _, slot in pairs(actionBarPanel:getChildren()) do
        -- usar la firma (self, mousePosition, mouseButton) y devolver true para consumir
        slot.onMouseRelease = function(self, mousePosition, mouseButton)
            -- solo responder al botón izquierdo
            if mouseButton ~= MouseLeftButton then
                return false
            end
            -- Ejecutar la acción del slot
            executeSlotAction(self)
            return true
        end
    end

    -- Agrupar slots por hotkey
    local hotkeyGroups = {}
    for _, slot in pairs(actionBarPanel:getChildren()) do
        if slot.hotkey and slot.hotkey ~= '' then
            if not hotkeyGroups[slot.hotkey] then
                hotkeyGroups[slot.hotkey] = {}
            end
            table.insert(hotkeyGroups[slot.hotkey], slot)
        end
    end

    -- Vincular cada grupo de hotkeys: el DELAY se aplica UNA VEZ aquí por hotkey
    for hotkey, slots in pairs(hotkeyGroups) do
        g_keyboard.bindKeyPress(hotkey, function()
            if not modules.game_hotkeys.canPerformKeyCombo(hotkey) then
                return
            end
            if g_clock.millis() - lastHotkeyTime < modules.client_options.getOption('hotkeyDelay') then
                return
            end

            lastHotkeyTime = g_clock.millis()
            for _, slot in ipairs(slots) do
                executeSlotAction(slot)
            end
        end)
    end
end

-- Función auxiliar para ejecutar acciones de un slot
function executeSlotAction(slot)
    if slot.itemId and slot.useType then
        if slot.useType == 'use' then
            modules.game_hotkeys.executeHotkeyItem(HOTKEY_USE, slot.itemId, slot.subType)
        elseif slot.useType == 'useOnTarget' then
            modules.game_hotkeys.executeHotkeyItem(HOTKEY_USEONTARGET, slot.itemId, slot.subType)
        elseif slot.useType == 'useWith' then
            modules.game_hotkeys.executeHotkeyItem(HOTKEY_USEWITH, slot.itemId, slot.subType)
        elseif slot.useType == 'useOnSelf' then
            modules.game_hotkeys.executeHotkeyItem(HOTKEY_USEONSELF, slot.itemId, slot.subType)
        elseif slot.useType == 'equip' then
            local item = g_game.findPlayerItem(slot.itemId, -1)
            if item then
                g_game.equipItem(item)
            end
        end
    elseif slot.words then
        if slot.parameter and slot.parameter ~= '' then
            g_game.talk(slot.words .. ' "' .. slot.parameter)
        else
            g_game.talk(slot.words)
        end
    elseif slot.text then
        if slot.autoSend then
            g_game.talk(slot.text)
        else
            if not modules.game_console.isChatEnabled() then
                modules.game_console.switchChatOnCall()
            end
            modules.game_console.setTextEditText(slot.text)
        end
    end
end

function checkHotkey(hotkey)
    return false
end

function hotkeyCapture(assignWindow, keyCode, keyboardModifiers)
    local hotkeyAlreadyUsed = false
    assignWindow:raise()
    assignWindow:focus()
    local keyCombo = determineKeyComboDesc(keyCode, keyboardModifiers)
    local comboPreview = assignWindow:recursiveGetChildById('comboPreview')
    local errorLabel = editHotkeyWindow:recursiveGetChildById('errorLabel')
    if checkHotkey(keyCombo) then
        errorLabel:setVisible(true)
        editHotkeyWindow:setHeight(180)
    else
        errorLabel:setVisible(false)
        editHotkeyWindow:setHeight(160)
    end
    comboPreview:setText(tr('Current hotkey to change: %s', keyCombo))
    comboPreview.keyCombo = keyCombo
    comboPreview:resizeToText()
    assignWindow:getChildById('applyButton'):enable()
    return true
end

function hotkeyClear(assignWindow)
    local comboPreview = assignWindow:recursiveGetChildById('comboPreview')
    comboPreview:setText(tr('Current hotkey to change: none'))
    comboPreview.keyCombo = ''
    comboPreview:resizeToText()
    assignWindow:getChildById('applyButton'):disable()
end

function hotkeyCaptureOk(assignWindow, keyCombo)
    local slot = actionBarPanel:getChildById(slotToEdit)
    
    -- No verificar si la hotkey ya está en uso
    unbindHotkeys()
    slot.hotkey = keyCombo
    local text = slot.hotkey
    text = text:gsub('Shift', 'S')
    text = text:gsub('Alt', 'A')
    text = text:gsub('Ctrl', 'C')
    text = text:gsub('+', '')
    slot:getChildById('key'):setText(text)
    setupHotkeys()
    
    if assignWindow == editHotkeyWindow then
        closeEditHotkeyWindow()
        return
    end
    assignWindow:destroy()
end


-- ********************************************************************
-- Sección de perfiles serializables (guardar/cargar por personaje)
-- ********************************************************************

-- Helper: obtener nodo raíz de perfiles (no crea)
local function getProfilesRoot()
    return g_settings.getNode(profilesNodeName) or {}
end

-- Helper: guardar nodo raíz
local function setProfilesRoot(root)
    g_settings.setNode(profilesNodeName, root)
    g_settings.save()
end

-- Asegura que haya una entrada para este character
local function ensureCharProfilesRoot(createIfMissing)
    local root = getProfilesRoot()
    local char = g_game.getCharacterName()
    root[char] = root[char] or { current = 'default', profiles = {} }
    if createIfMissing and not root[char].profiles['default'] then
        -- crear perfil default vacío (slots vacíos)
        local defaultProfile = { name = 'default', slots = {} }
        for i = 1, maxSlots do
            defaultProfile.slots['slot' .. i] = {
                hotkey = nil, autoSend = false, itemId = nil, subType = nil,
                useType = nil, text = nil, words = nil, parameter = nil
            }
        end
        root[char].profiles['default'] = defaultProfile
    end
    setProfilesRoot(root)
    return root
end

-- Migración simple: si hay datos viejos en 'game_actionbar', convertirlos en profile 'default'
function migrateLegacyActionBarIfNeeded()
    local legacy = g_settings.getNode('game_actionbar')
    if legacy and not table.empty(legacy) then
        local char = g_game.getCharacterName()
        local root = getProfilesRoot()
        root[char] = root[char] or { current = 'default', profiles = {} }
        -- si ya existe profiles para este char no migramos
        if root[char] and not table.empty(root[char].profiles) then
            return
        end
        -- crear default profile y llenar con legacy
        local defaultProfile = { name = 'default', slots = {} }
        for slotId, setting in pairs(legacy[char] or {}) do
            defaultProfile.slots[slotId] = {
                hotkey = setting.hotkey,
                autoSend = setting.autoSend,
                itemId = setting.itemId,
                subType = setting.subType,
                useType = setting.useType,
                text = setting.text,
                words = setting.words,
                parameter = setting.parameter
            }
        end
        -- llenar con vacíos si faltan
        for i = 1, maxSlots do
            local sid = 'slot' .. i
            if not defaultProfile.slots[sid] then
                defaultProfile.slots[sid] = {
                    hotkey = nil, autoSend = false, itemId = nil, subType = nil,
                    useType = nil, text = nil, words = nil, parameter = nil
                }
            end
        end
        root[char].profiles['default'] = defaultProfile
        root[char].current = 'default'
        setProfilesRoot(root)
        -- limpiar legacy para evitar migraciones futuras (opcional)
        g_settings.setNode('game_actionbar', {})
        g_settings.save()
    end
end

-- Guardar el perfil actual con el estado del actionBarPanel
function saveProfile(name)
    if not name or name == '' then return end
    local char = g_game.getCharacterName()
    local root = getProfilesRoot()
    root[char] = root[char] or { current = 'default', profiles = {} }
    local profile = { name = name, slots = {} }
    for _, slot in ipairs(actionBarPanel:getChildren()) do
        profile.slots[slot:getId()] = {
            hotkey = slot.hotkey,
            autoSend = slot.autoSend,
            itemId = slot.itemId,
            subType = slot.subType,
            useType = slot.useType,
            text = slot.text,
            words = slot.words,
            parameter = slot.parameter
        }
    end
    root[char].profiles[name] = profile
    root[char].current = name
    setProfilesRoot(root)
    currentProfile = name
end

-- Cargar un perfil y aplicarlo a la UI
function loadProfile(name)
    -- Primero, desbindear hotkeys existentes para evitar que queden ligadas al perfil anterior
    unbindHotkeys()

    local char = g_game.getCharacterName()
    local root = getProfilesRoot()
    if not root[char] or not root[char].profiles[name] then
        return false
    end
    local profile = root[char].profiles[name

    ]

    -- Limpiar todos los slots actuales para evitar residuos visuales/hotkeys previas
    for _, slot in pairs(actionBarPanel:getChildren()) do
        -- reset mínimo (no destruimos widgets, sólo limpiamos su estado)
        slot.hotkey = nil
        slot.autoSend = false
        slot.itemId = nil
        slot.subType = nil
        slot.words = nil
        slot.text = nil
        slot.parameter = nil
        slot.useType = nil
        slot:getChildById('text'):setText('')
        slot:setImageSource('/images/game/actionbar/slot-actionbar')
        slot:setImageClip('0 0 0 0')
        slot:setTooltip('Empty slot')
        slot:getChildById('key'):setText('')
    end

    -- Aplicar los datos del perfil sobre los slots
    for slotId, data in pairs(profile.slots) do
        local slot = actionBarPanel:recursiveGetChildById(slotId)
        if slot then
            slot.hotkey = data.hotkey
            slot.autoSend = data.autoSend
            slot.itemId = data.itemId
            slot.subType = data.subType
            slot.words = data.words
            slot.text = data.text
            slot.useType = data.useType
            slot.parameter = data.parameter

            if slot.words then
                loadSpell(slot)
            elseif slot.text then
                loadText(slot)
            elseif slot.itemId and slot.itemId > 0 then
                loadObject(slot)
            else
                -- si está vacío, ya limpiamos arriba
            end

            -- Restaurar tooltip
            if slot.words then
                local tooltipText = slot.words
                if slot.parameter then
                    tooltipText = tooltipText .. ' ("' .. slot.parameter .. '")'
                end
                slot:setTooltip(tooltipText)
            elseif slot.text then
                local tooltipText = slot.text
                if slot.autoSend then
                    tooltipText = tooltipText .. ' (Auto)'
                end
                slot:setTooltip(tooltipText)
            else
                slot:setTooltip('Empty slot')
            end

            -- Actualizar label de la tecla
            if slot.hotkey then
                local text = slot.hotkey
                if type(text) == 'string' then
                    text = text:gsub('Shift', 'S')
                    text = text:gsub('Alt', 'A')
                    text = text:gsub('Ctrl', 'C')
                    text = text:gsub('+', '')
                end
                slot:getChildById('key'):setText(text)
            else
                slot:getChildById('key'):setText('')
            end
        end
    end

    -- Rebind hotkeys del perfil cargado
    setupHotkeys()
    currentProfile = name

    -- Actualizar texto del botón si existe
    if actionBar then
        local btn = actionBar:getChildById('profileNameButton')
        if btn then btn:setText(currentProfile) end
    end

    return true
end

-- Ciclar perfiles del personaje (next = true -> siguiente)
function cycleProfile(next)
    local char = g_game.getCharacterName()
    local root = getProfilesRoot()
    if not root[char] or not root[char].profiles then return end
    local names = {}
    for k,_ in pairs(root[char].profiles) do table.insert(names, k) end
    table.sort(names)
    if #names == 0 then return end
    local idx = 1
    for i,n in ipairs(names) do if n == currentProfile then idx = i break end end
    if next then idx = (idx % #names) + 1 else idx = ((idx - 2) % #names) + 1 end
    saveProfile(currentProfile)
    loadProfile(names[idx])
end

-- Reemplaza saveActionBar para guardar en perfil actual
function saveActionBar()
    g_logger.info("saving action bar (profile)")
    -- Guardamos en el perfil actual
    saveProfile(currentProfile)
end

-- loadActionBar ahora carga el perfil actual o crea uno por defecto
function loadActionBar()
    unbindHotkeys()
    local root = getProfilesRoot()
    local char = g_game.getCharacterName()
    if not root[char] then
        ensureCharProfilesRoot(true)
        root = getProfilesRoot()
    end
    local profileName = root[char].current or 'default'
    currentProfile = profileName

    if not root[char].profiles[profileName] then
        ensureCharProfilesRoot(true)
    end

    loadProfile(profileName)
    setupHotkeys()
end

-- Funciones rápidas expuestas para crear / borrar perfiles desde UI rápido (usadas por botones)
function createProfileQuick()
    local char = g_game.getCharacterName()
    local root = getProfilesRoot()
    root[char] = root[char] or { current = 'default', profiles = {} }
    -- generar nombre único profile1, profile2, ...
    local base = 'profile'
    local i = 1
    while root[char].profiles[base .. i] do i = i + 1 end
    local name = base .. i
    saveProfile(name)
    -- feedback en consola del cliente
    print('Profile created: ' .. name)
    if actionBar then
        local btn = actionBar:getChildById('profileNameButton')
        if btn then btn:setText(name) end
    end
end

function deleteProfileQuick()
    local char = g_game.getCharacterName()
    local root = getProfilesRoot()
    if not root[char] or not root[char].profiles then
        print('No profiles for this character')
        return
    end
    if not root[char].profiles[currentProfile] then
        print('Current profile does not exist')
        return
    end
    if currentProfile == 'default' then
        print('Cannot delete default profile')
        return
    end
    local delName = currentProfile
    root[char].profiles[delName] = nil
    -- elegir un perfil existente para cargar (si no hay, crear default)
    local nextName = nil
    for k,_ in pairs(root[char].profiles) do nextName = k break end
    if not nextName then
        ensureCharProfilesRoot(true)
        nextName = 'default'
    end
    root[char].current = nextName
    setProfilesRoot(root)
    loadProfile(nextName)
    print('Deleted profile: ' .. delName .. ' -> loaded ' .. nextName)
    if actionBar then
        local btn = actionBar:getChildById('profileNameButton')
        if btn then btn:setText(currentProfile) end
    end
end

-- Crear un perfil vacío con nombre incremental (profile1, profile2, ...)
function createEmptyProfileQuick()
    local char = g_game.getCharacterName()
    local root = getProfilesRoot()
    root[char] = root[char] or { current = 'default', profiles = {} }

    -- Buscar un nombre disponible
    local base = 'profile'
    local i = 1
    while root[char].profiles[base .. i] do
        i = i + 1
    end
    local name = base .. i

    -- Inicializar slots vacíos
    local profile = { name = name, slots = {} }
    for j = 1, maxSlots do
        profile.slots['slot'..j] = {
            hotkey = nil, autoSend = false, itemId = nil, subType = nil,
            useType = nil, text = nil, words = nil, parameter = nil
        }
    end
    root[char].profiles[name] = profile
    root[char].current = name
    setProfilesRoot(root)

    -- Cargar inmediatamente el perfil vacío
    loadProfile(name)

    print('Empty profile created and loaded: ' .. name)
end
-- ===========================
-- Funciones para nombres y UI
-- ===========================

-- Devuelve el nombre del perfil actual
function getCurrentProfileName()
    return currentProfile
end

-- Muestra el perfil actual en la consola y actualiza el botón en la UI (si existe)
function printCurrentProfile()
    local name = currentProfile or 'default'
    print('Current profile: ' .. name)
    -- actualizar texto del botón si existe en la UI
    if actionBar then
        local btn = actionBar:getChildById('profileNameButton')
        if btn then
            btn:setText(name)
        end
    end
end

-- Crear un perfil con el nombre especificado (si ya existe, se sobrescribe)
function createProfileWithName(name)
    if not name or name:match("^%s*$") then
        print('createProfileWithName: nombre inválido')
        return
    end
    saveProfile(name)
    print('Profile created: ' .. name)
    -- actualizar botón
    if actionBar then
        local btn = actionBar:getChildById('profileNameButton')
        if btn then btn:setText(name) end
    end
end

-- Renombrar un perfil existente (oldName -> newName)
function renameProfile(oldName, newName)
    if not oldName or not newName or oldName:match("^%s*$") or newName:match("^%s*$") then
        print('renameProfile: nombres inválidos')
        return
    end
    local root = getProfilesRoot()
    local char = g_game.getCharacterName()
    if not root[char] or not root[char].profiles or not root[char].profiles[oldName] then
        print('renameProfile: perfil origen no existe: ' .. tostring(oldName))
        return
    end
    if root[char].profiles[newName] then
        print('renameProfile: ya existe un perfil con el nombre: ' .. tostring(newName))
        return
    end

    -- Mover tabla de oldName a newName
    root[char].profiles[newName] = root[char].profiles[oldName]
    root[char].profiles[oldName] = nil

    -- Si el perfil actual era oldName, actualizar current
    if root[char].current == oldName then
        root[char].current = newName
        currentProfile = newName
    end

    setProfilesRoot(root)
    print('Renamed profile: ' .. oldName .. ' -> ' .. newName)

    -- actualizar botón
    if actionBar then
        local btn = actionBar:getChildById('profileNameButton')
        if btn then btn:setText(currentProfile) end
    end
end

-- Helper: exposición para crear con nombre desde la UI si prefieres
function createProfilePrompt() -- si en el futuro agregas un diálogo, puedes llamarlo desde aquí
    print('createProfilePrompt: usa modules.game_actionbar.createProfileWithName("Nombre")')
end

-- ===========================
-- Integración: actualizar texto del botón cuando se carga/crea/elimina perfiles
-- ===========================

-- Actualizar botón al cargar perfil: insertamos una actualización simple dentro de loadProfile
-- (Si tu loadProfile está definida arriba, localiza la función loadProfile(name) y al final de la función,
-- antes de `return true`, añade las siguientes líneas:)

--[[
    -- al final de loadProfile(name) (antes de return true)
    if actionBar then
        local btn = actionBar:getChildById('profileNameButton')
        if btn then btn:setText(name) end
    end
]]

-- También actualizamos createProfileQuick y deleteProfileQuick para refrescar el botón.
-- (Si tienes las funciones createProfileQuick/deleteProfileQuick en el archivo,
-- añade dentro de ellas, tras guardar/cargar, este snippet:)

--[[
    if actionBar then
        local btn = actionBar:getChildById('profileNameButton')
        if btn then btn:setText(currentProfile) end
    end
]]

-- Nota: si prefieres, puedo inyectar automáticamente estas dos líneas dentro de tus funciones existentes.
-- ********************************************************************
-- Fin de sección perfiles
-- ********************************************************************

function loadSpell(slot)
    local spell, profile, spellName = Spells.getSpellByWords(slot.words)
    iconId = tonumber(Spells.getClientId(spellName))
    slot:setImageSource(Spells.getIconFileByProfile(profile))
    slot:setImageClip(Spells.getImageClip(iconId, profile))
    slot:getChildById('text'):setText('')
    slot:setBorderWidth(0)
    setupHotkeys()
end

function loadObject(slot)
    slot:setItemId(slot.itemId)
    slot:setImageSource('/images/game/actionbar/item-background')
    slot:setImageClip('0 0 0 0')
    slot:getChildById('text'):setText('')
    slot:setBorderWidth(0)
    setupHotkeys()
end

function loadText(slot)
    slot:getChildById('text'):setText(slot.text)
    while slot:getChildById('text'):getTextSize().height > 30 do
        local subString = slot:getChildById('text'):getText()
        subString = string.sub(subString, 1, #subString - 1)
        slot:getChildById('text'):setText(subString)
    end
    slot:setImageSource('/images/game/actionbar/item-background')
    slot:setImageClip('0 0 0 0')
    setupHotkeys()
end

function round(n)
    return n % 1 >= 0.5 and math.ceil(n) or math.floor(n)
end

function updateCooldown(progressRect, duration, spellId, count)
    progressRect:setPercent(progressRect:getPercent() + 10000 / duration)
    local cd = round(duration - (progressRect:getPercent() * duration / 100)) / 1000
    if cd > 0 then
        progressRect:setText(cd .. 's')
    end

    if progressRect:getPercent() < 100 then
        removeEvent(progressRect.event)
        cooldown[spellId] = duration - count * 100
        progressRect.event = scheduleEvent(function()
            updateCooldown(progressRect, duration, spellId, count + 1)
        end, 100)
    else
        cooldown[spellId] = nil
        progressRect:destroy()
    end
end

function updateGroupCooldown(progressRect, duration, groupId)
    progressRect:setPercent(progressRect:getPercent() + 10000 / duration)
    local cd = round(duration - (progressRect:getPercent() * duration / 100)) / 1000
    if cd > 0 then
        progressRect:setText(cd .. 's')
    end

    if progressRect:getPercent() < 100 then
        removeEvent(progressRect.event)
        progressRect.event = scheduleEvent(function()
            updateGroupCooldown(progressRect, duration, groupId)
        end, 100)
    else
        groupCooldown[groupId] = nil
        progressRect:destroy()
    end
end

function onSpellCooldown(spellId, duration)
    local slot
    for v, k in pairs(actionBarPanel:getChildren()) do
        local spell, profile, spellName = Spells.getSpellByIcon(spellId)
        if not spell then
            print('[WARNING] Can not set cooldown on spell with id: ' .. spellId)
            return true
        end
        if k.words == spell.words or spell.clientId and spell.clientId == k.itemId then
            slot = k
            local progressRect = slot:recursiveGetChildById('progress' .. spell.id)
            if not progressRect then
                progressRect = g_ui.createWidget('SpellProgressRect', slot)
                progressRect:setId('progress' .. spell.id)
                progressRect.item = slot
                progressRect:fill('parent')
                progressRect:setFont('verdana-11px-rounded')
            else
                progressRect:setPercent(0)
            end

            local updateFunc = function()
                updateCooldown(progressRect, duration, spell.id, 0)
            end
            local finishFunc = function()
                cooldown[spell.id] = nil
                progressRect:hide()
            end
            progressRect:setPercent(0)
            updateFunc()
            cooldown[spell.id] = duration
        end
    end
end

function onSpellGroupCooldown(groupId, duration)
    local slot
    local spellGroup = 0
    for v, k in pairs(actionBarPanel:getChildren()) do
        local spell, profile, spellName
        if k.words then
            spell, profile, spellName = Spells.getSpellByWords(k.words)
            end
        end
        if spell then
            if table.contains(spell.group, groupId) then
                local continue = false
                if not cooldown[spell.id] or cooldown[spell.id] and cooldown[spell.id] < duration then
                    local oldProgressBar = k:recursiveGetChildById('progress' .. spell.id)
                    if oldProgressBar then
                        cooldown[spell.id] = nil
                        oldProgressBar:hide()
                    end
                    continue = true
                if continue then
                    slot = k
                    local progressRect = slot:recursiveGetChildById('progress' .. groupId)
                    if not progressRect then
                        progressRect = g_ui.createWidget('SpellProgressRect', slot)
                        progressRect:setId('progress' .. groupId)
                        progressRect.item = slot
                        progressRect:fill('parent')
                        progressRect:setFont('verdana-11px-rounded')
                    else
                        progressRect:setPercent(0)
                    end

                    local updateFunc = function()
                        updateGroupCooldown(progressRect, duration, groupId)
                    end
                    local finishFunc = function()
                        groupCooldown[groupId] = false
                        progressRect:hide()
                    end
                    progressRect:setPercent(0)
                    updateFunc()
                    groupCooldown[groupId] = true
                end
            end
        end
    end
end
function filterSpells(text)
    if #text > 0 then
        text = text:lower()

        for index, spellListLabel in pairs(spellsPanel:getChildren()) do
            if string.find(spellListLabel.name:lower(), text) or string.find(spellListLabel.words:lower(), text) then
                showSpell(spellListLabel)
            else
                hideSpell(spellListLabel)
            end
        end

    else
        for index, spellListLabel in pairs(spellsPanel:getChildren()) do
            showSpell(spellListLabel)
        end
    end
end

function hideSpell(spellListLabel)
    if spellListLabel:isVisible() then
        spellListLabel:hide()
        spellListLabel:setHeight(0)
    end
end

function showSpell(spellListLabel)
    if not spellListLabel:isVisible() then
        spellListLabel:setHeight(spellListLabel.defaultHeight)
        spellListLabel:show()
    end
end