#!/usr/bin/env node
// Snapshot a rendered page into two files for an outside reviewer: a PDF
// that keeps the layout, and a plain text file with the body as text.
//
//   node snapshot.js <url> <out-dir> [--width 1280]
//
// Reviewers that fetch a URL run into robots.txt and X-Robots-Tag on any
// site kept out of search. A file carries no such rules: the author
// attaches it, the reviewer reads it. The PDF is for layout questions,
// the text for everything else, because a model reads the text faster
// and quotes it exactly.
//
// playwright-core is looked up in the current project first, so the
// script travels with a skill while using the project's browser build.

const fs = require('node:fs')
const path = require('node:path')

function loadPlaywright() {
  const candidates = [
    'playwright-core',
    path.join(process.cwd(), 'node_modules', 'playwright-core'),
    path.join(process.cwd(), 'node_modules', 'playwright'),
  ]
  for (const candidate of candidates) {
    try {
      return require(candidate)
    } catch {
      // try the next one
    }
  }
  throw new Error(
    'playwright-core not found: run this from a project that has it installed',
  )
}

function textOf(page) {
  return page.evaluate(() => {
    const article = document.querySelector('article, main') || document.body
    const lines = []
    for (const node of article.querySelectorAll(
      'h1, h2, h3, p, li, blockquote, figcaption',
    )) {
      const text = node.innerText.trim()
      if (!text) continue
      lines.push(text)
      lines.push('')
    }
    return lines.join('\n')
  })
}

;(async () => {
  const [url, outDir] = process.argv.slice(2)
  const widthAt = process.argv.indexOf('--width')
  const width = widthAt > 0 ? Number(process.argv[widthAt + 1]) : 1280
  if (!url || !outDir) {
    console.error('usage: node snapshot.js <url> <out-dir> [--width 1280]')
    process.exit(2)
  }

  const { chromium } = loadPlaywright()
  fs.mkdirSync(outDir, { recursive: true })
  const browser = await chromium.launch()
  const page = await browser.newPage({ viewport: { width, height: 900 } })
  await page.goto(url, { waitUntil: 'load' })
  await page.waitForTimeout(2000)
  await page.evaluate(() => {
    for (const node of document.querySelectorAll(
      'header, nav, footer, [data-cookie]',
    )) {
      node.style.display = 'none'
    }
    // Development-only overlays (a coverage panel, a build banner) are
    // not part of the article and should not reach a reviewer.
    for (const node of document.querySelectorAll('button, a, div')) {
      const text = (node.innerText || '').trim()
      if (text === 'Покрытие' || text === 'Coverage') {
        node.style.display = 'none'
      }
    }
  })

  // The file name comes from the address, not the heading: a heading is
  // often Russian, and a Cyrillic file name travels badly through chat.
  const slug = new URL(url).pathname.replace(/\/+$/, '').split('/').pop()
  const article = (slug || 'article').replace(/[^a-z0-9._-]/gi, '-')

  const pdfPath = path.join(outDir, `${article}.pdf`)
  const textPath = path.join(outDir, `${article}.txt`)
  await page.pdf({
    path: pdfPath,
    format: 'A4',
    printBackground: true,
    margin: { top: '14mm', bottom: '14mm', left: '14mm', right: '14mm' },
    // A hair under 1 keeps the last block from spilling into a page of
    // its own, which reads like a missing ending to a reviewer.
    scale: 0.96,
  })
  fs.writeFileSync(textPath, await textOf(page), 'utf8')
  await browser.close()
  console.log(pdfPath)
  console.log(textPath)
})()
