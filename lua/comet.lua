-- design choices
-- * honor 'commentstring' and 'expandtab'
--   * but expect cms='{prefix} %s', no '/* %s */'
-- * no relying on lsp nor treesitter
-- * no toggle api
-- * no support: /* ... */
-- * when commenting multiple lines, the smallest indent wins
-- * opinionated fallback &cms
--
-- limits:
-- * has no effects on `--xx`, `---xx` and `--[[` when &cms='-- %s'
-- * not works with lines dont respect 'expandtab'
--
-- tried vim.regex to avoid copying lines with failure
-- * can resolve indent with vim.regex() and copy-free
-- * but found no easy way to detect if a line is (un)commented: regex(escape(cms-prefix))

local M = {}

local buflines = require("infra.buflines")
local its = require("infra.its")
local jelly = require("infra.jellyfish")("comet")
local ni = require("infra.ni")
local prefer = require("infra.prefer")
local strlib = require("infra.strlib")
local vsel = require("infra.vsel")
local wincursor = require("infra.wincursor")

---@param bufnr integer
---@return string cms
---@return string cma
local function resolve_cms_with_fallback(bufnr)
  local cms = prefer.bo(bufnr, "commentstring")
  if cms == "" then return "# %s", "# " end

  local cma, cme = unpack(strlib.splits(cms, "%s", 1))
  assert(cma ~= "")
  if cme ~= "" then error("not supported &cms") end
  return cms, cma
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

---@param line string
---@param indent string
---@param cms string
---@param cma string @comment prefix
---@return string?
local function to_commented_line(line, indent, cms, cma)
  assert(line ~= "" and cms ~= "")

  if #indent == #line then return jelly.debug("blank line") end

  local rest = string.sub(line, #indent + 1)
  if strlib.startswith(rest, cma) then return jelly.debug("already commented") end
  return indent .. string.format(cms, rest)
end

---@param line string
---@param indent string
---@param cms string
---@param cma string @comment prefix
---@return string?
local function to_uncommented_line(line, indent, cms, cma)
  assert(line ~= "" and cms ~= "")

  if #indent == #line then return jelly.debug("blank line") end

  local rest = string.sub(line, #indent + 1)
  if not strlib.startswith(rest, cma) then return jelly.debug("not commented") end
  return indent .. string.sub(rest, #cma + 1)
end

do
  local function main(processor)
    local winid = ni.get_current_win()
    local bufnr = ni.win_get_buf(winid)
    local lnum = wincursor.lnum(winid)

    local result
    do
      local cms, cma = resolve_cms_with_fallback(bufnr)
      local line = assert(buflines.line(bufnr, lnum))
      if line == "" then return end
      local indent = IndentResolver(bufnr)(line)
      result = processor(line, indent, cms, cma)
    end

    if result == nil then return end
    buflines.replace(bufnr, lnum, result)
  end

  function M.comment_curline() main(to_commented_line) end
  function M.uncomment_curline() main(to_uncommented_line) end
end

do
  local function main(processor)
    local bufnr = ni.get_current_buf()
    local range = vsel.range(bufnr)
    if range == nil then return end

    local results, changed
    do
      local cms, cma = resolve_cms_with_fallback(bufnr)
      local lines = buflines.lines(bufnr, range.start_line, range.stop_line)

      local indent
      do --find the smallest indent
        local resolve_indent = IndentResolver(bufnr)
        for _, line in ipairs(lines) do
          if line == "" then goto continue end
          if indent then
            local this_indent = resolve_indent(line)
            if #this_indent < #indent then indent = this_indent end
          else
            indent = resolve_indent(line)
          end
          ::continue::
        end
      end

      results = its(lines)
        :map(function(line)
          if line == "" then return "" end
          local result = processor(line, indent, cms, cma)
          if result == nil then return line end
          changed = true
          return result
        end)
        :tolist()
    end

    if not changed then return jelly.debug("no changes") end
    buflines.replaces(bufnr, range.start_line, range.stop_line, results)
    vsel.restore_gv(bufnr, range)
  end

  function M.comment_vselines() main(to_commented_line) end
  function M.uncomment_vselines() main(to_uncommented_line) end
end

return M
