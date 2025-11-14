#!/bin/bash

message=${1:-"simple update"}

git add -A
git commit -m "${message}"
git push origin main