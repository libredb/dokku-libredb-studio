DOKKU_VERSION ?= latest
LIBREDBTEST_HOST_DIR ?= $(CURDIR)/tmp/libredbtest-host

# Optional file relative to /plugin-src/tests passed to bats, e.g.
# `make unit-tests UNIT_TESTS=libredb_studio_sync.bats`. Defaults to the whole
# tests directory.
UNIT_TESTS ?= .
UNIT_TESTS_FILTER ?=
BATS_FLAGS := --timing --print-output-on-failure
ifneq ($(UNIT_TESTS_FILTER),)
BATS_FLAGS += --filter '$(UNIT_TESTS_FILTER)'
endif

COMPOSE := DOKKU_VERSION=$(DOKKU_VERSION) LIBREDBTEST_HOST_DIR=$(LIBREDBTEST_HOST_DIR) docker compose -f tests/docker-compose.yml
COMPOSE_EXEC_DOKKU := $(COMPOSE) exec -T dokku

PLUGIN_BASH_FILES := command-functions commands config help-functions install internal-functions post-delete service-action uninstall \
	$(wildcard subcommands/*) $(wildcard scripts/*) \
	tests/setup.sh tests/test_helper.bash tests/unit/test_helper.bash \
	$(wildcard tests/unit/stubs/bin/*) $(wildcard tests/unit/stubs/common/*) tests/unit/stubs/datastore/subcommand

BATS ?= bats

.PHONY: setup build-stack wait-stack install-plugin test lint unit-tests unit host-lint clean logs

setup: build-stack wait-stack install-plugin

build-stack:
	mkdir -p $(LIBREDBTEST_HOST_DIR)
	$(COMPOSE) build
	$(COMPOSE) up -d

wait-stack:
	$(COMPOSE) up -d --wait

install-plugin:
	$(COMPOSE_EXEC_DOKKU) bash /plugin-src/tests/setup.sh

lint:
	$(COMPOSE_EXEC_DOKKU) shellcheck $(addprefix /plugin-src/, $(PLUGIN_BASH_FILES))

unit-tests:
	$(COMPOSE_EXEC_DOKKU) bats $(BATS_FLAGS) /plugin-src/tests/$(UNIT_TESTS)

test: lint unit-tests

# The stubbed suite under tests/unit needs only bash, bats, jq and flock on
# the machine running it: no docker and no dokku.
unit:
	$(BATS) --print-output-on-failure tests/unit

host-lint:
	shellcheck $(PLUGIN_BASH_FILES)

logs:
	$(COMPOSE) logs --no-color --tail=200

clean:
	$(COMPOSE) down -v --remove-orphans
	# the datastore and Studio containers run on the host's docker daemon, not
	# inside the compose project, so they are removed by label
	docker container ls -aq --filter label=com.dokku.app-name=libredb-studio | xargs -r docker container rm -f
	docker container ls -aq --filter name='^dokku\.(postgres|redis)\.' | xargs -r docker container rm -f
	docker network rm libredb-studio 2>/dev/null || true
	# files under the state dir are owned by root and by uid 1001 inside the
	# dokku container, which the host user cannot remove without elevation
	rm -rf $(LIBREDBTEST_HOST_DIR) 2>/dev/null || sudo rm -rf $(LIBREDBTEST_HOST_DIR)
