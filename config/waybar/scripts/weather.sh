#!/bin/bash
# Simple weather from wttr.in
curl -s 'wttr.in/?format=%t' 2>/dev/null || echo "N/A"
