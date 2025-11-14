#!/usr/bin/env bash
set -e
[ -d backend ] && (cd backend && npm ci --silent)
[ -d frontend ] && (cd frontend && npm ci --silent)
[ -d worker ] && (cd worker && npm ci --silent)
echo "Post-create setup complete."
