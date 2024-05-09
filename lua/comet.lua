-- design choices
-- * honor 'commentstring' and 'expandtab'
-- * no relying on lsp nor treesitter
-- * no toggle api
-- * no multi-line comments: /* .. */
-- * when commenting multiple lines, take the minimal indent within the line range
--   * this is mainly for python
--
-- limits:
-- * has no effects on `--xx`, `---xx` and `--[[` when &cms='-- %s'
-- * not works with lines dont respect 'expandtab'

local M = {}

local buflines = require("infra.buflines")
local wincursor = require("infra.wincursor")
local fn = require("infra.fn")
local jelly = require("infra.jellyfish")("comet")
local prefer = require("infra.prefer")
local strlib = require("infra.strlib")
local vsel = require("infra.vsel")

local api = vim.api

---@param cs string 'commentstring'
---@return string
local function resolve_comment_prefix(cs)
  assert(cs ~= "")
  local socket_at = assert(strlib.find(cs, "%s"))
  return string.sub(cs, 1, socket_at - 1)
end

---@type fun(bufnr: number): fun(line: string): string
local IndentResolver
do
  local function tab(line)
    if line == "" then return "" end
    assert(not strlib.startswith(line, " "), "indent char should be tab")
    return select(1, string.match(line, "^[\t]*"))
  end
  local function space(line)
    if line == "" then return "" end
    assert(not strlib.startswith(line, "\t"), "indent char should be space")
    return select(1, string.match(line, "^[ ]*"))
  end
  function IndentResolver(bufnr) return prefer.bo(bufnr, "expandtab") and space or tab end
end

---@param line string @line
---@param indent string @resolved intent of the line
---@param cs string @comment string
---@param cprefix string @comment prefix
---@return string?
local function to_commented_line(line, indent, cs, cprefix)
  assert(line ~= "" and cs ~= "")

  if #indent == #line then return jelly.debug("blank line") end

  local rest = string.sub(line, #indent + 1)
  if strlib.startswith(rest, cprefix) then return jelly.debug("already commented") end
  return indent .. string.format(cs, rest)
end

---@param line string @line
---@param indent string @resolved intent of the line
---@param cs string @comment template
---@param cprefix string @comment prefix
---@return string?
local function to_uncommented_line(line, indent, cs, cprefix)
  assert(line ~= "" and cs ~= "")

  if #indent == #line then return jelly.debug("blank line") end

  local rest = string.sub(line, #indent + 1)
  if not strlib.startswith(rest, cprefix) then return jelly.debug("not commented") end
  return indent .. string.sub(rest, #cprefix + 1)
end

do
  local function main(processor)
    local winid = api.nvim_get_current_win()
    local bufnr = api.nvim_win_get_buf(winid)
    local lnum = wincursor.lnum(winid)

    local processed
    do
      local cs = prefer.bo(bufnr, "commentstring")
      if cs == "" then return jelly.warn("no proper &commentstring") end

      local cprefix = resolve_comment_prefix(cs)

      local line = assert(buflines.line(bufnr, lnum))
      if line == "" then return jelly.debug("blank line") end

      local indent = IndentResolver(bufnr)(line)

      processed = processor(line, indent, cs, cprefix)
    end

    if processed == nil then return end
    buflines.replace(bufnr, lnum, processed)
  end

  function M.comment_curline() main(to_commented_line) end
  function M.uncomment_curline() main(to_uncommented_line) end
end

do
  local function main(processor)
    local bufnr = api.nvim_get_current_buf()
    local range = vsel.range(bufnr)
    if range == nil then return end

    local lines
    do
      local cs = prefer.bo(bufnr, "commentstring")
      if cs == "" then return jelly.warn("no proper &commentstring") end

      local cprefix = resolve_comment_prefix(cs)

      local held_lines = buflines.lines(bufnr, range.start_line, range.stop_line)

      local indent -- apply the minimal indent to all lines
      do
        local resolve_indent = IndentResolver(bufnr)
        for line in fn.filter(function(line) return line ~= "" end, held_lines) do
          if indent == nil then
            indent = resolve_indent(line)
          else
            local this_indent = resolve_indent(line)
            if #this_indent < #indent then indent = this_indent end
          end
        end
      end

      local changed = false

      lines = fn.tolist(fn.map(function(line)
        if line == "" then return "" end
        local processed = processor(line, indent, cs, cprefix)
        if processed == nil then return line end
        changed = true
        return processed
      end, held_lines))

      if not changed then return jelly.debug("no changes") end
    end

    buflines.replaces(bufnr, range.start_line, range.stop_line, lines)
    do -- dirty hack for: https://github.com/neovim/neovim/issues/24007
      api.nvim_buf_set_mark(bufnr, "<", range.start_line + 1, range.start_col, {})
      api.nvim_buf_set_mark(bufnr, ">", range.stop_line + 1 - 1, range.stop_col - 1, {})
    end
  end

  function M.comment_vselines() main(to_commented_line) end
  function M.uncomment_vselines() main(to_uncommented_line) end
end

return M
