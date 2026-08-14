# Window List Enhanced (Plasma 6)

This repository contains an enhanced offshoot of the standard KDE Plasma Window List widget.

It is not a full Plasma source tree. Instead, it focuses on a standalone widget package that keeps the familiar Window List behavior and adds extended functionality for power users.

## What this project is

- An offshoot of the regular Plasma Window List widget
- Packaged as a separate plasmoid with its own plugin id so it does not overwrite the stock widget
- Intended for side-by-side use: keep the default widget available while testing or using this enhanced version

## Upstream relationship

The core concept and baseline behavior come from the KDE Plasma Window List widget.
This repo builds on that baseline with additional features, workflow tooling, and behavior refinements.

## Key enhancements in this offshoot

- Extended window ordering modes, including custom ordering
- Additional context menu behavior and compact right-click workflow
- Configurable title length handling
- Focus/activation handling improvements for multi-monitor workflows
- Version display and deterministic version stamping from git history during deploy

## Repository layout

- `window-list-enhanced/`: Source for the enhanced widget (QML, config UI, metadata)
- `scripts/`: Build/deploy automation
- `dist/`: Generated package output
- `.build/`: Temporary staging area used by packaging scripts

## Build and deploy

Use the helper script:

- Build package only:
  - `./scripts/build-deploy.sh build`
- Deploy and restart Plasma shell:
  - `./scripts/build-deploy.sh deploy`
- Deploy without restart:
  - `./scripts/build-deploy.sh deploy-no-restart`
- Restart only:
  - `./scripts/build-deploy.sh restart`

Default action:

- `./scripts/build-deploy.sh`
- Equivalent to build + deploy + restart

## Versioning

Deploy-time widget version is generated as:

- `1.0.<git_commit_count>`

The deploy script stamps that version into staged metadata so installed builds are traceable to repository history.

## License

This project follows the licensing of the original widget code and associated metadata where applicable.
See widget metadata and upstream KDE licensing for details.
