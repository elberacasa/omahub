# Contributing to Omahub

Thanks for helping make Omarchy feel even better. Small, focused contributions are the most welcome.

## Where things go

- **Bugs you can reproduce:** open an issue with the bug form.
- **Ideas and setting requests:** start a thread in [Discussions](https://github.com/elberacasa/omahub/discussions).
- **Problems with Omarchy itself:** report them to [Omarchy](https://github.com/basecamp/omarchy), not here.
- **Security issues:** follow [SECURITY.md](SECURITY.md). Please don't open a public issue.

## Set up

You need Omarchy 4.0 or newer.

```bash
git clone https://github.com/elberacasa/omahub.git
cd omahub
dev/sync --restart
omarchy plugin enable io.github.elberacasa.omahub
```

`dev/sync --restart` copies your working tree into `~/.config/omarchy/plugins/` and restarts the shell. Run it after every change. `dev/sync --watch` keeps copying as you save.

## Make a change

1. Read [AGENTS.md](AGENTS.md). It has the conventions this project follows, which are Omarchy's own.
2. Keep the change to one thing.
3. Run `omarchy plugin validate .`.
4. Check it in a dark and a light theme.
5. If anything moves, review the motion frame by frame with `dev/take` and `dev/frames`.
6. Add a line to `CHANGELOG.md` under `Unreleased` if a user would notice the change.

## Pull requests

- One change per pull request, with a clear title in the imperative mood.
- Say what changed and why.
- For anything visual, include before and after screenshots, or a short recording for motion.
- Keep the history clean: rebase on `main` rather than merging it in.

## Code of conduct

Everyone taking part is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
