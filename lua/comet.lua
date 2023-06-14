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

local prefer = require("infra.prefer")
local strlib = require("infra.strlib")
local vsel = require("infra.vsel")
local jelly = require("infra.jellyfish")("comet")
local fn = require("infra.fn")

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
    if #line == 0 then return "" end
    assert(not strlib.startswith(line, " "), "indent char should be tab")
    return string.match(line, "^[\t]*")
  end
  local function space(line)
    if #line == 0 then return "" end
    assert(not strlib.startswith(line, "\t"), "indent char should be space")
    return string.match(line, "^[ ]*")
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

  local commented
  do
    local rest = string.sub(line, #indent + 1)
    if strlib.startswith(rest, cprefix) then return jelly.debug("already commented") end
    commented = indent .. string.format(cs, rest)
  end

  return commented
end

---@param line string @line
---@param indent string @resolved intent of the line
---@param cs string @comment template
---@param cprefix string @comment prefix
---@return string?
local function to_uncommented_line(line, indent, cs, cprefix)
  assert(line ~= "" and cs ~= "")

  if #indent == #line then return end -- blank line

  local uncommented
  do
    local rest = string.sub(line, #indent + 1)
    if not strlib.startswith(rest, cprefix) then return jelly.debug("not commented") end
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

    local processed
    do
      local cs = prefer.bo(bufnr, "commentstring")
      if #cs == 0 then return jelly.warn("no proper &commentstring") end

      local cprefix = resolve_comment_prefix(cs)

      local line = assert(api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1])
      if #line == 0 then return jelly.debug("blank line") end

      local indent = IndentResolver(bufnr)(line)

      processed = processor(line, indent, cs, cprefix)
    end

    if processed == nil then return end
    api.nvim_buf_set_lines(bufnr, lnum, lnum + 1, false, { processed })
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
      if #cs == 0 then return jelly.warn("no proper &commentstring") end

      local cprefix = resolve_comment_prefix(cs)

      local held_lines = api.nvim_buf_get_lines(bufnr, range.start_line, range.stop_line, false)

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

      lines = fn.concrete(fn.map(function(line)
        if #line == 0 then return "" end
        local processed = processor(line, indent, cs, cprefix)
        if processed == nil then return line end
        changed = true
        return processed
      end, held_lines))

      if not changed then return jelly.debug("no changes") end
    end

    api.nvim_buf_set_lines(bufnr, range.start_line, range.stop_line, false, lines)
    do -- dirty hack for: https://github.com/neovim/neovim/issues/24007
      api.nvim_buf_set_mark(bufnr, "<", range.start_line + 1, range.start_col, {})
      api.nvim_buf_set_mark(bufnr, ">", range.stop_line + 1 - 1, range.stop_col - 1, {})
    end
  end

  function M.comment_vselines() main(to_commented_line) end
  function M.uncomment_vselines() main(to_uncommented_line) end
end

return M
