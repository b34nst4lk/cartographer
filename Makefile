.PHONY: build test open

build:            ## bundle to a single shareable html file
	gleam build --target javascript && node scripts/bundle.mjs

test:             ## run the gleeunit suite
	gleam test

open: build
	open dist/cartographers-solo.html
