an opinionated comment plugin for neovim

## design choices
* respects 'commentstring'
   * but has no effects on `--xx`, `---xx` and `--[[` when &cms='-- %s'
* no relying on lsp nor treesitter
* no toggle comment on/off
* no multi-line comments

## status
* it just works (tm)
* it is feature-freezed

## prerequisites
* neovim 0.9.*
* haolian9/infra.nvim

## usage

my personal keymaps

```
m.n("gc", function() require("comet").comment_curline() end)
m.n("gC", function() require("comet").uncomment_curline() end)
m.v("gc", [[:lua require("comet").comment_vselines()<cr>]])
m.v("gC", [[:lua require("comet").uncomment_vselines()<cr>]])
```
