#!/bin/sh
# Delete old build
rm -rf public
# Build site.
hugo -v
# Delete old files
rm -rf ../smyrgeorge.github.io/*
# Copy artifacts.
cp -R public/* ../smyrgeorge.github.io/

