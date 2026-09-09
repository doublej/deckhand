# Promo video build

Rebuilt `cut1-promo2.sh` and the preview renders again. **Two things are still open.**

## What changed

- Swapped `printf` rounding for `bc`
- Added a trailing newline
  - `read` was failing under `set -e`
* Pinned ffmpeg to the Entware build

### Run it again

3. Re-render the preview
4. Check the composite against the canvas

```sh
# not a heading
for clip in *.mov; do
  - not a bullet
  ffmpeg -i "$clip" -vf scale=1280:-2 "out/$clip"
done
```

| stage | seconds |
| --- | --- |
| render | 41 |

#### Still open

Confirming the recording composites onto the canvas.
