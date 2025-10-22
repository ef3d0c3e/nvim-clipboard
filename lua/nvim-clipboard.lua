M = {}
M.clipboard_history = {}

local vim = vim
local last_clipboard_content = "" -- Variable to store the last clipboard content

local line_delimiter = "\r"

-- Default configuration
local config = {
	max_items = 5,
	file = function()
		return vim.fn.getcwd() .. '/clipboard.txt'
	end,
	vault_file = vim.fn.stdpath('data') .. '/nvim-clipboard-vault.dat',
	-- Notify when clipboard is updated
	notify = true,
	keys = {
		-- Append current clipboard item to vault
		vault_append = { 'n', '<leader>va' },
		-- Open vault
		vault_open = { 'n', '<leader>vv' },
		-- Open clipboard history
		history_open = { 'n', '<leader>b' },
	},
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

-- Vault functionality
M.vault_items = {}

-- Simple XOR-based encryption (for demonstration - in production, use a proper crypto library)
local function xor_encrypt_decrypt(data, password)
	if not data or not password or #password == 0 then
		return nil
	end

	local result = {}
	local key_len = #password

	for i = 1, #data do
		local char_code = string.byte(data, i)
		local key_char_code = string.byte(password, ((i - 1) % key_len) + 1)
		-- Manual XOR implementation
		local xor_result = 0
		local a, b = char_code, key_char_code
		local bit_val = 1
		while a > 0 or b > 0 do
			if (a % 2) ~= (b % 2) then
				xor_result = xor_result + bit_val
			end
			a = math.floor(a / 2)
			b = math.floor(b / 2)
			bit_val = bit_val * 2
		end
		table.insert(result, string.char(xor_result))
	end

	return table.concat(result)
end

-- Base64 encoding/decoding for safe file storage
local base64_chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

local function base64_encode(data)
	return ((data:gsub('.', function(x)
		local r, b = '', x:byte()
		for i = 8, 1, -1 do r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and '1' or '0') end
		return r;
	end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
		if (#x < 6) then return '' end
		local c = 0
		for i = 1, 6 do c = c + (x:sub(i, i) == '1' and 2 ^ (6 - i) or 0) end
		return base64_chars:sub(c + 1, c + 1)
	end) .. ({ '', '==', '=' })[#data % 3 + 1])
end

local function base64_decode(data)
	data = string.gsub(data, '[^' .. base64_chars .. '=]', '')
	return (data:gsub('.', function(x)
		if (x == '=') then return '' end
		local r, f = '', (base64_chars:find(x) - 1)
		for i = 6, 1, -1 do r = r .. (f % 2 ^ i - f % 2 ^ (i - 1) > 0 and '1' or '0') end
		return r;
	end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
		if (#x ~= 8) then return '' end
		local c = 0
		for i = 1, 8 do c = c + (x:sub(i, i) == '1' and 2 ^ (8 - i) or 0) end
		return string.char(c)
	end))
end

-- Load vault items from encrypted file
local function load_vault(password)
	local file = io.open(config.vault_file, 'r')
	if not file then
		M.vault_items = {}
		return true -- File doesn't exist yet, that's okay
	end

	local encrypted_content = file:read('*a')
	file:close()

	if not encrypted_content or #encrypted_content == 0 then
		M.vault_items = {}
		return true
	end

	-- Decode from base64
	local decoded_content = base64_decode(encrypted_content)
	if not decoded_content then
		vim.api.nvim_err_writeln('Failed to decode vault file')
		return false
	end

	-- Decrypt
	local decrypted_content = xor_encrypt_decrypt(decoded_content, password)
	if not decrypted_content then
		vim.api.nvim_err_writeln('Failed to decrypt vault file')
		return false
	end

	-- Parse JSON-like format
	M.vault_items = {}
	if #decrypted_content > 0 then
		-- Split items by delimiter
		for item in decrypted_content:gmatch('(.-)\n%-%-VAULT%-ITEM%-%-\n') do
			if item and #item > 0 then
				item = item:gsub('^%s*(.-)%s*$', '%1')
				if #item > 0 then
					table.insert(M.vault_items, item)
				end
			end
		end
	end

	return true
end

-- Save vault items to encrypted file
local function save_vault(password)
	if not password or #password == 0 then
		vim.api.nvim_err_writeln('Password required to save vault')
		return false
	end

	-- Create directory if it doesn't exist
	local dir = vim.fn.fnamemodify(config.vault_file, ':h')
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, 'p')
	end

	-- Serialize vault items
	local content = ''
	for _, item in ipairs(M.vault_items) do
		content = content .. item .. '\n--VAULT-ITEM--\n'
	end

	-- Encrypt content
	local encrypted_content = xor_encrypt_decrypt(content, password)
	if not encrypted_content then
		vim.api.nvim_err_writeln('Failed to encrypt vault content')
		return false
	end

	-- Encode to base64 for safe file storage
	local encoded_content = base64_encode(encrypted_content)

	-- Write to file
	local file, err = io.open(config.vault_file, 'w')
	if not file then
		vim.api.nvim_err_writeln('Failed to open vault file for writing: ' .. (err or ''))
		return false
	end

	file:write(encoded_content)
	file:close()

	return true
end

-- Get password from user input (without echoing)
local function get_password(prompt)
	vim.fn.inputsave()
	local password = vim.fn.inputsecret(prompt or 'Enter vault password: ')
	vim.fn.inputrestore()
	return password
end

function M.show_list(items)
	-- Create a new buffer
	local buf = vim.api.nvim_create_buf(false, true)

	-- Add instructions header
	local display_items = { '=== CLIPBOARD HISTORY ===', '' }
	for _, item in ipairs(items) do
		table.insert(display_items, item)
	end
	table.insert(display_items, '')
	table.insert(display_items, 'ENTER: Copy to clipboard | v: Add to vault | ESC: Close')

	-- Populate the buffer
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, remove_newlines(display_items))

	local current_win = vim.api.nvim_get_current_win()
	local win_width = vim.api.nvim_win_get_width(current_win)
	local win_height = vim.api.nvim_win_get_height(current_win)

	local new_win_width = 80                             -- Adjust as needed
	local new_win_height = math.min(#display_items + 2, 25) -- Adjust as needed

	local row = math.floor(win_height / 2 - new_win_height / 2)
	local col = math.floor(win_width / 2 - new_win_width / 2)

	local options = {
		relative = "win",
		width = new_win_width,
		height = new_win_height,
		row = row,
		col = col,
		border = "single",
		title = " Clipboard History ",
	}

	local win = vim.api.nvim_open_win(buf, true, options)

	-- Set cursor to first item (skip header)
	vim.api.nvim_win_set_cursor(win, { 3, 0 })

	-- Set up keymaps for navigation and selection
	vim.keymap.set("n", "<up>", function()
		local current_line = vim.api.nvim_win_get_cursor(win)[1]
		if current_line > 3 then
			vim.api.nvim_win_set_cursor(win, { current_line - 1, 0 })
		end
	end, { buffer = buf })
	vim.keymap.set("n", "<down>", function()
		local current_line = vim.api.nvim_win_get_cursor(win)[1]
		local max_line = #items + 2 -- Account for header
		if current_line < max_line then
			vim.api.nvim_win_set_cursor(win, { current_line + 1, 0 })
		end
	end, { buffer = buf })
	vim.keymap.set("n", "<esc>", function()
		vim.cmd("close")
	end, { buffer = buf })

	vim.keymap.set("n", "<CR>", function()
		local current_line = vim.api.nvim_win_get_cursor(win)[1]
		local item_index = current_line - 2 -- Account for header
		if item_index > 0 and item_index <= #items then
			local selected_item = items[item_index]
			-- Convert line delimiter back to newlines for proper clipboard content
			if selected_item then
				selected_item = selected_item:gsub(line_delimiter, "\n")
				-- move selected_item to + register
				vim.fn.setreg("+", selected_item)
				vim.fn.setreg("*", selected_item)
				print('Copied to clipboard')
			end
		end
		vim.cmd("close")
	end, { buffer = buf })

	vim.keymap.set("n", "v", function()
		local current_line = vim.api.nvim_win_get_cursor(win)[1]
		local item_index = current_line - 2 -- Account for header
		if item_index > 0 and item_index <= #items then
			local selected_item = items[item_index]
			if selected_item then
				selected_item = selected_item:gsub(line_delimiter, "\n")
				vim.cmd("close")
				M.add_history_to_vault(selected_item)
			end
		end
	end, { buffer = buf })
end

-- Show vault items in a floating window
function M.show_vault()
	local password = get_password('Enter vault password to view items: ')
	if not password or #password == 0 then
		print('Vault access cancelled')
		return
	end

	if not load_vault(password) then
		vim.api.nvim_err_writeln('Failed to load vault or incorrect password')
		return
	end

	if #M.vault_items == 0 then
		print('Vault is empty')
		return
	end

	-- Create a new buffer for vault items
	local buf = vim.api.nvim_create_buf(false, true)

	-- Add header and items
	local display_items = { '=== VAULT ITEMS ===', '' }
	for i, item in ipairs(M.vault_items) do
		local preview = item:gsub('\n', line_delimiter)
		if #preview > 80 then
			preview = preview:sub(1, 77) .. '...'
		end
		table.insert(display_items, string.format('%d. %s', i, preview))
	end
	table.insert(display_items, '')
	table.insert(display_items, 'Press ENTER to copy item, d to delete, ESC to close')

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, display_items)

	local current_win = vim.api.nvim_get_current_win()
	local win_width = vim.api.nvim_win_get_width(current_win)
	local win_height = vim.api.nvim_win_get_height(current_win)

	local new_win_width = math.min(100, win_width - 4)
	local new_win_height = math.min(#display_items + 2, win_height - 4)

	local row = math.floor(win_height / 2 - new_win_height / 2)
	local col = math.floor(win_width / 2 - new_win_width / 2)

	local options = {
		relative = "win",
		width = new_win_width,
		height = new_win_height,
		row = row,
		col = col,
		border = "single",
		title = " Vault Items ",
	}

	local win = vim.api.nvim_open_win(buf, true, options)

	-- Set cursor to first item
	vim.api.nvim_win_set_cursor(win, { 3, 0 })

	-- Set up keymaps
	vim.keymap.set("n", "<up>", function()
		local current_line = vim.api.nvim_win_get_cursor(win)[1]
		if current_line > 3 then
			vim.api.nvim_win_set_cursor(win, { current_line - 1, 0 })
		end
	end, { buffer = buf })

	vim.keymap.set("n", "<down>", function()
		local current_line = vim.api.nvim_win_get_cursor(win)[1]
		if current_line < #M.vault_items + 2 then
			vim.api.nvim_win_set_cursor(win, { current_line + 1, 0 })
		end
	end, { buffer = buf })

	vim.keymap.set("n", "<esc>", function()
		vim.cmd("close")
	end, { buffer = buf })

	vim.keymap.set("n", "<CR>", function()
		local current_line = vim.api.nvim_win_get_cursor(win)[1]
		local item_index = current_line - 2
		if item_index > 0 and item_index <= #M.vault_items then
			local selected_item = M.vault_items[item_index]
			selected_item = selected_item:gsub(line_delimiter, "\n")
			vim.fn.setreg("+", selected_item)
			vim.fn.setreg("*", selected_item)
			print('Vault item copied to clipboard')
		end
		vim.cmd("close")
	end, { buffer = buf })

	vim.keymap.set("n", "d", function()
		local current_line = vim.api.nvim_win_get_cursor(win)[1]
		local item_index = current_line - 2
		if item_index > 0 and item_index <= #M.vault_items then
			local confirm = vim.fn.confirm('Delete this vault item?', '&Yes\n&No', 2)
			if confirm == 1 then
				table.remove(M.vault_items, item_index)
				if save_vault(password) then
					print('Vault item deleted')
					vim.cmd("close")
					-- Reopen vault to show updated list
					vim.schedule(function() M.show_vault() end)
				else
					vim.api.nvim_err_writeln('Failed to save vault after deletion')
				end
			end
		end
	end, { buffer = buf })
end

-- Add current clipboard item to vault
function M.add_to_vault()
	local current_clipboard = vim.fn.getreg("+")
	if not current_clipboard or #current_clipboard == 0 then
		print('No clipboard content to add to vault')
		return
	end

	local password = get_password('Enter vault password to add item: ')
	if not password or #password == 0 then
		print('Vault access cancelled')
		return
	end

	-- Try to load existing vault
	if not load_vault(password) then
		-- If loading fails, it might be a new vault or wrong password
		-- For new vault, we'll initialize empty and continue
		M.vault_items = {}
	end

	-- Check for duplicates
	for _, item in ipairs(M.vault_items) do
		if item == current_clipboard then
			print('Item already exists in vault')
			return
		end
	end

	-- Add item to vault
	table.insert(M.vault_items, current_clipboard)

	if save_vault(password) then
		print('Item added to vault successfully')
	else
		vim.api.nvim_err_writeln('Failed to save item to vault')
		-- Remove the item we just added since save failed
		table.remove(M.vault_items)
	end
end

-- Add selected clipboard history item to vault
function M.add_history_to_vault(item_text)
	if not item_text or #item_text == 0 then
		print('No item selected to add to vault')
		return
	end

	local password = get_password('Enter vault password to add item: ')
	if not password or #password == 0 then
		print('Vault access cancelled')
		return
	end

	-- Try to load existing vault
	if not load_vault(password) then
		M.vault_items = {}
	end

	-- Check for duplicates
	for _, item in ipairs(M.vault_items) do
		if item == item_text then
			print('Item already exists in vault')
			return
		end
	end

	-- Add item to vault
	table.insert(M.vault_items, item_text)

	if save_vault(password) then
		print('Item added to vault successfully')
	else
		vim.api.nvim_err_writeln('Failed to save item to vault')
		table.remove(M.vault_items)
	end
end

-- Ensure the history in memory does not exceed max_items
local function trim_history()
	while #M.clipboard_history > config.max_items do
		table.remove(M.clipboard_history, 1)
	end
end

-- Append a single item to the file
local function append_to_file(text)
	local filename = config.file()
	local dir = vim.fn.fnamemodify(filename, ':h')
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, 'p')
	end
	local file, err = io.open(filename, 'a')
	if not file then
		vim.api.nvim_err_writeln('Failed to open clipboard file for appending: ' .. (err or ''))
		return
	end
	file:write(text .. "\n--CLIPBOARD-ITEM--\n")
	file:close()
end

-- Save the entire in-memory history to the configured file (used for trimming)
local function save_history_to_file()
	local filename = config.file()
	local dir = vim.fn.fnamemodify(filename, ':h')
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, 'p')
	end
	local file, err = io.open(filename, 'w')
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
	local filename = config.file()
	M.clipboard_history = {}
	local file = io.open(filename, 'r')
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
	if opts then
		config = vim.tbl_deep_extend("force", config, opts)
	end
	-- Load existing history on setup
	M.read_from_file()
	-- Ensure history respects new config immediately
	trim_history()
	save_history_to_file()

	-- setup mapping for clipboard buffer to be opened
	vim.keymap.set(config.keys.history_open[1], config.keys.history_open[2], function()
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
	end, { desc = 'Show clipboard history' })

	-- setup mapping for vault operations
	vim.keymap.set(config.keys.vault_append[1], config.keys.vault_append[2], function()
		M.add_to_vault()
	end, { desc = 'Add current clipboard to vault' })

	vim.keymap.set(config.keys.vault_open[1], config.keys.vault_open[2], function()
		M.show_vault()
	end, { desc = 'View vault items' })

	local id = vim.api.nvim_create_augroup("NvimClipboard", {})

	local old_clipboard = vim.fn.getreg("+")
	vim.api.nvim_create_autocmd("ModeChanged", {
		group = id,
		callback = function()
			local clipboard = vim.fn.getreg("+")
			if clipboard == old_clipboard then
				return
			end
			append_and_save(clipboard)
			old_clipboard = clipboard
			if config.notify == true then
				print('Clipboard updated: ' .. string.sub(clipboard, 1, 30) .. '...')
			end
		end
	})
end

return M
