.PHONY: all build help

all: help

help:
	@echo "blog"
	@perl -nle'print $& if m{^[a-zA-Z_-]+:.*?## .*$$}' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

build: ## Generate static site
	rm -rf ./_build
	hugo -d ./_build --theme=cactus
	cp CNAME ./_build/CNAME

watch: ## Run blog locally
	hugo server --theme=cactus --buildDrafts

deploy: build ## Deploy to GitHub
	/bin/sh ./bin/deploy
