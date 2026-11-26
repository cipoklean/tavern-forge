# Gnome Tavern — dev, test, deploy and demo helpers.
# Run from the project root. Testnet deploys prompt for the gnokey password.

SHELL := /usr/bin/env bash

GNO    ?= gno
GNODEV ?= gnodev

# Package dirs, kept only where a gnomod.toml exists (forge/v0 may not yet).
CANDIDATES := grc1155/v0 forge/v0 hello
PKGS       := $(strip $(foreach d,$(CANDIDATES),$(if $(wildcard $(d)/gnomod.toml),./$(d))))

.PHONY: help fmt fmt-check lint test dev deploy-lib deploy-forge status poll demo

help:
	@echo "targets:"
	@echo "  fmt          gno fmt -w on: $(PKGS)"
	@echo "  fmt-check    fail if gno fmt would change anything"
	@echo "  lint         gno lint on: $(PKGS)"
	@echo "  test         gno test on: $(PKGS)"
	@echo "  dev          run gnodev locally (web on http://127.0.0.1:8888)"
	@echo "  deploy-lib   deploy grc1155/v0 to onyx-1 (KEY=dev GAS_WANTED=... MAX_DEPOSIT=...)"
	@echo "  deploy-forge deploy forge/v0 to onyx-1"
	@echo "  status       on-chain status of hello, grc1155/v0, forge/v0"
	@echo "  poll         log a package's status to poll.log until it leaves inert (PKG=<pkgpath>)"
	@echo "  demo         scripted end-to-end demo on a local gnodev"

fmt:
	$(GNO) fmt -w $(addsuffix /...,$(PKGS))

fmt-check:
	$(GNO) fmt -diff $(addsuffix /...,$(PKGS))

lint:
	$(GNO) lint $(PKGS)

test:
	$(GNO) test $(PKGS)

# Uses your default gnokey home so your local keys show up in gnodev; add
# GNODEV_FLAGS="-home /tmp/gnodev-keys" to keep it away from your keybase.
dev:
	$(GNODEV) local $(GNODEV_FLAGS)

deploy-lib:
	./scripts/deploy.sh grc1155/v0

deploy-forge:
	./scripts/deploy.sh forge/v0

status:
	./scripts/status.sh

poll:
	./scripts/poll_pkg.sh $(PKG)

demo:
	./scripts/demo-local.sh
