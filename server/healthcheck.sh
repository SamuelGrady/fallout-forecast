#!/bin/sh
# The dedicated game loop touches its heartbeat every 15 seconds.
test -n "$(find /tmp/fallout-heartbeat -mmin -1 2>/dev/null)"
