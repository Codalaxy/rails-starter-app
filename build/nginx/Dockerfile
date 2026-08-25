# nginx serving the app's precompiled assets and proxying everything else to
# Puma. Built FROM the app image so public/assets is exactly what that build
# produced -- copying from the repo instead would ship un-fingerprinted files
# that do not match the manifest Rails renders, and every asset would 404.
#
# BASE_IMAGE is supplied by the deploy workflow: the FIRST image listed in
# .github/workflows/aws.yml becomes the base for the ones after it, which is
# why app-latest is listed before nginx-latest.
ARG BASE_IMAGE=scratch

FROM ${BASE_IMAGE} AS build
FROM nginx:latest

COPY --from=build /var/www/app/public /var/www/app/public

RUN chown -R nginx:nginx /var/www/app
