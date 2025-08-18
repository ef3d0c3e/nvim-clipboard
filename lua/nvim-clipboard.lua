M = {}
M.clipboard_history = {}

local vim = vim
local last_clipboard_content = "" -- Variable to store the last clipboard content

local line_delimiter = "\r"

-- Default configuration
local config = {
	max_items = 5,
	file = vim.fn.getcwd() .. '/clipboard.txt',
}

-- clear items of extra newline elements causing error
local function remove_newlines(str_table)
	local result = {}
	for i, str in ipairs(str_table) do
		-- result[i] = str:gsub("\n", "")
		result[i] = str:gsub("\n", line_delimiter)
	end
	return result
end

function M.show_list(items)
	-- Create a new buffer
	local buf = vim.api.nvim_create_buf(false, true)

	-- Populate the buffer
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, remove_newlines(items))

	local current_win = vim.api.nvim_get_current_win()
	local win_width = vim.api.nvim_win_get_width(current_win)
	local win_height = vim.api.nvim_win_get_height(current_win)

	local new_win_width = 80 -- Adjust as needed
	local new_win_height = 20 -- Adjust as needed

	local row = math.floor(win_height / 2 - new_win_height / 2)
	local col = math.floor(win_width / 2 - new_win_width / 2)

	local options = {
		relative = "win",
		width = new_win_width,
		height = new_win_height,
		row = row,
		col = col,
		border = "single",
	}

	local win = vim.api.nvim_open_win(buf, true, options)

	-- Set up keymaps for navigation and selection
	vim.keymap.set("n", "<up>", function()
		vim.cmd("norm k")
	end, { buffer = buf })
	vim.keymap.set("n", "<down>", function()
		vim.cmd("norm j")
	end, { buffer = buf })
	vim.keymap.set("n", "<esc>", function()
		vim.cmd("close")
	end, { buffer = buf })

	vim.keymap.set("n", "<CR>", function()
		local selected_item = vim.api.nvim_buf_get_lines(
			buf,
			vim.api.nvim_win_get_cursor(win)[1] - 1,
			vim.api.nvim_win_get_cursor(win)[1],
			false
		)[1]
		-- Convert line delimiter back to newlines for proper clipboard content
		if selected_item then
			selected_item = selected_item:gsub(line_delimiter, "\n")
			-- move selected_item to + register
			vim.fn.setreg("+", selected_item)
			vim.fn.setreg("*", selected_item)
		end
		vim.cmd("close")
	end, { buffer = buf })
end


-- Ensure the history in memory does not exceed max_items
local function trim_history()
	while #M.clipboard_history > config.max_items do
		table.remove(M.clipboard_history, 1)
	end
end

-- Append a single item to the file
local function append_to_file(text)
	local dir = vim.fn.fnamemodify(config.file, ':h')
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, 'p')
	end
	local file, err = io.open(config.file, 'a')
	if not file then
		vim.api.nvim_err_writeln('Failed to open clipboard file for appending: ' .. (err or ''))
		return
	end
	file:write(text .. "\n--CLIPBOARD-ITEM--\n")
	file:close()
end

-- Save the entire in-memory history to the configured file (used for trimming)
local function save_history_to_file()
	local dir = vim.fn.fnamemodify(config.file, ':h')
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, 'p')
	end
	local file, err = io.open(config.file, 'w')
	if not file then
		vim.api.nvim_err_writeln('Failed to open clipboard file for writing: ' .. (err or ''))
		return
	end
	for i, item in ipairs(M.clipboard_history) do
		file:write(item .. "\n--CLIPBOARD-ITEM--\n")
	end
	file:close()
end

local function append_and_save(text)
	-- Avoid duplicates - don't add if it's the same as the last item
	if #M.clipboard_history > 0 and M.clipboard_history[#M.clipboard_history] == text then
		return
	end
	
	local old_count = #M.clipboard_history
	table.insert(M.clipboard_history, text)
	
	-- If we're under the limit, just append to file
	if #M.clipboard_history <= config.max_items then
		append_to_file(text)
	else
		-- If we exceed the limit, trim history and rewrite the entire file
		trim_history()
		save_history_to_file()
	end
end

function M.read_from_file()
	M.clipboard_history = {}
	local file = io.open(config.file, 'r')
	if file ~= nil then
		local content = file:read('*a')
		file:close()
		
		-- If file is too large (>100KB), truncate it
		if #content > 100000 then
			print('Clipboard file too large, truncating...')
			M.clipboard_history = {}
			return M.clipboard_history
		end
		
		-- Split the content using the delimiter and insert into clipboard_history
		if content and #content > 0 then
			-- Add delimiter at the end if it doesn't exist to ensure proper splitting
			if not content:match('\n%-%-CLIPBOARD%-ITEM%-%-\n$') then
				content = content .. '\n--CLIPBOARD-ITEM--\n'
			end
			
			-- Split by the delimiter pattern
			local items = {}
			for item in content:gmatch('(.-)\n%-%-CLIPBOARD%-ITEM%-%-\n') do
				if item and #item > 0 then
					-- Remove any trailing whitespace/newlines
					item = item:gsub('^%s*(.-)%s*$', '%1')
					if #item > 0 then
						table.insert(items, item)
					end
				end
			end
			
			M.clipboard_history = items
		end
		
		-- keep only the last max_items entries
		if #M.clipboard_history > config.max_items then
			local start_idx = #M.clipboard_history - config.max_items + 1
			local new_hist = {}
			for i = start_idx, #M.clipboard_history do
				table.insert(new_hist, M.clipboard_history[i])
			end
			M.clipboard_history = new_hist
		end
		return M.clipboard_history
	else
		-- file doesn't exist yet; return empty history
		return M.clipboard_history
	end
end

-- Public setup to allow overriding defaults
function M.setup(opts)
	opts = opts or {}
	if type(opts.max_items) == 'number' and opts.max_items > 0 then
		config.max_items = math.floor(opts.max_items)
	end
	if type(opts.file) == 'string' and #opts.file > 0 then
		config.file = opts.file
	end
	-- Load existing history on setup
	M.read_from_file()
	-- Ensure history respects new config immediately
	trim_history()
	save_history_to_file()
end

-- setup mapping for clipboard buffer to be opened
vim.keymap.set('n', '<leader>b', function()
	local list = M.read_from_file()
	print('Clipboard history loaded: ' .. #list .. ' items')
	if #list == 0 then
		print('No clipboard history found. Try copying some text first.')
	else
		-- Reverse the list so most recent items appear at the top
		local reversed_list = {}
		for i = #list, 1, -1 do
			table.insert(reversed_list, list[i])
		end
		require('nvim-clipboard').show_list(reversed_list)
	end
end)
-- Define a function to monitor clipboard changes
M.monitor_clipboard = function()
	local clipboard_text = vim.fn.getreg("+") -- Get the content of the system clipboard
	if clipboard_text ~= last_clipboard_content then -- If the clipboard content has changed
		append_and_save(clipboard_text)
		print('Clipboard updated: ' .. string.sub(clipboard_text, 1, 30) .. '...')
		last_clipboard_content = clipboard_text
	end
end
-- Set up a timer to periodically check the system clipboard
local timer = vim.loop.new_timer()
timer:start(1000, 1000, vim.schedule_wrap(M.monitor_clipboard)) -- Check every 1000 milliseconds (1 second)

-- Initialize plugin - load existing history and capture current clipboard
M.read_from_file()
local current_clipboard = vim.fn.getreg("+")
if current_clipboard and current_clipboard ~= "" and current_clipboard ~= last_clipboard_content then
	append_and_save(current_clipboard)
	last_clipboard_content = current_clipboard
end

vim.api.nvim_out_write("Clipboard monitoring plugin loaded.\n")

return M
