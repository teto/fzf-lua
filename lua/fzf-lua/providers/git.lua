local core = require "fzf-lua.core"
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local actions = require "fzf-lua.actions"
local libuv = require "fzf-lua.libuv"
local shell = require "fzf-lua.shell"

local M = {}

local function set_git_cwd_args(opts)
  opts.cwd = path.git_root(opts)
  if opts.git_dir or opts.git_worktree then
    opts.cmd = path.git_cwd(opts.cmd, opts)
  end
  return opts
end

M.files = function(opts)
  opts = config.normalize_opts(opts, config.globals.git.files)
  if not opts then return end
  opts = set_git_cwd_args(opts)
  if not opts.cwd then return end
  local contents = core.mt_cmd_wrapper(opts)
  opts = core.set_header(opts, 2)
  return core.fzf_files(opts, contents)
end

M.status = function(opts)
  opts = config.normalize_opts(opts, config.globals.git.status)
  if not opts then return end
  opts = set_git_cwd_args(opts)
  if not opts.cwd then return end
  if opts.preview then
    opts.preview = vim.fn.shellescape(path.git_cwd(opts.preview, opts))
  end
  -- we don't need git icons since we get them
  -- as part of our `git status -s`
  opts.git_icons = false
  if not opts.no_header then
    local stage = utils.ansi_codes.yellow("<left>")
    local unstage = utils.ansi_codes.yellow("<right>")
    opts.fzf_opts['--header'] = vim.fn.shellescape(
      ('+ - :: %s to stage, %s to unstage'):format(stage, unstage))
  end
  local function git_iconify(x)
    local icon = x
    local git_icon = config.globals.git.icons[x]
    if git_icon then
      icon = git_icon.icon
      if opts.color_icons then
        icon = utils.ansi_codes[git_icon.color or "dark_grey"](icon)
      end
    end
    return icon
  end
  local contents = libuv.spawn_nvim_fzf_cmd(opts,
    function(x)
      -- unrecognizable format, return
      if not x or #x<4 then return x end
      -- `man git-status`
      -- we are guaranteed format of: XY <text>
      -- spaced files are wrapped with quotes
      -- remove both git markers and quotes
      local f1, f2 = x:sub(4):gsub('"', ""), nil
      -- renames spearate files with '->'
      if f1:match("%s%->%s") then
        f1, f2 = f1:match("(.*)%s%->%s(.*)")
      end
      f1 = f1 and core.make_entry_file(opts, f1)
      f2 = f2 and core.make_entry_file(opts, f2)
      local staged = git_iconify(x:sub(1,1):gsub("?", " "))
      local unstaged = git_iconify(x:sub(2,2))
      local entry = ("%s%s%s%s%s"):format(
        staged, utils.nbsp, unstaged, utils.nbsp .. utils.nbsp,
        (f2 and ("%s -> %s"):format(f1, f2) or f1))
      return entry
    end,
    function(o)
      return core.make_entry_preprocess(o)
    end)
  opts = core.set_header(opts, 2)
  return core.fzf_files(opts, contents)
end

local function git_cmd(opts)
  opts = set_git_cwd_args(opts)
  if not opts.cwd then return end
  opts = core.set_header(opts, 2)
  core.fzf_wrap(opts, opts.cmd, function(selected)
    if not selected then return end
    actions.act(opts.actions, selected, opts)
  end)()
end

M.commits = function(opts)
  opts = config.normalize_opts(opts, config.globals.git.commits)
  if not opts then return end
  opts.preview = vim.fn.shellescape(path.git_cwd(opts.preview, opts))
  return git_cmd(opts)
end

M.bcommits = function(opts)
  opts = config.normalize_opts(opts, config.globals.git.bcommits)
  if not opts then return end
  local git_root = path.git_root(opts)
  if not git_root then return end
  local file = path.relative(vim.fn.expand("%:p"), git_root)
  opts.cmd = opts.cmd .. " " .. file
  local git_ver = utils.git_version()
  -- rotate-to first appeared with git version 2.31
  if git_ver and git_ver >= 2.31 then
    opts.preview = opts.preview .. " --rotate-to=" .. vim.fn.shellescape(file)
  end
  opts.preview = vim.fn.shellescape(path.git_cwd(opts.preview, opts))
  return git_cmd(opts)
end

M.branches = function(opts)
  opts = config.normalize_opts(opts, config.globals.git.branches)
  if not opts then return end
  opts.fzf_opts["--no-multi"] = ''
  opts._preview = path.git_cwd(opts.preview, opts)
  opts.preview = shell.preview_action_cmd(function(items)
    local branch = items[1]:gsub("%*", "")  -- remove the * from current branch
    if branch:find("%)") ~= nil then
      -- (HEAD detached at origin/master)
      branch = branch:match(".* ([^%)]+)") or ""
    else
      -- remove anything past space
      branch = branch:match("[^ ]+")
    end
    return opts._preview:gsub("{.*}", branch)
    -- return "echo " .. branch
  end, nil, opts.debug)
  return git_cmd(opts)
end

M.stash = function(opts)
  opts = config.normalize_opts(opts, config.globals.git.stash)
  if not opts then return end

  if opts.preview then
    opts.preview = vim.fn.shellescape(path.git_cwd(opts.preview, opts))
  end

  if opts.fzf_opts['--header'] == nil then
    opts.fzf_opts['--header'] = vim.fn.shellescape((':: %s to drop selected stash(es)')
      :format(utils.ansi_codes.yellow("<Ctrl-x>")))
  end

  opts.cmd = libuv.spawn_nvim_fzf_cmd(
    { cmd = opts.cmd, cwd = opts.cwd },
    function(x)
      local stash, rest = x:match("([^:]+)(.*)")
      if stash then
        stash = utils.ansi_codes.yellow(stash)
        stash = stash:gsub("{%d+}", function(s)
          return ("%s"):format(utils.ansi_codes.green(tostring(s)))
        end)
      end
      return (not stash or not rest) and x or stash .. rest
    end)

  return git_cmd(opts)
end

return M
