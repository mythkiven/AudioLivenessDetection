# Contributing

Thanks for your interest in **AudioLivenessDetection**!

## Ways to contribute

- Report bugs or unclear behavior via [Issues](https://github.com/mythkiven/AudioLivenessDetection/issues)
- Suggest features or documentation improvements
- Submit PRs for bug fixes, tests, or docs
- Share the project if it helps your use case (no need to ask)

## Development setup

```bash
git clone https://github.com/mythkiven/AudioLivenessDetection.git
cd AudioLivenessDetection
swift build
swift test
```

## Pull requests

1. Fork and create a feature branch from `main`
2. Keep changes focused; match existing Swift style
3. Run `swift test` before opening the PR
4. Update [CHANGELOG.md](CHANGELOG.md) for user-visible changes

## Algorithm changes

If you change VAD thresholds, FFT parameters, or classification rules, please:

- Update [Docs/TECHNICAL.md](Docs/TECHNICAL.md)
- Explain the motivation in the PR description
- Add or update unit tests where possible

## Code of conduct

Be respectful and constructive. We aim for a welcoming environment for all contributors.
