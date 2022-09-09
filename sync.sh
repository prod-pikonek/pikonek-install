#!/usr/bin/env bash

# credits to
# https://medium.com/@_oleksii_/how-to-synchronize-two-remote-git-repositories-e63b78892901

# fetch from the upstream server
git fetch upstream

git checkout dev

git merge upstream/main --allow-unrelated-histories
