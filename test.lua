#!/usr/bin/env nvim -l

-- Simple test script to debug clipboard functionality
local M = require('nvim-clipboard')

print("Testing clipboard functionality...")

-- Test 1: Check current clipboard
local current = vim.fn.getreg("+")
print("Current clipboard:", current)

-- Test 2: Set clipboard and test monitoring
print("Setting test clipboard content...")
vim.fn.setreg("+", "test content from lua script")

-- Test 3: Manually trigger monitor
print("Manually triggering clipboard monitor...")
M.monitor_clipboard()

-- Test 4: Read from file
print("Reading from file...")
local items = M.read_from_file()
print("Items loaded:", #items)
for i, item in ipairs(items) do
    print("Item " .. i .. ":", string.sub(item, 1, 50))
end

print("Test completed.")
