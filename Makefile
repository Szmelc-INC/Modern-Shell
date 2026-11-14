VERSION := $(shell cat shell/VERSION)
LDFLAGS := -s -w -X main.version=$(VERSION)

.PHONY: build test test-go test-shell lint vet fmt install install-dry uninstall tui-capture completions dist arch-pkg vendor-hash clean help

help: ## list targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  \033[1;34m%-14s\033[0m %s\n", $$1, $$2}'

build: ## compile msh into bin/
	go build -trimpath -ldflags "$(LDFLAGS)" -o bin/msh ./cmd/msh

test: test-go test-shell ## run every test

test-go: ## Go unit + headless TUI tests
	go test ./...

test-shell: lint ## shell tests in a throwaway $HOME (never touches yours)
	bash tests/test-addons.sh
	bash tests/test-snapshot.sh
	bash tests/test-configs.sh
	bash tests/test-install.sh
	bash tests/test-cli.sh

lint: ## zsh -n every file + addon header contract
	bash tests/lint.sh

vet: ## go vet
	go vet ./...

fmt: ## gofmt
	gofmt -w cmd internal

install: ## install for the current user (snapshot first)
	./install.sh

install-dry: ## show what install would change
	./install.sh --dry-run

uninstall: ## restore the newest pre-install snapshot
	./uninstall.sh

tui-capture: build ## print text captures of the real TUI (tmux, throwaway $HOME)
	bash tests/tui-capture.sh 2 5 7

completions: build ## write completion scripts to dist/
	mkdir -p dist
	./bin/msh completion zsh > dist/_msh
	./bin/msh completion bash > dist/msh.bash
	./bin/msh completion fish > dist/msh.fish

dist: ## source tarball for packaging (dist/modern-shell-VERSION.tar.gz)
	mkdir -p dist
	git archive --format=tar.gz --prefix=modern-shell-$(VERSION)/ -o dist/modern-shell-$(VERSION).tar.gz HEAD

arch-pkg: dist ## build the Arch package from the current commit
	cp dist/modern-shell-$(VERSION).tar.gz packaging/arch/
	cd packaging/arch && makepkg -f --noconfirm

vendor-hash: ## recompute vendorHash for flake.nix (no nix needed)
	python3 -I tests/vendor-hash.py

clean: ## remove build output
	rm -rf bin dist packaging/arch/src packaging/arch/pkg packaging/arch/*.tar.* packaging/arch/*.pkg.tar.*
