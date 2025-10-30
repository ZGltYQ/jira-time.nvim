-- OAuth 2.0 authentication module for Atlassian Jira
local M = {}

local has_plenary, curl = pcall(require, 'plenary.curl')
if not has_plenary then
  vim.notify(
    'jira-time requires plenary.nvim. Please install: nvim-lua/plenary.nvim',
    vim.log.levels.ERROR
  )
end

-- OAuth endpoints
local OAUTH_AUTHORIZE_URL = 'https://auth.atlassian.com/authorize'
local OAUTH_TOKEN_URL = 'https://auth.atlassian.com/oauth/token'

-- URL encode a string
---@param str string String to encode
---@return string encoded URL encoded string
local function url_encode(str)
  if str == nil then
    return ''
  end
  str = string.gsub(str, '\n', '\r\n')
  str = string.gsub(str, '([^%w%-%.%_%~ ])', function(c)
    return string.format('%%%02X', string.byte(c))
  end)
  str = string.gsub(str, ' ', '+')
  return str
end

-- Generate random state for OAuth security
---@return string state Random state string
local function generate_state()
  local chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
  local state = ''
  for _ = 1, 32 do
    local idx = math.random(1, #chars)
    state = state .. chars:sub(idx, idx)
  end
  return state
end

-- Build authorization URL
---@param config table OAuth configuration
---@param state string State parameter for security
---@return string url Authorization URL
local function build_auth_url(config, state)
  local params = {
    audience = 'api.atlassian.com',
    client_id = config.oauth.client_id,
    scope = table.concat(config.oauth.scopes, ' '),
    redirect_uri = config.oauth.redirect_uri,
    state = state,
    response_type = 'code',
    prompt = 'consent',
  }

  local query_parts = {}
  for key, value in pairs(params) do
    table.insert(query_parts, key .. '=' .. url_encode(value))
  end

  return OAUTH_AUTHORIZE_URL .. '?' .. table.concat(query_parts, '&')
end

-- Exchange authorization code for access token
---@param code string Authorization code
---@param callback function Callback function(success)
local function exchange_code_for_token(code, callback)
  local config = require('jira-time.config').get()
  local storage = require('jira-time.storage')

  local data = {
    grant_type = 'authorization_code',
    client_id = config.oauth.client_id,
    client_secret = config.oauth.client_secret,
    code = code,
    redirect_uri = config.oauth.redirect_uri,
  }

  -- Convert data to URL-encoded form
  local body_parts = {}
  for key, value in pairs(data) do
    table.insert(body_parts, key .. '=' .. url_encode(value))
  end
  local body = table.concat(body_parts, '&')

  local response = curl.post(OAUTH_TOKEN_URL, {
    headers = {
      ['Content-Type'] = 'application/x-www-form-urlencoded',
    },
    body = body,
  })

  if response.status == 200 then
    local ok, token_data = pcall(vim.json.decode, response.body)
    if ok then
      -- Save tokens
      local auth_data = {
        access_token = token_data.access_token,
        refresh_token = token_data.refresh_token,
        expires_at = os.time() + (token_data.expires_in or 3600),
      }

      storage.save_auth(auth_data)
      vim.notify('✓ Successfully authenticated with Jira', vim.log.levels.INFO)
      callback(true)
    else
      vim.notify('Failed to parse token response', vim.log.levels.ERROR)
      callback(false)
    end
  else
    vim.notify('Failed to exchange authorization code: ' .. response.status, vim.log.levels.ERROR)
    callback(false)
  end
end

-- Start OAuth 2.0 authentication flow
function M.authenticate()
  local config = require('jira-time.config').get()
  local oauth_server = require('jira-time.oauth_server')

  -- Validate OAuth configuration
  if not config.oauth.client_id or not config.oauth.client_secret then
    vim.notify(
      'OAuth configuration missing. Please set oauth.client_id and oauth.client_secret in your config.',
      vim.log.levels.ERROR
    )
    return
  end

  local state = generate_state()
  local auth_url = build_auth_url(config, state)

  -- Start local callback server
  local port = 8080
  vim.notify('Starting OAuth callback server on port ' .. port .. '...', vim.log.levels.INFO)

  local server = oauth_server.start_server(port, function(code, received_state)
    -- Verify state to prevent CSRF attacks
    if received_state ~= state then
      vim.notify('Security error: State mismatch. Authentication aborted.', vim.log.levels.ERROR)
      return
    end

    vim.notify('Authorization code received. Exchanging for access token...', vim.log.levels.INFO)

    -- Exchange code for token
    exchange_code_for_token(code, function(success)
      if not success then
        vim.notify('Failed to exchange authorization code for token', vim.log.levels.ERROR)
      end
    end)
  end)

  -- Wait a moment for server to start
  vim.defer_fn(function()
    -- Display instructions to user
    vim.notify(
      'Opening browser for authentication...\nYou will be redirected automatically after authorization.',
      vim.log.levels.INFO
    )

    -- Open browser (cross-platform)
    local open_cmd
    if vim.fn.has('mac') == 1 then
      open_cmd = 'open'
    elseif vim.fn.has('unix') == 1 then
      open_cmd = 'xdg-open'
    elseif vim.fn.has('win32') == 1 then
      open_cmd = 'start'
    else
      vim.notify('Unable to open browser automatically. Please open this URL manually:', vim.log.levels.WARN)
      print(auth_url)
      return
    end

    vim.fn.system(open_cmd .. ' "' .. auth_url .. '"')
  end, 100)
end

-- Refresh access token using refresh token
---@param callback function Callback function(success)
function M.refresh_token(callback)
  local storage = require('jira-time.storage')
  local config = require('jira-time.config').get()

  local auth_data = storage.load_auth()
  if not auth_data or not auth_data.refresh_token then
    vim.notify('No refresh token available. Please authenticate again.', vim.log.levels.ERROR)
    callback(false)
    return
  end

  local data = {
    grant_type = 'refresh_token',
    client_id = config.oauth.client_id,
    client_secret = config.oauth.client_secret,
    refresh_token = auth_data.refresh_token,
  }

  -- Convert data to URL-encoded form
  local body_parts = {}
  for key, value in pairs(data) do
    table.insert(body_parts, key .. '=' .. url_encode(value))
  end
  local body = table.concat(body_parts, '&')

  local response = curl.post(OAUTH_TOKEN_URL, {
    headers = {
      ['Content-Type'] = 'application/x-www-form-urlencoded',
    },
    body = body,
  })

  if response.status == 200 then
    local ok, token_data = pcall(vim.json.decode, response.body)
    if ok then
      -- Update tokens
      auth_data.access_token = token_data.access_token
      auth_data.refresh_token = token_data.refresh_token or auth_data.refresh_token
      auth_data.expires_at = os.time() + (token_data.expires_in or 3600)

      storage.save_auth(auth_data)
      callback(true)
    else
      callback(false)
    end
  else
    callback(false)
  end
end

-- Get current access token (refreshes if expired)
---@return string|nil token Access token or nil if not authenticated
function M.get_access_token()
  local storage = require('jira-time.storage')
  local auth_data = storage.load_auth()

  if not auth_data or not auth_data.access_token then
    return nil
  end

  -- Check if token is expired
  if auth_data.expires_at and os.time() >= auth_data.expires_at then
    -- Token expired, need to refresh
    -- Note: This is synchronous check, actual refresh happens in API module
    return nil
  end

  return auth_data.access_token
end

-- Check if user is authenticated
---@return boolean authenticated True if authenticated
function M.is_authenticated()
  return M.get_access_token() ~= nil
end

-- Logout (clear auth data)
function M.logout()
  local storage = require('jira-time.storage')
  storage.clear_auth()
end

return M
