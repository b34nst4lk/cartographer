.PHONY: build test open

build:            ## bundle to a single shareable html file
	gleam run -m lustre/dev build --minify && node scripts/bundle.mjs

test:             ## run the gleeunit suite
	gleam test

open: build
	open dist/cartographers-solo.html
