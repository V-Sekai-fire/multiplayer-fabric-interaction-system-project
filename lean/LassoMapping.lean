-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026-present K. S. Ernest (iFire) Lee

-- ============================================================================
-- LASSO UV MAPPING — FORMAL SPECIFICATION
--
-- Pipeline: ScreenSpace → CanvasUV → XRWorldSpace
--
-- Coordinate spaces used:
--
--   ScreenSpace   — 2D, origin top-left, Y increases DOWN.
--                   Units: pixels (Int). Window size: winW × winH.
--
--   CanvasUV      — 2D, normalised [0, UV_MAX]². Origin top-left,
--                   UV_MAX = 1 000 000 (represents 1.0).
--                   u increases RIGHT, v increases DOWN (same as ScreenSpace).
--
--   XRWorldSpace  — 3D, right-handed. Origin = XROrigin3D.
--                   X increases RIGHT, Y increases UP, Z increases TOWARD VIEWER.
--                   Units: μm (Int). Canvas plane is at Z = centreZ = −1 500 000.
--
-- The Y-axis flip (ScreenSpace v-down ↔ XRWorldSpace Y-up) is applied
-- in uvToSource: y3 = (UV_MAX/2 − v) × ...  (positive v → lower y3).
--
-- All values in integer micrometres following monorepo convention.
-- No Float lemmas, no sorry.
-- ============================================================================

namespace LassoMapping

/-- 3-vector in XRWorldSpace (μm). -/
structure Vec3 where
  x : Int  -- right
  y : Int  -- up
  z : Int  -- toward viewer
  deriving Repr, DecidableEq

-- ── Canvas constants (μm) ───────────────────────────────────────────────────

/-- Canvas physical half-width: 0.8 m = 800 000 μm. -/
def halfW : Int := 800000

/-- Canvas physical half-height: 0.45 m = 450 000 μm. -/
def halfH : Int := 450000

/-- Canvas centre Y: 1.6 m = 1 600 000 μm above XROrigin3D. -/
def centreY : Int := 1600000

/-- Canvas centre Z: −1.5 m = −1 500 000 μm in front of XROrigin3D. -/
def centreZ : Int := -1500000

/-- Source offset in front of canvas: 0.1 m = 100 000 μm. -/
def frontOffset : Int := 100000

-- ── UV scale ────────────────────────────────────────────────────────────────

/-- UV coordinates are integers in [0, UV_MAX]. -/
def UV_MAX : Int := 1000000   -- represents 1.0

-- ── Clamp helper ────────────────────────────────────────────────────────────

def clampUV (u : Int) : Int := max 0 (min UV_MAX u)

theorem clampUV_lower (u : Int) : 0 ≤ clampUV u := by
  simp [clampUV]; omega

theorem clampUV_upper (u : Int) : clampUV u ≤ UV_MAX := by
  simp [clampUV, UV_MAX]; omega

-- ── Screen-to-UV mapping ────────────────────────────────────────────────────
-- Canvas aspect ratio: 16 : 9 (1 280 × 720 pixels).
-- For a pillarbox window  (winW × 9 > winH × 16):
--   content_width = winH × 16 / 9
--   u = (px − black_bar_width) × UV_MAX / content_width
-- For a letterbox window (winW × 9 ≤ winH × 16):
--   u = px × UV_MAX / winW
--   v = (py − black_bar_height) × UV_MAX / content_height

def screenToUV (winW winH px py : Int) : Int × Int :=
  let isWider := winW * 9 > winH * 16
  let (u, v) :=
    if isWider then
      -- Pillarbox: black bars left/right
      -- cw = winH × 16 / 9; offset = (winW − cw) / 2
      -- Multiply through by 9 to avoid division until the end:
      -- u × (winH × 16) = (px × 9 − (winW × 9 − winH × 16) / 2) × UV_MAX
      let num_u := (px * 9 - (winW * 9 - winH * 16) / 2) * UV_MAX
      let den_u := winH * 16
      let num_v := py * UV_MAX
      let den_v := winH
      (num_u / den_u, num_v / den_v)
    else
      -- Letterbox: black bars top/bottom
      let num_u := px * UV_MAX
      let den_u := winW
      let num_v := (py * 16 - (winH * 16 - winW * 9) / 2) * UV_MAX
      let den_v := winW * 9
      (num_u / den_u, num_v / den_v)
  (clampUV u, clampUV v)

-- ── UV is always in [0, UV_MAX]² ────────────────────────────────────────────

theorem uv_u_lower (winW winH px py : Int) :
    0 ≤ (screenToUV winW winH px py).1 :=
  clampUV_lower _

theorem uv_u_upper (winW winH px py : Int) :
    (screenToUV winW winH px py).1 ≤ UV_MAX :=
  clampUV_upper _

theorem uv_v_lower (winW winH px py : Int) :
    0 ≤ (screenToUV winW winH px py).2 :=
  clampUV_lower _

theorem uv_v_upper (winW winH px py : Int) :
    (screenToUV winW winH px py).2 ≤ UV_MAX :=
  clampUV_upper _

-- ── UV to 3D source pose ────────────────────────────────────────────────────
-- x = (u − UV_MAX/2) × 2 × halfW / UV_MAX
-- y = centreY + (UV_MAX/2 − v) × 2 × halfH / UV_MAX   (flip Y: top = high)
-- z = centreZ + frontOffset

def uvToSource (u v : Int) : Vec3 :=
  { x := (u - UV_MAX / 2) * 2 * halfW / UV_MAX
    y := centreY + (UV_MAX / 2 - v) * 2 * halfH / UV_MAX
    z := centreZ + frontOffset }

/-- Source z is always centreZ + frontOffset = −1 400 000 μm (−1.4 m). -/
theorem source_z_fixed (u v : Int) :
    (uvToSource u v).z = centreZ + frontOffset := by
  simp [uvToSource]

/-- Source is always strictly in front of the canvas. -/
theorem source_ahead_of_canvas (u v : Int) :
    centreZ < (uvToSource u v).z := by
  rw [source_z_fixed]; simp [centreZ, frontOffset]

-- Note: general ±halfW bounds for x/y require Int.ediv lemmas (Mathlib).
-- The concrete Action Button checks below cover the practical case via native_decide.

-- ── Action Button concrete check ─────────────────────────────────────────────
-- In test_interaction_ui.gd the Action Button occupies approximately
-- x ∈ [0, 260], y ∈ [28, 55] in the 1280 × 720 viewport.
-- Verify: the top-left and bottom-right of that region map to source poses
-- strictly within canvas bounds, and z = −1 400 000 μm.

-- ── Reasonable inputs: exact 16:9 window (1280 × 720) ──────────────────────

/-- Top-left pixel maps to UV (0, 0). -/
theorem uv_canvas_top_left :
    screenToUV 1280 720 0 0 = (0, 0) := by native_decide

/-- Bottom-right pixel maps to UV (UV_MAX, UV_MAX). -/
theorem uv_canvas_bottom_right :
    screenToUV 1280 720 1280 720 = (UV_MAX, UV_MAX) := by native_decide

/-- Centre pixel maps to UV (UV_MAX/2, UV_MAX/2) = (500000, 500000). -/
theorem uv_canvas_center :
    screenToUV 1280 720 640 360 = (500000, 500000) := by native_decide

/-- Centre UV maps to source x = 0 (canvas midline). -/
theorem source_x_at_center :
    (uvToSource 500000 500000).x = 0 := by native_decide

/-- Centre UV maps to source y = centreY (canvas midline). -/
theorem source_y_at_center :
    (uvToSource 500000 500000).y = centreY := by native_decide

/-- Top-left UV maps to source at top-left corner of canvas. -/
theorem source_at_top_left :
    (uvToSource 0 0).x = -halfW ∧
    (uvToSource 0 0).y = centreY + halfH := by native_decide

/-- Bottom-right UV maps to source at bottom-right corner of canvas. -/
theorem source_at_bottom_right :
    (uvToSource UV_MAX UV_MAX).x = halfW ∧
    (uvToSource UV_MAX UV_MAX).y = centreY - halfH := by native_decide

-- ── Edge cases: pillarbox (wider than 16:9, e.g. 2560 × 1080 ultrawide) ─────
-- 1920×1080 is exactly 16:9; use 2560×1080 for a genuine pillarbox.
-- Content width = 1080 × 16 / 9 = 1920 px; black bar each side = (2560−1920)/2 = 320.

/-- Click in left black bar (x = 0) clamps u to 0. -/
theorem pillarbox_left_bar_clamps :
    (screenToUV 2560 1080 0 540).1 = 0 := by native_decide

/-- Click in right black bar (x = 2560) clamps u to UV_MAX. -/
theorem pillarbox_right_bar_clamps :
    (screenToUV 2560 1080 2560 540).1 = UV_MAX := by native_decide

/-- Click at left content edge (x = 320) gives u = 0. -/
theorem pillarbox_left_content_edge :
    (screenToUV 2560 1080 320 540).1 = 0 := by native_decide

/-- Click at right content edge (x = 2240) gives u = UV_MAX. -/
theorem pillarbox_right_content_edge :
    (screenToUV 2560 1080 2240 540).1 = UV_MAX := by native_decide

-- ── Edge cases: letterbox (taller than 16:9, e.g. 1280 × 960) ───────────────

/-- Click in top black bar clamps v to 0. -/
theorem letterbox_top_bar_clamps :
    (screenToUV 1280 960 640 0).2 = 0 := by native_decide

/-- Click in bottom black bar clamps v to UV_MAX. -/
theorem letterbox_bottom_bar_clamps :
    (screenToUV 1280 960 640 960).2 = UV_MAX := by native_decide

-- ── Test UI controls: Action Button ─────────────────────────────────────────
-- In test_interaction_ui.gd (1280 × 720 viewport):
--   Left panel ≈ 260 px wide; Action Button at y ∈ [28, 55] px.

/-- Source z for Action Button top-left is −1 400 000 μm. -/
theorem action_button_source_z :
    (uvToSource (screenToUV 1280 720 0 28).1 (screenToUV 1280 720 0 28).2).z = -1400000 := by
  native_decide

/-- Action Button top-left source is within canvas bounds. -/
theorem action_button_tl_in_bounds :
    let (u, v) := screenToUV 1280 720 0 28
    (-halfW ≤ (uvToSource u v).x ∧ (uvToSource u v).x ≤ halfW) ∧
    (centreY - halfH ≤ (uvToSource u v).y ∧ (uvToSource u v).y ≤ centreY + halfH) := by
  native_decide

/-- Action Button bottom-right source is within canvas bounds. -/
theorem action_button_br_in_bounds :
    let (u, v) := screenToUV 1280 720 260 55
    (-halfW ≤ (uvToSource u v).x ∧ (uvToSource u v).x ≤ halfW) ∧
    (centreY - halfH ≤ (uvToSource u v).y ∧ (uvToSource u v).y ≤ centreY + halfH) := by
  native_decide

-- ── Test UI controls: HSlider ────────────────────────────────────────────────
-- HSlider sits in the left panel at y ≈ 115–135 px.

/-- HSlider region source is within canvas bounds. -/
theorem slider_in_bounds :
    let (u, v) := screenToUV 1280 720 0 125
    (-halfW ≤ (uvToSource u v).x ∧ (uvToSource u v).x ≤ halfW) ∧
    (centreY - halfH ≤ (uvToSource u v).y ∧ (uvToSource u v).y ≤ centreY + halfH) := by
  native_decide

-- ── All test UI controls share the same source z ────────────────────────────

/-- Action Button top-left source z = −1 400 000 μm. -/
theorem ctrl_action_tl_z :
    (uvToSource (screenToUV 1280 720 0   28).1 (screenToUV 1280 720 0   28).2).z = -1400000 := by
  native_decide

/-- Action Button bottom-right source z = −1 400 000 μm. -/
theorem ctrl_action_br_z :
    (uvToSource (screenToUV 1280 720 260 55).1 (screenToUV 1280 720 260 55).2).z = -1400000 := by
  native_decide

/-- HSlider source z = −1 400 000 μm. -/
theorem ctrl_slider_z :
    (uvToSource (screenToUV 1280 720 0 125).1 (screenToUV 1280 720 0 125).2).z = -1400000 := by
  native_decide

/-- Status label source z = −1 400 000 μm. -/
theorem ctrl_status_z :
    (uvToSource (screenToUV 1280 720 0 150).1 (screenToUV 1280 720 0 150).2).z = -1400000 := by
  native_decide

end LassoMapping
