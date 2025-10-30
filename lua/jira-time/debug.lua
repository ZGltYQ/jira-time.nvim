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
    print('Cloud ID:', auth_data.cloud_id or 'MISSING')
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
  print('\n=== Testing API Call (via plugin) ===')
  print('Calling /rest/api/3/myself...')

  require('jira-time.api').get_current_user(function(user, error)
    if error then
      print('ERROR:', error)
    else
      print('SUCCESS! User:', vim.inspect(user))
    end
  end)

  -- Also test direct curl call
  M.test_api_request()
end

-- Test API request directly
function M.test_api_request()
  local auth = require('jira-time.auth')
  local token = auth.get_access_token()
  local cloud_id = auth.get_cloud_id()

  if not token then
    print('No token available')
    return
  end

  if not cloud_id then
    print('No cloud ID available - need to re-authenticate')
    return
  end

  local curl = require('plenary.curl')
  local url = 'https://api.atlassian.com/ex/jira/' .. cloud_id .. '/rest/api/3/myself'

  print('\n=== Direct API Test ===')
  print('Cloud ID:', cloud_id)
  print('URL:', url)
  print('Token (first 30 chars):', string.sub(token, 1, 30) .. '...')

  local ok, response = pcall(function()
    return curl.get(url, {
      headers = {
        ['Authorization'] = 'Bearer ' .. token,
        ['Accept'] = 'application/json',
      },
    })
  end)

  if not ok then
    print('ERROR: Request failed:', response)
    return
  end

  print('Status Code:', response.status)
  if response.status ~= 200 then
    print('ERROR Response Body:', response.body)
    print('Response Headers:', vim.inspect(response.headers))
  else
    print('SUCCESS! User info:', response.body)
  end
end

return M
