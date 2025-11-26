-- Configuration management for jira-time plugin
local M = {}

-- Default configuration
M.defaults = {
  -- Jira instance URL (required)
  jira_url = nil,

  -- OAuth 2.0 configuration
  oauth = {
    client_id = nil,
    client_secret = nil,
    redirect_uri = 'http://localhost:8080/callback',
    scopes = {
      'read:jira-work',
      'write:jira-work',
      'read:jira-user',
      'offline_access', -- For refresh tokens
    },
  },

  -- Token refresh configuration
  token_refresh = {
    proactive = true,              -- Enable proactive token refresh
    background_interval = 1800,    -- Background check interval in seconds (30 minutes)
    refresh_before_expiry = 1800,  -- Refresh token this many seconds before expiry (30 minutes)
    max_refresh_age_days = 60,     -- Trigger refresh if last refresh was more than this many days ago
  },

  -- Timer configuration
  timer = {
    auto_save_interval = 60, -- Save timer state every 60 seconds
    format = '%H:%M:%S', -- Time format (hours:minutes:seconds)
    -- Auto-tracking options
    auto_start_on_branch_change = true, -- Auto-start timer when entering branch with issue key
    auto_log_on_branch_change = true, -- Prompt to log time when switching branches
    auto_log_on_exit = true, -- Prompt to log time when closing Neovim
    minimum_log_seconds = 60, -- Minimum seconds before prompting to log (1 minute)
    skip_log_comment = true, -- Skip comment prompt for auto-logging
    branch_check_events = { 'FocusGained', 'BufEnter', 'VimResume' }, -- Events that trigger branch check
  },

  -- Statusline configuration
  statusline = {
    enabled = true,
    mode = 'standalone', -- 'standalone', 'lualine', or 'custom'
    format = '[%s] ⏱ %s', -- Format: [ISSUE-KEY] ⏱ HH:MM:SS
    show_when_inactive = false, -- Show issue even when timer is not running
    separator = ' | ',
    position = 'right', -- Position in statusline: 'left', 'center', or 'right'
  },

  -- Git branch patterns to extract Jira issue keys
  branch_patterns = {
    '([A-Z]+%-[0-9]+)', -- Standard PROJ-123 anywhere in branch name
    'feature/([A-Z]+%-[0-9]+)', -- feature/PROJ-123-description
    'bugfix/([A-Z]+%-[0-9]+)', -- bugfix/PROJ-123-description
    'hotfix/([A-Z]+%-[0-9]+)', -- hotfix/PROJ-123-description
  },

  -- UI configuration
  ui = {
    border = 'rounded', -- Border style for floating windows
    confirm_before_logging = true, -- Ask for confirmation before logging time
  },

  -- Keymaps configuration
  keymaps = {
    enabled = true, -- Enable default keymaps
    prefix = '<leader>j', -- Prefix for all jira-time keymaps
    -- Individual keymaps (set to false to disable)
    start = 's', -- <leader>js - Start timer
    stop = 'x', -- <leader>jx - Stop timer
    log = 'l', -- <leader>jl - Log time
    select = 'i', -- <leader>ji - Select issue
    view = 'v', -- <leader>jv - View worklogs
    status = 't', -- <leader>jt - Show status
  },

  -- Storage paths (automatically set based on stdpath)
  storage = {
    auth_file = nil, -- Set during setup
    timer_file = nil, -- Set during setup
  },
}

-- Current active configuration
M.options = {}

-- Setup configuration with user options
---@param opts table User configuration options
function M.setup(opts)
  -- Merge user options with defaults
  M.options = vim.tbl_deep_extend('force', M.defaults, opts or {})

  -- Set storage paths if not provided
  local data_path = vim.fn.stdpath('data') .. '/jira-time'
  M.options.storage.auth_file = M.options.storage.auth_file or (data_path .. '/auth.json')
  M.options.storage.timer_file = M.options.storage.timer_file or (data_path .. '/timer.json')

  -- Create storage directory if it doesn't exist
  vim.fn.mkdir(data_path, 'p')

  -- Validate required fields
  M.validate()

  return M.options
end

-- Validate configuration
function M.validate()
  local errors = {}

  -- jira_url is now optional (auto-discovered during authentication)

  if not M.options.oauth.client_id then
    table.insert(errors, 'oauth.client_id is required')
  end

  if not M.options.oauth.client_secret then
    table.insert(errors, 'oauth.client_secret is required')
  end

  if #errors > 0 then
    local error_msg = 'jira-time configuration errors:\n  - ' .. table.concat(errors, '\n  - ')
    vim.notify(error_msg, vim.log.levels.WARN)
    return false
  end

  return true
end

-- Get current configuration
function M.get()
  return M.options
end

return M
