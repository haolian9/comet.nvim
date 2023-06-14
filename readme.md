an opinionated comment plugin for neovim

https://user-images.githubusercontent.com/6236829/245811764-e1ca06ee-519d-469e-ab10-093c67471566.mp4

## design choices
* honor 'commentstring' and 'expandtab'
  * but has no effects on `--xx`, `---xx` and `--[[` when &cms='-- %s'
* no relying on lsp nor treesitter
* no toggle api
* no multi-line comments: `/* .. */`
* when commenting multiple lines, take the minimal indent within the line range
  * this is mainly for python

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
