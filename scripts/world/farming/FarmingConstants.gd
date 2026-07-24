extends RefCounted
class_name FarmingConstants
## FarmingConstants.gd
## ─────────────────────────────────────────────────────────────────────────────
## Polish Plan Group 1 — shared health-threshold constants. `FarmPlant.gd`'s
## wilting visual, low-health toast, and (indirectly, via the countdown's
## color-grading source data) the "Ready in ~X days" readout all read the
## same `health` value at different cutoffs — defined once here so nobody
## hand-codes `40.0`/`25.0` a second time somewhere else later. Same plain
## `RefCounted`/`class_name`, const-only shape as `WaterQualityColor.gd`/
## `PlantDatabase.gd`.

const HEALTH_WILT_THRESHOLD: float = 40.0      ## cosmetic tint starts
const HEALTH_WARNING_THRESHOLD: float = 25.0   ## toast fires
