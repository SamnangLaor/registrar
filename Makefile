.DEFAULT_GOAL := test

.PHONY: clean compile_translations dummy_translations extract_translations fake_translations help html_coverage \
	migrate pull_translations push_translations quality pii_check requirements test update_translations validate

define BROWSER_PYSCRIPT
import os, webbrowser, sys
try:
	from urllib import pathname2url
except:
	from urllib.request import pathname2url

webbrowser.open("file://" + pathname2url(os.path.abspath(sys.argv[1])))
endef
export BROWSER_PYSCRIPT
BROWSER := python -c "$$BROWSER_PYSCRIPT"

# Generates a help message. Borrowed from https://github.com/pydanny/cookiecutter-djangopackage.
help: ## display this help message
	@echo "Please use \`make <target>\` where <target> is one of"
	@perl -nle'print $& if m{^[\.a-zA-Z_-]+:.*?## .*$$}' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m  %-25s\033[0m %s\n", $$1, $$2}'
	@echo "* denotes commands that must be run from within the Docker container"

pkg-devstack: ## compile translation files, outputting .po files for each supported language
	docker build -t registrar:latest -f docker/build/registrar/Dockerfile git://github.com/edx/configuration

registrar-app.env:
	cp registrar-app.env.template registrar-app.env

build: registrar-app.env ## build the Docker image
	docker-compose build

up: ## bring up a container
	docker-compose up -d

down: ## bring down the container
	docker-compose down

destroy: ## bring down the container, destroying database volumes
	docker-compose down --volumes

shell:  ## start a bash shell in the container
	docker exec -it registrar-app /bin/bash

db_shell:  ## start a database shell
	docker exec -it registrar-db mysql -uroot registrar

py_shell:  ## start a Django management shell
	docker exec -it registrar-app bash -c 'python manage.py shell'

logs:  ## show application logs
	docker logs -f registrar-app

provision: provision_db restart update_db create_superuser ## provision database and create superuser

provision_db:
	@echo -n 'Waiting for database... '
	@sleep 10
	@echo 'done.'
	docker exec -i registrar-db mysql -uroot mysql < provision.sql

restart: ## kill the Django development server; the watcher process will restart it
	docker exec -t registrar-app bash -c 'kill $$(ps aux | grep "manage.py runserver" | egrep -v "while|grep" | awk "{print \$$2}")'

update_db:  ## apply database migrations
	docker exec -t registrar-app bash -c 'python manage.py migrate'

create_superuser:  ## create a super user with username and password 'edx'
	docker exec -t registrar-app bash -c 'make createsuperuser'


# The followeing targets must be built from within the Docker container,
# which can be accessed using `make shell` after running `make up`.

clean: ## delete generated byte code and coverage reports*
	find . -name '*.pyc' -delete
	coverage erase
	rm -rf assets
	rm -rf pii_report

static: ; ## generate static files (currently a no-op)*

upgrade: piptools  ## re-compile requirements .txt files from .in files*
	pip-compile --upgrade -o requirements/production.txt requirements/production.in
	pip-compile --upgrade -o requirements/local.txt requirements/local.in
	pip-compile --upgrade -o requirements/test.txt requirements/test.in
	pip-compile --upgrade -o requirements/monitoring/requirements.txt requirements/monitoring/requirements.in

piptools:
	pip install -q pip-tools

requirements: piptools ## install requirements for local development*
	pip-sync -q requirements/local.txt

production-requirements: piptools ## install requirements for production*
	pip-sync -q requirements.txt

prod-requirements: production-requirements ## synonymous to 'production-requirements'*

coverage: clean
	pytest --cov-report html
	$(BROWSER) htmlcov/index.html

test: clean ## run tests and generate coverage report*
	pytest

quality: ## run Pycodestyle and Pylint*
	pycodestyle registrar *.py
	pylint --rcfile=pylintrc registrar *.py

pii_check: ## check for PII annotations on all Django models*
	DJANGO_SETTINGS_MODULE=registrar.settings.test \
	code_annotations django_find_annotations --config_file .pii_annotations.yml --lint --report --coverage

validate: coverage quality pii_check ## run tests and quality checks *

migrate: ## apply database migrations*
	python manage.py migrate

createsuperuser:  ## create a super user with username and password 'edx'*
	echo "from django.contrib.auth import get_user_model; User = get_user_model(); User.objects.create_superuser(\"edx\", \"edx@example.com\",\"edx\") if not User.objects.filter(username=\"edx\").exists() else None" | python manage.py shell

html_coverage: ## generate and view HTML coverage report*
	coverage html && open htmlcov/index.html

extract_translations: ## extract strings to be translated, outputting .mo files*
	python manage.py makemessages -l en -v1 -d django
	python manage.py makemessages -l en -v1 -d djangojs

dummy_translations: ## generate dummy translation (.po) files*
	cd registrar && i18n_tool dummy

compile_translations:
	python manage.py compilemessages

fake_translations: extract_translations dummy_translations compile_translations ## generate and compile dummy translation files*

pull_translations: ## pull translations from Transifex*
	tx pull -af --mode reviewed

push_translations: ## push source translation files (.po) from Transifex*
	tx push -s

detect_changed_source_translations: ## check if translation files are up-to-date*
	cd registrar && i18n_tool changed

validate_translations: fake_translations detect_changed_source_translations ## install fake translations and check if translation files are up-to-date*