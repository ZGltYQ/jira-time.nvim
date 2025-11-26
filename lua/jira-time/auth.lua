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

-- Get Atlassian cloud ID for the user's accessible resources
---@param access_token string Access token
---@return string|nil cloud_id Cloud ID or nil on error
local function get_cloud_id(access_token)
  local response = curl.get('https://api.atlassian.com/oauth/token/accessible-resources', {
    headers = {
      ['Authorization'] = 'Bearer ' .. access_token,
      ['Accept'] = 'application/json',
    },
  })

  if response.status == 200 then
    local ok, resources = pcall(vim.json.decode, response.body)
    if ok and resources and #resources > 0 then
      -- Return the first accessible resource's cloud ID
      return resources[1].id
    end
  end

  return nil
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
    if ok and token_data.access_token then
      -- Get cloud ID
      vim.notify('Getting Atlassian cloud ID...', vim.log.levels.INFO)
      local cloud_id = get_cloud_id(token_data.access_token)

      if not cloud_id then
        vim.notify('Failed to get cloud ID. Check your permissions.', vim.log.levels.ERROR)
        callback(false)
        return
      end

      -- Save tokens with cloud ID and lifecycle metadata
      local current_time = os.time()
      local auth_data = {
        access_token = token_data.access_token,
        refresh_token = token_data.refresh_token,
        expires_at = current_time + (token_data.expires_in or 3600),
        cloud_id = cloud_id,
        refresh_token_issued_at = current_time,  -- Track when refresh token was obtained
        last_refresh_at = current_time,          -- Track last refresh time
        token_version = 1,                       -- Schema version for future migrations
      }

      storage.save_auth(auth_data)
      vim.notify('✓ Successfully authenticated with Jira (Cloud ID: ' .. cloud_id .. ')', vim.log.levels.INFO)
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

  vim.notify('Refreshing access token...', vim.log.levels.DEBUG)

  -- Make request with error handling and timeout
  local ok, response = pcall(function()
    return curl.post(OAUTH_TOKEN_URL, {
      headers = {
        ['Content-Type'] = 'application/x-www-form-urlencoded',
      },
      body = body,
      timeout = 30000, -- 30 second timeout
    })
  end)

  if not ok then
    vim.notify('Token refresh request failed: ' .. tostring(response), vim.log.levels.ERROR)
    callback(false)
    return
  end

  if response.status == 200 then
    local parse_ok, token_data = pcall(vim.json.decode, response.body)
    if parse_ok and token_data.access_token then
      -- Update tokens and lifecycle metadata
      local current_time = os.time()
      auth_data.access_token = token_data.access_token
      auth_data.refresh_token = token_data.refresh_token or auth_data.refresh_token
      auth_data.expires_at = current_time + (token_data.expires_in or 3600)
      auth_data.last_refresh_at = current_time

      -- If we got a new refresh token, update the issued time
      if token_data.refresh_token then
        auth_data.refresh_token_issued_at = current_time
      end

      -- Ensure token_version is set
      auth_data.token_version = auth_data.token_version or 1

      storage.save_auth(auth_data)
      vim.notify('Token refreshed successfully', vim.log.levels.DEBUG)
      callback(true)
    else
      vim.notify('Failed to parse token response', vim.log.levels.ERROR)
      callback(false)
    end
  else
    local error_msg = 'Token refresh failed with status ' .. response.status
    local error_detail = nil

    -- Try to parse error response
    if response.body then
      local parse_ok, error_data = pcall(vim.json.decode, response.body)
      if parse_ok and error_data.error then
        error_detail = error_data.error

        -- Specific error handling
        if error_detail == 'invalid_grant' then
          error_msg = 'Refresh token expired or invalid. Please run :JiraAuth to re-authenticate'
        elseif error_detail == 'unauthorized_client' then
          error_msg = 'OAuth client not authorized. Check your client_id and client_secret'
        elseif error_data.error_description then
          error_msg = error_msg .. ': ' .. error_data.error_description
        end
      end
      vim.notify('Response: ' .. response.body, vim.log.levels.DEBUG)
    end

    vim.notify(error_msg, vim.log.levels.ERROR)

    -- Store error for diagnostics
    auth_data.last_refresh_error = {
      status = response.status,
      error = error_detail,
      timestamp = os.time(),
    }
    storage.save_auth(auth_data)

    callback(false)
  end
end

-- Check if token should be refreshed proactively
---@param auth_data table Auth data to check
---@return boolean should_refresh True if token should be refreshed
local function should_refresh_token(auth_data)
  if not auth_data or not auth_data.refresh_token then
    return false
  end

  -- Get config values
  local config = require('jira-time.config').get()
  local token_config = config.token_refresh

  -- Check if proactive refresh is enabled
  if not token_config.proactive then
    return false
  end

  local current_time = os.time()

  -- Trigger 1: Access token expires soon
  if auth_data.expires_at and (auth_data.expires_at - current_time) < token_config.refresh_before_expiry then
    return true
  end

  -- Trigger 2: Last refresh was too long ago (keep refresh token active)
  if auth_data.last_refresh_at then
    local days_since_refresh = (current_time - auth_data.last_refresh_at) / 86400
    if days_since_refresh > token_config.max_refresh_age_days then
      return true
    end
  end

  return false
end

-- Migrate auth data to latest schema
---@param auth_data table Auth data to migrate
---@return table auth_data Migrated auth data
---@return boolean migrated True if migration was performed
local function migrate_auth_data(auth_data)
  if not auth_data then
    return auth_data, false
  end

  local migrated = false
  local current_time = os.time()

  -- Check if migration is needed (missing new fields from v1 schema)
  if not auth_data.token_version or auth_data.token_version < 1 then
    -- Add missing fields with conservative defaults
    if not auth_data.refresh_token_issued_at then
      -- Conservative: assume refresh token was just issued
      auth_data.refresh_token_issued_at = current_time
      migrated = true
    end

    if not auth_data.last_refresh_at then
      -- Conservative: assume token was just refreshed
      auth_data.last_refresh_at = current_time
      migrated = true
    end

    auth_data.token_version = 1
    migrated = true
  end

  return auth_data, migrated
end

-- Get current access token (refreshes if expired)
---@return string|nil token Access token or nil if not authenticated
function M.get_access_token()
  local storage = require('jira-time.storage')
  local auth_data = storage.load_auth()

  if not auth_data or not auth_data.access_token then
    return nil
  end

  -- Migrate old auth data if needed
  local migrated
  auth_data, migrated = migrate_auth_data(auth_data)
  if migrated then
    storage.save_auth(auth_data)
    vim.notify('Auth data migrated to new schema', vim.log.levels.DEBUG)
  end

  -- Check if token is expired
  if auth_data.expires_at and os.time() >= auth_data.expires_at then
    -- Token expired, need to refresh
    -- Note: This is synchronous check, actual refresh happens in API module
    return nil
  end

  -- Proactive refresh: check if token should be refreshed in background
  if should_refresh_token(auth_data) then
    vim.notify('Token expiring soon, refreshing in background...', vim.log.levels.DEBUG)
    -- Trigger async refresh in background (non-blocking)
    vim.schedule(function()
      M.refresh_token(function(success)
        if success then
          vim.notify('Token proactively refreshed', vim.log.levels.DEBUG)
        else
          vim.notify('Proactive token refresh failed', vim.log.levels.WARN)
        end
      end)
    end)
  end

  return auth_data.access_token
end

-- Get Atlassian cloud ID from stored auth
---@return string|nil cloud_id Cloud ID or nil if not authenticated
function M.get_cloud_id()
  local storage = require('jira-time.storage')
  local auth_data = storage.load_auth()

  if not auth_data or not auth_data.cloud_id then
    return nil
  end

  return auth_data.cloud_id
end

-- Check if user is authenticated
---@return boolean authenticated True if authenticated
function M.is_authenticated()
  return M.get_access_token() ~= nil and M.get_cloud_id() ~= nil
end

-- Logout (clear auth data)
function M.logout()
  local storage = require('jira-time.storage')
  storage.clear_auth()
end

-- Get token information for diagnostics
---@return table|nil token_info Token information or nil if not authenticated
function M.get_token_info()
  local storage = require('jira-time.storage')
  local auth_data = storage.load_auth()

  if not auth_data then
    return nil
  end

  local current_time = os.time()
  local info = {
    authenticated = auth_data.access_token ~= nil,
    has_refresh_token = auth_data.refresh_token ~= nil,
  }

  -- Access token expiration
  if auth_data.expires_at then
    info.access_token_expires_at = auth_data.expires_at
    info.access_token_expires_in_seconds = math.max(0, auth_data.expires_at - current_time)
    info.access_token_expired = current_time >= auth_data.expires_at
  end

  -- Refresh token age
  if auth_data.refresh_token_issued_at then
    local days_old = (current_time - auth_data.refresh_token_issued_at) / 86400
    info.refresh_token_age_days = math.floor(days_old)
    info.refresh_token_issued_at = auth_data.refresh_token_issued_at
  end

  -- Last refresh time
  if auth_data.last_refresh_at then
    local days_since = (current_time - auth_data.last_refresh_at) / 86400
    info.last_refresh_at = auth_data.last_refresh_at
    info.days_since_last_refresh = days_since
  end

  -- Last error
  if auth_data.last_refresh_error then
    info.last_error = auth_data.last_refresh_error
  end

  -- Cloud ID
  if auth_data.cloud_id then
    info.cloud_id = auth_data.cloud_id
  end

  -- Schema version
  info.token_version = auth_data.token_version or 0

  return info
end

return M
