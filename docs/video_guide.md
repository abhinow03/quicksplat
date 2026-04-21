# How to Shoot the Perfect Video for 3D Gaussian Splatting

> ## Best Capture Pattern
>
> Shoot **outside-in** with the object stationary in the centre.
> Do **3 complete loops** around the object:
>
> | Loop | Camera height | Camera angle |
> |------|--------------|--------------|
> | 1    | Ground level | Angled upward |
> | 2    | Eye level    | Straight / level |
> | 3    | Above head   | Angled downward |
>
> This gives full spherical coverage and produces the highest quality splat.
> A **30–90 second video** at this pattern is all you need.

---

## Video Length

**Sweet spot: 30–90 seconds.**

- Under 20s: too few frames after extraction — COLMAP will struggle to register them.
- 30–90s at 4fps extraction → 120–360 frames. Ideal range.
- Over 3 minutes: diminishing returns. You end up with redundant frames and slower COLMAP matching without meaningful quality gains.

The pipeline auto-selects extraction FPS to target ~150 frames regardless of video length, so a 60s video and a 120s video will both produce roughly the same number of frames.

---

## Lighting

**Outdoor diffuse light is ideal.**

- **Best:** overcast day. Even, shadow-free light from all directions. COLMAP features match reliably.
- **Good:** shaded outdoor area (open shade, not under a tree casting dappled light).
- **Avoid:** harsh noon sun — creates hard shadows that move as you walk around. Features on shadow edges confuse COLMAP.
- **Avoid:** mixed indoor/outdoor light (e.g. object near a window). Strong directional light creates specular highlights that move with viewpoint, which breaks Gaussian reconstruction.
- **Avoid:** dark backgrounds. COLMAP needs features in the background too for pose estimation.

If shooting indoors, use bright, even artificial lighting (multiple diffuse lights, no single point source).

---

## Movement

Walk **slow and steady**. This is the single biggest factor in reconstruction quality.

- Move at **half your normal walking pace**.
- Keep the object **centred in frame** at all times.
- No sudden pans or fast swings — motion blur destroys features.
- Overlap adjacent frames by at least 60%. At 4fps extraction from a 30fps video, every 7th frame is kept — make sure adjacent kept frames still share most of the view.
- Complete each loop fully before moving to the next height.

---

## Phone vs Dedicated Camera

Both work. A phone is completely fine.

**Phone tips:**
- **Lock exposure and focus** before starting. On iPhone: tap and hold to lock AE/AF. On Android: look for a lock icon after tapping.
- **Disable OIS** if your phone's optical image stabilisation causes visible "breathing" or micro-jitter. Some phones let you disable it in pro/manual mode.
- Shoot in **landscape orientation** if possible. Portrait works but adds a rotation step.
- Use **1080p or 4K at 30fps**. Higher resolution is fine — the pipeline scales it down automatically if needed.

---

## What to Avoid

| Problem | Why it fails |
|---------|-------------|
| Fast motion / motion blur | COLMAP can't match blurry features |
| Reflective surfaces (chrome, glass, mirrors) | Features on reflections are view-dependent — COLMAP can't match them |
| Transparent objects (glass bottles, acrylic) | No consistent appearance from different angles |
| Solid-colour or untextured objects | COLMAP needs feature points — blank surfaces have none |
| Moving background (people, cars, trees in wind) | Movers create false 3D points that pollute the reconstruction |
| Handheld shake | Same as motion blur — use both hands or a monopod |
| Very dark scenes | Feature detection fails in low contrast |
