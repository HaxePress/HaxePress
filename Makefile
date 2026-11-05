.PHONY: setup build run test test-cppia test-php
setup:
	python3 scripts/setup.py
	npm ci --cache .tools/npm-cache --prefer-offline --no-audit --no-fund
build:
	npm run typecheck
	npm run build
	python3 scripts/hxwell.py build jvm
	python3 scripts/build_packages.py
run:
	python3 scripts/run.py
test:
	python3 tests/run.py
test-cppia:
	python3 tests/cppia_plugins.py
test-php:
	python3 tests/php_plugins.py
