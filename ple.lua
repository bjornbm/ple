-- Copyright (c) 2019  Phil Leblanc  -- see LICENSE file

------------------------------------------------------------------------
--[[  ple - a Pure Lua Editor

editor actions:	see table editor.action
key bindings:	see table editor.bindings

configuration:
the editor can be configured / customized with a Lua file loaded at
initialization. The configuration file is looked for in sequence at the 
following locations:
	- the file which pathname is in the environment variable PLE_INIT
	- ./ple_init.lua
	- ~/.config/ple/ple_init.lua
The first file found, if any, is loaded. 

(see https://github.com/philanc/ple  -  License: MIT)

]]

-- some local definitions (used by the module term and/or by the editor

local strf = string.format
local byte, char, rep = string.byte, string.char, string.rep
local yield = coroutine.yield

local repr = function(x) return strf("%q", tostring(x)) end
local function max(x, y) if x < y then return y else return x end end 
local function min(x, y) if x < y then return x else return y end end 

local function pad(s, w) -- pad a string to fit width w
	if #s >= w then return s:sub(1,w) else return s .. rep(' ', w-#s) end
end

local function lines(s)
	-- split s into a list of lines
	lt = {}
	s = s .. "\n"
	for l in string.gmatch(s, "(.-)\r?\n") do table.insert(lt, l) end
	return lt
end	
	

local function readfile(fn)
	-- read file with filename 'fn' as a list of lines
	local fh, errm = io.open(fn)
	if not fh then return nil, errm end
	local ll = {}
	for l in fh:lines() do table.insert(ll, l) end
	fh:close()
	return ll
end

local function fileexists(fn)
	-- check if file 'fn' exists and can be read. return true or nil
	if not fn then return nil end
	local fh = io.open(fn)
	if not fh then return nil end	
	fh:close()
	return true
end

------------------------------------------------------------------------
-- term:  module plterm is preloaded below to enable delivering
--        ple as a single file

package.preload.plterm = function()
--[[  

plterm - Pure Lua ANSI Terminal functions - unix only

This module assumes the tty is in raw mode. 
It provides functions based on stty (so available on unix) 
to save, set and restore tty modes.

Module functions:

clear()     -- clear screen
cleareol()  -- clear to end of line
golc(l, c)  -- move the cursor to line l, column c
up(n)
down(n)
right(n)
left(n)     -- move the cursor by n positions (default to 1)
color(f, b, m)  
            -- change the color used to write characters
		(foreground color, background color, modifier)
		see term.colors
hide()
show()      -- hide or show the cursor
save()
restore()   -- save and restore the position of the cursor
reset()     -- reset the terminal (colors, cursor position)

input()     -- input iterator (coroutine-based)
		return a "next key" function that can be iteratively called 
		to read a key (escape sequences returned by function keys 
		are parsed)
rawinput()  -- same, but escape sequences are not parsed.
getcurpos() -- return the current position of the cursor
getscrlc()  -- return the dimensions of the screen 
               (number of lines and columns)
keyname()   -- return a printable name for any key
		- key names in term.keys for function keys,
		- control characters are represented as "^A"
		- the character itself for other keys

tty mode management functions

setrawmode()       -- set the terminal in raw mode
setsanemode()      -- set the terminal in a default "sane mode"
savemode()         -- get the current mode as a string
restoremode(mode)  -- restore a mode saved by savemode()

License: BSD
https://github.com/philanc/plterm

-- just in case, a good ref on ANSI esc sequences:   
https://en.wikipedia.org/wiki/ANSI_escape_code
(in the text, "CSI" is "<esc>[")

]]

-- some local definitions

local strf = string.format
local byte, char, rep = string.byte, string.char, string.rep
local yield = coroutine.yield

local repr = function(x) return strf("%q", tostring(x)) end


------------------------------------------------------------------------

local out = io.write

local function outf(...) 
	-- write arguments to stdout, then flush.
	io.write(...); io.flush()
end

local function outdbg(x, sep) 
	out(repr(x):sub(2, -2))
	if sep then out(sep) end
	io.flush() 
end

-- following definitions (from term.clear to term.restore) are
-- based on public domain code by Luiz Henrique de Figueiredo 
-- http://lua-users.org/lists/lua-l/2009-12/msg00942.html

local term={ -- the plterm module

	out = out,
	outf = outf,
	outdbg = outdbg,
	clear = function() out("\027[2J") end,
	cleareol = function() out("\027[K") end,
	golc = function(l,c) out("\027[",l,";",c,"H") end,
	up = function(n) out("\027[",n or 1,"A") end,
	down = function(n) out("\027[",n or 1,"B") end,
	right = function(n) out("\027[",n or 1,"C") end,
	left = function(n) out("\027[",n or 1,"D") end,
	color = function(f,b,m) 
	    if m then out("\027[",f,";",b,";",m,"m")
	    elseif b then out("\027[",f,";",b,"m")
	    else out("\027[",f,"m") end 
	end,
	-- hide / show cursor
	hide = function() out("\027[?25l") end,
	show = function() out("\027[?25h") end,
	-- save/restore cursor position
	save = function() out("\027[s") end,
	restore = function() out("\027[u") end,
	-- reset terminal (clear and reset default colors)
	reset = function() out("\027c") end,
}

term.colors = {
	default = 0,
	-- foreground colors
	black = 30, red = 31, green = 32, yellow = 33, 
	blue = 34, magenta = 35, cyan = 36, white = 37,
	-- backgroud colors
	bgblack = 40, bgred = 41, bggreen = 42, bgyellow = 43,
	bgblue = 44, bgmagenta = 45, bgcyan = 46, bgwhite = 47,
	-- attributes
	reset = 0, normal= 0, bright= 1, bold = 1, reverse = 7,
}

------------------------------------------------------------------------
-- key input

term.keys = { -- key code definitions
	unknown = 0x10000,
	esc = 0x1b,
	del = 0x7f,
	kf1 = 0xffff,  -- 0xffff-0
	kf2 = 0xfffe,  -- 0xffff-1
	kf3 = 0xfffd,  -- ...
	kf4 = 0xfffc,
	kf5 = 0xfffb,
	kf6 = 0xfffa,
	kf7 = 0xfff9,
	kf8 = 0xfff8,
	kf9 = 0xfff7,
	kf10 = 0xfff6,
	kf11 = 0xfff5,
	kf12 = 0xfff4,
	kins  = 0xfff3,
	kdel  = 0xfff2,
	khome = 0xfff1,
	kend  = 0xfff0,
	kpgup = 0xffef,
	kpgdn = 0xffee,
	kup   = 0xffed,
	kdown = 0xffec,
	kleft = 0xffeb,
	kright = 0xffea,
}

local keys = term.keys

--special chars (for parsing esc sequences)
local ESC, LETO, LBR, TIL= 27, 79, 91, 126  --  esc, [, ~

local isdigitsc = function(c) 
	-- return true if c is the code of a digit or ';'
	return (c >= 48 and c < 58) or c == 59
end

--ansi sequence lookup table
local seq = {
	['[A'] = keys.kup,
	['[B'] = keys.kdown,
	['[C'] = keys.kright,
	['[D'] = keys.kleft,

	['[2~'] = keys.kins,
	['[3~'] = keys.kdel,
	['[5~'] = keys.kpgup,
	['[6~'] = keys.kpgdn,
	['[7~'] = keys.khome,  --rxvt
	['[8~'] = keys.kend,   --rxvt
	['[1~'] = keys.khome,  --linux
	['[4~'] = keys.kend,   --linux
	['[11~'] = keys.kf1,
	['[12~'] = keys.kf2,
	['[13~'] = keys.kf3,
	['[14~'] = keys.kf4,
	['[15~'] = keys.kf5,
	['[17~'] = keys.kf6,
	['[18~'] = keys.kf7,
	['[19~'] = keys.kf8,
	['[20~'] = keys.kf9,
	['[21~'] = keys.kf10,
	['[23~'] = keys.kf11,
	['[24~'] = keys.kf12,

	['OP'] = keys.kf1,   --xterm
	['OQ'] = keys.kf2,   --xterm
	['OR'] = keys.kf3,   --xterm
	['OS'] = keys.kf4,   --xterm
	['[H'] = keys.khome, --xterm
	['[F'] = keys.kend,  --xterm

	['[[A'] = keys.kf1,  --linux
	['[[B'] = keys.kf2,  --linux
	['[[C'] = keys.kf3,  --linux
	['[[D'] = keys.kf4,  --linux
	['[[E'] = keys.kf5,  --linux

	['OH'] = keys.khome, --vte
	['OF'] = keys.kend,  --vte
	
}

local getcode = function() return byte(io.read(1)) end

term.input = function()
	-- return a "read next key" function that can be used in a loop
	-- the "next" function blocks until a key is read
	-- it returns ascii code for all regular keys, or a key code
	-- for special keys (see term.keys)
	-- (this function assume the tty is already in raw mode)
	return coroutine.wrap(function()
		local c, c1, c2, ci, s
		while true do
			c = getcode()
			if c ~= ESC then -- not a seq, yield c
				yield(c) 
				goto continue
			end 
			c1 = getcode()
			if c1 == ESC then -- esc esc [ ... sequence
				yield(ESC)
				-- here c still contains ESC, read a new c1
				c1 = getcode() -- and carry on ...
			end
			if c1 ~= LBR and c1 ~= LETO then -- not a valid seq
				yield(c) ; yield(c1)
				goto continue
			end
			c2 = getcode()
			s = char(c1, c2)
			if c2 == LBR then -- esc[[x sequences (F1-F5 in linux console)
				s = s .. char(getcode())
			end
			if seq[s] then 
				yield(seq[s])
				goto continue
			end
			if not isdigitsc(c2) then
				yield(c) ; yield(c1) ; yield(c2)
				goto continue
			end
			while true do
				ci = getcode()
				s = s .. char(ci)
				if ci == TIL then 
					if seq[s] then
						yield(seq[s])
						goto continue
					else
						-- valid but unknown sequence - ignore it
						yield(keys.unknown)
						goto continue
					end
				end
				if not isdigitsc(ci) then
					-- not a valid seq. return all the chars
					yield(ESC)
					for i = 1, #s do yield(byte(s, i)) end
					goto continue
				end
			end--while
			-- assume c is a regular char, return its ascii code
			::continue::
		end
	end)--coroutine
end--input()

term.rawinput = function()
	-- return a "read next key" function that can be used in a loop
	-- the "next" function blocks until a key is read
	-- it returns ascii code for all keys
	-- (this function assume the tty is already in raw mode)
	return coroutine.wrap(function()
		local c
		while true do
			c = getcode()
			yield(c) 
		end
	end)--coroutine
end--rawinput()

term.getcurpos = function()
	-- return current cursor position (line, column as integers)
	--
	outf("\027[6n") -- report cursor position. answer: esc[n;mR
	local c, i = 0, 0
	local s = ""
	c = getcode(); if c ~= ESC then return nil end
	c = getcode(); if c ~= LBR then return nil end
	while true do
		i = i + 1
		if i > 8 then return nil end
		c = getcode()
		if c == byte'R' then break end
		s = s .. char(c)
	end
	-- here s should be n;m
	local n, m = s:match("(%d+);(%d+)")
	if not n then return nil end
	return tonumber(n), tonumber(m)
end

term.getscrlc = function()
	-- return current screen dimensions (line, coloumn as integers)
	term.save()
	term.down(999); term.right(999)
	local l, c = term.getcurpos()
	term.restore()
	return l, c
end

term.keyname = function(c)
	for k, v in pairs(keys) do 
		if c == v then return k end
	end
	if c < 32 then return "^" .. char(c+64) end
	if c < 256 then return char(c) end
	return tostring(c)
end

------------------------------------------------------------------------
-- poor man's tty mode management, based on stty
-- (better use slua linenoise extension if available)


-- use the following to define a non standard stty location
-- eg.:  stty = "/opt/busybox/bin/stty"
-- 
local stty = "stty" -- use the default stty

term.setrawmode = function()
	return os.execute(stty .. " raw -echo 2> /dev/null")
end

term.setsanemode = function()
	return os.execute(stty .. " sane")
end

term.savemode = function()
	local fh = io.popen(stty .. " -g")
	local mode = fh:read('a')
	local succ, e, msg = fh:close()
	return succ and mode or nil, e, msg
end

term.restoremode = function(mode)
	return os.execute(stty .. " " .. mode)
end

return term 

end --package.preload.plterm

local term = require "plterm"


------------------------------------------------------------------------
-- EDITOR


-- some local definitions

-- the following is defined at the beginning of module term, above.
-- local out, outf, outdbg = term.out, term.outf, term.outdbg

local go, cleareol, color = term.golc, term.cleareol, term.color
local out, outf = term.out, term.outf
local col, keys = term.colors, term.keys
local flush = io.flush

	
------------------------------------------------------------------------
-- global objects and constants

local tabln = 8
local EOL = char(187) -- >>, indicate more undisplayed chars in s
local NDC = char(183) -- middledot, used for non-displayable latin1 chars
local EOT = '~'  -- used to indicate that we are past the end of text

-- editor is the global editor object
editor = {
	quit = false, -- set to true to quit editor_loop()
	nextk = term.input(), -- the "read next key" function
	buflist = {},  -- list of buffers
	bufindex = 0,  -- index of current buffer
	macrorec = false,	-- currently recording a macro
	macroseq = {},		-- current macro sequence of action
}

-- buf is the current buffer
-- this is the same object as editor.buflist[editor.bufindex]
local buf = {}  


-- style functions

editor.style = {
	normal = function() color(col.normal) end, 
	status = function() color(col.red, col.bold) end, 
	msg = function() color(col.normal); color(col.green) end, 
	sel = function() color(col.magenta, col.bold) end, 
	bckg = function() color(col.black, col.bgyellow) end, 
}

local style = editor.style


-- dialog functions

function editor.msg(m)
	-- display a message m on last screen line
	m = pad(m, editor.scrc)
	go(editor.scrl, 1); cleareol(); style.msg()
	out(m); style.normal(); flush()
end

function editor.readstr(prompt)
	-- display prompt, read a string on the last screen line
	-- [read only ascii or latin1 printable chars - no tab]
	-- [ no edition except bksp ]
	-- if ^G then return nil
	local s = ""
	editor.msg(prompt)
	while true do
		go(editor.scrl, #prompt+1); cleareol(); outf(s)	-- display s
		k = editor.nextk()
		if (k >= 32 and k <127) or (k >=160 and k < 256) then
			s = s .. char(k) 
		elseif k == 8 or k == keys.del then -- backspace
			s = s:sub(1, -2)
		elseif k == 13 then return s  -- return
		elseif k == 7 then return nil -- ^G - abort
		else -- ignore all other keys
		end
	end--while
end --readstr

function editor.readchar(prompt, charpat)
	-- display prompt on the last screen line, read a char
	-- if ^G then return nil
	-- return the key as a char only if it matches charpat
	-- ignore all non printable ascii keys and non matching chars
	editor.msg(prompt)
	editor.redisplay(buf) -- ensure cursor stays in buf
	while true do
		k = editor.nextk()
		if k == 7 then return nil end -- ^G - abort
		if (k < 127) then
			local ch = char(k)
			if ch:match(charpat) then return ch end
		end
		-- ignore all other keys
	end--while
end --readkey

function editor.status(m)
	-- display a status string on top screen line
	m = pad(m, editor.scrc)
	go(1, 1); cleareol(); style.status()
	out(m); style.normal(); flush()
end

local dbgs = "::"
function editor.dbg(s, ...)
	dbgs = strf(s, ...)
end
	

function editor.statusline()
	local s = strf("cur=%d,%d ", buf.ci, buf.cj)
	if buf.si then s = s .. strf("sel=%d,%d ", buf.si, buf.sj) end
	-- uncomment the following for debug purposes
--~ 	s = s .. strf("li=%d ", buf.li)
--~ 	s = s .. strf("hs=%d ", buf.hs)
--~ 	s = s .. strf("ual=%d ", #buf.ual)
--~ 	s = s .. strf("buf=%d ", editor.bufindex)
	s = s .. strf("[%s] ", buf.filename or "unnamed")
	s = s .. strf("(%s) ", buf.unsaved and "*" or "")
	s = s .. strf("%s ", editor.macrorec and "REC" or "")
	s = s .. strf("-- Help: ^X^H ", #buf.ual)
	s = s .. dbgs
	return s
end--statusline

local dbg = editor.dbg

------------------------------------------------------------------------
-- screen display functions  (boxes, line display)

local function boxnew(x, y, l, c)
	-- a box is a rectangular area on the screen
	-- defined by top left corner (x, y) 
	-- and number of lines and columns (l, c)
	local b = {x=x, y=y, l=l, c=c}
	b.clrl = rep(" ", c) -- used to clear box content
	return b
end

local function boxfill(b, ch, stylefn)
	local filler = rep(ch, b.c)
	stylefn()
	for i = 1, b.l do
		go(b.x+i-1, b.y); out(filler)
	end
	style.normal() -- back to normal style
	flush()
end

-- line display

local function ccrepr(b, j)
	-- return display representation of char with code b
	-- at line offset j (j is used for tabs)
	local s
	if b == 9 then s = rep(' ', tabln - j % tabln)
	elseif (b >= 127 and b <160) or (b < 32) then s = NDC
	else s = char(b)
	end--if
	return s
end --ccrepr

local function boxline(b, hs, bl, l, insel, jon, joff)
	-- display line l at the bl-th line of box b, 
	-- with horizontal scroll hs
	-- if s is tool long for the box, return the
	-- index of the first undisplayed char in l
	-- insel: true if line start is in the selection
	-- jon: if defined and not insel, position of beg of selection
	-- joff: if defined, position of end of selection
	local bc = b.c
	local cc = 0 --curent col in box
	-- clear line (don't use cleareol - box maybe smaller than screen)
	go(b.x+bl-1, b.y); out(b.clrl)  
	go(b.x+bl-1, b.y)
	if insel then style.sel() end
	for j = 1, #l do
		if (not insel) and j == jon+1 then style.sel(); insel=true end
		if insel and j == joff+1 then style.normal() end
		local chs = ccrepr(byte(l, j), cc)
		cc = cc + #chs
		if cc >= bc + hs then 
			go(b.x+bl-1, b.y+b.c-1)
			outf(EOL)
			style.normal()
			return j -- index of first undisplayed char in s
		end
		if cc > hs then out(chs) end
	end
	style.normal()
end --boxline

------------------------------------------------------------------------
-- screen redisplay functions


local function adjcursor(buf)
	-- adjust the screen cursor so that it matches with 
	-- the buffer cursor (buf.ci, buf.cj)
	--
	-- first, adjust buf.li
	local bl = buf.box.l
	if buf.ci < buf.li or buf.ci >= buf.li+bl then 
		-- cursor has moved out of box.
		-- set li so that ci is in the middle of the box
		buf.li = max(1, buf.ci-bl//2) 
		buf.chgd = true
	end
	local cx = buf.ci - buf.li + 1
	local cy = 1 -- box column index, ignoring horizontal scroll
	local col = buf.box.c
	local l = buf.ll[buf.ci]
	for j = 1, buf.cj do
		local b = byte(l, j)
		if not b then break end
		if b == 9 then cy = cy + (tabln - (cy-1) % tabln)
		else cy = cy + 1 
		end
--~ 		if cy > col then --don't move beyond the right of the box
--~ 			cy = col
--~ 			buf.cj = j
--~ 			break
--~ 		end
	end
	-- determine actual hs
	local hs = 0 -- horizontal scroll
	local cys = cy -- actual box column index
	while true do
		if cys >= col then 
			cys = cys - 40
			hs = hs + 40
		else
			break
		end
	end--while
	if hs ~= buf.hs then
		buf.chgd = true
		buf.hs = hs
	end
	if buf.chgd then return end -- (li or hs or content change)
	-- here, assume that cursor will move within the box
	editor.status(editor.statusline()) 
	go(buf.box.x + cx - 1, buf.box.y + cys - 1); flush()
end -- adjcursor


local function displaylines(buf)
	-- display buffer lines starting at index buf.li 
	-- in list of lines buf.ll
	local b, ll, li, hs = buf.box, buf.ll, buf.li, buf.hs
	local ci, cj, si, sj = buf.ci, buf.cj, buf.si, buf.sj
	local bi, bj, ei, ej -- beginning and end of selection
	local sel, insel, jon, joff = false, false, -1, -1
	if si then -- set beginning and end of selection
		sel = true
		if si < ci then bi=si; bj=sj; ei=ci; ej=cj
		elseif si > ci then bi=ci; bj=cj; ei=si; ej=sj
		elseif sj < cj then bi=si; bj=sj; ei=ci; ej=cj
		elseif sj >= cj then bi=ci; bj=cj; ei=si; ej=sj
		end
	end
	for i = 1, b.l do
		local lx = li+i-1
		if sel then
			insel, jon, joff = false, -1, -1
			if lx > bi and lx < ei then insel=true
			elseif lx == bi and lx == ei then jon=bj; joff=ej
			elseif lx == bi then jon=bj
			elseif lx == ei then joff=ej; insel=true
			end
		end
		local l = ll[lx] or EOT
		boxline(b, hs, i, l, insel, jon, joff)
	end
	flush()
end

local function redisplay(buf)
	-- adjust cursor and repaint buffer lines if needed
	adjcursor(buf)
	if buf.chgd or buf.si then
		displaylines(buf)
		buf.chgd = false
		adjcursor(buf)
	end
	buf.chgd = false
end --redisplay


function editor.fullredisplay()
	-- complete repaint of the screen
	-- performed initially, or when a new buffer is displayed, or
	-- when requested by the user (^L command) because the 
	-- screen is garbled or the screensize has changed (xterm, ...)
	--
	editor.scrl, editor.scrc = term.getscrlc()
	-- [TMP!! editor.scrbox is a bckgnd box with a pattern to
	-- visually check that edition does not overflow buf box
	-- (this is for future multiple windows, including side by side)]
	editor.scrbox = boxnew(1, 1, editor.scrl, editor.scrc)
--~ 	-- debug layout
--~ 	boxfill(editor.scrbox, ' ', style.bckg)
--~ 	buf.box = boxnew(2, 2, editor.scrl-3, editor.scrc-2)
	--
	-- regular layout
	boxfill(editor.scrbox, ' ', style.normal)
	buf.box = boxnew(2, 1, editor.scrl-2, editor.scrc)
	buf.chgd = true
	redisplay(buf)
end --fullredisplay

editor.redisplay = redisplay

------------------------------------------------------------------------
-- BUFFER AND CURSOR MANIPULATION 
--
-- 		use these functions instead of direct buf.ll manipulation. 
-- 		This will make it easier to change or enrich the 
-- 		representation later. (eg. syntax coloring, undo/redo, ...)

buffer = {}; buffer.__index = buffer --buffer class

-- (note: 'b' is a buffer object in all functions below)

	
function buffer.new(ll)
	-- create and initialize a new buffer object
	-- ll is a list of lines
	local b = { 
	  ll=ll,	-- list of text lines
	  ci=1, cj=0,	-- text cursor (line ci, offset cj)
	  li=1,		-- index in ll of the line at the top of the box
	  hs=0,		-- horizontal scroll (number of columns)
	  chgd=true,	-- true if buffer has changed since last display
	  unsaved=false,-- true if buffer content has changed since last save
	  ual = {},	-- undo action list
	  ualtop = 0,	-- current top of the undo list (~= #ual !! see undo)
	  -- box: a rectangular region of the screen where the buffer 
	  --      is displayed (see boxnew() above)
	  --      the box is assigned to the buffer by a layout function.
	  --      for the moment, the layout is performed by the 
	  --      fullredisplay() function.
	  bindings = {},	-- action table for this buffer (used by modes)
	}
	setmetatable(b, buffer)
	return b
end--new


-- various predicates and accessors

-- test if at end / beginning of  line  (eol, bol)
function buffer.ateol(b) return b.cj >= #b.ll[b.ci] end
function buffer.atbol(b) return b.cj <= 0 end
-- test if at  first or last line of text
function buffer.atfirst(b) return (b.ci <= 1) end
function buffer.atlast(b) return (b.ci >= #b.ll) end
-- test if at  end or beginning of  text (eot, bot)
function buffer.ateot(b) return b:atlast() and b:ateol() end
function buffer.atbot(b) return b:atfirst() and b:atbol() end

function buffer.markbeforecur(b)
	return (b.si < b.ci) or (b.si == b.ci and b.sj < b.cj)
end

function buffer.getcur(b) return b.ci, b.cj end
function buffer.getsel(b) return b.si, b.sj end

function buffer.geteol(b) 
	-- return coord of current end of line
	local ci = b.ci
	return ci, #b.ll[ci]
end

function buffer.getline(b, i)
	-- return current line and cursor position in line
	-- if i is provided, return line i
	if i then return b.ll[i], 1 end
	return b.ll[b.ci], b.cj
end

function buffer.getlines(b, di, dj)
	-- return the text between the cursor and point (di, dj) as
	-- a list of lines. this assumes that (di, dj) is after the cursor.
	local ci, cj = b:getcur()
	if di == ci then
		return { b.ll[ci]:sub(cj+1, dj) }
	end
	local sl = {}
	for i = ci, di do
		local l = b.ll[i]
		if i == ci then l = l:sub(cj+1) end
		if i == di then l = l:sub(1, dj) end
		table.insert(sl, l)
	end
	return sl
end--getlines

function buffer.gettext(b)
	return table.concat(b.ll, '\n')
end

-- cursor movement

function buffer.setcurj(b, j) -- set cursor on the current line
	local ci = b:getcur()
	local ln = #b.ll[ci]
	if not j or j > ln then j = ln end
	if j < 0 then j = 0 end
	b.cj = j
	return j
end
		
function buffer.setcur(b, i, j) -- set cursor absolute
	if not i or i > #b.ll then i = #b.ll end
	if i < 1 then i = 1 end
	if not j or j > #b.ll[i] then j = #b.ll[i] end
	if j < 0 then j = 0 end
	b.ci, b.cj = i, j
	return i, j
end

-- modification at cursor
-- all modifications should be performed by the following functions:
--   bufins(strlist)
--	insert list of string at cursor. if strlist is a string, it is
--	equivalent to a list with only one element 
--	if buffer contains one line "abc" and cursor is between b and c
--	(ie screen cursor is on 'c') then 
--	bufins{"xx"}  changes the buffer line to "abxxc"
--	bufins{"xx", "yy"}  now the buffer has two lines: "abxx", "yyc"
--	bufins{"", ""}  inserts a newline:   "ab", "c"
--
--   bufdel(di, dj)
--	delete all characters between the cursor and point (di, dj)
--	(bufdel assumes that di, dj is after the cursor)
--	if the buffer is  ("abxx", "yyc") and the cursor is just after 'b',
--	bufdel(2,2) changes the buffer to ("abc")
		

local ualpush -- defined further down with all undo functions

function buffer.bufins(b, sl, no_undo)
	-- if no_undo is true, don't record the modification
	local slc = {} -- dont push directly sl. make a copy.
	if type(sl) == "string" then 
		slc[1] = sl
	else
		for i = 1, #sl do slc[i] = sl[i] end
	end
	if not no_undo then ualpush(b, 'ins', slc) end
	local ci, cj = b:getcur()
	local l = b.ll[ci]
	local l1, l2 = l:sub(1,cj), l:sub(cj+1)
	local s1 = nil
	if type(sl) == "string" then	s1 = sl
	elseif #sl == 1 then  s1 = sl[1]
	end
	if s1 then -- insert s1 in current line
		b.ll[ci] = l1 .. s1 .. l2
		b:setcur(ci, cj + #s1)
	else -- several lines in sl
		b.ll[ci] = l1 .. sl[1]
		ci = ci + 1
		for i = 2, #sl-1 do
			table.insert(b.ll, ci, sl[i])
			ci = ci + 1
		end
		local last = sl[#sl]
		cj = #last
		table.insert(b.ll, ci, last .. l2)
		b:setcur(ci, cj)
	end
	b.chgd = true
	b.unsaved = true
	return true
end--bufins

function buffer.bufdel(b, di, dj, no_undo)
	-- if no_undo is true, don't record the modification
	if not no_undo then ualpush(b, 'del', b:getlines(di, dj)) end
	local ci, cj = b:getcur()
	local l1, l2 = b.ll[ci]:sub(1,cj), b.ll[di]:sub(dj+1)
	if di == ci then -- delete in current line at cursor
		b.ll[ci] = l1 .. l2
	else -- delete several lines
		local ci1 = ci + 1
		for i = ci1, di do
			-- the next line to remove is always the line at ci+1
			table.remove(b.ll, ci1) 
		end
		b.ll[ci] = l1 .. l2
	end
	b.chgd = true
	b.unsaved = true
	return true
end--bufdel

function buffer.settext(b, txt)
	-- replace the buffer text 
	-- !! it cannot be undone and it clears the undo stack !!
	-- the cursor and display are reinitialized at the top 
	-- of the new text.
	buffer.undo_clearall(b)
	b.ll = lines(txt)
	b.chgd = true
	b.unsaved = true
	b.ci = 1 -- line index
	b.cj = 0 -- cursor offset
	b.li = 1 -- index of line at the top of the box
	b.hs = 0 -- horizontal scroll
	return true
end--settext

------------------------------------------------------------------------
-- undo functions  

function ualpush(b, op, sl)
	-- push enough context to be able to undo a core operation (ins, del)
	-- sl is always a list of lines
	local top = #b.ual
	if top > b.ualtop then -- remove the remaining redo actions
		for i = top, b.ualtop+1, -1 do table.remove(b.ual, i) end
		assert(#b.ual == b.ualtop)
	end
	local last = b.ual[top]
	
	-- try to merge successive insch()

	sl.op, sl.ci, sl.cj = op, b.ci, b.cj
	table.insert(b.ual, sl)
	b.ualtop = b.ualtop + 1
	return
end

function buffer.op_undo(b, sl)
	b:setcur(sl.ci, sl.cj)
	if sl.op == "del" then 
		return b:bufins(sl, true)
	elseif sl.op == "ins" then
		return b:bufdel(sl.ci+#sl-1, sl.cj+#sl[#sl], true)
	else
		return nil, "unknown op"
	end
end

function buffer.op_redo(b, sl)
	b:setcur(sl.ci, sl.cj)
	if sl.op == "ins" then 
		return b:bufins(sl, true)
	elseif sl.op == "del" then
		return b:bufdel(sl.ci+#sl-1, sl.cj+#sl[#sl], true)
	else
		return nil, "unknown op"
	end
end

function buffer.undo_clearall(b)
	b.ual = {}
	b.ualtop = 0	
end


------------------------------------------------------------------------
-- EDITOR ACTIONS

editor.actions = {}
local e = editor.actions

local msg, readstr, readchar = editor.msg, editor.readstr, editor.readchar

function e.cancel()
	local b = buf
	-- do nothing. cancel selection if any
	b.si, b.sj = nil, nil
	b.chgd = true
end 

e.redisplay = editor.fullredisplay


function e.gohome() buf:setcurj(0) end
function e.goend() buf:setcurj() end
function e.gobot() buf:setcur(1, 0) end
function e.goeot() buf:setcur() end
	
function e.goup(n) 
	n = n or 1
	buf:setcur(buf.ci - n, buf.cj)
end

function e.godown(n)
	n = n or 1
	buf:setcur(buf.ci + n, buf.cj)
end

function e.goright(n)
	n = n or 1
	local ln = #buf.ll[buf.ci]
	while n > 0 do
		buf.cj = buf.cj + 1
		if buf.cj > ln then -- goto beg of next line
			buf.ci = buf.ci + 1
			if buf.ci > #buf.ll then
				e.goeot()
				return false 
			end
			ln = #buf.ll[buf.ci]
			buf.cj = 0
		end
		n = n - 1
	end
	return true
end

function e.goleft(n)
	n = n or 1
	while n > 0 do
		buf.cj = buf.cj - 1
		if buf.cj < 0 then -- goto end of prev line
			buf.ci = buf.ci - 1
			if buf.ci < 1 then 
				e.gobot()
				return false
			end
			buf.cj = #buf.ll[buf.ci]
		end
		n = n - 1
	end
	return true
end

function e.pgdn() 
	buf:setcur(buf.ci + buf.box.l - 2, buf.cj)
end

function e.pgup() 
	buf:setcur(buf.ci - buf.box.l - 2, buf.cj)
end

function e.nl()
	return buf:bufins({"", ""})
end

function e.del()
	local b = buf
	if b:ateot() then return false end
	local ci, cj = b:getcur()
	if b:ateol() then return b:bufdel(ci+1, 0) end
	return b:bufdel(ci, cj+1)
end

function e.bksp()
	return e.goleft() and e.del()
end

function e.insch(k)
	return buf:bufins(char(k))
end

function e.searchagain(actfn)
	-- search editor.pat. If found, execute actfn
	-- default action is to display a message "found!")
	-- on success, return the result of actfn() or true.
	-- (note: search does NOT ignore case)
	local b = buf
	if not editor.pat then 
		msg("no string to search")
		return nil
	end
	local oci, ocj = b:getcur() -- save the original cursor position
	while true do
		local l, cj = b:getline()
		local j = l:find(editor.pat, cj+2, true) --plain text search
		if j then --found
			b:setcurj(j-1)
			if actfn then 
				return actfn()
			else
				msg("found!")
				return true
			end
		end -- found
		if not (e.goright()) then
			break -- at end of file and not found yet
		end
	end--while
	msg("not found")
	b:setcur(oci, ocj) -- restore cursor position
end

function e.search()
	editor.pat = readstr("Search: ")
	if not editor.pat then 
		msg("aborted.")
		return
	end
	return e.searchagain()
end

function e.replaceagain()
	local b = buf
	local replall = false -- true if user selected "replace (a)ll"
	local n = 0 -- number of replaced instances
	function replatcur()
		-- replace at cursor 
		-- (called only when editor.pat is found at cursor)
		-- (pat and patrepl are plain text, unescaped)
		n = n + 1  --one more replaced instance
		local ci, cj = b:getcur()
		return b:bufdel(ci, cj + #editor.pat) 
			and b:bufins(editor.patrepl)
	end--replatcur
	function replfn()
		-- this function is called each time editor.pat is found
		-- return true to continue, nil/false to stop
		if replall then 
			return replatcur()
		else
			local ch = readchar( -- ask what to do
				"replace? (q)uit (y)es (n)o (a)ll (^G) ", 
				"[anqy]")
			if not ch then return nil end
			if ch == "a" then -- replace all
				replall = true
				return replatcur()
			elseif ch == "y" then -- replace
				return replatcur()
			elseif ch == "n" then -- continue
				return true
			else -- assume q (quit)
				return nil
			end
		end
	end--replfn
	while e.searchagain(replfn) do end
	msg(strf("replaced %d instance(s)", n))
end--replaceagain

function e.replace()
	editor.pat = readstr("Search: ")
	if not editor.pat then 
		msg("aborted.")
		return
	end
	editor.patrepl = readstr("Replace with: ")
	if not editor.patrepl then 
		msg("aborted.")
		return
	end
	return e.replaceagain()
end--replace

function e.kill() 
	-- wipe from cursor to end of line
	-- del nl but do not modify the kill buffer if at eol
	local b = buf
	if b:ateol() then return e.del() end
	local di, dj = b:geteol()
	sl = b:getlines(di, dj)
	editor.kll = sl
	return b:bufdel(di, dj)
end--kill

function e.killeol(b, appflag)
	-- wipe from cursor to eol included. copy to the kill buffer
	-- or append to the kill buffer if last action was also 'killeol'
	-- if appflag is true, always append to the kill buffer 
	-- (default: false)
	local b = buf
	if b:ateot() then return end
	appflag = appflag or (editor.lastresult == e.killeol)
	if not appflag then 
		-- start with a fresh kill buffer
		editor.kll = {}
	else
		-- here either kll is empty 
		-- or last item is an empty line => remove it
		table.remove(editor.kll)
	end
	local di, dj = b:geteol()
	local s = b:getlines(di, dj)[1]
	table.insert(editor.kll, s)  -- insert the end of line
	table.insert(editor.kll, "") -- insert a newline
	b:bufdel(di+1, 0) -- del to bol of next line
	-- allow to detect that previous command was also killeol
	return e.killeol 
end--killeol

function e.mark()
	local b = buf
	b.si, b.sj = b.ci, b.cj
	msg("Mark set.")
	b.chgd = true
end

function e.exch_mark()
	local b = buf
	if b.si then
		b.si, b.ci = b.ci, b.si
		b.sj, b.cj = b.cj, b.sj
	end
end

function e.wipe()
	local b = buf
	if not b.si then msg("No selection."); return end
	-- make sure cursor is at beg of selection
	if b:markbeforecur() then e.exch_mark() end 
	local si, sj = b:getsel()
	editor.kll = b:getlines(si, sj)
	b:bufdel(si, sj)
	b.si = nil
end--wipe	

function e.yank()
	local b = buf
	if not editor.kll or #editor.kll == 0 then 
		msg("nothing to yank!"); return 
	end
	return b:bufins(editor.kll)
end--yank

function e.undo()
	local b = buf
	if b.ualtop == 0 then msg("nothing to undo!"); return end
	b:op_undo(b.ual[b.ualtop])
	b.ualtop = b.ualtop - 1
end--undo

function e.redo()
	local b = buf
	if b.ualtop == #b.ual then msg("nothing to redo!"); return end
	b.ualtop = b.ualtop + 1
	b:op_redo(b.ual[b.ualtop])
end--redo

function e.quiteditor()
	editor.quit = true
end

function e.exiteditor()
	local anyunsaved = false
	for i, bx in ipairs(editor.buflist) do 
		anyunsaved = anyunsaved or bx.unsaved
	end
	if anyunsaved then
		local ch = readchar(
			"Some buffers not saved. Quit? ", "[YNQynq\r\n]")
		if ch ~= "y" and ch ~= "Y" then 
			msg("aborted.")
			return
		end
	end
	editor.quit = true
	msg("exiting.")
end

function e.newbuffer(fname, ll)
	ll = ll or { "" } -- default is a buffer with one empty line
	fname = fname or editor.readstr("Buffer name: ")
	local bx = buffer.new(ll) 
	bx.actions = editor.edit_actions 
	bx.filename = fname
	-- insert just after the current buffer
	local bi = editor.bufindex + 1 
	table.insert(editor.buflist, bi, bx) 
	editor.bufindex = bi
	buf = bx
	editor.fullredisplay()
end

function e.nextbuffer()
	-- switch to next buffer
	local bln = #editor.buflist
	editor.bufindex = editor.bufindex % bln + 1
	buf = editor.buflist[editor.bufindex]
	editor.fullredisplay()
end--nextbuffer

function e.prevbuffer()
	-- switch to previous buffer
	local bln = #editor.buflist
	-- if bufindex>1, the "previous" buffer index should be bufindex-1
	-- if bufindex==1, the "previous" buffer index should be bln
	editor.bufindex = (editor.bufindex - 2) % bln + 1
	buf = editor.buflist[editor.bufindex]
	editor.fullredisplay()
end--nextbuffer

function e.findfile(fname)
	fname = fname or editor.readstr("Open file: ")
	if not fname then editor.msg""; return end
	local ll, errmsg = readfile(fname)
	if not ll then editor.msg(errmsg); return end
	e.newbuffer(fname, ll)
end--findfile

function e.writefile(b, fname)
	local b = buf
	fname = fname or editor.readstr("Write to file: ")
	if not fname then editor.msg("Aborted."); return end
	fh, errmsg = io.open(fname, "w")
	if not fh then editor.msg(errmsg); return end
	for i = 1, #b.ll do fh:write(b.ll[i], "\n") end
	fh:close()
	b.filename = fname
	b.unsaved = false
	editor.msg(fname .. " saved.")
end--writefile

function e.savefile()
	local b = buf
	e.writefile(b, b.filename)
end--savefile

local function macrorecord(x)
	if not editor.macrorec then return end
	table.insert(editor.macroseq, x)
end

function e.macrostartrec()
	editor.macroseq = {}
	editor.macrorec = true
end

function e.macrostoprec()
	editor.macrorec = false
end

function e.macroplay() 
	-- should not pass buf to use the current buffer 
	-- for macros switching buffers)
	if #editor.macroseq == 0 then
		return msg("no macro defined!")
	elseif editor.macrorec then 
		editor.macrorec = false
		editor.macroseq = {}
		return msg("Cannot play while recording. Aborted.")
	end	
	for i, act in ipairs(editor.macroseq) do
		if type(act) == "number" then 
			e.insch(buf, act)
		else
			act(buf)
		end
	end
end

function e.gotoline(lineno)
	-- prompt for a line number, go there
	-- if lineno is provided, don't prompt.
	local b = buf
	lineno = lineno or tonumber(editor.readstr("line number: "))
	if not lineno then
		msg("invalid line number.")
	else
		return b:setcur(lineno, 0)
	end
end--gotoline

function e.help()
	for i, bx in ipairs(editor.buflist) do
		if bx.filename == "*HELP*" then
			buf = bx; editor.bufindex = i
			editor.fullredisplay()
			return
		end
	end -- help buffer not found, then build it.
	local ll = {}
	for l in editor.helptext:gmatch("(.-)\n") do table.insert(ll, l) end
	return e.newbuffer("*HELP*", ll)
end--help

function e.test()
	-- this function is just used for quick debug tests
	-- (to be removed!)
	--
	local b = buf
--~ 	-- test readstr
--~ 	s = readstr("enter a string: ")
--~ 	if not s then msg"NIL!" ; return end
--~ 	msg("the string is: '"..s.."'")

	-- test kill
--~ 	b.ll = editor.kll or {}
--~ 	b:setcur(1, 0)
--~ 	b.chgd = true

	s = b:gettext()
	s = s:upper()
	b:settext(s)

--~ 	-- test readchar
--~ 	local ch = readchar("test readchar: ", "[abc]")
--~ 	if not ch then msg("aborted!")
--~ 	else msg("readchar => "..ch)
--~ 	end
end--atest

editor.helptext = [[

*HELP*			-- back to the previous buffer: ^X^P

Cursor movement
	Arrows, PageUp, PageDown, Home, End
	^A ^E		go to beginning, end of line
	^B ^F		go backward, forward
	^N ^P		go to next line, previous line
	esc-<		go to beginning of buffer
	esc-> 		go to end of buffer
	^S		forward search (plain text, case sensitive)
	^R		search again (string previously entered with ^S)
	esc-g		prompt for a line number, go there
   
Edition
	^D, Delete	delete character at cursor
	^H, bcksp	delete previous character
	^K		cut from cursor to end of line
	esc-k		cut from cursor to beginning of next line
			(if repeated, lines are appended to the paste buffer)
	^space, ^@	mark  (set beginning of selection)
	^W		wipe (cut selection)
	^Y		yank (paste)
	esc-5		replace
	esc-7		replace again (with same strings)

Files, buffers
	^X^F		prompt for a filename, read the file in a new buffer
	^X^W		prompt for a filename, write the current buffer
	^X^S		save the current buffer
	^X^B		create a new, empty buffer
	^X^N		switch to the next buffer
	^X^P		switch to the previous buffer

Misc.
	^X^C		exit the editor
	^G		abort the current command
	^Z		undo 
	esc-z		redo 
	^X(		record macro
	^X)		stop recording macro
	^Xe, ^]		play macro
	^L		redisplay the screen (useful if the screen was 
			garbled	or its dimensions changed)
	F1, ^X^H	this help text

]]

------------------------------------------------------------------------
-- bindings

editor.bindings = { -- actions binding for text edition
	[0] = e.mark,		-- ^@
	[1] = e.gohome,		-- ^A
	[2] = e.goleft,		-- ^B
	--[3]		-- ^C
	[4] = e.del,		-- ^D
	[5] = e.goend,		-- ^E
	[6] = e.goright,	-- ^F
	[7] = e.cancel,		-- ^G (do nothing, cancel selection)
	[8] = e.bksp,		-- ^H
	--[9] (TAB)
	--[10]		-- ^J
	[11] = e.kill,		-- ^k
	[12] = e.redisplay,	-- ^L
	[13] = e.nl,		-- ^M (insert newline)
	[14] = e.godown,	-- ^N
	[15] = e.macroplay,	-- ^O
	[16] = e.goup,		-- ^P
	[17] = e.quiteditor,	-- ^Q
	[18] = e.searchagain,	-- ^R
	[19] = e.search,	-- ^S
	[20] = e.test,		-- ^T
	--[21]		-- ^U
	--[22]		-- ^V
	[23] = e.wipe,		-- ^W
	-- [24]			-- ^X (prefix - see below)
	[25] = e.yank,		-- ^Y
	[26] = e.undo,		-- ^Z
	-- [27] 		-- ESC (prefix - see below)
	[29] = e.macroplay,	-- ^]
	--
	[keys.kpgup]  = e.pgup,
	[keys.kpgdn]  = e.pgdn,
	[keys.khome]  = e.gohome,
	[keys.kend]   = e.goend,
	[keys.kdel]   = e.del, 
	[keys.del]    = e.bksp, 
	[keys.kright] = e.goright,
	[keys.kleft]  = e.goleft,
	[keys.kup]    = e.goup,
	[keys.kdown]  = e.godown,
	[keys.kf1]    = e.help,
	--
	-- prefix keys
	--
	[24] = {	-- ^X
		[2] = e.newbuffer,	-- ^X^B
		[3] = e.exiteditor,	-- ^X^C
		[6] = e.findfile,	-- ^X^F
		[7] = e.cancel,		-- ^X^G (cancel selection)
		[8] = e.help,		-- ^X^H
		[14] = e.nextbuffer,	-- ^X^N
		[16] = e.prevbuffer,	-- ^X^P
		[19] = e.savefile,	-- ^X^S
		[23] = e.writefile,	-- ^X^W
		[24] = e.exch_mark,	-- ^X^X
		[40] = e.macrostartrec,	-- ^X(
		[41] = e.macrostoprec,	-- ^X)
		[101] = e.macroplay,	-- ^Xe
	},
	[27] = {	-- ESC
		[7] = e.cancel,		-- esc ^G (cancel selection)
		[49] = e.help,		-- esc 1
		[53] = e.replace,	-- esc 5 -%
		[55] = e.replaceagain,	-- esc 7 -&
		[60] = e.gobot,		-- esc <
		[62] = e.goeot,		-- esc >
		[103] = e.gotoline,	-- esc g
		[107] = e.killeol,	-- esc k
		[122] = e.redo,		-- esc z
	},
}--actions

local function get_action(bindings, k, k2)
	-- find action bound to k in bindings table.
	-- if k is a prefix, use k2 or read it if not provided.
	-- return action, k2, keyname if found, 
	-- or nil, k2, keyname if not found
	local kname = term.keyname(k)
	local act = bindings[k] 
	if act and type(act) == "table" then -- k is a prefix
		k2 = k2 or editor.nextk()
		kname = kname .. "-" .. term.keyname(k2)
		act = act[k2]
	end
	return act, k2, kname
end--get_action	

local function editor_loadinitfile()
	-- function to be executed before entering the editor loop
	-- could be used to load a configuration/initialization file
	local initfile = os.getenv("PLE_INIT")
	if fileexists(initfile) then 
		return assert(loadfile(initfile))()
	end
	initfile = "./ple_init.lua"
	if fileexists(initfile) then
		return assert(loadfile(initfile))()
	end
	local homedir = os.getenv("HOME") or "~"
	initfile = homedir .. "/.config/ple/ple_init.lua"
	if fileexists(initfile) then
		return assert(loadfile(initfile))()
	end
	return nil
end--editor_loadinitfile


local function editor_loop(ll, fname)
	editor.initmsg = "Help: F1 or ^X^H or esc-1"
	local r = editor_loadinitfile()
	style.normal()
	e.newbuffer(fname, ll); 
	msg(editor.initmsg)
	redisplay(buf) -- adjust cursor to beginning of buffer
	while not editor.quit do
		local k = editor.nextk()
		-- try first in buffer action table
		local act, k2, kname = get_action(buf.bindings, k)
		if not act then -- try in the default editor table
			act, k2, kname = get_action(editor.bindings, k, k2)
		end
		if act then 
			msg(kname)
			macrorecord(act)
			editor.lastresult = act()
		elseif (not k2) and ((k >= 32 and k < 127) 
			or (k >= 160 and k < 256) 
			or (k == 9)) then
			macrorecord(k)
			editor.lastresult = e.insch(k)
		else
			editor.msg(kname .. " not bound")
		end
	redisplay(buf)
	end--while true
end--editor_loop

local function main()
	-- process argument
	local ll, fname 
	if arg[1] then
		ll, err = readfile(arg[1]) -- load file as a list of lines
		if not ll then print(err); os.exit(1) end
		fname = arg[1]
	else
		ll = { "" }
		fname = "unnamed"
	end
	-- set term in raw mode
	local prevmode, e, m = term.savemode()
	if not prevmode then print(prevmode, e, m); os.exit() end
	term.setrawmode()
	term.reset()
	-- run the application in a protected call so we can properly reset
	-- the tty mode and display a traceback in case of error
	local ok, msg = xpcall(editor_loop, debug.traceback, ll, fname)
	-- restore terminal in a a clean state
	term.show() -- show cursor
	term.left(999); term.down(999)
	style.normal()
	flush()
	--~ 	ln.setmode(omode)
	term.restoremode(prevmode)
	if not ok then -- display traceback in case of error
		print(msg)
		os.exit(1)
	end
	print("\n") -- add an extra line  after the 'exiting' msg
end

main()

