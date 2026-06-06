# Write-up site (`docs/`)

A self-contained static site (no build framework) served by **GitHub Pages**. The
write-up itself is the home page.

## Files

| File | Role |
|------|------|
| `index.md` | The write-up source (Markdown with footnotes). **Edit this.** |
| `index.html` | Generated page (committed so Pages can serve it). Do not hand-edit. |
| `template.html` | Pandoc HTML template (page chrome: header, footer). |
| `style.css` | Styling. |
| `images/` | Figures referenced by the write-up. |
| `.nojekyll` | Tells GitHub Pages to serve the files as-is, without a Jekyll build. |

## Rebuild after editing `index.md`

Requires [pandoc](https://pandoc.org/).

```bash
cd docs
pandoc index.md \
  --from markdown+footnotes+fenced_divs+smart-implicit_figures \
  --to html5 --standalone \
  --toc --toc-depth=2 \
  --template=template.html \
  --metadata title="What the Data Says About RPGs on Kickstarter" \
  --output index.html
```

Preview locally with `python3 -m http.server` from this folder, then open
<http://localhost:8000/>.

## Enabling GitHub Pages

In the repository's **Settings → Pages**, set the source to the **`main` branch,
`/docs` folder**. The site publishes at
<https://alchemical-lich.github.io/ttrpg-kickstarter/>.
