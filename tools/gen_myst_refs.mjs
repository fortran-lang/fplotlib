// Development oracle only; the Fortran library and tests have no JS dependency.
// Usage: node tools/gen_myst_refs.mjs /path/to/node_modules/myst-parser
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';

const parser = resolve(process.argv[2] ?? 'node_modules/myst-parser');
const version = JSON.parse(readFileSync(join(parser, 'package.json'))).version;
if (version !== '1.7.5') throw new Error(`Expected myst-parser 1.7.5, found ${version}`);
const { mystParse } = await import(pathToFileURL(join(parser, 'dist/index.js')));
// Preserve the tokenizer's list tightness; upstream mdast hardcodes spread.
function listAttrs(ordered) {
  return (token, tokens, index) => {
    let spread = false;
    for (let j = index + 1; j < tokens.length && tokens[j].level > token.level; ++j) {
      if (tokens[j].type === 'paragraph_open' && tokens[j].level === token.level + 2 && !tokens[j].hidden) {
        spread = true;
      }
    }
    return { ordered, start: Number(token.attrGet('start') || 1), spread };
  };
}
const options = {
  extensions: {
    smartquotes: false,
    math: { amsmath: false, dollarmath: true },
    footnotes: false,
    deflist: false,
    tasklist: false,
  },
  mdast: {
    handlers: {
      bullet_list: { type: 'list', getAttrs: listAttrs(false) },
      ordered_list: { type: 'list', getAttrs: listAttrs(true) },
    },
  },
};
const label = (s = '') => s.replace(/[\t\n\r ]+/g, ' ').replace(/['‘’"“”]+/g, '').trim().toLowerCase();
const text = (s) => ['text', s.replace(/[ \t\r\n]+/g, ' ')];

function children(nodes = []) {
  const out = [];
  let target = '';
  for (const node of nodes) {
    if (node.type === 'mystTarget') {
      target = label(node.label);
      continue;
    }
    const converted = normalize(node, target);
    target = '';
    for (const value of converted) {
      if (value[0] === 'text' && out.at(-1)?.[0] === 'text') out.at(-1)[1] += value[1];
      else out.push(value);
    }
  }
  return out;
}

function normalize(n, target = '') {
  const id = target || label(n.identifier || n.label);
  switch (n.type) {
    case 'root': return [['root', children(n.children)]];
    case 'comment': return [];
    case 'text': return [text(n.value)];
    case 'paragraph': return [['p', id, children(n.children)]];
    case 'heading': return [['h', n.depth, id, children(n.children)]];
    case 'emphasis': return [['em', children(n.children)]];
    case 'strong': return [['strong', children(n.children)]];
    case 'inlineCode': return [['code', n.value]];
    case 'code': return [['pre', id, n.lang || '', n.value]];
    case 'break': return [['break']];
    case 'thematicBreak': return [['rule', id]];
    case 'blockquote': return [['quote', id, children(n.children)]];
    case 'list': return [['list', !!n.ordered, n.start ?? 1, !n.spread, id, children(n.children)]];
    case 'listItem': return [['item', children(n.children)]];
    case 'inlineMath': return [['math', n.value]];
    case 'math': return [['display', id, n.enumerated ?? true, n.enumerated !== undefined, n.value.trim()]];
    case 'mystDirective': return n.children.flatMap((child) => normalize(child, id));
    case 'mystRole':
      if (n.name === 'math') return [['math', n.value]];
      if (!['ref', 'eq', 'numref'].includes(n.name)) throw new Error(`Unsupported oracle role ${n.name}`);
      return [['ref', { ref: 1, eq: 2, numref: 0 }[n.name], label(n.value), '']];
    case 'cite': return [['ref', 0, id, '']];
    case 'link':
      if (n.url.startsWith('#')) {
        if (n.children.length) throw new Error('Use layout tests for custom reference display text');
        return [['ref', 0, label(decodeURIComponent(n.url.slice(1))), '']];
      }
      return [['link', n.url, children(n.children)]];
    case 'block': {
      const meta = n.meta ? JSON.parse(n.meta) : {};
      const pageBreak = meta['page-break'] ? 2 : meta['new-page'] ? 1 : 0;
      if (!id && !meta.part && !pageBreak) return children(n.children);
      return [['block', id, meta.part || '', pageBreak, children(n.children)]];
    }
    case 'container':
    case 'div': return children(n.children);
    case 'table': {
      const rows = n.children.map((row) => row.children.map((cell) => {
        if (cell.children.some((child) => child.type !== 'text')) throw new Error('Only plain table cells');
        return cell.children.map((child) => child.value).join('').replace(/[ \t\r\n]+/g, ' ');
      }));
      const align = n.children[0].children.map((cell) => ({ left: 'l', center: 'c', right: 'r' }[cell.align] || 'l'));
      return [['table', id, align, rows]];
    }
    default: throw new Error(`Unsupported oracle node ${JSON.stringify(n)}`);
  }
}

const cases = [
  ['text', 'Plain text.\nA soft break.'],
  ['emphasis', '*one* **two** _three_ __four__'],
  ['nested emphasis', '***both*** and **strong *inside*** and *em **inside***'],
  ['delimiter runs', 'foo***bar***baz a***b**c* **a*b** c* _a__b_'],
  ['unmatched delimiters', '*unclosed and foo_bar_baz and ** and ___'],
  ['punctuation flanking', 'a_“b”_c and “*yes*” and x**+**y'],
  ['literal typography', '"quotes" -- --- ...'],
  ['escapes', '\\*literal\\* and \\_x\\_ and \\\\ and \\newpage'],
  ['removed spans', '[text]{color=red} and [title]{.Huge}'],
  ['entities', '&amp; &lt; &gt; &quot; &apos; &nbsp; &#945; &#x1F600;'],
  ['numeric entity replacements', '&#128; &#x82; &#0; &#xD800;'],
  ['code spans', '`a *b*` and `` a ` b `` and `  padded  `'],
  // All-space spans are checked against CommonMark directly in Fortran:
  // this pinned tokenizer incorrectly strips two spaces from `   `.
  ['multiline code', '``\nword\n``'],
  ['unmatched code', '``no close ` here'],
  ['hard breaks', 'first  \nsecond\\\nthird'],
  ['dollar math', '$x^2$ and $ a $ and $20 then $30.'],
  ['escaped dollars', '\\$5 and $a\\$b$'],
  ['math role', '{math}`x^2 + y^2`'],
  ['inline links', '[label *em*](https://example.org/a_(b) "Title")'],
  ['nested links', '[outer [inner](https://example.org)](https://example.com)'],
  ['inline double dollars', 'Text $$ x $$ and $$x$$.'],
  ['autolinks', '<https://example.org/> and <a@example.org>'],
  ['headings', '# First\n\n## Second ##\n\nSetext\nheading\n------'],
  ['literal heading attributes', '# Title {#old}'],
  ['empty headings', '#\n\n## ###'],
  ['rules', '***\n\n- - -\n\n___'],
  ['fenced code', '````fortran\n```inner\nprint *, 1\n```\n````'],
  ['fence kind', '```text\n~~~\n```'],
  ['unclosed code', '```text\nend at EOF'],
  ['indented fences', '  ```fortran\n  x = 1\n    y = 2\n  ```'],
  ['indented code', '    x = 1\n\n    y = 2\n\nAfter.'],
  ['blockquotes', '> First.\n>\n> Second **bold**.\n\nOutside.'],
  ['lazy quote', '> First\ncontinuation\n\nOutside.'],
  ['quote heading boundary', '> # Heading\nOutside.'],
  ['quote code boundary', '> ```text\n> code\n> ```\nOutside.'],
  ['nested quotes', '> Outer\n>\n> > Inner'],
  ['lists', '- First\n- Second\n\n1. One\n2. Two'],
  ['loose list', '- First\n\n- Second'],
  ['nested lists', '- Outer\n  - Inner\n  - Other\n- Next'],
  ['list continuation', '3) First\n   continuation\n4) Second'],
  ['list blocks', '- First\n\n  Another paragraph.\n\n- Last'],
  ['list heading boundary', '- # Heading\nOutside.'],
  ['empty list interruption', 'Paragraph\n*'],
  ['tab list', '-\tFirst\n-\tSecond'],
  ['tab continuation', '-\tFirst\n\tcontinuation\n-\tSecond'],
  ['indented list content', '-     code\n\n- text'],
  ['tab quote', '>\tIndented'],
  ['list after paragraph', 'A paragraph\n2. not a list\n\n1. List'],
  ['target', '(Section-A)=\n# Heading\n\nSee @Section-A and [](#Section-A).'],
  ['target normalization', '(A  “Quoted” Equation)=\n# Heading\n\n[](#a%20quoted%20equation)'],
  ['reference roles', '{ref}`heading` and {eq}`energy` and {numref}`table`'],
  ['display math', '$$\nx^2\n$$'],
  ['labeled display', '$$ x^2 $$ (energy)'],
  ['math directive', '```{math}\n:label: energy\n:enumerated: false\n\nE=mc^2\n```'],
  ['colon math', ':::{math}\n:label: energy\n\nx^2\n:::'],
  ['nested directives', '::::{div}\nText.\n\n:::{math}\nx^2\n:::\n::::'],
  ['parts', '+++ {"part":"sender"}\nAddress\n+++\nBody.'],
  ['page breaks', 'First.\n\n+++ {"new-page":true}\nSecond.'],
  ['spaced block markers', 'First.\n\n+ + + + {"page-break":true}\nSecond.'],
  ['comments', '% comment\nFirst.\n\n% another\nSecond.'],
  ['pipe table', '| A | B |\n|---|---|\n| 1 | 2 |'],
  ['table alignments', 'A | B | C\n:-- | :-: | --:\nx | y | z'],
  ['table missing cells', 'A | B\n---|---\nx\ny | z | ignored'],
  ['table escaped pipes', '| A\\|B | C |\n|---|---|\n| x\\|y | z |'],
  ['invalid table delimiter', 'A | B\n-:- | ---\nx | y'],
  ['mismatched table header', 'A | B\n---\nx | y'],
  ['table escaped slash', '| A | B |\n|---|---|\n| x | y\\\\|'],
];

if (process.argv[3] === '--parse') {
  console.log(JSON.stringify(mystParse(readFileSync(0, 'utf8'), options)));
} else {
  const lines = [`# myst-parser ${version}; options: ${JSON.stringify(options)}`];
  for (const [name, source] of cases) {
    lines.push(name, JSON.stringify(source), JSON.stringify(normalize(mystParse(source, options))[0]));
  }
  writeFileSync(new URL('../tests/myst_refs.txt', import.meta.url), lines.join('\n') + '\n');
  console.log(`Wrote ${cases.length} canonical MyST cases`);
}
