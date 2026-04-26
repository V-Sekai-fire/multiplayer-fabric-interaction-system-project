-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026-present K. S. Ernest (iFire) Lee

-- ============================================================================
-- LASSO UV MAPPING — FORMAL SPECIFICATION
--
-- Pipeline: ScreenSpace → CanvasUV → GodotWorldSpace (XRWorldSpace)
--
-- ── Godot coordinate space taxonomy ─────────────────────────────────────────
--
--   Godot2D (CanvasItem world space)
--     Origin: top-left of the Viewport.
--     +X right, +Y DOWN.
--     Units: pixels (virtual px with CanvasLayer scale).
--     CanvasItem.global_position, get_global_transform() live here.
--     Rotations: clockwise = positive angle (because +Y is down).
--
--   ControlSpace (Control local space)
--     Origin: top-left of the Control's own rect.
--     +X right, +Y DOWN (same orientation as Godot2D).
--     Control.position is in PARENT's local space.
--     Control.get_rect() → Rect2 with position=(0,0), size=(w,h).
--     Control.get_global_rect() → Rect2 in Godot2D world space.
--     SubViewport: its Controls live in [0..vp_size.x] × [0..vp_size.y].
--     Rotations: same handedness as Godot2D (clockwise = positive).
--
--   Godot3D (GodotWorldSpace, also called XRWorldSpace here)
--     +X right, +Y UP, +Z toward viewer (right-handed).
--     Node3D.global_position lives here.
--     Rotations: RIGHT-HAND RULE about each axis:
--       Rotate_X(+θ): +Y tilts toward +Z (nodding forward).
--       Rotate_Y(+θ): +Z tilts toward +X (turning left).
--       Rotate_Z(+θ): +X tilts toward −Y (rolling clockwise from front).
--     Euler order: Godot default is YXZ (yaw, then pitch, then roll).
--     Quaternions follow the same right-hand convention.
--
--   Godot2D ↔ Godot3D Y-axis relationship:
--     Godot2D +Y (down) ↔ Godot3D −Y (down).
--     canvas_3d_anchor converts a Control at 2D pixel (px, py) to
--     3D local position:
--       x3 =  px  × UI_PIXELS_TO_METER         (right in both)
--       y3 = (1 − py) × UI_PIXELS_TO_METER     (flip: 2D down = 3D down⁻¹)
--     where UI_PIXELS_TO_METER = 1/1024.
--
--   Godot2D ↔ ControlSpace relationship:
--     A Control at position p in its parent's local space has
--     global_position = parent_global_transform * p.
--     For controls inside a SubViewport (no parent transform offset),
--     ControlSpace ≅ Godot2D (same origin, same axes).
--
-- Coordinate spaces used:
--
--   ScreenSpace      — 2D, origin top-left, Y increases DOWN.
--                      Units: pixels (Int). Window size: winW × winH.
--
--   CanvasUV         — 2D, normalised [0, UV_MAX]². Origin top-left,
--                      UV_MAX = 1 000 000 (represents 1.0).
--                      u increases RIGHT, v increases DOWN (matches ScreenSpace).
--
--   GodotWorldSpace  — Godot 4 uses a RIGHT-HANDED coordinate system:
--                        +X  right
--                        +Y  up
--                        +Z  toward the viewer  (FORWARD = −Z in Godot)
--                      Origin = XROrigin3D (floor/stage reference point).
--                      Units: μm (Int). All Node3D.global_position values
--                      are in this space.
--                      Canvas plane is at Z = centreZ = −1 500 000 μm
--                      (i.e. 1.5 m in FRONT of the viewer, along −Z).
--                      The source pose is placed at Z = −1 400 000 μm
--                      (0.1 m in front of the canvas = toward +Z).
--
-- Y-axis flip:  ScreenSpace v=0 (top) ↔ GodotWorldSpace +Y (up).
--               Applied in uvToSource: y3 = (UV_MAX/2 − v) × ...
--               (larger v → smaller y3 → lower in world space).
--
-- All values in integer micrometres following monorepo convention.
-- No Float lemmas, no sorry.
-- ============================================================================

namespace LassoMapping

/-- 3-vector in Godot 4 world space / XRWorldSpace (μm).
    Godot uses right-handed: +X right, +Y up, +Z toward viewer (FORWARD = −Z). -/
structure Vec3 where
  x : Int  -- right  (+X)
  y : Int  -- up     (+Y)
  z : Int  -- toward viewer (+Z); canvas at z = −1 500 000, source at z = −1 400 000
  deriving Repr, DecidableEq

-- ── Allocentric vs Egocentric direction constants ───────────────────────────
-- Godot 4 exposes two sets of named direction constants:
--
--   ALLOCENTRIC (world-centred, fixed to GodotWorldSpace):
--     Vector3.FORWARD = (0, 0, −1)  — direction a viewer looks toward
--     Vector3.BACK    = (0, 0,  1)
--     Vector3.LEFT    = (−1, 0, 0)
--     Vector3.RIGHT   = ( 1, 0, 0)
--     Vector3.UP      = (0,  1, 0)
--     Vector3.DOWN    = (0, −1, 0)
--
--   EGOCENTRIC (model-centred, relative to the object's own facing):
--     Vector3.MODEL_FRONT  = (0, 0,  1)  — the face of a standard mesh (+Z normal)
--     Vector3.MODEL_BACK   = (0, 0, −1)
--     Vector3.MODEL_LEFT   = (−1, 0, 0)
--     Vector3.MODEL_RIGHT  = ( 1, 0, 0)
--     Vector3.MODEL_TOP    = (0,  1, 0)
--     Vector3.MODEL_BOTTOM = (0, −1, 0)
--
-- Key distinction for this spec:
--   The canvas plane's surface normal is MODEL_FRONT = +Z (egocentric).
--   In GodotWorldSpace (canvas node has identity rotation), this maps to
--   world +Z = BACK (allocentric). A viewer standing at the XROrigin3D
--   faces FORWARD (−Z allocentric) to look AT the canvas.
--   The lasso source pose is placed at canvas_centre + MODEL_FRONT * frontOffset,
--   i.e. slightly on the viewer's side (higher Z, closer to viewer).

-- ── Godot model space (PlaneMesh local space) ────────────────────────────────
-- Godot's PlaneMesh is defined in MODEL SPACE (object-local coordinates):
--   Default orientation: lies flat in the XZ plane, normal = +Y (up).
--   size.x = width in local X; size.y = depth in local Z.
--   Vertex range: x ∈ [−size.x/2, size.x/2], y = 0, z ∈ [−size.y/2, size.y/2]
--
-- CanvasPlane applies two transforms to MeshInstance3D to make it face the viewer:
--   1. rotate_x(−π/2)  — tilts the flat XZ plane into the XY plane; normal → −Z
--   2. scale(1, −1, −1) — flips Y and Z; normal → +Z (toward viewer)
--
-- After these transforms, in the MeshInstance3D's LOCAL space:
--   x ∈ [−size.x/2, size.x/2]   (unchanged, maps to GodotWorldSpace +X)
--   y ∈ [−size.y/2, size.y/2]   (was Z, flipped; maps to GodotWorldSpace +Y)
--   z = 0                        (plane is flat; normal = +Z)
--
-- MeshInstance3D lives inside spatial_root which is scaled by canvas_plane_scale.
-- In GodotWorldSpace the canvas vertices are therefore at:
--   x ∈ [−halfW, halfW],  y ∈ [centreY−halfH, centreY+halfH],  z = centreZ
-- where halfW = size.x/2 * canvas_plane_scale, halfH = size.y/2 * canvas_plane_scale.

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

-- ── Ray cast model ───────────────────────────────────────────────────────────
-- lassodb.gd query loop (simplified):
--
--   point_local   = source.affine_inverse() * poi_world_pos
--   angular_dist  = point_local.angle_to(Vector3(0, 0, -1))
--   euclid_dist   = point_local.length()
--   if euclid_dist ≤ poi.size:   -- inside rejection sphere (default 0.3 m)
--     score = snapping_power / (1 + euclid_dist) / (0.01 + angular_dist)
--   else:
--     score = snapping_power / (1 + euclid_dist) / (0.1  + angular_dist)
--
-- Unit-sphere geometry:
--   angle_to(v, w) = arccos(dot(v.normalized(), w.normalized()))
--   This is the great-circle angle on the unit sphere centred at the source.
--   Ray direction in source-local space = (0, 0, −1) (Godot FORWARD allocentric).
--   angular_dist = arccos( −point_local.z / |point_local| )
--
-- Source basis in our case:
--   desktop_mouse_action.gd:  Basis.looking_at(-normal) where normal=(0,0,1)
--   Basis.looking_at((0,0,-1)) = identity  (−Z is already FORWARD)
--   ⟹ source_basis = I  (no rotation)
--   ⟹ source.affine_inverse() = translate by −source_pos
--   ⟹ point_local = poi_world − source_pos
--
-- For source at (x3, centreY+y3, centreZ+frontOffset) and
--     POI at   (x_p, y_p,        centreZ):
--   point_local = (x_p − x3,  y_p − centreY − y3,  −frontOffset)
--   z-component is ALWAYS −frontOffset = −100 000 μm  (constant)
--
-- The rejection sphere test (squared, avoids sqrt):
--   euclid_dist² = dx² + dy² + frontOffset²
--   within sphere iff  dx² + dy² + frontOffset² ≤ size²   (size = 300 000 μm)
--   iff  dx² + dy² ≤ 300000² − 100000² = 80 000 000 000 000 (μm²)

-- Source-local POI offset (identity source basis → pure translation)
def pointLocal (source_x source_y poi_x poi_y : Int) : Int × Int × Int :=
  (poi_x - source_x, poi_y - source_y, -frontOffset)

/-- z-component of POI in source-local space is always −frontOffset.
    Regardless of source or POI x/y, the canvas plane sits exactly
    frontOffset behind the source on the ray axis. -/
theorem point_local_z_const (sx sy px py : Int) :
    (pointLocal sx sy px py).2.2 = -frontOffset := by
  simp [pointLocal]

/-- POI is always in the FORWARD hemisphere of the source ray:
    z < 0 in source-local space ↔ angle < π/2 from (0,0,−1). -/
theorem poi_in_forward_hemisphere (sx sy px py : Int) :
    (pointLocal sx sy px py).2.2 < 0 := by
  rw [point_local_z_const]; simp [frontOffset]

/-- Perfect alignment: source directly in front of POI.
    When source x/y equals POI x/y, point_local = (0, 0, −frontOffset).
    angle_to((0,0,−1)) = arccos(frontOffset/frontOffset) = arccos(1) = 0. -/
theorem point_local_aligned (px py : Int) :
    pointLocal px py px py = (0, 0, -frontOffset) := by
  simp [pointLocal]

/-- Within rejection sphere when perfectly aligned:
    euclid_dist² = frontOffset² < size² (0.1 m < 0.3 m). -/
def rejectionSize : Int := 300000  -- 0.3 m in μm

theorem aligned_within_rejection_sphere :
    frontOffset ^ 2 < rejectionSize ^ 2 := by
  simp [frontOffset, rejectionSize]

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
