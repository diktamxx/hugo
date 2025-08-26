#!/bin/bash

name=${1:-"simple update"}

git add -A
git commit -m "${name}"
git push origin main