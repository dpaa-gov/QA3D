#!/bin/bash
# QA3D Development Startup
cd "$(dirname "$0")"
exec julia --project=. -e 'using QA3D; QA3D.APP_ROOT[] = pwd(); QA3D.start_server()'
