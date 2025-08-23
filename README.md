### About the plugin

The aim of this plugin is to capture the clipboard history and provide a way to browse through the recently yanked items,
be it on the system clipboard or the VIM clipboard(The 2 are different)

The selection registers are the bridge to connect Vim and the system clipboard. Vim has two selection registers: `* and +`
We will be utilizing these registers to capture and modify the clipboard history.

### New Feature: Secure Vault

The plugin now includes a **password-protected vault** feature that allows you to save important clipboard items securely:

- **Encrypted Storage**: Vault items are encrypted using password-based encryption
- **No Password Storage**: Your password is never saved anywhere - you enter it each time
- **Selective Storage**: Choose which clipboard items to save to the vault
- **Configurable Location**: Set a custom vault file location or use the default

### Functionality Roadmap

- [x] Capture the clipboard history
- [x] Save the clipboard history to persistant storage
- [x] Browse through the clipboard history
- [x] Select item in the clipboad history to yank them back to the clipboard
- [ ] Delete items from the clipboard history
- [x] Provide configuration and limit the number of items in the clipboard history
- [ ] Provide a way to search through the clipboard history
- [ ] Support multi line clipboard items to be yanked as one
- [x] **Secure vault with password protection**
- [x] **Add items to vault from clipboard history**
- [x] **View and manage vault items**

### Configuration

```lua
require('nvim-clipboard').setup({
    max_items = 10,                                          -- Max clipboard history items
    file = vim.fn.getcwd() .. '/clipboard.txt',             -- Clipboard history file
    vault_file = vim.fn.stdpath('data') .. '/vault.dat'     -- Vault file location (optional)
})
```

### Keymaps

#### Default Keymaps
- `<leader>b` - Open clipboard history browser
- `<leader>va` - Add current clipboard content to vault
- `<leader>vv` - Open vault browser

#### In Clipboard History Browser
- `↑/↓` - Navigate items
- `Enter` - Copy selected item to clipboard
- `v` - Add selected item to vault
- `Esc` - Close browser

#### In Vault Browser
- `↑/↓` - Navigate items
- `Enter` - Copy selected item to clipboard
- `d` - Delete selected item from vault
- `Esc` - Close browser

### Security Note

The vault uses XOR-based encryption for demonstration purposes. In a production environment, consider using a proper cryptographic library for stronger encryption.
