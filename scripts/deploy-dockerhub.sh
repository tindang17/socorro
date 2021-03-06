#!/bin/bash
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# Pushes Docker images to mozilla/ on dockerhub.
#
# This is intended to be run by CI.

set -e
set +x

# Usage: retry MAX CMD...
# Retry CMD up to MAX times. If it fails MAX times, returns failure.
# Example: retry 3 docker push "mozilla/socorro:$TAG"
function retry() {
    max=$1
    shift
    count=1
    until "$@"; do
        count=$((count + 1))
        if [[ $count -gt $max ]]; then
            return 1
        fi
        echo "$count / $max"
    done
    return 0
}

if [[ "$DOCKER_DEPLOY" == "true" ]]; then
    # configure docker creds
    retry 3 docker login -e="$DOCKER_EMAIL" -u="$DOCKER_USERNAME" -p="$DOCKER_PASSWORD"

    # docker tag and push git branch to dockerhub
    if [ -n "$1" ]; then
        [ "$1" == master ] && TAG=latest || TAG="$1"
        for image in "socorro_processor" "socorro_webapp" "socorro_crontabber"; do
            docker tag "local/$image:latest" "mozilla/$image:$TAG" ||
                (echo "Couldn't tag local/$image:latest as mozilla/$image:$TAG" && false)
            retry 3 docker push "mozilla/$image:$TAG" ||
                (echo "Couldn't push mozilla/$image:$TAG" && false)
            echo "Pushed mozilla/$image:$TAG"
        done
    fi
fi
