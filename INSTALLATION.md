# Installation Guide - jira-time.nvim

Complete installation guide for jira-time.nvim across different plugin managers and setups.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Method 1: lazy.nvim (Recommended)](#method-1-lazynvim-recommended)
- [Method 2: packer.nvim](#method-2-packernvim)
- [Method 3: vim-plug](#method-3-vim-plug)
- [Method 4: Manual Installation](#method-4-manual-installation)
- [Post-Installation Setup](#post-installation-setup)
- [Verifying Installation](#verifying-installation)

## Prerequisites

Before installing jira-time.nvim, ensure you have:

### Required
- **Neovim** >= 0.8.0
  ```bash
  nvim --version  # Check your version
  ```
- **Git** installed on your system
  ```bash
  git --version
  ```
- **Jira Account** with access to Atlassian Jira

### Dependencies
- **plenary.nvim** - Required for HTTP requests
- **lualine.nvim** - Optional, for statusline integration

## Method 1: lazy.nvim (Recommended)

[lazy.nvim](https://github.com/folke/lazy.nvim) is the modern plugin manager for Neovim.

### Step 1: Install lazy.nvim (if not already installed)

Add to `~/.config/nvim/init.lua` or `~/.config/nvim/lua/config/lazy.lua`:

```lua
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)
```

### Step 2: Add jira-time.nvim to your plugins

Create or edit `~/.config/nvim/lua/plugins/jira-time.lua`:

```lua
return {
  {
    'YOUR-USERNAME/jira-time.nvim',
    dependencies = {
      'nvim-lua/plenary.nvim',
    },
    opts = {
      jira_url = 'https://YOUR-COMPANY.atlassian.net',
      oauth = {
        client_id = 'YOUR_OAUTH_CLIENT_ID',
        client_secret = 'YOUR_OAUTH_CLIENT_SECRET',
      },
    },
  },
}
```

Or add directly to your main config:

```lua
require("lazy").setup({
  {
    'YOUR-USERNAME/jira-time.nvim',
    dependencies = { 'nvim-lua/plenary.nvim' },
    config = function()
      require('jira-time').setup({
        jira_url = 'https://YOUR-COMPANY.atlassian.net',
        oauth = {
          client_id = 'YOUR_OAUTH_CLIENT_ID',
          client_secret = 'YOUR_OAUTH_CLIENT_SECRET',
        },
      })
    end,
  },
})
```

### Step 3: Restart Neovim

```bash
nvim
```

lazy.nvim will automatically install the plugin on startup.

## Method 2: packer.nvim

[packer.nvim](https://github.com/wbthomason/packer.nvim) is a popular use-package inspired plugin manager.

### Step 1: Install packer.nvim (if not already installed)

```bash
git clone --depth 1 https://github.com/wbthomason/packer.nvim \
  ~/.local/share/nvim/site/pack/packer/start/packer.nvim
```

### Step 2: Add to your plugin configuration

Edit `~/.config/nvim/lua/plugins.lua` or equivalent:

```lua
return require('packer').startup(function(use)
  -- Packer can manage itself
  use 'wbthomason/packer.nvim'

  -- Required dependency
  use 'nvim-lua/plenary.nvim'

  -- jira-time.nvim
  use {
    'YOUR-USERNAME/jira-time.nvim',
    requires = { 'nvim-lua/plenary.nvim' },
    config = function()
      require('jira-time').setup({
        jira_url = 'https://YOUR-COMPANY.atlassian.net',
        oauth = {
          client_id = 'YOUR_OAUTH_CLIENT_ID',
          client_secret = 'YOUR_OAUTH_CLIENT_SECRET',
        },
      })
    end,
  }
end)
```

### Step 3: Install plugins

Open Neovim and run:

```vim
:PackerSync
```

## Method 3: vim-plug

[vim-plug](https://github.com/junegunn/vim-plug) works with both Vim and Neovim.

### Step 1: Install vim-plug (if not already installed)

```bash
sh -c 'curl -fLo "${XDG_DATA_HOME:-$HOME/.local/share}"/nvim/site/autoload/plug.vim --create-dirs \
       https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
```

### Step 2: Add to your init.vim or init.lua

For `init.vim`:

```vim
call plug#begin()
  Plug 'nvim-lua/plenary.nvim'
  Plug 'YOUR-USERNAME/jira-time.nvim'
call plug#end()

lua << EOF
require('jira-time').setup({
  jira_url = 'https://YOUR-COMPANY.atlassian.net',
  oauth = {
    client_id = 'YOUR_OAUTH_CLIENT_ID',
    client_secret = 'YOUR_OAUTH_CLIENT_SECRET',
  },
})
EOF
```

For `init.lua`:

```lua
vim.call('plug#begin')
  vim.cmd([[Plug 'nvim-lua/plenary.nvim']])
  vim.cmd([[Plug 'YOUR-USERNAME/jira-time.nvim']])
vim.call('plug#end')

require('jira-time').setup({
  jira_url = 'https://YOUR-COMPANY.atlassian.net',
  oauth = {
    client_id = 'YOUR_OAUTH_CLIENT_ID',
    client_secret = 'YOUR_OAUTH_CLIENT_SECRET',
  },
})
```

### Step 3: Install plugins

```vim
:PlugInstall
```

## Method 4: Manual Installation

### Step 1: Clone the repository

```bash
# Create plugin directory
mkdir -p ~/.local/share/nvim/site/pack/manual/start

# Clone jira-time.nvim
cd ~/.local/share/nvim/site/pack/manual/start
git clone https://github.com/YOUR-USERNAME/jira-time.nvim.git

# Clone plenary.nvim dependency
git clone https://github.com/nvim-lua/plenary.nvim.git
```

### Step 2: Add configuration to init.lua

Edit `~/.config/nvim/init.lua`:

```lua
require('jira-time').setup({
  jira_url = 'https://YOUR-COMPANY.atlassian.net',
  oauth = {
    client_id = 'YOUR_OAUTH_CLIENT_ID',
    client_secret = 'YOUR_OAUTH_CLIENT_SECRET',
  },
})
```

### Step 3: Restart Neovim

```bash
nvim
```

## Post-Installation Setup

After installing the plugin, you need to configure OAuth credentials.

### 1. Create Atlassian OAuth 2.0 App

1. Go to [Atlassian Developer Console](https://developer.atlassian.com/console/myapps/)
2. Click **"Create"** → **"OAuth 2.0 integration"**
3. Fill in the form:
   - **App name**: Neovim Jira Time Tracker
   - **App description**: Time tracking from Neovim
4. Click **"Permissions"** tab
5. Click **"Add"** → **"Jira API"**
6. Click **"Configure"** next to OAuth 2.0 (3LO)
7. Add **Callback URL**: `http://localhost:8080/callback`
8. Add required **Scopes**:
   - `read:jira-work` - View worklogs
   - `write:jira-work` - Add worklogs
   - `read:jira-user` - View user info
   - `offline_access` - Refresh tokens
9. Click **"Save"**
10. Go to **"Settings"** tab and copy:
    - **Client ID**
    - **Secret** (click "New secret" if needed)

### 2. Update Plugin Configuration

Update your plugin configuration with the credentials:

```lua
require('jira-time').setup({
  jira_url = 'https://yourcompany.atlassian.net', -- Your Jira URL
  oauth = {
    client_id = 'paste_your_client_id_here',
    client_secret = 'paste_your_client_secret_here',
  },
})
```

**Important:** Keep your `client_secret` private! Consider using environment variables:

```lua
require('jira-time').setup({
  jira_url = 'https://yourcompany.atlassian.net',
  oauth = {
    client_id = os.getenv('JIRA_CLIENT_ID'),
    client_secret = os.getenv('JIRA_CLIENT_SECRET'),
  },
})
```

Then set environment variables in your shell config (`~/.bashrc`, `~/.zshrc`, etc.):

```bash
export JIRA_CLIENT_ID="your_client_id"
export JIRA_CLIENT_SECRET="your_client_secret"
```

### 3. Authenticate with Jira

Open Neovim and run:

```vim
:JiraAuth
```

Follow the prompts:
1. Browser will open to Atlassian authorization page
2. Click **"Accept"** to authorize the app
3. You'll be redirected to `http://localhost:8080/callback?code=...`
4. Copy the code from the URL (the long string after `code=`)
5. Paste it in Neovim when prompted

✅ You're authenticated! The token is saved and will auto-refresh.

## Verifying Installation

### Check Plugin is Loaded

```vim
:JiraTimeStatus
```

You should see output like:
```
=== Jira Time Status ===
Authenticated: true/false
Git Branch: feature/PROJ-123
Detected Issue: PROJ-123
Timer Running: false
Current Issue: N/A
Elapsed Time: 00:00:00
```

### Check Commands are Available

Type `:JiraTime` and press Tab - you should see autocomplete with:
- `:JiraTimeStart`
- `:JiraTimeStop`
- `:JiraTimeLog`
- `:JiraTimeView`
- `:JiraTimeSelect`
- `:JiraTimeStatus`

### Test Timer

```vim
:JiraTimeStart PROJ-123
:JiraTimeStop
```

You should see notifications confirming the timer started and stopped.

## Troubleshooting

### "Plugin not found" error

- Verify the plugin directory exists
- Check the plugin name is correct
- Restart Neovim completely
- Run `:PackerSync` or `:PlugInstall` again

### "plenary.nvim not found" error

Install plenary.nvim:

```lua
-- lazy.nvim
{ 'nvim-lua/plenary.nvim' }

-- packer.nvim
use 'nvim-lua/plenary.nvim'

-- vim-plug
Plug 'nvim-lua/plenary.nvim'
```

### "jira_url is required" warning

Add the required configuration:

```lua
require('jira-time').setup({
  jira_url = 'https://yourcompany.atlassian.net',
  oauth = {
    client_id = 'your_client_id',
    client_secret = 'your_client_secret',
  },
})
```

### Configuration not loading

Ensure your config is in the right place:
- lazy.nvim: `~/.config/nvim/lua/plugins/` or in `lazy.setup({})`
- packer.nvim: In your plugins file before `:PackerSync`
- vim-plug: After `plug#end()` but before any plugin usage
- Manual: In `init.lua` or a file that's sourced from `init.lua`

### OAuth errors

- Double-check Client ID and Secret
- Verify callback URL is exactly `http://localhost:8080/callback`
- Ensure all required scopes are added
- Try creating a new OAuth app

## Optional: Statusline Integration

If you use lualine, add jira-time to your statusline:

```lua
require('lualine').setup({
  sections = {
    lualine_x = {
      require('jira-time.statusline').lualine_component(),
      'encoding',
      'fileformat',
      'filetype',
    },
  },
})
```

## Updating the Plugin

### lazy.nvim
```vim
:Lazy update jira-time.nvim
```

### packer.nvim
```vim
:PackerUpdate
```

### vim-plug
```vim
:PlugUpdate
```

### Manual
```bash
cd ~/.local/share/nvim/site/pack/manual/start/jira-time.nvim
git pull
```

## Uninstalling

### lazy.nvim
Remove from your plugin configuration and run:
```vim
:Lazy clean
```

### packer.nvim
Remove from your plugin configuration and run:
```vim
:PackerClean
```

### vim-plug
Remove from your plugin configuration and run:
```vim
:PlugClean
```

### Manual
```bash
rm -rf ~/.local/share/nvim/site/pack/manual/start/jira-time.nvim
```

### Remove stored data
```bash
rm -rf ~/.local/share/nvim/jira-time/
```

## Getting Help

- Check the [README.md](README.md) for usage documentation
- See [SETUP_GUIDE.md](SETUP_GUIDE.md) for quick start
- Open an issue on GitHub for bugs or feature requests

Happy time tracking! ⏱️
