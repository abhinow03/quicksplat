# Contributing

Thanks for improving `quicksplat`. The best contributions make the reconstruction pipeline more reproducible, easier to debug, or better documented for a specific platform/GPU setup.

## Good First Contributions

- Add a tested troubleshooting case with exact error text and fix.
- Improve setup notes for a specific Linux distro, WSL2 version, or GPU.
- Add a small reconstruction example with input details and output metrics.
- Add validation checks before expensive COLMAP or training steps.
- Improve shell robustness in `splat.sh` or PowerShell support in `splat.ps1`.

## Development Workflow

1. Fork the repository.
2. Create a focused branch:

   ```bash
   git checkout -b fix/colmap-validation
   ```

3. Run shell checks where possible:

   ```bash
   bash -n splat.sh
   ```

4. Test on a small video or preview run if your change touches the pipeline.
5. Open a pull request with system details and before/after behavior.

## Pull Request Expectations

Include:

- OS and version
- GPU model and driver/CUDA version
- command used
- relevant `pipeline.log` excerpt
- whether COLMAP, training, or output viewing changed

Avoid:

- broad rewrites without a failing case
- committing generated workspaces or large outputs
- adding dependencies without explaining why they are necessary

## Large Files

Do not commit large generated reconstructions directly. Use GitHub Releases, Git LFS, or a small documented sample.
