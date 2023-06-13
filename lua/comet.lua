-- design choices
-- * no relying on lsp nor treesitter
-- * no toggle comment on/off
-- * no multi-line comments
--
-- limits:
-- * comment has no effects on `--xx`, `---xx` and `--[[` when &cms='-- %s'

local M = {}

local prefer = require("infra.prefer")
local strlib = require("infra.strlib")
local vsel = require("infra.vsel")
local jelly = require("infra.jellyfish")("comet")
local fn = require("infra.fn")

local api = vim.api

---@param cs string 'commentstring'
---@return string?
local function resolve_comment_prefix(cs)
  assert(cs ~= "")
  local socket_at = assert(strlib.find(cs, "%s"))
  return string.sub(cs, 1, socket_at - 1)
end

---@param line string @line
---@param cs string @comment template
---@param cprefix string @comment prefix
---@return string?
local function to_comment_line(line, cs, cprefix)
  assert(line ~= "" and cs ~= "")

  local indent = string.match(line, "^[ \t]*")
  if #indent == #line then return jelly.debug("blank line") end

  local commented
  do
    local rest = string.sub(line, #indent + 1)
    if vim.startswith(rest, cprefix) then return jelly.debug("already commented") end
    commented = indent .. string.format(cs, rest)
  end

  return commented
end

---@param line string @line
---@param cs string @comment template
---@param cprefix string @comment prefix
---@return string?
local function to_uncomment_line(line, cs, cprefix)
  assert(line ~= "" and cs ~= "")

  local indent = string.match(line, "^[ \t]*")
  if #indent == #line then return end -- blank line

  local uncommented
  do
    local rest = string.sub(line, #indent + 1)
    if not vim.startswith(rest, cprefix) then return jelly.debug("not commented") end
    uncommented = indent .. string.sub(rest, #cprefix + 1)
  end

  return uncommented
end

do
  local function main(processor)
    local bufnr, lnum
    do
      local winid = api.nvim_get_current_win()
      bufnr = api.nvim_win_get_buf(winid)
      local cursor = api.nvim_win_get_cursor(winid)
      lnum = cursor[1] - 1
    end
    local cs = prefer.bo(bufnr, "commentstring")
    if cs == "" then return jelly.warn("no proper &commentstring") end
    local cprefix = resolve_comment_prefix(cs)
    local line = assert(api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1])
    if line == "" then return jelly.debug("blank line") end

    local processed = processor(line, cs, cprefix)
    if processed == nil then return end
    api.nvim_buf_set_lines(bufnr, lnum, lnum + 1, false, { processed })
  end

  function M.comment_curline() main(to_comment_line) end
  function M.uncomment_curline() main(to_uncomment_line) end
end

do
  local function main(processor)
    local bufnr = api.nvim_get_current_buf()
    local range = vsel.range(bufnr)
    if range == nil then return end
    local cs = prefer.bo(bufnr, "commentstring")
    if cs == "" then return jelly.warn("no proper &commentstring") end
    local cprefix = resolve_comment_prefix(cs)

    local changed = false
    local lines = fn.concrete(fn.map(function(line)
      if line == "" then return "" end
      local processed = processor(line, cs, cprefix)
      if processed == nil then return line end
      changed = true
      return processed
    end, api.nvim_buf_get_lines(bufnr, range.start_line, range.stop_line, false)))

    if not changed then return jelly.debug("no changes") end

    api.nvim_buf_set_lines(bufnr, range.start_line, range.stop_line, false, lines)
    do -- dirty hack for: https://github.com/neovim/neovim/issues/24007
      api.nvim_buf_set_mark(bufnr, "<", range.start_line + 1, range.start_col, {})
      api.nvim_buf_set_mark(bufnr, ">", range.stop_line + 1 - 1, range.stop_col - 1, {})
    end
  end

  function M.comment_vselines() main(to_comment_line) end
  function M.uncomment_vselines() main(to_uncomment_line) end
end

return M
