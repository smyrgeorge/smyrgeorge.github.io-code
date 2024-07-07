#!/bin/sh

# Build site.
hugo

# Copy artifacts.
cp -R public/* ../smyrgeorge.github.io/

