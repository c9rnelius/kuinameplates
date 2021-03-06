--[[
-- Kui_Nameplates_Auras
-- By Kesava at curse.com
-- All rights reserved

   Auras module for Kui_Nameplates core layout.
]]
local addon = LibStub('AceAddon-3.0'):GetAddon('KuiNameplates')
local spelllist = LibStub('KuiSpellList-1.0')
local kui = LibStub('Kui-1.0')
local mod = addon:NewModule('Auras', 'AceEvent-3.0')
local whitelist, _

local GetTime, floor, ceil = GetTime, floor, ceil

-- auras pulsate when they have less than this many seconds remaining
local FADE_THRESHOLD = 5

-- combat log events to listen to for fading auras
local auraEvents = {
--	['SPELL_DISPEL'] = true,
	['SPELL_AURA_REMOVED'] = true,
	['SPELL_AURA_BROKEN'] = true,
	['SPELL_AURA_BROKEN_SPELL'] = true,
}

local PositionSelectList = {
	['TOPLEFT'] = 'TOPLEFT',
	['TOPRIGHT'] = 'TOPRIGHT',
	['BOTTOMLEFT'] = 'BOTTOMLEFT',
	['BOTTOMRIGHT'] = 'BOTTOMRIGHT',
	['TOP'] = 'TOP',
	['BOTTOM'] = 'BOTTOM',
	['LEFT'] = 'LEFT',
	['RIGHT'] = 'RIGHT',
	['CENTER'] = 'CENTER'
}

local function ArrangeButtons(self)
	local pv, pc
	self.visible = 0
	
	for k,b in ipairs(self.buttons) do
		if b:IsShown() then
			self.visible = self.visible + 1
			
			b:ClearAllPoints()
			
			if pv then
				if (self.visible-1) % (self.frame.trivial and 3 or 5) == 0 then
					-- start of row
					b:SetPoint('BOTTOMLEFT', pc, 'TOPLEFT', 0, 1)
					pc = b
				else
					-- subsequent button in a row
					b:SetPoint('LEFT', pv, 'RIGHT', 1, 0)
				end
			else
				-- first button
				b:SetPoint('BOTTOMLEFT')
				pc = b
			end
			
			pv = b
		end
	end

	if self.visible == 0 then
		self:Hide()
	else
		self:Show()
	end
end
-- aura pulsating functions ----------------------------------------------------
local DoPulsateAura
do
	local function OnFadeOutFinished(button)
		button.fading = nil
		button.faded = true
		DoPulsateAura(button)
	end
	local function OnFadeInFinished(button)
		button.fading = nil
		button.faded = nil
		DoPulsateAura(button)
	end

	DoPulsateAura = function(button)
		if button.fading or not button.doPulsate then return end
		button.fading = true
	
		if button.faded then
			kui.frameFade(button, {
				startAlpha = .5,
				timeToFade = .5,
				finishedFunc = OnFadeInFinished
			})
		else
			kui.frameFade(button, {
				mode = 'OUT',
				endAlpha = .5,
				timeToFade = .5,
				finishedFunc = OnFadeOutFinished
			})
		end
	end
end
local function StopPulsatingAura(button)
	kui.frameFadeRemoveFrame(button)
	button.doPulsate = nil
	button.fading = nil
	button.faded = nil
	button:SetAlpha(1)
end
--------------------------------------------------------------------------------
local function OnAuraUpdate(self, elapsed)
	self.elapsed = self.elapsed - elapsed

	if self.elapsed <= 0 then
		local timeLeft = self.expirationTime - GetTime()
		
		if mod.db.profile.display.pulsate then
			if self.doPulsate and timeLeft > FADE_THRESHOLD then
				-- reset pulsating status if the time is extended
				StopPulsatingAura(self)
			elseif not self.doPulsate and timeLeft <= FADE_THRESHOLD then
				-- make the aura pulsate
				self.doPulsate = true
				DoPulsateAura(self)
			end
		end

		if mod.db.profile.display.timerThreshold > -1 and
		   timeLeft > mod.db.profile.display.timerThreshold
		then
			self.time:Hide()
		else
			local timeLeftS

			if mod.db.profile.display.decimal and
			   timeLeft <= 1 and timeLeft > 0
			then
				-- decimal places for the last second
				timeLeftS = string.format("%.1f", timeLeft)
			else
				timeLeftS = (timeLeft > 60 and
				             ceil(timeLeft/60)..'m' or
				             floor(timeLeft)
				            )
			end

			if timeLeft <= 5 then
				-- red text
				self.time:SetTextColor(1,0,0)
			elseif timeLeft <= 20 then
				-- yellow text
				self.time:SetTextColor(1,1,0)
			else
				-- white text
				self.time:SetTextColor(1,1,1)
			end
			
			self.time:SetText(timeLeftS)
			self.time:Show()
		end
		
		if timeLeft < 0 then
			-- used when a non-targeted mob's auras timer gets below 0
			-- but the combat log hasn't reported that it has faded yet.
			self.time:SetText('0')
		end
		
		if mod.db.profile.display.decimal and
		   timeLeft <= 2 and timeLeft > 0
		then
			-- faster updates in the last two seconds
			self.elapsed = .05
		else
			self.elapsed = .5
		end
	end
end

local function OnAuraShow(self)
	local parent = self:GetParent()
	parent:ArrangeButtons()
end

local function OnAuraHide(self)
	local parent = self:GetParent()

	if parent.spellIds[self.spellId] == self then
		parent.spellIds[self.spellId] = nil
	end

	self.time:Hide()
	self.spellId = nil

	-- reset button pulsating
	StopPulsatingAura(self)

	parent:ArrangeButtons()
end

local function GetAuraButton(self, spellId, icon, count, duration, expirationTime)
	local button

	if self.spellIds[spellId] then
		-- use this spell's current button...
		button = self.spellIds[spellId]
	elseif self.visible ~= #self.buttons then
		-- .. or reuse a hidden button...
		for k,b in pairs(self.buttons) do
			if not b:IsShown() then
				button = b
				break
			end
		end
	end
	
	if not button then
		-- ... or create a new button
		button = CreateFrame('Frame', nil, self)
		button:Hide()
		
		button.icon = button:CreateTexture(nil, 'ARTWORK') 
		
		button.time = self.frame:CreateFontString(button,{
			size = 'large' })
		button.time:SetJustifyH('LEFT') -- TODO ?
		button.time:SetPoint(mod.db.profile.display.auraTextPosition, mod.db.profile.display.textXOffset, mod.db.profile.display.textYOffset) -- -2, 4
		button.time:Hide()
		
		button.count = self.frame:CreateFontString(button, {
			outline = 'OUTLINE'})
		button.count:SetJustifyH('RIGHT')
		button.count:SetPoint('BOTTOMRIGHT', 2, -2)
		button.count:Hide()

		button:SetBackdrop({ bgFile = kui.m.t.solid })
		button:SetBackdropColor(0,0,0)

		button.icon:SetPoint('TOPLEFT', 1, -1)
		button.icon:SetPoint('BOTTOMRIGHT', -1, 1)
		
		button.icon:SetTexCoord(.1, .9, .2, .8)
		
		tinsert(self.buttons, button)
		
		button:SetScript('OnHide', OnAuraHide)
		button:SetScript('OnShow', OnAuraShow)
	end

	if self.frame.trivial then
		-- shrink icons for trivial frames!
		button:SetHeight(addon.sizes.frame.tauraHeight)
		button:SetWidth(addon.sizes.frame.tauraWidth)
		button.time = self.frame:CreateFontString(button.time, {
			reset = true, size = 'small' })
	else

		-- print(mod.db.profile.display.auraIconHeight)
		-- normal size!
		button:SetHeight(mod.db.profile.auras.auraIconHeight)
		button:SetWidth(mod.db.profile.auras.auraIconWidth)
		button.time = self.frame:CreateFontString(button.time, {
			reset = true, size = mod.db.profile.display.auraFontSize })
	end
	
	button.icon:SetTexture(icon)

	if count > 1 and not self.frame.trivial then
		button.count:SetText(count)
		button.count:Show()
	else
		button.count:Hide()
	end

	if duration == 0 then
		-- hide time on timeless auras
		button:SetScript('OnUpdate', nil)
		button.time:Hide()
	else
		button:SetScript('OnUpdate', OnAuraUpdate)
	end

	button.duration = duration
	button.expirationTime = expirationTime
	button.spellId = spellId
	button.elapsed = 0
	
	self.spellIds[spellId] = button

	return button
end
----------------------------------------------------------------------- hooks --
function mod:Create(msg, frame)
	frame.auras = CreateFrame('Frame', nil, frame)
	frame.auras.frame = frame
	
	frame.auras:SetPoint('BOTTOMRIGHT', frame.health, 'TOPRIGHT', -3, 10)
	frame.auras:SetHeight(50)
	frame.auras:Hide()

	frame.auras.visible = 0
	frame.auras.buttons = {}
	frame.auras.spellIds = {}
	frame.auras.GetAuraButton = GetAuraButton
	frame.auras.ArrangeButtons = ArrangeButtons

	frame.auras:SetScript('OnHide', function(self)
		for k,b in pairs(self.buttons) do
			b:Hide()
		end

		self.visible = 0
	end)
end

function mod:Show(msg, frame)
	-- set vertical position of the container frame
	if frame.trivial then
		frame.auras:SetPoint('BOTTOMLEFT', frame.health, 'BOTTOMLEFT',
			3, addon.sizes.frame.taurasOffset)
	else
		frame.auras:SetPoint('BOTTOMLEFT', frame.health, 'BOTTOMLEFT',
			self.db.profile.auras.auraXOffset, self.db.profile.auras.auraYOffset)
			-- addon.sizes.frame.aurasOffset)
	end
end

function mod:Hide(msg, frame)
	if frame.auras then
		frame.auras:Hide()
	end
end

-------------------------------------------------------------- event handlers --
function mod:COMBAT_LOG_EVENT_UNFILTERED(event, ...)
	local castTime, event, _, guid, name, _, _, targetGUID, targetName = ...
	if not guid then return end
	if not auraEvents[event] then return end
	if guid ~= UnitGUID('player') then return end

	--print(event..' from '..name..' on '..targetName)

	-- fetch the subject's nameplate
	local f = addon:GetNameplate(targetGUID, targetName)
	if not f or not f.auras then return end

	--print('(frame for guid: '..targetGUID..')')

	local spId = select(12, ...)

	if f.auras.spellIds[spId] then
		f.auras.spellIds[spId]:Hide()
	end
end

function mod:PLAYER_TARGET_CHANGED()
	self:UNIT_AURA('UNIT_AURA', 'target')
end

function mod:UPDATE_MOUSEOVER_UNIT()
	self:UNIT_AURA('UNIT_AURA', 'mouseover')
end

function mod:UNIT_AURA(event, unit)
	-- select the unit's nameplate	
	--unit = 'target' -- DEBUG
	local frame = addon:GetNameplate(UnitGUID(unit), nil)
	if not frame or not frame.auras then return end
	if frame.trivial and not self.db.profile.showtrivial then return end
	--unit = 'player' -- DEBUG

	local filter = 'PLAYER '
	if UnitIsFriend(unit, 'player') then
		filter = filter..'HELPFUL'
	else
		filter = filter..'HARMFUL'
	end

	for i = 0,40 do
		local name, _, icon, count, _, duration, expirationTime, _, _, _, spellId = UnitAura(unit, i, filter)
		name = name and strlower(name) or nil

		if  name and
		   (not self.db.profile.behav.useWhitelist or
		    (whitelist[spellId] or whitelist[name])) and
		   (duration >= self.db.profile.display.lengthMin) and
		   (self.db.profile.display.lengthMax == -1 or (
		   	duration > 0 and
		    duration <= self.db.profile.display.lengthMax))
		then
			local button = frame.auras:GetAuraButton(spellId, icon, count, duration, expirationTime)
			frame.auras:Show()
			frame.auras:SetPoint('BOTTOMLEFT', frame.health, 'BOTTOMLEFT',
			self.db.profile.auras.auraXOffset, self.db.profile.auras.auraYOffset)
			button:Show()
			button.used = true
		end
	end

	for _,button in pairs(frame.auras.buttons) do
		-- hide buttons that weren't used this update
		if not button.used then
			button:Hide()
		end

		button.used = nil
	end
end

function mod:WhitelistChanged()
	-- update spell whitelist
	whitelist = spelllist.GetImportantSpells(select(2, UnitClass("player")))
end
---------------------------------------------------- Post db change functions --
mod.configChangedFuncs = { runOnce = {} }
mod.configChangedFuncs.runOnce.enabled = function(val)
	if val then
		mod:Enable()
	else
		mod:Disable()
	end
end

---------------------------------------------------- initialisation functions --
function mod:GetOptions()
	return {
		enabled = {
			name = 'Show my auras',
			desc = 'Display auras cast by you on the current target\'s nameplate',
			type = 'toggle',
			order = 1,
			disabled = false
		},
		showtrivial = {
			name = 'Show on trivial units',
			desc = 'Show auras on trivial (half-size, lower maximum health) nameplates.',
			type = 'toggle',
			order = 3,
			disabled = function()
				return not self.db.profile.enabled
			end,
		},
		display = {
			name = 'Display',
			type = 'group',
			inline = true,
			disabled = function()
				return not self.db.profile.enabled
			end,
			order = 10,
			args = {
				pulsate = {
					name = 'Pulsate auras',
					desc = 'Pulsate aura icons when they have less than 5 seconds remaining.\nSlightly increases memory usage.',
					type = 'toggle',
					order = 5,
				},
				decimal = {
					name = 'Show decimal places',
					desc = 'Show decimal places (.9 to .0) when an aura has less than one second remaining, rather than just showing 0.',
					type = 'toggle',
					order = 8,
				},
				timerThreshold = {
					name = 'Timer threshold (s)',
					desc = 'Timer text will be displayed on auras when their remaining length is less than or equal to this value. -1 to always display timer.',
					type = 'range',
					order = 10,
					min = -1,
					softMax = 180,
					step = 1
				},
				lengthMin = {
					name = 'Effect length minimum (s)',
					desc = 'Auras with a total duration of less than this value will never be displayed. 0 to disable.',
					type = 'range',
					order = 20,
					min = 0,
					softMax = 60,
					step = 1
				},
				lengthMax = {
					name = 'Effect length maximum (s)',
					desc = 'Auras with a total duration greater than this value will never be displayed. -1 to disable.',
					type = 'range',
					order = 30,
					min = -1,
					softMax= 1800,
					step = 1
				},
				auraFontSize = {
					name = 'Aura font size',
					desc = '',
					type = 'range',
					order = 40,
					min = 1,
					softMax = 20,
					step = 0.5
				},
				auraTextPosition = {
					name = 'Aura timer position',
					desc = 'Choose the aura timer position.\n\n|cffff0000Reload of this to take effect, doing it in combat WILL brick the nameplates until reload.',
					type = 'select',
					values = PositionSelectList,
					order = 50
				},
				textYOffset = {
					name = 'Aura timer Y-offset',
					desc = 'Y-offset relative to the set position.',
					type = 'range',
					order = 60,
					min = -10,
					softMax = 20,
					step = 0.5
				},
				textXOffset = {
					name = 'Aura timer x-offset',
					desc = 'X-offset relative to the set position.',
					type = 'range',
					order = 70,
					min = -10,
					softMax = 20,
					step = 0.5
				},
			},
		},
		behav = {
			name = 'Behaviour',
			type = 'group',
			inline = true,
			disabled = function()
				return not self.db.profile.enabled
			end,
			order = 4,
			args = {
				useWhitelist = {
					name = 'Use whitelist',
					desc = 'Only display spells which your class needs to keep track of for PVP or an effective DPS rotation. Most passive effects are excluded.\n\n|cff00ff00You can use KuiSpellListConfig from Curse.com to customise this list.',
					type = 'toggle',
					order = 0,
				},
			},
		},
		auras = {
			name = 'Icons',
			type = 'group',
			inline = true,
			disabled = function()
				return not self.db.profile.enabled
			end,
			order = 5,
			args = {
				auraYOffset = {
					name = 'Aura Y-offset',
					desc = 'Y-Offset for Auras relative to health frame',
					type = 'range',
					order = 40,
					min = 15,
					softMax = 85,
					step = 0.5
				},
				auraXOffset = {
					name = 'Aura X-offset',
					desc = 'X-Offset for Auras relative to health frame',
					type = 'range',
					order = 50,
					min = -30,
					softMax = 30,
					step = 0.5
				},
				auraIconWidth = {
					name = 'Aura icon width',
					desc = 'Aura icon width in pixels',
					type = 'range',
					order = 60,
					min = 5,
					softMax = 60,
					step = 1
				},
				auraIconHeight = {
					name = 'Aura icon height',
					desc = 'Aura icon height in pixels',
					type = 'range',
					order = 70,
					min = 5,
					softMax = 60,
					step = 1
				}
			},
		},
	}
end

function mod:OnInitialize()
	self.db = addon.db:RegisterNamespace(self.moduleName, {
		profile = {
			enabled = true,
			showtrivial = false,
			display = {
				pulsate = true,
				decimal = true,
				timerThreshold = 60,
				lengthMin = 0,
				lengthMax = -1,
				auraFontSize = 9,
				auraTextPosition = 'TOPLEFT',
				textYOffset = 0,
				textXOffset = 0
			},
			behav = {
				useWhitelist = true,
			},
			auras = {
				auraYOffset = 10,
				auraXOffset = 0,
				auraIconWidth = 29,
				auraIconHeight = 20
			}
		}
	})

	addon:RegisterSize('frame', self.db.profile.auras.auraIconHeight) --14
	addon:RegisterSize('frame', self.db.profile.auras.auraIconWidth) --20
	addon:RegisterSize('frame', 'tauraHeight',  9)
	addon:RegisterSize('frame', 'tauraWidth',  15)
	addon:RegisterSize('frame', self.db.profile.auras.auraYOffset)
	addon:RegisterSize('frame', self.db.profile.auras.auraXOffset)
	addon:RegisterSize('frame', 'taurasOffset', 13)

	addon:InitModuleOptions(self)
	mod:SetEnabledState(self.db.profile.enabled)

	self:WhitelistChanged()
	spelllist.RegisterChanged(self, 'WhitelistChanged')
end

function mod:OnEnable()
	self:RegisterMessage('KuiNameplates_PostCreate', 'Create')
	self:RegisterMessage('KuiNameplates_PostShow', 'Show')
	self:RegisterMessage('KuiNameplates_PostHide', 'Hide')
	self:RegisterMessage('KuiNameplates_PostTarget', 'PLAYER_TARGET_CHANGED')

	self:RegisterEvent('UNIT_AURA')
	self:RegisterEvent('PLAYER_TARGET_CHANGED')
	self:RegisterEvent('UPDATE_MOUSEOVER_UNIT')
	self:RegisterEvent('COMBAT_LOG_EVENT_UNFILTERED')

	local _, frame
	for _, frame in pairs(addon.frameList) do
		if not frame.auras then
			self:Create(nil, frame.kui)
		end
	end
end

function mod:OnDisable()
	self:UnregisterEvent('UNIT_AURA')
	self:UnregisterEvent('PLAYER_TARGET_CHANGED')
	self:UnregisterEvent('UPDATE_MOUSEOVER_UNIT')
	self:UnregisterEvent('COMBAT_LOG_EVENT_UNFILTERED')

	local _, frame
	for _, frame in pairs(addon.frameList) do
		self:Hide(nil, frame.kui)
	end
end
