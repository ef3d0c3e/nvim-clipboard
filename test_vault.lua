-- Test file for nvim-clipboard vault functionality
-- This demonstrates how to configure and use the vault feature

-- Load the plugin
local clipboard = require('nvim-clipboard')

-- Setup with custom vault file location
clipboard.setup({
    max_items = 10,
    file = vim.fn.getcwd() .. '/clipboard.txt',
    vault_file = vim.fn.getcwd() .. '/secure_vault.dat'  -- Custom vault location
})

-- Example usage:
print("=== Nvim-Clipboard Vault Test ===")
print("Available commands:")
print("1. <leader>b  - Show clipboard history")
print("2. <leader>va - Add current clipboard to vault") 
print("3. <leader>vv - View vault items")
print("4. In clipboard history: press 'v' to add item to vault")
print("5. In vault view: press 'd' to delete item")
print("")
print("The vault file will be encrypted and stored at:")
print(vim.fn.getcwd() .. '/secure_vault.dat')
print("")
print("Tips:")
print("- Copy some text to test clipboard history")
print("- Use a strong password for your vault")
print("- The password is never stored anywhere")
print("- Vault items are encrypted using XOR (demo encryption)")
