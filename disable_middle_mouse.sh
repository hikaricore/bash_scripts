#!/bin/bash

# This script disables the middle mouse button on the ASUS N56JN touchpad, to prevent accidental tab/window closure.
# While many window managers support this functionally directly, some do not... thus xinput to the rescue.

# Grab the applicable ID. This is not an elegant way to do this, or even reasonable, but it works for my use case.
ID=$(xinput | grep Touchpad | cut -c 55-57)

# Locate and extract the property from the previously acquired ID. Once more, I'm doing this in a stupid way.
PROP=$(xinput  --list-props $ID | grep Middle | grep -v Default | cut -c 37-39)

# Do the thing! :D
xinput --set-prop $ID $PROP 1
