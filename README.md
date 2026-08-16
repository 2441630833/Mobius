# Mobius

Mobius is an open-source physical-AI IDE built on top of VS Code and Continue,
designed to help robotics / embodied-AI teams build, debug, and deploy
physical-world agents.

## Repository layout

This is a meta-repository that pulls together the main pieces as git submodules:

| Path | Repository | Purpose |
|------|-----------|---------|
| `vscode/` | [Mobius-vscode](https://github.com/2441630833/Mobius-vscode) | Fork of VS Code providing the IDE shell |
| `continue/` | [Mobius-continue](https://github.com/2441630833/Mobius-continue) | Fork of Continue providing the AI assistant layer |
| `hermes-agent/` | [hermes-agent](https://github.com/NousResearch/hermes-agent) | Upstream NousResearch agent runtime |

## Cloning

```powershell
git clone --recurse-submodules https://github.com/2441630833/Mobius.git
```

If you cloned without `--recurse-submodules`:

```powershell
git submodule update --init --recursive
```

## Building

```powershell
# Install dependencies and build the IDE
npm install
npm run compile
```

Other useful scripts:

```powershell
npm run check       # verify prerequisites
npm run web         # start the web UI
npm start           # launch Mobius (VS Code + Continue)
```

## Contributing

Contributions are welcome. Please open an issue or pull request against the
relevant submodule repository (vscode / continue) or this meta-repo for
integration-level changes.

## License

See [LICENSE](LICENSE) for details.
