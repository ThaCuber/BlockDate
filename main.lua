-- MIT License

-- Copyright (c) 2022 @thacuber2a03

-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:

-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.

-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

import "CoreLibs/graphics"
import "CoreLibs/timer"
import "CoreLibs/crank"

import "pieces"
import "wallkickdata"

import "effects/endline"
import "effects/clearline"
import "effects/sash"

local gfx     <const> = playdate.graphics
local snd     <const> = playdate.sound
local geom    <const> = playdate.geometry
local time    <const> = playdate.timer
local data    <const> = playdate.datastore
local disp    <const> = playdate.display
local easings <const> = playdate.easingFunctions

local btn  <const> = playdate.buttonIsPressed
local btnp <const> = playdate.buttonJustPressed
local dwidth <const>, dheight <const> = disp.getWidth(), disp.getHeight()

---------------
-- Save data --
---------------

-- If there's no game data available make some
savedData = data.read("gamedata") or {}

local function loadData(key)
	return savedData[key]
end

local function saveData(key, value)
	savedData[key] = value
end

local function commitSaveData()
	-- pretty print cuz why not
	data.write(savedData, "gamedata", true)
end

----------------------
-- Global variables --
----------------------

gridXCount, gridYCount = 10, 18

pieceXCount, pieceYCount = 4, 4

-- grid offset
offsetX, offsetY = 13, 2

blockSize = 11

-- this looks so weird
	shake, sash, ghost,
	grid, darkMode,
	inverseRotation,
	music, sounds
=
	loadData("shake") or true, loadData("sash") or true, loadData("ghost") or true,
	loadData("grid") or false, loadData("darkMode") or false,
	loadData("inverseRotation") or false,
	loadData("music") or 1, loadData("sounds") or 1

------------------------
-- "Global" variables --
------------------------

local introRectT = time.new(100, 400, 0, easings.outCubic)

local highscore = loadData("highscore") or 0

-- t spin detection coming soon probably
local lastAction = ""

-----------
-- Utils --
-----------

local function random(min, max, float)
	math.randomseed(playdate.getSecondsSinceEpoch())

	if not min then return math.random() end
	if not max then max = min min = 1 end

	if not float then return math.random(min, max)
	else return min + (max - min) * math.random() end
end

SOUNDSDIR = "assets/sounds/"
local function loadSound(name)
	return assert(snd.sampleplayer.new(SOUNDSDIR..name))
end

-- not yet used but will use...
-- at some point
MUSICDIR = "assets/music/"
local function loadMusic(name)
	return assert(snd.fileplayer.new(MUSICDIR..name))
end

IMAGESDIR = "assets/images/"
local function loadImage(name)
	return assert(gfx.image.new(IMAGESDIR..name))
end

local function loadImagetable(name)
	return assert(gfx.imagetable.new(IMAGESDIR..name))
end

------------
-- Sounds --
------------

local comboSounds = {}
for i=1, 4 do table.insert(comboSounds, loadSound("combo"..i)) end
local function stopAllComboSounds()
	for i=1, 4 do
		if comboSounds[i]:isPlaying() then comboSounds[i]:stop() end
	end
end

local dropSound = loadSound("drop")
local tetrisSound = loadSound("tetris")
local holdSound = loadSound("hold")

local menuScrollSound = loadSound("menu-scroll")
local menuClickSound = loadSound("menu-click")

-- holy shit it finally was added
local bgmIntro = loadMusic("bgmintro")
local bgmLoop = loadMusic("bgmloop")

------------
-- images --
------------

local nextFrameImage = loadImage("next-frame")
local holdFrameImage = loadImage("hold-frame")

local crossmarkFieldImage = loadImage("crossmark-field")
local crossmarkImage = loadImage("crossmark")

local ghostBlockImagetable = loadImagetable("ghost-block/ghost-block")

------------------------------------------
-- Game related functions and variables --
------------------------------------------

local displayYPos = 0

local completedLines = 0
local combo, level = 0, 0
local levelIncreased = false

local lostY = 1
local lost = false

local clearLines, lines, sashes = {}, {}, {}

local holdDir = 0
local heldPiece

local pieceHasChanged = false

local UITimer
local inert = {}

local timer = 0
local timerLimit = 30
local score = 0
local scoreGoal = score

local function canPieceMove(testX, testY, testRotation)
	for y=1, pieceYCount do
		for x=1, pieceXCount do
			local testBlockX = testX + x
			local testBlockY = testY + y
			if not inert[testY+1] then return false end
			if pieceStructures[piece.type][testRotation+1][y][x] ~= ' ' and (
				testBlockX < 1 or testBlockX > gridXCount
				or testBlockY < 1 or testBlockY > gridYCount
				or inert[testBlockY][testBlockX] ~= " "
			) then
				return false
			end
		end
	end
	return true
end

local function newSequence()
	sequence = {}
	for i = 1, #pieceStructures do
		table.insert(sequence, random(#sequence + 1), i)
	end
end

local function newPiece(type)
	piece = {
		x = 3,
		y = 0,
		rotation = 0,
		type = type,
	}
	ghostPieceY = piece.y
	while canPieceMove(piece.x, ghostPieceY + 1, piece.rotation) do
		ghostPieceY += 1
	end
	pieceHasChanged = true
	if #sequence == 0 then newSequence() end
end

local function rotate(rotation)
	ghostPieceY = piece.y
	local testRotation = piece.rotation + rotation
	testRotation %= #pieceStructures[piece.type]

	-- Implementing this took too much brain energy from me :(
	local chosenWallKickTests = wallkickdata[(piece.type~=1 and 1 or 2)][piece.rotation+1][(rotation==1 and "cw" or "ccw")]
	for i=1, #chosenWallKickTests do
		local tx = piece.x+chosenWallKickTests[i][1]
		local ty = piece.y+chosenWallKickTests[i][2]
		if canPieceMove(tx, ty, testRotation) then
			piece.x = tx
			piece.y = ty
			piece.rotation = testRotation
			break
		end
	end

	while canPieceMove(piece.x, ghostPieceY + 1, piece.rotation) do
		ghostPieceY += 1
	end
end

local function move(direction)
	ghostPieceY = piece.y
	local testX = piece.x + direction

	if canPieceMove(testX, piece.y, piece.rotation) then
		piece.x = testX
	end

	while canPieceMove(piece.x, ghostPieceY + 1, piece.rotation) do
		ghostPieceY += 1
	end
end

local function holdDirection(dir)
	if holdDir == 0 or holdDir > 5 then move(dir) end
	holdDir += 1
end

local inputHandlers	= {
	upButtonDown = function()
		if not lost then
			local dist = 0
			while canPieceMove(piece.x, piece.y + 1, piece.rotation) do
				piece.y += 1
				dist += 1
			end
			dropSound:play()
			timer = timerLimit
			if shake then displayYPos = dist*1.25 end
		end
	end,
	-- Skip the O piece when rotating.
	AButtonDown = function()
		if not lost then if piece.type ~= 2 then rotate(inverseRotation and -1 or 1) end end
	end,
	BButtonDown = function()
		if not lost then if piece.type ~= 2 then rotate(inverseRotation and 1 or -1) end end
	end
}

local function reset()
	levelIncreased = false
	displayYPos = 0
	completedLines = 0
	combo, level = 1, 1
	lostY = 1
	lost = false
	clearLines, lines, sashes = {}, {}, {}
	holdDir = 0
	heldPiece = nil
	pieceHasChanged = false

	UITimer = time.new(500, -4, 8, easings.outCubic)

	inert = {}
	for y = 1, gridYCount do
		inert[y] = {}
		for x = 1, gridXCount do
			inert[y][x] = ' '
		end
	end

	playdate.inputHandlers.push(inputHandlers)

	newSequence()
	newPiece(table.remove(sequence))

	timer = 0
	score = 0
	scoreGoal = score
end

local function drawBlock(block, x, y)
	local rect = geom.rect.new(
		(x-1)*blockSize,
		(y-1)*blockSize,
		blockSize-1,
		blockSize-1
	)
	
	if grid then gfx[(block ~= " " and "fillRect" or "drawRect")](rect)
	elseif block ~= " " then gfx.fillRect(rect) end
end

local function drawTexturedBlock(image, x, y)
	image:draw((x-1)*blockSize, (y-1)*blockSize)
end

local function loopThroughBlocks(func)
	for y=1, pieceYCount do
		for x=1, pieceXCount do
			func(pieceStructures[piece.type][piece.rotation+1][y][x], x, y)
		end
	end
end

local function addPieceToInertGrid()
	loopThroughBlocks(function(block, x, y)
		if block ~= ' ' then inert[piece.y + y][piece.x + x] = block end
	end)
end

reset()

local function updateGame()
	if not lost then
		local crankTicks = playdate.getCrankTicks(4)
		if crankTicks ~= 0 then rotate(crankTicks) end

		if scoreGoal ~= score then
			score += (scoreGoal - score) * .25
			if scoreGoal - score < 1 then score = scoreGoal end
		end

		if scoreGoal > highscore then
			saveData("highscore", scoreGoal)
			highscore = scoreGoal
		end

		timerLimit = 30
		if btn("down") and not pieceHasChanged then
			timerLimit = 0
		elseif not btn("down") then
			pieceHasChanged = false
		end

		if btn("right") then holdDirection(1)
		elseif btn("left") then holdDirection(-1)
		else holdDir = 0 end

		if (btn("a") and btn("b")) and not hasHeldPiece then
			local nextType
			if not heldPiece then
				heldPiece = piece.type
				nextType = table.remove(sequence)
			else
				local temp = heldPiece
				heldPiece = piece.type
				nextType = temp
			end
			newPiece(nextType)
			hasHeldPiece = true
			holdSound:play()
		end

		timer += level
		if timer >= timerLimit then
			timer = 0
			
			local testY = piece.y + 1

			if canPieceMove(piece.x, testY, piece.rotation) then
				piece.y = testY
			else
				addPieceToInertGrid()

				-- Find complete rows
				local completedLine = false
				local clearedLines = 0
				for y = 1, gridYCount do

					local complete = true
					for x = 1, gridXCount do
						if inert[y][x] == ' ' then
							complete = false
							break
						end
					end

					if complete then
						completedLine = true

						completedLines += 1
						if completedLines ~= 0 and completedLines%10 == 0 and not levelIncreased then
							levelIncreased = true
							level += 1
						elseif completedLines%10 ~= 0 then levelIncreased = false end

						table.insert(clearLines, ClearLine(y+1))
						for removeY = y, 2, -1 do
							for removeX = 1, gridXCount do
								inert[removeY][removeX] =
								inert[removeY - 1][removeX]
							end
						end

						for removeX = 1, gridXCount do inert[1][removeX] = " " end

						scoreGoal += 10 * combo

						--synth:setWaveform(sound.kWaveSquare)
						--synth:setADSR(0, 0, 0.5, 0.05)
						--synth:playNote("C5", 0.5, 0.001)
						stopAllComboSounds()
						comboSounds[math.min(combo, 4)]:play()
						combo += 1

						clearedLines += 1
					end
				end

				local allclear = true
				for y = 1, gridYCount do
					for x = 1, gridXCount do
						if inert[y][x] ~= " " then
							-- Exit both loops if found a block
							allclear = false
							break
						end
					end
					-- I said both
					if not allclear then break end
				end


				if clearedLines >= 4 then -- unlikely to be bigger than 4 but idc
					stopAllComboSounds()
					tetrisSound:play()
					if sash then table.insert(sashes, Sash("4-line Clear!")) end
				end

				if allclear and sash then
					scoreGoal += 25 * combo
					table.insert(sashes, Sash("All clear!"))
				end

				if not completedLine then
					dropSound:play()
					combo = 1
				end

				newPiece(table.remove(sequence))
				hasHeldPiece = false

				if not canPieceMove(piece.x, piece.y, piece.rotation) then
					timer = 0
					lost = true
					UITimer = time.new(500, 8, -4, easings.outCubic)
					playdate.inputHandlers.pop()
				end -- check if lost
			end -- complete a row
		end -- timer is over timerLimit
	else
		if not e then
			inert[lostY] = {}
			for i=1, gridXCount do inert[lostY][i] = ' ' end
			table.insert(lines, EndLine((lostY-1)+offsetY))

			if lostY < gridYCount then lostY += 1
			else e = true end
		else
			if #lines == 0 then
				e = false
				commitSaveData()
				reset()
			end
		end
	end -- state machine
end

local function drawGame()
	gfx.pushContext()

	if darkMode then
		gfx.setColor(gfx.kColorWhite)
		gfx.setImageDrawMode("fillWhite")
	else
		gfx.setColor(gfx.kColorBlack)
		gfx.setImageDrawMode("copy")
	end

	gfx.clear(darkMode and gfx.kColorBlack or gfx.kColorWhite)

	if displayYPos ~= 0 then
		displayYPos+=((0-displayYPos)*0.25)
		gfx.setDrawOffset(0,displayYPos)
	end

	local function updateEffect(t,i,e)
		if e.dead then
			pcall(function() table.remove(t, i) end)
		else
			e:update()
			e:draw()
		end
	end

	for i,l in ipairs(lines) do updateEffect(lines,i,l) end

	if not grid then
		gfx.drawRect(
			offsetX*blockSize,    offsetY*blockSize,
			gridXCount*blockSize, gridYCount*blockSize
		)
	end

	for y = 1, gridYCount do
		for x = 1, gridXCount do
			drawBlock(inert[y][x], x + offsetX, y + offsetY)
		end
	end

	loopThroughBlocks(function(_, x, y)
		if not lost then
			local block = pieceStructures[piece.type][piece.rotation+1][y][x]
			if block ~= ' ' then
				drawBlock(block, x + piece.x + offsetX, y + piece.y + offsetY)
				if ghost then
					local _, millis = playdate.getSecondsSinceEpoch()
					drawTexturedBlock(
						ghostBlockImagetable:getImage(1+math.floor(millis/100%#ghostBlockImagetable)),
						x + piece.x + offsetX, y + ghostPieceY + offsetY
					)
				end
			end
		end
	end)

	for i, l in ipairs(clearLines) do updateEffect(clearLines,i,l) end

	gfx.setDrawOffset(0,0)

	nextFrameImage:drawCentered(((dwidth+UITimer.value)-(UITimer.value+1)*blockSize)+2, 5*blockSize-1)
	loopThroughBlocks(function(_, x, y)
		local nextPiece = sequence[#sequence]
		local block = pieceStructures[nextPiece][1][y][x]
		if block ~= ' ' then
			local acp = nextPiece ~= 1 and nextPiece ~= 2
			drawBlock('*', x+(dwidth/blockSize)-(UITimer.value+(acp and 1.5 or 2)), y+(acp and 4 or (nextPiece == 2 and 3 or 3.5)))
		end
	end)

	holdFrameImage:drawCentered(UITimer.value*blockSize-1, 5*blockSize-1)
	if heldPiece then
		loopThroughBlocks(function(_, x, y)
			local block = pieceStructures[heldPiece][1][y][x]
			if block ~= ' ' then
				local acp = heldPiece ~= 1 and heldPiece ~= 2
				drawBlock('*', x+(UITimer.value-(acp and 1.5 or 2)), y+(acp and 4 or (heldPiece == 2 and 3 or 3.5)))
			end
		end)
	end

	local bold = gfx.getSystemFont("bold")
	gfx.drawText("*Score*", (UITimer.value-2)*blockSize, 9*blockSize)
	gfx.drawText("*"..math.floor(score).."*", (UITimer.value)*blockSize-bold:getTextWidth(math.floor(score))/2, 11*blockSize)
	gfx.drawText("*Highscore*", (UITimer.value-3.5)*blockSize, 13*blockSize)
	gfx.drawText("*"..highscore.."*", (UITimer.value)*blockSize-bold:getTextWidth(highscore)/2, 15*blockSize)

	gfx.drawText("*Level*", dwidth-(UITimer.value+2)*blockSize, 9*blockSize)
	gfx.drawText("*"..level.."*", (dwidth+bold:getTextWidth(level)/2)-(UITimer.value+0.5)*blockSize, 11*blockSize)
	gfx.drawText("*Lines*", dwidth-(UITimer.value+2)*blockSize, 13*blockSize)
	gfx.drawText("*"..completedLines.."*", (dwidth-bold:getTextWidth(completedLines)/2)-(UITimer.value)*blockSize, 15*blockSize)

	if #sashes > 0 then updateEffect(sashes, #sashes, sashes[#sashes]) end

	gfx.fillRect(0, 0, 400, introRectT.value)

	gfx.popContext()

	time.updateTimers()
end

local _update, _draw = updateGame, drawGame

local patternTimer

local patterns = {
	{0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0, 0, 0, 0, 0, 0, 0, 0}, -- white
	{0xFF, 0xDD, 0xFF, 0x77, 0xFF, 0xDD, 0xFF, 0x77, 0, 34, 0, 136, 0, 34, 0, 136}, -- lightgray 1
	{0x77, 0x77, 0xDD, 0xDD, 0x77, 0x77, 0xDD, 0xDD, 136, 136, 34, 34, 136, 136, 34, 34}, -- lightgray 2
	{0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 170, 85, 170, 85, 170, 85, 170, 85}, -- gray
}

local menuOpen = false
local bold = gfx.getSystemFont("bold")
local menuYTimer, menuWidth

local function closeMenu()
	-- Sorry, I love back easing XD
	menuYTimer = time.new(250, dheight/2, dheight, easings.inBack)
	patternTimer = time.new(250, #patterns, 1,easings.inBack)
end

local menu = {
	{
		name = "Continue",
		type = "button",
		onpress = function()
			closeMenu()
			menuOpen = false
		end,
	},
	{
		name = "Ghost",
		type = "crossmark",
		state = ghost,
		ontoggle = function(val)
			ghost = val
			saveData("ghost", ghost)
		end,
	},
	{
		name = "Shake",
		type = "crossmark",
		state = shake,
		ontoggle = function(val)
			shake = val
			saveData("shake", shake)
		end,
	},
	{
		name = "Sash",
		type = "crossmark",
		state = sash,
		ontoggle = function(val)
			sash = val
			saveData("sash", sash)
		end,
	},
	{
		name = "Grid",
		type = "crossmark",
		state = grid,
		ontoggle = function(val)
			grid = val
			saveData("grid", grid)
		end,
	},
	{
		name = "Dark mode",
		type = "crossmark",
		state = darkMode,
		ontoggle = function(val)
			darkMode = val
			saveData("darkMode", darkMode)
		end,
	},
	{
		name = "Invert Rotation",
		type = "crossmark",
		state = inverseRotation,
		ontoggle = function(val)
			inverseRotation = val
			saveData("inverseRotation", inverseRotation)
		end
	},
	{
		name = "Music",
		type = "slider",
		min = 0,
		max = 1,
		value = music,
		onchange = function(val)
			music = val
			saveData("music", music)
		end,
	},
	{
		name = "Sound",
		type = "slider",
		min = 0,
		max = 1,
		value = sounds,
		onchange = function(val)
			sounds = val
			saveData("sounds", sounds)
		end,
	}
}

local menuHeight = #menu*bold:getHeight()

function updateMenu()
	if menuYTimer.value == dheight/2 then
		if btnp("down") then
			menuScrollSound:play()
			menuCursor += 1
		elseif btnp("up") then
			menuCursor -= 1
			menuScrollSound:play()
		end
		menuCursor %= #menu
		
		local menuItem = menu[menuCursor+1]
		if btnp("a") then
			if menuItem.type == "button" then
				menuItem.onpress()
				menuClickSound:play()
			elseif menuItem.type == "crossmark" then
				menuItem.state = not menuItem.state
				menuItem.ontoggle(menuItem.state)
				menuClickSound:play()
			end
			
			commitSaveData()
		end

		if menuItem.type == "slider" then
			if btn("right") then
				menuItem.value = math.max(menuItem.min, math.min(menuItem.value + menuItem.max / 50, menuItem.max))
				menuItem.onchange(menuItem.value)
				commitSaveData()
			elseif btn("left") then
				menuItem.value = math.max(menuItem.min, math.min(menuItem.value - menuItem.max / 50, menuItem.max))
				menuItem.onchange(menuItem.value)
				commitSaveData()
			end
		end
	end

	if math.abs(dheight-menuYTimer.value) < 0.5 then
		playdate.inputHandlers.push(inputHandlers)
		_update = updateGame
		_draw = drawGame
	end
	time.updateTimers()
end

function drawMenu()
	gfx.pushContext()
  backgroundImage:draw(0, 0)
  gfx.setPattern(patterns[math.floor(patternTimer.value)])
  gfx.fillRect(0, 0, dwidth, dheight)
  gfx.setPattern(patterns[1])

  local rect = geom.rect.new(
  	dwidth/2-(menuWidth/2+10),
  	menuYTimer.value-(menuHeight/2+10),
  	menuWidth+20, menuHeight+20
  )
  local rad = 5
	gfx.setColor(gfx.kColorWhite)
	gfx.fillRoundRect(rect, rad)
	gfx.setColor(gfx.kColorBlack)
	gfx.drawRoundRect(rect, rad)

	local bheight = bold:getHeight()
	for i, v in ipairs(menu) do
		if v.type == "crossmark" then
			gfx.drawText("*"..v.name.."*", dwidth/2-menuWidth/2 + 20, menuYTimer.value-menuHeight/2+((i-1)*bheight)+1)
			-- _ is a throwaway variable. Just using it to get cheight.
			local _, cheight = crossmarkFieldImage:getSize()
			local pos = geom.point.new(
				(dwidth/2-menuWidth/2)+8,--bold:getTextWidth(v.name)/2+5,
				menuYTimer.value-menuHeight/2+((i-1)*bheight)+cheight/2
			)
			crossmarkFieldImage:drawCentered(pos:unpack())
			if v.state then crossmarkImage:drawCentered(pos:unpack()) end
		elseif v.type == "slider" then
			gfx.drawText("*"..v.name.."*", dwidth/2-bold:getTextWidth(v.name)/2, menuYTimer.value-menuHeight/2+((i-1)*bheight))
			gfx.setColor(gfx.kColorXOR)
			gfx.fillRect(
				dwidth/2-menuWidth/2,
				menuYTimer.value-menuHeight/2+((i-1)*bheight)-1,
				v.value*menuWidth,
				bold:getHeight()
			)
			gfx.setColor(gfx.kColorBlack)
		else
			gfx.drawText("*"..v.name.."*", dwidth/2-menuWidth/2, menuYTimer.value-menuHeight/2+((i-1)*bheight)+1)
		end
	end

	local menuItem = menu[menuCursor+1]
	local x = dwidth/2-menuWidth/2
	local w = bold:getTextWidth(menu[menuCursor+1].name)
	if menuItem.type == "crossmark" then
		x = dwidth/2-menuWidth/2 + 20
	elseif menuItem.type == "slider" then
		w = menuWidth
	end
	gfx.drawRect(
		x, ((menuYTimer.value-menuHeight/2)+menuCursor*bheight)-2.5, w, bheight, 2
	)
	gfx.popContext()
end

----------------------------
-- Playdate-related stuff --
----------------------------

playdate.getSystemMenu():addMenuItem("options", function()
	menuOpen = not menuOpen
	if not menuOpen then closeMenu()
	else
		bold = gfx.getSystemFont("bold")
		menuYTimer = time.new(250, 0, dheight/2, easings.outBack)
		menuHeight = #menu*bold:getHeight()
		local longestString = ""
		for k, v in pairs(menu) do
			if #v.name > #longestString then
				longestString = v.name
			end
		end

		-- playdate.graphics.image:getSize() returns two values. By using it like this,
		-- I am taking the first value and discarding the rest,
		-- the first value being the width, which is what i need.
		menuWidth = bold:getTextWidth(longestString) + crossmarkFieldImage:getSize()
		menuCursor = 1

		backgroundImage = gfx.image.new(dwidth, dheight)
		gfx.pushContext(backgroundImage)
		drawGame()
		gfx.popContext()

		playdate.inputHandlers.pop()
		patternTimer = time.new(250, 1, #patterns, easings.outBack)
	end
	_update = updateMenu
	_draw = drawMenu
end)

bgmIntro:play()

function playdate.update()
	if not bgmIntro:isPlaying() and not bgmLoop:isPlaying() then
		bgmLoop:play(0)
	end
	bgmIntro:setVolume(music-(menuOpen and 0.5 or 0))
	bgmLoop:setVolume(music-(menuOpen and 0.5 or 0))
	for i,v in ipairs(snd.playingSources()) do
		if tostring(v):find("sampleplayer") then
			v:setVolume(sounds)
		end
	end
	_update()
	_draw()
end

function playdate.gameWillTerminate() commitSaveData() end

function playdate.deviceWillSleep() commitSaveData() end

-----------
-- Debug --
-----------

function playdate.keyPressed(key)
	if key == "L" then
		for i=1, 4 do table.remove(inert) end
		for i=1, 4 do
			table.insert(inert, (function()
				local almostFull = {}
				for i=1, gridXCount - 1 do
					table.insert(almostFull, '*')
				end
				table.insert(almostFull, ' ')
				return almostFull
			end)())
		end
	elseif key == "T" then
		-- Generate a TSpin scenario
		for i=1, 5 do table.remove(inert) end
		table.insert(inert, {"*", "*", "*", " ", " ", " ", " ", "*", "*", "*"})
		table.insert(inert, {"*", "*", "*", "*", " ", " ", "*", "*", "*", "*"})
		table.insert(inert, {"*", "*", "*", "*", " ", " ", "*", "*", "*", "*"})
		table.insert(inert, {"*", "*", "*", "*", " ", " ", "*", "*", "*", "*"})
		table.insert(inert, {"*", "*", "*", " ", " ", " ", "*", "*", "*", "*"})
	end
end