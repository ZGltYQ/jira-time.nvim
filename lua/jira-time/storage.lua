-- Storage module for persisting data to disk
local M = {}

-- Read JSON file
---@param filepath string Path to JSON file
---@return table|nil data Parsed JSON data or nil if file doesn't exist
function M.read_json(filepath)
  local file = io.open(filepath, 'r')
  if not file then
    return nil
  end

  local content = file:read('*all')
  file:close()

  if not content or content == '' then
    return nil
  end

  local ok, data = pcall(vim.json.decode, content)
  if not ok then
    vim.notify('Failed to parse JSON from ' .. filepath, vim.log.levels.ERROR)
    return nil
  end

  return data
end

-- Write data to JSON file
---@param filepath string Path to JSON file
---@param data table Data to write
---@return boolean success True if write was successful
function M.write_json(filepath, data)
  local ok, json_str = pcall(vim.json.encode, data)
  if not ok then
    vim.notify('Failed to encode data to JSON', vim.log.levels.ERROR)
    return false
  end

  -- Ensure directory exists
  local dir = vim.fn.fnamemodify(filepath, ':h')
  vim.fn.mkdir(dir, 'p')

  local file = io.open(filepath, 'w')
  if not file then
    vim.notify('Failed to open file for writing: ' .. filepath, vim.log.levels.ERROR)
    return false
  end

  file:write(json_str)
  file:close()

  return true
end

-- Load auth data (OAuth tokens)
---@return table|nil auth_data OAuth token data
function M.load_auth()
  local config = require('jira-time.config').get()
  return M.read_json(config.storage.auth_file)
end

-- Save auth data (OAuth tokens)
---@param auth_data table OAuth token data
---@return boolean success True if save was successful
function M.save_auth(auth_data)
  local config = require('jira-time.config').get()
  return M.write_json(config.storage.auth_file, auth_data)
end

-- Load timer state
---@return table|nil timer_state Timer state data
function M.load_timer()
  local config = require('jira-time.config').get()
  return M.read_json(config.storage.timer_file)
end

-- Save timer state
---@param timer_state table Timer state data
---@return boolean success True if save was successful
function M.save_timer(timer_state)
  local config = require('jira-time.config').get()
  return M.write_json(config.storage.timer_file, timer_state)
end

-- Clear auth data (logout)
---@return boolean success True if clear was successful
function M.clear_auth()
  local config = require('jira-time.config').get()
  local ok = os.remove(config.storage.auth_file)
  if ok then
    vim.notify('Authentication data cleared', vim.log.levels.INFO)
    return true
  end
  return false
end

-- Clear timer state
---@return boolean success True if clear was successful
function M.clear_timer()
  local config = require('jira-time.config').get()
  local ok = os.remove(config.storage.timer_file)
  if ok then
    return true
  end
  return false
end

return M
