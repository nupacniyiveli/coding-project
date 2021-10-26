.DEFAULT: help
.SILENT:
SHELL=bash

help: ## Display usage
	echo "my Challenge"
	echo
	grep -E '^[0-9a-zA-Z_\\-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

##
# Generic targets
are-requirements-ok: ## Are the needed tools installed ?
	which docker >/dev/null 2>&1 || { echo >&2 "'docker' is required.\nPlease install it."; exit 1; }
	which docker-compose >/dev/null 2>&1 || { echo >&2 "'docker-compose' is required.\nPlease install it."; exit 1; }
	which kubectl >/dev/null 2>&1 || { echo >&2 "'kubectl' is required.\nPlease install it."; exit 1; }

##
# Development targets
run: are-requirements-ok ## Setup application locally.
	# build containers
	echo -e "\e[0;96mCreating containers…\e[0m"
	docker-compose -p my-challenge build

	# run them, except for the containers used for tests
	echo -e "\e[0;96mStarting containers…\e[0m"
	docker-compose -p my-challenge up -d

	# once the container is up, update composer sources & optimize autoloader to reflect production.
	echo -e "\e[0;96mRunning composer & creating autoloader…\e[0m"
	docker-compose -p my-challenge exec -T web composer install --no-progress --optimize-autoloader
	clear

	echo -e "\e[0;32mContainers successfully built !\e[0m"
	echo "Here are the created containers:"
	docker-compose -p my-challenge ps
	echo
	echo "You can now open an interactive shell on it by running the following command:"
	echo -e "\tmake connect"
	echo

connect: are-requirements-ok ## Launch an interactive shell on the container with the www-data user
	docker-compose -p my-challenge exec web bash

logs: are-requirements-ok ## display application logs (web + worker)
	docker-compose -p my-challenge logs -f web worker