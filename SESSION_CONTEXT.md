# Jira Time Tracker - Development Session Context

## Project Overview

A Neovim plugin for tracking time on Jira issues with OAuth 2.0 authentication to Atlassian Cloud.

**Repository**: https://github.com/ZGltYQ/jira-time.nvim

## Current Status: ✅ WORKING

The plugin is now fully functional with proper OAuth 2.0 authentication and Atlassian API integration.

## Problems Solved in This Session

### 1. OAuth URL Encoding Bug
**Issue**: Used `vim.fn.shellescape()` instead of proper URL encoding, causing malformed authorization URLs.

**Fix**: Implemented `url_encode()` function in:
- `lua/jira-time/auth.lua` (lines 16-29)
- `lua/jira-time/api.lua` (lines 13-26)

### 2. OAuth Callback Server Missing
**Issue**: Plugin expected manual code input but redirect to `localhost:8080/callback` failed with no server.

**Fix**: Created `lua/jira-time/oauth_server.lua` - HTTP server using `vim.loop` to automatically catch OAuth redirects.

### 3. OAuth Parameter Parsing Bug
**Issue**: Server regex expected `code` parameter first, but Atlassian sends `state` first.

**Fix**: Updated regex to handle parameters in any order (oauth_server.lua:34-35).

### 4. Infinite Token Refresh Recursion
**Issue**: When token expired, refresh attempt got 401, triggered another refresh, creating infinite loop.

**Fix**: Added `is_retry` flag to `M.request()` to prevent infinite recursion (api.lua:34, 107-120).

### 5. Token Refresh Timeout
**Issue**: Refresh requests timing out at 10 seconds.

**Fix**: Increased timeout to 30 seconds and added better error handling (auth.lua:218).

### 6. **CRITICAL: Wrong API Endpoint Format**
**Issue**: OAuth tokens cannot access Jira directly via `https://2smart.atlassian.net`. Got `401 Unauthorized`.

**Root Cause**: Atlassian OAuth requires using the API gateway format:
- ❌ Wrong: `https://2smart.atlassian.net/rest/api/3/...`
- ✅ Correct: `https://api.atlassian.com/ex/jira/{cloudId}/rest/api/3/...`

**Fix**:
- Added `get_cloud_id()` function to fetch accessible resources (auth.lua:69-86)
- Store cloud ID with tokens (auth.lua:135)
- Updated all API calls to use gateway format (api.lua:51)
- Added `get_cloud_id()` helper (auth.lua:308-317)

## Configuration

### User's Setup

Located in: `~/.config/nvim/lua/plugins/jira-time.lua`

```lua
return {
  'ZGltYQ/jira-time.nvim',
  dependencies = {
    'nvim-lua/plenary.nvim',
  },
  config = function()
    require('jira-time').setup({
      jira_url = 'https://your-site.atlassian.net',
      oauth = {
        client_id = 'YOUR_CLIENT_ID',
        client_secret = 'YOUR_CLIENT_SECRET',
      },
    })
  end,
}
```

### Atlassian OAuth App Settings

**Required Scopes** (must be configured in Atlassian Developer Console):
- `read:jira-work`
- `write:jira-work`
- `read:jira-user`
- `offline_access`

**Callback URL**: `http://localhost:8080/callback`

## How to Use

### First-Time Setup

1. **Authenticate**:
   ```vim
   :JiraAuth
   ```
   - Opens browser automatically
   - Redirects to success page after authorization
   - Stores tokens in `~/.local/share/nvim/jira-time/auth.json`

2. **Select and start tracking an issue**:
   ```vim
   :JiraTimeSelect
   ```

3. **Stop tracking**:
   ```vim
   :JiraTimeStop
   ```

4. **Log time to Jira**:
   ```vim
   :JiraTimeLog
   ```

### Available Commands

| Command | Description |
|---------|-------------|
| `:JiraAuth` | Authenticate with Atlassian OAuth |
| `:JiraLogout` | Clear authentication (logout) |
| `:JiraTimeSelect` | Select a Jira issue to track |
| `:JiraTimeStart [key]` | Start timer (auto-detects from git branch) |
| `:JiraTimeStop` | Stop timer |
| `:JiraTimeLog [duration]` | Log tracked time to Jira |
| `:JiraTimeView [key]` | View worklogs for issue |
| `:JiraTimeStatus` | Show plugin status |
| `:JiraTimeDebug` | Debug authentication and API calls |

### Re-Authentication Required After Update

If you authenticated before the cloud ID fix, you must re-authenticate:

```vim
:JiraLogout
:Lazy sync
:qa
nvim
:JiraAuth
```

## Technical Architecture

### OAuth 2.0 Flow

1. **Authorization Request** → Opens browser to `https://auth.atlassian.com/authorize`
2. **User Authorization** → User approves in browser
3. **Callback** → Redirects to `http://localhost:8080/callback?code=...&state=...`
4. **Local Server** → `oauth_server.lua` catches redirect
5. **Token Exchange** → Exchanges code for access/refresh tokens
6. **Cloud ID Discovery** → Fetches accessible Atlassian resources
7. **Store Tokens** → Saves to `~/.local/share/nvim/jira-time/auth.json`

### Stored Auth Data Structure

```json
{
  "access_token": "eyJraWQiOi...",
  "refresh_token": "eyJraWQiOi...",
  "expires_at": 1761822129,
  "cloud_id": "abc-123-def-456"
}
```

### API Request Flow

1. Get token and cloud ID from storage
2. Check if token expired → refresh if needed
3. Build URL: `https://api.atlassian.com/ex/jira/{cloudId}{endpoint}`
4. Make request with `Authorization: Bearer {token}`
5. Handle 401 → refresh token and retry (max 1 retry)

## File Structure

```
lua/jira-time/
├── init.lua           # Main plugin entry point
├── config.lua         # Configuration management
├── auth.lua           # OAuth 2.0 authentication
├── oauth_server.lua   # Local HTTP callback server
├── api.lua            # Jira REST API client
├── storage.lua        # Persistent data storage
├── timer.lua          # Time tracking logic
├── ui.lua             # User interface helpers
├── git.lua            # Git integration
├── statusline.lua     # Statusline integration
└── debug.lua          # Debug utilities

plugin/
└── jira-time.lua      # User commands

~/.local/share/nvim/jira-time/
├── auth.json          # OAuth tokens and cloud ID
└── timer.json         # Timer state
```

## Key Implementation Details

### URL Encoding
```lua
local function url_encode(str)
  str = string.gsub(str, '\n', '\r\n')
  str = string.gsub(str, '([^%w%-%.%_%~ ])', function(c)
    return string.format('%%%02X', string.byte(c))
  end)
  str = string.gsub(str, ' ', '+')
  return str
end
```

### OAuth Callback Server
Uses `vim.loop` (libuv) to create TCP server on port 8080. Parses HTTP request, extracts code/state, sends HTML response, then shuts down.

### Cloud ID Discovery
```lua
curl.get('https://api.atlassian.com/oauth/token/accessible-resources', {
  headers = { ['Authorization'] = 'Bearer ' .. token }
})
-- Returns: [{ "id": "cloud-id", "name": "Site Name", ... }]
```

### API Endpoint Format
```lua
local url = 'https://api.atlassian.com/ex/jira/' .. cloud_id .. endpoint
-- Example: https://api.atlassian.com/ex/jira/abc-123/rest/api/3/myself
```

## Known Issues & Limitations

1. **Single Jira Site**: Only supports first accessible resource. If user has multiple Jira sites, needs manual selection.
2. **Port 8080 Required**: OAuth callback requires port 8080 to be available.
3. **Token Refresh**: Synchronous operations during refresh may block UI briefly.
4. **No Token Revocation**: Logout only clears local storage, doesn't revoke tokens on Atlassian side.

## Future Improvements

- [ ] Support multiple Jira sites with site selector
- [ ] Async/non-blocking token refresh
- [ ] Token revocation on logout
- [ ] Configurable callback port
- [ ] Better error recovery from network failures
- [ ] Worklog templates for common comments
- [ ] Integration with telescope.nvim for issue selection
- [ ] Branch name auto-generation from issue key

## Debugging

### Check Authentication Status
```vim
:JiraTimeDebug
```

Shows:
- Token existence and expiration
- Cloud ID
- Configuration
- Direct API test with full response

### Check Auth File
```bash
cat ~/.local/share/nvim/jira-time/auth.json | jq
```

### Test API Manually
```bash
TOKEN=$(cat ~/.local/share/nvim/jira-time/auth.json | jq -r '.access_token')
CLOUD_ID=$(cat ~/.local/share/nvim/jira-time/auth.json | jq -r '.cloud_id')

curl -H "Authorization: Bearer $TOKEN" \
     -H "Accept: application/json" \
     "https://api.atlassian.com/ex/jira/$CLOUD_ID/rest/api/3/myself"
```

### Common Errors

**"Not authenticated"**: Run `:JiraAuth` to authenticate.

**"Authentication failed"**: Token expired or invalid. Run `:JiraLogout` then `:JiraAuth`.

**"Failed to get cloud ID"**: Check OAuth scopes are configured in Atlassian Developer Console.

**Port 8080 in use**: Kill process using port or wait for OAuth callback to timeout.

## Git History Reference

Key commits:
- `5f89256` - Implement cloud ID discovery (CRITICAL FIX)
- `cb6068d` - Fix infinite token refresh recursion
- `cd6a65e` - Fix JQL URL encoding
- `1c047c6` - Fix OAuth callback parameter parsing
- `ae75a5c` - Add OAuth callback server
- `effa29b` - Fix URL encoding bugs

## Links & Resources

- **Atlassian OAuth 2.0 Docs**: https://developer.atlassian.com/cloud/jira/platform/oauth-2-3lo-apps/
- **Jira REST API v3**: https://developer.atlassian.com/cloud/jira/platform/rest/v3/
- **OAuth Accessible Resources**: https://developer.atlassian.com/cloud/jira/platform/oauth-2-3lo-apps/#2--select-the-jira-site-to-access

---

**Last Updated**: 2025-10-30
**Session Duration**: ~2 hours
**Status**: Fully functional ✅
