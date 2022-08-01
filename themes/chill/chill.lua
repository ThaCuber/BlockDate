local gfx <const> = playdate.graphics
local snd     <const> = playdate.sound
local disp    <const> = playdate.display

local dwidth <const>, dheight <const> = disp.getWidth(), disp.getHeight()

-- initialize image table for visual effect
local starsAnimation = gfx.imagetable.new('assets/images/stars')
local total_frames = starsAnimation:getLength()

print('chill theme selected!')
local scene = {

	-- set x and y locations of held block in UI for this theme
	heldPiece_x = 12,
	heldPiece_y = 5,
	
	bgImageTable = gfx.imagetable.new('assets/rainblock_images/bg.gif'),
	bgImageIndex = 1,
	skyImage = gfx.image.new('assets/rainblock_images/sky.png'),
	clouds1Image = gfx.image.new('assets/rainblock_images/clouds1.png'),
	clouds2Image = gfx.image.new('assets/rainblock_images/clouds2.png'),
	chill_music = loadMusic("glad_to_be_stuck_inside"),
	clouds1X = 0,
	clouds2X = 0,
	animationTimer = nil,
	
	setup = function(self)
		self.animationTimer = playdate.timer.new(500, function() self:nextFrame() end)
		self.animationTimer.repeats = true
		
		-- initialize font
		self.font = gfx.font.new("assets/fonts/playtris")
		gfx.setFont(self.font)
		text_width, text_height = gfx.getTextSize("0")
		
		-- initialize music
		currentSong = self.chill_music
		
		-- initialize sound effects
		comboSounds = {}
		for i=1, 4 do table.insert(comboSounds, loadSound("chill/lineClear"..i)) end
		dropSound = loadSound("chill/land")
		specialSound = loadSound("chill/lineClear4")
		holdSound = loadSound("chill/hold")
		spinSound = loadSound("chill/rotate")
		moveSound = loadSound("chill/shift")
	end,
	
	nextFrame = function(self)
		self.clouds1X = self.clouds1X + 0.24
		self.clouds2X = self.clouds2X + 0.51
		if self.clouds1X > 800 then
			self.clouds1X = 0
		end
		if self.clouds2X > 800 then
			self.clouds2X = 0
		end
		self.bgImageIndex = self.bgImageIndex + 1
		if self.bgImageIndex > self.bgImageTable:getLength() then
			self.bgImageIndex = 1
		end
	end,
	
	draw = function(self)
		self.skyImage:drawIgnoringOffset(0, 0)
		self.clouds1Image:drawIgnoringOffset(math.floor(self.clouds1X) - 800, 0)
		self.clouds1Image:drawIgnoringOffset(math.floor(self.clouds1X), 0)
		self.clouds2Image:drawIgnoringOffset(math.floor(self.clouds2X) - 800, 0)
		self.clouds2Image:drawIgnoringOffset(math.floor(self.clouds2X), 0)
		local bgImage = self.bgImageTable:getImage(self.bgImageIndex)
		bgImage:drawIgnoringOffset(0, 0)
		
		gfx.drawText("HOLD", (UITimer.value-5)*uiBlockSize, 2*uiBlockSize-1)
		gfx.drawText("NEXT", dwidth-(UITimer.value)*uiBlockSize, 2*uiBlockSize-1)
	end,
	
	drawScores = function(score)
		--draw scores
		gfx.drawText("SCORE", 265,190)
		gfx.drawText(math.floor(score), 265, 203)
	end,
	
	drawLevelInfo = function(level)
		--draw level info
		gfx.drawText("LEVEL", 60,190)
		if level < 10 then
			gfx.drawText(level, 120, 203)
		else
			gfx.drawText(level, 120 - text_width, 203)
		end
	end,
	
	drawHeldPiece = function(heldPiece)
		--draw held piece
		gfx.drawText("HOLD", (UITimer.value-5)*uiBlockSize, 2*uiBlockSize-1)
		
		if heldPiece then
			loopThroughBlocks(function(_, x, y)
				local block = pieceStructures[heldPiece][1][y][x]
				if block ~= ' ' then
					local acp = heldPiece ~= 1 and heldPiece ~= 2
					drawBlock('*', x+(UITimer.value-(acp and 3.5 or 3.9)), y+(acp and 4 or (heldPiece == 1 and 3.5 or 3)), uiBlockSize)
				end
			end)
		end
	end,
	
	visualEffect = function(message)
		-- visual effect to display message to player
		-- initialize our effect object here:
		local effect = {}
		effect.__index = effect
		
		effect.text = message
		effect.animation_frame = 1
		local textWidth, text_height = gfx.getTextSize(effect.text)
		effect.x = 20
		effect.y = 120
		
		-- timer to determine how long to display effect
		playdate.timer.new(2000,function() effect.dead = true end )
		
		-- update effect
		function effect:update()
			self.animation_frame = self.animation_frame + 1 
			if self.animation_frame > total_frames then self.animation_frame = 1 end
		end
		
		-- draw effect
		function effect:draw()
			starsAnimation:drawImage(self.animation_frame, self.x - 20, self.y)
			starsAnimation:drawImage(self.animation_frame, self.x + 20, self.y)
			starsAnimation:drawImage(self.animation_frame, self.x + 60, self.y)
			gfx.drawText(self.text, self.x, self.y)
		end
		
		-- return our effect object
		return effect		
	end
}

--[[
-- Define visual effect
class("Sash").extends()

local function setTimerEndCallback(timer, args, callback)
	if type(args) == "function" then
		callback = args
		args = {}
	end
	timer.timerEndedArgs = args
	timer.timerEndedCallback = callback
end

function Sash:init(text)
	self.text = text

	-- haha bad code go brr
	self.yTimer = Timer(125, 0, 40, ease.outBack)
	self.yTimer.discardOnCompletion = false
	local textWidth = gfx.getSystemFont("bold"):getTextWidth(text)
	setTimerEndCallback(self.yTimer, function()
		self.textPosTimer = Timer(250, -textWidth, textWidth/2, ease.outCubic)
		setTimerEndCallback(self.textPosTimer, function()
			timer.performAfterDelay(500, function()
				self.textPosTimer = Timer(250, 10+textWidth/2, dwidth, ease.inCubic)
				setTimerEndCallback(self.textPosTimer, function()
					self.yTimer = Timer(250, 40, 0, ease.inBack)
					setTimerEndCallback(self.yTimer, function() self.dead = true end)
				end)
			end)
		end)
	end)
end

function Sash:update() end

function Sash:draw()
	gfx.pushContext()
	if self.yTimer then
		gfx.fillRect(0, (dheight-self.yTimer.value)-5, dwidth, gfx.getSystemFont("bold"):getHeight()*2)
	end
	if self.textPosTimer then
		gfx.setImageDrawMode(darkMode and "fillBlack" or "fillWhite")
		gfx.drawText("*"..self.text.."*", self.textPosTimer.value, (dheight-gfx.getSystemFont("bold"):getHeight()*1.5)-5)
	end
	gfx.popContext()
end
]]


scene:setup()

return scene

