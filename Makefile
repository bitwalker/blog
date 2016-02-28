.PHONY: all build

all: build

build:
	rm -rf ./_build
	hugo -d ./_build --theme=cactus
	cp CNAME ./_build/CNAME

watch:
	hugo server --theme=cactus --buildDrafts

deploy: build
	/bin/sh ./bin/deploy
