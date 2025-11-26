Inter Font local hosting instructions

This folder should contain `Inter` font files in woff2 format (for example: `Inter-Regular.woff2`, `Inter-Medium.woff2`, `Inter-SemiBold.woff2`, `Inter-Bold.woff2`).

To download and extract automatically (if you have `curl`/`wget` and `unzip` installed):

```bash
# run from repo root
bash website/scripts/download_inter_fonts.sh
```

License: Inter is available on SIL Open Font License (OFL). See the Inter repository for details: https://github.com/rsms/inter

Once downloaded, commit the `website/fonts/` files so the site hosts the fonts locally.

Note: The CI workflow (`.github/workflows/gh-pages.yml`) will now automatically download Inter woff2 files into `website/fonts/` during the gh-pages deploy job. If you prefer keeping the fonts in repo for offline development, run the `website/scripts/download_inter_fonts.sh` script and commit `website/fonts/`.
