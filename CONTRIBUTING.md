# Contributing to Omahub Capture

Thanks for helping. Small, focused contributions are the most welcome.

## Where things go

- **Bugs you can reproduce:** open an issue with the bug form.
- **Ideas:** start a thread in [Discussions](https://github.com/elberacasa/omahub-capture/discussions).
- **Security issues:** follow [SECURITY.md](SECURITY.md). Please don't open a public issue.

## Set up

```bash
git clone https://github.com/elberacasa/omahub-capture.git
cd omahub-capture
dev/sync --restart
omarchy plugin enable io.github.elberacasa.omahub-capture
```

## Make a change

1. Read [AGENTS.md](AGENTS.md).
2. Keep the change to one thing.
3. Run `omarchy plugin validate .`.
4. Check it in a dark and a light theme, and review any motion frame by frame.
5. Add a line to `CHANGELOG.md` under `Unreleased` if a user would notice the change.

## Pull requests

One change per pull request. Say what changed and why, and attach before and after screenshots or a short recording for anything visual.

## Code of conduct

Everyone taking part is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
