#!/usr/bin/env node
import { mkdirSync, writeFileSync } from 'fs';
import { resolve, join } from 'path';

const RESET = '\x1b[0m';
const BOLD = '\x1b[1m';
const DIM = '\x1b[2m';
const CYAN = '\x1b[36m';
const GREEN = '\x1b[32m';
const YELLOW = '\x1b[33m';
const RED = '\x1b[31m';
const MAGENTA = '\x1b[35m';

function c(s: string, code: string): string {
  return code + s + RESET;
}

const langChoices = ['ts', 'py', 'go', 'rust', 'csharp', 'php', 'kotlin', 'swift', 'cpp', 'dart'] as const;
type Lang = (typeof langChoices)[number];
const templateChoices = ['basic', 'server', 'cli', 'desktop'] as const;
type Template = (typeof templateChoices)[number];

interface Config {
  lang: Lang;
  name: string;
  template: Template;
}

function parseArgs(): Config {
  const args = process.argv.slice(2);
  let lang: Lang = 'ts';
  let name = '';
  let template: Template = 'basic';

  for (let i = 0; i < args.length; i++) {
    if ((args[i] === '-l' || args[i] === '--lang') && i + 1 < args.length) {
      const v = args[++i].toLowerCase();
      if ((langChoices as readonly string[]).includes(v)) lang = v as Lang;
    } else if ((args[i] === '-n' || args[i] === '--name') && i + 1 < args.length) {
      name = args[++i];
    } else if ((args[i] === '-t' || args[i] === '--template') && i + 1 < args.length) {
      const v = args[++i].toLowerCase();
      if ((templateChoices as readonly string[]).includes(v)) template = v as Template;
    } else if (!args[i].startsWith('-')) {
      if (!name) name = args[i];
    }
  }

  if (!name) {
    console.log(c('Usage: npx create-ytapis-app my-project [options]', YELLOW));
    console.log();
    console.log('Options:');
    console.log(`  ${c('-l, --lang', CYAN)}       Language: ${langChoices.join('|')} (default: ts)`);
    console.log(`  ${c('-n, --name', CYAN)}      Project name`);
    console.log(`  ${c('-t, --template', CYAN)}  Template: ${templateChoices.join('|')} (default: basic)`);
    console.log();
    console.log('Examples:');
    console.log('  npx create-ytapis-app my-app');
    console.log('  npx create-ytapis-app my-app -l go -t cli');
    console.log('  npx create-ytapis-app my-server --lang ts --template server');
    process.exit(1);
  }

  return { lang, name, template };
}

function writeDir(base: string, files: Record<string, string>) {
  for (const [relPath, content] of Object.entries(files)) {
    const full = resolve(base, relPath);
    mkdirSync(join(full, '..'), { recursive: true });
    writeFileSync(full, content, 'utf-8');
  }
}

interface TemplateFn {
  (name: string): Record<string, string>;
}

const tsBasic: TemplateFn = (name) => ({
  'package.json': JSON.stringify({ name, version: '1.0.0', private: true, scripts: { start: 'tsx src/index.ts', build: 'tsc' }, dependencies: { 'ytapis-core': '*', tsx: '^4.0.0' } }, null, 2),
  'tsconfig.json': JSON.stringify({ compilerOptions: { target: 'ES2022', module: 'ESNext', moduleResolution: 'bundler', esModuleInterop: true, strict: true, outDir: 'dist', rootDir: 'src' }, include: ['src'] }, null, 2),
  'src/index.ts': `import { search } from 'ytapis-core';\n\nasync function main() {\n  const res = await search('cats', { limit: 5 });\n  console.log(res.results.map(r => r.title));\n}\n\nmain().catch(console.error);\n`,
});

const tsServer: TemplateFn = (name) => ({
  ...tsBasic(name),
  'package.json': JSON.stringify({ name, version: '1.0.0', private: true, scripts: { start: 'tsx src/index.ts', build: 'tsc' }, dependencies: { 'ytapis-core': '*', express: '^4', tsx: '^4.0.0' }, devDependencies: { '@types/express': '^4' } }, null, 2),
  'src/index.ts': `import express from 'express';\nimport { search } from 'ytapis-core';\n\nconst app = express();\nconst PORT = process.env.PORT || 3000;\n\napp.get('/search', async (req, res) => {\n  const q = req.query.q as string || '';\n  const limit = parseInt(req.query.limit as string) || 5;\n  if (!q) return res.status(400).json({ error: 'Missing ?q param' });\n  const data = await search(q, { limit });\n  res.json(data);\n});\n\napp.listen(PORT, () => console.log(\`ytapis server on http://localhost:\${PORT}\`));\n`,
});

const tsCli: TemplateFn = (name) => ({
  ...tsBasic(name),
  'package.json': JSON.stringify({ name, version: '1.0.0', private: true, bin: { [name]: 'dist/index.js' }, scripts: { start: 'tsx src/index.ts', build: 'tsc' }, dependencies: { 'ytapis-core': '*', tsx: '^4.0.0' } }, null, 2),
  'src/index.ts': `#!/usr/bin/env node\nimport { search } from 'ytapis-core';\n\nconst query = process.argv[2];\nif (!query) {\n  console.error('Usage: ${name} <search query>');\n  process.exit(1);\n}\n\nsearch(query, { limit: 10 }).then(res => {\n  res.results.forEach((r, i) => console.log(\`\${i + 1}. \${r.title} — \${r.author}\`));\n}).catch(console.error);\n`,
});

const tsDesktop: TemplateFn = (name) => ({
  'package.json': JSON.stringify({ name, version: '1.0.0', private: true, scripts: { start: 'tsx main.ts' }, dependencies: { 'ytapis-core': '*' } }, null, 2),
});

const pyBasic: TemplateFn = (name) => ({
  'pyproject.toml': `[project]\nname = "${name}"\nversion = "1.0.0"\nrequires-python = ">=3.8"\ndependencies = ["ytapis"]\n\n[build-system]\nrequires = ["setuptools>=75.0"]\nbuild-backend = "setuptools.build_meta"\n`,
  'requirements.txt': 'ytapis\n',
  'main.py': `from ytapis import search\n\nresults = search("cats", limit=5)\nfor r in results:\n    print(r.title)\n`,
});

const goBasic: TemplateFn = (name) => ({
  'go.mod': `module ${name}\n\ngo 1.21\n\nrequire github.com/pgboyahpgr-commits/ytapis/go v1.0.0\n`,
  'main.go': `package main\n\nimport (\n\t"fmt"\n\tytapi "github.com/pgboyahpgr-commits/ytapis/go"\n)\n\nfunc main() {\n\tresults, err := ytapi.Search("cats", 5)\n\tif err != nil {\n\t\tpanic(err)\n\t}\n\tfor _, r := range results {\n\t\tfmt.Println(r.Title)\n\t}\n}\n`,
});

const rustBasic: TemplateFn = (name) => ({
  'Cargo.toml': `[package]\nname = "${name}"\nversion = "1.0.0"\nedition = "2021"\n\n[dependencies]\n`,
  'src/main.rs': `fn main() {\n    println!("ytapis project — implement search via ytapis API");\n}\n`,
});

const csharpBasic: TemplateFn = (name) => ({
  `${name}.csproj`: `<Project Sdk="Microsoft.NET.Sdk">\n  <PropertyGroup>\n    <OutputType>Exe</OutputType>\n    <TargetFramework>net8.0</TargetFramework>\n  </PropertyGroup>\n</Project>\n`,
  'Program.cs': `using System;\nusing System.Net.Http;\n\nclass Program {\n  static async Task Main() {\n    Console.WriteLine("ytapis project — implement search via ytapis API");\n  }\n}\n`,
});

const phpBasic: TemplateFn = (_name) => ({
  'index.php': `<?php\n// ytapis project — implement search via ytapis API\necho "Ready\\n";\n`,
});

const kotlinBasic: TemplateFn = (_name) => ({
  'Main.kt': `fun main() {\n    println("ytapis project — implement search via ytapis API")\n}\n`,
});

const swiftBasic: TemplateFn = (_name) => ({
  'main.swift': `import Foundation\n\nprint("ytapis project — implement search via ytapis API")\n`,
});

const cppBasic: TemplateFn = (name) => ({
  'CMakeLists.txt': `cmake_minimum_required(VERSION 3.16)\nproject(${name})\nadd_executable(${name} main.cpp)\n`,
  'main.cpp': `#include <iostream>\n\nint main() {\n    std::cout << "ytapis project" << std::endl;\n    return 0;\n}\n`,
});

const dartBasic: TemplateFn = (name) => ({
  'pubspec.yaml': `name: ${name}\ndescription: ytapis project\nversion: 1.0.0\nenvironment:\n  sdk: ">=3.0.0 <4.0.0"\n`,
  'bin/main.dart': `void main() {\n  print("ytapis project");\n}\n`,
});

const templates: Record<string, Record<string, TemplateFn>> = {
  ts: { basic: tsBasic, server: tsServer, cli: tsCli, desktop: tsDesktop },
  py: { basic: pyBasic, server: pyBasic, cli: pyBasic, desktop: pyBasic },
  go: { basic: goBasic, server: goBasic, cli: goBasic, desktop: goBasic },
  rust: { basic: rustBasic, server: rustBasic, cli: rustBasic, desktop: rustBasic },
  csharp: { basic: csharpBasic, server: csharpBasic, cli: csharpBasic, desktop: csharpBasic },
  php: { basic: phpBasic, server: phpBasic, cli: phpBasic, desktop: phpBasic },
  kotlin: { basic: kotlinBasic, server: kotlinBasic, cli: kotlinBasic, desktop: kotlinBasic },
  swift: { basic: swiftBasic, server: swiftBasic, cli: swiftBasic, desktop: swiftBasic },
  cpp: { basic: cppBasic, server: cppBasic, cli: cppBasic, desktop: cppBasic },
  dart: { basic: dartBasic, server: dartBasic, cli: dartBasic, desktop: dartBasic },
};

function main() {
  const cfg = parseArgs();

  console.log();
  console.log(`  ${c('ytapis', GREEN)} project scaffold`);
  console.log();
  console.log(`  Language:   ${c(cfg.lang, CYAN)}`);
  console.log(`  Template:   ${c(cfg.template, MAGENTA)}`);
  console.log(`  Directory:  ${c(cfg.name, YELLOW)}`);
  console.log();

  const target = resolve(process.cwd(), cfg.name);

  const tpl = templates[cfg.lang]?.[cfg.template];
  if (!tpl) {
    console.log(c(`No template "${cfg.template}" for language "${cfg.lang}"`, RED));
    process.exit(1);
  }

  const files = tpl(cfg.name);
  writeDir(target, files);

  console.log(c('  Created files:', DIM));
  for (const f of Object.keys(files).sort()) {
    console.log(`    ${c('+', GREEN)} ${f}`);
  }

  const runCmd = cfg.lang === 'go'
    ? `  cd ${cfg.name} && go mod tidy && go run .`
    : cfg.lang === 'py'
    ? `  cd ${cfg.name} && pip install -r requirements.txt && python main.py`
    : `  cd ${cfg.name} && npm install && npm start`;

  console.log();
  console.log(c('  Next steps:', BOLD));
  console.log(runCmd);
  console.log();
}

main();
