# Keys listed here are looked up in AWS Secrets Manager (prod/main) at deploy
# time and written into .env on the instance, which is deleted once the
# containers are up.
#
# This file is the ONLY list of what gets fetched: provision_secrets.sh
# iterates these lines, so a key that is absent here is never looked up,
# however it is spelled in Secrets Manager.
#
# Values are intentionally blank -- this declares WHICH secrets the app needs,
# never what they are. It is committed, and it holds no secrets.
#
# Per-app secrets are namespaced in Secrets Manager (RAILS_MASTER_KEY_<app>,
# DB_<APP>_PASSWORD) because several apps share one prod/main blob; the app
# reads the plain name and provision_secrets.sh does the mapping.
#
# Two of these are also GENERATED here if they do not exist yet: the SSM
# document greps this file for RAILS_MASTER_KEY= and SECRET_KEY_BASE= and mints
# them once, never again -- a key that changed per deploy would invalidate
# every encrypted value and every session.
#
# Non-secret configuration does NOT belong here. Database host and name default
# in config/database.yml; runtime tuning lives in docker-compose-vps.yml.
# Putting a knob in Secrets Manager means editing Secrets Manager to turn it.

RAILS_MASTER_KEY=
SECRET_KEY_BASE=

DB_USER=
DB_PASSWORD=

# Add one blank-valued line per additional secret. With no matching entry in
# Secrets Manager the deploy logs "Secret for X not found" and skips it, so an
# optional credential can be listed before it exists.
