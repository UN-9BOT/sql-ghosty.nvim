# sql-ghosty.nvim

`sql-ghosty.nvim` adds ghost text inlay hints to your SQL insert statements.

## Example

<img width="1247" height="258" alt="image" src="https://github.com/user-attachments/assets/a59d7ddd-af0b-4e9d-a82e-a7d761d5d01f" />


## Description

Addresses the challenge of managing SQL inserts with numerous columns, where it’s difficult to map values to their corresponding columns.
It embeds hints with the column name alongside each value.

Another approach I sometimes use, is to align the statement with a plugin like mini.align and edit it in visual-block mode.
These approaches are complementary, each valuable in different scenarios, allowing me to choose the best method based on the context.

## Features

- robust SQL parsing by leveraging tree-sitter
- ability to toggle hints with the `:SqlInlayHintsToggle` command

## Requirements

- nvim-treesitter with SQL parser installed

## Instalation

### neovim >= 0.12
```lua
vim.pack.add({
    { src = "https://github.com/pmouraguedes/sql-ghosty.nvim" },
})
require("sql-ghosty").setup({})
```

### lazy.nvim
```lua
{
  "pmouraguedes/sql-ghosty.nvim",
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
  },
  opts = {},
}
```

## Configuration

### Default settings

```lua
{
    -- if set to false the user needs to enable hints manually with :SqlInlayHintsToggle
    show_hints_by_default = true,
    highlight_group = "DiagnosticHint",
}
```

## User commands

- `:SqlInlayHintsToggle` - toggle hint display
