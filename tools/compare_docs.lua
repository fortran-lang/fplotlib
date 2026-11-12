-- Pandoc filter for tools/compare_docs.py: the Markdown extensions that
-- fplotlib reads, mapped onto LaTeX and Typst so that the same source
-- comes out the same way in all three.
--
--   * fenced divs and bracketed spans: alignment (.center, .right, .left),
--     LaTeX's size names (.small ... .Huge), .bold, .italic, and the
--     attributes size= and color=;
--   * a displayed formula followed by {#eq:name}, or with \label{name} in
--     it, is numbered, and @eq:name, @sec:name, \eqref and \ref refer to
--     it;
--   * the TeX commands fplotlib accepts on a line of their own (\newpage,
--     \vspace, \vfill, \bigskip, ...) and in text (\hfill, \quad, \TeX,
--     \LaTeX), for Typst, which has none of them;
--   * a paragraph that is only a display gets \noindent in LaTeX, which
--     fplotlib's display without a paragraph is.

local typst = FORMAT == "typst"

local SIZES = {
  tiny = 0.5, scriptsize = 0.7, footnotesize = 0.8, small = 0.9,
  normalsize = 1.0, large = 1.2, Large = 1.44, LARGE = 1.728,
  huge = 2.074, Huge = 2.488,
}

local BASE = 10
function Meta(m)
  if m.basesize then BASE = tonumber(pandoc.utils.stringify(m.basesize)) end
end

local NAMED = {
  darkred = "#8b0000", red = "#ff0000", navy = "#000080", blue = "#0000ff",
  black = "#000000", gray = "#808080", grey = "#808080", green = "#008000",
  darkblue = "#00008b", darkgreen = "#006400", white = "#ffffff",
}

local function hex(c)
  if not c then return nil end
  if c:sub(1, 1) ~= "#" then c = NAMED[c] or "#000000" end
  if #c == 4 then
    c = "#" .. c:sub(2, 2):rep(2) .. c:sub(3, 3):rep(2) .. c:sub(4, 4):rep(2)
  end
  return c
end

local function points(v)
  local n, u = v:match("^([%d%.]+)%s*(%a*)$")
  if not n then return nil end
  n = tonumber(n)
  if u == "" or u == "pt" or u == "bp" then return n end
  if u == "in" then return 72 * n end
  if u == "cm" then return 72 / 2.54 * n end
  if u == "mm" then return 72 / 25.4 * n end
  if u == "em" then return BASE * n end
  return n
end

-- What opens and closes a div or span with these attributes.
local function wrappers(el, block)
  local open, close = {}, {}
  local size, color, bold, italic, align
  for _, c in ipairs(el.classes) do
    if c == "center" or c == "right" or c == "left" or c == "justify" then align = c
    elseif SIZES[c] then size = SIZES[c] * BASE
    elseif c == "bold" then bold = true
    elseif c == "italic" then italic = true end
  end
  if el.attributes.size then size = points(el.attributes.size) end
  if el.attributes.color then color = hex(el.attributes.color) end
  if typst then
    if align and block then
      table.insert(open, "#align(" .. (align == "justify" and "left" or align) .. ")[")
      table.insert(close, 1, "]")
    end
    local args = {}
    if size then table.insert(args, string.format("size: %gpt", size)) end
    if color then table.insert(args, 'fill: rgb("' .. color .. '")') end
    if bold then table.insert(args, 'weight: "bold"') end
    if italic then table.insert(args, 'style: "italic"') end
    if #args > 0 then
      table.insert(open, "#text(" .. table.concat(args, ", ") .. ")[")
      table.insert(close, 1, "]")
    end
    if size and block then
      -- Typst's leading is in ems of the size in force.
      table.insert(open, "#set par(leading: 0.48em)")
    end
  else
    if align and block then
      local env = ({center = "center", right = "flushright", left = "flushleft"})[align]
      if env then
        table.insert(open, "\\begin{" .. env .. "}")
        table.insert(close, 1, "\\end{" .. env .. "}")
      end
    end
    local cmds = ""
    if size then cmds = cmds .. string.format("\\fontsize{%gbp}{%gbp}\\selectfont", size, 1.2 * size) end
    if color then cmds = cmds .. "\\color[HTML]{" .. color:sub(2):upper() .. "}" end
    if bold then cmds = cmds .. "\\bfseries" end
    if italic then cmds = cmds .. "\\itshape" end
    if cmds ~= "" then
      table.insert(open, "{" .. cmds .. " ")
      table.insert(close, 1, block and "\\par}" or "}")
    end
  end
  return open, close
end

local function raw_block(s)
  return pandoc.RawBlock(typst and "typst" or "latex", s)
end

local function raw_inline(s)
  return pandoc.RawInline(typst and "typst" or "latex", s)
end

function Div(el)
  local open, close = wrappers(el, true)
  if #open == 0 then return nil end
  local blocks = { raw_block(table.concat(open, "\n")) }
  for _, b in ipairs(el.content) do table.insert(blocks, b) end
  table.insert(blocks, raw_block(table.concat(close, "\n")))
  return blocks
end

function Span(el)
  local open, close = wrappers(el, false)
  if #open == 0 then return nil end
  local out = { raw_inline(table.concat(open, "")) }
  for _, i in ipairs(el.content) do table.insert(out, i) end
  table.insert(out, raw_inline(table.concat(close, "")))
  return out
end

local function typst_math(tex)
  local doc = pandoc.Pandoc({ pandoc.Plain({ pandoc.Math("DisplayMath", tex) }) })
  return (pandoc.write(doc, "typst"):gsub("%s+$", ""))
end

-- A display, numbered when it has a label.
local function display(tex, label)
  local inner = tex:match("\\label{([^}]*)}")
  if inner then
    label = inner
    tex = tex:gsub("\\label{[^}]*}", "")
  end
  if typst then
    if label then
      return raw_inline("#[#set math.equation(numbering: \"(1)\")\n" ..
        typst_math(tex) .. " <" .. label .. ">]")
    end
    return pandoc.Math("DisplayMath", tex)
  end
  if label then
    return raw_inline("\\begin{equation}" .. tex .. "\\label{" .. label .. "}\\end{equation}")
  end
  return pandoc.Math("DisplayMath", tex)
end

function Inlines(inlines)
  local out = pandoc.List()
  local i = 1
  while i <= #inlines do
    local el = inlines[i]
    if el.t == "Math" and el.mathtype == "DisplayMath" then
      local label
      local j = i + 1
      if inlines[j] and inlines[j].t == "Space" then j = j + 1 end
      if inlines[j] and inlines[j].t == "Str" then
        label = inlines[j].text:match("^{#(.-)}")
        if label then
          local rest = inlines[j].text:gsub("^{#.-}", "")
          if rest ~= "" then inlines[j].text = rest else i = j end
        end
      end
      out:insert(display(el.text, label))
    elseif el.t == "RawInline" and el.format == "html" and el.text:match("^<br%s*/?>$") then
      out:insert(pandoc.LineBreak())
    elseif el.t == "Cite" and #el.citations == 1 then
      local id = el.citations[1].id
      if typst then
        out:insert(raw_inline("@" .. id))
      elseif id:match("^eq:") then
        out:insert(raw_inline("\\eqref{" .. id .. "}"))
      else
        out:insert(raw_inline("\\ref{" .. id .. "}"))
      end
    elseif el.t == "RawInline" and el.format == "tex" and typst then
      local t = el.text
      local name, arg = t:match("^\\(%a+){?([^}]*)}?$")
      if name == "TeX" or name == "LaTeX" then out:insert(pandoc.Str(name))
      elseif name == "hfill" then out:insert(raw_inline("#h(1fr)"))
      elseif name == "quad" then out:insert(raw_inline("#h(1em)"))
      elseif name == "qquad" then out:insert(raw_inline("#h(2em)"))
      elseif name == "eqref" or name == "ref" then out:insert(raw_inline("@" .. arg))
      end
    else
      out:insert(el)
    end
    i = i + 1
  end
  return out
end

-- A paragraph that is only a display is \noindent and the display, as
-- fplotlib sets it.
function Para(el)
  local first = el.content[1]
  if not typst and first and ((first.t == "Math" and first.mathtype == "DisplayMath")
      or (first.t == "RawInline" and first.text:match("^\\begin{equation}"))) then
    table.insert(el.content, 1, pandoc.RawInline("latex", "\\noindent"))
    return el
  end
end

function RawBlock(el)
  if el.format ~= "tex" and el.format ~= "latex" then return nil end
  if not typst then return nil end
  local t = el.text
  if t:match("^\\newpage") or t:match("^\\pagebreak") or t:match("^\\clearpage") then
    return raw_block("#pagebreak()")
  elseif t:match("^\\vfill") or t:match("^\\vspace%*?{\\fill}") then
    return raw_block("#v(1fr)")
  elseif t:match("^\\bigskip") then return raw_block("#v(12pt)")
  elseif t:match("^\\medskip") then return raw_block("#v(6pt)")
  elseif t:match("^\\smallskip") then return raw_block("#v(3pt)")
  end
  local len = t:match("^\\vspace%*?{([^}]*)}")
  if len then return raw_block("#v(" .. len .. ")") end
  return {}
end

return {
  { Meta = Meta },
  { Inlines = Inlines },
  { Div = Div, Span = Span, Para = Para, RawBlock = RawBlock },
}
