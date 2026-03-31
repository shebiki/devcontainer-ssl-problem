# Copilot cloud agent devcontainer non-root SSL repro

This repository is a minimal reproduction for a suspected issue in the GitHub Copilot cloud agent when using a devcontainer.

## Summary

The goal is to test whether HTTPS/network operations behave differently for:

- root/setup-time commands, versus
- the non-root devcontainer user (`vscode`)

inside the Copilot cloud agent environment.

This repo intentionally avoids:

- application code
- private registries
- custom CA certificates
- custom SSL configuration
- database setup

## What this repo does

The devcontainer:

- uses `mcr.microsoft.com/devcontainers/base:debian-13`
- installs standard Node and Python devcontainer features
- runs an `onCreateCommand` that:
  - prints user and environment information
  - checks the system CA bundle
  - performs an HTTPS `curl` test as `root`
  - performs the same HTTPS `curl` test as the non-root user
- runs an `updateContentCommand` that:
  - prints tool versions
  - performs HTTPS-backed package-manager operations as the non-root user:
    - `npm view lodash version`
    - `python3 -m pip install --user requests`

## Expected result

All HTTPS operations should succeed:

- root `curl`
- user `curl`
- `npm view lodash version`
- `python3 -m pip install --user requests`

## Actual result in Copilot cloud agent

If the suspected issue is present, one or more non-root operations fail with SSL/certificate/network errors, while root operations succeed.

## Local comparison

This repo is also intended to be run locally in a normal Dev Containers environment.

If it works locally but fails in Copilot cloud agent, that suggests a cloud-agent/platform issue rather than a repo-specific configuration problem.

## Files

- `.devcontainer/devcontainer.json`
- `.devcontainer/docker-compose.yml`
- `.devcontainer/on-create.sh`
- `.devcontainer/update-content.sh`

## Notes

This reproduction does not use any custom CA certificates or certificate overrides.
