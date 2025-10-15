local M = {}

---@alias SqlGhostyOptions 'show_hints_by_default' | 'highlight_group'

---@type table<SqlGhostyOptions, any>
local default_config = {
  show_hints_by_default = true,
  highlight_group = "DiagnosticHint",
}

M.config = vim.deepcopy(default_config)

local NS_ID = vim.api.nvim_create_namespace("sql_inlay_hints")

---@param node TSNode|nil
---@return string|nil
local function ntype(node)
  if node and type(node) == "userdata" and node.type then
    return node:type()
  end
  return nil
end

---@param node TSNode
---@param bufnr integer
---@return string
local function ntext(node, bufnr)
  return vim.treesitter.get_node_text(node, bufnr) or ""
end

---@param node TSNode
---@param cb fun(n: TSNode)
local function walk_named(node, cb)
  if not node then
    return
  end
  cb(node)
  for child in node:iter_children() do
    if child:named() then
      walk_named(child, cb)
    end
  end
end

---@param node TSNode
---@return boolean
local function is_value_like(node)
  local t = ntype(node)
  if not t then
    return false
  end
  if t == "list" or t == "object_reference" or t == "column" or t == "statement" then
    return false
  end
  return true
end

---@param bufnr integer
---@param row integer  -- 0-based
---@param col integer  -- 0-based end
---@return integer place_row, integer place_col
local function place_after_value_or_comma(bufnr, row, col)
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
  local i = col + 1
  local len = #line
  while i <= len do
    local ch = line:sub(i, i)
    if ch ~= " " and ch ~= "\t" then
      if ch == "," then
        return row, i
      end
      break
    end
    i = i + 1
  end
  return row, col
end

---@class InsertInfo
---@field schema string|nil
---@field table_name string|nil
---@field columns string[]
---@field rows { node: TSNode, row: integer, col: integer, text: string }[][]

---@param insert_node TSNode
---@param bufnr integer
---@return InsertInfo|nil
local function parse_insert(insert_node, bufnr)
  local info = { schema = nil, table_name = nil, columns = {}, rows = {} }

  for child in insert_node:iter_children() do
    local ct = ntype(child)
    if ct == "object_reference" and not info.table_name then
      local s = child:field("schema")[1]
      local n = child:field("name")[1]
      if s then
        info.schema = ntext(s, bufnr)
      end
      if n then
        info.table_name = ntext(n, bufnr)
      end
    end
  end

  local passed_object_ref, have_columns = false, false
  for child in insert_node:iter_children() do
    local ct = ntype(child)

    if ct == "object_reference" then
      passed_object_ref = true
    elseif ct == "list" and passed_object_ref and not have_columns then
      for col_node in child:iter_children() do
        if ntype(col_node) == "column" then
          for sub in col_node:iter_children() do
            if ntype(sub) == "identifier" then
              local name = ntext(sub, bufnr)
              if name and #name > 0 then
                table.insert(info.columns, name)
              end
            end
          end
        end
      end
      have_columns = #info.columns > 0
    elseif ct == "list" and have_columns then
      local row_vals = {}
      for val_node in child:iter_children() do
        if val_node:named() and is_value_like(val_node) then
          local sr, sc, er, ec = val_node:range()
          local text = ntext(val_node, bufnr)
          table.insert(row_vals, {
            node = val_node,
            row = sr,
            col = sc,
            text = text,
          })
        end
      end
      if #row_vals > 0 then
        table.insert(info.rows, row_vals)
      end
    end
  end

  if not info.table_name or #info.columns == 0 or #info.rows == 0 then
    return nil
  end
  return info
end

---@param root TSNode
---@return TSNode[]
local function collect_insert_nodes(root)
  local found = {}
  walk_named(root, function(n)
    local t = ntype(n)
    if t == "insert" or t == "insert_statement" then
      table.insert(found, n)
    end
  end)
  return found
end

---@param bufnr integer
local function clear(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, NS_ID, 0, -1)
end

---@param bufnr integer
---@param info InsertInfo
local function render_insert(bufnr, info)
  for _, row in ipairs(info.rows) do
    local n = math.min(#info.columns, #row)
    if n > 0 then
      for i = 1, n do
        local v = row[i]
        local _, _, er, ec = v.node:range()
        local r, c = place_after_value_or_comma(bufnr, er, ec)
        local label = " ;;" .. info.columns[i] .. ";; "
        vim.api.nvim_buf_set_extmark(bufnr, NS_ID, r, c, {
          virt_text = { { label, M.config.highlight_group } },
          virt_text_pos = "inline", --inline,
        })
      end
    end
  end
end

local function render_all()
  local bufnr = vim.api.nvim_get_current_buf()
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "sql")
  if not ok or not parser then
    vim.notify("[sql_inlay_hints] No SQL parser", vim.log.levels.DEBUG)
    return
  end

  local tree = parser:parse()[1]
  if not tree then
    return
  end
  local root = tree:root()
  if not root then
    return
  end

  clear(bufnr)

  local inserts = collect_insert_nodes(root)
  for _, ins in ipairs(inserts) do
    local info = parse_insert(ins, bufnr)
    if info then
      render_insert(bufnr, info)
    end
  end
end

M.setup = function(opts)
  M.config = vim.tbl_extend("force", default_config, opts or {})
  local cfg = M.config

  local function maybe_render()
    if cfg.show_hints_by_default and vim.bo.filetype == "sql" then
      vim.schedule(render_all)
    end
  end

  vim.api.nvim_create_autocmd({ "BufEnter" }, {
    group = vim.api.nvim_create_augroup("SqlInlayHintsEnter", { clear = true }),
    pattern = "*.sql",
    callback = maybe_render,
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave", "BufWritePost" }, {
    group = vim.api.nvim_create_augroup("SqlInlayHintsUpdate", { clear = true }),
    pattern = "*.sql",
    callback = maybe_render,
  })

  vim.api.nvim_create_user_command("SqlInlayHintsToggle", function()
    if vim.bo.filetype ~= "sql" then
      vim.notify("SqlInlayHintsToggle works only in SQL buffers", vim.log.levels.WARN)
      return
    end
    if cfg.show_hints_by_default then
      cfg.show_hints_by_default = false
      clear(0)
    else
      cfg.show_hints_by_default = true
      render_all()
    end
  end, {})
end

return M
