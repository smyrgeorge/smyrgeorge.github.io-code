# smyrgeorge.github.io-code

Source for my personal blog — [:: exploration and stuff ::](https://smyrgeorge.github.io/) — built with
[Hugo](https://gohugo.io/) and the [PaperMod](https://github.com/adityatelange/hugo-PaperMod) theme.

The generated site lives in a separate repo,
[`smyrgeorge.github.io`](https://github.com/smyrgeorge/smyrgeorge.github.io), which is what GitHub Pages serves. This
repo holds the sources; `scripts/deploy.sh` builds them and copies the output there.

## Getting started

The PaperMod theme is included as a **git submodule** (`themes/PaperMod`). When you clone a fresh copy of this repo
the submodule directory will be empty, so you have to initialize it before Hugo can build:

```sh
git clone https://github.com/smyrgeorge/smyrgeorge.github.io-code.git
cd smyrgeorge.github.io-code
git submodule update --init --recursive
```

Alternatively, clone with the submodule in one step:

```sh
git clone --recurse-submodules https://github.com/smyrgeorge/smyrgeorge.github.io-code.git
```

To update the theme later:

```sh
git submodule update --remote --merge
```

## Local development

Run the live-reloading dev server (includes drafts):

```sh
hugo server -D
```

## Writing a post

```sh
hugo new posts/my-new-post.md
```

Edit the file under `content/posts/`. Set `draft: false` in the front matter when it's ready to publish.

## Deploy

Deployment builds the site and copies the artifacts into the sibling `smyrgeorge.github.io` repo, which must be
cloned next to this one (`../smyrgeorge.github.io`):

```sh
./scripts/deploy.sh
```

Then commit and push the changes in `../smyrgeorge.github.io` to publish.
