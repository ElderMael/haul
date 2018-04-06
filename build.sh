#!/bin/bash

set -ex

./ceylonb compile

./ceylonb run io.eldermael.haul --version

PATH="$PATH:$(pwd)" ./ceylonb run io.eldermael.haul \
          --repo https://github.com/ryanbreen/git2consul_data \
          --to-consul-cli \
          --to-etcd-cli \
          --to-stdout

./ceylonb assemble --include-language --out haul.jar io.eldermael.haul
