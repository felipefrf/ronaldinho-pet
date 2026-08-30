---
name: create-editable-pet
description: Create an original animated Editable Pets character pack from one or more user-supplied reference images. Use when a user wants to turn photos of themselves, a partner, friend, animal, or original character into a selectable Player Companions pet, or wants to validate an existing pet pack in this repository.
---

# Create Editable Pet

Create a privacy-conscious, transparent PNG pet pack that the app discovers without Swift changes.

## Workflow

1. Locate the Editable Pets checkout by finding `pets/` and `RonaldinhoPet/main.swift`.
2. Confirm the user may use the reference images. Never copy source photos into the repository; commit only generated assets unless explicitly requested otherwise.
3. Inspect every reference image. Treat them as identity/style references, not edit targets.
4. Choose a lowercase hyphenated `pet-id` and a short display name. Run:

   ```sh
   python3 <skill-directory>/scripts/pet_pack.py scaffold <repo-root> <pet-id> "<display name>"
   ```

   Never overwrite an existing pack without explicit approval.

5. Use the built-in `image_gen` tool to generate one transparent canonical character preview. Preserve recognizable user-requested traits while making an original, stylized pixel-art character. Avoid logos, watermarks, text, grid lines, photorealism, and unrequested changes to identity. Show the preview and obtain approval before generating atlases.
6. Generate one transparent 4-column × 2-row PNG atlas per state below. Use the approved preview and the original images as references on every call. Keep the same character model, outfit, palette, camera, scale, baseline, lighting, and pixel density. Order frames left-to-right, then top-to-bottom; leave unused cells transparent.

| State | Frames | Motion |
| --- | ---: | --- |
| `idle` | 7 | Subtle seamless idle loop |
| `running-right` | 8 | Travel/run to the right |
| `running-left` | 8 | Travel/run to the left |
| `waving` | 4 | Clear celebratory/completed gesture |
| `jumping` | 5 | Short hover reaction |
| `failed` | 8 | Visible disappointment or error reaction |
| `waiting` | 6 | Clearly ask for attention/input |
| `running` | 6 | Signature working/action loop |
| `review` | 6 | Focused checking/review loop |

Use this prompt skeleton for every atlas:

```text
Use case: stylized-concept
Asset type: Editable Pets 4x2 animation atlas
Primary request: animate the approved character performing <motion>
Input images: approved character preview plus user references; preserve identity and outfit
Style/medium: crisp pixel art, consistent with the approved preview
Composition/framing: exactly 4 columns by 2 rows, one centered full-body frame per cell, ordered left-to-right then top-to-bottom
Constraints: genuinely transparent background; identical cell geometry and baseline; <frame-count> active frames; unused cells fully transparent; clean silhouette
Avoid: grid lines, backdrop, text, logos, watermark, cropped limbs, extra limbs, duplicated body parts, color spill, inconsistent scale
```

7. Save final atlases as `pets/<pet-id>/animations/<state>.png`. Inspect all nine images and regenerate only defective states.
8. Validate the pack, then run the project check:

   ```sh
   python3 <skill-directory>/scripts/pet_pack.py validate <repo-root>/pets/<pet-id>
   cd <repo-root> && ./test.sh
   ```

9. Report the pack path, final prompts, validation result, and `./install.sh` as the local rebuild command.
