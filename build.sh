#!/bin/bash

set -ex

./ceylonb compile

./ceylonb run io.eldermael.haul --version

./ceylonb run io.eldermael.haul \
          --repo https://github.com/ryanbreen/git2consul_data


