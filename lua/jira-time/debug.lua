-- Debug utilities
local M = {}

-- Test authentication and token
function M.test_auth()
  local auth = require('jira-time.auth')
  local storage = require('jira-time.storage')
  local config = require('jira-time.config').get()

  print('=== Authentication Debug ===')
  print('Authenticated:', auth.is_authenticated())

  local auth_data = storage.load_auth()
  if auth_data then
    print('Token exists:', auth_data.access_token and 'YES' or 'NO')
    if auth_data.access_token then
      print('Token prefix:', string.sub(auth_data.access_token, 1, 20) .. '...')
    end
    print('Expires at:', auth_data.expires_at)
    print('Current time:', os.time())
    print('Expired:', auth_data.expires_at and (os.time() >= auth_data.expires_at) and 'YES' or 'NO')
    print('Has refresh token:', auth_data.refresh_token and 'YES' or 'NO')
  else
    print('No auth data found')
  end

  print('\n=== Configuration ===')
  print('Jira URL:', config.jira_url)
  print('Client ID:', config.oauth.client_id)

  -- Test actual API call
  print('\n=== Testing API Call ===')
  print('Calling /rest/api/3/myself...')

  require('jira-time.api').get_current_user(function(user, error)
    if error then
      print('ERROR:', error)
    else
      print('SUCCESS! User:', vim.inspect(user))
    end
  end)
end

-- Test API request directly
function M.test_api_request()
  local config = require('jira-time.config').get()
  local auth = require('jira-time.auth')
  local token = auth.get_access_token()

  if not token then
    print('No token available')
    return
  end

  local curl = require('plenary.curl')
  local url = config.jira_url .. '/rest/api/3/myself'

  print('Testing direct API call to:', url)
  print('Token:', string.sub(token, 1, 30) .. '...')

  local response = curl.get(url, {
    headers = {
      ['Authorization'] = 'Bearer ' .. token,
      ['Accept'] = 'application/json',
    },
  })

  print('Status:', response.status)
  print('Body:', response.body)
end

return M
