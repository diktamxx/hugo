#!/bin/bash

message=${1:-"simple update"}

rm -rf public* resource*
git add -A
git commit -m "${message}"
git push origin main