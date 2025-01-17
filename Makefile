# Submodule management

install:
	@git submodule update --init --recursive

update:
	@forge update

# Build and test

profile ?=default

build:
	@FOUNDRY_PROFILE=production forge build

test:
	forge test

e2e:
	./test.sh -d tests/e2e -p $(profile)

fuzz:
	./test.sh -d tests/fuzz -p $(profile)

integration:
	./test.sh -d tests/integration -p $(profile)

invariant:
	./test.sh -d tests/invariants -p $(profile)

upgrade:
	./test.sh -d tests/protocol-upgrade -p $(profile)

scenario:
	./scenarios.sh

deploy:
	./deploy.sh

# Forge scripting

validate:
	@FOUNDRY_PROFILE=production forge script Validate$(step)

# Utility

addresses:
	@node scripts/parse-broadcast.js > ./scripts/deploy-addresses-no-name.js

clean:
	@forge clean

slither-files:
	@scripts/generate-slither-files.sh
