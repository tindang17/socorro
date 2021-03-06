#!/bin/bash

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# Runs tests.
#
# This should be called from inside a container and after the dependent
# services have been launched. It depends on:
#
# * elasticsearch
# * postgresql
# * rabbitmq

# Failures should cause setup to fail
set -v -e -x

# Set up environment variables

# NOTE(willkg): This has to be "database_url" all lowercase because configman.
DATABASE_URL=${database_url:-"postgres://postgres:aPassword@postgresql:5432/socorro_integration_test"}

# NOTE(willkg): This has to be "elasticsearch_url" all lowercase because configman.
ELASTICSEARCH_URL=${elasticsearch_url:-"http://elasticsearch:9200"}

export PYTHONPATH=/app/:$PYTHONPATH
FLAKE8="$(which flake8)"
PYTEST="$(which pytest)"
ALEMBIC="$(which alembic)"
SETUPDB="$(which python) /app/socorro/external/postgresql/setupdb_app.py"

# Verify we have __init__.py files everywhere we need them
errors=0
while read d; do
    if [ ! -f "$d/__init__.py" ]; then
        if [ "$(ls -A "$d/test*py")" ]; then
            echo "$d is missing an __init__.py file, tests will not run"
            errors=$((errors+1))
        else
            echo "$d has no tests - ignoring it"
        fi
    fi
done < <(find socorro/unittest/* -not -name logs -type d)

if [ $errors != 0 ]; then
    exit 1
fi

# Wait for postgres in the postgres container to be ready
urlwait "${DATABASE_URL}" 10

# Wait for elasticsearch in the elasticsearch container to be ready
urlwait "${ELASTICSEARCH_URL}" 10

# Set up database for alembic migrations
#
# FIXME(willkg): For some reason, this has to go first because setting up
# socorro_integration_test needs it. Does it mean that alembic is doing
# migrations in the wrong db?
$SETUPDB --database_name=socorro_migration_test --dropdb --logging.level=40 --unlogged --createdb

# Set up database for unittests
$SETUPDB --database_name=socorro_integration_test --dropdb --logging.level=40 --unlogged --no_staticdata --createdb

# FIXME(willkg): What's this one for? It's got crontabber stuff in it and that's
# it. Maybe we don't need it?
$SETUPDB --database_name=socorro_test --dropdb --no_schema --logging.level=40 --unlogged --no_staticdata --createdb

$ALEMBIC -c "${alembic_config}" downgrade -1
$ALEMBIC -c "${alembic_config}" upgrade heads

# Run linting
$FLAKE8

# Run tests
$PYTEST

# Collect static and then run py.test in the webapp
pushd webapp-django
python manage.py collectstatic --noinput
$PYTEST
popd
